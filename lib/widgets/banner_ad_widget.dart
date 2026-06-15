import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _isPro = false;

  int _retryCount = 0;
  static const _maxRetries = 3;
  static const _kProCacheKey = 'banner_is_pro_';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkAndLoad();
    });
  }

  Future<void> _checkAndLoad() async {
    if (!mounted) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final prefs = await SharedPreferences.getInstance();
    final cachedPro = uid != null && (prefs.getBool('$_kProCacheKey$uid') ?? false);

    if (!mounted) return;

    if (cachedPro) {
      setState(() => _isPro = true);
      _verifyProInBackground(uid, prefs);
      return;
    }

    _adSize = AdSize.banner;
    _createBannerAd(AdSize.banner);

    _verifyProInBackground(uid, prefs);
  }

  Future<void> _verifyProInBackground(String? uid, SharedPreferences prefs) async {
    final user = await UserService().getCurrentUser();
    final isProNow = user?.isPro == true;
    if (uid != null) {
      if (isProNow) {
        await prefs.setBool('$_kProCacheKey$uid', true);
      } else {
        await prefs.remove('$_kProCacheKey$uid');
      }
    }
    if (!mounted) return;
    if (isProNow) {
      setState(() => _isPro = true);
      _bannerAd?.dispose();
      _bannerAd = null;
    } else if (_isPro) {
      setState(() => _isPro = false);
      _adSize = AdSize.banner;
      _createBannerAd(AdSize.banner);
    }
  }

  void _createBannerAd(AdSize adSize) {
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
              if (mounted && _adSize != null) _createBannerAd(_adSize!);
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
    return SizedBox(
      width: double.infinity,
      height: _adSize!.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
