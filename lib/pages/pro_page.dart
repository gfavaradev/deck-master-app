import '../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../services/subscription_service.dart';
import '../services/revenue_cat_service.dart';
import '../theme/app_colors.dart';

enum _Plan { monthly, semiannual, annual }

class ProPage extends StatefulWidget {
  const ProPage({super.key});

  @override
  State<ProPage> createState() => _ProPageState();
}

class _ProPageState extends State<ProPage> with SingleTickerProviderStateMixin {
  _Plan _selectedPlan = _Plan.annual;
  bool _isPurchasing = false;
  Offerings? _offerings;
  late AnimationController _shimmerController;
  late final Future<bool> _proStatusFuture;

  // ─── Prezzi ───────────────────────────────────────────────────────────────
  static const double _monthly        = 2.99;
  static const double _semiannual     = 12.99;  // €2.17/mese  −27%
  static const double _annual         = 19.99;  // €1.67/mese  −44%
  static const double _annualOriginal = 35.88;  // 2.99 × 12

  @override
  void initState() {
    super.initState();
    _proStatusFuture = SubscriptionService().currentUserHasPro();
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
        if (packages.isNotEmpty) {
          final id = switch (_selectedPlan) {
            _Plan.monthly    => kProductMonthly,
            _Plan.semiannual => kProductSemiannual,
            _Plan.annual     => kProductAnnual,
          };
          package = packages.firstWhere(
            (p) => p.storeProduct.identifier == id,
            orElse: () => packages.first,
          );
        }
      }
    }

    if (package == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.proNotAvailable)),
      );
      return;
    }

    setState(() => _isPurchasing = true);
    final success = await RevenueCatService().purchasePackage(package);
    if (!mounted) return;
    setState(() => _isPurchasing = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.proWelcomeMsg),
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
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(restored ? l10n.proPurchasesRestored : l10n.proNoPurchasesToRestore),
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
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 28),
              _buildFeatures(),
              const SizedBox(height: 28),
              _buildPricingSection(),
              const SizedBox(height: 24),
              _buildCTA(),
              const SizedBox(height: 16),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        AnimatedBuilder(
          animation: _shimmerController,
          builder: (_, _) => ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: const [Color(0xFFD4AF37), Color(0xFFF5E27A), Color(0xFFD4AF37)],
              stops: const [0.0, 0.5, 1.0],
              transform: GradientRotation(_shimmerController.value * 6.28),
            ).createShader(bounds),
            child: const Icon(Icons.workspace_premium, size: 72, color: Colors.white),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'DECK MASTER PRO',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.gold, letterSpacing: 2.0),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.proHeaderSubtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
        ),
        const SizedBox(height: 12),
        // Sconto lancio badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF6B35), Color(0xFFFF3D00)],
            ),
            borderRadius: BorderRadius.circular(50),
            boxShadow: [
              BoxShadow(color: const Color(0xFFFF6B35).withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_fire_department, color: Colors.white, size: 15),
              const SizedBox(width: 5),
              Text(
                l10n.proLaunchBadge,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.8),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Features ─────────────────────────────────────────────────────────────

  Widget _buildFeatures() {
    final l10n = AppLocalizations.of(context)!;
    final features = [
      _Feature(Icons.table_chart_outlined,         l10n.proFeatExcelTitle,   l10n.proFeatExcelSub),
      _Feature(Icons.analytics_outlined,           l10n.proFeatStatsTitle,   l10n.proFeatStatsSub),
      _Feature(Icons.trending_up,                  l10n.proFeatRoiTitle,     l10n.proFeatRoiSub),
      _Feature(Icons.share_outlined,               l10n.proFeatShareTitle,   l10n.proFeatShareSub),
      _Feature(Icons.auto_awesome,                 l10n.proFeatAiTitle,      l10n.proFeatAiSub),
      _Feature(Icons.notifications_active_outlined,l10n.proFeatAlertsTitle,  l10n.proFeatAlertsSub),
      _Feature(Icons.block,                        l10n.proFeatNoAdsTitle,   l10n.proFeatNoAdsSub),
      _Feature(Icons.support_agent,                l10n.proFeatSupportTitle, l10n.proFeatSupportSub),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.proAllIncluded,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.gold, letterSpacing: 1.5),
          ),
          const SizedBox(height: 16),
          ...features.map((f) => _FeatureTile(feature: f)),
        ],
      ),
    );
  }

  // ─── Pricing ──────────────────────────────────────────────────────────────

  Widget _buildPricingSection() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 12),
          child: Text(
            l10n.proChoosePlan,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textHint, letterSpacing: 1.2),
          ),
        ),
        _PlanCard(
          plan: _Plan.monthly,
          selected: _selectedPlan == _Plan.monthly,
          title: l10n.proMonthlyLabel,
          price: _monthly,
          period: l10n.proMonthPeriod,
          note: l10n.proMonthlyNote,
          onTap: () => setState(() => _selectedPlan = _Plan.monthly),
        ),
        const SizedBox(height: 10),
        _PlanCard(
          plan: _Plan.semiannual,
          selected: _selectedPlan == _Plan.semiannual,
          title: l10n.proSemiannualLabel,
          price: _semiannual,
          period: l10n.proSemiannualPeriod,
          note: l10n.proSaveNote((_semiannual / 6).toStringAsFixed(2), '27'),
          badge: '−27%',
          onTap: () => setState(() => _selectedPlan = _Plan.semiannual),
        ),
        const SizedBox(height: 10),
        _PlanCard(
          plan: _Plan.annual,
          selected: _selectedPlan == _Plan.annual,
          title: l10n.proYearlyLabel,
          price: _annual,
          period: l10n.proYearPeriod,
          originalPrice: _annualOriginal,
          note: l10n.proSaveNote((_annual / 12).toStringAsFixed(2), '44'),
          badge: '−44%',
          isLaunchDeal: true,
          onTap: () => setState(() => _selectedPlan = _Plan.annual),
        ),
      ],
    );
  }

  // ─── CTA ──────────────────────────────────────────────────────────────────

  Widget _buildCTA() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            onPressed: _isPurchasing ? null : _onPurchaseTap,
            icon: _isPurchasing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Icon(Icons.star, size: 20),
            label: Text(
              _isPurchasing ? l10n.proProcessing : l10n.proSubscribeNow,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
          future: _proStatusFuture,
          builder: (context, snap) {
            if (snap.data == true) {
              return Text(l10n.proAlreadySubscribed, style: const TextStyle(color: AppColors.gold, fontSize: 13));
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }

  // ─── Footer ───────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Text(
          l10n.proFooterCancel,
          style: const TextStyle(color: AppColors.textHint, fontSize: 12),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.proFooterPayment,
          style: const TextStyle(color: AppColors.textHint, fontSize: 11),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _isPurchasing ? null : _onRestoreTap,
          child: Text(l10n.proRestorePurchases, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ),
      ],
    );
  }
}

