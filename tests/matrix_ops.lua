-- Matrix operation tests (change: matrix-terrain-ops; specs matrix-features,
-- matrix-rivers, matrix-filters). Run from the repository root after `make`:
-- luajit tests/matrix_ops.lua
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
    if m[k] < 0 or m[k] > 1 then
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

-- A matrix that slopes from 1 at the top row to 0.1 at the bottom, with a
-- gentle ripple so the steepest descent has to choose.
local function slope(w, h)
  local m = vnoise.matrix(w, h)
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      m[j * w + i] = 1 - 0.9 * (j + 0.5) / h + 0.01 * math.sin(i * 0.37)
    end
  end
  return m
end

local W, H = 200, 200
local N = W * H

-- Convention -----------------------------------------------------------------

do
  local m = vnoise.matrix(W, H, 0.5)
  vnoise.stamp(m, W, H, { shape = "cone", height = 5, rx = 40, blend = "add" })
  vnoise.stamp(m, W, H, { shape = "basin", height = 5, rx = 30, cx = 40, cy = 40 })
  vnoise.path_feature(m, W, H, { 10, 10, 190, 190 }, { kind = "ridge", height = 5, width = 30, roughness = 1 })
  vnoise.path_feature(m, W, H, { 10, 190, 190, 10 }, { kind = "valley", height = 5, width = 30 })
  ok("every operation keeps values in 0..1", inRange(m, N))

  local a, b = vnoise.matrix(W, H, 0.2), vnoise.matrix(W, H, 0.2)
  for _, mm in ipairs({ a, b }) do
    vnoise.stamp(mm, W, H, { shape = "crater", rx = 30, roughness = 0.7, seed = 9 })
    vnoise.path_feature(
      mm,
      W,
      H,
      { 20, 50, 100, 120, 180, 60 },
      { kind = "ridge", spurs = 6, roughness = 0.5, seed = 4 }
    )
  end
  ok("operations are deterministic", same(a, b, N))
end

-- Stamps ---------------------------------------------------------------------

do
  local m = vnoise.matrix(W, H, 0.2)
  vnoise.stamp(m, W, H, { shape = "dome", cx = 100.5, cy = 100.5, rx = 20, height = 0.4 })
  ok("dome peak", near(m[100 * W + 100], 0.6, 1e-4))
  ok("cells outside the dome are unchanged", m[100 * W + 130] == m[0] and near(m[0], 0.2))

  local c = vnoise.matrix(W, H)
  vnoise.stamp(c, W, H, { shape = "cone", cx = 100.5, cy = 100.5, rx = 40, height = 0.8, crater = 0.2 })
  ok("volcano crater dips below its rim", c[100 * W + 100] < c[100 * W + 110])

  local mesa = vnoise.matrix(W, H, 0.1)
  vnoise.stamp(
    mesa,
    W,
    H,
    { shape = "mesa", cx = 100, cy = 100, rx = 40, height = 0.7, slope = 0.3, blend = "replace" }
  )
  local flat = true
  for j = 0, H - 1 do
    for i = 0, W - 1 do
      local dx, dy = (i + 0.5 - 100) / 40, (j + 0.5 - 100) / 40
      if math.sqrt(dx * dx + dy * dy) <= 0.7 then
        flat = flat and near(mesa[j * W + i], 0.7, 1e-4)
      end
    end
  end
  ok("mesa top is flat at its height", flat)
  ok("unknown stamp shape raises", raises("pyramid", vnoise.stamp, mesa, W, H, { shape = "pyramid" }))
end

-- Path features -----------------------------------------------------------------

do
  local m = vnoise.matrix(W, H)
  vnoise.path_feature(m, W, H, { 20, 100, 180, 100 }, { kind = "ridge", height = 0.5, width = 40, peakiness = 0 })
  ok("ridge crest height", near(m[100 * W + 100], 0.5, 1e-3))
  ok("ridge ends at its half width", m[125 * W + 100] == 0)
  ok("ridge tapers at the ends", m[100 * W + 25] < m[100 * W + 100])

  local e = vnoise.matrix(W, H, 0.3)
  vnoise.path_feature(
    e,
    W,
    H,
    { 100, 10, 100, 190 },
    { kind = "escarpment", height = 0.3, width = 10, side = 1, taper = 0 }
  )
  -- 20 cells either side (inside `reach` = 4 * width = 40).
  local left, right = e[100 * W + 80], e[100 * W + 120]
  ok("escarpment raises exactly one side", (left > 0.31) ~= (right > 0.31) and (near(left, 0.3) or near(right, 0.3)))

  local v = vnoise.matrix(W, H, 0.6)
  vnoise.path_feature(v, W, H, { 20, 100, 180, 100 }, { kind = "valley", height = 0.3, width = 30 })
  ok("valley carves down", v[100 * W + 100] < 0.6 and near(v[10 * W + 100], 0.6))

  local u = vnoise.matrix(W, H, 0.4)
  local before = copy(u, N)
  vnoise.path_feature(u, W, H, { 20, 20 }, { kind = "ridge" })
  ok("fewer than two points leaves the matrix unchanged", same(u, before, N))
