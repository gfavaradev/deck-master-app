import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/card_model.dart';
import '../models/album_model.dart';
import '../services/data_repository.dart';
import '../services/language_service.dart';
import '../pages/album_list_page.dart';
import 'cardtrader_price_badge.dart' show CardtraderAllPricesSection;

class CardDialogs {
  static void showDetails({
    required BuildContext context,
    required CardModel card,
    required String albumName,
    required Function(CardModel) onDelete,
    List<AlbumModel> availableAlbums = const [],
    VoidCallback? onAlbumChanged,
    List<Map<String, dynamic>> cardDecks = const [],
  }) {
    int? selectedAlbumId = card.albumId == -1 ? null : card.albumId;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(card.name),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('S/N: ${card.serialNumber}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 8),
                if (availableAlbums.isNotEmpty)
                  DropdownButtonFormField<int>(
                    initialValue: selectedAlbumId,
                    decoration: const InputDecoration(labelText: 'Album', isDense: true),
                    items: availableAlbums.map((album) {
                      return DropdownMenuItem<int>(
                        value: album.id,
                        child: Text(album.name),
                      );
                    }).toList(),
                    onChanged: (newId) async {
                      if (newId == null || newId == selectedAlbumId) return;
                      setDialogState(() => selectedAlbumId = newId);
                      await DataRepository().updateCard(card.copyWith(albumId: newId));
                      onAlbumChanged?.call();
                    },
                  )
                else
                  Text('Album: $albumName', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Quantità: ${card.quantity}'),
                if (card.serialNumber.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  CardtraderAllPricesSection(
                    collection: card.collection,
                    serialNumber: card.serialNumber,
                    cardName: card.name,
                    rarity: card.rarity.isNotEmpty ? card.rarity : null,
                  ),
                ],
                Text('Tipo: ${card.type}'),
                Text('Rarità: ${card.rarity}'),
                if (cardDecks.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Deck:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...cardDecks.map((d) => Text(
                    '• ${d['name']} (x${d['quantity']})',
                    style: const TextStyle(fontSize: 13),
                  )),
                ],
                const SizedBox(height: 10),
                const Text('Descrizione:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(card.description),
              ],
            ),
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
      ),
    );
  }

  static void showAddCard({
    required BuildContext context,
    required String collectionName,
    required String collectionKey,
    required List<AlbumModel> availableAlbums,
    required Function(int albumId, String serialNumber) onCardAdded,
    required Future<int> Function() getOrCreateDuplicatesAlbum,
    required List<CardModel> allCards,
    Map<String, dynamic>? initialCatalogCard,
    int? lastUsedAlbumId,
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
                );
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
        lastUsedAlbumId: lastUsedAlbumId,
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
  final Function(int albumId, String serialNumber) onCardAdded;
  final Future<int> Function() getOrCreateDuplicatesAlbum;
  final int? lastUsedAlbumId;

  const _AddCardDialog({
    required this.collectionName,
    required this.collectionKey,
    required this.availableAlbums,
    required this.allCards,
    this.initialCatalogCard,
    required this.onCardAdded,
    required this.getOrCreateDuplicatesAlbum,
    this.lastUsedAlbumId,
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
  String? selectedSetCode; // composite key: setCode\x00rarity
  String? _selectedArtwork; // artwork URL of the currently selected set/print

  /// Composite key that uniquely identifies a print (set + rarity).
  String _setKey(Map<String, dynamic> set) {
    final code = set['setCode'] ?? '';
    final rarity = set['rarity'] ?? set['setRarity'] ?? '';
    return '$code\x00$rarity';
  }

  bool get _isYugioh => widget.collectionKey == 'yugioh';
  bool get _isPokemon => widget.collectionKey == 'pokemon';
  bool get _isLocalized => _isYugioh || _isPokemon;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCatalogCard;
    final displayName = _isLocalized
        ? (initial?['localizedName'] ?? initial?['name'] ?? '')
        : (initial?['name'] ?? '');
    final displayDesc = _isLocalized
        ? (initial?['localizedDescription'] ?? initial?['description'] ?? '')
        : (initial?['description'] ?? '');

    nameController = TextEditingController(text: displayName);
    serialController = TextEditingController();
    typeController = TextEditingController(text: initial?['type'] ?? '');
    rarityController = TextEditingController();
    quantityController = TextEditingController(text: '1');
    valueController = TextEditingController(text: '0.0');
    descController = TextEditingController(text: displayDesc);
    final hasLastUsed = widget.lastUsedAlbumId != null &&
        widget.availableAlbums.any((a) => a.id == widget.lastUsedAlbumId);
    selectedAlbumId = hasLastUsed
        ? widget.lastUsedAlbumId
        : (widget.availableAlbums.isNotEmpty ? widget.availableAlbums.first.id : null);
    selectedCatalogCard = initial;

    _initAsync();
  }

  Future<void> _initAsync() async {
    _preferredLanguage = await LanguageService.getPreferredLanguage();

    if (selectedCatalogCard != null) {
      final preSelectedSetCode = selectedCatalogCard!['setCode'];
      if (preSelectedSetCode != null) {
        serialController.text = _isLocalized
            ? (selectedCatalogCard!['localizedSetCode'] ?? preSelectedSetCode)
            : preSelectedSetCode;
        rarityController.text = _isLocalized
            ? (selectedCatalogCard!['localizedRarityCode'] ?? selectedCatalogCard!['rarityCode'] ?? selectedCatalogCard!['localizedRarity'] ?? '')
            : (selectedCatalogCard!['rarity'] ?? selectedCatalogCard!['setRarity'] ?? '');
        valueController.text = _isLocalized
            ? (selectedCatalogCard!['localizedSetPrice'] ?? selectedCatalogCard!['setPrice'] ?? 0.0).toString()
            : (selectedCatalogCard!['marketPrice'] ?? 0.0).toString();
        _selectedArtwork = selectedCatalogCard!['artwork'] as String?;
      }
      final cardId = selectedCatalogCard!['id'];
      if (cardId != null) {
        final preSelectedRarity = _isLocalized
            ? (selectedCatalogCard!['rarityCode'] ?? selectedCatalogCard!['setRarity'])
            : selectedCatalogCard!['setRarity'];
        _updateSets(cardId, preSelectedSetCode: preSelectedSetCode, preSelectedRarity: preSelectedRarity?.toString());
      }
    }
  }

  Future<void> _updateSets(dynamic cardId, {String? preSelectedSetCode, String? preSelectedRarity}) async {
    List<Map<String, dynamic>> sets;
    final id = cardId is int ? cardId : int.parse(cardId.toString());
    if (_isYugioh) {
      sets = await _dbHelper.getYugiohCardPrints(id, language: _preferredLanguage);
    } else if (_isPokemon) {
      sets = await _dbHelper.getPokemonCardPrints(id, language: _preferredLanguage);
    } else {
      sets = await _dbHelper.getOnepieceCardPrints(id);
    }
    if (!mounted) return;
    setState(() {
      availableSets = sets;
      if (sets.isNotEmpty) {
        if (preSelectedSetCode != null) {
          List<Map<String, dynamic>> found = [];
          // Try exact match on both setCode + rarity first
          if (preSelectedRarity != null) {
            found = sets.where((s) =>
              s['setCode'] == preSelectedSetCode &&
              (s['rarity'] == preSelectedRarity || s['setRarity'] == preSelectedRarity)
            ).toList();
          }
          // Fall back to setCode-only match
          if (found.isEmpty) {
            found = sets.where((s) => s['setCode'] == preSelectedSetCode).toList();
          }
          final matchedSet = found.isNotEmpty ? found.first : (sets.isNotEmpty ? sets.first : null);
          selectedSetCode = matchedSet != null ? _setKey(matchedSet) : null;
          // Apply the matched set data so serial/rarity/value/artwork come from
          // the actual print row, not from the flat catalog search result.
          if (matchedSet != null) _applySet(matchedSet);
        } else {
          selectedSetCode = sets.isNotEmpty ? _setKey(sets.first) : null;
          if (sets.isNotEmpty) _applySet(sets.first);
        }
      } else {
        selectedSetCode = null;
      }
    });
  }

  void _applySet(Map<String, dynamic> set) {
    _selectedArtwork = set['artwork'] as String?;
    if (_isLocalized) {
      serialController.text = set['localizedSetCode'] ?? set['setCode'] ?? '';
      rarityController.text = set['localizedRarityCode'] ?? set['rarityCode'] ?? set['localizedRarity'] ?? set['rarity'] ?? '';
      valueController.text = (set['localizedSetPrice'] ?? set['setPrice'] ?? 0.0).toString();
    } else {
      serialController.text = set['setCode'] ?? '';
      rarityController.text = set['setRarity'] ?? '';
      valueController.text = (set['marketPrice'] ?? 0.0).toString();
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Album ─────────────────────────────────────────────────────
            DropdownButtonFormField<int>(
              initialValue: selectedAlbumId,
              decoration: const InputDecoration(labelText: 'Seleziona Album'),
              items: widget.availableAlbums.map((album) {
                return DropdownMenuItem<int>(
                  value: album.id,
                  child: Text('${album.name} (${album.currentCount}/${album.maxCapacity})'),
                );
              }).toList(),
              onChanged: (val) => setState(() => selectedAlbumId = val),
            ),
            const SizedBox(height: 20),

            // ── Ricerca / Carta selezionata ────────────────────────────────
            if (selectedCatalogCard == null)
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Cerca Carta (Nome o Seriale)',
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: (query) async {
                  final results = await _dbHelper.getCatalogCardsByCollection(
                    widget.collectionKey,
                    query: query,
                    language: _preferredLanguage,
                  );
                  if (!mounted) return;
                  if (results.isNotEmpty) {
                    final card = results.first;
                    setState(() {
                      selectedCatalogCard = card;
                      nameController.text = _isLocalized
                          ? (card['localizedName'] ?? card['name'] ?? '')
                          : (card['name'] ?? '');
                      typeController.text = card['card_type'] ?? card['type'] ?? '';
                      descController.text = _isLocalized
                          ? (card['localizedDescription'] ?? card['description'] ?? '')
                          : (card['card_text'] ?? card['description'] ?? '');
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
                  _isLocalized
                      ? (selectedCatalogCard!['localizedName'] ?? selectedCatalogCard!['name'])
                      : selectedCatalogCard!['name'],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(selectedCatalogCard!['type'] ?? ''),
              ),
            const SizedBox(height: 16),

            // ── Set / Seriale ──────────────────────────────────────────────
            if (availableSets.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                initialValue: selectedSetCode,
                decoration: const InputDecoration(labelText: 'Seleziona Set / Seriale'),
                items: availableSets.map((set) {
                  final code = set['setCode'] ?? '';
                  final displayCode = _isLocalized
                      ? (set['localizedSetCode'] ?? code)
                      : code;
                  final rarity = _isLocalized
                      ? (set['localizedRarity'] ?? set['rarity'] ?? '')
                      : (set['setRarity'] ?? '');
                  return DropdownMenuItem<String>(
                    value: _setKey(set),
                    child: Text('$displayCode - $rarity'),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    selectedSetCode = val;
                    if (val != null) {
                      final setToApply = availableSets.firstWhere((s) => _setKey(s) == val, orElse: () => availableSets.first);
                      _applySet(setToApply);
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
            ],

            // ── Quantità e Valore ──────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: quantityController,
                    decoration: const InputDecoration(labelText: 'Quantità'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: valueController,
                    decoration: const InputDecoration(labelText: 'Valore (€)'),
                    keyboardType: TextInputType.number,
                    readOnly: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Descrizione ────────────────────────────────────────────────
            if (descController.text.isNotEmpty) ...[
              const Text('Descrizione', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(
                descController.text,
                style: const TextStyle(fontSize: 13),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
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
    if (selectedCatalogCard == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona una carta dal catalogo')),
      );
      return;
    }

    if (selectedAlbumId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona un album')),
      );
      return;
    }

    // Capacity check: block if the selected album is full (skip Doppioni)
    final targetAlbum = widget.availableAlbums.firstWhere(
      (a) => a.id == selectedAlbumId,
      orElse: () => AlbumModel(name: '', collection: '', maxCapacity: 0),
    );
    if (targetAlbum.maxCapacity > 0 && targetAlbum.name != 'Doppioni') {
      final freshCount = await _dbHelper.getCardCountByAlbum(selectedAlbumId!);
      if (freshCount >= targetAlbum.maxCapacity) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Album pieno'),
            content: Text(
              '${targetAlbum.name} ha raggiunto la capacità massima '
              '($freshCount/${targetAlbum.maxCapacity}).\n\n'
              'Aumenta la capacità dell\'album oppure seleziona un altro album.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
    }

    final String name = nameController.text;
    final String serialNumber = serialController.text;
    final int quantity = int.tryParse(quantityController.text) ?? 1;

    // Cerchiamo istanze già esistenti nel database invece di usare una lista potenzialmente vecchia
    final existingInstances = await _dbHelper.findOwnedInstances(widget.collectionKey, name, serialNumber, rarityController.text);
    
    int albumIdToUse = selectedAlbumId!;
    int quantityForMain = quantity;
    int quantityForDoppioni = 0;

    // Se esiste già in QUALSIASI album, questa aggiunta va nei doppioni
    final bool redirectedToDoppioni = existingInstances.isNotEmpty;
    if (redirectedToDoppioni) {
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
      imageUrl: _selectedArtwork ?? selectedCatalogCard?['imageUrl'] as String?,
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
      final instancesAfterFirstInsert = await _dbHelper.findOwnedInstances(widget.collectionKey, name, serialNumber, rarityController.text);
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
    
    // Save last used album before pop (always the user's real choice, not the auto-doppioni album)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_album_id_${widget.collectionKey}', selectedAlbumId!);

    if (!mounted) return;
    Navigator.pop(context);
    if (redirectedToDoppioni) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Carta già presente nella collezione → aggiunta ai Doppioni'),
          duration: Duration(seconds: 3),
        ),
      );
    }
    // Passa sempre la scelta dell'utente (selectedAlbumId), non albumIdToUse che
    // potrebbe essere l'album Doppioni: così il prossimo inserimento pre-seleziona
    // l'album scelto dall'utente e non quello dei doppioni.
    widget.onCardAdded(selectedAlbumId!, serialNumber);
  }
}
