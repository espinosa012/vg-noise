-- Grayscale images as noise (spec: noise-image-source).
-- Run from the repository root after `make`: luajit tests/image_source.lua
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
local function near(a, b, e)
  return math.abs(a - b) < (e or 1e-5)
end

local tmp = os.tmpname()
local function write(path, bytes)
  local f = assert(io.open(path, "wb"))
  f:write(bytes)
  f:close()
end

-- Minimal PNG writer (grayscale, stored deflate blocks) for 8 and 16 bits.
local function crc32(str)
  local c, crc = 0, 0xffffffff
  for i = 1, #str do
    c = bit.bxor(crc, str:byte(i))
    for _ = 1, 8 do
      c = bit.band(c, 1) == 1 and bit.bxor(bit.rshift(c, 1), 0xedb88320) or bit.rshift(c, 1)
    end
    crc = c
  end
  return bit.bxor(crc, 0xffffffff)
end
local function be32(n)
  n = n % 4294967296
  return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
end
local function chunk(kind, data)
  return be32(#data) .. kind .. data .. be32(bit.tobit(crc32(kind .. data)))
end
local function png(w, h, depth, values)
  local rows = {}
  for j = 0, h - 1 do
    local row = { "\0" } -- filter: none
    for i = 0, w - 1 do
      local v = values[j * w + i + 1]
      row[#row + 1] = depth == 16 and string.char(math.floor(v / 256), v % 256) or string.char(v)
    end
    rows[#rows + 1] = table.concat(row)
  end
  local raw = table.concat(rows)
  local a, b = 1, 0
  for i = 1, #raw do
    a = (a + raw:byte(i)) % 65521
    b = (b + a) % 65521
  end
  local z = "\120\1" .. "\1" .. string.char(#raw % 256, math.floor(#raw / 256), (-#raw - 1) % 256, math.floor((65535 - #raw) / 256))
    .. raw .. be32(b * 65536 + a)
  return "\137PNG\r\n\26\n" .. chunk("IHDR", be32(w) .. be32(h) .. string.char(depth, 0, 0, 0, 0)) .. chunk("IDAT", z) .. chunk("IEND", "")
end

local state = vnoise.new(1)

-- 4 x 2 ramp: values 0, 85, 170, 255 over two rows (second row inverted).
local vals8 = { 0, 85, 170, 255, 255, 170, 85, 0 }
write(tmp .. ".png", png(4, 2, 8, vals8))
local img = vnoise.load_image(tmp .. ".png")
ok("png size", img.w == 4 and img.h == 2)
ok("png 8-bit values", near(img:pixel(1, 0), 1 / 3) and near(img:pixel(3, 0), 1) and near(img:pixel(0, 1), 1))
ok("pixel outside is nil", img:pixel(4, 0) == nil)

-- 16-bit precision
write(tmp .. "16.png", png(2, 1, 16, { 1, 65535 }))
local img16 = vnoise.load_image(tmp .. "16.png")
ok("png 16-bit precision", near(img16:pixel(0, 0), 1 / 65535, 1e-7) and near(img16:pixel(1, 0), 1))

-- PGM (binary P5)
write(tmp .. ".pgm", "P5\n2 2\n255\n" .. string.char(0, 255, 51, 102))
local pgm = vnoise.load_image(tmp .. ".pgm")
ok("pgm values", near(pgm:pixel(1, 0), 1) and near(pgm:pixel(0, 1), 0.2) and near(pgm:pixel(1, 1), 0.4))

-- Errors
ok("missing file raises", not pcall(vnoise.load_image, "/nonexistent/none.png"))
write(tmp .. ".bad", "not an image")
ok("garbage raises", not pcall(vnoise.load_image, tmp .. ".bad"))

-- Raw pixels (RGBA8 as LÖVE ImageData: luminance)
local rgba = ffi.new("uint8_t[8]", { 255, 0, 0, 255, 0, 0, 0, 255 })
local raw = vnoise.image_from_pixels(rgba, 2, 1, 4, 1)
ok("rgba luminance", near(raw:pixel(0, 0), 0.299, 1e-4) and near(raw:pixel(1, 0), 0))
local fl = ffi.new("float[2]", { 0.25, 0.75 })
ok("float pixels", near(vnoise.image_from_pixels(fl, 2, 1, 1, 4):pixel(1, 0), 0.75))
ok("bad format raises", not pcall(vnoise.image_from_pixels, rgba, 2, 1, 4, 3))

-- fill_sampler: freq 1 reproduces pixels exactly (default for the image kind)
local out = vnoise.fill_sampler(state, { kind = "image", image = img }, { w = 4, h = 2 })
local exact = true
for k = 0, 7 do
  exact = exact and near(out[k], vals8[k + 1] / 255)
end
ok("image kind reproduces pixels", exact)

-- Path as image
local byPath = vnoise.fill_sampler(state, { kind = "image", image = tmp .. ".png" }, { w = 4, h = 2 })
collectgarbage()
collectgarbage()
ok("image by path survives gc", near(byPath[3], 1) and near(vnoise.fill_sampler(state, { kind = "image", image = tmp .. ".png" }, { w = 4, h = 2 })[3], 1))

-- Filters
local half = { kind = "image", image = img, filter = "nearest" }
ok("nearest rounds", near(vnoise.fill_sampler(state, half, { w = 1, h = 1, ox = 0.4 })[0], 0))
ok("nearest rounds up", near(vnoise.fill_sampler(state, half, { w = 1, h = 1, ox = 0.6 })[0], 1 / 3))
local bil = vnoise.fill_sampler(state, { kind = "image", image = img }, { w = 1, h = 1, ox = 0.5 })
ok("bilinear midpoint", near(bil[0], 1 / 6))
local bic = vnoise.fill_sampler(state, { kind = "image", image = img, filter = "bicubic" }, { w = 1, h = 1, ox = 2 })
ok("bicubic interpolates samples", near(bic[0], 2 / 3))
ok("unknown filter raises", not pcall(vnoise.fill_sampler, state, { kind = "image", image = img, filter = "x" }, { w = 1, h = 1 }))
ok("missing image raises", not pcall(vnoise.fill_sampler, state, { kind = "image" }, { w = 1, h = 1 }))

-- Wrap modes (x = -1 and x = 4 are outside a 4 wide image)
local function at(wrap, x)
  return vnoise.fill_sampler(state, { kind = "image", image = img, wrap = wrap, filter = "nearest" }, { w = 1, h = 1, ox = x })[0]
end
ok("clamp left", near(at("clamp", -1), 0))
ok("clamp right", near(at("clamp", 9), 1))
ok("repeat", near(at("repeat", 4), 0) and near(at("repeat", -1), 1))
ok("mirror", near(at("mirror", 4), 1) and near(at("mirror", -1), 0) and near(at("mirror", -2), 1 / 3))
ok("nan coordinate is zero", at("clamp", 0 / 0) == 0)

-- Domain: scaling a 2 x 2 image to 4 x 4 cells (freq 0.5) and flipping
local up = vnoise.fill_sampler(state, { kind = "image", image = pgm }, { w = 3, h = 1, freq = 0.5 })
ok("freq upsamples", near(up[0], 0) and near(up[1], 0.5) and near(up[2], 1))

-- Source tree: image leaf, combinators and ops behave like noise
local src = vnoise.compile_source({ "add", { "image", image = img }, { "const", 0.5 }, weights = { 0.5, 1 } })
local buf = vnoise.fill_source(state, src, { w = 4, h = 2, clamp = false })
ok("source add", near(buf[3], 0.5 * 1 + 0.5) and near(buf[0], 0.5))
local inv = vnoise.fill_source(state, vnoise.compile_source({ "image", image = img, ops = { { "invert" } } }), { w = 4, h = 2 })
ok("leaf ops", near(inv[0], 1) and near(inv[3], 0))

-- Tiling: any tiling of the region equals one call
local tree = vnoise.compile_source({
  "mul",
  { "image", image = img, filter = "bicubic", wrap = "mirror", freq = 0.37, domain = { rotate = 0.4 } },
  { "fbm", freq = 0.05, octaves = 3 },
})
local whole = vnoise.fill_source(state, tree, { c0 = -8, r0 = 3, w = 16, h = 16, clamp = false })
local tiled = true
for ty = 0, 1 do
  for tx = 0, 1 do
    local part = vnoise.fill_source(state, tree, { c0 = -8 + tx * 8, r0 = 3 + ty * 8, w = 8, h = 8, clamp = false })
    for j = 0, 7 do
      for i = 0, 7 do
        tiled = tiled and near(part[j * 8 + i], whole[(ty * 8 + j) * 16 + tx * 8 + i])
      end
    end
  end
end
ok("tiling equals whole", tiled)

-- Pipeline: kernel stages run over image values
local pipe = { source = { "image", image = img }, stages = { { "blur", 1 } } }
local blurred = vnoise.fill_pipeline(state, nil, pipe, { w = 4, h = 2 })
ok("pipeline blur smooths", blurred[0] > 0.05 and blurred[3] < 0.95)
local direct = vnoise.fill_pipeline(state, "image", { stages = {} }, { w = 4, h = 2, image = img })
ok("pipeline kind image with opts", near(direct[3], 1))

-- fill_grid and fill_domain accept the kind too
ok("fill_grid", near(vnoise.fill_grid(state, "image", { w = 4, h = 2, image = img })[2], 2 / 3))
ok("fill_domain", near(vnoise.fill_domain(state, "image", { w = 4, h = 2, image = img })[2], 2 / 3))

for _, ext in ipairs({ ".png", "16.png", ".pgm", ".bad" }) do
  os.remove(tmp .. ext)
end
os.remove(tmp)
print(failures == 0 and "all image source tests passed" or (failures .. " test(s) failed"))
os.exit(failures == 0 and 0 or 1)
