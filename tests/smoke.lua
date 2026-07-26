package.cpath = package.cpath .. ";./?.dylib;./libvnoise.dylib"
package.path  = package.path  .. ";./lua/?.lua"

local vnoise = require("vnoise")

local function ok(name, cond)
    print((cond and "  ok  " or " FAIL ") .. name)
    if not cond then os.exit(1) end
end

local s = vnoise.new(42)
ok("state created", s ~= nil)

-- Determinism: same seed → same result
local s2 = vnoise.new(42)
ok("same seed same perlin2",
   s:perlin2(1.5, 2.5) == s2:perlin2(1.5, 2.5))
ok("same seed same simplex3",
   s:simplex3(1.5, 2.5, 3.5) == s2:simplex3(1.5, 2.5, 3.5))

-- Different seed → different result
local s3 = vnoise.new(43)
ok("diff seed diff perlin2",
   s:perlin2(1.5, 2.5) ~= s3:perlin2(1.5, 2.5))

-- Output range check
local function check_range(name, fn, n)
    local mn, mx = 1e9, -1e9
    for i = 1, n do
        local x = (i / n) * 20 - 10
        local y = ((i * 7) % n / n) * 20 - 10
        local v = fn(x, y)
        if v < mn then mn = v end
        if v > mx then mx = v end
    end
    ok(name .. " range [" .. mn .. "," .. mx .. "]", mn >= -1.2 and mx <= 1.2)
end
check_range("perlin2",  function(x,y) return s:perlin2(x,y) end, 1000)
check_range("simplex2", function(x,y) return s:simplex2(x,y) end, 1000)
check_range("fbm2",    function(x,y) return s:fbm2(x,y,6,vnoise.BASE_SIMPLEX2) end, 1000)
check_range("ridge2",  function(x,y) return s:ridge2(x,y,6) end, 1000)
ok("turb2 >= 0",
   (function()
        for i = 1, 1000 do
            local x, y = i * 0.1, (i * 0.13) % 17
            if s:turb2(x, y, 6) < -0.01 then return false end
        end
        return true
    end)())

-- Invalid base → 0
ok("invalid base → 0", s:fbm2(1, 1, 4, 999) == 0)

-- fBm 1 octave with BASE_PERLIN2 ≈ perlin2_eval
local a = s:fbm2(1.234, 5.678, 1, vnoise.BASE_PERLIN2)
local b = s:perlin2(1.234, 5.678)
ok("fbm2 1-oct perlin2 matches", math.abs(a - b) < 1e-5)

-- fill_grid matches per-point
local w, h = 32, 32
local buf = vnoise.fill_grid(s, "fbm", {
    w = w, h = h, ox = 10, oy = 10, freq = 0.05, octaves = 4,
    base = vnoise.BASE_PERLIN2,
})
ok("fill_grid returns buffer", type(buf) == "cdata")
local mismatch = 0
for j = 0, h-1 do
    for i = 0, w-1 do
        local x, y = 10 + i * 0.05, 10 + j * 0.05
        local p = s:fbm2(x, y, 4, vnoise.BASE_PERLIN2)
        if math.abs(buf[j*w + i] - p) > 1e-4 then
            mismatch = mismatch + 1
        end
    end
end
ok("fill_grid matches per-point (mismatches="..mismatch..")", mismatch == 0)

-- white2 equality per integer cell
ok("white2 same cell twice", s:white2(7, 3) == s:white2(7, 3))
ok("white2 different cells",
   s:white2(0, 0) ~= s:white2(1, 0) or s:white2(0, 0) ~= s:white2(0, 1))

print("\nAll tests passed")