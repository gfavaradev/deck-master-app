import 'package:flutter/material.dart';

/// Palette colori ufficiale di Deck Master.
/// Derivata dal logo: scudo DM con sfondo blu notte e bordo dorato.
abstract final class AppColors {
  // ── Sfondi ──────────────────────────────────────────────────────────────────
  static const Color bgDark    = Color(0xFF161929); // sfondo principale
  static const Color bgMedium  = Color(0xFF1E2140); // AppBar, BottomNav, card
  static const Color bgLight   = Color(0xFF272B4A); // card elevate, dialog

  // ── Accenti logo ─────────────────────────────────────────────────────────────
  static const Color gold      = Color(0xFFD4AF37); // bordo scudo – primary
  static const Color blue      = Color(0xFF4D7FFF); // lettera DM – secondary
  static const Color purple    = Color(0xFF7C4DFF); // sfumatura logo

  // ── Stati semantici ──────────────────────────────────────────────────────────
  static const Color success = Color(0xFF4CAF50); // verde conferma
  static const Color error   = Color(0xFFE53935); // rosso errore
  static const Color warning = Color(0xFFFFB300); // arancio avviso
  static const Color info    = Color(0xFF29B6F6); // azzurro informativo

  // ── Collezioni ───────────────────────────────────────────────────────────────
  static const Color yugiohAccent   = Color(0xFF8B6914); // oro scuro YGO
  static const Color pokemonAccent  = Color(0xFFD32F2F); // rosso Pokémon
  static const Color onepieceAccent = Color(0xFF1565C0); // blu One Piece

  // ── Servizi terzi ────────────────────────────────────────────────────────────
  static const Color cardtraderTeal    = Color(0xFF4ECDC4); // testo/icone CardTrader
  static const Color cardtraderBg      = Color(0xFF0D3330); // sfondo badge CardTrader
  static const Color cardtraderBorder  = Color(0xFF1A6B5A); // bordo badge CardTrader

  // ── Testo ────────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Colors.white;
  static const Color textSecondary = Color(0xB3FFFFFF); // white70
  static const Color textHint      = Color(0x80FFFFFF); // white50

  // ── Bordi e divisori ─────────────────────────────────────────────────────────
  static const Color border        = Color(0x40FFFFFF); // bordi standard
  static const Color divider       = Color(0x1FFFFFFF); // divisori sottili

  // ── Glow (con opacità) ────────────────────────────────────────────────────────
  static const Color glowBlue   = Color(0x554D7FFF);
  static const Color glowGold   = Color(0x44D4AF37);
  static const Color glowPurple = Color(0x337C4DFF);
}
