import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/magic_models.dart';

/// Client per l'API Scryfall (Magic: The Gathering).
/// Nessuna chiave API richiesta. Rate limit: max 10 req/s.
class ScryfallService {
  static const _base = 'https://api.scryfall.com';

  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'DeckMaster/1.0 (g.favara.dev@gmail.com)',
  };

  /// Cerca carte Magic per nome. Restituisce max [limit] risultati.
  /// Usa `unique=cards` per de-duplicare per nome (una stampa per carta).
  static Future<List<MagicCardModel>> searchByName(
    String query, {
    int limit = 30,
  }) async {
    if (query.trim().isEmpty) return [];

    final uri = Uri.parse('$_base/cards/search').replace(queryParameters: {
      'q': 'name:"${query.trim()}"',
      'unique': 'cards',
      'order': 'name',
    });

    try {
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));

      if (response.statusCode == 404) return [];
      if (response.statusCode != 200) {
        throw ScryfallException('HTTP ${response.statusCode}');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'] as List<dynamic>? ?? [];
      return data
          .take(limit)
          .map((e) => MagicCardModel.fromScryfall(e as Map<String, dynamic>))
          .toList();
    } on ScryfallException {
      rethrow;
    } catch (e) {
      throw ScryfallException('Ricerca fallita: $e');
    }
  }

  /// Ricerca fuzzy per nome (suggerisce risultati anche con typo).
  static Future<List<MagicCardModel>> searchFuzzy(
    String query, {
    int limit = 30,
  }) async {
    if (query.trim().isEmpty) return [];

    final uri = Uri.parse('$_base/cards/search').replace(queryParameters: {
      'q': query.trim(),
      'unique': 'cards',
      'order': 'name',
    });

    try {
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));

      if (response.statusCode == 404) return [];
      if (response.statusCode != 200) {
        throw ScryfallException('HTTP ${response.statusCode}');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'] as List<dynamic>? ?? [];
      return data
          .take(limit)
          .map((e) => MagicCardModel.fromScryfall(e as Map<String, dynamic>))
          .toList();
    } on ScryfallException {
      rethrow;
    } catch (e) {
      throw ScryfallException('Ricerca fallita: $e');
    }
  }
}

class ScryfallException implements Exception {
  final String message;
  const ScryfallException(this.message);

  @override
  String toString() => 'ScryfallException: $message';
}
