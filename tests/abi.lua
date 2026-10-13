-- Calling convention tests against the built library (see the rule at the top
-- of cpp/include/vnoise/vnoise.h): every function the binding declares passes
-- all its arguments in registers, octave counts are bounded, and calls made
-- from JIT-compiled code give the interpreter's results.
-- Run from the repository root after `make`: luajit tests/abi.lua
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

-- 1. No declared function needs stack arguments: at most 8 integer/pointer
-- and 8 float arguments (arm64 and x86-64 SysV register counts).
do
  local f = assert(io.open("lua/vnoise.lua", "r"))
  local src = f:read("*a")
  f:close()
  local offenders, count = {}, 0
  for cdef in src:gmatch("ffi%.cdef%(?%s*%[%[(.-)%]%]") do
    cdef = cdef:gsub("/%*.-%*/", ""):gsub("//[^\n]*", "")
    -- Struct bodies hold fields, not parameters.
    cdef = cdef:gsub("%b{}", "{}")
    for name, params in cdef:gmatch("([%w_]+)%s*(%b())%s*;") do
      count = count + 1
      local gp, fp = 0, 0
      for arg in params:sub(2, -2):gmatch("[^,]+") do
        arg = arg:gsub("^%s+", ""):gsub("%s+$", "")
        if arg ~= "" and arg ~= "void" then
          if not arg:find("%*") and (arg:match("^const%s+float") or arg:match("^float") or arg:match("^double")) then
            fp = fp + 1
          else
            gp = gp + 1
          end
        end
      end
      if gp > 8 or fp > 8 then
        offenders[#offenders + 1] = ("%s (%d int/ptr, %d float)"):format(name, gp, fp)
      end
    end
  end
  ok(("%d declared functions, none with stack arguments"):format(count), count > 50 and #offenders == 0)
  for _, o in ipairs(offenders) do
    print("        " .. o)
  end
end

local s = vnoise.new(4321)
local opts = { c0 = -5, r0 = 9, w = 24, h = 18, freq = 0.07, lac = 2.0, gain = 0.5 }
local function fill(kind, octaves)
  opts.octaves = octaves
  return vnoise.fill_domain(s, kind, opts)
end
local function same(a, b, n)
  for i = 0, n - 1 do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end
local n = opts.w * opts.h

-- 2. Octave counts are clamped to VNOISE_MAX_OCTAVES (32): a corrupted count
-- costs no more than 32 octaves.
do
  local t = os.clock()
  local huge = fill("fbm", 13282480)
  local elapsed = os.clock() - t
  ok(("huge octave count runs as 32 octaves (%.1f ms)"):format(elapsed * 1000), same(huge, fill("fbm", 32), n))
  ok("huge octave count is fast", elapsed < 0.5)
  ok("33 octaves run as 32", same(fill("fbm", 33), fill("fbm", 32), n))
  ok("counts below the bound are kept", not same(fill("fbm", 4), fill("fbm", 5), n))
end

-- 3. Hot calls (JIT-compiled where the JIT is available) match a call made by
-- the interpreter, for every function that used to take stack arguments.
do
  local function run()
    local acc = {}
    for i = 1, 300 do
      local kind = ({ "fbm", "ridge", "turb" })[i % 3 + 1]
      acc[i] = fill(kind, i % 5 + 1)[i % n]
    end
    local pipe = vnoise.fill_pipeline(s, "fbm", {
      stages = { { "invert", mask = { "polygon", { 0, 0, 20, 2, 10, 15 } } } },
    }, { w = 16, h = 16, freq = 0.05 })
    acc[#acc + 1] = pipe[100]
    local img = ffi.new("unsigned char[?]", 8 * 8 * 4)
    local fake = {
      getDimensions = function()
        return 8, 8
      end,
      getPointer = function()
        return img
      end,
    }
    for i = 1, 100 do
      vnoise.fill_imagedata(s, "ridge", fake, { octaves = i % 4 + 1, r = 10, g = 20, b = 30, a = 40 })
      vnoise.fill_imagedata(s, "fbm", fake, { octaves = i % 4 + 1, ops = { { "invert" } }, a = 7 })
    end
    acc[#acc + 1] = img[4] * 1e6 + img[5] * 1e3 + img[7]
    return acc
  end
  if jit then
    jit.off()
  end
  local ref = run()
  if jit then
    jit.on()
    jit.flush()
  end
  local hot = run()
  local equal = #ref == #hot
  for i = 1, #ref do
    equal = equal and ref[i] == hot[i]
  end
  ok("JIT-compiled calls match the interpreter", equal)
  ok("image color packing keeps alpha", ref[#ref] % 1000 == 7)
end

if failures > 0 then
  print(failures .. " failure(s)")
  os.exit(1)
end
print("all calling-convention tests passed")
