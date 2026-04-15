import 'package:flutter/material.dart';

/// Palette colori ufficiale di Deck Master.
/// Derivata dal logo: scudo DM con sfondo blu notte e bordo dorato.
abstract final class AppColors {
  // ── Sfondi ──────────────────────────────────────────────────────────────────
  static const Color bgDark    = Color(0xFF12152A); // sfondo principale
  static const Color bgMedium  = Color(0xFF1A1E3C); // AppBar, BottomNav, card
  static const Color bgLight   = Color(0xFF242850); // card elevate, dialog

  // ── Accenti logo ─────────────────────────────────────────────────────────────
  static const Color gold      = Color(0xFFD4AF37); // bordo scudo – primary
  static const Color blue      = Color(0xFF4D7FFF); // lettera DM – secondary
  static const Color purple    = Color(0xFF7C4DFF); // sfumatura logo

  // ── Stati semantici ──────────────────────────────────────────────────────────
  static const Color success = Color(0xFF4CAF50);
  static const Color error   = Color(0xFFE53935);
  static const Color warning = Color(0xFFFFB300);
  static const Color info    = Color(0xFF29B6F6);

  // ── Collezioni ───────────────────────────────────────────────────────────────
  static const Color yugiohAccent   = Color(0xFFD4AC0D); // oro reale YGO
  static const Color pokemonAccent  = Color(0xFFEF3A3A); // rosso Pokéball
  static const Color onepieceAccent = Color(0xFF1E88E5); // blu oceano
  static const Color magicAccent    = Color(0xFF7E57C2); // viola arcano MTG

  // ── Mappa colori per chiave collezione ───────────────────────────────────────
  static Color forCollection(String key) => switch (key) {
    'yugioh'            => const Color(0xFFD4AC0D), // oro reale
    'pokemon'           => const Color(0xFFEF3A3A), // rosso Pokéball
    'magic'             => const Color(0xFF7E57C2), // viola arcano
    'onepiece'          => const Color(0xFF1E88E5), // blu oceano
    'digimon'           => const Color(0xFF00ACC1), // ciano digitale
    'dragon-ball-super' => const Color(0xFFFF6D00), // arancione SSJ
    'lorcana'           => const Color(0xFF7B1FA2), // viola Disney
    'flesh-and-blood'   => const Color(0xFFBF360C), // rosso sangue
    'vanguard'          => const Color(0xFF00695C), // verde militare
    'star-wars'         => const Color(0xFFFFD600), // giallo titolo SW
    'riftbound'         => const Color(0xFF1565C0), // blu fantasy
    'gundam'            => const Color(0xFF546E7A), // grigio mecha
    'union-arena'       => const Color(0xFF2E7D32), // verde battaglia
    _                   => const Color(0xFF607D8B), // grigio default
  };

  // ── Servizi terzi ────────────────────────────────────────────────────────────
  static const Color cardtraderTeal    = Color(0xFF4ECDC4);
  static const Color cardtraderBg      = Color(0xFF0D3330);
  static const Color cardtraderBorder  = Color(0xFF1A6B5A);

  // ── Testo ────────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Colors.white;
  static const Color textSecondary = Color(0xB3FFFFFF); // white70
  static const Color textHint      = Color(0x80FFFFFF); // white50

  // ── Bordi e divisori ─────────────────────────────────────────────────────────
  static const Color border        = Color(0x40FFFFFF);
  static const Color divider       = Color(0x1FFFFFFF);

  // ── Glow (con opacità) ────────────────────────────────────────────────────────
  static const Color glowBlue   = Color(0x554D7FFF);
  static const Color glowGold   = Color(0x44D4AF37);
  static const Color glowPurple = Color(0x337C4DFF);
}
