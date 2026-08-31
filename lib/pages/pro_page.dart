import '../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../services/billing_service.dart';
import '../services/subscription_service.dart';
import '../theme/app_colors.dart';
import '../utils/subscription_pricing.dart';

enum _Plan { monthly, semiannual, annual }

class ProPage extends StatefulWidget {
  const ProPage({super.key});

  @override
  State<ProPage> createState() => _ProPageState();
}

class _ProPageState extends State<ProPage> with SingleTickerProviderStateMixin {
  _Plan _selectedPlan = _Plan.annual;
  bool _isPurchasing = false;

  /// Ricaricata a ogni `loadProducts`: il paywall la usa solo per ridisegnarsi
  /// quando i prezzi reali arrivano. Le offerte vivono in [BillingService].
  bool _productsLoaded = false;
  late AnimationController _shimmerController;
  late final Future<bool> _proStatusFuture;

  // ─── Prezzi ───────────────────────────────────────────────────────────────
  //
  // I prezzi mostrati vengono dal negozio (ProductDetails.price), già
  // localizzati nella valuta del paese dell'utente, e le percentuali di
  // risparmio sono calcolate sui prezzi reali. Le costanti qui sotto sono solo
  // un listino di riserva, usato dove un negozio non c'è affatto: Windows e
  // Web, dove il paywall è in sola lettura. Su una piattaforma con billing non
  // vengono mai mostrate — vedi [_pricesFor].
  //
  // ATTENZIONE: sono gli importi di Play Console, cioè **al netto
  // dell'imposta**. Quello che l'utente paga davvero è ~×1,20 (verificato con
  // un dump di ProductDetails il 30/08/2026: il rapporto è uniforme su tutti e
  // tre i piani, quindi è fiscale e non un difetto di matching delle offerte).
  // Chi apre il paywall da Windows vede quindi una cifra più bassa di quella
  // che gli verrebbe addebitata su Android: se un giorno da qui si potrà
  // comprare, questi numeri vanno portati al lordo prima.
  //
  // Le percentuali di risparmio non ne risentono: sono un rapporto fra piani,
  // invariante rispetto a un fattore comune.
  static const double _fallbackMonthly    = 4.99;
  static const double _fallbackSemiannual = 22.99;
  static const double _fallbackAnnual     = 34.99;

  @override
  void initState() {
    super.initState();
    _proStatusFuture = SubscriptionService().currentUserHasPro();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    await BillingService().loadProducts();
    if (mounted) setState(() => _productsLoaded = true);
  }

  static int _monthsOf(_Plan plan) => switch (plan) {
    _Plan.monthly    => 1,
    _Plan.semiannual => 6,
    _Plan.annual     => 12,
  };

  static String _productIdOf(_Plan plan) => switch (plan) {
    _Plan.monthly    => kProductMonthly,
    _Plan.semiannual => kProductSemiannual,
    _Plan.annual     => kProductAnnual,
  };

  static double _fallbackPriceOf(_Plan plan) => switch (plan) {
    _Plan.monthly    => _fallbackMonthly,
    _Plan.semiannual => _fallbackSemiannual,
    _Plan.annual     => _fallbackAnnual,
  };

  /// Offerta del negozio corrispondente a [plan], `null` se non c'è.
  ///
  /// La selezione fra i base plan dello stesso abbonamento la fa
  /// [BillingService.productFor]: qui il piano è già scelto.
  ProductDetails? _productFor(_Plan plan) =>
      BillingService().productFor(_productIdOf(plan));

  /// Segnaposto usato finché il negozio non ha risposto.
  static const _PlanPrices _pricesPlaceholder = _PlanPrices(
    price: '—',
    perMonth: '—',
  );

