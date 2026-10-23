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
                               float lo, float hi, unsigned int rgba);
void ridge2_fill_imagedata_rgba8(const noise_state_t* s, int base,
                                 unsigned char* out, int w, int h,
                                 float ox, float oy, float freq,
                                 int octaves, float lac, float gain,
                                 float lo, float hi, unsigned int rgba);
void turb2_fill_imagedata_rgba8(const noise_state_t* s, int base,
                                unsigned char* out, int w, int h,
                                float ox, float oy, float freq,
                                int octaves, float lac, float gain,
                                float lo, float hi, unsigned int rgba);

typedef struct {
    int op;
    float p[4];
} vnoise_op_t;

float vnoise_apply_ops(float v, const vnoise_op_t* ops, int n, const float* data, int clamp01);
void vnoise_map_buffer(float* buf, int count, const vnoise_op_t* ops, int n, const float* data, int clamp01);

typedef struct {
    const vnoise_op_t* ops;
    int n;
    const float* data;
} vnoise_chain_t;

void fbm2_fill_imagedata_ops_rgba8(const noise_state_t* s, int base,
                                   unsigned char* out, int w, int h,
                                   float ox, float oy, float freq,
                                   int octaves, float lac, float gain,
                                   const vnoise_chain_t* chain, unsigned int rgba);
void ridge2_fill_imagedata_ops_rgba8(const noise_state_t* s, int base,
                                     unsigned char* out, int w, int h,
                                     float ox, float oy, float freq,
                                     int octaves, float lac, float gain,
                                     const vnoise_chain_t* chain, unsigned int rgba);
void turb2_fill_imagedata_ops_rgba8(const noise_state_t* s, int base,
                                    unsigned char* out, int w, int h,
                                    float ox, float oy, float freq,
                                    int octaves, float lac, float gain,
                                    const vnoise_chain_t* chain, unsigned int rgba);

typedef struct {
    float m[6];
    float ox, oy, freq;
    float warp_amp, warp_freq;
    int warp_octaves;
    int warp_base;
    int warp_levels;
    float warp_lac, warp_gain;
} vnoise_domain_t;

typedef struct vnoise_image_t vnoise_image_t;

typedef struct {
    int mode;
    int base;
    int octaves;
    float lac, gain;
    float jitter;
    float damping;
    float p[4];
    const vnoise_image_t* image;
    int wrap, filter;
} vnoise_sampler_t;

void vnoise_fill_domain(const noise_state_t* s, const vnoise_sampler_t* sp,
                        float* out, int c0, int r0, int w, int h,
                        const vnoise_domain_t* d);

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
    const float* data;
} vnoise_mask_t;

void vnoise_mask_blend(float* dst, int w, int h, const float* before, int before_stride,
                       int c0, int r0, const vnoise_mask_t* mask);
]])

