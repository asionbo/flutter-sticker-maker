import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sticker_maker/flutter_sticker_maker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FlutterStickerMaker', () {
    const MethodChannel channel = MethodChannel('flutter_sticker_maker');
    final List<MethodCall> log = <MethodCall>[];

    // Valid PNG header for testing
    final validPngBytes = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG header
      ...List.filled(100, 0), // Dummy data
    ]);

    // Valid JPEG header for testing
    final validJpegBytes = Uint8List.fromList([
      0xFF, 0xD8, 0xFF, 0xE0, // JPEG header
      ...List.filled(100, 0), // Dummy data
    ]);

    setUp(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            log.add(methodCall);

            if (methodCall.method == 'makeSticker') {
              return Uint8List.fromList([137, 80, 78, 71]); // PNG header bytes
            } else if (methodCall.method == 'getIOSVersion') {
              return '17.1'; // Mock iOS 17.1 for testing platform channel
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      // Clean up after each test
      FlutterStickerMaker.dispose();
    });

    group('Initialization', () {
      test('initialize can be called multiple times safely', () async {
        expect(() async {
          await FlutterStickerMaker.initialize();
          await FlutterStickerMaker.initialize();
          await FlutterStickerMaker.initialize();
        }, returnsNormally);
      });

      test('makeSticker works without explicit initialization', () async {
        final result = await FlutterStickerMaker.makeSticker(validPngBytes);
        expect(result, isNotNull);
        expect(result, isA<Uint8List>());
      });
    });

    group('Basic functionality', () {
      test('makeSticker works with valid PNG input', () async {
        final result = await FlutterStickerMaker.makeSticker(validPngBytes);

        // Should succeed (either through platform channel or ONNX)
        expect(result, isNotNull);
        expect(result, isA<Uint8List>());
      });

      test('makeSticker works with custom parameters', () async {
        final result = await FlutterStickerMaker.makeSticker(
          validPngBytes,
          addBorder: false,
          borderColor: '#FF0000',
          borderWidth: 8.0,
        );

        expect(result, isNotNull);
        expect(result, isA<Uint8List>());
      });

      test('makeSticker works with visual effect parameter', () async {
        final result = await FlutterStickerMaker.makeSticker(
          validPngBytes,
          showVisualEffect: true,
        );

        expect(result, isNotNull);
        expect(result, isA<Uint8List>());
        
        // Verify the parameter was passed to the platform
        expect(log.isNotEmpty, isTrue);
        expect(log.last.arguments['showVisualEffect'], equals(true));
      });

      test('makeSticker defaults visual effect to false', () async {
        final result = await FlutterStickerMaker.makeSticker(validPngBytes);

        expect(result, isNotNull);
        expect(result, isA<Uint8List>());
        
        // Verify the default parameter value
        expect(log.isNotEmpty, isTrue);
        expect(log.last.arguments['showVisualEffect'], equals(false));
      });
    });

    group('Input validation', () {
      test('throws ArgumentError for empty image data', () async {
        expect(
          () => FlutterStickerMaker.makeSticker(Uint8List.fromList([])),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Image data cannot be empty'),
            ),
          ),
        );
      });

      test('throws ArgumentError for invalid image format', () async {
        final invalidBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

        expect(
          () => FlutterStickerMaker.makeSticker(invalidBytes),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Invalid image format'),
            ),
          ),
        );
      });

      test('throws ArgumentError for border width too small', () async {
        expect(
          () =>
              FlutterStickerMaker.makeSticker(validPngBytes, borderWidth: -1.0),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Border width must be between'),
            ),
          ),
        );
      });

      test('throws ArgumentError for border width too large', () async {
        expect(
          () => FlutterStickerMaker.makeSticker(
            validPngBytes,
            borderWidth: 100.0,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Border width must be between'),
            ),
          ),
        );
      });

      test('throws ArgumentError for invalid color format', () async {
        expect(
          () => FlutterStickerMaker.makeSticker(
            validPngBytes,
            borderColor: 'invalid',
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Invalid color format'),
            ),
          ),
        );
      });

      test('accepts valid color formats', () async {
        // Test various valid color formats
        await FlutterStickerMaker.makeSticker(
          validPngBytes,
          borderColor: '#000000',
        );
        await FlutterStickerMaker.makeSticker(
          validPngBytes,
          borderColor: 'FFFFFF',
        );
        await FlutterStickerMaker.makeSticker(
          validPngBytes,
          borderColor: '#ff00ff',
        );

        expect(log, hasLength(3));
        expect(log[0].arguments['borderColor'], equals('#000000'));
        expect(log[1].arguments['borderColor'], equals('FFFFFF'));
        expect(log[2].arguments['borderColor'], equals('#ff00ff'));
      });

      test('accepts valid image formats', () async {
        // Test PNG
        final result1 = await FlutterStickerMaker.makeSticker(validPngBytes);
        expect(result1, isNotNull);

        // Test JPEG
        final result2 = await FlutterStickerMaker.makeSticker(validJpegBytes);
        expect(result2, isNotNull);
      });
    });

    group('Error handling', () {
      test('handles null response from platform gracefully', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
              return null;
            });

        final result = await FlutterStickerMaker.makeSticker(validPngBytes);
        // Should still work via ONNX fallback
        expect(result, isNotNull);
      });

      test('handles platform exception gracefully', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
              throw PlatformException(
                code: 'ERROR',
                message: 'Failed to process image',
              );
            });

        // Should still work via ONNX fallback
        final result = await FlutterStickerMaker.makeSticker(validPngBytes);
        expect(result, isNotNull);
      });

      test('handles timeout with ONNX fallback', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
              // Simulate timeout by delaying longer than the timeout
              await Future.delayed(Duration(seconds: 35));
              return Uint8List.fromList([]);
            });

        // Should work via ONNX fallback, though it may be slower
        final result = await FlutterStickerMaker.makeSticker(validPngBytes);
        expect(result, isNotNull);
      });
    });

    group('Edge cases', () {
      test('handles minimum border width', () async {
        final result = await FlutterStickerMaker.makeSticker(
          validPngBytes,
          borderWidth: 0.0,
        );
        expect(result, isNotNull);
      });

      test('handles maximum border width', () async {
        final result = await FlutterStickerMaker.makeSticker(
          validPngBytes,
          borderWidth: 50.0,
        );
        expect(result, isNotNull);
      });

      test('handles large valid image data', () async {
        final largeImage = Uint8List.fromList([
          ...validPngBytes.take(8), // Keep valid header
          ...List.filled(1024 * 1024, 255), // 1MB of data
        ]);

        final result = await FlutterStickerMaker.makeSticker(largeImage);
        expect(result, isNotNull);
      });
    });

    group('Resource management', () {
      test('dispose method works without throwing', () {
        expect(() => FlutterStickerMaker.dispose(), returnsNormally);
      });

      test('dispose can be called multiple times safely', () {
        expect(() {
          FlutterStickerMaker.dispose();
          FlutterStickerMaker.dispose();
          FlutterStickerMaker.dispose();
        }, returnsNormally);
      });

      test('makeSticker works after dispose', () async {
        // Dispose first
        FlutterStickerMaker.dispose();

        // Should still work (will reinitialize if needed)
        final result = await FlutterStickerMaker.makeSticker(validPngBytes);
        expect(result, isNotNull);
        expect(result, isA<Uint8List>());
      });

      test('initialize after dispose works correctly', () async {
        FlutterStickerMaker.dispose();
        await FlutterStickerMaker.initialize();
        
        final result = await FlutterStickerMaker.makeSticker(validPngBytes);
        expect(result, isNotNull);
        expect(result, isA<Uint8List>());
      });
    });
  });
}
