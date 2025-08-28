#ifndef MASK_PROCESSOR_H
#define MASK_PROCESSOR_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Return codes for native functions
typedef enum {
    MASK_PROCESSOR_SUCCESS = 0,
    MASK_PROCESSOR_ERROR_INVALID_PARAMS = -1,
    MASK_PROCESSOR_ERROR_MEMORY = -2,
    MASK_PROCESSOR_ERROR_PROCESSING = -3
} MaskProcessorResult;

// Structure for RGB color
typedef struct {
    uint8_t r;
    uint8_t g;
    uint8_t b;
} RGBColor;

/**
 * Apply sticker mask effects to image pixels with native optimization
 * 
 * @param pixels RGBA pixel data (input/output)
 * @param mask Mask values (0.0-1.0)
 * @param width Image width
 * @param height Image height
 * @param add_border Whether to add border
 * @param border_color Border color RGB
 * @param border_width Border width in pixels
 * @param expanded_mask Optional expanded mask for borders (can be NULL)
 * @return Result code
 */
MaskProcessorResult apply_sticker_mask_native(
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
 * Smooth mask using optimized separable Gaussian blur
 * 
 * @param mask Input mask values
 * @param output Output smoothed mask values
 * @param width Mask width
 * @param height Mask height
 * @param kernel_size Blur kernel size (must be odd)
 * @return Result code
 */
MaskProcessorResult smooth_mask_native(
    const double* mask,
    double* output,
    int width,
    int height,
    int kernel_size
);

/**
 * Expand mask for border creation using distance transform
 * 
 * @param mask Input mask values
 * @param output Output expanded mask values
 * @param width Mask width
 * @param height Mask height
 * @param border_width Border expansion width
 * @return Result code
 */
MaskProcessorResult expand_mask_native(
    const double* mask,
    double* output,
    int width,
    int height,
    int border_width
);

#ifdef __cplusplus
}
#endif

#endif // MASK_PROCESSOR_H