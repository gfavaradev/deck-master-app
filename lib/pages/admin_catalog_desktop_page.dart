import 'package:flutter/material.dart';
import 'package:deck_master/services/admin_catalog_service.dart';
import 'package:deck_master/models/pending_catalog_change.dart';
import 'package:deck_master/services/auth_service.dart';
import 'package:deck_master/utils/platform_helper.dart';
import 'dart:math';

/// Desktop-optimized admin interface for catalog management
/// Designed for Windows/Web with full database-style table view
class AdminCatalogDesktopPage extends StatefulWidget {
  const AdminCatalogDesktopPage({super.key});

  @override
  State<AdminCatalogDesktopPage> createState() => _AdminCatalogDesktopPageState();
}

class _AdminCatalogDesktopPageState extends State<AdminCatalogDesktopPage> {
  final AdminCatalogService _catalogService = AdminCatalogService();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _verticalScroll = ScrollController();

  List<PendingCatalogChange> _pendingChanges = [];
  List<Map<String, dynamic>> _allCards = [];
  List<Map<String, dynamic>> _filteredCards = [];
  bool _isLoading = false;
  bool _isDownloading = false;
  bool _isSyncing = false;
  double? _downloadProgress;

  String _searchQuery = '';
  String? _sortColumn;
  bool _sortAscending = true;

  // Table columns definition
  final List<TableColumn> _columns = [
    TableColumn('id', 'ID', width: 100, sortable: true),
    TableColumn('name', 'Nome', width: 250, sortable: true),
    TableColumn('type', 'Tipo', width: 120, sortable: true),
    TableColumn('archetype', 'Archetipo', width: 150, sortable: true),
    TableColumn('race', 'Razza', width: 120, sortable: true),
    TableColumn('attribute', 'Attributo', width: 100, sortable: true),
    TableColumn('atk', 'ATK', width: 80, sortable: true),
    TableColumn('def', 'DEF', width: 80, sortable: true),
    TableColumn('level', 'Level', width: 80, sortable: true),
    TableColumn('description', 'Descrizione', width: 300),
  ];

  @override
  void initState() {
    super.initState();
    _loadPendingChanges();
    _checkAndLoadCatalog();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _horizontalScroll.dispose();
    _verticalScroll.dispose();
    super.dispose();
  }

  Future<void> _loadPendingChanges() async {
    final changes = await _catalogService.getPendingChanges();
    if (mounted) {
      setState(() => _pendingChanges = changes);
    }
  }

