import '../l10n/app_localizations.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';
import 'support_page.dart';
import 'home_page_simple.dart';
import 'card_list_page.dart';
import 'catalog_page.dart';
import 'album_deck_page.dart';
import 'news_page.dart';
import 'stats_page.dart';
import 'settings_page.dart';
import 'login_page.dart';
import 'profile_page.dart';
import '../services/auth_service.dart';
import '../services/catalog_download_service.dart';
import '../services/data_repository.dart';
import '../services/notification_service.dart';
import '../services/review_service.dart';
import '../services/sync_service.dart';
import '../services/update_service.dart';
import '../services/xp_service.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/update_dialog.dart';
import '../widgets/user_avatar_widget.dart';
import 'notifications_page.dart';
import 'card_scanner_page.dart';
import 'wishlist_page.dart';
import '../services/price_alert_service.dart';
import 'tutorial_page.dart';
import 'pro_page.dart';
import '../widgets/pro_promo_sheet.dart';
import '../services/subscription_service.dart' show SubscriptionService;

/// Layout principale con barra di navigazione persistente
class MainLayout extends StatefulWidget {
  final int initialIndex;
  final String? collectionKey;
  final String? collectionName;
  final String? updateNotification;
  final bool showTutorial;

  const MainLayout({
    super.key,
    this.initialIndex = 0,
    this.collectionKey,
    this.collectionName,
    this.updateNotification,
    this.showTutorial = false,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> with WidgetsBindingObserver {
  late int _currentIndex;
  String? _currentCollectionKey;
  String? _currentCollectionName;
  bool _isPro = false;
  int _unreadCount = 0;
  final AuthService _authService = AuthService();
  final DataRepository _repo = DataRepository();
  User? _currentUser;
  StreamSubscription<int>? _levelUpSub;
  StreamSubscription<String>? _remoteSub;
  int _avatarVersion = 0;

  // Catalog update state
  bool _hasPendingCatalogUpdate = false;
  List<Map<String, dynamic>> _pendingUpdates = [];
  OverlayEntry? _popoverEntry;

  /// Il download non è più di proprietà di questa pagina: lo possiede
  /// [CatalogDownloadService], che vive quanto l'app. Qui si tiene solo
  /// l'ultimo stato ricevuto, e all'`initState` si riparte da quello corrente —
  /// così tornare in home o cambiare collezione non fa più "sparire" un
  /// download che in realtà stava continuando a girare.
  CatalogDownloadState _dl = CatalogDownloadService().state;
  StreamSubscription<CatalogDownloadState>? _dlSub;
  StreamSubscription<CatalogDownloadOutcome>? _dlOutcomeSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentIndex = widget.initialIndex;
    _currentCollectionKey = widget.collectionKey;
    _currentCollectionName = widget.collectionName;
    _currentUser = FirebaseAuth.instance.currentUser;
    _checkUnreadNotifications();
    SubscriptionService().currentUserHasPro().then((v) { if (mounted) setState(() => _isPro = v); });
    _levelUpSub = XpService().onLevelUp.listen(_onLevelUp);
    _remoteSub = SyncService().onRemoteChange.listen((event) {
      if (event == 'catalog_update_pending' && mounted) _loadPersistedPendingUpdates();
    });
    // Ci si riaggancia a un download già in corso invece di ignorarlo: questa
    // pagina viene ricostruita a ogni uscita/rientro in una collezione.
    _dlSub = CatalogDownloadService().onStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _dl = state);
      _popoverEntry?.markNeedsBuild();
    });
    _dlOutcomeSub =
        CatalogDownloadService().onFinished.listen(_onDownloadFinished);
    // Defer XP sync and real-time listener to reduce peak memory during startup.
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      XpService().syncFromFirestore();
      SyncService().startListening();
    });
    // Backfill XP for cards added before the XP system existed (one-time, idempotent)
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _repo.backfillXpFromExistingCards().catchError((_) {});
    });
    // Review prompt — shown after 7 days of use, then ogni 30 giorni se non completato
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) ReviewService.maybePrompt(context);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkPendingCatalogNavigation();
      _loadPersistedPendingUpdates();
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) _checkCatalogUpdate();
      if (mounted) _checkForAppUpdate();
    });

    if (widget.updateNotification != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.msgAppUpdated(widget.updateNotification!)),
              duration: const Duration(seconds: 4),
              backgroundColor: Colors.green.shade700,
            ),
          );
        }
      });
    }

    if (widget.showTutorial) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(const Duration(milliseconds: 800));
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TutorialPage()),
        );
      });
    }

    // Popup promozionale Pro — mostrato ad ogni avvio per utenti non-Pro
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(seconds: 6));
      if (!mounted) return;
      final isPro = await SubscriptionService().currentUserHasPro();
      if (!mounted || isPro) return;
      showProPromoSheet(context);
    });
  }


  @override
  void dispose() {
    _popoverEntry?.remove();
    _popoverEntry = null;
    _levelUpSub?.cancel();
    _remoteSub?.cancel();
    // Si annulla la sottoscrizione, non il download: quello va avanti nel
    // servizio e la prossima pagina montata lo ritrova.
    _dlSub?.cancel();
    _dlOutcomeSub?.cancel();
    SyncService().stopListening();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onLevelUp(int newLevel) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.emoji_events, color: Colors.black),
            const SizedBox(width: 10),
            Text(
              AppLocalizations.of(context)!.msgLevelUp(newLevel),
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFF9A825),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _flushOnBackground();
    } else if (state == AppLifecycleState.resumed) {
      _loadPersistedPendingUpdates();
      PriceAlertService.checkAlerts();
    }
  }

  static const _collectionNames = {
    'yugioh': 'Yu-Gi-Oh!',
    'pokemon': 'Pokémon',
    'onepiece': 'One Piece TCG',
  };

  Future<void> _checkPendingCatalogNavigation() async {
    final collectionKey = await NotificationService().getPendingCatalogNavigation();
    if (collectionKey == null || !mounted) return;
    await NotificationService().clearPendingCatalogNavigation();
    final name = _collectionNames[collectionKey] ?? collectionKey;
    setState(() {
      _currentCollectionKey = collectionKey;
      _currentCollectionName = name;
      _currentIndex = 2; // CatalogPage tab
    });
  }

  Future<void> _flushOnBackground() async {
    try {
      await _repo.fullSync();
    } catch (_) { // ignore: empty_catches
      // Sync best-effort: se fallisce viene ritentata all'apertura successiva
    }
  }

  void _onNavTap(int index) {
    // In collection mode, index 0 = Home (exit collection)
    if (_currentCollectionKey != null && index == 0) {
      _exitCollection();
    } else {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  void _onCollectionSelected(String key, String name) {
    setState(() {
      _currentCollectionKey = key;
      _currentCollectionName = name;
      _currentIndex = 1;
    });
  }

  void _exitCollection() {
    setState(() {
      _currentCollectionKey = null;
      _currentCollectionName = null;
      _currentIndex = 0;
    });
  }

  Future<void> _logout() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _checkUnreadNotifications() async {
    final count = await unreadNotificationCount();
    if (mounted) setState(() => _unreadCount = count);
  }

  /// Ritorna true se è stato mostrato il dialog di aggiornamento.
  Future<bool> _checkForAppUpdate({bool force = false}) async {
    final info = await UpdateService.checkForUpdate(force: force);
    if (info == null || !mounted) return false;
    await showUpdateDialog(context, info);
    return true;
  }

  static const _kCatalogCheckedAtKey = 'catalog_update_checked_at';
  static const _kCatalogCheckTtl = Duration(hours: 1);

  void _loadPersistedPendingUpdates() async {
    final prefs = await SharedPreferences.getInstance();
    final updates = DataRepository.loadPendingCatalogUpdatesFromPrefs(prefs);
    if (updates.isEmpty) {
      if (!mounted) return;
      setState(() {
        _pendingUpdates = updates;
        _hasPendingCatalogUpdate = false;
      });
      return;
    }

    // Re-check which catalogs the user actually has active/unlocked right now —
    // persisted entries can go stale (e.g. a catalog was unlocked when the
    // update was saved but isn't anymore) and must not be offered for download.
    final unlockedKeys =
        (await _repo.getCollections()).where((c) => c.isUnlocked).map((c) => c.key).toSet();
    final active = updates.where((u) => unlockedKeys.contains(u['collectionKey'])).toList();
    if (active.length != updates.length) {
      await _repo.replacePendingCatalogUpdates(active);
    }

    if (!mounted) return;
    setState(() {
      _pendingUpdates = active;
      _hasPendingCatalogUpdate = active.isNotEmpty;
    });
  }

  Future<void> _checkCatalogUpdate({bool force = false}) async {
    // Se c'è già un pending persistito, non serve ricontrollare
    if (!force && _hasPendingCatalogUpdate) return;
    try {
      if (!force) {
        final prefs = await SharedPreferences.getInstance();
        final lastChecked = prefs.getString(_kCatalogCheckedAtKey);
        if (lastChecked != null) {
          final last = DateTime.tryParse(lastChecked);
          if (last != null && DateTime.now().difference(last) < _kCatalogCheckTtl) return;
        }
        await prefs.setString(_kCatalogCheckedAtKey, DateTime.now().toIso8601String());
      }
      final updates = await _repo.checkAllUnlockedCatalogUpdates();
      if (!mounted || updates.isEmpty) return;
      // Persiste ogni update in SharedPreferences (sopravvive a navigazione e resume)
      for (final update in updates) {
        await _repo.savePendingCatalogUpdate(
          update['collectionKey'] as String, update,
        );
      }
      setState(() {
        _pendingUpdates = updates;
        _hasPendingCatalogUpdate = true;
      });
      await setPendingUpdatesCount(updates.length);
      await detectAndSaveNotifications();
      if (mounted) _checkUnreadNotifications();
    } catch (_) {}
  }

  /// Etichette della notifica, già localizzate: il servizio non ha un
  /// `BuildContext` e nella fase con foreground service girerà in un isolate
  /// separato, dove non ce n'è proprio uno.
  CatalogDownloadLabels _downloadLabels(AppLocalizations l10n, String operation) =>
      CatalogDownloadLabels(
        notificationTitle: l10n.downloadTitle,
        starting: l10n.downloadStarting,
        operationName: operation,
        perCatalog: l10n.downloadCollectionProgress,
        perCatalogPct: l10n.downloadCollectionProgressPct,
        singlePct: l10n.downloadProgressPct,
      );

  Future<void> _startCatalogDownload() async {
    final updates = List<Map<String, dynamic>>.from(_pendingUpdates);
    if (updates.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _hasPendingCatalogUpdate = false);
    await CatalogDownloadService().start(
      updates: updates,
      labels: _downloadLabels(l10n, l10n.downloadCatalog),
    );
  }

  void _startRestoreDownload(String collectionKey) {
    if (_dl.isRunning) return;
    final keys = collectionKey == 'all'
        ? (_pendingUpdates.isNotEmpty
            ? _pendingUpdates.map((u) => u['collectionKey'] as String).toList()
            : ['yugioh', 'pokemon', 'onepiece'])
        : [collectionKey];

    final l10n = AppLocalizations.of(context)!;
    CatalogDownloadService().start(
      updates: [
        for (final key in keys)
          {'collectionKey': key, 'collectionName': _collectionNames[key] ?? key},
      ],
      labels: _downloadLabels(l10n, l10n.downloadRestoreCatalog),
      isRestore: true,
    );
  }

  /// Applica alla UI un esito arrivato dal servizio: snackbar di riepilogo e
  /// pulizia della lista di aggiornamenti in sospeso.
  void _onDownloadFinished(CatalogDownloadOutcome outcome) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    if (outcome.successCount > 0) {
      setState(() {
        _pendingUpdates = [];
        _hasPendingCatalogUpdate = false;
      });
    }

    for (final entry in outcome.failures.entries) {
      messenger.showSnackBar(SnackBar(
        content: Text(outcome.isRestore
            ? l10n.msgErrorRestoreCollection(entry.key, entry.value)
            : l10n.msgErrorUpdateCollection(entry.key, entry.value)),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 6),
      ));
    }

    if (outcome.successCount > 0) {
      messenger.showSnackBar(SnackBar(
        content: Text(outcome.isRestore
            ? l10n.msgCatalogRestoredSuccess
            : l10n.msgCatalogUpdatedSuccess),
        backgroundColor: Colors.green,
      ));
    } else if (outcome.isRestore && outcome.hasFailures) {
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.msgCatalogRestoreFailed(outcome.failures.values.first)),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 8),
      ));
    }
  }

  void _toggleDownloadPopover() {
    if (_popoverEntry != null) {
      _popoverEntry!.remove();
      _popoverEntry = null;
      return;
    }

    final overlayState = Overlay.of(context);
    final topPadding = MediaQuery.of(context).padding.top;

    _popoverEntry = OverlayEntry(builder: (_) {
      final progress      = _dl.progress;
      final name          = _dl.currentName;
      final idx           = _dl.currentIndex;
      final total         = _dl.total > 0
          ? _dl.total
          : (_pendingUpdates.isNotEmpty ? _pendingUpdates.length : idx);
      final collectionKey = _dl.currentKey;
      final phase         = _dl.phase;

      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          _popoverEntry?.remove();
          _popoverEntry = null;
        },
        child: Stack(
          children: [
            Positioned(
              top: topPadding + kToolbarHeight + 6,
              right: 8,
              child: GestureDetector(
                onTap: () {},
                child: _DownloadPopoverCard(
                  progress: progress,
                  name: name,
                  index: idx,
                  total: total,
                  collectionKey: collectionKey,
                  phase: phase,
                ),
              ),
            ),
          ],
        ),
      );
    });

    overlayState.insert(_popoverEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final bool inCollection = _currentCollectionKey != null;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isWide = screenWidth > 700;

    // IndexedStack keeps all in-collection pages alive so switching tab is instant (no reload)
    final Widget currentPage;

    if (inCollection) {
      // Lo scanner (indice 4) sta FUORI dall'IndexedStack di proposito: quello
      // costruisce tutti i figli subito e li tiene vivi, e CardScannerPage
      // accende la fotocamera in initState. Dentro lo stack la camera
      // resterebbe aperta per tutta la permanenza nella collezione anche senza
      // mai aprire la scheda. Qui viene montata solo quando la scheda è attiva
      // e smontata (con dispose del controller) appena la lasci, mentre le
      // altre tre schede restano vive dietro l'Offstage.
      final bool onScanner = _currentIndex == 4;
      currentPage = Stack(
        // expand: entrambi i figli sono pagine intere e devono ricevere vincoli
        // stretti, altrimenti con il fit loose di default si dimensionerebbero
        // sul contenuto invece che sullo spazio disponibile.
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: onScanner,
            child: IndexedStack(
              key: ValueKey(_currentCollectionKey),
              index: (_currentIndex - 1).clamp(0, 2),
              children: [
                CardListPage(
                  collectionKey: _currentCollectionKey!,
                  collectionName: _currentCollectionName!,
                  showOwnBannerAd: false,
                ),
                CatalogPage(
                  collectionKey: _currentCollectionKey!,
                  collectionName: _currentCollectionName!,
                ),
                AlbumDeckPage(
                  collectionKey: _currentCollectionKey!,
                  collectionName: _currentCollectionName!,
                ),
              ],
            ),
          ),
          if (onScanner)
            CardScannerPage(
              key: ValueKey('scanner-$_currentCollectionKey'),
              collectionKey: _currentCollectionKey,
              collectionName: _currentCollectionName,
              embedded: true,
            ),
        ],
      );
    } else {
      currentPage = HomePageSimple(
        onCollectionSelected: _onCollectionSelected,
        onCatalogRefreshNeeded: () async {
          // Piccolo delay affinché il DB registri la nuova collezione sbloccata
          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) _checkCatalogUpdate();
        },
      );
    }

    final l10n = AppLocalizations.of(context)!;
    String appBarTitle;
    if (!inCollection) {
      appBarTitle = 'Deck Master';
    } else {
      // Le schede "Le mie carte", "Catalogo" e "Raccolta" non mostrano il
      // titolo in alto (richiesta esplicita): l'AppBar resta senza scritta.
      final titles = [l10n.navHome, '', '', '', l10n.cardScannerTitle];
      appBarTitle = _currentIndex < titles.length ? titles[_currentIndex] : _currentCollectionName ?? 'Deck Master';
    }

    // On wide screens wrap content with a max-width so it doesn't stretch edge-to-edge
    Widget pageBody = isWide
        ? Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: currentPage,
            ),
          )
        : currentPage;

    return PopScope(
      // Quando si è dentro una collezione, il tasto back (gesture o 3-pulsanti)
      // torna alla home invece di chiudere l'app.
      canPop: !inCollection,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && inCollection) _exitCollection();
      },
      child: Scaffold(
      appBar: AppBar(
        leading: inCollection
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: l10n.tooltipBackToHome,
                onPressed: _exitCollection,
              )
            : null,
        title: Text(appBarTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (inCollection)
            IconButton(
              icon: const Icon(Icons.newspaper_outlined),
              tooltip: l10n.navNews,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NewsPage()),
              ),
            ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                tooltip: l10n.tooltipNotifications,
                onPressed: () async {
                  final result = await Navigator.push<Map<String, dynamic>>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NotificationsPage(
                        pendingCatalogUpdates: _pendingUpdates,
                      ),
                    ),
                  );
                  if (!mounted) return;
                  if (result?['action'] == 'download') {
                    _startCatalogDownload();
                  } else if (result?['action'] == 'later') {
                    setState(() => _hasPendingCatalogUpdate = true);
                  }
                  _checkUnreadNotifications();
                },
              ),
              if (_unreadCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        _unreadCount > 99 ? '99+' : '$_unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_dl.isRunning)
            GestureDetector(
              onTap: _toggleDownloadPopover,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: _dl.progress,
                        strokeWidth: 3,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                      ),
                      Text(
                        _dl.progress != null
                            ? '${(_dl.progress! * 100).toInt()}%'
                            : '···',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_hasPendingCatalogUpdate)
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.cloud_download_outlined),
                  tooltip: l10n.tooltipCatalogUpdate,
                  onPressed: _startCatalogDownload,
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: l10n.tooltipStats,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => StatsPage(
                  collectionKey: _currentCollectionKey,
                  collectionName: _currentCollectionName,
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: l10n.tooltipUserMenu,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            menuPadding: const EdgeInsets.symmetric(vertical: 6),
            onSelected: (value) async {
              if (value == 'profile') {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
                if (mounted) setState(() => _avatarVersion++);
              } else if (value == 'wishlist') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const WishlistPage()));
              } else if (value == 'check_update') {
                final messenger = ScaffoldMessenger.of(context);
                final shown = await _checkForAppUpdate(force: true);
                if (!shown && mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.msgAlreadyLatestVersion)),
                  );
                }
              } else if (value == 'settings') {
                final result = await Navigator.push<Map<String, dynamic>>(
                  context,
                  MaterialPageRoute(builder: (_) => SettingsPage(collectionKey: _currentCollectionKey)),
                );
                if (mounted && result?['restore'] != null) {
                  _startRestoreDownload(result!['restore'] as String);
                }
              } else if (value == 'support') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportPage()));
              } else if (value == 'pro') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProPage()));
              } else if (value == 'logout') {
                _logout();
              }
            },
            itemBuilder: (_) => [
              if (!_isPro)
                PopupMenuItem(
                  value: 'pro',
                  height: 36,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.workspace_premium, size: 26, color: AppColors.gold),
                    title: const Text('Diventa Pro', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              PopupMenuItem(
                value: 'profile',
                height: 36,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.manage_accounts_outlined, size: 26),
                  title: Text(l10n.menuProfile),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'wishlist',
                height: 36,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.favorite_border, size: 26),
                  title: Text(l10n.menuWishlist),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                height: 36,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.settings, size: 26),
                  title: Text(l10n.menuSettings),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'check_update',
                height: 36,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.system_update_alt_rounded, size: 26),
                  title: Text(l10n.menuCheckUpdates),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'support',
                height: 36,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.support_agent, size: 26),
                  title: Text(l10n.menuSupport),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'logout',
                height: 36,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.logout, color: Colors.red, size: 26),
                  title: Text(l10n.btnLogout, style: const TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: UserAvatarWidget(
                key: ValueKey(_avatarVersion),
                radius: 18,
                showLevelBadge: true,
                photoUrl: _currentUser?.photoURL,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          children: [
            Expanded(child: pageBody),
            if (!kIsWeb) const BannerAdWidget(),
          ],
        ),
      ),
      // Un solo design di navigazione (bottom nav) su tutte le dimensioni di schermo.
      bottomNavigationBar: inCollection
          ? BottomNavigationBar(
              currentIndex: _currentIndex,
              type: BottomNavigationBarType.fixed,
              backgroundColor: AppColors.bgMedium,
              selectedItemColor: AppColors.gold,
              unselectedItemColor: AppColors.textHint,
              items: [
                BottomNavigationBarItem(icon: const Icon(Icons.home), label: l10n.navHome),
                BottomNavigationBarItem(icon: const Icon(Icons.style), label: l10n.navCards),
                BottomNavigationBarItem(icon: const Icon(Icons.search), label: l10n.navCatalog),
                BottomNavigationBarItem(icon: const Icon(Icons.book), label: l10n.navCollection),
                BottomNavigationBarItem(icon: const Icon(Icons.document_scanner_outlined), label: l10n.navScan),
              ],
              onTap: _onNavTap,
            )
          : null,
      ),
    );
  }
}