ffi.cdef([[
float perlin2_deriv(const noise_state_t* s, float x, float y, float* dx, float* dy);
float simplex2_deriv(const noise_state_t* s, float x, float y, float* dx, float* dy);
float cellular2_eval(const noise_state_t* s, float x, float y, float jitter, int ret);

void vnoise_fill_sampler(const noise_state_t* s, const vnoise_sampler_t* sp,
                         float* out, int c0, int r0, int w, int h, const vnoise_domain_t* d);
vnoise_image_t* vnoise_image_load(const char* path);
vnoise_image_t* vnoise_image_from_pixels(const void* data, int w, int h, int channels, int bytes);
void vnoise_image_free(vnoise_image_t* img);
int vnoise_image_width(const vnoise_image_t* img);
int vnoise_image_height(const vnoise_image_t* img);
const float* vnoise_image_data(const vnoise_image_t* img);
const char* vnoise_image_error(void);
void vnoise_combine(float* dst, const float* src, int count, int op, float w);
void vnoise_combine_lerp(float* dst, const float* b, const float* t, int count);
void vnoise_gullies(const float* src, int sw, int sh, float* dst, int c0, int r0,
                    const noise_state_t* s, float scale, float strength, int octaves,
                    float gain, float sharpness);

typedef struct {
    int width, height;
    int macro_cell;
    float sea_level;
    int outlets;
    unsigned long long seed;
    int erosion_iterations;
    int erosion_reroute;
    float erosion_k, erosion_m, erosion_dt, erosion_uplift, erosion_diffusion;
    float river_min_flow;
    float river_width, river_max_width;
    float river_depth, river_max_depth;
    float lake_depth;
    int river_smooth;
    float valley, valley_min, valley_shape, bank;
    float meander_amp, meander_freq;
    float distance_range;
    float detail_amplitude, detail_valley_damping;
} vnoise_plan_params_t;

typedef struct vnoise_plan vnoise_plan_t;

vnoise_plan_t* vnoise_plan_create(const vnoise_plan_params_t* params, const float* height, const float* uplift);
void vnoise_plan_destroy(vnoise_plan_t* plan);
void vnoise_plan_info(const vnoise_plan_t* plan, int* mw, int* mh, int* polylines, int* vertices);
void vnoise_plan_grid(const vnoise_plan_t* plan, int which, float* out);
typedef struct {
    int* start;
    int* count;
    int* mouth;
    float* x;
    float* y;
    float* flow;
    float* width;
    float* bed;
} vnoise_rivers_out_t;

typedef struct {
    float* elevation;
    float* river;
    float* lake;
    float* flow;
    float* channel_distance;
} vnoise_terrain_out_t;

void vnoise_plan_rivers(const vnoise_plan_t* plan, const vnoise_rivers_out_t* out);
int vnoise_plan_query(const vnoise_plan_t* plan, float c, float r, float* out);
void vnoise_plan_fill(const vnoise_plan_t* plan, int c0, int r0, int w, int h,
                      const float* detail, const vnoise_terrain_out_t* out);
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
  -- Extra modes of fill_sampler.
  MODE_CELL_F1 = 3,
  MODE_CELL_F2 = 4,
  MODE_CELL_EDGE = 5,
  MODE_CELL_VALUE = 6,
  MODE_DAMPED = 7,
  MODE_IMAGE = 8,
  -- Image wrap modes and filters (vnoise_sampler_t).
  WRAP_CLAMP = 0,
  WRAP_REPEAT = 1,
  WRAP_MIRROR = 2,
  FILTER_NEAREST = 0,
  FILTER_BILINEAR = 1,
  FILTER_BICUBIC = 2,
  -- cellular2_eval results.
  CELL_F1 = 0,
  CELL_F2 = 1,
  CELL_EDGE = 2,
  CELL_VALUE = 3,
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

-- Sampler kinds of fill_sampler and source leaves, mapped to their modes.
local SAMPLER_KINDS = {
  fbm = vnoise.MODE_FBM,
  ridge = vnoise.MODE_RIDGE,
  turb = vnoise.MODE_TURB,
  cell_f1 = vnoise.MODE_CELL_F1,
  cell_f2 = vnoise.MODE_CELL_F2,
  cell_edge = vnoise.MODE_CELL_EDGE,
  cell_value = vnoise.MODE_CELL_VALUE,
  damped = vnoise.MODE_DAMPED,
  image = vnoise.MODE_IMAGE,
}

-- Grayscale images ------------------------------------------------------------

-- Marks an image object: { ptr = vnoise_image_t* (freed with the object), w, h }.
local Image = {}
Image.__index = Image

local IMAGE_WRAPS = { clamp = vnoise.WRAP_CLAMP, ["repeat"] = vnoise.WRAP_REPEAT, mirror = vnoise.WRAP_MIRROR }
local IMAGE_FILTERS =
  { nearest = vnoise.FILTER_NEAREST, bilinear = vnoise.FILTER_BILINEAR, bicubic = vnoise.FILTER_BICUBIC }

-- Keeps the image of each sampler struct alive as long as the struct is
-- (the struct only holds a raw pointer). Weak keys: entries go with the struct.
local IMAGE_OF = setmetatable({}, { __mode = "k" })

local function wrapImage(ptr, level, what)
  if ptr == nil then
    error("vnoise: " .. what, level + 1)
  end
  ptr = ffi.gc(ptr, lib.vnoise_image_free)
  return setmetatable({ ptr = ptr, w = lib.vnoise_image_width(ptr), h = lib.vnoise_image_height(ptr) }, Image)
end

--- Loads a grayscale image to use as a noise field (`kind = "image"`). PNG,
-- JPEG, BMP, TGA and PGM/PNM files are read; colour files become luminance,
-- 16-bit files keep their precision. Values are floats in 0..1, row 0 on top.
-- @param path string The image file.
-- @return table An image `{ w, h, ptr }` with `:pixel(i, j)`.
function vnoise.load_image(path)
  if type(path) ~= "string" then
    error("vnoise: load_image needs a path string", 2)
  end
  local ptr = lib.vnoise_image_load(path)
  if ptr == nil then
    error(("vnoise: cannot load image '%s': %s"):format(path, ffi.string(lib.vnoise_image_error())), 2)
  end
  return wrapImage(ptr, 2, "")
end

--- Builds an image from raw pixels (copied), e.g. a LÖVE ImageData with
-- `image_from_pixels(data:getPointer(), data:getWidth(), data:getHeight(), 4, 1)`.
-- @param data cdata|string Row-major pixels, top row first.
-- @param w number Width in pixels.
-- @param h number Height in pixels.
-- @param channels number|nil Interleaved channels, 1..4 (default 1). One or two use the first
--   channel; three or four use the luminance of the first three.
-- @param bytes number|nil Bytes per channel: 1 (0..255), 2 (uint16) or 4 (float 0..1). Default 1.
-- @return table The image.
function vnoise.image_from_pixels(data, w, h, channels, bytes)
  local ptr = lib.vnoise_image_from_pixels(data, w, h, channels or 1, bytes or 1)
  return wrapImage(ptr, 2, "image_from_pixels needs positive sizes, 1..4 channels, 1/2/4 bytes and pixel data")
end

--- True when `v` is an image made by `load_image` or `image_from_pixels`.
function vnoise.is_image(v)
  return getmetatable(v) == Image
end

--- The value (0..1) of pixel `(i, j)`, zero-based; nil outside the image.
function Image:pixel(i, j)
  if i < 0 or j < 0 or i >= self.w or j >= self.h then
    return nil
  end
  return lib.vnoise_image_data(self.ptr)[j * self.w + i]
end

-- An image given as a path or an image object.
local function resolveImage(v, level)
  if type(v) == "string" then
    return vnoise.load_image(v)
  end
  if getmetatable(v) ~= Image then
    error("vnoise: kind 'image' needs an `image` (a path or an image from load_image)", level + 1)
  end
  return v
end

-- Reads a named choice of a table, raising an error naming an unknown value.
local function pick(map, value, default, what, level)
  local v = map[value == nil and default or value]
  if v == nil then
    error("vnoise: unknown " .. what .. " '" .. tostring(value) .. "'", level + 1)
  end
  return v
end

-- Builds a vnoise_sampler_t from `{ kind, base, octaves, lac, gain, jitter, damping }`.
local function samplerStruct(spec, level)
  local mode = SAMPLER_KINDS[spec.kind]
  if not mode then
    error("vnoise: unknown sampler kind '" .. tostring(spec.kind) .. "'", level + 1)
  end
  local sp = ffi.new("vnoise_sampler_t")
  sp.mode = mode
  sp.base = spec.base or vnoise.BASE_SIMPLEX2
  sp.octaves = spec.octaves or 6
  sp.lac = spec.lac or 2.0
  sp.gain = spec.gain or 0.5
  sp.jitter = spec.jitter or 1
  sp.damping = spec.damping or 1
  if mode == vnoise.MODE_IMAGE then
    local img = resolveImage(spec.image, level + 1)
    sp.image = img.ptr
    sp.wrap = pick(IMAGE_WRAPS, spec.wrap, "clamp", "image wrap", level + 1)
    sp.filter = pick(IMAGE_FILTERS, spec.filter, "bilinear", "image filter", level + 1)
    IMAGE_OF[sp] = img
  end
  return sp
end

-- Builds the sampler for a non-classic kind of `fill_grid`, `fill_domain` or
-- `fill_pipeline` from the fill options (`base`, `octaves`, `lac`, `gain`,
-- `jitter`, `damping`); nil for the classic fractal kinds, which keep their
-- dedicated native fills (bit-identical to earlier versions).
local function fillSampler(kind, opts, level)
  if kind == "fbm" or kind == "ridge" or kind == "turb" then
    return nil
  end
  return samplerStruct({
    kind = kind,
    base = opts.base,
    octaves = opts.octaves,
    lac = opts.lac,
    gain = opts.gain,
    jitter = opts.jitter,
    damping = opts.damping,
    image = opts.image,
    wrap = opts.wrap,
    filter = opts.filter,
  }, level + 1)
end

-- Builds the sampler of a classic fractal kind ("fbm", "ridge", "turb") for
-- `vnoise_fill_domain` from the fill options (`base`, `octaves`, `lac`, `gain`).
local function classicSampler(kind, opts, level)
  return samplerStruct({
    kind = kind,
    base = opts.base,
    octaves = opts.octaves,
    lac = opts.lac,
    gain = opts.gain,
  }, level + 1)
end

--- Fills a float[w*h] grid: cell (i, j) is sampled at (ox + i * freq, oy + j * freq).
-- @param state table A state from `vnoise.new`.
-- @param kind string Any sampler kind ("fbm", "ridge", "turb" use the dedicated grid fills;
--   "damped" and the cellular kinds go through `vnoise_fill_sampler` with an identity domain
--   and read `opts.jitter` / `opts.damping`).
-- @param opts table w, h (256), ox, oy, freq (0.01), octaves, lac, gain, base, jitter, damping,
--   out, ops and clamp (default true, applied with ops).
-- @return cdata The float[w*h] buffer.
function vnoise.fill_grid(state, kind, opts)
  local fn = FNS_2D[kind]
  local sp = not fn and fillSampler(kind, opts, 2)
  local w, h = opts.w or 256, opts.h or 256
  local out = opts.out or ffi.new("float[?]", w * h)
  if sp then
    -- Identity domain over cells (0 .. w - 1, 0 .. h - 1): cell (i, j) is
    -- sampled at (ox + i * freq, oy + j * freq), as the classic grid fills.
    local d = ffi.new("vnoise_domain_t")
    d.m[0], d.m[4] = 1, 1
    d.ox, d.oy, d.freq = opts.ox or 0, opts.oy or 0, opts.freq or (kind == "image" and 1 or 0.01)
    lib.vnoise_fill_sampler(state.s, sp, out, 0, 0, w, h, d)
  else
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
  end
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

-- Packs `opts.r`, `g`, `b`, `a` (0..255, default 255) into the unsigned int
-- the image fills take: r | g << 8 | b << 16 | a << 24.
local function packRGBA(opts)
  local function byte(v)
    return bit.band(math.floor(v or 255), 0xff)
  end
  return ffi.cast(
    "unsigned int",
    bit.bor(byte(opts.r), bit.lshift(byte(opts.g), 8), bit.lshift(byte(opts.b), 16), bit.lshift(byte(opts.a), 24))
  )
end

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
    local full = ffi.new("vnoise_chain_t", { ops, chain.n + 1, chain.data })
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
      full,
      packRGBA(opts)
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
    packRGBA(opts)
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
-- simplex); `levels` (1..4, default 1) iterates it (`f(p + a r)`,
-- `r = g(p + a q)`, `q = g(p)`) and `lac`/`gain` (2, 0.5) shape its octaves.
-- `affine = { a, b, c, d, e, f }` gives the cell map directly
-- (`c' = a c + b r + c0`, `r' = d c + e r + f`) instead of the transform
-- fields, e.g. to compose it with a caller's own pixel-to-cell map (see
-- `domain_affine`). The sample origin and frequency (`ox`, `oy`, `freq`) are
-- set per fill. A compiled domain is returned unchanged.
-- @param spec table|nil The domain description (nil = identity).
-- @return table The compiled domain `{ d = vnoise_domain_t }`.
function vnoise.compile_domain(spec)
  if getmetatable(spec) == Domain then
    return spec
  end
  spec = spec or {}
  local d = ffi.new("vnoise_domain_t")
  if spec.affine then
    -- Explicit map from output cell to sample cell (used by callers that
    -- compose the transform with their own pixel-to-cell mapping).
    local a = spec.affine
    for i = 1, 6 do
      if type(a[i]) ~= "number" then
        error("vnoise: domain affine needs six numbers", 2)
      end
      d.m[i - 1] = a[i]
    end
  else
    local m = vnoise.domain_affine(spec)
    for i = 1, 6 do
      d.m[i - 1] = m[i]
    end
  end
  d.ox, d.oy, d.freq = 0, 0, 1
  local warp = spec.warp
  if warp then
    d.warp_amp = warp.amp or warp[1] or 0
    d.warp_freq = warp.freq or warp[2] or 0.05
    d.warp_octaves = warp.octaves or warp[3] or 3
    d.warp_base = warp.base or warp[4] or vnoise.BASE_SIMPLEX2
    local levels = warp.levels or 1
    if type(levels) ~= "number" or levels < 1 or levels > 4 or levels % 1 ~= 0 then
      error("vnoise: domain warp 'levels' must be an integer in 1..4", 2)
    end
    d.warp_levels = levels
    d.warp_lac = warp.lac or 2
    d.warp_gain = warp.gain or 0.5
  end
  return setmetatable({ d = d }, Domain)
end

--- Returns the affine map from output cell to sample cell of a domain
-- description (`rotate`, `scale`, `flip_x`, `flip_y`, `translate`, `pivot`;
-- see `compile_domain`) as six numbers `{ a, b, c, d, e, f }`:
-- `c' = a c + b r + c0`, `r' = d c + e r + f`. A scale of 0 raises an error.
-- @param spec table|nil The domain description (nil = identity).
-- @return table The six coefficients.
function vnoise.domain_affine(spec)
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
  return { a, b, px - a * (tx + px) - b * (ty + py), c, e, py - c * (tx + px) - e * (ty + py) }
end

-- Copies a compiled domain with the per-fill origin and frequency.
local function domainFor(domain, opts, kind)
  local d = ffi.new("vnoise_domain_t", domain.d)
  d.ox, d.oy, d.freq = opts.ox or 0, opts.oy or 0, opts.freq or (kind == "image" and 1 or 0.01)
  return d
end

local function modeOf(kind)
  return MODES[kind] or SAMPLER_KINDS[kind] or error("vnoise: unknown fractal kind '" .. tostring(kind) .. "'", 3)
end

--- Fills cells `(c0 .. c0 + w - 1, r0 .. r0 + h - 1)` by absolute index
-- through a domain (`opts.domain`, a description or compiled domain). Cell
-- `(c, r)` is sampled at `(ox + c' * freq, oy + r' * freq)`, `(c', r')` the
-- transformed cell, so overlapping blocks agree.
-- @param state table A state from `vnoise.new`.
-- @param kind string Any sampler kind: "fbm", "ridge", "turb", "damped", "cell_f1", "cell_f2",
--   "cell_edge" or "cell_value" (the last five read `opts.jitter` and `opts.damping`).
-- @param opts table c0, r0 (default 0), w, h (default 256), ox, oy, freq, octaves, lac, gain, base,
--   domain, out (optional buffer), ops and clamp (as in fill_grid).
-- @return cdata The filled float[w*h] buffer.
function vnoise.fill_domain(state, kind, opts)
  modeOf(kind) -- raises for an unknown kind
  local w, h = opts.w or 256, opts.h or 256
  local out = opts.out or ffi.new("float[?]", w * h)
  local d = domainFor(vnoise.compile_domain(opts.domain), opts, kind)
  local sp = fillSampler(kind, opts, 2)
  if sp then
    lib.vnoise_fill_sampler(state.s, sp, out, opts.c0 or 0, opts.r0 or 0, w, h, d)
  else
    lib.vnoise_fill_domain(state.s, classicSampler(kind, opts, 2), out, opts.c0 or 0, opts.r0 or 0, w, h, d)
  end
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

-- Kernel stages by name: builder(entry, name) -> { radius, run(src, sw, sh, dst, c0, r0, state) },
-- with (c0, r0) the absolute cell of src[0] (only position-dependent stages use it).
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
  gullies = function(entry)
    local scale = entry.scale or 8
    if type(scale) ~= "number" or scale <= 0 then
      error("vnoise: stage 'gullies' needs scale > 0, got " .. tostring(scale), 3)
    end
    local octaves = entry.octaves or 2
    if type(octaves) ~= "number" or octaves ~= math.floor(octaves) or octaves < 1 or octaves > 4 then
      error("vnoise: stage 'gullies' needs integer octaves in 1..4, got " .. tostring(octaves), 3)
    end
    local strength, gain, sharpness = entry.strength or 0.05, entry.gain or 0.5, entry.sharpness or 1
    for pname, v in pairs({ strength = strength, gain = gain, sharpness = sharpness }) do
      if type(v) ~= "number" then
        error("vnoise: stage 'gullies' needs a number for " .. pname, 3)
      end
    end
    return {
      radius = 1,
      run = function(src, sw, sh, dst, c0, r0, state)
        lib.vnoise_gullies(src, sw, sh, dst, c0, r0, state.s, scale, strength, octaves, gain, sharpness)
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
-- @return table `{ mask = vnoise_mask_t, data = float[]|nil }` (`mask.data` points into
--   `data`, which the table keeps alive).
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
    m.data = data
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
-- `median` (r) and `distance` (r, t), and `gullies` (scale, strength,
-- octaves, gain, sharpness; radius 1, an erosion filter). Any stage may carry
-- `mask = <mask spec>` (see `compile_mask`): it then only acts where the mask
-- weighs. `source = <source spec>` (see `compile_source`) replaces the single
-- fractal sampler with a source tree; it cannot be combined with `domain`.
-- Consecutive unmasked point ops are fused into one chain. `radius` is the
-- total border the stages consume. A compiled pipeline is returned unchanged.
-- @param spec table The pipeline description.
-- @return table The compiled pipeline.
function vnoise.compile_pipeline(spec)
  if getmetatable(spec) == Pipeline then
    return spec
  end
  if spec.source ~= nil and spec.domain ~= nil then
    error("vnoise: a pipeline cannot have both 'domain' and 'source' (source leaves carry their domains)", 2)
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
  local source = spec.source ~= nil and vnoise.compile_source(spec.source) or nil
  return setmetatable(
    { domain = vnoise.compile_domain(spec.domain), source = source, stages = stages, radius = radius },
    Pipeline
  )
end

-- Runs a compiled pipeline's stages on `cur` (sw x sh, its cell (0, 0) at
-- absolute cell (ac0, ar0)), each kernel consuming its radius of apron; `alt`
-- is a scratch buffer of the same size. Values stay unclamped. Returns the
-- buffer holding the result (shrunk by the pipeline radius on every side).
local function runStages(state, p, cur, alt, sw, sh, ac0, ar0)
  for _, stage in ipairs(p.stages) do
    local m = stage.mask
    if stage.chain then
      local chain = stage.chain
      if m then
        ffi.copy(alt, cur, sw * sh * ffi.sizeof("float"))
      end
      lib.vnoise_map_buffer(cur, sw * sh, chain.ops, chain.n, chain.data, 0)
      if m then
        lib.vnoise_mask_blend(cur, sw, sh, alt, sw, ac0, ar0, m.mask)
      end
    else
      local r = stage.radius
      local nw, nh = sw - 2 * r, sh - 2 * r
      stage.run(cur, sw, sh, alt, ac0, ar0, state)
      if m then
        lib.vnoise_mask_blend(alt, nw, nh, cur + r * sw + r, sw, ac0 + r, ar0 + r, m.mask)
      end
      cur, alt = alt, cur
      sw, sh, ac0, ar0 = nw, nh, ac0 + r, ar0 + r
    end
  end
  return cur
end

--- Evaluates a pipeline for cells `(c0 .. c0 + w - 1, r0 .. r0 + h - 1)`.
-- The noise is sampled through the pipeline's domain over the block grown by
-- `pipeline.radius` on every side (the apron; from the pipeline's source
-- tree when it has one, then `kind` may be nil), the stages run in order on
-- unclamped values (each kernel shrinks the buffer by twice its radius), and
-- the result is clamped to 0..1 unless `opts.clamp` is false. Every cell's
-- value depends only on its absolute index, so blocks tile seamlessly.
-- @param state table A state from `vnoise.new`.
-- @param kind string|nil Any sampler kind (see `fill_domain`; non-classic kinds read `opts.jitter`
--   and `opts.damping`), ignored with a source.
-- @param pipeline table A pipeline description or compiled pipeline.
-- @param opts table c0, r0 (default 0), w, h (default 256), ox, oy, freq, octaves, lac, gain, base,
--   out (optional float[w*h]), clamp (default true).
-- @return cdata The float[w*h] buffer.
function vnoise.fill_pipeline(state, kind, pipeline, opts)
  local p = vnoise.compile_pipeline(pipeline)
  if not p.source then
    modeOf(kind) -- raises for an unknown kind
  end
  local w, h = opts.w or 256, opts.h or 256
  local c0, r0 = opts.c0 or 0, opts.r0 or 0
  local rem = p.radius -- apron still around the current buffer
  local sw, sh = w + 2 * rem, h + 2 * rem
  local cur = ffi.new("float[?]", sw * sh)
  local alt = ffi.new("float[?]", sw * sh)
  local sp = not p.source and fillSampler(kind, opts, 2)
  if p.source then
    vnoise.fill_source(state, p.source, { c0 = c0 - rem, r0 = r0 - rem, w = sw, h = sh, out = cur })
  elseif sp then
    lib.vnoise_fill_sampler(state.s, sp, cur, c0 - rem, r0 - rem, sw, sh, domainFor(p.domain, opts, kind))
  else
    lib.vnoise_fill_domain(
      state.s,
      classicSampler(kind, opts, 2),
      cur,
      c0 - rem,
      r0 - rem,
      sw,
      sh,
      domainFor(p.domain, opts)
    )
  end
  cur = runStages(state, p, cur, alt, sw, sh, c0 - rem, r0 - rem)
  local out = opts.out or ffi.new("float[?]", w * h)
  ffi.copy(out, cur, w * h * ffi.sizeof("float"))
  if opts.clamp ~= false then
    lib.vnoise_map_buffer(out, w * h, nil, 0, nil, 1)
  end
  return out
end

-- Samplers --------------------------------------------------------------------

-- Folds a stride and a cell origin into a domain's affine map, so a native
-- fill over cells (0 .. w - 1, 0 .. h - 1) samples the absolute cells
-- (c0 + i * stride, r0 + j * stride).
local function stridedDomain(d, c0, r0, stride)
  local m = d.m
  local nd = ffi.new("vnoise_domain_t", d)
  nd.m[0], nd.m[1], nd.m[2] = m[0] * stride, m[1] * stride, m[0] * c0 + m[1] * r0 + m[2]
  nd.m[3], nd.m[4], nd.m[5] = m[3] * stride, m[4] * stride, m[3] * c0 + m[4] * r0 + m[5]
  return nd
end

--- Fills cells `(c0 .. c0 + w - 1, r0 .. r0 + h - 1)` with a sampler through
-- a domain. Kinds: "fbm", "ridge", "turb" (as `fill_domain`), "cell_f1",
-- "cell_f2", "cell_edge", "cell_value" (cellular noise, values in 0..1) and
-- "damped" (derivative-damped fBm).
-- @param state table A state from `vnoise.new`.
-- @param spec table `{ kind, base, octaves (6), lac (2), gain (0.5), jitter (1), damping (1) }`.
-- @param opts table|nil c0, r0 (0), w, h (256), freq (0.01), ox, oy, domain, out, and stride (1:
--   buffer cell (i, j) is cell (c0 + i * stride, r0 + j * stride)).
-- @return cdata The float[w*h] buffer.
function vnoise.fill_sampler(state, spec, opts)
  opts = opts or {}
  local sp = samplerStruct(spec, 2)
  local w, h = opts.w or 256, opts.h or 256
  local out = opts.out or ffi.new("float[?]", w * h)
  local d = domainFor(vnoise.compile_domain(opts.domain), opts, spec.kind)
  local c0, r0, stride = opts.c0 or 0, opts.r0 or 0, opts.stride or 1
  if stride ~= 1 then
    d, c0, r0 = stridedDomain(d, c0, r0, stride), 0, 0
  end
  lib.vnoise_fill_sampler(state.s, sp, out, c0, r0, w, h, d)
  return out
end

-- Source trees ----------------------------------------------------------------

-- Marks a compiled source node.
local Source = {}
-- Marks a terrain plan object.
local Plan = {}
Plan.__index = Plan

local COMBINE = { set = 0, add = 1, mul = 2, min = 3, max = 4, sub = 5, abs = 6, pow = 7 }
local TERRAIN_OUTPUTS = { elevation = true, river = true, lake = true, flow = true, channel_distance = true }

local compileNode

-- Compiles the children spec[first .. #spec] of a combinator.
local function children(spec, first, path, min, max)
  local list = {}
  for k = first, #spec do
    list[#list + 1] = compileNode(spec[k], path .. "." .. spec[1] .. "[" .. (k - first + 1) .. "]")
  end
  if #list < min or (max and #list > max) then
    local want = max == min and tostring(min) or (max and (min .. ".." .. max) or ("at least " .. min))
    error(("vnoise: source node '%s' at %s needs %s children, got %d"):format(spec[1], path, want, #list), 0)
  end
  return list
end

-- Builders of the non-sampler nodes: (spec, path) -> node.
local SOURCE_NODES = {
  const = function(spec, path)
    if type(spec[2]) ~= "number" then
      error("vnoise: source node 'const' at " .. path .. " needs a number", 0)
    end
    return { t = "const", v = spec[2] }
  end,
  mask = function(spec, path)
    if type(spec[2]) ~= "table" then
      error("vnoise: source node 'mask' at " .. path .. " needs a mask spec", 0)
    end
    return { t = "mask", mask = vnoise.compile_mask(spec[2]) }
  end,
  pipeline = function(spec, path)
    if type(spec[2]) ~= "table" then
      error("vnoise: source node 'pipeline' at " .. path .. " needs a pipeline spec", 0)
    end
    local p = vnoise.compile_pipeline(spec[2])
    local kind = spec.kind or (not p.source and "fbm" or nil)
    if kind ~= nil and not MODES[kind] then
      error("vnoise: source node 'pipeline' at " .. path .. " has an unknown kind '" .. tostring(kind) .. "'", 0)
    end
    return {
      t = "pipeline",
      pipeline = p,
      kind = kind,
      state = spec.seed and vnoise.new(spec.seed) or nil,
      opts = {
        freq = spec.freq,
        ox = spec.ox,
        oy = spec.oy,
        octaves = spec.octaves,
        lac = spec.lac,
        gain = spec.gain,
        base = spec.base,
      },
    }
  end,
  plan = function(spec, path)
    if getmetatable(spec[2]) ~= Plan then
      error("vnoise: source node 'plan' at " .. path .. " needs a terrain plan", 0)
    end
    local output = spec.output or "elevation"
    if not TERRAIN_OUTPUTS[output] then
      error("vnoise: source node 'plan' at " .. path .. " has an unknown output '" .. tostring(output) .. "'", 0)
    end
    return { t = "plan", plan = spec[2], output = output }
  end,
  add = function(spec, path)
    local list = children(spec, 2, path, 1)
    local weights = {}
    for k = 1, #list do
      local w = spec.weights and spec.weights[k] or 1
      if type(w) ~= "number" then
        error("vnoise: source node 'add' at " .. path .. " has a non-numeric weight", 0)
      end
      weights[k] = w
    end
    return { t = "add", children = list, weights = weights }
  end,
  mul = function(spec, path)
    return { t = "mul", children = children(spec, 2, path, 1) }
  end,
  min = function(spec, path)
    return { t = "min", children = children(spec, 2, path, 1) }
  end,
  max = function(spec, path)
    return { t = "max", children = children(spec, 2, path, 1) }
  end,
  sub = function(spec, path)
    return { t = "sub", children = children(spec, 2, path, 2, 2) }
  end,
  abs = function(spec, path)
    return { t = "abs", children = children(spec, 2, path, 1, 1) }
  end,
  pow = function(spec, path)
    local e = spec[3]
    if type(e) ~= "number" then
      error("vnoise: source node 'pow' at " .. path .. " needs a numeric exponent", 0)
    end
    return { t = "pow", children = { compileNode(spec[2], path .. ".pow[1]") }, e = e }
  end,
  lerp = function(spec, path)
    return { t = "lerp", children = children(spec, 2, path, 3, 3) }
  end,
}

compileNode = function(spec, path)
  if getmetatable(spec) == Source then
    return spec
  end
  if type(spec) ~= "table" then
    error("vnoise: source at " .. path .. " must be a table, got " .. type(spec), 0)
  end
  local tag = spec[1]
  local node
  local kind = spec.kind
  if type(tag) == "string" and SAMPLER_KINDS[tag] then
    kind, tag = tag, nil
  end
  if tag == nil then
    if kind == nil then
      error("vnoise: source at " .. path .. " has no node name or sampler kind", 0)
    end
    if not SAMPLER_KINDS[kind] then
      error("vnoise: unknown sampler kind '" .. tostring(kind) .. "' at " .. path, 0)
    end
    node = {
      t = "sampler",
      sp = samplerStruct({
        kind = kind,
        base = spec.base,
        octaves = spec.octaves,
        lac = spec.lac,
        gain = spec.gain,
        jitter = spec.jitter,
        damping = spec.damping,
        image = spec.image,
        wrap = spec.wrap,
        filter = spec.filter,
      }, 1),
      domain = vnoise.compile_domain(spec.domain),
      freq = spec.freq or (kind == "image" and 1 or nil),
      ox = spec.ox,
      oy = spec.oy,
      state = spec.seed and vnoise.new(spec.seed) or nil,
    }
  else
    local builder = type(tag) == "string" and SOURCE_NODES[tag]
    if not builder then
      error("vnoise: unknown source node '" .. tostring(tag) .. "' at " .. path, 0)
    end
    node = builder(spec, path)
  end
  if spec.ops then
    node.chain = vnoise.compile_ops(spec.ops)
  end
  return setmetatable(node, Source)
end

--- Compiles a source tree: sampler leaves (`{ "fbm", freq = ..., ... }` or
-- `{ kind = "fbm", ... }`, with optional `domain`, `seed` (own state) and
-- `ops`), `{ "const", v }`, `{ "mask", <mask spec> }` (the mask weight),
-- `{ "pipeline", <pipeline spec>, kind = ..., <sampler opts> }`,
-- `{ "plan", plan, output = name }`, and the combinators `add` (with
-- `weights`), `mul`, `min`, `max`, `sub`, `abs`, `pow` (`{ "pow", a, e }`) and
-- `lerp` (`{ "lerp", a, b, t }`). Any node may carry `ops` (a point op chain
-- applied after it). Values flow unclamped. A compiled source is returned
-- unchanged.
-- @param spec table The source description.
-- @return table The compiled source.
function vnoise.compile_source(spec)
  local ok, res = pcall(compileNode, spec, "source")
  if not ok then
    error(res, 2)
  end
  return res
end

-- Evaluates a node cell by cell (w = h = 1 calls), for leaves that cannot
-- sample with a stride (pipelines, masks, plans) when a stride is asked.
local function perCell(fill, c0, r0, w, h, stride, out)
  local one = ffi.new("float[1]")
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      fill(c0 + i * stride, r0 + j * stride, one)
      out[j * w + i] = one[0]
    end
  end
end

local evalNode

local function evalLeafMask(node, c0, r0, w, h, out)
  local n = w * h
  for k = 0, n - 1 do
    out[k] = 1
  end
  local zero = ffi.new("float[?]", n)
  lib.vnoise_mask_blend(out, w, h, zero, w, c0, r0, node.mask.mask)
end

-- Fills `out` (w * h) with node `node` over the strided block of cells.
evalNode = function(node, state, c0, r0, w, h, stride, out)
  local n = w * h
  local t = node.t
  if t == "sampler" then
    local d = domainFor(node.domain, node)
    local cc, rr = c0, r0
    if stride ~= 1 then
      d, cc, rr = stridedDomain(d, c0, r0, stride), 0, 0
    end
    lib.vnoise_fill_sampler((node.state or state).s, node.sp, out, cc, rr, w, h, d)
  elseif t == "const" then
    for k = 0, n - 1 do
      out[k] = node.v
    end
  elseif t == "mask" then
    if stride == 1 then
      evalLeafMask(node, c0, r0, w, h, out)
    else
      perCell(function(c, r, one)
        evalLeafMask(node, c, r, 1, 1, one)
      end, c0, r0, w, h, stride, out)
    end
  elseif t == "pipeline" then
    local st = node.state or state
    local function run(c, r, ww, hh, dst)
      local o = { c0 = c, r0 = r, w = ww, h = hh, out = dst, clamp = false }
      for key, v in pairs(node.opts) do
        o[key] = v
      end
      vnoise.fill_pipeline(st, node.kind, node.pipeline, o)
    end
    if stride == 1 then
      run(c0, r0, w, h, out)
    else
      perCell(function(c, r, one)
        run(c, r, 1, 1, one)
      end, c0, r0, w, h, stride, out)
    end
  elseif t == "plan" then
    local function run(c, r, ww, hh, dst)
      vnoise.fill_terrain(state, node.plan, {
        c0 = c,
        r0 = r,
        w = ww,
        h = hh,
        outputs = { node.output },
        out = { [node.output] = dst },
      })
    end
    if stride == 1 then
      run(c0, r0, w, h, out)
    else
      perCell(function(c, r, one)
        run(c, r, 1, 1, one)
      end, c0, r0, w, h, stride, out)
    end
  else
    local kids = node.children
    evalNode(kids[1], state, c0, r0, w, h, stride, out)
    if t == "add" then
      if node.weights[1] ~= 1 then
        lib.vnoise_combine(out, out, n, COMBINE.set, node.weights[1])
      end
    elseif t == "abs" then
      lib.vnoise_combine(out, nil, n, COMBINE.abs, 0)
    elseif t == "pow" then
      lib.vnoise_combine(out, nil, n, COMBINE.pow, node.e)
    end
    if #kids > 1 then
      local tmp = ffi.new("float[?]", n)
      if t == "lerp" then
        local tt = ffi.new("float[?]", n)
        evalNode(kids[2], state, c0, r0, w, h, stride, tmp)
        evalNode(kids[3], state, c0, r0, w, h, stride, tt)
        lib.vnoise_combine_lerp(out, tmp, tt, n)
      else
        for k = 2, #kids do
          evalNode(kids[k], state, c0, r0, w, h, stride, tmp)
          lib.vnoise_combine(out, tmp, n, COMBINE[t], t == "add" and node.weights[k] or 1)
        end
      end
    end
  end
  local chain = node.chain
  if chain then
    lib.vnoise_map_buffer(out, n, chain.ops, chain.n, chain.data, 0)
  end
end

--- Evaluates a source tree over cells `(c0 .. c0 + w - 1, r0 .. r0 + h - 1)`
-- (or every `stride`-th cell). Every value depends only on its absolute
-- cell, so blocks tile.
-- @param state table A state from `vnoise.new` (leaves with `seed` use their own).
-- @param source table A source description or compiled source.
-- @param opts table|nil c0, r0 (0), w, h (256), out, stride (1), clamp (false: clamp to 0..1).
-- @return cdata The float[w*h] buffer.
function vnoise.fill_source(state, source, opts)
  opts = opts or {}
  local src = vnoise.compile_source(source)
  local w, h = opts.w or 256, opts.h or 256
  local out = opts.out or ffi.new("float[?]", w * h)
  evalNode(src, state, opts.c0 or 0, opts.r0 or 0, w, h, opts.stride or 1, out)
  if opts.clamp then
    lib.vnoise_map_buffer(out, w * h, nil, 0, nil, 1)
  end
  return out
end

-- Presets ---------------------------------------------------------------------

vnoise.presets = {}

--- A continent: warped fBm in 0..1, offset by `land - 0.5`, multiplied by a
-- feathered rectangle over the extent so land falls to 0 toward the border.
-- @param opts table|nil width, height (extent in cells, 1024), freq (2.5 / max side), octaves (6),
--   coast (0.15 of the shorter side), land (0.5), warp (cells, 0.08 of the shorter side), seed.
-- @return table A source spec with values in 0..1.
function vnoise.presets.continent(opts)
  opts = opts or {}
  local w, h = opts.width or 1024, opts.height or 1024
  local size = math.min(w, h)
  local freq = opts.freq or 2.5 / math.max(w, h)
  return {
    "mul",
    {
      "add",
      {
        "fbm",
        freq = freq,
        octaves = opts.octaves or 6,
        seed = opts.seed,
        domain = { warp = { amp = opts.warp or size * 0.08, freq = freq * 1.5, octaves = 3 } },
        ops = { { "remap", -0.7, 0.7 } },
      },
      { "const", (opts.land or 0.5) - 0.5 },
    },
    { "mask", { "rect", 0, 0, w - 1, h - 1, feather = math.max(1, (opts.coast or 0.15) * size) } },
    ops = { { "clamp", 0, 1 } },
  }
end

--- Mountain belts: ridged noise multiplied by a band mask along the warped
-- edges of a low-frequency cellular lattice, so ridges form long chains.
-- @param opts table|nil freq (1/96), belt_freq (1/700), octaves (5), width (belt width as a
--   cell_edge value, 0.25), sharpness (1.5), jitter (1), seed.
-- @return table A source spec with values in 0..1.
function vnoise.presets.mountain_belts(opts)
  opts = opts or {}
  local belt_freq = opts.belt_freq or 1 / 700
  return {
    "mul",
    { "ridge", freq = opts.freq or 1 / 96, octaves = opts.octaves or 5, seed = opts.seed },
    {
      "cell_edge",
      freq = belt_freq,
      octaves = 1,
      jitter = opts.jitter or 1,
      seed = opts.seed and opts.seed + 1,
      domain = { warp = { amp = 0.3 / belt_freq, freq = belt_freq * 2, octaves = 3 } },
      ops = { { "smoothstep", 0, opts.width or 0.25 }, { "invert" }, { "gamma", opts.sharpness or 1.5 } },
    },
    ops = { { "clamp", 0, 1 } },
  }
end

-- Terrain plans ---------------------------------------------------------------

local OUTLETS = { edges = 0, sea = 1, both = 2 }
local MOUTHS = { [0] = "sea", [1] = "edge", [2] = "river" }
local GRIDS = { height = 0, filled = 1, flow = 2, lake = 3, receiver = 4, outlet = 5 }

-- Reads a numeric option with a default and an inclusive range.
local function numOpt(t, key, default, lo, hi, label, integer)
  local v = t and t[key]
  if v == nil then
    return default
  end
  if type(v) ~= "number" or (integer and v ~= math.floor(v)) or (lo and v < lo) or (hi and v > hi) then
    error(
      ("vnoise: terrain_plan option '%s' must be %s%s, got %s"):format(
        label,
        integer and "an integer" or "a number",
        (lo or hi) and (" in " .. tostring(lo or "-inf") .. ".." .. tostring(hi or "inf")) or "",
        tostring(v)
      ),
      4
    )
  end
  return v
end

--- Builds a terrain plan over a finite extent: the `elevation` (and optional
-- `uplift`) source is sampled at the macro nodes (every `macro_cell` cells),
-- eroded (implicit stream-power with uplift and diffusion), drained
-- (priority-flood, D8, accumulation, lakes) and turned into a river network.
-- The plan is immutable; its native memory is released by the collector.
-- @param state table A state from `vnoise.new` (sources and the meander warp use its seed).
-- @param spec table width, height (cells, 1..65536), macro_cell (64), elevation (source, required),
--   uplift (source), sea_level (0), outlets ("both" | "edges" | "sea"),
--   erosion = { iterations (60), reroute (4), k (0.01), m (0.5), dt (1), uplift (0.002), diffusion (0.01, <= 0.25) },
--   rivers = { min_flow (32 nodes), width (2), max_width (24), depth (0.004), max_depth (0.03),
--     lake_depth (0.002), smooth (2), valley (6), valley_min (8), valley_shape (1), bank (1),
--     meander_amp (0), meander_freq (1/64), distance_range (64) },
--   detail = { source (source spec, values in -1..1), amplitude (0.05), valley_damping (0.7) }.
-- @return table The plan.
function vnoise.terrain_plan(state, spec)
  if type(spec) ~= "table" then
    error("vnoise: terrain_plan needs a spec table", 2)
  end
  if spec.elevation == nil then
    error("vnoise: terrain_plan needs 'elevation' (a source spec)", 2)
  end
  local width = numOpt(spec, "width", nil, 1, 65536, "width", true)
  local height = numOpt(spec, "height", nil, 1, 65536, "height", true)
  if not width or not height then
    error("vnoise: terrain_plan needs 'width' and 'height' (cells)", 2)
  end
  local mc = numOpt(spec, "macro_cell", 64, 4, nil, "macro_cell", true)
  local mw, mh = math.ceil(width / mc) + 1, math.ceil(height / mc) + 1
  if mw * mh > 1048576 then
    error(("vnoise: terrain_plan macro grid %d x %d exceeds 1048576 nodes; raise macro_cell"):format(mw, mh), 2)
  end
  local outlets = OUTLETS[spec.outlets or "both"]
  if not outlets then
    error("vnoise: terrain_plan option 'outlets' must be 'edges', 'sea' or 'both'", 2)
  end
  local er, rv, dt = spec.erosion or {}, spec.rivers or {}, spec.detail or {}

  local p = ffi.new("vnoise_plan_params_t")
  p.width, p.height, p.macro_cell = width, height, mc
  p.sea_level = numOpt(spec, "sea_level", 0, 0, 1, "sea_level")
  p.outlets = outlets
  p.seed = state.s.seed
  p.erosion_iterations = numOpt(er, "iterations", 60, 0, nil, "erosion.iterations", true)
  p.erosion_reroute = numOpt(er, "reroute", 4, 1, nil, "erosion.reroute", true)
  p.erosion_k = numOpt(er, "k", 0.01, 0, nil, "erosion.k")
  p.erosion_m = numOpt(er, "m", 0.5, 0, nil, "erosion.m")
  p.erosion_dt = numOpt(er, "dt", 1, 0, nil, "erosion.dt")
  p.erosion_uplift = numOpt(er, "uplift", 0.002, nil, nil, "erosion.uplift")
  p.erosion_diffusion = numOpt(er, "diffusion", 0.01, 0, 0.25, "erosion.diffusion")
  p.river_min_flow = numOpt(rv, "min_flow", 32, 1, nil, "rivers.min_flow")
  p.river_width = numOpt(rv, "width", 2, 0.001, nil, "rivers.width")
  p.river_max_width = numOpt(rv, "max_width", math.max(24, p.river_width), p.river_width, nil, "rivers.max_width")
  p.river_depth = numOpt(rv, "depth", 0.004, 0, nil, "rivers.depth")
  p.river_max_depth = numOpt(rv, "max_depth", 0.03, 0, nil, "rivers.max_depth")
  p.lake_depth = numOpt(rv, "lake_depth", 0.002, 0, nil, "rivers.lake_depth")
  p.river_smooth = numOpt(rv, "smooth", 2, 0, 8, "rivers.smooth", true)
  p.valley = numOpt(rv, "valley", 6, 0, nil, "rivers.valley")
  p.valley_min = numOpt(rv, "valley_min", 8, 0, nil, "rivers.valley_min")
  p.valley_shape = numOpt(rv, "valley_shape", 1, 0.01, nil, "rivers.valley_shape")
  p.bank = numOpt(rv, "bank", 1, 0.001, nil, "rivers.bank")
  p.meander_amp = numOpt(rv, "meander_amp", 0, 0, nil, "rivers.meander_amp")
  p.meander_freq = numOpt(rv, "meander_freq", 1 / 64, 0, nil, "rivers.meander_freq")
  p.distance_range = numOpt(rv, "distance_range", 64, 0.001, nil, "rivers.distance_range")
  p.detail_amplitude = numOpt(dt, "amplitude", 0.05, 0, nil, "detail.amplitude")
  p.detail_valley_damping = numOpt(dt, "valley_damping", 0.7, 0, 1, "detail.valley_damping")

  local detail = dt.source ~= nil and vnoise.compile_source(dt.source) or nil
  local hbuf = vnoise.fill_source(state, spec.elevation, { w = mw, h = mh, stride = mc })
  local ubuf = spec.uplift ~= nil and vnoise.fill_source(state, spec.uplift, { w = mw, h = mh, stride = mc }) or nil
  local handle = lib.vnoise_plan_create(p, hbuf, ubuf)
  if handle == nil then
    error("vnoise: terrain_plan parameters were rejected by the native library", 2)
  end
  return setmetatable({
    handle = ffi.gc(handle, lib.vnoise_plan_destroy),
    width = width,
    height = height,
    macro_cell = mc,
    mw = mw,
    mh = mh,
    sea_level = p.sea_level,
    detail_source = detail,
  }, Plan)
end

--- Returns a copy of a macro grid (mw * mh floats, node (i, j) at j * mw + i):
-- "height" (eroded), "filled", "flow" (accumulation in nodes), "lake" (0/1),
-- "receiver" (node index, -1 for outlets) or "outlet" (0/1).
-- @param name string The grid name.
-- @return cdata float[mw * mh].
function Plan:grid(name)
  local which = GRIDS[name] or error("vnoise: unknown plan grid '" .. tostring(name) .. "'", 2)
  local out = ffi.new("float[?]", self.mw * self.mh)
  lib.vnoise_plan_grid(self.handle, which, out)
  return out
end

--- Returns the river network as a list of polylines `{ points = { x1, y1, ...
-- }, flow = {...}, width = {...}, bed = {...}, mouth = "sea" | "edge" |
-- "river" }` in absolute cells (cached; do not modify).
-- @return table The polylines.
function Plan:rivers()
  if self._rivers then
    return self._rivers
  end
  local info = ffi.new("int[4]")
  lib.vnoise_plan_info(self.handle, info, info + 1, info + 2, info + 3)
  local np, nv = info[2], info[3]
  local start, count, mouth = ffi.new("int[?]", np + 1), ffi.new("int[?]", np + 1), ffi.new("int[?]", np + 1)
  local x, y = ffi.new("float[?]", nv + 1), ffi.new("float[?]", nv + 1)
  local fl, wd, bd = ffi.new("float[?]", nv + 1), ffi.new("float[?]", nv + 1), ffi.new("float[?]", nv + 1)
  lib.vnoise_plan_rivers(self.handle, ffi.new("vnoise_rivers_out_t", { start, count, mouth, x, y, fl, wd, bd }))
  local list = {}
  for k = 0, np - 1 do
    local poly = { points = {}, flow = {}, width = {}, bed = {}, mouth = MOUTHS[mouth[k]] }
    for v = start[k], start[k] + count[k] - 1 do
      poly.points[#poly.points + 1] = x[v]
      poly.points[#poly.points + 1] = y[v]
      poly.flow[#poly.flow + 1] = fl[v]
      poly.width[#poly.width + 1] = wd[v]
      poly.bed[#poly.bed + 1] = bd[v]
    end
    list[k + 1] = poly
  end
  self._rivers = list
  return list
end

--- Nearest river at cell (c, r), after the meander warp.
-- @return number|nil distance (cells), bed, width, flow, polyline index (1-based); nil when no
--   river is indexed near the cell.
function Plan:query(c, r)
  local out = ffi.new("float[5]")
  if lib.vnoise_plan_query(self.handle, c, r, out) == 0 then
    return nil
  end
  return out[0], out[1], out[2], out[3], out[4] + 1
end

--- Fills a block of cells from a terrain plan with several outputs, all in
-- 0..1: "elevation" (macro height + detail, rivers carved), "river"
-- (channel mask), "lake", "flow" (log accumulation) and "channel_distance".
-- Every value depends only on its absolute cell, so blocks tile.
-- @param state table The state for the plan's detail source.
-- @param plan table A plan from `vnoise.terrain_plan`.
-- @param opts table|nil c0, r0 (0), w, h (256), outputs ({ "elevation" }), out ({ name = float[w*h] }).
-- @return table Output name -> float[w*h].
function vnoise.fill_terrain(state, plan, opts)
  opts = opts or {}
  if getmetatable(plan) ~= Plan then
    error("vnoise: fill_terrain needs a terrain plan", 2)
  end
  local w, h = opts.w or 256, opts.h or 256
  local c0, r0 = opts.c0 or 0, opts.r0 or 0
  local res = {}
  for _, name in ipairs(opts.outputs or { "elevation" }) do
    if not TERRAIN_OUTPUTS[name] then
      error("vnoise: unknown terrain output '" .. tostring(name) .. "'", 2)
    end
    res[name] = opts.out and opts.out[name] or ffi.new("float[?]", w * h)
  end
  local detail
  if plan.detail_source and (res.elevation or res.lake) then
    detail = vnoise.fill_source(state, plan.detail_source, { c0 = c0, r0 = r0, w = w, h = h })
  end
  local outs = ffi.new("vnoise_terrain_out_t")
  outs.elevation = res.elevation
  outs.river = res.river
  outs.lake = res.lake
  outs.flow = res.flow
  outs.channel_distance = res.channel_distance
  lib.vnoise_plan_fill(plan.handle, c0, r0, w, h, detail, outs)
  return res
end

-- Matrix operations ------------------------------------------------------------

ffi.cdef([[
typedef struct {
    int shape;
    int blend;
    float cx, cy;
    float rx, ry;
    float angle;
    float height;
    float roughness;
    unsigned long long seed;
    float p[4];
} vnoise_stamp_t;
void vnoise_stamp(float* m, int w, int h, const vnoise_stamp_t* st);

typedef struct {
    int kind;
    int blend;
    float height;
    float width;
    float taper;
    float sharpness;
    float peakiness;
    float spurs;
    float roughness;
    float reach;
    int side;
    int smooth;
    unsigned long long seed;
} vnoise_path_t;
void vnoise_path_feature(float* m, int w, int h, const float* points, int n, const vnoise_path_t* pf);

typedef struct {
    float sea_level;
    float width0, width_growth, max_width;
    float depth0, depth_growth, max_depth;
    float valley, valley_shape, bank;
    int breach_radius;
    int smooth;
    int max_length;
} vnoise_river_t;
int vnoise_river(float* height, int w, int h, float sx, float sy, const vnoise_river_t* rp,
                 float* mask, float* out_points, int max_points);
int vnoise_river_sources(const float* height, int w, int h, int count, float min_elev,
                         float min_spacing, unsigned long long seed, float* out_xy);

typedef struct {
    int iterations;
    int reroute;
    float k, m, dt;
    float uplift_rate;
    float diffusion;
    float sea_level;
    int outlets;
    int max_cells;
} vnoise_erosion_t;
void vnoise_erode_matrix(float* m, int w, int h, const vnoise_erosion_t* ep, const float* uplift,
                         float* flow_out);
void vnoise_resample(const float* src, int sw, int sh, float* dst, int dw, int dh, int mode);
]])

local BLENDS = { add = 0, sub = 1, max = 2, min = 3, replace = 4 }
local STAMP_SHAPES = { dome = 0, cone = 1, crater = 2, mesa = 3, basin = 4 }
local PATH_KINDS = { ridge = 0, valley = 1, escarpment = 2 }
local RESAMPLE_MODES = { bilinear = 0, bicubic = 1 }
local MATRIX_OUTLETS = { edges = 0, sea = 1, both = 2 }

-- Reads a named choice, raising an error naming an unknown value.
local function choice(map, value, default, what)
  local v = map[value == nil and default or value]
  if v == nil then
    error("vnoise: unknown " .. what .. " '" .. tostring(value) .. "'", 3)
  end
  return v
end

-- Reads an optional finite number.
local function num(t, key, default)
  local v = t[key]
  if v == nil then
    return default
  end
  if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
    error("vnoise: '" .. key .. "' must be a finite number, got " .. tostring(v), 3)
  end
  return v
end

--- Allocates a matrix (row-major `float[w * h]`), optionally filled with a
-- constant. Matrix operations take it with explicit `w` and `h`.
-- @param w number Columns.
-- @param h number Rows.
-- @param fill number|nil Initial value (default 0).
-- @return cdata The matrix.
function vnoise.matrix(w, h, fill)
  local m = ffi.new("float[?]", w * h)
  if fill and fill ~= 0 then
    for k = 0, w * h - 1 do
      m[k] = fill
    end
  end
  return m
end

--- Stamps a point feature into a matrix. Positions and radii are in cells
-- (cell (i, j) has its center at (i + 0.5, j + 0.5)); values written are
-- clamped to 0..1.
-- @param m cdata The matrix.
-- @param w number Columns.
-- @param h number Rows.
-- @param spec table shape ("dome", "cone", "crater", "mesa", "basin"), blend ("add", "sub",
--   "max", "min", "replace"; default "add"), cx, cy, rx, ry (default rx), angle (degrees),
--   height (0.3), roughness (0), seed (0), crater (cone: crater radius fraction, 0),
--   rim (crater: rim width fraction, 0.3), floor (crater: floor height fraction, 0.2),
--   slope (mesa: slope width fraction, 0.3).
function vnoise.stamp(m, w, h, spec)
  local st = ffi.new("vnoise_stamp_t")
  st.shape = choice(STAMP_SHAPES, spec.shape, "dome", "stamp shape")
  st.blend = choice(BLENDS, spec.blend, "add", "blend")
  st.cx, st.cy = num(spec, "cx", w / 2), num(spec, "cy", h / 2)
  st.rx = num(spec, "rx", math.min(w, h) / 8)
  st.ry = num(spec, "ry", st.rx)
  st.angle = num(spec, "angle", 0)
  st.height = num(spec, "height", 0.3)
  st.roughness = num(spec, "roughness", 0)
  st.seed = spec.seed or 0
  if st.shape == STAMP_SHAPES.cone then
    st.p[0] = num(spec, "crater", 0)
  elseif st.shape == STAMP_SHAPES.crater then
    st.p[0], st.p[1] = num(spec, "rim", 0.3), num(spec, "floor", 0.2)
  elseif st.shape == STAMP_SHAPES.mesa then
    st.p[0] = num(spec, "slope", 0.3)
  end
  lib.vnoise_stamp(m, w, h, st)
end

--- Draws a feature along a polyline into a matrix.
-- @param m cdata The matrix.
-- @param w number Columns.
-- @param h number Rows.
-- @param points table Lua array `{ x1, y1, x2, y2, ... }` (at least two points), in cells.
-- @param spec table kind ("ridge", "valley", "escarpment"), blend (default "sub" for valleys,
--   "add" otherwise), height (0.3), width (cells, 1/8 of the shorter side), taper (0.2),
--   sharpness (1), peakiness (0.5 for ridges, else 0), spurs (cells, 0), roughness (0),
--   side (+1/-1, escarpments), reach (escarpments, 4 * width), smooth (2), seed (0).
function vnoise.path_feature(m, w, h, points, spec)
  local n = math.floor(#points / 2)
  if n < 2 then
    return
  end
  local pf = ffi.new("vnoise_path_t")
  pf.kind = choice(PATH_KINDS, spec.kind, "ridge", "path kind")
  pf.blend = choice(BLENDS, spec.blend, pf.kind == PATH_KINDS.valley and "sub" or "add", "blend")
  pf.height = num(spec, "height", 0.3)
  pf.width = num(spec, "width", math.min(w, h) / 8)
  pf.taper = num(spec, "taper", 0.2)
  pf.sharpness = num(spec, "sharpness", 1)
  pf.peakiness = num(spec, "peakiness", pf.kind == PATH_KINDS.ridge and 0.5 or 0)
  pf.spurs = num(spec, "spurs", 0)
  pf.roughness = num(spec, "roughness", 0)
  pf.reach = num(spec, "reach", 0)
  pf.side = (spec.side or 1) < 0 and -1 or 1
  pf.smooth = spec.smooth or 2
  pf.seed = spec.seed or 0
  local pts = ffi.new("float[?]", 2 * n)
  for k = 1, 2 * n do
    pts[k - 1] = points[k]
  end
  lib.vnoise_path_feature(m, w, h, pts, n, pf)
end

--- Traces a river from a source down the slope, carving its channel into the
-- height matrix and writing the river mask (1 in the channel, 0.5 for a lake
-- where the river ends trapped).
-- @param height cdata The height matrix (modified).
-- @param w number Columns.
-- @param h number Rows.
-- @param sx number Source x in cells.
-- @param sy number Source y in cells.
-- @param spec table|nil sea_level (0), width0 (1.5), width_growth (0.01), max_width (8),
--   depth0 (0.004), depth_growth (0.00005), max_depth (0.03), valley (6), valley_shape (1),
--   bank (1), breach_radius (64), smooth (2), max_length (4 * (w + h)).
-- @param mask cdata|nil The river mask (allocated when nil).
-- @return table The traced points `{ x1, y1, ... }` (empty when nothing was traced).
-- @return cdata The mask.
function vnoise.river(height, w, h, sx, sy, spec, mask)
  spec = spec or {}
  mask = mask or vnoise.matrix(w, h)
  local rp = ffi.new("vnoise_river_t")
  rp.sea_level = num(spec, "sea_level", 0)
  rp.width0 = num(spec, "width0", 1.5)
  rp.width_growth = num(spec, "width_growth", 0.01)
  rp.max_width = num(spec, "max_width", 8)
  rp.depth0 = num(spec, "depth0", 0.004)
  rp.depth_growth = num(spec, "depth_growth", 0.00005)
  rp.max_depth = num(spec, "max_depth", 0.03)
  rp.valley = num(spec, "valley", 6)
  rp.valley_shape = num(spec, "valley_shape", 1)
  rp.bank = num(spec, "bank", 1)
  rp.breach_radius = spec.breach_radius or 64
  rp.smooth = spec.smooth or 2
  rp.max_length = spec.max_length or 4 * (w + h)
  local cap = 4 * rp.max_length + 8
  local out = ffi.new("float[?]", 2 * cap)
  local n = lib.vnoise_river(height, w, h, sx, sy, rp, mask, out, cap)
  local points = {}
  for k = 0, 2 * n - 1 do
    points[k + 1] = out[k]
  end
  return points, mask
end

--- Picks seeded river sources on cells at or above `min_elev`, weighted by
-- `height - min_elev`, at least `min_spacing` apart.
-- @param height cdata The height matrix.
-- @param w number Columns.
-- @param h number Rows.
-- @param spec table count (1), min_elev (0.5), min_spacing (cells, 1/10 of the shorter side), seed (0).
-- @return table `{ { x, y }, ... }` cell centers (possibly fewer than `count`).
function vnoise.river_sources(height, w, h, spec)
  spec = spec or {}
  local count = spec.count or 1
  local out = ffi.new("float[?]", 2 * math.max(count, 1))
  local n = lib.vnoise_river_sources(
    height,
    w,
    h,
    count,
    num(spec, "min_elev", 0.5),
    num(spec, "min_spacing", math.min(w, h) / 10),
    spec.seed or 0,
    out
  )
  local list = {}
  for k = 0, n - 1 do
    list[k + 1] = { out[2 * k], out[2 * k + 1] }
  end
  return list
end

--- Erodes a matrix in place (stream-power erosion and hillslope diffusion, as
-- in terrain plans). Above `max_cells` cells a downsample is eroded and the
-- upsampled height change is added.
-- @param m cdata The matrix (modified).
-- @param w number Columns.
-- @param h number Rows.
-- @param spec table|nil iterations (60), reroute (4), k (0.01), m (0.5), dt (1), uplift_rate
--   (0.002), diffusion (0.01, <= 0.25), sea_level (0), outlets ("both"), max_cells (262144),
--   uplift (optional matrix), flow (true to return the flow matrix).
-- @return cdata|nil The flow matrix (log-normalized accumulation in 0..1) when `spec.flow`.
function vnoise.erode(m, w, h, spec)
  spec = spec or {}
  local ep = ffi.new("vnoise_erosion_t")
  ep.iterations = spec.iterations or 60
  ep.reroute = spec.reroute or 4
  ep.k = num(spec, "k", 0.01)
  ep.m = num(spec, "m", 0.5)
  ep.dt = num(spec, "dt", 1)
  ep.uplift_rate = num(spec, "uplift_rate", 0.002)
  ep.diffusion = num(spec, "diffusion", 0.01)
  if ep.diffusion < 0 or ep.diffusion > 0.25 then
    error("vnoise: erosion 'diffusion' must be in 0..0.25", 2)
  end
  ep.sea_level = num(spec, "sea_level", 0)
  ep.outlets = choice(MATRIX_OUTLETS, spec.outlets, "both", "outlets")
  ep.max_cells = spec.max_cells or 262144
  local flow = spec.flow and vnoise.matrix(w, h) or nil
  lib.vnoise_erode_matrix(m, w, h, ep, spec.uplift, flow)
  return flow
end

--- Runs pipeline stages (point ops and kernels, with masks in matrix cells)
-- on an existing matrix, in place. The matrix is padded by the stages' radius
-- with clamped edges, so the result keeps its size and its edges are defined;
-- values are clamped to 0..1.
-- @param m cdata The matrix (modified).
-- @param w number Columns.
-- @param h number Rows.
-- @param stages table A stage list (as in `compile_pipeline`) or a compiled pipeline.
-- @param state table|nil A state for position-dependent stages (`gullies`; default seed 0).
function vnoise.apply_stages(m, w, h, stages, state)
  local p = getmetatable(stages) == Pipeline and stages or vnoise.compile_pipeline({ stages = stages })
  local R = p.radius
  local sw, sh = w + 2 * R, h + 2 * R
  local cur = ffi.new("float[?]", sw * sh)
  local alt = ffi.new("float[?]", sw * sh)
  for j = 0, sh - 1 do
    local sj = math.min(math.max(j - R, 0), h - 1)
    for i = 0, sw - 1 do
      local si = math.min(math.max(i - R, 0), w - 1)
      cur[j * sw + i] = m[sj * w + si]
    end
  end
  local res = runStages(state or vnoise.new(0), p, cur, alt, sw, sh, -R, -R)
  ffi.copy(m, res, w * h * ffi.sizeof("float"))
  lib.vnoise_map_buffer(m, w * h, nil, 0, nil, 1)
end

--- Resamples a matrix to another size by cell centers.
-- @param src cdata The source matrix.
-- @param sw number Source columns.
-- @param sh number Source rows.
-- @param dw number Target columns.
-- @param dh number Target rows.
-- @param mode string|nil "bilinear" (default) or "bicubic" (clamped Catmull-Rom).
-- @return cdata The new matrix.
function vnoise.resample(src, sw, sh, dw, dh, mode)
  local dst = ffi.new("float[?]", dw * dh)
  lib.vnoise_resample(src, sw, sh, dst, dw, dh, choice(RESAMPLE_MODES, mode, "bilinear", "resample mode"))
  return dst
end

-- Landform operations ----------------------------------------------------------

ffi.cdef([[
typedef struct {
    float amp;
    int filter;
    float freq;
    int octaves;
    float lac, gain;
    int base;
    int levels;
} vnoise_warp_t;
void vnoise_warp_matrix(const float* src, int w, int h, float* dst, const float* dx, const float* dy,
                        const float* strength, const vnoise_warp_t* wp);
void vnoise_warp_matrix_noise(const float* src, int w, int h, float* dst, const noise_state_t* s,
                              const vnoise_warp_t* wp);

typedef struct {
    int droplets;
    int lifetime;
    float inertia;
    float capacity, min_slope;
    float erode, deposit;
    float evaporation, gravity;
    int radius;
    float relief;
    float sea_level;
    unsigned long long seed;
} vnoise_hydraulic_t;
void vnoise_erode_hydraulic(float* m, int w, int h, const vnoise_hydraulic_t* hp, const float* hardness,
                            const float* rain, float* change_out);

typedef struct {
    int iterations;
    float talus;
    float rate;
    float relief;
} vnoise_thermal_t;
void vnoise_erode_thermal(float* m, int w, int h, const vnoise_thermal_t* tp, const float* hardness);

typedef struct {
    float threshold;
    int mode;
    float range;
    int edge;
} vnoise_distance_t;
void vnoise_distance_field(const float* m, int w, int h, float* out, const vnoise_distance_t* dp);

typedef struct {
    int mode;
    float relief;
    float range;
} vnoise_slope_t;
void vnoise_slope(const float* m, int w, int h, float* out, const vnoise_slope_t* sp);

typedef struct {
    int method;
    float exponent;
    int scale;
    float range;
    float sea_level;
    int outlets;
    float lake_depth;
} vnoise_flow_t;
typedef struct {
    float* flow;
    float* filled;
    float* lake;
} vnoise_flow_out_t;
void vnoise_flow(const float* m, int w, int h, const vnoise_flow_t* fp, const float* rain,
                 const vnoise_flow_out_t* out);
typedef struct {
    float relief;
    float epsilon;
    float range;
} vnoise_twi_t;
void vnoise_flow_twi(const float* m, int w, int h, const vnoise_flow_t* fp, const vnoise_twi_t* tp,
                     const float* rain, const vnoise_flow_out_t* out, float* twi);

typedef struct {
    float min_flow;
    float sea_level;
    int outlets;
    float width0, width_k, max_width;
    float depth0, depth_k, max_depth;
    float valley, valley_shape, bank;
    float lake_depth;
    int fill_lakes;
    int smooth;
    int min_length;
} vnoise_network_t;
typedef struct {
    float* mask;
    float* flow;
    int max_rivers, max_points;
    int* start;
    int* count;
    float* xy;
    float* width;
} vnoise_network_out_t;
int vnoise_river_network(float* height, int w, int h, const vnoise_network_t* np, const float* rain,
                         const vnoise_network_out_t* out);
]])

local SAMPLE_FILTERS = { bilinear = 0, bicubic = 1 }
local DIST_MODES = { outside = 0, inside = 1, signed = 2 }
local DIST_EDGES = { none = 0, below = 1, above = 2 }
local SLOPE_MODES = { angle = 0, gradient = 1, aspect = 2, dx = 3, dy = 4, curvature = 5 }
local FLOW_METHODS = { d8 = 0, mfd = 1 }
local FLOW_SCALES = { log = 0, linear = 1, range = 2 }

-- Reads an optional positive integer.
local function int(t, key, default, lo, hi)
  local v = t[key]
  if v == nil then
    return default
  end
  if type(v) ~= "number" or v % 1 ~= 0 or v < lo or (hi and v > hi) then
    error(("vnoise: '%s' must be an integer in %d..%s, got %s"):format(key, lo, hi or "inf", tostring(v)), 3)
  end
  return v
end

-- Resolves a state for a seeded operation: spec.state, else a state of spec.seed.
local function stateOf(spec)
  if spec.state then
    return spec.state.s
  end
  return vnoise.new(spec.seed or 0).s
end

--- Warps a matrix: every cell reads the source at its own position displaced
-- by `amp` cells times a displacement. The displacement comes from two
-- matrices `dx`, `dy` (0.5 = none, 0 and 1 = -amp and +amp), from a
-- `direction` matrix (0..1 = one turn clockwise from +x on a y-down screen)
-- with an optional `strength` matrix (0..1), or, with none of them, from a
-- seeded fBm warp field (`freq`, `octaves`, `lac`, `gain`, `base`) iterated
-- `levels` times (1..4: `f(p + a r)`, `r = g(p + a q)`, `q = g(p)`), as the
-- domain warp of `compile_domain`.
-- @param m cdata The source matrix (not modified).
-- @param w number Columns.
-- @param h number Rows.
-- @param spec table amp (cells, 1/16 of the shorter side), filter ("bilinear", "bicubic"),
--   dx, dy, direction, strength (matrices), freq (1/64), octaves (3), lac (2), gain (0.5),
--   base (simplex), levels (1), state or seed (noise warp), out (optional destination).
-- @return cdata The warped matrix (a new one unless `out`).
function vnoise.warp(m, w, h, spec)
  spec = spec or {}
  local out = spec.out or vnoise.matrix(w, h)
  if out == m then
    error("vnoise: warp 'out' cannot be the source matrix", 2)
  end
  local wp = ffi.new("vnoise_warp_t")
  wp.amp = num(spec, "amp", math.min(w, h) / 16)
  wp.filter = choice(SAMPLE_FILTERS, spec.filter, "bilinear", "warp filter")
  wp.freq = num(spec, "freq", 1 / 64)
  wp.octaves = int(spec, "octaves", 3, 1, 32)
  wp.lac = num(spec, "lac", 2)
  wp.gain = num(spec, "gain", 0.5)
  wp.base = spec.base or vnoise.BASE_SIMPLEX2
  wp.levels = int(spec, "levels", 1, 1, 4)
  if spec.dx or spec.dy then
    if not (spec.dx and spec.dy) then
      error("vnoise: warp needs both 'dx' and 'dy' (or 'direction')", 2)
    end
    lib.vnoise_warp_matrix(m, w, h, out, spec.dx, spec.dy, nil, wp)
  elseif spec.direction then
    lib.vnoise_warp_matrix(m, w, h, out, spec.direction, nil, spec.strength, wp)
  else
    lib.vnoise_warp_matrix_noise(m, w, h, out, stateOf(spec), wp)
  end
  return out
end

--- Hydraulic erosion by seeded droplets, in place: each droplet follows the
-- slope with some inertia, picks up sediment where it speeds up and drops it
-- where it slows down or climbs, carving gullies and valleys and filling
-- basins. Heights are worked in cells: a value of 1 stands
-- `relief * max(w, h)` cells high.
-- @param m cdata The matrix (modified).
-- @param w number Columns.
-- @param h number Rows.
-- @param spec table|nil droplets (density * w * h), density (droplets per cell, 0.3),
--   lifetime (30), inertia (0.05), capacity (4), min_slope (0.01), erode (0.3), deposit (0.3),
--   evaporation (0.01), gravity (4), radius (cells, 1..8, 3), relief (0.05), sea_level (0:
--   droplets stop and drop their load below it), seed (0), hardness, rain (matrices),
--   change (true to return the change map).
-- @return cdata|nil The change map (0.5 unchanged, above deposition, below erosion) when `spec.change`.
function vnoise.erode_hydraulic(m, w, h, spec)
  spec = spec or {}
  local hp = ffi.new("vnoise_hydraulic_t")
  hp.droplets = spec.droplets or math.floor(num(spec, "density", 0.3) * w * h)
  hp.lifetime = int(spec, "lifetime", 30, 1, 1024)
  hp.inertia = num(spec, "inertia", 0.05)
  hp.capacity = num(spec, "capacity", 4)
  hp.min_slope = num(spec, "min_slope", 0.01)
  hp.erode = num(spec, "erode", 0.3)
  hp.deposit = num(spec, "deposit", 0.3)
  hp.evaporation = num(spec, "evaporation", 0.01)
  hp.gravity = num(spec, "gravity", 4)
  hp.radius = int(spec, "radius", 3, 1, 8)
  hp.relief = num(spec, "relief", 0.05)
  hp.sea_level = num(spec, "sea_level", 0)
  hp.seed = spec.seed or 0
  local change = spec.change and vnoise.matrix(w, h) or nil
  lib.vnoise_erode_hydraulic(m, w, h, hp, spec.hardness, spec.rain, change)
  return change
end

--- Thermal (talus) erosion, in place: material slides off slopes steeper
-- than `talus` degrees and piles at their foot, rounding cliffs into screes.
-- @param m cdata The matrix (modified).
-- @param w number Columns.
-- @param h number Rows.
-- @param spec table|nil iterations (50), talus (degrees, 35), rate (0..1, 0.5), relief (0.05),
--   hardness (matrix).
function vnoise.erode_thermal(m, w, h, spec)
  spec = spec or {}
  local tp = ffi.new("vnoise_thermal_t")
  tp.iterations = int(spec, "iterations", 50, 0, 100000)
  tp.talus = num(spec, "talus", 35)
  tp.rate = num(spec, "rate", 0.5)
  tp.relief = num(spec, "relief", 0.05)
  lib.vnoise_erode_thermal(m, w, h, tp, spec.hardness)
end

--- Exact Euclidean distance field of the set `m >= threshold` (cells between
-- centers, unbounded): "outside" (distance from the cells below the
-- threshold to the set), "inside" (from the set to the cells below) or
-- "signed" (0.5 on the boundary, above inside, below outside). Values are
-- `min(d, range) / range`, or divided by the largest distance when `range`
-- is 0. Distance to the coast is `distance_field(elevation, w, h,
-- { threshold = sea_level, mode = "signed", range = 64 })`.
-- @param m cdata The matrix.
-- @param w number Columns.
-- @param h number Rows.
-- @param spec table|nil threshold (0.5), mode ("outside"), range (cells, 0), edge ("none";
--   "below" or "above": the outside of the matrix belongs to that side), out.
-- @return cdata The distance matrix.
function vnoise.distance_field(m, w, h, spec)
  spec = spec or {}
  local dp = ffi.new("vnoise_distance_t")
  dp.threshold = num(spec, "threshold", 0.5)
  dp.mode = choice(DIST_MODES, spec.mode, "outside", "distance mode")
  dp.range = num(spec, "range", 0)
  dp.edge = choice(DIST_EDGES, spec.edge, "none", "distance edge")
  local out = spec.out or vnoise.matrix(w, h)
  lib.vnoise_distance_field(m, w, h, out, dp)
  return out
end

--- Slope analysis (Horn's 3 x 3 gradient, clamped edges) with heights in
-- cells (`relief`): "angle" (0 flat .. 1 vertical), "gradient"
-- (`min(rise / run / range, 1)`), "aspect" (downhill direction, 0..1 one
-- turn clockwise from +x; flat cells 0), "dx" / "dy" (0.5 + signed slope /
-- range / 2) and "curvature" (0.5 + Laplacian / range / 2: above 0.5
-- concave, valleys; below convex, ridges).
-- @param m cdata The matrix.
-- @param w number Columns.
-- @param h number Rows.
-- @param spec table|nil mode ("angle"), relief (0.05), range (1), out.
-- @return cdata The slope matrix.
function vnoise.slope(m, w, h, spec)
  spec = spec or {}
  local sp = ffi.new("vnoise_slope_t")
  sp.mode = choice(SLOPE_MODES, spec.mode, "angle", "slope mode")
  sp.relief = num(spec, "relief", 0.05)
  sp.range = num(spec, "range", 1)
  local out = spec.out or vnoise.matrix(w, h)
  if out == m then
    error("vnoise: slope 'out' cannot be the source matrix", 2)
  end
  lib.vnoise_slope(m, w, h, out, sp)
  return out
end

--- Flow accumulation over the depression-filled matrix (priority-flood,
-- outlets at the sea and/or the edges): every cell adds its rain (1 without
-- a `rain` matrix) to the cells downstream, along the steepest descent
-- ("d8") or shared among the lower neighbors ("mfd", slope^exponent).
-- With `twi`, also the topographic wetness index `ln(A / tan(beta))` of the
-- same accumulation A (cells of rain) and the local slope tan(beta) (the
-- steepest descent to a neighbor on the unfilled heights, in cells through
-- `relief`; at least `epsilon` so pits and flats stay finite): `clamp(twi / twi_range, 0, 1)`, or stretched from the
-- smallest to the largest index of the matrix when `twi_range` is 0. High in
-- valley floors and flats that drain a large area, low on ridges and steep
-- slopes.
-- @param m cdata The height matrix.
-- @param w number Columns.
-- @param h number Rows.
-- @param spec table|nil method ("d8"), exponent (mfd, 1.1), scale ("log", "linear", "range"),
--   range (cells of rain, scale "range"), sea_level (0), outlets ("both"), lake_depth (0.002),
--   rain (matrix), filled and lake (true to return them too), twi (true to return the wetness
--   index), relief (twi, 0.05), epsilon (twi: smallest tan(beta), 0.001), twi_range (0).
-- @return cdata The flow matrix (0..1).
-- @return cdata|nil The depression-filled heights when `spec.filled`.
-- @return cdata|nil The lake mask (1 where filled more than lake_depth) when `spec.lake`.
-- @return cdata|nil The wetness index (0..1) when `spec.twi`.
function vnoise.flow(m, w, h, spec)
  spec = spec or {}
  local fp = ffi.new("vnoise_flow_t")
  fp.method = choice(FLOW_METHODS, spec.method, "d8", "flow method")
  fp.exponent = num(spec, "exponent", 1.1)
  fp.scale = choice(FLOW_SCALES, spec.scale, "log", "flow scale")
  fp.range = num(spec, "range", 1)
  fp.sea_level = num(spec, "sea_level", 0)
  fp.outlets = choice(MATRIX_OUTLETS, spec.outlets, "both", "outlets")
  fp.lake_depth = num(spec, "lake_depth", 0.002)
  local out = ffi.new("vnoise_flow_out_t")
  local flow = vnoise.matrix(w, h)
  local filled = spec.filled and vnoise.matrix(w, h) or nil
  local lake = spec.lake and vnoise.matrix(w, h) or nil
  out.flow, out.filled, out.lake = flow, filled, lake
  if not spec.twi then
    lib.vnoise_flow(m, w, h, fp, spec.rain, out)
    return flow, filled, lake
  end
  local tp = ffi.new("vnoise_twi_t")
  tp.relief = num(spec, "relief", 0.05)
  tp.epsilon = num(spec, "epsilon", 0.001)
  tp.range = num(spec, "twi_range", 0)
  if tp.epsilon <= 0 then
    error("vnoise: flow 'epsilon' must be positive", 2)
  end
  local twi = vnoise.matrix(w, h)
  lib.vnoise_flow_twi(m, w, h, fp, tp, spec.rain, out, twi)
  return flow, filled, lake, twi
end

--- Carves a whole river network into a height matrix: the D8 drainage of
-- the depression-filled heights becomes a channel wherever the accumulated
-- rain reaches `min_flow` cells, traced from every head to the sea, the edge
-- or a larger river (main stems first; tributaries join at the stem's bed).
-- Width and depth grow with the square root of the flow; the bed never
-- rises downstream; lakes the rivers cross are marked 0.5 in the mask (and
-- filled to their surface with `fill_lakes`).
-- @param height cdata The height matrix (modified).
-- @param w number Columns.
-- @param h number Rows.
-- @param spec table|nil min_flow (cells of rain, max(16, w * h / 2000)), sea_level (0),
--   outlets ("both"), width0 (1), width_k (0.5), max_width (8), depth0 (0.004), depth_k (0.002),
--   max_depth (0.03), valley (4), valley_shape (1), bank (1), lake_depth (0.002), fill_lakes
--   (false), smooth (Chaikin passes, 2), min_length (cells, 4), rain (matrix), flow (true to
--   return the log-normalized flow), max_rivers (4096), max_points (262144).
-- @param mask cdata|nil The river mask (allocated when nil; values only grow).
-- @return table Rivers, main stems first: `{ points = { x1, y1, ... }, width = { ... } }` (cells).
-- @return cdata The mask.
-- @return cdata|nil The flow matrix when `spec.flow`.
function vnoise.river_network(height, w, h, spec, mask)
  spec = spec or {}
  mask = mask or vnoise.matrix(w, h)
  local np = ffi.new("vnoise_network_t")
  np.min_flow = num(spec, "min_flow", math.max(16, w * h / 2000))
  np.sea_level = num(spec, "sea_level", 0)
  np.outlets = choice(MATRIX_OUTLETS, spec.outlets, "both", "outlets")
  np.width0 = num(spec, "width0", 1)
  np.width_k = num(spec, "width_k", 0.5)
  np.max_width = num(spec, "max_width", 8)
  np.depth0 = num(spec, "depth0", 0.004)
  np.depth_k = num(spec, "depth_k", 0.002)
  np.max_depth = num(spec, "max_depth", 0.03)
  np.valley = num(spec, "valley", 4)
  np.valley_shape = num(spec, "valley_shape", 1)
  np.bank = num(spec, "bank", 1)
  np.lake_depth = num(spec, "lake_depth", 0.002)
  np.fill_lakes = spec.fill_lakes and 1 or 0
  np.smooth = int(spec, "smooth", 2, 0, 4)
  np.min_length = int(spec, "min_length", 4, 1)
  local max_rivers = int(spec, "max_rivers", 4096, 0)
  local max_points = int(spec, "max_points", 262144, 0)
  local out = ffi.new("vnoise_network_out_t")
  local start = ffi.new("int[?]", math.max(max_rivers, 1))
  local count = ffi.new("int[?]", math.max(max_rivers, 1))
  local xy = ffi.new("float[?]", 2 * math.max(max_points, 1))
  local width = ffi.new("float[?]", math.max(max_points, 1))
  local flow = spec.flow and vnoise.matrix(w, h) or nil
  out.mask, out.flow = mask, flow
  out.max_rivers, out.max_points = max_rivers, max_points
  out.start, out.count, out.xy, out.width = start, count, xy, width
  local n = lib.vnoise_river_network(height, w, h, np, spec.rain, out)
  local rivers = {}
  for r = 0, math.min(n, max_rivers) - 1 do
    local points, widths = {}, {}
    local s0 = start[r]
    for k = 0, count[r] - 1 do
      points[2 * k + 1] = xy[2 * (s0 + k)]
      points[2 * k + 2] = xy[2 * (s0 + k) + 1]
      widths[k + 1] = width[s0 + k]
    end
    rivers[r + 1] = { points = points, width = widths }
  end
  return rivers, mask, flow
end

-- Climate operations -----------------------------------------------------------

ffi.cdef([[
typedef struct {
    float sigma;
    int passes;
} vnoise_blur_t;
void vnoise_blur_matrix(const float* src, int w, int h, float* dst, const vnoise_blur_t* bp);

typedef struct {
    float sea_level;
    float evaporation;
    float capacity;
    float base_rate;
    float orographic;
    float relief;
    float inflow;
    float range;
    float fetch_range;
    float bands[5];
    float tilt;
    int iterations;
} vnoise_moisture_t;
typedef struct {
    float* precip;
    float* moisture;
    float* fetch;
} vnoise_moisture_out_t;
void vnoise_moisture(const float* m, int w, int h, const vnoise_moisture_t* mp, const float* src,
                     const float* dir, const vnoise_moisture_out_t* out);
]])

--- Gaussian blur of any width, in time per cell independent of `sigma`:
-- `passes` successive extended box filters per axis (integer radius plus
-- fractional end weights, so the variance is exactly `sigma^2`), with
-- clamped edges like `apply_stages`. It is not limited by the 32-cell kernel
-- radius of pipeline stages; `sigma` (up to 16384) may exceed the matrix,
-- which then tends to a constant. With 3 passes it stays within about 1% of
-- the value range of the exact Gaussian (more passes come closer).
-- @param m cdata The matrix (not modified unless it is `out`).
-- @param w number Columns.
-- @param h number Rows.
-- @param spec table sigma (cells, 0 copies), passes (1..8, 3), out (destination; may be `m`).
-- @return cdata The blurred matrix (a new one unless `out`).
function vnoise.blur_large(m, w, h, spec)
  spec = spec or {}
  local bp = ffi.new("vnoise_blur_t")
  bp.sigma = num(spec, "sigma", 8)
  bp.passes = int(spec, "passes", 3, 1, 8)
  if bp.sigma < 0 then
    error("vnoise: blur_large 'sigma' must not be negative", 2)
  end
  local out = spec.out or vnoise.matrix(w, h)
  lib.vnoise_blur_matrix(m, w, h, out, bp)
  return out
end

local DEFAULT_BANDS = { 1 / 6, 1 / 3, 0.5, 2 / 3, 5 / 6 }

--- Moisture carried by the wind over a height matrix, with orographic
-- precipitation: the air picks up `evaporation` per cell over the sources
-- (the `source` matrix, 0..1, or the cells below `sea_level`), up to
-- `capacity`; over land it rains `base_rate` of its moisture per cell plus
-- `orographic` times the height it climbs (in cells, `relief`), so windward
-- slopes are wet and their lee lies in a rain shadow. The wind comes from a
-- `direction` matrix (0..1 = one turn clockwise from +x, as `warp`) or, by
-- row, from latitude `bands`: five row fractions (0..1 of the height,
-- non-decreasing) of the polar front, the subtropical ridge, the equator,
-- the other ridge and the other polar front. Trade winds (between the
-- ridges) and polar easterlies (beyond the fronts) blow toward -x, the
-- westerlies toward +x; `tilt` degrees turn them toward the equator
-- (easterlies) or the pole (westerlies). The bands mirror about the equator,
-- so it does not matter which edge is north. Air entering from outside the
-- matrix carries `inflow`. Solved upwind in `iterations` cycles of four
-- sweeps (a uniform wind is exact after one).
-- @param m cdata The height matrix.
-- @param w number Columns.
-- @param h number Rows.
-- @param spec table|nil sea_level (0), evaporation (0.05), capacity (1), base_rate (0.002),
--   orographic (1), relief (0.05), inflow (0), range (precipitation mapped to 1; 0: the largest),
--   fetch_range (cells; 0: the largest), bands ({ 1/6, 1/3, 1/2, 2/3, 5/6 }), tilt (degrees, 0),
--   iterations (1..256, 4), source, direction (matrices), moisture and fetch (true to return
--   them too), out (destination of the precipitation).
-- @return cdata The precipitation (0..1).
-- @return cdata|nil The moisture carried (q / capacity) when `spec.moisture`.
-- @return cdata|nil The fetch when `spec.fetch`: distance along the wind since the last cell with
--   source >= 0.5, `min(d, fetch_range) / fetch_range`, 1 where no source lies upwind.
function vnoise.moisture(m, w, h, spec)
  spec = spec or {}
  local mp = ffi.new("vnoise_moisture_t")
  mp.sea_level = num(spec, "sea_level", 0)
  mp.evaporation = num(spec, "evaporation", 0.05)
  mp.capacity = num(spec, "capacity", 1)
  mp.base_rate = num(spec, "base_rate", 0.002)
  mp.orographic = num(spec, "orographic", 1)
  mp.relief = num(spec, "relief", 0.05)
  mp.inflow = num(spec, "inflow", 0)
  mp.range = num(spec, "range", 0)
  mp.fetch_range = num(spec, "fetch_range", 0)
  mp.tilt = num(spec, "tilt", 0)
  mp.iterations = int(spec, "iterations", 4, 1, 256)
  if mp.capacity <= 0 then
    error("vnoise: moisture 'capacity' must be positive", 2)
  end
  local bands = spec.bands or DEFAULT_BANDS
  if type(bands) ~= "table" or #bands ~= 5 then
    error("vnoise: moisture 'bands' must be a list of 5 row fractions", 2)
  end
  local last = 0
  for i = 1, 5 do
    local b = bands[i]
    if type(b) ~= "number" or b ~= b or b < last or b > 1 then
      error("vnoise: moisture 'bands' must be non-decreasing numbers in 0..1", 2)
    end
    mp.bands[i - 1] = b
    last = b
  end
  local out = ffi.new("vnoise_moisture_out_t")
  local precip = spec.out or vnoise.matrix(w, h)
  local moisture = spec.moisture and vnoise.matrix(w, h) or nil
  local fetch = spec.fetch and vnoise.matrix(w, h) or nil
  out.precip, out.moisture, out.fetch = precip, moisture, fetch
  lib.vnoise_moisture(m, w, h, mp, spec.source, spec.direction, out)
  return precip, moisture, fetch
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
