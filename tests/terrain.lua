-- Terrain tests against the built library (change: terrain-topography; specs
-- noise-cellular, noise-terrain-fractals, noise-sources, terrain-plan,
-- terrain-detail, noise-pipeline).
-- Run from the repository root after `make`: luajit tests/terrain.lua
package.path = package.path .. ";./lua/?.lua"

local vnoise = require("vnoise")
local ffi = require("ffi")
local lib = vnoise._lib

local failures = 0
local function ok(name, cond)
  print((cond and "  ok  " or " FAIL ") .. name)
  if not cond then
    failures = failures + 1
  end
end

local function near(a, b, eps)
  return math.abs(a - b) < (eps or 1e-5)
end

-- True when f(...) raises an error whose message contains `needle`.
local function raises(needle, f, ...)
  local good, err = pcall(f, ...)
  return not good and tostring(err):find(needle, 1, true) ~= nil
end

-- Max absolute difference between a w x h block `b` (at bx, by) and the same
-- cells of a W-wide buffer `a`.
local function blockDiff(a, W, b, bx, by, w, h)
  local m = 0
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      m = math.max(m, math.abs(a[(by + j) * W + bx + i] - b[j * w + i]))
    end
  end
  return m
end

-- Evaluates fill(c0, r0, w, h) -> buffer over an n x n region as one block and
-- as k x k tiles, returning the largest difference.
local function tilingDiff(n, k, fill)
  local whole = fill(0, 0, n, n)
  local t = n / k
  local m = 0
  for by = 0, n - 1, t do
    for bx = 0, n - 1, t do
      m = math.max(m, blockDiff(whole, n, fill(bx, by, t, t), bx, by, t, t))
    end
  end
  return m
end

local function minmax(buf, count)
  local lo, hi = math.huge, -math.huge
  for k = 0, count - 1 do
    lo = math.min(lo, buf[k])
    hi = math.max(hi, buf[k])
  end
  return lo, hi
end

local s = vnoise.new(1234)
math.randomseed(42)

-- Gradients and damped fBm -----------------------------------------------------

do
  local dx, dy = ffi.new("float[1]"), ffi.new("float[1]")
  local worst, value_ok = 0, true
  local h = 3e-3
  local f32buf = ffi.new("float[1]")
  local function f32(v)
    f32buf[0] = v
    return f32buf[0]
  end
  for _, base in ipairs({ "simplex", "perlin" }) do
    local deriv = base == "simplex" and lib.simplex2_deriv or lib.perlin2_deriv
    local eval = base == "simplex" and lib.simplex2_eval or lib.perlin2_eval
    for _ = 1, 1000 do
      local x, y = math.random() * 200 - 100, math.random() * 200 - 100
      local v = deriv(s.s, x, y, dx, dy)
      value_ok = value_ok and near(v, eval(s.s, x, y), 1e-6)
      -- Divide by the float32 step actually taken (x +- h is rounded).
      local xp, xm, yp, ym = f32(x + h), f32(x - h), f32(y + h), f32(y - h)
      local fx = (eval(s.s, xp, y) - eval(s.s, xm, y)) / (xp - xm)
      local fy = (eval(s.s, x, yp) - eval(s.s, x, ym)) / (yp - ym)
      worst = math.max(worst, math.abs(fx - dx[0]), math.abs(fy - dy[0]))
    end
  end
  ok("analytic gradients match finite differences (worst " .. string.format("%.4f", worst) .. ")", worst < 1e-2)
  ok("deriv functions return the plain value", value_ok)
end

