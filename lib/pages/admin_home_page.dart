import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../services/admin_catalog_service.dart';
import '../services/background_download_service.dart';
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

  // ─── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final collections = AdminCatalogService.getCollectionList();

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: collections.length + 1, // +1 for operations card
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) return _buildOperationsCard();
        final col = collections[index - 1];
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
