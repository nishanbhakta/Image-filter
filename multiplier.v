// 32x32 Shift-Add Multiplier Implementation

#include <stdint.h>

uint64_t shift_add_multiplier(uint32_t a, uint32_t b) {
    uint64_t product = 0;
    for (int i = 0; i < 32; i++) {
        if (b & (1 << i)) {
            product += (uint64_t)a << i;
        }
    }
    return product;
}