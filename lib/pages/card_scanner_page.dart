import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/card_scanner_service.dart';
import '../services/data_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/card_dialogs.dart';

class CardScannerPage extends StatefulWidget {
  /// If set, limits scanning to this specific collection.
  final String? collectionKey;
  final String? collectionName;

  const CardScannerPage({
    super.key,
    this.collectionKey,
    this.collectionName,
  });

  @override
  State<CardScannerPage> createState() => _CardScannerPageState();
}

class _CardScannerPageState extends State<CardScannerPage> {
  final _scanner = CardScannerService();
  final _repo = DataRepository();

  _ScanState _state = _ScanState.idle;
  CardScanResult? _result;
  String? _errorMessage;

  static const _collectionLabels = {
    'yugioh': 'Yu-Gi-Oh!',
    'pokemon': 'Pokémon',
    'onepiece': 'One Piece TCG',
  };

  static const _collectionColors = {
    'yugioh': AppColors.yugiohAccent,
    'pokemon': AppColors.pokemonAccent,
    'onepiece': AppColors.onepieceAccent,
  };

  @override
  void initState() {
    super.initState();
    // Auto-open camera on first load
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    setState(() {
      _state = _ScanState.scanning;
      _result = null;
      _errorMessage = null;
    });

    try {
      final result = await _scanner.scanFromCamera(
        collectionHint: widget.collectionKey,
      );
      if (!mounted) return;

      if (result == null) {
        setState(() {
          _state = _ScanState.notFound;
          _errorMessage = 'Carta non riconosciuta.\nProva con una foto più nitida e ben illuminata.';
        });
      } else {
        setState(() {
          _state = _ScanState.found;
          _result = result;
        });
      }
    } catch (e) { // ignore: empty_catches
      if (!mounted) return;
      setState(() {
        _state = _ScanState.notFound;
        _errorMessage = 'Errore durante la scansione: $e';
      });
    }
  }

  Future<void> _addToCollection() async {
    final result = _result;
    if (result == null) return;

    final collection = result.collection;
    final collectionName = _collectionLabels[collection] ?? collection;

    final albums = await _repo.getAlbumsByCollection(collection);
    final allCards = await _repo.getCardsByCollection(collection);

    if (!mounted) return;

    if (albums.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nessun album trovato per $collectionName'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    CardDialogs.showAddCard(
      context: context,
      collectionName: collectionName,
      collectionKey: collection,
      availableAlbums: albums,
      allCards: allCards,
      initialCatalogCard: result.catalogCard,
      onCardAdded: (albumId, serial) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${result.cardName} aggiunta alla collezione!'),
              backgroundColor: Colors.green.shade700,
            ),
          );
        }
      },
      getOrCreateDuplicatesAlbum: () => _repo.getOrCreateDoppioniAlbum(collection),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text('Scansiona Carta'),
        backgroundColor: AppColors.bgMedium,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: switch (_state) {
            _ScanState.idle => _buildIdle(),
            _ScanState.scanning => _buildScanning(),
            _ScanState.found => _buildFound(),
          _ScanState.notFound => _buildNotFound(),
        },
      ),
      ),
    );
  }

  Widget _buildIdle() {
    return Center(
      key: const ValueKey('idle'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.document_scanner_outlined,
              size: 80, color: AppColors.textHint),
          const SizedBox(height: 24),
          const Text(
            'Punta la fotocamera su una carta\nper identificarla automaticamente',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
          const SizedBox(height: 32),
          _scanButton(),
        ],
      ),
    );
  }

  Widget _buildScanning() {
    return const Center(
      key: ValueKey('scanning'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.blue),
          SizedBox(height: 20),
          Text(
            'Analisi in corso…',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
          SizedBox(height: 8),
          Text(
            'OCR → Gemini Vision',
            style: TextStyle(color: AppColors.textHint, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildFound() {
    final result = _result!;
    final collectionLabel = _collectionLabels[result.collection] ?? result.collection;
    final collectionColor = _collectionColors[result.collection] ?? AppColors.blue;
    final imageUrl = result.catalogCard?['imageUrl'] as String?;
    final inCatalog = result.catalogCard != null;

    return SingleChildScrollView(
      key: const ValueKey('found'),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // ── Card preview ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgMedium,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 80,
                    height: 110,
                    child: imageUrl != null && imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 160,
                            memCacheHeight: 220,
                            placeholder: (ctx, url) => Container(color: AppColors.bgLight),
                            errorWidget: (ctx, url, err) => const _CardPlaceholder(),
                          )
                        : const _CardPlaceholder(),
                  ),
                ),
                const SizedBox(width: 16),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _Badge(
                            label: collectionLabel,
                            color: collectionColor,
                          ),
                          const SizedBox(width: 8),
                          _Badge(
                            label: result.source == 'ocr' ? 'OCR' : 'AI',
                            color: result.source == 'ocr'
                                ? AppColors.blue
                                : AppColors.purple,
                            icon: result.source == 'gemini'
                                ? Icons.auto_awesome
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        result.cardName,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (result.serialNumber.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          result.serialNumber,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                      if (!inCatalog) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.4)),
                          ),
                          child: const Text(
                            'Carta non nel catalogo locale',
                            style: TextStyle(
                                color: Colors.orange, fontSize: 11),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Actions ───────────────────────────────────────────────────────
          if (inCatalog)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _addToCollection,
                icon: const Icon(Icons.add),
                label: const Text('Aggiungi a Collezione'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Scansiona un\'altra carta'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: BorderSide(color: AppColors.textHint.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotFound() {
    return Center(
      key: const ValueKey('notFound'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 64, color: AppColors.textHint),
            const SizedBox(height: 20),
            Text(
              _errorMessage ?? 'Carta non riconosciuta.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 32),
            _scanButton(),
          ],
        ),
      ),
    );
  }

  Widget _scanButton() {
    return ElevatedButton.icon(
      onPressed: _scan,
      icon: const Icon(Icons.camera_alt),
      label: const Text('Apri Fotocamera'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

enum _ScanState { idle, scanning, found, notFound }

class _CardPlaceholder extends StatelessWidget {
  const _CardPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgLight,
      child: const Icon(Icons.style, color: AppColors.textHint, size: 32),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const _Badge({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
