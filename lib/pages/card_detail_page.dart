import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/card_model.dart';
import '../models/album_model.dart';
import '../services/data_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/app_dialog.dart';
import '../services/cardtrader_service.dart' show CardtraderService;
import '../widgets/cardtrader_price_badge.dart' show CardtraderAllPricesSection;
import '../widgets/cardtrader_price_history.dart';

String _langFromSerial(String sn, String collection) =>
    CardtraderService.languageFromSerial(sn, collection);

Color _rarityColor(String rarity) {
  final code = rarity.toUpperCase();
  const map = {
    'C': Color(0xFF757575), 'N': Color(0xFF9E9E9E), 'COMMON': Color(0xFF757575),
    'R': Color(0xFF1976D2), 'RARE': Color(0xFF1976D2),
    'SR': Color(0xFF00ACC1), 'SUPER RARE': Color(0xFF00ACC1),
    'UR': Color(0xFFFFB300), 'ULTRA RARE': Color(0xFFFFB300),
    'SCR': Color(0xFF7B1FA2), 'SECRET RARE': Color(0xFF7B1FA2),
    'SLR': Color(0xFFEC407A), 'STARLIGHT RARE': Color(0xFFEC407A),
  };
  if (map.containsKey(code)) return map[code]!;
  for (final e in map.entries) {
    if (code.contains(e.key)) return e.value;
  }
  return AppColors.textHint;
}

Color _collectionAccent(String collection) => switch (collection) {
  'yugioh'   => AppColors.yugiohAccent,
  'pokemon'  => AppColors.pokemonAccent,
  'onepiece' => AppColors.onepieceAccent,
  _          => AppColors.gold,
};

// ─────────────────────────────────────────────────────────────────────────────

class CardDetailPage extends StatefulWidget {
  /// Lista completa di carte navigabili con swipe.
  final List<CardModel> cards;
  /// Indice della carta da mostrare all'apertura.
  final int initialIndex;
  final Function(CardModel) onDelete;
  final List<AlbumModel> availableAlbums;
  final VoidCallback? onAlbumChanged;
  /// Deck della carta all'indice iniziale; vengono ricaricati ad ogni navigazione.
  final List<Map<String, dynamic>> initialDecks;

  const CardDetailPage({
    super.key,
    required this.cards,
    required this.initialIndex,
    required this.onDelete,
    this.availableAlbums = const [],
    this.onAlbumChanged,
    this.initialDecks = const [],
  });

