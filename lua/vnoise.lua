local ffi = require("ffi")

local ok, lib = pcall(ffi.load, "vnoise")
if not ok then
    local cwd = love and love.filesystem and love.filesystem.getSourceBaseDirectory()
        or (os.getenv("PWD") or ".")
    lib = ffi.load(cwd .. "/libvnoise")
end

ffi.cdef[[
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
]]

local vnoise = {
    BASE_PERLIN2  = 0,
    BASE_PERLIN3  = 1,
    BASE_SIMPLEX2 = 2,
    BASE_SIMPLEX3 = 3,
    BASE_WHITE2   = 4,
    BASE_WHITE3   = 5,
}

local State = {}
State.__index = State

function vnoise.new(seed)
    local s = ffi.new("noise_state_t")
    lib.noise_init(s, seed or 0)
    return setmetatable({ s = s }, State)
end

function State:perlin2(x, y)       return lib.perlin2_eval(self.s, x, y) end
function State:perlin3(x, y, z)    return lib.perlin3_eval(self.s, x, y, z) end
function State:simplex2(x, y)      return lib.simplex2_eval(self.s, x, y) end
function State:simplex3(x, y, z)   return lib.simplex3_eval(self.s, x, y, z) end
function State:white2(ix, iy)      return lib.white2_eval(self.s, ix, iy) end
function State:white3(ix, iy, iz) return lib.white3_eval(self.s, ix, iy, iz) end

-- Fractal samplers. lac (lacunarity) and gain are optional and default to
-- 2.0 and 0.5, matching fill_grid / fill_volume / fill_imagedata.
function State:fbm2(x, y, octaves, base, lac, gain)
    return lib.fbm2_eval(self.s, base or vnoise.BASE_SIMPLEX2,
                        x, y, octaves or 6, lac or 2.0, gain or 0.5)
end
function State:fbm3(x, y, z, octaves, base, lac, gain)
    return lib.fbm3_eval(self.s, base or vnoise.BASE_SIMPLEX3,
                        x, y, z, octaves or 6, lac or 2.0, gain or 0.5)
end
function State:ridge2(x, y, octaves, base, lac, gain)
    return lib.ridge2_eval(self.s, base or vnoise.BASE_SIMPLEX2,
                          x, y, octaves or 6, lac or 2.0, gain or 0.5)
end
function State:ridge3(x, y, z, octaves, base, lac, gain)
    return lib.ridge3_eval(self.s, base or vnoise.BASE_SIMPLEX3,
                          x, y, z, octaves or 6, lac or 2.0, gain or 0.5)
end
function State:turb2(x, y, octaves, base, lac, gain)
    return lib.turb2_eval(self.s, base or vnoise.BASE_SIMPLEX2,
                         x, y, octaves or 6, lac or 2.0, gain or 0.5)
end
function State:turb3(x, y, z, octaves, base, lac, gain)
    return lib.turb3_eval(self.s, base or vnoise.BASE_SIMPLEX3,
                         x, y, z, octaves or 6, lac or 2.0, gain or 0.5)
end

local FNS_2D = {
    fbm   = lib.fbm2_fill_grid,
    ridge = lib.ridge2_fill_grid,
    turb  = lib.turb2_fill_grid,
}
local FNS_3D = {
    fbm   = lib.fbm3_fill_volume,
    ridge = lib.ridge3_fill_volume,
    turb  = lib.turb3_fill_volume,
}

function vnoise.fill_grid(state, kind, opts)
    local fn = FNS_2D[kind] or error("unknown fractal kind '" .. tostring(kind) .. "'", 2)
    local w, h = opts.w or 256, opts.h or 256
    local out = opts.out or ffi.new("float[?]", w * h)
    fn(state.s, opts.base or vnoise.BASE_SIMPLEX2, out,
       opts.ox or 0, opts.oy or 0, w, h, opts.freq or 0.01,
       opts.octaves or 6, opts.lac or 2.0, opts.gain or 0.5)
    return out
end

function vnoise.fill_volume(state, kind, opts)
    local fn = FNS_3D[kind] or error("unknown fractal kind '" .. tostring(kind) .. "'", 2)
    local w, h, d = opts.w or 64, opts.h or 64, opts.d or 64
    local out = opts.out or ffi.new("float[?]", w * h * d)
    fn(state.s, opts.base or vnoise.BASE_SIMPLEX3, out,
       opts.ox or 0, opts.oy or 0, opts.oz or 0, w, h, d, opts.freq or 0.01,
       opts.octaves or 6, opts.lac or 2.0, opts.gain or 0.5)
    return out
end

local IMG_FNS = {
    fbm   = lib.fbm2_fill_imagedata_rgba8,
    ridge = lib.ridge2_fill_imagedata_rgba8,
    turb  = lib.turb2_fill_imagedata_rgba8,
}

function vnoise.fill_imagedata(state, kind, img, opts)
    local fn = IMG_FNS[kind] or error("unknown fractal kind '" .. tostring(kind) .. "'", 2)
    local w, h = img:getDimensions()
    local ptr = ffi.cast("unsigned char*", img:getPointer())
    fn(state.s, opts.base or vnoise.BASE_SIMPLEX2, ptr, w, h,
       opts.ox or 0, opts.oy or 0, opts.freq or 0.01,
       opts.octaves or 6, opts.lac or 2.0, opts.gain or 0.5,
       opts.lo or -1, opts.hi or 1,
       opts.r or 255, opts.g or 255, opts.b or 255, opts.a or 255)
    return img
end

vnoise._lib = lib
return vnoise