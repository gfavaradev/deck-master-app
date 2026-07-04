import '../l10n/app_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/admin_catalog_service.dart';
import '../services/admin_translation_service.dart';
import '../services/background_download_service.dart';
import '../services/cardtrader_service.dart';
import '../services/database_helper.dart';
import '../services/subscription_service.dart';
import '../models/user_model.dart';
import '../theme/app_colors.dart';
import '../utils/cancellation_token.dart';
import 'admin_collection_page.dart';
import 'admin_excel_page.dart';
import 'admin_news_page.dart';
import 'admin_sets_rarities_page.dart';

/// Body riutilizzabile con la lista dei cataloghi da gestire
class AdminCatalogBody extends StatefulWidget {
  const AdminCatalogBody({super.key});

  @override
  State<AdminCatalogBody> createState() => _AdminCatalogBodyState();
}

class _AdminCatalogBodyState extends State<AdminCatalogBody> {
  final AdminCatalogService _service = AdminCatalogService();
  final AdminTranslationService _translationService = AdminTranslationService();
  final CardtraderService _cardtraderService = CardtraderService();
  final DatabaseHelper _db = DatabaseHelper();
  bool _isRunning = false;
  double? _progress;
  String _statusText = '';
  String _currentOp = '';
  Future<List<Map<String, dynamic>>>? _coverageStatsFuture;
  CancellationToken? _cancelToken;

  // ─── Operations ───────────────────────────────────────────────────────────

  Future<void> _run(
    String collectionKey,
    String opLabel,
    Future<Map<String, dynamic>> Function(String uid) task,
    String Function(Map<String, dynamic> result) successMessage,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.adminHomeSessions),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    final token = CancellationToken();
    setState(() {
      _isRunning = true;
      _progress = null;
      _statusText = '';
      _currentOp = opLabel;
      _cancelToken = token;
    });