  @override
  State<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<CardDetailPage> {
  late int _currentIndex;
  late int? _selectedAlbumId;
  List<Map<String, dynamic>> _decks = [];
  Map<String, dynamic>? _extraInfo;

  // Direzione per l'animazione: +1 = arriva da destra, -1 = arriva da sinistra
  int _slideDir = 1;

  CardModel get _card => widget.cards[_currentIndex];
  bool get _hasPrev => _currentIndex > 0;
  bool get _hasNext => _currentIndex < widget.cards.length - 1;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.cards.length - 1);
    _selectedAlbumId = _card.albumId == -1 ? null : _card.albumId;
    _decks = widget.initialDecks;
    _loadExtraInfo(_card);
  }

  Future<void> _loadExtraInfo(CardModel card) async {
    final info = await DataRepository()
        .getCardExtraInfo(card.collection, card.catalogId);
    if (!mounted) return;
    setState(() => _extraInfo = info);
  }

  Future<void> _navigateTo(int index, {required int dir}) async {
    if (index < 0 || index >= widget.cards.length) return;
    final newCard = widget.cards[index];
    final repo = DataRepository();
    final results = await Future.wait([
      newCard.id != null
          ? repo.getDecksForCard(newCard.id!)
          : Future.value(<Map<String, dynamic>>[]),
      repo.getCardExtraInfo(newCard.collection, newCard.catalogId),
    ]);
    if (!mounted) return;
    setState(() {
      _slideDir = dir;
      _currentIndex = index;
      _selectedAlbumId = newCard.albumId == -1 ? null : newCard.albumId;
      _decks = results[0] as List<Map<String, dynamic>>;
      _extraInfo = results[1] as Map<String, dynamic>?;
    });
  }

  void _onSwipe(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    if (v < -300 && _hasNext) _navigateTo(_currentIndex + 1, dir: -1);
    if (v > 300 && _hasPrev) _navigateTo(_currentIndex - 1, dir: 1);
  }

  Future<void> _changeAlbum(int? newId) async {
    if (newId == null || newId == _selectedAlbumId) return;
    setState(() => _selectedAlbumId = newId);
    await DataRepository().updateCard(_card.copyWith(albumId: newId));
    widget.onAlbumChanged?.call();
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AppConfirmDialog(
        title: 'Elimina carta',
        icon: Icons.delete_outline,
        message: 'Eliminare "${_card.name}" dalla collezione?',
        confirmLabel: 'Elimina',
      ),
    );
    if (confirm != true || !mounted) return;
    Navigator.pop(context);
    widget.onDelete(_card);
  }

  String _currentAlbumName() {
    final id = _selectedAlbumId ?? _card.albumId;
    return widget.availableAlbums
        .firstWhere(
          (a) => a.id == id,
          orElse: () => AlbumModel(name: '—', collection: _card.collection, maxCapacity: 0),
        )
        .name;
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ────────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bgMedium,
            surfaceTintColor: Colors.transparent,
            iconTheme: const IconThemeData(color: AppColors.textPrimary),
            title: Text(
              card.name,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                tooltip: 'Elimina',
                onPressed: _delete,
              ),
            ],
          ),

          // ── Body ───────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Immagine sinistra + info destra
                _CardHeader(
                  card: card,
                  extraInfo: _extraInfo,
                  slideKey: _currentIndex,
                  slideDir: _slideDir,
                  hasPrev: _hasPrev,
                  hasNext: _hasNext,
                  cardIndex: _currentIndex,
                  cardCount: widget.cards.length,
                  onSwipe: _onSwipe,
                  onPrev: _hasPrev
                      ? () => _navigateTo(_currentIndex - 1, dir: 1)
                      : null,
                  onNext: _hasNext
                      ? () => _navigateTo(_currentIndex + 1, dir: -1)
                      : null,
                ),

                // Descrizione
                if (card.description.isNotEmpty) ...[
                  const Divider(color: AppColors.divider, height: 1),
                  _DescriptionPanel(description: card.description),
                ],

                const Divider(color: AppColors.divider, height: 1),

                // Album
                _AlbumPanel(
                  availableAlbums: widget.availableAlbums,
                  selectedId: _selectedAlbumId,
                  currentName: _currentAlbumName(),
                  onChanged: _changeAlbum,
                ),

                // Prezzi CardTrader
                if (card.serialNumber.isNotEmpty) ...[
                  const Divider(color: AppColors.divider, height: 1),
                  _PricesPanel(card: card),
                  const Divider(color: AppColors.divider, height: 1),
                  _Panel(
                    title: 'ANDAMENTO PREZZI',
                    child: CardtraderPriceHistoryChart(card: card),
                  ),
                ],

                // Deck
                if (_decks.isNotEmpty) ...[
                  const Divider(color: AppColors.divider, height: 1),
                  _DecksPanel(decks: _decks),
                ],

                const SizedBox(height: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Card header: image left (swipeable) + info right ─────────────────────────

class _CardHeader extends StatelessWidget {
  final CardModel card;
  final Map<String, dynamic>? extraInfo;
  final int slideKey;
  final int slideDir;   // +1 nuova carta arriva da destra, -1 da sinistra
  final bool hasPrev;
  final bool hasNext;
  final int cardIndex;
  final int cardCount;
  final GestureDragEndCallback onSwipe;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _CardHeader({
    required this.card,
    required this.extraInfo,
    required this.slideKey,
    required this.slideDir,
    required this.hasPrev,
    required this.hasNext,
    required this.cardIndex,
    required this.cardCount,
    required this.onSwipe,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _collectionAccent(card.collection);
    final hasImage = card.imageUrl != null && card.imageUrl!.isNotEmpty;
    final showCounter = cardCount > 1;

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Riga: immagine + info ──────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final imgWidth = constraints.maxWidth * 0.48;
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                // ── Immagine (swipeable) ─────────────────────────────────────
                GestureDetector(
                  onHorizontalDragEnd: onSwipe,
                  child: SizedBox(
                    width: imgWidth,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 240),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Sfondo sfumato collezione
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  accent.withValues(alpha: 0.38),
                                  AppColors.bgMedium,
                                ],
                              ),
                            ),
                          ),
                          // Immagine con animazione al cambio carta
                          if (hasImage)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 10, 10, 28),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                transitionBuilder: (child, anim) {
                                  final slide = Tween<Offset>(
                                    begin: Offset(-slideDir.toDouble() * 0.25, 0),
                                    end: Offset.zero,
                                  ).animate(CurvedAnimation(
                                    parent: anim,
                                    curve: Curves.easeOut,
                                  ));
                                  return SlideTransition(
                                    position: slide,
                                    child: FadeTransition(opacity: anim, child: child),
                                  );
                                },
                                child: CachedNetworkImage(
                                  key: ValueKey(slideKey),
                                  imageUrl: card.imageUrl!,
                                  fit: BoxFit.contain,
                                  placeholder: (_, _) => const Center(
                                    child: CircularProgressIndicator(
                                      color: AppColors.gold,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  errorWidget: (_, _, _) => const Icon(
                                    Icons.style,
                                    size: 48,
                                    color: AppColors.textHint,
                                  ),
                                ),
                              ),
                            )
                          else
                            const Center(
                              child: Icon(Icons.style, size: 48, color: AppColors.textHint),
                            ),
                          // Freccia sinistra
                          if (hasPrev)
                            Positioned(
                              left: 4, top: 0, bottom: 24,
                              child: Center(
                                child: GestureDetector(
                                  onTap: onPrev,
                                  child: Container(
                                    width: 28, height: 28,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.45),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.chevron_left_rounded,
                                        color: Colors.white, size: 20),
                                  ),
                                ),
                              ),
                            ),
                          // Freccia destra
                          if (hasNext)
                            Positioned(
                              right: 4, top: 0, bottom: 24,
                              child: Center(
                                child: GestureDetector(
                                  onTap: onNext,
                                  child: Container(
                                    width: 28, height: 28,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.45),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.chevron_right_rounded,
                                        color: Colors.white, size: 20),
                                  ),
                                ),
                              ),
                            ),
                          // Counter "3 / 12"
                          if (showCounter)
                            Positioned(
                              bottom: 6, left: 0, right: 0,
                              child: Center(
                                child: Text(
                                  '${cardIndex + 1} / $cardCount',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.55),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Separatore verticale
                Container(width: 1, color: AppColors.border),

                // ── Info ─────────────────────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Nome
                        Text(
                          card.name,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            height: 1.25,
                          ),
                        ),
                        // Seriale
                        if (card.serialNumber.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            card.serialNumber,
                            style: const TextStyle(
                              color: AppColors.textHint,
                              fontSize: 11,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        const Divider(color: AppColors.divider, height: 1),
                        const SizedBox(height: 8),
                        // Rarità + collezione + quantità sulla stessa riga
                        Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: [
                            if (card.rarity.isNotEmpty)
                              _RarityBadge(rarity: card.rarity),
                            _Chip(
                              label: _collectionLabel(card.collection),
                              color: _collectionAccent(card.collection),
                            ),
                            _Chip(
                              label: '×${card.quantity}',
                              color: card.quantity > 1
                                  ? AppColors.gold
                                  : AppColors.textHint,
                              icon: Icons.inventory_2_outlined,
                            ),
                          ],
                        ),
                        // Tipo
                        if (card.type.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.category_outlined,
                                  size: 12, color: AppColors.textHint),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  card.type,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        // Stats specifici per gioco
                        if (extraInfo != null) ...[
                          const SizedBox(height: 8),
                          const Divider(color: AppColors.divider, height: 1),
                          const SizedBox(height: 8),
                          _GameStats(
                              collection: card.collection,
                              info: extraInfo!),
                        ],
                        const SizedBox(height: 10),
                        _CardtraderLinkButton(card: card),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),

        ],
    );
  }

  static String _collectionLabel(String c) => switch (c) {
    'yugioh'   => 'Yu-Gi-Oh!',
    'pokemon'  => 'Pokémon',
    'onepiece' => 'One Piece',
    _          => c,
  };
}

