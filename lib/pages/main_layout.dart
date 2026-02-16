import 'package:flutter/material.dart';
import 'home_page_simple.dart';
import 'card_list_page.dart';
import 'catalog_page.dart';
import 'album_list_page.dart';
import 'deck_list_page.dart';
import 'stats_page.dart';
import 'settings_page.dart';

/// Layout principale con barra di navigazione persistente
class MainLayout extends StatefulWidget {
  final int initialIndex;
  final String? collectionKey;
  final String? collectionName;

  const MainLayout({
    super.key,
    this.initialIndex = 0,
    this.collectionKey,
    this.collectionName,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  late int _currentIndex;
  String? _currentCollectionKey;
  String? _currentCollectionName;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _currentCollectionKey = widget.collectionKey;
    _currentCollectionName = widget.collectionName;
  }

  void _onNavTap(int index) {
    final bool inCollection = _currentCollectionKey != null;

    // In collection mode, index 0 = Home (exit collection)
    if (inCollection && index == 0) {
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
      _currentIndex = 0; // Torna alla home
    });
  }

  @override
  Widget build(BuildContext context) {
    // Determina le pagine disponibili in base allo stato
    final bool inCollection = _currentCollectionKey != null;

    Widget currentPage;
    List<BottomNavigationBarItem> navItems;

    if (inCollection) {
      // Modalità collezione: Home, Carte, Catalogo, Album, Deck, Stats, Settings
      navItems = const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.style), label: 'Carte'),
        BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Catalogo'),
        BottomNavigationBarItem(icon: Icon(Icons.book), label: 'Album'),
        BottomNavigationBarItem(icon: Icon(Icons.deck), label: 'Deck'),
        BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Stats'),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Impostazioni'),
      ];

      switch (_currentIndex) {
        case 0:
          currentPage = HomePageSimple(
            onCollectionSelected: _onCollectionSelected,
          );
          break;
        case 1:
          currentPage = CardListPage(
            collectionKey: _currentCollectionKey!,
            collectionName: _currentCollectionName!,
          );
          break;
        case 2:
          currentPage = CatalogPage(
            collectionKey: _currentCollectionKey!,
            collectionName: _currentCollectionName!,
          );
          break;
        case 3:
          currentPage = AlbumListPage(
            collectionKey: _currentCollectionKey!,
            collectionName: _currentCollectionName!,
          );
          break;
        case 4:
          currentPage = DeckListPage(
            collectionKey: _currentCollectionKey!,
            collectionName: _currentCollectionName!,
          );
          break;
        case 5:
          currentPage = const StatsPage();
          break;
        case 6:
          currentPage = const SettingsPage();
          break;
        default:
          currentPage = HomePageSimple(
            onCollectionSelected: _onCollectionSelected,
          );
      }
    } else {
      // Modalità normale: Home, Stats, Settings
      navItems = const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Stats'),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Impostazioni'),
      ];

      switch (_currentIndex) {
        case 0:
          currentPage = HomePageSimple(
            onCollectionSelected: _onCollectionSelected,
          );
          break;
        case 1:
          currentPage = const StatsPage();
          break;
        case 2:
          currentPage = const SettingsPage();
          break;
        default:
          currentPage = HomePageSimple(
            onCollectionSelected: _onCollectionSelected,
          );
      }
    }

    return Scaffold(
      body: currentPage,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        items: navItems,
        onTap: _onNavTap,
      ),
    );
  }
}
