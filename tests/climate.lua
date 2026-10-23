-- Climate operation tests (change: climate-matrix-ops; specs matrix-climate,
-- matrix-analysis). Run from the repository root after `make`:
-- luajit tests/climate.lua
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

local function timed(label, fn)
  local t = os.clock()
  local r = { fn() }
  print(("        %s: %.1f ms"):format(label, (os.clock() - t) * 1000))
  return unpack(r)
end

-- Rolling noise in 0..1.
local function terrain(w, h, seed)
  return vnoise.fill_grid(vnoise.new(seed or 5), "fbm", {
    w = w,
    h = h,
    freq = 1 / 40,
    octaves = 5,
    ops = { { "remap", -0.7, 0.7 } },
  })
end

-- Large blur -----------------------------------------------------------------------

do
  local w, h = 96, 80
  local n = w * h
  local m = terrain(w, h)
  for _, sigma in ipairs({ 0.6, 1.5, 3, 6 }) do
    local fast = vnoise.blur_large(m, w, h, { sigma = sigma })
    local exact = copy(m, n)
    vnoise.apply_stages(exact, w, h, { { "gaussian", sigma } })
    local worst, sq = 0, 0
    for k = 0, n - 1 do
      local d = math.abs(fast[k] - exact[k])
      worst, sq = math.max(worst, d), sq + d * d
    end
    local rms = math.sqrt(sq / n)
    ok(
      ("sigma %.1f matches the exact gaussian (max error %.4f, rms %.4f)"):format(sigma, worst, rms),
      worst < 0.015 and rms < 0.004
    )
  end
  local c = vnoise.blur_large(vnoise.matrix(w, h, 0.37), w, h, { sigma = 40 })
  local const = true
  for k = 0, n - 1 do
    if not near(c[k], 0.37, 1e-5) then
      const = false
    end
  end
  ok("a constant matrix stays constant", const)
  -- An impulse far from the edges keeps its mass, its center and a variance
  -- of exactly sigma^2 per axis.
  local bump = vnoise.matrix(w, h)
  bump[40 * w + 48] = 1
  local spread = vnoise.blur_large(bump, w, h, { sigma = 4 })
  local total, cx, cy = 0, 0, 0
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      local v = spread[j * w + i]
      total, cx, cy = total + v, cx + v * i, cy + v * j
    end
  end
  ok("an interior impulse keeps its mass", near(total, 1, 1e-4))
  local var = 0
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      var = var + spread[j * w + i] * (i - 48) ^ 2
    end
  end
  ok(("its variance is sigma^2 per axis (%.4f)"):format(var), near(var, 16, 1e-3))
  ok("the impulse stays centered", near(cx / total, 48, 1e-4) and near(cy / total, 40, 1e-4))
  local huge = vnoise.blur_large(m, w, h, { sigma = 1024 })
  local lo, hi = 1, 0
  for k = 0, n - 1 do
    lo, hi = math.min(lo, huge[k]), math.max(hi, huge[k])
  end
  ok(("sigma far above the matrix flattens it (spread %.5f)"):format(hi - lo), hi - lo < 0.02 and inRange(huge, n))
  ok("sigma 0 copies", same(vnoise.blur_large(m, w, h, { sigma = 0 }), m, n))
  local inplace = copy(m, n)
  vnoise.blur_large(inplace, w, h, { sigma = 5, out = inplace })
  ok("in place equals a separate output", same(inplace, vnoise.blur_large(m, w, h, { sigma = 5 }), n))
  local function errorOf(passes)
    local exact = copy(m, n)
    vnoise.apply_stages(exact, w, h, { { "gaussian", 6 } })
    local fast, sq = vnoise.blur_large(m, w, h, { sigma = 6, passes = passes }), 0
    for k = 0, n - 1 do
      sq = sq + (fast[k] - exact[k]) ^ 2
    end
    return sq
  end
  ok("more passes are closer to the gaussian", errorOf(5) < errorOf(3) and errorOf(3) < errorOf(1))
  ok("negative sigma raises", raises("sigma", vnoise.blur_large, m, w, h, { sigma = -1 }))
  ok("passes outside 1..8 raise", raises("passes", vnoise.blur_large, m, w, h, { sigma = 1, passes = 9 }))
  local big = terrain(1024, 1024)
  timed("blur_large 1024^2 sigma 4", function()
    vnoise.blur_large(big, 1024, 1024, { sigma = 4 })
  end)
  timed("blur_large 1024^2 sigma 512", function()
    vnoise.blur_large(big, 1024, 1024, { sigma = 512 })
  end)
