import 'package:flutter/material.dart';
import '../services/admin_catalog_service.dart';
import '../services/auth_service.dart';
import '../models/pending_catalog_change.dart';
import '../widgets/admin_card_edit_dialog.dart';
import 'dart:math';

/// Admin page for managing a specific catalog's cards (Firestore-only, no SQLite)
class AdminCollectionPage extends StatefulWidget {
  final String collectionKey;
  final String collectionName;

  const AdminCollectionPage({
    super.key,
    required this.collectionKey,
    required this.collectionName,
  });

  @override
  State<AdminCollectionPage> createState() => _AdminCollectionPageState();
}

class _AdminCollectionPageState extends State<AdminCollectionPage> {
  final AdminCatalogService _catalogService = AdminCatalogService();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _allCards = [];
  List<Map<String, dynamic>> _filteredCards = [];
  List<PendingCatalogChange> _pendingChanges = [];
  bool _isLoading = true;
  double? _loadProgress;
  String _loadStatus = 'Caricamento...';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadProgress = null;
      _loadStatus = 'Connessione a Firestore...';
    });

    try {
      final pending = await _catalogService.getPendingChanges();
      final cards = await _catalogService.downloadCurrentCatalog(
        widget.collectionKey,
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _loadProgress = total > 0 ? current / total : null;
              _loadStatus = 'Scaricando chunk $current/$total...';
            });
          }
        },
      );

      if (!mounted) return;
      setState(() {
        _allCards = cards;
        _filteredCards = cards;
        _pendingChanges = pending;
        _isLoading = false;
        _loadStatus = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadStatus = 'Errore: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore caricamento: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _filterCards(String query) {
    final q = query.toLowerCase().trim();
    setState(() {
      _filteredCards = q.isEmpty
          ? _allCards
          : _allCards.where((c) {
              final name = (c['name'] ?? '').toString().toLowerCase();
              final id = (c['id'] ?? '').toString();
              final archetype = (c['archetype'] ?? '').toString().toLowerCase();
              return name.contains(q) || id.contains(q) || archetype.contains(q);
            }).toList();
    });
  }

  String _generateChangeId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(9999);
    return '${timestamp}_$random';
  }

  Future<void> _editCard(Map<String, dynamic> card) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => AdminCardEditDialog(initialCard: {
        ...card,
        'catalog': widget.collectionKey,
      }),
    );
    if (result == null) return;

    final adminUid = _authService.currentUserId ?? 'unknown';
    final change = PendingCatalogChange(
      changeId: _generateChangeId(),
      type: ChangeType.edit,
      cardData: result,
      originalCardId: (card['id'] as num?)?.toInt(),
      timestamp: DateTime.now(),
      adminUid: adminUid,
    );

    try {
      await _catalogService.addPendingChange(change);
      if (!mounted) return;
      setState(() {
        final idx = _allCards.indexWhere((c) => c['id'] == card['id']);
        if (idx >= 0) _allCards[idx] = result;
        _pendingChanges = [..._pendingChanges, change];
        _filterCards(_searchController.text);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Modifica in attesa di pubblicazione'), duration: Duration(seconds: 2)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore salvataggio: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _addCard() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => AdminCardEditDialog(initialCard: {'catalog': widget.collectionKey}),
    );
    if (result == null) return;

    final adminUid = _authService.currentUserId ?? 'unknown';
    final change = PendingCatalogChange(
      changeId: _generateChangeId(),
      type: ChangeType.add,
      cardData: result,
      timestamp: DateTime.now(),
      adminUid: adminUid,
    );

    try {
      await _catalogService.addPendingChange(change);
      if (!mounted) return;
      setState(() {
        _allCards.add(result);
        _pendingChanges = [..._pendingChanges, change];
        _filterCards(_searchController.text);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Carta aggiunta — in attesa di pubblicazione'), duration: Duration(seconds: 2)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore salvataggio: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteCard(Map<String, dynamic> card) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Elimina Carta'),
        content: Text('Eliminare "${card['name']}" dal catalogo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elimina', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final adminUid = _authService.currentUserId ?? 'unknown';
    final change = PendingCatalogChange(
      changeId: _generateChangeId(),
      type: ChangeType.delete,
      cardData: {},
      originalCardId: (card['id'] as num?)?.toInt(),
      timestamp: DateTime.now(),
      adminUid: adminUid,
    );

    try {
      await _catalogService.addPendingChange(change);
      if (!mounted) return;
      setState(() {
        _allCards.removeWhere((c) => c['id'] == card['id']);
        _pendingChanges = [..._pendingChanges, change];
        _filterCards(_searchController.text);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore eliminazione: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _publishChanges() async {
    if (_pendingChanges.isEmpty) return;

    final adminUid = _authService.currentUserId;
    if (adminUid == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Pubblica Modifiche'),
        content: Text('Pubblicare ${_pendingChanges.length} modifiche su Firestore?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('Pubblica'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      await _catalogService.publishChanges(
        adminUid: adminUid,
        onProgress: (current, total) {
          if (mounted) setState(() => _loadStatus = 'Pubblicando $current/$total...');
        },
      );
      if (!mounted) return;
      setState(() {
        _pendingChanges = [];
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Modifiche pubblicate con successo!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore pubblicazione: $e'), backgroundColor: Colors.red),
      );
    }
  }

  bool _hasPendingChange(Map<String, dynamic> card) {
    return _pendingChanges.any((c) => c.originalCardId == card['id']);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.collectionName),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          if (_pendingChanges.isNotEmpty)
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.upload),
                  tooltip: 'Pubblica modifiche',
                  onPressed: _publishChanges,
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                    child: Text(
                      '${_pendingChanges.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Ricarica',
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_loadProgress != null)
                    SizedBox(
                      width: 240,
                      child: LinearProgressIndicator(value: _loadProgress),
                    )
                  else
                    const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_loadStatus, style: const TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Cerca per nome, ID o archetipo...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _filterCards('');
                              },
                            )
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: _filterCards,
                  ),
                ),
                // Count
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        '${_filteredCards.length} / ${_allCards.length} carte',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                      if (_pendingChanges.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_pendingChanges.length} modifiche in attesa',
                            style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Card list
                Expanded(
                  child: _filteredCards.isEmpty
                      ? const Center(child: Text('Nessuna carta trovata'))
                      : ListView.builder(
                          itemCount: _filteredCards.length,
                          itemBuilder: (context, index) {
                            final card = _filteredCards[index];
                            final isPending = _hasPendingChange(card);
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isPending
                                    ? Colors.orange.shade100
                                    : Colors.deepPurple.shade50,
                                child: Icon(
                                  Icons.style,
                                  color: isPending ? Colors.orange : Colors.deepPurple,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                card['name'] ?? 'Sconosciuto',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isPending ? Colors.orange.shade800 : null,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  if (card['id'] != null) '#${card['id']}',
                                  if (card['type'] != null) card['type'],
                                  if (card['archetype'] != null && card['archetype'] != '') card['archetype'],
                                ].join(' • '),
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (action) {
                                  if (action == 'edit') _editCard(card);
                                  if (action == 'delete') _deleteCard(card);
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Modifica')])),
                                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text('Elimina', style: TextStyle(color: Colors.red))])),
                                ],
                              ),
                              onTap: () => _editCard(card),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCard,
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nuova Carta'),
      ),
    );
  }
}
