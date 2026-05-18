import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/claude_service.dart';
import '../services/data_repository.dart';
import '../services/subscription_service.dart';
import '../theme/app_colors.dart';
import 'pro_page.dart';

// ─── Modelli risposta AI ───────────────────────────────────────────────────────

class _AiCard {
  final String name;
  final int quantity;
  final String reason;
  // Matched from local DB
  int? ownedId;
  int? ownedQuantity;
  String? imageUrl;

  _AiCard({required this.name, required this.quantity, required this.reason});
}

class _AiDeckResult {
  final String deckName;
  final String strategy;
  final List<_AiCard> mainDeck;
  final List<_AiCard> extraDeck;
  final List<_AiCard> sideDeck;

  _AiDeckResult({
    required this.deckName,
    required this.strategy,
    required this.mainDeck,
    required this.extraDeck,
    required this.sideDeck,
  });
}

// ─── Page ─────────────────────────────────────────────────────────────────────

class AiDeckBuilderPage extends StatefulWidget {
  const AiDeckBuilderPage({super.key});

  @override
  State<AiDeckBuilderPage> createState() => _AiDeckBuilderPageState();
}

class _AiDeckBuilderPageState extends State<AiDeckBuilderPage> {
  final _repo = DataRepository();
  final _strategyCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  bool _isPro = false;
  bool _checkingPro = true;
  bool _generating = false;
  bool _savingDeck = false;
  String? _errorMessage;
  _AiDeckResult? _result;
  List<Map<String, dynamic>> _ownedCards = [];

  @override
  void initState() {
    super.initState();
    _checkPro();
  }

