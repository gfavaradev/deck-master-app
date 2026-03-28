import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/image_upload_service.dart';

// ─── Suggestions service ────────────────────────────────────────────────────

/// Persists per-language lists of set names and rarities in SharedPreferences.
/// Lists grow automatically as the admin saves new values.
class AdminSuggestionsService {
  static const _setNamesPrefix = 'admin_setnames_';
  static const _raritiesPrefix = 'admin_rarities_';

  static const _defaultRarities = [
    'Common', 'Rare', 'Super Rare', 'Ultra Rare', 'Ultimate Rare',
    'Secret Rare', 'Prismatic Secret Rare', 'Ghost Rare', 'Starlight Rare',
    "Collector's Rare", 'Quarter Century Secret Rare', 'Mosaic Rare',
    'Shatterfoil Rare', 'Short Print', 'Super Short Print',
  ];

  static Future<List<String>> getSetNames(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('$_setNamesPrefix$lang') ?? [];
  }

  static Future<List<String>> getRarities(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('$_raritiesPrefix$lang') ?? [];
    final result = List<String>.from(stored);
    for (final r in _defaultRarities) {
      if (!result.contains(r)) result.add(r);
    }
    return result;
  }

  static Future<void> addSetName(String lang, String name) async {
    if (name.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = '$_setNamesPrefix$lang';
    final list = prefs.getStringList(key) ?? [];
    if (!list.contains(name)) {
      list.insert(0, name);
      if (list.length > 300) list.removeLast();
      await prefs.setStringList(key, list);
    }
  }

  static Future<void> addRarity(String lang, String rarity) async {
    if (rarity.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = '$_raritiesPrefix$lang';
    final list = prefs.getStringList(key) ?? [];
    if (!list.contains(rarity)) {
      list.insert(0, rarity);
      if (list.length > 100) list.removeLast();
      await prefs.setStringList(key, list);
    }
  }
}

/// Comprehensive dialog for adding/editing catalog cards
/// Tabs: Info Base | Traduzioni | Meccaniche/Stats | Set per Lingua
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
  late TextEditingController _imageUrlController;
  bool _imageUploading = false;
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

  // --- Pokemon fields ---
  String _pkSupertype = 'Pokémon'; // Pokémon | Trainer | Energy
  List<String> _pkSubtypes = [];
  late TextEditingController _pkHpController;
  List<String> _pkTypes = []; // energy types
  late TextEditingController _pkEvolvesFromController;
  late TextEditingController _pkArtistController;
  String _pkRegulationMark = '';
  late TextEditingController _pkPokedexController; // comma-separated numbers
  List<Map<String, dynamic>> _pkAttacks = []; // {name, cost:[], damage, text}
  List<Map<String, dynamic>> _pkAbilities = []; // {name, type, text}
  List<Map<String, dynamic>> _pkWeaknesses = []; // {type, value}
  List<Map<String, dynamic>> _pkResistances = []; // {type, value}
  int _pkRetreatCost = 0;
  List<String> _pkRules = [];

  // --- One Piece fields ---
  String _opCardType = 'Character'; // Leader | Character | Event | Stage | DON!!
  List<String> _opColors = []; // Red, Blue, Green, Yellow, Purple, Black
  late TextEditingController _opCostController;
  late TextEditingController _opPowerController;
  late TextEditingController _opCounterController;
  late TextEditingController _opLifeController; // Leader only
  String _opAttribute = ''; // Slash | Strike | Ranged | Wisdom | Special | ?
  late TextEditingController _opSubTypesController; // e.g. "Straw Hat Crew"
  late TextEditingController _opTriggerController;

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
  // Languages officially printed per catalog
  static const Map<String, List<String>> _catalogSetLanguages = {
    'yugioh':   ['en', 'it', 'fr', 'de', 'pt', 'sp'],
    'pokemon':  ['en', 'ja', 'fr', 'de', 'it', 'es', 'pt', 'ko'],
    'onepiece': ['ja', 'en', 'fr', 'zh', 'ko'],
    'magic':    ['en', 'it', 'fr', 'de', 'pt', 'es'],
  };

  static const Map<String, String> _allSetLanguageLabels = {
    'en': 'Inglese',
    'it': 'Italiano',
    'fr': 'Francese',
    'de': 'Tedesco',
    'pt': 'Portoghese',
    'sp': 'Spagnolo',
    'es': 'Spagnolo',
    'ja': 'Giapponese',
    'zh': 'Cinese (Semplificato)',
    'ko': 'Coreano',
  };

  List<String> get _currentSetLanguages =>
      _catalogSetLanguages[_catalog] ?? _catalogSetLanguages['yugioh']!;

  String _setLangLabel(String lang) => _allSetLanguageLabels[lang] ?? lang.toUpperCase();

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

    _imageUrlController = TextEditingController(text: card['image_url'] ?? '');

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
    _setsByLanguage = {for (final l in _currentSetLanguages) l: []};

    final setsMap = card['sets'] as Map<String, dynamic>?;
    if (setsMap != null) {
      for (final lang in _currentSetLanguages) {
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

    // Pokemon init
    _pkHpController = TextEditingController(text: card['hp']?.toString() ?? '');
    _pkEvolvesFromController = TextEditingController(text: card['evolvesFrom'] ?? '');
    _pkArtistController = TextEditingController(text: card['artist'] ?? '');
    _pkRegulationMark = card['regulationMark'] ?? '';
    _pkPokedexController = TextEditingController(
      text: (card['nationalPokedexNumbers'] as List?)?.join(', ') ?? '',
    );
    _pkSupertype = card['supertype'] ?? 'Pokémon';
    _pkSubtypes = List<String>.from(card['subtypes'] ?? []);
    _pkTypes = List<String>.from(card['types'] ?? []);
    _pkAttacks = (card['attacks'] as List?)
        ?.map((a) => Map<String, dynamic>.from(a as Map))
        .toList() ?? [];
    _pkAbilities = (card['abilities'] as List?)
        ?.map((a) => Map<String, dynamic>.from(a as Map))
        .toList() ?? [];
    _pkWeaknesses = (card['weaknesses'] as List?)
        ?.map((w) => Map<String, dynamic>.from(w as Map))
        .toList() ?? [];
    _pkResistances = (card['resistances'] as List?)
        ?.map((r) => Map<String, dynamic>.from(r as Map))
        .toList() ?? [];
    _pkRetreatCost = (card['convertedRetreatCost'] as int?) ?? 0;
    _pkRules = List<String>.from(card['rules'] ?? []);

    // One Piece init
    _opCardType = card['op_card_type'] ?? 'Character';
    _opColors = List<String>.from(card['op_colors'] ?? []);
    _opCostController = TextEditingController(text: card['op_cost']?.toString() ?? '');
    _opPowerController = TextEditingController(text: card['op_power']?.toString() ?? '');
    _opCounterController = TextEditingController(text: card['op_counter']?.toString() ?? '');
    _opLifeController = TextEditingController(text: card['op_life']?.toString() ?? '');
    _opAttribute = card['op_attribute'] ?? '';
    _opSubTypesController = TextEditingController(text: card['op_subtypes'] ?? '');
    _opTriggerController = TextEditingController(text: card['op_trigger'] ?? '');
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
    _imageUrlController.dispose();
    _atkController.dispose();
    _defController.dispose();
    _levelController.dispose();
    _scaleController.dispose();
    _descEnController.dispose();
    for (final c in _transNameControllers.values) { c.dispose(); }
    for (final c in _transDescControllers.values) { c.dispose(); }
    _pkHpController.dispose();
    _pkEvolvesFromController.dispose();
    _pkArtistController.dispose();
    _pkPokedexController.dispose();
    _opCostController.dispose();
    _opPowerController.dispose();
    _opCounterController.dispose();
    _opLifeController.dispose();
    _opSubTypesController.dispose();
    _opTriggerController.dispose();
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
              tabs: [
                const Tab(text: 'Info Base'),
                const Tab(text: 'Traduzioni'),
                Tab(text: _catalog == 'pokemon' ? 'Meccaniche' : 'Stats'),
                const Tab(text: 'Set per Lingua'),
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
          _sectionTitle('Catalogo'),
          _dropdown('Catalogo', _catalog, ['yugioh', 'pokemon', 'magic', 'onepiece'],
              (v) {
                if (v == null || v == _catalog) return;
                setState(() {
                  _catalog = v;
                  // Rebuild _setsByLanguage preserving existing data for common languages
                  final newLangs = _catalogSetLanguages[v] ?? _catalogSetLanguages['yugioh']!;
                  final newMap = <String, List<Map<String, dynamic>>>{};
                  for (final l in newLangs) {
                    newMap[l] = List.from(_setsByLanguage[l] ?? []);
                  }
                  _setsByLanguage = newMap;
                });
              }),
          _sectionTitle('Nome e Descrizione (EN) *'),
          _field('Nome Inglese *', _nameEnController),
          _field('Descrizione Inglese', _descEnController, maxLines: 4),
          _sectionTitle('Immagine Carta'),
          StatefulBuilder(
            builder: (ctx, setS) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _imageUrlController,
                        decoration: InputDecoration(
                          labelText: 'Image URL',
                          hintText: 'Carica dal dispositivo →',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: _imageUrlController.text.contains('firebasestorage')
                              ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
                              : null,
                        ),
                        readOnly: _imageUrlController.text.contains('firebasestorage'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_imageUploading)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.upload_file, color: Colors.orange),
                        tooltip: 'Carica dal dispositivo',
                        onPressed: () async {
                          setS(() => _imageUploading = true);
                          try {
                            final url = await ImageUploadService.pickAndUpload(
                              catalog: _catalog,
                              cardId: _cardId!,
                              setCode: null,
                            );
                            if (ctx.mounted && url != null) setS(() => _imageUrlController.text = url);
                          } finally {
                            if (ctx.mounted) setS(() => _imageUploading = false);
                          }
                        },
                      ),
                  ],
                ),
                if (_imageUrlController.text.contains('firebasestorage'))
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        _imageUrlController.text,
                        height: 100,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stack) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_catalog == 'yugioh') ...[
            _sectionTitle('Tipo e Categoria'),
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
          ] else if (_catalog == 'pokemon')
            _buildPokemonInfoSection()
          else if (_catalog == 'onepiece')
            _buildOnePieceInfoSection(),
        ],
      ),
    );
  }

  // ─── Pokemon Info Section ────────────────────────────────────────────────────

  Widget _buildPokemonInfoSection() {
    const supertypes = ['Pokémon', 'Trainer', 'Energy'];
    const allSubtypes = [
      'Basic', 'Stage 1', 'Stage 2', 'V', 'VMAX', 'VSTAR', 'EX', 'GX', 'ex',
      'Mega', 'Rapid Strike', 'Single Strike', 'Item', 'Supporter', 'Stadium',
      'Pokémon Tool', 'ACE SPEC',
    ];
    const energyTypes = [
      'Grass', 'Fire', 'Water', 'Lightning', 'Psychic',
      'Fighting', 'Darkness', 'Metal', 'Dragon', 'Colorless',
    ];
    const regMarks = ['', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Tipo Carta'),
        _dropdown('Supertype', _pkSupertype, supertypes, (v) => setState(() => _pkSupertype = v!)),

        _sectionTitle('Sottotipi'),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: allSubtypes.map((st) => FilterChip(
            label: Text(st, style: const TextStyle(fontSize: 11)),
            selected: _pkSubtypes.contains(st),
            onSelected: (v) => setState(() {
              if (v) { _pkSubtypes.add(st); } else { _pkSubtypes.remove(st); }
            }),
          )).toList(),
        ),
        const SizedBox(height: 12),

        if (_pkSupertype == 'Pokémon') ...[
          _sectionTitle('Statistiche Pokémon'),
          Row(children: [
            Expanded(child: _field('HP', _pkHpController, number: true)),
            const SizedBox(width: 8),
            Expanded(child: _field('Evolve da', _pkEvolvesFromController)),
          ]),
          _sectionTitle('Tipi Energia'),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: energyTypes.map((t) => FilterChip(
              label: Text(t, style: const TextStyle(fontSize: 11)),
              selected: _pkTypes.contains(t),
              onSelected: (v) => setState(() {
                if (v) { _pkTypes.add(t); } else { _pkTypes.remove(t); }
              }),
            )).toList(),
          ),
          const SizedBox(height: 12),
        ],

        _sectionTitle('Altre Info'),
        Row(children: [
          Expanded(child: _field('Artista', _pkArtistController)),
          const SizedBox(width: 8),
          Expanded(
            child: _dropdown('Regulation Mark', _pkRegulationMark, regMarks,
                (v) => setState(() => _pkRegulationMark = v!)),
          ),
        ]),
        _field('N° Pokédex (separati da virgola)', _pkPokedexController),
      ],
    );
  }

  // ─── One Piece Info Section ──────────────────────────────────────────────────

  Widget _buildOnePieceInfoSection() {
    const cardTypes = ['Leader', 'Character', 'Event', 'Stage', 'DON!!'];
    const colors = ['Red', 'Blue', 'Green', 'Yellow', 'Purple', 'Black'];
    const attributes = ['', 'Slash', 'Strike', 'Ranged', 'Wisdom', 'Special', '?'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Tipo e Colore'),
        _dropdown('Tipo Carta', _opCardType, cardTypes, (v) => setState(() => _opCardType = v!)),
        _sectionTitle('Colori'),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: colors.map((c) {
            final colorMap = {
              'Red': Colors.red.shade400,
              'Blue': Colors.blue.shade400,
              'Green': Colors.green.shade400,
              'Yellow': Colors.yellow.shade600,
              'Purple': Colors.purple.shade400,
              'Black': Colors.grey.shade800,
            };
            return FilterChip(
              label: Text(c, style: TextStyle(
                fontSize: 11,
                color: _opColors.contains(c) ? Colors.white : Colors.black87,
              )),
              selected: _opColors.contains(c),
              selectedColor: colorMap[c],
              onSelected: (v) => setState(() {
                if (v) { _opColors.add(c); } else { _opColors.remove(c); }
              }),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),

        _sectionTitle('Statistiche'),
        Row(children: [
          Expanded(child: _field('Costo (DON!!)', _opCostController, number: true)),
          const SizedBox(width: 8),
          Expanded(child: _field('Potere', _opPowerController, number: true)),
        ]),
        Row(children: [
          Expanded(child: _field('Counter', _opCounterController, number: true)),
          const SizedBox(width: 8),
          Expanded(child: _field(
            'Vita (solo Leader)',
            _opLifeController,
            number: true,
          )),
        ]),
        _dropdown('Attributo', _opAttribute, attributes, (v) => setState(() => _opAttribute = v!)),
        _field('Famiglie / Sottotipi', _opSubTypesController),
        _field('Effetto Trigger', _opTriggerController, maxLines: 3),
      ],
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
    if (_catalog == 'pokemon') {
      return _buildPokemonMechanicsSection();
    }
    if (_catalog != 'yugioh') {
      return const Center(
        child: Text('Statistiche non applicabili per questa collezione.',
            style: TextStyle(color: Colors.grey)),
      );
    }
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

  // ─── Pokemon Mechanics Section ───────────────────────────────────────────────

  Widget _buildPokemonMechanicsSection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Attacks ---
          Row(
            children: [
              _sectionTitle('Attacchi'),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _addPokemonAttack(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Aggiungi'),
              ),
            ],
          ),
          if (_pkAttacks.isEmpty)
            const Text('Nessun attacco.', style: TextStyle(color: Colors.grey, fontSize: 12))
          else
            ..._pkAttacks.asMap().entries.map((e) => Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text(e.value['name'] ?? '—', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  '${(e.value['cost'] as List?)?.join(', ') ?? ''} • ${e.value['damage'] ?? ''}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.edit, size: 16), onPressed: () => _editPokemonAttack(e.key)),
                    IconButton(icon: const Icon(Icons.delete, size: 16, color: Colors.red), onPressed: () => setState(() => _pkAttacks.removeAt(e.key))),
                  ],
                ),
              ),
            )),
          const SizedBox(height: 8),

          // --- Abilities ---
          Row(
            children: [
              _sectionTitle('Abilità'),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _addPokemonAbility(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Aggiungi'),
              ),
            ],
          ),
          if (_pkAbilities.isEmpty)
            const Text('Nessuna abilità.', style: TextStyle(color: Colors.grey, fontSize: 12))
          else
            ..._pkAbilities.asMap().entries.map((e) => Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text(e.value['name'] ?? '—', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${e.value['type'] ?? 'Ability'} • ${e.value['text'] ?? ''}',
                  style: const TextStyle(fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.edit, size: 16), onPressed: () => _editPokemonAbility(e.key)),
                    IconButton(icon: const Icon(Icons.delete, size: 16, color: Colors.red), onPressed: () => setState(() => _pkAbilities.removeAt(e.key))),
                  ],
                ),
              ),
            )),
          const SizedBox(height: 8),

          // --- Weaknesses & Resistances ---
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      _sectionTitle('Debolezze'),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.add, size: 18),
                        onPressed: () => _addWeaknessOrResistance(true),
                      ),
                    ]),
                    ..._pkWeaknesses.asMap().entries.map((e) => Chip(
                      label: Text('${e.value['type']} ${e.value['value']}'),
                      onDeleted: () => setState(() => _pkWeaknesses.removeAt(e.key)),
                    )),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      _sectionTitle('Resistenze'),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.add, size: 18),
                        onPressed: () => _addWeaknessOrResistance(false),
                      ),
                    ]),
                    ..._pkResistances.asMap().entries.map((e) => Chip(
                      label: Text('${e.value['type']} ${e.value['value']}'),
                      onDeleted: () => setState(() => _pkResistances.removeAt(e.key)),
                    )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // --- Retreat Cost ---
          _sectionTitle('Costo Ritirata'),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _pkRetreatCost > 0 ? () => setState(() => _pkRetreatCost--) : null,
              ),
              Text('$_pkRetreatCost', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => setState(() => _pkRetreatCost++),
              ),
              const Text('energia/e', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Pokemon Attack dialog methods ──────────────────────────────────────────

  Future<void> _addPokemonAttack() async {
    final result = await _showPokemonAttackDialog();
    if (result != null) setState(() => _pkAttacks.add(result));
  }

  Future<void> _editPokemonAttack(int index) async {
    final result = await _showPokemonAttackDialog(initial: _pkAttacks[index]);
    if (result != null) setState(() => _pkAttacks[index] = result);
  }

  Future<Map<String, dynamic>?> _showPokemonAttackDialog({Map<String, dynamic>? initial}) async {
    final nameCtrl = TextEditingController(text: initial?['name'] ?? '');
    final damageCtrl = TextEditingController(text: initial?['damage'] ?? '');
    final textCtrl = TextEditingController(text: initial?['text'] ?? '');
    List<String> cost = List<String>.from(initial?['cost'] ?? []);
    const energyTypes = ['Grass', 'Fire', 'Water', 'Lightning', 'Psychic', 'Fighting', 'Darkness', 'Metal', 'Dragon', 'Colorless'];

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(initial == null ? 'Nuovo Attacco' : 'Modifica Attacco'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nome Attacco *', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                const Text('Costo Energia:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  children: energyTypes.map((t) => FilterChip(
                    label: Text(t, style: const TextStyle(fontSize: 10)),
                    selected: cost.contains(t),
                    onSelected: (v) => setS(() {
                      if (v) { cost.add(t); } else { cost.remove(t); }
                    }),
                  )).toList(),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: damageCtrl, decoration: const InputDecoration(labelText: 'Danno (es. 120)', border: OutlineInputBorder()))),
                ]),
                const SizedBox(height: 8),
                TextField(controller: textCtrl, decoration: const InputDecoration(labelText: 'Testo Effetto', border: OutlineInputBorder()), maxLines: 3),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, {
                  'name': nameCtrl.text.trim(),
                  'cost': cost,
                  'convertedEnergyCost': cost.length,
                  'damage': damageCtrl.text.trim(),
                  'text': textCtrl.text.trim(),
                });
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );

    nameCtrl.dispose(); damageCtrl.dispose(); textCtrl.dispose();
    return result;
  }

  // ─── Pokemon Ability dialog methods ─────────────────────────────────────────

  Future<void> _addPokemonAbility() async {
    final result = await _showPokemonAbilityDialog();
    if (result != null) setState(() => _pkAbilities.add(result));
  }

  Future<void> _editPokemonAbility(int index) async {
    final result = await _showPokemonAbilityDialog(initial: _pkAbilities[index]);
    if (result != null) setState(() => _pkAbilities[index] = result);
  }

  Future<Map<String, dynamic>?> _showPokemonAbilityDialog({Map<String, dynamic>? initial}) async {
    final nameCtrl = TextEditingController(text: initial?['name'] ?? '');
    final textCtrl = TextEditingController(text: initial?['text'] ?? '');
    String abilityType = initial?['type'] ?? 'Ability';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(initial == null ? 'Nuova Abilità' : 'Modifica Abilità'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nome Abilità *', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: abilityType,
                decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
                items: ['Ability', 'Pokémon Power'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setS(() => abilityType = v!),
              ),
              const SizedBox(height: 8),
              TextField(controller: textCtrl, decoration: const InputDecoration(labelText: 'Testo Effetto *', border: OutlineInputBorder()), maxLines: 3),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty || textCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, {'name': nameCtrl.text.trim(), 'type': abilityType, 'text': textCtrl.text.trim()});
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );

    nameCtrl.dispose(); textCtrl.dispose();
    return result;
  }

  // ─── Weakness/Resistance dialog ──────────────────────────────────────────────

  Future<void> _addWeaknessOrResistance(bool isWeakness) async {
    const energyTypes = ['Grass', 'Fire', 'Water', 'Lightning', 'Psychic', 'Fighting', 'Darkness', 'Metal', 'Dragon', 'Colorless'];
    String selectedType = energyTypes.first;
    final valueCtrl = TextEditingController(text: isWeakness ? '×2' : '-20');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(isWeakness ? 'Aggiungi Debolezza' : 'Aggiungi Resistenza'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
                items: energyTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setS(() => selectedType = v!),
              ),
              const SizedBox(height: 8),
              TextField(controller: valueCtrl, decoration: InputDecoration(
                labelText: isWeakness ? 'Moltiplicatore (es. ×2)' : 'Riduzione (es. -20)',
                border: const OutlineInputBorder(),
              )),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, {'type': selectedType, 'value': valueCtrl.text.trim()}),
              child: const Text('Aggiungi'),
            ),
          ],
        ),
      ),
    );

    valueCtrl.dispose();
    if (result != null) {
      setState(() {
        if (isWeakness) { _pkWeaknesses.add(result); } else { _pkResistances.add(result); }
      });
    }
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
            children: _currentSetLanguages.map((lang) {
              final sets = _setsByLanguage[lang] ?? [];
              final label = _setLangLabel(lang);
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
  /// e.g. LOB-EN001 → LOB-IT001  (formato con sigla lingua)
  ///      AST-070   → AST-IT070  (formato senza sigla lingua)
  static String? _localizedSetCode(String enCode, String targetLang) {
    final upper = enCode.toUpperCase();
    final langCode = switch (targetLang) {
      'it' => 'IT',
      'fr' => 'FR',
      'de' => 'DE',
      'pt' => 'PT',
      'sp' => 'SP',
      _ => null,
    };
    if (langCode == null) return null;

    // Caso 1: PREFIX-EN001 o PREFIX-E001 → PREFIX-IT001
    final matchWithLang = RegExp(r'^([A-Z0-9]+)-(EN|E)(.+)$').firstMatch(upper);
    if (matchWithLang != null) {
      final isShort = matchWithLang.group(2) == 'E';
      final prefix = matchWithLang.group(1)!;
      final suffix = matchWithLang.group(3)!;
      final code = isShort ? langCode[0] : langCode;
      return '$prefix-$code$suffix';
    }

    // Caso 2: PREFIX-070 (nessuna sigla lingua) → PREFIX-IT070
    final matchNoLang = RegExp(r'^([A-Z0-9]+)-(\d+.*)$').firstMatch(upper);
    if (matchNoLang != null) {
      final prefix = matchNoLang.group(1)!;
      final numbers = matchNoLang.group(2)!;
      return '$prefix-$langCode$numbers';
    }

    return null;
  }

  /// Auto-generates IT/FR/DE/PT sets from existing EN sets.
  void _generateSetsFromEn() {
    final enSets = List<Map<String, dynamic>>.from(_setsByLanguage['en'] ?? []);
    if (enSets.isEmpty) return;

    setState(() {
      for (final lang in _currentSetLanguages.where((l) => l != 'en')) {
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
    if (result != null) setState(() => (_setsByLanguage[lang] ??= []).add(result));
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
    final priceCtrl = TextEditingController(
      text: (initialData?['set_price'] as num?)?.toStringAsFixed(2) ?? '0.00',
    );
    final langLabel = _setLangLabel(lang);

    // Valori correnti per set name e rarity (gestiti da Autocomplete)
    String currentSetName = initialData?['set_name'] ?? '';
    String currentRarity = initialData?['rarity'] ?? '';

    // Suggerimenti per lingua (caricati prima di aprire il dialog)
    final results = await Future.wait([
      AdminSuggestionsService.getSetNames(lang),
      AdminSuggestionsService.getRarities(lang),
    ]);
    List<String> setNameSugs = results[0];
    List<String> raritySugs = results[1];

    if (!mounted) return null;
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
                  // Set Name con autocomplete
                  _autocompleteField(
                    label: 'Set Name *',
                    initialValue: currentSetName,
                    suggestions: setNameSugs,
                    onChanged: (v) => currentSetName = v,
                  ),
                  const SizedBox(height: 12),
                  // Rarità con autocomplete
                  _autocompleteField(
                    label: 'Rarità *',
                    initialValue: currentRarity,
                    suggestions: raritySugs,
                    onChanged: (v) => currentRarity = v,
                  ),
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
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
              ElevatedButton(
                onPressed: () async {
                  if (setCodeCtrl.text.trim().isEmpty ||
                      currentSetName.trim().isEmpty ||
                      currentRarity.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Tutti i campi sono obbligatori')),
                    );
                    return;
                  }
                  await AdminSuggestionsService.addSetName(lang, currentSetName.trim());
                  await AdminSuggestionsService.addRarity(lang, currentRarity.trim());
                  if (ctx.mounted) {
                    Navigator.pop(ctx, {
                      'set_code': setCodeCtrl.text.trim(),
                      'set_name': currentSetName.trim(),
                      'rarity': currentRarity.trim(),
                      'set_price': double.tryParse(priceCtrl.text) ?? 0.0,
                    });
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                child: const Text('Salva'),
              ),
            ],
          );
        },
      ),
    );

    for (final c in [setCodeCtrl, priceCtrl]) {
      c.dispose();
    }
    return result;
  }


  /// Campo con autocomplete a dropdown. Usa [suggestions] per mostrare opzioni
  /// mentre si digita; chiama [onChanged] ad ogni modifica.
  Widget _autocompleteField({
    required String label,
    required String initialValue,
    required List<String> suggestions,
    required void Function(String) onChanged,
  }) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: initialValue),
      optionsBuilder: (TextEditingValue tv) {
        if (suggestions.isEmpty) return const Iterable.empty();
        if (tv.text.isEmpty) return suggestions;
        final q = tv.text.toLowerCase();
        return suggestions.where((s) => s.toLowerCase().contains(q));
      },
      onSelected: onChanged,
      fieldViewBuilder: (ctx, ctrl, focusNode, _) {
        ctrl.addListener(() => onChanged(ctrl.text));
        return TextField(
          controller: ctrl,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        );
      },
      optionsViewBuilder: (ctx, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200, maxWidth: 400),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (_, i) {
                final option = options.elementAt(i);
                return ListTile(
                  dense: true,
                  title: Text(option),
                  onTap: () => onSelected(option),
                );
              },
            ),
          ),
        ),
      ),
    );
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
    for (final lang in _currentSetLanguages) {
      if ((_setsByLanguage[lang] ?? []).isNotEmpty) {
        sets[lang] = _setsByLanguage[lang]!;
      }
    }

    final cardData = <String, dynamic>{
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
      if (_imageUrlController.text.trim().isNotEmpty) 'image_url': _imageUrlController.text.trim(),
      if (translations.isNotEmpty) 'translations': translations,
      if (sets.isNotEmpty) 'sets': sets,
      '_adminModified': true,
    };

    if (_catalog == 'pokemon') {
      cardData['supertype'] = _pkSupertype;
      if (_pkSubtypes.isNotEmpty) cardData['subtypes'] = _pkSubtypes;
      if (_pkHpController.text.isNotEmpty) cardData['hp'] = int.tryParse(_pkHpController.text.trim()) ?? _pkHpController.text.trim();
      if (_pkTypes.isNotEmpty) cardData['types'] = _pkTypes;
      if (_pkEvolvesFromController.text.isNotEmpty) cardData['evolvesFrom'] = _pkEvolvesFromController.text.trim();
      if (_pkArtistController.text.isNotEmpty) cardData['artist'] = _pkArtistController.text.trim();
      if (_pkRegulationMark.isNotEmpty) cardData['regulationMark'] = _pkRegulationMark;
      if (_pkPokedexController.text.isNotEmpty) {
        cardData['nationalPokedexNumbers'] = _pkPokedexController.text
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>()
            .toList();
      }
      if (_pkAttacks.isNotEmpty) cardData['attacks'] = _pkAttacks;
      if (_pkAbilities.isNotEmpty) cardData['abilities'] = _pkAbilities;
      if (_pkWeaknesses.isNotEmpty) cardData['weaknesses'] = _pkWeaknesses;
      if (_pkResistances.isNotEmpty) cardData['resistances'] = _pkResistances;
      cardData['convertedRetreatCost'] = _pkRetreatCost;
      if (_pkRules.isNotEmpty) cardData['rules'] = _pkRules;
    }

    if (_catalog == 'onepiece') {
      cardData['op_card_type'] = _opCardType;
      if (_opColors.isNotEmpty) cardData['op_colors'] = _opColors;
      if (_opCostController.text.isNotEmpty) cardData['op_cost'] = int.tryParse(_opCostController.text);
      if (_opPowerController.text.isNotEmpty) cardData['op_power'] = int.tryParse(_opPowerController.text);
      if (_opCounterController.text.isNotEmpty) cardData['op_counter'] = int.tryParse(_opCounterController.text);
      if (_opLifeController.text.isNotEmpty) cardData['op_life'] = int.tryParse(_opLifeController.text);
      if (_opAttribute.isNotEmpty) cardData['op_attribute'] = _opAttribute;
      if (_opSubTypesController.text.isNotEmpty) cardData['op_subtypes'] = _opSubTypesController.text.trim();
      if (_opTriggerController.text.isNotEmpty) cardData['op_trigger'] = _opTriggerController.text.trim();
    }

    Navigator.pop(context, cardData);
  }
}
