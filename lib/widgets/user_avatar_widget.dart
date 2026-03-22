import 'package:flutter/material.dart';
import '../services/xp_service.dart';
import '../theme/app_colors.dart';

/// Mostra l'avatar dell'utente: avatar sbloccato se selezionato,
/// altrimenti la [photoUrl] fornita. Con [showLevelBadge] aggiunge
/// il badge con il numero di livello in basso a destra.
class UserAvatarWidget extends StatefulWidget {
  final double radius;
  final bool showLevelBadge;
  final String? photoUrl;

  const UserAvatarWidget({
    super.key,
    this.radius = 18,
    this.showLevelBadge = false,
    this.photoUrl,
  });

  @override
  State<UserAvatarWidget> createState() => _UserAvatarWidgetState();
}

class _UserAvatarWidgetState extends State<UserAvatarWidget> {
  AvatarDef? _selectedAvatar;
  int _xp = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final xp = await XpService().getCurrentXp();
    final selectedId = await XpService().getSelectedAvatarId();
    AvatarDef? avatar;
    if (selectedId != null) {
      try {
        avatar = XpService.avatars.firstWhere((a) => a.id == selectedId);
      } catch (_) {}
    }
    if (mounted) setState(() { _xp = xp; _selectedAvatar = avatar; });
  }

  @override
  Widget build(BuildContext context) {
    final level = XpService.levelFromXp(_xp);

    Widget circle;
    if (_selectedAvatar != null) {
      circle = _selectedAvatar!.buildCircle(widget.radius);
    } else if (widget.photoUrl != null) {
      circle = CircleAvatar(
        radius: widget.radius,
        backgroundImage: NetworkImage(widget.photoUrl!),
        backgroundColor: AppColors.bgLight,
      );
    } else {
      circle = CircleAvatar(
        radius: widget.radius,
        backgroundColor: AppColors.bgLight,
        child: Icon(Icons.person, size: widget.radius, color: AppColors.textSecondary),
      );
    }

    if (!widget.showLevelBadge) return circle;

    return Stack(
      alignment: Alignment.center,
      children: [
        circle,
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.gold,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black, width: 1),
            ),
            child: Text(
              '$level',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
