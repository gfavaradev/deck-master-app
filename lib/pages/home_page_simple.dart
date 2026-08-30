import 'dart:async';

import '../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../models/collection_model.dart';
import '../services/ad_service.dart';
import '../services/data_repository.dart';
import '../services/subscription_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_dialog.dart';
import 'pro_page.dart';

/// Home page semplificata - mostra solo la griglia delle collezioni
class HomePageSimple extends StatefulWidget {
  final Function(String collectionKey, String collectionName) onCollectionSelected;
  /// Chiamata dopo aver sbloccato una nuova collezione: lascia che MainLayout
  /// gestisca il check/download catalogo con il suo indicatore circolare.
  final VoidCallback? onCatalogRefreshNeeded;

  const HomePageSimple({
    super.key,
    required this.onCollectionSelected,
    this.onCatalogRefreshNeeded,
  });

  @override
  State<HomePageSimple> createState() => _HomePageSimpleState();
}

class _HomePageSimpleState extends State<HomePageSimple> {
  static const _catalogAvailable = {
    'yugioh', 'onepiece', 'pokemon', 'magic',
    'digimon', 'lorcana', 'flesh-and-blood', 'vanguard',
    'dragon-ball-super', 'star-wars', 'riftbound', 'gundam', 'union-arena',
  };

  final DataRepository _repo = DataRepository();
  List<CollectionModel> _unlockedCollections = [];
  List<CollectionModel> _availableCollections = [];
  bool _isLoading = true;

  // ── Rewarded ad & Pro ────────────────────────────────────────────────────
  bool _isPro = false;
  RewardedAd? _rewardedAd;
  // Notifier invece di un bool: il dialog ci si aggancia da sé con un
  // ValueListenableBuilder. Prima la pagina teneva il `setState` dello
  // StatefulBuilder del dialog (`_dialogSetState`) e lo richiamava a mano, ma
  // quel riferimento sopravviveva alla chiusura del dialog: il timer di retry
  // che scattava subito dopo chiamava il setState di uno State già smontato,
  // "Null check operator used on a null value" — visto in produzione su
  // 1.3.11 vc118.
  final ValueNotifier<bool> _adLoading = ValueNotifier(false);
  // Backoff del preload: un fallimento non deve lasciare _rewardedAd a null
  // fino al tap dell'utente, altrimenti il primo tentativo mostra sempre
  // "Video non disponibile".
  int _adRetries = 0;
  Timer? _adRetryTimer;
  static const _maxAdRetries = 4;

  @override
  void initState() {
    super.initState();
    _loadCollections();
    _loadProAndAd();
  }

  @override
  void dispose() {
    _adRetryTimer?.cancel();
    _rewardedAd?.dispose();
    _adLoading.dispose();
    super.dispose();
  }

  Future<void> _loadProAndAd() async {
    final isPro = await SubscriptionService().currentUserHasPro();
    if (!mounted) return;
    setState(() => _isPro = isPro);
    if (!isPro && AdService.isSupportedPlatform) _preloadRewardedAd();
  }

  void _preloadRewardedAd() {
    // Guardia single-flight. I quattro punti che chiamano questo metodo possono
    // sovrapporsi (preload iniziale, tap a vuoto, chiusura dell'ad, errore di
    // show): con due caricamenti in volo il secondo onLoaded sovrascriveva
    // _rewardedAd senza fare dispose del primo, perdendo l'istanza nativa.
    if (_adLoading.value || _rewardedAd != null) return;
    // La guardia sta qui e non solo nei quattro chiamanti: dopo il dispose il
    // notifier è chiuso e scrivergli dentro lancerebbe.
    if (!mounted) return;

    _adRetryTimer?.cancel();
    _adLoading.value = true;
    AdService.loadRewardedAd(
      onLoaded: (ad) {
        if (!mounted) { ad.dispose(); return; }
        _adRetries = 0;
        setState(() => _rewardedAd = ad);
        _adLoading.value = false;
      },
      onFailed: (_) {
        if (!mounted) return;
        setState(() => _rewardedAd = null);
        _adLoading.value = false;
        _scheduleAdRetry();
      },
    );
  }

