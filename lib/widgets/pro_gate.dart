import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Blocca visivamente un widget se l'utente non ha il piano Pro.
/// Mostra un overlay sfocato con lucchetto e CTA alla ProPage.
class ProGate extends StatelessWidget {
  final Widget child;
  final bool hasPro;
  final String featureName;
  final VoidCallback? onUpgrade;

  const ProGate({
    super.key,
    required this.child,
    required this.hasPro,
    this.featureName = 'questa funzione',
    this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    if (hasPro) return child;

    return Stack(
      children: [
        // Contenuto originale sfocato
        IgnorePointer(
          child: Opacity(opacity: 0.35, child: child),
        ),

        // Overlay blur + lock
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.bgDark.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.gold.withValues(alpha: 0.15),
                          border: Border.all(
                            color: AppColors.gold.withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Icon(
                          Icons.lock_outline,
                          color: AppColors.gold,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Funzione Pro',
                        style: TextStyle(
                          color: AppColors.gold,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sblocca $featureName con Pro',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: onUpgrade ??
                            () => Navigator.of(context).pushNamed('/pro'),
                        icon: const Icon(Icons.workspace_premium, size: 16),
                        label: const Text('Passa a Pro'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.gold,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
