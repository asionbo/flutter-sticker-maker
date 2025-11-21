import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'src/constants.dart';
import 'src/exceptions.dart';
import 'src/onnx_sticker_processor.dart';
import 'src/onnx_visual_effect_overlay.dart';
import 'src/visual_effect_builder.dart';

import 'dart:developer' as dev;

export 'src/constants.dart';
export 'src/exceptions.dart';
export 'src/visual_effect_builder.dart';

/// Flutter plugin for creating stickers by removing image backgrounds using ML Kit.
class FlutterStickerMaker {
  static const MethodChannel _channel = MethodChannel('flutter_sticker_maker');
  static bool _isPluginInitialized = false;
  static bool _isUsingOnnx = false;

  /// Initialize the plugin resources.
  ///
  /// This method should be called once, preferably in your app's main() function
  /// or in the initState() of your root widget for optimal performance.
  ///
  /// **Example:**
  /// ```dart
  /// void main() async {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///   await FlutterStickerMaker.initialize();
  ///   runApp(MyApp());
  /// }
  /// ```
  static Future<void> initialize() async {
    if (_isPluginInitialized) return;

    try {
      // Pre-initialize ONNX if we'll be using it
      _isUsingOnnx = await _shouldUseOnnx();
      if (_isUsingOnnx) {
        await OnnxStickerProcessor.initialize();
      }
      _isPluginInitialized = true;
    } catch (e) {
      // Don't fail initialization completely, just log the error
      // The plugin can still work with lazy initialization
      if (kDebugMode) {
        print('FlutterStickerMaker: Warning - Pre-initialization failed: $e');
      }
    }
  }

  /// Creates a sticker by removing background from an image using ML Kit.
  ///
  /// **Parameters:**
  /// - [imageBytes]: Raw image data (PNG/JPEG). Max recommended size: 2048x2048px
  /// - [addBorder]: Whether to add a border around the subject
  /// - [borderColor]: Hex color string (#RRGGBB or RRGGBB format)
  /// - [borderWidth]: Border thickness in pixels (0.0 to 50.0)
  /// - [showVisualEffect]: Whether to request the default visual effect when
  ///   [visualEffectBuilder] is null. When a builder is provided it will always
  ///   be used regardless of this flag.
  /// - [visualEffectBuilder]: Optional Flutter overlay builder that runs on
  ///   every platform. When set it replaces the native/ONNX visualizations.
  ///
  /// **Returns:**
  /// - [Uint8List?]: PNG image data with transparent background, or null if processing failed
  ///
  /// **Throws:**
  /// - [ArgumentError]: For invalid parameters
  /// - [StickerException]: For processing errors
  /// - [TimeoutException]: If processing takes longer than 30 seconds
  ///
  /// **Example:**
  /// ```dart
  /// final imageBytes = await File('photo.jpg').readAsBytes();
  /// final sticker = await FlutterStickerMaker.makeSticker(
  ///   imageBytes,
  ///   addBorder: true,
  ///   borderColor: '#FFFFFF',
  ///   borderWidth: 8.0,
  ///   showVisualEffect: true,
  ///   visualEffectBuilder: (context, request) => const Center(
  ///     child: CircularProgressIndicator.adaptive(),
  ///   ),
  /// );
  /// ```
  static Future<Uint8List?> makeSticker(
    Uint8List imageBytes, {
    bool addBorder = StickerDefaults.defaultAddBorder,
    String borderColor = StickerDefaults.defaultBorderColor,
    double borderWidth = StickerDefaults.defaultBorderWidth,
    bool showVisualEffect = StickerDefaults.defaultShowVisualEffect,
    SpeckleType speckleType = StickerDefaults.defaultSpeckleType,
    VisualEffectBuilder? visualEffectBuilder,
  }) async {
    // Validate input parameters
    _validateInput(imageBytes, borderColor, borderWidth);
    final bool wantsVisualEffect =
        showVisualEffect || visualEffectBuilder != null;

    try {
      // Determine which implementation to use based on platform and version
      _isUsingOnnx = await _shouldUseOnnx();
      if (_isUsingOnnx) {
        // Use ONNX implementation for Android and iOS < 17
        final pixelImage = await OnnxStickerProcessor.getPixelsFromImage(
          imageBytes,
        );
        if (pixelImage == null) {
          throw StickerException(
            'Failed to decode image for processing',
            errorCode: 'IMAGE_DECODING_FAILED',
          );
        }

        final mask = await OnnxStickerProcessor.generateMask(pixelImage);
        if (mask == null) {
          throw StickerException(
            'Failed to generate mask for the image',
            errorCode: 'MASK_GENERATION_FAILED',
          );
        }

        final process =
            () => OnnxStickerProcessor.applyStickerEffect(
              pixelImage,
              mask,
              addBorder: addBorder,
              borderColor: borderColor,
              borderWidth: borderWidth,
            );

        if (!wantsVisualEffect) {
          return await process();
        }

        if (visualEffectBuilder != null) {
          return await VisualEffectPresenter.run(
            imageBytes: imageBytes,
            speckleType: speckleType,
            process: process,
            builder: visualEffectBuilder,
          );
        }

        return await OnnxVisualEffectOverlay.run(
          imageBytes: imageBytes,
          speckleType: speckleType,
          process: process,
        );
      } else {
        // Use platform-specific implementation (iOS 17+ only)
        final bool shouldRequestNativeEffect =
            showVisualEffect && visualEffectBuilder == null;

        final process =
            () => _channel
                .invokeMethod<Uint8List>('makeSticker', {
                  'image': imageBytes,
                  'addBorder': addBorder,
                  'borderColor': borderColor,
                  'borderWidth': borderWidth,
                  'showVisualEffect': shouldRequestNativeEffect,
                  'speckleType': speckleType.name,
                })
                .timeout(
                  Duration(seconds: StickerDefaults.processingTimeoutSeconds),
                );

        if (visualEffectBuilder != null) {
          return await VisualEffectPresenter.run(
            imageBytes: imageBytes,
            speckleType: speckleType,
            process: process,
            builder: visualEffectBuilder,
          );
        }

        return await process();
      }
    } on TimeoutException {
      throw StickerException(
        'Processing timeout - image may be too large or complex',
        errorCode: 'TIMEOUT',
      );
    } on PlatformException catch (e) {
      throw StickerException(
        'Platform error: ${e.message ?? 'Unknown error'}',
        originalError: e,
        errorCode: e.code,
      );
    } catch (e) {
      throw StickerException(
        'Unexpected error during sticker creation',
        originalError: e,
        errorCode: 'UNKNOWN',
      );
    }
  }

