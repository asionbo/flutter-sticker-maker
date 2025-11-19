import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_sticker_maker/flutter_sticker_maker.dart';
import 'package:flutter_sticker_maker/src/onnx_sticker_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final Uint8List validPngBytes = _decodeBase64(_kTestPngBase64);
  final Uint8List validJpegBytes = _decodeBase64(_kTestJpegBase64);
  final Uint8List largeValidPngBytes = _decodeBase64(_kLargePngBase64);

  setUpAll(() async {
    try {
      await OnnxStickerProcessor.initialize();
    } catch (_) {
      // ONNX runtime is optional on some platforms; ignore failures here.
    }
  });

  setUp(() {
    FlutterStickerMaker.dispose();
  });

  group('Initialization', () {
    testWidgets('initialize can be called multiple times safely', (
      tester,
    ) async {
      await FlutterStickerMaker.initialize();
      await FlutterStickerMaker.initialize();
      await FlutterStickerMaker.initialize();
    });

    testWidgets('makeSticker works without explicit initialization', (
      tester,
    ) async {
      final result = await FlutterStickerMaker.makeSticker(validPngBytes);
      expect(result, isNotNull);
      expect(result, isA<Uint8List>());
    });
  });

  group('Basic functionality', () {
    testWidgets('makeSticker works with valid PNG input', (tester) async {
      await FlutterStickerMaker.initialize();
      final result = await FlutterStickerMaker.makeSticker(validPngBytes);

      expect(result, isNotNull);
      expect(result, isA<Uint8List>());
    });

    testWidgets('makeSticker works with custom parameters', (tester) async {
      await FlutterStickerMaker.initialize();
      final result = await FlutterStickerMaker.makeSticker(
        validPngBytes,
        addBorder: false,
        borderColor: '#FF0000',
        borderWidth: 8.0,
      );

      expect(result, isNotNull);
      expect(result, isA<Uint8List>());
    });

    testWidgets('makeSticker works with visual effect parameter', (
      tester,
    ) async {
      await FlutterStickerMaker.initialize();
      final result = await FlutterStickerMaker.makeSticker(
        validPngBytes,
        showVisualEffect: true,
      );

      expect(result, isNotNull);
      expect(result, isA<Uint8List>());
    });
  });

  group('Input validation', () {
    testWidgets('throws ArgumentError for empty image data', (tester) async {
      await FlutterStickerMaker.initialize();
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

    testWidgets('throws ArgumentError for invalid image format', (
      tester,
    ) async {
      await FlutterStickerMaker.initialize();
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

    testWidgets('throws ArgumentError for border width too small', (
      tester,
    ) async {
      await FlutterStickerMaker.initialize();
      expect(
        () => FlutterStickerMaker.makeSticker(validPngBytes, borderWidth: -1.0),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Border width must be between'),
          ),
        ),
      );
    });

    testWidgets('throws ArgumentError for border width too large', (
      tester,
    ) async {
      await FlutterStickerMaker.initialize();
      expect(
        () =>
            FlutterStickerMaker.makeSticker(validPngBytes, borderWidth: 100.0),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Border width must be between'),
          ),
        ),
      );
    });

    testWidgets('throws ArgumentError for invalid color format', (
      tester,
    ) async {
      await FlutterStickerMaker.initialize();
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

    testWidgets('accepts valid color formats', (tester) async {
      await FlutterStickerMaker.initialize();
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
    });

    testWidgets('accepts valid image formats', (tester) async {
      await FlutterStickerMaker.initialize();

      final result1 = await FlutterStickerMaker.makeSticker(validPngBytes);
      final result2 = await FlutterStickerMaker.makeSticker(validJpegBytes);

      expect(result1, isNotNull);
      expect(result2, isNotNull);
    });
  });

  group('Edge cases', () {
    testWidgets('handles minimum border width', (tester) async {
      await FlutterStickerMaker.initialize();
      final result = await FlutterStickerMaker.makeSticker(
        validPngBytes,
        borderWidth: 0.0,
      );
      expect(result, isNotNull);
    });

    testWidgets('handles maximum border width', (tester) async {
      await FlutterStickerMaker.initialize();
      final result = await FlutterStickerMaker.makeSticker(
        validPngBytes,
        borderWidth: 50.0,
      );
      expect(result, isNotNull);
    });

    testWidgets('handles large valid image data', (tester) async {
      await FlutterStickerMaker.initialize();
      final result = await FlutterStickerMaker.makeSticker(largeValidPngBytes);
      expect(result, isNotNull);
    });
  });

  group('Resource management', () {
    testWidgets('dispose method works without throwing', (tester) async {
      expect(() => FlutterStickerMaker.dispose(), returnsNormally);
    });

    testWidgets('dispose can be called multiple times safely', (tester) async {
      expect(() {
        FlutterStickerMaker.dispose();
        FlutterStickerMaker.dispose();
        FlutterStickerMaker.dispose();
      }, returnsNormally);
    });

    testWidgets('makeSticker works after dispose', (tester) async {
      FlutterStickerMaker.dispose();
      final result = await FlutterStickerMaker.makeSticker(validPngBytes);
      expect(result, isNotNull);
      expect(result, isA<Uint8List>());
    });

    testWidgets('initialize after dispose works correctly', (tester) async {
      FlutterStickerMaker.dispose();
      await FlutterStickerMaker.initialize();

      final result = await FlutterStickerMaker.makeSticker(validPngBytes);
      expect(result, isNotNull);
      expect(result, isA<Uint8List>());
    });
  });
}

Uint8List _decodeBase64(String data) => base64Decode(data);

const String _kTestPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFUlEQVR4nGNk+M/wn4GBgYEJRIAwAB4YAgKxtDcvAAAAAElFTkSuQmCC';

const String _kTestJpegBase64 =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAACAAIDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD2Kiiivw09M//Z';

const String _kLargePngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAgAAAAIACAYAAAD0eNT6AAAIX0lEQVR4nO3WMQHAMAzAsHT8OacsusMS'
    'Ap8+O7sDAKR8fwcAAO8ZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDI'
    'AABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAA'
    'EGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZ'
    'AAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAA'
    'ggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCAD'
    'AABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABA'
    'kAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQA'
    'ACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAI'
    'MgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwA'
    'AAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABB'
    'BgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEA'
    'gCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDI'
    'AABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAA'
    'EGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZ'
    'AAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAA'
    'ggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCAD'
    'AABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABA'
    'kAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQA'
    'ACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAI'
    'MgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwA'
    'AAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABB'
    'BgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEA'
    'gCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDI'
    'AABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAA'
    'EGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZ'
    'AAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAA'
    'ggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCAD'
    'AABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABA'
    'kAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQA'
    'ACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAI'
    'MgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwA'
    'AAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABB'
    'BgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEA'
    'gCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDI'
    'AABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAAEGQAACDIAABAkAEAgCADAABBBgAAggwAAAQZAAAIMgAA'
    'EGQAACDIAABAkAEAgCADAADTcwGi+gb9JR0mugAAAABJRU5ErkJggg==';
