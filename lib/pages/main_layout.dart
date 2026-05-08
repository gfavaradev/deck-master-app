import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';
import 'support_page.dart';
import 'donations_page.dart';
import 'home_page_simple.dart';
import 'card_list_page.dart';
import 'catalog_page.dart';
import 'album_list_page.dart';
import 'deck_list_page.dart';
import 'stats_page.dart';
import 'settings_page.dart';
import 'login_page.dart';
import 'profile_page.dart';
import 'admin_home_page.dart';
import '../services/auth_service.dart';
import '../services/background_download_service.dart';
import '../services/data_repository.dart';
import '../services/notification_service.dart';
import '../services/review_service.dart';
import '../services/sync_service.dart';
import '../services/xp_service.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/user_avatar_widget.dart';
import 'notifications_page.dart';
import 'card_scanner_page.dart';

/// Layout principale con barra di navigazione persistente
class MainLayout extends StatefulWidget {
  final int initialIndex;
  final String? collectionKey;
  final String? collectionName;
  final String? updateNotification;

  const MainLayout({
    super.key,
    this.initialIndex = 0,
    this.collectionKey,
    this.collectionName,
    this.updateNotification,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> with WidgetsBindingObserver {
  late int _currentIndex;
  String? _currentCollectionKey;
  String? _currentCollectionName;
  bool _isAdmin = false;
  int _unreadCount = 0;
  final AuthService _authService = AuthService();
  final DataRepository _repo = DataRepository();
  User? _currentUser;
  StreamSubscription<int>? _levelUpSub;
  StreamSubscription<String>? _remoteSub;
  int _avatarVersion = 0;

  // Catalog update state
  bool _hasPendingCatalogUpdate = false;
  bool _isCatalogDownloading = false;
  double? _catalogDownloadProgress;
  List<Map<String, dynamic>> _pendingUpdates = [];
  String? _currentDownloadingName;
  String? _currentDownloadingKey;
  int _currentDownloadingIndex = 0;
  _DownloadPhase _downloadPhase = _DownloadPhase.connecting;
  OverlayEntry? _popoverEntry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentIndex = widget.initialIndex;
    _currentCollectionKey = widget.collectionKey;
    _currentCollectionName = widget.collectionName;
    _currentUser = FirebaseAuth.instance.currentUser;
    _checkAdminAndNotifications();
    XpService().syncFromFirestore();
    _levelUpSub = XpService().onLevelUp.listen(_onLevelUp);
    SyncService().startListening();
    _remoteSub = SyncService().onRemoteChange.listen((event) {
      if (event == 'catalog_update_pending' && mounted) _loadPersistedPendingUpdates();
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
    });

    if (widget.updateNotification != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('App aggiornata alla versione ${widget.updateNotification}'),
              duration: const Duration(seconds: 4),
              backgroundColor: Colors.green.shade700,
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _popoverEntry?.remove();
    _popoverEntry = null;
    _levelUpSub?.cancel();
    _remoteSub?.cancel();
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
              'Sei salito al livello $newLevel! 🎉',
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
      _currentIndex = 1; // Vai alle carte della collezione
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

  static const _kAdminCachePrefix = 'admin_verified_';
  static const _kAdminCheckedAtPrefix = 'admin_checked_at_';
  // Verifica Firestore solo una volta ogni 24h per ridurre le letture
  static const _kAdminCheckTtl = Duration(hours: 24);

  Future<void> _checkAdminAndNotifications() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final prefs = await SharedPreferences.getInstance();

    // 1. Applica subito il valore cached per evitare flickering.
    final cached = uid != null ? (prefs.getBool('$_kAdminCachePrefix$uid') ?? false) : false;
    if (cached && mounted) setState(() => _isAdmin = true);

    // 2. Se il check Firestore è stato fatto di recente (< 24h), usa la cache.
    if (uid != null) {
      final lastChecked = prefs.getString('$_kAdminCheckedAtPrefix$uid');
      if (lastChecked != null) {
        final last = DateTime.tryParse(lastChecked);
        if (last != null && DateTime.now().difference(last) < _kAdminCheckTtl) {
          final unread = await unreadNotificationCount();
          if (mounted) setState(() { _isAdmin = cached; _unreadCount = unread; });
          return;
        }
      }
    }

    // 3. Verifica Firestore (fonte autorevole) + notifiche in parallelo.
    // null = Firestore non raggiungibile (offline/timeout) → mantieni cache.
    final results = await Future.wait([
      _authService.isCurrentUserAdmin()
          .timeout(const Duration(seconds: 12))
          .then<bool?>((v) => v)
          .catchError((_) => null as bool?),
      unreadNotificationCount().catchError((_) => 0),
    ]);
    if (!mounted) return;
    final bool? firestoreAdmin = results[0] as bool?;
    final int unread = results[1] as int;

    final isAdmin = firestoreAdmin ?? cached; // offline → mantieni ultimo stato noto

    // 4. Persiste ruolo e timestamp SOLO se Firestore ha risposto.
    // Se offline, il timestamp non viene aggiornato così al prossimo avvio
    // ritenterà subito invece di aspettare le 24h.
    if (uid != null && firestoreAdmin != null) {
      if (isAdmin) {
        await prefs.setBool('$_kAdminCachePrefix$uid', true);
      } else {
        await prefs.remove('$_kAdminCachePrefix$uid');
      }
      await prefs.setString('$_kAdminCheckedAtPrefix$uid', DateTime.now().toIso8601String());
    }

    if (mounted) setState(() { _isAdmin = isAdmin; _unreadCount = unread; });
  }

  Future<void> _checkUnreadNotifications() async {
    final count = await unreadNotificationCount();
    if (mounted) setState(() => _unreadCount = count);
  }

  static const _kCatalogCheckedAtKey = 'catalog_update_checked_at';
  static const _kCatalogCheckTtl = Duration(hours: 1);

  void _loadPersistedPendingUpdates() async {
    final prefs = await SharedPreferences.getInstance();
    final updates = DataRepository.loadPendingCatalogUpdatesFromPrefs(prefs);
    if (!mounted) return;
    setState(() {
      _pendingUpdates = updates;
      _hasPendingCatalogUpdate = updates.isNotEmpty;
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

  Future<void> _startCatalogDownload() async {
    final updates = List<Map<String, dynamic>>.from(_pendingUpdates);
    if (updates.isEmpty) return;
    setState(() {
      _isCatalogDownloading = true;
      _hasPendingCatalogUpdate = false;
      _catalogDownloadProgress = null;
    });

    final total = updates.length;
    int successCount = 0;
    try {
      // Avvia il Foreground Service Android (tiene vivo il processo in background)
      await BackgroundDownloadService.startDownload('Catalogo');
      for (int i = 0; i < updates.length; i++) {
        final info = updates[i];
        final key = info['collectionKey'] as String;
        final name = info['collectionName'] as String? ?? key;
        if (mounted) {
          setState(() {
            _currentDownloadingName = name;
            _currentDownloadingKey = key;
            _currentDownloadingIndex = i + 1;
            _downloadPhase = _DownloadPhase.connecting;
          });
          _popoverEntry?.markNeedsBuild();
        }
        BackgroundDownloadService.updateStatus(
          total > 1 ? 'Collezione ${i + 1}/$total: $name' : name,
        );
        try {
          await _repo.downloadCollectionCatalog(
            key,
            updateInfo: info,
            onProgress: (current, colTotal) {
              if (mounted) {
                setState(() {
                  _catalogDownloadProgress = (i + current / colTotal) / total;
                  // Advance to downloading only once; never cycle back
                  if (_downloadPhase == _DownloadPhase.connecting) {
                    _downloadPhase = _DownloadPhase.downloading;
                  }
                });
                _popoverEntry?.markNeedsBuild();
              }
              final pct = colTotal > 0 ? ((current / colTotal) * 100).toInt() : 0;
              BackgroundDownloadService.updateStatus(
                total > 1 ? 'Collezione ${i + 1}/$total: $name ($pct%)' : '$name ($pct%)',
              );
            },
            onSaveProgress: (progress) {
              if (mounted) {
                setState(() {
                  _catalogDownloadProgress = (i + progress) / total;
                  // Switch to saving only near the end to avoid rapid cycling
                  if (_downloadPhase != _DownloadPhase.saving && progress >= 0.85) {
                    _downloadPhase = _DownloadPhase.saving;
                  }
                });
                _popoverEntry?.markNeedsBuild();
              }
            },
          );
          successCount++;
        } catch (e) { // ignore: empty_catches
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Errore aggiornamento ${info['collectionName'] ?? key}: $e')),
            );
          }
        }
      }
    } finally {
      // Ferma sempre il Foreground Service, anche in caso di errore
      await BackgroundDownloadService.stopDownload();
      if (successCount > 0) await _repo.clearPendingCatalogUpdates();
      if (mounted) {
        setState(() {
          _isCatalogDownloading = false;
          _hasPendingCatalogUpdate = false;
          _catalogDownloadProgress = null;
          _currentDownloadingName = null;
          _currentDownloadingKey = null;
          _currentDownloadingIndex = 0;
          _downloadPhase = _DownloadPhase.connecting;
          _pendingUpdates = [];
        });
        if (successCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Catalogo aggiornato con successo!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }

  void _startRestoreDownload(String collectionKey) {
    if (_isCatalogDownloading) return;
    final keys = collectionKey == 'all'
        ? (_pendingUpdates.isNotEmpty
            ? _pendingUpdates.map((u) => u['collectionKey'] as String).toList()
            : ['yugioh', 'pokemon', 'onepiece'])
        : [collectionKey];

    setState(() {
      _isCatalogDownloading = true;
      _catalogDownloadProgress = null;
      _currentDownloadingName = null;
      _currentDownloadingIndex = 0;
    });

    () async {
      final total = keys.length;
      int successCount = 0;
      Object? lastError;
      try {
        await BackgroundDownloadService.startDownload('Ripristino catalogo');
        for (int i = 0; i < keys.length; i++) {
          final key = keys[i];
          final name = switch (key) {
            'yugioh'   => 'Yu-Gi-Oh!',
            'pokemon'  => 'Pokémon',
            'onepiece' => 'One Piece',
            _          => key,
          };
          if (mounted) {
            setState(() {
              _currentDownloadingName = name;
              _currentDownloadingKey = key;
              _currentDownloadingIndex = i + 1;
              _downloadPhase = _DownloadPhase.connecting;
            });
            _popoverEntry?.markNeedsBuild();
          }
          BackgroundDownloadService.updateStatus(total > 1 ? 'Ripristino ${i + 1}/$total: $name' : name);

          void onProg(int cur, int tot) {
            if (mounted) {
              setState(() {
                _catalogDownloadProgress = (i + (tot > 0 ? cur / tot : 0)) / total;
                if (_downloadPhase == _DownloadPhase.connecting) {
                  _downloadPhase = _DownloadPhase.downloading;
                }
              });
              _popoverEntry?.markNeedsBuild();
            }
          }
          void onSave(double p) {
            if (mounted) {
              setState(() {
                _catalogDownloadProgress = (i + p) / total;
                if (_downloadPhase != _DownloadPhase.saving && p >= 0.85) {
                  _downloadPhase = _DownloadPhase.saving;
                }
              });
              _popoverEntry?.markNeedsBuild();
            }
          }

          try {
            await switch (key) {
              'yugioh'   => _repo.redownloadYugiohCatalog(onProgress: onProg, onSaveProgress: onSave),
              'pokemon'  => _repo.redownloadPokemonCatalog(onProgress: onProg, onSaveProgress: onSave),
              'onepiece' => _repo.redownloadOnepieceCatalog(onProgress: onProg, onSaveProgress: onSave),
              _ => Future.value(),
            };
            successCount++;
          } catch (e) {
            lastError = e;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Errore ripristino $name: $e'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 6),
                ),
              );
            }
          }
        }
      } catch (e) {
        lastError = e;
      } finally {
        await BackgroundDownloadService.stopDownload();
        if (mounted) {
          setState(() {
            _isCatalogDownloading = false;
            _catalogDownloadProgress = null;
            _currentDownloadingName = null;
            _currentDownloadingKey = null;
            _currentDownloadingIndex = 0;
            _downloadPhase = _DownloadPhase.connecting;
            if (successCount > 0) _pendingUpdates = [];
          });
          if (successCount > 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Catalogo ripristinato con successo!'), backgroundColor: Colors.green),
            );
          } else if (lastError != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ripristino fallito: $lastError'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 8),
              ),
            );
          }
        }
      }
    }();
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
      final progress      = _catalogDownloadProgress;
      final name          = _currentDownloadingName;
      final idx           = _currentDownloadingIndex;
      final total         = _pendingUpdates.isNotEmpty ? _pendingUpdates.length : idx;
      final collectionKey = _currentDownloadingKey;
      final phase         = _downloadPhase;

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
      currentPage = IndexedStack(
        key: ValueKey(_currentCollectionKey),
        index: _currentIndex - 1, // _currentIndex is always 1–4 inside a collection
        children: [
          CardListPage(
            collectionKey: _currentCollectionKey!,
            collectionName: _currentCollectionName!,
          ),
          CatalogPage(
            collectionKey: _currentCollectionKey!,
            collectionName: _currentCollectionName!,
          ),
          AlbumListPage(
            collectionKey: _currentCollectionKey!,
            collectionName: _currentCollectionName!,
          ),
          DeckListPage(
            collectionKey: _currentCollectionKey!,
            collectionName: _currentCollectionName!,
          ),
        ],
      );
    } else {
      currentPage = _isAdmin
          ? const AdminCatalogBody()
          : HomePageSimple(
              onCollectionSelected: _onCollectionSelected,
              onCatalogRefreshNeeded: () async {
                // Piccolo delay affinché il DB registri la nuova collezione sbloccata
                await Future.delayed(const Duration(milliseconds: 800));
                if (mounted) _checkCatalogUpdate();
              },
            );
    }

    String appBarTitle;
    if (!inCollection) {
      appBarTitle = _isAdmin ? 'Admin — Gestione Catalogo' : 'Deck Master';
    } else {
      const titles = ['Home', 'Le mie Carte', 'Catalogo', 'Album', 'Deck'];
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

    // On wide screens inside a collection replace BottomNav with a NavigationRail on the left
    if (isWide && inCollection) {
      pageBody = Row(
        children: [
          NavigationRail(
            backgroundColor: AppColors.bgMedium,
            selectedIndex: _currentIndex - 1,
            onDestinationSelected: (i) => setState(() => _currentIndex = i + 1),
            labelType: NavigationRailLabelType.all,
            selectedIconTheme: const IconThemeData(color: AppColors.gold),
            selectedLabelTextStyle: const TextStyle(color: AppColors.gold, fontSize: 12),
            unselectedLabelTextStyle: TextStyle(color: AppColors.textHint, fontSize: 12),
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.style), label: Text('Carte')),
              NavigationRailDestination(icon: Icon(Icons.search), label: Text('Catalogo')),
              NavigationRailDestination(icon: Icon(Icons.book), label: Text('Album')),
              NavigationRailDestination(icon: Icon(Icons.deck), label: Text('Deck')),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: currentPage,
              ),
            ),
          ),
        ],
      );
    }

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
                tooltip: 'Torna alla Home',
                onPressed: _exitCollection,
              )
            : null,
        title: Text(appBarTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (inCollection)
            IconButton(
              icon: const Icon(Icons.document_scanner_outlined),
              tooltip: 'Scansiona carta',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CardScannerPage(
                    collectionKey: _currentCollectionKey,
                    collectionName: _currentCollectionName,
                  ),
                ),
              ),
            ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                tooltip: 'Notifiche',
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
          if (_isCatalogDownloading)
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
                        value: _catalogDownloadProgress,
                        strokeWidth: 3,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                      ),
                      Text(
                        _catalogDownloadProgress != null
                            ? '${(_catalogDownloadProgress! * 100).toInt()}%'
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
                  tooltip: 'Aggiornamento catalogo disponibile — tocca per scaricare',
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
            tooltip: 'Statistiche',
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
            tooltip: 'Menu utente',
            onSelected: (value) async {
              if (value == 'profile') {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
                if (mounted) setState(() => _avatarVersion++);
              } else if (value == 'settings') {
                final result = await Navigator.push<Map<String, dynamic>>(
                  context,
                  MaterialPageRoute(builder: (_) => SettingsPage(collectionKey: _currentCollectionKey)),
                );
                if (mounted && result?['restore'] != null) {
                  _startRestoreDownload(result!['restore'] as String);
                }
              } else if (value == 'donations') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const DonationsPage()));
              } else if (value == 'support') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportPage()));
              } else if (value == 'logout') {
                _logout();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: Icon(Icons.manage_accounts_outlined),
                  title: Text('Profilo'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings),
                  title: Text('Impostazioni'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'donations',
                child: ListTile(
                  leading: Icon(Icons.coffee, color: Color(0xFFFF6B35)),
                  title: Text('Offrimi un caffè',
                      style: TextStyle(color: Color(0xFFFF6B35), fontWeight: FontWeight.w600)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'support',
                child: ListTile(
                  leading: Icon(Icons.support_agent),
                  title: Text('Supporto'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout, color: Colors.red),
                  title: Text('Logout', style: TextStyle(color: Colors.red)),
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
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              top: false,
              bottom: true,
              child: pageBody,
            ),
          ),
          if (!kIsWeb) const BannerAdWidget(),
        ],
      ),
      // Bottom nav only shown on narrow screens inside a collection
      bottomNavigationBar: (!isWide && inCollection)
          ? BottomNavigationBar(
              currentIndex: _currentIndex,
              type: BottomNavigationBarType.fixed,
              backgroundColor: AppColors.bgMedium,
              selectedItemColor: AppColors.gold,
              unselectedItemColor: AppColors.textHint,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
                BottomNavigationBarItem(icon: Icon(Icons.style), label: 'Carte'),
                BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Catalogo'),
                BottomNavigationBarItem(icon: Icon(Icons.book), label: 'Album'),
                BottomNavigationBarItem(icon: Icon(Icons.deck), label: 'Deck'),
              ],
              onTap: _onNavTap,
            )
          : null,
      ),
    );
  }
}

