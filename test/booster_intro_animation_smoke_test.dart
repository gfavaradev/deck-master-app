import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/widgets/booster_intro_animation.dart';

void main() {
  testWidgets('BoosterIntroAnimation runs the full 7s sequence without throwing', (tester) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BoosterIntroAnimation(
            duration: const Duration(seconds: 7),
            onCompleted: () => completed = true,
          ),
        ),
      ),
    );

    // Pump through every phase beat (drop, tear, open, burst, fan, header, album, grid, flip, hold).
    for (var ms = 0; ms < 7200; ms += 100) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(completed, isTrue);
  });

  testWidgets('SplashIntro fades the logo bridge into the booster animation without throwing', (tester) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SplashIntro(onCompleted: () => completed = true),
        ),
      ),
    );

    // Bridge (500ms delay + 350ms fade) precede in sequenza i 7s dell'animazione.
    for (var ms = 0; ms < 8200; ms += 100) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(completed, isTrue);
  });
}
