import 'dart:async';
import 'package:flutter/material.dart';
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
    _entry?.remove();
    _entry = null;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _UndoBarWidget(
        message: message,
        onUndo: onUndo != null
            ? () { onUndo(); _dismiss(); }
            : null,
        onExpired: _dismiss,
        accentColor: accentColor,
      ),
    );
    _entry = entry;
    Overlay.of(context).insert(entry);
  }

  static void _dismiss() {
    _entry?.remove();
    _entry = null;
  }
}

class _UndoBarWidget extends StatefulWidget {
  final String message;
  final VoidCallback? onUndo;
  final VoidCallback onExpired;
  final Color accentColor;

  const _UndoBarWidget({
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
    final topPad = MediaQuery.of(context).padding.top;
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
                  child: const Text('Annulla', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
