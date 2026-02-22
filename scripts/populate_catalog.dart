// ignore_for_file: avoid_print
library;

/// Script per popolare il catalogo Yu-Gi-Oh su Firestore da YGOPRODeck API.
///
/// Eseguire con: flutter run -t scripts/populate_catalog.dart -d chrome
///
/// Funzionalità:
/// - Scarica catalogo completo da YGOPRODeck API
/// - Organizza set per lingua (en, it, fr, de, pt)
/// - Genera automaticamente i set localizzati da EN:
///     LOB-EN001 → LOB-IT001, LOB-FR001, LOB-DE001, LOB-PT001
///     LOB-E001  → LOB-I001,  LOB-F001,  LOB-D001,  LOB-P001
///   Se la lingua ha già quel set nativo non viene sovrascritto.
///   Se il codice non ha prefisso lingua riconoscibile, copia il set EN.
/// - Upload su Firestore in chunk da 1000 carte
/// - Aggiornamenti incrementali (solo carte nuove)
/// - Migrazione: riempie set mancanti su catalogo esistente

import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:deck_master/firebase_options.dart';

const String ygoprodeckApiUrl = 'https://db.ygoprodeck.com/api/v7/cardinfo.php';
const int chunkSize = 200;

// Lingue supportate (spagnolo escluso)
const List<String> _supportedLangs = ['en', 'it', 'fr', 'de', 'pt'];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const PopulateCatalogApp());
}