// ─── Download theming ─────────────────────────────────────────────────────────

class _CollectionTheme {
  final Color accent;
  final IconData icon;
  final String Function(AppLocalizations) connecting;
  final String Function(AppLocalizations) downloading;
  final String Function(AppLocalizations) saving;
  const _CollectionTheme({
    required this.accent,
    required this.icon,
    required this.connecting,
    required this.downloading,
    required this.saving,
  });
}

const _kCollectionThemes = <String, _CollectionTheme>{
  'yugioh': _CollectionTheme(
    accent: Color(0xFF9B59B6),
    icon: Icons.auto_fix_high_rounded,
    connecting: _yugiohConnecting,
    downloading: _yugiohDownloading,
    saving: _yugiohSaving,
  ),
  'pokemon': _CollectionTheme(
    accent: Color(0xFFFFCB05),
    icon: Icons.catching_pokemon_rounded,
    connecting: _pokemonConnecting,
    downloading: _pokemonDownloading,
    saving: _pokemonSaving,
  ),
  'onepiece': _CollectionTheme(
    accent: Color(0xFFE74C3C),
    icon: Icons.sailing_rounded,
    connecting: _onepieceConnecting,
    downloading: _onepieceDownloading,
    saving: _onepieceSaving,
  ),
};

String _yugiohConnecting(AppLocalizations l10n) => l10n.downloadYugiohConnecting;
String _yugiohDownloading(AppLocalizations l10n) => l10n.downloadYugiohDownloading;
String _yugiohSaving(AppLocalizations l10n) => l10n.downloadYugiohSaving;
String _pokemonConnecting(AppLocalizations l10n) => l10n.downloadPokemonConnecting;
String _pokemonDownloading(AppLocalizations l10n) => l10n.downloadPokemonDownloading;
String _pokemonSaving(AppLocalizations l10n) => l10n.downloadPokemonSaving;
String _onepieceConnecting(AppLocalizations l10n) => l10n.downloadOnepieceConnecting;
String _onepieceDownloading(AppLocalizations l10n) => l10n.downloadOnepieceDownloading;
String _onepieceSaving(AppLocalizations l10n) => l10n.downloadOnepieceSaving;

