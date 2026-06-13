import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_service.dart';
import '../services/user_service.dart';

/// Banner AdMob adattivo alla larghezza — nascosto per utenti Pro e su Web.
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  AdSize? _adSize;
  bool _isAdLoaded = false;
  bool _isPro = true; // default: nascosto finché non sappiamo lo stato

  @override
  void initState() {
    super.initState();
    _checkAndLoad();
  }

  Future<void> _checkAndLoad() async {
    final user = await UserService().getCurrentUser();
    if (!mounted) return;
    if (user?.isPro == true) {
      setState(() => _isPro = true);
      return;
    }
    setState(() => _isPro = false);
    _loadAd();
  }

  int _retryCount = 0;
  static const _maxRetries = 3;

  Future<void> _loadAd() async {
    // Banner adattivo: usa tutta la larghezza disponibile dello schermo
    final screenWidth = MediaQuery.of(context).size.width.truncate();
    final adSize = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(screenWidth);
    if (!mounted || adSize == null) return;
    _adSize = adSize;

    final ad = BannerAd(
      adUnitId: AdService.bannerAdUnitId,
      size: adSize,
      request: const AdRequest(nonPersonalizedAds: true),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() { _isAdLoaded = true; _retryCount = 0; });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted && _retryCount < _maxRetries) {
            _retryCount++;
            Future.delayed(Duration(seconds: _retryCount * 5), () {
              if (mounted) _loadAd();
            });
          }
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
    if (kIsWeb || _isPro || !_isAdLoaded || _bannerAd == null || _adSize == null) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      top: false,
      child: SizedBox(
        width: double.infinity,
        height: _adSize!.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      ),
    );
  }
}
