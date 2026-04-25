import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// Bindings for native mask processing library
final class RGBColor extends ffi.Struct {
  @ffi.Uint8()
  external int r;
  @ffi.Uint8()
  external int g;
  @ffi.Uint8()
  external int b;
}

/// Result codes for native functions
class MaskProcessorResult {
  static const int success = 0;
  static const int errorInvalidParams = -1;
  static const int errorMemory = -2;
  static const int errorProcessing = -3;
}

/// Native function typedefs
typedef ApplyStickerMaskNativeC =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8> pixels,
      ffi.Pointer<ffi.Double> mask,
      ffi.Int32 width,
      ffi.Int32 height,
      ffi.Int32 addBorder,
      RGBColor borderColor,
      ffi.Int32 borderWidth,
      ffi.Pointer<ffi.Double> expandedMask,
    );

typedef ApplyStickerMaskNativeDart =
    int Function(
      ffi.Pointer<ffi.Uint8> pixels,
      ffi.Pointer<ffi.Double> mask,
      int width,
      int height,
      int addBorder,
      RGBColor borderColor,
      int borderWidth,
      ffi.Pointer<ffi.Double> expandedMask,
    );

typedef SmoothMaskNativeC =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Double> mask,
      ffi.Pointer<ffi.Double> output,
      ffi.Int32 width,
      ffi.Int32 height,
      ffi.Int32 kernelSize,
    );

typedef SmoothMaskNativeDart =
    int Function(
      ffi.Pointer<ffi.Double> mask,
      ffi.Pointer<ffi.Double> output,
      int width,
      int height,
      int kernelSize,
    );

typedef ExpandMaskNativeC =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Double> mask,
      ffi.Pointer<ffi.Double> output,
      ffi.Int32 width,
      ffi.Int32 height,
      ffi.Int32 borderWidth,
    );

typedef ExpandMaskNativeDart =
    int Function(
      ffi.Pointer<ffi.Double> mask,
      ffi.Pointer<ffi.Double> output,
      int width,
      int height,
      int borderWidth,
    );

/// Native library loader
class NativeMaskProcessor {
  static const int _maxNativeAllocationBytes = 256 * 1024 * 1024;

  static ffi.DynamicLibrary? _lib;
  static ApplyStickerMaskNativeDart? _applyStickerMaskOptimized;
  static SmoothMaskNativeDart? _smoothMaskOptimized;
  static ExpandMaskNativeDart? _expandMaskNative;

  static bool _initialized = false;
  static bool _available = false;

  /// Initialize the native library
  static bool initialize() {
    if (_initialized) return _available;

    try {
      if (Platform.isAndroid) {
        _lib = ffi.DynamicLibrary.open('libflutter_sticker_maker_native.so');
      } else if (Platform.isIOS) {
        _lib = ffi.DynamicLibrary.process();
      } else {
        _initialized = true;
        _available = false;
        return false;
      }

      // Load function pointers
      _applyStickerMaskOptimized =
          _lib!
              .lookup<ffi.NativeFunction<ApplyStickerMaskNativeC>>(
                'apply_sticker_mask_optimized',
              )
              .asFunction<ApplyStickerMaskNativeDart>();

      _smoothMaskOptimized =
          _lib!
              .lookup<ffi.NativeFunction<SmoothMaskNativeC>>(
                'smooth_mask_optimized',
              )
              .asFunction<SmoothMaskNativeDart>();

      _expandMaskNative =
          _lib!
              .lookup<ffi.NativeFunction<ExpandMaskNativeC>>(
                'expand_mask_native',
              )
              .asFunction<ExpandMaskNativeDart>();

      _available = true;
    } catch (e) {
      _available = false;
    }

    _initialized = true;
    return _available;
  }

  /// Check if native processing is available
  static bool get isAvailable => _available;

  static int? _checkedElementCount(int width, int height, [int channels = 1]) {
    if (width <= 0 || height <= 0 || channels <= 0) {
      return null;
    }

    final pixelCount = width * height;
    final elementCount = pixelCount * channels;
    if (pixelCount <= 0 || elementCount <= 0) {
      return null;
    }

    return elementCount;
  }

  static bool _canAllocate(int elementCount, int elementSize) {
    if (elementCount <= 0 || elementSize <= 0) {
      return false;
    }

    final maxElements = _maxNativeAllocationBytes ~/ elementSize;
    return elementCount <= maxElements;
  }

