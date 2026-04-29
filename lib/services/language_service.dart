import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;

class LanguageService {
  // Legacy key — kept for backward compatibility with existing SharedPreferences data
  static const String _legacyYugiohKey = 'yugioh_display_language';

  /// Languages available per collection. Collections not listed (or with empty list)
  /// have no language support and won't show the language picker.
  static const Map<String, List<String>> collectionLanguages = {
    'yugioh':   ['EN', 'IT', 'FR', 'DE', 'PT', 'SP'],
    'pokemon':  ['EN', 'IT', 'FR', 'DE', 'PT'],
    'onepiece': ['JP', 'EN', 'FR', 'KO', 'ZH'],
  };

  /// Kept for backward compatibility — same as yugioh list.
  static const List<String> supportedLanguages = ['EN', 'IT', 'FR', 'DE', 'PT', 'SP'];

  static const Map<String, String> languageLabels = {
    'EN': 'English',
    'IT': 'Italiano',
    'FR': 'Français',
    'DE': 'Deutsch',
    'PT': 'Português',
    'SP': 'Español',
    'JP': '日本語',
    'KO': '한국어',
    'ZH': '中文',
  };

  /// Bandiere emoji per codice lingua.
  static const Map<String, String> flagEmoji = {
    'EN': '🇬🇧',
    'IT': '🇮🇹',
    'FR': '🇫🇷',
    'DE': '🇩🇪',
    'PT': '🇵🇹',
    'SP': '🇪🇸',
    'JP': '🇯🇵',
    'KO': '🇰🇷',
    'ZH': '🇨🇳',
  };

  // Per-collection in-memory cache: avoids repeated SharedPreferences I/O
  static final Map<String, String> _cache = {};

  // Broadcast stream: pages subscribe to be notified when the language changes
  static final _controller = StreamController<String>.broadcast();
  static Stream<String> get onLanguageChanged => _controller.stream;

  static String _prefKey(String collectionKey) =>
      collectionKey == 'yugioh' ? _legacyYugiohKey : '${collectionKey}_display_language';

  // ── Legacy API (backward compat — delegates to yugioh) ──────────────────────

  static Future<String> getPreferredLanguage() =>
      getPreferredLanguageForCollection('yugioh');

  static Future<void> setPreferredLanguage(String languageCode) =>
      setPreferredLanguageForCollection('yugioh', languageCode);

  // ── Per-collection API ───────────────────────────────────────────────────────

  static Future<String> getPreferredLanguageForCollection(String collectionKey) async {
    final langs = collectionLanguages[collectionKey] ?? [];
    if (langs.isEmpty) return 'EN';
    if (_cache.containsKey(collectionKey)) return _cache[collectionKey]!;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey(collectionKey));
    final resolved = (saved != null && langs.contains(saved)) ? saved : _detectDeviceLanguage(langs);
    _cache[collectionKey] = resolved;
    return resolved;
  }

  static Future<void> setPreferredLanguageForCollection(String collectionKey, String languageCode) async {
    final code = languageCode.toUpperCase();
    _cache[collectionKey] = code;
    _controller.add('$collectionKey:$code');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey(collectionKey), code);
  }

  // ── Utility ──────────────────────────────────────────────────────────────────

  static String _detectDeviceLanguage(List<String> langs) {
    try {
      final String locale = Platform.localeName;
      final String code = locale.split('_')[0].toUpperCase();
      return langs.contains(code) ? code : 'EN';
    } catch (_) { // ignore: empty_catches
      return 'EN';
    }
  }

  /// Detects language from a serial code query, e.g. "LOB-EN001" → "EN", "SDAZ-IT042" → "IT".
  /// Returns null if the pattern is not recognized.
  static String? detectLanguageFromQuery(String query) {
    final match = RegExp(r'^[A-Z0-9]+-([A-Z]{2})\d', caseSensitive: false)
        .firstMatch(query.trim());
    if (match == null) return null;
    final code = match.group(1)!.toUpperCase();
    return supportedLanguages.contains(code) ? code : null;
  }
}
