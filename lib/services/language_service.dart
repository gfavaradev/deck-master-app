import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;

class LanguageService {
  static const String _languageKey = 'yugioh_display_language';
  static const List<String> supportedLanguages = ['EN', 'IT', 'FR', 'DE', 'PT'];

  static const Map<String, String> languageLabels = {
    'EN': 'English',
    'IT': 'Italiano',
    'FR': 'Français',
    'DE': 'Deutsch',
    'PT': 'Português',
  };

  // In-memory cache: avoids repeated SharedPreferences I/O on every page load
  static String? _cached;

  // Broadcast stream: pages subscribe to be notified when the language changes
  static final _controller = StreamController<String>.broadcast();
  static Stream<String> get onLanguageChanged => _controller.stream;

  static Future<String> getPreferredLanguage() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_languageKey);
    _cached = (saved != null && supportedLanguages.contains(saved))
        ? saved
        : _detectDeviceLanguage();
    return _cached!;
  }

  static Future<void> setPreferredLanguage(String languageCode) async {
    final code = languageCode.toUpperCase();
    _cached = code; // update cache immediately
    _controller.add(code); // notify all listeners
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, code);
  }

  static String _detectDeviceLanguage() {
    final String locale = Platform.localeName;
    final String code = locale.split('_')[0].toUpperCase();
    return supportedLanguages.contains(code) ? code : 'EN';
  }
}
