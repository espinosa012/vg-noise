-- Image-processing tests against the built library (change: image-ops; specs
-- noise-value-ops, noise-domain, noise-image-kernels, noise-pipeline).
-- Run from the repository root after `make`: luajit tests/image_ops.lua
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

local apply = vnoise.apply_ops

-- Builds a w x h float buffer from f(i, j) (0-based).
local function buffer(w, h, f)
  local b = ffi.new("float[?]", w * h)
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      b[j * w + i] = f(i, j)
    end
  end
  return b
end

-- True when every cell of the w x h output satisfies pred(i, j, v).
local function all(b, w, h, pred)
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      if not pred(i, j, b[j * w + i]) then
        return false
      end
    end
  end
  return true
end

-- Extended point operations ---------------------------------------------------

ok("invert", near(apply(0.3, { { "invert" } }), 0.7))
ok("threshold below", apply(0.49, { { "threshold", 0.5 } }) == 0)
ok("threshold at", apply(0.5, { { "threshold", 0.5 } }) == 1)
ok("threshold above", apply(0.8, { { "threshold", 0.5 } }) == 1)
ok("smoothstep low", apply(0.1, { { "smoothstep", 0.2, 0.6 } }) == 0)
ok("smoothstep mid", near(apply(0.4, { { "smoothstep", 0.2, 0.6 } }), 0.5))
ok("smoothstep high", apply(0.9, { { "smoothstep", 0.2, 0.6 } }) == 1)
ok("smoothstep zero width", apply(0.3, { { "smoothstep", 0.3, 0.3 } }) == 1)
ok("gamma", near(apply(0.5, { { "gamma", 2 } }), 0.25))
ok("gamma negative", apply(-0.3, { { "gamma", 2 } }, false) == 0)
ok("quantize 0.1", near(apply(0.1, { { "quantize", 4 } }), 0))
ok("quantize 0.3", near(apply(0.3, { { "quantize", 4 } }), 1 / 3))
ok("quantize 0.74", near(apply(0.74, { { "quantize", 4 } }), 2 / 3))
ok("quantize 1", near(apply(1, { { "quantize", 4 } }), 1))
ok("quantize < 2 levels passes", near(apply(0.37, { { "quantize", 1 } }), 0.37))
ok("explicit clamp", near(apply(0.5, { { "scale", 3 }, { "clamp", 0, 1 }, { "offset", -0.5 } }, false), 0.5))
ok("op constants", vnoise.OP_INVERT == 5 and vnoise.OP_CLAMP == 10)

-- Domain ----------------------------------------------------------------------

local s = vnoise.new(11)
local base_opts = { freq = 0.07, octaves = 4, ox = 0.3, oy = -0.6 }

local function with(t, extra)
  local r = {}
  for k, v in pairs(t) do
    r[k] = v
  end
  for k, v in pairs(extra) do
    r[k] = v
  end
  return r
end

do
  local c0, r0, w, h = 5, -3, 24, 20
  local dom = vnoise.fill_domain(s, "fbm", with(base_opts, { c0 = c0, r0 = r0, w = w, h = h }))
  local grid = vnoise.fill_grid(s, "fbm", {
    w = w,
    h = h,
    freq = 0.07,
    octaves = 4,
    ox = 0.3 + c0 * 0.07,
    oy = -0.6 + r0 * 0.07,
  })
  ok(
    "identity domain matches fill_grid",
    all(dom, w, h, function(i, j, v)
      return near(v, grid[j * w + i])
    end)
  )
end

-- Value of a cell in an unrotated reference fill around the origin.
local REF = 48
local ref = vnoise.fill_domain(s, "fbm", with(base_opts, { c0 = -REF, r0 = -REF, w = 2 * REF, h = 2 * REF }))
local function at(c, r)
  return ref[(r + REF) * 2 * REF + (c + REF)]
end

local function domainBlock(domain, c0, r0, w, h)
  return vnoise.fill_domain(s, "fbm", with(base_opts, { domain = domain, c0 = c0, r0 = r0, w = w, h = h }))
end

