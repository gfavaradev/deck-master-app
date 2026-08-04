import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/language_service.dart';

/// Mostra la bandiera di una lingua come immagine vettoriale (SVG), resa in
/// modo identico su iOS, Android, Windows e Web — a differenza delle
/// emoji-bandiera, che su alcune piattaforme (in particolare Windows) non
/// vengono disegnate affatto.
///
/// Se il codice lingua non ha una bandiera associata, ricade su un badge
/// testuale con il codice stesso, così l'indicatore resta sempre leggibile.
class LanguageFlag extends StatelessWidget {
  final String languageCode;
  final double width;
  final double? height;

  const LanguageFlag({
    super.key,
    required this.languageCode,
    this.width = 26,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final code = languageCode.toUpperCase();
    final asset = LanguageService.flagAsset[code];
    final h = height ?? width * 0.7;

    final Widget flag = asset != null
        ? SvgPicture.asset(
            asset,
            width: width,
            height: h,
            fit: BoxFit.cover,
            placeholderBuilder: (_) => _codeBadge(code, width, h),
          )
        : _codeBadge(code, width, h);

    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(width: width, height: h, child: flag),
    );
  }

  static Widget _codeBadge(String code, double width, double height) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      color: const Color(0xFF333333),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            code,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 10,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}
