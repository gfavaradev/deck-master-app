import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../services/database_helper.dart';
import '../theme/app_colors.dart';

// ─── SharedPreferences keys ───────────────────────────────────────────────────
const _kHistory = 'notif_history';
const _kLastSeenAppVersion = 'notif_last_seen_app_version';
const _kLastSeenVersionYugioh = 'notif_last_seen_catalog_version_yugioh';
const _kPrevTotalYugioh = 'notif_prev_total_cards_yugioh';
const _kLastSeenVersionOnepiece = 'notif_last_seen_catalog_version_onepiece';
const _kPrevTotalOnepiece = 'notif_prev_total_cards_onepiece';

// ─── Model ────────────────────────────────────────────────────────────────────

class _NotifEntry {
  final String id;
  final String type; // 'app_update' | 'catalog_update'
  final String detectedAt; // ISO8601
  final bool isRead;
  final Map<String, dynamic> data;

  const _NotifEntry({
    required this.id,
    required this.type,
    required this.detectedAt,
    required this.isRead,
    required this.data,
  });

  _NotifEntry markRead() => _NotifEntry(
        id: id,
        type: type,
        detectedAt: detectedAt,
        isRead: true,
        data: data,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'detectedAt': detectedAt,
        'isRead': isRead,
        'data': data,
      };

  factory _NotifEntry.fromJson(Map<String, dynamic> j) => _NotifEntry(
        id: j['id'] as String,
        type: j['type'] as String,
        detectedAt: j['detectedAt'] as String,
        isRead: j['isRead'] as bool? ?? false,
        data: j['data'] is Map ? Map<String, dynamic>.from(j['data'] as Map) : {},
      );
}

// ─── History persistence helpers ──────────────────────────────────────────────

Future<List<_NotifEntry>> _loadHistory(SharedPreferences prefs) async {
  final raw = prefs.getString(_kHistory);
  if (raw == null) return [];
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => _NotifEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
}

Future<void> _saveHistory(
    SharedPreferences prefs, List<_NotifEntry> history) async {
  await prefs.setString(
      _kHistory, jsonEncode(history.map((e) => e.toJson()).toList()));
}

// ─── New notification detection (mutates history + prefs) ─────────────────────

