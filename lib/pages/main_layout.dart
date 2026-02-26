import 'package:flutter/material.dart';
import 'home_page_simple.dart';
import 'card_list_page.dart';
import 'catalog_page.dart';
import 'album_list_page.dart';
import 'deck_list_page.dart';
import 'stats_page.dart';
import 'settings_page.dart';
import 'admin_home_page.dart';
import '../services/auth_service.dart';

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
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _currentCollectionKey = widget.collectionKey;
    _currentCollectionName = widget.collectionName;
    _checkAdmin();

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

  Future<void> _checkAdmin() async {
    final isAdmin = await _authService.isCurrentUserAdmin();
    if (mounted) {
      setState(() {
        _isAdmin = isAdmin;
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
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Statistiche',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const StatsPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Impostazioni',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsPage()),
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
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: Colors.grey,
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
