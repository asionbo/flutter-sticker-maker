#include "mask_processor.h"
#include <math.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>

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

static inline bool checked_total_pixels(int width, int height, size_t* total_pixels) {
    if (!total_pixels || width <= 0 || height <= 0) {
        return false;
    }

    const size_t safe_width = (size_t)width;
    const size_t safe_height = (size_t)height;
    if (safe_width > SIZE_MAX / safe_height) {
        return false;
    }

    *total_pixels = safe_width * safe_height;
    return true;
}

static inline bool checked_total_bytes(size_t element_count, size_t element_size, size_t* total_bytes) {
    if (!total_bytes) {
        return false;
    }

    if (element_count > SIZE_MAX / element_size) {
        return false;
    }

    *total_bytes = element_count * element_size;
    return true;
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
    size_t total_pixels = 0;
    if (!pixels || !mask || border_width < 0 || !checked_total_pixels(width, height, &total_pixels)) {
        return MASK_PROCESSOR_ERROR_INVALID_PARAMS;
    }
    
    for (size_t i = 0; i < total_pixels; i++) {
        const size_t pixel_index = i * 4;
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
    size_t total_pixels = 0;
    size_t total_bytes = 0;
    if (!mask || !output || kernel_size <= 0 || !checked_total_pixels(width, height, &total_pixels) ||
        !checked_total_bytes(total_pixels, sizeof(double), &total_bytes)) {
        return MASK_PROCESSOR_ERROR_INVALID_PARAMS;
    }

    if (kernel_size <= 1) {
        memcpy(output, mask, total_bytes);
        return MASK_PROCESSOR_SUCCESS;
    }

    // Allocate temporary buffer for separable blur
    double* temp = (double*)malloc(total_bytes);
    if (!temp) {
        return MASK_PROCESSOR_ERROR_MEMORY;
    }

    const int half_kernel = kernel_size / 2;

    // Horizontal pass with a sliding window to reduce repeated summations.
    for (int y = 0; y < height; y++) {
        const size_t row_start = (size_t)y * (size_t)width;
        double sum = 0.0;
        int count = 0;

        for (int x = 0; x <= half_kernel && x < width; x++) {
            sum += mask[row_start + (size_t)x];
            count++;
        }

        for (int x = 0; x < width; x++) {
            temp[row_start + (size_t)x] = sum / (double)count;

            const int remove_x = x - half_kernel;
            const int add_x = x + half_kernel + 1;
            if (remove_x >= 0) {
                sum -= mask[row_start + (size_t)remove_x];
                count--;
            }
            if (add_x < width) {
                sum += mask[row_start + (size_t)add_x];
                count++;
            }
        }
    }

    // Vertical pass with the same sliding-window approach.
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            double sum = 0.0;
            int count = 0;
            const int start_y = y - half_kernel < 0 ? 0 : y - half_kernel;
            const int end_y = y + half_kernel >= height ? height - 1 : y + half_kernel;

            for (int ny = start_y; ny <= end_y; ny++) {
                sum += temp[(size_t)ny * (size_t)width + (size_t)x];
                count++;
            }
            output[(size_t)y * (size_t)width + (size_t)x] = sum / (double)count;
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
    size_t total_pixels = 0;
    size_t total_bytes = 0;
    if (!mask || !output || border_width < 0 || !checked_total_pixels(width, height, &total_pixels) ||
        !checked_total_bytes(total_pixels, sizeof(double), &total_bytes)) {
        return MASK_PROCESSOR_ERROR_INVALID_PARAMS;
    }

    // If border_width is 0, just copy the mask
    if (border_width == 0) {
        memcpy(output, mask, total_bytes);
        return MASK_PROCESSOR_SUCCESS;
    }

    // Initialize output to zero
    memset(output, 0, total_bytes);

    // For small border widths, use optimized direct approach
    if (border_width <= 3) {
        // Pre-compute circular kernel offsets for small borders
        int kernel_dx[64];
        int kernel_dy[64];
        int kernel_count = 0;
        
        for (int dy = -border_width; dy <= border_width; dy++) {
            for (int dx = -border_width; dx <= border_width; dx++) {
                if (dx * dx + dy * dy <= border_width * border_width) {
                    kernel_dx[kernel_count] = dx;
                    kernel_dy[kernel_count] = dy;
                    kernel_count++;
                }
            }
        }

        // Apply kernel to each foreground pixel
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                if (mask[y * width + x] > THRESHOLD) {
                    for (int k = 0; k < kernel_count; k++) {
                        const int target_x = x + kernel_dx[k];
                        const int target_y = y + kernel_dy[k];

                        if (target_y >= 0 && target_y < height &&
                            target_x >= 0 && target_x < width) {
                            output[(size_t)target_y * (size_t)width + (size_t)target_x] = 1.0;
                        }
                    }
                }
            }
        }
    } else {
        // For larger border widths, use distance transform approach
        // First pass: mark all foreground pixels
        for (size_t i = 0; i < total_pixels; i++) {
            if (mask[i] > THRESHOLD) {
                output[i] = 1.0;
            }
        }

        // Multi-pass dilation for better cache performance
        double* temp_buffer = (double*)malloc(total_bytes);
        if (!temp_buffer) {
            return MASK_PROCESSOR_ERROR_MEMORY;
        }

        // Use iterative dilation approach - more cache friendly
        for (int iter = 0; iter < border_width; iter++) {
            memcpy(temp_buffer, output, total_bytes);
            
            for (int y = 0; y < height; y++) {
                const int start_y = y > 0 ? y - 1 : 0;
                const int end_y = y + 1 < height ? y + 1 : height - 1;

                for (int x = 0; x < width; x++) {
                    const size_t idx = (size_t)y * (size_t)width + (size_t)x;
                    if (temp_buffer[idx] != 0.0) {
                        continue;
                    }

                    const int start_x = x > 0 ? x - 1 : 0;
                    const int end_x = x + 1 < width ? x + 1 : width - 1;
                    bool has_foreground_neighbor = false;

                    for (int ny = start_y; ny <= end_y && !has_foreground_neighbor; ny++) {
                        for (int nx = start_x; nx <= end_x; nx++) {
                            if (nx == x && ny == y) {
                                continue;
                            }

                            if (temp_buffer[(size_t)ny * (size_t)width + (size_t)nx] > 0.0) {
                                has_foreground_neighbor = true;
                                break;
                            }
                        }
                    }

                    if (has_foreground_neighbor) {
                        output[idx] = 1.0;
                    }
                }
            }
        }

        free(temp_buffer);
    }

    return MASK_PROCESSOR_SUCCESS;
}