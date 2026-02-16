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

  static Future<String> getPreferredLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_languageKey);
    if (saved != null && supportedLanguages.contains(saved)) {
      return saved;
    }
    return _detectDeviceLanguage();
  }

  static Future<void> setPreferredLanguage(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, languageCode.toUpperCase());
  }

  static String _detectDeviceLanguage() {
    final String locale = Platform.localeName;
    final String code = locale.split('_')[0].toUpperCase();
    return supportedLanguages.contains(code) ? code : 'EN';
  }
}
