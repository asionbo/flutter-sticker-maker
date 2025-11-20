import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'constants.dart';

/// Presents a Flutter-driven visual effect while ONNX processing runs.
class OnnxVisualEffectOverlay {
  const OnnxVisualEffectOverlay._();

  /// Runs [process] while showing the visual effect overlay when possible.
  static Future<Uint8List?> run({
    required Uint8List imageBytes,
    required SpeckleType speckleType,
    required Future<Uint8List?> Function() process,
  }) async {
    final overlayState = _findOverlayState();
    if (overlayState == null) {
      return process();
    }

    final completer = Completer<Uint8List?>();
    late OverlayEntry entry;

    entry = OverlayEntry(
      maintainState: true,
      builder:
          (_) => _OnnxVisualEffectOverlay(
            imageBytes: imageBytes,
            speckleType: speckleType,
            process: process,
            disableAnimations: debugDisableAnimations,
            onComplete: (result) {
              if (!completer.isCompleted) {
                completer.complete(result);
              }
              entry.remove();
            },
            onError: (error, stackTrace) {
              if (!completer.isCompleted) {
                completer.completeError(error, stackTrace);
              }
              entry.remove();
            },
          ),
    );

    overlayState.insert(entry);
    return completer.future;
  }

  @visibleForTesting
  static OverlayState? debugFindOverlayState() => _findOverlayState();

  @visibleForTesting
  static bool debugDisableAnimations = false;

  static OverlayState? _findOverlayState() {
    final binding = WidgetsBinding.instance;
    final root = binding.rootElement;
    if (root == null) return null;

    OverlayState? overlay;
    void visitor(Element element) {
      if (overlay != null) return;
      if (element is StatefulElement && element.state is OverlayState) {
        overlay = element.state as OverlayState;
        return;
      }
      element.visitChildElements(visitor);
    }

    root.visitChildElements(visitor);
    return overlay;
  }
}

class _OnnxVisualEffectOverlay extends StatefulWidget {
  const _OnnxVisualEffectOverlay({
    required this.imageBytes,
    required this.speckleType,
    required this.process,
    required this.onComplete,
    required this.onError,
    required this.disableAnimations,
  });

  final Uint8List imageBytes;
  final SpeckleType speckleType;
  final Future<Uint8List?> Function() process;
  final void Function(Uint8List? result) onComplete;
  final void Function(Object error, StackTrace stackTrace) onError;
  final bool disableAnimations;

  @override
  State<_OnnxVisualEffectOverlay> createState() =>
      _OnnxVisualEffectOverlayState();
}

