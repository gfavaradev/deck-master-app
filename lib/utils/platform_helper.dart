import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

/// Helper class to check platform-specific features and capabilities
class PlatformHelper {
  // Platform checks
  static bool get isWeb => kIsWeb;
  static bool get isMobile => !kIsWeb && (Platform.isIOS || Platform.isAndroid);
  static bool get isDesktop => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;
  static bool get isLinux => !kIsWeb && Platform.isLinux;
  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  // Feature support checks
  static bool get supportsFacebookAuth => !kIsWeb && (Platform.isIOS || Platform.isAndroid);
  static bool get supportsAppleSignIn => !kIsWeb && (Platform.isIOS || Platform.isMacOS);
  static bool get supportsGoogleSignIn => true; // Supported on all platforms

  // Mobile-specific features
  static bool get supportsBiometrics => !kIsWeb && (Platform.isIOS || Platform.isAndroid);
  static bool get supportsPushNotifications => !kIsWeb && (Platform.isIOS || Platform.isAndroid);
  static bool get supportsCamera => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  // Desktop-specific features
  static bool get supportsFileSystem => !kIsWeb;
  static bool get supportsMultipleWindows => isDesktop;

  /// Get a human-readable platform name
  static String get platformName {
    if (kIsWeb) return 'Web';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isAndroid) return 'Android';
    return 'Unknown';
  }

  /// Check if running on a specific platform
  static bool isPlatform(String platform) {
    if (kIsWeb) return platform.toLowerCase() == 'web';
    return Platform.operatingSystem.toLowerCase() == platform.toLowerCase();
  }

  /// Get platform-specific configuration
  static T platformValue<T>({
    T? windows,
    T? macos,
    T? linux,
    T? android,
    T? ios,
    T? web,
    required T fallback,
  }) {
    if (kIsWeb && web != null) return web;
    if (!kIsWeb) {
      if (Platform.isWindows && windows != null) return windows;
      if (Platform.isMacOS && macos != null) return macos;
      if (Platform.isLinux && linux != null) return linux;
      if (Platform.isAndroid && android != null) return android;
      if (Platform.isIOS && ios != null) return ios;
    }
    return fallback;
  }

  /// Get adaptive padding based on platform
  static double get defaultPadding {
    return platformValue(
      windows: 16.0,
      macos: 20.0,
      linux: 16.0,
      android: 16.0,
      ios: 20.0,
      web: 24.0,
      fallback: 16.0,
    );
  }

  /// Get adaptive button height based on platform
  static double get defaultButtonHeight {
    return platformValue(
      windows: 40.0,
      macos: 36.0,
      linux: 40.0,
      android: 48.0,
      ios: 44.0,
      web: 48.0,
      fallback: 44.0,
    );
  }
}
