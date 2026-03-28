import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../services/subscription_service.dart';
import '../services/revenue_cat_service.dart';
import '../theme/app_colors.dart';

class ProPage extends StatefulWidget {
  const ProPage({super.key});

  @override
  State<ProPage> createState() => _ProPageState();
}

class _ProPageState extends State<ProPage> with SingleTickerProviderStateMixin {
  final bool _annual = true;
  bool _isPurchasing = false;
  Offerings? _offerings;
  late AnimationController _shimmerController;

  static const double _monthlyPrice = 2.99;
  static const double _annualPrice = 24.99;
  static const double _annualMonthly = _annualPrice / 12;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    final offerings = await RevenueCatService().getOfferings();
    if (mounted) setState(() => _offerings = offerings);
  }

  Future<void> _onPurchaseTap() async {
    final offerings = _offerings;
    Package? package;

    if (offerings != null) {
      final current = offerings.current;
      if (current != null) {
        final packages = current.availablePackages;
        if (_annual) {
          package = packages.firstWhere(
            (p) => p.storeProduct.identifier == kProductAnnual,
            orElse: () => packages.first,
          );
        } else {
          package = packages.firstWhere(
            (p) => p.storeProduct.identifier == kProductMonthly,
            orElse: () => packages.first,
          );
        }
      }
    }

    if (package == null) {
      // Prodotti non ancora configurati in RevenueCat
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Abbonamento non disponibile al momento.')),
      );
      return;
    }

    setState(() => _isPurchasing = true);
    final success = await RevenueCatService().purchasePackage(package);
    if (!mounted) return;
    setState(() => _isPurchasing = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Benvenuto nel piano Pro!'),
          backgroundColor: AppColors.gold,
        ),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _onRestoreTap() async {
    setState(() => _isPurchasing = true);
    final restored = await RevenueCatService().restorePurchases();
    if (!mounted) return;
    setState(() => _isPurchasing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(restored ? 'Acquisti ripristinati!' : 'Nessun acquisto da ripristinare.'),
      ),
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 32),
            _buildFeatures(),
            const SizedBox(height: 32),
            _buildPricingToggle(),
            const SizedBox(height: 16),
            _buildPricingCards(),
            const SizedBox(height: 24),
            _buildCTA(),
            const SizedBox(height: 16),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _shimmerController,
          builder: (_, _) {
            return ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: const [
                  Color(0xFFD4AF37),
                  Color(0xFFF5E27A),
                  Color(0xFFD4AF37),
                ],
                stops: const [0.0, 0.5, 1.0],
                transform: GradientRotation(_shimmerController.value * 6.28),
              ).createShader(bounds),
              child: const Icon(
                Icons.workspace_premium,
                size: 72,
                color: Colors.white,
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        const Text(
          'DECK MASTER PRO',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: AppColors.gold,
            letterSpacing: 2.0,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Porta la tua collezione al livello successivo',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
          ),
          child: const Text(
            '🚀  PROSSIMAMENTE',
            style: TextStyle(
              color: AppColors.gold,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatures() {
    final features = [
      _Feature(Icons.style, 'Deck Builder', 'Crea e condividi i tuoi mazzi da gioco', true),
      _Feature(Icons.analytics_outlined, 'Statistiche Avanzate', 'Analisi dettagliata del valore e delle rarità', true),
      _Feature(Icons.compare_arrows, 'Confronto Collezioni', 'Confronta la tua collezione con altri utenti', true),
      _Feature(Icons.cloud_sync, 'Backup Prioritario', 'Sincronizzazione cloud sempre aggiornata', true),
      _Feature(Icons.new_releases_outlined, 'Accesso Anticipato', 'Prime nuove funzioni in anteprima', true),
      _Feature(Icons.support_agent, 'Supporto Prioritario', 'Risposte garantite entro 24 ore', true),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TUTTO INCLUSO',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.gold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          ...features.map((f) => _FeatureTile(feature: f)),
        ],
      ),
    );
  }

  Widget _buildPricingToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          _ToggleOption(
            label: 'Mensile',
            selected: !_annual,
            onTap: null,
          ),
          _ToggleOption(
            label: 'Annuale',
            selected: _annual,
            onTap: null,
            badge: '-30%',
          ),
        ],
      ),
    );
  }

  Widget _buildPricingCards() {
    if (_annual) {
      return _PricingCard(
        title: 'Piano Annuale',
        price: _annualPrice,
        period: 'anno',
        subText: '€${_annualMonthly.toStringAsFixed(2)}/mese — risparmia il 30%',
        highlight: true,
      );
    }
    return _PricingCard(
      title: 'Piano Mensile',
      price: _monthlyPrice,
      period: 'mese',
      subText: 'Rinnovo automatico mensile',
      highlight: false,
    );
  }

  Widget _buildCTA() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            onPressed: _isPurchasing ? null : _onPurchaseTap,
            icon: _isPurchasing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Icon(Icons.star, size: 20),
            label: Text(
              _isPurchasing ? 'Elaborazione...' : 'Abbonati ora',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        FutureBuilder<bool>(
          future: SubscriptionService().currentUserHasPro(),
          builder: (context, snap) {
            if (snap.data == true) {
              return const Text(
                '✓ Sei già abbonato a Pro!',
                style: TextStyle(color: AppColors.gold, fontSize: 13),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        const Text(
          'Annulla in qualsiasi momento · Nessun vincolo',
          style: TextStyle(color: AppColors.textHint, fontSize: 12),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        const Text(
          'Il pagamento verrà addebitato tramite App Store / Google Play',
          style: TextStyle(color: AppColors.textHint, fontSize: 11),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _isPurchasing ? null : _onRestoreTap,
          child: const Text(
            'Ripristina acquisti',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

class _Feature {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool included;
  const _Feature(this.icon, this.title, this.subtitle, this.included);
}

class _FeatureTile extends StatelessWidget {
  final _Feature feature;
  const _FeatureTile({required this.feature});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(feature.icon, color: AppColors.gold, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  feature.subtitle,
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            feature.included ? Icons.check_circle : Icons.cancel,
            color: feature.included ? AppColors.gold : Colors.red.shade400,
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _PricingCard extends StatelessWidget {
  final String title;
  final double price;
  final String period;
  final String subText;
  final bool highlight;

  const _PricingCard({
    required this.title,
    required this.price,
    required this.period,
    required this.subText,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.gold.withValues(alpha: 0.1)
            : AppColors.bgMedium,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight ? AppColors.gold : AppColors.bgLight,
          width: highlight ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subText,
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '€${price.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: highlight ? AppColors.gold : AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(
                  text: '/$period',
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final String? badge;

  const _ToggleOption({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap ?? () {},
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.gold : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.black : AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected ? Colors.black26 : AppColors.gold,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.black : Colors.black,
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
}
