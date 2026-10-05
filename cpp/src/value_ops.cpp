#include "vnoise/internal.h"

extern "C" VNOISE_API float vnoise_apply_ops(float v, const vnoise_op_t* ops,
                                             int n, int clamp01) {
    if (!ops) n = 0;
    return vnoise::apply_ops(v, ops, n, clamp01);
}

extern "C" VNOISE_API void vnoise_map_buffer(float* buf, int count,
                                             const vnoise_op_t* ops, int n,
                                             int clamp01) {
    if (!buf || count <= 0) return;
    if (!ops) n = 0;
    for (int i = 0; i < count; ++i) {
        buf[i] = vnoise::apply_ops(buf[i], ops, n, clamp01);
    }
}
