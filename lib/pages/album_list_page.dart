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

class AlbumListPage extends StatefulWidget {
  final String collectionName;
  final String collectionKey;

  const AlbumListPage({
    super.key,
    required this.collectionName,
    required this.collectionKey,
  });

  @override
  State<AlbumListPage> createState() => _AlbumListPageState();
}

class _AlbumListPageState extends State<AlbumListPage> {
  final DataRepository _dbHelper = DataRepository();
  List<AlbumModel> _albums = [];
  bool _loading = true;
  StreamSubscription<String>? _syncSub;

  @override
  void initState() {
    super.initState();
    _refreshAlbums();
    _syncSub = SyncService().onRemoteChange.listen((_) {
      if (mounted) _refreshAlbums();
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshAlbums() async {
    final data = await _dbHelper.getAlbumsByCollection(widget.collectionKey);
    if (!mounted) return;
    setState(() {
      _albums = data;
      _loading = false;
    });
  }

  void _showAddAlbumDialog({AlbumModel? album}) {
    showDialog<AlbumModel>(
      context: context,
      builder: (ctx) => _AddAlbumDialog(
        album: album,
        collectionKey: widget.collectionKey,
      ),
    ).then((result) {
      if (result == null || !mounted) return;
      _saveAlbum(result, isEdit: album != null);
    });
  }

  Future<void> _saveAlbum(AlbumModel newAlbum, {required bool isEdit}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (isEdit) {
        await _dbHelper.updateAlbum(newAlbum);
      } else {
        await _dbHelper.insertAlbum(newAlbum);
      }
      if (mounted) _refreshAlbums();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Errore: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  void _showDeleteConfirmation(AlbumModel album) {
    final pageContext = context;
    showDialog<bool>(
      context: pageContext,
      builder: (_) => AppConfirmDialog(
        title: 'Elimina Album',
        icon: Icons.delete_outline,
        message: album.currentCount > 0
            ? 'Sei sicuro di voler eliminare "${album.name}"?\n\n'
                'Verranno eliminate anche tutte le ${album.currentCount} carte contenute in questo album.\n\n'
                'Questa azione non può essere annullata.'
            : 'Sei sicuro di voler eliminare "${album.name}"?',
        confirmLabel: 'Elimina',
      ),
    ).then((confirmed) async {
      if (confirmed != true) return;
      await _dbHelper.deleteAlbum(album.id!);
      if (!pageContext.mounted) return;
      _refreshAlbums();
      TopUndoBar.show(
        context: pageContext,
        message: 'Album "${album.name}" eliminato',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_albums.isEmpty) {
      body = const Center(child: Text('Nessun album creato.'));
    } else {
      body = ListView.builder(
        itemCount: _albums.length,
        itemBuilder: (_, index) {
          final album = _albums[index];
          return ListTile(
            leading: const Icon(Icons.book),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => Scaffold(
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
              );
            },
            title: Row(
              children: [
                Text(album.name),
                const SizedBox(width: 8),
                Text(
                  '${album.currentCount}/${album.maxCapacity}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.edit), onPressed: () => _showAddAlbumDialog(album: album)),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _showDeleteConfirmation(album),
                ),
              ],
            ),
          );
        },
      );
    }

    final isWide = MediaQuery.of(context).size.width > 600;
    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: true,
        child: isWide
            ? Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: body))
            : body,
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        onPressed: () => _showAddAlbumDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ─── Dialog widget ────────────────────────────────────────────────────────────
// StatefulWidget dedicato: i controller vengono creati in initState() e
// distrutti dal framework in dispose(), dopo che l'animazione di chiusura
// è completata. Questo evita "used after being disposed" e _dependents assertion.

class _AddAlbumDialog extends StatefulWidget {
  final AlbumModel? album;
  final String collectionKey;

  const _AddAlbumDialog({this.album, required this.collectionKey});

  @override
  State<_AddAlbumDialog> createState() => _AddAlbumDialogState();
}

class _AddAlbumDialogState extends State<_AddAlbumDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _capacityController;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.album?.name);
    _capacityController = TextEditingController(
      text: widget.album != null ? widget.album!.maxCapacity.toString() : '100',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _nameError = 'Il nome è obbligatorio');
      return;
    }
    final result = AlbumModel(
      id: widget.album?.id,
      name: _nameController.text.trim(),
      collection: widget.collectionKey,
      maxCapacity: int.tryParse(_capacityController.text) ?? 100,
    );
    Navigator.pop(context, result);
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
            // ── Header ──────────────────────────────────────────────────────
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
                      color: AppColors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isEdit ? Icons.edit_outlined : Icons.create_new_folder_outlined,
                      color: AppColors.blue,
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

            // ── Campi ───────────────────────────────────────────────────────
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
                      controller: _nameController,
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
                        prefixIcon: const Icon(Icons.book_outlined, color: AppColors.blue, size: 20),
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
                      controller: _capacityController,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        hintText: '100',
                        hintStyle: const TextStyle(color: AppColors.textHint),
                        prefixIcon: const Icon(Icons.layers_outlined, color: AppColors.blue, size: 20),
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
                          borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
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

            // ── Azioni ──────────────────────────────────────────────────────
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Annulla'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