end

-- Rivers ---------------------------------------------------------------------------

local function heightAt(m, x, y)
  return m[math.floor(y) * W + math.floor(x)]
end

do
  local m = slope(W, H)
  local pts, mask = vnoise.river(m, W, H, 100.5, 3.5, { sea_level = 0.2 })
  local n = #pts / 2
  local last_y = pts[#pts]
  local end_h = heightAt(m, pts[#pts - 1], last_y)
  ok("river reaches the sea or the edge", n >= 2 and (end_h < 0.2 + 0.05 or last_y >= H - 2))
  local mono = true
  for k = 2, n do
    mono = mono and heightAt(m, pts[2 * k - 1], pts[2 * k]) <= heightAt(m, pts[2 * k - 3], pts[2 * k - 2]) + 1e-6
  end
  ok("heights along the river never rise", mono)
  local channel = true
  for k = 1, n, 7 do
    channel = channel and mask[math.floor(pts[2 * k]) * W + math.floor(pts[2 * k - 1])] == 1
  end
  ok("channel cells have mask 1", channel)

  -- A small closed pit on the slope.
  local p = slope(W, H)
  for j = 60, 70 do
    for i = 95, 106 do
      p[j * W + i] = p[j * W + i] - 0.05
    end
  end
  local pp = vnoise.river(p, W, H, 100.5, 40.5, { sea_level = 0.2 })
  ok("a river breaches a small pit and continues", #pp >= 4 and pp[#pp] > 120)

  -- A wide closed basin: the river ends in a lake.
  local b = vnoise.matrix(W, H, 0.9)
  for j = 0, H - 1 do
    for i = 0, W - 1 do
      local dx, dy = i - 100, j - 100
      local d = math.sqrt(dx * dx + dy * dy)
      if d < 90 then
        b[j * W + i] = 0.3 + 0.5 * (d / 90) ^ 2
      end
    end
  end
  local _, bm = vnoise.river(b, W, H, 140.5, 100.5, { sea_level = 0, breach_radius = 32 })
  -- The channel ends at the pit (mask 1 there); other basin cells are lake.
  ok("a river trapped in a wide basin ends in a lake", bm[120 * W + 100] == 0.5)
  -- Only cells below the spill level are lake: a window corner (higher than
  -- the lowest border cell of a round basin) is not.
  -- The flood window is centered on the pit (100, 100) with radius 32; its
  -- corner (68, 68) lies above the lowest border cell, so it is not lake.
  ok("the lake stops at the spill level", bm[68 * W + 68] ~= 0.5 and bm[120 * W + 100] == 0.5)

  -- Junction: a second river stops at the first channel.
  local j = slope(W, H)
  local mask2 = vnoise.matrix(W, H)
  vnoise.river(j, W, H, 100.5, 3.5, { sea_level = 0.2 }, mask2)
  local trib = vnoise.river(j, W, H, 130.5, 3.5, { sea_level = 0.2 }, mask2)
  local tx, ty = trib[#trib - 1], trib[#trib]
  ok("a tributary stops at the existing channel", mask2[math.floor(ty) * W + math.floor(tx)] >= 0.75 and ty < H - 2)

  ok("wrapper defaults trace something", #vnoise.river(slope(W, H), W, H, 50.5, 5.5) >= 4)
  local srcs = vnoise.river_sources(slope(W, H), W, H, { count = 10, min_elev = 0.5, min_spacing = 30, seed = 3 })
  local sp_ok = #srcs > 0
  local sm = slope(W, H)
  for a = 1, #srcs do
    sp_ok = sp_ok and heightAt(sm, srcs[a][1], srcs[a][2]) >= 0.5
    for c = a + 1, #srcs do
      local dx, dy = srcs[a][1] - srcs[c][1], srcs[a][2] - srcs[c][2]
      sp_ok = sp_ok and dx * dx + dy * dy >= 900
    end
  end
  ok(("random sources respect elevation and spacing (%d)"):format(#srcs), sp_ok)
  local again = vnoise.river_sources(slope(W, H), W, H, { count = 10, min_elev = 0.5, min_spacing = 30, seed = 3 })
  local seeded = #again == #srcs
  for a = 1, #srcs do
    seeded = seeded and again[a][1] == srcs[a][1] and again[a][2] == srcs[a][2]
  end
  ok("random sources are seeded", seeded)
end

-- Filters ----------------------------------------------------------------------------

do
  local function ridgeMatrix(w, h)
    local s = vnoise.new(5)
    return vnoise.fill_grid(s, "ridge", { w = w, h = h, freq = 1 / 40, octaves = 5, clamp = false })
  end
  local function drainageRatio(m, flow, n)
    local list, mean = {}, 0
    for k = 0, n - 1 do
      list[#list + 1] = k
      mean = mean + m[k]
    end
    table.sort(list, function(a, b)
      return flow[a] > flow[b]
    end)
    local top, count = 0, math.floor(n * 0.05)
    for i = 1, count do
      top = top + m[list[i]]
    end
    return (top / count) / (mean / n)
  end
  local w, h = 128, 128
  local m0 = ridgeMatrix(w, h)
  local up = copy(m0, w * h)
  local plain = copy(m0, w * h)
  local flow0 = vnoise.erode(plain, w, h, { iterations = 0, flow = true })
  local eroded = copy(m0, w * h)
  local t0 = os.clock()
  local flow1 = vnoise.erode(eroded, w, h, { iterations = 100, uplift = up, flow = true })
  print(("  info erosion 128x128, 100 iterations: %.0f ms"):format((os.clock() - t0) * 1000))
  ok(
    "erosion concentrates low ground along the drainage",
    drainageRatio(eroded, flow1, w * h) < drainageRatio(plain, flow0, w * h)
  )
  ok("eroded values stay in 0..1", inRange(eroded, w * h) and inRange(flow1, w * h))

  local big = ridgeMatrix(2048, 2048)
  t0 = os.clock()
  vnoise.erode(big, 2048, 2048, { iterations = 60 })
  print(("  info erosion 2048x2048 (512x512 eroded), 60 iterations: %.0f ms"):format((os.clock() - t0) * 1000))
  ok("a large matrix erodes within range", inRange(big, 2048 * 2048))

  -- Stages on a matrix.
  local g = ridgeMatrix(64, 64)
  local ref = copy(g, 64 * 64)
  vnoise.apply_stages(g, 64, 64, { { "gaussian", 2 } })
  -- Interior reference: the Gaussian of a padded copy through the matrix API equals a manual one.
  local manual = vnoise.matrix(64, 64)
  local taps, sum = {}, 0
  for i = -6, 6 do
    taps[i] = math.exp(-(i * i) / 8)
    sum = sum + taps[i]
  end
  local function at(i, j)
    i = math.min(math.max(i, 0), 63)
    j = math.min(math.max(j, 0), 63)
    return ref[j * 64 + i]
  end
  local worst = 0
  for j = 0, 63 do
    for i = 0, 63 do
      local acc = 0
      for dj = -6, 6 do
        for di = -6, 6 do
          acc = acc + taps[di] * taps[dj] * at(i + di, j + dj)
        end
      end
      manual[j * 64 + i] = math.min(1, math.max(0, acc / (sum * sum)))
      worst = math.max(worst, math.abs(manual[j * 64 + i] - g[j * 64 + i]))
    end
  end
  ok(("stages on a matrix keep the size and clamp the edges (max diff %.2g)"):format(worst), worst < 1e-4)

  -- Resampling.
  local r = ridgeMatrix(32, 32)
  local id = vnoise.resample(r, 32, 32, 32, 32, "bicubic")
  local id_ok = true
  for k = 0, 32 * 32 - 1 do
    id_ok = id_ok and near(id[k], r[k], 1e-6)
  end
  ok("resampling to the same size is the identity", id_ok)
  local step = vnoise.matrix(8, 8)
  for j = 0, 7 do
    for i = 4, 7 do
      step[j * 8 + i] = 1
    end
  end
  local upd = vnoise.resample(step, 8, 8, 32, 32, "bicubic")
  ok("bicubic upsampling does not overshoot", inRange(upd, 32 * 32))
  ok("unknown resample mode raises", raises("lanczos", vnoise.resample, step, 8, 8, 4, 4, "lanczos"))
end

-- Timings at the editor's working resolution ------------------------------------------

do
  local w = 1024
  local m = vnoise.fill_grid(vnoise.new(1), "fbm", { w = w, h = w, freq = 1 / 300, ops = { { "remap", -1, 1 } } })
  local t0 = os.clock()
  vnoise.stamp(m, w, w, { shape = "cone", rx = 120, height = 0.4, roughness = 0.6, crater = 0.15 })
  local t1 = os.clock()
  vnoise.path_feature(
    m,
    w,
    w,
    { 100, 500, 400, 300, 700, 450, 950, 350 },
    { kind = "ridge", width = 160, spurs = 20, roughness = 0.5 }
  )
  local t2 = os.clock()
  vnoise.river(m, w, w, 500.5, 300.5, { sea_level = 0.25 })
  local t3 = os.clock()
  vnoise.erode(m, w, w, { iterations = 60 })
  local t4 = os.clock()
  print(
    ("  info 1024x1024: stamp %.1f ms, ridge %.1f ms, river %.1f ms, erosion (60 it, 512x512) %.0f ms"):format(
      (t1 - t0) * 1000,
      (t2 - t1) * 1000,
      (t3 - t2) * 1000,
      (t4 - t3) * 1000
    )
  )
  ok("1024x1024 result in range", inRange(m, w * w))
end

print(failures == 0 and "all matrix-op tests passed" or (failures .. " failure(s)"))
os.exit(failures == 0 and 0 or 1)
