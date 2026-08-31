import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../firebase_options.dart';
import 'data_repository.dart';

/// Chiavi dello scambio dati fra isolate principale e isolate di servizio.
///
/// `FlutterForegroundTask.saveData` è l'unico canale disponibile prima che il
/// task parta, e accetta solo tipi primitivi: la coda viaggia come JSON.
class CatalogTaskKeys {
  CatalogTaskKeys._();

  /// Coda dei cataloghi da scaricare, serializzata.
  static const queue = 'catalog_dl_queue';

  /// Etichette già localizzate per la notifica.
  static const labels = 'catalog_dl_labels';

  // ── Campi dei messaggi verso l'isolate principale ────────────────────────
  static const type = 'type';
  static const typeProgress = 'progress';
  static const typeFinished = 'finished';
  static const currentKey = 'key';
  static const currentName = 'name';
  static const currentIndex = 'index';
  static const total = 'total';
  static const progress = 'progress';
  static const phase = 'phase';
  static const successCount = 'successCount';
  static const failures = 'failures';
}

/// Punto d'ingresso dell'isolate di servizio.
///
/// `vm:entry-point` è obbligatorio: senza, il tree-shaking dell'AOT rimuove la
/// funzione e il servizio parte su un riferimento nullo in release, mentre in
/// debug sembra funzionare.
@pragma('vm:entry-point')
void startCatalogDownloadTask() {
  FlutterForegroundTask.setTaskHandler(CatalogDownloadTaskHandler());
}

/// Esegue il download del catalogo dentro il foreground service.
///
/// Gira in un isolate **separato** da quello della UI, con il proprio
/// `FlutterEngine` e il proprio registrant dei plugin: niente di ciò che
/// `main()` ha inizializzato è visibile qui, e va rifatto in [onStart].
class CatalogDownloadTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      await _initFirebase();
    } catch (e) {
      debugPrint('[catalog-task] init Firebase fallita: $e');
      _sendFinished(0, {'': e.toString()});
      await FlutterForegroundTask.stopService();
      return;
    }

    final rawQueue = FlutterForegroundTask.getData<String>(key: CatalogTaskKeys.queue);
    final queue = _decodeQueue(await rawQueue);
    if (queue.isEmpty) {
      _sendFinished(0, const {});
      await FlutterForegroundTask.stopService();
      return;
    }

    final labels = _decodeLabels(
      await FlutterForegroundTask.getData<String>(key: CatalogTaskKeys.labels),
    );

    await _runQueue(queue, labels);
    await FlutterForegroundTask.stopService();
  }

  /// Firebase, App Check e le impostazioni Firestore vanno rifatti qui.
  ///
  /// App Check in particolare: l'enforcement è attivo su Firestore, e senza
  /// attivazione in **questo** isolate ogni lettura viene rifiutata. Con la
  /// persistence disabilitata quella lettura non ritorna e non lancia — resta
  /// appesa — quindi il download si pianterebbe senza un solo errore nei log.
  Future<void> _initFirebase() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleAppAttestProvider(),
    );
    FirebaseFirestore.instance.settings =
        const Settings(persistenceEnabled: false);
  }

  Future<void> _runQueue(
    List<Map<String, dynamic>> queue,
    Map<String, String> labels,
  ) async {
    final repo = DataRepository();
    final total = queue.length;
    var successCount = 0;
    final failures = <String, String>{};

    for (var i = 0; i < queue.length; i++) {
      final info = queue[i];
      final key = info['collectionKey'] as String;
      final name = info['collectionName'] as String? ?? key;

      _sendProgress(key, name, i + 1, total, null, 'connecting');
      _updateNotification(labels, name, null);

      try {
        await repo.downloadCollectionCatalog(
          key,
          updateInfo: info,
          onProgress: (current, colTotal) {
            final p = colTotal > 0 ? (i + current / colTotal) / total : i / total;
            _sendProgress(key, name, i + 1, total, p, 'downloading');
            _updateNotification(labels, name,
                colTotal > 0 ? ((current / colTotal) * 100).toInt() : null);
          },
          onSaveProgress: (progress) {
            _sendProgress(key, name, i + 1, total, (i + progress) / total,
                progress >= 0.85 ? 'saving' : 'downloading');
          },
        );
        successCount++;
      } catch (e) {
        failures[name] = e.toString();
      }
    }

    if (successCount > 0) {
      try {
        await repo.clearPendingCatalogUpdates();
      } catch (_) {}
    }
    _sendFinished(successCount, failures);
  }

  // ── Comunicazione verso l'isolate principale ──────────────────────────────

  DateTime? _lastSend;

  void _sendProgress(String key, String name, int index, int total,
      double? progress, String phase) {
    // Throttle: senza, un catalogo grosso inonda la porta di comunicazione e
    // la ricostruzione dei widget diventa il collo di bottiglia del download.
    final now = DateTime.now();
    final isPhaseStart = progress == null;
    if (!isPhaseStart &&
        _lastSend != null &&
        now.difference(_lastSend!).inMilliseconds < 200) {
      return;
    }
    _lastSend = now;
    FlutterForegroundTask.sendDataToMain({
      CatalogTaskKeys.type: CatalogTaskKeys.typeProgress,
      CatalogTaskKeys.currentKey: key,
      CatalogTaskKeys.currentName: name,
      CatalogTaskKeys.currentIndex: index,
      CatalogTaskKeys.total: total,
      CatalogTaskKeys.progress: progress,
      CatalogTaskKeys.phase: phase,
    });
  }

  void _sendFinished(int successCount, Map<String, String> failures) {
    FlutterForegroundTask.sendDataToMain({
      CatalogTaskKeys.type: CatalogTaskKeys.typeFinished,
      CatalogTaskKeys.successCount: successCount,
      CatalogTaskKeys.failures: jsonEncode(failures),
    });
  }

  void _updateNotification(
      Map<String, String> labels, String name, int? pct) {
    FlutterForegroundTask.updateService(
      notificationTitle: labels['title'] ?? name,
      notificationText: pct == null ? name : '$name — $pct%',
    );
  }

  // ── Decodifica dei parametri ──────────────────────────────────────────────

  List<Map<String, dynamic>> _decodeQueue(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      debugPrint('[catalog-task] coda illeggibile: $e');
      return const [];
    }
  }

  Map<String, String> _decodeLabels(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return const {};
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Il download è guidato da onStart, non da un timer: qui non serve nulla.
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    if (isTimeout) {
      debugPrint('[catalog-task] servizio terminato per timeout di sistema');
    }
  }
}
