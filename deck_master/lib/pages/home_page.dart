import 'package:flutter/material.dart';
import '../models/collection_model.dart';
import '../services/database_helper.dart';
import '../services/api_service.dart';
import 'card_list_page.dart';
import 'stats_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final ApiService _apiService = ApiService();
  List<CollectionModel> _unlockedCollections = [];
  List<CollectionModel> _availableCollections = [];
  bool _isLoading = true;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadCollections();
  }

  Future<void> _loadCollections() async {
    final all = await _dbHelper.getCollections();
    if (mounted) {
      setState(() {
        _unlockedCollections = all.where((c) => c.isUnlocked).toList();
        _availableCollections = all.where((c) => !c.isUnlocked).toList();
        _isLoading = false;
      });
    }
  }

  Future<void> _unlock(CollectionModel collection) async {
    await _dbHelper.unlockCollection(collection.key);
    _loadCollections();
  }

  Widget _buildHomeContent() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_unlockedCollections.isNotEmpty) ...[
                  _buildSectionTitle('Le mie Collezioni'),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.2,
                    ),
                    itemCount: _unlockedCollections.length,
                    itemBuilder: (context, index) => _buildCollectionTile(context, _unlockedCollections[index], true),
                  ),
                  const SizedBox(height: 30),
                ],
                
                _buildSectionTitle('Collezioni Disponibili'),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.2,
                  ),
                  itemCount: _availableCollections.length,
                  itemBuilder: (context, index) => _buildCollectionTile(context, _availableCollections[index], false),
                ),
              ],
            ),
          );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _buildHomeContent(),
      const StatsPage(),
      const SettingsPage(),
    ];

    return Scaffold(
      appBar: _currentIndex == 0 ? AppBar(
        title: const Text('Deck Master'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ) : null,
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Stats'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Text(
        title,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildCollectionTile(BuildContext context, CollectionModel collection, bool isUnlocked) {
    Color color = _getCollectionColor(collection.key);
    String logoUrl = _getCollectionLogoUrl(collection.key);

    return InkWell(
      onTap: () {
        if (isUnlocked) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CardListPage(
                collectionName: collection.name,
                collectionKey: collection.key,
              ),
            ),
          );
        } else {
          _showUnlockDialog(collection);
        }
      },
      child: Opacity(
        opacity: isUnlocked ? 1.0 : 0.4,
        child: Card(
          elevation: isUnlocked ? 4 : 0,
          color: isUnlocked ? Colors.white : Colors.grey.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(color: isUnlocked ? color.withValues(alpha: 0.5) : Colors.grey),
          ),
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(15.0),
                  child: Image.network(
                    logoUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Icon(Icons.style, size: 50, color: isUnlocked ? color : Colors.grey),
                  ),
                ),
              ),
              if (!isUnlocked)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: Icon(Icons.lock, size: 18, color: Colors.grey),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUnlockDialog(CollectionModel collection) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sblocca ${collection.name}'),
        content: Text('Vuoi aggiungere ${collection.name} alle tue collezioni?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _unlock(collection);
            },
            child: const Text('Sblocca'),
          ),
        ],
      ),
    );
  }

  Color _getCollectionColor(String key) {
    switch (key) {
      case 'yugioh': return Colors.orange;
      case 'pokemon': return Colors.red;
      case 'magic': return Colors.blueGrey;
      default: return Colors.blue;
    }
  }

  String _getCollectionLogoUrl(String key) {
    switch (key) {
      case 'yugioh': 
        return 'https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/Yu-Gi-Oh%21_Logo.png/640px-Yu-Gi-Oh%21_Logo.png';
      case 'pokemon': 
        return 'https://upload.wikimedia.org/wikipedia/commons/thumb/9/98/International_Pok%C3%A9mon_logo.svg/1200px-International_Pok%C3%A9mon_logo.svg.png';
      case 'magic': 
        return 'https://upload.wikimedia.org/wikipedia/commons/thumb/3/3f/Magicthegathering-logo.svg/1200px-Magicthegathering-logo.svg.png';
      default: 
        return 'https://via.placeholder.com/150';
    }
  }
}
