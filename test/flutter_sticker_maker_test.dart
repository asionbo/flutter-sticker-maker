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
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    group('Basic functionality', () {
      test(
        'makeSticker calls platform method with default parameters',
        () async {
          final result = await FlutterStickerMaker.makeSticker(validPngBytes);

          expect(log, hasLength(1));
          expect(log.first.method, equals('makeSticker'));
          expect(log.first.arguments['image'], equals(validPngBytes));
          expect(log.first.arguments['addBorder'], equals(true));
          expect(log.first.arguments['borderColor'], equals('#FFFFFF'));
          expect(log.first.arguments['borderWidth'], equals(12.0));
          expect(result, isNotNull);
          expect(result, isA<Uint8List>());
        },
      );

      test(
        'makeSticker calls platform method with custom parameters',
        () async {
          await FlutterStickerMaker.makeSticker(
            validPngBytes,
            addBorder: false,
            borderColor: '#FF0000',
            borderWidth: 8.0,
          );

          expect(log, hasLength(1));
          expect(log.first.method, equals('makeSticker'));
          expect(log.first.arguments['image'], equals(validPngBytes));
          expect(log.first.arguments['addBorder'], equals(false));
          expect(log.first.arguments['borderColor'], equals('#FF0000'));
          expect(log.first.arguments['borderWidth'], equals(8.0));
        },
      );
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
        await FlutterStickerMaker.makeSticker(validPngBytes);
        // Test JPEG
        await FlutterStickerMaker.makeSticker(validJpegBytes);

        expect(log, hasLength(2));
      });
    });

    group('Error handling', () {
      test('handles null response from platform', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
              return null;
            });

        final result = await FlutterStickerMaker.makeSticker(validPngBytes);
        expect(result, isNull);
      });

      test('throws StickerException for platform exception', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
              throw PlatformException(
                code: 'ERROR',
                message: 'Failed to process image',
              );
            });

        expect(
          () => FlutterStickerMaker.makeSticker(validPngBytes),
          throwsA(
            isA<StickerException>().having(
              (e) => e.message,
              'message',
              contains('Platform error'),
            ),
          ),
        );
      });

      test('throws StickerException for timeout', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
              // Simulate timeout by delaying longer than the timeout
              await Future.delayed(Duration(seconds: 35));
              return Uint8List.fromList([]);
            });

        expect(
          () => FlutterStickerMaker.makeSticker(validPngBytes),
          throwsA(
            isA<StickerException>().having(
              (e) => e.message,
              'message',
              contains('Processing timeout'),
            ),
          ),
        );
      });
    });

    group('Edge cases', () {
      test('handles minimum border width', () async {
        await FlutterStickerMaker.makeSticker(validPngBytes, borderWidth: 0.0);
        expect(log.first.arguments['borderWidth'], equals(0.0));
      });

      test('handles maximum border width', () async {
        await FlutterStickerMaker.makeSticker(validPngBytes, borderWidth: 50.0);
        expect(log.first.arguments['borderWidth'], equals(50.0));
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
  });
}