Future<List<_NotifEntry>> _detectAndPersistNewNotifs(
    SharedPreferences prefs) async {
  final history = await _loadHistory(prefs);
  final existingIds = history.map((e) => e.id).toSet();
  final now = DateTime.now().toIso8601String();

  // ── App update ──────────────────────────────────────────────────────────────
  final info = await PackageInfo.fromPlatform();
  final currentVersion = info.version;
  final lastSeenVersion = prefs.getString(_kLastSeenAppVersion) ?? '';

  for (final entry in AppChangelog.entries) {
    final v = entry['version'] as String;
    final id = 'app_$v';
    if (!existingIds.contains(id) &&
        (lastSeenVersion.isEmpty || _versionGt(v, lastSeenVersion))) {
      history.insert(
        0,
        _NotifEntry(
          id: id,
          type: 'app_update',
          detectedAt: now,
          isRead: false,
          data: Map<String, dynamic>.from(entry),
        ),
      );
      existingIds.add(id);
    }
  }
  await prefs.setString(_kLastSeenAppVersion, currentVersion);

  // ── Catalogo Yu-Gi-Oh ───────────────────────────────────────────────────────
  final db = DatabaseHelper();
  final yugiohMeta = await db.getCatalogMetadata('yugioh');
  if (yugiohMeta != null) {
    final remoteV = yugiohMeta['version'] as int? ?? 0;
    final seenV = prefs.getInt(_kLastSeenVersionYugioh) ?? 0;
    if (remoteV > seenV) {
      final prevTotal = prefs.getInt(_kPrevTotalYugioh) ?? 0;
      final currentTotal = yugiohMeta['total_cards'] as int? ?? 0;
      final id = 'catalog_yugioh_v$remoteV';
      if (!existingIds.contains(id)) {
        history.insert(
          0,
          _NotifEntry(
            id: id,
            type: 'catalog_update',
            detectedAt: now,
            isRead: false,
            data: {
              'catalog': 'yugioh',
              'version': remoteV,
              'newCards': currentTotal - prevTotal,
              'lastUpdated': yugiohMeta['last_updated'] ?? '',
            },
          ),
        );
        existingIds.add(id);
      }
      await prefs.setInt(_kPrevTotalYugioh, currentTotal);
    }
    await prefs.setInt(_kLastSeenVersionYugioh, remoteV);
  }

  // ── Catalogo One Piece ──────────────────────────────────────────────────────
  final opMeta = await db.getCatalogMetadata('onepiece');
  if (opMeta != null) {
    final remoteV = opMeta['version'] as int? ?? 0;
    final seenV = prefs.getInt(_kLastSeenVersionOnepiece) ?? 0;
    if (remoteV > seenV) {
      final prevTotal = prefs.getInt(_kPrevTotalOnepiece) ?? 0;
      final currentTotal = opMeta['total_cards'] as int? ?? 0;
      final id = 'catalog_onepiece_v$remoteV';
      if (!existingIds.contains(id)) {
        history.insert(
          0,
          _NotifEntry(
            id: id,
            type: 'catalog_update',
            detectedAt: now,
            isRead: false,
            data: {
              'catalog': 'onepiece',
              'version': remoteV,
              'newCards': currentTotal - prevTotal,
              'lastUpdated': opMeta['last_updated'] ?? '',
            },
          ),
        );
        existingIds.add(id);
      }
      await prefs.setInt(_kPrevTotalOnepiece, currentTotal);
    }
    await prefs.setInt(_kLastSeenVersionOnepiece, remoteV);
  }

  await _saveHistory(prefs, history);
  return history;
}

// ─── Public API: badge check (usato da MainLayout) ────────────────────────────

