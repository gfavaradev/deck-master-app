import 'package:flutter/material.dart';
import '../services/data_repository.dart';
import '../theme/app_colors.dart';
import 'set_detail_page.dart';

class SetCompletionPage extends StatefulWidget {
  final String collectionKey;
  final String collectionName;

  const SetCompletionPage({
    super.key,
    required this.collectionKey,
    required this.collectionName,
  });

  @override
  State<SetCompletionPage> createState() => _SetCompletionPageState();
}

class _SetCompletionPageState extends State<SetCompletionPage>
    with SingleTickerProviderStateMixin {
  final DataRepository _repo = DataRepository();
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;

  List<Map<String, dynamic>> _allSets = [];
  bool _isLoading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSets();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSets() async {
    final data = await _repo.getSetStats(widget.collectionKey);
    if (!mounted) return;
    setState(() {
      _allSets = data;
      _isLoading = false;
    });
  }

  double _pct(Map<String, dynamic> set) {
    final total = (set['totalCards'] as int?) ?? 0;
    final owned = (set['ownedCards'] as int?) ?? 0;
    return total > 0 ? owned / total : 0.0;
  }

  String _setIdentifier(Map<String, dynamic> set) {
    return set['setCode'] as String? ?? set['setName'] as String? ?? '';
  }

  List<Map<String, dynamic>> _filterSets(List<Map<String, dynamic>> sets) {
    if (_query.isEmpty) return sets;
    return sets.where((s) => (s['setName'] as String? ?? '').toLowerCase().contains(_query)).toList();
  }

  List<Map<String, dynamic>> get _inProgress {
    final list = _allSets.where((s) => _pct(s) > 0 && _pct(s) < 1.0).toList()
      ..sort((a, b) => _pct(b).compareTo(_pct(a)));
    return _filterSets(list);
  }

  List<Map<String, dynamic>> get _completed {
    final list = _allSets.where((s) => _pct(s) >= 1.0).toList()
      ..sort((a, b) {
        final da = a['completedAt'] as String?;
        final db = b['completedAt'] as String?;
        if (da != null && db != null) return db.compareTo(da);
        if (da != null) return -1;
        if (db != null) return 1;
        return (a['setName'] as String? ?? '').compareTo(b['setName'] as String? ?? '');
      });
    return _filterSets(list);
  }

  List<Map<String, dynamic>> get _available {
    final list = _allSets.where((s) => _pct(s) == 0).toList()
      ..sort((a, b) => (a['setName'] as String? ?? '').compareTo(b['setName'] as String? ?? ''));
    return _filterSets(list);
  }

  Widget _buildSetTile(Map<String, dynamic> set) {
    final setName = set['setName'] as String? ?? '';
    final setCode = set['setCode'] as String?;
    final total = (set['totalCards'] as int?) ?? 0;
    final owned = (set['ownedCards'] as int?) ?? 0;
    final pct = _pct(set);
    final pctLabel = '${(pct * 100).toStringAsFixed(0)}%';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      title: Row(
        children: [
          Expanded(
            child: Text(
              setName,
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (setCode != null && setCode.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.bgLight,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                setCode,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
            ),
          ],
        ],
      ),
      subtitle: pct > 0
          ? Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: AppColors.bgLight,
                valueColor: AlwaysStoppedAnimation<Color>(
                  pct >= 1.0 ? Colors.green : AppColors.blue,
                ),
                borderRadius: BorderRadius.circular(4),
                minHeight: 6,
              ),
            )
          : null,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            pct > 0 ? '$owned / $total' : '$total carte',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          Text(
            pctLabel,
            style: TextStyle(fontSize: 11, color: pct >= 1.0 ? Colors.green : AppColors.textSecondary),
          ),
        ],
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SetDetailPage(
              collectionKey: widget.collectionKey,
              collectionName: widget.collectionName,
              setIdentifier: _setIdentifier(set),
              setName: setName,
              totalCards: total,
              ownedCards: owned,
            ),
          ),
        );
      },
    );
  }

  Widget _buildList(List<Map<String, dynamic>> sets, String emptyMessage) {
    if (sets.isEmpty) {
      return Center(
        child: Text(emptyMessage, style: const TextStyle(color: AppColors.textHint)),
      );
    }
    return ListView.builder(
      itemCount: sets.length,
      itemBuilder: (_, i) => _buildSetTile(sets[i]),
    );
  }

  Widget _buildSummaryCard() {
    final totalSets = _allSets.length;
    final completedSets = _allSets.where((s) => _pct(s) >= 1.0).length;
    final inProgressSets = _allSets.where((s) => _pct(s) > 0 && _pct(s) < 1.0).length;
    final startedSets = _allSets.where((s) => _pct(s) > 0).toList();
    final totalCards = startedSets.fold<int>(0, (sum, s) => sum + ((s['totalCards'] as int?) ?? 0));
    final ownedCards = startedSets.fold<int>(0, (sum, s) => sum + ((s['ownedCards'] as int?) ?? 0));
    final overallPct = totalCards > 0 ? ownedCards / totalCards : 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$totalSets espansioni totali',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: overallPct,
                  backgroundColor: AppColors.bgLight,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    overallPct >= 1.0 ? Colors.green : AppColors.blue,
                  ),
                  borderRadius: BorderRadius.circular(4),
                  minHeight: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${(overallPct * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              Text(
                '$completedSets completate · $inProgressSets in corso',
                style: TextStyle(fontSize: 11, color: completedSets == totalSets && totalSets > 0 ? Colors.green : AppColors.textSecondary),
              ),
              Text(
                'su $totalSets espansioni',
                style: const TextStyle(fontSize: 10, color: AppColors.textHint),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Espansioni — ${widget.collectionName}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        bottom: _isLoading || _allSets.isEmpty
            ? null
            : TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: 'In corso (${_inProgress.length})'),
                  Tab(text: 'Completate (${_completed.length})'),
                  Tab(text: 'Disponibili (${_available.length})'),
                ],
              ),
      ),
      body: Column(
        children: [
          if (!_isLoading && _allSets.isNotEmpty) _buildSummaryCard(),
          if (!_isLoading && _allSets.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Cerca espansione...',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (v) => setState(() => _query = v.toLowerCase()),
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _allSets.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 64, color: AppColors.textHint),
                            SizedBox(height: 16),
                            Text(
                              'Catalogo non ancora scaricato.\nScarica il catalogo dalle Impostazioni.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textHint),
                            ),
                          ],
                        ),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildList(_inProgress, 'Nessuna espansione in corso.'),
                          _buildList(_completed, 'Nessuna espansione completata.'),
                          _buildList(_available, 'Nessuna espansione disponibile.'),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