// ─── Plan Card ────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final _Plan plan;
  final bool selected;
  final String title;
  final double price;
  final String period;
  final String note;
  final String? badge;
  final double? originalPrice;
  final bool isLaunchDeal;
  final VoidCallback onTap;

  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.title,
    required this.price,
    required this.period,
    required this.note,
    required this.onTap,
    this.badge,
    this.originalPrice,
    this.isLaunchDeal = false,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? AppColors.gold : AppColors.border;
    final bgColor = selected ? AppColors.gold.withValues(alpha: 0.08) : AppColors.bgMedium;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: selected ? 1.5 : 0.5),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? AppColors.gold : AppColors.border, width: 2),
                color: selected ? AppColors.gold : Colors.transparent,
              ),
              child: selected
                  ? const Icon(Icons.check, size: 13, color: Colors.black)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: selected ? AppColors.gold : AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      if (isLaunchDeal) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6B35),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(AppLocalizations.of(context)!.proLaunchTag, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(note, style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (originalPrice != null)
                  Text(
                    '€${originalPrice!.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 12,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '€${price.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: selected ? AppColors.gold : AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      TextSpan(
                        text: '/$period',
                        style: const TextStyle(color: AppColors.textHint, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (badge != null)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(badge!, style: const TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Feature tile ─────────────────────────────────────────────────────────────

class _Feature {
  final IconData icon;
  final String title;
  final String subtitle;
  const _Feature(this.icon, this.title, this.subtitle);
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
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(feature.icon, color: AppColors.gold, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(feature.title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                Text(feature.subtitle, style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.check_circle, color: AppColors.gold, size: 20),
        ],
      ),
    );
  }
}
