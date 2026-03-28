import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/admin_translation_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminSetsRaritiesPage extends StatefulWidget {
  const AdminSetsRaritiesPage({super.key});

  @override
  State<AdminSetsRaritiesPage> createState() => _AdminSetsRaritiesPageState();
}

class _AdminSetsRaritiesPageState extends State<AdminSetsRaritiesPage>
    with SingleTickerProviderStateMixin {
  static const _collections = [
    {'key': 'yugioh',   'name': 'Yu-Gi-Oh!',  'langs': ['it','fr','de','pt','sp']},
    {'key': 'pokemon',  'name': 'Pokémon',     'langs': ['it','fr','de','pt']},
    {'key': 'onepiece', 'name': 'One Piece',   'langs': <String>[]},
  ];

  late final TabController _tabController;
  final _db = DatabaseHelper();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _collections.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _syncToFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _syncing = true);
    try {
      final svc = AdminTranslationService();
      await svc.pushSetRarityTranslations(
        catalog: 'yugioh',
        adminUid: uid,
        onProgress: (msg, _) => debugPrint('[sync] $msg'),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Traduzioni sincronizzate su Firestore')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Espansioni & Rarità'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          if (_syncing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.cloud_upload_outlined),
              tooltip: 'Sincronizza su Firestore',
              onPressed: _syncToFirestore,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: _collections.map((c) => Tab(text: c['name'] as String)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _collections.map((c) => _CollectionSetsRarities(
          collectionKey: c['key'] as String,
          langs: List<String>.from(c['langs'] as List),
          db: _db,
        )).toList(),
      ),
    );
  }
}

class _CollectionSetsRarities extends StatelessWidget {
  final String collectionKey;
  final List<String> langs;
  final DatabaseHelper db;

  const _CollectionSetsRarities({
    required this.collectionKey,
    required this.langs,
    required this.db,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            labelColor: Colors.deepPurple,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.deepPurple,
            tabs: [Tab(text: 'Espansioni'), Tab(text: 'Rarità')],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _DataList(
                  key: ValueKey('${collectionKey}_sets'),
                  loader: () => db.getDistinctSets(collectionKey),
                  langs: langs,
                  nameKey: 'set_name',
                  emptyMsg: 'Nessuna espansione trovata',
                  onSave: (oldEn, newEn, translations) async {
                    await db.renameSetName(collectionKey, oldEn, newEn);
                    await db.updateSetTranslations(collectionKey, newEn, translations);
                  },
                ),
                _DataList(
                  key: ValueKey('${collectionKey}_rarities'),
                  loader: () => db.getDistinctRarities(collectionKey),
                  langs: langs,
                  nameKey: 'rarity',
                  emptyMsg: 'Nessuna rarità trovata',
                  onSave: (oldEn, newEn, translations) async {
                    await db.renameRarity(collectionKey, oldEn, newEn);
                    await db.updateRarityTranslations(collectionKey, newEn, translations);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DataList extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function() loader;
  final List<String> langs;
  final String nameKey;
  final String emptyMsg;
  final Future<void> Function(String oldEnName, String newEnName, Map<String, String> translations) onSave;

  const _DataList({
    super.key,
    required this.loader,
    required this.langs,
    required this.nameKey,
    required this.emptyMsg,
    required this.onSave,
  });

  @override
  State<_DataList> createState() => _DataListState();
}

class _DataListState extends State<_DataList> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loader();
  }

  void _reload() => setState(() => _future = widget.loader());

  String _colKey(String lang) => '${widget.nameKey}_$lang';

  String _missingLangs(Map<String, dynamic> row) {
    final missing = widget.langs.where((l) {
      final v = row[_colKey(l)]?.toString();
      return v == null || v.isEmpty;
    }).toList();
    if (missing.isEmpty) return '';
    return 'Mancanti: ${missing.map((l) => l.toUpperCase()).join(', ')}';
  }

  Future<void> _openEdit(Map<String, dynamic> row) async {
    final oldEnName = row[widget.nameKey]?.toString() ?? '';
    final enController = TextEditingController(text: oldEnName);
    final controllers = {
      for (final l in widget.langs)
        l: TextEditingController(text: row[_colKey(l)]?.toString() ?? '')
    };

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(oldEnName, style: const TextStyle(fontSize: 15)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: enController,
                  decoration: const InputDecoration(
                    labelText: 'EN',
                    prefixIcon: _LangBadge('EN'),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              ...widget.langs.map((l) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: controllers[l],
                  decoration: InputDecoration(
                    labelText: l.toUpperCase(),
                    prefixIcon: _LangBadge(l.toUpperCase()),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              )),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
        ],
      ),
    );

    // Read text values BEFORE disposing controllers to avoid use-after-dispose crash.
    final newEnName = enController.text.trim();
    final translations = {
      for (final l in widget.langs) l: controllers[l]!.text.trim(),
    };

    enController.dispose();
    for (final c in controllers.values) {
      c.dispose();
    }

    if (saved != true) return;

    await widget.onSave(oldEnName, newEnName, translations);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Errore: ${snap.error}',
                  style: const TextStyle(color: Colors.red)),
            ),
          );
        }
        final rows = snap.data ?? [];
        if (rows.isEmpty) return Center(child: Text(widget.emptyMsg));

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final row = rows[i];
            final enValue = row[widget.nameKey]?.toString() ?? '';
            final setCode = row['set_code']?.toString() ?? '';
            final missing = _missingLangs(row);

            return ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (missing.isNotEmpty)
                    const Icon(Icons.warning_amber, size: 16, color: Colors.orange),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Modifica traduzioni',
                    onPressed: widget.langs.isEmpty ? null : () => _openEdit(row),
                    color: Colors.deepPurple,
                  ),
                  const Icon(Icons.expand_more),
                ],
              ),
              title: Row(
                children: [
                  if (setCode.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withValues(alpha: 0.1),
                        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        setCode,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                    ),
                  ],
                  Expanded(
                    child: Text(enValue, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              subtitle: missing.isNotEmpty
                  ? Text(missing, style: const TextStyle(fontSize: 11, color: Colors.orange))
                  : null,
              children: widget.langs.isEmpty
                  ? [
                      const ListTile(
                        dense: true,
                        title: Text(
                          'Solo inglese disponibile',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      )
                    ]
                  : widget.langs.map((lang) {
                      final val = row[_colKey(lang)]?.toString();
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 32),
                        leading: _LangBadge(lang.toUpperCase()),
                        title: val != null && val.isNotEmpty
                            ? Text(val)
                            : Text(
                                '— mancante —',
                                style: TextStyle(
                                  color: Colors.red.shade300,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                      );
                    }).toList(),
            );
          },
        );
      },
    );
  }
}

class _LangBadge extends StatelessWidget {
  final String lang;
  const _LangBadge(this.lang);

  static const _colors = {
    'IT': Colors.green,
    'FR': Colors.blue,
    'DE': Colors.amber,
    'PT': Colors.teal,
    'SP': Colors.orange,
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[lang] ?? Colors.grey;
    return Container(
      width: 32,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        lang,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
