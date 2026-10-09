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

typedef struct {
    float m[6];
    float ox, oy, freq;
    float warp_amp, warp_freq;
    int warp_octaves;
    int warp_base;
} vnoise_domain_t;

void vnoise_fill_domain(const noise_state_t* s, int base, int mode,
                        float* out, int c0, int r0, int w, int h,
                        const vnoise_domain_t* d,
                        int octaves, float lac, float gain);

void vnoise_convolve(const float* src, int sw, int sh, float* dst, const float* kernel, int r);
void vnoise_convolve_sep(const float* src, int sw, int sh, float* dst,
                         const float* kx, const float* ky, int r);
void vnoise_sobel(const float* src, int sw, int sh, float* dst, int mode, float k);
void vnoise_morph(const float* src, int sw, int sh, float* dst, int op, int r, int shape);
int vnoise_morph_radius(int op, int r);
void vnoise_median(const float* src, int sw, int sh, float* dst, int r);
void vnoise_distance(const float* src, int sw, int sh, float* dst, int r, float t);

typedef struct {
    int type;
    int invert;
    float feather;
    float p[4];
} vnoise_mask_t;

void vnoise_mask_blend(float* dst, int w, int h, const float* before, int before_stride,
                       int c0, int r0, const vnoise_mask_t* mask, const float* data);
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
  OP_INVERT = 5,
  OP_THRESHOLD = 6,
  OP_SMOOTHSTEP = 7,
  OP_GAMMA = 8,
  OP_QUANTIZE = 9,
  OP_CLAMP = 10,
  -- Fractal modes of fill_domain / fill_pipeline.
  MODE_FBM = 0,
  MODE_RIDGE = 1,
  MODE_TURB = 2,
  -- Morphology ops and structuring element shapes (vnoise_morph).
  MORPH_ERODE = 0,
  MORPH_DILATE = 1,
  MORPH_OPEN = 2,
  MORPH_CLOSE = 3,
  MORPH_GRADIENT = 4,
  MORPH_TOPHAT = 5,
  MORPH_BLACKHAT = 6,
  SHAPE_SQUARE = 0,
  SHAPE_DISC = 1,
  -- Sobel outputs (vnoise_sobel).
  SOBEL_MAG = 0,
  SOBEL_X = 1,
  SOBEL_Y = 2,
  -- Mask types (vnoise_mask_t).
  MASK_RECT = 0,
  MASK_ELLIPSE = 1,
  MASK_POLYGON = 2,
  MASK_RANGE = 3,
}

