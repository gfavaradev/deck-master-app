import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';

/// Banner pubblicitario AdMob adattivo — si estende a tutta la larghezza dello schermo.
/// Nascosto automaticamente per gli utenti Pro.
/// Si auto-carica al mount e si auto-dispone all'unmount.
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  AdSize? _adSize;
  bool _isPro = true; // default true: niente banner finché non sappiamo lo stato

  @override
  void initState() {
    super.initState();
    _checkPro();
  }

  Future<void> _checkPro() async {
    final user = await UserService().getCurrentUser();
    if (!mounted) return;
    final isPro = user?.isPro ?? false;
    setState(() => _isPro = isPro);
    if (!isPro) _loadAd();
  }

  Future<void> _loadAd() async {
    if (kIsWeb) return;
    final width = MediaQuery.sizeOf(context).width.truncate();
    final adSize = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
    if (adSize == null || !mounted) return;

    final ad = BannerAd(
      adUnitId: AdService.bannerAdUnitId,
      size: adSize,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _adSize = adSize);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    );
    ad.load();
    _bannerAd = ad;
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isPro || _adSize == null || _bannerAd == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      height: _adSize!.height.toDouble(),
      color: AppColors.bgMedium,
      alignment: Alignment.center,
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
