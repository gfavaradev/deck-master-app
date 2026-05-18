import 'package:flutter/material.dart';
import '../services/app_preferences.dart';
import '../theme/app_colors.dart';

class OnboardingPage extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingPage({super.key, required this.onComplete});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with SingleTickerProviderStateMixin {
  int _step = 0; // 0 = lingua, 1 = valuta

  String _selectedLang = 'it';
  String _selectedCurrency = 'EUR';

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _selectedLang = AppPreferences.instance.languageCode;
    _selectedCurrency = AppPreferences.instance.currencyCode;
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _goToStep(int step) async {
    await _animCtrl.reverse();
    if (!mounted) return;
    setState(() => _step = step);
    _animCtrl.forward();
  }

  Future<void> _finish() async {
    final prefs = AppPreferences.instance;
    await prefs.setLanguage(_selectedLang);
    await prefs.setCurrency(_selectedCurrency);
    await prefs.setOnboardingDone();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: _step == 0 ? _buildLanguageStep() : _buildCurrencyStep(),
        ),
      ),
    );
  }

  // ─── Step 1: Lingua ──────────────────────────────────────────────────────

  Widget _buildLanguageStep() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 56),
          _buildHeader(
            icon: Icons.language,
            step: '1 / 2',
            title: 'Seleziona la lingua',
            subtitle: 'Choose your language',
          ),
          const SizedBox(height: 40),
          ...AppPreferences.languages.map((lang) => _buildLangCard(lang)),
          const Spacer(),
          _buildContinueButton(
            label: 'Continua',
            onTap: () => _goToStep(1),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildLangCard(({String code, String name, String flag}) lang) {
    final selected = _selectedLang == lang.code;
    return GestureDetector(
      onTap: () => setState(() => _selectedLang = lang.code),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold.withValues(alpha: 0.1) : AppColors.bgMedium,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.border,
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Text(lang.flag, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                lang.name,
                style: TextStyle(
                  color: selected ? AppColors.gold : AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
            AnimatedOpacity(
              opacity: selected ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: const Icon(Icons.check_circle, color: AppColors.gold, size: 22),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Step 2: Valuta ──────────────────────────────────────────────────────

  Widget _buildCurrencyStep() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 56),
          _buildHeader(
            icon: Icons.monetization_on_outlined,
            step: '2 / 2',
            title: 'Seleziona la valuta',
            subtitle: 'Select your preferred currency',
          ),
          const SizedBox(height: 40),
          Expanded(
            child: ListView(
              children: AppPreferences.currencies
                  .map((c) => _buildCurrencyCard(c))
                  .toList(),
            ),
          ),
          _buildContinueButton(label: 'Inizia', onTap: _finish),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildCurrencyCard(
      ({String code, String symbol, String name}) currency) {
    final selected = _selectedCurrency == currency.code;
    return GestureDetector(
      onTap: () => setState(() => _selectedCurrency = currency.code),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold.withValues(alpha: 0.1) : AppColors.bgMedium,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.border,
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.gold.withValues(alpha: 0.15)
                    : AppColors.bgLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  currency.symbol,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: selected ? AppColors.gold : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currency.code,
                    style: TextStyle(
                      color: selected ? AppColors.gold : AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    currency.name,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            AnimatedOpacity(
              opacity: selected ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: const Icon(Icons.check_circle, color: AppColors.gold, size: 22),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Shared widgets ──────────────────────────────────────────────────────

  Widget _buildHeader({
    required IconData icon,
    required String step,
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.gold, size: 22),
            ),
            const SizedBox(width: 12),
            Text(step,
                style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 20),
        Text(title,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                height: 1.2)),
        const SizedBox(height: 6),
        Text(subtitle,
            style: const TextStyle(color: AppColors.textHint, fontSize: 14)),
      ],
    );
  }

  Widget _buildContinueButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        child: Text(label),
      ),
    );
  }
}
