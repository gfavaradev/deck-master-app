import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton that coordinates the interactive onboarding tutorial across pages.
///
/// Phases:
///   0 — Home: spotlight on the first collection card
///   1 — Inside collection: spotlight scanner / wishlist / ROI buttons in AppBar
///   2 — WishlistPage: spotlight the add-to-wishlist FAB
///   3 — RoiPage: spotlight the total-value KPI card
///  -1 — Tutorial complete
class TutorialService {
  TutorialService._();
  static final TutorialService instance = TutorialService._();

  static const _prefKey = 'tutorial_completed';

  bool isActive = false;
  int phase = 0;

  /// Bumped every time the tutorial is (re)started.
  /// HomePageSimple and MainLayout listen to this to react immediately,
  /// even when they are already mounted (not rebuilt from scratch).
  final ValueNotifier<int> startSignal = ValueNotifier(0);

  /// Call once when the user logs in for the first time.
  void start() {
    isActive = true;
    phase = 0;
    startSignal.value++;
  }

  /// Advance phase without triggering the start signal.
  void advanceTo(int next) {
    phase = next;
  }

  /// Called by RoiPage to mark the tutorial as done.
  Future<void> complete() async {
    isActive = false;
    phase = -1;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
  }

  /// Whether the tutorial has already been completed on this device.
  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  /// Resets so the tutorial can be replayed from Settings.
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    instance.isActive = false;
    instance.phase = 0;
  }
}
