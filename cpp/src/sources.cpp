#include <cmath>
#include "vnoise/internal.h"

// Buffer combinators for source trees (see VNOISE_COMBINE_*). Keeping these
// loops native avoids per-cell work in Lua.

extern "C" VNOISE_API void vnoise_combine(float* dst, const float* src, int count, int op, float w) {
    if (!dst || count <= 0) return;
    if (!src && op != VNOISE_COMBINE_ABS && op != VNOISE_COMBINE_POW) return;
    switch (op) {
    case VNOISE_COMBINE_SET:
        for (int k = 0; k < count; ++k) dst[k] = w * src[k];
        break;
    case VNOISE_COMBINE_ADD:
        for (int k = 0; k < count; ++k) dst[k] += w * src[k];
        break;
    case VNOISE_COMBINE_MUL:
        for (int k = 0; k < count; ++k) dst[k] *= src[k];
        break;
    case VNOISE_COMBINE_MIN:
        for (int k = 0; k < count; ++k) dst[k] = src[k] < dst[k] ? src[k] : dst[k];
        break;
    case VNOISE_COMBINE_MAX:
        for (int k = 0; k < count; ++k) dst[k] = src[k] > dst[k] ? src[k] : dst[k];
        break;
    case VNOISE_COMBINE_SUB:
        for (int k = 0; k < count; ++k) dst[k] -= src[k];
        break;
    case VNOISE_COMBINE_ABS:
        for (int k = 0; k < count; ++k) dst[k] = fabsf(dst[k]);
        break;
    case VNOISE_COMBINE_POW:
        for (int k = 0; k < count; ++k) dst[k] = dst[k] > 0.0f ? powf(dst[k], w) : 0.0f;
        break;
    default:
        break;
    }
}

extern "C" VNOISE_API void vnoise_combine_lerp(float* dst, const float* b, const float* t, int count) {
    if (!dst || !b || !t || count <= 0) return;
    for (int k = 0; k < count; ++k) dst[k] = dst[k] + t[k] * (b[k] - dst[k]);
}
