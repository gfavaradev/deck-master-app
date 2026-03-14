import 'package:flutter/material.dart';

/// Tier donazione — si scala in base al totale cumulativo donato
enum DonationTier {
  none,
  comune,
  nonComune,
  raro,
  ultraRaro,
  secretRare;

  String get label {
    switch (this) {
      case DonationTier.none:       return '';
      case DonationTier.comune:     return 'Comune';
      case DonationTier.nonComune:  return 'Non Comune';
      case DonationTier.raro:       return 'Raro';
      case DonationTier.ultraRaro:  return 'Ultra Raro';
      case DonationTier.secretRare: return 'Secret Rare';
    }
  }

  String get symbol {
    switch (this) {
      case DonationTier.none:       return '';
      case DonationTier.comune:     return '☆';
      case DonationTier.nonComune:  return '◆';
      case DonationTier.raro:       return '★';
      case DonationTier.ultraRaro:  return '✦';
      case DonationTier.secretRare: return '✦✦';
    }
  }

  String get badgeTitle {
    switch (this) {
      case DonationTier.none:       return '';
      case DonationTier.comune:     return 'Sostenitore';
      case DonationTier.nonComune:  return 'Fan';
      case DonationTier.raro:       return 'Mecenate';
      case DonationTier.ultraRaro:  return 'Leggenda';
      case DonationTier.secretRare: return 'Fondatore';
    }
  }

  /// Totale cumulativo necessario per sbloccare questo tier
  double get requiredTotal {
    switch (this) {
      case DonationTier.none:       return 0;
      case DonationTier.comune:     return 1.99;
      case DonationTier.nonComune:  return 6.0;
      case DonationTier.raro:       return 12.0;
      case DonationTier.ultraRaro:  return 20.0;
      case DonationTier.secretRare: return 30.0;
    }
  }

  DonationTier? get nextTier {
    switch (this) {
      case DonationTier.none:       return DonationTier.comune;
      case DonationTier.comune:     return DonationTier.nonComune;
      case DonationTier.nonComune:  return DonationTier.raro;
      case DonationTier.raro:       return DonationTier.ultraRaro;
      case DonationTier.ultraRaro:  return DonationTier.secretRare;
      case DonationTier.secretRare: return null;
    }
  }

  Color get color {
    switch (this) {
      case DonationTier.none:       return Colors.transparent;
      case DonationTier.comune:     return const Color(0xFF9E9E9E);
      case DonationTier.nonComune:  return const Color(0xFF4CAF50);
      case DonationTier.raro:       return const Color(0xFF2196F3);
      case DonationTier.ultraRaro:  return const Color(0xFFD4AF37);
      case DonationTier.secretRare: return const Color(0xFF9C27B0);
    }
  }

  /// Colori per gradiente (per animazioni speciali)
  List<Color> get gradientColors {
    switch (this) {
      case DonationTier.ultraRaro:
        return [const Color(0xFFD4AF37), const Color(0xFFF5E27A), const Color(0xFFD4AF37)];
      case DonationTier.secretRare:
        return [const Color(0xFF9C27B0), const Color(0xFFE040FB), const Color(0xFF3F51B5), const Color(0xFF9C27B0)];
      default:
        return [color, color];
    }
  }

  bool get hasBorder    => this != DonationTier.none && this != DonationTier.comune;
  bool get hasAnimation => this == DonationTier.ultraRaro || this == DonationTier.secretRare;
  bool get isInWallOfFame => this == DonationTier.secretRare;

  static DonationTier fromTotal(double total) {
    if (total >= 30.0) return DonationTier.secretRare;
    if (total >= 20.0) return DonationTier.ultraRaro;
    if (total >= 12.0) return DonationTier.raro;
    if (total >= 6.0)  return DonationTier.nonComune;
    if (total >= 1.99) return DonationTier.comune;
    return DonationTier.none;
  }

  static DonationTier fromString(String? s) {
    return DonationTier.values.firstWhere(
      (e) => e.name == s,
      orElse: () => DonationTier.none,
    );
  }
}