-- Op names accepted in op lists, mapped to their ids.
local OP_IDS = {
  remap = vnoise.OP_REMAP,
  scale = vnoise.OP_SCALE,
  offset = vnoise.OP_OFFSET,
  contrast = vnoise.OP_CONTRAST,
  lut = vnoise.OP_LUT,
  invert = vnoise.OP_INVERT,
  threshold = vnoise.OP_THRESHOLD,
  smoothstep = vnoise.OP_SMOOTHSTEP,
  gamma = vnoise.OP_GAMMA,
  quantize = vnoise.OP_QUANTIZE,
  clamp = vnoise.OP_CLAMP,
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

-- Domain transforms, neighborhood kernels and pipelines ----------------------

-- Fractal kind -> fill_domain mode.
local MODES = { fbm = vnoise.MODE_FBM, ridge = vnoise.MODE_RIDGE, turb = vnoise.MODE_TURB }

-- Marks a compiled domain wrapper: { d = vnoise_domain_t }.
local Domain = {}

-- Reads a scalar or `{ x, y }` pair, with a default.
local function pair(v, default)
  if v == nil then
    return default, default
  elseif type(v) == "number" then
    return v, v
  end
  return v[1] or default, v[2] or default
end

--- Compiles a domain description into a `vnoise_domain_t` (wrapped). The
-- image is mirrored (`flip_x`, `flip_y`), scaled (`scale`, a number or
-- `{sx, sy}`, > 1 magnifies) and rotated (`rotate`, degrees, clockwise on a
-- y-down screen) about `pivot` (cells, default `{0, 0}`), then moved by
-- `translate` (cells). Internally this is the inverse map from output cell to
-- sample cell, `c' = pivot + M (c - translate - pivot)`. `warp = { amp, freq,
-- octaves, base }` (or named fields) adds fBm domain warping of `amp` cells
-- with a warp field of `freq` noise units per cell (defaults 0.05, 3 octaves,
-- simplex). The sample origin and frequency (`ox`, `oy`, `freq`) are set per
-- fill. A compiled domain is returned unchanged.
-- @param spec table|nil The domain description (nil = identity).
-- @return table The compiled domain `{ d = vnoise_domain_t }`.
function vnoise.compile_domain(spec)
  if getmetatable(spec) == Domain then
    return spec
  end
  spec = spec or {}
  local sx, sy = pair(spec.scale, 1)
  if sx == 0 or sy == 0 then
    error("vnoise: domain scale cannot be 0", 2)
  end
  local px, py = pair(spec.pivot, 0)
  local tx, ty = pair(spec.translate, 0)
  local angle = math.rad(spec.rotate or 0)
  local cs, sn = math.cos(angle), math.sin(angle)
  local fx = spec.flip_x and -1 or 1
  local fy = spec.flip_y and -1 or 1
  -- M = F * diag(1/sx, 1/sy) * R(-angle), R(-a) = [cos, sin; -sin, cos].
  local a, b = fx * cs / sx, fx * sn / sx
  local c, e = -fy * sn / sy, fy * cs / sy
  local d = ffi.new("vnoise_domain_t")
  d.m[0], d.m[1], d.m[2] = a, b, px - a * (tx + px) - b * (ty + py)
  d.m[3], d.m[4], d.m[5] = c, e, py - c * (tx + px) - e * (ty + py)
  d.ox, d.oy, d.freq = 0, 0, 1
  local warp = spec.warp
  if warp then
    d.warp_amp = warp.amp or warp[1] or 0
    d.warp_freq = warp.freq or warp[2] or 0.05
    d.warp_octaves = warp.octaves or warp[3] or 3
    d.warp_base = warp.base or warp[4] or vnoise.BASE_SIMPLEX2
  end
  return setmetatable({ d = d }, Domain)
end

-- Copies a compiled domain with the per-fill origin and frequency.
local function domainFor(domain, opts)
  local d = ffi.new("vnoise_domain_t", domain.d)
  d.ox, d.oy, d.freq = opts.ox or 0, opts.oy or 0, opts.freq or 0.01
  return d
end

local function modeOf(kind)
  return MODES[kind] or error("vnoise: unknown fractal kind '" .. tostring(kind) .. "'", 3)
end

--- Fills cells `(c0 .. c0 + w - 1, r0 .. r0 + h - 1)` by absolute index
-- through a domain (`opts.domain`, a description or compiled domain). Cell
-- `(c, r)` is sampled at `(ox + c' * freq, oy + r' * freq)`, `(c', r')` the
-- transformed cell, so overlapping blocks agree.
-- @param state table A state from `vnoise.new`.
-- @param kind string "fbm", "ridge" or "turb".
-- @param opts table c0, r0 (default 0), w, h (default 256), ox, oy, freq, octaves, lac, gain, base,
--   domain, out (optional buffer), ops and clamp (as in fill_grid).
-- @return cdata The filled float[w*h] buffer.
function vnoise.fill_domain(state, kind, opts)
  local mode = modeOf(kind)
  local w, h = opts.w or 256, opts.h or 256
  local out = opts.out or ffi.new("float[?]", w * h)
  local d = domainFor(vnoise.compile_domain(opts.domain), opts)
  lib.vnoise_fill_domain(
    state.s,
    opts.base or vnoise.BASE_SIMPLEX2,
    mode,
    out,
    opts.c0 or 0,
    opts.r0 or 0,
    w,
    h,
    d,
    opts.octaves or 6,
    opts.lac or 2.0,
    opts.gain or 0.5
  )
  if opts.ops then
    local chain = vnoise.compile_ops(opts.ops)
    lib.vnoise_map_buffer(out, w * h, chain.ops, chain.n, chain.data, opts.clamp == false and 0 or 1)
  end
  return out
end

-- Radius limits of the kernel stages (cost grows with the radius squared).
local MAX_RADIUS = 32
local MAX_MEDIAN_RADIUS = 7

-- Validates an integer radius parameter of a stage.
local function radiusArg(name, r, min, max)
  if type(r) ~= "number" or r ~= math.floor(r) or r < min or r > max then
    error(("vnoise: stage '%s' needs an integer radius in %d..%d, got %s"):format(name, min, max, tostring(r)), 4)
  end
  return r
end

local function floats(values)
  local buf = ffi.new("float[?]", #values)
  for i = 1, #values do
    buf[i - 1] = values[i]
  end
  return buf
end

-- A full (2r + 1)^2 convolution stage from a flat row-major kernel.
local function convStage(values, r)
  local kernel = floats(values)
  return {
    radius = r,
    run = function(src, sw, sh, dst)
      lib.vnoise_convolve(src, sw, sh, dst, kernel, r)
    end,
  }
end

-- A separable convolution stage applying the same 1D kernel on both axes.
local function sepStage(values, r)
  local k = floats(values)
  return {
    radius = r,
    run = function(src, sw, sh, dst)
      lib.vnoise_convolve_sep(src, sw, sh, dst, k, k, r)
    end,
  }
end

local function sobelStage(mode)
  return function(entry)
    local k = entry[2] or 1
    return {
      radius = 1,
      run = function(src, sw, sh, dst)
        lib.vnoise_sobel(src, sw, sh, dst, mode, k)
      end,
    }
  end
end

local SHAPES = { square = vnoise.SHAPE_SQUARE, disc = vnoise.SHAPE_DISC }

local function morphStage(op)
  return function(entry, name)
    local r = radiusArg(name, entry[2], 1, MAX_RADIUS)
    local shape = SHAPES[entry.shape or entry[3] or "square"]
    if not shape then
      error("vnoise: stage '" .. name .. "' has an unknown shape '" .. tostring(entry.shape or entry[3]) .. "'", 3)
    end
    return {
      radius = lib.vnoise_morph_radius(op, r),
      run = function(src, sw, sh, dst)
        lib.vnoise_morph(src, sw, sh, dst, op, r, shape)
      end,
    }
  end
end

-- Kernel stages by name: builder(entry, name) -> { radius, run(src, sw, sh, dst) }.
local KERNEL_STAGES = {
  convolve = function(entry, name)
    local k = entry.kernel or entry[2]
    if type(k) ~= "table" then
      error("vnoise: stage 'convolve' needs a kernel table", 3)
    end
    local values = {}
    if type(k[1]) == "table" then
      for _, row in ipairs(k) do
        if #row ~= #k then
          error("vnoise: convolve kernel must be square", 3)
        end
        for _, v in ipairs(row) do
          values[#values + 1] = v
        end
      end
    else
      values = k
    end
    local side = math.floor(math.sqrt(#values) + 0.5)
    if side * side ~= #values or side % 2 == 0 then
      error("vnoise: convolve kernel needs an odd square size, got " .. #values .. " values", 3)
    end
    return convStage(values, radiusArg(name, (side - 1) / 2, 0, MAX_RADIUS))
  end,
  blur = function(entry, name)
    local r = radiusArg(name, entry[2], 1, MAX_RADIUS)
    local taps = {}
    for i = 1, 2 * r + 1 do
      taps[i] = 1 / (2 * r + 1)
    end
    return sepStage(taps, r)
  end,
  gaussian = function(entry)
    local sigma = entry[2]
    if type(sigma) ~= "number" or sigma <= 0 then
      error("vnoise: stage 'gaussian' needs sigma > 0", 3)
    end
    local r = radiusArg("gaussian", math.ceil(3 * sigma), 1, MAX_RADIUS)
    local taps, sum = {}, 0
    for i = -r, r do
      local v = math.exp(-(i * i) / (2 * sigma * sigma))
      taps[#taps + 1] = v
      sum = sum + v
    end
    for i = 1, #taps do
      taps[i] = taps[i] / sum
    end
    return sepStage(taps, r)
  end,
  sharpen = function(entry)
    local k = entry[2] or 1
    return convStage({ 0, -k, 0, -k, 1 + 4 * k, -k, 0, -k, 0 }, 1)
  end,
  emboss = function(entry)
    local k = entry[2] or 1
    return convStage({ -k, -k, 0, -k, 1, k, 0, k, k }, 1)
  end,
  laplacian = function(entry)
    local k = entry[2] or 1
    return convStage({ 0, k, 0, k, -4 * k, k, 0, k, 0 }, 1)
  end,
  sobel = sobelStage(vnoise.SOBEL_MAG),
  sobel_x = sobelStage(vnoise.SOBEL_X),
  sobel_y = sobelStage(vnoise.SOBEL_Y),
  erode = morphStage(vnoise.MORPH_ERODE),
  dilate = morphStage(vnoise.MORPH_DILATE),
  open = morphStage(vnoise.MORPH_OPEN),
  close = morphStage(vnoise.MORPH_CLOSE),
  morph_gradient = morphStage(vnoise.MORPH_GRADIENT),
  tophat = morphStage(vnoise.MORPH_TOPHAT),
  blackhat = morphStage(vnoise.MORPH_BLACKHAT),
  median = function(entry, name)
    local r = radiusArg(name, entry[2], 1, MAX_MEDIAN_RADIUS)
    return {
      radius = r,
      run = function(src, sw, sh, dst)
        lib.vnoise_median(src, sw, sh, dst, r)
      end,
    }
  end,
  distance = function(entry, name)
    local r = radiusArg(name, entry[2], 1, MAX_RADIUS)
    local t = entry[3] or 0.5
    return {
      radius = r,
      run = function(src, sw, sh, dst)
        lib.vnoise_distance(src, sw, sh, dst, r, t)
      end,
    }
  end,
}

local MASK_TYPES = {
  rect = vnoise.MASK_RECT,
  ellipse = vnoise.MASK_ELLIPSE,
  polygon = vnoise.MASK_POLYGON,
  range = vnoise.MASK_RANGE,
}

--- Compiles a mask description: `{ "rect", x0, y0, x1, y1 }` (inclusive
-- absolute cell bounds), `{ "ellipse", cx, cy, rx, ry }`, `{ "polygon",
-- { x1, y1, x2, y2, ... } }` (three vertices or more) or `{ "range", lo, hi }`
-- (on the stage input), with optional `feather` (fade width inside the
-- boundary, default 0) and `invert`.
-- @param spec table The mask description.
-- @return table `{ mask = vnoise_mask_t, data = float[]|nil }`.
function vnoise.compile_mask(spec)
  local mtype = MASK_TYPES[spec[1]]
  if not mtype then
    error("vnoise: unknown mask '" .. tostring(spec[1]) .. "'", 2)
  end
  local m = ffi.new("vnoise_mask_t")
  m.type = mtype
  m.invert = spec.invert and 1 or 0
  m.feather = spec.feather or 0
  local data
  if mtype == vnoise.MASK_POLYGON then
    local pts = spec[2]
    if type(pts) ~= "table" or #pts < 6 or #pts % 2 ~= 0 then
      error("vnoise: polygon mask needs at least three x, y pairs", 2)
    end
    data = floats(pts)
    m.p[0], m.p[1] = 0, #pts / 2
  else
    local count = mtype == vnoise.MASK_RANGE and 2 or 4
    for i = 1, count do
      local v = spec[i + 1]
      if type(v) ~= "number" then
        error("vnoise: mask '" .. spec[1] .. "' needs " .. count .. " numbers", 2)
      end
      m.p[i - 1] = v
    end
  end
  return { mask = m, data = data }
end

-- Marks a compiled pipeline: { domain, stages, radius }.
local Pipeline = {}

--- Compiles a pipeline: `{ domain = <domain spec>, stages = { ... } }`. A
-- stage is a point op entry (as in `compile_ops`, e.g. `{ "threshold", 0.5 }`)
-- or a kernel stage: `convolve` (`kernel` = flat or nested odd square table),
-- `blur` (r), `gaussian` (sigma), `sharpen`/`emboss`/`laplacian` (k),
-- `sobel`/`sobel_x`/`sobel_y` (k), `erode`/`dilate`/`open`/`close`/
-- `morph_gradient`/`tophat`/`blackhat` (r, `shape` = "square" | "disc"),
-- `median` (r) and `distance` (r, t). Any stage may carry `mask = <mask
-- spec>` (see `compile_mask`): it then only acts where the mask weighs.
-- Consecutive unmasked point ops are fused into one chain. `radius` is the
-- total border the stages consume. A compiled pipeline is returned unchanged.
-- @param spec table The pipeline description.
-- @return table The compiled pipeline.
function vnoise.compile_pipeline(spec)
  if getmetatable(spec) == Pipeline then
    return spec
  end
  local stages, radius = {}, 0
  local pending -- unmasked point entries waiting to be fused
  local function flush()
    if pending then
      stages[#stages + 1] = { radius = 0, chain = vnoise.compile_ops(pending) }
      pending = nil
    end
  end
  for _, entry in ipairs(spec.stages or {}) do
    local name = entry[1]
    local builder = type(name) == "string" and KERNEL_STAGES[name]
    local stage
    if builder then
      flush()
      stage = builder(entry, name)
    elseif type(name) == "number" or OP_IDS[name] then
      if not entry.mask then
        pending = pending or {}
        pending[#pending + 1] = entry
      else
        flush()
        stage = { radius = 0, chain = vnoise.compile_ops({ entry }) }
      end
    else
      error("vnoise: unknown pipeline stage '" .. tostring(name) .. "'", 2)
    end
    if stage then
      if entry.mask then
        stage.mask = vnoise.compile_mask(entry.mask)
      end
      stages[#stages + 1] = stage
      radius = radius + stage.radius
    end
  end
  flush()
  return setmetatable({ domain = vnoise.compile_domain(spec.domain), stages = stages, radius = radius }, Pipeline)
end

--- Evaluates a pipeline for cells `(c0 .. c0 + w - 1, r0 .. r0 + h - 1)`.
-- The noise is sampled through the pipeline's domain over the block grown by
-- `pipeline.radius` on every side (the apron), the stages run in order on
-- unclamped values (each kernel shrinks the buffer by twice its radius), and
-- the result is clamped to 0..1 unless `opts.clamp` is false. Every cell's
-- value depends only on its absolute index, so blocks tile seamlessly.
-- @param state table A state from `vnoise.new`.
-- @param kind string "fbm", "ridge" or "turb".
-- @param pipeline table A pipeline description or compiled pipeline.
-- @param opts table c0, r0 (default 0), w, h (default 256), ox, oy, freq, octaves, lac, gain, base,
--   out (optional float[w*h]), clamp (default true).
-- @return cdata The float[w*h] buffer.
function vnoise.fill_pipeline(state, kind, pipeline, opts)
  local mode = modeOf(kind)
  local p = vnoise.compile_pipeline(pipeline)
  local w, h = opts.w or 256, opts.h or 256
  local c0, r0 = opts.c0 or 0, opts.r0 or 0
  local rem = p.radius -- apron still around the current buffer
  local sw, sh = w + 2 * rem, h + 2 * rem
  local cur = ffi.new("float[?]", sw * sh)
  local alt = ffi.new("float[?]", sw * sh)
  lib.vnoise_fill_domain(
    state.s,
    opts.base or vnoise.BASE_SIMPLEX2,
    mode,
    cur,
    c0 - rem,
    r0 - rem,
    sw,
    sh,
    domainFor(p.domain, opts),
    opts.octaves or 6,
    opts.lac or 2.0,
    opts.gain or 0.5
  )
  for _, stage in ipairs(p.stages) do
    local m = stage.mask
    if stage.chain then
      local chain = stage.chain
      if m then
        ffi.copy(alt, cur, sw * sh * ffi.sizeof("float"))
      end
      lib.vnoise_map_buffer(cur, sw * sh, chain.ops, chain.n, chain.data, 0)
      if m then
        lib.vnoise_mask_blend(cur, sw, sh, alt, sw, c0 - rem, r0 - rem, m.mask, m.data)
      end
    else
      local r = stage.radius
      local nw, nh = sw - 2 * r, sh - 2 * r
      stage.run(cur, sw, sh, alt)
      if m then
        lib.vnoise_mask_blend(alt, nw, nh, cur + r * sw + r, sw, c0 - rem + r, r0 - rem + r, m.mask, m.data)
      end
      cur, alt = alt, cur
      sw, sh, rem = nw, nh, rem - r
    end
  end
  local out = opts.out or ffi.new("float[?]", w * h)
  ffi.copy(out, cur, w * h * ffi.sizeof("float"))
  if opts.clamp ~= false then
    lib.vnoise_map_buffer(out, w * h, nil, 0, nil, 1)
  end
  return out
end

-- Global statistics as point ops ----------------------------------------------

--- Counts the values of a buffer in `bins` equal bins over `[lo, hi]`;
-- values outside go to the first or last bin. Use it on a fixed probe (for
-- example a low-resolution fill of the whole region) and turn the result
-- into point ops with `otsu` or `equalize_lut`, which are block independent.
-- @param buf cdata|table A float buffer (0-based cdata) or a 1-based Lua array.
-- @param count number The number of values.
-- @param bins number|nil Bin count (default 256).
-- @param lo number|nil Lower bound (default 0).
-- @param hi number|nil Upper bound (default 1).
-- @return table A 1-based array of `bins` counts.
function vnoise.histogram(buf, count, bins, lo, hi)
  bins, lo, hi = bins or 256, lo or 0, hi or 1
  local hist = {}
  for i = 1, bins do
    hist[i] = 0
  end
  local base = type(buf) == "table" and 1 or 0
  local scale = bins / (hi - lo)
  for i = 0, count - 1 do
    local b = math.floor((buf[i + base] - lo) * scale) + 1
    if b < 1 then
      b = 1
    elseif b > bins then
      b = bins
    end
    hist[b] = hist[b] + 1
  end
  return hist
end

--- Otsu's threshold of a histogram: the bin boundary that maximizes the
-- between-class variance (the middle of the range of boundaries when several
-- tie, as across empty bins between two modes), as a value in `[lo, hi]`
-- (use it in a `threshold` stage).
-- @param hist table Counts from `vnoise.histogram`.
-- @param lo number|nil Histogram lower bound (default 0).
-- @param hi number|nil Histogram upper bound (default 1).
-- @return number The threshold.
function vnoise.otsu(hist, lo, hi)
  lo, hi = lo or 0, hi or 1
  local bins, total, sum = #hist, 0, 0
  for i = 1, bins do
    total = total + hist[i]
    sum = sum + (i - 1) * hist[i]
  end
  -- Empty bins between two modes give a plateau of equal maxima; the
  -- threshold is the middle of the plateau (first to last best boundary).
  local best, first, last = -1, bins / 2, bins / 2
  local w0, sum0 = 0, 0
  for k = 1, bins - 1 do
    w0 = w0 + hist[k]
    sum0 = sum0 + (k - 1) * hist[k]
    local w1 = total - w0
    if w0 > 0 and w1 > 0 then
      local m0, m1 = sum0 / w0, (sum - sum0) / w1
      local between = w0 * w1 * (m0 - m1) * (m0 - m1)
      if between > best * (1 + 1e-12) then
        best, first, last = between, k, k
      elseif between >= best * (1 - 1e-12) then
        last = k
      end
    end
  end
  return lo + (first + last) / 2 * (hi - lo) / bins
end

--- Histogram-equalization table: `size` samples of the histogram's
-- cumulative distribution at inputs spread evenly over 0..1 (the histogram
-- must cover 0..1), for a `lut` stage. Non-decreasing, from 0 to 1.
-- @param hist table Counts from `vnoise.histogram` over 0..1.
-- @param size number|nil Number of samples (default 256).
-- @return table A 1-based array of samples.
function vnoise.equalize_lut(hist, size)
  size = size or 256
  local bins, total = #hist, 0
  for i = 1, bins do
    total = total + hist[i]
  end
  local cdf, acc = { [0] = 0 }, 0
  for i = 1, bins do
    acc = acc + hist[i]
    cdf[i] = total > 0 and acc / total or i / bins
  end
  local lut = {}
  for k = 0, size - 1 do
    local f = k / (size - 1) * bins -- position in bins
    local i = math.min(math.floor(f), bins - 1)
    lut[k + 1] = cdf[i] + (cdf[i + 1] - cdf[i]) * (f - i)
  end
  return lut
end

vnoise._lib = lib
return vnoise
