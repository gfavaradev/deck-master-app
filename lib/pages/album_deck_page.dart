import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/album_model.dart';
import '../services/data_repository.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_dialog.dart';
import '../widgets/top_undo_bar.dart';
import 'card_list_page.dart';
import 'deck_detail_page.dart';

class AlbumDeckPage extends StatefulWidget {
  final String collectionName;
  final String collectionKey;

  const AlbumDeckPage({
    super.key,
    required this.collectionName,
    required this.collectionKey,
  });

  @override
  State<AlbumDeckPage> createState() => _AlbumDeckPageState();
}

class _AlbumDeckPageState extends State<AlbumDeckPage>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  late final AnimationController _fabAnim;

  final DataRepository _repo = DataRepository();

  List<AlbumModel> _albums = [];
  bool _loadingAlbums = true;
  List<Map<String, dynamic>> _decks = [];
  bool _loadingDecks = true;
  bool _fabExpanded = false;

  StreamSubscription<String>? _syncSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fabAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _refreshAlbums();
    _refreshDecks();
    _syncSub = SyncService().onRemoteChange.listen((_) {
      if (mounted) {
        _refreshAlbums();
        _refreshDecks();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fabAnim.dispose();
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshAlbums() async {
    final data = await _repo.getAlbumsByCollection(widget.collectionKey);
    if (!mounted) return;
    setState(() {
      _albums = data;
      _loadingAlbums = false;
    });
  }

  Future<void> _refreshDecks() async {
    final data = await _repo.getDecksByCollection(widget.collectionKey);
    if (!mounted) return;
    setState(() {
      _decks = data;
      _loadingDecks = false;
    });
  }

  // ── Album CRUD ─────────────────────────────────────────────────────────────

  void _showAddAlbumDialog({AlbumModel? album}) {
    showDialog<AlbumModel>(
      context: context,
      builder: (_) => _AlbumDialog(album: album, collectionKey: widget.collectionKey),
    ).then((result) {
      if (result == null || !mounted) return;
      _saveAlbum(result, isEdit: album != null);
    });
  }

  Future<void> _saveAlbum(AlbumModel album, {required bool isEdit}) async {
    try {
      if (isEdit) {
        await _repo.updateAlbum(album);
      } else {
        await _repo.insertAlbum(album);
      }
      if (mounted) _refreshAlbums();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _confirmDeleteAlbum(AlbumModel album) {
    showDialog<bool>(
      context: context,
      builder: (_) => AppConfirmDialog(
        title: 'Elimina Album',
        icon: Icons.delete_outline,
        message: album.currentCount > 0
            ? 'Sei sicuro di voler eliminare "${album.name}"?\n\n'
                'Verranno eliminate anche tutte le ${album.currentCount} carte contenute.\n\n'
                'Questa azione non può essere annullata.'
            : 'Sei sicuro di voler eliminare "${album.name}"?',
        confirmLabel: 'Elimina',
      ),
    ).then((confirmed) async {
      if (confirmed != true) return;
      await _repo.deleteAlbum(album.id!);
      if (!mounted) return;
      _refreshAlbums();
      TopUndoBar.show(context: context, message: 'Album "${album.name}" eliminato');
    });
  }

  // ── Deck CRUD ──────────────────────────────────────────────────────────────

  Future<void> _showAddDeckDialog() async {
    final deckName = await showDialog<String>(
      context: context,
      builder: (_) => const _DeckDialog(),
    );
    if (deckName == null || !mounted) return;
    await _repo.insertDeck(deckName, widget.collectionKey);
    _refreshDecks();
  }

  Future<void> _confirmDeleteDeck(Map<String, dynamic> deck) async {
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
    await _repo.deleteDeck(deck['id']);
    if (!mounted) return;
    _refreshDecks();
    TopUndoBar.show(context: context, message: 'Deck "${deck['name']}" eliminato');
  }

  // ── FAB ────────────────────────────────────────────────────────────────────

  void _toggleFab() {
    setState(() => _fabExpanded = !_fabExpanded);
    if (_fabExpanded) {
      _fabAnim.forward();
    } else {
      _fabAnim.reverse();
    }
  }

  void _closeFab() {
    if (!_fabExpanded) return;
    setState(() => _fabExpanded = false);
    _fabAnim.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;

    Widget albumContent;
    if (_loadingAlbums) {
      albumContent = const Center(child: CircularProgressIndicator());
    } else if (_albums.isEmpty) {
      albumContent = const Center(child: Text('Nessun album creato.'));
    } else {
      albumContent = ListView.builder(
        itemCount: _albums.length,
        itemBuilder: (_, i) {
          final album = _albums[i];
          return ListTile(
            leading: const Icon(Icons.book, color: AppColors.gold),
            title: Row(
              children: [
                Flexible(child: Text(album.name)),
                const SizedBox(width: 8),
                Text(
                  '${album.currentCount}/${album.maxCapacity}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(
                    title: Text(album.name),
                    backgroundColor: AppColors.bgMedium,
                    foregroundColor: AppColors.textPrimary,
                  ),
                  body: CardListPage(
                    collectionName: widget.collectionName,
                    collectionKey: widget.collectionKey,
                    albumId: album.id,
                  ),
                ),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _showAddAlbumDialog(album: album),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  onPressed: () => _confirmDeleteAlbum(album),
                ),
              ],
            ),
          );
        },
      );
    }

    Widget deckContent;
    if (_loadingDecks) {
      deckContent = const Center(child: CircularProgressIndicator());
    } else if (_decks.isEmpty) {
      deckContent = const Center(child: Text('Nessun deck creato.'));
    } else {
      deckContent = ListView.builder(
        itemCount: _decks.length,
        itemBuilder: (_, i) {
          final deck = _decks[i];
          return ListTile(
            leading: const Icon(Icons.style, color: AppColors.blue),
            title: Text(deck['name']),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red, size: 20),
              onPressed: () => _confirmDeleteDeck(deck),
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DeckDetailPage(
                  deckId: deck['id'],
                  deckName: deck['name'],
                  collectionKey: widget.collectionKey,
                ),
              ),
            ),
          );
        },
      );
    }

    if (isWide) {
      albumContent = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: albumContent,
        ),
      );
      deckContent = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: deckContent,
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            top: false,
            bottom: true,
            child: Column(
              children: [
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: AppColors.bgMedium,
                    border: Border(
                      bottom: BorderSide(color: AppColors.divider, width: 0.5),
                    ),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: AppColors.gold,
                    unselectedLabelColor: AppColors.textHint,
                    indicatorColor: AppColors.gold,
                    indicatorWeight: 2,
                    labelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    tabs: const [
                      Tab(
                        text: 'Album',
                        icon: Icon(Icons.book_outlined, size: 18),
                      ),
                      Tab(
                        text: 'Deck',
                        icon: Icon(Icons.style_outlined, size: 18),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [albumContent, deckContent],
                  ),
                ),
              ],
            ),
          ),
          // Backdrop dismisses FAB when tapping outside
          if (_fabExpanded)
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeFab,
                child: AnimatedBuilder(
                  animation: _fabAnim,
                  builder: (context, child) => Container(
                    color: Colors.black.withValues(alpha: 0.45 * _fabAnim.value),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _buildFab(),
    );
  }

  Widget _buildFab() {
    return AnimatedBuilder(
      animation: _fabAnim,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Options: fade + slide up
            IgnorePointer(
              ignoring: !_fabExpanded,
              child: Opacity(
                opacity: _fabAnim.value,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - _fabAnim.value)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _FabOption(
                        icon: Icons.style_outlined,
                        label: 'Nuovo Deck',
                        color: AppColors.blue,
                        onTap: () {
                          _closeFab();
                          Future.delayed(
                            const Duration(milliseconds: 180),
                            _showAddDeckDialog,
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      _FabOption(
                        icon: Icons.book_outlined,
                        label: 'Nuovo Album',
                        color: AppColors.gold,
                        onTap: () {
                          _closeFab();
                          Future.delayed(
                            const Duration(milliseconds: 180),
                            () => _showAddAlbumDialog(),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
            // Main FAB
            FloatingActionButton(
              heroTag: 'album_deck_fab',
              onPressed: _toggleFab,
              backgroundColor: Color.lerp(
                AppColors.gold,
                AppColors.bgLight,
                _fabAnim.value,
              ),
              foregroundColor: Color.lerp(
                Colors.black,
                Colors.white,
                _fabAnim.value,
              ),
              elevation: 6,
              child: Transform.rotate(
                angle: _fabAnim.value * 0.7854, // 45°
                child: const Icon(Icons.add, size: 28),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── FAB Option ───────────────────────────────────────────────────────────────

class _FabOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _FabOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.bgMedium,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: color.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
                BoxShadow(
                  color: color.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, size: 18, color: Colors.black),
          ),
        ],
      ),
    );
  }
}

// ─── Album Dialog ─────────────────────────────────────────────────────────────

class _AlbumDialog extends StatefulWidget {
  final AlbumModel? album;
  final String collectionKey;

  const _AlbumDialog({this.album, required this.collectionKey});

  @override
  State<_AlbumDialog> createState() => _AlbumDialogState();
}

class _AlbumDialogState extends State<_AlbumDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _capacityCtrl;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.album?.name);
    _capacityCtrl = TextEditingController(
      text: widget.album != null ? widget.album!.maxCapacity.toString() : '100',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _capacityCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _nameError = 'Il nome è obbligatorio');
      return;
    }
    Navigator.pop(
      context,
      AlbumModel(
        id: widget.album?.id,
        name: _nameCtrl.text.trim(),
        collection: widget.collectionKey,
        maxCapacity: int.tryParse(_capacityCtrl.text) ?? 100,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.album != null;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: AppColors.bgMedium,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
              decoration: const BoxDecoration(
                color: AppColors.bgLight,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isEdit ? Icons.edit_outlined : Icons.create_new_folder_outlined,
                      color: AppColors.gold,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEdit ? 'Modifica Album' : 'Nuovo Album',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppColors.textHint, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            Container(height: 0.5, color: AppColors.divider),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'NOME ALBUM',
                      style: TextStyle(
                        color: AppColors.textHint,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameCtrl,
                      autofocus: true,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                        LengthLimitingTextInputFormatter(19),
                      ],
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Es. CollezioneBase',
                        hintStyle: const TextStyle(color: AppColors.textHint),
                        errorText: _nameError,
                        prefixIcon: const Icon(Icons.book_outlined, color: AppColors.gold, size: 20),
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
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.error),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 13,
                        ),
                      ),
                      onChanged: (_) {
                        if (_nameError != null) setState(() => _nameError = null);
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'CAPACITÀ MASSIMA',
                      style: TextStyle(
                        color: AppColors.textHint,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _capacityCtrl,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        hintText: '100',
                        hintStyle: const TextStyle(color: AppColors.textHint),
                        prefixIcon: const Icon(Icons.layers_outlined, color: AppColors.gold, size: 20),
                        suffixText: 'carte',
                        suffixStyle: const TextStyle(color: AppColors.textHint, fontSize: 13),
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
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Imposta 0 per nessun limite.',
                      style: TextStyle(color: AppColors.textHint, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Annulla'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(isEdit ? 'Salva' : 'Crea Album'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Deck Dialog ──────────────────────────────────────────────────────────────

class _DeckDialog extends StatefulWidget {
  const _DeckDialog();

  @override
  State<_DeckDialog> createState() => _DeckDialogState();
}

class _DeckDialogState extends State<_DeckDialog> {
  final _nameCtrl = TextEditingController();
  String? _nameError;

  @override
  void dispose() {
    _nameCtrl.dispose();
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
            controller: _nameCtrl,
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
                borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.error),
              ),
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
            final name = _nameCtrl.text.trim();
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
