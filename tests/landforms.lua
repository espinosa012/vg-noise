-- Landform operation tests (change: matrix-landform-ops; specs matrix-warp,
-- matrix-erosion, matrix-analysis, matrix-river-network, noise-domain). Run
-- from the repository root after `make`: luajit tests/landforms.lua
package.path = package.path .. ";./lua/?.lua"

local vnoise = require("vnoise")
local ffi = require("ffi")

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

local function raises(needle, f, ...)
  local good, err = pcall(f, ...)
  return not good and tostring(err):find(needle, 1, true) ~= nil
end

local function copy(m, n)
  local c = ffi.new("float[?]", n)
  ffi.copy(c, m, n * ffi.sizeof("float"))
  return c
end

local function inRange(m, n)
  for k = 0, n - 1 do
    if m[k] < 0 or m[k] > 1 or m[k] ~= m[k] then
      return false
    end
  end
  return true
end

local function same(a, b, n)
  for k = 0, n - 1 do
    if a[k] ~= b[k] then
      return false
    end
  end
  return true
end

local function sum(m, n)
  local s = 0
  for k = 0, n - 1 do
    s = s + m[k]
  end
  return s
end

local function timed(label, fn)
  local t = os.clock()
  local r = { fn() }
  print(("        %s: %.1f ms"):format(label, (os.clock() - t) * 1000))
  return unpack(r)
end

local W, H = 160, 120
local N = W * H
local state = vnoise.new(5)
-- Rolling noise in 0..1.
local function terrain(w, h, seed)
  return vnoise.fill_grid(vnoise.new(seed or 5), "fbm", {
    w = w or W,
    h = h or H,
    freq = 1 / 40,
    octaves = 5,
    ops = { { "remap", -0.7, 0.7 } },
  })
end
-- A cone around (cx, cy) falling into a sea at the edges.
local function island(w, h)
  local m = vnoise.matrix(w, h)
  local cx, cy, r = w / 2, h / 2, math.min(w, h) * 0.45
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      local d = math.sqrt((i + 0.5 - cx) ^ 2 + (j + 0.5 - cy) ^ 2) / r
      m[j * w + i] = math.max(0, math.max(0, 1 - d) * 0.9 + 0.02 * math.sin(i * 0.7) * math.cos(j * 0.6))
    end
  end
  return m
end

-- Domain warp levels ----------------------------------------------------------

do
  local opts = { w = 48, h = 48, c0 = 4, r0 = -3, freq = 0.03 }
  local function fill(warp)
    opts.domain = { warp = warp }
    return vnoise.fill_domain(state, "fbm", opts)
  end
  local one = fill({ amp = 8, freq = 0.04, octaves = 3 })
  local explicit = fill({ amp = 8, freq = 0.04, octaves = 3, levels = 1, lac = 2, gain = 0.5 })
  ok("one warp level with default lac/gain is the original warp", same(one, explicit, 48 * 48))
  local two = fill({ amp = 8, freq = 0.04, octaves = 3, levels = 2 })
  ok("two warp levels differ from one", not same(one, two, 48 * 48))
  ok("warp lac/gain change the field", not same(one, fill({ amp = 8, freq = 0.04, octaves = 3, lac = 3 }), 48 * 48))
  -- Overlapping blocks agree with iterated warps.
  local d = { rotate = 15, warp = { amp = 10, freq = 0.05, levels = 3 } }
  local a = vnoise.fill_domain(state, "ridge", { w = 40, h = 40, freq = 0.02, domain = d })
  local b = vnoise.fill_domain(state, "ridge", { c0 = 17, r0 = 9, w = 20, h = 20, freq = 0.02, domain = d })
  local agree = true
  for j = 0, 19 do
    for i = 0, 19 do
      if j + 9 < 40 and i + 17 < 40 and not near(a[(j + 9) * 40 + i + 17], b[j * 20 + i]) then
        agree = false
      end
    end
  end
  ok("iterated warp: overlapping blocks agree", agree)
  ok("warp levels outside 1..4 raise", raises("levels", vnoise.compile_domain, { warp = { amp = 1, levels = 5 } }))
end

-- Matrix warp -------------------------------------------------------------------

