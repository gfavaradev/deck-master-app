/// Replica Flutter dell'animazione "E — Booster Pack → 9 Cards → Album"
/// disegnata nel progetto Claude Design "animation deck master logo".
///
/// Sequenza (7s totali): bustina che cade → si strappa e si apre con flash →
/// 7 carte escono a raggiera → si dispongono a ventaglio → header e album
/// vuoto appaiono → le carte migrano nella griglia 3×3 → flip a cascata →
/// badge "+9" finale.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:package_info_plus/package_info_plus.dart';

// L'asset del logo è 2000x2000: decodificarlo a piena risoluzione solo per
// mostrarlo a 64-140px causa un frame jankato al primo utilizzo. Stessa
// chiave di cache in entrambi i punti dove l'asset è usato, così il
// secondo utilizzo riusa il bitmap già decodificato invece di rifare il decode.
const kLogoDecodeCacheWidth = 280;

/// Chiave del canvas virtuale 360x640 della scena: serve ai test per misurare
/// le posizioni in coordinate di canvas invece che in pixel di schermo.
/// Larghezza minima del canvas che deve restare visibile: l'album è largo 280
/// su 360 e il badge finale arriva a 324, quindi sotto questa soglia il
/// ritaglio laterale comincerebbe a tagliare la scena.
const _kSceneSafeWidth = 296.0;

const introCanvasKey = ValueKey('booster-intro-canvas');

// ── Palette (dal design originale) ──────────────────────────────────────────
const _ink = Color(0xFF1A1A24);
const _paper = Color(0xFFFBF8F1);
const _navy = Color(0xFF0D1A3A);
// Stesso colore dello splash nativo Android/iOS (flutter_native_splash) e dello
// sfondo dello Scaffold in splash_page.dart: evita uno stacco di colore visibile
// nel passaggio dallo splash nativo al primo frame di questa animazione.
const _splashBg = Color(0xFF12152A);
const _cyan = Color(0xFF22D3EE);
const _gold = Color(0xFFE8B845);
const _goldSoft = Color(0x8CE8B845);

/// Tavolozza colori di una carta tematica (corpo, profondità, accento, glow).
class CardTheme {
  final Color body, deep, accent, glow;
  const CardTheme(this.body, this.deep, this.accent, this.glow);
}

const _cardThemes = [
  CardTheme(Color(0xFF3A2670), Color(0xFF1F1545), Color(0xFF7D5CD9), Color(0xFFB9A3FF)),
  CardTheme(Color(0xFF0F5D6B), Color(0xFF063040), Color(0xFF2BB3B8), Color(0xFF7FE8EB)),
  CardTheme(Color(0xFFA83817), Color(0xFF5B1A08), Color(0xFFE8642A), Color(0xFFFFB27A)),
];

const _monsterNames = [
  'Slime', 'Drago', 'Cavaliere', 'Fenice', 'Veggente',
  'Teschio', 'Golem', 'Volpe', 'Mandragora',
];

double _clamp01(double v) => v.clamp(0.0, 1.0);

({int idx, int rarity}) _pickMonster(int seed) {
  final h = (math.sin((seed + 1) * 43.7) * 9301 + math.cos(seed * 17.3) * 233) % 1;
  final idx = (h.abs() * 9).floor() % 9;
  final rarity = (seed * 3) % 7 == 0 ? 2 : (seed % 3 == 0 ? 1 : 0);
  return (idx: idx, rarity: rarity);
}

void _drawText(
  Canvas canvas,
  String text,
  Offset anchor,
  Color color,
  double fontSize, {
  bool center = true,
  double letterSpacing = 0,
  FontWeight weight = FontWeight.w600,
}) {
  final span = TextSpan(
    text: text,
    style: TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: weight,
      letterSpacing: letterSpacing,
    ),
  );
  final tp = TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
  final offset = center
      ? anchor - Offset(tp.width / 2, tp.height / 2)
      : anchor;
  tp.paint(canvas, offset);
}

