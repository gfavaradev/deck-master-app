import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'exchange_rate_service.dart';

class AppPreferences {
  static AppPreferences? _instance;
  static AppPreferences get instance => _instance!;

  static late SharedPreferences _prefs;

  static const _langKey = 'app_ui_language';
  static const _currencyKey = 'app_currency';
  static const _onboardingKey = 'app_onboarding_done';

  static final localeNotifier = ValueNotifier<Locale>(const Locale('it'));
  static final currencyNotifier = ValueNotifier<String>('EUR');

  AppPreferences._();

  static Future<AppPreferences> init() async {
    if (_instance != null) return _instance!;
    _prefs = await SharedPreferences.getInstance();
    _instance = AppPreferences._();
    localeNotifier.value = Locale(_instance!.languageCode);
    currencyNotifier.value = _instance!.currencyCode;
    await ExchangeRateService.instance.init();
    return _instance!;
  }

  // ─── Onboarding ──────────────────────────────────────────────────────────

  bool get isOnboardingDone => _prefs.getBool(_onboardingKey) ?? false;

  Future<void> setOnboardingDone() => _prefs.setBool(_onboardingKey, true);

  // ─── Language ─────────────────────────────────────────────────────────────

  String get languageCode => _prefs.getString(_langKey) ?? 'it';

  Future<void> setLanguage(String code) async {
    await _prefs.setString(_langKey, code);
    localeNotifier.value = Locale(code);
  }

  // ─── Currency ─────────────────────────────────────────────────────────────

  String get currencyCode => _prefs.getString(_currencyKey) ?? 'EUR';

  Future<void> setCurrency(String code) async {
    await _prefs.setString(_currencyKey, code);
    currencyNotifier.value = code;
  }

  String get currencySymbol {
    return currencies.firstWhere((c) => c.code == currencyCode,
        orElse: () => currencies.first).symbol;
  }

  // ─── Static data ──────────────────────────────────────────────────────────

  static const languages = [
    (code: 'it', name: 'Italiano', flag: '🇮🇹'),
    (code: 'en', name: 'English',  flag: '🇬🇧'),
  ];

  static const currencies = [
    (code: 'EUR', symbol: '€',   name: 'Euro'),
    (code: 'USD', symbol: '\$',  name: 'US Dollar'),
    (code: 'GBP', symbol: '£',   name: 'British Pound'),
    (code: 'JPY', symbol: '¥',   name: 'Japanese Yen'),
    (code: 'CHF', symbol: 'Fr.', name: 'Swiss Franc'),
  ];

  String languageName(String code) =>
      languages.firstWhere((l) => l.code == code, orElse: () => languages.first).name;

  String currencyName(String code) =>
      currencies.firstWhere((c) => c.code == code, orElse: () => currencies.first).name;
}