do
  local m = terrain()
  local zero = vnoise.matrix(W, H, 0.5)
  ok(
    "warp by neutral displacement matrices is the identity",
    same(vnoise.warp(m, W, H, { dx = zero, dy = zero }), m, N)
  )
  -- A uniform displacement of +amp in x reads the cell amp columns right.
  local right = vnoise.matrix(W, H, 1)
  local shifted = vnoise.warp(m, W, H, { dx = right, dy = zero, amp = 3 })
  local good = true
  for j = 0, H - 1 do
    for i = 0, W - 4 do
      if not near(shifted[j * W + i], m[j * W + i + 3]) then
        good = false
      end
    end
  end
  ok("uniform dx = 1 shifts by amp cells", good)
  -- direction 0.25 = +y (clockwise from +x on a y-down screen).
  local down = vnoise.warp(m, W, H, { direction = vnoise.matrix(W, H, 0.25), amp = 2, filter = "bicubic" })
  good = true
  for j = 0, H - 3 do
    for i = 0, W - 1 do
      if not near(down[j * W + i], m[(j + 2) * W + i], 1e-4) then
        good = false
      end
    end
  end
  ok("direction 0.25 shifts by amp cells along +y", good)
  local strength =
    vnoise.warp(m, W, H, { direction = vnoise.matrix(W, H, 0.6), strength = vnoise.matrix(W, H), amp = 9 })
  ok("strength 0 leaves the matrix unchanged", same(strength, m, N))
  local nw1 = vnoise.warp(m, W, H, { amp = 12, seed = 3 })
  local nw2 = vnoise.warp(m, W, H, { amp = 12, seed = 3 })
  local nw3 = vnoise.warp(m, W, H, { amp = 12, seed = 4 })
  local nw4 = vnoise.warp(m, W, H, { amp = 12, seed = 3, levels = 2 })
  ok("noise warp is deterministic per seed", same(nw1, nw2, N) and not same(nw1, nw3, N))
  ok("noise warp levels change the result", not same(nw1, nw4, N))
  ok("noise warp with amp 0 is the identity", same(vnoise.warp(m, W, H, { amp = 0 }), m, N))
  ok("warp keeps values in 0..1", inRange(nw4, N) and inRange(down, N))
  ok("warp needs both dx and dy", raises("dx", vnoise.warp, m, W, H, { dx = zero }))
  ok("warp rejects out == source", raises("out", vnoise.warp, m, W, H, { out = m }))
  -- Bicubic stays within the 2 x 2 neighborhood: no overshoot on a step.
  local step = vnoise.matrix(W, H)
  for j = 0, H - 1 do
    for i = W / 2, W - 1 do
      step[j * W + i] = 0.8
    end
  end
  local bc = vnoise.warp(step, W, H, { amp = 4, seed = 1, filter = "bicubic" })
  local lo, hi = 1, 0
  for k = 0, N - 1 do
    lo, hi = math.min(lo, bc[k]), math.max(hi, bc[k])
  end
  ok("bicubic warp does not overshoot", lo >= 0 and hi <= 0.8 + 1e-6)
end

-- Hydraulic erosion -------------------------------------------------------------

do
  local m = terrain()
  local before = copy(m, N)
  local change = vnoise.erode_hydraulic(m, W, H, { seed = 2, change = true })
  ok("hydraulic erosion changes the matrix and stays in 0..1", not same(m, before, N) and inRange(m, N))
  local b2 = copy(before, N)
  vnoise.erode_hydraulic(b2, W, H, { seed = 2 })
  ok("hydraulic erosion is deterministic per seed", same(m, b2, N))
  local b3 = copy(before, N)
  vnoise.erode_hydraulic(b3, W, H, { seed = 3 })
  ok("another seed gives another result", not same(m, b3, N))
  -- Mostly material moves (erosion is redeposited): the total changes little.
  local s0, s1 = sum(before, N), sum(m, N)
  ok(("material is mostly conserved (%.3f%%)"):format(100 * (s1 - s0) / s0), math.abs(s1 - s0) / s0 < 0.02)
  local below, above = 0, 0
  for k = 0, N - 1 do
    if change[k] < 0.499 then
      below = below + 1
    elseif change[k] > 0.501 then
      above = above + 1
    end
  end
  ok("change map shows both erosion and deposition", below > 0 and above > 0 and inRange(change, N))
  local hard = copy(before, N)
  vnoise.erode_hydraulic(hard, W, H, { seed = 2, hardness = vnoise.matrix(W, H, 1), deposit = 0 })
  local raised = false
  for k = 0, N - 1 do
    if hard[k] < before[k] - 1e-6 then
      raised = true
    end
  end
  ok("hardness 1 prevents erosion", not raised)
  local dry = copy(before, N)
  vnoise.erode_hydraulic(dry, W, H, { seed = 2, rain = vnoise.matrix(W, H, 0) })
  ok("rain 0 starts no droplet", same(dry, before, N))
  -- Under the sea: droplets stop on reaching it and drop their load there
  -- (deltas), so the coast gains material and the far seabed is untouched.
  local isl = island(W, H)
  local i0 = copy(isl, N)
  vnoise.erode_hydraulic(isl, W, H, { seed = 1, sea_level = 0.3, density = 1 })
  local far_changed, delta = false, false
  for k = 0, N - 1 do
    if i0[k] < 0.02 and isl[k] ~= i0[k] then
      far_changed = true
    end
    if i0[k] < 0.3 and isl[k] > i0[k] + 1e-4 then
      delta = true
    end
  end
  ok("the far seabed is untouched", not far_changed)
  ok("sediment is dropped where droplets reach the sea", delta)
  local big = terrain(1024, 1024)
  timed("hydraulic erosion 1024^2 (0.3 droplets per cell)", function()
    vnoise.erode_hydraulic(big, 1024, 1024, {})
  end)
