import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const _channelId = 'deck_master_download';
const _channelName = 'Download Catalogo';
const _notificationId = 888;

/// Shows a persistent progress notification during long admin downloads.
/// Runs entirely in the main isolate — no background service needed.
class BackgroundDownloadService {
  static final _notifications = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Call once in main() before runApp.
  static Future<void> initialize() async {
    if (!_isMobile || _initialized) return;
    try {
      await _notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );

      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              description: 'Progresso download catalogo',
              importance: Importance.low,
              playSound: false,
              enableVibration: false,
            ),
          );

      _initialized = true;
    } catch (_) {}
  }

  /// Shows the progress notification.
  static Future<void> startDownload(String operationName) async {
    if (!_isMobile) return;
    await _show(operationName, 'Avvio...');
  }

  /// Updates the notification text.
  static void updateStatus(String status) {
    if (!_isMobile) return;
    _show('Deck Master — Download', status);
  }

  /// Cancels the notification.
  static Future<void> stopDownload() async {
    if (!_isMobile) return;
    try {
      await _notifications.cancel(id: _notificationId);
    } catch (_) {}
  }

  static Future<void> _show(String title, String body) async {
    try {
      await _notifications.show(
        id: _notificationId,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Progresso download catalogo',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            showProgress: true,
            indeterminate: true,
            playSound: false,
            enableVibration: false,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    } catch (_) {}
  }
}