// ─── Rarity badge ─────────────────────────────────────────────────────────────

class _RarityBadge extends StatelessWidget {
  final String rarity;
  const _RarityBadge({required this.rarity});

  @override
  Widget build(BuildContext context) {
    final color = _rarityColor(rarity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 10, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              rarity,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mini chip ────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const _Chip({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Game-specific stats (ATK/DEF, HP, Power…) ───────────────────────────────

class _GameStats extends StatelessWidget {
  final String collection;
  final Map<String, dynamic> info;
  const _GameStats({required this.collection, required this.info});

  @override
  Widget build(BuildContext context) {
    return switch (collection) {
      'yugioh'   => _YgoStats(info: info),
      'pokemon'  => _PkmStats(info: info),
      'onepiece' => _OpStats(info: info),
      _          => const SizedBox.shrink(),
    };
  }
}

// Yu-Gi-Oh stats: ATK / DEF or LINK, Level/Rank, Attribute, Race
class _YgoStats extends StatelessWidget {
  final Map<String, dynamic> info;
  const _YgoStats({required this.info});

  @override
  Widget build(BuildContext context) {
    final atk      = info['atk'];
    final def      = info['def'];
    final level    = info['level'] as int?;
    final linkval  = info['linkval'] as int?;
    final attribute = (info['attribute'] as String?)?.toUpperCase();
    final race     = info['race'] as String?;

    final isLink   = linkval != null && linkval > 0 && (def == null);
    final stars    = level ?? linkval;

    final items = <Widget>[];

    // ATK / DEF row
    if (atk != null || def != null) {
      items.add(Row(
        children: [
          if (atk != null) _StatPill(label: 'ATK', value: '$atk',
              color: const Color(0xFFEF5350)),
          if (atk != null && def != null) const SizedBox(width: 6),
          if (def != null && !isLink) _StatPill(label: 'DEF', value: '$def',
              color: const Color(0xFF42A5F5)),
          if (isLink) _StatPill(label: 'LINK', value: '$linkval',
              color: const Color(0xFF7E57C2)),
        ],
      ));
    }

    // Level / Rank
    if (stars != null && stars > 0) {
      items.add(const SizedBox(height: 5));
      items.add(Row(
        children: [
          Icon(
            isLink ? Icons.link_rounded : Icons.star_rounded,
            size: 12, color: AppColors.gold,
          ),
          const SizedBox(width: 4),
          Text(
            isLink ? 'Link $stars' : '×$stars',
            style: const TextStyle(
              color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          if (attribute != null && attribute.isNotEmpty) ...[
            const SizedBox(width: 10),
            const Icon(Icons.brightness_7_rounded,
                size: 12, color: AppColors.textHint),
            const SizedBox(width: 3),
            Text(attribute,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ],
          if (race != null && race.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text('/ $race',
                style: const TextStyle(
                    color: AppColors.textHint, fontSize: 11),
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ));
    } else if (attribute != null && attribute.isNotEmpty) {
      items.add(const SizedBox(height: 5));
      items.add(Text(attribute,
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 12)));
    }

    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: items);
  }
}

// Pokémon stats: HP, Types, Subtype
class _PkmStats extends StatelessWidget {
  final Map<String, dynamic> info;
  const _PkmStats({required this.info});

  @override
  Widget build(BuildContext context) {
    final hp      = info['hp'] as int?;
    final types   = info['types'] as String?;
    final subtype = info['subtype'] as String?;

    final items = <Widget>[];

    if (hp != null && hp > 0) {
      items.add(_StatPill(
          label: 'HP', value: '$hp', color: const Color(0xFF66BB6A)));
    }
    if (types != null && types.isNotEmpty) {
      // types is stored as comma-separated e.g. "Fire,Water"
      for (final t in types.split(',')) {
        final name = t.trim();
        if (name.isEmpty) continue;
        items.add(_StatPill(label: name, value: '', color: _pkmnTypeColor(name)));
      }
    }
    if (subtype != null && subtype.isNotEmpty) {
      items.add(const SizedBox(height: 5));
      items.add(Text(subtype,
          style: const TextStyle(
              color: AppColors.textHint, fontSize: 11)));
    }

    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 5, children: items);
  }

  static Color _pkmnTypeColor(String type) => switch (type.toLowerCase()) {
    'fire'      => const Color(0xFFEF5350),
    'water'     => const Color(0xFF42A5F5),
    'grass'     => const Color(0xFF66BB6A),
    'lightning' => const Color(0xFFFFEE58),
    'psychic'   => const Color(0xFFEC407A),
    'fighting'  => const Color(0xFFBF360C),
    'darkness'  => const Color(0xFF616161),
    'metal'     => const Color(0xFF90A4AE),
    'dragon'    => const Color(0xFF7E57C2),
    'fairy'     => const Color(0xFFF48FB1),
    _           => AppColors.textHint,
  };
}

// One Piece stats: Power, Cost, Color, Counter
class _OpStats extends StatelessWidget {
  final Map<String, dynamic> info;
  const _OpStats({required this.info});

  @override
  Widget build(BuildContext context) {
    final power   = info['power'] as int?;
    final cost    = info['cost'] as int?;
    final color   = info['color'] as String?;
    final counter = info['counter_amount'] as int?;

    final items = <Widget>[];
    if (power != null) {
      items.add(_StatPill(label: 'PWR', value: '$power',
          color: const Color(0xFFEF5350)));
    }
    if (cost != null) {
      items.add(_StatPill(label: 'COST', value: '$cost',
          color: const Color(0xFFFFB300)));
    }
    if (counter != null && counter > 0) {
      items.add(_StatPill(label: 'CTR', value: '+$counter',
          color: const Color(0xFF42A5F5)));
    }

    if (color != null && color.isNotEmpty) {
      items.add(const SizedBox(width: 2));
      items.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, size: 10, color: AppColors.textHint),
          const SizedBox(width: 4),
          Text(color,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ],
      ));
    }

    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 5, children: items);
  }
}

// Compact label+value pill used in game stats
class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatPill({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  color: color.withValues(alpha: 0.75),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5)),
          if (value.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
          ],
        ],
      ),
    );
  }
}

