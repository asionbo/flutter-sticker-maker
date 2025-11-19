import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sticker_maker/src/constants.dart';
import 'package:flutter_sticker_maker/src/onnx_visual_effect_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleImage = Uint8List.fromList(_oneByOneTransparentPng);

  setUp(() {
    OnnxVisualEffectOverlay.debugDisableAnimations = true;
  });

  tearDown(() {
    OnnxVisualEffectOverlay.debugDisableAnimations = false;
  });

  testWidgets('falls back gracefully when no overlay is mounted', (
    tester,
  ) async {
    var callCount = 0;

    final result = await OnnxVisualEffectOverlay.run(
      imageBytes: sampleImage,
      speckleType: SpeckleType.classic,
      process: () async {
        callCount++;
        return sampleImage;
      },
    );

    expect(result, same(sampleImage));
    expect(callCount, equals(1));
  });

  testWidgets('runs inside a widget tree overlay when available', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));

    var callCount = 0;
    final future = OnnxVisualEffectOverlay.run(
      imageBytes: sampleImage,
      speckleType: SpeckleType.sparkle,
      process: () async {
        callCount++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return sampleImage;
      },
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final result = await future;

    expect(result, same(sampleImage));
    expect(callCount, equals(1));
  });
}

const List<int> _oneByOneTransparentPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG header
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
  0x00, 0x00, 0x00, 0x01, // width = 1
  0x00, 0x00, 0x00, 0x01, // height = 1
  0x08, 0x06, 0x00, 0x00, 0x00, // RGBA
  0x1F, 0x15, 0xC4, 0x89,
  0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, // IDAT chunk
  0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0x00, 0x00,
  0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D, 0x18,
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND
  0xAE, 0x42, 0x60, 0x82,
];
