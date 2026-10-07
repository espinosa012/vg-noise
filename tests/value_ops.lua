-- Value-op chain tests against the built library (spec: noise-value-ops).
-- Run from the repository root after `make`: luajit tests/value_ops.lua
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

local function near(a, b)
  return math.abs(a - b) < 1e-5
end

local apply = vnoise.apply_ops

-- Op set
ok("scale", near(apply(0.3, { { "scale", 2 } }), 0.6))
ok("offset", near(apply(0.3, { { "offset", -0.25 } }), 0.05))
ok("contrast above pivot", near(apply(0.75, { { "contrast", 2, 0.5 } }), 1.0))
ok("contrast at pivot", near(apply(0.5, { { "contrast", 2, 0.5 } }), 0.5))
ok("remap", near(apply(0, { { "remap", -1, 1 } }), 0.5))
ok("remap zero range", apply(0.3, { { "remap", 1, 1 } }, false) == 0)
ok("unknown id passes through", near(apply(0.3, { { 999, 1, 2 } }, false), 0.3))
ok("ids accepted", near(apply(0.3, { { vnoise.OP_SCALE, 2 } }), 0.6))

-- Ordered chain, single final clamp
ok("order a", near(apply(0.4, { { "scale", 2 }, { "offset", -0.5 } }, false), 0.3))
ok("order b", near(apply(0.4, { { "offset", -0.5 }, { "scale", 2 } }, false), -0.2))
ok("no intermediate clamp", near(apply(0.8, { { "scale", 2 }, { "offset", -0.5 } }), 1.0))
ok("unclamped output", near(apply(0.5, { { "scale", 3 } }, false), 1.5))
ok("empty chain clamps", apply(1.7, {}) == 1)
ok("empty chain unclamped", near(apply(1.7, {}, false), 1.7))

-- Unknown op name
local good, err = pcall(vnoise.compile_ops, { { "blur", 1 } })
ok("unknown name raises", not good and tostring(err):find("blur") ~= nil)

-- Compiled chains are reusable
local chain = vnoise.compile_ops({ { "scale", 2 } })
ok("compiled chain reused", vnoise.compile_ops(chain) == chain and near(apply(0.2, chain), 0.4))

-- Buffer vs per-value application
local s = vnoise.new(7)
local w, h = 32, 32
local list = { { "remap", -1, 1 }, { "contrast", 1.7, 0.4 }, { "offset", 0.05 } }
local raw = vnoise.fill_grid(s, "fbm", { w = w, h = h, freq = 0.07 })
local mapped = vnoise.fill_grid(s, "fbm", { w = w, h = h, freq = 0.07, ops = list })
local same = true
for i = 0, w * h - 1 do
  if mapped[i] ~= apply(raw[i], list) then
    same = false
    break
  end
end
ok("map buffer equals per-value", same)

local unclamped = vnoise.fill_grid(s, "fbm", { w = w, h = h, freq = 0.07, ops = { { "scale", 5 } }, clamp = false })
local beyond = false
for i = 0, w * h - 1 do
  if unclamped[i] > 1 or unclamped[i] < 0 then
    beyond = true
    break
  end
end
ok("grid clamp = false keeps range", beyond)

local plain = vnoise.fill_grid(s, "fbm", { w = w, h = h, freq = 0.07 })
local raw_same = true
for i = 0, w * h - 1 do
  if plain[i] ~= raw[i] then
    raw_same = false
    break
  end
end
ok("grid without ops is raw", raw_same)

-- Fused image fill
local function fake_image(iw, ih)
  local buf = ffi.new("unsigned char[?]", iw * ih * 4)
  return {
    buf = buf,
    getDimensions = function()
      return iw, ih
    end,
    getPointer = function()
      return buf
    end,
  }
end

local function same_bytes(a, b, n)
  for i = 0, n - 1 do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

for _, kind in ipairs({ "fbm", "ridge", "turb" }) do
  local opts = { freq = 0.05, lo = -0.6, hi = 0.7, ox = 3, oy = -2, octaves = 5 }
  local a = fake_image(48, 40)
  vnoise.fill_imagedata(s, kind, a, opts)
  local b = fake_image(48, 40)
  vnoise.fill_imagedata(s, kind, b, { freq = 0.05, lo = -0.6, hi = 0.7, ox = 3, oy = -2, octaves = 5, ops = {} })
  ok(kind .. ": empty ops image identical", same_bytes(a.buf, b.buf, 48 * 40 * 4))

  local c = fake_image(48, 40)
  local cops = {}
  for k, v in pairs(opts) do
    cops[k] = v
  end
  cops.ops = { { "contrast", 1.7, 0.4 } }
  vnoise.fill_imagedata(s, kind, c, cops)
  local grid = vnoise.fill_grid(s, kind, {
    w = 48,
    h = 40,
    freq = 0.05,
    ox = 3,
    oy = -2,
    octaves = 5,
    ops = { { "remap", -0.6, 0.7 }, { "contrast", 1.7, 0.4 } },
  })
  local match = true
  for i = 0, 48 * 40 - 1 do
    if c.buf[i * 4] ~= math.floor(255 * grid[i]) and c.buf[i * 4] ~= math.floor(255 * grid[i] + 0.5) then
      match = false
      break
    end
  end
  ok(kind .. ": image ops match grid ops", match)
