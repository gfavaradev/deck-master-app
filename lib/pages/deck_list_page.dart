import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/data_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/app_dialog.dart';
import '../widgets/top_undo_bar.dart';
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
    return AppDialog(
      title: 'Nuovo Deck',
      icon: Icons.style_outlined,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'NOME DECK',
            style: TextStyle(
              color: AppColors.textHint,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            autofocus: true,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
              LengthLimitingTextInputFormatter(19),
            ],
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Es. MazzoAttacco',
              hintStyle: const TextStyle(color: AppColors.textHint),
              errorText: _nameError,
              prefixIcon: const Icon(Icons.style_outlined, color: AppColors.blue, size: 20),
              filled: true,
              fillColor: AppColors.bgLight,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.blue, width: 1.5)),
              errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.error)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            ),
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: appDialogCancelStyle(),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) {
              setState(() => _nameError = 'Il nome è obbligatorio');
              return;
            }
            Navigator.pop(context, name);
          },
          style: appDialogConfirmStyle(),
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

  Future<void> _deleteDeck(Map<String, dynamic> deck) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AppConfirmDialog(
        title: 'Elimina Deck',
        icon: Icons.delete_outline,
        message: 'Sei sicuro di voler eliminare "${deck['name']}"?',
        confirmLabel: 'Elimina',
      ),
    );
    if (confirmed != true || !mounted) return;
    await _dbHelper.deleteDeck(deck['id']);
    if (!mounted) return;
    _refreshDecks();
    TopUndoBar.show(
      context: context,
      message: 'Deck "${deck['name']}" eliminato',
    );
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
      body: SafeArea(
        top: false,
        bottom: true,
        child: _decks.isEmpty
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
                      onPressed: () => _deleteDeck(deck),
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
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        onPressed: _showAddDeckDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