do
  local b = domainBlock({ rotate = 90 }, -10, -10, 20, 20)
  ok(
    "quarter turn",
    all(b, 20, 20, function(i, j, v)
      local c, r = i - 10, j - 10
      return near(v, at(r, -c))
    end)
  )
  local sc = domainBlock({ scale = 2 }, -20, -20, 40, 40)
  ok(
    "magnification",
    all(sc, 40, 40, function(i, j, v)
      local c, r = i - 20, j - 20
      if c % 2 ~= 0 or r % 2 ~= 0 then
        return true
      end
      return near(v, at(c / 2, r / 2))
    end)
  )
  local fl = domainBlock({ flip_x = true, pivot = { 10, 0 } }, 0, -5, 20, 10)
  ok(
    "mirror about pivot",
    all(fl, 20, 10, function(i, j, v)
      return near(v, at(20 - i, j - 5))
    end)
  )
  local tr = domainBlock({ translate = { 3, -2 } }, -5, -5, 10, 10)
  ok(
    "translation",
    all(tr, 10, 10, function(i, j, v)
      local c, r = i - 5, j - 5
      return near(v, at(c - 3, r + 2))
    end)
  )
  ok("zero scale raises", not pcall(vnoise.compile_domain, { scale = 0 }))

  local spec = { rotate = 33, scale = { 1.5, 0.7 }, flip_y = true, pivot = { 4, -2 }, translate = { 1, 2 } }
  local by_spec = domainBlock(spec, -6, -6, 12, 12)
  local by_affine = domainBlock({ affine = vnoise.domain_affine(spec) }, -6, -6, 12, 12)
  ok(
    "explicit affine equals the description",
    all(by_spec, 12, 12, function(i, j, v)
      return v == by_affine[j * 12 + i]
    end)
  )
  -- Pixel p shows cell 2p + 5: compose the map with that and sample pixels.
  local m = vnoise.domain_affine(spec)
  local composed = { 2 * m[1], 2 * m[2], 5 * m[1] + 5 * m[2] + m[3], 2 * m[4], 2 * m[5], 5 * m[4] + 5 * m[5] + m[6] }
  local pixels = domainBlock({ affine = composed }, 0, 0, 6, 6)
  local cells = domainBlock(spec, 5, 5, 12, 12)
  ok(
    "composed affine samples every other cell",
    all(pixels, 6, 6, function(i, j, v)
      return near(v, cells[(2 * j) * 12 + 2 * i])
    end)
  )
  ok("affine needs six numbers", not pcall(vnoise.compile_domain, { affine = { 1, 0, 0 } }))

  local dom = { rotate = 37, scale = { 1.5, 0.8 }, pivot = { 7, 3 }, warp = { amp = 6, freq = 0.08, octaves = 2 } }
  local big = domainBlock(dom, 0, 0, 40, 40)
  local small = domainBlock(dom, 17, 9, 20, 20)
  ok(
    "overlapping warped blocks agree",
    all(small, 20, 20, function(i, j, v)
      return near(v, big[(j + 9) * 40 + (i + 17)])
    end)
  )
  local nowarp = domainBlock({ rotate = 37 }, 0, 0, 10, 10)
  local zero = domainBlock({ rotate = 37, warp = { amp = 0 } }, 0, 0, 10, 10)
  local warped = domainBlock({ rotate = 37, warp = { amp = 6 } }, 0, 0, 10, 10)
  ok(
    "zero warp is no warp",
    all(zero, 10, 10, function(i, j, v)
      return v == nowarp[j * 10 + i]
    end)
  )
  ok("warp changes values", not all(warped, 10, 10, function(i, j, v)
    return near(v, nowarp[j * 10 + i])
  end))
end

-- Kernels ---------------------------------------------------------------------

