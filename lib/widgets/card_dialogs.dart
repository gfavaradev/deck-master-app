import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../models/album_model.dart';
import '../services/data_repository.dart';
import '../services/language_service.dart';
import '../pages/album_list_page.dart';

class CardDialogs {
  static void showDetails({
    required BuildContext context,
    required CardModel card,
    required String albumName,
    required Function(CardModel) onDelete,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(card.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('S/N: ${card.serialNumber}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            Text('Album: $albumName', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Quantità: ${card.quantity}'),
            Text('Valore unitario: €${card.value.toStringAsFixed(2)}'),
            Text('Valore totale: €${(card.value * card.quantity).toStringAsFixed(2)}'),
            Text('Tipo: ${card.type}'),
            Text('Rarità: ${card.rarity}'),
            const SizedBox(height: 10),
            const Text('Descrizione:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(card.description),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete(card);
            },
            child: const Text('Elimina', style: TextStyle(color: Colors.red)),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Chiudi')),
        ],
      ),
    );
  }

  static void showAddCard({
    required BuildContext context,
    required String collectionName,
    required String collectionKey,
    required List<AlbumModel> availableAlbums,
    required Function() onCardAdded,
    required Future<int> Function() getOrCreateDuplicatesAlbum,
    required List<CardModel> allCards,
    Map<String, dynamic>? initialCatalogCard,
  }) {
    if (availableAlbums.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Nessun Album Trovato'),
          content: const Text('Devi prima creare almeno un album per questa collezione prima di poter aggiungere delle carte.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Chiudi')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AlbumListPage(
                      collectionName: collectionName,
                      collectionKey: collectionKey,
                    ),
                  ),
                ).then((_) => onCardAdded());
              },
              child: const Text('Gestisci Album'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => _AddCardDialog(
        collectionName: collectionName,
        collectionKey: collectionKey,
        availableAlbums: availableAlbums,
        allCards: allCards,
        initialCatalogCard: initialCatalogCard,
        onCardAdded: onCardAdded,
        getOrCreateDuplicatesAlbum: getOrCreateDuplicatesAlbum,
      ),
    );
  }
}

class _AddCardDialog extends StatefulWidget {
  final String collectionName;
  final String collectionKey;
  final List<AlbumModel> availableAlbums;
  final List<CardModel> allCards;
  final Map<String, dynamic>? initialCatalogCard;
  final Function() onCardAdded;
  final Future<int> Function() getOrCreateDuplicatesAlbum;

  const _AddCardDialog({
    required this.collectionName,
    required this.collectionKey,
    required this.availableAlbums,
    required this.allCards,
    this.initialCatalogCard,
    required this.onCardAdded,
    required this.getOrCreateDuplicatesAlbum,
  });

  @override
  State<_AddCardDialog> createState() => _AddCardDialogState();
}

class _AddCardDialogState extends State<_AddCardDialog> {
  final _dbHelper = DataRepository();
  late TextEditingController nameController;
  late TextEditingController serialController;
  late TextEditingController typeController;
  late TextEditingController rarityController;
  late TextEditingController quantityController;
  late TextEditingController valueController;
  late TextEditingController descController;
  int? selectedAlbumId;
  String _preferredLanguage = 'EN';

  Map<String, dynamic>? selectedCatalogCard;
  List<Map<String, dynamic>> availableSets = [];
  String? selectedSetCode;

  bool get _isYugioh => widget.collectionKey == 'yugioh';

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCatalogCard;
    final displayName = _isYugioh
        ? (initial?['localizedName'] ?? initial?['name'] ?? '')
        : (initial?['name'] ?? '');
    final displayDesc = _isYugioh
        ? (initial?['localizedDescription'] ?? initial?['description'] ?? '')
        : (initial?['description'] ?? '');

    nameController = TextEditingController(text: displayName);
    serialController = TextEditingController();
    typeController = TextEditingController(text: initial?['type'] ?? '');
    rarityController = TextEditingController();
    quantityController = TextEditingController(text: '1');
    valueController = TextEditingController(text: '0.0');
    descController = TextEditingController(text: displayDesc);
    selectedAlbumId = widget.availableAlbums.first.id;
    selectedCatalogCard = initial;

