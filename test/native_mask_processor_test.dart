import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sticker_maker/src/native_mask_processor.dart';
import 'dart:typed_data';

void main() {
  group('NativeMaskProcessor', () {
    test('initialize returns boolean status', () {
      // Note: In a test environment, the native library may not be available
      final result = NativeMaskProcessor.initialize();
      expect(result, isA<bool>());
    });

    test('isAvailable property works', () {
      NativeMaskProcessor.initialize();
      expect(NativeMaskProcessor.isAvailable, isA<bool>());
    });

    test('applyStickerMask handles invalid parameters gracefully', () {
      if (!NativeMaskProcessor.isAvailable) {
        // Skip test if native library is not available
        return;
      }

      final result = NativeMaskProcessor.applyStickerMask(
        Uint8List(0), // Empty array
        [], // Empty mask
        0, // Invalid width
        0, // Invalid height
        false,
        [255, 255, 255],
        0,
        null,
      );

      expect(result, equals(MaskProcessorResult.errorInvalidParams));
    });

    test('smoothMask handles invalid parameters gracefully', () {
      if (!NativeMaskProcessor.isAvailable) {
        // Skip test if native library is not available
        return;
      }

      final result = NativeMaskProcessor.smoothMask(
        [], // Empty mask
        [], // Empty output
        0, // Invalid width
        0, // Invalid height
        0, // Invalid kernel size
      );

      expect(result, equals(MaskProcessorResult.errorInvalidParams));
    });

    test('expandMask handles invalid parameters gracefully', () {
      if (!NativeMaskProcessor.isAvailable) {
        // Skip test if native library is not available
        return;
      }

      final result = NativeMaskProcessor.expandMask(
        [], // Empty mask
        [], // Empty output
        0, // Invalid width
        0, // Invalid height
        -1, // Invalid border width
      );

      expect(result, equals(MaskProcessorResult.errorInvalidParams));
    });

    test('native functions work with valid small data', () {
      if (!NativeMaskProcessor.isAvailable) {
        // Skip test if native library is not available
        return;
      }

      const width = 4;
      const height = 4;
      final pixelCount = width * height;

      // Create test data
      final pixels = Uint8List(pixelCount * 4); // RGBA
      final mask = List<double>.filled(pixelCount, 0.5);
      final output = List<double>.filled(pixelCount, 0.0);

      // Fill with some test values
      for (int i = 0; i < pixelCount * 4; i++) {
        pixels[i] = 128; // Mid-gray
      }

      // Test smooth mask
      final smoothResult = NativeMaskProcessor.smoothMask(
        mask,
        output,
        width,
        height,
        3,
      );

      expect(smoothResult, equals(MaskProcessorResult.success));

      // Test expand mask
      final expandOutput = List<double>.filled(pixelCount, 0.0);
      final expandResult = NativeMaskProcessor.expandMask(
        mask,
        expandOutput,
        width,
        height,
        2,
      );

      expect(expandResult, equals(MaskProcessorResult.success));

      // Test apply sticker mask
      final applyResult = NativeMaskProcessor.applyStickerMask(
        pixels,
        mask,
        width,
        height,
        true,
        [255, 0, 0], // Red border
        2,
        expandOutput,
      );

      expect(applyResult, equals(MaskProcessorResult.success));
    });
  });
}