do
  local src = buffer(10, 8, function(i, j)
    return i * 0.1 + j
  end)
  local dst = ffi.new("float[?]", 6 * 4)
  local k5 = ffi.new("float[25]")
  k5[12] = 1
  lib.vnoise_convolve(src, 10, 8, dst, k5, 2)
  ok(
    "valid output size and identity kernel",
    all(dst, 6, 4, function(i, j, v)
      return near(v, (i + 2) * 0.1 + (j + 2))
    end)
  )

  local const = buffer(12, 12, function()
    return 0.37
  end)
  local function stageOut(stages, src_buf, sw, sh)
    local p = vnoise.compile_pipeline({ stages = stages })
    local st = p.stages[1]
    local out = ffi.new("float[?]", (sw - 2 * st.radius) * (sh - 2 * st.radius))
    st.run(src_buf, sw, sh, out)
    return out, sw - 2 * st.radius, sh - 2 * st.radius
  end
  local bo, bw, bh = stageOut({ { "blur", 2 } }, const, 12, 12)
  ok(
    "box blur keeps constants",
    all(bo, bw, bh, function(_, _, v)
      return near(v, 0.37, 1e-6)
    end)
  )
  local go, gw, gh = stageOut({ { "gaussian", 1 } }, const, 12, 12)
  ok("gaussian keeps constants", gw == 6 and all(go, gw, gh, function(_, _, v)
    return near(v, 0.37, 1e-6)
  end))
  local so, sw2, sh2 = stageOut({ { "sharpen", 0.7 } }, const, 12, 12)
  ok(
    "sharpen keeps constants",
    all(so, sw2, sh2, function(_, _, v)
      return near(v, 0.37)
    end)
  )
  local lo, lw, lh = stageOut({ { "laplacian", 1 } }, const, 12, 12)
  ok(
    "laplacian of a constant is 0",
    all(lo, lw, lh, function(_, _, v)
      return near(v, 0)
    end)
  )
  local co, cw, ch = stageOut({ { "convolve", kernel = { { 0, 0, 0 }, { 0, 2, 0 }, { 0, 0, 0 } } } }, const, 12, 12)
  ok("nested convolve kernel", cw == 10 and all(co, cw, ch, function(_, _, v)
    return near(v, 0.74)
  end))
  ok("even kernel raises", not pcall(vnoise.compile_pipeline, { stages = { { "convolve", kernel = { 1, 0, 0, 1 } } } }))

  local step = buffer(10, 6, function(i)
    return i < 5 and 0 or 1
  end)
  local sob = ffi.new("float[?]", 8 * 4)
  lib.vnoise_sobel(step, 10, 6, sob, vnoise.SOBEL_MAG, 1)
  -- Output column i is input column i + 1; columns 4 and 5 straddle the step.
  ok(
    "sobel step edge",
    all(sob, 8, 4, function(i, _, v)
      local c = i + 1
      return near(v, (c == 4 or c == 5) and 1 or 0)
    end)
  )
  lib.vnoise_sobel(step, 10, 6, sob, vnoise.SOBEL_Y, 1)
  ok(
    "sobel y of a vertical edge is 0",
    all(sob, 8, 4, function(_, _, v)
      return near(v, 0)
    end)
  )

  -- Morphology
  local point = buffer(9, 9, function(i, j)
    return (i == 4 and j == 4) and 1 or 0
  end)
  local dil = ffi.new("float[?]", 7 * 7)
  lib.vnoise_morph(point, 9, 9, dil, vnoise.MORPH_DILATE, 1, vnoise.SHAPE_SQUARE)
  ok(
    "dilate a point",
    all(dil, 7, 7, function(i, j, v)
      local inside = math.abs(i + 1 - 4) <= 1 and math.abs(j + 1 - 4) <= 1
      return v == (inside and 1 or 0)
    end)
  )
  local disc = ffi.new("float[?]", 5 * 5)
  lib.vnoise_morph(point, 9, 9, disc, vnoise.MORPH_DILATE, 2, vnoise.SHAPE_DISC)
  ok(
    "disc element",
    all(disc, 5, 5, function(i, j, v)
      local dx, dy = i + 2 - 4, j + 2 - 4
      return v == ((dx * dx + dy * dy <= 4) and 1 or 0)
    end)
  )
  ok("morph radius", lib.vnoise_morph_radius(vnoise.MORPH_OPEN, 3) == 6 and lib.vnoise_morph_radius(0, 3) == 3)

  -- 20 x 20: filled square at 4..9, speck at (15, 15).
  local shapes = buffer(20, 20, function(i, j)
    if i >= 4 and i <= 9 and j >= 4 and j <= 9 then
      return 1
    end
    return (i == 15 and j == 15) and 1 or 0
  end)
  local opened = ffi.new("float[?]", 16 * 16)
  lib.vnoise_morph(shapes, 20, 20, opened, vnoise.MORPH_OPEN, 1, vnoise.SHAPE_SQUARE)
  ok(
    "opening removes specks, keeps the square",
    all(opened, 16, 16, function(i, j, v)
      local c, r = i + 2, j + 2
      local in_square = c >= 4 and c <= 9 and r >= 4 and r <= 9
      return v == (in_square and 1 or 0)
    end)
  )
  local tophat = ffi.new("float[?]", 16 * 16)
  lib.vnoise_morph(shapes, 20, 20, tophat, vnoise.MORPH_TOPHAT, 1, vnoise.SHAPE_SQUARE)
  ok(
    "top-hat keeps only the speck",
    all(tophat, 16, 16, function(i, j, v)
      return v == ((i + 2 == 15 and j + 2 == 15) and 1 or 0)
    end)
  )

  local holed = buffer(12, 12, function(i, j)
    if i == 6 and j == 6 then
      return 0
    end
    return (i >= 3 and i <= 9 and j >= 3 and j <= 9) and 1 or 0
  end)
  local closed = ffi.new("float[?]", 8 * 8)
  lib.vnoise_morph(holed, 12, 12, closed, vnoise.MORPH_CLOSE, 1, vnoise.SHAPE_SQUARE)
  ok("closing fills holes", closed[(6 - 2) * 8 + (6 - 2)] == 1)
  local blackhat = ffi.new("float[?]", 8 * 8)
  lib.vnoise_morph(holed, 12, 12, blackhat, vnoise.MORPH_BLACKHAT, 1, vnoise.SHAPE_SQUARE)
  ok(
    "black-hat marks the hole",
    all(blackhat, 8, 8, function(i, j, v)
      return v == ((i + 2 == 6 and j + 2 == 6) and 1 or 0)
    end)
  )
  local grad = ffi.new("float[?]", 18 * 18)
  lib.vnoise_morph(shapes, 20, 20, grad, vnoise.MORPH_GRADIENT, 1, vnoise.SHAPE_SQUARE)
  ok("gradient: inside 0, border 1", grad[(6 - 1) * 18 + (6 - 1)] == 0 and grad[(4 - 1) * 18 + (6 - 1)] == 1)

  -- Median and distance
  local salt = buffer(9, 9, function(i, j)
    return (i == 4 and j == 4) and 1 or 0.2
  end)
  local med = ffi.new("float[?]", 7 * 7)
  lib.vnoise_median(salt, 9, 9, med, 1)
  ok(
    "median removes salt",
    all(med, 7, 7, function(_, _, v)
      return near(v, 0.2)
    end)
  )
  local seed = buffer(21, 21, function(i, j)
    return (i == 10 and j == 10) and 1 or 0
  end)
  local dist = ffi.new("float[?]", 13 * 13)
  lib.vnoise_distance(seed, 21, 21, dist, 4, 0.5)
  local function d(c, r)
    return dist[(r - 4) * 13 + (c - 4)]
  end
  ok("distance 0 on the cell", d(10, 10) == 0)
  ok("distance 2 away is 0.5", near(d(12, 10), 0.5))
  ok("distance beyond r is 1", d(15, 10) == 1 and d(14, 14) == 1)
