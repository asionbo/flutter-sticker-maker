import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sticker_maker/src/constants.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'dart:ui' as ui;
import 'dart:developer' as dev;

/// Memory pool for reusing byte arrays
class _MemoryPool {
  static final Map<int, List<Uint8List>> _pools = {};
  static const int _maxPoolSize = 5;

  static Uint8List getBuffer(int size) {
    final pool = _pools[size];
    if (pool != null && pool.isNotEmpty) {
      return pool.removeLast();
    }
    return Uint8List(size);
  }

  static void returnBuffer(Uint8List buffer) {
    final size = buffer.length;
    final pool = _pools.putIfAbsent(size, () => <Uint8List>[]);
    if (pool.length < _maxPoolSize) {
      // Clear buffer and return to pool
      buffer.fillRange(0, buffer.length, 0);
      pool.add(buffer);
    }
  }

  static void clear() {
    _pools.clear();
  }
}

/// Cache for processed masks and resized images
class _ProcessingCache {
  static final Map<String, List<double>> _maskCache = {};
  static final Map<String, ui.Image> _imageCache = {};
  static const int _maxCacheSize = 10;

  static String _generateKey(Uint8List data, int width, int height) {
    // Simple hash based on data characteristics
    int hash = width.hashCode ^ height.hashCode;
    for (int i = 0; i < math.min(data.length, 100); i += 10) {
      hash ^= data[i].hashCode;
    }
    return hash.toString();
  }

  static List<double>? getMask(String key) => _maskCache[key];

  static void putMask(String key, List<double> mask) {
    if (_maskCache.length >= _maxCacheSize) {
      _maskCache.remove(_maskCache.keys.first);
    }
    _maskCache[key] = mask;
  }

  static ui.Image? getImage(String key) => _imageCache[key];

  static void putImage(String key, ui.Image image) {
    if (_imageCache.length >= _maxCacheSize) {
      final oldKey = _imageCache.keys.first;
      _imageCache[oldKey]?.dispose();
      _imageCache.remove(oldKey);
    }
    _imageCache[key] = image;
  }

  static void clear() {
    _imageCache.values.forEach((image) => image.dispose());
    _maskCache.clear();
    _imageCache.clear();
  }
}

/// ONNX-based implementation for background removal and sticker creation
class OnnxStickerProcessor {
  static OrtSession? _session;
  static bool _isInitialized = false;
  static bool _isInitializing = false;
  static final Map<int, Float32List> _floatBufferPool = {};

  // Pre-computed constants for better performance
  static const mean = [0.485, 0.456, 0.406];
  static const invStd = [1.0 / 0.229, 1.0 / 0.224, 1.0 / 0.225];

  /// Initialize the ONNX session with the segmentation model
  static Future<void> initialize() async {
    if (_isInitialized || _isInitializing) return;

    _isInitializing = true;
    try {
      /// Initialize the ONNX runtime environment.
      await initializeOrt();
      _isInitialized = true;
    } catch (e) {
      _isInitialized = false;
      throw Exception('Failed to initialize ONNX model: $e');
    } finally {
      _isInitializing = false;
    }
  }

  static Future<void> initializeOrt() async {
    try {
      /// Initialize the ONNX runtime environment.
      OrtEnv.instance.init();

      /// Create the ONNX session.
      await _createSession();
    } catch (e) {
      dev.log(e.toString());
    }
  }

  /// Creates an ONNX session using the model from assets.
  static Future<void> _createSession() async {
    try {
      /// Session configuration options.
      final sessionOptions = OrtSessionOptions();

      /// Load the model as a raw asset.
      final rawAssetFile = await rootBundle.load(StickerDefaults.onnxModelPath);

      /// Convert the asset to a byte array.
      final bytes = rawAssetFile.buffer.asUint8List();

      /// Create the ONNX session.
      _session = OrtSession.fromBuffer(bytes, sessionOptions);
      sessionOptions.release();
      if (kDebugMode) {
        dev.log(
          'ONNX session created successfully.',
          name: "FlutterStickerMaker",
        );
      }
    } catch (e) {
      if (kDebugMode) {
        dev.log('Error creating ONNX session: $e', name: "FlutterStickerMaker");
      }
    }
  }

