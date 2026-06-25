import '../l10n/app_localizations.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../widgets/banner_ad_widget.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../services/database_helper.dart';
import '../theme/app_colors.dart';
import '../widgets/app_dialog.dart';

// ─── SharedPreferences keys ───────────────────────────────────────────────────
const _kHistory = 'notif_history';
const _kLastSeenAppVersion = 'notif_last_seen_app_version';
const _kLastSeenVersionYugioh = 'notif_last_seen_catalog_version_yugioh';
const _kPrevTotalYugioh = 'notif_prev_total_cards_yugioh';
const _kLastSeenVersionOnepiece = 'notif_last_seen_catalog_version_onepiece';
const _kPrevTotalOnepiece = 'notif_prev_total_cards_onepiece';
const _kLastSeenVersionPokemon = 'notif_last_seen_catalog_version_pokemon';
const _kPrevTotalPokemon = 'notif_prev_total_cards_pokemon';
const _kPendingUpdatesCount = 'notif_pending_updates_count';
const _kCachedChangelog = 'notif_cached_changelog';

// ─── Firestore changelog fetch ────────────────────────────────────────────────

/// Scarica il changelog da Firestore (doc: app_config/changelog, campo: entries).
/// In caso di errore/offline restituisce null → si usa il fallback hardcoded.
/// Salva in cache SharedPreferences per uso offline futuro.
Future<List<Map<String, dynamic>>?> _fetchRemoteChangelog(
    SharedPreferences prefs) async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('app_config')
        .doc('changelog')
        .get()
        .timeout(const Duration(seconds: 5));
    if (!doc.exists) return null;
    final raw = doc.data()?['entries'];
    if (raw is! List) return null;
    final entries = raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    // Salva cache per uso offline
    await prefs.setString(_kCachedChangelog, jsonEncode(entries));
    return entries;
  } catch (_) { // ignore: empty_catches
    // Offline o errore: prova la cache locale
    final cached = prefs.getString(_kCachedChangelog);
    if (cached != null) {
      try {
        final list = jsonDecode(cached) as List;
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {}
    }
    return null;
  }
}

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
  } catch (_) { // ignore: empty_catches
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

  // Usa changelog remoto (Firestore) con fallback all'hardcoded
  final remoteEntries = await _fetchRemoteChangelog(prefs);
  final changelogEntries = remoteEntries ?? AppChangelog.entries;

  for (final entry in changelogEntries) {
    final v = entry['version'] as String;
    final id = 'app_$v';
    // Mostra tutte le entries <= versione corrente non ancora in storico.
    // Non usare lastSeenVersion per filtrare: se un entry viene aggiunta
    // retroattivamente al changelog va comunque mostrata.
    if (!existingIds.contains(id) && !_versionGt(v, currentVersion)) {
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

  // ── Catalogo Yu-Gi-Oh ── (only on native; web has no local SQLite catalog) ──
  if (kIsWeb) return history;
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

  // ── Catalogo Pokémon ────────────────────────────────────────────────────────
  final pokemonMeta = await db.getCatalogMetadata('pokemon');
  if (pokemonMeta != null) {
    final remoteV = pokemonMeta['version'] as int? ?? 0;
    final seenV = prefs.getInt(_kLastSeenVersionPokemon) ?? 0;
    if (remoteV > seenV) {
      final prevTotal = prefs.getInt(_kPrevTotalPokemon) ?? 0;
      final currentTotal = pokemonMeta['total_cards'] as int? ?? 0;
      final id = 'catalog_pokemon_v$remoteV';
      if (!existingIds.contains(id)) {
        history.insert(
          0,
          _NotifEntry(
            id: id,
            type: 'catalog_update',
            detectedAt: now,
            isRead: false,
            data: {
              'catalog': 'pokemon',
              'version': remoteV,
              'newCards': currentTotal - prevTotal,
              'lastUpdated': pokemonMeta['last_updated'] ?? '',
            },
          ),
        );
        existingIds.add(id);
      }
      await prefs.setInt(_kPrevTotalPokemon, currentTotal);
    }
    await prefs.setInt(_kLastSeenVersionPokemon, remoteV);
  }

  await _saveHistory(prefs, history);
  return history;
}

// ─── Public API ───────────────────────────────────────────────────────────────

/// Salva il numero di aggiornamenti catalogo in attesa di download (per il badge)
Future<void> setPendingUpdatesCount(int count) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kPendingUpdatesCount, count);
}

/// Rileva nuove notifiche (app update + catalog update) e le salva nello storico.
/// Da chiamare quando si sa che potrebbero esserci aggiornamenti (es. dopo
/// _checkCatalogUpdate), NON ad ogni aggiornamento del badge.
Future<void> detectAndSaveNotifications() async {
  final prefs = await SharedPreferences.getInstance();
  await _detectAndPersistNewNotifs(prefs);
}

