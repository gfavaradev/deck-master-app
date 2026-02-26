import 'package:flutter/material.dart';

/// Palette colori ufficiale di Deck Master
/// Derivata dal logo: scudo DM con sfondo blu notte e bordo dorato
abstract final class AppColors {
  // ── Sfondi ──────────────────────────────────────────────────────────────────
  static const Color bgDark    = Color(0xFF161929); // sfondo principale
  static const Color bgMedium  = Color(0xFF1E2140); // AppBar, BottomNav, card
  static const Color bgLight   = Color(0xFF272B4A); // card elevate, dialog

  // ── Accenti ─────────────────────────────────────────────────────────────────
  static const Color gold      = Color(0xFFD4AF37); // bordo scudo – primary
  static const Color blue      = Color(0xFF4D7FFF); // lettera DM – secondary
  static const Color purple    = Color(0xFF7C4DFF); // sfumatura logo

  // ── Testo ───────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Colors.white;
  static const Color textSecondary = Color(0xB3FFFFFF); // white70
  static const Color textHint      = Color(0x80FFFFFF); // white50

  // ── Sfumature glow (con opacità) ────────────────────────────────────────────
  static const Color glowBlue   = Color(0x554D7FFF);
  static const Color glowGold   = Color(0x44D4AF37);
  static const Color glowPurple = Color(0x337C4DFF);
}