end

-- Wetness index -------------------------------------------------------------------

do
  local w, h = 64, 64
  -- A valley draining south, its axis at column 32.
  local v = vnoise.matrix(w, h)
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      v[j * w + i] = 0.2 + 0.3 * (1 - j / h) + 0.01 * math.abs(i - 32)
    end
  end
  local flow0, f0, l0 = vnoise.flow(v, w, h, { method = "mfd", filled = true, lake = true })
  local flow1, f1, l1, twi = vnoise.flow(v, w, h, { method = "mfd", filled = true, lake = true, twi = true })
  ok(
    "twi leaves the other outputs unchanged",
    same(flow0, flow1, w * h) and same(f0, f1, w * h) and same(l0, l1, w * h)
  )
  ok("twi stays in 0..1", inRange(twi, w * h))
  local axis, side = twi[50 * w + 32], twi[50 * w + 8]
  ok(("twi is higher in the valley axis than on its sides (%.3f > %.3f)"):format(axis, side), axis > side)
  ok("twi grows downstream along the valley axis", twi[(h - 4) * w + 32] > twi[4 * w + 32])
  -- A ridge: a crest at column 32 between two slopes.
  local r = vnoise.matrix(w, h)
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      r[j * w + i] = 0.8 - 0.01 * math.abs(i - 32)
    end
  end
  local _, _, _, rt = vnoise.flow(r, w, h, { twi = true, outlets = "edges" })
  ok("twi is lower on the crest than at the foot", rt[32 * w + 32] < rt[32 * w + 2])
  -- Flat ground: the slope is epsilon, so a larger epsilon lowers the index.
  local flat = vnoise.matrix(w, h, 0.4)
  local _, _, _, ft = vnoise.flow(flat, w, h, { twi = true, twi_range = 20 })
  local _, _, _, ft2 = vnoise.flow(flat, w, h, { twi = true, twi_range = 20, epsilon = 0.1 })
  ok("flat cells use epsilon (finite, lower for a larger one)", ft[100] > ft2[100] and inRange(ft, w * h))
  -- twi_range: ln(A / tan) / range, checked on a plane with one cell of rain.
  local plane = vnoise.matrix(w, h)
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      plane[j * w + i] = 0.1 + 0.005 * i
    end
  end
  local _, _, _, pt = vnoise.flow(plane, w, h, { twi = true, twi_range = 10, outlets = "edges" })
  -- D8 on a plane rising east: column c < 63 drains the 63 - c cells east of
  -- it (the edge column is an outlet and keeps its own rain).
  local tanb = 0.005 * 0.05 * 64
  ok("twi_range scales ln(A / tan(beta))", near(pt[30 * w + 60], math.log(3 / tanb) / 10, 1e-4))
  local _, _, _, ps = vnoise.flow(plane, w, h, { twi = true, outlets = "edges" })
  local lo, hi = 1, 0
  for k = 0, w * h - 1 do
    lo, hi = math.min(lo, ps[k]), math.max(hi, ps[k])
  end
  ok("twi_range 0 stretches the index from 0 to 1", lo == 0 and near(hi, 1, 1e-6))
  ok("epsilon must be positive", raises("epsilon", vnoise.flow, v, w, h, { twi = true, epsilon = 0 }))
