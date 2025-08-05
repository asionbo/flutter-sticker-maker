import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sticker_maker/src/constants.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'dart:ui' as ui;
import 'dart:developer' as dev;

/// ONNX-based implementation for background removal and sticker creation
class OnnxStickerProcessor {
  static OrtSession? _session;
  static bool _isInitialized = false;

  /// Initialize the ONNX session with the segmentation model
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      /// Initialize the ONNX runtime environment.
      await initializeOrt();
      _isInitialized = true;
    } catch (e) {
      throw Exception('Failed to initialize ONNX model: $e');
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
    await initialize();

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

      // Use actual ONNX model for background removal
      final mask = await _runOnnxInference(pixels, width, height);

      // Apply the mask and create the sticker
      final stickerBytes = await _applyStickerEffects(
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
      // Preprocess image for ONNX model input
      final inputTensor = await _preprocessImageForOnnx(pixels, width, height);

      // Run inference with correct input name
      final inputs = {'input.1': inputTensor};
      final runOptions = OrtRunOptions();
      final outputs = await _session!.runAsync(runOptions, inputs);

      // Extract mask from output
      final mask = await _postprocessOnnxOutput(outputs, width, height);

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

  /// Preprocess image data for ONNX model input
  static Future<OrtValueTensor> _preprocessImageForOnnx(
    Uint8List pixels,
    int originalWidth,
    int originalHeight,
  ) async {
    // Most segmentation models expect 320x320 input
    const modelInputSize = 320;

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
    final resizedImage = await _resizeImageToModel(
      originalImage,
      modelInputSize,
    );

    // Convert to normalized tensor data
    final normalizedData = await _imageToFloatTensor(resizedImage);

    // Create tensor with shape [1, 3, 320, 320] (NCHW format)
    final inputShape = [1, 3, modelInputSize, modelInputSize];
    final tensor = OrtValueTensor.createTensorWithDataList(
      normalizedData,
      inputShape,
    );

    // Clean up
    originalImage.dispose();
    resizedImage.dispose();

    return tensor;
  }

  /// Resize image for model input
  static Future<ui.Image> _resizeImageToModel(
    ui.Image image,
    int targetSize,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.high;

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

  /// Convert image to normalized float tensor (ImageNet normalization)
  static Future<Float32List> _imageToFloatTensor(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) throw Exception("Failed to get image ByteData");

    final rgbaBytes = byteData.buffer.asUint8List();
    final pixelCount = image.width * image.height;
    final floats = Float32List(pixelCount * 3);

    // ImageNet mean and std
    final mean = [0.485, 0.456, 0.406];
    final std = [0.229, 0.224, 0.225];

    // Extract and normalize RGB channels with ImageNet mean/std
    for (int i = 0; i < pixelCount; i++) {
      floats[i] = (rgbaBytes[i * 4] / 255.0 - mean[0]) / std[0]; // Red
      floats[pixelCount + i] =
          (rgbaBytes[i * 4 + 1] / 255.0 - mean[1]) / std[1]; // Green
      floats[2 * pixelCount + i] =
          (rgbaBytes[i * 4 + 2] / 255.0 - mean[2]) / std[2]; // Blue
    }

    return floats;
  }

  /// Postprocess ONNX model output to extract segmentation mask
  static Future<List<double>> _postprocessOnnxOutput(
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

    // Handle the output format - expect [1, 1, H, W] or [1, H, W]
    List maskData;
    if (outputTensor is List && outputTensor.isNotEmpty) {
      if (outputTensor[0] is List && outputTensor[0][0] is List) {
        // Format: [1, 1, H, W] or [1, 2, H, W]
        maskData = outputTensor[0][0]; // Take first channel
      } else if (outputTensor[0] is List) {
        // Format: [1, H, W]
        maskData = outputTensor[0];
      } else {
        throw Exception('Unexpected output tensor format');
      }
    } else {
      throw Exception('Invalid output tensor structure');
    }

    // Convert to flat list of doubles
    final flatMask = <double>[];
    for (var row in maskData) {
      if (row is List) {
        for (var pixel in row) {
          flatMask.add(pixel.toDouble());
        }
      } else {
        flatMask.add(row.toDouble());
      }
    }

    final modelOutputSize = math.sqrt(flatMask.length).round();

    // Resize mask back to original image size using bilinear interpolation
    return _resizeMaskBilinear(
      flatMask,
      modelOutputSize,
      modelOutputSize,
      targetWidth,
      targetHeight,
    );
  }

  /// Resize mask using bilinear interpolation for smoother edges
  static List<double> _resizeMaskBilinear(
    List<double> mask,
    int sourceWidth,
    int sourceHeight,
    int targetWidth,
    int targetHeight,
  ) {
    final resized = List<double>.filled(targetWidth * targetHeight, 0.0);

    for (int y = 0; y < targetHeight; y++) {
      for (int x = 0; x < targetWidth; x++) {
        // Map to floating point coordinates in the source mask
        final srcX = x * sourceWidth / targetWidth;
        final srcY = y * sourceHeight / targetHeight;

        // Get integer coordinates for the four surrounding pixels
        final x1 = srcX.floor();
        final y1 = srcY.floor();
        final x2 = (x1 + 1).clamp(0, sourceWidth - 1);
        final y2 = (y1 + 1).clamp(0, sourceHeight - 1);

        // Calculate interpolation weights
        final wx = srcX - x1;
        final wy = srcY - y1;

        // Get values from source mask
        final q11 = mask[y1 * sourceWidth + x1];
        final q21 = mask[y1 * sourceWidth + x2];
        final q12 = mask[y2 * sourceWidth + x1];
        final q22 = mask[y2 * sourceWidth + x2];

        // Perform bilinear interpolation
        final interpolated =
            q11 * (1 - wx) * (1 - wy) +
            q21 * wx * (1 - wy) +
            q12 * (1 - wx) * wy +
            q22 * wx * wy;

        resized[y * targetWidth + x] = interpolated;
      }
    }

    return resized;
  }

  /// Apply sticker effects including mask and optional border
  static Future<Uint8List> _applyStickerEffects(
    Uint8List pixels,
    List<double> mask,
    int width,
    int height, {
    required bool addBorder,
    required String borderColor,
    required double borderWidth,
  }) async {
    final result = Uint8List(width * height * 4);
    final borderColorRgb = _parseBorderColor(borderColor);
    final borderWidthInt = borderWidth.round();

    // Apply smoothing to the mask for better edges
    final smoothedMask = _smoothMask(mask, width, height, 3);

    // Create expanded mask for border if needed
    List<double>? expandedMask;
    if (addBorder && borderWidthInt > 0) {
      expandedMask = _expandMask(smoothedMask, width, height, borderWidthInt);
    }

    const threshold = 0.5;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixelIndex = (y * width + x) * 4;
        final maskValue = smoothedMask[y * width + x];
        final expandedMaskValue = expandedMask?[y * width + x] ?? maskValue;

        int alpha;

        if (maskValue > threshold + 0.05) {
          // Foreground pixel - keep original with smooth alpha
          result[pixelIndex] = pixels[pixelIndex]; // R
          result[pixelIndex + 1] = pixels[pixelIndex + 1]; // G
          result[pixelIndex + 2] = pixels[pixelIndex + 2]; // B
          alpha = 255;
        } else if (maskValue < threshold - 0.05) {
          if (addBorder && expandedMaskValue > threshold) {
            // Border pixel
            result[pixelIndex] = borderColorRgb[0]; // R
            result[pixelIndex + 1] = borderColorRgb[1]; // G
            result[pixelIndex + 2] = borderColorRgb[2]; // B
            alpha = 255;
          } else {
            // Background pixel - transparent
            result[pixelIndex] = 0; // R
            result[pixelIndex + 1] = 0; // G
            result[pixelIndex + 2] = 0; // B
            alpha = 0;
          }
        } else {
          // Smooth transition in the boundary region
          result[pixelIndex] = pixels[pixelIndex]; // R
          result[pixelIndex + 1] = pixels[pixelIndex + 1]; // G
          result[pixelIndex + 2] = pixels[pixelIndex + 2]; // B
          alpha = ((maskValue - (threshold - 0.05)) / 0.1 * 255).round().clamp(
            0,
            255,
          );
        }

        result[pixelIndex + 3] = alpha; // A
      }
    }

    // Convert RGBA bytes back to PNG format
    return _encodeToPng(result, width, height);
  }

  /// Helper method for mask smoothing using a box blur
  static List<double> _smoothMask(
    List<double> mask,
    int width,
    int height,
    int kernelSize,
  ) {
    final smoothed = List<double>.filled(width * height, 0.0);
    final halfKernel = kernelSize ~/ 2;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        double sum = 0.0;
        int count = 0;

        for (int ky = -halfKernel; ky <= halfKernel; ky++) {
          for (int kx = -halfKernel; kx <= halfKernel; kx++) {
            final ny = y + ky;
            final nx = x + kx;

            if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
              sum += mask[ny * width + nx];
              count++;
            }
          }
        }

        smoothed[y * width + x] = sum / count;
      }
    }

    return smoothed;
  }

  static List<int> _parseBorderColor(String colorString) {
    String hex =
        colorString.startsWith('#') ? colorString.substring(1) : colorString;
    if (hex.length != 6) hex = 'FFFFFF'; // Default to white

    try {
      final value = int.parse(hex, radix: 16);
      return [
        (value >> 16) & 0xFF, // R
        (value >> 8) & 0xFF, // G
        value & 0xFF, // B
      ];
    } catch (e) {
      return [255, 255, 255]; // Default to white
    }
  }

  static List<double> _expandMask(
    List<double> mask,
    int width,
    int height,
    int borderWidth,
  ) {
    final expanded = List<double>.filled(width * height, 0.0);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (mask[y * width + x] > 0.5) {
          // Expand around this pixel
          for (int dy = -borderWidth; dy <= borderWidth; dy++) {
            for (int dx = -borderWidth; dx <= borderWidth; dx++) {
              final nx = x + dx;
              final ny = y + dy;
              if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
                final distance = math.sqrt(dx * dx + dy * dy);
                if (distance <= borderWidth) {
                  expanded[ny * width + nx] = 1.0;
                }
              }
            }
          }
        }
      }
    }

    return expanded;
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
    _session?.release();
    _session = null;
    _isInitialized = false;
  }
}
