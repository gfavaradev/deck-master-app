import 'dart:async';
import 'package:flutter/material.dart';
import '../models/album_model.dart';
import '../services/data_repository.dart';
import '../services/sync_service.dart';
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
    setState(() {
      _albums = data;
    });
  }

  void _showAddAlbumDialog({AlbumModel? album}) {
    final nameController = TextEditingController(text: album?.name);
    final capacityController = TextEditingController(text: album?.maxCapacity.toString() ?? '100');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(album == null ? 'Nuovo Album' : 'Modifica Album'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nome Album')),
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
              final newAlbum = AlbumModel(
                id: album?.id,
                name: nameController.text,
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
    );
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
    return Scaffold(
      body: _albums.isEmpty
          ? const Center(child: Text('Nessun album creato.'))
          : ListView.builder(
              itemCount: _albums.length,
              itemBuilder: (context, index) {
                final album = _albums[index];
                return ListTile(
                  leading: const Icon(Icons.book),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => Scaffold(
                          appBar: AppBar(
                            title: Text(album.name),
                            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddAlbumDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
