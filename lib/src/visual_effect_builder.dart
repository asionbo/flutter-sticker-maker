import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Signature for building a custom visual effect overlay.
typedef VisualEffectBuilder =
    Widget Function(BuildContext context, VisualEffectRequest request);

/// Encapsulates the data exposed to a [VisualEffectBuilder].
class VisualEffectRequest {
  VisualEffectRequest({
    required this.imageBytes,
    required this.processing,
    required this.dismiss,
    required VoidCallback enableManualDismiss,
  }) : _enableManualDismiss = enableManualDismiss;

  /// Original image bytes being processed.
  final Uint8List imageBytes;

  /// The in-flight processing future. Builders can listen to completion.
  final Future<Uint8List?> processing;

  /// Allows builders to dismiss the overlay early if desired.
  final VoidCallback dismiss;

  final VoidCallback _enableManualDismiss;

  /// Prevents automatic dismissal once processing completes. Builders must
  /// call [dismiss] manually after invoking this method.
  void keepOverlayUntilDismissed() => _enableManualDismiss();
}

/// Presents a custom builder-driven visual effect while work is in-flight.
class VisualEffectPresenter {
  const VisualEffectPresenter._();

  /// Runs [process] while mounting [builder] inside the root overlay.
  static Future<Uint8List?> run({
    required Uint8List imageBytes,
    required Future<Uint8List?> Function() process,
    required VisualEffectBuilder builder,
    Duration completionDelay = const Duration(milliseconds: 240),
  }) async {
    final overlayState = _findOverlayState();
    if (overlayState == null) {
      return process();
    }

    final processingFuture = Future<Uint8List?>.sync(process);
    final completer = Completer<Uint8List?>();
    late final OverlayEntry entry;
    var removed = false;
    var manualDismissEnabled = false;

    void removeEntry() {
      if (removed) return;
      removed = true;
      entry.remove();
      debugOnOverlayRemoved?.call();
    }

    void enableManualDismiss() {
      manualDismissEnabled = true;
    }

    entry = OverlayEntry(
      maintainState: true,
      builder:
          (context) => builder(
            context,
            VisualEffectRequest(
              imageBytes: imageBytes,
              processing: processingFuture,
              dismiss: removeEntry,
              enableManualDismiss: enableManualDismiss,
            ),
          ),
    );

    overlayState.insert(entry);

    processingFuture
        .then((value) async {
          if (!completer.isCompleted) {
            completer.complete(value);
          }
          if (manualDismissEnabled) {
            return;
          }
          if (completionDelay > Duration.zero) {
            await Future<void>.delayed(completionDelay);
          }
          removeEntry();
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
          removeEntry();
        });

    return completer.future;
  }

  @visibleForTesting
  static OverlayState? debugFindOverlayState() => _findOverlayState();

  @visibleForTesting
  static VoidCallback? debugOnOverlayRemoved;

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
