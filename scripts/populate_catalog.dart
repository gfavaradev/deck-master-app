// ignore_for_file: avoid_print
library;

/// Script per popolare il catalogo Yu-Gi-Oh su Firestore.
///
/// Eseguire con: flutter run -t scripts/populate_catalog.dart -d windows
///
/// Dopo aver caricato il catalogo, rimuovere http:
///   flutter pub remove http

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:deck_master/firebase_options.dart';

const String backendUrl = 'https://deck-master-backend-kappa.vercel.app/api';
const int pageLimit = 1000;
const int chunkSize = 350;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const PopulateCatalogApp());
}

class PopulateCatalogApp extends StatelessWidget {
  const PopulateCatalogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Populate Catalog')),
        body: const PopulateCatalogScreen(),
      ),
    );
  }
}

class PopulateCatalogScreen extends StatefulWidget {
  const PopulateCatalogScreen({super.key});

  @override
  State<PopulateCatalogScreen> createState() => _PopulateCatalogScreenState();
}

class _PopulateCatalogScreenState extends State<PopulateCatalogScreen> {
  String _status = 'Premi il bottone per iniziare';
  double? _progress;
  bool _running = false;

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _status = 'Scaricando carte dal backend...';
      _progress = null;
    });

    try {
      // Step 1: Fetch all cards from backend
      final allCards = await _fetchAllCards();
      setState(() => _status = 'Scaricate ${allCards.length} carte. Caricando su Firestore...');

      if (allCards.isEmpty) {
        setState(() {
          _status = 'Nessuna carta trovata!';
          _running = false;
        });
        return;
      }

      // Step 2: Split into chunks
      final List<List<Map<String, dynamic>>> chunks = [];
      for (int i = 0; i < allCards.length; i += chunkSize) {
        final end = (i + chunkSize < allCards.length) ? i + chunkSize : allCards.length;
        chunks.add(allCards.sublist(i, end));
      }

      // Step 3: Upload chunks to Firestore
      final firestore = FirebaseFirestore.instance;
      for (int i = 0; i < chunks.length; i++) {
        final chunkId = 'chunk_${(i + 1).toString().padLeft(3, '0')}';
        await firestore
            .collection('yugioh_catalog')
            .doc('chunks')
            .collection('items')
            .doc(chunkId)
            .set({'cards': chunks[i]});

        setState(() {
          _progress = (i + 1) / chunks.length;
          _status = 'Caricato chunk ${i + 1} di ${chunks.length}';
        });
      }

      // Step 4: Write metadata
      await firestore.collection('yugioh_catalog').doc('metadata').set({
        'totalCards': allCards.length,
        'totalChunks': chunks.length,
        'chunkSize': chunkSize,
        'lastUpdated': FieldValue.serverTimestamp(),
        'version': 1,
      });

      setState(() {
        _status = 'Completato! ${allCards.length} carte in ${chunks.length} chunks.';
        _progress = 1.0;
        _running = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Errore: $e';
        _running = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAllCards() async {
    final List<Map<String, dynamic>> allCards = [];
    int currentPage = 1;
    bool hasMore = true;

    while (hasMore) {
      final url = '$backendUrl/yugioh/export-batch?page=$currentPage&limit=$pageLimit';
      setState(() => _status = 'Scaricando pagina $currentPage...');

      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        List<dynamic> cardsData = [];
        int? totalPages;

        if (data is Map) {
          cardsData = data['cards'] ?? data['data'] ?? [];
          totalPages = data['totalPages'] ?? data['total_pages'];
        } else if (data is List) {
          cardsData = data;
        }

        if (cardsData.isEmpty) {
          hasMore = false;
        } else {
          final transformed = _transformCards(cardsData);
          allCards.addAll(transformed);

          setState(() {
            if (totalPages != null) {
              _progress = currentPage / totalPages;
            }
            _status = 'Pagina $currentPage${totalPages != null ? " di $totalPages" : ""} - ${allCards.length} carte totali';
          });

          if (totalPages != null && currentPage >= totalPages) {
            hasMore = false;
          } else if (cardsData.length < pageLimit) {
            hasMore = false;
          } else {
            currentPage++;
          }
        }
      } else {
        throw Exception('Errore pagina $currentPage: HTTP ${response.statusCode}');
      }
    }

    return allCards;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_upload, size: 64, color: Colors.blue),
            const SizedBox(height: 20),
            const Text(
              'Popola catalogo Yu-Gi-Oh su Firestore',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            if (_progress != null) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 10),
            ],
            if (_running && _progress == null)
              const CircularProgressIndicator(),
            const SizedBox(height: 10),
            Text(_status, textAlign: TextAlign.center),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _running ? null : _run,
              icon: const Icon(Icons.play_arrow),
              label: Text(_running ? 'In corso...' : 'Avvia'),
            ),
          ],
        ),
      ),
    );
  }
}

