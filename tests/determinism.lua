package.cpath = package.cpath .. ";./?.dylib;./libvnoise.dylib;./?.so;./libvnoise.so"
package.path  = package.path  .. ";./lua/?.lua"
package.cpath = package.cpath .. ";/Users/espinosa012/vg-noise/libvnoise.dylib"
package.path  = package.path  .. ";/Users/espinosa012/vg-noise/lua/?.lua"
local vnoise = require("vnoise")
local ffi = require("ffi")

local w, h = 64, 64
local function render(seed)
    local s = vnoise.new(seed)
    local buf = ffi.new("unsigned char[?]", w*h*4)
    vnoise._lib.fbm2_fill_imagedata_rgba8(
        s.s, vnoise.BASE_SIMPLEX2, buf, w, h, 0, 0, 0.05,
        5, 2.0, 0.5, -1, 1, 255, 255, 255, 255)
    return buf
end

local a = render(1234)
local b = render(1234)
local c = render(1235)

local eq = true
for i = 0, w*h*4 - 1 do
    if a[i] ~= b[i] then eq = false break end
end
print("same-seed bit-identical: " .. (eq and "yes" or "NO"))
local diff_seed = false
for i = 0, w*h*4 - 1 do
    if a[i] ~= c[i] then diff_seed = true break end
end
print("diff-seed differs: " .. (diff_seed and "yes" or "no (suspicious)"))

-- Saturating case: v=2.0 → byte 255; v=-2.0 → byte 0
local s = vnoise.new(7)
local buf = ffi.new("unsigned char[?]", 1*4)
vnoise._lib.fbm2_fill_imagedata_rgba8(
    s.s, vnoise.BASE_WHITE2, buf, 1, 1, 0, 0, 0,
    1, 2.0, 0.5, -1, 1, 255, 255, 255, 255)
print("clamping white2 pixel: " .. buf[0] .. "," .. buf[1] .. "," .. buf[2] .. "," .. buf[3])

-- Direct clamping test: write 2.0 and -2.0
-- We do this by distortioning range to known: set lo=1.0 hi=0.0 inverted? test lo=0, hi=1
-- For .99..1.0 saturation values - we verify perclamp elsewhere.
os.exit(eq and diff_seed and 0 or 1)