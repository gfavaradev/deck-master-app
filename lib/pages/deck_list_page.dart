import 'package:flutter/material.dart';
import '../services/data_repository.dart';
import 'deck_detail_page.dart';

class DeckListPage extends StatefulWidget {
  final String collectionName;
  final String collectionKey;

  const DeckListPage({
    super.key,
    required this.collectionName,
    required this.collectionKey,
  });

  @override
  State<DeckListPage> createState() => _DeckListPageState();
}

class _DeckListPageState extends State<DeckListPage> {
  final DataRepository _dbHelper = DataRepository();
  List<Map<String, dynamic>> _decks = [];

  @override
  void initState() {
    super.initState();
    _refreshDecks();
  }

  Future<void> _refreshDecks() async {
    final data = await _dbHelper.getDecksByCollection(widget.collectionKey);
    setState(() {
      _decks = data;
    });
  }

  void _showAddDeckDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuovo Deck'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Nome Deck'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                await _dbHelper.insertDeck(nameController.text, widget.collectionKey);
                if (!context.mounted) return;
                Navigator.pop(context);
                _refreshDecks();
              }
            },
            child: const Text('Crea'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Deck ${widget.collectionName}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _decks.isEmpty
          ? const Center(child: Text('Nessun deck creato.'))
          : ListView.builder(
              itemCount: _decks.length,
              itemBuilder: (context, index) {
                final deck = _decks[index];
                return ListTile(
                  leading: const Icon(Icons.deck),
                  title: Text(deck['name']),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () async {
                      await _dbHelper.deleteDeck(deck['id']);
                      if (mounted) _refreshDecks();
                    },
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DeckDetailPage(
                          deckId: deck['id'],
                          deckName: deck['name'],
                          collectionKey: widget.collectionKey,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDeckDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
