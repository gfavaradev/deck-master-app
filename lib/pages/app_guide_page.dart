import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';

class _Feature {
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final List<_Step> steps;

  const _Feature({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.steps,
  });
}

class _Step {
  final String text;
  const _Step(this.text);
}

List<_Feature> _buildFeatures(AppLocalizations l10n) => [
  _Feature(
    icon: Icons.collections_bookmark_outlined,
    color: const Color(0xFF9B59B6),
    title: l10n.guideCollectionsTitle,
    description: l10n.guideCollectionsDesc,
    steps: [
      _Step(l10n.guideCollectionsStep1),
      _Step(l10n.guideCollectionsStep2),
      _Step(l10n.guideCollectionsStep3),
      _Step(l10n.guideCollectionsStep4),
    ],
  ),
  _Feature(
    icon: Icons.add_circle_outline,
    color: AppColors.gold,
    title: l10n.guideAddTitle,
    description: l10n.guideAddDesc,
    steps: [
      _Step(l10n.guideAddStep1),
      _Step(l10n.guideAddStep2),
      _Step(l10n.guideAddStep3),
      _Step(l10n.guideAddStep4),
    ],
  ),
  _Feature(
    icon: Icons.document_scanner_outlined,
    color: Colors.lightBlue,
    title: l10n.guideScannerTitle,
    description: l10n.guideScannerDesc,
    steps: [
      _Step(l10n.guideScannerStep1),
      _Step(l10n.guideScannerStep2),
      _Step(l10n.guideScannerStep3),
      _Step(l10n.guideScannerStep4),
      _Step(l10n.guideScannerStep5),
    ],
  ),
  _Feature(
    icon: Icons.search,
    color: AppColors.cardtraderTeal,
    title: l10n.guideCatalogTitle,
    description: l10n.guideCatalogDesc,
    steps: [
      _Step(l10n.guideCatalogStep1),
      _Step(l10n.guideCatalogStep2),
      _Step(l10n.guideCatalogStep3),
      _Step(l10n.guideCatalogStep4),
      _Step(l10n.guideCatalogStep5),
    ],
  ),
  _Feature(
    icon: Icons.book_outlined,
    color: AppColors.gold,
    title: l10n.guideAlbumTitle,
    description: l10n.guideAlbumDesc,
    steps: [
      _Step(l10n.guideAlbumStep1),
      _Step(l10n.guideAlbumStep2),
      _Step(l10n.guideAlbumStep3),
      _Step(l10n.guideAlbumStep4),
      _Step(l10n.guideAlbumStep5),
    ],
  ),
  _Feature(
    icon: Icons.style_outlined,
    color: AppColors.blue,
    title: l10n.guideDeckTitle,
    description: l10n.guideDeckDesc,
    steps: [
      _Step(l10n.guideDeckStep1),
      _Step(l10n.guideDeckStep2),
      _Step(l10n.guideDeckStep3),
      _Step(l10n.guideDeckStep4),
      _Step(l10n.guideDeckStep5),
    ],
  ),
  _Feature(
    icon: Icons.favorite_outline,
    color: Colors.redAccent,
    title: l10n.guideWishlistTitle,
    description: l10n.guideWishlistDesc,
    steps: [
      _Step(l10n.guideWishlistStep1),
      _Step(l10n.guideWishlistStep2),
      _Step(l10n.guideWishlistStep3),
      _Step(l10n.guideWishlistStep4),
      _Step(l10n.guideWishlistStep5),
    ],
  ),
  _Feature(
    icon: Icons.trending_up,
    color: AppColors.success,
    title: l10n.guideStatsTitle,
    description: l10n.guideStatsDesc,
    steps: [
      _Step(l10n.guideStatsStep1),
      _Step(l10n.guideStatsStep2),
      _Step(l10n.guideStatsStep3),
      _Step(l10n.guideStatsStep4),
      _Step(l10n.guideStatsStep5),
    ],
  ),
  _Feature(
    icon: Icons.notifications_outlined,
    color: const Color(0xFFFF6D00),
    title: l10n.guideNotifTitle,
    description: l10n.guideNotifDesc,
    steps: [
      _Step(l10n.guideNotifStep1),
      _Step(l10n.guideNotifStep2),
      _Step(l10n.guideNotifStep3),
      _Step(l10n.guideNotifStep4),
    ],
  ),
  _Feature(
    icon: Icons.file_download_outlined,
    color: const Color(0xFF1D6F42),
    title: l10n.guideExportTitle,
    description: l10n.guideExportDesc,
    steps: [
      _Step(l10n.guideExportStep1),
      _Step(l10n.guideExportStep2),
      _Step(l10n.guideExportStep3),
      _Step(l10n.guideExportStep4),
      _Step(l10n.guideExportStep5),
    ],
  ),
  _Feature(
    icon: Icons.sync,
    color: AppColors.blue,
    title: l10n.guideSyncTitle,
    description: l10n.guideSyncDesc,
    steps: [
      _Step(l10n.guideSyncStep1),
      _Step(l10n.guideSyncStep2),
      _Step(l10n.guideSyncStep3),
      _Step(l10n.guideSyncStep4),
    ],
  ),
];

class AppGuidePage extends StatefulWidget {
  const AppGuidePage({super.key});

  @override
  State<AppGuidePage> createState() => _AppGuidePageState();
}

class _AppGuidePageState extends State<AppGuidePage> {
  final Set<int> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final features = _buildFeatures(l10n);
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text(l10n.guideAppBarTitle),
        backgroundColor: AppColors.bgMedium,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _buildHeader(l10n),
            const SizedBox(height: 20),
            ...List.generate(features.length, (i) {
              final feature = features[i];
              final isOpen = _expanded.contains(i);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _FeatureCard(
                  feature: feature,
                  isOpen: isOpen,
                  onToggle: () => setState(() {
                    if (isOpen) {
                      _expanded.remove(i);
                    } else {
                      _expanded.add(i);
                    }
                  }),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.menu_book_outlined, color: AppColors.gold, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.guideHeaderTitle,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.guideHeaderSubtitle,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final _Feature feature;
  final bool isOpen;
  final VoidCallback onToggle;

  const _FeatureCard({
    required this.feature,
    required this.isOpen,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOpen ? feature.color.withValues(alpha: 0.4) : AppColors.border,
          width: isOpen ? 1 : 0.5,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: feature.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(feature.icon, color: feature.color, size: 22),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      feature.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: isOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: isOpen ? feature.color : AppColors.textHint,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isOpen) ...[
            Container(height: 0.5, color: AppColors.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    feature.description,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ...feature.steps.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: feature.color.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${e.key + 1}',
                              style: TextStyle(
                                color: feature.color,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            e.value.text,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13.5,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
