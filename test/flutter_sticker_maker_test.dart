import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sticker_maker/flutter_sticker_maker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FlutterStickerMaker', () {
    const MethodChannel channel = MethodChannel('flutter_sticker_maker');
    final List<MethodCall> log = <MethodCall>[];

    setUp(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            log.add(methodCall);

            // Mock successful response with dummy image data
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

    test('makeSticker calls platform method with default parameters', () async {
      final imageBytes = Uint8List.fromList([1, 2, 3, 4]);

      final result = await FlutterStickerMaker.makeSticker(imageBytes);

      expect(log, hasLength(1));
      expect(log.first.method, 'makeSticker');
      expect(log.first.arguments['image'], imageBytes);
      expect(log.first.arguments['addBorder'], true);
      expect(log.first.arguments['borderColor'], '#FFFFFF');
      expect(log.first.arguments['borderWidth'], 12.0);
      expect(result, isNotNull);
      expect(result, isA<Uint8List>());
    });

    test('makeSticker calls platform method with custom parameters', () async {
      final imageBytes = Uint8List.fromList([1, 2, 3, 4]);

      await FlutterStickerMaker.makeSticker(
        imageBytes,
        addBorder: false,
        borderColor: '#FF0000',
        borderWidth: 8.0,
      );

      expect(log, hasLength(1));
      expect(log.first.method, 'makeSticker');
      expect(log.first.arguments['image'], imageBytes);
      expect(log.first.arguments['addBorder'], false);
      expect(log.first.arguments['borderColor'], '#FF0000');
      expect(log.first.arguments['borderWidth'], 8.0);
    });

    test('makeSticker handles null response from platform', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            return null;
          });

      final imageBytes = Uint8List.fromList([1, 2, 3, 4]);
      final result = await FlutterStickerMaker.makeSticker(imageBytes);

      expect(result, isNull);
    });

    test('makeSticker handles platform exception', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            throw PlatformException(
              code: 'ERROR',
              message: 'Failed to process image',
            );
          });

      final imageBytes = Uint8List.fromList([1, 2, 3, 4]);

      expect(
        () => FlutterStickerMaker.makeSticker(imageBytes),
        throwsA(isA<PlatformException>()),
      );
    });

    test('makeSticker validates border color formats', () async {
      final imageBytes = Uint8List.fromList([1, 2, 3, 4]);

      // Test various color formats
      await FlutterStickerMaker.makeSticker(imageBytes, borderColor: '#000000');
      await FlutterStickerMaker.makeSticker(imageBytes, borderColor: 'FFFFFF');
      await FlutterStickerMaker.makeSticker(imageBytes, borderColor: '#ff00ff');

      expect(log, hasLength(3));
      expect(log[0].arguments['borderColor'], '#000000');
      expect(log[1].arguments['borderColor'], 'FFFFFF');
      expect(log[2].arguments['borderColor'], '#ff00ff');
    });

    test('makeSticker handles different border widths', () async {
      final imageBytes = Uint8List.fromList([1, 2, 3, 4]);

      await FlutterStickerMaker.makeSticker(imageBytes, borderWidth: 0.0);
      await FlutterStickerMaker.makeSticker(imageBytes, borderWidth: 5.5);
      await FlutterStickerMaker.makeSticker(imageBytes, borderWidth: 20.0);

      expect(log, hasLength(3));
      expect(log[0].arguments['borderWidth'], 0.0);
      expect(log[1].arguments['borderWidth'], 5.5);
      expect(log[2].arguments['borderWidth'], 20.0);
    });

    test('makeSticker with empty image data', () async {
      final imageBytes = Uint8List.fromList([]);

      final result = await FlutterStickerMaker.makeSticker(imageBytes);

      expect(log, hasLength(1));
      expect(log.first.arguments['image'], imageBytes);
      expect(result, isNotNull);
    });

    test('makeSticker with large image data', () async {
      final imageBytes = Uint8List.fromList(
        List.filled(1024 * 1024, 255),
      ); // 1MB of data

      final result = await FlutterStickerMaker.makeSticker(imageBytes);

      expect(log, hasLength(1));
      expect(log.first.arguments['image'], imageBytes);
      expect(result, isNotNull);
    });
  });
}
