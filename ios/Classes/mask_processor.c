#include "mask_processor.h"
#include <math.h>
#include <string.h>
#include <stdlib.h>

// Add header for aligned memory allocation
#if defined(__ANDROID_API__) && __ANDROID_API__ >= 28
#include <malloc.h>
#elif defined(__APPLE__) || defined(__linux__)
#include <stdlib.h>  // For posix_memalign
#endif

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

    // Allocate temporary buffer for separable blur with 16KB alignment
    double* temp = (double*)aligned_malloc(sizeof(double) * width * height);
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

    aligned_free(temp);
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

    // If border_width is 0, just copy the mask
    if (border_width == 0) {
        memcpy(output, mask, sizeof(double) * width * height);
        return MASK_PROCESSOR_SUCCESS;
    }

    // Initialize output to zero
    memset(output, 0, sizeof(double) * width * height);

    // For small border widths, use optimized direct approach
    if (border_width <= 3) {
        // Pre-compute circular kernel offsets for small borders
        int kernel_offsets[64]; // Maximum for border_width=3: (2*3+1)^2 = 49
        int kernel_count = 0;
        
        for (int dy = -border_width; dy <= border_width; dy++) {
            for (int dx = -border_width; dx <= border_width; dx++) {
                if (dx * dx + dy * dy <= border_width * border_width) {
                    kernel_offsets[kernel_count++] = dy * width + dx;
                }
            }
        }

        // Apply kernel to each foreground pixel
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                if (mask[y * width + x] > THRESHOLD) {
                    const int center_idx = y * width + x;
                    
                    for (int k = 0; k < kernel_count; k++) {
                        const int target_idx = center_idx + kernel_offsets[k];
                        const int target_y = target_idx / width;
                        const int target_x = target_idx % width;
                        
                        // Bounds check
                        if (target_y >= 0 && target_y < height && 
                            target_x >= 0 && target_x < width) {
                            output[target_idx] = 1.0;
                        }
                    }
                }
            }
        }
    } else {
        // For larger border widths, use distance transform approach
        // First pass: mark all foreground pixels
        for (int i = 0; i < width * height; i++) {
            if (mask[i] > THRESHOLD) {
                output[i] = 1.0;
            }
        }

        // Multi-pass dilation for better cache performance with 16KB alignment
        double* temp_buffer = (double*)aligned_malloc(sizeof(double) * width * height);
        if (!temp_buffer) {
            return MASK_PROCESSOR_ERROR_MEMORY;
        }

        // Use iterative dilation approach - more cache friendly
        for (int iter = 0; iter < border_width; iter++) {
            memcpy(temp_buffer, output, sizeof(double) * width * height);
            
            for (int y = 1; y < height - 1; y++) {
                for (int x = 1; x < width - 1; x++) {
                    const int idx = y * width + x;
                    if (temp_buffer[idx] == 0.0) {
                        // Check 8-connected neighbors
                        if (temp_buffer[idx - width - 1] > 0.0 ||  // Top-left
                            temp_buffer[idx - width] > 0.0 ||      // Top
                            temp_buffer[idx - width + 1] > 0.0 ||  // Top-right
                            temp_buffer[idx - 1] > 0.0 ||          // Left
                            temp_buffer[idx + 1] > 0.0 ||          // Right
                            temp_buffer[idx + width - 1] > 0.0 ||  // Bottom-left
                            temp_buffer[idx + width] > 0.0 ||      // Bottom
                            temp_buffer[idx + width + 1] > 0.0) {  // Bottom-right
                            output[idx] = 1.0;
                        }
                    }
                }
            }
            
            // Handle border pixels separately to avoid bounds checking in main loop
            for (int x = 0; x < width; x++) {
                // Top row (y = 0)
                if (temp_buffer[x] == 0.0) {
                    if ((x > 0 && temp_buffer[x - 1] > 0.0) ||
                        (x < width - 1 && temp_buffer[x + 1] > 0.0) ||
                        temp_buffer[width + x] > 0.0 ||
                        (x > 0 && temp_buffer[width + x - 1] > 0.0) ||
                        (x < width - 1 && temp_buffer[width + x + 1] > 0.0)) {
                        output[x] = 1.0;
                    }
                }
                // Bottom row
                const int bottom_idx = (height - 1) * width + x;
                if (temp_buffer[bottom_idx] == 0.0) {
                    if ((x > 0 && temp_buffer[bottom_idx - 1] > 0.0) ||
                        (x < width - 1 && temp_buffer[bottom_idx + 1] > 0.0) ||
                        temp_buffer[bottom_idx - width] > 0.0 ||
                        (x > 0 && temp_buffer[bottom_idx - width - 1] > 0.0) ||
                        (x < width - 1 && temp_buffer[bottom_idx - width + 1] > 0.0)) {
                        output[bottom_idx] = 1.0;
                    }
                }
            }
            
            for (int y = 1; y < height - 1; y++) {
                // Left column
                const int left_idx = y * width;
                if (temp_buffer[left_idx] == 0.0) {
                    if (temp_buffer[left_idx - width] > 0.0 ||
                        temp_buffer[left_idx - width + 1] > 0.0 ||
                        temp_buffer[left_idx + 1] > 0.0 ||
                        temp_buffer[left_idx + width] > 0.0 ||
                        temp_buffer[left_idx + width + 1] > 0.0) {
                        output[left_idx] = 1.0;
                    }
                }
                // Right column
                const int right_idx = y * width + width - 1;
                if (temp_buffer[right_idx] == 0.0) {
                    if (temp_buffer[right_idx - width - 1] > 0.0 ||
                        temp_buffer[right_idx - width] > 0.0 ||
                        temp_buffer[right_idx - 1] > 0.0 ||
                        temp_buffer[right_idx + width - 1] > 0.0 ||
                        temp_buffer[right_idx + width] > 0.0) {
                        output[right_idx] = 1.0;
                    }
                }
            }
        }

        aligned_free(temp_buffer);
    }

    return MASK_PROCESSOR_SUCCESS;
}