  @override
  void dispose() {
    _strategyCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkPro() async {
    final isPro = await SubscriptionService().currentUserHasPro();
    if (!mounted) return;
    setState(() { _isPro = isPro; _checkingPro = false; });
    if (isPro) _loadOwnedCards();
  }

  Future<void> _loadOwnedCards() async {
    final cards = await _repo.getOwnedYugiohCardsForAi();
    if (!mounted) return;
    setState(() => _ownedCards = cards);
  }

  Future<void> _generate() async {
    final strategy = _strategyCtrl.text.trim();
    if (strategy.isEmpty) {
      setState(() => _errorMessage = 'Descrivi la tua strategia per continuare.');
      return;
    }
    if (_ownedCards.isEmpty) {
      setState(() => _errorMessage = 'Nessuna carta Yu-Gi-Oh! nella tua collezione. Aggiungi carte per usare l\'AI Deck Builder.');
      return;
    }
    if (!ClaudeService.isConfigured) {
      setState(() => _errorMessage = 'API key Anthropic non configurata. Imposta anthropicApiKey in app_secrets.dart.');
      return;
    }

    setState(() { _generating = true; _errorMessage = null; _result = null; });

    try {
      final cardList = _buildCardList();
      final userMessage = '''Strategia desiderata: $strategy

Carte disponibili (${_ownedCards.length} in collezione, format: Nome|Tipo|Attributo|Livello|ATK/DEF|Race):
$cardList

Costruisci il deck ottimale per questa strategia usando SOLO le carte elencate.''';

      final rawResponse = await ClaudeService.sendMessage(
        systemPrompt: _systemPrompt(),
        userMessage: userMessage,
        maxTokens: 2048,
      );

      final result = _parseResponse(rawResponse);
      _matchOwnedCards(result);

      if (!mounted) return;
      setState(() { _result = result; _generating = false; });

      // Scroll to results
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
          );
        }
      });
    } on ClaudeApiException catch (e) {
      if (!mounted) return;
      setState(() { _errorMessage = 'Errore API: ${e.message}'; _generating = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _errorMessage = 'Errore: $e'; _generating = false; });
    }
  }

  String _buildCardList() {
    final seen = <String>{};
    final lines = <String>[];
    for (final c in _ownedCards) {
      final name = c['name']?.toString() ?? '';
      if (name.isEmpty || seen.contains(name)) continue;
      seen.add(name);
      final type = c['type']?.toString() ?? '';
      final attr = c['attribute']?.toString() ?? '';
      final lvl = c['level']?.toString() ?? '-';
      final atk = c['atk']?.toString() ?? '-';
      final def = c['def']?.toString() ?? '-';
      final race = c['race']?.toString() ?? '';
      lines.add('$name|$type|$attr|Lv$lvl|$atk/$def|$race');
    }
    // Limit to 200 lines to avoid exceeding context
    return lines.take(200).join('\n');
  }

  static String _systemPrompt() => '''
Sei un esperto costruttore di deck Yu-Gi-Oh!. Costruisci deck ottimali seguendo le regole ufficiali.

Regole TCG Yu-Gi-Oh!:
- Main Deck: 40-60 carte, max 3 copie per carta
- Extra Deck: 0-15 carte (Fusion/Synchro/XYZ/Link)
- Side Deck: 0-15 carte (opzionale)
- Usa SOLO le carte fornite dall'utente

Rispondi SOLO con un oggetto JSON valido (no markdown, no testo extra):
{
  "deck_name": "nome archetipo/strategia",
  "strategy": "spiegazione strategia in 2-3 frasi",
  "main_deck": [{"name": "nome carta", "quantity": 3, "reason": "motivo breve"}],
  "extra_deck": [{"name": "nome carta", "quantity": 1, "reason": "motivo breve"}],
  "side_deck": [{"name": "nome carta", "quantity": 2, "reason": "motivo breve"}]
}
''';

  _AiDeckResult _parseResponse(String raw) {
    // Strip markdown code blocks if present
    var text = raw
        .replaceAll(RegExp(r'```json\s*', caseSensitive: false), '')
        .replaceAll('```', '')
        .trim();

    // Extract first JSON object
    final match = RegExp(r'\{.*\}', dotAll: true).firstMatch(text);
    if (match == null) throw const ClaudeApiException('Nessun JSON trovato nella risposta');

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(match.group(0)!) as Map<String, dynamic>;
    } catch (_) {
      throw const ClaudeApiException('JSON non valido nella risposta');
    }

    List<_AiCard> parseSection(String key) {
      final raw = data[key] as List<dynamic>? ?? [];
      return raw.map((e) {
        final m = e as Map<String, dynamic>;
        return _AiCard(
          name: m['name']?.toString() ?? '',
          quantity: (m['quantity'] as num?)?.toInt() ?? 1,
          reason: m['reason']?.toString() ?? '',
        );
      }).where((c) => c.name.isNotEmpty).toList();
    }

    return _AiDeckResult(
      deckName: data['deck_name']?.toString() ?? 'AI Deck',
      strategy: data['strategy']?.toString() ?? '',
      mainDeck: parseSection('main_deck'),
      extraDeck: parseSection('extra_deck'),
      sideDeck: parseSection('side_deck'),
    );
  }

  void _matchOwnedCards(_AiDeckResult result) {
    final byName = <String, Map<String, dynamic>>{};
    for (final c in _ownedCards) {
      final name = (c['name']?.toString() ?? '').toLowerCase();
      byName.putIfAbsent(name, () => c);
    }

    void match(_AiCard card) {
      final owned = byName[card.name.toLowerCase()];
      if (owned != null) {
        card.ownedId = owned['owned_id'] as int?;
        card.ownedQuantity = owned['quantity'] as int?;
        card.imageUrl = owned['imageUrl'] as String?;
      }
    }

    for (final c in result.mainDeck) { match(c); }
    for (final c in result.extraDeck) { match(c); }
    for (final c in result.sideDeck) { match(c); }
  }

  Future<void> _saveDeck(_AiDeckResult result) async {
    setState(() => _savingDeck = true);
    try {
      final deckId = await _repo.insertDeck(result.deckName, 'yugioh');
      final ownedInMain = result.mainDeck.where((c) => c.ownedId != null);
      for (final card in ownedInMain) {
        await _repo.addCardToDeck(deckId, card.ownedId!, card.quantity);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deck "${result.deckName}" salvato! (${ownedInMain.length} carte aggiunte)'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore nel salvare: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _savingDeck = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text('AI Deck Builder'),
        backgroundColor: AppColors.bgMedium,
        foregroundColor: AppColors.textPrimary,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.star, color: AppColors.gold, size: 14),
                SizedBox(width: 4),
                Text('Pro', style: TextStyle(color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
      body: _checkingPro
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : !_isPro
              ? _buildProGate()
              : _buildContent(),
    );
  }

  Widget _buildProGate() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 64, color: AppColors.gold),
            const SizedBox(height: 16),
            const Text('AI Deck Builder', style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Costruisci deck ottimali con l\'intelligenza artificiale basata su Claude.\nDisponibile solo per utenti Pro.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProPage())),
              style: FilledButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: Colors.black),
              icon: const Icon(Icons.star),
              label: const Text('Passa a Pro'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          _buildStrategyInput(),
          const SizedBox(height: 16),
          _buildGenerateButton(),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            _buildError(),
          ],
          if (_result != null) ...[
            const SizedBox(height: 24),
            _buildResult(_result!),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: AppColors.gold, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AI Deck Builder — Yu-Gi-Oh!',
                    style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 13)),
                Text(
                  '${_ownedCards.length} carte disponibili nella tua collezione',
                  style: const TextStyle(color: AppColors.textHint, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStrategyInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        const Text('Descrivi la tua strategia',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: _strategyCtrl,
          maxLines: 4,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Es: "Un deck aggressivo Dragon con attacchi rapidi e fusioni potenti. Voglio usare i miei Blue-Eyes e un misto di carte di supporto."',
            hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 12),
            filled: true,
            fillColor: AppColors.bgMedium,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.gold),
            ),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'L\'AI costruirà un deck usando solo le carte nella tua collezione.',
          style: TextStyle(color: AppColors.textHint, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildGenerateButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _generating ? null : _generate,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: _generating
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
            : const Icon(Icons.auto_awesome, size: 20),
        label: Text(_generating ? 'Analisi in corso…' : 'Genera Deck con AI', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(_errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildResult(_AiDeckResult result) {
    final mainTotal = result.mainDeck.fold(0, (s, c) => s + c.quantity);
    final extraTotal = result.extraDeck.fold(0, (s, c) => s + c.quantity);
    final ownedCount = result.mainDeck.where((c) => c.ownedId != null).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Deck name + strategy
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.bgMedium,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: AppColors.gold, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(result.deckName,
                        style: const TextStyle(color: AppColors.gold, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(result.strategy, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _StatChip(label: 'Main', value: '$mainTotal', color: AppColors.blue),
                  const SizedBox(width: 8),
                  if (extraTotal > 0) _StatChip(label: 'Extra', value: '$extraTotal', color: AppColors.purple),
                  const Spacer(),
                  _StatChip(label: 'Possedute', value: '$ownedCount/${result.mainDeck.length}', color: AppColors.success),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Save button
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _savingDeck ? null : () => _saveDeck(result),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: _savingDeck
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined, size: 18),
            label: const Text('Salva Deck', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 16),
        // Main deck
        if (result.mainDeck.isNotEmpty) ...[
          _buildSectionHeader('Main Deck', mainTotal, AppColors.blue),
          const SizedBox(height: 6),
          ...result.mainDeck.map((c) => _buildCardTile(c)),
        ],
        // Extra deck
        if (result.extraDeck.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildSectionHeader('Extra Deck', extraTotal, AppColors.purple),
          const SizedBox(height: 6),
          ...result.extraDeck.map((c) => _buildCardTile(c)),
        ],
        // Side deck
        if (result.sideDeck.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildSectionHeader('Side Deck', result.sideDeck.fold(0, (s, c) => s + c.quantity), AppColors.warning),
          const SizedBox(height: 6),
          ...result.sideDeck.map((c) => _buildCardTile(c)),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String label, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        Text('($count carte)', style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
      ],
    );
  }

  Widget _buildCardTile(_AiCard card) {
    final isOwned = card.ownedId != null;
    final hasEnough = isOwned && (card.ownedQuantity ?? 0) >= card.quantity;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isOwned
              ? (hasEnough ? AppColors.success.withValues(alpha: 0.3) : AppColors.warning.withValues(alpha: 0.3))
              : AppColors.error.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          // Owned indicator
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isOwned
                  ? (hasEnough ? AppColors.success : AppColors.warning).withValues(alpha: 0.15)
                  : AppColors.error.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isOwned ? (hasEnough ? Icons.check : Icons.warning_outlined) : Icons.close,
              size: 14,
              color: isOwned ? (hasEnough ? AppColors.success : AppColors.warning) : AppColors.error,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.name,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(card.reason, style: const TextStyle(color: AppColors.textHint, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Quantity
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('×${card.quantity}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
              if (isOwned && !hasEnough)
                Text('hai ${card.ownedQuantity}', style: const TextStyle(color: AppColors.warning, fontSize: 10)),
              if (!isOwned)
                const Text('non posseduta', style: TextStyle(color: AppColors.error, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Helper widget ────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 10)),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
