import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Admin page non localizzata (coerente con le altre pagine admin del progetto):
/// gestisce sia le news pubblicate (collection `news`) sia i draft generati
/// automaticamente da scripts/news_sync in attesa di revisione (`news_drafts`).
class AdminNewsPage extends StatefulWidget {
  const AdminNewsPage({super.key});

  @override
  State<AdminNewsPage> createState() => _AdminNewsPageState();
}

const _collectionOptions = [
  {'key': 'all', 'name': 'Tutte'},
  {'key': 'yugioh', 'name': 'Yu-Gi-Oh!'},
  {'key': 'pokemon', 'name': 'Pokémon'},
  {'key': 'onepiece', 'name': 'One Piece'},
  {'key': 'magic', 'name': 'Magic: The Gathering'},
  {'key': 'digimon', 'name': 'Digimon'},
  {'key': 'lorcana', 'name': 'Disney Lorcana'},
  {'key': 'flesh-and-blood', 'name': 'Flesh and Blood'},
  {'key': 'vanguard', 'name': 'Cardfight!! Vanguard'},
  {'key': 'dragon-ball-super', 'name': 'Dragon Ball Super'},
  {'key': 'star-wars', 'name': 'Star Wars: Unlimited'},
  {'key': 'riftbound', 'name': 'Riftbound'},
  {'key': 'gundam', 'name': 'Gundam Card Game'},
  {'key': 'union-arena', 'name': 'Union Arena'},
];

class _AdminNewsPageState extends State<AdminNewsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _approveDraft(DocumentSnapshot doc) async {
    final data = Map<String, dynamic>.from(doc.data() as Map);
    data.remove('status');
    data.remove('fetchedAt');
    await _firestore.collection('news').add({
      ...data,
      'status': 'published',
    });
    await doc.reference.delete();
  }

  Future<void> _rejectDraft(DocumentSnapshot doc) async {
    await doc.reference.delete();
  }

  Future<void> _deleteNews(DocumentSnapshot doc) async {
    await doc.reference.delete();
  }

  Future<void> _togglePinned(DocumentSnapshot doc, bool current) async {
    await doc.reference.update({'pinned': !current});
  }

  Future<void> _openEditDialog({DocumentSnapshot? doc}) async {
    final data = doc?.data() as Map<String, dynamic>? ?? const {};
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _NewsEditDialog(initial: data),
    );
    if (result == null) return;
    if (doc != null) {
      await doc.reference.update(result);
    } else {
      await _firestore.collection('news').add({
        ...result,
        'status': 'published',
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestione News'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Pubblicate'),
            Tab(text: 'In revisione'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditDialog(),
        backgroundColor: Colors.deepPurple,
        child: const Icon(Icons.add),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _PublishedList(
            firestore: _firestore,
            onEdit: (doc) => _openEditDialog(doc: doc),
            onDelete: _deleteNews,
            onTogglePinned: _togglePinned,
          ),
          _DraftsList(
            firestore: _firestore,
            onApprove: _approveDraft,
            onReject: _rejectDraft,
          ),
        ],
      ),
    );
  }
}

class _PublishedList extends StatelessWidget {
  final FirebaseFirestore firestore;
  final void Function(DocumentSnapshot doc) onEdit;
  final void Function(DocumentSnapshot doc) onDelete;
  final void Function(DocumentSnapshot doc, bool current) onTogglePinned;

