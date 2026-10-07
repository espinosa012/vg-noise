local ffi = require("ffi")

-- Shared library extension for the current OS.
local LIB_EXT = ({ OSX = ".dylib", Windows = ".dll" })[ffi.os] or ".so"

--- Loads the native library. Tries, in order: the system library search
-- path, then each base directory with `libvnoise` next to it and inside a
-- `lib/` subfolder. Base directories are the LÖVE source directory and its
-- parent when running under LÖVE, then the working directory. This lets the
-- same file work in this repository, in `dist/`, and in a game that keeps
-- the binding at its root and the library in `lib/`.
-- @return cdata The loaded library namespace.
local function load_library()
  local ok, lib = pcall(ffi.load, "vnoise")
  if ok then
    return lib
  end

  local dirs = {}
  local fs = love and love.filesystem
  if fs then
    if fs.getSource then
      dirs[#dirs + 1] = fs.getSource()
    end
    if fs.getSourceBaseDirectory then
      dirs[#dirs + 1] = fs.getSourceBaseDirectory()
    end
  end
  dirs[#dirs + 1] = os.getenv("PWD") or "."

  local tried = {}
  for _, dir in ipairs(dirs) do
    for _, rel in ipairs({ "/libvnoise", "/lib/libvnoise" }) do
      local path = dir .. rel .. LIB_EXT
      ok, lib = pcall(ffi.load, path)
      if ok then
        return lib
      end
      tried[#tried + 1] = path
    end
  end
  error("vnoise: native library not found in the system path or:\n  " .. table.concat(tried, "\n  "), 2)
end

local lib = load_library()

ffi.cdef([[
typedef struct {
    unsigned int perm[512];
    unsigned long long seed;
} noise_state_t;

void noise_init(noise_state_t* s, unsigned long long seed);

float perlin2_eval(const noise_state_t* s, float x, float y);
float perlin3_eval(const noise_state_t* s, float x, float y, float z);
float simplex2_eval(const noise_state_t* s, float x, float y);
float simplex3_eval(const noise_state_t* s, float x, float y, float z);
float white2_eval(const noise_state_t* s, int ix, int iy);
float white3_eval(const noise_state_t* s, int ix, int iy, int iz);
void white2_fill_grid(const noise_state_t* s, float* out, int ox, int oy, int w, int h);

float fbm2_eval(const noise_state_t* s, int base, float x, float y,
                int octaves, float lac, float gain);
float fbm3_eval(const noise_state_t* s, int base, float x, float y, float z,
                int octaves, float lac, float gain);
float ridge2_eval(const noise_state_t* s, int base, float x, float y,
                  int octaves, float lac, float gain);
float ridge3_eval(const noise_state_t* s, int base, float x, float y, float z,
                  int octaves, float lac, float gain);
float turb2_eval(const noise_state_t* s, int base, float x, float y,
                 int octaves, float lac, float gain);
float turb3_eval(const noise_state_t* s, int base, float x, float y, float z,
                 int octaves, float lac, float gain);

void fbm2_fill_grid(const noise_state_t* s, int base, float* out,
                    float ox, float oy, int w, int h, float freq,
                    int octaves, float lac, float gain);
void ridge2_fill_grid(const noise_state_t* s, int base, float* out,
                      float ox, float oy, int w, int h, float freq,
                      int octaves, float lac, float gain);
void turb2_fill_grid(const noise_state_t* s, int base, float* out,
                     float ox, float oy, int w, int h, float freq,
                     int octaves, float lac, float gain);

void fbm3_fill_volume(const noise_state_t* s, int base, float* out,
                      float ox, float oy, float oz, int w, int h, int d, float freq,
                      int octaves, float lac, float gain);
void ridge3_fill_volume(const noise_state_t* s, int base, float* out,
                        float ox, float oy, float oz, int w, int h, int d, float freq,
                        int octaves, float lac, float gain);
void turb3_fill_volume(const noise_state_t* s, int base, float* out,
                        float ox, float oy, float oz, int w, int h, int d, float freq,
                        int octaves, float lac, float gain);

void fbm2_fill_imagedata_rgba8(const noise_state_t* s, int base,
                               unsigned char* out, int w, int h,
                               float ox, float oy, float freq,
                               int octaves, float lac, float gain,
                               float lo, float hi,
                               unsigned char r, unsigned char g,
                               unsigned char b, unsigned char a);
void ridge2_fill_imagedata_rgba8(const noise_state_t* s, int base,
                                 unsigned char* out, int w, int h,
                                 float ox, float oy, float freq,
                                 int octaves, float lac, float gain,
                                 float lo, float hi,
                                 unsigned char r, unsigned char g,
                                 unsigned char b, unsigned char a);
void turb2_fill_imagedata_rgba8(const noise_state_t* s, int base,
                                unsigned char* out, int w, int h,
                                float ox, float oy, float freq,
                                int octaves, float lac, float gain,
                                float lo, float hi,
                                unsigned char r, unsigned char g,
                                unsigned char b, unsigned char a);

typedef struct {
    int op;
    float p[4];
} vnoise_op_t;

float vnoise_apply_ops(float v, const vnoise_op_t* ops, int n, const float* data, int clamp01);
void vnoise_map_buffer(float* buf, int count, const vnoise_op_t* ops, int n, const float* data, int clamp01);

void fbm2_fill_imagedata_ops_rgba8(const noise_state_t* s, int base,
                                   unsigned char* out, int w, int h,
                                   float ox, float oy, float freq,
                                   int octaves, float lac, float gain,
                                   const vnoise_op_t* ops, int n, const float* data,
                                   unsigned char r, unsigned char g,
                                   unsigned char b, unsigned char a);
void ridge2_fill_imagedata_ops_rgba8(const noise_state_t* s, int base,
                                     unsigned char* out, int w, int h,
                                     float ox, float oy, float freq,
                                     int octaves, float lac, float gain,
                                     const vnoise_op_t* ops, int n, const float* data,
                                     unsigned char r, unsigned char g,
                                     unsigned char b, unsigned char a);
void turb2_fill_imagedata_ops_rgba8(const noise_state_t* s, int base,
                                    unsigned char* out, int w, int h,
                                    float ox, float oy, float freq,
                                    int octaves, float lac, float gain,
                                    const vnoise_op_t* ops, int n, const float* data,
                                    unsigned char r, unsigned char g,
                                    unsigned char b, unsigned char a);
]])

local vnoise = {
  BASE_PERLIN2 = 0,
  BASE_PERLIN3 = 1,
  BASE_SIMPLEX2 = 2,
  BASE_SIMPLEX3 = 3,
  BASE_WHITE2 = 4,
  BASE_WHITE3 = 5,
  -- Value operation ids (see compile_ops).
  OP_REMAP = 0,
  OP_SCALE = 1,
  OP_OFFSET = 2,
  OP_CONTRAST = 3,
  OP_LUT = 4,
}

-- Op names accepted in op lists, mapped to their ids.
local OP_IDS = {
  remap = vnoise.OP_REMAP,
  scale = vnoise.OP_SCALE,
  offset = vnoise.OP_OFFSET,
  contrast = vnoise.OP_CONTRAST,
  lut = vnoise.OP_LUT,
}

-- Metatable that marks a compiled op chain:
-- { ops = vnoise_op_t[n], n = n, data = float[data_n] or nil, data_n = data_n }.
local Chain = {}

-- Returns the samples and sample count of a LUT entry: `{ "lut", values }`
-- with a Lua array, or `{ "lut", ptr, count }` with a float cdata pointer.
local function lutSource(entry)
  local values, count = entry[2], entry[3]
  if type(values) == "table" then
    count = #values
  end
  if type(count) ~= "number" or count < 1 then
    error("vnoise: lut op needs at least one sample", 3)
  end
  return values, count
end

--- Compiles an op list into a chain the native functions accept. Each entry
-- is `{ name_or_id, p0, p1, ... }` (up to four parameters, missing ones are
-- 0), e.g. `{ {"remap", -1, 1}, {"contrast", 2, 0.5} }`. A look-up table op
-- is `{ "lut", values }` (a Lua array of samples spread evenly over [0, 1])
-- or `{ "lut", float_ptr, count }`; its samples are copied into the chain's
-- float pool (`data`). The result can be reused across calls to avoid
-- rebuilding the arrays; a compiled chain is returned unchanged.
-- @param list table The op list, or an already compiled chain.
-- @return table The compiled chain `{ ops = cdata, n = count, data = cdata|nil, data_n = count }`.
function vnoise.compile_ops(list)
  if getmetatable(list) == Chain then
    return list
  end
  local n = #list
  local ops = ffi.new("vnoise_op_t[?]", math.max(n, 1))
  -- First pass: resolve ids and size the LUT pool.
  local ids, data_n = {}, 0
  for k = 1, n do
    local id = list[k][1]
    if type(id) == "string" then
      id = OP_IDS[id] or error("vnoise: unknown op '" .. id .. "'", 2)
    end
    ids[k] = id
    if id == vnoise.OP_LUT then
      local _, count = lutSource(list[k])
      data_n = data_n + count
    end
  end
  local data = data_n > 0 and ffi.new("float[?]", data_n) or nil
  local offset = 0
  for k = 1, n do
    local entry = list[k]
    local o = ops[k - 1]
    o.op = ids[k]
    if ids[k] == vnoise.OP_LUT then
      local values, count = lutSource(entry)
      if type(values) == "table" then
        for i = 1, count do
          data[offset + i - 1] = values[i]
        end
      else
        ffi.copy(data + offset, values, count * ffi.sizeof("float"))
      end
      o.p[0], o.p[1], o.p[2], o.p[3] = offset, count, 0, 0
      offset = offset + count
    else
      for i = 1, 4 do
        o.p[i - 1] = entry[i + 1] or 0
      end
    end
  end
  return setmetatable({ ops = ops, n = n, data = data, data_n = data_n }, Chain)
end

--- Applies an op chain to one value.
-- @param v number The input value.
-- @param ops table An op list or compiled chain.
-- @param clamp boolean|nil Clamp the result to [0, 1] (default true).
-- @return number The result.
function vnoise.apply_ops(v, ops, clamp)
  local chain = vnoise.compile_ops(ops)
  return lib.vnoise_apply_ops(v, chain.ops, chain.n, chain.data, clamp == false and 0 or 1)
end

local State = {}
State.__index = State

function vnoise.new(seed)
  local s = ffi.new("noise_state_t")
  lib.noise_init(s, seed or 0)
  return setmetatable({ s = s }, State)
end

function State:perlin2(x, y)
  return lib.perlin2_eval(self.s, x, y)
end
function State:perlin3(x, y, z)
  return lib.perlin3_eval(self.s, x, y, z)
end
function State:simplex2(x, y)
  return lib.simplex2_eval(self.s, x, y)
end
function State:simplex3(x, y, z)
  return lib.simplex3_eval(self.s, x, y, z)
end
function State:white2(ix, iy)
  return lib.white2_eval(self.s, ix, iy)
end
function State:white3(ix, iy, iz)
  return lib.white3_eval(self.s, ix, iy, iz)
end

-- Fractal samplers. lac (lacunarity) and gain are optional and default to
-- 2.0 and 0.5, matching fill_grid / fill_volume / fill_imagedata.
function State:fbm2(x, y, octaves, base, lac, gain)
  return lib.fbm2_eval(self.s, base or vnoise.BASE_SIMPLEX2, x, y, octaves or 6, lac or 2.0, gain or 0.5)
end
function State:fbm3(x, y, z, octaves, base, lac, gain)
  return lib.fbm3_eval(self.s, base or vnoise.BASE_SIMPLEX3, x, y, z, octaves or 6, lac or 2.0, gain or 0.5)
end
function State:ridge2(x, y, octaves, base, lac, gain)
  return lib.ridge2_eval(self.s, base or vnoise.BASE_SIMPLEX2, x, y, octaves or 6, lac or 2.0, gain or 0.5)
end
function State:ridge3(x, y, z, octaves, base, lac, gain)
  return lib.ridge3_eval(self.s, base or vnoise.BASE_SIMPLEX3, x, y, z, octaves or 6, lac or 2.0, gain or 0.5)
end
function State:turb2(x, y, octaves, base, lac, gain)
  return lib.turb2_eval(self.s, base or vnoise.BASE_SIMPLEX2, x, y, octaves or 6, lac or 2.0, gain or 0.5)
end
function State:turb3(x, y, z, octaves, base, lac, gain)
  return lib.turb3_eval(self.s, base or vnoise.BASE_SIMPLEX3, x, y, z, octaves or 6, lac or 2.0, gain or 0.5)
end

local FNS_2D = {
  fbm = lib.fbm2_fill_grid,
  ridge = lib.ridge2_fill_grid,
  turb = lib.turb2_fill_grid,
}
local FNS_3D = {
  fbm = lib.fbm3_fill_volume,
  ridge = lib.ridge3_fill_volume,
  turb = lib.turb3_fill_volume,
}

function vnoise.fill_grid(state, kind, opts)
  local fn = FNS_2D[kind] or error("unknown fractal kind '" .. tostring(kind) .. "'", 2)
  local w, h = opts.w or 256, opts.h or 256
  local out = opts.out or ffi.new("float[?]", w * h)
  fn(
    state.s,
    opts.base or vnoise.BASE_SIMPLEX2,
    out,
    opts.ox or 0,
    opts.oy or 0,
    w,
    h,
    opts.freq or 0.01,
    opts.octaves or 6,
    opts.lac or 2.0,
    opts.gain or 0.5
  )
  -- Optional op chain over the raw values (clamped unless opts.clamp is false).
  if opts.ops then
    local chain = vnoise.compile_ops(opts.ops)
    lib.vnoise_map_buffer(out, w * h, chain.ops, chain.n, chain.data, opts.clamp == false and 0 or 1)
  end
  return out
end

-- Fills a float[w*h] buffer with seeded 2D white noise over integer cells:
-- out[j * w + i] = state:white2(ox + i, oy + j), values in [-1, 1].
-- opts: w, h (default 256), ox, oy (integer cell origin, default 0), out
-- (optional pre-allocated buffer), ops (optional op list or compiled chain)
-- and clamp (clamp the op results to 0..1, default true), as in fill_grid.
function vnoise.fill_white(state, opts)
  local w, h = opts.w or 256, opts.h or 256
  local out = opts.out or ffi.new("float[?]", w * h)
  lib.white2_fill_grid(state.s, out, opts.ox or 0, opts.oy or 0, w, h)
  if opts.ops then
    local chain = vnoise.compile_ops(opts.ops)
    lib.vnoise_map_buffer(out, w * h, chain.ops, chain.n, chain.data, opts.clamp == false and 0 or 1)
  end
  return out
end

function vnoise.fill_volume(state, kind, opts)
  local fn = FNS_3D[kind] or error("unknown fractal kind '" .. tostring(kind) .. "'", 2)
  local w, h, d = opts.w or 64, opts.h or 64, opts.d or 64
  local out = opts.out or ffi.new("float[?]", w * h * d)
  fn(
    state.s,
    opts.base or vnoise.BASE_SIMPLEX3,
    out,
    opts.ox or 0,
    opts.oy or 0,
    opts.oz or 0,
    w,
    h,
    d,
    opts.freq or 0.01,
    opts.octaves or 6,
    opts.lac or 2.0,
    opts.gain or 0.5
  )
  return out
end

local IMG_FNS = {
  fbm = lib.fbm2_fill_imagedata_rgba8,
  ridge = lib.ridge2_fill_imagedata_rgba8,
  turb = lib.turb2_fill_imagedata_rgba8,
}

local IMG_OPS_FNS = {
  fbm = lib.fbm2_fill_imagedata_ops_rgba8,
  ridge = lib.ridge2_fill_imagedata_ops_rgba8,
  turb = lib.turb2_fill_imagedata_ops_rgba8,
}

-- With opts.ops, fills through the chain remap(lo, hi) followed by opts.ops
-- (one native pass); without it, maps [lo, hi] to [0, 255] as before.
function vnoise.fill_imagedata(state, kind, img, opts)
  local fn = IMG_FNS[kind] or error("unknown fractal kind '" .. tostring(kind) .. "'", 2)
  local w, h = img:getDimensions()
  local ptr = ffi.cast("unsigned char*", img:getPointer())
  if opts.ops then
    local chain = vnoise.compile_ops(opts.ops)
    local ops = ffi.new("vnoise_op_t[?]", chain.n + 1)
    ops[0].op = vnoise.OP_REMAP
    ops[0].p[0] = opts.lo or -1
    ops[0].p[1] = opts.hi or 1
    if chain.n > 0 then
      ffi.copy(ops + 1, chain.ops, chain.n * ffi.sizeof("vnoise_op_t"))
    end
    IMG_OPS_FNS[kind](
      state.s,
      opts.base or vnoise.BASE_SIMPLEX2,
      ptr,
      w,
      h,
      opts.ox or 0,
      opts.oy or 0,
      opts.freq or 0.01,
      opts.octaves or 6,
      opts.lac or 2.0,
      opts.gain or 0.5,
      ops,
      chain.n + 1,
      chain.data,
      opts.r or 255,
      opts.g or 255,
      opts.b or 255,
      opts.a or 255
    )
    return img
  end
  fn(
    state.s,
    opts.base or vnoise.BASE_SIMPLEX2,
    ptr,
    w,
    h,
    opts.ox or 0,
    opts.oy or 0,
    opts.freq or 0.01,
    opts.octaves or 6,
    opts.lac or 2.0,
    opts.gain or 0.5,
    opts.lo or -1,
    opts.hi or 1,
    opts.r or 255,
    opts.g or 255,
    opts.b or 255,
    opts.a or 255
  )
  return img
end

vnoise._lib = lib
return vnoise