end

-- Look-up table op (spec: noise-value-ops, "Look-up table operation")
do
  local ramp = { 0, 0.2, 1 } -- samples at x = 0, 0.5, 1
  ok("lut endpoints", near(apply(0, { { "lut", ramp } }, false), 0) and near(apply(1, { { "lut", ramp } }, false), 1))
  ok("lut sample", near(apply(0.5, { { "lut", ramp } }, false), 0.2))
  ok("lut interpolates", near(apply(0.75, { { "lut", ramp } }, false), 0.6))
  ok("lut flat below", near(apply(-0.4, { { "lut", ramp } }, false), 0))
  ok("lut flat above", near(apply(1.6, { { "lut", ramp } }, false), 1))
  ok("lut NaN goes to first sample", near(apply(0 / 0, { { "lut", { 0.3, 0.9 } } }, false), 0.3))
  ok("lut single sample is constant", near(apply(0.7, { { "lut", { 0.25 } } }, false), 0.25))
  ok("lut id accepted", near(apply(0.5, { { vnoise.OP_LUT, { 0, 1 } } }, false), 0.5))
  local empty_ok = pcall(vnoise.compile_ops, { { "lut", {} } })
  ok("lut without samples raises", not empty_ok)

  local two = vnoise.compile_ops({ { "lut", { 1, 0 } }, { "lut", { 0, 0.5, 0.5, 1 } } })
  ok("two tables share one pool", two.data_n == 6)
  -- 0.25 -> 0.75 (first, inverted) -> second table at 0.75: between 0.5 and 1.
  ok("two tables in order", near(apply(0.25, two, false), 0.625))

  local mixed = { { "scale", 2 }, { "lut", { 0, 1 } }, { "offset", -0.25 } }
  ok("lut mixed with scalar ops", near(apply(0.3, mixed, false), 0.35))
  ok("lut clamps its input, not the chain", near(apply(0.8, mixed, false), 0.75))

  local ptr = ffi.new("float[3]", { 0, 0.2, 1 })
  ok("lut from a float pointer", near(apply(0.75, { { "lut", ptr, 3 } }, false), 0.6))

  local list = { { "remap", -1, 1 }, { "lut", { 0, 0.1, 0.9, 1 } } }
  local raw = vnoise.fill_grid(s, "fbm", { w = w, h = h, freq = 0.07 })
  local mapped = vnoise.fill_grid(s, "fbm", { w = w, h = h, freq = 0.07, ops = list })
  local same = true
  for i = 0, w * h - 1 do
    if mapped[i] ~= apply(raw[i], list) then
      same = false
      break
    end
  end
  ok("lut map buffer equals per-value", same)

  local img = fake_image(48, 40)
  local lut = { 0, 0.1, 0.9, 1 }
  vnoise.fill_imagedata(s, "fbm", img, { freq = 0.05, lo = -0.6, hi = 0.7, octaves = 5, ops = { { "lut", lut } } })
  local grid = vnoise.fill_grid(s, "fbm", {
    w = 48,
    h = 40,
    freq = 0.05,
    octaves = 5,
    ops = { { "remap", -0.6, 0.7 }, { "lut", lut } },
  })
  local match = true
  for i = 0, 48 * 40 - 1 do
    if img.buf[i * 4] ~= math.floor(255 * grid[i]) and img.buf[i * 4] ~= math.floor(255 * grid[i] + 0.5) then
      match = false
      break
    end
  end
  ok("lut image fill matches grid", match)
end

-- Seeded white-noise grid fill (spec: noise-white-fill)
do
  local s1 = vnoise.new(1)
  local grid = vnoise.fill_white(s1, { w = 16, h = 16, ox = 100, oy = 200 })
  local match = true
  for j = 0, 15 do
    for i = 0, 15 do
      if grid[j * 16 + i] ~= s1:white2(100 + i, 200 + j) then
        match = false
      end
    end
  end
  ok("white fill matches white2 per cell", match)
  local other = vnoise.fill_white(vnoise.new(2), { w = 16, h = 16, ox = 100, oy = 200 })
  local differs = false
  for i = 0, 255 do
    if other[i] ~= grid[i] then
      differs = true
    end
  end
  ok("white fill depends on the seed", differs)
  local neg = vnoise.fill_white(s1, { w = 4, h = 1, ox = -2, oy = -7 })
  ok("white fill negative origin", neg[0] == s1:white2(-2, -7) and neg[3] == s1:white2(1, -7))
  local mapped = vnoise.fill_white(s1, { w = 16, h = 16, ox = 100, oy = 200, ops = { { "remap", -1, 1 } } })
  local in_range = true
  for i = 0, 255 do
    if mapped[i] < 0 or mapped[i] > 1 or math.abs(mapped[i] - (grid[i] + 1) / 2) > 1e-6 then
      in_range = false
    end
  end
  ok("white fill ops remap to 0..1", in_range)
end

if failures > 0 then
  print(failures .. " failure(s)")
  os.exit(1)
end
print("all value-op tests passed")
