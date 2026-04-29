import 'package:flutter/material.dart';
import '../services/language_service.dart';

/// Rileva la lingua di una carta One Piece dal suo serial number / card_set_id.
/// OP01-001  → 'JP'  (collector number inizia con cifra = giapponese)
/// OP01-EN001 → 'EN'  (prefisso 2 lettere)
/// OP01-FR001 → 'FR', OP01-KO001 → 'KO', ecc.
String opLangFromSerial(String? serial) {
  if (serial == null || serial.isEmpty) return 'JP';
  if (!serial.contains('-')) return 'JP';
  final afterDash = serial.substring(serial.indexOf('-') + 1);
  if (afterDash.isEmpty) return 'JP';
  final first = afterDash.codeUnitAt(0);
  // Inizia con cifra → JP (no prefisso lingua)
  if (first >= 0x30 && first <= 0x39) return 'JP';
  // Prefisso 2 lettere uppercase
  final match = RegExp(r'^([A-Za-z]{2})').firstMatch(afterDash);
  return match != null ? match.group(1)!.toUpperCase() : 'JP';
}

/// Badge lingua per carte One Piece.
/// Mostra bandiera + codice (es. 🇯🇵 JP, 🇬🇧 EN).
class OpLangBadge extends StatelessWidget {
  final String serialNumber;
  /// Se true usa un layout compatto (solo testo, senza bandiera) — per spazi stretti.
  final bool compact;

  const OpLangBadge({
    super.key,
    required this.serialNumber,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final lang = opLangFromSerial(serialNumber);
    final flag = LanguageService.flagEmoji[lang] ?? '';
    final Color bg = switch (lang) {
      'JP' => const Color(0xCC8B0000),
      'EN' => const Color(0xCC003580),
      'FR' => const Color(0xCC003189),
      'KO' => const Color(0xCC0047A0),
      'ZH' => const Color(0xCCDE2910),
      _    => const Color(0xCC333333),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 5, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        compact ? lang : '$flag $lang',
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 8 : 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