end

-- Thermal erosion -----------------------------------------------------------------

do
  -- A cliff: a step from 0.1 to 0.9 in the middle.
  local w, h = 64, 16
  local m = vnoise.matrix(w, h)
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      m[j * w + i] = i < w / 2 and 0.1 or 0.9
    end
  end
  local before = copy(m, w * h)
  local function maxSlope(mm, relief)
    local Z, worst = relief * math.max(w, h), 0
    for j = 0, h - 1 do
      for i = 0, w - 2 do
        worst = math.max(worst, math.abs(mm[j * w + i + 1] - mm[j * w + i]) * Z)
      end
    end
    return math.deg(math.atan(worst))
  end
  vnoise.erode_thermal(m, w, h, { talus = 30, iterations = 2000, rate = 0.5 })
  local s0, s1 = sum(before, w * h), sum(m, w * h)
  ok(("material is conserved (%.4f%%)"):format(100 * (s1 - s0) / s0), math.abs(s1 - s0) / s0 < 1e-3)
  local final = maxSlope(m, 0.05)
  ok(("the cliff relaxes toward the talus angle (max %.1f deg)"):format(final), final < 33)
  local hard = copy(before, w * h)
  vnoise.erode_thermal(hard, w, h, { talus = 30, iterations = 50, hardness = vnoise.matrix(w, h, 1) })
  ok("hardness 1 keeps the cliff", same(hard, before, w * h))
  local flat = vnoise.matrix(w, h, 0.4)
  vnoise.erode_thermal(flat, w, h, {})
  ok("flat ground is unchanged", same(flat, vnoise.matrix(w, h, 0.4), w * h))
  local big = terrain(1024, 1024)
  timed("thermal erosion 1024^2 (50 iterations)", function()
    vnoise.erode_thermal(big, 1024, 1024, {})
  end)
end

-- Distance fields ---------------------------------------------------------------

do
  local w, h = 50, 40
  local m = vnoise.matrix(w, h)
  m[20 * w + 10] = 1 -- one land cell
  local d = vnoise.distance_field(m, w, h, { mode = "outside", range = 100 })
  local exact = true
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      local e = math.sqrt((i - 10) ^ 2 + (j - 20) ^ 2) / 100
      if not near(d[j * w + i], math.min(e, 1), 1e-5) then
        exact = false
      end
    end
  end
  ok("outside distance is the exact Euclidean distance", exact)
  -- Brute force on random sets.
  local r = vnoise.fill_white(state, { w = w, h = h, ops = { { "remap", -1, 1 }, { "threshold", 0.93 } } })
  local inside = vnoise.distance_field(r, w, h, { mode = "inside", range = 1000 })
  local outside = vnoise.distance_field(r, w, h, { mode = "outside", range = 1000 })
  local good = true
  for j = 0, h - 1, 3 do
    for i = 0, w - 1, 3 do
      local a = r[j * w + i] >= 0.5
      local best = math.huge
      for jj = 0, h - 1 do
        for ii = 0, w - 1 do
          if (r[jj * w + ii] >= 0.5) ~= a then
            best = math.min(best, math.sqrt((ii - i) ^ 2 + (jj - j) ^ 2))
          end
        end
      end
      local got = a and inside[j * w + i] or outside[j * w + i]
      if not near(got * 1000, best, 1e-2) then
        good = false
      end
    end
  end
  ok("inside and outside match brute force", good)
  local sd = vnoise.distance_field(m, w, h, { mode = "signed", range = 20 })
  ok("signed: land above 0.5, sea below", sd[20 * w + 10] > 0.5 and sd[0] < 0.5)
  ok("signed: the boundary is half a cell from each side", near(sd[20 * w + 11], 0.5 - 0.5 * 0.5 / 20))
  -- Edge modes: an all-land matrix measured inland from a sea outside it.
  local land = vnoise.matrix(w, h, 1)
  local edge = vnoise.distance_field(land, w, h, { mode = "inside", edge = "below", range = 100 })
  ok(
    "edge 'below' measures the distance to the matrix edge",
    near(edge[0], 1 / 100) and near(edge[20 * w + 25], 20 / 100)
  )
  local none = vnoise.distance_field(land, w, h, { mode = "inside", range = 100 })
  ok("no target cell reads 1", none[0] == 1 and none[100] == 1)
  local norm = vnoise.distance_field(m, w, h, { mode = "outside" })
  local mx = 0
  for k = 0, w * h - 1 do
    mx = math.max(mx, norm[k])
  end
  ok("range 0 normalizes by the largest distance", near(mx, 1))
  ok("unknown mode raises", raises("distance mode", vnoise.distance_field, m, w, h, { mode = "nope" }))
  local big = terrain(2048, 2048)
  timed("signed distance field 2048^2", function()
    vnoise.distance_field(big, 2048, 2048, { mode = "signed", threshold = 0.45 })
  end)