// ── 9 mostri stilizzati (tradotti dai path SVG originali) ──────────────────
void _paintMonster(Canvas canvas, double s, int idx, Color c, Color ink) {
  final fill = Paint()..color = c..style = PaintingStyle.fill;
  final inkFill = Paint()..color = ink..style = PaintingStyle.fill;
  Paint inkStroke(double w) => Paint()
    ..color = ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final outline = inkStroke(s * 0.018);

  switch (idx) {
    case 0: // Slime
      final p = Path()
        ..moveTo(s * 0.15, s * 0.7)
        ..quadraticBezierTo(s * 0.1, s * 0.35, s * 0.5, s * 0.25)
        ..quadraticBezierTo(s * 0.9, s * 0.35, s * 0.85, s * 0.7)
        ..quadraticBezierTo(s * 0.92, s * 0.82, s * 0.5, s * 0.85)
        ..quadraticBezierTo(s * 0.08, s * 0.82, s * 0.15, s * 0.7)
        ..close();
      canvas.drawPath(p, fill);
      canvas.drawPath(p, outline);
      canvas.drawCircle(Offset(s * 0.38, s * 0.5), s * 0.05, inkFill);
      canvas.drawCircle(Offset(s * 0.62, s * 0.5), s * 0.05, inkFill);
      final mouth = Path()
        ..moveTo(s * 0.4, s * 0.65)
        ..quadraticBezierTo(s * 0.5, s * 0.7, s * 0.6, s * 0.65);
      canvas.drawPath(mouth, inkStroke(s * 0.014));
      break;
    case 1: // Drago
      final p = Path()
        ..moveTo(s * 0.15, s * 0.6)
        ..lineTo(s * 0.25, s * 0.4)
        ..lineTo(s * 0.45, s * 0.3)
        ..lineTo(s * 0.7, s * 0.35)
        ..lineTo(s * 0.85, s * 0.5)
        ..lineTo(s * 0.8, s * 0.65)
        ..lineTo(s * 0.9, s * 0.7)
        ..lineTo(s * 0.7, s * 0.7)
        ..lineTo(s * 0.55, s * 0.78)
        ..lineTo(s * 0.3, s * 0.75)
        ..close();
      canvas.drawPath(p, fill);
      canvas.drawPath(p, outline);
      canvas.drawCircle(Offset(s * 0.62, s * 0.5), s * 0.04, Paint()..color = _paper);
      canvas.drawCircle(Offset(s * 0.62, s * 0.5), s * 0.04, inkStroke(s * 0.012));
      final horns = Path()
        ..moveTo(s * 0.3, s * 0.4)
        ..lineTo(s * 0.35, s * 0.28)
        ..lineTo(s * 0.42, s * 0.36)
        ..moveTo(s * 0.5, s * 0.32)
        ..lineTo(s * 0.55, s * 0.22)
        ..lineTo(s * 0.6, s * 0.32);
      canvas.drawPath(horns, inkStroke(s * 0.015));
      break;
    case 2: // Cavaliere (elmo)
      final p = Path()
        ..moveTo(s * 0.3, s * 0.3)
        ..lineTo(s * 0.7, s * 0.3)
        ..lineTo(s * 0.78, s * 0.45)
        ..lineTo(s * 0.78, s * 0.75)
        ..lineTo(s * 0.65, s * 0.85)
        ..lineTo(s * 0.35, s * 0.85)
        ..lineTo(s * 0.22, s * 0.75)
        ..lineTo(s * 0.22, s * 0.45)
        ..close();
      canvas.drawPath(p, fill);
      canvas.drawPath(p, outline);
      canvas.drawRect(Rect.fromLTWH(s * 0.32, s * 0.5, s * 0.36, s * 0.08), inkFill);
      final plume = Path()
        ..moveTo(s * 0.4, s * 0.3)
        ..lineTo(s * 0.5, s * 0.18)
        ..lineTo(s * 0.6, s * 0.3)
        ..close();
      canvas.drawPath(plume, fill);
      canvas.drawPath(plume, inkStroke(s * 0.016));
      break;
    case 3: // Fenice
      final p = Path()
        ..moveTo(s * 0.5, s * 0.25)
        ..quadraticBezierTo(s * 0.7, s * 0.4, s * 0.85, s * 0.55)
        ..lineTo(s * 0.7, s * 0.6)
        ..quadraticBezierTo(s * 0.6, s * 0.78, s * 0.5, s * 0.85)
        ..quadraticBezierTo(s * 0.4, s * 0.78, s * 0.3, s * 0.6)
        ..lineTo(s * 0.15, s * 0.55)
        ..quadraticBezierTo(s * 0.3, s * 0.4, s * 0.5, s * 0.25)
        ..close();
      canvas.drawPath(p, fill);
      canvas.drawPath(p, outline);
      final beak = Path()
        ..moveTo(s * 0.5, s * 0.32)
        ..lineTo(s * 0.55, s * 0.42)
        ..lineTo(s * 0.5, s * 0.5)
        ..lineTo(s * 0.45, s * 0.42)
        ..close();
      canvas.drawPath(beak, Paint()..color = _paper);
      canvas.drawPath(beak, inkStroke(s * 0.011));
      canvas.drawCircle(Offset(s * 0.5, s * 0.42), s * 0.025, inkFill);
      break;
    case 4: // Occhio fluttuante
      canvas.drawOval(Rect.fromCenter(center: Offset(s * 0.5, s * 0.55), width: s * 0.64, height: s * 0.44), fill);
      canvas.drawOval(Rect.fromCenter(center: Offset(s * 0.5, s * 0.55), width: s * 0.64, height: s * 0.44), outline);
      canvas.drawCircle(Offset(s * 0.5, s * 0.55), s * 0.1, Paint()..color = _paper);
      canvas.drawCircle(Offset(s * 0.5, s * 0.55), s * 0.1, inkStroke(s * 0.013));
      canvas.drawCircle(Offset(s * 0.5, s * 0.55), s * 0.045, inkFill);
      final tentacles = Path()
        ..moveTo(s * 0.3, s * 0.78)
        ..lineTo(s * 0.35, s * 0.88)
        ..moveTo(s * 0.5, s * 0.78)
        ..lineTo(s * 0.5, s * 0.9)
        ..moveTo(s * 0.7, s * 0.78)
        ..lineTo(s * 0.65, s * 0.88);
      canvas.drawPath(tentacles, inkStroke(s * 0.014));
      break;
    case 5: // Teschio
      final p = Path()
        ..moveTo(s * 0.25, s * 0.45)
        ..quadraticBezierTo(s * 0.25, s * 0.25, s * 0.5, s * 0.25)
        ..quadraticBezierTo(s * 0.75, s * 0.25, s * 0.75, s * 0.45)
        ..lineTo(s * 0.75, s * 0.65)
        ..lineTo(s * 0.65, s * 0.7)
        ..lineTo(s * 0.65, s * 0.8)
        ..lineTo(s * 0.55, s * 0.8)
        ..lineTo(s * 0.55, s * 0.7)
        ..lineTo(s * 0.45, s * 0.7)
        ..lineTo(s * 0.45, s * 0.8)
        ..lineTo(s * 0.35, s * 0.8)
        ..lineTo(s * 0.35, s * 0.7)
        ..lineTo(s * 0.25, s * 0.65)
        ..close();
      canvas.drawPath(p, fill);
      canvas.drawPath(p, outline);
      canvas.drawCircle(Offset(s * 0.4, s * 0.48), s * 0.06, inkFill);
      canvas.drawCircle(Offset(s * 0.6, s * 0.48), s * 0.06, inkFill);
      final nose = Path()
        ..moveTo(s * 0.45, s * 0.6)
        ..lineTo(s * 0.5, s * 0.65)
        ..lineTo(s * 0.55, s * 0.6)
        ..close();
      canvas.drawPath(nose, inkFill);
      break;
    case 6: // Golem
      final p = Path()
        ..moveTo(s * 0.2, s * 0.85)
        ..lineTo(s * 0.25, s * 0.4)
        ..lineTo(s * 0.4, s * 0.25)
        ..lineTo(s * 0.6, s * 0.25)
        ..lineTo(s * 0.78, s * 0.4)
        ..lineTo(s * 0.82, s * 0.85)
        ..close();
      canvas.drawPath(p, fill);
      canvas.drawPath(p, outline);
      final cracks = Path()
        ..moveTo(s * 0.3, s * 0.5)
        ..lineTo(s * 0.45, s * 0.45)
        ..lineTo(s * 0.45, s * 0.65)
        ..lineTo(s * 0.3, s * 0.65)
        ..close()
        ..moveTo(s * 0.55, s * 0.45)
        ..lineTo(s * 0.7, s * 0.5)
        ..lineTo(s * 0.7, s * 0.65)
        ..lineTo(s * 0.55, s * 0.65)
        ..close();
      canvas.drawPath(cracks, inkStroke(s * 0.012));
      canvas.drawCircle(Offset(s * 0.37, s * 0.55), s * 0.025, inkFill);
      canvas.drawCircle(Offset(s * 0.62, s * 0.55), s * 0.025, inkFill);
      break;
    case 7: // Volpe spirito
      final p = Path()
        ..moveTo(s * 0.2, s * 0.55)
        ..lineTo(s * 0.32, s * 0.3)
        ..lineTo(s * 0.4, s * 0.45)
        ..lineTo(s * 0.6, s * 0.45)
        ..lineTo(s * 0.68, s * 0.3)
        ..lineTo(s * 0.8, s * 0.55)
        ..lineTo(s * 0.7, s * 0.8)
        ..lineTo(s * 0.3, s * 0.8)
        ..close();
      canvas.drawPath(p, fill);
      canvas.drawPath(p, outline);
      canvas.drawCircle(Offset(s * 0.4, s * 0.6), s * 0.04, inkFill);
      canvas.drawCircle(Offset(s * 0.6, s * 0.6), s * 0.04, inkFill);
      final smile = Path()
        ..moveTo(s * 0.45, s * 0.72)
        ..lineTo(s * 0.5, s * 0.76)
        ..lineTo(s * 0.55, s * 0.72);
      canvas.drawPath(smile, inkStroke(s * 0.013));
      break;
    case 8: // Mandragora
      canvas.drawLine(Offset(s * 0.5, s * 0.85), Offset(s * 0.5, s * 0.55), inkStroke(s * 0.015));
      final head = Path()
        ..moveTo(s * 0.3, s * 0.45)
        ..quadraticBezierTo(s * 0.5, s * 0.2, s * 0.7, s * 0.45)
        ..quadraticBezierTo(s * 0.65, s * 0.55, s * 0.5, s * 0.55)
        ..quadraticBezierTo(s * 0.35, s * 0.55, s * 0.3, s * 0.45)
        ..close();
      canvas.drawPath(head, fill);
      canvas.drawPath(head, outline);
      final arms = Path()
        ..moveTo(s * 0.35, s * 0.78)
        ..lineTo(s * 0.25, s * 0.85)
        ..moveTo(s * 0.65, s * 0.78)
        ..lineTo(s * 0.75, s * 0.85);
      canvas.drawPath(arms, inkStroke(s * 0.014));
      canvas.drawCircle(Offset(s * 0.45, s * 0.4), s * 0.025, inkFill);
      canvas.drawCircle(Offset(s * 0.55, s * 0.4), s * 0.025, inkFill);
      break;
  }
}

