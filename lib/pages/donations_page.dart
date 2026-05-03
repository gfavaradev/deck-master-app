import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/subscription_model.dart';
import '../models/user_model.dart';
import '../services/subscription_service.dart';
import '../theme/app_colors.dart';
import '../widgets/donation_badge.dart';

class DonationsPage extends StatefulWidget {
  const DonationsPage({super.key});

  @override
  State<DonationsPage> createState() => _DonationsPageState();
}

class _DonationsPageState extends State<DonationsPage> {
  final SubscriptionService _service = SubscriptionService();
  UserModel? _user;
  bool _loading = true;
  List<Map<String, String>> _wallOfFame = [];

  static const String _kofiUrl = 'https://ko-fi.com/deckmaster';

  static const List<_DonationAmount> _amounts = [
    _DonationAmount(1.99, 'Una carta comune', '☆'),
    _DonationAmount(4.99, 'Un booster pack', '◆'),
    _DonationAmount(9.99, 'Un box di buste', '★'),
    _DonationAmount(19.99, 'Una collezione completa', '✦'),
    _DonationAmount(29.99, 'Diventa leggenda', '✦✦'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _service.getCurrentUserModel()
            .timeout(const Duration(seconds: 8), onTimeout: () => null),
        _service.getWallOfFame()
            .timeout(const Duration(seconds: 8), onTimeout: () => <Map<String, String>>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _user = results[0] as UserModel?;
        _wallOfFame = results[1] as List<Map<String, String>>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openDonation(double amount) async {
    final uri = Uri.parse(_kofiUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) { // ignore: empty_catches
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile aprire il link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text('Supporta il Progetto'),
        backgroundColor: AppColors.bgMedium,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.gold.withValues(alpha: 0.2)),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.gold,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                children: [
                  _buildCurrentTier(),
                  const SizedBox(height: 24),
                  _buildProgress(),
                  const SizedBox(height: 28),
                  _buildAmounts(),
                  const SizedBox(height: 28),
                  _buildTierList(),
                  if (_wallOfFame.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _buildWallOfFame(),
                  ],
                  const SizedBox(height: 16),
                  _buildDisclaimer(),
                ],
              ),
            ),
      ),
    );
  }

  // ── Tier attuale ──────────────────────────────────────────────────────────

  Widget _buildCurrentTier() {
    final tier = _user?.donationTier ?? DonationTier.none;
    final total = _user?.totalDonated ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: tier == DonationTier.none
              ? AppColors.gold.withValues(alpha: 0.2)
              : tier.color.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          if (tier == DonationTier.none) ...[
            const Icon(Icons.favorite_border, color: AppColors.gold, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Nessuna donazione ancora',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Ogni contributo, piccolo o grande, fa la differenza.\nGrazie di cuore!',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
            ),
          ] else ...[
            DonationAvatarBorder(
              tier: tier,
              radius: 40,
              child: CircleAvatar(
                radius: 40,
                backgroundColor: tier.color.withValues(alpha: 0.15),
                child: Text(
                  tier.symbol,
                  style: const TextStyle(fontSize: 32),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              tier.badgeTitle,
              style: TextStyle(
                color: tier.color,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${tier.symbol} ${tier.label}',
              style: TextStyle(color: tier.color.withValues(alpha: 0.7), fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'Totale donato: €${total.toStringAsFixed(2)}',
              style: const TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  // ── Barra progresso al prossimo tier ─────────────────────────────────────

  Widget _buildProgress() {
    final tier = _user?.donationTier ?? DonationTier.none;
    final total = _user?.totalDonated ?? 0.0;
    final next = tier.nextTier;

    if (next == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bgMedium,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.emoji_events, color: AppColors.gold),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Hai raggiunto il tier massimo!\nSei un vero leggendario. Grazie!',
                style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    final current = tier.requiredTotal;
    final target = next.requiredTotal;
    final progress = target > 0 ? ((total - current) / (target - current)).clamp(0.0, 1.0) : 0.0;
    final remaining = (target - total).clamp(0.0, double.infinity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Prossimo tier: ${next.symbol} ${next.label}',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            Text(
              '€${remaining.toStringAsFixed(2)} mancanti',
              style: const TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 10,
            backgroundColor: AppColors.bgLight,
            valueColor: AlwaysStoppedAnimation(next.color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Sblocchi: ${next.badgeTitle}${next.hasBorder ? " + bordo profilo" : ""}',
          style: TextStyle(color: next.color, fontSize: 11),
        ),
      ],
    );
  }

  // ── Importi donazione ─────────────────────────────────────────────────────

  Widget _buildAmounts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('DONA ORA'),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 2.0,
          children: _amounts.map((a) => _AmountCard(
            amount: a,
            onTap: () => _openDonation(a.value),
          )).toList(),
        ),
        const SizedBox(height: 8),
        const Text(
          'Le donazioni vengono registrate manualmente.\nDopo aver donato, invia una mail allo sviluppatore per aggiornare il tuo tier.',
          style: TextStyle(color: AppColors.textHint, fontSize: 11, height: 1.4),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ── Elenco tier ───────────────────────────────────────────────────────────

  Widget _buildTierList() {
    final current = _user?.donationTier ?? DonationTier.none;
    final tiers = DonationTier.values.where((t) => t != DonationTier.none).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('LIVELLI'),
        const SizedBox(height: 12),
        ...tiers.map((tier) => _TierRow(tier: tier, current: current)),
      ],
    );
  }

  // ── Wall of Fame ──────────────────────────────────────────────────────────

  Widget _buildWallOfFame() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('WALL OF FAME'),
        const SizedBox(height: 4),
        const Text(
          'I leggendari Fondatori che hanno contribuito di più',
          style: TextStyle(color: AppColors.textHint, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgMedium,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF9C27B0).withValues(alpha: 0.4)),
          ),
          child: Column(
            children: _wallOfFame.asMap().entries.map((entry) {
              final i = entry.key;
              final donor = entry.value;
              return ListTile(
                leading: Text(
                  ['🥇', '🥈', '🥉'][i.clamp(0, 2)],
                  style: const TextStyle(fontSize: 22),
                ),
                title: Text(
                  donor['nickname'] ?? 'Fondatore Anonimo',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                trailing: const DonationBadge(tier: DonationTier.secretRare, size: 28),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildDisclaimer() {
    return const Text(
      'Le donazioni sono completamente facoltative e non danno diritto a funzioni extra.\n'
      'I badge e il Wall of Fame sono un modo per ringraziarti del tuo supporto. ♥',
      textAlign: TextAlign.center,
      style: TextStyle(color: AppColors.textHint, fontSize: 11, height: 1.5),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

class _DonationAmount {
  final double value;
  final String label;
  final String symbol;
  const _DonationAmount(this.value, this.label, this.symbol);
}

class _AmountCard extends StatelessWidget {
  final _DonationAmount amount;
  final VoidCallback onTap;
  const _AmountCard({required this.amount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgMedium,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Text(amount.symbol, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '€${amount.value.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      amount.label,
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TierRow extends StatelessWidget {
  final DonationTier tier;
  final DonationTier current;
  const _TierRow({required this.tier, required this.current});

  @override
  Widget build(BuildContext context) {
    final unlocked = current.index >= tier.index;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: unlocked
            ? tier.color.withValues(alpha: 0.08)
            : AppColors.bgMedium,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: unlocked
              ? tier.color.withValues(alpha: 0.5)
              : AppColors.bgLight,
        ),
      ),
      child: Row(
        children: [
          DonationBadge(tier: tier, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      tier.badgeTitle,
                      style: TextStyle(
                        color: unlocked ? tier.color : AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tier.label,
                      style: TextStyle(
                        color: unlocked
                            ? tier.color.withValues(alpha: 0.6)
                            : AppColors.textHint,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Text(
                  '≥ €${tier.requiredTotal.toStringAsFixed(2)} cumulativi'
                  '${tier.hasBorder ? " · bordo profilo" : ""}',
                  style: const TextStyle(color: AppColors.textHint, fontSize: 11),
                ),
              ],
            ),
          ),
          if (unlocked)
            Icon(Icons.check_circle, color: tier.color, size: 20)
          else
            const Icon(Icons.lock_outline, color: AppColors.textHint, size: 18),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: AppColors.gold,
        letterSpacing: 1.5,
      ),
    );
  }
}