// ─── Welcome overlay ─────────────────────────────────────────────────────────

class _WelcomeOverlay extends StatefulWidget {
  final String name;
  final bool isFirstLogin;

  const _WelcomeOverlay({required this.name, required this.isFirstLogin});

  @override
  State<_WelcomeOverlay> createState() => _WelcomeOverlayState();
}

class _WelcomeOverlayState extends State<_WelcomeOverlay> {
  static const _returningMessages = [
    'Le tue carte ti stavano aspettando. 🃏',
    'Il tuo mazzo è pronto per l\'azione. ⚔️',
    'La collezione chiama, il collezionista risponde. 🎴',
    'Ogni carta ha una storia. Qual è la tua di oggi? ✨',
  ];

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isFirst = widget.isFirstLogin;
    final subtitle = isFirst
        ? 'La tua avventura da collezionista inizia ora. 🎴'
        : _returningMessages[DateTime.now().millisecond % _returningMessages.length];

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        backgroundColor: AppColors.bgDark,
        body: Stack(
          children: [
            // Gradient background
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.bgDark, Color(0xFF121526), AppColors.bgMedium],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
            // Gold glow top-center
            Positioned(
              top: -60,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.gold.withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Content
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Card icon with glow
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.bgMedium,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.gold.withValues(alpha: 0.5),
                              blurRadius: 40,
                              spreadRadius: 6,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.style, size: 54, color: AppColors.gold),
                      ),
                      const SizedBox(height: 36),
                      Text(
                        isFirst ? 'Benvenuto,' : 'Bentornato,',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 22,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [AppColors.gold, Color(0xFFFFE88A)],
                        ).createShader(bounds),
                        child: Text(
                          widget.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 42,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        height: 1,
                        width: 80,
                        color: AppColors.gold.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 64),
                      const Text(
                        'Tocca per continuare',
                        style: TextStyle(color: AppColors.textHint, fontSize: 12, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Download theming ─────────────────────────────────────────────────────────

enum _DownloadPhase { connecting, downloading, saving }

class _CollectionTheme {
  final Color accent;
  final IconData icon;
  final String connecting;
  final String downloading;
  final String saving;
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
    connecting: 'Connessione al Mondo delle Ombre...',
    downloading: 'Maximillion Pegasus sta creando le carte...',
    saving: 'Il Faraone sigilla le carte nel Dueling Book...',
  ),
  'pokemon': _CollectionTheme(
    accent: Color(0xFFFFCB05),
    icon: Icons.catching_pokemon_rounded,
    connecting: 'Connessione al Lab. del Prof. Oak...',
    downloading: 'Il Prof. Oak sta catalogando i Pokémon...',
    saving: 'Archiviazione nel Pokédex Nazionale...',
  ),
  'onepiece': _CollectionTheme(
    accent: Color(0xFFE74C3C),
    icon: Icons.sailing_rounded,
    connecting: 'Navigazione verso il Grand Line...',
    downloading: 'Shanks sta distribuendo le carte...',
    saving: 'Il Mugiwara Crew carica le carte...',
  ),
};

// ─── Download popover card ────────────────────────────────────────────────────

class _DownloadPopoverCard extends StatelessWidget {
  final double? progress;
  final String? name;
  final int index;
  final int total;
  final String? collectionKey;
  final _DownloadPhase phase;

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

    final phaseMessage = theme == null
        ? switch (phase) {
            _DownloadPhase.connecting  => 'Connessione in corso...',
            _DownloadPhase.downloading => 'Download in corso...',
            _DownloadPhase.saving      => 'Salvataggio in corso...',
          }
        : switch (phase) {
            _DownloadPhase.connecting  => theme.connecting,
            _DownloadPhase.downloading => theme.downloading,
            _DownloadPhase.saving      => theme.saving,
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
                const Text(
                  'Tocca fuori per chiudere',
                  style: TextStyle(color: AppColors.textHint, fontSize: 10),
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