// ─── Album panel ──────────────────────────────────────────────────────────────

class _AlbumPanel extends StatelessWidget {
  final List<AlbumModel> availableAlbums;
  final int? selectedId;
  final String currentName;
  final ValueChanged<int?> onChanged;

  const _AlbumPanel({
    required this.availableAlbums,
    required this.selectedId,
    required this.currentName,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'ALBUM',
      child: availableAlbums.isNotEmpty
          ? DropdownButtonFormField<int>(
              initialValue: selectedId,
              dropdownColor: AppColors.bgLight,
              style: const TextStyle(color: AppColors.textPrimary),
              icon: const Icon(Icons.expand_more_rounded, color: AppColors.textHint),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
              items: availableAlbums.map((album) {
                return DropdownMenuItem<int>(
                  value: album.id,
                  child: Text(
                    album.maxCapacity > 0
                        ? '${album.name}  (${album.currentCount}/${album.maxCapacity})'
                        : album.name,
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            )
          : Row(
              children: [
                const Icon(Icons.photo_album_outlined,
                    size: 18, color: AppColors.textHint),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    currentName,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ─── Prices panel ─────────────────────────────────────────────────────────────

class _PricesPanel extends StatelessWidget {
  final CardModel card;
  const _PricesPanel({required this.card});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'VALORE DI MERCATO',
      child: CardtraderAllPricesSection(
        collection: card.collection,
        serialNumber: card.serialNumber,
        cardName: card.name,
        rarity: card.rarity.isNotEmpty ? card.rarity : null,
        highlightLanguage: _langFromSerial(card.serialNumber, card.collection),
        catalogId: card.catalogId,
      ),
    );
  }
}

// ─── Decks panel ──────────────────────────────────────────────────────────────

class _DecksPanel extends StatelessWidget {
  final List<Map<String, dynamic>> decks;
  const _DecksPanel({required this.decks});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'DECK',
      child: Column(
        children: decks.map((d) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.style, size: 18, color: AppColors.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    d['name'] as String? ?? '',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.bgMedium,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    '×${d['quantity']}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Description panel ────────────────────────────────────────────────────────

class _DescriptionPanel extends StatelessWidget {
  final String description;
  const _DescriptionPanel({required this.description});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'DESCRIZIONE',
      child: Text(
        description,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          height: 1.6,
        ),
      ),
    );
  }
}

// ─── CardTrader link button ───────────────────────────────────────────────────

class _CardtraderLinkButton extends StatefulWidget {
  final CardModel card;
  const _CardtraderLinkButton({required this.card});

  @override
  State<_CardtraderLinkButton> createState() => _CardtraderLinkButtonState();
}

class _CardtraderLinkButtonState extends State<_CardtraderLinkButton> {
  Uri? _url;

  @override
  void initState() {
    super.initState();
    final slug = _ctSlug(widget.card.collection);
    if (slug != null) {
      _url = Uri.parse(
        'https://www.cardtrader.com/en/$slug/singles'
        '?q=${Uri.encodeQueryComponent(widget.card.name)}',
      );
    }
    _loadBlueprintUrl();
  }

  Future<void> _loadBlueprintUrl() async {
    final sn = widget.card.serialNumber;
    final exp = sn.isEmpty ? '' : sn.split('-').first.toLowerCase();
    final prices = await CardtraderService().getAllPricesForCard(
      catalog: widget.card.collection,
      expansionCode: exp,
      cardName: widget.card.name,
      catalogId: widget.card.catalogId,
    );
    if (!mounted || prices.isEmpty) return;
    final best = prices.firstWhere((p) => p.blueprintId > 0, orElse: () => prices.first);
    if (best.blueprintId > 0) setState(() => _url = Uri.parse(best.cardtraderUrl));
  }

  static String? _ctSlug(String c) => switch (c) {
    'yugioh'   => 'yu-gi-oh',
    'pokemon'  => 'pokemon',
    'onepiece' => 'one-piece',
    _          => null,
  };

  @override
  Widget build(BuildContext context) {
    if (_url == null) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => launchUrl(_url!, mode: LaunchMode.externalApplication),
        icon: const Icon(Icons.open_in_new, size: 13),
        label: const Text('Vedi su CardTrader'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.teal,
          side: const BorderSide(color: Colors.teal),
          padding: const EdgeInsets.symmetric(vertical: 7),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ─── Generic section panel ────────────────────────────────────────────────────

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;

  const _Panel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 13,
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