  const _PublishedList({
    required this.firestore,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePinned,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('news')
          .orderBy('publishedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Errore: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('Nessuna news pubblicata.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            final pinned = data['pinned'] == true;
            final collections = (data['collections'] as List?)
                    ?.map((e) => e.toString())
                    .join(', ') ??
                '';
            return Card(
              child: ListTile(
                leading: Icon(
                  pinned ? Icons.push_pin : Icons.article_outlined,
                  color: pinned ? Colors.amber.shade700 : null,
                ),
                title: Text(data['title'] as String? ?? ''),
                subtitle: Text(
                  '$collections${data['source'] != null ? ' · ${data['source']}' : ''}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
                      tooltip: pinned ? 'Rimuovi evidenza' : 'Metti in evidenza',
                      onPressed: () => onTogglePinned(doc, pinned),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => onEdit(doc),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => onDelete(doc),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _DraftsList extends StatelessWidget {
  final FirebaseFirestore firestore;
  final void Function(DocumentSnapshot doc) onApprove;
  final void Function(DocumentSnapshot doc) onReject;

  const _DraftsList({
    required this.firestore,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('news_drafts')
          .orderBy('publishedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Errore: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('Nessun draft in attesa di revisione.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            final collections = (data['collections'] as List?)
                    ?.map((e) => e.toString())
                    .join(', ') ??
                '';
            return Card(
              child: ListTile(
                leading: const Icon(Icons.hourglass_top_outlined),
                title: Text(data['title'] as String? ?? ''),
                subtitle: Text(
                  '$collections · ${data['source'] ?? ''} (${data['kind'] ?? ''})\n'
                  '${data['body'] ?? ''}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                      tooltip: 'Approva e pubblica',
                      onPressed: () => onApprove(doc),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                      tooltip: 'Rifiuta',
                      onPressed: () => onReject(doc),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _NewsEditDialog extends StatefulWidget {
  final Map<String, dynamic> initial;
  const _NewsEditDialog({required this.initial});

  @override
  State<_NewsEditDialog> createState() => _NewsEditDialogState();
}

class _NewsEditDialogState extends State<_NewsEditDialog> {
  late final _titleCtrl = TextEditingController(text: widget.initial['title'] as String? ?? '');
  late final _subtitleCtrl = TextEditingController(text: widget.initial['subtitle'] as String? ?? '');
  late final _bodyCtrl = TextEditingController(text: widget.initial['body'] as String? ?? '');
  late final _imageCtrl = TextEditingController(text: widget.initial['imageUrl'] as String? ?? '');
  late final _urlCtrl = TextEditingController(text: widget.initial['externalUrl'] as String? ?? '');
  late final Set<String> _selectedCollections = (widget.initial['collections'] as List?)
          ?.map((e) => e.toString())
          .toSet() ??
      <String>{};
  late bool _pinned = widget.initial['pinned'] == true;
  late DateTime _publishedAt = (widget.initial['publishedAt'] is Timestamp)
      ? (widget.initial['publishedAt'] as Timestamp).toDate()
      : DateTime.now();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _bodyCtrl.dispose();
    _imageCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _publishedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _publishedAt = picked);
  }

  void _save() {
    if (_titleCtrl.text.trim().isEmpty || _selectedCollections.isEmpty) return;
    Navigator.of(context).pop({
      'title': _titleCtrl.text.trim(),
      'subtitle': _subtitleCtrl.text.trim().isEmpty ? null : _subtitleCtrl.text.trim(),
      'body': _bodyCtrl.text.trim(),
      'imageUrl': _imageCtrl.text.trim().isEmpty ? null : _imageCtrl.text.trim(),
      'externalUrl': _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
      'collections': _selectedCollections.toList(),
      'pinned': _pinned,
      'publishedAt': Timestamp.fromDate(_publishedAt),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial.isEmpty ? 'Nuova news' : 'Modifica news'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Titolo'),
              ),
              TextField(
                controller: _subtitleCtrl,
                decoration: const InputDecoration(labelText: 'Sottotitolo (opzionale)'),
              ),
              TextField(
                controller: _bodyCtrl,
                decoration: const InputDecoration(labelText: 'Testo'),
                maxLines: 4,
              ),
              TextField(
                controller: _imageCtrl,
                decoration: const InputDecoration(labelText: 'URL immagine (opzionale)'),
              ),
              TextField(
                controller: _urlCtrl,
                decoration: const InputDecoration(labelText: 'Link esterno (opzionale)'),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Collezioni', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _collectionOptions.map((c) {
                  final key = c['key']!;
                  final selected = _selectedCollections.contains(key);
                  return FilterChip(
                    label: Text(c['name']!),
                    selected: selected,
                    onSelected: (sel) => setState(() {
                      if (sel) {
                        _selectedCollections.add(key);
                      } else {
                        _selectedCollections.remove(key);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pubblicata il ${_publishedAt.day}/${_publishedAt.month}/${_publishedAt.year}',
                    ),
                  ),
                  TextButton(onPressed: _pickDate, child: const Text('Cambia data')),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('In evidenza (pinned)'),
                value: _pinned,
                onChanged: (v) => setState(() => _pinned = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Salva'),
        ),
      ],
    );
  }
}
