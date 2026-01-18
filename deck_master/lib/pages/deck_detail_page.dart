import 'package:flutter/material.dart';
import '../services/database_helper.dart';

class DeckDetailPage extends StatefulWidget {
  final int deckId;
  final String deckName;
  final String collectionKey;

  const DeckDetailPage({
    super.key,
    required this.deckId,
    required this.deckName,
    required this.collectionKey,
  });

  @override
  State<DeckDetailPage> createState() => _DeckDetailPageState();
}

class _DeckDetailPageState extends State<DeckDetailPage> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _deckCards = [];

  @override
  void initState() {
    super.initState();
    _refreshDeckCards();
  }

  Future<void> _refreshDeckCards() async {
    final data = await _dbHelper.getDeckCards(widget.deckId);
    setState(() {
      _deckCards = data;
    });
  }

  void _showAddCardToDeckDialog() async {
    final allCards = await _dbHelper.getCardsByCollection(widget.collectionKey);
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aggiungi Carta al Deck'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: allCards.length,
            itemBuilder: (context, index) {
              final card = allCards[index];
              return ListTile(
                title: Text(card.name),
                subtitle: Text(card.serialNumber),
                onTap: () async {
                  await _dbHelper.addCardToDeck(widget.deckId, card.id!, 1);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  _refreshDeckCards();
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.deckName),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _deckCards.isEmpty
          ? const Center(child: Text('Nessuna carta in questo deck.'))
          : ListView.builder(
              itemCount: _deckCards.length,
              itemBuilder: (context, index) {
                final item = _deckCards[index];
                return ListTile(
                  leading: const Icon(Icons.style),
                  title: Text(item['name']),
                  subtitle: Text('S/N: ${item['serialNumber']} | Quantità: ${item['deckQuantity']}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle, color: Colors.red),
                    onPressed: () async {
                      await _dbHelper.removeCardFromDeck(widget.deckId, item['id']);
                      if (mounted) _refreshDeckCards();
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddCardToDeckDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