end

-- Pipeline --------------------------------------------------------------------

do
  local p = vnoise.compile_pipeline({ stages = { { "gaussian", 1 }, { "threshold", 0.5 }, { "open", 2 } } })
  ok("pipeline radius", p.radius == 7)
  ok("compiled pipeline reused", vnoise.compile_pipeline(p) == p)
  ok("unknown stage raises", not pcall(vnoise.compile_pipeline, { stages = { { "sepia" } } }))
  ok("radius limit", not pcall(vnoise.compile_pipeline, { stages = { { "median", 8 } } }))
  ok("non-integer radius raises", not pcall(vnoise.compile_pipeline, { stages = { { "erode", 1.5 } } }))
  ok("unknown shape raises", not pcall(vnoise.compile_pipeline, { stages = { { "erode", 1, shape = "star" } } }))
  ok("unknown mask raises", not pcall(vnoise.compile_pipeline, { stages = { { "invert", mask = { "blob" } } } }))

  local spec = {
    domain = { rotate = 25, pivot = { 32, 32 }, warp = { amp = 4, freq = 0.05, octaves = 2 } },
    stages = {
      { "remap", -1, 1 },
      { "gaussian", 1 },
      { "threshold", 0.5 },
      { "open", 1, shape = "disc" },
      { "invert", mask = { "ellipse", 30, 34, 18, 12, feather = 5 } },
      { "sobel", mask = { "polygon", { 0, 0, 40, 5, 20, 60 } } },
    },
  }
  local opts = { freq = 0.05, octaves = 5, ox = 1.5, oy = 2.5 }
  local whole = vnoise.fill_pipeline(s, "fbm", spec, with(opts, { w = 64, h = 64 }))
  local same = true
  for _, q in ipairs({ { 0, 0 }, { 32, 0 }, { 0, 32 }, { 32, 32 } }) do
    local part = vnoise.fill_pipeline(s, "fbm", spec, with(opts, { c0 = q[1], r0 = q[2], w = 32, h = 32 }))
    for j = 0, 31 do
      for i = 0, 31 do
        if not near(part[j * 32 + i], whole[(q[2] + j) * 64 + q[1] + i]) then
          same = false
        end
      end
    end
  end
  ok("tiling equals the whole", same)

  local chain = { { "remap", -1, 1 }, { "contrast", 1.5, 0.5 }, { "invert" } }
  local piped = vnoise.fill_pipeline(s, "ridge", { stages = chain }, with(opts, { w = 16, h = 16 }))
  local grid = vnoise.fill_grid(s, "ridge", with(opts, { w = 16, h = 16, ops = chain }))
  ok(
    "point-only pipeline equals a chain",
    all(piped, 16, 16, function(i, j, v)
      return near(v, grid[j * 16 + i])
    end)
  )
  local unclamped =
    vnoise.fill_pipeline(s, "fbm", { stages = { { "scale", 5 } } }, with(opts, { w = 16, h = 16, clamp = false }))
  local beyond = false
  for i = 0, 255 do
    beyond = beyond or unclamped[i] > 1 or unclamped[i] < 0
  end
  ok("clamp = false keeps range", beyond)
