import 'package:flutter/material.dart';
import '../services/language_service.dart';

/// Rileva la lingua dal serial number.
/// One Piece: OP01-001 → JP (cifra dopo dash = JP), OP01-EN001 → EN
/// YuGiOh: LOB-EN005 → EN, LOB-IT005 → IT
/// Altri giochi: cifra dopo dash = EN (default)
String opLangFromSerial(String? serial, {String collection = ''}) {
  if (serial == null || serial.isEmpty) return 'EN';
  if (!serial.contains('-')) return 'EN';
  final afterDash = serial.substring(serial.indexOf('-') + 1);
  if (afterDash.isEmpty) return 'EN';
  final first = afterDash.codeUnitAt(0);
  if (first >= 0x30 && first <= 0x39) {
    // Cifra dopo dash: One Piece senza prefisso = JP, altri giochi = EN
    return collection == 'onepiece' ? 'JP' : 'EN';
  }
  // Prefisso 2 lettere uppercase
  final match = RegExp(r'^([A-Za-z]{2})').firstMatch(afterDash);
  return match != null ? match.group(1)!.toUpperCase() : 'EN';
}

/// Badge lingua per carte One Piece.
/// Mostra bandiera + codice (es. 🇯🇵 JP, 🇬🇧 EN).
class OpLangBadge extends StatelessWidget {
  final String serialNumber;
  final String collection;
  /// Se true usa un layout compatto (solo testo, senza bandiera) — per spazi stretti.
  final bool compact;

  const OpLangBadge({
    super.key,
    required this.serialNumber,
    this.collection = '',
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final lang = opLangFromSerial(serialNumber, collection: collection);
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
