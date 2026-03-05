import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';
import 'support_page.dart';
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
import 'notifications_page.dart';

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

class _MainLayoutState extends State<MainLayout> {
  late int _currentIndex;
  String? _currentCollectionKey;
  String? _currentCollectionName;
  bool _isAdmin = false;
  bool _hasUnreadNotifications = false;
  final AuthService _authService = AuthService();
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _currentCollectionKey = widget.collectionKey;
    _currentCollectionName = widget.collectionName;
    _currentUser = FirebaseAuth.instance.currentUser;
    _checkAdmin();
    _checkUnreadNotifications();

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

  Future<void> _checkAdmin() async {
    final isAdmin = await _authService.isCurrentUserAdmin();
    if (mounted) {
      setState(() {
        _isAdmin = isAdmin;
      });
    }
  }

  Future<void> _checkUnreadNotifications() async {
    final hasUnread = await hasUnreadNotifications();
    if (mounted) {
      setState(() {
        _hasUnreadNotifications = hasUnread;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool inCollection = _currentCollectionKey != null;

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
          : HomePageSimple(onCollectionSelected: _onCollectionSelected);
    }

    String appBarTitle;
    if (!inCollection) {
      appBarTitle = _isAdmin ? 'Admin — Gestione Catalogo' : 'Deck Master';
    } else {
      const titles = ['Home', 'Le mie Carte', 'Catalogo', 'Album', 'Deck'];
      appBarTitle = _currentIndex < titles.length ? titles[_currentIndex] : _currentCollectionName ?? 'Deck Master';
    }

    return Scaffold(
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
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                tooltip: 'Notifiche',
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const NotificationsPage()),
                  );
                  _checkUnreadNotifications();
                },
              ),
              if (_hasUnreadNotifications)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
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
              MaterialPageRoute(builder: (context) => const StatsPage()),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Menu utente',
            onSelected: (value) {
              if (value == 'profile') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
              } else if (value == 'settings') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
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
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'support',
                child: ListTile(
                  leading: Icon(Icons.support_agent),
                  title: Text('Supporto'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
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
              child: CircleAvatar(
                radius: 18,
                backgroundImage: _currentUser?.photoURL != null
                    ? NetworkImage(_currentUser!.photoURL!)
                    : null,
                backgroundColor: AppColors.bgLight,
                child: _currentUser?.photoURL == null
                    ? const Icon(Icons.person, size: 20, color: AppColors.textSecondary)
                    : null,
              ),
            ),
          ),
        ],
      ),
      body: currentPage,
      // Bottom nav only shown when inside a collection (Home, Carte, Catalogo, Album, Deck)
      bottomNavigationBar: inCollection
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
    );
  }
}