end

-- Masks: run stages over a constant 0.2 image (scale 0 + offset 0.2).
local function masked(stage)
  local spec = { stages = { { "scale", 0 }, { "offset", 0.2 }, stage } }
  return vnoise.fill_pipeline(s, "fbm", spec, { w = 24, h = 24 })
end

do
  local r = masked({ "invert", mask = { "rect", 2, 2, 5, 5 } })
  ok(
    "rectangle mask",
    all(r, 24, 24, function(i, j, v)
      local inside = i >= 2 and i <= 5 and j >= 2 and j <= 5
      return near(v, inside and 0.8 or 0.2)
    end)
  )
  local inv = masked({ "invert", mask = { "rect", 2, 2, 5, 5, invert = true } })
  ok(
    "inverted mask",
    all(inv, 24, 24, function(i, j, v)
      local inside = i >= 2 and i <= 5 and j >= 2 and j <= 5
      return near(v, inside and 0.2 or 0.8)
    end)
  )
  local f = masked({ "invert", mask = { "rect", 0, 0, 20, 20, feather = 4 } })
  ok("feather half way", near(f[10 * 24 + 2], 0.5))
  ok("feather full inside", near(f[10 * 24 + 10], 0.8))
  local e = masked({ "invert", mask = { "ellipse", 12, 12, 6, 3 } })
  ok("ellipse inside/outside", near(e[12 * 24 + 17], 0.8) and near(e[12 * 24 + 19], 0.2) and near(e[16 * 24 + 12], 0.2))
  local pg = masked({ "invert", mask = { "polygon", { 0, 0, 20, 0, 0, 20 } } })
  ok("polygon inside/outside", near(pg[2 * 24 + 2], 0.8) and near(pg[18 * 24 + 18], 0.2))

  local ramp = { stages = { { "remap", -1, 1 }, { "scale", 0 }, { "offset", 0.5 } } }
  local mid = vnoise.fill_pipeline(s, "fbm", ramp, { w = 4, h = 4 })
  ok("range base value", near(mid[0], 0.5))
  local spec = { stages = { { "scale", 0 }, { "offset", 0.5 }, { "scale", 0, mask = { "range", 0.4, 0.6 } } } }
  local zeroed = vnoise.fill_pipeline(s, "fbm", spec, { w = 4, h = 4 })
  ok("range mask hits", near(zeroed[0], 0))
  spec.stages[3].mask = { "range", 0.6, 0.9 }
  local kept = vnoise.fill_pipeline(s, "fbm", vnoise.compile_pipeline(spec), { w = 4, h = 4 })
  ok("range mask misses", near(kept[0], 0.5))

  -- A masked kernel stage blends with its own input at the same cell.
  local spec2 = { stages = { { "remap", -1, 1 }, { "blur", 2, mask = { "rect", 0, 0, 7, 23 } } } }
  local blurred = vnoise.fill_pipeline(s, "fbm", spec2, { w = 24, h = 24, freq = 0.2 })
  local raw = vnoise.fill_pipeline(s, "fbm", { stages = { { "remap", -1, 1 } } }, { w = 24, h = 24, freq = 0.2 })
  local outside_same, inside_diff = true, false
  for j = 0, 23 do
    for i = 0, 23 do
      local a, b = blurred[j * 24 + i], raw[j * 24 + i]
      if i > 7 and not near(a, b) then
        outside_same = false
      elseif i <= 7 and not near(a, b) then
        inside_diff = true
      end
    end
  end
  ok("masked kernel only acts inside", outside_same and inside_diff)
