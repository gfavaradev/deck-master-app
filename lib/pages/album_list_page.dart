import 'package:flutter/material.dart';
import '../models/album_model.dart';
import '../services/data_repository.dart';
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

  @override
  void initState() {
    super.initState();
    _refreshAlbums();
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

  Color _getOccupancyColor(int current, int max) {
    if (max == 0) return Colors.green;
    double ratio = current / max;
    if (ratio >= 1.0) return Colors.red;
    if (ratio >= 0.6) return Colors.amber;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Album ${widget.collectionName}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
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
                        builder: (context) => CardListPage(
                          collectionName: widget.collectionName,
                          collectionKey: widget.collectionKey,
                          albumId: album.id,
                        ),
                      ),
                    );
                  },
                  title: Text(album.name),
                  subtitle: Text(
                    'Occupazione: ${album.currentCount}/${album.maxCapacity} carte',
                    style: TextStyle(
                      color: _getOccupancyColor(album.currentCount, album.maxCapacity),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit), onPressed: () => _showAddAlbumDialog(album: album)),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          await _dbHelper.deleteAlbum(album.id!);
                          if (mounted) _refreshAlbums();
                        },
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
