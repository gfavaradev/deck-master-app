import '../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/card_scanner_service.dart';
import '../services/data_repository.dart';
import '../services/subscription_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_dialog.dart';
import '../widgets/card_dialogs.dart';
import 'pro_page.dart';

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

  // ── Scanner limit ─────────────────────────────────────────────────────────
  static const int _kFreeLimit = 25;
  static const String _kScanCountKey = 'scanner_monthly_count';
  static const String _kScanMonthKey = 'scanner_month';
  static const String _kAiConsentKey = 'scanner_ai_consent_v1';

  int _scansUsed = 0;
  bool _isPro = false;
  bool _limitLoaded = false;

  bool get _canScan => _isPro || _scansUsed < _kFreeLimit;
  int get _scansRemaining => (_kFreeLimit - _scansUsed).clamp(0, _kFreeLimit);

  static String _currentMonth() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  // ─────────────────────────────────────────────────────────────────────────

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
    _loadScanLimit();
  }

  Future<void> _loadScanLimit() async {
    final results = await Future.wait([
      SharedPreferences.getInstance(),
      SubscriptionService().currentUserHasPro(),
    ]);
    final prefs = results[0] as SharedPreferences;
    final isPro = results[1] as bool;

    final storedMonth = prefs.getString(_kScanMonthKey) ?? '';
    final currentMonth = _currentMonth();
    int count = prefs.getInt(_kScanCountKey) ?? 0;

    if (storedMonth != currentMonth) {
      count = 0;
      await prefs.setInt(_kScanCountKey, 0);
      await prefs.setString(_kScanMonthKey, currentMonth);
    }

    if (!mounted) return;
    setState(() {
      _scansUsed = count;
      _isPro = isPro;
      _limitLoaded = true;
    });

    // Auto-open camera after limit is loaded
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _incrementScanCount() async {
    final prefs = await SharedPreferences.getInstance();
    final newCount = _scansUsed + 1;
    await prefs.setInt(_kScanCountKey, newCount);
    await prefs.setString(_kScanMonthKey, _currentMonth());
    if (mounted) setState(() => _scansUsed = newCount);
  }

  void _showLimitDialog() {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (_) => AppDialog(
        title: l10n.cardScannerLimitTitle,
        icon: Icons.document_scanner_outlined,
        iconColor: AppColors.gold,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hai utilizzato tutte le 25 scansioni gratuite di questo mese.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.glowGold,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.workspace_premium, color: AppColors.gold, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Con il piano Pro hai scansioni illimitate ogni mese.',
                      style: TextStyle(color: AppColors.gold, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Il contatore si azzera il 1° di ogni mese.',
              style: TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: appDialogCancelStyle(),
            child: const Text('Chiudi'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProPage()),
              );
            },
            icon: const Icon(Icons.workspace_premium, size: 16),
            label: Text(l10n.cardScannerGoToPro),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows the Google Play-required prominent disclosure before first camera use.
  /// Returns true if the user consented (or had already consented), false otherwise.
  Future<bool> _ensureAiConsent() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kAiConsentKey) == true) return true;
    if (!mounted) return false;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.privacy_tip_outlined, color: AppColors.gold, size: 22),
            SizedBox(width: 10),
            Text(
              'Informativa scanner AI',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            'Per identificare le tue carte, la foto scattata viene inviata temporaneamente ai servizi AI di Google (Gemini) tramite connessione cifrata.\n\n'
            'Le immagini non vengono conservate da Deck Master né da Google oltre il tempo necessario all\'elaborazione della singola richiesta.\n\n'
            'Continuando autorizzi questo trasferimento. Puoi rifiutare: in quel caso lo scanner non sarà disponibile.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.55),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non accetto', style: TextStyle(color: AppColors.textHint)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Accetto'),
          ),
        ],
      ),
    );

    if (accepted == true) {
      await prefs.setBool(_kAiConsentKey, true);
      return true;
    }
    return false;
  }

  Future<void> _scan() async {
    if (!_limitLoaded) return;

    if (!_canScan) {
      _showLimitDialog();
      return;
    }

    if (!await _ensureAiConsent()) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }

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

      // Count every API call (found or not)
      await _incrementScanCount();
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
          content: Text(AppLocalizations.of(context)!.cardScannerNoAlbum(collectionName)),
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
              content: Text(AppLocalizations.of(context)!.cardScannerCardAdded(result.cardName)),
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
    final showCounter = _limitLoaded && !_isPro;
    final isNearLimit = _scansRemaining <= 5;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.cardScannerTitle),
        backgroundColor: AppColors.bgMedium,
        foregroundColor: AppColors.textPrimary,
        actions: [
          if (showCounter)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: GestureDetector(
                  onTap: isNearLimit || _scansRemaining == 0
                      ? _showLimitDialog
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isNearLimit
                          ? AppColors.error.withValues(alpha: 0.15)
                          : AppColors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isNearLimit ? AppColors.error : AppColors.blue,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.document_scanner_outlined,
                          size: 12,
                          color: isNearLimit ? AppColors.error : AppColors.blue,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$_scansUsed / $_kFreeLimit',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isNearLimit ? AppColors.error : AppColors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: !_limitLoaded
            ? const Center(child: CircularProgressIndicator())
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: switch (_state) {
                  _ScanState.idle     => _buildIdle(),
                  _ScanState.scanning => _buildScanning(),
                  _ScanState.found    => _buildFound(),
                  _ScanState.notFound => _buildNotFound(),
                },
              ),
      ),
    );
  }

  Widget _buildIdle() {
    return Center(
      key: const ValueKey('idle'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
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
            if (!_isPro && _scansRemaining <= 5 && _scansRemaining > 0) ...[
              const SizedBox(height: 16),
              _ScanLimitWarning(remaining: _scansRemaining, onUpgrade: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProPage()));
              }),
            ],
          ],
        ),
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
                label: Text(AppLocalizations.of(context)!.cardScannerAddToCollection),
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
              label: Text(AppLocalizations.of(context)!.cardScannerScanAnother),
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
      label: Text(AppLocalizations.of(context)!.cardScannerOpenCamera),
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

// ─── Scan limit warning banner ────────────────────────────────────────────────

class _ScanLimitWarning extends StatelessWidget {
  final int remaining;
  final VoidCallback onUpgrade;
  const _ScanLimitWarning({required this.remaining, required this.onUpgrade});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Ti restano solo $remaining scansioni gratuite questo mese.',
              style: const TextStyle(color: AppColors.warning, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onUpgrade,
            child: Text(
              AppLocalizations.of(context)!.cardScannerGoToPro,
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.gold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

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