end

-- Global statistics -----------------------------------------------------------

do
  local values = {}
  for i = 1, 200 do
    values[i] = (i <= 100 and 0.2 or 0.8) + ((i * 37) % 11 - 5) * 0.005
  end
  local hist = vnoise.histogram(values, #values, 64)
  local count = 0
  for i = 1, 64 do
    count = count + hist[i]
  end
  ok("histogram counts every value", count == 200)
  local t = vnoise.otsu(hist)
  ok("otsu between the modes", t > 0.25 and t < 0.75)

  local half = {}
  for i = 1, 500 do
    half[i] = (i - 1) / 1000
  end
  local lut = vnoise.equalize_lut(vnoise.histogram(half, #half, 128), 65)
  local mono = true
  for i = 2, #lut do
    mono = mono and lut[i] >= lut[i - 1]
  end
  ok("equalize lut non-decreasing", mono)
  ok("equalize lut starts near 0", lut[1] < 0.02)
  ok("equalize lut reaches 1 at 0.5", near(lut[33], 1, 1e-6) and near(lut[65], 1, 1e-6))
  ok("equalize lut as a stage", near(apply(0.25, { { "lut", lut } }), 0.5, 0.02))

  local buf = ffi.new("float[4]", { 0, 0.5, 0.99, 1.5 })
  local h4 = vnoise.histogram(buf, 4, 2)
  ok("histogram of a cdata buffer", h4[1] == 1 and h4[2] == 3)
end

-- Existing fills are unchanged ------------------------------------------------

do
  local a = vnoise.fill_grid(s, "turb", { w = 8, h = 8, freq = 0.1 })
  local b = vnoise.fill_grid(vnoise.new(11), "turb", { w = 8, h = 8, freq = 0.1 })
  ok(
    "fill_grid deterministic",
    all(a, 8, 8, function(i, j, v)
      return v == b[j * 8 + i]
    end)
  )
end

print(failures == 0 and "all image-op tests passed" or (failures .. " failure(s)"))
os.exit(failures == 0 and 0 or 1)
