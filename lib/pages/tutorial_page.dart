import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/tutorial_service.dart';
import '../theme/app_colors.dart';

class _Slide {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  const _Slide({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });
}

List<_Slide> _buildSlides(AppLocalizations l10n) => [
  _Slide(
    icon: Icons.style,
    iconColor: AppColors.gold,
    title: l10n.tutorialSlide1Title,
    description: l10n.tutorialSlide1Desc,
  ),
  _Slide(
    icon: Icons.collections_bookmark_outlined,
    iconColor: const Color(0xFF9B59B6),
    title: l10n.tutorialSlide2Title,
    description: l10n.tutorialSlide2Desc,
  ),
  _Slide(
    icon: Icons.search,
    iconColor: AppColors.cardtraderTeal,
    title: l10n.tutorialSlide3Title,
    description: l10n.tutorialSlide3Desc,
  ),
  _Slide(
    icon: Icons.document_scanner_outlined,
    iconColor: Colors.lightBlue,
    title: l10n.tutorialSlide4Title,
    description: l10n.tutorialSlide4Desc,
  ),
  _Slide(
    icon: Icons.favorite,
    iconColor: Colors.redAccent,
    title: l10n.tutorialSlide5Title,
    description: l10n.tutorialSlide5Desc,
  ),
  _Slide(
    icon: Icons.trending_up,
    iconColor: AppColors.success,
    title: l10n.tutorialSlide6Title,
    description: l10n.tutorialSlide6Desc,
  ),
  _Slide(
    icon: Icons.book_outlined,
    iconColor: const Color(0xFFFF6B35),
    title: l10n.tutorialSlide7Title,
    description: l10n.tutorialSlide7Desc,
  ),
];

class TutorialPage extends StatefulWidget {
  const TutorialPage({super.key});

  @override
  State<TutorialPage> createState() => _TutorialPageState();
}

class _TutorialPageState extends State<TutorialPage> {
  final _pageCtrl = PageController();
  int _currentPage = 0;
  late List<_Slide> _slides;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _slides.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _close();
    }
  }

  void _close() {
    TutorialService.complete();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    _slides = _buildSlides(l10n);
    final isLast = _currentPage == _slides.length - 1;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _close,
                  child: Text(l10n.tutorialBtnSkip, style: const TextStyle(color: AppColors.textHint)),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: _slides.length,
                itemBuilder: (_, i) => _buildSlide(_slides[i]),
              ),
            ),
            _buildDots(),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: Text(isLast ? l10n.tutorialBtnStart : l10n.tutorialBtnNext),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSlide(_Slide slide) {
    return GestureDetector(
      onTap: _next,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: slide.iconColor.withValues(alpha: 0.12),
                border: Border.all(
                  color: slide.iconColor.withValues(alpha: 0.3),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: slide.iconColor.withValues(alpha: 0.2),
                    blurRadius: 40,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(slide.icon, size: 56, color: slide.iconColor),
            ),
            const SizedBox(height: 36),
            Text(
              slide.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              slide.description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              AppLocalizations.of(context)!.splashTapToContinue,
              style: const TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_slides.length, (i) {
        final active = i == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active
                ? AppColors.gold
                : AppColors.textHint.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
