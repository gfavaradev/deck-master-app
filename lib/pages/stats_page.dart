import 'dart:async';
import 'package:flutter/material.dart';
import '../services/data_repository.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import 'set_completion_page.dart';

class StatsPage extends StatefulWidget {
  final String? collectionKey;
  final String? collectionName;

  const StatsPage({super.key, this.collectionKey, this.collectionName});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  final DataRepository _dbHelper = DataRepository();
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _collectionStats = [];
  List<Map<String, dynamic>> _rarityStats = [];
  bool _isLoading = true;
  StreamSubscription<String>? _syncSub;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _syncSub = SyncService().onRemoteChange.listen((_) {
      if (mounted) _loadStats();
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final results = await Future.wait([
      _dbHelper.getGlobalStats(),
      _dbHelper.getStatsPerCollection(),
      _dbHelper.getStatsPerRarity(),
    ]);
    if (mounted) {
      setState(() {
        _stats = results[0] as Map<String, dynamic>;
        _collectionStats = results[1] as List<Map<String, dynamic>>;
        _rarityStats = results[2] as List<Map<String, dynamic>>;
        _isLoading = false;
      });
    }
  }

  static const _collectionLabels = {
    'yugioh': 'Yu-Gi-Oh!',
    'pokemon': 'Pokémon',
    'onepiece': 'One Piece TCG',
  };

  static final _collectionColors = {
    'yugioh':   AppColors.yugiohAccent,
    'pokemon':  AppColors.pokemonAccent,
    'onepiece': AppColors.onepieceAccent,
    'magic':    AppColors.magicAccent,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistiche'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildStatCard('Carte Totali', _stats?['totalCards'].toString() ?? '0', Icons.copy_all, Colors.indigo),
                  _buildStatCard('Carte Uniche', _stats?['uniqueCards'].toString() ?? '0', Icons.style, Colors.teal),
                  _buildStatCard('Valore Stimato', '€${(_stats?['totalValue'] as double? ?? 0.0).toStringAsFixed(2)}', Icons.euro, Colors.green),
                  if (_collectionStats.isNotEmpty) _buildCollectionBreakdown(),
                  if (_rarityStats.isNotEmpty) _buildRarityBreakdown(),
                  if (widget.collectionKey != null) _buildExpansioniCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildCollectionBreakdown() {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.collections_bookmark, color: Colors.blue, size: 24),
                ),
                const SizedBox(width: 12),
                const Text('Per Collezione', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            ..._collectionStats.map((row) {
              final key = row['collection'] as String? ?? '';
              final label = _collectionLabels[key] ?? key;
              final color = _collectionColors[key] ?? Colors.grey;
              final cards = (row['totalCards'] as num?)?.toInt() ?? 0;
              final value = (row['totalValue'] as num?)?.toDouble() ?? 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
                    Text('$cards carte', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(width: 12),
                    Text('€${value.toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildRarityBreakdown() {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.amber, size: 24),
                ),
                const SizedBox(width: 12),
                const Text('Per Rarità (top 10)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            ..._rarityStats.map((row) {
              final rarity = row['rarity'] as String? ?? '';
              final count = (row['count'] as num?)?.toInt() ?? 0;
              final value = (row['totalValue'] as num?)?.toDouble() ?? 0.0;
              final maxCount = (_rarityStats.first['count'] as num?)?.toInt() ?? 1;
              final ratio = maxCount > 0 ? count / maxCount : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(rarity, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                        ),
                        Text('$count  •  €${value.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    LinearProgressIndicator(
                      value: ratio,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                      color: Colors.amber,
                      backgroundColor: Colors.amber.withValues(alpha: 0.15),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildExpansioniCard() {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.layers, color: Colors.orange, size: 30),
        ),
        title: const Text('Espansioni', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        subtitle: Text(
          'Completamento set per ${widget.collectionName}',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SetCompletionPage(
              collectionKey: widget.collectionKey!,
              collectionName: widget.collectionName!,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