do
  local domain = { rotate = 30, warp = { amp = 4, freq = 0.05, octaves = 2 } }
  local same = true
  for mode, kind in pairs({ [0] = "fbm", [1] = "ridge", [2] = "turb" }) do
    local a = vnoise.fill_sampler(
      s,
      { kind = kind, octaves = 5 },
      { c0 = 7, r0 = -3, w = 32, h = 32, freq = 0.03, domain = domain }
    )
    local b =
      vnoise.fill_domain(s, kind, { c0 = 7, r0 = -3, w = 32, h = 32, freq = 0.03, octaves = 5, domain = domain })
    same = same and blockDiff(b, 32, a, 0, 0, 32, 32) < 1e-6
    assert(vnoise.MODE_FBM + mode == mode)
  end
  ok("fractal sampler modes match fill_domain", same)

  local buf = ffi.new("float[16]")
  for k = 0, 15 do
    buf[k] = 0.123
  end
  local sp = ffi.new("vnoise_sampler_t")
  sp.mode, sp.octaves, sp.lac, sp.gain = 99, 3, 2, 0.5
  local d = ffi.new("vnoise_domain_t")
  d.m[0], d.m[4], d.freq = 1, 1, 0.1
  lib.vnoise_fill_sampler(s.s, sp, buf, 0, 0, 4, 4, d)
  local untouched = true
  for k = 0, 15 do
    untouched = untouched and near(buf[k], 0.123, 1e-7)
  end
  ok("unknown sampler mode leaves the buffer untouched", untouched)
  ok("unknown sampler kind raises naming it", raises("voronoi3", vnoise.fill_sampler, s, { kind = "voronoi3" }, {}))

  local diff = 0
  for _, base in ipairs({ vnoise.BASE_SIMPLEX2, vnoise.BASE_PERLIN2 }) do
    local a = vnoise.fill_sampler(s, { kind = "damped", damping = 0, base = base }, { w = 48, h = 48, freq = 0.02 })
    local b = vnoise.fill_sampler(s, { kind = "fbm", base = base }, { w = 48, h = 48, freq = 0.02 })
    diff = math.max(diff, blockDiff(b, 48, a, 0, 0, 48, 48))
  end
  ok("damped fBm with damping 0 equals fBm", diff < 1e-5)

  local function roughness(damping)
    local b = vnoise.fill_sampler(s, { kind = "damped", damping = damping }, { w = 256, h = 256, freq = 0.01 })
    local sum = 0
    for j = 0, 255 do
      for i = 0, 254 do
        sum = sum + math.abs(b[j * 256 + i + 1] - b[j * 256 + i])
      end
    end
    return sum
  end
  ok("damping smooths the field", roughness(4) < roughness(0))
end

-- Every fill accepts every sampler kind ------------------------------------------

do
  local same = true
  for _, kind in ipairs({ "damped", "cell_f1", "cell_f2", "cell_edge", "cell_value" }) do
    local spec = { kind = kind, octaves = 3, jitter = 0.6, damping = 2 }
    local opts = { w = 24, h = 24, freq = 0.07, octaves = 3, jitter = 0.6, damping = 2 }
    local ref = vnoise.fill_sampler(s, spec, { w = 24, h = 24, freq = 0.07 })
    local grid = vnoise.fill_grid(s, kind, opts)
    same = same and blockDiff(ref, 24, grid, 0, 0, 24, 24) < 1e-6
    local dom = { rotate = 25, warp = { amp = 3, freq = 0.05 } }
    local a = vnoise.fill_domain(
      s,
      kind,
      { c0 = 5, r0 = -2, w = 24, h = 24, freq = 0.07, octaves = 3, jitter = 0.6, damping = 2, domain = dom }
    )
    local b = vnoise.fill_sampler(s, spec, { c0 = 5, r0 = -2, w = 24, h = 24, freq = 0.07, domain = dom })
    same = same and blockDiff(b, 24, a, 0, 0, 24, 24) < 1e-6
    local p = vnoise.fill_pipeline(
      s,
      kind,
      { domain = dom },
      { c0 = 5, r0 = -2, w = 24, h = 24, freq = 0.07, octaves = 3, jitter = 0.6, damping = 2, clamp = false }
    )
    same = same and blockDiff(b, 24, p, 0, 0, 24, 24) < 1e-6
  end
  ok("fill_grid, fill_domain and fill_pipeline accept every sampler kind", same)
  local jit_a = vnoise.fill_grid(s, "cell_f1", { w = 16, h = 16, freq = 0.1, jitter = 0 })
  local jit_b = vnoise.fill_grid(s, "cell_f1", { w = 16, h = 16, freq = 0.1, jitter = 1 })
  ok("fill options carry jitter", blockDiff(jit_a, 16, jit_b, 0, 0, 16, 16) > 1e-3)
  ok("unknown kinds still raise", raises("voronoi", vnoise.fill_grid, s, "voronoi", { w = 2, h = 2 }))
  local tiling = tilingDiff(64, 2, function(c0, r0, w, h)
    return vnoise.fill_pipeline(
      s,
      "cell_edge",
      { stages = { { "gaussian", 1 }, { "gullies" } } },
      { c0 = c0, r0 = r0, w = w, h = h, freq = 0.05, jitter = 0.8 }
    )
  end)
  ok("new kinds tile through pipelines", tiling < 1e-5)