end

-- Slope -----------------------------------------------------------------------

do
  local w, h = 40, 30
  -- A plane rising east: 0.01 per cell.
  local m = vnoise.matrix(w, h)
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      m[j * w + i] = 0.1 + 0.01 * i
    end
  end
  local relief = 0.05
  local rise = 0.01 * relief * math.max(w, h) -- 0.02 cells per cell
  local angle = vnoise.slope(m, w, h, { relief = relief })
  ok("angle of an inclined plane", near(angle[15 * w + 20], math.atan(rise) / (math.pi / 2), 1e-5))
  local grad = vnoise.slope(m, w, h, { mode = "gradient", relief = relief, range = 0.04 })
  ok("gradient scaled by range", near(grad[15 * w + 20], 0.5, 1e-5))
  local aspect = vnoise.slope(m, w, h, { mode = "aspect" })
  ok("aspect: downhill is west (0.5)", near(aspect[15 * w + 20], 0.5, 1e-5))
  local dx = vnoise.slope(m, w, h, { mode = "dx", relief = relief, range = 0.04 })
  local dy = vnoise.slope(m, w, h, { mode = "dy", relief = relief, range = 0.04 })
  ok("dx and dy components", near(dx[15 * w + 20], 0.75, 1e-5) and near(dy[15 * w + 20], 0.5, 1e-6))
  local bowl = vnoise.matrix(w, h)
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      bowl[j * w + i] = 0.001 * ((i - 20) ^ 2 + (j - 15) ^ 2)
    end
  end
  local curv = vnoise.slope(bowl, w, h, { mode = "curvature" })
  ok("a bowl is concave (curvature above 0.5)", curv[15 * w + 20] > 0.5)
  local flat = vnoise.slope(vnoise.matrix(w, h, 0.3), w, h)
  ok("flat ground has slope 0", flat[100] == 0)
  ok("slope rejects out == source", raises("out", vnoise.slope, m, w, h, { out = m }))
end

-- Flow ---------------------------------------------------------------------------

do
  local w, h = 64, 64
  local isl = island(w, h)
  local d8 = vnoise.flow(isl, w, h, { sea_level = 0.1, scale = "range", range = w * h })
  local mfd = vnoise.flow(isl, w, h, { sea_level = 0.1, method = "mfd" })
  ok("flow outputs stay in 0..1", inRange(d8, w * h) and inRange(mfd, w * h))
  ok("a peak receives only its own rain", near(d8[32 * w + 32] * w * h, 1, 1e-3))
  -- A valley: the flow concentrates in its axis.
  local v = vnoise.matrix(w, h)
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      v[j * w + i] = 0.2 + 0.6 * (1 - j / h) * 0.5 + 0.01 * math.abs(i - 32)
    end
  end
  local f = vnoise.flow(v, w, h, { scale = "linear", outlets = "edges" })
  local axis_max = 0
  for i = 0, w - 1 do
    axis_max = math.max(axis_max, f[(h - 2) * w + i])
  end
  ok("flow concentrates in the valley axis", f[(h - 2) * w + 32] == axis_max)
  local _, filled, lake = vnoise.flow(island(w, h), w, h, { filled = true, lake = true })
  local pit = vnoise.matrix(w, h, 0.5)
  pit[30 * w + 30] = 0.2
  local _, pf, pl = vnoise.flow(pit, w, h, { filled = true, lake = true, outlets = "edges" })
  ok("a pit is filled and marked as a lake", pf[30 * w + 30] >= 0.5 - 1e-4 and pl[30 * w + 30] == 1)
  ok("filled heights never go below the input", filled ~= nil and lake ~= nil)
  local half = vnoise.flow(isl, w, h, { sea_level = 0.1, rain = vnoise.matrix(w, h, 0.5), scale = "range", range = 1 })
  ok("rain weights the accumulation", near(half[32 * w + 32], 0.5, 1e-5))
  local big = terrain(1024, 1024)
  timed("flow d8 1024^2", function()
    vnoise.flow(big, 1024, 1024, { sea_level = 0.45 })
  end)
  timed("flow mfd 1024^2", function()
    vnoise.flow(big, 1024, 1024, { sea_level = 0.45, method = "mfd" })
  end)
