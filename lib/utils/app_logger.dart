import 'package:flutter/foundation.dart';

/// Centralized logging utility
/// Provides consistent logging across the application with different log levels
class AppLogger {
  static const String _prefix = '[DeckMaster]';

  /// Log levels
  static const bool _enableDebug = kDebugMode;
  static const bool _enableInfo = true;
  static const bool _enableWarning = true;
  static const bool _enableError = true;

  /// Debug log (only in debug mode)
  static void debug(String message, {String? tag}) {
    if (_enableDebug) {
      final tagPrefix = tag != null ? '[$tag]' : '';
      debugPrint('$_prefix [DEBUG] $tagPrefix $message');
    }
  }

  /// Info log
  static void info(String message, {String? tag}) {
    if (_enableInfo) {
      final tagPrefix = tag != null ? '[$tag]' : '';
      debugPrint('$_prefix [INFO] $tagPrefix $message');
    }
  }

  /// Warning log
  static void warning(String message, {String? tag}) {
    if (_enableWarning) {
      final tagPrefix = tag != null ? '[$tag]' : '';
      debugPrint('$_prefix [WARNING] $tagPrefix $message');
    }
  }

  /// Error log
  static void error(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    if (_enableError) {
      final tagPrefix = tag != null ? '[$tag]' : '';
      debugPrint('$_prefix [ERROR] $tagPrefix $message');
      if (error != null) {
        debugPrint('$_prefix [ERROR] Exception: $error');
      }
      if (stackTrace != null) {
        debugPrint('$_prefix [ERROR] StackTrace: $stackTrace');
      }
    }
  }

  /// Success log
  static void success(String message, {String? tag}) {
    if (_enableInfo) {
      final tagPrefix = tag != null ? '[$tag]' : '';
      debugPrint('$_prefix [SUCCESS] $tagPrefix $message');
    }
  }

  /// Network log
  static void network(String message, {String? tag}) {
    if (_enableDebug) {
      final tagPrefix = tag != null ? '[$tag]' : '';
      debugPrint('$_prefix [NETWORK] $tagPrefix $message');
    }
  }

  /// Database log
  static void database(String message, {String? tag}) {
    if (_enableDebug) {
      final tagPrefix = tag != null ? '[$tag]' : '';
      debugPrint('$_prefix [DATABASE] $tagPrefix $message');
    }
  }

  /// Sync log
  static void sync(String message, {String? tag}) {
    if (_enableDebug) {
      final tagPrefix = tag != null ? '[$tag]' : '';
      debugPrint('$_prefix [SYNC] $tagPrefix $message');
    }
  }

  /// Auth log
  static void auth(String message, {String? tag}) {
    if (_enableDebug) {
      final tagPrefix = tag != null ? '[$tag]' : '';
      debugPrint('$_prefix [AUTH] $tagPrefix $message');
    }
  }
}

/// Extension for easy logging
extension LoggableError on Object {
  void logError({String? message, String? tag}) {
    AppLogger.error(
      message ?? 'An error occurred',
      tag: tag,
      error: this,
      stackTrace: StackTrace.current,
    );
  }
}