  /// Riprova il preload con backoff esponenziale: 2s, 4s, 8s, 16s.
  /// L'errore vero è già loggato da AdService.loadRewardedAd.
  void _scheduleAdRetry() {
    if (_adRetries >= _maxAdRetries) return;
    final delay = Duration(seconds: 2 << _adRetries);
    _adRetries++;
    _adRetryTimer?.cancel();
    _adRetryTimer = Timer(delay, () {
      if (mounted && !_isPro) _preloadRewardedAd();
    });
  }

  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadCollections() async {
    try {
      final all = await _repo.getCollections();
      if (mounted) {
        setState(() {
          _unlockedCollections = all.where((c) => c.isUnlocked).toList();
          final locked = all.where((c) => !c.isUnlocked).toList();
          locked.sort((a, b) {
            final aHas = _catalogAvailable.contains(a.key) ? 0 : 1;
            final bHas = _catalogAvailable.contains(b.key) ? 0 : 1;
            return aHas.compareTo(bHas);
          });
          _availableCollections = locked;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _unlock(CollectionModel collection) async {
    await _repo.unlockCollection(collection.key);
    await _loadCollections();
    widget.onCatalogRefreshNeeded?.call();
  }

  bool get _isFirstCollection => _unlockedCollections.isEmpty;

  void _handleUnlockTap(CollectionModel collection) {
    // Prima collezione o utente Pro → sblocco diretto
    if (_isFirstCollection || _isPro) {
      _showFreeUnlockDialog(collection);
      return;
    }
    // Free + 2ª+ collezione → rewarded ad
    _showRewardedUnlockDialog(collection);
  }

  void _showFreeUnlockDialog(CollectionModel collection) {
    final l10n = AppLocalizations.of(context)!;
    final isFirst = _isFirstCollection;
    showDialog<bool>(
      context: context,
      builder: (_) => AppConfirmDialog(
        title: l10n.homeUnlockTitle(collection.name),
        icon: isFirst ? Icons.lock_open_outlined : Icons.workspace_premium,
        iconColor: isFirst ? AppColors.blue : AppColors.gold,
        message: isFirst
            ? l10n.homeUnlockFirstMsg(collection.name)
            : l10n.homeUnlockProMsg,
        confirmLabel: l10n.homeUnlockBtn,
        confirmColor: isFirst ? AppColors.blue : AppColors.gold,
      ),
    ).then((confirmed) {
      if (confirmed == true) _unlock(collection);
    });
  }

  void _showRewardedUnlockDialog(CollectionModel collection) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      // Il dialog si aggancia al notifier e si ridisegna da sé quando il
      // preload cambia stato. Prima era uno StatefulBuilder il cui setState
      // veniva salvato nella pagina e richiamato a mano: quel riferimento
      // restava valido anche dopo la chiusura del dialog.
      builder: (ctx) => ValueListenableBuilder<bool>(
        valueListenable: _adLoading,
        builder: (ctx, loading, _) {
          return AppDialog(
            title: l10n.homeWatchVideoTitle(collection.name),
            icon: Icons.ondemand_video_outlined,
            iconColor: AppColors.blue,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.homeWatchVideoMsg,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.glowGold,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.workspace_premium, color: AppColors.gold, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.homeWatchVideoProNote,
                          style: const TextStyle(color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const ProPage()));
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.gold,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(l10n.btnGoPro, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: appDialogCancelStyle(),
                child: Text(l10n.btnCancel),
              ),
              FilledButton.icon(
                icon: loading
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.play_circle_outline, size: 18),
                label: Text(l10n.homeWatchVideoBtn),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: loading
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _playRewardedAdFor(collection);
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  void _playRewardedAdFor(CollectionModel collection) {
    final ad = _rewardedAd;
    if (ad == null) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.msgVideoNotAvailable),
            duration: const Duration(seconds: 3),
          ),
        );
        // Il tap è un'azione esplicita dell'utente: fa ripartire il ciclo di
        // backoff anche se i tentativi automatici erano già esauriti.
        _adRetries = 0;
        _preloadRewardedAd();
      }
      return;
    }

    // Svuota il riferimento subito: non usare la stessa istanza due volte
    setState(() => _rewardedAd = null);

    AdService.showRewardedAd(
      ad,
      onRewarded: () {
        // Ricompensa guadagnata → sblocca la collezione
        _unlock(collection);
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.msgCollectionUnlocked(collection.name)),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      onDismissed: () {
        // Ricarica sempre il prossimo ad dopo la chiusura
        if (mounted && !_isPro) _preloadRewardedAd();
      },
      onFailed: (error) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.msgVideoError)),
          );
          _preloadRewardedAd();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final l10n = AppLocalizations.of(context)!;
    final double width = MediaQuery.of(context).size.width;
    final int crossAxisCount = width > 1200 ? 6 : (width > 900 ? 5 : (width > 600 ? 4 : 2));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_unlockedCollections.isNotEmpty) ...[
            _buildSectionTitle(l10n.homeMyCollections),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.1,
              ),
              itemCount: _unlockedCollections.length,
              itemBuilder: (context, index) => _buildCollectionTile(
                _unlockedCollections[index], true,
              ),
            ),
            const SizedBox(height: 32),
          ],
          if (_availableCollections.isNotEmpty) ...[
            _buildSectionTitle(l10n.homeAvailableCollections),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.1,
              ),
              itemCount: _availableCollections.length,
              itemBuilder: (context, index) => _buildCollectionTile(
                _availableCollections[index], false,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.gold, Color(0xFFF5D76E)],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionTile(CollectionModel collection, bool isUnlocked) {
    final bool hasCatalog = _catalogAvailable.contains(collection.key);
    final Color color = AppColors.forCollection(collection.key);
    final String logoUrl = _getCollectionLogoUrl(collection.key);

    // Sfondo neutro cremoso uniforme per tutte le card
    const Color cardBg = Color(0xFFE8DFCC);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (!hasCatalog) return;
          if (isUnlocked) {
            widget.onCollectionSelected(collection.key, collection.name);
          } else {
            _handleUnlockTap(collection);
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: cardBg,
            border: Border.all(
              color: isUnlocked
                  ? color.withValues(alpha: 0.70)
                  : color.withValues(alpha: 0.22),
              width: isUnlocked ? 1.5 : 1.0,
            ),
            boxShadow: isUnlocked
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.28),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Opacity(
                    opacity: isUnlocked ? 1.0 : 0.38,
                    child: Image.asset(
                      logoUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, e) => Icon(
                        Icons.style,
                        size: 40,
                        color: isUnlocked ? color : AppColors.textHint,
                      ),
                    ),
                  ),
                ),
              ),
              if (!isUnlocked && hasCatalog)
                Positioned(
                  top: 7,
                  right: 7,
                  child: _UnlockBadge(
                    isFree: _isFirstCollection,
                    isPro: _isPro,
                    color: color,
                  ),
                ),
              if (!hasCatalog)
                Positioned(
                  bottom: 6,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Builder(
                      builder: (context) {
                        final l10n = AppLocalizations.of(context)!;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.60),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            l10n.homeComingSoon,
                            style: const TextStyle(
                              color: AppColors.textHint,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _getCollectionLogoUrl(String key) => switch (key) {
    'yugioh'           => 'assets/images/collections/yugioh-logo.png',
    'pokemon'          => 'assets/images/collections/pokemon-logo.png',
    'magic'            => 'assets/images/collections/magic-logo.png',
    'onepiece'         => 'assets/images/collections/one-piece-logo.webp',
    'digimon'          => 'assets/images/collections/digimon-logo.png',
    'dragon-ball-super'=> 'assets/images/collections/dragon-ball-super-logo.png',
    'lorcana'          => 'assets/images/collections/lorcana-logo.png',
    'flesh-and-blood'  => 'assets/images/collections/flesh-and-blood-logo.png',
    'vanguard'         => 'assets/images/collections/vanguard-logo.png',
    'star-wars'        => 'assets/images/collections/star-wars-logo.png',
    'riftbound'        => 'assets/images/collections/riftbound-logo.png',
    'gundam'           => 'assets/images/collections/gundam-logo.png',
    'union-arena'      => 'assets/images/collections/union-arena-logo.png',
    _                  => 'assets/images/collections/yugioh-logo.png',
  };
}

// ─── Unlock badge ─────────────────────────────────────────────────────────────

class _UnlockBadge extends StatelessWidget {
  final bool isFree;
  final bool isPro;
  final Color color;

  const _UnlockBadge({
    required this.isFree,
    required this.isPro,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (isFree) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          l10n.homeUnlockFree,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    if (isPro) {
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.85),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.workspace_premium, size: 11, color: Colors.black87),
      );
    }

    // Free + 2ª+ collezione → richiede video
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.60),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.play_circle_outline, size: 13, color: color.withValues(alpha: 0.9)),
    );
  }
}
