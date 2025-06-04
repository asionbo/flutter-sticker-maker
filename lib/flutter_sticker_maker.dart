import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';

class FlutterStickerMaker {
  static const MethodChannel _channel = MethodChannel('flutter_sticker_maker');

  /// Creates a sticker by removing the background from the image data (PNG/JPEG).
  static Future<Uint8List?> makeSticker(Uint8List imageBytes) async {
    final result = await _channel.invokeMethod<Uint8List>(
      'makeSticker',
      {'image': imageBytes},
    );
    return result;
  }
}