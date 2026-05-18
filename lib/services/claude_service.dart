import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_secrets.dart';

/// Client per l'Anthropic Messages API.
/// Usato per AI Deck Builder (Pro).
class ClaudeService {
  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-haiku-4-5-20251001';
  static const _apiVersion = '2023-06-01';

  static bool get isConfigured =>
      AppSecrets.anthropicApiKey.isNotEmpty &&
      AppSecrets.anthropicApiKey != 'your_anthropic_api_key_here';

  /// Invia un messaggio e restituisce la risposta testuale.
  /// Lancia [ClaudeApiException] in caso di errore.
  static Future<String> sendMessage({
    required String systemPrompt,
    required String userMessage,
    int maxTokens = 2048,
  }) async {
    final body = jsonEncode({
      'model': _model,
      'max_tokens': maxTokens,
      'system': systemPrompt,
      'messages': [
        {'role': 'user', 'content': userMessage},
      ],
    });

    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'x-api-key': AppSecrets.anthropicApiKey,
        'anthropic-version': _apiVersion,
        'content-type': 'application/json',
      },
      body: body,
    ).timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw ClaudeApiException(
        'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        statusCode: response.statusCode,
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final content = json['content'] as List<dynamic>?;
    if (content == null || content.isEmpty) {
      throw const ClaudeApiException('Risposta vuota dall\'API');
    }
    final text = (content.first as Map<String, dynamic>)['text'] as String?;
    if (text == null || text.isEmpty) {
      throw const ClaudeApiException('Contenuto testuale mancante');
    }
    return text;
  }
}

class ClaudeApiException implements Exception {
  final String message;
  final int? statusCode;

  const ClaudeApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ClaudeApiException: $message';
}
