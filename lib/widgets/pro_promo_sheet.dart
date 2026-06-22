import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../pages/pro_page.dart';
import '../theme/app_colors.dart';

/// Mostra il popup promozionale Pro come dialog centrato (non una bottom sheet).
/// Va chiamato solo per utenti non-Pro.
void showProPromoSheet(BuildContext context) {
  showGeneralDialog<void>(
    context: context,
    barrierLabel: 'Deck Master PRO',
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, _, _) => const _ProPromoDialog(),
    transitionBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: curved, child: child),
      );
    },
  );
}

class _ProPromoDialog extends StatelessWidget {
  const _ProPromoDialog();

  // Stessi numeri del piano annuale in pro_page.dart — mantenere in sync.
  static const double _monthlyPrice = 2.99;
  static const double _annualMonthlyEquivalent = 1.67;
  static const int _savingsPercent = 44;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final benefits = <(IconData, String)>[
      (Icons.analytics_outlined,            l10n.proBenefitStats),
      (Icons.table_chart_outlined,          l10n.proBenefitExcel),
      (Icons.auto_awesome,                  l10n.proBenefitAi),
      (Icons.notifications_active_outlined, l10n.proBenefitAlerts),
      (Icons.block,                         l10n.proBenefitNoAds),
      (Icons.share_outlined,                l10n.proBenefitShare),
    ];

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Material(
                color: AppColors.bgMedium,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                elevation: 24,
                shadowColor: AppColors.gold.withValues(alpha: 0.4),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.4), width: 1.2),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _Header(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.proPromoHeadline,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.proPromoSubheadline,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.3),
                        ),
                        const SizedBox(height: 18),

                        // Benefits — lista verticale con check, più leggibile dei chip.
                        ...benefits.map((b) => _BenefitRow(icon: b.$1, label: b.$2)),

                        const SizedBox(height: 18),
                        _PriceBlock(
                          monthlyPrice: _monthlyPrice,
                          annualMonthlyEquivalent: _annualMonthlyEquivalent,
                          savingsPercent: _savingsPercent,
                          annualNote: l10n.proPromoBilledAnnually,
                        ),
                        const SizedBox(height: 18),

                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: const LinearGradient(
                                colors: [AppColors.gold, Color(0xFFFFD76A)],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.gold.withValues(alpha: 0.45),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ProPage()));
                                },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.star_rounded, size: 20, color: Colors.black),
                                    const SizedBox(width: 8),
                                    Text(
                                      l10n.proPromoCta,
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        Center(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(l10n.proPromoDismiss, style: const TextStyle(color: AppColors.textHint, fontSize: 13)),
                          ),
                        ),
                      ],
                    ),
                  ),
                    ],
                  ),
                ),
              ),
              // Badge interamente sopra il box (nessuna sovrapposizione col
              // Material sottostante) — evita qualunque artefatto di rendering
              // dovuto a ombra/elevazione/bordo che attraversi il badge.
              Positioned(
                top: -34,
                left: 0,
                right: 0,
                child: Center(
                  child: _SavingsBadge(badge: l10n.proPromoBadge, savingsPercent: _savingsPercent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavingsBadge extends StatelessWidget {
  final String badge;
  final int savingsPercent;
  const _SavingsBadge({required this.badge, required this.savingsPercent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B35),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Text(
        '$badge · −$savingsPercent%',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.3),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Container(
          height: 108,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2A1F00), Color(0xFF4A3700)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.18),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.5), width: 1.5),
              ),
              child: const Icon(Icons.workspace_premium, color: AppColors.gold, size: 36),
            ),
          ),
        ),
        Positioned(
          top: 14,
          right: 14,
          child: _CloseButton(),
        ),
      ],
    );
  }
}

class _CloseButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pop(context),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, color: Colors.white, size: 16),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _BenefitRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.gold, size: 15),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w500),
            ),
          ),
          const Icon(Icons.check_circle, color: AppColors.success, size: 16),
        ],
      ),
    );
  }
}

class _PriceBlock extends StatelessWidget {
  final double monthlyPrice;
  final double annualMonthlyEquivalent;
  final int savingsPercent;
  final String annualNote;
  const _PriceBlock({
    required this.monthlyPrice,
    required this.annualMonthlyEquivalent,
    required this.savingsPercent,
    required this.annualNote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Text(
            '€${monthlyPrice.toStringAsFixed(2)}',
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 14,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '€${annualMonthlyEquivalent.toStringAsFixed(2)}',
            style: const TextStyle(color: AppColors.gold, fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(width: 4),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('/mese', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
          const Spacer(),
          Expanded(
            flex: 0,
            child: Text(
              annualNote,
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppColors.textHint, fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }
}