// ─── Download popover card ────────────────────────────────────────────────────

class _DownloadPopoverCard extends StatelessWidget {
  final double? progress;
  final String? name;
  final int index;
  final int total;
  final String? collectionKey;
  final CatalogDownloadPhase phase;

  const _DownloadPopoverCard({
    required this.progress,
    required this.name,
    required this.index,
    required this.total,
    required this.collectionKey,
    required this.phase,
  });

  @override
  Widget build(BuildContext context) {
    final theme = collectionKey != null ? _kCollectionThemes[collectionKey] : null;
    final accent = theme?.accent ?? Colors.blue;
    final icon   = theme?.icon   ?? Icons.download_rounded;

    final pct = progress != null ? '${(progress! * 100).toInt()}%' : '···';

    final l10n = AppLocalizations.of(context)!;
    final phaseMessage = theme == null
        ? switch (phase) {
            CatalogDownloadPhase.connecting  => l10n.downloadPhaseConnecting,
            CatalogDownloadPhase.downloading => l10n.downloadPhaseDownloading,
            CatalogDownloadPhase.saving      => l10n.downloadPhaseSaving,
          }
        : switch (phase) {
            CatalogDownloadPhase.connecting  => theme.connecting(l10n),
            CatalogDownloadPhase.downloading => theme.downloading(l10n),
            CatalogDownloadPhase.saving      => theme.saving(l10n),
          };

    final multiCollection = index > 0 && total > 1;

    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -7,
            right: 16,
            child: CustomPaint(
              size: const Size(14, 7),
              painter: _ArrowPainter(AppColors.bgMedium),
            ),
          ),
          Container(
            width: 248,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: AppColors.bgMedium,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.25), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: accent.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: accent, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        multiCollection ? '$index/$total · ${name ?? ''}' : (name ?? 'Catalogo'),
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      pct,
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  phaseMessage,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    backgroundColor: AppColors.bgDark,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.popoverTapToClose,
                  style: const TextStyle(color: AppColors.textHint, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  final Color color;
  const _ArrowPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color;
}
