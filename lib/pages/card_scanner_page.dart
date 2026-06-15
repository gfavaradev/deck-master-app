import '../l10n/app_localizations.dart';
import 'dart:math' as math;
import 'package:camera/camera.dart';
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
  final String? collectionKey;
  final String? collectionName;

  const CardScannerPage({super.key, this.collectionKey, this.collectionName});

  @override
  State<CardScannerPage> createState() => _CardScannerPageState();
}

class _CardScannerPageState extends State<CardScannerPage> {
  final _scanner = CardScannerService();
  final _repo = DataRepository();

  _ScanState _state = _ScanState.preview;
  CardScanResult? _result;
  String? _errorMessage;

  // ── Camera ────────────────────────────────────────────────────────────────
  CameraController? _cameraCtrl;
  bool _cameraReady = false;
  String? _cameraError;

  // ── Scan limit ────────────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadScanLimit();
    _initCamera();
  }

  @override
  void dispose() {
    _cameraCtrl?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = 'Nessuna fotocamera trovata sul dispositivo.');
        return;
      }
      if (!mounted) return;
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      if (!mounted) { await ctrl.dispose(); return; }
      setState(() {
        _cameraCtrl = ctrl;
        _cameraReady = true;
      });
    } catch (e) {
      if (mounted) setState(() => _cameraError = 'Impossibile accedere alla fotocamera: $e');
    }
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
            child: Text(AppLocalizations.of(context)!.btnClose),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ProPage()));
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
        title: Row(
          children: [
            const Icon(Icons.privacy_tip_outlined, color: AppColors.gold, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppLocalizations.of(ctx)!.scannerPrivacyTitle,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            AppLocalizations.of(ctx)!.scannerPrivacyBody,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.55),
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
            child: Text(AppLocalizations.of(ctx)!.btnAccept),
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
    if (_state == _ScanState.analyzing) return;
    if (!_limitLoaded || !_cameraReady) return;

    if (!_canScan) {
      _showLimitDialog();
      return;
    }

    if (!await _ensureAiConsent()) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }

    final ctrl = _cameraCtrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    setState(() {
      _state = _ScanState.analyzing;
      _result = null;
      _errorMessage = null;
    });

    try {
      final xFile = await ctrl.takePicture();
      await _incrementScanCount();
      if (!mounted) return;

      final result = await _scanner.processImage(xFile, collectionHint: widget.collectionKey);
      if (!mounted) return;

      if (result == null) {
        setState(() {
          _state = _ScanState.notFound;
          _errorMessage = 'Carta non riconosciuta.\nInquadra meglio la carta e riprova.';
        });
      } else {
        setState(() {
          _state = _ScanState.found;
          _result = result;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ScanState.notFound;
        _errorMessage = 'Errore durante la scansione: $e';
      });
    }
  }

  void _resetToPreview() {
    setState(() {
      _state = _ScanState.preview;
      _result = null;
      _errorMessage = null;
    });
  }

  Future<void> _addToCollection() async {
    final result = _result;
    if (result == null) return;

    final collection = result.collection;
    final collectionName = _collectionLabels[collection] ?? collection;

    final albums = await _repo.getAlbumsByCollection(collection);

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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final showCounter = _limitLoaded && !_isPro;
    final isNearLimit = _scansRemaining <= 5;
    final inCameraView = _state == _ScanState.preview || _state == _ScanState.analyzing;

    return Scaffold(
      backgroundColor: inCameraView ? Colors.black : AppColors.bgDark,
      extendBodyBehindAppBar: inCameraView,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.cardScannerTitle),
        backgroundColor: inCameraView ? Colors.black.withValues(alpha: 0.35) : AppColors.bgMedium,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (showCounter)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: GestureDetector(
                  onTap: isNearLimit || _scansRemaining == 0 ? _showLimitDialog : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isNearLimit
                          ? AppColors.error.withValues(alpha: 0.20)
                          : Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isNearLimit ? AppColors.error : Colors.white.withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.document_scanner_outlined,
                          size: 12,
                          color: isNearLimit ? AppColors.error : Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$_scansUsed / $_kFreeLimit',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isNearLimit ? AppColors.error : Colors.white,
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
      body: switch (_state) {
        _ScanState.preview || _ScanState.analyzing => _buildLiveScanner(),
        _ScanState.found    => _buildFound(),
        _ScanState.notFound => _buildNotFound(),
      },
    );
  }

  // ── Live scanner view (preview + analyzing overlay) ───────────────────────

  Widget _buildLiveScanner() {
    final isAnalyzing = _state == _ScanState.analyzing;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview
        if (_cameraReady && _cameraCtrl != null)
          _CameraFit(controller: _cameraCtrl!)
        else if (_cameraError != null)
          _buildCameraError()
        else
          const Center(child: CircularProgressIndicator(color: Colors.white)),

        // Scanning frame overlay
        if (_cameraReady)
          const _ScannerFrameOverlay(),

        // Analyzing overlay
        if (isAnalyzing)
          Container(
            color: Colors.black.withValues(alpha: 0.6),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.gold, strokeWidth: 3),
                  SizedBox(height: 20),
                  Text(
                    'Analisi in corso…',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Gemini Vision AI',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

        // Bottom controls (shown only in preview state)
        if (!isAnalyzing && _cameraReady)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildScanControls(),
          ),
      ],
    );
  }

  Widget _buildScanControls() {
    return Container(
      padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(context).padding.bottom + 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppLocalizations.of(context)!.scannerFrameInstruction,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          // Scan button
          GestureDetector(
            onTap: _scan,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold,
                boxShadow: [
                  BoxShadow(color: AppColors.gold.withValues(alpha: 0.45), blurRadius: 18, spreadRadius: 2),
                ],
              ),
              child: const Icon(Icons.document_scanner_outlined, color: Colors.black87, size: 30),
            ),
          ),
          const SizedBox(height: 10),
          Text(AppLocalizations.of(context)!.scannerScanBtn, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          if (!_isPro && _scansRemaining <= 5 && _scansRemaining > 0) ...[
            const SizedBox(height: 12),
            _ScanLimitWarning(
              remaining: _scansRemaining,
              onUpgrade: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProPage())),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCameraError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              _cameraError ?? 'Fotocamera non disponibile.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  // ── Result views (unchanged from before) ─────────────────────────────────

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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _Badge(label: collectionLabel, color: collectionColor),
                          const SizedBox(width: 8),
                          _Badge(
                            label: result.source == 'ocr' ? 'OCR' : 'AI',
                            color: result.source == 'ocr' ? AppColors.blue : AppColors.purple,
                            icon: result.source == 'gemini' ? Icons.auto_awesome : null,
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
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                          ),
                          child: const Text(
                            'Carta non nel catalogo locale',
                            style: TextStyle(color: Colors.orange, fontSize: 11),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _resetToPreview,
              icon: const Icon(Icons.document_scanner_outlined),
              label: Text(AppLocalizations.of(context)!.cardScannerScanAnother),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: BorderSide(color: AppColors.textHint.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            ElevatedButton.icon(
              onPressed: _resetToPreview,
              icon: const Icon(Icons.document_scanner_outlined),
              label: Text(AppLocalizations.of(context)!.cardScannerOpenCamera),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Camera full-fit helper ───────────────────────────────────────────────────

/// Fills the available space with the camera preview, cropping edges if needed
/// (similar to how a native camera viewfinder looks).
class _CameraFit extends StatelessWidget {
  final CameraController controller;
  const _CameraFit({required this.controller});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final previewSize = controller.value.previewSize;
      if (previewSize == null) return const SizedBox.expand();
      // previewSize is landscape (width > height) on most devices
      final previewAspect = previewSize.flipped.aspectRatio; // portrait
      final screenAspect = constraints.maxWidth / constraints.maxHeight;
      final scale = screenAspect > previewAspect
          ? constraints.maxWidth / (constraints.maxHeight * previewAspect)
          : 1.0;
      return ClipRect(
        child: Transform.scale(
          scale: scale,
          child: Center(child: CameraPreview(controller)),
        ),
      );
    });
  }
}

// ─── Scanner frame overlay ────────────────────────────────────────────────────

class _ScannerFrameOverlay extends StatelessWidget {
  const _ScannerFrameOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _FramePainter());
  }
}

