#ifndef MASK_PROCESSOR_H
#define MASK_PROCESSOR_H

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>  // For malloc/free in aligned memory functions

#ifdef __cplusplus
extern "C" {
#endif

// Memory alignment for 16KB page size support
#define MEMORY_ALIGNMENT 16384  // 16KB alignment for modern page sizes

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

/**
 * Aligned memory allocation utility for 16KB page size support
 * 
 * @param size Size to allocate in bytes
 * @return Aligned pointer or NULL on failure
 */
static inline void* aligned_malloc(size_t size) {
    // Ensure size is properly aligned to avoid issues
    size_t aligned_size = (size + MEMORY_ALIGNMENT - 1) & ~(MEMORY_ALIGNMENT - 1);
    
#if defined(__ANDROID_API__) && __ANDROID_API__ >= 28
    // Use aligned_alloc for Android API 28+
    return aligned_alloc(MEMORY_ALIGNMENT, aligned_size);
#elif defined(__APPLE__)
    // Use posix_memalign for iOS/macOS
    void* ptr = NULL;
    if (posix_memalign(&ptr, MEMORY_ALIGNMENT, aligned_size) == 0) {
        return ptr;
    }
    return NULL;
#else
    // Fallback to malloc for older systems
    return malloc(size);
#endif
}

/**
 * Free aligned memory
 * 
 * @param ptr Pointer to free
 */
static inline void aligned_free(void* ptr) {
    if (ptr) {
        free(ptr);
    }
}

#ifdef __cplusplus
}
#endif

#endif // MASK_PROCESSOR_H