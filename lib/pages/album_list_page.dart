import 'dart:async';
import 'package:flutter/material.dart';
import '../models/album_model.dart';
import '../services/data_repository.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
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
    final nameController = TextEditingController(text: album?.name);
    final capacityController = TextEditingController(
      text: album?.maxCapacity.toString() ?? '100',
    );
    String? nameError;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(album == null ? 'Nuovo Album' : 'Modifica Album'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Nome Album',
                  errorText: nameError,
                ),
                onChanged: (_) {
                  if (nameError != null) setDialogState(() => nameError = null);
                },
              ),
              TextField(
                controller: capacityController,
                decoration: const InputDecoration(labelText: 'Capacità Massima'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  setDialogState(() => nameError = 'Il nome è obbligatorio');
                  return;
                }
                final newAlbum = AlbumModel(
                  id: album?.id,
                  name: nameController.text.trim(),
                  collection: widget.collectionKey,
                  maxCapacity: int.tryParse(capacityController.text) ?? 100,
                );
                if (album == null) {
                  await _dbHelper.insertAlbum(newAlbum);
                } else {
                  await _dbHelper.updateAlbum(newAlbum);
                }
                if (!context.mounted) return;
                Navigator.pop(context);
                _refreshAlbums();
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    ).then((_) {
      nameController.dispose();
      capacityController.dispose();
    });
  }

  void _showDeleteConfirmation(AlbumModel album) {
    final pageContext = context;
    showDialog(
      context: pageContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Elimina Album'),
        content: Text(
          album.currentCount > 0
              ? 'Sei sicuro di voler eliminare "${album.name}"?\n\n'
                  'Verranno eliminate anche tutte le ${album.currentCount} carte contenute in questo album.\n\n'
                  'Questa azione non può essere annullata.'
              : 'Sei sicuro di voler eliminare "${album.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _dbHelper.deleteAlbum(album.id!);
              if (!pageContext.mounted) return;
              _refreshAlbums();
              ScaffoldMessenger.of(pageContext).showSnackBar(
                SnackBar(content: Text('Album "${album.name}" eliminato')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Elimina', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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

    return Scaffold(
      body: body,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddAlbumDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
