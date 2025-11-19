import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_sticker_maker/src/native_mask_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Integration-flavored copy of the performance benchmarks so we can run them
/// on physical devices/emulators and measure the real native code paths.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const testSizes = <List<int>>[
    [64, 64],
    [256, 256],
    [512, 512],
    [1024, 1024],
  ];

  setUpAll(() {
    NativeMaskProcessor.initialize();
  });

  group('Native mask processor benchmarks (integration)', () {
    for (final size in testSizes) {
      final width = size[0];
      final height = size[1];
      final pixelCount = width * height;

      group('${width}x$height image', () {
        late List<double> testMask;
        late Uint8List testPixels;

        setUp(() {
          testMask = List<double>.generate(pixelCount, (index) {
            final x = index % width;
            final y = index ~/ width;
            final centerX = width / 2;
            final centerY = height / 2;
            final distance = math.sqrt(
              math.pow(x - centerX, 2) + math.pow(y - centerY, 2),
            );
            final radius = math.min(width, height) / 3;
            return math.max(0.0, 1.0 - distance / radius);
          });

          testPixels = Uint8List(pixelCount * 4);
          for (var i = 0; i < pixelCount * 4; i++) {
            testPixels[i] = (i % 256);
          }
        });

        testWidgets('Mask smoothing performance', (tester) async {
          if (!NativeMaskProcessor.isAvailable) {
            print('Native processor not available, skipping performance test');
            return;
          }

          const kernelSize = 5;
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
          print(
            'Native smooth mask (${width}x$height): ${nativeStopwatch.elapsedMicroseconds}μs',
          );

          final estimatedDartMicroseconds =
              (pixelCount * kernelSize * kernelSize * 0.01).round();
          print(
            'Estimated Dart smooth mask (${width}x$height): $estimatedDartMicrosecondsμs',
          );

          if (estimatedDartMicroseconds > 0) {
            final speedup =
                estimatedDartMicroseconds / nativeStopwatch.elapsedMicroseconds;
            print('Estimated speedup: ${speedup.toStringAsFixed(2)}x');
          }
        });

        testWidgets('Mask expansion performance', (tester) async {
          if (!NativeMaskProcessor.isAvailable) {
            print('Native processor not available, skipping performance test');
            return;
          }

          const borderWidth = 8;
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
          print(
            'Native expand mask (${width}x$height): ${nativeStopwatch.elapsedMicroseconds}μs',
          );

          final estimatedDartMicroseconds =
              (pixelCount * borderWidth * borderWidth * 0.005).round();
          print(
            'Estimated Dart expand mask (${width}x$height): $estimatedDartMicrosecondsμs',
          );

          if (estimatedDartMicroseconds > 0) {
            final speedup =
                estimatedDartMicroseconds / nativeStopwatch.elapsedMicroseconds;
            print('Estimated speedup: ${speedup.toStringAsFixed(2)}x');
          }
        });

        testWidgets('Sticker mask application performance', (tester) async {
          if (!NativeMaskProcessor.isAvailable) {
            print('Native processor not available, skipping performance test');
            return;
          }

          final nativeStopwatch = Stopwatch()..start();
          final nativeResult = NativeMaskProcessor.applyStickerMask(
            testPixels,
            testMask,
            width,
            height,
            true,
            const [255, 255, 255],
            4,
            null,
          );

          nativeStopwatch.stop();
          expect(nativeResult, equals(MaskProcessorResult.success));
          print(
            'Native apply mask (${width}x$height): ${nativeStopwatch.elapsedMicroseconds}μs',
          );

          final estimatedDartMicroseconds = (pixelCount * 0.02).round();
          print(
            'Estimated Dart apply mask (${width}x$height): $estimatedDartMicrosecondsμs',
          );

          if (estimatedDartMicroseconds > 0) {
            final speedup =
                estimatedDartMicroseconds / nativeStopwatch.elapsedMicroseconds;
            print('Estimated speedup: ${speedup.toStringAsFixed(2)}x');
          }
        });
      });
    }

    testWidgets('Memory usage sanity check', (tester) async {
      if (!NativeMaskProcessor.isAvailable) {
        print('Native processor not available, skipping memory test');
        return;
      }

      const width = 512;
      const height = 512;
      const pixelCount = width * height;

      final mask = List<double>.filled(pixelCount, 0.5);
      final output = List<double>.filled(pixelCount, 0.0);
      final pixels = Uint8List(pixelCount * 4);

      const iterations = 100;
      for (var i = 0; i < iterations; i++) {
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
          const [255, 255, 255],
          0,
          null,
        );
        expect(result3, equals(MaskProcessorResult.success));
      }

      print('Memory test completed: $iterations iterations without issues');
    });
  });
}
