import 'dart:convert';
import 'package:flutter/foundation.dart';
// google_mlkit_text_recognition disabled for simulator build
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'data_repository.dart';

/// Result from a card scan attempt.
class CardScanResult {
  final String cardName;
  final String serialNumber;
  final String collection;

  /// The full catalog card record (if found in local DB), usable as
  /// `initialCatalogCard` in [CardDialogs.showAddCard].
  final Map<String, dynamic>? catalogCard;

  /// 'ocr' = found via ML Kit text recognition.
  /// 'gemini' = found via Gemini Vision fallback.
  final String source;

  const CardScanResult({
    required this.cardName,
    required this.serialNumber,
    required this.collection,
    this.catalogCard,
    required this.source,
  });
}

/// Identifies trading cards from photos using ML Kit OCR + Gemini Vision fallback.
///
/// Flow:
///   1. ML Kit reads text from the image and matches known serial-number patterns.
///   2. If no match, Gemini Vision identifies the card from the photo.
///   3. Each hit is verified against the local catalog DB.
class CardScannerService {
  final DataRepository _repo = DataRepository();
  final ImagePicker _picker = ImagePicker();

  // ─── Serial patterns ───────────────────────────────────────────────────────

  // Yu-Gi-Oh con codice lingua: LOB-EN001  RA01-EN001  MAZE-EN111  TN19-EN014
  // Supporta set con cifre nel codice (RA01, TN19) e 3-4 digit nel numero.
  static final _ygoSerial = RegExp(r'[A-Z0-9]{2,6}-[A-Z]{2}\d{3,4}');

  // One Piece: OP01-001  ST01-001  EB01-001
  static final _opSerial = RegExp(r'(?:OP|ST|EB)\d{2}-\d{3}');

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Opens the device camera, captures a photo, then attempts to identify
  /// the card. Returns null if cancelled or unidentifiable.
  Future<CardScanResult?> scanFromCamera() async {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (image == null) return null;
    return _processImage(image);
  }

  /// Processes an already-captured [XFile] image.
  Future<CardScanResult?> processImage(XFile image) => _processImage(image);

  // ─── Internal processing ──────────────────────────────────────────────────

  Future<CardScanResult?> _processImage(XFile image) async {
    // Step 1 — ML Kit OCR
    final ocrResult = await _tryOcr(image);
    if (ocrResult != null) return ocrResult;

    // Step 2 — Gemini Vision fallback
    return _tryGemini(image);
  }

  Future<CardScanResult?> _tryOcr(XFile image) async {
    // ML Kit disabled for simulator build (iOS 26 incompatibility)
    debugPrint('[CardScanner OCR] disabled on simulator — skipping to Gemini');
    return null;
  }

  Future<CardScanResult?> _tryGemini(XFile image) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty || apiKey == 'your_gemini_api_key_here') {
      debugPrint('[CardScanner] GEMINI_API_KEY non configurata — fallback disabilitato');
      return null;
    }

    try {
      final model = GenerativeModel(
        model: 'gemini-2.0-flash',
        apiKey: apiKey,
      );

      final bytes = await image.readAsBytes();
      const prompt = '''You are a trading card game expert. Look at this card image and identify it.
Return ONLY a raw JSON object (no markdown, no explanation):
{"name":"exact english card name","serial":"set code printed on card e.g. LOB-EN001 or swsh1-1","collection":"yugioh or pokemon or onepiece"}
If you cannot identify the card with confidence return: {"error":"not_found"}
Important: "serial" for Yu-Gi-Oh looks like SETCODE-LANG###, for Pokemon like SET-### or ###/###, for One Piece like OP##-###.''';

      final response = await model.generateContent([
        Content.multi([
          DataPart('image/jpeg', bytes),
          TextPart(prompt),
        ]),
      ]).timeout(const Duration(seconds: 30));

      final text = response.text ?? '';
      debugPrint('[CardScanner Gemini] response: $text');

      // Gemini può wrappare la risposta in ```json ... ``` — rimuoviamo il markdown
      final stripped = text
          .replaceAll(RegExp(r'```json\s*', caseSensitive: false), '')
          .replaceAll('```', '')
          .trim();

      // Cerca il primo oggetto JSON nel testo ripulito
      final jsonMatch = RegExp(r'\{.*?\}', dotAll: true).firstMatch(stripped);
      if (jsonMatch == null) return null;

      Map<String, dynamic> data;
      try {
        data = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
      } catch (_) {
        debugPrint('[CardScanner Gemini] JSON parse error for: ${jsonMatch.group(0)}');
        return null;
      }
      if (data.containsKey('error')) return null;

      final name = (data['name'] as String? ?? '').trim();
      final serial = (data['serial'] as String? ?? '').trim();
      final collection = (data['collection'] as String? ?? '').trim().toLowerCase();

      if (name.isEmpty || collection.isEmpty) return null;
      if (!['yugioh', 'pokemon', 'onepiece'].contains(collection)) return null;

      // Try to find in local catalog
      Map<String, dynamic>? catalogCard;
      if (serial.isNotEmpty) {
        catalogCard = await _searchCatalog(collection, serial);
      }
      catalogCard ??= await _searchCatalog(collection, name);

      return CardScanResult(
        cardName: name,
        serialNumber: serial,
        collection: collection,
        catalogCard: catalogCard,
        source: 'gemini',
      );
    } catch (e) {
      debugPrint('[CardScanner Gemini] error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _searchCatalog(
      String collection, String query) async {
    if (query.isEmpty) return null;
    final results = await _repo.getCatalogCardsByCollection(
      collection,
      query: query,
    );
    return results.isNotEmpty ? results.first : null;
  }
}
