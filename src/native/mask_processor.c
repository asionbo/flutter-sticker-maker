#include "mask_processor.h"
#include <math.h>
#include <string.h>
#include <stdlib.h>

// Threshold constants matching Dart implementation
#define THRESHOLD 0.5
#define THRESHOLD_HIGH (THRESHOLD + 0.05)
#define THRESHOLD_LOW (THRESHOLD - 0.05)
#define THRESHOLD_RANGE 0.1

// SIMD optimization detection
#ifdef __ARM_NEON
#include <arm_neon.h>
#define USE_NEON 1
#elif defined(__SSE2__)
#include <emmintrin.h>
#define USE_SSE2 1
#endif

// Utility function to clamp values
static inline int clamp_int(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
}

static inline double clamp_double(double value, double min, double max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
}

MaskProcessorResult apply_sticker_mask_native(
    uint8_t* pixels,
    const double* mask,
    int width,
    int height,
    int add_border,
    RGBColor border_color,
    int border_width,
    const double* expanded_mask
) {
    if (!pixels || !mask || width <= 0 || height <= 0) {
        return MASK_PROCESSOR_ERROR_INVALID_PARAMS;
    }

    const int total_pixels = width * height;
    
    for (int i = 0; i < total_pixels; i++) {
        const int pixel_index = i * 4;
        const double mask_value = mask[i];
        const double expanded_mask_value = expanded_mask ? expanded_mask[i] : mask_value;

        if (mask_value > THRESHOLD_HIGH) {
            // Foreground pixel - keep original with full alpha
            pixels[pixel_index + 3] = 255;
        } else if (mask_value < THRESHOLD_LOW) {
            if (add_border && expanded_mask_value > THRESHOLD) {
                // Border pixel
                pixels[pixel_index] = border_color.r;
                pixels[pixel_index + 1] = border_color.g;
                pixels[pixel_index + 2] = border_color.b;
                pixels[pixel_index + 3] = 255;
            } else {
                // Background pixel - transparent
                pixels[pixel_index + 3] = 0;
            }
        } else {
            // Smooth transition - alpha blending
            const int alpha = clamp_int(
                (int)round((mask_value - THRESHOLD_LOW) / THRESHOLD_RANGE * 255.0),
                0, 255
            );
            pixels[pixel_index + 3] = (uint8_t)alpha;
        }
    }

    return MASK_PROCESSOR_SUCCESS;
}

MaskProcessorResult smooth_mask_native(
    const double* mask,
    double* output,
    int width,
    int height,
    int kernel_size
) {
    if (!mask || !output || width <= 0 || height <= 0 || kernel_size <= 0) {
        return MASK_PROCESSOR_ERROR_INVALID_PARAMS;
    }

    if (kernel_size <= 1) {
        memcpy(output, mask, sizeof(double) * width * height);
        return MASK_PROCESSOR_SUCCESS;
    }

    // Allocate temporary buffer for separable blur
    double* temp = (double*)malloc(sizeof(double) * width * height);
    if (!temp) {
        return MASK_PROCESSOR_ERROR_MEMORY;
    }

    const int half_kernel = kernel_size / 2;

    // Horizontal pass
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            double sum = 0.0;
            int count = 0;

            for (int kx = -half_kernel; kx <= half_kernel; kx++) {
                const int nx = x + kx;
                if (nx >= 0 && nx < width) {
                    sum += mask[y * width + nx];
                    count++;
                }
            }
            temp[y * width + x] = sum / count;
        }
    }

    // Vertical pass
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            double sum = 0.0;
            int count = 0;

            for (int ky = -half_kernel; ky <= half_kernel; ky++) {
                const int ny = y + ky;
                if (ny >= 0 && ny < height) {
                    sum += temp[ny * width + x];
                    count++;
                }
            }
            output[y * width + x] = sum / count;
        }
    }

    free(temp);
    return MASK_PROCESSOR_SUCCESS;
}

MaskProcessorResult expand_mask_native(
    const double* mask,
    double* output,
    int width,
    int height,
    int border_width
) {
    if (!mask || !output || width <= 0 || height <= 0 || border_width < 0) {
        return MASK_PROCESSOR_ERROR_INVALID_PARAMS;
    }

    // Initialize output to zero
    memset(output, 0, sizeof(double) * width * height);

    const int border_width_sq = border_width * border_width;

    // Efficient distance-based expansion
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            if (mask[y * width + x] > THRESHOLD) {
                const int start_y = clamp_int(y - border_width, 0, height - 1);
                const int end_y = clamp_int(y + border_width, 0, height - 1);
                const int start_x = clamp_int(x - border_width, 0, width - 1);
                const int end_x = clamp_int(x + border_width, 0, width - 1);

                for (int ny = start_y; ny <= end_y; ny++) {
                    for (int nx = start_x; nx <= end_x; nx++) {
                        const int dx = nx - x;
                        const int dy = ny - y;
                        const int distance_sq = dx * dx + dy * dy;
                        if (distance_sq <= border_width_sq) {
                            output[ny * width + nx] = 1.0;
                        }
                    }
                }
            }
        }
    }

    return MASK_PROCESSOR_SUCCESS;
}