end

-- Cellular ---------------------------------------------------------------------

do
  local c = lib.cellular2_eval
  ok("cellular F1 at a cell center is 0", near(c(s.s, 3.5, 7.5, 0, 0), 0))
  ok("cellular F2 at a cell center is 1/1.5", near(c(s.s, 3.5, 7.5, 0, 1), 1 / 1.5))
  ok("cellular EDGE at a cell center is 1", near(c(s.s, 3.5, 7.5, 0, 2), 1))
  ok("cellular F1 at a corner is sqrt(0.5)", near(c(s.s, 3, 7, 0, 0), math.sqrt(0.5)))
  ok("cellular EDGE at a corner is 0", near(c(s.s, 3, 7, 0, 2), 0))
  local inrange = true
  for _ = 1, 100000 do
    local x, y = math.random() * 1000 - 500, math.random() * 1000 - 500
    for ret = 0, 3 do
      local v = c(s.s, x, y, 1, ret)
      inrange = inrange and v >= 0 and v <= 1
    end
  end
  ok("cellular values lie in [0, 1]", inrange)

  local b = vnoise.fill_sampler(s, { kind = "cell_f1", octaves = 1 }, { w = 32, h = 32, freq = 0.1 })
  local same = true
  for j = 0, 31 do
    for i = 0, 31 do
      same = same and near(b[j * 32 + i], c(s.s, i * 0.1, j * 0.1, 1, 0), 1e-6)
    end
  end
  ok("single-octave cellular sampler equals cellular2_eval", same)
  local e = vnoise.fill_sampler(s, { kind = "cell_edge", octaves = 4 }, { w = 256, h = 256, freq = 0.05 })
  local lo, hi = minmax(e, 256 * 256)
  ok("fractal cellular stays in [0, 1]", lo >= 0 and hi <= 1)
end

-- Sources ----------------------------------------------------------------------

do
  ok(
    "unknown source node raises naming it",
    raises("xor", vnoise.compile_source, { "xor", { "const", 1 }, { "const", 2 } })
  )
  ok("sub with one child raises", raises("sub", vnoise.compile_source, { "sub", { "const", 1 } }))
  local l = vnoise.fill_source(s, { "lerp", { "const", 0.2 }, { "const", 0.6 }, { "const", 0.25 } }, { w = 8, h = 8 })
  local all03 = true
  for k = 0, 63 do
    all03 = all03 and near(l[k], 0.3, 1e-6)
  end
  ok("lerp combinator arithmetic", all03)
  local a = vnoise.fill_source(
    s,
    { "add", { "const", 0.5 }, { "mul", { "const", 0.5 }, { "const", 0.4 } }, weights = { 2, 1 } },
    { w = 2, h = 2 }
  )
  ok("weighted add and mul", near(a[0], 1.2, 1e-6))

  local leaf = vnoise.fill_source(
    s,
    { "ridge", freq = 0.02, ops = { { "remap", 0, 1 } } },
    { c0 = 5, r0 = 9, w = 32, h = 32 }
  )
  local ref = vnoise.fill_sampler(s, { kind = "ridge" }, { c0 = 5, r0 = 9, w = 32, h = 32, freq = 0.02 })
  local chain = vnoise.compile_ops({ { "remap", 0, 1 } })
  lib.vnoise_map_buffer(ref, 32 * 32, chain.ops, chain.n, chain.data, 0)
  ok("sampler leaf equals fill_sampler and its ops", blockDiff(ref, 32, leaf, 0, 0, 32, 32) < 1e-6)

  local tree = {
    "add",
    { "fbm", freq = 0.03, domain = { rotate = 20, warp = { amp = 5, freq = 0.04 } } },
    { "cell_edge", freq = 0.05, seed = 5 },
    { "pipeline", { stages = { { "gaussian", 1.5 } } }, kind = "ridge", freq = 0.04 },
    weights = { 1, 0.5, 0.25 },
  }
  local d = tilingDiff(64, 2, function(c0, r0, w, h)
    return vnoise.fill_source(s, tree, { c0 = c0, r0 = r0, w = w, h = h })
  end)
  ok("source trees tile", d < 1e-5)

  local full = vnoise.fill_source(s, tree, { w = 64, h = 64 })
  local strided = vnoise.fill_source(s, tree, { w = 8, h = 8, stride = 8 })
  local sd = 0
  for j = 0, 7 do
    for i = 0, 7 do
      sd = math.max(sd, math.abs(strided[j * 8 + i] - full[j * 8 * 64 + i * 8]))
    end
  end
  ok("stride samples every stride-th cell", sd < 1e-5)

  local ranges = true
  for _, preset in ipairs({ vnoise.presets.continent(), vnoise.presets.mountain_belts() }) do
    local b = vnoise.fill_source(s, preset, { w = 256, h = 256, stride = 4 })
    local lo, hi = minmax(b, 256 * 256)
    ranges = ranges and lo >= -1e-5 and hi <= 1 + 1e-5
  end
  ok("presets lie in [0, 1]", ranges)
