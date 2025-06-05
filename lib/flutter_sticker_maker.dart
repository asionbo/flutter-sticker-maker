import 'dart:async';
import 'package:flutter/services.dart';
import 'src/constants.dart';
import 'src/exceptions.dart';

export 'src/constants.dart';
export 'src/exceptions.dart';

/// Flutter plugin for creating stickers by removing image backgrounds using ML Kit.
class FlutterStickerMaker {
  static const MethodChannel _channel = MethodChannel('flutter_sticker_maker');

  /// Creates a sticker by removing background from an image using ML Kit.
  ///
  /// **Parameters:**
  /// - [imageBytes]: Raw image data (PNG/JPEG). Max recommended size: 2048x2048px
  /// - [addBorder]: Whether to add a border around the subject
  /// - [borderColor]: Hex color string (#RRGGBB or RRGGBB format)
  /// - [borderWidth]: Border thickness in pixels (0.0 to 50.0)
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
  /// );
  /// ```
  static Future<Uint8List?> makeSticker(
    Uint8List imageBytes, {
    bool addBorder = StickerDefaults.defaultAddBorder,
    String borderColor = StickerDefaults.defaultBorderColor,
    double borderWidth = StickerDefaults.defaultBorderWidth,
  }) async {
    // Validate input parameters
    _validateInput(imageBytes, borderColor, borderWidth);

    try {
      final result = await _channel
          .invokeMethod<Uint8List>('makeSticker', {
            'image': imageBytes,
            'addBorder': addBorder,
            'borderColor': borderColor,
            'borderWidth': borderWidth,
          })
          .timeout(Duration(seconds: StickerDefaults.processingTimeoutSeconds));

      return result;
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
}
