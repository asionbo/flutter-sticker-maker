import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sticker_maker/src/visual_effect_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleImage = Uint8List.fromList(_oneByOneTransparentPng);

  tearDown(() {
    VisualEffectPresenter.debugOnOverlayRemoved = null;
  });

  testWidgets('falls back when no overlay is available', (tester) async {
    var callCount = 0;

    final result = await VisualEffectPresenter.run(
      imageBytes: sampleImage,
      process: () async {
        callCount++;
        return sampleImage;
      },
      builder: (context, request) => throw StateError('should not build'),
      completionDelay: Duration.zero,
    );

    expect(result, same(sampleImage));
    expect(callCount, equals(1));
  });

  testWidgets('builds inside overlay and exposes processing future', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));

    var buildCount = 0;

    final future = VisualEffectPresenter.run(
      imageBytes: sampleImage,
      process: () async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return sampleImage;
      },
      builder: (context, request) {
        buildCount++;
        return FutureBuilder<Uint8List?>(
          future: request.processing,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              return const ColoredBox(color: Colors.green);
            }
            return const ColoredBox(color: Colors.red);
          },
        );
      },
      completionDelay: Duration.zero,
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    final result = await future;

    expect(result, same(sampleImage));
    expect(buildCount, greaterThanOrEqualTo(1));
  });

  testWidgets('dismiss can hide overlay early without affecting result', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));

    final future = VisualEffectPresenter.run(
      imageBytes: sampleImage,
      process: () async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return sampleImage;
      },
      builder: (context, request) {
        WidgetsBinding.instance.addPostFrameCallback((_) => request.dismiss());
        return const SizedBox.shrink();
      },
      completionDelay: Duration.zero,
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    final result = await future;
    expect(result, same(sampleImage));
  });

  testWidgets('waits before auto-dismiss when delay is provided', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));

    var removalCount = 0;
    VisualEffectPresenter.debugOnOverlayRemoved = () {
      removalCount++;
    };

    final future = VisualEffectPresenter.run(
      imageBytes: sampleImage,
      process: () async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return sampleImage;
      },
      builder: (context, request) => const SizedBox.shrink(),
      completionDelay: const Duration(milliseconds: 40),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    await future;
    expect(removalCount, equals(0));

    await tester.pump(const Duration(milliseconds: 20));
    expect(removalCount, equals(0));

    await tester.pump(const Duration(milliseconds: 30));
    expect(removalCount, equals(1));
  });

  testWidgets('overlay can stay visible until manual dismiss', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));

    var removalCount = 0;
    VisualEffectPresenter.debugOnOverlayRemoved = () {
      removalCount++;
    };

    late VisualEffectRequest capturedRequest;

    final future = VisualEffectPresenter.run(
      imageBytes: sampleImage,
      process: () async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return sampleImage;
      },
      builder: (context, request) {
        capturedRequest = request;
        request.keepOverlayUntilDismissed();
        return const SizedBox.shrink();
      },
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    await future;
    await tester.pump(const Duration(milliseconds: 200));
    expect(removalCount, equals(0));

    capturedRequest.dismiss();
    await tester.pump();
    expect(removalCount, equals(1));
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