end

-- Pipelines with sources and gullies ---------------------------------------------

do
  ok("gullies radius is 1", vnoise.compile_pipeline({ stages = { { "gullies" }, { "blur", 2 } } }).radius == 3)
  ok(
    "domain and source together raise naming source",
    raises("source", vnoise.compile_pipeline, { domain = { rotate = 10 }, source = { "const", 1 } })
  )
  ok("gullies scale 0 raises", raises("scale", vnoise.compile_pipeline, { stages = { { "gullies", scale = 0 } } }))
  ok(
    "gullies octaves 5 raises",
    raises("octaves", vnoise.compile_pipeline, { stages = { { "gullies", octaves = 5 } } })
  )

  local src = { "add", { "fbm", freq = 0.02 }, { "cell_f1", freq = 0.05, seed = 3 } }
  local p = { source = src, stages = { { "gaussian", 1 } } }
  local d = tilingDiff(64, 2, function(c0, r0, w, h)
    return vnoise.fill_pipeline(s, nil, p, { c0 = c0, r0 = r0, w = w, h = h })
  end)
  ok("pipeline with a source tiles", d < 1e-5)
  local plain = vnoise.fill_pipeline(s, nil, { source = src }, { c0 = 3, r0 = 4, w = 32, h = 32 })
  local ref = vnoise.fill_source(s, src, { c0 = 3, r0 = 4, w = 32, h = 32, clamp = true })
  ok("stage-less source pipeline equals fill_source clamped", blockDiff(ref, 32, plain, 0, 0, 32, 32) < 1e-6)

  local flat = vnoise.fill_pipeline(
    s,
    nil,
    { source = { "const", 0.4 }, stages = { { "gullies" } } },
    { w = 16, h = 16 }
  )
  local unchanged = true
  for k = 0, 255 do
    unchanged = unchanged and near(flat[k], 0.4, 1e-7)
  end
  ok("gullies leave a flat input unchanged", unchanged)

  local gp = {
    source = { "damped", freq = 0.01, ops = { { "remap", -1, 1 } } },
    stages = { { "gullies", scale = 6, strength = 0.1, octaves = 3 } },
  }
  local gd = tilingDiff(64, 2, function(c0, r0, w, h)
    return vnoise.fill_pipeline(s, nil, gp, { c0 = c0, r0 = r0, w = w, h = h, clamp = false })
  end)
  ok("gullies tile", gd < 1e-5)
  local g = vnoise.fill_pipeline(s, nil, gp, { w = 64, h = 64, clamp = false })
  local base = vnoise.fill_source(s, gp.source, { w = 64, h = 64 })
  ok("gullies change a sloped input", blockDiff(base, 64, g, 0, 0, 64, 64) > 1e-3)
end

-- Terrain plan -------------------------------------------------------------------

local function grid(plan, name)
  return plan:grid(name), plan.mw, plan.mh
end