    _initAsync();
  }

  Future<void> _initAsync() async {
    _preferredLanguage = await LanguageService.getPreferredLanguage();

    if (selectedCatalogCard != null) {
      final preSelectedSetCode = selectedCatalogCard!['setCode'];
      if (preSelectedSetCode != null) {
        serialController.text = _isYugioh
            ? (selectedCatalogCard!['localizedSetCode'] ?? preSelectedSetCode)
            : preSelectedSetCode;
        rarityController.text = _isYugioh
            ? (selectedCatalogCard!['localizedRarity'] ?? selectedCatalogCard!['setRarity'] ?? '')
            : (selectedCatalogCard!['setRarity'] ?? '');
        valueController.text = _isYugioh
            ? (selectedCatalogCard!['localizedSetPrice'] ?? selectedCatalogCard!['setPrice'] ?? 0.0).toString()
            : (selectedCatalogCard!['setPrice'] ?? 0.0).toString();
      }
      final cardId = selectedCatalogCard!['id'];
      if (cardId != null) {
        _updateSets(cardId, preSelectedSetCode: preSelectedSetCode);
      }
    }
  }

  Future<void> _updateSets(dynamic cardId, {String? preSelectedSetCode}) async {
    List<Map<String, dynamic>> sets;
    if (_isYugioh) {
      sets = await _dbHelper.getYugiohCardPrints(
        cardId is int ? cardId : int.parse(cardId.toString()),
        language: _preferredLanguage,
      );
    } else {
      sets = await _dbHelper.getCardSets(cardId.toString());
    }
    if (!mounted) return;
    setState(() {
      availableSets = sets;
      if (sets.isNotEmpty) {
        if (preSelectedSetCode != null) {
          final found = sets.where((s) => s['setCode'] == preSelectedSetCode).toList();
          selectedSetCode = found.isNotEmpty ? found.first['setCode'] : sets.first['setCode'];
        } else {
          selectedSetCode = sets.first['setCode'];
        }
        if (preSelectedSetCode == null) {
          final setToApply = sets.firstWhere((s) => s['setCode'] == selectedSetCode);
          _applySet(setToApply);
        }
      } else {
        selectedSetCode = null;
      }
    });
  }

  void _applySet(Map<String, dynamic> set) {
    if (_isYugioh) {
      serialController.text = set['localizedSetCode'] ?? set['setCode'] ?? '';
      rarityController.text = set['localizedRarity'] ?? set['rarity'] ?? '';
      valueController.text = (set['localizedSetPrice'] ?? set['setPrice'] ?? 0.0).toString();
    } else {
      serialController.text = set['setCode'] ?? '';
      rarityController.text = set['setRarity'] ?? '';
      valueController.text = (set['setPrice'] ?? 0.0).toString();
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    serialController.dispose();
    typeController.dispose();
    rarityController.dispose();
    quantityController.dispose();
    valueController.dispose();
    descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Aggiungi a ${widget.collectionName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              value: selectedAlbumId,
              decoration: const InputDecoration(labelText: 'Seleziona Album'),
              items: widget.availableAlbums.map((album) {
                return DropdownMenuItem<int>(
                  value: album.id,
                  child: Text('${album.name} (${album.currentCount}/${album.maxCapacity})'),
                );
              }).toList(),
              onChanged: (val) => setState(() => selectedAlbumId = val),
            ),
            const SizedBox(height: 10),
            if (selectedCatalogCard == null)
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Cerca Carta (Nome o Seriale)',
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: (query) async {
                  List<Map<String, dynamic>> results;
                  if (_isYugioh) {
                    results = await _dbHelper.getYugiohCatalogCards(
                      language: _preferredLanguage,
                      query: query,
                    );
                  } else {
                    results = await _dbHelper.getCatalogCards(widget.collectionKey, query: query);
                  }
                  if (results.isNotEmpty) {
                    final card = results.first;
                    setState(() {
                      selectedCatalogCard = card;
                      nameController.text = _isYugioh
                          ? (card['localizedName'] ?? card['name'] ?? '')
                          : (card['name'] ?? '');
                      typeController.text = card['type'] ?? '';
                      descController.text = _isYugioh
                          ? (card['localizedDescription'] ?? card['description'] ?? '')
                          : (card['description'] ?? '');
                    });
                    final cardId = card['id'];
                    if (cardId != null) {
                      _updateSets(cardId);
                    }
                  }
                },
              )
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _isYugioh
                      ? (selectedCatalogCard!['localizedName'] ?? selectedCatalogCard!['name'])
                      : selectedCatalogCard!['name'],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(selectedCatalogCard!['type'] ?? ''),
                trailing: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() {
                    selectedCatalogCard = null;
                    availableSets = [];
                    selectedSetCode = null;
                    nameController.clear();
                    typeController.clear();
                    descController.clear();
                  }),
                ),
              ),

            if (availableSets.isNotEmpty)
              DropdownButtonFormField<String>(
                value: selectedSetCode,
                decoration: const InputDecoration(labelText: 'Seleziona Set / Seriale'),
                items: availableSets.map((set) {
                  final code = set['setCode'] ?? '';
                  final displayCode = _isYugioh
                      ? (set['localizedSetCode'] ?? code)
                      : code;
                  final rarity = _isYugioh
                      ? (set['localizedRarity'] ?? set['rarity'] ?? '')
                      : (set['setRarity'] ?? '');
                  return DropdownMenuItem<String>(
                    value: code,
                    child: Text('$displayCode - $rarity'),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    selectedSetCode = val;
                    if (val != null) {
                      final setToApply = availableSets.firstWhere((s) => s['setCode'] == val);
                      _applySet(setToApply);
                    }
                  });
                },
              ),

            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nome Carta'), readOnly: selectedCatalogCard != null),
            TextField(controller: serialController, decoration: const InputDecoration(labelText: 'Numero di Serie')),
            Row(
              children: [
                Expanded(child: TextField(controller: quantityController, decoration: const InputDecoration(labelText: 'Quantità'), keyboardType: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: valueController, decoration: const InputDecoration(labelText: 'Valore (€)'), keyboardType: TextInputType.number)),
              ],
            ),
            TextField(controller: rarityController, decoration: const InputDecoration(labelText: 'Rarità')),
            TextField(controller: typeController, decoration: const InputDecoration(labelText: 'Tipo'), readOnly: selectedCatalogCard != null),
            TextField(controller: descController, decoration: const InputDecoration(labelText: 'Descrizione'), maxLines: 3),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
        ElevatedButton(
          onPressed: _saveCard,
          child: const Text('Salva'),
        ),
      ],
    );
  }

  Future<void> _saveCard() async {
    final String name = nameController.text;
    final String serialNumber = serialController.text;
    final int quantity = int.tryParse(quantityController.text) ?? 1;
    
    if (name.isEmpty || serialNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nome e Numero di Serie sono obbligatori')),
      );
      return;
    }

    // Cerchiamo istanze già esistenti nel database invece di usare una lista potenzialmente vecchia
    final existingInstances = await _dbHelper.findOwnedInstances(widget.collectionKey, name, serialNumber);
    
    int albumIdToUse = selectedAlbumId!;
    int quantityForMain = quantity;
    int quantityForDoppioni = 0;

    // Se esiste già in QUALSIASI album, questa aggiunta va nei doppioni
    if (existingInstances.isNotEmpty) {
      albumIdToUse = await widget.getOrCreateDuplicatesAlbum();
    } else if (quantity > 1) {
      // Se ne stiamo aggiungendo più di una per la prima volta, 1 va nel main e le altre nei doppioni
      quantityForMain = 1;
      quantityForDoppioni = quantity - 1;
    }

    final cardToSave = CardModel(
      catalogId: selectedCatalogCard?['id']?.toString(),
      name: name,
      serialNumber: serialNumber,
      collection: widget.collectionKey,
      albumId: albumIdToUse,
      type: typeController.text,
      rarity: rarityController.text,
      description: descController.text,
      quantity: quantityForMain,
      value: double.tryParse(valueController.text) ?? 0.0,
    );

    // Controlliamo se esiste già ESATTAMENTE in quell'album di destinazione (per sommare quantità)
    final existingInTarget = existingInstances.where((c) => c.albumId == albumIdToUse).toList();

    if (existingInTarget.isNotEmpty) {
      await _dbHelper.updateCard(existingInTarget.first.copyWith(
        quantity: existingInTarget.first.quantity + quantityForMain
      ));
    } else {
      await _dbHelper.insertCard(cardToSave);
    }

    if (quantityForDoppioni > 0) {
      final doppioniId = await widget.getOrCreateDuplicatesAlbum();
      // Verifichiamo se esiste già nell'album doppioni (potrebbe essere stato appena creato o già esistente)
      final instancesAfterFirstInsert = await _dbHelper.findOwnedInstances(widget.collectionKey, name, serialNumber);
      final existingInDoppioni = instancesAfterFirstInsert.where((c) => c.albumId == doppioniId).toList();

      if (existingInDoppioni.isNotEmpty) {
        await _dbHelper.updateCard(existingInDoppioni.first.copyWith(
          quantity: existingInDoppioni.first.quantity + quantityForDoppioni
        ));
      } else {
        await _dbHelper.insertCard(cardToSave.copyWith(
          albumId: doppioniId,
          quantity: quantityForDoppioni,
        ));
      }
    }
    
    if (!mounted) return;
    Navigator.pop(context);
    widget.onCardAdded();
  }
}