  /// Prezzi da mostrare per [plan]: dal negozio quando disponibili, altrimenti
  /// dal listino di riserva in euro.
  ///
  /// Su una piattaforma con billing il listino di riserva non si usa mai: se
  /// il negozio non ha (ancora) risposto si mostra un segnaposto. Mostrare una
  /// cifra scritta nel codice accanto a un pulsante "Abbonati" significa
  /// annunciare un prezzo che non è detto sia quello che Play addebiterà — ed
  /// è esattamente il disallineamento con Play Console che si vedeva.
  _PlanPrices _pricesFor(_Plan plan) {
    final months = _monthsOf(plan);
    final product = _productFor(plan);
    if (product == null && BillingService.isSupportedPlatform) {
      return _pricesPlaceholder;
    }
    final monthlyPrice = _productFor(_Plan.monthly)?.rawPrice ?? _fallbackMonthly;
    final price = product?.rawPrice ?? _fallbackPriceOf(plan);

    // Il totale usa il prezzo formattato dal negozio, già con il separatore e
    // il simbolo giusti per il paese. Gli importi derivati (al mese, prezzo
    // barrato) li formattiamo noi nella stessa valuta.
    String money(double value) => product == null
        ? '€${value.toStringAsFixed(2)}'
        : NumberFormat.simpleCurrency(name: product.currencyCode).format(value);

    final savings = plan == _Plan.monthly
        ? 0
        : savingsPercent(
            monthlyPrice: monthlyPrice,
            planPrice: price,
            months: months,
          );

    return _PlanPrices(
      price: product?.price ?? money(price),
      perMonth: money(price / months),
      savings: savings == 0 ? null : savings,
      // Barrato solo sull'annuale: quanto costerebbero 12 mesi di mensile.
      original: plan == _Plan.annual ? money(monthlyPrice * 12) : null,
    );
  }