Future<bool> hasUnreadNotifications() async {
  final prefs = await SharedPreferences.getInstance();
  final history = await _detectAndPersistNewNotifs(prefs);
  return history.any((e) => !e.isRead);
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

bool _versionGt(String a, String b) {
  final aParts = a.split('.').map(int.tryParse).toList();
  final bParts = b.split('.').map(int.tryParse).toList();
  for (int i = 0; i < 3; i++) {
    final ai = (i < aParts.length ? aParts[i] : null) ?? 0;
    final bi = (i < bParts.length ? bParts[i] : null) ?? 0;
    if (ai > bi) return true;
    if (ai < bi) return false;
  }
  return false;
}

String _formatDate(String iso) {
  try {
    final parts = iso.split('-');
    if (parts.length < 3) return iso;
    const months = [
      '', 'gen', 'feb', 'mar', 'apr', 'mag', 'giu',
      'lug', 'ago', 'set', 'ott', 'nov', 'dic'
    ];
    final m = int.tryParse(parts[1]) ?? 0;
    final day = parts[2].split('T').first; // rimuovi eventuale orario
    return '$day ${months[m]} ${parts[0]}';
  } catch (_) {
    return iso;
  }
}

// ─── Page ─────────────────────────────────────────────────────────────────────

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _loading = true;
  List<_NotifEntry> _history = [];

  @override
  void initState() {
    super.initState();
    _loadAndMarkRead();
  }

  Future<void> _loadAndMarkRead() async {
    final prefs = await SharedPreferences.getInstance();

    // Rileva nuove notifiche e aggiunge allo storico
    final history = await _detectAndPersistNewNotifs(prefs);

    // Salva subito la versione con tutto marcato come letto (per il badge in MainLayout)
    final markedHistory = history.map((e) => e.isRead ? e : e.markRead()).toList();
    await _saveHistory(prefs, markedHistory);

    if (mounted) {
      // Mostra la lista con lo stato originale (isRead=false = badge "NUOVA" visibile)
      setState(() {
        _history = history;
        _loading = false;
      });
    }
  }

  Future<void> _deleteEntry(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = _history.where((e) => e.id != id).toList();
    await _saveHistory(prefs, updated);
    if (mounted) setState(() => _history = updated);
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancella tutto'),
        content: const Text('Vuoi eliminare tutte le notifiche?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await _saveHistory(prefs, []);
    if (mounted) setState(() => _history = []);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text('Notifiche'),
        backgroundColor: AppColors.bgMedium,
        foregroundColor: AppColors.textPrimary,
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Cancella tutto',
              onPressed: _deleteAll,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none, size: 64, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(
              'Nessuna notifica',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
          ],
        ),
      );
    }

    // Raggruppa per tipo per i section headers
    final appEntries =
        _history.where((e) => e.type == 'app_update').toList();
    final catalogEntries =
        _history.where((e) => e.type == 'catalog_update').toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (appEntries.isNotEmpty) ...[
          _buildSectionHeader('Novità dell\'App', Icons.system_update_alt),
          ...appEntries.map(_buildAppEntry),
        ],
        if (catalogEntries.isNotEmpty) ...[
          _buildSectionHeader(
              'Aggiornamenti Catalogo', Icons.library_books),
          ...catalogEntries.map(_buildCatalogTile),
        ],
      ],
    );
  }

  // ── Sezione header ───────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.gold),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  // ── Delete background (swipe left) ───────────────────────────────────────────

  Widget _deleteBg() => Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
      );

  // ── App update card ───────────────────────────────────────────────────────────

  Widget _buildAppEntry(_NotifEntry entry) {
    final version = entry.data['version'] as String? ?? '';
    final date = entry.data['date'] as String? ?? '';
    final changes = entry.data['changes'] as List<dynamic>? ?? [];

    return Dismissible(
      key: Key(entry.id),
      direction: DismissDirection.endToStart,
      background: _deleteBg(),
      onDismissed: (_) => _deleteEntry(entry.id),
      child: Card(
      color: AppColors.bgMedium,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Badge "NUOVA" se non ancora letta al momento della rilevazione
                if (!entry.isRead) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'NUOVA',
                      style: TextStyle(
                          color: Colors.red,
                          fontSize: 10,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.blue.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.blue.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'v$version',
                    style: TextStyle(
                      color: AppColors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDate(date),
                  style:
                      TextStyle(color: AppColors.textHint, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...changes.map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5, right: 8),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: AppColors.gold,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        c as String,
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),  // Card
    );  // Dismissible
  }

  // ── Catalog update tile ───────────────────────────────────────────────────────

  Widget _buildCatalogTile(_NotifEntry entry) {
    final catalog = entry.data['catalog'] as String? ?? '';
    final newCards = entry.data['newCards'] as int? ?? 0;
    final lastUpdated = entry.data['lastUpdated'] as String? ?? '';

    final isYugioh = catalog == 'yugioh';
    final color = isYugioh ? AppColors.gold : const Color(0xFF4CAF50);
    final icon = isYugioh ? Icons.auto_awesome : Icons.sailing;
    final name = isYugioh ? 'Yu-Gi-Oh!' : 'One Piece TCG';

    final List<String> details = ['Prezzi di mercato aggiornati'];
    if (newCards > 0) details.insert(0, '+$newCards nuove carte aggiunte');

    return Dismissible(
      key: Key(entry.id),
      direction: DismissDirection.endToStart,
      background: _deleteBg(),
      onDismissed: (_) => _deleteEntry(entry.id),
      child: Card(
      color: AppColors.bgMedium,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                if (!entry.isRead)
                  Positioned(
                    right: -3,
                    top: -3,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$name aggiornato',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (lastUpdated.isNotEmpty)
                        Text(
                          _formatDate(lastUpdated.split('T').first),
                          style: TextStyle(
                              color: AppColors.textHint, fontSize: 12),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...details.map(
                    (d) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 6, top: 4),
                            child: Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                  color: color, shape: BoxShape.circle),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              d,
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),  // Card
    );  // Dismissible
  }
}