// ── Carta da gioco (dorso o fronte tematizzato) ─────────────────────────────
class WireCard extends StatelessWidget {
  final double w, h;
  final bool faceUp;
  final int seed;
  final String? label;
  final CardTheme? theme;

  const WireCard({
    super.key,
    this.w = 64,
    this.h = 92,
    this.faceUp = false,
    this.seed = 0,
    this.label,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: w,
      height: h,
      child: CustomPaint(
        painter: _WireCardPainter(faceUp: faceUp, seed: seed, label: label, theme: theme),
      ),
    );
  }
}

class _WireCardPainter extends CustomPainter {
  final bool faceUp;
  final int seed;
  final String? label;
  final CardTheme? theme;

  _WireCardPainter({required this.faceUp, required this.seed, this.label, this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final monster = _pickMonster(seed);
    final artSize = w * 0.72;
    final artX = (w - artSize) / 2;
    final artY = h * 0.18;
    final rarityBadge = ['C', 'R', '★'][monster.rarity];

    final useTheme = theme != null && faceUp;
    final rrect = RRect.fromRectAndRadius(Rect.fromLTWH(1, 1, w - 2, h - 2), const Radius.circular(4));

    if (useTheme) {
      final shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [theme!.body, theme!.deep],
      ).createShader(rrect.outerRect);
      canvas.drawRRect(rrect, Paint()..shader = shader);
    } else if (faceUp) {
      canvas.drawRRect(rrect, Paint()..color = _paper);
    } else {
      canvas.save();
      canvas.clipRRect(rrect);
      final hatch = Paint()
        ..color = _navy.withValues(alpha: 0.4)
        ..strokeWidth = 0.7;
      for (double x = -h; x < w + h; x += 4) {
        canvas.drawLine(Offset(x, 0), Offset(x + h, h), hatch);
      }
      canvas.restore();
    }

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = useTheme ? _gold : _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = useTheme ? 1.76 : 1.6,
    );

