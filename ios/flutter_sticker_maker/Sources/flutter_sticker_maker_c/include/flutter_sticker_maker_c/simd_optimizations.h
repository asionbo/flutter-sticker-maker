#ifndef SIMD_OPTIMIZATIONS_H
#define SIMD_OPTIMIZATIONS_H

#include "mask_processor.h"

#ifdef __cplusplus
extern "C" {
#endif

// Platform-specific SIMD optimizations
#ifdef __ARM_NEON
/**
 * ARM NEON optimized mask application
 */
MaskProcessorResult apply_sticker_mask_neon(
    uint8_t* pixels,
    const double* mask,
    int width,
    int height,
    int add_border,
    RGBColor border_color,
    int border_width,
    const double* expanded_mask
);

/**
 * ARM NEON optimized blur
 */
MaskProcessorResult smooth_mask_neon(
    const double* mask,
    double* output,
    int width,
    int height,
    int kernel_size
);
#endif

#ifdef __SSE2__
/**
 * SSE2 optimized mask application
 */
MaskProcessorResult apply_sticker_mask_sse2(
    uint8_t* pixels,
    const double* mask,
    int width,
    int height,
    int add_border,
    RGBColor border_color,
    int border_width,
    const double* expanded_mask
);

/**
 * SSE2 optimized blur
 */
MaskProcessorResult smooth_mask_sse2(
    const double* mask,
    double* output,
    int width,
    int height,
    int kernel_size
);
#endif

// Auto-dispatch function that selects best available implementation
MaskProcessorResult apply_sticker_mask_optimized(
    uint8_t* pixels,
    const double* mask,
    int width,
    int height,
    int add_border,
    RGBColor border_color,
    int border_width,
    const double* expanded_mask
);

MaskProcessorResult smooth_mask_optimized(
    const double* mask,
    double* output,
    int width,
    int height,
    int kernel_size
);

#ifdef __cplusplus
}
#endif

#endif // SIMD_OPTIMIZATIONS_H