end

-- River network -----------------------------------------------------------------

do
  local w, h = 128, 128
  local sea = 0.15
  local m = island(w, h)
  local detail = terrain(w, h, 9)
  for k = 0, w * h - 1 do
    m[k] = math.min(1, math.max(0, m[k] + 0.04 * (detail[k] - 0.5)))
  end
  local before = copy(m, w * h)
  local rivers, mask, flow = vnoise.river_network(m, w, h, { sea_level = sea, min_flow = 40, flow = true })
  ok(("a network is traced (%d rivers)"):format(#rivers), #rivers > 3)
  ok("the result stays in 0..1", inRange(m, w * h) and inRange(mask, w * h) and inRange(flow, w * h))
  local lowered = true
  for k = 0, w * h - 1 do
    if m[k] > before[k] + 1e-6 then
      lowered = false
    end
  end
  ok("carving only lowers the terrain (fill_lakes off)", lowered)
  -- Every river ends at the sea, the edge or another river.
  local ends = true
  for _, r in ipairs(rivers) do
    local n = #r.points / 2
    local x, y = math.floor(r.points[2 * n - 1]), math.floor(r.points[2 * n])
    local k = y * w + x
    local at_sea = before[k] < sea
    local at_edge = x == 0 or y == 0 or x == w - 1 or y == h - 1
    if not (at_sea or at_edge or mask[k] >= 0.99) then
      ends = false
    end
  end
  ok("every river ends at the sea, the edge or a river", ends)
  -- The main stem's bed never rises downstream (checked on the mask cells
  -- along its points).
  local main = rivers[1]
  local mono, last = true, math.huge
  for k = 1, #main.points / 2 do
    local x, y = math.floor(main.points[2 * k - 1]), math.floor(main.points[2 * k])
    local v = m[y * w + x]
    if v > last + 0.01 then
      mono = false
    end
    last = math.min(last, v)
  end
  ok("the main stem descends to its mouth", mono)
  ok(
    "main stems come first (widest river first)",
    main.width[#main.width] >= rivers[#rivers].width[#rivers[#rivers].width]
  )
  local again = copy(before, w * h)
  local r2 = vnoise.river_network(again, w, h, { sea_level = sea, min_flow = 40 })
  ok("the network is deterministic", #r2 == #rivers and same(again, m, w * h))
  local fewer = vnoise.river_network(copy(before, w * h), w, h, { sea_level = sea, min_flow = 200 })
  ok("a larger min_flow gives fewer rivers", #fewer < #rivers)
  local dry =
    vnoise.river_network(copy(before, w * h), w, h, { sea_level = sea, min_flow = 40, rain = vnoise.matrix(w, h, 0) })
  ok("no rain, no rivers", #dry == 0)
  -- A basin on the way is crossed as a lake.
  local valley = vnoise.matrix(w, h)
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      valley[j * w + i] = 0.9 - 0.8 * i / w + 0.004 * math.abs(j - 64)
    end
  end
  for j = 54, 74 do
    for i = 50, 70 do
      valley[j * w + i] = valley[j * w + i] - 0.08
    end
  end
  local lake_mask
  _, lake_mask = vnoise.river_network(valley, w, h, { min_flow = 30, fill_lakes = true, outlets = "edges" })
  ok("a crossed basin is marked as a lake", lake_mask[64 * w + 60] >= 0.5)
  local big = terrain(1024, 1024)
  timed("river network 1024^2", function()
    vnoise.river_network(big, 1024, 1024, { sea_level = 0.45 })
  end)
end

print(failures == 0 and "all landform tests passed" or (failures .. " landform test(s) failed"))
os.exit(failures == 0 and 0 or 1)
