/// Configuration constants for the Flutter Sticker Maker plugin.
class StickerDefaults {
  /// Default border color in hex format
  static const String defaultBorderColor = '#FFFFFF';

  /// Default border width in pixels
  static const double defaultBorderWidth = 12.0;

  /// Default setting for adding border
  static const bool defaultAddBorder = true;

  /// Maximum recommended image size in pixels (width or height)
  static const int maxImageSize = 4096;

  /// Maximum allowed border width in pixels
  static const double maxBorderWidth = 50.0;

  /// Minimum allowed border width in pixels
  static const double minBorderWidth = 0.0;

  /// Processing timeout in seconds
  static const int processingTimeoutSeconds = 30;

  /// Whether to automatically dispose resources on app lifecycle changes
  static const bool autoDisposeOnPause = true;

  /// Valid image format headers
  static const List<int> pngHeader = [0x89, 0x50, 0x4E, 0x47];
  static const List<int> jpegHeader = [0xFF, 0xD8, 0xFF];

  /// Path for ONNX model
  static const String onnxModelPath =
      'packages/flutter_sticker_maker/assets/model.onnx';
}
