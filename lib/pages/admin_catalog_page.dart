import 'package:flutter/material.dart';
import 'package:deck_master/services/admin_catalog_service.dart';
import 'package:deck_master/models/pending_catalog_change.dart';
import 'package:deck_master/services/auth_service.dart';
import 'package:deck_master/widgets/admin_card_edit_dialog.dart';
import 'package:deck_master/theme/app_colors.dart';
import 'dart:math';

/// Admin page for managing Yu-Gi-Oh catalog
class AdminCatalogPage extends StatefulWidget {
  const AdminCatalogPage({super.key});

  @override
  State<AdminCatalogPage> createState() => _AdminCatalogPageState();
}

class _AdminCatalogPageState extends State<AdminCatalogPage> {
  final AdminCatalogService _catalogService = AdminCatalogService();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();

  List<PendingCatalogChange> _pendingChanges = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  String _generateChangeId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(99999);
    return '${timestamp}_$random';
  }

  @override
  void initState() {
    super.initState();
    _loadPendingChanges();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPendingChanges() async {
    final changes = await _catalogService.getPendingChanges();
    if (mounted) setState(() => _pendingChanges = changes);
  }

  Future<void> _searchCards(String query) async {
    if (query.trim().isEmpty) {
      setState(() { _searchResults = []; _isSearching = false; });
      return;
    }
    setState(() => _isSearching = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final results = await _catalogService.searchCards(query);
      if (mounted) setState(() { _searchResults = results; _isSearching = false; });
    } catch (e) { // ignore: empty_catches
      if (mounted) {
        setState(() => _isSearching = false);
        messenger.showSnackBar(SnackBar(content: Text('Errore ricerca: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestione Catalogo'),
        actions: [
          if (_pendingChanges.isNotEmpty)
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.publish),
                  onPressed: _publishChanges,
                  tooltip: 'Pubblica modifiche',
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: Text(
                      '${_pendingChanges.length}',
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPendingChanges,
            tooltip: 'Ricarica',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          if (_pendingChanges.isNotEmpty) _buildPendingChangesBanner(),
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _searchResults.isEmpty
                    ? _buildEmptyState()
                    : _buildSearchResults(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCardDialog,
        icon: const Icon(Icons.add),
        label: const Text('Nuova Carta'),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Cerca carta (nome, archetipo, ID)...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () { _searchController.clear(); _searchCards(''); },
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onChanged: _searchCards,
      ),
    );
  }

  Widget _buildPendingChangesBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.deepPurple.withValues(alpha: 0.15),
      child: Row(
        children: [
          const Icon(Icons.pending_actions, color: Colors.deepPurple),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${_pendingChanges.length} modifica/e in sospeso',
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
          ),
          TextButton(
            onPressed: _showPendingChangesDialog,
            child: const Text('Visualizza', style: TextStyle(color: Colors.deepPurple)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search, size: 64, color: AppColors.textHint),
          const SizedBox(height: 16),
          const Text(
            'Cerca una carta o aggiungi una nuova',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) => _buildCardTile(_searchResults[index]),
    );
  }

  Widget _buildCardTile(Map<String, dynamic> card) {
    final hasPendingChange = _pendingChanges.any((c) => c.originalCardId == card['id']);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: hasPendingChange
              ? Colors.deepPurple.withValues(alpha: 0.25)
              : AppColors.blue.withValues(alpha: 0.2),
          child: Text(
            card['id'].toString().padRight(2).substring(0, 2),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: hasPendingChange ? Colors.deepPurple : AppColors.blue,
            ),
          ),
        ),
        title: Text(
          card['name'] ?? 'Sconosciuto',
          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ID: ${card['id']} • ${card['type'] ?? ''}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            if (card['archetype'] != null)
              Text(
                'Archetipo: ${card['archetype']}',
                style: const TextStyle(color: AppColors.textHint, fontSize: 12),
              ),
            if (hasPendingChange)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.4)),
                ),
                child: const Text(
                  'MODIFICHE IN SOSPESO',
                  style: TextStyle(fontSize: 10, color: Colors.deepPurple, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleCardAction(value, card),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(children: [
                Icon(Icons.edit, size: 20),
                SizedBox(width: 8),
                Text('Modifica'),
              ]),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(children: [
                Icon(Icons.delete, size: 20, color: Colors.red),
                SizedBox(width: 8),
                Text('Elimina', style: TextStyle(color: Colors.red)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleCardAction(String action, Map<String, dynamic> card) async {
    switch (action) {
      case 'edit': _showEditCardDialog(card);
      case 'delete': _deleteCard(card);
    }
  }

  Future<void> _showAddCardDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const AdminCardEditDialog(),
    );
    if (result != null) {
      final uid = _authService.currentUserId ?? 'unknown';
      await _catalogService.addPendingChange(PendingCatalogChange(
        changeId: _generateChangeId(),
        type: ChangeType.add,
        cardData: result,
        timestamp: DateTime.now(),
        adminUid: uid,
      ));
      await _loadPendingChanges();
      if (mounted) messenger.showSnackBar(const SnackBar(content: Text('Carta aggiunta alle modifiche')));
    }
  }

  Future<void> _showEditCardDialog(Map<String, dynamic> card) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AdminCardEditDialog(initialCard: card),
    );
    if (result != null) {
      final uid = _authService.currentUserId ?? 'unknown';
      await _catalogService.addPendingChange(PendingCatalogChange(
        changeId: _generateChangeId(),
        type: ChangeType.edit,
        cardData: result,
        originalCardId: card['id'] is num ? (card['id'] as num).toInt() : null,
        timestamp: DateTime.now(),
        adminUid: uid,
      ));
      await _loadPendingChanges();
      if (mounted) messenger.showSnackBar(const SnackBar(content: Text('Modifica aggiunta')));
    }
  }

  Future<void> _deleteCard(Map<String, dynamic> card) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conferma eliminazione'),
        content: Text('Vuoi eliminare "${card['name']}"?\nLa carta sarà rimossa al prossimo aggiornamento.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final uid = _authService.currentUserId ?? 'unknown';
      await _catalogService.addPendingChange(PendingCatalogChange(
        changeId: _generateChangeId(),
        type: ChangeType.delete,
        cardData: {},
        originalCardId: card['id'] is num ? (card['id'] as num).toInt() : null,
        timestamp: DateTime.now(),
        adminUid: uid,
      ));
      await _loadPendingChanges();
      if (mounted) messenger.showSnackBar(const SnackBar(content: Text('Eliminazione aggiunta alle modifiche')));
    }
  }

  Future<void> _showPendingChangesDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifiche in sospeso'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _pendingChanges.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final change = _pendingChanges[index];
              return ListTile(
                leading: Icon(_getChangeIcon(change.type),
                    color: change.type == ChangeType.delete ? Colors.red : Colors.deepPurple),
                title: Text(_getChangeTitle(change)),
                subtitle: Text(_formatDate(change.timestamp),
                    style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  onPressed: () async {
                    await _catalogService.removePendingChange(change.changeId);
                    await _loadPendingChanges();
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Chiudi')),
        ],
      ),
    );
  }

  IconData _getChangeIcon(ChangeType type) => switch (type) {
        ChangeType.add => Icons.add_circle,
        ChangeType.edit => Icons.edit,
        ChangeType.delete => Icons.delete,
      };

  String _getChangeTitle(PendingCatalogChange change) => switch (change.type) {
        ChangeType.add => 'Aggiungi: ${change.cardData['name'] ?? 'Nuova carta'}',
        ChangeType.edit => 'Modifica: ${change.cardData['name'] ?? 'ID ${change.originalCardId}'}',
        ChangeType.delete => 'Elimina: ID ${change.originalCardId}',
      };

  String _formatDate(DateTime date) =>
      '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';

  Future<void> _publishChanges() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pubblica modifiche'),
        content: Text(
          'Vuoi pubblicare ${_pendingChanges.length} modifica/e su Firestore?\n\n'
          'Tutti gli utenti riceveranno una notifica dell\'aggiornamento.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Pubblica')),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return;
    try {
      final uid = _authService.currentUserId ?? 'unknown';
      final result = await _catalogService.publishChanges(
        adminUid: uid,
        onProgress: (current, total) {},
      );
      if (result['success'] == true) {
        await _loadPendingChanges();
        messenger.showSnackBar(SnackBar(content: Text(result['message'] ?? 'Pubblicato con successo')));
      } else {
        messenger.showSnackBar(SnackBar(content: Text('Errore: ${result['error']}')));
      }
    } catch (e) { // ignore: empty_catches
      messenger.showSnackBar(SnackBar(content: Text('Errore pubblicazione: $e')));
    }
  }
}