/// Numero totale di notifiche non lette (storico + aggiornamenti in attesa).
/// Legge solo lo storico già salvato — non fa query DB né rilevazione.
Future<int> unreadNotificationCount() async {
  final prefs = await SharedPreferences.getInstance();
  final history = await _loadHistory(prefs);
  final historyUnread = history.where((e) => !e.isRead).length;
  final pendingCount = prefs.getInt(_kPendingUpdatesCount) ?? 0;
  return historyUnread + pendingCount;
}

/// Restituisce true se ci sono notifiche non lette (usato da MainLayout)
Future<bool> hasUnreadNotifications() async {
  return (await unreadNotificationCount()) > 0;
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
    final day = parts[2].split('T').first;
    return '$day ${months[m]} ${parts[0]}';
  } catch (_) { // ignore: empty_catches
    return iso;
  }
}

// ─── Page ─────────────────────────────────────────────────────────────────────

class NotificationsPage extends StatefulWidget {
  /// Aggiornamenti catalogo rilevati ma non ancora scaricati.
  /// Passati da MainLayout per mostrare la sezione "Da scaricare".
  final List<Map<String, dynamic>> pendingCatalogUpdates;

  const NotificationsPage({
    super.key,
    this.pendingCatalogUpdates = const [],
  });

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _loading = true;
  List<_NotifEntry> _history = [];
  final Set<String> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    _loadAndMarkRead();
  }

  Future<void> _loadAndMarkRead() async {
    final prefs = await SharedPreferences.getInstance();

    // Rileva nuove notifiche. Se SQLite è occupato da un download in corso,
    // il timeout evita lo spinner infinito e mostra la storia già salvata.
    List<_NotifEntry> history;
    try {
      history = await _detectAndPersistNewNotifs(prefs)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      history = await _loadHistory(prefs);
    }

    // Cancella il contatore pending (l'utente sta guardando la pagina)
    await prefs.setInt(_kPendingUpdatesCount, 0);

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
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AppConfirmDialog(
        title: l10n.notifClearAllTitle,
        icon: Icons.notifications_off_outlined,
        message: l10n.notifClearAllMsg,
        confirmLabel: l10n.notifClearAllTitle,
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
        title: Text(AppLocalizations.of(context)!.notificationsTitle),
        backgroundColor: AppColors.bgMedium,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: AppLocalizations.of(context)!.notifClearAllTooltip,
              onPressed: _deleteAll,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              top: false,
              bottom: true,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildBody(),
            ),
          ),
          if (!kIsWeb) const BannerAdWidget(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final hasPending = widget.pendingCatalogUpdates.isNotEmpty;
    final isEmpty = _history.isEmpty && !hasPending;
    final l10n = AppLocalizations.of(context)!;

    if (isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none, size: 64, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(
              l10n.notifNoNotifications,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
          ],
        ),
      );
    }

    // Primary: detectedAt descending (entries detected in the same session all share
    // the same detectedAt timestamp). Tie-break: for two app_update entries, compare by
    // semantic version rather than trusting the changelog 'date' field, which can be
    // entered inconsistently; otherwise fall back to 'date' descending.
    final sorted = [..._history]
      ..sort((a, b) {
        final cmp = b.detectedAt.compareTo(a.detectedAt);
        if (cmp != 0) return cmp;
        if (a.type == 'app_update' && b.type == 'app_update') {
          final aVersion = a.data['version'] as String? ?? '';
          final bVersion = b.data['version'] as String? ?? '';
          if (aVersion != bVersion) return _versionGt(aVersion, bVersion) ? -1 : 1;
        }
        final aDate = a.data['date'] as String? ?? '';
        final bDate = b.data['date'] as String? ?? '';
        return bDate.compareTo(aDate);
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        // ── Header ────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.bgLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Column(
            children: [
              const Icon(Icons.notifications_active_outlined, size: 52, color: AppColors.gold),
              const SizedBox(height: 12),
              Text(
                l10n.notifHeaderTitle,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.notifHeaderSubtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Sezione aggiornamenti in attesa di download ──────────────────────
        if (hasPending) ...[
          _SectionLabel(label: l10n.notifSectionAvailableUpdates, color: AppColors.gold),
          const SizedBox(height: 8),
          _GroupCard(
            children: _withDividers(
              widget.pendingCatalogUpdates.map(_buildPendingUpdateTile).toList(),
            ),
          ),
          const SizedBox(height: 24),
        ],
        if (sorted.isNotEmpty) ...[
          _SectionLabel(label: l10n.notifSectionHistory, color: AppColors.blue),
          const SizedBox(height: 8),
          _GroupCard(
            children: _withDividers(
              sorted
                  .map((e) => e.type == 'app_update'
                      ? _buildAppEntry(e)
                      : _buildCatalogTile(e))
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }

  // ── Inserisce un divider tra ogni tile di un gruppo ──────────────────────────

  List<Widget> _withDividers(List<Widget> tiles) {
    final out = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) out.add(const _GroupDivider());
      out.add(tiles[i]);
    }
    return out;
  }

  // ── Pending update tile (da scaricare) ───────────────────────────────────────

  Widget _buildPendingUpdateTile(Map<String, dynamic> update) {
    final key = update['collectionKey'] as String? ?? '';
    final name = update['collectionName'] as String? ?? key;
    final isFirst = update['isFirstDownload'] == true;
    final canIncremental = update['canDoIncremental'] == true;

    final IconData icon;
    final Color color;
    if (key == 'yugioh') {
      icon = Icons.auto_awesome;
      color = AppColors.gold;
    } else if (key == 'pokemon') {
      icon = Icons.catching_pokemon;
      color = const Color(0xFFEE1515);
    } else {
      icon = Icons.sailing;
      color = const Color(0xFF4CAF50);
    }

    final l10n = AppLocalizations.of(context)!;
    final String subtitle;
    if (isFirst) {
      subtitle = l10n.notifFirstDownload;
    } else if (canIncremental) {
      final chunks = (update['modifiedChunks'] as List?)?.length ?? 0;
      subtitle = l10n.notifPartialUpdate(chunks);
    } else {
      subtitle = l10n.notifFullUpdate;
    }

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  height: 32,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => Navigator.pop(context, {'action': 'download'}),
                    child: Text(AppLocalizations.of(context)!.notifDownloadBtn),
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => Navigator.pop(context, {'action': 'later'}),
                  child: Text(
                    AppLocalizations.of(context)!.notifLater,
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 11,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
    );
  }

  // ── Delete background (swipe left) ───────────────────────────────────────────

  Widget _deleteBg() => Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
      );

  // ── App update card ───────────────────────────────────────────────────────────

  Widget _buildAppEntry(_NotifEntry entry) {
    final version = entry.data['version'] as String? ?? '';
    final date = entry.data['date'] as String? ?? '';
    final changes = entry.data['changes'] as List<dynamic>? ?? [];
    final isExpanded = _expandedIds.contains(entry.id);

    return Dismissible(
      key: Key(entry.id),
      direction: DismissDirection.endToStart,
      background: _deleteBg(),
      onDismissed: (_) => _deleteEntry(entry.id),
      child: InkWell(
        onTap: () => setState(() => isExpanded
            ? _expandedIds.remove(entry.id)
            : _expandedIds.add(entry.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (!entry.isRead) ...[
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.notifNewBadge,
                        style: const TextStyle(
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
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: isExpanded ? AppColors.blue : AppColors.textHint,
                      size: 20,
                    ),
                  ),
                ],
              ),
              if (isExpanded) ...[
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
            ],
          ),
        ),
      ),
    );
  }

  // ── Catalog update tile (post-download storico) ───────────────────────────────

  Widget _buildCatalogTile(_NotifEntry entry) {
    final catalog = entry.data['catalog'] as String? ?? '';
    final newCards = entry.data['newCards'] as int? ?? 0;
    final lastUpdated = entry.data['lastUpdated'] as String? ?? '';

    final isYugioh = catalog == 'yugioh';
    final isPokemon = catalog == 'pokemon';
    final color = isYugioh
        ? AppColors.gold
        : isPokemon
            ? const Color(0xFFEE1515)
            : const Color(0xFF4CAF50);
    final icon = isYugioh
        ? Icons.auto_awesome
        : isPokemon
            ? Icons.catching_pokemon
            : Icons.sailing;
    final name = isYugioh ? 'Yu-Gi-Oh!' : isPokemon ? 'Pokémon' : 'One Piece TCG';

    final l10n = AppLocalizations.of(context)!;
    final List<String> details = [l10n.notifPricesUpdated];
    if (newCards > 0) details.insert(0, l10n.notifNewCardsAdded(newCards));

    // Always show a date: prefer lastUpdated (catalog update date), fallback detectedAt
    final rawDate = lastUpdated.isNotEmpty ? lastUpdated : entry.detectedAt;
    final displayDate = _formatDate(rawDate.split('T').first);

    return Dismissible(
      key: Key(entry.id),
      direction: DismissDirection.endToStart,
      background: _deleteBg(),
      onDismissed: (_) => _deleteEntry(entry.id),
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
                      Text(
                        displayDate,
                        style: TextStyle(color: AppColors.textHint, fontSize: 12),
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
    );
  }
}

// ─── Section label (stile pagina Supporto) ────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color color;

  const _SectionLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

// ─── Group card wrapper (stile pagina Supporto) ────────────────────────────────

class _GroupCard extends StatelessWidget {
  final List<Widget> children;
  const _GroupCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13.5),
        child: Column(children: children),
      ),
    );
  }
}

class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) =>
      Container(height: 0.5, color: AppColors.divider, margin: const EdgeInsets.only(left: 64));
}