  Future<void> _checkAndLoadCatalog() async {
    setState(() => _isLoading = true);

    try {
      // Try to load from local database first
      final results = await _catalogService.searchCards('');

      if (results.isEmpty) {
        // Show dialog to download full catalog
        if (mounted) {
          final shouldDownload = await _showDownloadDialog();
          if (shouldDownload == true) {
            await _downloadFullCatalog();
          }
        }
      } else {
        setState(() {
          _allCards = results;
          _filteredCards = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError('Errore caricamento: $e');
      }
    }
  }

  Future<bool?> _showDownloadDialog() {
    final isWeb = PlatformHelper.isWeb;

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.download, color: isWeb ? Colors.orange : Colors.blue),
            const SizedBox(width: 12),
            Text(isWeb ? 'Scarica da Firebase (Web)' : 'Catalogo Mancante'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isWeb) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Web: Nessun database locale. Devi scaricare da Firebase.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Text('Il catalogo delle carte non è presente.'),
            const SizedBox(height: 16),
            const Text('Vuoi scaricare l\'intero catalogo da Firebase?'),
            const SizedBox(height: 8),
            Text(
              isWeb
                  ? '⚠️ Su Web dovrai riscaricare ad ogni refresh.'
                  : 'Salvato localmente per accessi futuri.',
              style: TextStyle(
                fontSize: 12,
                color: isWeb ? Colors.orange : Colors.green,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.download),
            label: const Text('Scarica'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isWeb ? Colors.orange : Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadFullCatalog() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = null;
    });

    try {
      final catalog = await _catalogService.downloadCurrentCatalog(
        'yugioh',
        onProgress: (current, total) {
          if (mounted) {
            setState(() => _downloadProgress = current / total);
          }
        },
      );

      if (mounted) {
        setState(() {
          _allCards = catalog;
          _filteredCards = catalog;
          _isDownloading = false;
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scaricate ${catalog.length} carte')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _isLoading = false;
        });
        _showError('Errore download: $e');
      }
    }
  }

  void _filterCards(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredCards = _allCards;
      } else {
        _filteredCards = _allCards.where((card) {
          final name = card['name']?.toString().toLowerCase() ?? '';
          final id = card['id']?.toString() ?? '';
          final archetype = card['archetype']?.toString().toLowerCase() ?? '';
          final searchLower = query.toLowerCase();

          return name.contains(searchLower) ||
              id.contains(query) ||
              archetype.contains(searchLower);
        }).toList();
      }
    });
  }

  void _sortData(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }

      _filteredCards.sort((a, b) {
        final aVal = a[column];
        final bVal = b[column];

        if (aVal == null && bVal == null) return 0;
        if (aVal == null) return _sortAscending ? 1 : -1;
        if (bVal == null) return _sortAscending ? -1 : 1;

        int comparison;
        if (aVal is num && bVal is num) {
          comparison = aVal.compareTo(bVal);
        } else {
          comparison = aVal.toString().compareTo(bVal.toString());
        }

        return _sortAscending ? comparison : -comparison;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // Platform check - only show on desktop
    if (!PlatformHelper.isDesktop && !PlatformHelper.isWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gestione Catalogo')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.desktop_windows, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'Interfaccia Admin Desktop',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Questa pagina è ottimizzata per Windows e Web.\nUsa un dispositivo desktop per accedere.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: _buildAppBar(),
      body: Column(
        children: [
          if (_pendingChanges.isNotEmpty) _buildPendingBanner(),
          _buildToolbar(),
          if (_isLoading || _isDownloading) _buildLoadingIndicator(),
          if (!_isLoading && !_isDownloading) Expanded(child: _buildDataTable()),
        ],
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Row(
        children: [
          Icon(Icons.admin_panel_settings),
          SizedBox(width: 12),
          Text('Admin Catalogo - Vista Database'),
        ],
      ),
      backgroundColor: Colors.deepPurple,
      actions: [
        // Pending changes badge
        if (_pendingChanges.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.pending_actions, size: 16),
                const SizedBox(width: 6),
                Text('${_pendingChanges.length} modifiche'),
              ],
            ),
          ),

        // Sync button
        if (_pendingChanges.isNotEmpty)
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.cloud_upload),
            onPressed: _isSyncing ? null : _syncChanges,
            tooltip: 'Sincronizza con Firebase',
          ),

        // Refresh
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _checkAndLoadCatalog,
          tooltip: 'Ricarica catalogo',
        ),

        // Download full catalog
        IconButton(
          icon: const Icon(Icons.download),
          onPressed: _downloadFullCatalog,
          tooltip: 'Scarica catalogo completo',
        ),
      ],
    );
  }

  Widget _buildPendingBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      color: Colors.orange[50],
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${_pendingChanges.length} modifiche in sospeso - Le modifiche saranno applicate solo dopo la sincronizzazione',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          TextButton.icon(
            onPressed: _showPendingChangesDialog,
            icon: const Icon(Icons.visibility),
            label: const Text('Visualizza'),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        children: [
          // Search
          Expanded(
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              onChanged: _filterCards,
            ),
          ),
          const SizedBox(width: 16),

          // Results count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${_filteredCards.length} / ${_allCards.length} carte',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              _isDownloading ? 'Scaricamento catalogo...' : 'Caricamento...',
              style: const TextStyle(fontSize: 16),
            ),
            if (_downloadProgress != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: 300,
                child: LinearProgressIndicator(value: _downloadProgress),
              ),
              const SizedBox(height: 8),
              Text('${(_downloadProgress! * 100).toStringAsFixed(0)}%'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDataTable() {
    if (_filteredCards.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty
                  ? 'Nessuna carta nel database'
                  : 'Nessun risultato per "$_searchQuery"',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Scrollbar(
        controller: _horizontalScroll,
        thumbVisibility: true,
        child: Scrollbar(
          controller: _verticalScroll,
          thumbVisibility: true,
          notificationPredicate: (notif) => notif.depth == 1,
          child: SingleChildScrollView(
            controller: _horizontalScroll,
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              controller: _verticalScroll,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(Colors.deepPurple[50]),
                columns: _columns.map((col) => _buildDataColumn(col)).toList(),
                rows: _filteredCards.map((card) => _buildDataRow(card)).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  DataColumn _buildDataColumn(TableColumn column) {
    return DataColumn(
      label: InkWell(
        onTap: column.sortable ? () => _sortData(column.key) : null,
        child: Row(
          children: [
            Text(
              column.label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (column.sortable) ...[
              const SizedBox(width: 4),
              Icon(
                _sortColumn == column.key
                    ? (_sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
                    : Icons.unfold_more,
                size: 16,
                color: _sortColumn == column.key ? Colors.deepPurple : Colors.grey,
              ),
            ],
          ],
        ),
      ),
    );
  }

  DataRow _buildDataRow(Map<String, dynamic> card) {
    final hasPending = _pendingChanges.any((c) => c.originalCardId == card['id']);

    return DataRow(
      color: WidgetStateProperty.resolveWith<Color?>((states) {
        if (hasPending) return Colors.orange[50];
        if (states.contains(WidgetState.selected)) return Colors.blue[50];
        return null;
      }),
      cells: _columns.map((col) {
        final value = card[col.key];
        return DataCell(
          Container(
            width: col.width,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              value?.toString() ?? '-',
              overflow: TextOverflow.ellipsis,
              maxLines: col.key == 'description' ? 2 : 1,
            ),
          ),
          onTap: () => _editCard(card),
        );
      }).toList(),
      onSelectChanged: (_) => _editCard(card),
    );
  }

  Widget _buildFAB() {
    return FloatingActionButton.extended(
      onPressed: _addNewCard,
      icon: const Icon(Icons.add),
      label: const Text('Nuova Carta'),
      backgroundColor: Colors.deepPurple,
    );
  }

  Future<void> _editCard(Map<String, dynamic> card) async {
    final result = await _showCardEditorDialog(initialCard: card);

    if (result != null) {
      final uid = _authService.currentUserId ?? 'unknown';
      final change = PendingCatalogChange(
        changeId: _generateChangeId(),
        type: ChangeType.edit,
        cardData: result,
        originalCardId: card['id'] as int,
        timestamp: DateTime.now(),
        adminUid: uid,
      );

      await _catalogService.addPendingChange(change);
      await _loadPendingChanges();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Modifica aggiunta alla coda')),
        );
      }
    }
  }

  Future<void> _addNewCard() async {
    final result = await _showCardEditorDialog();

    if (result != null) {
      final uid = _authService.currentUserId ?? 'unknown';
      final change = PendingCatalogChange(
        changeId: _generateChangeId(),
        type: ChangeType.add,
        cardData: result,
        timestamp: DateTime.now(),
        adminUid: uid,
      );

      await _catalogService.addPendingChange(change);
      await _loadPendingChanges();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nuova carta aggiunta alla coda')),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _showCardEditorDialog({Map<String, dynamic>? initialCard}) async {
    final isEdit = initialCard != null;
    final nameController = TextEditingController(text: initialCard?['name'] ?? '');
    final typeController = TextEditingController(text: initialCard?['type'] ?? '');
    final archetypeController = TextEditingController(text: initialCard?['archetype'] ?? '');
    final raceController = TextEditingController(text: initialCard?['race'] ?? '');
    final attributeController = TextEditingController(text: initialCard?['attribute'] ?? '');
    final atkController = TextEditingController(text: initialCard?['atk']?.toString() ?? '');
    final defController = TextEditingController(text: initialCard?['def']?.toString() ?? '');
    final levelController = TextEditingController(text: initialCard?['level']?.toString() ?? '');
    final descController = TextEditingController(text: initialCard?['description'] ?? '');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Container(
          width: 900,
          height: 700,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isEdit ? Icons.edit : Icons.add_circle,
                    color: Colors.deepPurple,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEdit ? 'Modifica Carta' : 'Nuova Carta',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Basic info
                      const Text('Informazioni Base', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: nameController,
                              decoration: const InputDecoration(
                                labelText: 'Nome *',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: typeController,
                              decoration: const InputDecoration(
                                labelText: 'Tipo',
                                border: OutlineInputBorder(),
                                hintText: 'Monster Card',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: archetypeController,
                              decoration: const InputDecoration(
                                labelText: 'Archetipo',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: raceController,
                              decoration: const InputDecoration(
                                labelText: 'Razza',
                                border: OutlineInputBorder(),
                                hintText: 'Dragon, Spellcaster, etc.',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Stats
                      const Text('Statistiche', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: attributeController,
                              decoration: const InputDecoration(
                                labelText: 'Attributo',
                                border: OutlineInputBorder(),
                                hintText: 'DARK, LIGHT, etc.',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: atkController,
                              decoration: const InputDecoration(
                                labelText: 'ATK',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: defController,
                              decoration: const InputDecoration(
                                labelText: 'DEF',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: levelController,
                              decoration: const InputDecoration(
                                labelText: 'Level',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Description
                      const Text('Descrizione', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      TextField(
                        controller: descController,
                        decoration: const InputDecoration(
                          labelText: 'Descrizione Carta',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 4,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Annulla'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      if (nameController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(content: Text('Il nome è obbligatorio')),
                        );
                        return;
                      }

                      final cardData = {
                        if (isEdit) 'id': initialCard['id'],
                        'name': nameController.text.trim(),
                        'type': typeController.text.trim(),
                        'archetype': archetypeController.text.trim().isEmpty ? null : archetypeController.text.trim(),
                        'race': raceController.text.trim().isEmpty ? null : raceController.text.trim(),
                        'attribute': attributeController.text.trim().isEmpty ? null : attributeController.text.trim(),
                        'atk': atkController.text.trim().isEmpty ? null : int.tryParse(atkController.text.trim()),
                        'def': defController.text.trim().isEmpty ? null : int.tryParse(defController.text.trim()),
                        'level': levelController.text.trim().isEmpty ? null : int.tryParse(levelController.text.trim()),
                        'description': descController.text.trim(),
                      };

                      Navigator.pop(dialogContext, cardData);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                    child: Text(isEdit ? 'Salva Modifiche' : 'Aggiungi Carta'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    // Dispose controllers
    nameController.dispose();
    typeController.dispose();
    archetypeController.dispose();
    raceController.dispose();
    attributeController.dispose();
    atkController.dispose();
    defController.dispose();
    levelController.dispose();
    descController.dispose();

    return result;
  }

  Future<void> _showPendingChangesDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifiche in Sospeso'),
        content: SizedBox(
          width: 600,
          height: 400,
          child: ListView.builder(
            itemCount: _pendingChanges.length,
            itemBuilder: (context, index) {
              final change = _pendingChanges[index];
              return ListTile(
                leading: Icon(_getChangeIcon(change.type)),
                title: Text(_getChangeTitle(change)),
                subtitle: Text(_formatDate(change.timestamp)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncChanges() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sincronizza Modifiche'),
        content: Text(
          'Vuoi sincronizzare ${_pendingChanges.length} modifiche con Firebase?\n\n'
          'Questa operazione aggiornerà il catalogo per tutti gli utenti.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
            child: const Text('Sincronizza'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSyncing = true);

    try {
      final uid = _authService.currentUserId ?? 'unknown';
      final result = await _catalogService.publishChanges(
        adminUid: uid,
        onProgress: (current, total) {
          // Progress feedback via logs for now
          debugPrint('Sync progress: $current / $total');
        },
      );

      if (context.mounted) setState(() => _isSyncing = false);

      if (result['success'] == true) {
        await _loadPendingChanges();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Sincronizzato'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (context.mounted) {
        _showError(result['error'] ?? 'Errore sconosciuto');
      }
    } catch (e) {
      if (context.mounted) {
        setState(() => _isSyncing = false);
        _showError('Errore sincronizzazione: $e');
      }
    }
  }

  IconData _getChangeIcon(ChangeType type) {
    switch (type) {
      case ChangeType.add:
        return Icons.add_circle;
      case ChangeType.edit:
        return Icons.edit;
      case ChangeType.delete:
        return Icons.delete;
    }
  }

  String _getChangeTitle(PendingCatalogChange change) {
    switch (change.type) {
      case ChangeType.add:
        return 'Aggiungi: ${change.cardData['name'] ?? 'Nuova carta'}';
      case ChangeType.edit:
        return 'Modifica: ${change.cardData['name'] ?? 'ID ${change.originalCardId}'}';
      case ChangeType.delete:
        return 'Elimina: ID ${change.originalCardId}';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  String _generateChangeId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(99999);
    return '${timestamp}_$random';
  }
}

class TableColumn {
  final String key;
  final String label;
  final double width;
  final bool sortable;

  TableColumn(
    this.key,
    this.label, {
    this.width = 150,
    this.sortable = false,
  });
}