    if (useTheme) {
      final innerRect = RRect.fromRectAndRadius(Rect.fromLTWH(3, 3, w - 6, h - 6), const Radius.circular(3));
      final glow = RadialGradient(
        center: const Alignment(0, -0.2),
        radius: 0.9,
        colors: [theme!.glow.withValues(alpha: 0.55), theme!.glow.withValues(alpha: 0)],
      ).createShader(innerRect.outerRect);
      canvas.drawRRect(innerRect, Paint()..shader = glow);
      canvas.drawRRect(
        innerRect,
        Paint()
          ..color = _gold.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.72,
      );

      final artRect = Rect.fromLTWH(artX - 1, artY - 1, artSize + 2, artSize + 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(artRect, const Radius.circular(2)),
        Paint()..color = Colors.black.withValues(alpha: 0.20),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(artRect, const Radius.circular(2)),
        Paint()
          ..color = _gold.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.88,
      );
      canvas.save();
      canvas.translate(artX, artY);
      _paintMonster(canvas, artSize, monster.idx, theme!.glow, _ink);
      canvas.restore();

      _drawText(canvas, rarityBadge, Offset(w - 6, 9), _gold, 10);
      if (label != null) {
        _drawText(canvas, label!, Offset(w / 2, h - 8), _gold, math.min(w * 0.16, 10), letterSpacing: 0.4);
      }
    } else if (!faceUp) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(5, 5, w - 10, h - 10), const Radius.circular(2)),
        Paint()
          ..color = _ink.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.96,
      );
      final cx = w / 2, cy = h / 2;
      final diamond = Path()
        ..moveTo(cx, cy - w * 0.16)
        ..lineTo(cx + w * 0.16, cy)
        ..lineTo(cx, cy + w * 0.16)
        ..lineTo(cx - w * 0.16, cy)
        ..close();
      canvas.drawPath(diamond, Paint()..color = _paper);
      canvas.drawPath(
        diamond,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.12,
      );
      canvas.drawCircle(Offset(cx, cy), w * 0.05, Paint()..color = _navy);
    } else {
      // fronte non tematizzato (non usato in VariantE, ma completo per coerenza)
      final artRect = Rect.fromLTWH(artX - 1, artY - 1, artSize + 2, artSize + 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(artRect, const Radius.circular(2)),
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.12,
      );
      canvas.save();
      canvas.translate(artX, artY);
      _paintMonster(canvas, artSize, monster.idx, _navy, _ink);
      canvas.restore();
      if (label != null) {
        _drawText(canvas, label!, Offset(w / 2, h - 8), _ink, math.min(w * 0.13, 9));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WireCardPainter old) =>
      old.faceUp != faceUp || old.seed != seed || old.label != label || old.theme != theme;
}

// ── Sparkle: stella a 4 punte ───────────────────────────────────────────────
class Sparkle extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;
  const Sparkle({super.key, this.size = 8, this.color = _cyan, this.opacity = 1});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: CustomPaint(size: Size(size, size), painter: _SparklePainter(color)),
    );
  }
}

class _SparklePainter extends CustomPainter {
  final Color color;
  _SparklePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    final s = size.width / 20 * 8; // normalizza scala simile all'originale 20x20 viewBox -10..10
    final p = Path()
      ..moveTo(0, -s)
      ..lineTo(s * 0.19, -s * 0.19)
      ..lineTo(s, 0)
      ..lineTo(s * 0.19, s * 0.19)
      ..lineTo(0, s)
      ..lineTo(-s * 0.19, s * 0.19)
      ..lineTo(-s, 0)
      ..lineTo(-s * 0.19, -s * 0.19)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparklePainter old) => old.color != color;
}

// ── Whoosh: scia curva ───────────────────────────────────────────────────────
class Whoosh extends StatelessWidget {
  final Offset from, to;
  final Color color;
  final double strokeWidth;
  const Whoosh({super.key, required this.from, required this.to, this.color = const Color(0x4022D3EE), this.strokeWidth = 1.5});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _WhooshPainter(from, to, color, strokeWidth),
    );
  }
}

class _WhooshPainter extends CustomPainter {
  final Offset from, to;
  final Color color;
  final double sw;
  _WhooshPainter(this.from, this.to, this.color, this.sw);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = (from.dx + to.dx) / 2 + (to.dy - from.dy) * 0.2;
    final cy = (from.dy + to.dy) / 2 - (to.dx - from.dx) * 0.2;
    final p = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(cx, cy, to.dx, to.dy);
    canvas.drawPath(
      p,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _WhooshPainter old) => old.from != from || old.to != to || old.color != color;
}

// ── BoosterPack: bustina con linguetta che si strappa e si apre ─────────────
class BoosterPack extends StatelessWidget {
  final double w, h;
  final double tearProgress;
  final double opening;
  const BoosterPack({super.key, this.w = 110, this.h = 170, this.tearProgress = 0, this.opening = 0});

