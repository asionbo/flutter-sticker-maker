import 'package:flutter/material.dart';

/// A widget that provides iOS-style lift animation effect on long press.
///
/// This widget wraps its child and provides visual feedback when the user
/// performs a long press gesture, similar to the iOS Photos app. The animation
/// includes:
/// - Scale transformation (slight zoom)
/// - Elevation/shadow effect
/// - Smooth spring-like animation
///
/// **Example:**
/// ```dart
/// LiftAnimationWidget(
///   child: Image.memory(imageBytes),
///   onLongPress: () {
///     print('Long press detected');
///   },
/// )
/// ```
class LiftAnimationWidget extends StatefulWidget {
  /// The widget to apply the lift animation to
  final Widget child;

  /// Callback when long press is detected
  final VoidCallback? onLongPress;

  /// Callback when long press ends
  final VoidCallback? onLongPressEnd;

  /// The scale factor when lifted (default: 1.05)
  final double liftScale;

  /// The elevation when lifted (default: 8.0)
  final double liftElevation;

  /// Duration of the lift animation (default: 200ms)
  final Duration animationDuration;

  /// Creates a lift animation widget.
  const LiftAnimationWidget({
    super.key,
    required this.child,
    this.onLongPress,
    this.onLongPressEnd,
    this.liftScale = 1.05,
    this.liftElevation = 8.0,
    this.animationDuration = const Duration(milliseconds: 200),
  });

  @override
  State<LiftAnimationWidget> createState() => _LiftAnimationWidgetState();
}

class _LiftAnimationWidgetState extends State<LiftAnimationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );

    // Create smooth spring-like curve for scale
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.liftScale,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
    );

    // Create elevation animation
    _elevationAnimation = Tween<double>(
      begin: 0.0,
      end: widget.liftElevation,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    _controller.forward();
    widget.onLongPress?.call();
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    _controller.reverse();
    widget.onLongPressEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: _handleLongPressStart,
      onLongPressEnd: _handleLongPressEnd,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: PhysicalModel(
              color: Colors.transparent,
              elevation: _elevationAnimation.value,
              borderRadius: BorderRadius.circular(8),
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}
