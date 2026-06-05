import '../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import '../services/tutorial_service.dart';
import '../theme/app_colors.dart';

/// Launcher page for the interactive tutorial.
/// Shown from Settings → "Guida all'App".
/// On "Inizia", resets the tutorial state and navigates to a fresh MainLayout.
class TutorialPage extends StatelessWidget {
  const TutorialPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.tutorialPageTitle),
        backgroundColor: AppColors.bgMedium,
        foregroundColor: AppColors.textPrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.gold.withValues(alpha: 0.12),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.35), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.25),
                      blurRadius: 32,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(Icons.explore_outlined, size: 56, color: AppColors.gold),
              ),
              const SizedBox(height: 28),
              const Text(
                'Tutorial Interattivo',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Il tutorial ti guiderà passo dopo passo attraverso le funzionalità principali dell\'app con indicatori animati direttamente sull\'interfaccia.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Durata: ~1 minuto',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textHint, fontSize: 12),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: () => _startTutorial(context),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(AppLocalizations.of(context)!.tutorialStartBtn),
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
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(foregroundColor: AppColors.textHint),
                child: Text(AppLocalizations.of(context)!.tutorialMaybeLater),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startTutorial(BuildContext context) async {
    await TutorialService.reset();
    if (!context.mounted) return;
    // Pop all routes back to root (MainLayout), then signal it to start the tutorial
    Navigator.popUntil(context, (route) => route.isFirst);
    // Give MainLayout a frame to settle, then fire the tutorial signal
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TutorialService.instance.start();
    });
  }
}
