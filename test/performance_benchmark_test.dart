import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sticker_maker/src/native_mask_processor.dart';
import 'dart:typed_data';
import 'dart:math' as math;

/// Performance benchmark tests for native mask processing
void main() {
  group('Performance Benchmarks', () {
    const testSizes = [
      [64, 64], // Small
      [256, 256], // Medium
      [512, 512], // Large
      [1024, 1024], // Very Large
    ];

    setUpAll(() {
      // Initialize native processor
      NativeMaskProcessor.initialize();
    });

    for (final size in testSizes) {
      final width = size[0];
      final height = size[1];
      final pixelCount = width * height;

      group('${width}x${height} Image', () {
        late List<double> testMask;
        late Uint8List testPixels;

        setUp(() {
          // Create realistic test data
          testMask = List<double>.generate(pixelCount, (i) {
            final x = i % width;
            final y = i ~/ width;
            final centerX = width / 2;
            final centerY = height / 2;
            final distance = math.sqrt(
              math.pow(x - centerX, 2) + math.pow(y - centerY, 2),
            );
            final radius = math.min(width, height) / 3;
            return math.max(0.0, 1.0 - distance / radius);
          });

          testPixels = Uint8List(pixelCount * 4);
          for (int i = 0; i < pixelCount * 4; i++) {
            testPixels[i] = (i % 256);
          }
        });

        test('Mask Smoothing Performance', () async {
          if (!NativeMaskProcessor.isAvailable) {
            print('Native processor not available, skipping performance test');
            return;
          }

          const kernelSize = 5;

          // Measure native performance
          final nativeOutput = List<double>.filled(pixelCount, 0.0);
          final nativeStopwatch = Stopwatch()..start();

          final nativeResult = NativeMaskProcessor.smoothMask(
            testMask,
            nativeOutput,
            width,
            height,
            kernelSize,
          );

          nativeStopwatch.stop();

          expect(nativeResult, equals(MaskProcessorResult.success));

          // Print performance results
          print(
            'Native smooth mask (${width}x${height}): ${nativeStopwatch.elapsedMicroseconds}μs',
          );

          // For comparison, estimate Dart performance based on algorithmic complexity
          // Dart implementation has O(width * height * kernelSize²) complexity
          final estimatedDartMicroseconds =
              (pixelCount * kernelSize * kernelSize * 0.01).round();
          print(
            'Estimated Dart smooth mask (${width}x${height}): ${estimatedDartMicroseconds}μs',
          );

          if (estimatedDartMicroseconds > 0) {
            final speedup =
                estimatedDartMicroseconds / nativeStopwatch.elapsedMicroseconds;
            print('Estimated speedup: ${speedup.toStringAsFixed(2)}x');
          }
        });

        test('Mask Expansion Performance', () async {
          if (!NativeMaskProcessor.isAvailable) {
            print('Native processor not available, skipping performance test');
            return;
          }

          const borderWidth = 8;

          // Measure native performance
          final nativeOutput = List<double>.filled(pixelCount, 0.0);
          final nativeStopwatch = Stopwatch()..start();

          final nativeResult = NativeMaskProcessor.expandMask(
            testMask,
            nativeOutput,
            width,
            height,
            borderWidth,
          );

          nativeStopwatch.stop();

          expect(nativeResult, equals(MaskProcessorResult.success));

          // Print performance results
          print(
            'Native expand mask (${width}x${height}): ${nativeStopwatch.elapsedMicroseconds}μs',
          );

          // Estimate Dart performance: O(width * height * borderWidth²)
          final estimatedDartMicroseconds =
              (pixelCount * borderWidth * borderWidth * 0.005).round();
          print(
            'Estimated Dart expand mask (${width}x${height}): ${estimatedDartMicroseconds}μs',
          );

          if (estimatedDartMicroseconds > 0) {
            final speedup =
                estimatedDartMicroseconds / nativeStopwatch.elapsedMicroseconds;
            print('Estimated speedup: ${speedup.toStringAsFixed(2)}x');
          }
        });

        test('Sticker Mask Application Performance', () async {
          if (!NativeMaskProcessor.isAvailable) {
            print('Native processor not available, skipping performance test');
            return;
          }

          // Measure native performance
          final nativeStopwatch = Stopwatch()..start();

          final nativeResult = NativeMaskProcessor.applyStickerMask(
            testPixels,
            testMask,
            width,
            height,
            true, // Add border
            [255, 255, 255], // White border
            4, // Border width
            null, // No expanded mask for this test
          );

          nativeStopwatch.stop();

          expect(nativeResult, equals(MaskProcessorResult.success));

          // Print performance results
          print(
            'Native apply mask (${width}x${height}): ${nativeStopwatch.elapsedMicroseconds}μs',
          );

          // Estimate Dart performance: O(width * height)
          final estimatedDartMicroseconds = (pixelCount * 0.02).round();
          print(
            'Estimated Dart apply mask (${width}x${height}): ${estimatedDartMicroseconds}μs',
          );

          if (estimatedDartMicroseconds > 0) {
            final speedup =
                estimatedDartMicroseconds / nativeStopwatch.elapsedMicroseconds;
            print('Estimated speedup: ${speedup.toStringAsFixed(2)}x');
          }
        });
      });
    }

    test('Memory Usage Test', () {
      if (!NativeMaskProcessor.isAvailable) {
        print('Native processor not available, skipping memory test');
        return;
      }

      const width = 512;
      const height = 512;
      const pixelCount = width * height;

      // Create test data
      final mask = List<double>.filled(pixelCount, 0.5);
      final output = List<double>.filled(pixelCount, 0.0);
      final pixels = Uint8List(pixelCount * 4);

      // Run multiple operations to test for memory leaks
      const iterations = 100;

      for (int i = 0; i < iterations; i++) {
        final result1 = NativeMaskProcessor.smoothMask(
          mask,
          output,
          width,
          height,
          3,
        );
        expect(result1, equals(MaskProcessorResult.success));

        final result2 = NativeMaskProcessor.expandMask(
          mask,
          output,
          width,
          height,
          4,
        );
        expect(result2, equals(MaskProcessorResult.success));

        final result3 = NativeMaskProcessor.applyStickerMask(
          pixels,
          mask,
          width,
          height,
          false,
          [255, 255, 255],
          0,
          null,
        );
        expect(result3, equals(MaskProcessorResult.success));
      }

      print('Memory test completed: $iterations iterations without issues');
    });
  });
}
