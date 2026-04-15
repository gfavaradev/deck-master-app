import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Styled dialog shell — tutti i dialog dell'app usano questo widget
/// per garantire coerenza visiva (header scuro, bordi arrotondati, ombra).
class AppDialog extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget content;
  final List<Widget> actions;
  final bool showCloseButton;
  final EdgeInsets contentPadding;

  const AppDialog({
    super.key,
    required this.title,
    required this.icon,
    this.iconColor = AppColors.blue,
    required this.content,
    this.actions = const [],
    this.showCloseButton = true,
    this.contentPadding = const EdgeInsets.fromLTRB(20, 20, 20, 8),
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: AppColors.bgMedium,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
              decoration: const BoxDecoration(
                color: AppColors.bgLight,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (showCloseButton)
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: AppColors.textHint, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ),
            Container(height: 0.5, color: AppColors.divider),

            // ── Content ──────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: contentPadding,
                child: content,
              ),
            ),

            // ── Actions ──────────────────────────────────────────────────
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(
                  children: [
                    for (int i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(child: actions[i]),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Stili bottoni condivisi ─────────────────────────────────────────────────

ButtonStyle appDialogCancelStyle() => OutlinedButton.styleFrom(
  foregroundColor: AppColors.textSecondary,
  side: const BorderSide(color: AppColors.border),
  padding: const EdgeInsets.symmetric(vertical: 13),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
);

ButtonStyle appDialogConfirmStyle({Color color = AppColors.blue}) =>
    FilledButton.styleFrom(
      backgroundColor: color,
      padding: const EdgeInsets.symmetric(vertical: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );

// ─── AppConfirmDialog ────────────────────────────────────────────────────────

/// Dialog di conferma standard (Annulla + Azione). Non mostra la X —
/// il bottone Annulla è l'unico modo per uscire senza confermare.
class AppConfirmDialog extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final String message;
  final String confirmLabel;
  final Color confirmColor;
  final String cancelLabel;

  const AppConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.warning_amber_rounded,
    this.iconColor = AppColors.error,
    this.confirmLabel = 'Conferma',
    this.confirmColor = AppColors.error,
    this.cancelLabel = 'Annulla',
  });

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: title,
      icon: icon,
      iconColor: iconColor,
      showCloseButton: false,
      content: Text(
        message,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          height: 1.5,
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          style: appDialogCancelStyle(),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: appDialogConfirmStyle(color: confirmColor),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
