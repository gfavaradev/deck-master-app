import 'package:flutter/material.dart';
import '../services/data_repository.dart';
import 'deck_detail_page.dart';

/// Dialog separato come StatefulWidget: il TextEditingController viene
/// disposto da Flutter nel metodo dispose() al momento corretto (dopo
/// l'animazione di chiusura), evitando l'assertion _dependents.isEmpty.
class _AddDeckDialog extends StatefulWidget {
  const _AddDeckDialog();

  @override
  State<_AddDeckDialog> createState() => _AddDeckDialogState();
}

class _AddDeckDialogState extends State<_AddDeckDialog> {
  final _nameController = TextEditingController();
  String? _nameError;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuovo Deck'),
      content: TextField(
        controller: _nameController,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Nome Deck',
          errorText: _nameError,
        ),
        onChanged: (_) {
          if (_nameError != null) setState(() => _nameError = null);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        ElevatedButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) {
              setState(() => _nameError = 'Il nome è obbligatorio');
              return;
            }
            Navigator.pop(context, name);
          },
          child: const Text('Crea'),
        ),
      ],
    );
  }
}

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
    if (mounted) {
      setState(() {
        _decks = data;
      });
    }
  }

  Future<void> _showAddDeckDialog() async {
    final deckName = await showDialog<String>(
      context: context,
      builder: (_) => const _AddDeckDialog(),
    );
    if (deckName == null || !mounted) return;
    await _dbHelper.insertDeck(deckName, widget.collectionKey);
    _refreshDecks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
