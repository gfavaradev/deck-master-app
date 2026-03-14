import 'package:flutter/material.dart';
import '../models/subscription_model.dart';

/// Badge donazione visibile nel profilo utente.
/// Mostra il tier con colore, simbolo e bordo animato per Ultra Raro e Secret Rare.
class DonationBadge extends StatefulWidget {
  final DonationTier tier;
  final double size;
  final bool showLabel;

  const DonationBadge({
    super.key,
    required this.tier,
    this.size = 24,
    this.showLabel = false,
  });

  @override
  State<DonationBadge> createState() => _DonationBadgeState();
}

class _DonationBadgeState extends State<DonationBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    if (widget.tier.hasAnimation) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(DonationBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tier.hasAnimation && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.tier.hasAnimation && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tier == DonationTier.none) return const SizedBox.shrink();

    final badge = _buildBadge();

    if (!widget.showLabel) return badge;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        const SizedBox(width: 6),
        Text(
          '${widget.tier.symbol} ${widget.tier.badgeTitle}',
          style: TextStyle(
            color: widget.tier.color,
            fontSize: widget.size * 0.58,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildBadge() {
    final color = widget.tier.color;
    final s = widget.size;

    if (widget.tier.hasAnimation) {
      return AnimatedBuilder(
        animation: _controller,
        builder: (_, _) {
          return Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: widget.tier.gradientColors,
                transform: GradientRotation(_controller.value * 6.28),
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Center(
              child: Text(
                widget.tier.symbol,
                style: TextStyle(fontSize: s * 0.5, height: 1),
              ),
            ),
          );
        },
      );
    }

    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.2),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Center(
        child: Text(
          widget.tier.symbol,
          style: TextStyle(fontSize: s * 0.48, height: 1),
        ),
      ),
    );
  }
}

/// Bordo animato attorno all'avatar per tier con hasBorder
class DonationAvatarBorder extends StatefulWidget {
  final DonationTier tier;
  final double radius;
  final Widget child;

  const DonationAvatarBorder({
    super.key,
    required this.tier,
    required this.radius,
    required this.child,
  });

  @override
  State<DonationAvatarBorder> createState() => _DonationAvatarBorderState();
}

class _DonationAvatarBorderState extends State<DonationAvatarBorder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.tier.hasAnimation) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.tier.hasBorder) return widget.child;

    final color = widget.tier.color;
    final r = widget.radius;

    if (widget.tier.hasAnimation) {
      return AnimatedBuilder(
        animation: _controller,
        builder: (_, child) {
          return Container(
            width: r * 2 + 6,
            height: r * 2 + 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: widget.tier.gradientColors,
                transform: GradientRotation(_controller.value * 6.28),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: ClipOval(child: widget.child),
            ),
          );
        },
      );
    }

    return Container(
      width: r * 2 + 6,
      height: r * 2 + 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 3),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: ClipOval(child: widget.child),
      ),
    );
  }
}