end

-- Moisture ---------------------------------------------------------------------------

do
  local w, h = 128, 12
  local n = w * h
  local sea = 0.2
  -- Sea on the first 16 columns, land at 0.3 beyond, wind toward +x.
  local function strip(ridge)
    local m = vnoise.matrix(w, h)
    for j = 0, h - 1 do
      for i = 0, w - 1 do
        local v = i < 16 and 0.1 or 0.3
        if ridge and i >= 16 then
          v = v + 0.3 * math.exp(-((i - 64) / 6) ^ 2)
        end
        m[j * w + i] = v
      end
    end
    return m
  end
  local east = vnoise.matrix(w, h, 0)
  local spec = { sea_level = sea, direction = east, range = 0.05, moisture = true, fetch = true, fetch_range = 100 }
  local flatP, flatQ, flatF = vnoise.moisture(strip(false), w, h, spec)
  local ridgeP, ridgeQ = vnoise.moisture(strip(true), w, h, spec)
  ok("outputs stay in 0..1", inRange(flatP, n) and inRange(flatQ, n) and inRange(flatF, n) and inRange(ridgeP, n))
  local row = 6 * w
  ok("no rain over the sea", flatP[row + 8] == 0)
  ok("the air leaves the sea moist", flatQ[row + 15] > 0.5)
  ok("moisture decreases inland over flat ground", flatQ[row + 100] < flatQ[row + 20])
  ok(
    ("the windward slope is wetter than flat ground (%.3f > %.3f)"):format(ridgeP[row + 58], flatP[row + 58]),
    ridgeP[row + 58] > flatP[row + 58] * 2
  )
  ok(
    ("the lee is drier than flat ground (%.4f < %.4f)"):format(ridgeP[row + 76], flatP[row + 76]),
    ridgeP[row + 76] < flatP[row + 76]
  )
  ok("the ridge wrings the air out", ridgeQ[row + 80] < flatQ[row + 80])
  ok("fetch is 0 over the source", flatF[row + 10] == 0)
  ok("fetch counts the cells over land", near(flatF[row + 16], 1 / 100) and near(flatF[row + 40], 25 / 100))
  -- Sea only east of the land with the wind toward +x: nothing reaches the land.
  local m = vnoise.matrix(w, h, 0.3)
  for j = 0, h - 1 do
    for i = 100, w - 1 do
      m[j * w + i] = 0.1
    end
  end
  local dryP, _, dryF = vnoise.moisture(m, w, h, { sea_level = sea, direction = east, fetch = true })
  local rained = false
  for j = 0, h - 1 do
    for i = 0, 99 do
      if dryP[j * w + i] ~= 0 then
        rained = true
      end
    end
  end
  ok("no rain where no source lies upwind", not rained)
  ok("fetch is 1 where no source lies upwind", dryF[0] == 1 and dryF[50] == 1)
  local wetP = vnoise.moisture(m, w, h, { sea_level = sea, direction = east, inflow = 0.5 })
  ok("inflow brings moisture from outside", wetP[6 * w + 10] > 0)
  -- A source matrix replaces the sea.
  local lakeSrc = vnoise.matrix(w, h)
  for j = 0, h - 1 do
    lakeSrc[j * w + 40] = 1
  end
  local srcP = vnoise.moisture(vnoise.matrix(w, h, 0.5), w, h, { sea_level = sea, direction = east, source = lakeSrc })
  ok("a source matrix feeds the cells downwind", srcP[6 * w + 39] == 0 and srcP[6 * w + 50] > 0)
  -- A uniform wind settles in one cycle, in any direction.
  local t = terrain(96, 64)
  local diag = vnoise.matrix(96, 64, 0.125 + 0.03)
  local one = vnoise.moisture(t, 96, 64, { sea_level = 0.45, direction = diag, iterations = 1, range = 0.02 })
  local many = vnoise.moisture(t, 96, 64, { sea_level = 0.45, direction = diag, iterations = 6, range = 0.02 })
  ok("a uniform diagonal wind is exact after one cycle", same(one, many, 96 * 64))
  local again = vnoise.moisture(t, 96, 64, { sea_level = 0.45, direction = diag, iterations = 6, range = 0.02 })
  ok("moisture is deterministic", same(many, again, 96 * 64))
