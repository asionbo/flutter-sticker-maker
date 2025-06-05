/// Custom exception for sticker creation errors.
class StickerException implements Exception {
  /// Error message describing what went wrong
  final String message;

  /// Optional original error that caused this exception
  final dynamic originalError;

  /// Optional error code for categorizing errors
  final String? errorCode;

  const StickerException(this.message, {this.originalError, this.errorCode});

  @override
  String toString() {
    if (originalError != null) {
      return 'StickerException: $message (Original: $originalError)';
    }
    return 'StickerException: $message';
  }
}