  @override
  Widget build(BuildContext context) {
    final flapAngle = opening * 130; // gradi, simula rotateX CSS
    return SizedBox(
      width: w,
      height: h + 30,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CustomPaint(
            size: Size(w, h + 30),
            painter: _BoosterBodyPainter(w: w, h: h, tearProgress: tearProgress, opening: opening),
          ),
          // flap superiore — simula apertura 3D con una prospettiva approssimata
          Positioned(
            left: 2,
            top: 2,
            child: Transform(
              alignment: Alignment.topCenter,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0015)
                ..rotateX(flapAngle * math.pi / 180),
              child: CustomPaint(
                size: Size(w - 4, 20),
                painter: _BoosterFlapPainter(),
              ),
            ),
          ),
          if (opening > 0.2 && opening < 0.9)
            for (int i = 0; i < 4; i++)
              Builder(builder: (context) {
                final ang = (i / 4) * math.pi - math.pi / 2;
                final dist = 14 + (opening - 0.2) * 30;
                return Positioned(
                  left: w / 2 + math.cos(ang) * dist - 4,
                  top: 20 + math.sin(ang) * dist - 4,
                  child: Sparkle(size: 8, color: _cyan, opacity: 1 - opening),
                );
              }),
        ],
      ),
    );
  }
}

class _BoosterBodyPainter extends CustomPainter {
  final double w, h, tearProgress, opening;
  _BoosterBodyPainter({required this.w, required this.h, required this.tearProgress, required this.opening});

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(2, 20, w - 4, h - 22), const Radius.circular(4));
    final shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF3A2670), Color(0xFF1F1545)],
    ).createShader(body.outerRect);
    canvas.drawRRect(body, Paint()..shader = shader);
    canvas.drawRRect(body, Paint()..color = _gold..style = PaintingStyle.stroke..strokeWidth = 1.8);

    canvas.save();
    canvas.clipRRect(body);
    final hatch = Paint()..color = _gold.withValues(alpha: 0.35)..strokeWidth = 0.7;
    for (double x = -h; x < w + h; x += 5) {
      canvas.drawLine(Offset(x, 20), Offset(x + h, 20 + h), hatch);
    }
    canvas.restore();

    _drawText(canvas, 'DECK MASTER', Offset(w / 2, 76), _gold, 12, letterSpacing: 0.5);
    _drawText(canvas, '— BOOSTER —', Offset(w / 2, 90), _goldSoft, 7, letterSpacing: 1.4, weight: FontWeight.w400);

    // linea di strappo frastagliata
    const teeth = 14;
    final yLine = 22 + opening * 4;
    final path = Path();
    for (int i = 0; i <= teeth; i++) {
      final x = (i / teeth) * (w - 8) + 4;
      final y = yLine + (i % 2 != 0 ? 2 : -2) * (1 - tearProgress * 0.6);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final tearPaint = Paint()
      ..color = _gold.withValues(alpha: 1 - opening * 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    if (tearProgress <= 0) {
      canvas.drawPath(dashPath(path, dashArray: const [3, 3]), tearPaint);
    } else {
      canvas.drawPath(path, tearPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BoosterBodyPainter old) =>
      old.tearProgress != tearProgress || old.opening != opening;
}

class _BoosterFlapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), const Radius.circular(3));
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFF1F1545));
    canvas.drawRRect(rrect, Paint()..color = _gold..style = PaintingStyle.stroke..strokeWidth = 1.6);
    final tabs = Path()
      ..moveTo(10, 0)
      ..lineTo(14, 6)
      ..lineTo(18, 0)
      ..moveTo(size.width - 18, 0)
      ..lineTo(size.width - 14, 6)
      ..lineTo(size.width - 10, 0);
    canvas.drawPath(tabs, Paint()..color = _gold..style = PaintingStyle.stroke..strokeWidth = 1.2);
  }

  @override
  bool shouldRepaint(covariant _BoosterFlapPainter old) => false;
}

/// Helper minimale per disegnare un path tratteggiato senza dipendenze esterne.
Path dashPath(Path source, {required List<double> dashArray}) {
  final dest = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    var draw = true;
    var dashIndex = 0;
    while (distance < metric.length) {
      final len = dashArray[dashIndex % dashArray.length];
      if (draw) {
        dest.addPath(metric.extractPath(distance, math.min(distance + len, metric.length)), Offset.zero);
      }
      distance += len;
      draw = !draw;
      dashIndex++;
    }
  }
  return dest;
}

// ── AlbumFrame: cornice album con rilegatura a spirale e griglia 3×3 ────────
class AlbumFrame extends StatelessWidget {
  final double w, h;
  final double opacity;
  const AlbumFrame({super.key, required this.w, required this.h, this.opacity = 1});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: CustomPaint(size: Size(w, h), painter: _AlbumFramePainter()),
    );
  }
}

