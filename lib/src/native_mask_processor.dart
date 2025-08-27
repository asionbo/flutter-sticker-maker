import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

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
typedef ApplyStickerMaskNativeC = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> pixels,
  ffi.Pointer<ffi.Double> mask,
  ffi.Int32 width,
  ffi.Int32 height,
  ffi.Int32 addBorder,
  RGBColor borderColor,
  ffi.Int32 borderWidth,
  ffi.Pointer<ffi.Double> expandedMask,
);

typedef ApplyStickerMaskNativeDart = int Function(
  ffi.Pointer<ffi.Uint8> pixels,
  ffi.Pointer<ffi.Double> mask,
  int width,
  int height,
  int addBorder,
  RGBColor borderColor,
  int borderWidth,
  ffi.Pointer<ffi.Double> expandedMask,
);

typedef SmoothMaskNativeC = ffi.Int32 Function(
  ffi.Pointer<ffi.Double> mask,
  ffi.Pointer<ffi.Double> output,
  ffi.Int32 width,
  ffi.Int32 height,
  ffi.Int32 kernelSize,
);

typedef SmoothMaskNativeDart = int Function(
  ffi.Pointer<ffi.Double> mask,
  ffi.Pointer<ffi.Double> output,
  int width,
  int height,
  int kernelSize,
);

typedef ExpandMaskNativeC = ffi.Int32 Function(
  ffi.Pointer<ffi.Double> mask,
  ffi.Pointer<ffi.Double> output,
  ffi.Int32 width,
  ffi.Int32 height,
  ffi.Int32 borderWidth,
);

typedef ExpandMaskNativeDart = int Function(
  ffi.Pointer<ffi.Double> mask,
  ffi.Pointer<ffi.Double> output,
  int width,
  int height,
  int borderWidth,
);

/// Native library loader
class NativeMaskProcessor {
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
      _applyStickerMaskOptimized = _lib!
          .lookup<ffi.NativeFunction<ApplyStickerMaskNativeC>>('apply_sticker_mask_optimized')
          .asFunction<ApplyStickerMaskNativeDart>();

      _smoothMaskOptimized = _lib!
          .lookup<ffi.NativeFunction<SmoothMaskNativeC>>('smooth_mask_optimized')
          .asFunction<SmoothMaskNativeDart>();

      _expandMaskNative = _lib!
          .lookup<ffi.NativeFunction<ExpandMaskNativeC>>('expand_mask_native')
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

    // Allocate native memory
    final pixelsPtr = ffi.malloc.allocate<ffi.Uint8>(pixels.length);
    final maskPtr = ffi.malloc.allocate<ffi.Double>(mask.length);
    final expandedMaskPtr = expandedMask != null 
        ? ffi.malloc.allocate<ffi.Double>(expandedMask.length)
        : ffi.nullptr;

    try {
      // Copy data to native memory
      final pixelsNative = pixelsPtr.asTypedList(pixels.length);
      pixelsNative.setAll(0, pixels);

      final maskNative = maskPtr.asTypedList(mask.length);
      maskNative.setAll(0, mask);

      if (expandedMask != null) {
        final expandedMaskNative = expandedMaskPtr.asTypedList(expandedMask.length);
        expandedMaskNative.setAll(0, expandedMask);
      }

      // Create border color
      final borderColor = ffi.malloc.allocate<RGBColor>(ffi.sizeOf<RGBColor>());
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

      // Copy result back
      if (result == MaskProcessorResult.success) {
        pixels.setAll(0, pixelsNative);
      }

      ffi.malloc.free(borderColor);
      return result;
    } finally {
      ffi.malloc.free(pixelsPtr);
      ffi.malloc.free(maskPtr);
      if (expandedMaskPtr != ffi.nullptr) {
        ffi.malloc.free(expandedMaskPtr);
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

    final maskPtr = ffi.malloc.allocate<ffi.Double>(mask.length);
    final outputPtr = ffi.malloc.allocate<ffi.Double>(output.length);

    try {
      final maskNative = maskPtr.asTypedList(mask.length);
      maskNative.setAll(0, mask);

      final result = _smoothMaskOptimized!(
        maskPtr,
        outputPtr,
        width,
        height,
        kernelSize,
      );

      if (result == MaskProcessorResult.success) {
        final outputNative = outputPtr.asTypedList(output.length);
        output.setAll(0, outputNative);
      }

      return result;
    } finally {
      ffi.malloc.free(maskPtr);
      ffi.malloc.free(outputPtr);
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

    final maskPtr = ffi.malloc.allocate<ffi.Double>(mask.length);
    final outputPtr = ffi.malloc.allocate<ffi.Double>(output.length);

    try {
      final maskNative = maskPtr.asTypedList(mask.length);
      maskNative.setAll(0, mask);

      final result = _expandMaskNative!(
        maskPtr,
        outputPtr,
        width,
        height,
        borderWidth,
      );

      if (result == MaskProcessorResult.success) {
        final outputNative = outputPtr.asTypedList(output.length);
        output.setAll(0, outputNative);
      }

      return result;
    } finally {
      ffi.malloc.free(maskPtr);
      ffi.malloc.free(outputPtr);
    }
  }
}