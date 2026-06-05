import '../services/app_preferences.dart';
import '../services/exchange_rate_service.dart';

abstract final class CurrencyFormatter {
  static String get symbol => _symbolFor(AppPreferences.instance.currencyCode);

  static String get prefixText => '$symbol ';

  /// Format EUR double → selected currency string.
  static String format(double euros, {String? overrideCode}) {
    final code = overrideCode ?? AppPreferences.instance.currencyCode;
    return _doFormat(euros, code);
  }

  /// Format EUR cents (int?) → selected currency string. Returns '—' for null.
  static String formatCents(int? cents, {String? overrideCode}) {
    if (cents == null) return '—';
    return format(cents / 100, overrideCode: overrideCode);
  }

  /// Format EUR double with mandatory sign prefix (for gain/loss display).
  static String formatSigned(double euros, {String? overrideCode}) {
    final code = overrideCode ?? AppPreferences.instance.currencyCode;
    final rate = ExchangeRateService.instance.rateFor(code);
    final converted = euros * rate;
    final sym = _symbolFor(code);
    final abs = converted.abs();
    final formatted =
        code == 'JPY' ? abs.round().toString() : abs.toStringAsFixed(2);
    return '${converted >= 0 ? '+' : '-'}$sym$formatted';
  }

  /// Convert a value in the selected currency back to EUR for DB storage.
  static double toEuros(double amount, {String? overrideCode}) {
    final code = overrideCode ?? AppPreferences.instance.currencyCode;
    final rate = ExchangeRateService.instance.rateFor(code);
    return rate == 0 ? amount : amount / rate;
  }

  /// Convert EUR to the selected currency (for pre-filling input fields).
  static double fromEuros(double euros, {String? overrideCode}) {
    final code = overrideCode ?? AppPreferences.instance.currencyCode;
    return euros * ExchangeRateService.instance.rateFor(code);
  }

  static String _doFormat(double euros, String code) {
    final rate = ExchangeRateService.instance.rateFor(code);
    final converted = euros * rate;
    final sym = _symbolFor(code);
    final formatted =
        code == 'JPY' ? converted.round().toString() : converted.toStringAsFixed(2);
    return '$sym$formatted';
  }

  static String _symbolFor(String code) => AppPreferences.currencies
      .firstWhere((c) => c.code == code,
          orElse: () => AppPreferences.currencies.first)
      .symbol;
}