    try {
      // Avvia la notifica di progresso: mantiene il processo vivo in background
      await BackgroundDownloadService.startDownload(opLabel);
      await WakelockPlus.enable();

      final result = await task(uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage(result)),
          duration: const Duration(seconds: 5),
        ),
      );
    } on CancelledException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.adminHomeOperationCancelled),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Errore: $_currentOp'),
            content: SingleChildScrollView(
              child: SelectableText(
                e.toString(),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Chiudi'),
              ),
            ],
          ),
        );
      }
    } finally {
      // Ferma il foreground service al termine (successo, errore o annullamento)
      await BackgroundDownloadService.stopDownload();
      WakelockPlus.disable();
      if (mounted) setState(() { _isRunning = false; _cancelToken = null; });
    }
  }

  Future<void> _confirmAndRun(
    String collectionKey,
    String opLabel,
    String confirmTitle,
    String confirmBody,
    Future<Map<String, dynamic>> Function(String uid) task,
    String Function(Map<String, dynamic>) successMessage,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(confirmTitle),
        content: Text(confirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Avvia'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(collectionKey, opLabel, task, successMessage);
  }

  void _onProgress(String status, double? progress) {
    // Controlla il token prima di aggiornare — se annullato interrompe l'operazione.
    if (_cancelToken?.isCancelled ?? false) throw const CancelledException();
    if (mounted) setState(() { _statusText = status; _progress = progress; });
    BackgroundDownloadService.updateStatus(status);
  }

  // ─── Yu-Gi-Oh! action handlers ────────────────────────────────────────────

  Future<void> _downloadFull() => _confirmAndRun(
        'yugioh',
        'Download Completo',
        'Download Completo Catalogo',
        'Scarica l\'intero catalogo Yu-Gi-Oh! da YGOPRODeck API e '
            'sostituisce tutti i chunk su Firestore.\n\n'
            'Le carte modificate manualmente vengono preservate.\n\n'
            'Può richiedere diversi minuti. Continuare?',
        (uid) => _service.downloadFullCatalogFromAPI(
          adminUid: uid,
          onProgress: _onProgress,
        ),
        (r) => 'Completato! ${r['totalCards']} carte caricate'
            '${(r['preservedAdminCards'] as int? ?? 0) > 0 ? " (${r['preservedAdminCards']} preservate)" : ""}.',
      );

  Future<void> _downloadIncremental() => _confirmAndRun(
        'yugioh',
        'Aggiornamento Incrementale',
        'Aggiorna Nuove Carte',
        'Aggiunge solo le carte nuove presenti su YGOPRODeck '
            'che non sono ancora nel catalogo Firestore.\n\n'
            'Le carte esistenti non vengono modificate. Continuare?',
        (uid) => _service.downloadIncrementalCatalog(
          adminUid: uid,
          onProgress: _onProgress,
        ),
        _incrementalResultMessage,
      );

  String _incrementalResultMessage(Map<String, dynamic> r) {
    final n = r['newCards'] as int? ?? 0;
    if (n == 0) return 'Nessuna carta nuova trovata.';
    final ok = r['imagesOk'] as int? ?? 0;
    final fail = r['imagesFail'] as int? ?? 0;
    final imgNote = ok > 0 ? ' — immagini: $ok ok${fail > 0 ? ", $fail fallite" : ""}' : '';
    return '$n carte nuove aggiunte$imgNote.';
  }

  String _migrationResultMessage(Map<String, dynamic> r) {
    final migrated = r['migrated'] as int? ?? 0;
    final failed = r['failed'] as int? ?? 0;
    final chunks = r['chunksUpdated'] as int? ?? 0;
    final verified = r['verified'] as int?;
    final verifiedOf = r['verifiedOf'] as int? ?? 0;
    final diagMsg = r['diagMsg'] as String?;

    if (migrated == 0 && failed == 0) {
      return diagMsg != null
          ? 'Nessuna immagine da migrare.\nDiagnostica: $diagMsg'
          : 'Nessuna immagine da migrare.';
    }

    final verifyNote = (verified != null && verifiedOf > 0)
        ? '\nVerifica: $verified/$verifiedOf URL raggiungibili su Backblaze'
        : '';
    return '$migrated migrate, $failed errori, $chunks chunk aggiornati.$verifyNote';
  }

  Future<void> _migrateImages() => _confirmAndRun(
        'yugioh',
        'Migrazione Immagini',
        'Migrazione Immagini',
        'Migra le immagini delle carte da ygoprodeck.com a Backblaze B2.\n\n'
            'Solo le immagini non ancora migrate vengono scaricate. '
            'Può richiedere diversi minuti. Continuare?',
        (uid) => _service.migrateAllImagesToStorage(
          catalog: 'yugioh',
          adminUid: uid,
          onProgress: (cur, tot) =>
              _onProgress('$cur / $tot immagini', tot > 0 ? cur / tot : null),
        ),
        _migrationResultMessage,
      );

  Future<void> _translateMissingYugioh() => _confirmAndRun(
        'yugioh',
        'Traduci Carte YGO',
        'Scarica Traduzioni Ufficiali',
        'Scarica i nomi e le descrizioni ufficiali in IT, FR, DE, PT, SP '
            'dal database YGOPRODeck (Konami/Neuron) per tutte le carte '
            'con campi mancanti.\n\n'
            'Può richiedere diversi minuti. Continuare?',
        (uid) => _translationService.translateMissingTranslations(
          catalog: 'yugioh',
          adminUid: uid,
          onProgress: _onProgress,
        ),
        (r) => (r['translated'] as int? ?? 0) == 0
            ? 'Nessuna traduzione mancante trovata.'
            : '${r['translated']} carte aggiornate in ${r['modifiedChunks']} chunk'
                '${(r['errors'] as int? ?? 0) > 0 ? " (${r['errors']} errori)" : ""}.',
      );

  Future<void> _fillMissingSetsYugioh() => _confirmAndRun(
        'yugioh',
        'Genera Set Mancanti YGO',
        'Genera Set Localizzati Yu-Gi-Oh!',
        'Genera automaticamente i set in IT/FR/DE/PT per tutte le carte '
            'che hanno solo i set EN.\n\n'
            'I set già presenti non vengono sovrascritti. Continuare?',
        (uid) => _service.fillMissingLocalizedSets(
          catalog: 'yugioh',
          adminUid: uid,
          onProgress: _onProgress,
        ),
        (r) => (r['modifiedCards'] as int? ?? 0) == 0
            ? 'Nessun set mancante trovato.'
            : '${r['modifiedCards']} carte aggiornate in ${r['modifiedChunks']} chunk.',
      );

  // ─── CardTrader-based catalog download (Pokemon & One Piece) ─────────────

  Future<void> _downloadFromCardtrader(String catalog) => _confirmAndRun(
        catalog,
        'Aggiorna Catalogo da CardTrader',
        'Aggiorna Catalogo da CardTrader',
        'Sincronizza il catalogo $catalog da CardTrader (blueprint + metadati).\n\n'
            'Solo le carte nuove o incomplete vengono elaborate; quelle già '
            'complete (seriale ufficiale reale + immagine su Backblaze) vengono '
            'saltate. Le immagini vengono caricate immediatamente su Backblaze B2. '
            'Se CardTrader non espone il seriale ufficiale di una carta, viene '
            'recuperato dall\'API ufficiale del gioco; se non si trova in nessuna '
            'fonte la carta viene scartata (mai salvata con un id CardTrader fittizio).\n\n'
            'Può richiedere diversi minuti. Continuare?',
        (uid) => _service.downloadCatalogFromCardtrader(
          catalog: catalog,
          adminUid: uid,
          onProgress: _onProgress,
        ),
        _cardtraderSyncResultMessage,
      );

  String _cardtraderSyncResultMessage(Map<String, dynamic> r) {
    final newCards = r['newCards'] as int? ?? 0;
    final updated = r['updatedCards'] as int? ?? 0;
    final skippedExisting = r['skippedExisting'] as int? ?? 0;
    final discarded = r['discarded'] as int? ?? 0;
    if (newCards == 0 && updated == 0) {
      return 'Catalogo già aggiornato: nessuna carta nuova o incompleta trovata'
          '${skippedExisting > 0 ? " ($skippedExisting già complete)" : ""}.'
          '${discarded > 0 ? "\n$discarded carte scartate (nessun seriale ufficiale risolvibile)." : ""}';
    }
    return '$newCards carte nuove, $updated aggiornate'
        '${skippedExisting > 0 ? ", $skippedExisting già complete (saltate)" : ""}.'
        '${discarded > 0 ? "\n$discarded carte scartate (nessun seriale ufficiale risolvibile)." : ""}';
  }

  Future<void> _repairDirtySerials(String catalog, {required bool dryRun}) => _confirmAndRun(
        catalog,
        dryRun ? 'Anteprima Riparazione Seriali' : 'Riparazione Seriali Sporchi',
        dryRun ? 'Anteprima Riparazione Seriali' : 'Ripara Seriali Sporchi',
        dryRun
            ? 'Analizza il catalogo $catalog cercando carte con un seriale '
                'CardTrader fittizio (eredità di sync precedenti) e mostra quante '
                'potrebbero essere riparate, SENZA scrivere nulla su Firestore.\n\n'
                'Continuare?'
            : 'Cerca nel catalogo $catalog le carte con un seriale CardTrader '
                'fittizio (eredità di sync precedenti) e le ri-risolve tramite '
                'l\'API ufficiale del gioco, aggiornando seriale e immagine.\n\n'
                'Le carte non risolvibili NON vengono cancellate, solo segnalate '
                'per revisione manuale.\n\n'
                'Può richiedere diversi minuti. Continuare?',
        (uid) => _service.repairDirtySerials(
          catalog: catalog,
          adminUid: uid,
          onProgress: (cur, tot) =>
              _onProgress('$cur / $tot carte analizzate', tot > 0 ? cur / tot : null),
          dryRun: dryRun,
        ),
        _repairResultMessage,
      );

  String _repairResultMessage(Map<String, dynamic> r) {
    final dryRun = r['dryRun'] as bool? ?? false;
    final repaired = dryRun ? (r['wouldRepair'] as int? ?? 0) : (r['repaired'] as int? ?? 0);
    final unresolved = r['unresolved'] as int? ?? 0;
    final chunks = r['chunksUpdated'] as int? ?? 0;
    final sample = (r['unresolvedSample'] as List?)?.cast<String>() ?? const [];
    final unresolvedNote = unresolved > 0
        ? '\n$unresolved non risolte${sample.isNotEmpty ? ":\n${sample.take(5).join('\n')}" : ""}'
        : '';
    if (dryRun) {
      return '$repaired carte riparabili trovate.$unresolvedNote';
    }
    return '$repaired carte riparate, $chunks chunk aggiornati.$unresolvedNote';
  }

  // ─── One Piece action handlers ─────────────────────────────────────────────

  Future<void> _downloadIncrementalOnePiece() => _confirmAndRun(
        'onepiece',
        'Aggiornamento Incrementale One Piece',
        'Aggiorna Nuove Carte One Piece',
        'Aggiunge solo le carte One Piece nuove presenti sull\'OPTCG API '
            'che non sono ancora nel catalogo Firestore.\n\n'
            'Le carte esistenti e tutti i dati di prezzo vengono preservati. Continuare?',
        (uid) => _service.downloadIncrementalOnepieceCatalog(
          adminUid: uid,
          onProgress: _onProgress,
        ),
        _incrementalResultMessage,
      );

  Future<void> _downloadFullOnePiece() => _confirmAndRun(
        'onepiece',
        'Download Completo One Piece',
        'Download Completo One Piece TCG',
        'Scarica l\'intero catalogo One Piece TCG da OPTCG API, '
            'carica le immagini su Backblaze B2 e salva tutto su Firestore.\n\n'
            'Le immagini già su Backblaze B2 vengono preservate.\n\n'
            'Può richiedere diversi minuti. Continuare?',
        (uid) => _service.downloadOnepieceCatalogFromAPI(
          adminUid: uid,
          onProgress: _onProgress,
        ),
        (r) => 'Completato! ${r['totalCards']} carte, ${r['totalPrints']} stampe.',
      );

  Future<void> _migrateOnePieceImages() => _confirmAndRun(
        'onepiece',
        'Migrazione Immagini One Piece',
        'Migrazione Immagini One Piece',
        'Scarica le immagini delle carte One Piece dall\'OPTCG API '
            'e le carica su Backblaze B2.\n\n'
            'Solo le immagini non ancora migrate vengono scaricate. '
            'Può richiedere diversi minuti. Continuare?',
        (uid) => _service.migrateOnepieceImagesToStorage(
          adminUid: uid,
          onProgress: (cur, tot) =>
              _onProgress('$cur / $tot immagini', tot > 0 ? cur / tot : null),
        ),
        _migrationResultMessage,
      );

  // ─── Magic: The Gathering action handlers ─────────────────────────────────

  Future<void> _downloadFullMagic() => _confirmAndRun(
        'magic',
        'Download Completo Magic',
        'Download Catalogo Magic: The Gathering',
        'Scarica l\'intero catalogo Magic: The Gathering da Scryfall (oracle_cards bulk) '
            'e sostituisce tutti i chunk su Firestore.\n\n'
            'Il download è ~100 MB e può richiedere diversi minuti. Continuare?',
        (uid) => _service.downloadMagicCatalogFromAPI(
          adminUid: uid,
          onProgress: _onProgress,
        ),
        (r) => 'Completato! ${r['totalCards']} carte caricate.',
      );

  Future<void> _downloadIncrementalMagic() => _confirmAndRun(
        'magic',
        'Aggiornamento Incrementale Magic',
        'Aggiorna Nuove Carte Magic',
        'Aggiunge solo le carte Magic nuove o modificate rispetto all\'ultimo '
            'download da Scryfall.\n\n'
            'Le carte esistenti non vengono modificate. Continuare?',
        (uid) => _service.downloadIncrementalMagicCatalog(
          adminUid: uid,
          onProgress: _onProgress,
        ),
        _incrementalResultMessage,
      );

  Future<void> _migrateMagicImages() => _confirmAndRun(
        'magic',
        'Migrazione Immagini Magic',
        'Migrazione Immagini Magic: The Gathering',
        'Carica le immagini Magic da Scryfall su Backblaze.\n\n'
            'Solo le immagini non ancora migrate vengono caricate. '
            'Può richiedere diversi minuti. Continuare?',
        (uid) => _service.migrateMagicImagesToStorage(
          adminUid: uid,
          onProgress: (cur, tot) =>
              _onProgress('$cur / $tot immagini', tot > 0 ? cur / tot : null),
        ),
        _migrationResultMessage,
      );

  Future<void> _fillMissingSetsMagic() => _confirmAndRun(
        'magic',
        'Genera Set Mancanti Magic',
        'Genera Set Localizzati Magic',
        'Genera automaticamente i set nelle lingue mancanti per tutte le carte '
            'Magic che hanno solo i set base.\n\n'
            'I set già presenti non vengono sovrascritti. Continuare?',
        (uid) => _service.fillMissingLocalizedSets(
          catalog: 'magic',
          adminUid: uid,
          onProgress: _onProgress,
        ),
        (r) => (r['modifiedCards'] as int? ?? 0) == 0
            ? 'Nessun set mancante trovato.'
            : '${r['modifiedCards']} carte aggiornate in ${r['modifiedChunks']} chunk.',
      );

  // ─── Pokémon action handlers ──────────────────────────────────────────────

  Future<void> _downloadIncrementalPokemon() => _confirmAndRun(
        'pokemon',
        'Aggiornamento Incrementale Pokémon',
        'Aggiorna Nuove Carte Pokémon',
        'Aggiunge solo le carte Pokémon nuove presenti su pokemontcg.io '
            'che non sono ancora nel catalogo Firestore.\n\n'
            'Le carte esistenti e tutti i dati di prezzo vengono preservati. Continuare?',
        (uid) => _service.downloadIncrementalPokemonCatalog(
          adminUid: uid,
          onProgress: _onProgress,
        ),
        _incrementalResultMessage,
      );

  Future<void> _downloadFullPokemon() => _confirmAndRun(
        'pokemon',
        'Download Completo Pokémon',
        'Download Catalogo Pokémon TCG',
        'Scarica l\'intero catalogo Pokémon TCG da pokemontcg.io e '
            'sostituisce tutti i chunk su Firestore.\n\n'
            'Le URL immagini già su Backblaze B2 vengono preservate.\n\n'
            'Può richiedere diversi minuti. Continuare?',
        (uid) => _service.downloadPokemonCatalogFromAPI(
          adminUid: uid,
          onProgress: _onProgress,
        ),
        (r) => 'Completato! ${r['totalCards']} carte caricate.',
      );

  Future<void> _migratePokemonImages() => _confirmAndRun(
        'pokemon',
        'Migrazione Immagini Pokémon',
        'Migrazione Immagini Pokémon',
        'Scarica le immagini Pokémon da pokemontcg.io e le carica su Backblaze B2 '
            'con compressione JPEG.\n\n'
            'Solo le immagini non ancora migrate vengono scaricate. '
            'Può richiedere diversi minuti. Continuare?',
        (uid) => _service.migratePokemonImagesToStorage(
          adminUid: uid,
          onProgress: (cur, tot) =>
              _onProgress('$cur / $tot immagini', tot > 0 ? cur / tot : null),
        ),
        _migrationResultMessage,
      );

  Future<void> _fillMissingSetsOnePiece() => _confirmAndRun(
        'onepiece',
        'Genera Set Mancanti One Piece',
        'Genera Set Localizzati One Piece',
        'Genera automaticamente i set nelle lingue mancanti per tutte le carte '
            'One Piece che hanno solo i set base.\n\n'
            'I set già presenti non vengono sovrascritti. Continuare?',
        (uid) => _service.fillMissingLocalizedSets(
          catalog: 'onepiece',
          adminUid: uid,
          onProgress: _onProgress,
        ),
        (r) => (r['modifiedCards'] as int? ?? 0) == 0
            ? 'Nessun set mancante trovato.'
            : '${r['modifiedCards']} carte aggiornate in ${r['modifiedChunks']} chunk.',
      );

  Future<void> _fillMissingSetsPokemon() => _confirmAndRun(
        'pokemon',
        'Genera Set Mancanti Pokémon',
        'Genera Set Localizzati Pokémon',
        'Genera automaticamente i set nelle lingue mancanti per tutte le carte '
            'Pokémon che hanno solo i set base.\n\n'
            'I set già presenti non vengono sovrascritti. Continuare?',
        (uid) => _service.fillMissingLocalizedSets(
          catalog: 'pokemon',
          adminUid: uid,
          onProgress: _onProgress,
        ),
        (r) => (r['modifiedCards'] as int? ?? 0) == 0
            ? 'Nessun set mancante trovato.'
            : '${r['modifiedCards']} carte aggiornate in ${r['modifiedChunks']} chunk.',
      );

  // ─── CardTrader sync handlers ──────────────────────────────────────────────

  /// Mostra una dialog di conferma e avvia il sync CT per [catalog].
  /// Il sync scarica prezzi per TUTTE le lingue in un'unica passata.
  Future<void> _syncCardtraderWithLanguagePicker(String catalog) async {
    final displayName = _catalogDisplayName(catalog);
    await _confirmAndRun(
      catalog,
      'Sync Prezzi CardTrader — $displayName',
      'Sincronizza Prezzi',
      'Verranno scaricati tutti i blueprint e i prezzi per ogni lingua '
          'disponibile su CardTrader ($displayName).\n\n'
          'Può richiedere diversi minuti. Continuare?',
      (uid) => _cardtraderService.syncPrices(
        catalog: catalog,
        adminUid: uid,
        onProgress: _onProgress,
      ),
      (r) {
        final total = r['blueprints'] as int? ?? 0;
        final priced = r['pricedBlueprints'] as int? ?? 0;
        final exps = r['expansions'] as int? ?? 0;
        final ctTotal = r['ctExpansionsTotal'] as int? ?? 0;
        final localSets = r['localSets'] as int? ?? 0;
        final err = r['errors'] as int? ?? 0;
        // Refresh coverage stats after sync completes (mobile only — SQLite required)
        if (mounted && !kIsWeb) setState(() { _coverageStatsFuture = _db.getCardtraderCoverageStats(); });
        return '$total blueprint in $exps/$ctTotal espansioni CT (set locali: $localSets)'
            ' · $priced con prezzo · ${r['valuesUpdated'] ?? 0} carte'
            ' · ${r['catalogUpdated'] ?? 0} catalogo'
            '${err > 0 ? " ($err errori)" : ""}.';
      },
    );
  }

  static String _catalogDisplayName(String catalog) => switch (catalog) {
        'yugioh'           => 'Yu-Gi-Oh!',
        'pokemon'          => 'Pokémon',
        'onepiece'         => 'One Piece',
        'magic'            => 'Magic: The Gathering',
        'digimon'          => 'Digimon',
        'lorcana'          => 'Disney Lorcana',
        'flesh-and-blood'  => 'Flesh and Blood',
        'vanguard'         => 'Cardfight!! Vanguard',
        'dragon-ball-super'=> 'Dragon Ball Super',
        'star-wars'        => 'Star Wars: Unlimited',
        'riftbound'        => 'Riftbound',
        'gundam'           => 'Gundam Card Game',
        'union-arena'      => 'Union Arena',
        _                  => catalog,
      };

  Future<void> _syncCardtraderYugioh() =>
      _syncCardtraderWithLanguagePicker('yugioh');

  Future<void> _syncCardtraderPokemon() =>
      _syncCardtraderWithLanguagePicker('pokemon');

  Future<void> _syncCardtraderOnePiece() =>
      _syncCardtraderWithLanguagePicker('onepiece');

  Future<void> _syncCT(String catalog) =>
      _syncCardtraderWithLanguagePicker(catalog);

  // ─── Nuove collezioni ────────────────────────────────────────────────────

  Future<void> _downloadFullDigimon() => _run(
        'digimon',
        'Download Digimon Catalog',
        (uid) => _service.downloadDigimonCatalogFromAPI(
          adminUid: uid,
          onProgress: _onProgress,
        ),
        (r) => '${r['totalCards']} carte Digimon caricate su Firestore.',
      );

  Future<void> _downloadFullLorcana() => _run(
        'lorcana',
        'Download Disney Lorcana Catalog',
        (uid) => _service.downloadLorcanaCatalogFromAPI(
          adminUid: uid,
          onProgress: _onProgress,
        ),
        (r) => '${r['totalCards']} carte Lorcana caricate su Firestore.',
      );

  Future<void> _downloadFullFab() => _downloadGenericFromCT('flesh-and-blood');

  /// Migrazione immagini generica per Digimon, Lorcana, FAB e tutte le collezioni CT.
  Future<void> _migrateGenericImages(String catalogKey) => _confirmAndRun(
        catalogKey,
        'Migrazione Immagini ${_catalogDisplayName(catalogKey)}',
        'Migra Immagini ${_catalogDisplayName(catalogKey)}',
        'Carica le immagini di ${_catalogDisplayName(catalogKey)} su Backblaze B2.\n\n'
            'Solo le immagini non ancora migrate vengono elaborate. '
            'Può richiedere diversi minuti. Continuare?',
        (uid) => _service.migrateGenericCatalogImages(
          catalogKey: catalogKey,
          adminUid: uid,
          onProgress: (cur, tot) =>
              _onProgress('$cur / $tot immagini', tot > 0 ? cur / tot : null),
        ),
        _migrationResultMessage,
      );

  Future<void> _downloadGenericFromCT(String catalogKey) => _run(
        catalogKey,
        'Aggiorna ${_catalogDisplayName(catalogKey)} (CardTrader)',
        (uid) => _service.downloadCardtraderGenericCatalog(
          catalogKey: catalogKey,
          adminUid: uid,
          onProgress: _onProgress,
        ),
        (r) {
          final newCards = r['newCards'] as int? ?? 0;
          final updated = r['updatedCards'] as int? ?? 0;
          final discarded = r['discarded'] as int? ?? 0;
          return '$newCards carte nuove, $updated aggiornate'
              '${discarded > 0 ? "\n$discarded scartate (nessun numero ufficiale CT)" : ""}.';
        },
      );


  // ─── UI ───────────────────────────────────────────────────────────────────

  static final _catalogs = [
    _CatalogDef(key: 'yugioh',           name: 'Yu-Gi-Oh!',               icon: Icons.auto_awesome,         color: Color(0xFF7B1FA2)),
    _CatalogDef(key: 'onepiece',         name: 'One Piece TCG',            icon: Icons.sailing,              color: Color(0xFFD32F2F)),
    _CatalogDef(key: 'pokemon',          name: 'Pokémon TCG',              icon: Icons.catching_pokemon,     color: Color(0xFFF57C00)),
    _CatalogDef(key: 'magic',            name: 'Magic: The Gathering',     icon: Icons.diamond_outlined,     color: Color(0xFF7B5EA7)),
    _CatalogDef(key: 'digimon',          name: 'Digimon',                  icon: Icons.pets,                 color: Color(0xFF0288D1)),
    _CatalogDef(key: 'lorcana',          name: 'Disney Lorcana',           icon: Icons.auto_stories,         color: Color(0xFF0097A7)),
    _CatalogDef(key: 'flesh-and-blood',  name: 'Flesh and Blood',          icon: Icons.sports_martial_arts,  color: Color(0xFF880E4F)),
    _CatalogDef(key: 'vanguard',         name: 'Cardfight!! Vanguard',     icon: Icons.shield,               color: Color(0xFF1565C0)),
    _CatalogDef(key: 'dragon-ball-super',name: 'Dragon Ball Super',        icon: Icons.bolt,                 color: Color(0xFFFF6F00)),
    _CatalogDef(key: 'star-wars',        name: 'Star Wars: Unlimited',     icon: Icons.rocket_launch,        color: Color(0xFF212121)),
    _CatalogDef(key: 'riftbound',        name: 'Riftbound',                icon: Icons.casino,               color: Color(0xFF4A148C)),
    _CatalogDef(key: 'gundam',           name: 'Gundam Card Game',         icon: Icons.smart_toy,            color: Color(0xFF37474F)),
    _CatalogDef(key: 'union-arena',      name: 'Union Arena',              icon: Icons.people,               color: Color(0xFF2E7D32)),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Global progress bar (shown while any operation runs)
        if (_isRunning) _buildGlobalProgress(),
        if (_isRunning) const SizedBox(height: 12),

        // Per-collection stepper cards
        for (final cat in _catalogs) ...[
          _buildCollectionCard(cat),
          const SizedBox(height: 12),
        ],

        // CardTrader prices
        _buildCardtraderSyncCard(),
        const SizedBox(height: 12),

        // Espansioni & Rarità
        _buildSetsRaritiesCard(context),
        const SizedBox(height: 12),

        // Gestione News
        _buildNewsManagementCard(context),
        const SizedBox(height: 12),

        // Pro management
        _buildProManagementCard(context),
      ],
    );
  }

  Widget _buildGlobalProgress() {
    final alreadyCancelled = _cancelToken?.isCancelled ?? false;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: alreadyCancelled
              ? Colors.orange.withValues(alpha: 0.5)
              : AppColors.blue.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: alreadyCancelled ? Colors.orange : AppColors.blue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(
                alreadyCancelled ? 'Annullamento in corso...' : _currentOp,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: alreadyCancelled ? Colors.orange : AppColors.textPrimary,
                ),
              )),
              // Bottone Annulla — si disabilita dopo il primo tap
              TextButton.icon(
                onPressed: alreadyCancelled
                    ? null
                    : () => setState(() => _cancelToken?.cancel()),
                icon: Icon(
                  Icons.stop_circle_outlined,
                  size: 16,
                  color: alreadyCancelled ? AppColors.textHint : Colors.orange,
                ),
                label: Text(
                  alreadyCancelled ? 'Annullamento…' : 'Annulla',
                  style: TextStyle(
                    color: alreadyCancelled ? AppColors.textHint : Colors.orange,
                    fontSize: 12,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _progress,
            backgroundColor: AppColors.bgDark,
            valueColor: AlwaysStoppedAnimation(
              alreadyCancelled ? Colors.orange : AppColors.blue,
            ),
            minHeight: 3,
          ),
          if (_statusText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(_statusText, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }

  Widget _buildCollectionCard(_CatalogDef cat) {
    final steps = _stepsFor(cat);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cat.color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: cat.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(cat.icon, color: cat.color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  cat.name,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: cat.color),
                )),
                // Gestisci Carte shortcut
                TextButton.icon(
                  onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => AdminCollectionPage(
                      collectionKey: cat.key,
                      collectionName: cat.name,
                    ))),
                  icon: Icon(Icons.style, size: 14, color: cat.color),
                  label: Text('Carte', style: TextStyle(fontSize: 12, color: cat.color)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                // Espansioni & Rarità shortcut
                TextButton.icon(
                  onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => AdminSetsRaritiesPage(initialCollection: cat.key))),
                  icon: Icon(Icons.list_alt, size: 14, color: cat.color),
                  label: Text('Set/Rarità', style: TextStyle(fontSize: 12, color: cat.color)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                // Excel export/import shortcut
                Tooltip(
                  message: 'Esporta / Importa Excel',
                  child: IconButton(
                    onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => AdminExcelPage(initialCollection: cat.key))),
                    icon: Icon(Icons.table_chart, size: 17, color: cat.color),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 0.5, color: AppColors.divider),
          // Steps
          ...steps.asMap().entries.map((entry) {
            final i = entry.key;
            final step = entry.value;
            return _buildStepRow(i + 1, step, cat.color, isLast: i == steps.length - 1);
          }),
        ],
      ),
    );
  }

  Widget _buildStepRow(int n, _StepDef step, Color accent, {required bool isLast}) {
    final disabled = _isRunning || step.onTap == null;
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: disabled ? null : step.onTap,
            borderRadius: isLast
                ? const BorderRadius.vertical(bottom: Radius.circular(16))
                : BorderRadius.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                children: [
                  Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: disabled
                          ? AppColors.bgLight
                          : accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: disabled ? AppColors.border : accent.withValues(alpha: 0.6)),
                    ),
                    child: Center(child: Text(
                      '$n',
                      style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold,
                        color: disabled ? AppColors.textHint : accent,
                      ),
                    )),
                  ),
                  const SizedBox(width: 12),
                  Icon(step.icon, size: 17,
                      color: disabled ? AppColors.textHint : AppColors.textPrimary),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(step.label, style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500,
                        color: disabled ? AppColors.textHint : AppColors.textPrimary,
                      )),
                      if (step.subtitle != null)
                        Text(step.subtitle!, style: const TextStyle(
                          fontSize: 11.5, color: AppColors.textSecondary,
                        )),
                    ],
                  )),
                  if (step.onTap != null)
                    Icon(Icons.chevron_right, size: 18, color: accent.withValues(alpha: 0.7)),
                ],
              ),
            ),
          ),
        ),
        if (!isLast) Padding(
          padding: const EdgeInsets.only(left: 52),
          child: Container(height: 0.5, color: AppColors.divider),
        ),
      ],
    );
  }

  List<_StepDef> _stepsFor(_CatalogDef cat) {
    switch (cat.key) {
      case 'yugioh':
        return [
          _StepDef(Icons.download_for_offline, 'Scarica Catalogo', 'Download completo da YGOPRODeck API', _downloadFull),
          _StepDef(Icons.update, 'Aggiorna Nuove Carte', 'Solo carte nuove (incrementale)', _downloadIncremental),
          _StepDef(Icons.cloud_upload, 'Migra Immagini', 'Carica su Backblaze B2', _migrateImages),
          _StepDef(Icons.auto_fix_high, 'Genera Seriali Mancanti', 'Genera set IT/FR/DE/PT/SP da EN', _fillMissingSetsYugioh),
          _StepDef(Icons.translate, 'Scarica Traduzioni', 'Nomi e descrizioni ufficiali', _translateMissingYugioh),
        ];
      case 'onepiece':
        return [
          _StepDef(Icons.cloud_download, 'Scarica Catalogo (CT)', 'Blueprint e metadati da CardTrader (senza immagini)', () => _downloadFromCardtrader('onepiece')),
          _StepDef(Icons.update, 'Aggiorna Nuove Carte', 'Solo carte nuove da OPTCG API (prezzi preservati)', _downloadIncrementalOnePiece),
          _StepDef(Icons.download_for_offline, 'Scarica da OPTCG API', 'Download completo — fonte alternativa', _downloadFullOnePiece),
          _StepDef(Icons.cloud_upload, 'Migra Immagini', 'Carica immagini su Backblaze B2', _migrateOnePieceImages),
          _StepDef(Icons.auto_fix_high, 'Genera Seriali Mancanti', 'Genera set localizzati mancanti', _fillMissingSetsOnePiece),
          _StepDef(Icons.search, 'Anteprima Riparazione Seriali', 'Mostra carte con seriale CT fittizio, senza scrivere', () => _repairDirtySerials('onepiece', dryRun: true)),
          _StepDef(Icons.build, 'Ripara Seriali Sporchi', 'Ri-risolve i seriali CT fittizi via OPTCG', () => _repairDirtySerials('onepiece', dryRun: false)),
        ];
      case 'pokemon':
        return [
          _StepDef(Icons.cloud_download, 'Scarica Catalogo (CT)', 'Blueprint e metadati da CardTrader (senza immagini)', () => _downloadFromCardtrader('pokemon')),
          _StepDef(Icons.update, 'Aggiorna Nuove Carte', 'Solo carte nuove da pokemontcg.io (prezzi preservati)', _downloadIncrementalPokemon),
          _StepDef(Icons.download_for_offline, 'Scarica da pokemontcg.io', 'Download completo — fonte alternativa', _downloadFullPokemon),
          _StepDef(Icons.cloud_upload, 'Migra Immagini', 'Carica immagini su Backblaze B2', _migratePokemonImages),
          _StepDef(Icons.auto_fix_high, 'Genera Seriali Mancanti', 'Genera set localizzati mancanti', _fillMissingSetsPokemon),
          _StepDef(Icons.search, 'Anteprima Riparazione Seriali', 'Mostra carte con seriale CT fittizio, senza scrivere', () => _repairDirtySerials('pokemon', dryRun: true)),
          _StepDef(Icons.build, 'Ripara Seriali Sporchi', 'Ri-risolve i seriali CT fittizi via TCGDex', () => _repairDirtySerials('pokemon', dryRun: false)),
        ];
      case 'magic':
        return [
          _StepDef(Icons.download_for_offline, 'Scarica Catalogo', 'Download completo da Scryfall (oracle_cards ~100 MB)', _downloadFullMagic),
          _StepDef(Icons.update, 'Aggiorna Nuove Carte', 'Solo carte nuove o modificate (incrementale)', _downloadIncrementalMagic),
          _StepDef(Icons.cloud_upload, 'Migra Immagini', 'Carica immagini su Backblaze B2', _migrateMagicImages),
          _StepDef(Icons.auto_fix_high, 'Genera Seriali Mancanti', 'Genera set localizzati mancanti', _fillMissingSetsMagic),
        ];
      case 'digimon':
        return [
          _StepDef(Icons.download_for_offline, 'Scarica Catalogo', 'Download completo da digimoncard.io (EN)',             _downloadFullDigimon),
          _StepDef(Icons.cloud_upload,         'Migra Immagini',   'Carica immagini su Backblaze B2',                      () => _migrateGenericImages('digimon')),
        ];
      case 'lorcana':
        return [
          _StepDef(Icons.download_for_offline, 'Scarica Catalogo', 'Download completo da lorcana-api.com (EN/IT/FR/DE)',   _downloadFullLorcana),
          _StepDef(Icons.cloud_upload,         'Migra Immagini',   'Carica immagini su Backblaze B2',                      () => _migrateGenericImages('lorcana')),
        ];
      case 'flesh-and-blood':
        return [
          _StepDef(Icons.cloud_download, 'Scarica da CardTrader', 'Blueprint e metadati da CardTrader (fabdb.net non disponibile)', _downloadFullFab),
          _StepDef(Icons.cloud_upload,   'Migra Immagini',        'Carica immagini su Backblaze B2',                               () => _migrateGenericImages('flesh-and-blood')),
        ];
      case 'vanguard':
      case 'dragon-ball-super':
      case 'star-wars':
      case 'riftbound':
      case 'gundam':
      case 'union-arena':
        return [
          _StepDef(
            Icons.cloud_download,
            'Scarica da CardTrader',
            'Blueprint e metadati da CardTrader (se disponibile)',
            () => _downloadGenericFromCT(cat.key),
          ),
          _StepDef(Icons.cloud_upload, 'Migra Immagini', 'Carica immagini su Backblaze B2', () => _migrateGenericImages(cat.key)),
        ];
      default:
        return [];
    }
  }

  Widget _opButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
    required String tooltip,
  }) {
    final disabled = _isRunning || onTap == null;
    return Tooltip(
      message: tooltip,
      child: ElevatedButton.icon(
        onPressed: disabled ? null : onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.bgLight,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }

  Widget _buildProManagementCard(BuildContext context) {
    return Card(
      elevation: 2,
      color: AppColors.bgMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.gold.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.workspace_premium, color: AppColors.gold),
                SizedBox(width: 8),
                Text(
                  'Gestione Pro & Donazioni',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.gold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Attiva/disattiva Pro manualmente e registra donazioni',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminProPage()),
                ),
                icon: const Icon(Icons.manage_accounts, size: 16),
                label: Text(AppLocalizations.of(context)!.adminHomeManageProUsers),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetsRaritiesCard(BuildContext context) {
    return Card(
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: const CircleAvatar(
          backgroundColor: AppColors.bgLight,
          child: Icon(Icons.list_alt, color: Colors.deepPurple),
        ),
        title: const Text(
          'Espansioni & Rarità',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Lista completa con traduzioni per collezione'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminSetsRaritiesPage()),
        ),
      ),
    );
  }

  Widget _buildNewsManagementCard(BuildContext context) {
    return Card(
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: const CircleAvatar(
          backgroundColor: AppColors.bgLight,
          child: Icon(Icons.newspaper_outlined, color: Colors.deepPurple),
        ),
        title: const Text(
          'Gestione News',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Pubblicazioni manuali e revisione draft da news_sync'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminNewsPage()),
        ),
      ),
    );
  }

  Widget _buildCardtraderSyncCard() {
    if (!kIsWeb) _coverageStatsFuture ??= _db.getCardtraderCoverageStats();
    return Card(
      elevation: 2,
      color: AppColors.bgLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.teal.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.price_check, color: Colors.teal),
                SizedBox(width: 8),
                Text(
                  'Prezzi CardTrader',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.teal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Prezzi di mercato reali per lingua e 1ª Edizione',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),

            // Coverage stats (mobile-only, SQLite required)
            if (!kIsWeb) _buildCoverageStats(),

            if (_isRunning) ...[
              const SizedBox(height: 12),
              Text(
                _currentOp,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: _progress),
              if (_statusText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _statusText,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
              const SizedBox(height: 12),
            ] else
              const SizedBox(height: 12),

            // ──TCG ─────────────────────────────────────────────────────
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _opButton(icon: Icons.auto_awesome,       label: 'Yu-Gi-Oh!',   color: const Color(0xFF7B1FA2), onTap: _syncCardtraderYugioh,              tooltip: 'Sincronizza prezzi YGO per lingua e edizione'),
                _opButton(icon: Icons.catching_pokemon,   label: 'Pokémon',     color: const Color(0xFFF57C00), onTap: _syncCardtraderPokemon,             tooltip: 'Sincronizza prezzi Pokémon per lingua'),
                _opButton(icon: Icons.sailing,            label: 'One Piece',   color: const Color(0xFFD32F2F), onTap: _syncCardtraderOnePiece,            tooltip: 'Sincronizza prezzi One Piece'),
                _opButton(icon: Icons.pets,                  label: 'Digimon',      color: const Color(0xFF0288D1), onTap: () => _syncCT('digimon'),          tooltip: 'Sincronizza prezzi Digimon'),
                _opButton(icon: Icons.auto_stories,          label: 'Lorcana',      color: const Color(0xFF7B1FA2), onTap: () => _syncCT('lorcana'),          tooltip: 'Sincronizza prezzi Disney Lorcana'),
                _opButton(icon: Icons.sports_martial_arts,   label: 'F&B',          color: const Color(0xFF880E4F), onTap: () => _syncCT('flesh-and-blood'),  tooltip: 'Sincronizza prezzi Flesh and Blood'),
                _opButton(icon: Icons.shield,                label: 'Vanguard',     color: const Color(0xFF1565C0), onTap: () => _syncCT('vanguard'),         tooltip: 'Sincronizza prezzi Cardfight!! Vanguard'),
                _opButton(icon: Icons.bolt,                  label: 'Dragon Ball',  color: const Color(0xFFFF6F00), onTap: () => _syncCT('dragon-ball-super'),tooltip: 'Sincronizza prezzi Dragon Ball Super'),
                _opButton(icon: Icons.rocket_launch,         label: 'Star Wars',    color: const Color(0xFF37474F), onTap: () => _syncCT('star-wars'),        tooltip: 'Sincronizza prezzi Star Wars: Unlimited'),
                _opButton(icon: Icons.casino,                label: 'Riftbound',    color: const Color(0xFF4A148C), onTap: () => _syncCT('riftbound'),        tooltip: 'Sincronizza prezzi Riftbound'),
                _opButton(icon: Icons.smart_toy,             label: 'Gundam',       color: const Color(0xFF37474F), onTap: () => _syncCT('gundam'),           tooltip: 'Sincronizza prezzi Gundam Card Game'),
                _opButton(icon: Icons.people,                label: 'Union Arena',  color: const Color(0xFF2E7D32), onTap: () => _syncCT('union-arena'),      tooltip: 'Sincronizza prezzi Union Arena'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverageStats() {
    final catalogMeta = <String, ({String label, Color color})>{
      'yugioh':           (label: 'Yu-Gi-Oh!',    color: const Color(0xFF7B1FA2)),
      'pokemon':          (label: 'Pokémon',       color: const Color(0xFFF57C00)),
      'onepiece':         (label: 'One Piece',     color: const Color(0xFFD32F2F)),
      'magic':            (label: 'Magic',         color: const Color(0xFF7B5EA7)),
      'digimon':          (label: 'Digimon',       color: const Color(0xFF0288D1)),
      'lorcana':          (label: 'Lorcana',       color: const Color(0xFF7B1FA2)),
      'flesh-and-blood':  (label: 'F&B',           color: const Color(0xFF880E4F)),
      'vanguard':         (label: 'Vanguard',      color: const Color(0xFF1565C0)),
      'dragon-ball-super':(label: 'Dragon Ball',  color: const Color(0xFFFF6F00)),
      'star-wars':        (label: 'Star Wars',     color: const Color(0xFF37474F)),
      'riftbound':        (label: 'Riftbound',     color: const Color(0xFF4A148C)),
      'gundam':           (label: 'Gundam',        color: const Color(0xFF546E7A)),
      'union-arena':      (label: 'Union Arena',   color: const Color(0xFF2E7D32)),
    };

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _coverageStatsFuture,
      builder: (context, snap) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.bgMedium,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Copertura blueprint',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  if (snap.connectionState == ConnectionState.waiting)
                    const SizedBox(
                      width: 12, height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.teal),
                    )
                  else
                    GestureDetector(
                      onTap: () => setState(() { _coverageStatsFuture = _db.getCardtraderCoverageStats(); }),
                      child: const Icon(Icons.refresh, size: 14, color: Colors.teal),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (snap.hasError)
                Text('Errore: ${snap.error}', style: const TextStyle(fontSize: 11, color: Colors.red))
              else if (!snap.hasData || snap.data!.isEmpty)
                Text(AppLocalizations.of(context)!.adminHomeCtNoData, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))
              else ...[
                // Header row
                Row(
                  children: [
                    const SizedBox(width: 84),
                    Expanded(child: Text(AppLocalizations.of(context)!.adminHomeCtData, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary), textAlign: TextAlign.center)),
                    Expanded(child: Text(AppLocalizations.of(context)!.adminHomeCtBlueprint, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary), textAlign: TextAlign.center)),
                    Expanded(child: Text(AppLocalizations.of(context)!.adminHomeCtWithPrice, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary), textAlign: TextAlign.center)),
                    Expanded(child: Text(AppLocalizations.of(context)!.adminHomeCtDiff, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary), textAlign: TextAlign.center)),
                  ],
                ),
                const SizedBox(height: 4),
                for (final row in snap.data!)
                  _buildCoverageRow(row, catalogMeta),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCoverageRow(
    Map<String, dynamic> row,
    Map<String, ({String label, Color color})> meta,
  ) {
    final cat = row['catalog'] as String;
    final local = row['localCards'] as int;
    final ct = row['ctBlueprints'] as int;
    final priced = row['ctPriced'] as int;
    final diff = ct - local;
    final m = meta[cat];
    final color = m?.color ?? Colors.grey;
    final label = m?.label ?? cat;

    final coveragePct = local > 0 ? (ct / local * 100).clamp(0, 999) : 0.0;
    final diffStr = diff > 0 ? '+$diff' : '$diff';
    final diffColor = diff < 0 ? Colors.orange : (diff > 0 ? Colors.green : AppColors.textSecondary);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 84,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Text(
              label,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              '$local',
              style: const TextStyle(fontSize: 11, color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '$ct',
                  style: const TextStyle(fontSize: 11, color: AppColors.textPrimary),
                  textAlign: TextAlign.center,
                ),
                Text(
                  '${coveragePct.toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              '$priced',
              style: const TextStyle(fontSize: 11, color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              diffStr,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: diffColor),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

}

// ── Data classes for stepper UI ────────────────────────────────────────────

class _CatalogDef {
  final String key;
  final String name;
  final IconData icon;
  final Color color;
  const _CatalogDef({
    required this.key,
    required this.name,
    required this.icon,
    required this.color,
  });
}

class _StepDef {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  const _StepDef(this.icon, this.label, this.subtitle, this.onTap);
}

// ── Admin Pro Page ─────────────────────────────────────────────────────────

class AdminProPage extends StatefulWidget {
  const AdminProPage({super.key});
  @override
  State<AdminProPage> createState() => _AdminProPageState();
}

class _AdminProPageState extends State<AdminProPage> {
  final SubscriptionService _service = SubscriptionService();
  final _emailController = TextEditingController();

  List<UserModel> _users = [];
  List<UserModel> _filtered = [];
  bool _loading = true;
  static const int _pageSize = 50;
  int _displayLimit = _pageSize;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final all = await _service.getAllUsers();
      if (!mounted) return;
      setState(() {
        _users = all;
        _filtered = all;
        _loading = false;
      });
    } catch (e) { // ignore: empty_catches
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore caricamento utenti: $e')),
      );
    }
  }

  void _filter(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filtered = _users
          .where((u) =>
              u.email.toLowerCase().contains(q) ||
              (u.displayName?.toLowerCase().contains(q) ?? false))
          .toList();
      _displayLimit = _pageSize; // Reset pagination on new search
    });
  }

  Future<void> _togglePro(UserModel user) async {
    try {
      if (user.isPro) {
        await _service.deactivateProManually(user.uid);
      } else {
        await _service.activateProManually(user.uid);
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(user.isPro
              ? 'Pro disattivato per ${user.displayName ?? user.email}'
              : 'Pro attivato per ${user.displayName ?? user.email}'),
        ),
      );
    } catch (e) { // ignore: empty_catches
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text('Gestione Pro'),
        backgroundColor: AppColors.bgMedium,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _emailController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Cerca per email o nickname...',
                  hintStyle: const TextStyle(color: AppColors.textHint),
                  prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.bgMedium,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: _filter,
              ),
            ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator(color: AppColors.gold)))
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.gold,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _filtered.length > _displayLimit
                        ? _displayLimit + 1
                        : _filtered.length,
                    itemBuilder: (_, i) {
                      if (i >= _displayLimit) {
                      // "Load more" row
                      final remaining = _filtered.length - _displayLimit;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: TextButton(
                          onPressed: () => setState(
                              () => _displayLimit += _pageSize),
                          child: Text(
                            'Mostra altri $remaining utenti',
                            style: const TextStyle(color: AppColors.gold),
                          ),
                        ),
                      );
                    }
                    return _UserProTile(
                      user: _filtered[i],
                      onTogglePro: () => _togglePro(_filtered[i]),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}

class _UserProTile extends StatelessWidget {
  final UserModel user;
  final VoidCallback onTogglePro;
  const _UserProTile({required this.user, required this.onTogglePro});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.bgMedium,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.bgLight,
              backgroundImage: user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
              child: user.photoUrl == null
                  ? const Icon(Icons.person, color: AppColors.textSecondary)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName ?? user.email,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    user.email,
                    style: const TextStyle(color: AppColors.textHint, fontSize: 11),
                  ),
                  if (user.isPro)
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'PRO',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: user.isPro ? 'Disattiva Pro' : 'Attiva Pro',
              onPressed: onTogglePro,
              icon: Icon(
                user.isPro ? Icons.workspace_premium : Icons.workspace_premium_outlined,
                color: user.isPro ? AppColors.gold : AppColors.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Admin home: mostra la lista dei cataloghi da gestire (con proprio Scaffold)
class AdminHomePage extends StatelessWidget {
  const AdminHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.adminCatalogTitle),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: const AdminCatalogBody(),
    );
  }
}