List<Map<String, dynamic>> _transformCards(List<dynamic> apiCards) {
  return apiCards.map((card) {
    final prints = card['prints'] as List<dynamic>? ?? [];

    final transformedPrints = prints.map((p) {
      final prices = p['prices'] as Map<String, dynamic>? ?? {};

      final Map<String, dynamic> pricesPerLang = {};
      for (final lang in ['EN', 'IT', 'FR', 'DE', 'PT']) {
        final langPrices = prices[lang] as Map<String, dynamic>?;
        if (langPrices != null && langPrices.isNotEmpty) {
          pricesPerLang[lang] = langPrices;
        }
      }
      if (pricesPerLang.isEmpty && prices.isNotEmpty && !prices.containsKey('EN')) {
        pricesPerLang['EN'] = prices;
      }

      return {
        'set_code': p['setCode'] ?? '',
        'set_name': p['setName'],
        'rarity': p['rarity'],
        'rarity_code': p['rarityCode'],
        'set_price': _parseDouble(prices['cardmarketPrice'] ?? p['cardmarketPrice']),
        'artwork': p['artworkUrl'] ?? p['artwork'],
        'set_name_it': p['setNameIt'],
        'set_code_it': p['setCodeIt'],
        'rarity_it': p['rarityIt'],
        'rarity_code_it': p['rarityCodeIt'],
        'set_price_it': _parseDouble(p['setPriceIt']),
        'set_name_fr': p['setNameFr'],
        'set_code_fr': p['setCodeFr'],
        'rarity_fr': p['rarityFr'],
        'rarity_code_fr': p['rarityCodeFr'],
        'set_price_fr': _parseDouble(p['setPriceFr']),
        'set_name_de': p['setNameDe'],
        'set_code_de': p['setCodeDe'],
        'rarity_de': p['rarityDe'],
        'rarity_code_de': p['rarityCodeDe'],
        'set_price_de': _parseDouble(p['setPriceDe']),
        'set_name_pt': p['setNamePt'],
        'set_code_pt': p['setCodePt'],
        'rarity_pt': p['rarityPt'],
        'rarity_code_pt': p['rarityCodePt'],
        'set_price_pt': _parseDouble(p['setPricePt']),
        'prices': pricesPerLang,
      };
    }).toList();

    return {
      'id': card['id'] is int ? card['id'] : int.tryParse(card['id']?.toString() ?? ''),
      'type': card['type'] ?? '',
      'human_readable_type': card['humanReadableCardType'] ?? '',
      'frame_type': card['frameType'] ?? '',
      'race': card['race'] ?? '',
      'archetype': card['archetype'],
      'ygoprodeck_url': card['ygoprodeckUrl'],
      'atk': card['atk'],
      'def': card['def'],
      'level': card['level'],
      'attribute': card['attribute'],
      'scale': card['scale'],
      'linkval': card['linkval'],
      'linkmarkers': (card['linkmarkers'] as List<dynamic>?)?.join(','),
      'name': card['name'] ?? '',
      'description': card['description'] ?? '',
      'name_it': card['nameIt'],
      'description_it': card['descriptionIt'],
      'name_fr': card['nameFr'],
      'description_fr': card['descriptionFr'],
      'name_de': card['nameDe'],
      'description_de': card['descriptionDe'],
      'name_pt': card['namePt'],
      'description_pt': card['descriptionPt'],
      'prints': transformedPrints,
    };
  }).toList();
}

double? _parseDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
