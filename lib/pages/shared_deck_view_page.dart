import '../l10n/app_localizations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/data_repository.dart';
import '../services/deck_sharing_service.dart';
import '../theme/app_colors.dart';

class SharedDeckViewPage extends StatefulWidget {
  /// Se fornito, cerca direttamente il codice all'avvio.
  final String? initialCode;

  const SharedDeckViewPage({super.key, this.initialCode});

  @override
  State<SharedDeckViewPage> createState() => _SharedDeckViewPageState();
}

class _SharedDeckViewPageState extends State<SharedDeckViewPage> {
  final _codeCtrl = TextEditingController();
  final _repo = DataRepository();

  bool _loading = false;
  bool _importing = false;
  String? _error;
  Map<String, dynamic>? _deck;

  @override
  void initState() {
    super.initState();
    if (widget.initialCode != null) {
      _codeCtrl.text = widget.initialCode!.toUpperCase();
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Inserisci un codice');
      return;
    }
    setState(() { _loading = true; _error = null; _deck = null; });
    try {
      final result = await DeckSharingService.fetchDeck(code);
      if (!mounted) return;
      if (result == null) {
        setState(() { _error = 'Nessun deck trovato con il codice "$code"'; _loading = false; });
      } else {
        setState(() { _deck = result; _loading = false; });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'Errore: $e'; _loading = false; });
    }
  }

  Future<void> _importDeck() async {
    final deck = _deck;
    if (deck == null) return;

    final collectionKey = deck['collectionKey'] as String? ?? 'yugioh';
    final deckName = deck['deckName'] as String? ?? 'Deck importato';
    final rawCards = deck['cards'] as List<dynamic>? ?? [];

    // Check which cards the user owns
    final owned = await _repo.getCardsByCollection(collectionKey);
    final ownedByName = <String, int>{};
    for (final c in owned) {
      ownedByName[c.name.toLowerCase()] = c.id!;
    }

    final ownedInDeck = rawCards.where((c) {
      final name = (c as Map<String, dynamic>)['name']?.toString().toLowerCase() ?? '';
      return ownedByName.containsKey(name);
    }).toList();

    if (ownedInDeck.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.sharedDeckNoCards),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _importing = true);
    try {
      final newDeckId = await _repo.insertDeck('$deckName (importato)', collectionKey);
      for (final c in ownedInDeck) {
        final name = (c as Map<String, dynamic>)['name']?.toString().toLowerCase() ?? '';
        final qty = (c['quantity'] as int?) ?? 1;
        final cardId = ownedByName[name];
        if (cardId != null) {
          await _repo.addCardToDeck(newDeckId, cardId, qty);
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.sharedDeckImported(ownedInDeck.length)),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.sharedDeckTitle),
        backgroundColor: AppColors.bgMedium,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: AppColors.bgMedium,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _codeCtrl,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 4,
              ),
              onChanged: (v) => _codeCtrl.value = _codeCtrl.value.copyWith(
                text: v.toUpperCase(),
                selection: TextSelection.collapsed(offset: v.length),
              ),
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'XXXXXX',
                hintStyle: const TextStyle(
                  color: AppColors.textHint,
                  letterSpacing: 4,
                  fontSize: 20,
                ),
                counterText: '',
                prefixIcon: const Icon(Icons.qr_code_outlined, color: AppColors.gold),
                filled: true,
                fillColor: AppColors.bgLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: _loading ? null : _search,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('Cerca', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.gold));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 48, color: AppColors.textHint),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textHint)),
            ],
          ),
        ),
      );
    }
    if (_deck == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.link, size: 48, color: AppColors.textHint),
              const SizedBox(height: 12),
              const Text(
                'Inserisci il codice a 6 caratteri\nricevuto da un altro giocatore.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textHint),
              ),
            ],
          ),
        ),
      );
    }

    return _buildDeckView(_deck!);
  }

  Widget _buildDeckView(Map<String, dynamic> deck) {
    final name = deck['deckName'] as String? ?? 'Deck';
    final owner = deck['ownerName'] as String? ?? 'Anonimo';
    final collection = deck['collectionName'] as String? ?? '';
    final code = deck['shortCode'] as String? ?? '';
    final total = deck['totalCards'] as int? ?? 0;
    final rawCards = deck['cards'] as List<dynamic>? ?? [];
    final cards = rawCards.cast<Map<String, dynamic>>();

    return Column(
      children: [
        // Deck header
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bgMedium,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(name,
                        style: const TextStyle(color: AppColors.gold, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  // Copy code chip
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(AppLocalizations.of(context)!.sharedDeckCodeCopied), duration: const Duration(seconds: 2)),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.bgLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(code,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                              )),
                          const SizedBox(width: 6),
                          const Icon(Icons.copy, size: 12, color: AppColors.textHint),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(AppLocalizations.of(context)!.sharedDeckByOwner(owner, collection, total),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
        // Card grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.68,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: cards.length,
            itemBuilder: (_, i) {
              final card = cards[i];
              final cardName = card['name'] as String? ?? '?';
              final qty = card['quantity'] as int? ?? 1;
              final imageUrl = card['imageUrl'] as String?;
              return _CardCell(name: cardName, imageUrl: imageUrl, qty: qty);
            },
          ),
        ),
        // Import button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _importing ? null : _importDeck,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: _importing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download_outlined, size: 20),
              label: Text(
                _importing ? 'Importazione...' : 'Importa nelle mie carte',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CardCell extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final int qty;

  const _CardCell({required this.name, this.imageUrl, required this.qty});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: imageUrl != null
              ? CachedNetworkImage(
                  imageUrl: imageUrl!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  placeholder: (ctx, url) => Container(
                    color: AppColors.bgMedium,
                    child: const Center(child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.textHint)),
                  ),
                  errorWidget: (ctx, url, err) => _placeholder(name),
                )
              : _placeholder(name),
        ),
        if (qty > 1)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.blue,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('x$qty', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }

  Widget _placeholder(String name) {
    return Container(
      color: AppColors.bgMedium,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Text(
          name,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 9),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
