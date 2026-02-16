/// Utility per rilevare la lingua dal set code
class LanguageDetector {
  /// Rileva la lingua dal set code (serial number)
  /// Esempi:
  /// - "MP14-EN092" → EN
  /// - "MP14-IT092" → IT
  /// - "SDY-E006" → EN (E = English)
  /// - "SDY-I006" → IT (I = Italian)
  static String detectLanguageFromSetCode(String setCode) {
    final upper = setCode.trim().toUpperCase();

    // Pattern: PREFIX-LANG123 o PREFIX-L123
    final match = RegExp(r'^[A-Z0-9]+-([A-Z]+)').firstMatch(upper);
    if (match == null) return 'EN'; // Default

    final langPart = match.group(1)!;

    // 2 lettere: IT, FR, DE, PT, EN, ES, JP, KR, ecc.
    if (langPart.length == 2) {
      switch (langPart) {
        case 'IT': return 'IT';
        case 'FR': return 'FR';
        case 'DE': return 'DE';
        case 'PT': return 'PT';
        case 'EN': return 'EN';
        case 'ES': return 'ES';
        case 'SP': return 'ES'; // Spanish alternative
        case 'JP': return 'JP';
        case 'JA': return 'JP'; // Japanese alternative
        case 'KR': return 'KR';
        case 'KO': return 'KR'; // Korean alternative
        default: return 'EN';
      }
    }

    // 1 lettera: E, I, F, D, P (regionale Europa)
    if (langPart.length == 1) {
      switch (langPart[0]) {
        case 'I': return 'IT';
        case 'F': return 'FR';
        case 'D': return 'DE';
        case 'P': return 'PT';
        case 'E': return 'EN';
        default: return 'EN';
      }
    }

    return 'EN'; // Fallback
  }

  /// Ottieni il suffisso del campo per la lingua
  /// EN → '' (base), IT → '_it', FR → '_fr', ecc.
  static String getFieldSuffix(String language) {
    final upper = language.toUpperCase();
    if (upper == 'EN') return '';
    switch (upper) {
      case 'IT': return '_it';
      case 'FR': return '_fr';
      case 'DE': return '_de';
      case 'PT': return '_pt';
      default: return '';
    }
  }
}
