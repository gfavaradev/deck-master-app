import 'package:flutter/material.dart';
import 'package:deck_master/services/admin_catalog_service.dart';
import 'package:deck_master/services/auth_service.dart';
import 'package:deck_master/theme/app_colors.dart';

/// Admin page for managing the Pokémon TCG catalog.
/// Allows downloading the full catalog from pokemontcg.io and migrating
/// images to Firebase Storage.
class AdminPokemonCatalogPage extends StatefulWidget {
  const AdminPokemonCatalogPage({super.key});

  @override
  State<AdminPokemonCatalogPage> createState() =>
      _AdminPokemonCatalogPageState();
}

class _AdminPokemonCatalogPageState extends State<AdminPokemonCatalogPage> {
  final AdminCatalogService _catalogService = AdminCatalogService();
  final AuthService _authService = AuthService();

  bool _isBusy = false;
  String _status = '';
  double? _progress;
  String? _lastResult;

  Future<void> _run(Future<void> Function(String adminUid) task) async {
    final uid = _authService.currentUserId ?? 'unknown';
    setState(() {
      _isBusy = true;
      _status = 'Inizializzando...';
      _progress = null;
      _lastResult = null;
    });
    try {
      await task(uid);
    } catch (e) { // ignore: empty_catches
      if (mounted) {
        setState(() => _status = 'Errore: $e');
        _showSnack('Errore: $e');
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _downloadCatalog() => _run((uid) async {
        final result = await _catalogService.downloadPokemonCatalogFromAPI(
          adminUid: uid,
          onProgress: (status, progress) {
            if (mounted) {
              setState(() {
                _status = status;
                _progress = progress;
              });
            }
          },
        );
        if (mounted) {
          final total = result['totalCards'] ?? 0;
          final preserved = result['preservedImages'] ?? 0;
          setState(() {
            _lastResult =
                '$total carte caricate. $preserved immagini Firebase preservate.';
            _status = 'Completato.';
            _progress = 1.0;
          });
          _showSnack('Catalogo Pokémon caricato: $total carte.');
        }
      });

  Future<void> _migrateImages() => _run((uid) async {
        final result = await _catalogService.migratePokemonImagesToStorage(
          adminUid: uid,
          onProgress: (current, total) {
            if (mounted) {
              setState(() {
                _status = 'Migrazione immagini $current/$total...';
                _progress = total > 0 ? current / total : null;
              });
            }
          },
        );
        if (mounted) {
          final migrated = result['migrated'] ?? 0;
          final failed = result['failed'] ?? 0;
          final chunks = result['chunksUpdated'] ?? 0;
          setState(() {
            _lastResult =
                '$migrated migrate, $failed fallite, $chunks chunk aggiornati.';
            _status = 'Migrazione completata.';
            _progress = 1.0;
          });
          _showSnack('Immagini migrate: $migrated ok, $failed errori.');
        }
      });

  Future<void> _forceMigrateImages() => _run((uid) async {
        final result = await _catalogService.migratePokemonImagesToStorage(
          adminUid: uid,
          force: true,
          onProgress: (current, total) {
            if (mounted) {
              setState(() {
                _status = 'Re-migrazione immagini $current/$total...';
                _progress = total > 0 ? current / total : null;
              });
            }
          },
        );
        if (mounted) {
          final migrated = result['migrated'] ?? 0;
          final failed = result['failed'] ?? 0;
          setState(() {
            _lastResult = '$migrated re-migrate, $failed fallite.';
            _status = 'Re-migrazione completata.';
            _progress = 1.0;
          });
          _showSnack('Re-migrazione completata: $migrated ok, $failed errori.');
        }
      });

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin — Catalogo Pokémon'),
        backgroundColor: AppColors.bgMedium,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info card
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.catching_pokemon,
                            color: Colors.red.shade700, size: 28),
                        const SizedBox(width: 12),
                        Text(
                          'Pokémon TCG Catalog',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Scarica il catalogo completo da pokemontcg.io (15k+ carte) e '
                      'migra le immagini su Firebase Storage con compressione JPEG.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Progress area
            if (_isBusy || _status.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _status,
                        style: const TextStyle(fontSize: 14),
                      ),
                      if (_progress != null) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: _progress),
                        const SizedBox(height: 4),
                        Text(
                          '${((_progress ?? 0) * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ] else if (_isBusy) ...[
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(),
                      ],
                      if (_lastResult != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle,
                                  color: Colors.green, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _lastResult!,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Actions
            _SectionHeader(title: '1. Scarica catalogo da API'),
            const SizedBox(height: 8),
            _ActionCard(
              icon: Icons.download_rounded,
              title: 'Scarica catalogo completo',
              description:
                  'Recupera tutte le carte da pokemontcg.io e le carica su Firestore. '
                  'Le immagini Firebase già migrate vengono preservate.',
              color: Colors.red.shade700,
              enabled: !_isBusy,
              onTap: () => _showConfirm(
                title: 'Scarica catalogo Pokémon?',
                body:
                    'Questa operazione sostituisce l\'intero catalogo su Firestore.\n\n'
                    'Le immagini già su Firebase Storage vengono preservate.\n'
                    'Può richiedere alcuni minuti.',
                onConfirm: _downloadCatalog,
              ),
            ),

            const SizedBox(height: 24),

            _SectionHeader(title: '2. Migra immagini su Firebase Storage'),
            const SizedBox(height: 8),
            _ActionCard(
              icon: Icons.image_rounded,
              title: 'Migra immagini (solo nuove)',
              description:
                  'Scarica le immagini non ancora su Firebase Storage, le comprime '
                  'in JPEG (400px, q78) e le carica. Carte già migrate vengono saltate.',
              color: Colors.orange.shade700,
              enabled: !_isBusy,
              onTap: _migrateImages,
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.refresh_rounded,
              title: 'Re-migra tutte le immagini',
              description:
                  'Forza la ri-verifica e ri-compressione di ogni immagine, '
                  'anche quelle già su Firebase Storage.',
              color: Colors.deepOrange.shade700,
              enabled: !_isBusy,
              onTap: () => _showConfirm(
                title: 'Re-migrare tutte le immagini?',
                body:
                    'Questa operazione ri-verifica ed eventualmente ri-carica TUTTE '
                    'le immagini su Firebase Storage.\n\nPuò richiedere molto tempo.',
                onConfirm: _forceMigrateImages,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showConfirm({
    required String title,
    required String body,
    required VoidCallback onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Conferma'),
          ),
        ],
      ),
    );
    if (confirmed == true) onConfirm();
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: enabled ? color.withValues(alpha: 0.1) : AppColors.bgLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: enabled ? color : AppColors.textHint,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: enabled ? AppColors.textPrimary : AppColors.textHint,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        color: enabled ? AppColors.textSecondary : AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: enabled ? color : AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