  Future<void> _onPurchaseTap() async {
    // Nessun ripiego sul primo prodotto disponibile: prima, quando il matching
    // falliva, l'utente sceglieva l'annuale e ne comprava un altro.
    final product = _productFor(_selectedPlan);
    final l10n = AppLocalizations.of(context)!;

    if (product == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.proNotAvailable)));
      return;
    }

    setState(() => _isPurchasing = true);
    final outcome = await BillingService().purchase(product);
    if (!mounted) return;
    setState(() => _isPurchasing = false);

    switch (outcome) {
      case BillingOutcome.success:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.proWelcomeMsg),
            backgroundColor: AppColors.gold,
          ),
        );
        Navigator.pop(context);

      case BillingOutcome.pending:
        // Pagamento differito (es. contanti in cartoleria): l'utente non ha
        // ancora il Pro e non deve credere di averlo, ma non è un errore.
        _showInfo(l10n.proPurchasePending);

      case BillingOutcome.verificationFailed:
        // L'addebito può esserci stato: l'acquisto resta pendente e riparte da
        // solo al prossimo avvio. Dirlo, invece di mostrare un errore secco.
        _showInfo(l10n.proVerificationPending);

      case BillingOutcome.cancelled:
        break;

      case BillingOutcome.unavailable:
      case BillingOutcome.error:
        _showInfo(l10n.proNotAvailable);
    }
  }

  Future<void> _onRestoreTap() async {
    setState(() => _isPurchasing = true);
    final restored = await BillingService().restore();
    if (!mounted) return;
    setState(() => _isPurchasing = false);
    final l10n = AppLocalizations.of(context)!;
    _showInfo(
      restored ? l10n.proPurchasesRestored : l10n.proNoPurchasesToRestore,
    );
  }

  /// Manda l'utente alla pagina Play da cui gestisce o disdice l'abbonamento.
  /// La disdetta non avviene mai dentro l'app: l'abbonamento è fra l'utente e
  /// Google.
  Future<void> _openSubscriptionManagement() async {
    final l10n = AppLocalizations.of(context)!;
    final opened = await launchUrl(
      BillingService().manageSubscriptionUri(),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) _showInfo(l10n.proManageSubscriptionFailed);
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
    final monthly = _pricesFor(_Plan.monthly);
    final semiannual = _pricesFor(_Plan.semiannual);
    final annual = _pricesFor(_Plan.annual);
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
          prices: monthly,
          period: l10n.proMonthPeriod,
          note: l10n.proMonthlyNote,
          onTap: () => setState(() => _selectedPlan = _Plan.monthly),
        ),
        const SizedBox(height: 10),
        _PlanCard(
          plan: _Plan.semiannual,
          selected: _selectedPlan == _Plan.semiannual,
          title: l10n.proSemiannualLabel,
          prices: semiannual,
          period: l10n.proSemiannualPeriod,
          note: semiannual.savings == null
              ? l10n.proMonthlyNote
              : l10n.proSaveNote(semiannual.perMonth, '${semiannual.savings}'),
          badge: semiannual.savings == null ? null : '−${semiannual.savings}%',
          onTap: () => setState(() => _selectedPlan = _Plan.semiannual),
        ),
        const SizedBox(height: 10),
        _PlanCard(
          plan: _Plan.annual,
          selected: _selectedPlan == _Plan.annual,
          title: l10n.proYearlyLabel,
          prices: annual,
          period: l10n.proYearPeriod,
          note: annual.savings == null
              ? l10n.proMonthlyNote
              : l10n.proSaveNote(annual.perMonth, '${annual.savings}'),
          badge: annual.savings == null ? null : '−${annual.savings}%',
          isLaunchDeal: true,
          onTap: () => setState(() => _selectedPlan = _Plan.annual),
        ),
      ],
    );
  }

  // ─── CTA ──────────────────────────────────────────────────────────────────

  Widget _buildCTA() {
    final l10n = AppLocalizations.of(context)!;

    // Su Windows, Web e (per ora) iOS non c'è un negozio da cui comprare: il
    // paywall resta visibile con il listino di riserva, ma senza pulsanti che
    // non porterebbero da nessuna parte.
    if (!BillingService.isSupportedPlatform) {
      return Text(
        l10n.proPlatformUnsupported,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textHint, fontSize: 13),
      );
    }

    // Finché Play non ha risposto i prezzi a schermo sono quelli di riserva:
    // lasciar premere significherebbe far comprare un piano a un prezzo che
    // non è detto sia quello mostrato.
    final canBuy =
        _productsLoaded && !_isPurchasing && _productFor(_selectedPlan) != null;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            onPressed: canBuy ? _onPurchaseTap : null,
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
            if (snap.data != true) return const SizedBox.shrink();
            // Prima qui c'era solo la scritta "sei già abbonato": un vicolo
            // cieco per chi voleva cambiare piano o disdire.
            return Column(
              children: [
                Text(
                  l10n.proAlreadySubscribed,
                  style: const TextStyle(color: AppColors.gold, fontSize: 13),
                ),
                if (BillingService.isSupportedPlatform)
                  TextButton.icon(
                    onPressed: _openSubscriptionManagement,
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: Text(l10n.proManageSubscription),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            );
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
        if (BillingService.isSupportedPlatform) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: _isPurchasing ? null : _onRestoreTap,
            child: Text(l10n.proRestorePurchases, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
        ],
      ],
    );
  }
}

// ─── Plan Card ────────────────────────────────────────────────────────────────

/// Prezzi di un piano, già formattati e pronti da mostrare.
class _PlanPrices {
  const _PlanPrices({
    required this.price,
    required this.perMonth,
    this.savings,
    this.original,
  });

  /// Totale del piano, es. "€22,99".
  final String price;

  /// Equivalente mensile, es. "€3,83".
  final String perMonth;

  /// Sconto sul mensile in percentuale, `null` se assente o non applicabile.
  final int? savings;

  /// Prezzo barrato di confronto, `null` se non va mostrato.
  final String? original;
}

class _PlanCard extends StatelessWidget {
  final _Plan plan;
  final bool selected;
  final String title;
  final _PlanPrices prices;
  final String period;
  final String note;
  final String? badge;
  final bool isLaunchDeal;
  final VoidCallback onTap;

  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.title,
    required this.prices,
    required this.period,
    required this.note,
    required this.onTap,
    this.badge,
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
                if (prices.original != null)
                  Text(
                    prices.original!,
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
                        text: prices.price,
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
