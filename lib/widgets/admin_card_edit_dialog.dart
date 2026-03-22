import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/image_upload_service.dart';

/// Comprehensive dialog for adding/editing catalog cards
/// Tabs: Info Base | Traduzioni | Stats | Set per Lingua
class AdminCardEditDialog extends StatefulWidget {
  final Map<String, dynamic>? initialCard;

  const AdminCardEditDialog({super.key, this.initialCard});

  @override
  State<AdminCardEditDialog> createState() => _AdminCardEditDialogState();
}

class _AdminCardEditDialogState extends State<AdminCardEditDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // --- Basic Info ---
  late TextEditingController _nameEnController;
  late TextEditingController _archetypeController;
  String _catalog = 'yugioh';
  String _cardType = 'Monster Card';
  String _frameType = 'Normal';
  String _race = 'Dragon';
  String _attribute = 'DARK';
  List<String> _linkMarkers = [];
  dynamic _cardId; // int for YuGiOh, String for Pokemon

  // --- Stats ---
  late TextEditingController _atkController;
  late TextEditingController _defController;
  late TextEditingController _levelController;
  late TextEditingController _scaleController;

  // --- Translations: name + description per language ---
  static const List<Map<String, String>> _languages = [
    {'code': 'it', 'label': 'Italiano'},
    {'code': 'fr', 'label': 'Francese'},
    {'code': 'de', 'label': 'Tedesco'},
    {'code': 'pt', 'label': 'Portoghese'},
    {'code': 'sp', 'label': 'Spagnolo'},
  ];

  late Map<String, TextEditingController> _transNameControllers;
  late Map<String, TextEditingController> _transDescControllers;
  late TextEditingController _descEnController;

  // --- Sets per language ---
  static const List<String> _setLanguages = ['en', 'it', 'fr', 'de', 'pt', 'sp'];
  static const Map<String, String> _setLanguageLabels = {
    'en': 'Inglese',
    'it': 'Italiano',
    'fr': 'Francese',
    'de': 'Tedesco',
    'pt': 'Portoghese',
    'sp': 'Spagnolo',
  };

  late Map<String, List<Map<String, dynamic>>> _setsByLanguage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    final card = widget.initialCard ?? {};
    // id can be int (YuGiOh), String (Pokemon api_id), or missing (new card)
    final rawId = card['api_id'] ?? card['id'];
    if (rawId is String) {
      _cardId = rawId;
    } else {
      _cardId = (rawId as num?)?.toInt() ?? _generateCustomCardId();
    }

    // Basic info
    _nameEnController = TextEditingController(text: card['name'] ?? '');
    _archetypeController = TextEditingController(text: card['archetype'] ?? '');
    _catalog = card['catalog'] ?? 'yugioh';
    _cardType = card['type'] ?? 'Monster Card';
    _frameType = card['frame_type'] ?? 'Normal';
    _race = card['race'] ?? 'Dragon';
    _attribute = card['attribute'] ?? 'DARK';

    if (card['linkmarkers'] != null) {
      _linkMarkers = (card['linkmarkers'] as String).split(',').where((s) => s.isNotEmpty).toList();
    }

    // Stats
    _atkController = TextEditingController(text: card['atk']?.toString() ?? '');
    _defController = TextEditingController(text: card['def']?.toString() ?? '');
    _levelController = TextEditingController(text: card['level']?.toString() ?? '');
    _scaleController = TextEditingController(text: card['scale']?.toString() ?? '');

    // Translations — support both nested 'translations' map and flat name_it / description_it fields
    final translations = card['translations'] as Map<String, dynamic>? ?? {};
    _transNameControllers = {};
    _transDescControllers = {};
    _descEnController = TextEditingController(text: card['description'] ?? '');

    for (final lang in _languages) {
      final code = lang['code']!;
      final nested = translations[code] as Map<String, dynamic>? ?? {};
      _transNameControllers[code] = TextEditingController(
        text: nested['name'] ?? card['name_$code'] ?? '',
      );
      _transDescControllers[code] = TextEditingController(
        text: nested['description'] ?? card['description_$code'] ?? '',
      );
    }

    // Sets per language — support 'sets' map or legacy 'prints' list
    _setsByLanguage = {for (final l in _setLanguages) l: []};

    final setsMap = card['sets'] as Map<String, dynamic>?;
    if (setsMap != null) {
      for (final lang in _setLanguages) {
        final langSets = setsMap[lang] as List<dynamic>?;
        if (langSets != null) {
          _setsByLanguage[lang] = langSets
              .map((s) => Map<String, dynamic>.from(s as Map))
              .toList();
        }
      }
    } else if (card['prints'] is List) {
      // Migrate legacy flat prints to English
      _setsByLanguage['en'] = (card['prints'] as List)
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();
    }
  }

  int _generateCustomCardId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 900000000 + (timestamp % 100000000);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameEnController.dispose();
    _archetypeController.dispose();
    _atkController.dispose();
    _defController.dispose();
    _levelController.dispose();
    _scaleController.dispose();
    _descEnController.dispose();
    for (final c in _transNameControllers.values) { c.dispose(); }
    for (final c in _transDescControllers.values) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 860,
        height: 720,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.initialCard == null ? 'Nuova Carta' : 'Modifica Carta',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'ID: $_cardId',
                    style: TextStyle(fontSize: 12, color: Colors.deepPurple.shade700),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 8),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Info Base'),
                Tab(text: 'Traduzioni'),
                Tab(text: 'Stats'),
                Tab(text: 'Set per Lingua'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildBasicInfoTab(),
                  _buildTranslationsTab(),
                  _buildStatsTab(),
                  _buildSetsTab(),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saveCard,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Salva Carta'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Tab: Info Base ──────────────────────────────────────────────────────────

  Widget _buildBasicInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Nome e Descrizione (EN) *'),
          _field('Nome Inglese *', _nameEnController),
          _field('Descrizione Inglese', _descEnController, maxLines: 4),
          _sectionTitle('Tipo e Categoria'),
          _dropdown('Catalogo', _catalog, ['yugioh', 'pokemon', 'magic', 'onepiece'],
              (v) => setState(() => _catalog = v!)),
          _dropdown('Tipo Carta', _cardType, ['Monster Card', 'Spell Card', 'Trap Card'],
              (v) => setState(() => _cardType = v!)),
          _dropdown('Frame Type', _frameType,
              ['Normal', 'Effect', 'Ritual', 'Fusion', 'Synchro', 'Xyz', 'Pendulum', 'Link'],
              (v) => setState(() => _frameType = v!)),
          if (_cardType == 'Monster Card') ...[
            _dropdown(
              'Razza', _race,
              ['Dragon', 'Spellcaster', 'Warrior', 'Beast-Warrior', 'Beast', 'Fiend',
               'Zombie', 'Machine', 'Aqua', 'Pyro', 'Rock', 'Winged Beast', 'Plant',
               'Insect', 'Thunder', 'Dinosaur', 'Fish', 'Sea Serpent', 'Reptile',
               'Psychic', 'Divine-Beast', 'Creator God', 'Wyrm', 'Cyberse'],
              (v) => setState(() => _race = v!),
            ),
            _dropdown('Attributo', _attribute,
                ['DARK', 'LIGHT', 'WATER', 'FIRE', 'EARTH', 'WIND', 'DIVINE'],
                (v) => setState(() => _attribute = v!)),
          ],
          _field('Archetipo', _archetypeController),
        ],
      ),
    );
  }

  // ─── Tab: Traduzioni ─────────────────────────────────────────────────────────

  Widget _buildTranslationsTab() {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: _languages.map((lang) {
        final code = lang['code']!;
        final label = lang['label']!;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: Colors.deepPurple.shade50,
              radius: 16,
              child: Text(code.toUpperCase(),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
            ),
            title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              _transNameControllers[code]!.text.isEmpty ? 'Nessuna traduzione' : _transNameControllers[code]!.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    _field('Nome ($label)', _transNameControllers[code]!),
                    _field('Descrizione ($label)', _transDescControllers[code]!, maxLines: 4),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ─── Tab: Stats ──────────────────────────────────────────────────────────────

  Widget _buildStatsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_cardType == 'Monster Card') ...[
            _sectionTitle('Statistiche Mostro'),
            Row(children: [
              Expanded(child: _field('ATK', _atkController, number: true)),
              const SizedBox(width: 8),
              Expanded(child: _field('DEF', _defController, number: true)),
            ]),
            Row(children: [
              Expanded(child: _field('Level/Rank', _levelController, number: true)),
              const SizedBox(width: 8),
              Expanded(child: _field('Scale (Pendulum)', _scaleController, number: true)),
            ]),
            if (_frameType == 'Link') ...[
              _sectionTitle('Link Markers'),
              Wrap(
                spacing: 8,
                children: ['Top', 'Top-Left', 'Top-Right', 'Left', 'Right', 'Bottom', 'Bottom-Left', 'Bottom-Right']
                    .map((marker) => FilterChip(
                          label: Text(marker),
                          selected: _linkMarkers.contains(marker),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _linkMarkers.add(marker);
                              } else {
                                _linkMarkers.remove(marker);
                              }
                            });
                          },
                        ))
                    .toList(),
              ),
            ],
          ] else
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Le Spell e Trap non hanno statistiche mostro', style: TextStyle(color: Colors.grey))),
            ),
        ],
      ),
    );
  }

  // ─── Tab: Set per Lingua ─────────────────────────────────────────────────────

  Widget _buildSetsTab() {
    final hasEnSets = _setsByLanguage['en']?.isNotEmpty ?? false;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'EN è la lingua base. Usa "Genera da EN" per creare i codici localizzati.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: hasEnSets ? _generateSetsFromEn : null,
                icon: const Icon(Icons.auto_fix_high, size: 15),
                label: const Text('Genera da EN'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            children: _setLanguages.map((lang) {
              final sets = _setsByLanguage[lang]!;
              final label = _setLanguageLabels[lang]!;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  initiallyExpanded: sets.isNotEmpty,
                  leading: CircleAvatar(
                    backgroundColor: sets.isNotEmpty ? Colors.orange.shade100 : Colors.grey.shade100,
                    radius: 16,
                    child: Text(lang.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: sets.isNotEmpty ? Colors.orange.shade800 : Colors.grey,
                        )),
                  ),
                  title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    sets.isEmpty ? 'Nessun set' : '${sets.length} set',
                    style: TextStyle(fontSize: 12, color: sets.isNotEmpty ? Colors.orange.shade700 : Colors.grey),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: Colors.orange),
                    tooltip: 'Aggiungi set',
                    onPressed: () => _addSet(lang),
                  ),
                  children: sets.isEmpty
                      ? [const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Nessun set per questa lingua.', style: TextStyle(color: Colors.grey)))]
                      : sets.asMap().entries.map((entry) {
                          final i = entry.key;
                          final s = entry.value;
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: Colors.orange,
                              child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                            ),
                            title: Text(s['set_name'] ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${s['set_code'] ?? ''} • ${s['rarity'] ?? ''} • €${(s['set_price'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                                    style: const TextStyle(fontSize: 11),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if ((s['image_url'] as String?)?.isNotEmpty == true)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 4),
                                    child: Icon(Icons.image, size: 14, color: Colors.green),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _editSet(lang, i)),
                                IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () => _removeSet(lang, i)),
                              ],
                            ),
                          );
                        }).toList(),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  /// Converts an EN set code to the target language code.
  /// e.g. LOB-EN001 → LOB-IT001 (for 'it')
  static String? _localizedSetCode(String enCode, String targetLang) {
    final match = RegExp(r'^([A-Z0-9]+)-(EN|E)(.+)$').firstMatch(enCode.toUpperCase());
    if (match == null) return null;
    final isShort = match.group(2) == 'E';
    final prefix = match.group(1)!;
    final suffix = match.group(3)!;
    final langCode = switch (targetLang) {
      'it' => isShort ? 'I' : 'IT',
      'fr' => isShort ? 'F' : 'FR',
      'de' => isShort ? 'D' : 'DE',
      'pt' => isShort ? 'P' : 'PT',
      'sp' => isShort ? 'S' : 'SP',
      _ => null,
    };
    if (langCode == null) return null;
    return '$prefix-$langCode$suffix';
  }

  /// Auto-generates IT/FR/DE/PT sets from existing EN sets.
  void _generateSetsFromEn() {
    final enSets = List<Map<String, dynamic>>.from(_setsByLanguage['en'] ?? []);
    if (enSets.isEmpty) return;

    setState(() {
      for (final lang in ['it', 'fr', 'de', 'pt', 'sp']) {
        // Build index of existing sets for this language (by set_code, uppercased)
        final existing = <String, Map<String, dynamic>>{};
        for (final s in (_setsByLanguage[lang] ?? [])) {
          final code = (s['set_code']?.toString() ?? '').toUpperCase();
          if (code.isNotEmpty) existing.putIfAbsent(code, () => s);
        }

        final newList = <Map<String, dynamic>>[];
        for (final enSet in enSets) {
          final enCode = enSet['set_code']?.toString() ?? '';
          final localCode = _localizedSetCode(enCode, lang) ?? enCode;
          final localUpper = localCode.toUpperCase();
          final enUpper = enCode.toUpperCase();
          // Prefer matching by target code, fallback to EN code (handles first run)
          final found = existing[localUpper] ?? existing[enUpper];
          if (found != null) {
            // Fix the set_code if it still has the EN code
            final foundCode = (found['set_code']?.toString() ?? '').toUpperCase();
            if (foundCode != localUpper) {
              newList.add(Map<String, dynamic>.from(found)
                ..['set_code'] = localCode);
            } else {
              newList.add(found);
            }
          } else {
            // Create new entry from EN template
            newList.add({
              'set_code': localCode,
              'set_name': enSet['set_name'] ?? '',
              'rarity': enSet['rarity'] ?? '',
              'set_price': enSet['set_price'],
              if ((enSet['image_url'] as String?)?.isNotEmpty == true)
                'image_url': enSet['image_url'],
            });
          }
        }
        _setsByLanguage[lang] = newList;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Set generati per IT, FR, DE, PT, SP da EN'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _addSet(String lang) async {
    final result = await _showSetDialog(lang: lang);
    if (result != null) setState(() => _setsByLanguage[lang]!.add(result));
  }

  Future<void> _editSet(String lang, int index) async {
    final result = await _showSetDialog(lang: lang, initialData: _setsByLanguage[lang]![index]);
    if (result != null) setState(() => _setsByLanguage[lang]![index] = result);
  }

  void _removeSet(String lang, int index) {
    setState(() => _setsByLanguage[lang]!.removeAt(index));
  }

  Future<Map<String, dynamic>?> _showSetDialog({required String lang, Map<String, dynamic>? initialData}) async {
    final setCodeCtrl = TextEditingController(text: initialData?['set_code'] ?? '');
    final setNameCtrl = TextEditingController(text: initialData?['set_name'] ?? '');
    final rarityCtrl = TextEditingController(text: initialData?['rarity'] ?? '');
    final priceCtrl = TextEditingController(
      text: (initialData?['set_price'] as num?)?.toStringAsFixed(2) ?? '0.00',
    );
    final imageUrlCtrl = TextEditingController(text: initialData?['image_url'] ?? '');
    final langLabel = _setLanguageLabels[lang] ?? lang.toUpperCase();

    bool uploading = false;
    String? uploadError;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setS) {
          return AlertDialog(
            title: Text('${initialData == null ? 'Aggiungi' : 'Modifica'} Set — $langLabel'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dialogField(setCodeCtrl, 'Set Code *', 'es. LOB-EN001'),
                  const SizedBox(height: 12),
                  _dialogField(setNameCtrl, 'Set Name *', 'es. Legend of Blue Eyes White Dragon'),
                  const SizedBox(height: 12),
                  _dialogField(rarityCtrl, 'Rarità *', 'es. Ultra Rare, Super Rare, Common'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Prezzo (€)',
                      hintText: 'es. 4.50',
                      border: OutlineInputBorder(),
                      prefixText: '€ ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Image URL field + upload button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: imageUrlCtrl,
                          decoration: InputDecoration(
                            labelText: 'Image URL',
                            hintText: 'https://... oppure carica →',
                            border: const OutlineInputBorder(),
                            suffixIcon: imageUrlCtrl.text.contains('firebasestorage')
                                ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
                                : null,
                          ),
                          readOnly: imageUrlCtrl.text.contains('firebasestorage'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (uploading)
                        const SizedBox(
                          width: 36,
                          height: 36,
                          child: Padding(
                            padding: EdgeInsets.all(6),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else ...[
                        IconButton(
                          icon: const Icon(Icons.upload_file, color: Colors.orange),
                          tooltip: 'Carica dal dispositivo',
                          onPressed: () => _uploadSetImage(
                            setS,
                            imageUrlCtrl,
                            setCodeCtrl.text.trim(),
                            (v) => setS(() => uploading = v),
                            (e) => setS(() => uploadError = e),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.cloud_download_outlined, color: Colors.blue),
                          tooltip: 'Carica da URL API',
                          onPressed: () => _uploadFromApiUrl(
                            setS,
                            imageUrlCtrl,
                            setCodeCtrl.text.trim(),
                            (v) => setS(() => uploading = v),
                            (e) => setS(() => uploadError = e),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (uploadError != null) ...[
                    const SizedBox(height: 4),
                    Text(uploadError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
              ElevatedButton(
                onPressed: uploading
                    ? null
                    : () {
                        if ([setCodeCtrl, setNameCtrl, rarityCtrl].any((c) => c.text.trim().isEmpty)) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Tutti i campi sono obbligatori')),
                          );
                          return;
                        }
                        final imageUrl = imageUrlCtrl.text.trim();
                        Navigator.pop(ctx, {
                          'set_code': setCodeCtrl.text.trim(),
                          'set_name': setNameCtrl.text.trim(),
                          'rarity': rarityCtrl.text.trim(),
                          'set_price': double.tryParse(priceCtrl.text) ?? 0.0,
                          if (imageUrl.isNotEmpty) 'image_url': imageUrl,
                        });
                      },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                child: const Text('Salva'),
              ),
            ],
          );
        },
      ),
    );

    for (final c in [setCodeCtrl, setNameCtrl, rarityCtrl, priceCtrl, imageUrlCtrl]) {
      c.dispose();
    }
    return result;
  }

  Future<void> _uploadFromApiUrl(
    StateSetter setState2,
    TextEditingController imageUrlCtrl,
    String setCode,
    void Function(bool) setLoading,
    void Function(String?) setError,
  ) async {
    final currentUrl = imageUrlCtrl.text.trim();
    if (currentUrl.isEmpty || currentUrl.contains('firebasestorage')) {
      setError('Inserisci prima un URL API nel campo immagine');
      return;
    }
    setLoading(true);
    setError(null);
    try {
      final url = await ImageUploadService.uploadFromUrl(
        imageUrl: currentUrl,
        catalog: _catalog,
        cardId: _cardId!,
        setCode: setCode.isNotEmpty ? setCode : null,
      );
      if (url != null) {
        setState2(() => imageUrlCtrl.text = url);
      } else {
        setError('Download immagine fallito');
      }
    } catch (e) {
      setError('Upload fallito: $e');
    } finally {
      setLoading(false);
    }
  }

  Future<void> _uploadSetImage(
    StateSetter setState2,
    TextEditingController imageUrlCtrl,
    String setCode,
    void Function(bool) setLoading,
    void Function(String?) setError,
  ) async {
    setLoading(true);
    setError(null);
    try {
      final url = await ImageUploadService.pickAndUpload(
        catalog: _catalog,
        cardId: _cardId!,
        setCode: setCode.isNotEmpty ? setCode : null,
      );
      if (url != null) setState2(() => imageUrlCtrl.text = url);
    } catch (e) {
      setError('Upload fallito: $e');
    } finally {
      setLoading(false);
    }
  }

  Widget _dialogField(TextEditingController ctrl, String label, String hint) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
    );
  }

  // ─── Shared helpers ──────────────────────────────────────────────────────────

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      );

  Widget _field(String label, TextEditingController controller, {int maxLines = 1, bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
        maxLines: maxLines,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
      ),
    );
  }

  Widget _dropdown(String label, String value, List<String> items, void Function(String?) onChanged) {
    final safeValue = items.contains(value) ? value : items.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: safeValue,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
        items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  // ─── Save ────────────────────────────────────────────────────────────────────

  void _saveCard() {
    if (_nameEnController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nome inglese obbligatorio!')),
      );
      _tabController.animateTo(0);
      return;
    }

    // Build translations map
    final translations = <String, Map<String, String>>{};
    for (final lang in _languages) {
      final code = lang['code']!;
      final name = _transNameControllers[code]!.text.trim();
      final desc = _transDescControllers[code]!.text.trim();
      if (name.isNotEmpty || desc.isNotEmpty) {
        translations[code] = {
          if (name.isNotEmpty) 'name': name,
          if (desc.isNotEmpty) 'description': desc,
        };
      }
    }

    // Build sets map (keep only non-empty language entries)
    final sets = <String, List<Map<String, dynamic>>>{};
    for (final lang in _setLanguages) {
      if (_setsByLanguage[lang]!.isNotEmpty) {
        sets[lang] = _setsByLanguage[lang]!;
      }
    }

    final cardData = {
      'id': _cardId,
      'catalog': _catalog,
      'name': _nameEnController.text.trim(),
      'description': _descEnController.text.trim(),
      'type': _cardType,
      'frame_type': _frameType,
      'race': _race,
      'attribute': _attribute,
      'archetype': _archetypeController.text.trim().isEmpty ? null : _archetypeController.text.trim(),
      'atk': _atkController.text.isEmpty ? null : int.tryParse(_atkController.text),
      'def': _defController.text.isEmpty ? null : int.tryParse(_defController.text),
      'level': _levelController.text.isEmpty ? null : int.tryParse(_levelController.text),
      'scale': _scaleController.text.isEmpty ? null : int.tryParse(_scaleController.text),
      'linkval': _linkMarkers.length,
      'linkmarkers': _linkMarkers.isEmpty ? null : _linkMarkers.join(','),
      if (translations.isNotEmpty) 'translations': translations,
      if (sets.isNotEmpty) 'sets': sets,
      '_adminModified': true,
    };

    Navigator.pop(context, cardData);
  }
}