do
  local p = vnoise.terrain_plan(s, { width = 1000, height = 500, macro_cell = 64, elevation = { "const", 0.5 } })
  ok("macro grid size", p.mw == 17 and p.mh == 9)
  ok("missing elevation raises naming it", raises("elevation", vnoise.terrain_plan, s, { width = 64, height = 64 }))
  ok(
    "bad option raises naming it",
    raises("erosion.diffusion", vnoise.terrain_plan, s, {
      width = 64,
      height = 64,
      elevation = { "const", 0.5 },
      erosion = { diffusion = 0.5 },
    })
  )
  ok(
    "too many nodes raises",
    raises(
      "macro_cell",
      vnoise.terrain_plan,
      s,
      { width = 65536, height = 65536, macro_cell = 4, elevation = { "const", 0 } }
    )
  )
end

-- A reference world: continent plus mountain belts, eroded, with rivers.
local W = 4096
local function worldSpec(extra)
  local spec = {
    width = W,
    height = W,
    macro_cell = 32,
    sea_level = 0.3,
    elevation = {
      "add",
      vnoise.presets.continent({ width = W, height = W, seed = 1 }),
      vnoise.presets.mountain_belts({ seed = 2, freq = 1 / 200, belt_freq = 1 / 1500 }),
      weights = { 0.75, 0.35 },
      ops = { { "clamp", 0, 1 } },
    },
    uplift = vnoise.presets.mountain_belts({ seed = 2, freq = 1 / 200, belt_freq = 1 / 1500 }),
    erosion = { iterations = 60 },
    rivers = { min_flow = 16 },
  }
  for k, v in pairs(extra or {}) do
    spec[k] = v
  end
  return spec
end

