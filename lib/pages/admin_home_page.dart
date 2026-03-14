import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../services/admin_catalog_service.dart';
import '../services/background_download_service.dart';
import '../services/subscription_service.dart';
import '../models/user_model.dart';
import '../models/subscription_model.dart';
import '../theme/app_colors.dart';
import 'admin_collection_page.dart';

/// Body riutilizzabile con la lista dei cataloghi da gestire
class AdminCatalogBody extends StatefulWidget {
  const AdminCatalogBody({super.key});

  @override
  State<AdminCatalogBody> createState() => _AdminCatalogBodyState();
}

class _AdminCatalogBodyState extends State<AdminCatalogBody> {
  final AdminCatalogService _service = AdminCatalogService();
  bool _isRunning = false;
  double? _progress;
  String _statusText = '';
  String _currentOp = '';

  // ─── Operations ───────────────────────────────────────────────────────────

  Future<void> _run(
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

    // Avvia il foreground service: mantiene il processo vivo se l'app va in background
    await BackgroundDownloadService.startDownload(opLabel);

    try {
      final result = await task(uid);
      if (!mounted) return;
      setState(() => _isRunning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage(result)),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e, stack) {
      debugPrint('[$_currentOp] ERROR: $e\n$stack');
      if (mounted) {
        setState(() => _isRunning = false);
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
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Avvia'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(opLabel, task, successMessage);
  }

  void _onProgress(String status, double? progress) {
    if (mounted) setState(() { _statusText = status; _progress = progress; });
    BackgroundDownloadService.updateStatus(status);
  }

  // ─── Action handlers ──────────────────────────────────────────────────────

  Future<void> _downloadFull() => _confirmAndRun(
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
            '${r['preservedAdminCards'] > 0 ? " (${r['preservedAdminCards']} preservate)" : ""}.',
      );

  Future<void> _downloadIncremental() => _confirmAndRun(
        'Aggiornamento Incrementale',
        'Aggiorna Nuove Carte',
        'Aggiunge solo le carte nuove presenti su YGOPRODeck '
            'che non sono ancora nel catalogo Firestore.\n\n'
            'Le carte esistenti non vengono modificate. Continuare?',
        (uid) => _service.downloadIncrementalCatalog(
          adminUid: uid,
          onProgress: _onProgress,
        ),
        (r) => r['newCards'] == 0
            ? 'Nessuna carta nuova trovata.'
            : '${r['newCards']} carte nuove aggiunte.',
      );

  Future<void> _fillSets() => _confirmAndRun(
        'Riempi Set Mancanti',
        'Riempi Set Localizzati',
        'Genera i set IT/FR/DE/PT mancanti per tutte le carte '
            'nel catalogo Firestore.\n\n'
            'Scrive solo i chunk che necessitano modifiche. Continuare?',
        (uid) => _service.fillMissingLocalizedSets(
          adminUid: uid,
          onProgress: _onProgress,
        ),
        (r) => r['modifiedCards'] == 0
            ? 'Tutti i set erano già completi.'
            : '${r['modifiedCards']} carte aggiornate in ${r['modifiedChunks']}/${r['totalChunks']} chunk.',
      );

  Future<void> _migrateImages() => _confirmAndRun(
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
        (r) => r['migrated'] == 0 && r['failed'] == 0
            ? 'Tutte le immagini erano già migrate.'
            : '${r['migrated']} migrate, ${r['failed']} errori, ${r['chunksUpdated']} chunk aggiornati.',
      );

  // ─── One Piece action handlers ─────────────────────────────────────────────

  Future<void> _downloadFullOnePiece() => _confirmAndRun(
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
        (r) => r['migrated'] == 0 && r['failed'] == 0
            ? 'Tutte le immagini erano già migrate.'
            : '${r['migrated']} migrate, ${r['failed']} errori, ${r['chunksUpdated']} chunk aggiornati.',
      );

  Future<void> _forceMigrateOnePieceImages() => _confirmAndRun(
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
        (r) => r['migrated'] == 0 && r['failed'] == 0
            ? 'Tutte le immagini erano già migrate.'
            : '${r['migrated']} migrate, ${r['failed']} errori, ${r['chunksUpdated']} chunk aggiornati.',
      );

  Future<void> _forceMigratePokemonImages() => _confirmAndRun(
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

  // ─── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final collections = AdminCatalogService.getCollectionList();

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: collections.length + 4, // +4 for operations cards + pro card
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) return _buildOperationsCard();
        if (index == 1) return _buildOnePieceOperationsCard();
        if (index == 2) return _buildPokemonOperationsCard();
        if (index == 3) return _buildProManagementCard(context);
        final col = collections[index - 4];
        return Card(
          elevation: 2,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            leading: CircleAvatar(
              backgroundColor: Colors.deepPurple.shade100,
              child: Icon(_iconFor(col['icon']!), color: Colors.deepPurple),
            ),
            title: Text(
              col['name']!,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            subtitle: Text('Catalogo: ${col['key']}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AdminCollectionPage(
                    collectionKey: col['key']!,
                    collectionName: col['name']!,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildOperationsCard() {
    return Card(
      elevation: 2,
      color: Colors.deepPurple.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Row(
              children: [
                Icon(Icons.settings_applications, color: Colors.deepPurple),
                SizedBox(width: 8),
                Text(
                  'Operazioni Catalogo',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.deepPurple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Yu-Gi-Oh! — Gestione dati Firestore',
              style: TextStyle(color: Colors.black45, fontSize: 12),
            ),
            const SizedBox(height: 16),

            // Progress area (shown while running)
            if (_isRunning) ...[
              Text(
                _currentOp,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: _progress),
              if (_statusText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _statusText,
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
              const SizedBox(height: 16),
            ],

            // Operation buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _opButton(
                  icon: Icons.download_for_offline,
                  label: 'Download Completo',
                  color: Colors.deepPurple,
                  onTap: _downloadFull,
                  tooltip: 'Scarica tutto il catalogo da YGOPRODeck API',
                ),
                _opButton(
                  icon: Icons.update,
                  label: 'Aggiorna Nuove',
                  color: Colors.indigo,
                  onTap: _downloadIncremental,
                  tooltip: 'Aggiunge solo le carte nuove (incrementale)',
                ),
                _opButton(
                  icon: Icons.language,
                  label: 'Riempi Set',
                  color: Colors.orange.shade700,
                  onTap: _fillSets,
                  tooltip: 'Genera i set IT/FR/DE/PT mancanti',
                ),
                _opButton(
                  icon: Icons.cloud_upload,
                  label: 'Migra Immagini',
                  color: Colors.teal,
                  onTap: kIsWeb ? null : _migrateImages,
                  tooltip: kIsWeb
                      ? 'Non disponibile su Web (CORS)'
                      : 'Carica immagini su Firebase Storage',
                ),
              ],
            ),

            if (kIsWeb) ...[
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.info_outline, size: 12, color: Colors.black38),
                  SizedBox(width: 4),
                  Text(
                    '"Migra Immagini" non disponibile su Web (CORS).',
                    style: TextStyle(fontSize: 11, color: Colors.black38),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOnePieceOperationsCard() {
    return Card(
      elevation: 2,
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.sailing, color: Colors.red),
                SizedBox(width: 8),
                Text(
                  'Operazioni Catalogo',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'One Piece TCG — Gestione dati Firestore',
              style: TextStyle(color: Colors.black45, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _opButton(
                  icon: Icons.download_for_offline,
                  label: 'Download Completo',
                  color: Colors.red.shade700,
                  onTap: _downloadFullOnePiece,
                  tooltip: 'Scarica tutto il catalogo da OPTCG API',
                ),
                _opButton(
                  icon: Icons.cloud_upload,
                  label: 'Migra Immagini',
                  color: Colors.orange.shade800,
                  onTap: kIsWeb ? null : _migrateOnePieceImages,
                  tooltip: kIsWeb
                      ? 'Non disponibile su Web (CORS)'
                      : 'Carica immagini su Firebase Storage',
                ),
                _opButton(
                  icon: Icons.refresh,
                  label: 'Ri-migra Tutto',
                  color: Colors.deepOrange.shade700,
                  onTap: kIsWeb ? null : _forceMigrateOnePieceImages,
                  tooltip: kIsWeb
                      ? 'Non disponibile su Web (CORS)'
                      : 'Forza ri-migrazione di tutte le immagini (dopo eliminazione da Storage)',
                ),
              ],
            ),
            if (kIsWeb) ...[
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.info_outline, size: 12, color: Colors.black38),
                  SizedBox(width: 4),
                  Text(
                    '"Migra Immagini" non disponibile su Web (CORS).',
                    style: TextStyle(fontSize: 11, color: Colors.black38),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPokemonOperationsCard() {
    return Card(
      elevation: 2,
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.catching_pokemon, color: Colors.red),
                SizedBox(width: 8),
                Text(
                  'Operazioni Catalogo',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Pokémon TCG — Gestione dati Firestore',
              style: TextStyle(color: Colors.black45, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _opButton(
                  icon: Icons.download_for_offline,
                  label: 'Download Completo',
                  color: Colors.red.shade700,
                  onTap: _downloadFullPokemon,
                  tooltip: 'Scarica tutto il catalogo da pokemontcg.io',
                ),
                _opButton(
                  icon: Icons.cloud_upload,
                  label: 'Migra Immagini',
                  color: Colors.orange.shade800,
                  onTap: kIsWeb ? null : _migratePokemonImages,
                  tooltip: kIsWeb
                      ? 'Non disponibile su Web (CORS)'
                      : 'Carica immagini su Firebase Storage',
                ),
                _opButton(
                  icon: Icons.refresh,
                  label: 'Ri-migra Tutto',
                  color: Colors.deepOrange.shade700,
                  onTap: kIsWeb ? null : _forceMigratePokemonImages,
                  tooltip: kIsWeb
                      ? 'Non disponibile su Web (CORS)'
                      : 'Forza ri-migrazione di tutte le immagini',
                ),
              ],
            ),
            if (kIsWeb) ...[
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.info_outline, size: 12, color: Colors.black38),
                  SizedBox(width: 4),
                  Text(
                    '"Migra Immagini" non disponibile su Web (CORS).',
                    style: TextStyle(fontSize: 11, color: Colors.black38),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
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
          disabledBackgroundColor: Colors.grey.shade300,
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

  IconData _iconFor(String iconName) {
    switch (iconName) {
      case 'catching_pokemon':
        return Icons.catching_pokemon;
      case 'auto_awesome':
        return Icons.auto_awesome;
      case 'sailing':
        return Icons.sailing;
      default:
        return Icons.style;
    }
  }
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