class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Dark semi-transparent overlay with a cut-out rectangle
    const double frameW = 260;
    final double frameH = frameW * 1.4; // card aspect ratio ≈ 1:1.4
    final double left = (size.width - frameW) / 2;
    final double top = (size.height - frameH) / 2 - 30;
    final frameRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, frameW, frameH),
      const Radius.circular(12),
    );

    // Dim the area outside the frame
    final dimPaint = Paint()..color = Colors.black.withValues(alpha: 0.50);
    final fullPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final framePath = Path()..addRRect(frameRect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, fullPath, framePath),
      dimPaint,
    );

    // White frame border
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(frameRect, borderPaint);

    // Corner markers
    _drawCorners(canvas, left, top, frameW, frameH);
  }

  void _drawCorners(Canvas canvas, double l, double t, double w, double h) {
    const double cLen = 22;
    const double r = 12.0;
    final paint = Paint()
      ..color = AppColors.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final corners = [
      // top-left
      [Offset(l + r, t), Offset(l + r + cLen, t)],
      [Offset(l, t + r), Offset(l, t + r + cLen)],
      // top-right
      [Offset(l + w - r, t), Offset(l + w - r - cLen, t)],
      [Offset(l + w, t + r), Offset(l + w, t + r + cLen)],
      // bottom-left
      [Offset(l + r, t + h), Offset(l + r + cLen, t + h)],
      [Offset(l, t + h - r), Offset(l, t + h - r - cLen)],
      // bottom-right
      [Offset(l + w - r, t + h), Offset(l + w - r - cLen, t + h)],
      [Offset(l + w, t + h - r), Offset(l + w, t + h - r - cLen)],
    ];

    for (final c in corners) {
      canvas.drawLine(c[0], c[1], paint);
    }
    // arc corners
    _drawCornerArc(canvas, paint, l, t, r, math.pi, true);
    _drawCornerArc(canvas, paint, l + w - r * 2, t, r, math.pi * 1.5, true);
    _drawCornerArc(canvas, paint, l, t + h - r * 2, r, math.pi * 0.5, true);
    _drawCornerArc(canvas, paint, l + w - r * 2, t + h - r * 2, r, 0, true);
  }

  void _drawCornerArc(Canvas canvas, Paint paint, double x, double y, double r,
      double startAngle, bool clockwise) {
    canvas.drawArc(
      Rect.fromLTWH(x, y, r * 2, r * 2),
      startAngle,
      math.pi / 2 * (clockwise ? 1 : -1),
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

enum _ScanState { preview, analyzing, found, notFound }

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

class _ScanLimitWarning extends StatelessWidget {
  final int remaining;
  final VoidCallback onUpgrade;
  const _ScanLimitWarning({required this.remaining, required this.onUpgrade});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
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
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