local world = vnoise.terrain_plan(s, worldSpec())
local rivers = world:rivers()
print(("  info world %d x %d nodes, %d polylines"):format(world.mw, world.mh, #rivers))
ok("the reference world has rivers", #rivers > 5)

do
  local other = vnoise.terrain_plan(vnoise.new(1234), worldSpec())
  local same = true
  for _, name in ipairs({ "height", "filled", "flow" }) do
    local a, b = world:grid(name), other:grid(name)
    for k = 0, world.mw * world.mh - 1 do
      same = same and a[k] == b[k]
    end
  end
  local r2 = other:rivers()
  same = same and #r2 == #rivers
  for k = 1, math.min(#r2, #rivers) do
    for i, v in ipairs(rivers[k].points) do
      same = same and r2[k].points[i] == v
    end
    for i, v in ipairs(rivers[k].bed) do
      same = same and r2[k].bed[i] == v
    end
  end
  ok("plans are deterministic", same)
end

do
  local F, mw, mh = grid(world, "filled")
  local O = world:grid("outlet")
  local R = world:grid("receiver")
  local A = world:grid("flow")
  local pits, downhill, outsum = 0, true, 0
  for j = 0, mh - 1 do
    for i = 0, mw - 1 do
      local k = j * mw + i
      if O[k] == 1 then
        outsum = outsum + A[k]
      else
        local lower = false
        for dj = -1, 1 do
          for di = -1, 1 do
            local ii, jj = i + di, j + dj
            if (di ~= 0 or dj ~= 0) and ii >= 0 and jj >= 0 and ii < mw and jj < mh and F[jj * mw + ii] < F[k] then
              lower = true
            end
          end
        end
        pits = pits + (lower and 0 or 1)
        local r = R[k]
        downhill = downhill and r >= 0 and F[r] < F[k]
      end
    end
  end
  ok("no pits after filling", pits == 0)
  ok("receivers are strictly lower", downhill)
  ok("flow is conserved at the outlets", outsum == mw * mh)
end

do
  -- Bowl: an 0.8 ring around a 0.2 floor, outlets on the edges, no erosion.
  local mc = 4
  local bowl = {
    "add",
    { "const", 0 },
    { "mask", { "ellipse", 100, 100, 80, 80, feather = 12 } },
    { "mask", { "ellipse", 100, 100, 48, 48, feather = 12 } },
    weights = { 1, 0.8, -0.6 },
  }
  local p = vnoise.terrain_plan(s, {
    width = 200,
    height = 200,
    macro_cell = mc,
    elevation = bowl,
    outlets = "edges",
    erosion = { iterations = 0 },
  })
  local F, L, mw = p:grid("filled"), p:grid("lake"), p.mw
  local lakes, surface = true, true
  for j = 0, p.mh - 1 do
    for i = 0, mw - 1 do
      local dx, dy = i * mc - 100, j * mc - 100
      if dx * dx + dy * dy < 30 * 30 then
        lakes = lakes and L[j * mw + i] == 1
        surface = surface and near(F[j * mw + i], 0.8, 1e-4)
      end
    end
  end
  ok("a closed bowl becomes a lake", lakes)
  ok("the lake surface is the rim's pass height", surface)

  local H = p:grid("height")
  local ref = vnoise.fill_source(s, bowl, { w = p.mw, h = p.mh, stride = mc, clamp = true })
  ok("no erosion keeps the sampled height", blockDiff(ref, p.mw, H, 0, 0, p.mw, p.mh) < 1e-6)
end

do
  -- Mean height of the top 5% accumulation nodes over the mean height.
  local function drainageRatio(iterations)
    local ridge = { "ridge", freq = 1 / 300, octaves = 5 }
    local p = vnoise.terrain_plan(s, {
      width = 2048,
      height = 2048,
      macro_cell = 16,
      elevation = ridge,
      uplift = ridge,
      erosion = { iterations = iterations },
    })
    local H, A, n = p:grid("height"), p:grid("flow"), p.mw * p.mh
    local list, mean = {}, 0
    for k = 0, n - 1 do
      list[#list + 1] = k
      mean = mean + H[k]
    end
    table.sort(list, function(a, b)
      return A[a] > A[b]
    end)
    local top, count = 0, math.floor(n * 0.05)
    for i = 1, count do
      top = top + H[list[i]]
    end
    return (top / count) / (mean / n)
  end
  ok("erosion carves valleys along the drainage", drainageRatio(100) < drainageRatio(0))

  local strong = vnoise.terrain_plan(s, {
    width = 2048,
    height = 2048,
    macro_cell = 16,
    elevation = { "fbm", freq = 1 / 500, ops = { { "remap", -1, 1 } } },
    uplift = { "const", 1 },
    erosion = { iterations = 200, uplift = 0.05 },
  })
  local lo, hi = minmax(strong:grid("height"), strong.mw * strong.mh)
  ok("strong uplift keeps heights in [0, 1]", lo >= 0 and hi <= 1)
end

do
  local mono, reach = true, true
  local starts = {}
  for _, r in ipairs(rivers) do
    starts[r.points[1] .. "," .. r.points[2]] = true
  end
  local O, mw, mc = world:grid("outlet"), world.mw, world.macro_cell
  for _, r in ipairs(rivers) do
    for k = 2, #r.bed do
      mono = mono and r.bed[k] <= r.bed[k - 1]
    end
    local n = #r.points
    local x, y = r.points[n - 1], r.points[n]
    if r.mouth == "river" then
      reach = reach and starts[x .. "," .. y] == true
    else
      reach = reach and O[(y / mc) * mw + x / mc] == 1
    end
  end
  ok("river beds never rise downstream", mono)
  ok("every river ends at an outlet or another river", reach)

  local dry = vnoise.terrain_plan(s, worldSpec({ rivers = { min_flow = 1e9 } }))
  ok("no rivers above the flow threshold", #dry:rivers() == 0)
  ok("a plan without rivers answers no query", dry:query(2000, 2000) == nil)
  ok("far outside the extent there is no river", world:query(-100000, -100000) == nil)

  local good, tested = true, 0
  for _, r in ipairs(rivers) do
    for k = 2, #r.bed - 1 do
      local d, bed = world:query(r.points[2 * k - 1], r.points[2 * k])
      good = good and d ~= nil and d <= 0.5 and near(bed, r.bed[k], 1e-4)
      tested = tested + 1
    end
  end
  ok(("query at river vertices (%d)"):format(tested), good and tested > 0)
end

do
  local spec = worldSpec({ erosion = { iterations = 100 } })
  spec.width, spec.height, spec.macro_cell = 16384, 16384, 64
  local t0 = os.clock()
  local big = vnoise.terrain_plan(s, spec)
  local ms = (os.clock() - t0) * 1000
  print(("  info plan build %d x %d nodes, 100 iterations: %.0f ms"):format(big.mw, big.mh, ms))
  ok("plan build under 500 ms", ms < 500)
end

-- Terrain detail -------------------------------------------------------------------

local ALL = { "elevation", "river", "lake", "flow", "channel_distance" }

-- A region crossed by the reference world's largest river.
local function riverRegion(plan, n)
  local best, flow = nil, -1
  for _, r in ipairs(plan:rivers()) do
    local k = math.floor(#r.flow / 2) + 1
    if r.flow[k] > flow and #r.flow > 4 then
      best, flow = r, r.flow[k]
    end
  end
  local k = math.floor(#best.flow / 2) + 1
  return math.floor(best.points[2 * k - 1]) - n / 2, math.floor(best.points[2 * k]) - n / 2
end

do
  ok(
    "unknown terrain output raises naming it",
    raises("snow", vnoise.fill_terrain, s, world, { w = 4, h = 4, outputs = { "elevation", "snow" } })
  )

  local detailed = vnoise.terrain_plan(
    s,
    worldSpec({
      rivers = { min_flow = 16, meander_amp = 6 },
      detail = { source = { "damped", freq = 1 / 30, octaves = 4 }, amplitude = 0.05 },
    })
  )
  local cx, cy = riverRegion(detailed, 128)
  local worst = 0
  for _, name in ipairs(ALL) do
    worst = math.max(
      worst,
      tilingDiff(128, 4, function(c0, r0, w, h)
        return vnoise.fill_terrain(s, detailed, { c0 = cx + c0, r0 = cy + r0, w = w, h = h, outputs = { name } })[name]
      end)
    )
  end
  ok("all terrain outputs tile", worst < 1e-5)

  local strong = vnoise.terrain_plan(s, worldSpec({ detail = { source = { "fbm", freq = 1 / 20 }, amplitude = 0.3 } }))
  local res = vnoise.fill_terrain(s, strong, { c0 = 1500, r0 = 1500, w = 512, h = 512, outputs = ALL })
  local inrange = true
  for _, name in ipairs(ALL) do
    local lo, hi = minmax(res[name], 512 * 512)
    inrange = inrange and lo >= 0 and hi <= 1
  end
  ok("all terrain outputs lie in [0, 1]", inrange)
end

do
  local cx, cy = riverRegion(world, 128)
  local res = vnoise.fill_terrain(s, world, { c0 = cx, r0 = cy, w = 128, h = 128, outputs = ALL })
  local below, equal, inside, mask_ok = true, 0, 0, true
  local R = 64
  for j = 0, 127 do
    for i = 0, 127 do
      local k = j * 128 + i
      local d, bed, width = world:query(cx + i, cy + j)
      if d and d <= width / 2 then
        inside = inside + 1
        local e = res.elevation[k]
        below = below and e <= bed + 1e-5
        equal = equal + (near(e, bed, 1e-5) and 1 or 0)
        mask_ok = mask_ok and res.river[k] == 1 and near(res.channel_distance[k], d / R, 1e-5)
      elseif not d then
        mask_ok = mask_ok and res.river[k] == 0 and res.channel_distance[k] == 1
      end
    end
  end
  ok(
    ("channel cells sit on the bed (%d/%d equal)"):format(equal, inside),
    inside > 0 and below and equal >= 0.9 * inside
  )
  ok("river mask and channel distance match the query", mask_ok)
end

do
  local dry = vnoise.terrain_plan(s, worldSpec({ rivers = { min_flow = 1e9 } }))
  local H, mw, mc = dry:grid("height"), dry.mw, dry.macro_cell
  local same = true
  for j = 10, 20 do
    local res = vnoise.fill_terrain(s, dry, { c0 = 0, r0 = j * mc, w = W + 1, h = 1 })
    for i = 0, mw - 1 do
      same = same and near(res.elevation[i * mc], H[j * mw + i], 1e-5)
    end
  end
  ok("without rivers or detail the elevation at nodes is the macro height", same)
end

do
  -- Walk the largest river's channel: elevations at its vertices (rounded to
  -- cells, outside lakes) never rise downstream.
  local mono, samples = true, 0
  for _, r in ipairs(rivers) do
    local prev
    for k = 1, #r.bed do
      local c, rr = math.floor(r.points[2 * k - 1] + 0.5), math.floor(r.points[2 * k] + 0.5)
      local res = world
        and vnoise.fill_terrain(s, world, { c0 = c, r0 = rr, w = 1, h = 1, outputs = { "elevation", "river", "lake" } })
      if res.river[0] == 1 and res.lake[0] == 0 then
        local e = res.elevation[0]
        if prev then
          mono = mono and e <= prev + 1e-4
        end
        prev = e
        samples = samples + 1
      end
    end
  end
  ok(("elevation never rises along the channels (%d samples)"):format(samples), mono and samples > 0)
end

do
  local m = vnoise.terrain_plan(s, worldSpec({ rivers = { min_flow = 16, meander_amp = 10 } }))
  local cx, cy = riverRegion(m, 128)
  local res = vnoise.fill_terrain(s, m, { c0 = cx, r0 = cy, w = 128, h = 128, outputs = { "river" } })
  -- Unwarped distance to the polylines, brute force.
  local segs = {}
  for _, r in ipairs(m:rivers()) do
    for k = 1, #r.width - 1 do
      segs[#segs + 1] = {
        r.points[2 * k - 1],
        r.points[2 * k],
        r.points[2 * k + 1],
        r.points[2 * k + 2],
        math.max(r.width[k], r.width[k + 1]),
      }
    end
  end
  local bounded, count = true, 0
  for j = 0, 127 do
    for i = 0, 127 do
      if res.river[j * 128 + i] == 1 then
        count = count + 1
        local x, y, best = cx + i, cy + j, math.huge
        for _, sg in ipairs(segs) do
          local ex, ey = sg[3] - sg[1], sg[4] - sg[2]
          local t = math.max(0, math.min(1, ((x - sg[1]) * ex + (y - sg[2]) * ey) / (ex * ex + ey * ey)))
          local dx, dy = sg[1] + t * ex - x, sg[2] + t * ey - y
          best = math.min(best, math.sqrt(dx * dx + dy * dy) - sg[5] / 2)
        end
        bounded = bounded and best <= 10 + 1
      end
    end
  end
  ok(("meanders stay within their amplitude (%d channel cells)"):format(count), bounded and count > 0)
end

do
  local A, mw, mc = world:grid("flow"), world.mw, world.macro_cell
  local best, amax = 0, -1
  for k = 0, mw * world.mh - 1 do
    if A[k] > amax then
      best, amax = k, A[k]
    end
  end
  local res = vnoise.fill_terrain(
    s,
    world,
    { c0 = (best % mw) * mc, r0 = math.floor(best / mw) * mc, w = 1, h = 1, outputs = { "flow" } }
  )
  ok("flow is 1 at the largest accumulation", near(res.flow[0], 1, 1e-4))
end

do
  local p = { source = { "plan", world, output = "elevation" }, stages = { { "gullies", scale = 8, strength = 0.03 } } }
  local cx, cy = riverRegion(world, 64)
  local d = tilingDiff(64, 2, function(c0, r0, w, h)
    return vnoise.fill_pipeline(s, nil, p, { c0 = cx + c0, r0 = cy + r0, w = w, h = h })
  end)
  ok("a pipeline over a plan output tiles", d < 1e-5)
  ok(
    "plan leaf with an unknown output raises",
    raises("snow", vnoise.compile_source, { "plan", world, output = "snow" })
  )
end

do
  local detailed = vnoise.terrain_plan(s, worldSpec({ detail = { source = { "fbm", freq = 1 / 40, octaves = 6 } } }))
  local n, t0 = 40, os.clock()
  for k = 1, n do
    vnoise.fill_terrain(s, detailed, { c0 = 1000 + k * 64, r0 = 2000, w = 64, h = 64, outputs = ALL })
  end
  local ms = (os.clock() - t0) * 1000 / n
  print(("  info fill 64 x 64, all outputs, 6-octave detail: %.2f ms"):format(ms))
  ok("block fill under 2 ms", ms < 2)
end

print(failures == 0 and "all terrain tests passed" or (failures .. " failure(s)"))
os.exit(failures == 0 and 0 or 1)
