#include <cmath>
#include <cstdlib>
#include <cstring>
#include "vnoise/internal.h"

// Grayscale images as noise fields: loading (stb_image), raw pixel import and
// the sampler (wrap modes, nearest/bilinear/bicubic filters).

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_ONLY_BMP
#define STBI_ONLY_TGA
#define STBI_ONLY_PNM
#define STBI_NO_LINEAR
#define STBI_NO_HDR
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-function"
#pragma GCC diagnostic ignored "-Wmissing-field-initializers"
#include "../third_party/stb_image.h"
#pragma GCC diagnostic pop

namespace {

vnoise_image_t* make_image(int w, int h) {
    if (w <= 0 || h <= 0 || (long long)w * h > (1LL << 28)) return nullptr;
    vnoise_image_t* img = (vnoise_image_t*)malloc(sizeof(vnoise_image_t));
    if (!img) return nullptr;
    img->w = w;
    img->h = h;
    img->data = (float*)malloc(sizeof(float) * (size_t)w * (size_t)h);
    if (!img->data) {
        free(img);
        return nullptr;
    }
    return img;
}

// Index into [0, n) under a wrap mode.
inline int wrap_index(int i, int n, int wrap) {
    switch (wrap) {
    case VNOISE_WRAP_REPEAT: {
        int m = i % n;
        return m < 0 ? m + n : m;
    }
    case VNOISE_WRAP_MIRROR: {
        const int period = 2 * n;
        int m = i % period;
        if (m < 0) m += period;
        return m < n ? m : period - 1 - m;
    }
    default:
        return i < 0 ? 0 : (i >= n ? n - 1 : i);
    }
}

inline float texel(const vnoise_image_t* img, int i, int j, int wrap) {
    return img->data[(size_t)wrap_index(j, img->h, wrap) * (size_t)img->w + (size_t)wrap_index(i, img->w, wrap)];
}

// Catmull-Rom weights for the four taps around a fraction t.
inline void cubic_weights(float t, float* w) {
    const float t2 = t * t, t3 = t2 * t;
    w[0] = -0.5f * t3 + t2 - 0.5f * t;
    w[1] = 1.5f * t3 - 2.5f * t2 + 1.0f;
    w[2] = -1.5f * t3 + 2.0f * t2 + 0.5f * t;
    w[3] = 0.5f * t3 - 0.5f * t2;
}

} // namespace

namespace vnoise {

float image_sample(const vnoise_image_t* img, float x, float y, int wrap, int filter) {
    if (!img || !img->data) return 0.0f;
    // NaN, infinite or absurd coordinates must not reach the integer casts.
    // Tested on the bits: -ffast-math may assume comparisons never see a NaN.
    unsigned int bx, by;
    memcpy(&bx, &x, 4);
    memcpy(&by, &y, 4);
    if (((bx >> 23) & 0xff) > 150 || ((by >> 23) & 0xff) > 150) return 0.0f; // |v| >= 2^24 or NaN/Inf
    if (filter == VNOISE_FILTER_NEAREST) {
        return texel(img, (int)floorf(x + 0.5f), (int)floorf(y + 0.5f), wrap);
    }
    const float fx0 = floorf(x), fy0 = floorf(y);
    const int x0 = (int)fx0, y0 = (int)fy0;
    const float tx = x - fx0, ty = y - fy0;
    if (filter == VNOISE_FILTER_BICUBIC) {
        float wx[4], wy[4];
        cubic_weights(tx, wx);
        cubic_weights(ty, wy);
        float sum = 0.0f;
        for (int j = 0; j < 4; ++j) {
            float row = 0.0f;
            for (int i = 0; i < 4; ++i) row += wx[i] * texel(img, x0 - 1 + i, y0 - 1 + j, wrap);
            sum += wy[j] * row;
        }
        return sum;
    }
    const float a = texel(img, x0, y0, wrap), b = texel(img, x0 + 1, y0, wrap);
    const float c = texel(img, x0, y0 + 1, wrap), d = texel(img, x0 + 1, y0 + 1, wrap);
    return lerp(lerp(a, b, tx), lerp(c, d, tx), ty);
}

} // namespace vnoise

extern "C" VNOISE_API vnoise_image_t* vnoise_image_load(const char* path) {
    if (!path) return nullptr;
    int w = 0, h = 0, n = 0;
    vnoise_image_t* img = nullptr;
    if (stbi_is_16_bit(path)) {
        stbi_us* px = stbi_load_16(path, &w, &h, &n, 1);
        if (!px) return nullptr;
        img = make_image(w, h);
        if (img) {
            for (long long k = 0, m = (long long)w * h; k < m; ++k) img->data[k] = (float)px[k] * (1.0f / 65535.0f);
        }
        stbi_image_free(px);
    } else {
        stbi_uc* px = stbi_load(path, &w, &h, &n, 1);
        if (!px) return nullptr;
        img = make_image(w, h);
        if (img) {
            for (long long k = 0, m = (long long)w * h; k < m; ++k) img->data[k] = (float)px[k] * (1.0f / 255.0f);
        }
        stbi_image_free(px);
    }
    return img;
}

extern "C" VNOISE_API vnoise_image_t* vnoise_image_from_pixels(const void* data, int w, int h,
                                                               int channels, int bytes) {
    if (!data || channels < 1 || channels > 4) return nullptr;
    if (bytes != 1 && bytes != 2 && bytes != 4) return nullptr;
    vnoise_image_t* img = make_image(w, h);
    if (!img) return nullptr;
    const unsigned char* base = (const unsigned char*)data;
    const long long count = (long long)w * h;
    const float scale = bytes == 1 ? 1.0f / 255.0f : (bytes == 2 ? 1.0f / 65535.0f : 1.0f);
    for (long long k = 0; k < count; ++k) {
        const unsigned char* px = base + (size_t)(k * channels * bytes);
        float v[3] = {0.0f, 0.0f, 0.0f};
        const int used = channels >= 3 ? 3 : 1;
        for (int c = 0; c < used; ++c) {
            if (bytes == 1) {
                v[c] = (float)px[c];
            } else if (bytes == 2) {
                unsigned short u;
                memcpy(&u, px + c * 2, 2);
                v[c] = (float)u;
            } else {
                memcpy(&v[c], px + c * 4, 4);
            }
        }
        const float g = used == 3 ? 0.299f * v[0] + 0.587f * v[1] + 0.114f * v[2] : v[0];
        img->data[k] = g * scale;
    }
    return img;
}

extern "C" VNOISE_API void vnoise_image_free(vnoise_image_t* img) {
    if (!img) return;
    free(img->data);
    free(img);
}

extern "C" VNOISE_API int vnoise_image_width(const vnoise_image_t* img) { return img ? img->w : 0; }
extern "C" VNOISE_API int vnoise_image_height(const vnoise_image_t* img) { return img ? img->h : 0; }
extern "C" VNOISE_API const float* vnoise_image_data(const vnoise_image_t* img) { return img ? img->data : nullptr; }
extern "C" VNOISE_API const char* vnoise_image_error(void) {
    const char* r = stbi_failure_reason();
    return r ? r : "unknown error";
}
