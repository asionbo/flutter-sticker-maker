import 'package:flutter/foundation.dart';

class PixelImage {
  int width;
  int height;
  Uint8List pixels; // RGBA format

  PixelImage({required this.width, required this.height, required this.pixels});
}
