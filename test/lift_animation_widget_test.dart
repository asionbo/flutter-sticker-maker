import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sticker_maker/flutter_sticker_maker.dart';

void main() {
  group('LiftAnimationWidget', () {
    testWidgets('renders child widget', (WidgetTester tester) async {
      const testText = 'Test Child';
      
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LiftAnimationWidget(
              child: Text(testText),
            ),
          ),
        ),
      );

      expect(find.text(testText), findsOneWidget);
    });

    testWidgets('triggers onLongPress callback', (WidgetTester tester) async {
      bool longPressTriggered = false;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiftAnimationWidget(
              onLongPress: () {
                longPressTriggered = true;
              },
              child: const Text('Test'),
            ),
          ),
        ),
      );

      // Perform long press
      await tester.longPress(find.byType(LiftAnimationWidget));
      await tester.pump();

      expect(longPressTriggered, true);
    });

    testWidgets('triggers onLongPressEnd callback', (WidgetTester tester) async {
      bool longPressEndTriggered = false;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiftAnimationWidget(
              onLongPressEnd: () {
                longPressEndTriggered = true;
              },
              child: const Text('Test'),
            ),
          ),
        ),
      );

      // Perform long press and release
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(LiftAnimationWidget)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pump();

      expect(longPressEndTriggered, true);
    });

    testWidgets('applies scale animation on long press', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LiftAnimationWidget(
              liftScale: 1.1,
              child: SizedBox(
                width: 100,
                height: 100,
                child: Text('Test'),
              ),
            ),
          ),
        ),
      );

      // Get initial state
      final transformFinder = find.byType(Transform);
      expect(transformFinder, findsOneWidget);

      // Start long press
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(LiftAnimationWidget)),
      );
      await tester.pump(const Duration(milliseconds: 600));

      // Animation should be active (scale changes)
      final transform = tester.widget<Transform>(transformFinder);
      expect(transform.transform, isNotNull);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('uses custom animation parameters', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LiftAnimationWidget(
              liftScale: 1.2,
              liftElevation: 16.0,
              animationDuration: Duration(milliseconds: 300),
              child: Text('Test'),
            ),
          ),
        ),
      );

      expect(find.byType(LiftAnimationWidget), findsOneWidget);
    });

    testWidgets('works without callbacks', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LiftAnimationWidget(
              child: Text('Test'),
            ),
          ),
        ),
      );

      // Should not throw when long pressing without callbacks
      await tester.longPress(find.byType(LiftAnimationWidget));
      await tester.pumpAndSettle();

      expect(find.text('Test'), findsOneWidget);
    });
  });
}