  /// Apply sticker mask effects using native code
  static int applyStickerMask(
    Uint8List pixels,
    List<double> mask,
    int width,
    int height,
    bool addBorder,
    List<int> borderColorRgb,
    int borderWidth,
    List<double>? expandedMask,
  ) {
    if (!_available || _applyStickerMaskOptimized == null) {
      return MaskProcessorResult.errorProcessing;
    }

    // Validate input parameters
    if (pixels.isEmpty ||
        mask.isEmpty ||
        width <= 0 ||
        height <= 0 ||
        borderWidth < 0 ||
        borderColorRgb.length < 3) {
      return MaskProcessorResult.errorInvalidParams;
    }

    // Validate array sizes
    final expectedPixelCount = _checkedElementCount(width, height, 4);
    final expectedMaskCount = _checkedElementCount(width, height);

    if (expectedPixelCount == null ||
        expectedMaskCount == null ||
        !_canAllocate(expectedPixelCount, ffi.sizeOf<ffi.Uint8>()) ||
        !_canAllocate(expectedMaskCount, ffi.sizeOf<ffi.Double>()) ||
        pixels.length != expectedPixelCount ||
        mask.length != expectedMaskCount ||
        (expandedMask != null && expandedMask.length != expectedMaskCount)) {
      return MaskProcessorResult.errorInvalidParams;
    }

    // Allocate native memory with proper size checks
    ffi.Pointer<ffi.Uint8> pixelsPtr = ffi.nullptr;
    ffi.Pointer<ffi.Double> maskPtr = ffi.nullptr;
    ffi.Pointer<ffi.Double> expandedMaskPtr = ffi.nullptr;
    ffi.Pointer<RGBColor> borderColor = ffi.nullptr;

    try {
      // Allocate memory
      pixelsPtr = malloc.allocate<ffi.Uint8>(
        pixels.length * ffi.sizeOf<ffi.Uint8>(),
      );
      maskPtr = malloc.allocate<ffi.Double>(
        mask.length * ffi.sizeOf<ffi.Double>(),
      );

      if (expandedMask != null && expandedMask.isNotEmpty) {
        if (!_canAllocate(expandedMask.length, ffi.sizeOf<ffi.Double>())) {
          return MaskProcessorResult.errorMemory;
        }
        expandedMaskPtr = malloc.allocate<ffi.Double>(
          expandedMask.length * ffi.sizeOf<ffi.Double>(),
        );
      }

      // Verify pointers are valid
      if (pixelsPtr == ffi.nullptr || maskPtr == ffi.nullptr) {
        return MaskProcessorResult.errorMemory;
      }

      // Copy data to native memory safely
      pixelsPtr.asTypedList(pixels.length).setAll(0, pixels);
      maskPtr.asTypedList(mask.length).setAll(0, mask);

      if (expandedMask != null && expandedMaskPtr != ffi.nullptr) {
        expandedMaskPtr
            .asTypedList(expandedMask.length)
            .setAll(0, expandedMask);
      }

      // Create border color
      borderColor = malloc.allocate<RGBColor>(ffi.sizeOf<RGBColor>());
      if (borderColor == ffi.nullptr) {
        return MaskProcessorResult.errorMemory;
      }

      borderColor.ref.r = borderColorRgb[0];
      borderColor.ref.g = borderColorRgb[1];
      borderColor.ref.b = borderColorRgb[2];

      // Call native function
      final result = _applyStickerMaskOptimized!(
        pixelsPtr,
        maskPtr,
        width,
        height,
        addBorder ? 1 : 0,
        borderColor.ref,
        borderWidth,
        expandedMaskPtr,
      );

      // Copy result back safely
      if (result == MaskProcessorResult.success) {
        pixels.setAll(0, pixelsPtr.asTypedList(pixels.length));
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error in applyStickerMask: $e');
      }
      return MaskProcessorResult.errorProcessing;
    } finally {
      // Clean up allocated memory
      if (pixelsPtr != ffi.nullptr) {
        malloc.free(pixelsPtr);
      }
      if (maskPtr != ffi.nullptr) {
        malloc.free(maskPtr);
      }
      if (expandedMaskPtr != ffi.nullptr) {
        malloc.free(expandedMaskPtr);
      }
      if (borderColor != ffi.nullptr) {
        malloc.free(borderColor);
      }
    }
  }

