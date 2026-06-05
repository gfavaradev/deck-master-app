import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ExchangeRateService {
  static final ExchangeRateService instance = ExchangeRateService._();
  ExchangeRateService._();

  static const _cacheKey = 'exchange_rates_v1';
  static const _timestampKey = 'exchange_rates_ts_v1';
  static const _ttlMs = 24 * 3600 * 1000;

  Map<String, double> _rates = const {'EUR': 1.0};

  double rateFor(String code) => _rates[code] ?? 1.0;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_timestampKey) ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    if (age < _ttlMs) {
      final raw = prefs.getString(_cacheKey);
      if (raw != null) {
        final parsed = _parse(raw);
        if (parsed.isNotEmpty) {
          _rates = parsed;
          return;
        }
      }
    }
    await _fetch(prefs);
  }

  Future<void> _fetch(SharedPreferences prefs) async {
    try {
      final res = await http
          .get(Uri.parse('https://open.er-api.com/v6/latest/EUR'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final parsed = _parse(res.body);
        if (parsed.isNotEmpty) {
          _rates = parsed;
          await prefs.setString(_cacheKey, res.body);
          await prefs.setInt(
              _timestampKey, DateTime.now().millisecondsSinceEpoch);
        }
      }
    } catch (_) {
      // Keep stale/default rates on network failure
    }
  }

  Map<String, double> _parse(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final ratesMap = json['rates'] as Map<String, dynamic>;
      return ratesMap.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }
}
