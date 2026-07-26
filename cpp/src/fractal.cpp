#include "vnoise/internal.h"

extern "C" {

VNOISE_API float ridge2_eval(const noise_state_t* s, int base, float x, float y,
                              int octaves, float lac, float gain) {
    return vnoise::fbm_sample(s, base, x, y, octaves, lac, gain, vnoise::RIDGE);
}

VNOISE_API float ridge3_eval(const noise_state_t* s, int base, float x, float y, float z,
                              int octaves, float lac, float gain) {
    return vnoise::fbm_sample3(s, base, x, y, z, octaves, lac, gain, vnoise::RIDGE);
}

VNOISE_API float turb2_eval(const noise_state_t* s, int base, float x, float y,
                             int octaves, float lac, float gain) {
    return vnoise::fbm_sample(s, base, x, y, octaves, lac, gain, vnoise::TURB);
}

VNOISE_API float turb3_eval(const noise_state_t* s, int base, float x, float y, float z,
                             int octaves, float lac, float gain) {
    return vnoise::fbm_sample3(s, base, x, y, z, octaves, lac, gain, vnoise::TURB);
}

}