import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../services/admin_catalog_service.dart';
import '../services/admin_translation_service.dart';
import '../services/background_download_service.dart';
import '../services/cardtrader_service.dart';
import '../services/subscription_service.dart';
import '../models/user_model.dart';
import '../models/subscription_model.dart';
import '../theme/app_colors.dart';
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
  bool _isRunning = false;
  double? _progress;
  String _statusText = '';
  String _currentOp = '';

  // ─── Operations ───────────────────────────────────────────────────────────

  Future<void> _run(
    String collectionKey,
    String opLabel,
    Future<Map<String, dynamic>> Function(String uid) task,
    String Function(Map<String, dynamic> result) successMessage,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() {
      _isRunning = true;
      _progress = null;
      _statusText = '';
      _currentOp = opLabel;
    });

    try {
      // Avvia il foreground service: mantiene il processo vivo se l'app va in background
      await BackgroundDownloadService.startDownload(opLabel);

      final result = await task(uid);
      if (!mounted) return;
      setState(() { _isRunning = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage(result)),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e, stack) {
      debugPrint('[$_currentOp] ERROR: $e\n$stack');
      if (mounted) {
        setState(() { _isRunning = false; });
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
      // Ferma il foreground service al termine (successo o errore)
      await BackgroundDownloadService.stopDownload();
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
        (r) => (r['newCards'] as int? ?? 0) == 0
            ? 'Nessuna carta nuova trovata.'
            : '${r['newCards']} carte nuove aggiunte.',
      );

  Future<void> _migrateImages() => _confirmAndRun(
        'yugioh',
        'Migrazione Immagini',
        'Migrazione Immagini',
        'Migra le immagini delle carte da ygoprodeck.com a Firebase Storage.\n\n'
            'Solo le immagini non ancora migrate vengono scaricate. '
            'Può richiedere diversi minuti. Continuare?',
        (uid) => _service.migrateAllImagesToStorage(
          catalog: 'yugioh',
          adminUid: uid,
          onProgress: (cur, tot) =>
              _onProgress('$cur / $tot immagini', tot > 0 ? cur / tot : null),
        ),
        (r) => (r['migrated'] as int? ?? 0) == 0 && (r['failed'] as int? ?? 0) == 0
            ? 'Tutte le immagini erano già migrate.'
            : '${r['migrated']} migrate, ${r['failed']} errori, ${r['chunksUpdated']} chunk aggiornati.',
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

  // ─── One Piece action handlers ─────────────────────────────────────────────

  Future<void> _downloadFullOnePiece() => _confirmAndRun(
        'onepiece',
        'Download Completo One Piece',
        'Download Completo One Piece TCG',
        'Scarica l\'intero catalogo One Piece TCG da OPTCG API e '
            'sostituisce tutti i chunk su Firestore.\n\n'
            'Le URL immagini già su Firebase Storage vengono preservate.\n\n'
            'Può richiedere diversi minuti. Continuare?',
        (uid) => _service.downloadOnepieceCatalogFromAPI(
          adminUid: uid,
          onProgress: _onProgress,
        ),
        (r) => 'Completato! ${r['totalCards']} carte, ${r['totalPrints']} print caricate.',
      );

  Future<void> _migrateOnePieceImages() => _confirmAndRun(
        'onepiece',
        'Migrazione Immagini One Piece',
        'Migrazione Immagini One Piece',
        'Scarica le immagini delle carte One Piece dall\'OPTCG API '
            'e le carica su Firebase Storage.\n\n'
            'Solo le immagini non ancora migrate vengono scaricate. '
            'Può richiedere diversi minuti. Continuare?',
        (uid) => _service.migrateOnepieceImagesToStorage(
          adminUid: uid,
          onProgress: (cur, tot) =>
              _onProgress('$cur / $tot immagini', tot > 0 ? cur / tot : null),
        ),
        (r) => (r['migrated'] as int? ?? 0) == 0 && (r['failed'] as int? ?? 0) == 0
            ? 'Tutte le immagini erano già migrate.'
            : '${r['migrated']} migrate, ${r['failed']} errori, ${r['chunksUpdated']} chunk aggiornati.',
      );

  Future<void> _forceMigrateOnePieceImages() => _confirmAndRun(
        'onepiece',
        'Ri-migrazione Forzata One Piece',
        'Ri-migrazione Forzata Immagini',
        'Ri-carica TUTTE le immagini One Piece su Firebase Storage, '
            'anche quelle già presenti.\n\n'
            'Usare dopo aver eliminato le immagini dallo Storage. '
            'Può richiedere diversi minuti. Continuare?',
        (uid) => _service.migrateOnepieceImagesToStorage(
          adminUid: uid,
          onProgress: (cur, tot) =>
              _onProgress('$cur / $tot immagini', tot > 0 ? cur / tot : null),
          force: true,
        ),
        (r) => '${r['migrated']} migrate, ${r['failed']} errori, ${r['chunksUpdated']} chunk aggiornati.',
      );

  // ─── Pokémon action handlers ──────────────────────────────────────────────

  Future<void> _downloadFullPokemon() => _confirmAndRun(
        'pokemon',
        'Download Completo Pokémon',
        'Download Catalogo Pokémon TCG',
        'Scarica l\'intero catalogo Pokémon TCG da pokemontcg.io e '
            'sostituisce tutti i chunk su Firestore.\n\n'
            'Le URL immagini già su Firebase Storage vengono preservate.\n\n'
            'Può richiedere diversi minuti. Continuare?',
        (uid) => _service.downloadPokemonCatalogFromAPI(
          adminUid: uid,
          onProgress: _onProgress,
        ),
        (r) => 'Completato! ${r['totalCards']} carte caricate — '
            'immagini su Storage: ${r['imagesOk']}'
            '${(r['imagesFailed'] as int? ?? 0) > 0 ? ", fallite: ${r['imagesFailed']}" : ""}.',
      );

  Future<void> _migratePokemonImages() => _confirmAndRun(
        'pokemon',
        'Migrazione Immagini Pokémon',
        'Migrazione Immagini Pokémon',
        'Scarica le immagini Pokémon da pokemontcg.io e le carica su Firebase Storage '
            'con compressione JPEG.\n\n'
            'Solo le immagini non ancora migrate vengono scaricate. '
            'Può richiedere diversi minuti. Continuare?',
        (uid) => _service.migratePokemonImagesToStorage(
          adminUid: uid,
          onProgress: (cur, tot) =>
              _onProgress('$cur / $tot immagini', tot > 0 ? cur / tot : null),
        ),
        (r) => (r['migrated'] as int? ?? 0) == 0 && (r['failed'] as int? ?? 0) == 0
            ? 'Tutte le immagini erano già migrate.'
            : '${r['migrated']} migrate, ${r['failed']} errori, ${r['chunksUpdated']} chunk aggiornati.',
      );

  Future<void> _forceMigratePokemonImages() => _confirmAndRun(
        'pokemon',
        'Ri-migrazione Forzata Pokémon',
        'Ri-migrazione Forzata Immagini Pokémon',
        'Ri-carica TUTTE le immagini Pokémon su Firebase Storage, '
            'anche quelle già presenti.\n\n'
            'Può richiedere molto tempo. Continuare?',
        (uid) => _service.migratePokemonImagesToStorage(
          adminUid: uid,
          onProgress: (cur, tot) =>
              _onProgress('$cur / $tot immagini', tot > 0 ? cur / tot : null),
          force: true,
        ),
        (r) => '${r['migrated']} migrate, ${r['failed']} errori, ${r['chunksUpdated']} chunk aggiornati.',
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

  /// Shows a language-picker dialog for [catalog], then runs the CT sync for
  /// the selected language. Returns without doing anything if cancelled.
  Future<void> _syncCardtraderWithLanguagePicker(String catalog) async {
    final langs = CardtraderService.languagesForCatalog(catalog);
    if (langs.isEmpty) return;

    // Default selection: first language in the map
    String? selected = langs.keys.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Sync Prezzi CardTrader — ${_catalogDisplayName(catalog)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Seleziona la lingua da sincronizzare.\n'
                'Verranno scaricati tutti i blueprint noti e i prezzi '
                'delle carte con listing attivi.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: const InputDecoration(
                  labelText: 'Lingua',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: langs.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text('${e.value} (${e.key})'),
                        ))
                    .toList(),
                onChanged: (v) => setS(() => selected = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Avvia Sync'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || selected == null) return;
    final lang = selected!;
    final langLabel = langs[lang] ?? lang;

    await _confirmAndRun(
      catalog,
      'Sync Prezzi CardTrader — $langLabel',
      'Sincronizza Prezzi ($langLabel)',
      'Verranno scaricati tutti i blueprint per la lingua "$langLabel" '
          'e i prezzi per le carte con listing attivi su CardTrader.\n\n'
          'Può richiedere diversi minuti. Continuare?',
      (uid) => _cardtraderService.syncPrices(
        catalog: catalog,
        adminUid: uid,
        onProgress: _onProgress,
        language: lang,
      ),
      (r) {
        final total = r['blueprints'] as int? ?? 0;
        final priced = r['pricedBlueprints'] as int? ?? 0;
        final exps = r['expansions'] as int? ?? 0;
        final err = r['errors'] as int? ?? 0;
        return '$total blueprint in $exps espansioni · $priced con prezzo'
            ' · ${r['valuesUpdated'] ?? 0} valori aggiornati'
            '${err > 0 ? " ($err errori)" : ""}.';
      },
    );
  }

  static String _catalogDisplayName(String catalog) => switch (catalog) {
        'yugioh' => 'Yu-Gi-Oh!',
        'pokemon' => 'Pokémon',
        'onepiece' => 'One Piece',
        _ => catalog,
      };

  Future<void> _syncCardtraderYugioh() =>
      _syncCardtraderWithLanguagePicker('yugioh');

  Future<void> _syncCardtraderPokemon() =>
      _syncCardtraderWithLanguagePicker('pokemon');

  Future<void> _syncCardtraderOnePiece() =>
      _syncCardtraderWithLanguagePicker('onepiece');

  /// Ricalcola `cards.value` dai prezzi CT già in cache locale (senza API call).
  Future<void> _applyCtPricesToCollection() => _run(
        'cardtrader',
        'Applica Prezzi CT',
        (_) async {
          int total = 0;
          for (final cat in ['yugioh', 'pokemon', 'onepiece']) {
            total += await _cardtraderService.applyLocalPricesToCollection(cat);
          }
          return {'valuesUpdated': total};
        },
        (r) => '${r['valuesUpdated']} valori aggiornati dalla cache CT locale.',
      );

  // ─── UI ───────────────────────────────────────────────────────────────────

  static final _catalogs = [
    _CatalogDef(
      key: 'yugioh', name: 'Yu-Gi-Oh!',
      icon: Icons.auto_awesome, color: Color(0xFF7B1FA2),
    ),
    _CatalogDef(
      key: 'onepiece', name: 'One Piece TCG',
      icon: Icons.sailing, color: Color(0xFFD32F2F),
    ),
    _CatalogDef(
      key: 'pokemon', name: 'Pokémon TCG',
      icon: Icons.catching_pokemon, color: Color(0xFFF57C00),
    ),
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

        // Pro management
        _buildProManagementCard(context),
      ],
    );
  }

  Widget _buildGlobalProgress() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blue),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(
                _currentOp,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
              )),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _progress,
            backgroundColor: AppColors.bgDark,
            valueColor: const AlwaysStoppedAnimation(AppColors.blue),
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
          _StepDef(Icons.cloud_upload, 'Migra Immagini', 'Carica su Firebase Storage', kIsWeb ? null : _migrateImages),
          _StepDef(Icons.auto_fix_high, 'Genera Seriali Mancanti', 'Genera set IT/FR/DE/PT/SP da EN', _fillMissingSetsYugioh),
          _StepDef(Icons.translate, 'Scarica Traduzioni', 'Nomi e descrizioni ufficiali', _translateMissingYugioh),
        ];
      case 'onepiece':
        return [
          _StepDef(Icons.download_for_offline, 'Scarica Catalogo', 'Download completo da OPTCG API', _downloadFullOnePiece),
          _StepDef(Icons.cloud_upload, 'Migra Immagini', 'Carica su Firebase Storage', kIsWeb ? null : _migrateOnePieceImages),
          _StepDef(Icons.refresh, 'Ri-migra Tutto', 'Forza ri-migrazione di tutte le immagini', kIsWeb ? null : _forceMigrateOnePieceImages),
          _StepDef(Icons.auto_fix_high, 'Genera Seriali Mancanti', 'Genera set localizzati mancanti', _fillMissingSetsOnePiece),
        ];
      case 'pokemon':
        return [
          _StepDef(Icons.download_for_offline, 'Scarica Catalogo', 'Download completo da pokemontcg.io', _downloadFullPokemon),
          _StepDef(Icons.cloud_upload, 'Migra Immagini', 'Carica su Firebase Storage', kIsWeb ? null : _migratePokemonImages),
          _StepDef(Icons.refresh, 'Ri-migra Tutto', 'Forza ri-migrazione di tutte le immagini', kIsWeb ? null : _forceMigratePokemonImages),
          _StepDef(Icons.auto_fix_high, 'Genera Seriali Mancanti', 'Genera set localizzati mancanti', _fillMissingSetsPokemon),
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
                label: const Text('Gestisci Utenti Pro'),
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

  Widget _buildCardtraderSyncCard() {
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
            const SizedBox(height: 16),
            if (_isRunning) ...[
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
              const SizedBox(height: 16),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _opButton(
                  icon: Icons.style,
                  label: 'Yu-Gi-Oh!',
                  color: Colors.deepPurple,
                  onTap: _syncCardtraderYugioh,
                  tooltip: 'Sincronizza prezzi YGO per lingua e edizione',
                ),
                _opButton(
                  icon: Icons.catching_pokemon,
                  label: 'Pokémon',
                  color: Colors.red.shade700,
                  onTap: _syncCardtraderPokemon,
                  tooltip: 'Sincronizza prezzi Pokémon per lingua',
                ),
                _opButton(
                  icon: Icons.sailing,
                  label: 'One Piece',
                  color: Colors.orange.shade800,
                  onTap: _syncCardtraderOnePiece,
                  tooltip: 'Sincronizza prezzi One Piece',
                ),
                _opButton(
                  icon: Icons.calculate_outlined,
                  label: 'Applica prezzi',
                  color: Colors.teal,
                  onTap: _applyCtPricesToCollection,
                  tooltip: 'Ricalcola valori collezione dai prezzi CT già in cache (senza API)',
                ),
              ],
            ),
          ],
        ),
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
  final _donationController = TextEditingController();

  List<UserModel> _users = [];
  List<UserModel> _filtered = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _donationController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final all = await _service.getAllUsers();
      if (!mounted) return;
      setState(() {
        _users = all;
        _filtered = all;
        _loading = false;
      });
    } catch (e) {
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: $e')));
    }
  }

  Future<void> _recordDonation(UserModel user) async {
    _donationController.clear();
    final confirmed = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMedium,
        title: Text(
          'Registra Donazione — ${user.displayName ?? user.email}',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Totale attuale: €${user.totalDonated.toStringAsFixed(2)}'
              ' (${user.donationTier.label.isEmpty ? "Nessun tier" : user.donationTier.label})',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _donationController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Importo (€)',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                prefixText: '€ ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla', style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: Colors.black),
            onPressed: () {
              final val = double.tryParse(_donationController.text.replaceAll(',', '.'));
              Navigator.pop(ctx, val);
            },
            child: const Text('Registra'),
          ),
        ],
      ),
    );

    if (confirmed == null || confirmed <= 0 || !mounted) return;

    try {
      final newTier = await _service.recordDonation(user.uid, confirmed);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Donazione €${confirmed.toStringAsFixed(2)} registrata.'
            '${newTier != user.donationTier ? " Nuovo tier: ${newTier.label}" : ""}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text('Gestione Pro & Donazioni'),
        backgroundColor: AppColors.bgMedium,
        foregroundColor: AppColors.textPrimary,
      ),
      body: Column(
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
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) => _UserProTile(
                    user: _filtered[i],
                    onTogglePro: () => _togglePro(_filtered[i]),
                    onDonation: () => _recordDonation(_filtered[i]),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UserProTile extends StatelessWidget {
  final UserModel user;
  final VoidCallback onTogglePro;
  final VoidCallback onDonation;
  const _UserProTile({required this.user, required this.onTogglePro, required this.onDonation});

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
                  Row(
                    children: [
                      if (user.isPro)
                        Container(
                          margin: const EdgeInsets.only(top: 3, right: 6),
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
                      if (user.donationTier != DonationTier.none)
                        Text(
                          '${user.donationTier.symbol} ${user.donationTier.label} · €${user.totalDonated.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: user.donationTier.color,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  tooltip: user.isPro ? 'Disattiva Pro' : 'Attiva Pro',
                  onPressed: onTogglePro,
                  icon: Icon(
                    user.isPro ? Icons.workspace_premium : Icons.workspace_premium_outlined,
                    color: user.isPro ? AppColors.gold : AppColors.textHint,
                  ),
                ),
                IconButton(
                  tooltip: 'Registra donazione',
                  onPressed: onDonation,
                  icon: const Icon(Icons.favorite_outline, color: Color(0xFFFF6B35)),
                ),
              ],
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
        title: const Text('Admin — Gestione Catalogo'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: const AdminCatalogBody(),
    );
  }
}