class PopulateCatalogApp extends StatelessWidget {
  const PopulateCatalogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.data == null) {
            return const Scaffold(
              appBar: null,
              body: AdminLoginScreen(),
            );
          }
          return Scaffold(
            appBar: AppBar(
              title: Text('YGOPRODeck → Firestore  (${snapshot.data!.email})'),
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.logout, color: Colors.white),
                  label: const Text('Esci', style: TextStyle(color: Colors.white)),
                  onPressed: () => FirebaseAuth.instance.signOut(),
                ),
              ],
            ),
            body: const PopulateCatalogScreen(),
          );
        },
      ),
    );
  }
}

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String _error = '';

  Future<void> _loginEmail() async {
    setState(() { _loading = true; _error = ''; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Errore di accesso');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginGoogle() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final googleProvider = GoogleAuthProvider();
      await FirebaseAuth.instance.signInWithPopup(googleProvider);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Errore Google Sign-In');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 380,
        child: Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.admin_panel_settings, size: 60, color: Colors.deepPurple),
                const SizedBox(height: 16),
                const Text('Admin Login', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                TextField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                  onSubmitted: (_) => _loginEmail(),
                ),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(_error, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _loginEmail,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _loading
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Accedi con Email'),
                  ),
                ),
                if (kIsWeb) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _loginGoogle,
                      icon: const Icon(Icons.login),
                      label: const Text('Accedi con Google'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
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
  String _status = 'Scegli un\'azione per iniziare';
  double? _progress;
  bool _running = false;
  int _totalCards = 0;
  int _currentVersion = 0;

  @override
  void initState() {
    super.initState();
    _loadCurrentVersion();
  }

  Future<void> _loadCurrentVersion() async {
    try {
      final metadata = await FirebaseFirestore.instance
          .collection('yugioh_catalog')
          .doc('metadata')
          .get();
      if (metadata.exists) {
        setState(() {
          _currentVersion = metadata.data()?['version'] ?? 0;
          _totalCards = metadata.data()?['totalCards'] ?? 0;
        });
      }
    } catch (e) {
      print('Errore caricamento versione: $e');
    }
  }

  // ─── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _runFullDownload() async {
    if (_running) return;
    setState(() {
      _running = true;
      _status = 'Scaricando tutte le carte da YGOPRODeck API...';
      _progress = null;
    });

    try {
      final allCards = await _downloadFromYGOPRODeck();
      if (allCards.isEmpty) {
        setState(() { _status = 'Nessuna carta scaricata!'; _running = false; });
        return;
      }

      // Legge il catalogo esistente: preserva carte admin-modificate e imageUrl di Storage
      setState(() => _status = 'Recuperando dati esistenti da Firestore...');
      final existingMap = await _getExistingCardsMap();

      final adminModified = Map<int, Map<String, dynamic>>.fromEntries(
        existingMap.entries.where((e) => e.value['_adminModified'] == true),
      );

      // Raccoglie gli imageUrl di Firebase Storage per TUTTE le carte (non solo admin)
      final imageUrlMap = <int, String>{};
      for (final entry in existingMap.entries) {
        final url = entry.value['imageUrl'] as String?;
        if (url != null && url.contains('firebasestorage')) {
          imageUrlMap[entry.key] = url;
        }
      }

      if (adminModified.isNotEmpty) {
        setState(() => _status = 'Trovate ${adminModified.length} carte admin-modificate, '
            '${imageUrlMap.length} immagini Storage. Preservando...');
      }

      // Merge: carte admin preservate per intero; per le altre applica imageUrl salvato
      final mergedCards = allCards.map((card) {
        final id = card['id'] as int?;
        if (id == null) return card;
        if (adminModified.containsKey(id)) return adminModified[id]!;
        final imageUrl = imageUrlMap[id];
        if (imageUrl != null) {
          return Map<String, dynamic>.from(card)..['imageUrl'] = imageUrl;
        }
        return card;
      }).toList();

      setState(() => _status = 'Scaricate ${mergedCards.length} carte. Caricando su Firestore...');
      await _uploadToFirestore(mergedCards, isIncremental: false);
      setState(() {
        _status = 'Completato! ${mergedCards.length} carte in ${(mergedCards.length / chunkSize).ceil()} chunks.';
        _progress = 1.0;
        _running = false;
      });
      await _loadCurrentVersion();
    } catch (e) {
      setState(() { _status = 'Errore: $e'; _running = false; });
    }
  }

  /// Returns a map of cardId → card for ALL cards currently in Firestore.
  Future<Map<int, Map<String, dynamic>>> _getExistingCardsMap() async {
    final firestore = FirebaseFirestore.instance;
    final chunksSnapshot = await firestore
        .collection('yugioh_catalog')
        .doc('chunks')
        .collection('items')
        .get();

    final map = <int, Map<String, dynamic>>{};
    for (var doc in chunksSnapshot.docs) {
      for (final raw in (doc.data()['cards'] as List? ?? [])) {
        final card = Map<String, dynamic>.from(raw as Map);
        final id = card['id'];
        if (id is int) map[id] = card;
      }
    }
    return map;
  }

  Future<void> _runIncrementalUpdate() async {
    if (_running) return;
    setState(() {
      _running = true;
      _status = 'Controllo aggiornamenti disponibili...';
      _progress = null;
    });

    try {
      final allCards = await _downloadFromYGOPRODeck();
      final existingIds = await _getExistingCardIds();
      final newCards = allCards.where((card) => !existingIds.contains(card['id'])).toList();

      if (newCards.isEmpty) {
        setState(() { _status = 'Nessuna carta nuova trovata!'; _running = false; });
        return;
      }

      setState(() => _status = 'Trovate ${newCards.length} carte nuove. Caricando...');
      await _uploadToFirestore(newCards, isIncremental: true);
      setState(() {
        _status = 'Completato! Aggiunte ${newCards.length} carte nuove.';
        _progress = 1.0;
        _running = false;
      });
      await _loadCurrentVersion();
    } catch (e) {
      setState(() { _status = 'Errore: $e'; _running = false; });
    }
  }

  /// Carica le immagini delle carte su Firebase Storage.
  ///
  /// - Scarica i chunks esistenti da Firestore
  /// - Per ogni carta con `image_url` (ygoprodeck) ma senza `imageUrl` (Storage),
  ///   scarica l'immagine e la carica su Firebase Storage `yugioh/cards/{id}.jpg`
  /// - Aggiorna il campo `imageUrl` nella carta con il download URL di Storage
  /// - Scrive SOLO i chunks modificati (approccio chirurgico)
  Future<void> _runUploadImages() async {
    if (_running) return;

    // Image download via http.get() is blocked by CORS when running in Chrome.
    // Run the script with -d windows to avoid this restriction.
    if (kIsWeb) {
      setState(() {
        _status = 'Carica Immagini non è disponibile su Chrome a causa '
            'delle restrizioni CORS del browser.\n\n'
            'Esegui lo script su Windows:\n'
            'flutter run -t scripts/populate_catalog.dart -d windows';
      });
      return;
    }

    setState(() {
      _running = true;
      _status = 'Scaricando lista carte da Firestore...';
      _progress = null;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final storage = FirebaseStorage.instance;

      // 1. Download all chunks
      final chunksSnapshot = await firestore
          .collection('yugioh_catalog')
          .doc('chunks')
          .collection('items')
          .get();

      // Build ordered chunkMap: chunkId → mutable card list
      final chunkMap = <String, List<Map<String, dynamic>>>{};
      for (var doc in chunksSnapshot.docs) {
        final cards = (doc.data()['cards'] as List? ?? [])
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList();
        chunkMap[doc.id] = cards;
      }

      // 2. Collect cards that need image upload (have image_url but not imageUrl from Storage)
      final toUpload = <String, List<int>>{}; // chunkId → list of indices
      int totalToUpload = 0;
      for (final entry in chunkMap.entries) {
        for (int i = 0; i < entry.value.length; i++) {
          final card = entry.value[i];
          final hasStorageUrl = (card['imageUrl'] as String?)?.contains('firebasestorage') == true;
          final hasSourceUrl = (card['image_url'] as String?)?.isNotEmpty == true;
          if (!hasStorageUrl && hasSourceUrl) {
            toUpload.putIfAbsent(entry.key, () => []).add(i);
            totalToUpload++;
          }
        }
      }

      if (totalToUpload == 0) {
        setState(() {
          _status = 'Nessuna immagine da caricare (tutte già presenti su Firebase Storage).';
          _running = false;
          _progress = 1.0;
        });
        return;
      }

      setState(() => _status = 'Trovate $totalToUpload immagini da caricare su Firebase Storage...');

      final affectedChunkIds = <String>{};
      int uploaded = 0;
      int failed = 0;

      // 3. Process in batches of 10 concurrent uploads
      for (final chunkEntry in toUpload.entries) {
        final chunkId = chunkEntry.key;
        final indices = chunkEntry.value;
        final cards = chunkMap[chunkId]!;

        // Process indices in sub-batches of 10
        for (int b = 0; b < indices.length; b += 10) {
          final batchIndices = indices.sublist(b, b + 10 < indices.length ? b + 10 : indices.length);

          await Future.wait(batchIndices.map((idx) async {
            final card = cards[idx];
            final sourceUrl = card['image_url'] as String;
            final cardId = card['id'];

            try {
              final response = await http.get(Uri.parse(sourceUrl))
                  .timeout(const Duration(seconds: 30));
              if (response.statusCode != 200) {
                print('Errore HTTP ${response.statusCode} per carta $cardId');
                failed++;
                return;
              }

              final ref = storage.ref('yugioh/cards/$cardId.jpg');
              await ref.putData(
                response.bodyBytes,
                SettableMetadata(contentType: 'image/jpeg'),
              );
              final downloadUrl = await ref.getDownloadURL();

              cards[idx] = Map<String, dynamic>.from(card)..['imageUrl'] = downloadUrl;
              affectedChunkIds.add(chunkId);
              uploaded++;
            } catch (e) {
              print('Errore upload carta $cardId: $e');
              failed++;
            }
          }));

          setState(() {
            _progress = (uploaded + failed) / totalToUpload;
            _status = 'Caricando immagini: $uploaded/$totalToUpload '
                '${failed > 0 ? '($failed errori)' : ''}';
          });
        }
      }

      // 4. Write only affected chunks (surgical approach)
      if (affectedChunkIds.isNotEmpty) {
        setState(() => _status = 'Aggiornando ${affectedChunkIds.length} chunk su Firestore...');
        for (final chunkId in affectedChunkIds) {
          await firestore
              .collection('yugioh_catalog')
              .doc('chunks')
              .collection('items')
              .doc(chunkId)
              .set({'cards': chunkMap[chunkId]!});
        }

        // 5. Bump metadata version
        final metadataDoc = await firestore.collection('yugioh_catalog').doc('metadata').get();
        final currentVersion = metadataDoc.exists
            ? (metadataDoc.data()?['version'] as int? ?? 0)
            : 0;
        await firestore.collection('yugioh_catalog').doc('metadata').update({
          'version': currentVersion + 1,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }

      setState(() {
        _status = 'Completato! $uploaded immagini caricate su Firebase Storage.'
            '${failed > 0 ? ' $failed errori.' : ''}';
        _progress = 1.0;
        _running = false;
      });
      await _loadCurrentVersion();
    } catch (e) {
      setState(() { _status = 'Errore: $e'; _running = false; });
    }
  }

  /// Compila i set localizzati mancanti su Firestore usando aggiornamenti chirurgici.
  /// NON cancella i chunk esistenti: scrive solo quelli che hanno subito modifiche.
  /// Garantisce che ogni lingua (IT/FR/DE/PT) abbia esattamente lo stesso numero
  /// di set dell'EN per ogni carta.
  Future<void> _runFillMissingSets() async {
    if (_running) return;
    setState(() {
      _running = true;
      _status = 'Leggendo chunks da Firestore...';
      _progress = null;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final chunksSnapshot = await firestore
          .collection('yugioh_catalog')
          .doc('chunks')
          .collection('items')
          .get();

      if (chunksSnapshot.docs.isEmpty) {
        setState(() { _status = 'Catalogo vuoto su Firestore.'; _running = false; });
        return;
      }

      final totalChunks = chunksSnapshot.docs.length;
      int processedChunks = 0;
      int modifiedChunks = 0;
      int modifiedCards = 0;

      for (final doc in chunksSnapshot.docs) {
        processedChunks++;
        setState(() {
          _progress = processedChunks / totalChunks;
          _status = 'Analizzando chunk $processedChunks/$totalChunks'
              '${modifiedChunks > 0 ? ' ($modifiedChunks modificati, $modifiedCards carte)' : ''}...';
        });

        final rawCards = doc.data()['cards'] as List<dynamic>? ?? [];
        bool chunkModified = false;

        final updatedChunkCards = rawCards.map((raw) {
          final card = Map<String, dynamic>.from(raw as Map);
          final updated = _fillMissingSets(card);
          // _fillMissingSets restituisce un nuovo oggetto solo se ha effettuato modifiche
          if (!identical(updated, card)) {
            chunkModified = true;
            modifiedCards++;
          }
          return updated;
        }).toList();

        if (chunkModified) {
          modifiedChunks++;
          await firestore
              .collection('yugioh_catalog')
              .doc('chunks')
              .collection('items')
              .doc(doc.id)
              .set({'cards': updatedChunkCards});
        }
      }

      // Aggiorna metadata solo se qualcosa è cambiato
      if (modifiedChunks > 0) {
        final metadataDoc = await firestore.collection('yugioh_catalog').doc('metadata').get();
        final currentVersion = metadataDoc.exists
            ? (metadataDoc.data()?['version'] as int? ?? 0)
            : 0;
        await firestore.collection('yugioh_catalog').doc('metadata').update({
          'version': currentVersion + 1,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }

      setState(() {
        _status = modifiedChunks == 0
            ? 'Tutti i set sono già completi. Nessuna modifica necessaria.'
            : 'Completato! $modifiedCards carte aggiornate in $modifiedChunks chunk su $totalChunks.';
        _progress = 1.0;
        _running = false;
      });
      await _loadCurrentVersion();
    } catch (e) {
      setState(() { _status = 'Errore: $e'; _running = false; });
    }
  }

  // ─── Set code helpers ─────────────────────────────────────────────────────────

  /// Analizza un codice set nel formato PREFIX-LANGNUM.
  /// Riconosce sia codici a 2 lettere (EN, IT, FR, DE, PT)
  /// sia a singola lettera (E, I, F, D, P).
  /// Restituisce null se il formato non è riconoscibile.
  Map<String, String>? _parseSetCode(String setCode) {
    final match = RegExp(r'^([A-Z0-9]+)-(EN|IT|FR|DE|PT|E|I|F|D|P)(.+)$')
        .firstMatch(setCode.toUpperCase());
    if (match == null) return null;
    return {
      'prefix': match.group(1)!,
      'lang': match.group(2)!,
      'num': match.group(3)!,
    };
  }

  /// Rileva la lingua di appartenenza di un codice set.
  String _detectSetLanguage(String setCode) {
    final parsed = _parseSetCode(setCode);
    if (parsed == null) return 'en'; // es. LOB-001 senza prefisso lingua → EN
    switch (parsed['lang']) {
      case 'IT': case 'I': return 'it';
      case 'FR': case 'F': return 'fr';
      case 'DE': case 'D': return 'de';
      case 'PT': case 'P': return 'pt';
      default: return 'en'; // EN, E
    }
  }

  /// Genera il codice set localizzato per [targetLang] partendo da un set EN.
  /// Mantiene il formato originale (singola o doppia lettera):
  ///   LOB-EN001 → LOB-IT001  (doppia lettera)
  ///   LOB-E001  → LOB-I001   (singola lettera)
  /// Restituisce null se il codice non ha prefisso lingua parsabile.
  String? _generateLocalizedSetCode(String enSetCode, String targetLang) {
    final parsed = _parseSetCode(enSetCode);
    if (parsed == null) return null;

    final isShort = parsed['lang']!.length == 1;
    final String? targetCode = switch (targetLang) {
      'it' => isShort ? 'I' : 'IT',
      'fr' => isShort ? 'F' : 'FR',
      'de' => isShort ? 'D' : 'DE',
      'pt' => isShort ? 'P' : 'PT',
      _ => null,
    };
    if (targetCode == null) return null;

    return '${parsed['prefix']!}-$targetCode${parsed['num']!}';
  }

  /// Per ogni set EN di una carta, garantisce che IT/FR/DE/PT abbiano esattamente
  /// lo stesso numero di set di EN, con i codici localizzati corretti.
  ///
  /// Strategia per ogni lingua:
  ///   1. Costruisce una lookup degli entry esistenti per codice (case-insensitive).
  ///   2. Per ogni set EN, determina il codice target nella lingua (localizzato se
  ///      possibile, altrimenti copia il codice EN).
  ///   3. Cerca l'entry migliore esistente (codice localizzato, poi codice EN sbagliato).
  ///   4. Se trovata, la riutilizza correggendo il codice; se mancante, la genera da EN.
  ///   5. Il risultato finale ha ESATTAMENTE gli stessi set dell'EN.
  bool _generateMissingSetsFromEn(
    Map<String, List<Map<String, dynamic>>> setsByLang,
  ) {
    final enSets = List<Map<String, dynamic>>.from(setsByLang['en'] ?? []);
    if (enSets.isEmpty) return false;

    bool changed = false;

    for (final lang in ['it', 'fr', 'de', 'pt']) {
      // Lookup esistente per codice (case-insensitive) → primo match vince
      final existingByCode = <String, Map<String, dynamic>>{};
      for (final s in List.from(setsByLang[lang]!)) {
        final code = (s['set_code']?.toString() ?? '').toUpperCase();
        if (code.isNotEmpty) existingByCode.putIfAbsent(code, () => s);
      }

      final newList = <Map<String, dynamic>>[];

      for (final enSet in enSets) {
        final enCode = enSet['set_code']?.toString() ?? '';
        final localCode = _generateLocalizedSetCode(enCode, lang);
        // Se il codice non è localizzabile (es. SDK-001), lo usiamo as-is
        final targetCode = localCode ?? enCode;
        final targetUpper = targetCode.toUpperCase();
        final enUpper = enCode.toUpperCase();

        // Preferenza: entry con codice target già corretto, poi entry con codice EN sbagliato
        final existing = existingByCode[targetUpper] ?? existingByCode[enUpper];

        if (existing != null) {
          final existingCode = (existing['set_code']?.toString() ?? '').toUpperCase();
          if (existingCode != targetUpper) {
            // Corregge il codice sbagliato (es. EN code in bucket IT)
            final fixed = Map<String, dynamic>.from(existing)
              ..['set_code'] = targetCode
              ..['print_code'] = targetCode;
            newList.add(fixed);
            changed = true;
          } else {
            newList.add(existing);
          }
        } else {
          // Genera da EN
          newList.add({
            'set_code': targetCode,
            'set_name': enSet['set_name'] ?? '',
            'print_code': targetCode,
            'rarity': enSet['rarity'] ?? '',
            'rarity_code': enSet['rarity_code'] ?? '',
            'set_price': null,
          });
          changed = true;
        }
      }

      // Sostituisce l'intera lista se la lunghezza o i contenuti sono cambiati
      if (newList.length != setsByLang[lang]!.length) changed = true;
      setsByLang[lang] = newList;
    }

    return changed;
  }

  // ─── Migration helper ─────────────────────────────────────────────────────────

  /// Applica la generazione dei set localizzati a una carta già in Firestore.
  /// Gestisce sia il vecchio formato `prints` (lista piatta) che il nuovo `sets`.
  Map<String, dynamic> _fillMissingSets(Map<String, dynamic> card) {
    final rawSets = card['sets'];
    final rawPrints = card['prints'];

    final setsByLang = <String, List<Map<String, dynamic>>>{
      for (final l in _supportedLangs) l: [],
    };

    if (rawSets is Map) {
      // Nuovo formato: legge sets per lingua
      for (final lang in _supportedLangs) {
        final langSets = rawSets[lang];
        if (langSets is List) {
          setsByLang[lang] = langSets
              .map((s) => Map<String, dynamic>.from(s as Map))
              .toList();
        }
      }
    } else if (rawPrints is List) {
      // Vecchio formato: migra prints piatti verso sets per lingua
      for (final p in rawPrints) {
        final setCode = p['set_code']?.toString() ?? '';
        final lang = _detectSetLanguage(setCode);
        if (setsByLang.containsKey(lang)) {
          setsByLang[lang]!.add({
            'set_code': setCode,
            'set_name': p['set_name']?.toString() ?? '',
            'print_code': setCode,
            'rarity': p['rarity']?.toString() ?? '',
            'rarity_code': p['rarity_code']?.toString() ?? '',
            'set_price': p['set_price'],
          });
        }
      }
    }

    // Genera/corregge i set localizzati da EN; traccia se qualcosa è cambiato
    final bool setsChanged = _generateMissingSetsFromEn(setsByLang);
    final bool changed = setsChanged || rawPrints != null;

    if (!changed) return card;

    final setsMap = <String, dynamic>{};
    for (final entry in setsByLang.entries) {
      if (entry.value.isNotEmpty) setsMap[entry.key] = entry.value;
    }

    final updated = Map<String, dynamic>.from(card);
    if (setsMap.isNotEmpty) updated['sets'] = setsMap;
    updated.remove('prints'); // Rimuove il vecchio campo flat
    // Rimuove eventuali riferimenti a 'es' residui
    if (updated['sets'] is Map) {
      (updated['sets'] as Map).remove('es');
    }
    return updated;
  }

  // ─── Download & transform ─────────────────────────────────────────────────────

  /// Scarica le carte da YGOPRODeck per una specifica lingua.
  Future<List<dynamic>> _fetchApiForLang(String lang) async {
    final url = lang == 'en'
        ? ygoprodeckApiUrl
        : '$ygoprodeckApiUrl?language=$lang';
    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(minutes: 5));
    if (response.statusCode != 200) {
      throw Exception('Errore API ($lang): HTTP ${response.statusCode}');
    }
    final data = json.decode(response.body);
    return (data['data'] as List<dynamic>?) ?? [];
  }

  /// Come [_fetchApiForLang] ma non propaga errori: restituisce lista vuota
  /// se l'API non supporta la lingua o è temporaneamente non disponibile.
  Future<List<dynamic>> _fetchApiForLangSafe(String lang) async {
    try {
      return await _fetchApiForLang(lang);
    } catch (e) {
      print('Avviso: traduzioni $lang non disponibili ($e). Continuo senza.');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _downloadFromYGOPRODeck() async {
    // 1. Scarica EN (base)
    setState(() => _status = 'Scaricando catalogo EN da YGOPRODeck...');
    final enCards = await _fetchApiForLang('en');
    setState(() => _status = 'Scaricato EN: ${enCards.length} carte. Scaricando traduzioni...');

    // 2. Scarica le altre lingue in parallelo — errori per singola lingua
    //    non bloccano il download (l'API potrebbe non supportare tutte le lingue).
    final futures = await Future.wait([
      _fetchApiForLangSafe('it'),
      _fetchApiForLangSafe('fr'),
      _fetchApiForLangSafe('de'),
      _fetchApiForLangSafe('pt'),
    ]);
    final itCards = futures[0];
    final frCards = futures[1];
    final deCards = futures[2];
    final ptCards = futures[3];

    setState(() => _status = 'Costruendo mappa traduzioni...');

    // 3. Costruisce mappe id → {name, desc} per ogni lingua
    Map<int, Map<String, String>> buildTranslationMap(List<dynamic> cards) {
      final map = <int, Map<String, String>>{};
      for (final c in cards) {
        final id = c['id'] as int?;
        if (id == null) continue;
        final name = c['name']?.toString() ?? '';
        final desc = c['desc']?.toString() ?? '';
        if (name.isNotEmpty || desc.isNotEmpty) {
          map[id] = {'name': name, 'desc': desc};
        }
      }
      return map;
    }

    final itMap = buildTranslationMap(itCards);
    final frMap = buildTranslationMap(frCards);
    final deMap = buildTranslationMap(deCards);
    final ptMap = buildTranslationMap(ptCards);

    setState(() => _status = 'Processando ${enCards.length} carte con traduzioni...');
    return _transformYGOProDeckCards(enCards, itMap: itMap, frMap: frMap, deMap: deMap, ptMap: ptMap);
  }

  /// Trasforma il formato YGOPRODeck nel formato interno.
  /// Per ogni carta EN:
  ///   1. Raggruppa i set per lingua dal loro codice
  ///   2. Per ogni set EN mancante in IT/FR/DE/PT, genera il codice localizzato
  ///   3. Aggiunge nome e descrizione nelle lingue disponibili
  List<Map<String, dynamic>> _transformYGOProDeckCards(
    List<dynamic> apiCards, {
    Map<int, Map<String, String>> itMap = const {},
    Map<int, Map<String, String>> frMap = const {},
    Map<int, Map<String, String>> deMap = const {},
    Map<int, Map<String, String>> ptMap = const {},
  }) {
    return apiCards.map((card) {
      final cardId = card['id'] as int?;
      final cardSets = card['card_sets'] as List<dynamic>? ?? [];

      final setsByLang = <String, List<Map<String, dynamic>>>{
        for (final l in _supportedLangs) l: [],
      };

      // Raggruppa i set per lingua
      for (final set in cardSets) {
        final setCode = set['set_code']?.toString() ?? '';
        final lang = _detectSetLanguage(setCode);
        if (setsByLang.containsKey(lang)) {
          setsByLang[lang]!.add({
            'set_code': setCode,
            'set_name': set['set_name']?.toString() ?? '',
            'print_code': setCode,
            'rarity': set['set_rarity']?.toString() ?? '',
            'rarity_code': set['set_rarity_code']?.toString() ?? '',
            'set_price': _parseDouble(set['set_price']),
          });
        }
      }

      // Genera set localizzati mancanti da EN
      _generateMissingSetsFromEn(setsByLang);

      // Costruisce la mappa sets (solo lingue non vuote)
      final setsMap = <String, dynamic>{};
      for (final entry in setsByLang.entries) {
        if (entry.value.isNotEmpty) setsMap[entry.key] = entry.value;
      }

      // Recupera traduzioni ufficiali per questo card ID
      final it = cardId != null ? itMap[cardId] : null;
      final fr = cardId != null ? frMap[cardId] : null;
      final de = cardId != null ? deMap[cardId] : null;
      final pt = cardId != null ? ptMap[cardId] : null;

      // YGOPRODeck provides card_images as an array; use the first (largest) image
      final cardImages = card['card_images'] as List<dynamic>?;
      final imageUrl = cardImages != null && cardImages.isNotEmpty
          ? (cardImages[0] as Map<dynamic, dynamic>?)?.cast<String, dynamic>()['image_url'] as String?
          : null;

      return {
        'id': cardId,
        'type': card['type'] ?? '',
        'human_readable_type': card['humanReadableCardType'] ?? card['type'] ?? '',
        'frame_type': card['frameType'] ?? '',
        'race': card['race'] ?? '',
        'archetype': card['archetype'],
        'ygoprodeck_url': 'https://ygoprodeck.com/card/$cardId',
        'image_url': imageUrl,
        'atk': card['atk'],
        'def': card['def'],
        'level': card['level'],
        'attribute': card['attribute'],
        'scale': card['scale'],
        'linkval': card['linkval'],
        'linkmarkers': (card['linkmarkers'] as List<dynamic>?)?.join(','),
        'name': card['name'] ?? '',
        'description': card['desc'] ?? '',
        // Traduzioni ufficiali da API localizzate
        if (it?['name'] != null && it!['name']!.isNotEmpty) 'name_it': it['name'],
        if (it?['desc'] != null && it!['desc']!.isNotEmpty) 'description_it': it['desc'],
        if (fr?['name'] != null && fr!['name']!.isNotEmpty) 'name_fr': fr['name'],
        if (fr?['desc'] != null && fr!['desc']!.isNotEmpty) 'description_fr': fr['desc'],
        if (de?['name'] != null && de!['name']!.isNotEmpty) 'name_de': de['name'],
        if (de?['desc'] != null && de!['desc']!.isNotEmpty) 'description_de': de['desc'],
        if (pt?['name'] != null && pt!['name']!.isNotEmpty) 'name_pt': pt['name'],
        if (pt?['desc'] != null && pt!['desc']!.isNotEmpty) 'description_pt': pt['desc'],
        if (setsMap.isNotEmpty) 'sets': setsMap,
      };
    }).toList();
  }

  // ─── Firestore helpers ────────────────────────────────────────────────────────

  Future<Set<int>> _getExistingCardIds() async {
    final Set<int> ids = {};
    final chunksSnapshot = await FirebaseFirestore.instance
        .collection('yugioh_catalog')
        .doc('chunks')
        .collection('items')
        .get();

    for (var doc in chunksSnapshot.docs) {
      final cards = doc.data()['cards'] as List<dynamic>? ?? [];
      for (var card in cards) {
        final id = card['id'];
        if (id != null) ids.add((id as num).toInt());
      }
    }
    return ids;
  }

  Future<void> _uploadToFirestore(
    List<Map<String, dynamic>> cards, {
    required bool isIncremental,
  }) async {
    final firestore = FirebaseFirestore.instance;

    if (!isIncremental) {
      setState(() => _status = 'Cancellando chunks esistenti...');
      final chunksSnapshot = await firestore
          .collection('yugioh_catalog')
          .doc('chunks')
          .collection('items')
          .get();
      for (var doc in chunksSnapshot.docs) {
        await doc.reference.delete();
      }
    }

    final chunks = <List<Map<String, dynamic>>>[];
    for (int i = 0; i < cards.length; i += chunkSize) {
      final end = (i + chunkSize < cards.length) ? i + chunkSize : cards.length;
      chunks.add(cards.sublist(i, end));
    }

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

    final newVersion = _currentVersion + 1;
    await firestore.collection('yugioh_catalog').doc('metadata').set({
      'totalCards': isIncremental ? _totalCards + cards.length : cards.length,
      'totalChunks': chunks.length,
      'chunkSize': chunkSize,
      'lastUpdated': FieldValue.serverTimestamp(),
      'version': newVersion,
    });
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  // ─── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_download, size: 64, color: Colors.blue),
            const SizedBox(height: 20),
            const Text(
              'YGOPRODeck → Firestore',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Versione corrente: $_currentVersion | Carte: $_totalCards',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 30),
            if (_progress != null) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 10),
            ],
            if (_running && _progress == null) const CircularProgressIndicator(),
            const SizedBox(height: 10),
            Text(_status, textAlign: TextAlign.center),
            const SizedBox(height: 30),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _running ? null : _runFullDownload,
                  icon: const Icon(Icons.download),
                  label: const Text('Download Completo'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _running ? null : _runIncrementalUpdate,
                  icon: const Icon(Icons.update),
                  label: const Text('Aggiorna Solo Nuove'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _running ? null : _runFillMissingSets,
                  icon: const Icon(Icons.language),
                  label: const Text('Riempi Set Mancanti'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _running ? null : _runUploadImages,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Carica Immagini'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            const Divider(),
            const SizedBox(height: 20),
            const Text('Info:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text(
              '• Download Completo: Scarica tutto il catalogo da YGOPRODeck (~13.000 carte)\n'
              '  Le carte modificate dall\'admin (flag _adminModified) vengono preservate.\n'
              '• Aggiorna Solo Nuove: Aggiunge solo le carte mancanti (incrementale)\n'
              '• Riempi Set Mancanti: Genera i set localizzati mancanti sul catalogo Firestore\n'
              '• Carica Immagini: Carica le immagini su Firebase Storage (yugioh/cards/{id}.jpg)\n'
              '  Solo le immagini mancanti vengono caricate. Salva il download URL in Firestore.\n\n'
              'Generazione automatica set per lingua:\n'
              '  LOB-EN001 → LOB-IT001, LOB-FR001, LOB-DE001, LOB-PT001\n'
              '  LOB-E001  → LOB-I001,  LOB-F001,  LOB-D001,  LOB-P001\n'
              'I set nativi non vengono sovrascritti.\n'
              'Lingue: EN, IT, FR, DE, PT (spagnolo escluso).',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