  /// Create a sticker using ONNX-based background removal
  static Future<Uint8List?> makeSticker(
    Uint8List imageBytes, {
    bool addBorder = true,
    String borderColor = '#FFFFFF',
    double borderWidth = 12.0,
  }) async {
    // Only initialize if not already done
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Decode the input image
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      // Convert to bytes for processing
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) return null;

      final width = image.width;
      final height = image.height;
      final pixels = byteData.buffer.asUint8List();

      // Check cache first
      final cacheKey = _ProcessingCache._generateKey(pixels, width, height);
      List<double>? mask = _ProcessingCache.getMask(cacheKey);

      if (mask == null) {
        // Use actual ONNX model for background removal
        mask = await _runOnnxInference(pixels, width, height);
        _ProcessingCache.putMask(cacheKey, mask);
      }

      // Apply the mask and create the sticker with async processing
      final stickerBytes = await _applyStickerEffectsAsync(
        pixels,
        mask,
        width,
        height,
        addBorder: addBorder,
        borderColor: borderColor,
        borderWidth: borderWidth,
      );

      return stickerBytes;
    } catch (e) {
      throw Exception('ONNX sticker processing failed: $e');
    }
  }

  /// Run ONNX model inference for background segmentation
  static Future<List<double>> _runOnnxInference(
    Uint8List pixels,
    int width,
    int height,
  ) async {
    if (_session == null) {
      throw Exception('ONNX session not initialized');
    }

    try {
      // Preprocess image for ONNX model input with memory pooling
      final inputTensor = await _preprocessImageForOnnxOptimized(
        pixels,
        width,
        height,
      );

      // Run inference with correct input name
      final inputs = {'input.1': inputTensor};
      final runOptions = OrtRunOptions();
      final outputs = await _session!.runAsync(runOptions, inputs);

      // Extract mask from output
      final mask = await _postprocessOnnxOutputOptimized(
        outputs,
        width,
        height,
      );

      // Clean up tensors
      inputTensor.release();
      runOptions.release();
      outputs?.forEach((output) {
        output?.release();
      });

      return mask;
    } catch (e) {
      if (kDebugMode) {
        dev.log('ONNX inference failed: $e', name: "FlutterStickerMaker");
      }
      throw Exception('ONNX inference failed: $e');
    }
  }

  /// Optimized preprocessing with memory pooling and efficient operations
  static Future<OrtValueTensor> _preprocessImageForOnnxOptimized(
    Uint8List pixels,
    int originalWidth,
    int originalHeight,
  ) async {
    const modelInputSize = 320;
    final cacheKey = '${originalWidth}x${originalHeight}_$modelInputSize';

    // Try to get cached resized image
    ui.Image? resizedImage = _ProcessingCache.getImage(cacheKey);

    if (resizedImage == null) {
      // Convert to ui.Image first
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pixels,
        originalWidth,
        originalHeight,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final originalImage = await completer.future;

      // Resize image
      resizedImage = await _resizeImageToModelOptimized(
        originalImage,
        modelInputSize,
      );

      _ProcessingCache.putImage(cacheKey, resizedImage);
      originalImage.dispose();
    }

    // Convert to normalized tensor data with pooled buffer
    final normalizedData = await _imageToFloatTensorOptimized(
      resizedImage,
      modelInputSize,
    );

    // Create tensor with shape [1, 3, 320, 320] (NCHW format)
    final inputShape = [1, 3, modelInputSize, modelInputSize];
    final tensor = OrtValueTensor.createTensorWithDataList(
      normalizedData,
      inputShape,
    );

    return tensor;
  }

  /// Optimized image resizing using direct pixel manipulation
  static Future<ui.Image> _resizeImageToModelOptimized(
    ui.Image image,
    int targetSize,
  ) async {
    // Use a more efficient resizing approach for better performance
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint =
        ui.Paint()
          ..filterQuality =
              ui
                  .FilterQuality
                  .medium // Balanced quality/performance
          ..isAntiAlias = false; // Faster rendering

    final srcRect = ui.Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dstRect = ui.Rect.fromLTWH(
      0,
      0,
      targetSize.toDouble(),
      targetSize.toDouble(),
    );
    canvas.drawImageRect(image, srcRect, dstRect, paint);

    final picture = recorder.endRecording();
    return picture.toImage(targetSize, targetSize);
  }

  /// Optimized tensor conversion with memory pooling
  static Future<Float32List> _imageToFloatTensorOptimized(
    ui.Image image,
    int modelInputSize,
  ) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) throw Exception("Failed to get image ByteData");

    final rgbaBytes = byteData.buffer.asUint8List();
    final pixelCount = modelInputSize * modelInputSize;

    // Use pooled buffer if available
    final bufferSize = pixelCount * 3;
    Float32List floats =
        _floatBufferPool[bufferSize] ?? Float32List(bufferSize);
    _floatBufferPool[bufferSize] = floats;

    // Pre-compute division

    // Optimized loop with direct array access
    for (int i = 0; i < pixelCount; i++) {
      final baseIndex = i * 4;
      floats[i] =
          (rgbaBytes[baseIndex] * 0.00392156862745098 - mean[0]) *
          invStd[0]; // R (1/255 = 0.00392...)
      floats[pixelCount + i] =
          (rgbaBytes[baseIndex + 1] * 0.00392156862745098 - mean[1]) *
          invStd[1]; // G
      floats[2 * pixelCount + i] =
          (rgbaBytes[baseIndex + 2] * 0.00392156862745098 - mean[2]) *
          invStd[2]; // B
    }

    return floats;
  }

  /// Optimized postprocessing with efficient data handling
  static Future<List<double>> _postprocessOnnxOutputOptimized(
    List<OrtValue?>? outputs,
    int targetWidth,
    int targetHeight,
  ) async {
    if (outputs == null || outputs.isEmpty) {
      throw Exception('No output from ONNX model');
    }

    final outputTensor = outputs[0]?.value;
    if (outputTensor == null) {
      throw Exception('Output tensor is null');
    }

    // More efficient data extraction
    final flatMask = <double>[];
    _extractMaskDataOptimized(outputTensor, flatMask);

    final modelOutputSize = math.sqrt(flatMask.length).round();

    // Use optimized resize with pre-allocated buffer
    return _resizeMaskBilinearOptimized(
      flatMask,
      modelOutputSize,
      modelOutputSize,
      targetWidth,
      targetHeight,
    );
  }

  /// Optimized mask data extraction
  static void _extractMaskDataOptimized(
    dynamic outputTensor,
    List<double> flatMask,
  ) {
    if (outputTensor is List && outputTensor.isNotEmpty) {
      dynamic maskData;
      if (outputTensor[0] is List && outputTensor[0][0] is List) {
        maskData = outputTensor[0][0];
      } else if (outputTensor[0] is List) {
        maskData = outputTensor[0];
      } else {
        throw Exception('Unexpected output tensor format');
      }

      // Direct conversion without nested loops where possible
      for (var row in maskData) {
        if (row is List) {
          flatMask.addAll(row.map<double>((e) => e.toDouble()));
        } else {
          flatMask.add(row.toDouble());
        }
      }
    } else {
      throw Exception('Invalid output tensor structure');
    }
  }

  /// Optimized bilinear resize with pre-allocated memory
  static List<double> _resizeMaskBilinearOptimized(
    List<double> mask,
    int sourceWidth,
    int sourceHeight,
    int targetWidth,
    int targetHeight,
  ) {
    final resized = Float64List(
      targetWidth * targetHeight,
    ); // Use typed list for better performance

    // Pre-compute scaling factors
    final scaleX = sourceWidth / targetWidth;
    final scaleY = sourceHeight / targetHeight;

    for (int y = 0; y < targetHeight; y++) {
      final srcY = y * scaleY;
      final y1 = srcY.floor();
      final y2 = (y1 + 1).clamp(0, sourceHeight - 1);
      final wy = srcY - y1;
      final wy1 = 1.0 - wy;

      for (int x = 0; x < targetWidth; x++) {
        final srcX = x * scaleX;
        final x1 = srcX.floor();
        final x2 = (x1 + 1).clamp(0, sourceWidth - 1);
        final wx = srcX - x1;
        final wx1 = 1.0 - wx;

        // Get values from source mask with direct indexing
        final q11 = mask[y1 * sourceWidth + x1];
        final q21 = mask[y1 * sourceWidth + x2];
        final q12 = mask[y2 * sourceWidth + x1];
        final q22 = mask[y2 * sourceWidth + x2];

        // Optimized bilinear interpolation
        resized[y * targetWidth + x] =
            q11 * wx1 * wy1 + q21 * wx * wy1 + q12 * wx1 * wy + q22 * wx * wy;
      }
    }

    return resized;
  }

  /// Safe async sticker effects application with yield points
  static Future<Uint8List> _applyStickerEffectsAsync(
    Uint8List pixels,
    List<double> mask,
    int width,
    int height, {
    required bool addBorder,
    required String borderColor,
    required double borderWidth,
  }) async {
    // Use memory pool for result buffer
    final result = _MemoryPool.getBuffer(width * height * 4);
    final borderColorRgb = _parseBorderColorOptimized(borderColor);
    final borderWidthInt = borderWidth.round();

    // Apply smoothing to the mask for better edges with yield points
    final smoothedMask = await _smoothMaskAsync(mask, width, height, 3);

    // Create expanded mask for border if needed
    List<double>? expandedMask;
    if (addBorder && borderWidthInt > 0) {
      expandedMask = await _expandMaskAsync(
        smoothedMask,
        width,
        height,
        borderWidthInt,
      );
    }

    const threshold = 0.5;
    const thresholdHigh = threshold + 0.05;
    const thresholdLow = threshold - 0.05;
    const thresholdRange = 0.1;

    // Process in chunks to avoid blocking the main thread
    const chunkSize = 10000; // Process 10k pixels at a time
    final totalPixels = width * height;

    for (int chunk = 0; chunk < totalPixels; chunk += chunkSize) {
      final endChunk = math.min(chunk + chunkSize, totalPixels);

      // Process chunk
      for (int i = chunk; i < endChunk; i++) {
        final pixelIndex = i * 4;
        final maskValue = smoothedMask[i];
        final expandedMaskValue = expandedMask?[i] ?? maskValue;

        if (maskValue > thresholdHigh) {
          // Foreground pixel - direct copy
          result[pixelIndex] = pixels[pixelIndex];
          result[pixelIndex + 1] = pixels[pixelIndex + 1];
          result[pixelIndex + 2] = pixels[pixelIndex + 2];
          result[pixelIndex + 3] = 255;
        } else if (maskValue < thresholdLow) {
          if (addBorder && expandedMaskValue > threshold) {
            // Border pixel
            result[pixelIndex] = borderColorRgb[0];
            result[pixelIndex + 1] = borderColorRgb[1];
            result[pixelIndex + 2] = borderColorRgb[2];
            result[pixelIndex + 3] = 255;
          } else {
            // Background pixel - transparent (already zeroed by pool)
            result[pixelIndex + 3] = 0;
          }
        } else {
          // Smooth transition - optimized alpha calculation
          result[pixelIndex] = pixels[pixelIndex];
          result[pixelIndex + 1] = pixels[pixelIndex + 1];
          result[pixelIndex + 2] = pixels[pixelIndex + 2];
          result[pixelIndex + 3] = ((maskValue - thresholdLow) /
                  thresholdRange *
                  255)
              .round()
              .clamp(0, 255);
        }
      }

      // Yield control back to the event loop periodically
      if (chunk % (chunkSize * 5) == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    // Convert RGBA bytes back to PNG format
    final pngBytes = await _encodeToPng(result, width, height);

    // Return buffer to pool
    _MemoryPool.returnBuffer(result);

    return pngBytes;
  }

  /// Async mask smoothing with yield points
  static Future<List<double>> _smoothMaskAsync(
    List<double> mask,
    int width,
    int height,
    int kernelSize,
  ) async {
    if (kernelSize <= 1) return mask;

    // Use separable blur for O(n) instead of O(n²) complexity
    final temp = Float64List(width * height);
    final smoothed = Float64List(width * height);
    final halfKernel = kernelSize ~/ 2;

    // Horizontal pass with yield points
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        double sum = 0.0;
        int count = 0;

        for (int kx = -halfKernel; kx <= halfKernel; kx++) {
          final nx = x + kx;
          if (nx >= 0 && nx < width) {
            sum += mask[y * width + nx];
            count++;
          }
        }
        temp[y * width + x] = sum / count;
      }

      // Yield every 50 rows
      if (y % 50 == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    // Vertical pass with yield points
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        double sum = 0.0;
        int count = 0;

        for (int ky = -halfKernel; ky <= halfKernel; ky++) {
          final ny = y + ky;
          if (ny >= 0 && ny < height) {
            sum += temp[ny * width + x];
            count++;
          }
        }
        smoothed[y * width + x] = sum / count;
      }

      // Yield every 50 rows
      if (y % 50 == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    return smoothed;
  }

  /// Async mask expansion with yield points
  static Future<List<double>> _expandMaskAsync(
    List<double> mask,
    int width,
    int height,
    int borderWidth,
  ) async {
    final expanded = Float64List(width * height);
    final borderWidthSq = borderWidth * borderWidth;

    // Use a more efficient flood-fill approach with yield points
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (mask[y * width + x] > 0.5) {
          final startY = math.max(0, y - borderWidth);
          final endY = math.min(height - 1, y + borderWidth);
          final startX = math.max(0, x - borderWidth);
          final endX = math.min(width - 1, x + borderWidth);

          for (int ny = startY; ny <= endY; ny++) {
            for (int nx = startX; nx <= endX; nx++) {
              final dx = nx - x;
              final dy = ny - y;
              final distanceSq = dx * dx + dy * dy;
              if (distanceSq <= borderWidthSq) {
                expanded[ny * width + nx] = 1.0;
              }
            }
          }
        }
      }

      // Yield every 20 rows to prevent blocking
      if (y % 20 == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    return expanded;
  }

  /// Optimized border color parsing with caching
  static final Map<String, List<int>> _colorCache = {};

  static List<int> _parseBorderColorOptimized(String colorString) {
    if (_colorCache.containsKey(colorString)) {
      return _colorCache[colorString]!;
    }

    String hex =
        colorString.startsWith('#') ? colorString.substring(1) : colorString;
    if (hex.length != 6) hex = 'FFFFFF';

    List<int> rgb;
    try {
      final value = int.parse(hex, radix: 16);
      rgb = [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF];
    } catch (e) {
      rgb = [255, 255, 255];
    }

    _colorCache[colorString] = rgb;
    return rgb;
  }

  static Future<Uint8List> _encodeToPng(
    Uint8List rgbaBytes,
    int width,
    int height,
  ) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgbaBytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );

    final image = await completer.future;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Clean up resources
  static void dispose() {
    try {
      _session?.release();
      _session = null;
      OrtEnv.instance.release();
      _isInitialized = false;
      _isInitializing = false;

      // Clear caches and memory pools
      _ProcessingCache.clear();
      _MemoryPool.clear();
      _floatBufferPool.clear();
      _colorCache.clear();
    } catch (e) {
      // Log error but don't throw to prevent app crashes during disposal
      if (kDebugMode) {
        dev.log(
          'Error disposing ONNX resources: $e',
          name: "FlutterStickerMaker",
        );
      }
    }
  }
}