class _OnnxVisualEffectOverlayState extends State<_OnnxVisualEffectOverlay>
    with TickerProviderStateMixin {
  static const _overlayBackground = Color(0x59000000);

  late final MemoryImage _sourceImage;
  late final AnimationController _speckleController;
  late final AnimationController _spoilerController;
  late final AnimationController _stickerController;
  final ValueNotifier<double> _overlayOpacity = ValueNotifier<double>(0);

  double _aspectRatio = 1.0;
  Color _spoilerColor = Colors.white.withValues(alpha: 0.4);
  Uint8List? _stickerBytes;
  bool _showSticker = false;
  bool _hasCompleted = false;
  bool get _disableAnimations => widget.disableAnimations;

  @override
  void initState() {
    super.initState();
    _sourceImage = MemoryImage(widget.imageBytes);
    _speckleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _spoilerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _stickerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );

    scheduleMicrotask(() {
      if (!mounted) return;
      _overlayOpacity.value = 1;
      _spoilerController.forward();
    });

    _resolveMetadata();
    _runProcess();
  }

  @override
  void dispose() {
    _speckleController.dispose();
    _spoilerController.dispose();
    _stickerController.dispose();
    _overlayOpacity.dispose();
    super.dispose();
  }

  Future<void> _runProcess() async {
    try {
      final result = await widget.process();
      if (!mounted) return;
      await _playCompletionSequence(result);
      widget.onComplete(result);
    } catch (error, stackTrace) {
      if (!mounted) return;
      await _dismissOverlay();
      widget.onError(error, stackTrace);
    }
  }

  Future<void> _resolveMetadata() async {
    try {
      final metadata = await _OverlayMetadata.fromBytes(widget.imageBytes);
      if (!mounted) return;
      setState(() {
        _aspectRatio = metadata.aspectRatio;
        _spoilerColor = metadata.overlayColor;
      });
    } catch (_) {
      // Defaults stay in place when decoding fails.
    }
  }

  Future<void> _playCompletionSequence(Uint8List? stickerBytes) async {
    if (!mounted || stickerBytes == null) {
      await _dismissOverlay();
      return;
    }

    setState(() {
      _stickerBytes = stickerBytes;
      _showSticker = true;
    });

    if (_disableAnimations) {
      await _dismissOverlay(immediate: true);
      return;
    }

    await Future.wait([
      _spoilerController.reverse(),
      _stickerController.forward(),
    ]);

    await Future.delayed(const Duration(milliseconds: 240));
    await _dismissOverlay();
  }

  Future<void> _dismissOverlay({bool immediate = false}) async {
    if (_hasCompleted) return;
    _hasCompleted = true;
    _overlayOpacity.value = 0;
    if (immediate || _disableAnimations) {
      return;
    }
    await Future.delayed(const Duration(milliseconds: 220));
  }

  double _stickerScale() {
    final progress = _stickerController.value;
    if (progress <= 0.55) {
      final t = progress / 0.55;
      final eased = Curves.easeOut.transform(t);
      return ui.lerpDouble(1.0, 1.12, eased)!;
    }
    final t = (progress - 0.55) / 0.45;
    final eased = Curves.easeIn.transform(t.clamp(0.0, 1.0));
    return ui.lerpDouble(1.12, 1.0, eased)!;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _overlayOpacity,
        builder:
            (context, child) =>
                Opacity(opacity: _overlayOpacity.value, child: child),
        child: Container(
          color: _overlayBackground,
          alignment: Alignment.center,
          child: FractionallySizedBox(
            widthFactor: 1.0,
            heightFactor: 1.0,
            child: AspectRatio(
              aspectRatio:
                  _aspectRatio.isFinite && _aspectRatio > 0
                      ? _aspectRatio
                      : 1.0,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedOpacity(
                    opacity: _showSticker ? 0 : 1,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOut,
                    child: Image(image: _sourceImage, fit: BoxFit.contain),
                  ),
                  if (_stickerBytes != null)
                    AnimatedBuilder(
                      animation: _stickerController,
                      builder:
                          (context, child) => Transform.scale(
                            scale: _stickerScale(),
                            child: child,
                          ),
                      child: Image.memory(
                        _stickerBytes!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      _spoilerController,
                      _speckleController,
                    ]),
                    builder:
                        (context, _) => Opacity(
                          opacity: _spoilerController.value,
                          child: _SpoilerOverlay(
                            animation: _speckleController,
                            baseColor: _spoilerColor,
                            speckleType: widget.speckleType,
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayMetadata {
  const _OverlayMetadata({
    required this.aspectRatio,
    required this.overlayColor,
  });

  final double aspectRatio;
  final Color overlayColor;

  static Future<_OverlayMetadata> fromBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 64,
      targetHeight: 64,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    codec.dispose();

    final width = image.width == 0 ? 1 : image.width;
    final height = image.height == 0 ? 1 : image.height;
    final color = _deriveSpoilerColor(byteData);
    image.dispose();

    return _OverlayMetadata(aspectRatio: width / height, overlayColor: color);
  }

  static Color _deriveSpoilerColor(ByteData? data) {
    if (data == null) {
      return Colors.white.withValues(alpha: 0.4);
    }

    final values = data.buffer.asUint8List();
    if (values.isEmpty) {
      return Colors.white.withValues(alpha: 0.4);
    }

    double r = 0, g = 0, b = 0;
    final pixels = values.length ~/ 4;
    for (int i = 0; i < values.length; i += 4) {
      r += values[i];
      g += values[i + 1];
      b += values[i + 2];
    }

    final inv = 1.0 / pixels;
    final red = (r * inv) / 255.0;
    final green = (g * inv) / 255.0;
    final blue = (b * inv) / 255.0;
    final brightness = 0.299 * red + 0.587 * green + 0.114 * blue;
    final targetAlpha = math.max(
      0.3,
      math.min(0.55, 0.35 + (0.5 - brightness).abs()),
    );
    final baseColor = brightness >= 0.55 ? Colors.black : Colors.white;
    return baseColor.withValues(alpha: targetAlpha);
  }
}

class _SpoilerOverlay extends StatelessWidget {
  const _SpoilerOverlay({
    required this.animation,
    required this.baseColor,
    required this.speckleType,
  });

  final Animation<double> animation;
  final Color baseColor;
  final SpeckleType speckleType;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final phase = animation.value;
        final style = _SpeckleStyle.fromType(speckleType);
        final primaryAlignment = Alignment(
          math.cos(phase * 2 * math.pi) * style.drift,
          math.sin(phase * 2 * math.pi) * style.drift,
        );
        final secondaryAlignment = Alignment(
          math.cos((phase + 0.35) * 2 * math.pi) * style.drift,
          math.sin((phase + 0.35) * 2 * math.pi) * style.drift,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: primaryAlignment,
                  radius: 1.2,
                  colors: [
                    baseColor.withValues(alpha: style.primaryOpacity),
                    baseColor.withValues(alpha: style.midOpacity),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: secondaryAlignment,
                  end: -secondaryAlignment,
                  colors: [
                    baseColor.withValues(alpha: style.secondaryOpacity),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: style.blurSigma,
                sigmaY: style.blurSigma,
              ),
              child: const SizedBox.expand(),
            ),
          ],
        );
      },
    );
  }
}

class _SpeckleStyle {
  const _SpeckleStyle({
    required this.drift,
    required this.primaryOpacity,
    required this.midOpacity,
    required this.secondaryOpacity,
    required this.blurSigma,
  });

  final double drift;
  final double primaryOpacity;
  final double midOpacity;
  final double secondaryOpacity;
  final double blurSigma;

  static _SpeckleStyle fromType(SpeckleType type) {
    switch (type) {
      case SpeckleType.sparkle:
        return const _SpeckleStyle(
          drift: 0.8,
          primaryOpacity: 0.75,
          midOpacity: 0.25,
          secondaryOpacity: 0.35,
          blurSigma: 10,
        );
      case SpeckleType.burst:
        return const _SpeckleStyle(
          drift: 0.95,
          primaryOpacity: 0.85,
          midOpacity: 0.3,
          secondaryOpacity: 0.45,
          blurSigma: 12,
        );
      case SpeckleType.classic:
        return const _SpeckleStyle(
          drift: 0.7,
          primaryOpacity: 0.8,
          midOpacity: 0.28,
          secondaryOpacity: 0.4,
          blurSigma: 9,
        );
      case SpeckleType.flutterOverlay:
        return const _SpeckleStyle(
          drift: 0.88,
          primaryOpacity: 0.82,
          midOpacity: 0.32,
          secondaryOpacity: 0.42,
          blurSigma: 11,
        );
    }
  }
}