class _AlbumFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const strokeMain = Color(0x8CBEDCFF); // rgba(190,220,255,0.55)
    const strokeAccent = Color(0x7322D3EE); // rgba(34,211,238,0.45)
    const strokeFaint = Color(0x2EBEDCFF); // rgba(190,220,255,0.18)
    const strokeMid = Color(0x4DBEDCFF); // rgba(190,220,255,0.30)

    final outer = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(8));
    canvas.drawRRect(outer, Paint()..color = Colors.white.withValues(alpha: 0.04));
    canvas.drawRRect(outer, Paint()..color = strokeMain..style = PaintingStyle.stroke..strokeWidth = 1.6);

    for (int i = 0; i < 12; i++) {
      final y = 20 + i * (h - 40) / 11;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(14, y), width: 12, height: 8),
        Paint()..color = strokeAccent..style = PaintingStyle.stroke..strokeWidth = 1.2,
      );
      canvas.drawLine(Offset(20, y - 1), Offset(26, y - 1), Paint()..color = strokeMid..strokeWidth = 1);
    }

    canvas.drawPath(
      dashPath(Path()..moveTo(30, 10)..lineTo(30, h - 10), dashArray: const [2, 4]),
      Paint()..color = strokeFaint..style = PaintingStyle.stroke..strokeWidth = 1,
    );

    final slotW = (w - 50) / 3;
    final slotH = (h - 30) / 3;
    for (int i = 0; i < 9; i++) {
      final col = i % 3, row = i ~/ 3;
      final x = 36 + col * slotW + 4;
      final y = 12 + row * slotH + 4;
      final slot = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, slotW - 8, slotH - 8), const Radius.circular(2));
      canvas.drawRRect(
        slot,
        Paint()..color = strokeFaint..style = PaintingStyle.stroke..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AlbumFramePainter old) => false;
}

// ── VariantE: orchestratore della scena completa ────────────────────────────
class BoosterIntroAnimation extends StatefulWidget {
  /// Durata totale della sequenza (default 7s, come il design originale).
  final Duration duration;
  final VoidCallback? onCompleted;

  const BoosterIntroAnimation({super.key, this.duration = const Duration(seconds: 7), this.onCompleted});

  @override
  State<BoosterIntroAnimation> createState() => _BoosterIntroAnimationState();
}

