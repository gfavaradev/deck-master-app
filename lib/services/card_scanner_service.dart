import 'dart:convert';
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

  // ─── Serial patterns (used in OCR and Pokémon catalog search) ───────────────

  // Pokémon: numero stampato sulla carta  025/202  001/264
  static final _pokemonNumber = RegExp(r'\b(\d{1,3})/\d{2,3}\b');

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Opens the device camera, captures a photo, then attempts to identify
  /// the card. Returns null if cancelled or unidentifiable.
  ///
  /// Pass [collectionHint] (e.g. 'pokemon', 'yugioh') when the current context
  /// is known — Gemini will be biased toward that game for better accuracy.
  Future<CardScanResult?> scanFromCamera({String? collectionHint}) async {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (image == null) return null;
    return _processImage(image, collectionHint: collectionHint);
  }

  /// Processes an already-captured [XFile] image.
  Future<CardScanResult?> processImage(XFile image, {String? collectionHint}) =>
      _processImage(image, collectionHint: collectionHint);

  // ─── Internal processing ──────────────────────────────────────────────────

  Future<CardScanResult?> _processImage(XFile image,
      {String? collectionHint}) async {
    // Step 1 — ML Kit OCR
    final ocrResult = await _tryOcr(image, collectionHint: collectionHint);
    if (ocrResult != null) return ocrResult;

    // Step 2 — Gemini Vision fallback
    return _tryGemini(image, collectionHint: collectionHint);
  }

  Future<CardScanResult?> _tryOcr(XFile image,
      {String? collectionHint}) async {
    // ML Kit disabled for simulator build (iOS 26 incompatibility)
    // When re-enabled, use: _ygoSerial, _opSerial, _pokemonNumber patterns

    return null;
  }

  Future<CardScanResult?> _tryGemini(XFile image,
      {String? collectionHint}) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty || apiKey == 'your_gemini_api_key_here') {

      return null;
    }

    try {
      final model = GenerativeModel(
        model: 'gemini-2.0-flash',
        apiKey: apiKey,
      );

      final bytes = await image.readAsBytes();

      final hintLine = collectionHint != null
          ? 'Note: this card is likely from ${_collectionDisplayName(collectionHint)}.\n'
          : '';

      final prompt =
          '''You are a trading card game expert. Look at this card image and identify it.
${hintLine}Return ONLY a raw JSON object (no markdown, no explanation):
{"name":"exact english card name","serial":"identifier printed on card","collection":"yugioh or pokemon or onepiece","set_name":"set/expansion name (Pokemon only)"}
If you cannot identify the card with confidence return: {"error":"not_found"}
Serial format per game:
- Yu-Gi-Oh!: SETCODE-LANG### e.g. LOB-EN001, RA01-EN001
- Pokémon: the number printed at the bottom e.g. 025/202 (include the /total)
- One Piece TCG: OP##-### or ST##-### e.g. OP01-001''';

      final response = await model.generateContent([
        Content.multi([
          DataPart('image/jpeg', bytes),
          TextPart(prompt),
        ]),
      ]).timeout(const Duration(seconds: 30));

      final text = response.text ?? '';


      // Gemini può wrappare la risposta in ```json ... ``` — rimuoviamo il markdown
      final stripped = text
          .replaceAll(RegExp(r'```json\s*', caseSensitive: false), '')
          .replaceAll('```', '')
          .trim();

      // Cerca il primo oggetto JSON nel testo ripulito
      final jsonMatch =
          RegExp(r'\{.*?\}', dotAll: true).firstMatch(stripped);
      if (jsonMatch == null) return null;

      Map<String, dynamic> data;
      try {
        data = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
      } catch (_) { // ignore: empty_catches

        return null;
      }
      if (data.containsKey('error')) return null;

      final name = (data['name'] as String? ?? '').trim();
      final serial = (data['serial'] as String? ?? '').trim();
      final collection =
          (data['collection'] as String? ?? '').trim().toLowerCase();
      final setName = (data['set_name'] as String? ?? '').trim();

      if (name.isEmpty || collection.isEmpty) return null;
      if (!['yugioh', 'pokemon', 'onepiece'].contains(collection)) return null;

      // Try to find in local catalog (collection-aware strategy)
      final catalogCard =
          await _searchCatalogSmart(collection, name, serial, setName: setName);

      return CardScanResult(
        cardName: name,
        serialNumber: serial,
        collection: collection,
        catalogCard: catalogCard,
        source: 'gemini',
      );
    } catch (e) { // ignore: empty_catches

      return null;
    }
  }

  // ─── Catalog search helpers ───────────────────────────────────────────────

  static String _collectionDisplayName(String key) => switch (key) {
        'yugioh' => 'Yu-Gi-Oh!',
        'pokemon' => 'Pokémon',
        'onepiece' => 'One Piece TCG',
        _ => key,
      };

  /// Collection-aware catalog lookup.
  Future<Map<String, dynamic>?> _searchCatalogSmart(
    String collection,
    String name,
    String serial, {
    String setName = '',
  }) async {
    if (collection == 'pokemon') {
      return _searchPokemonCatalog(name, serial, setName);
    }
    // YGO and OP: serial is the primary lookup key
    if (serial.isNotEmpty) {
      final bySerial = await _searchCatalog(collection, serial);
      if (bySerial != null) return bySerial;
    }
    if (name.isNotEmpty) {
      return _searchCatalog(collection, name);
    }
    return null;
  }

  /// Pokémon-specific search: name first, then narrow by card number.
  ///
  /// Pokémon serials are printed as "025/202" — we extract the number part
  /// and compare against the `number` field in pokemon_cards.
  Future<Map<String, dynamic>?> _searchPokemonCatalog(
      String name, String serial, String setName) async {
    if (name.isEmpty) return null;

    final results = await _repo.getCatalogCardsByCollection(
      'pokemon',
      query: name,
      limit: 50,
    );
    if (results.isEmpty) return null;
    if (results.length == 1) return results.first;

    // Try to narrow by card number extracted from serial (e.g. "025/202" → "025" → 25)
    final numberMatch = _pokemonNumber.firstMatch(serial);
    if (numberMatch != null) {
      final raw = numberMatch.group(1)!; // e.g. "025"
      final parsed = int.tryParse(raw);
      final candidate = results.firstWhere(
        (r) {
          final n = (r['number'] as String? ?? '');
          return n == raw ||
              n == parsed?.toString() ||
              n.padLeft(3, '0') == raw.padLeft(3, '0');
        },
        orElse: () => <String, dynamic>{},
      );
      if (candidate.isNotEmpty) return candidate;
    }

    // Try to narrow by set name
    if (setName.isNotEmpty) {
      final lc = setName.toLowerCase();
      final candidate = results.firstWhere(
        (r) {
          final sn = (r['setName'] as String? ?? '').toLowerCase();
          return sn.contains(lc) || lc.contains(sn);
        },
        orElse: () => <String, dynamic>{},
      );
      if (candidate.isNotEmpty) return candidate;
    }

    return results.first;
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
