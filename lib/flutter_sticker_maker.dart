import 'dart:async';
import 'package:flutter/services.dart';

class FlutterStickerMaker {
  static const MethodChannel _channel = MethodChannel('flutter_sticker_maker');

  /// Creates a sticker by removing the background from the image data (PNG/JPEG).
  static Future<Uint8List?> makeSticker(
    Uint8List imageBytes, {
    bool addBorder = true,
    String borderColor = '#FFFFFF',
    double borderWidth = 12.0,
  }) async {
    final result = await _channel.invokeMethod<Uint8List>('makeSticker', {
      'image': imageBytes,
      'addBorder': addBorder,
      'borderColor': borderColor,
      'borderWidth': borderWidth,
    });
    return result;
  }
}
