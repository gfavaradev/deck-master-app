import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_service.dart';
import '../services/user_service.dart';

/// Banner AdMob — nascosto per utenti Pro e su Web.
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
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

  void _loadAd() {
    final ad = BannerAd(
      adUnitId: AdService.bannerAdUnitId,
      size: AdSize.banner,
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
    if (kIsWeb || _isPro || !_isAdLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: double.infinity,
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