class _BoosterIntroAnimationState extends State<BoosterIntroAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration);
    _c.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onCompleted?.call();
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Scala con cui il canvas virtuale 360x640 viene proiettato sullo schermo.
  ///
  /// Parte da cover — la scena deve riempire lo schermo, non lasciare bande
  /// vuote dove si vedrebbe il gradiente della pagina dietro — ma la limita:
  /// su un telefono più alto di 360:640 cover scala sull'altezza e ritaglia i
  /// lati, e a 20:9 i bordi dell'album (280 di larghezza su 360) arrivavano a
  /// filo dello schermo, a 21:9 ci finivano fuori. Il tetto è il punto in cui
  /// il ritaglio comincerebbe a mangiare la scena.
  ///
  /// Quel che resta scoperto sopra e sotto è comunque invisibile: lo dipinge
  /// il [ColoredBox] con lo stesso colore di sfondo della scena.
  static double _sceneScale(Size box) {
    if (box.isEmpty || !box.width.isFinite || !box.height.isFinite) return 1;
    final cover = math.max(box.width / _SceneE.w, box.height / _SceneE.h);
    final maxBeforeClipping = box.width / _kSceneSafeWidth;
    return math.min(cover, maxBeforeClipping);
  }

  @override
  Widget build(BuildContext context) {
    final totalSeconds = widget.duration.inMilliseconds / 1000.0;
    return ColoredBox(
      color: _splashBg,
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // OverflowBox impone al canvas i suoi 360x640 anche su schermi più
            // stretti (altrimenti la geometria fissa della scena si
            // deformerebbe) e lo centra; Transform.scale scala attorno al
            // centro, quindi la scena resta centrata su entrambi gli assi.
            return OverflowBox(
              alignment: Alignment.center,
              minWidth: _SceneE.w,
              maxWidth: _SceneE.w,
              minHeight: _SceneE.h,
              maxHeight: _SceneE.h,
              child: Transform.scale(
                scale: _sceneScale(constraints.biggest),
                child: SizedBox(
                  key: introCanvasKey,
                  width: _SceneE.w,
                  height: _SceneE.h,
                  // Solo la scena si ricostruisce a ogni frame: sfondo, clip,
                  // layout e scala restano fuori dall'AnimatedBuilder.
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) => _SceneE(t: _c.value * totalSeconds),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SceneE extends StatelessWidget {
  final double t;
  const _SceneE({required this.t});

  static const w = 360.0;
  static const h = 640.0;
  static const cx = w / 2;
  static const cy = h / 2;
  static const num = 7;
  static const fanSpread = 90.0;
  static const fanRadius = 130.0;

  // ── Geometria verticale ──────────────────────────────────────────────────
  // La composizione finale (header + album) è centrata nel canvas *per
  // costruzione*: l'header occupa un'altezza riservata fissa, quindi il
  // margine sopra e quello sotto risultano uguali senza costanti da ritarare
  // a mano. Prima header e album erano ancorati a top fissi (24 e 170) e la
  // scena finale restava 73px sopra il centro, con tutto lo spazio morto in
  // basso.
  static const headerH = 140.0;
  static const headerAlbumGap = 12.0;
  static const albumW = 280.0;
  static const albumH = 300.0;
  static const contentH = headerH + headerAlbumGap + albumH;
  static const sceneTop = (h - contentH) / 2;
  static const albumX = (w - albumW) / 2;
  static const albumY = sceneTop + headerH + headerAlbumGap;

  // Bustina (110x200 col lembo) e ventaglio sono centrati sul canvas, così
  // anche le fasi intermedie stanno esattamente al centro dello schermo.
  static const packBoxH = 200.0;
  static const packTargetY = (h - packBoxH) / 2;
  static const fanCy = cy;

  // Fasi (in secondi), identiche al design originale.
  static const pDrop = [0.0, 0.8];
  static const pTear = [0.8, 1.4];
  static const pOpen = [1.3, 1.9];
  static const pBurst = [1.7, 2.6];
  static const pHeader = [3.4, 4.0];
  static const pAlbum = [3.8, 4.5];
  static const pGridIn = [4.3, 5.4];
  static const pFlip = [5.4, 6.4];

  double _seg(List<double> p, double v) => _clamp01((v - p[0]) / (p[1] - p[0]));

  @override
  Widget build(BuildContext context) {
    final dropT = Curves.easeOutCubic.transform(_seg(pDrop, t));
    // La bustina parte fuori dal canvas di tutta la sua altezza, così non si
    // vede spuntare dal bordo prima che inizi la caduta.
    const packStartY = -packBoxH;
    final packY = packStartY + (packTargetY - packStartY) * dropT;
    final tearT = _seg(pTear, t);
    final openT = Curves.easeOutCubic.transform(_seg(pOpen, t));
    final packFade = 1 - _clamp01((t - 2.0) / 0.5);

    final headerT = Curves.easeOutBack.transform(_seg(pHeader, t));
    final albumT = Curves.easeOutCubic.transform(_seg(pAlbum, t));

    final slotW = (albumW - 50) / 3;
    final slotH = (albumH - 30) / 3;

    const fanCx = cx;
    const openX = cx, openY = packTargetY;

    return Container(
      color: _splashBg,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Header: logo + titolo ───────────────────────────────────────
          if (headerT > 0)
            Positioned(
              left: 0,
              right: 0,
              top: sceneTop,
              // Altezza riservata fissa: è quello che tiene centrata la
              // composizione anche se le metriche del font Caveat cambiano di
              // qualche pixel tra le piattaforme. OverflowBox lascia alla
              // Column la sua altezza naturale, centrata dentro il blocco,
              // senza mai andare in overflow se sfora.
              child: SizedBox(
                height: headerH,
                child: OverflowBox(
                  minHeight: 0,
                  maxHeight: double.infinity,
                  alignment: Alignment.center,
                  child: Opacity(
                    opacity: _clamp01(headerT),
                    child: Transform.scale(
                      scale: 0.85 + 0.15 * math.min(headerT, 1.0),
                      // Logo (con ombra sfocata) e wordmark non cambiano più
                      // dopo l'ingresso, ma senza boundary venivano
                      // ridisegnati a ogni frame perché lo Stack padre
                      // ridisegna tutti i figli quando una carta si muove.
                      child: const RepaintBoundary(child: _IntroHeader()),
                    ),
                  ),
                ),
              ),
            ),

          // ── Album vuoto sotto l'header ──────────────────────────────────
          if (albumT > 0)
            Positioned(
              left: albumX,
              top: albumY + (1 - albumT) * 12,
              child: Transform.scale(
                alignment: Alignment.topCenter,
                scale: 0.9 + 0.1 * albumT,
                // La cornice (rilegatura a spirale + griglia tratteggiata) è
                // il disegno più costoso della scena e resta identica una
                // volta entrata: il boundary la fa rasterizzare una volta sola
                // invece che a ogni frame.
                child: RepaintBoundary(
                  child: AlbumFrame(w: albumW, h: albumH, opacity: albumT),
                ),
              ),
            ),

          // ── Bustina ──────────────────────────────────────────────────────
          if (packFade > 0.01)
            Positioned(
              left: cx - 55,
              top: packY,
              child: Opacity(
                opacity: packFade,
                child: Transform.scale(
                  scale: 1 - _seg(pBurst, t) * 0.3,
                  child: BoosterPack(tearProgress: tearT, opening: openT),
                ),
              ),
            ),

          // ── Flash apertura ──────────────────────────────────────────────
          Builder(builder: (context) {
            final fT = _clamp01((t - 1.7) / 0.4);
            if (fT <= 0 || fT >= 1) return const SizedBox.shrink();
            return Positioned(
              left: openX - 30 * (1 + fT * 4),
              top: openY - 30 * (1 + fT * 4),
              child: Opacity(
                opacity: 1 - fT,
                child: Container(
                  width: 60 * (1 + fT * 4),
                  height: 60 * (1 + fT * 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [_cyan.withValues(alpha: 0.6), _cyan.withValues(alpha: 0)]),
                  ),
                ),
              ),
            );
          }),

          // ── Whoosh trails durante il burst ───────────────────────────────
          Builder(builder: (context) {
            final wT = _clamp01((t - pBurst[0]) / 0.6);
            if (wT <= 0 || wT >= 1) return const SizedBox.shrink();
            return Positioned.fill(
              child: Stack(
                children: List.generate(num, (i) {
                  final angDeg = -fanSpread / 2 + (i / (num - 1)) * fanSpread;
                  final angRad = angDeg * math.pi / 180;
                  final dist = 80 * wT;
                  return Whoosh(
                    from: const Offset(openX, openY),
                    to: Offset(openX + math.sin(angRad) * dist, openY + 30 + (1 - math.cos(angRad)) * dist * 0.5),
                  );
                }),
              ),
            );
          }),

          // ── Le 7 carte: bustina → ventaglio → album, con flip ────────────
          ...List.generate(num, (i) {
            final burstDelay = i * 0.04;
            final bT = Curves.easeOutCubic.transform(_clamp01((t - pBurst[0] - burstDelay) / 0.7));

            final angDeg = -fanSpread / 2 + (i / (num - 1)) * fanSpread;
            final angRad = angDeg * math.pi / 180;
            final fanX = fanCx + math.sin(angRad) * fanRadius;
            final fanY = fanCy + (1 - math.cos(angRad)) * 30 - 10;
            final fanRot = angDeg;

            final col = i % 3, row = i ~/ 3;
            final gridX = albumX + 36 + col * slotW + slotW / 2 - 4;
            final gridY = albumY + 12 + row * slotH + slotH / 2 - 4;

            final gridDelay = i * 0.05;
            final gT = Curves.easeInOutCubic.transform(_clamp01((t - pGridIn[0] - gridDelay) / 0.7));

            final flipDelay = pFlip[0] + i * 0.07;
            final flipT = _clamp01((t - flipDelay) / 0.5);

            double x, y, rot, scale, opacity;
            if (gT > 0) {
              x = fanX + (gridX - fanX) * gT;
              final yLin = fanY + (gridY - fanY) * gT;
              final arc = -math.sin(gT * math.pi) * 25;
              y = yLin + arc;
              rot = fanRot * (1 - gT);
              scale = 1 - gT * 0.35;
              opacity = 1;
            } else if (bT > 0) {
              x = openX + (fanX - openX) * bT;
              final yLin = openY + (fanY - openY) * bT;
              final arc = -math.sin(bT * math.pi) * 35;
              y = yLin + arc;
              rot = fanRot * bT;
              scale = 0.45 + 0.55 * bT;
              opacity = bT;
            } else {
              x = 0;
              y = 0;
              rot = 0;
              scale = 0;
              opacity = 0;
            }

            if (opacity <= 0.01) return const SizedBox.shrink();

            final flipScaleX = flipT == 0 ? 1.0 : (math.cos(flipT * math.pi)).abs();
            final showFace = flipT >= 0.5;
            final monster = _pickMonster(i + 1);

            return Positioned(
              left: x - 32,
              top: y - 46,
              child: Opacity(
                opacity: opacity,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..rotateZ(rot * math.pi / 180)
                    ..scaleByDouble(scale * flipScaleX, scale, 1.0, 1.0),
                  // Il contenuto della carta (mostro a tratti + layout del
                  // testo della label) cambia solo al flip: il boundary evita
                  // di ridisegnarlo a ogni frame mentre la carta si muove.
                  child: RepaintBoundary(
                    child: WireCard(
                      w: 64,
                      h: 92,
                      faceUp: showFace,
                      seed: i + 1,
                      label: showFace ? _monsterNames[monster.idx] : null,
                      theme: _cardThemes[i % 3],
                    ),
                  ),
                ),
              ),
            );
          }),

          // ── Badge "+9" finale ─────────────────────────────────────────────
          Builder(builder: (context) {
            final bT = _clamp01((t - 6.6) / 0.3);
            if (bT <= 0) return const SizedBox.shrink();
            final scale = 0.6 + 0.4 * Curves.easeOutBack.transform(bT);
            return Positioned(
              right: 36,
              top: albumY + 4,
              child: Opacity(
                opacity: bT,
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _cyan,
                      shape: BoxShape.circle,
                      border: Border.all(color: _ink, width: 1.5),
                      boxShadow: const [BoxShadow(color: Color(0x26000000), offset: Offset(2, 2))],
                    ),
                    alignment: Alignment.center,
                    child: const Text('+9', style: TextStyle(color: _ink, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Header della scena: logo dell'app + wordmark. Estratto in un widget a sé
/// perché il suo contenuto è costante — l'unica cosa che cambia durante
/// l'ingresso sono opacità e scala, applicate dal chiamante.
class _IntroHeader extends StatelessWidget {
  const _IntroHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            'assets/icon/dm_logo_no_white.png',
            fit: BoxFit.cover,
            cacheWidth: kLogoDecodeCacheWidth,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Deck Master',
          style: TextStyle(
            fontFamily: 'Caveat',
            fontSize: 38,
            color: _gold,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          '— MY COLLECTION —',
          style: TextStyle(fontSize: 8, color: _goldSoft, letterSpacing: 2.2),
        ),
      ],
    );
  }
}

/// Wrapper usato dallo splash: mostra subito il logo (identico allo splash
/// nativo, per un cambio invisibile), lo sfuma a schermo vuoto, e SOLO DOPO
/// monta la [BoosterIntroAnimation] — le due fasi sono sequenziali, non
/// sovrapposte, perché l'animazione non esiste ancora (quindi non sta già
/// "cadendo" sotto al logo) mentre il bridge è visibile.
/// Rimuove anche lo splash nativo non appena questo widget ha disegnato il
/// suo primo frame, evitando l'animazione di uscita (e il crop) del logo
/// nativo Android 12+.
class SplashIntro extends StatefulWidget {
  final VoidCallback? onCompleted;
  const SplashIntro({super.key, this.onCompleted});

  @override
  State<SplashIntro> createState() => _SplashIntroState();
}

class _SplashIntroState extends State<SplashIntro> with SingleTickerProviderStateMixin {
  late AnimationController _bridgeController;
  bool _showBooster = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _bridgeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      FlutterNativeSplash.remove();
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      await _bridgeController.forward();
      if (mounted) setState(() => _showBooster = true);
    });
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = 'v${info.version}');
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _bridgeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bridgeOpacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _bridgeController, curve: Curves.easeOut),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_showBooster)
          BoosterIntroAnimation(onCompleted: widget.onCompleted)
        else
          FadeTransition(
            opacity: bridgeOpacity,
            child: Center(
              child: Image.asset(
                'assets/icon/dm_logo_no_white.png',
                width: 140,
                height: 140,
                fit: BoxFit.contain,
                cacheWidth: kLogoDecodeCacheWidth,
              ),
            ),
          ),
        if (_version.isNotEmpty)
          Positioned(
            left: 16,
            bottom: 16,
            child: Text(_version, style: const TextStyle(fontSize: 11, color: _goldSoft)),
          ),
      ],
    );
  }
}