end

-- Latitude bands ----------------------------------------------------------------------

do
  local w, h = 120, 60
  -- Low land everywhere except a sea strip in the middle columns.
  local m = vnoise.matrix(w, h, 0.21)
  for j = 0, h - 1 do
    for i = 55, 64 do
      m[j * w + i] = 0.1
    end
  end
  local spec = { sea_level = 0.2, fetch = true }
  local p, _, f = vnoise.moisture(m, w, h, spec)
  local function west(j)
    return p[j * w + 40]
  end
  local function eastOf(j)
    return p[j * w + 80]
  end
  -- Default bands: westerlies between 1/6 and 1/3 and between 2/3 and 5/6,
  -- trades between 1/3 and 2/3, polar easterlies beyond.
  ok("trade winds (equator) carry moisture west", west(30) > 0 and eastOf(30) == 0)
  ok("westerlies carry moisture east", eastOf(15) > 0 and west(15) == 0)
  ok("the other hemisphere's westerlies too", eastOf(45) > 0 and west(45) == 0)
  ok("polar easterlies carry moisture west", west(3) > 0 and eastOf(3) == 0 and west(57) > 0)
  ok("fetch follows the band winds", f[30 * w + 54] < f[30 * w + 20] and f[15 * w + 66] < f[15 * w + 100])
  -- Custom bands: everything between the edges is a trade wind.
  local tp = vnoise.moisture(m, w, h, { sea_level = 0.2, bands = { 0, 0, 0.5, 1, 1 } })
  ok("custom bands move the belts", tp[15 * w + 40] > 0 and tp[15 * w + 80] == 0)
  -- Tilt: trades turn toward the equator (row 30): moisture from a source in
  -- rows 20..23 drifts to larger rows as it travels west.
  local land = vnoise.matrix(w, h, 0.5)
  local src = vnoise.matrix(w, h)
  for j = 20, 23 do
    src[j * w + 100] = 1
  end
  local function wettestRow(tilt, col)
    local p = vnoise.moisture(land, w, h, { sea_level = 0.2, source = src, tilt = tilt, bands = { 0, 0, 0.5, 1, 1 } })
    local best, row = -1, -1
    for j = 0, h - 1 do
      if p[j * w + col] > best then
        best, row = p[j * w + col], j
      end
    end
    return row
  end
  local straight, tilted = wettestRow(0, 80), wettestRow(30, 80)
  ok(("untilted trades blow straight (row %d)"):format(straight), straight >= 20 and straight <= 23)
  ok(("tilted trades drift toward the equator (row %d)"):format(tilted), tilted > 23 and tilted <= 31)
  ok(
    "bands must be 5 non-decreasing fractions",
    raises("bands", vnoise.moisture, m, w, h, { bands = { 0.5, 0.2, 0.5, 0.6, 0.7 } })
  )
  ok("bands must have 5 entries", raises("bands", vnoise.moisture, m, w, h, { bands = { 0.5 } }))
  local big = terrain(1024, 1024)
  timed("moisture 1024^2 (bands, 4 cycles, all outputs)", function()
    vnoise.moisture(big, 1024, 1024, { sea_level = 0.45, moisture = true, fetch = true })
  end)
  timed("flow + twi 1024^2 (mfd)", function()
    vnoise.flow(big, 1024, 1024, { sea_level = 0.45, method = "mfd", twi = true })
  end)
end

print(failures == 0 and "all climate tests passed" or (failures .. " climate test(s) failed"))
os.exit(failures == 0 and 0 or 1)
