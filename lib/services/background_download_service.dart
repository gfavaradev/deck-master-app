import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ─── Costanti ────────────────────────────────────────────────────────────────

const _channelId = 'deck_master_download';
const _channelName = 'Download Catalogo';
const _notificationId = 888;

// ─── Entry point del servizio (gira in un isolato separato) ──────────────────
//
// Non esegue il download — viene già eseguito nell'isolato principale.
// Il suo unico scopo è mantenere vivo il processo Android mostrando
// una notifica persistente (Foreground Service).

@pragma('vm:entry-point')
void _onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Rimane in ascolto del comando "stop" inviato dall'isolato principale
  service.on('stop').listen((_) => service.stopSelf());

  // Aggiorna il testo della notifica quando arriva un aggiornamento di stato
  service.on('update').listen((data) {
    if (data == null) return;
    service.invoke('setNotificationInfo', {
      'title': 'Deck Master — Download',
      'content': data['status'] ?? 'Operazione in corso...',
    });
  });
}

// ─── Helper pubblico usato dall'UI ───────────────────────────────────────────

class BackgroundDownloadService {
  static final _service = FlutterBackgroundService();
  static bool _initialized = false;

  /// Inizializza il canale notifiche e configura il servizio.
  /// Va chiamato una sola volta in main() prima di runApp.
  static Future<void> initialize() async {
    if (kIsWeb || _initialized) return;

    // Crea il canale notifiche Android
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Mostra il progresso del download del catalogo in background',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    );

    final notifications = FlutterLocalNotificationsPlugin();
    await notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onServiceStart,
        isForegroundMode: true,
        autoStart: false,
        notificationChannelId: _channelId,
        initialNotificationTitle: 'Deck Master',
        initialNotificationContent: 'Download in corso...',
        foregroundServiceNotificationId: _notificationId,
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );

    _initialized = true;
  }

  /// Avvia il Foreground Service prima di iniziare un download.
  /// Il download reale gira nell'isolato principale (nessuna modifica al codice esistente).
  static Future<void> startDownload(String operationName) async {
    if (kIsWeb) return;
    await _service.startService();
  }

  /// Aggiorna il testo della notifica con il progresso corrente.
  static void updateStatus(String status) {
    if (kIsWeb) return;
    _service.invoke('update', {'status': status});
  }

  /// Ferma il Foreground Service al termine del download.
  static Future<void> stopDownload() async {
    if (kIsWeb) return;
    _service.invoke('stop');
  }
}