  /// Smooth mask using native code
  static int smoothMask(
    List<double> mask,
    List<double> output,
    int width,
    int height,
    int kernelSize,
  ) {
    if (!_available || _smoothMaskOptimized == null) {
      return MaskProcessorResult.errorProcessing;
    }

    // Validate input parameters
    if (mask.isEmpty ||
        output.isEmpty ||
        width <= 0 ||
        height <= 0 ||
        kernelSize <= 0) {
      return MaskProcessorResult.errorInvalidParams;
    }

    // Validate array sizes
    final expectedSize = _checkedElementCount(width, height);
    if (expectedSize == null ||
        !_canAllocate(expectedSize, ffi.sizeOf<ffi.Double>()) ||
        mask.length != expectedSize ||
        output.length != expectedSize) {
      return MaskProcessorResult.errorInvalidParams;
    }

    ffi.Pointer<ffi.Double> maskPtr = ffi.nullptr;
    ffi.Pointer<ffi.Double> outputPtr = ffi.nullptr;

    try {
      // Allocate memory with proper size calculation
      maskPtr = malloc.allocate<ffi.Double>(
        mask.length * ffi.sizeOf<ffi.Double>(),
      );
      outputPtr = malloc.allocate<ffi.Double>(
        output.length * ffi.sizeOf<ffi.Double>(),
      );

      // Verify pointers are valid
      if (maskPtr == ffi.nullptr || outputPtr == ffi.nullptr) {
        return MaskProcessorResult.errorMemory;
      }

      // Copy data to native memory safely
      maskPtr.asTypedList(mask.length).setAll(0, mask);

      // Call native function
      final result = _smoothMaskOptimized!(
        maskPtr,
        outputPtr,
        width,
        height,
        kernelSize,
      );

      // Copy result back safely
      if (result == MaskProcessorResult.success) {
        output.setAll(0, outputPtr.asTypedList(output.length));
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error in smoothMask: $e');
      }
      return MaskProcessorResult.errorProcessing;
    } finally {
      // Clean up allocated memory
      if (maskPtr != ffi.nullptr) {
        malloc.free(maskPtr);
      }
      if (outputPtr != ffi.nullptr) {
        malloc.free(outputPtr);
      }
    }
  }

  /// Expand mask using native code
  static int expandMask(
    List<double> mask,
    List<double> output,
    int width,
    int height,
    int borderWidth,
  ) {
    if (!_available || _expandMaskNative == null) {
      return MaskProcessorResult.errorProcessing;
    }

    // Validate input parameters
    if (mask.isEmpty ||
        output.isEmpty ||
        width <= 0 ||
        height <= 0 ||
        borderWidth < 0) {
      return MaskProcessorResult.errorInvalidParams;
    }

    // Validate array sizes
    final expectedSize = _checkedElementCount(width, height);
    if (expectedSize == null ||
        !_canAllocate(expectedSize, ffi.sizeOf<ffi.Double>()) ||
        mask.length != expectedSize ||
        output.length != expectedSize) {
      return MaskProcessorResult.errorInvalidParams;
    }

    ffi.Pointer<ffi.Double> maskPtr = ffi.nullptr;
    ffi.Pointer<ffi.Double> outputPtr = ffi.nullptr;

    try {
      // Allocate memory with proper size calculation
      maskPtr = malloc.allocate<ffi.Double>(
        mask.length * ffi.sizeOf<ffi.Double>(),
      );
      outputPtr = malloc.allocate<ffi.Double>(
        output.length * ffi.sizeOf<ffi.Double>(),
      );

      // Verify pointers are valid
      if (maskPtr == ffi.nullptr || outputPtr == ffi.nullptr) {
        return MaskProcessorResult.errorMemory;
      }

      // Copy data to native memory safely
      maskPtr.asTypedList(mask.length).setAll(0, mask);

      // Call native function
      final result = _expandMaskNative!(
        maskPtr,
        outputPtr,
        width,
        height,
        borderWidth,
      );

      // Copy result back safely
      if (result == MaskProcessorResult.success) {
        output.setAll(0, outputPtr.asTypedList(output.length));
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error in expandMask: $e');
      }
      return MaskProcessorResult.errorProcessing;
    } finally {
      // Clean up allocated memory
      if (maskPtr != ffi.nullptr) {
        malloc.free(maskPtr);
      }
      if (outputPtr != ffi.nullptr) {
        malloc.free(outputPtr);
      }
    }
  }
}