  /// Determines whether to use ONNX implementation based on platform and version
  static Future<bool> _shouldUseOnnx() async {
    if (Platform.isAndroid) {
      // Android always uses ONNX
      return true;
    } else if (Platform.isIOS) {
      // iOS uses ONNX for versions below 17.0
      final version = await _getIOSVersion();
      return version < 17.0;
    }
    // Default to ONNX for other platforms
    return true;
  }

  /// Gets the iOS version number
  static Future<double> _getIOSVersion() async {
    try {
      final version = await _channel.invokeMethod<String>('getIOSVersion');
      if (version != null) {
        // Parse version string like "16.5" to double
        final parts = version.split('.');
        if (parts.isNotEmpty) {
          final major = int.tryParse(parts[0]) ?? 15;
          final minor = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
          return major + (minor / 10.0);
        }
      }
    } catch (e) {
      // If we can't determine version, assume older iOS and use ONNX
      return 15.0;
    }
    return 15.0;
  }

  /// Validates input parameters for sticker creation.
  static void _validateInput(
    Uint8List imageBytes,
    String borderColor,
    double borderWidth,
  ) {
    if (imageBytes.isEmpty) {
      throw ArgumentError('Image data cannot be empty');
    }

    if (borderWidth < StickerDefaults.minBorderWidth ||
        borderWidth > StickerDefaults.maxBorderWidth) {
      throw ArgumentError(
        'Border width must be between ${StickerDefaults.minBorderWidth} '
        'and ${StickerDefaults.maxBorderWidth}',
      );
    }

    if (!_isValidHexColor(borderColor)) {
      throw ArgumentError('Invalid color format. Use #RRGGBB or RRGGBB format');
    }

    if (!_isValidImageData(imageBytes)) {
      throw ArgumentError(
        'Invalid image format. Only PNG and JPEG are supported',
      );
    }
  }

  /// Validates hex color format.
  static bool _isValidHexColor(String color) {
    final String cleanColor =
        color.startsWith('#') ? color.substring(1) : color;
    return RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(cleanColor);
  }

  /// Validates image data format.
  static bool _isValidImageData(Uint8List data) {
    if (data.length < 8) return false;

    return _hasHeader(data, StickerDefaults.pngHeader) ||
        _hasHeader(data, StickerDefaults.jpegHeader);
  }

  /// Checks if data starts with the given header bytes.
  static bool _hasHeader(Uint8List data, List<int> header) {
    if (data.length < header.length) return false;

    for (int i = 0; i < header.length; i++) {
      if (data[i] != header[i]) return false;
    }
    return true;
  }

  /// Clean up resources used by the plugin.
  ///
  /// This method should be called when the plugin is no longer needed,
  /// typically in the dispose() method of your widget or when the app
  /// is shutting down.
  ///
  /// **Example:**
  /// ```dart
  /// @override
  /// void dispose() {
  ///   FlutterStickerMaker.dispose();
  ///   super.dispose();
  /// }
  /// ```
  static void dispose() {
    try {
      // Clean up ONNX resources only if we're using ONNX
      if (_isUsingOnnx) {
        OnnxStickerProcessor.dispose();
      }
      _isPluginInitialized = false;
      _isUsingOnnx = false;
      if (kDebugMode) {
        dev.log('Resources disposed successfully', name: 'FlutterStickerMaker');
      }
    } catch (e) {
      // Silently handle disposal errors to prevent app crashes
      // during shutdown
      if (kDebugMode) {
        dev.log('Warning - Disposal failed: $e', name: 'FlutterStickerMaker');
      }
    }
  }
}
