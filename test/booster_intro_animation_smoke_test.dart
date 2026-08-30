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

  testWidgets('la composizione finale è centrata nel canvas su entrambi gli assi', (tester) async {
    // Regressione: header e album erano ancorati a top fissi (24 e 170) dentro
    // un canvas alto 640, quindi la scena finale restava ~73px sopra il centro
    // con tutto lo spazio morto in basso.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BoosterIntroAnimation())),
    );
    // Fino a scena completa (album entrato e carte già nella griglia).
    for (var ms = 0; ms < 6900; ms += 100) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final canvas = tester.getRect(find.byKey(introCanvasKey));
    final album = tester.getRect(find.byType(AlbumFrame));
    final scale = canvas.width / 360;

    // Coordinate riportate nel canvas virtuale 360x640.
    double toCanvasX(double x) => (x - canvas.left) / scale;
    double toCanvasY(double y) => (y - canvas.top) / scale;

    expect(toCanvasX(album.center.dx), moreOrLessEquals(180, epsilon: 0.5));
    // L'album è centrato sotto il blocco header ad altezza riservata fissa:
    // 320 (centro canvas) + (headerH + gap) / 2 = 396.
    expect(toCanvasY(album.center.dy), moreOrLessEquals(396, epsilon: 0.5));

    // Margine sopra l'header e margine sotto l'album devono coincidere.
    final topMargin = toCanvasY(album.top) - (140 + 12);
    final bottomMargin = 640 - toCanvasY(album.bottom);
    expect(topMargin, moreOrLessEquals(bottomMargin, epsilon: 0.5));

    // La scala è limitata perché il ritaglio laterale non arrivi mai a
    // tagliare l'album: qui il canvas deborda, l'album no.
    final screenW = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(canvas.width, greaterThan(screenW), reason: 'la scena deve riempire lo schermo');
    expect(album.left, greaterThanOrEqualTo(0));
    expect(album.right, lessThanOrEqualTo(screenW));
  });
}
