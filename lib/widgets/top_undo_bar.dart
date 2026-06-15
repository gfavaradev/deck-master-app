import '../l10n/app_localizations.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../theme/app_colors.dart';

/// Barra di notifica in stile app — appare in alto sotto la AppBar.
/// Se [onUndo] è fornito, mostra il countdown e il tasto "Annulla".
/// Se [onUndo] è null, mostra solo il messaggio con auto-dismiss.
class TopUndoBar {
  static OverlayEntry? _entry;

  /// Mostra la barra. Se [onUndo] è null nessun bottone "Annulla" viene mostrato.
  static void show({
    required BuildContext context,
    required String message,
    VoidCallback? onUndo,
    Color accentColor = AppColors.error,
  }) {
    _safeRemove();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _UndoBarWidget(
        // Pass the outer context so SafeArea/MediaQuery use the page's
        // viewPadding rather than the anonymous OverlayEntry builder context,
        // which may have stale insets on some OEM devices.
        pageContext: context,
        message: message,
        onUndo: onUndo != null
            ? () { onUndo(); _dismiss(); }
            : null,
        onExpired: _dismiss,
        accentColor: accentColor,
      ),
    );
    _entry = entry;
    // rootOverlay: true ensures we always get the root Navigator's overlay,
    // even when called from a context inside a nested Navigator.
    try {
      Overlay.of(context, rootOverlay: true).insert(entry);
    } catch (_) {
      // Fallback: try without rootOverlay (e.g., nested-only navigator setups).
      try {
        Overlay.of(context).insert(entry);
      } catch (_) {
        _entry = null;
      }
    }
  }

  static void _dismiss() {
    // Defer removal to after the current frame to avoid
    // "remove called during build" assertions on some devices.
    final entry = _entry;
    _entry = null;
    if (entry == null) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _safeEntry(entry));
    } else {
      _safeEntry(entry);
    }
  }

  static void _safeRemove() {
    final entry = _entry;
    _entry = null;
    if (entry == null) return;
    _safeEntry(entry);
  }

  static void _safeEntry(OverlayEntry entry) {
    try { entry.remove(); } catch (_) {}
  }
}

class _UndoBarWidget extends StatefulWidget {
  final BuildContext pageContext;
  final String message;
  final VoidCallback? onUndo;
  final VoidCallback onExpired;
  final Color accentColor;

  const _UndoBarWidget({
    required this.pageContext,
    required this.message,
    required this.onUndo,
    required this.onExpired,
    required this.accentColor,
  });

  @override
  State<_UndoBarWidget> createState() => _UndoBarWidgetState();
}

class _UndoBarWidgetState extends State<_UndoBarWidget> {
  int _remaining = 5;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_remaining <= 1) {
        t.cancel();
        widget.onExpired();
      } else {
        setState(() => _remaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use pageContext for localization and viewPadding — the anonymous OverlayEntry
    // builder context may lack localizations or return stale insets on some OEMs.
    final l10n = AppLocalizations.of(widget.pageContext) ?? AppLocalizations.of(context);
    final undoLabel = l10n?.undoBarUndo ?? 'Annulla';
    // viewPadding.top is unaffected by keyboard insets — safer than padding.top.
    final topPad = MediaQuery.viewPaddingOf(widget.pageContext).top;
    return Positioned(
      top: topPad + kToolbarHeight + 8,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.bgMedium,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: widget.accentColor.withValues(alpha: 0.45)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: _remaining / 5,
                      strokeWidth: 2.5,
                      color: widget.accentColor,
                      backgroundColor: widget.accentColor.withValues(alpha: 0.15),
                    ),
                    Text(
                      '$_remaining',
                      style: TextStyle(
                        color: widget.accentColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.message,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                ),
              ),
              if (widget.onUndo != null)
                TextButton(
                  onPressed: widget.onUndo,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orange.shade300,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(undoLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
