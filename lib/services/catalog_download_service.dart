import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'background_download_service.dart';
import 'catalog_download_task.dart';
import 'data_repository.dart';

/// Fase corrente del download, per l'etichetta mostrata dalla UI.
enum CatalogDownloadPhase { connecting, downloading, saving }

/// Stato osservabile di un download di catalogo.
@immutable
class CatalogDownloadState {
  const CatalogDownloadState({
    this.isRunning = false,
    this.currentKey,
    this.currentName,
    this.currentIndex = 0,
    this.total = 0,
    this.progress,
    this.phase = CatalogDownloadPhase.connecting,
  });

  /// Vero mentre un download è in corso.
  final bool isRunning;

  /// Catalogo attualmente in scarico (`yugioh`, `pokemon`, …).
  final String? currentKey;

  /// Nome leggibile del catalogo in corso.
  final String? currentName;

  /// Posizione 1-based nella coda.
  final int currentIndex;

  /// Quanti cataloghi compongono questo download.
  final int total;

  /// Avanzamento complessivo 0.0→1.0, `null` finché non arriva il primo dato.
  final double? progress;

  final CatalogDownloadPhase phase;

  static const idle = CatalogDownloadState();

  CatalogDownloadState copyWith({
    bool? isRunning,
    String? currentKey,
    String? currentName,
    int? currentIndex,
    int? total,
    double? progress,
    CatalogDownloadPhase? phase,
  }) =>
      CatalogDownloadState(
        isRunning: isRunning ?? this.isRunning,
        currentKey: currentKey ?? this.currentKey,
        currentName: currentName ?? this.currentName,
        currentIndex: currentIndex ?? this.currentIndex,
        total: total ?? this.total,
        progress: progress ?? this.progress,
        phase: phase ?? this.phase,
      );
}

/// Esito finale di un download, consumato una sola volta dalla UI per mostrare
/// la snackbar. Non fa parte di [CatalogDownloadState] perché è un evento, non
/// uno stato: ripubblicarlo a ogni ricostruzione mostrerebbe la stessa
/// notifica più volte.
@immutable
class CatalogDownloadOutcome {
  const CatalogDownloadOutcome({
    required this.successCount,
    required this.failures,
    required this.isRestore,
  });

  final int successCount;

  /// Nome del catalogo → messaggio d'errore, per i cataloghi non riusciti.
  final Map<String, String> failures;

  /// Vero se l'operazione era un ripristino esplicito e non un aggiornamento.
  final bool isRestore;

  bool get hasFailures => failures.isNotEmpty;
}

/// Etichette già localizzate per la notifica di sistema.
///
/// Il servizio non ha un `BuildContext` — e nella Fase 2 girerà in un isolate
/// separato, dove non ce n'è proprio uno — quindi le stringhe le inietta la UI
/// al momento dell'avvio.
@immutable
class CatalogDownloadLabels {
  const CatalogDownloadLabels({
    required this.notificationTitle,
    required this.starting,
    required this.operationName,
    required this.perCatalog,
    required this.perCatalogPct,
    required this.singlePct,
  });

  final String notificationTitle;
  final String starting;
  final String operationName;

  /// (indice, totale, nome) → "Catalogo 1 di 3 · Yu-Gi-Oh!"
  final String Function(int index, int total, String name) perCatalog;

  /// (indice, totale, nome, percentuale)
  final String Function(int index, int total, String name, int pct) perCatalogPct;

  /// (nome, percentuale) — usato quando c'è un solo catalogo in coda.
  final String Function(String name, int pct) singlePct;
}

/// Possiede il download dei cataloghi, al posto dello `State` di una pagina.
///
/// Prima il ciclo di download viveva dentro `_MainLayoutState` e
/// `_CatalogPageState`: uscire dalla collezione o tornare alla home smontava la
/// pagina, e tutti i callback di progresso finivano su `if (!mounted) return`.
/// Il `Future` continuava a girare — nessuno lo annullava — ma diventava
/// invisibile e irrecuperabile: al rientro la pagina si ricreava senza stato,
/// riproponeva il bottone di download, e premerlo sbatteva contro il lock
/// statico di [DataRepository] con un "download già in corso". Per l'utente era
/// indistinguibile da un'interruzione.
///
/// Qui lo stato vive quanto l'app: qualunque pagina si monti dopo l'avvio si
/// riaggancia leggendo [state] e sottoscrivendo [onStateChanged].
class CatalogDownloadService {
  CatalogDownloadService._internal();
  static final CatalogDownloadService _instance =
      CatalogDownloadService._internal();
  factory CatalogDownloadService() => _instance;

  /// `late`: costruire il servizio non deve toccare Firebase. `DataRepository`
  /// tira dentro `FirestoreService`, che legge `FirebaseFirestore.instance` nel
  /// proprio costruttore — con l'inizializzazione ansiosa bastava nominare il
  /// singleton per far fallire tutto dove Firebase non è inizializzato.
  late final DataRepository _repo = DataRepository();

  final _stateController = StreamController<CatalogDownloadState>.broadcast();
  final _outcomeController = StreamController<CatalogDownloadOutcome>.broadcast();

  CatalogDownloadState _state = CatalogDownloadState.idle;

  /// Stato corrente. Una pagina appena montata parte da qui invece di
  /// ricostruirselo.
  CatalogDownloadState get state => _state;

  /// Emette a ogni avanzamento.
  Stream<CatalogDownloadState> get onStateChanged => _stateController.stream;

  /// Emette una volta a fine download.
  Stream<CatalogDownloadOutcome> get onFinished => _outcomeController.stream;

  /// Throttle degli aggiornamenti alla UI: senza, un catalogo grosso emette
  /// migliaia di eventi al secondo e la ricostruzione dei widget diventa il
  /// collo di bottiglia del download stesso.
  static const _minEmitInterval = Duration(milliseconds: 100);
  DateTime? _lastEmit;

  void _emit(CatalogDownloadState next, {bool force = false}) {
    _state = next;
    final now = DateTime.now();
    if (!force &&
        _lastEmit != null &&
        now.difference(_lastEmit!) < _minEmitInterval) {
      return;
    }
    _lastEmit = now;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  /// Avvia il download dei cataloghi descritti da [updates].
  ///
  /// Ogni voce deve avere `collectionKey` e (opzionalmente) `collectionName`;
  /// il resto viene passato a `downloadCollectionCatalog` come `updateInfo`.
  /// Ritorna subito se un download è già in corso: due download paralleli sullo
  /// stesso database si ostacolerebbero a vicenda.
  Future<void> start({
    required List<Map<String, dynamic>> updates,
    required CatalogDownloadLabels labels,
    bool isRestore = false,
  }) async {
    if (_state.isRunning || updates.isEmpty) return;

    final total = updates.length;
    _lastEmit = null;
    _emit(
      CatalogDownloadState(isRunning: true, total: total),
      force: true,
    );

    if (_usesForegroundService) {
      await _startViaForegroundService(updates, labels, isRestore);
      return;
    }

    BackgroundDownloadService.startingLabel = labels.starting;
    BackgroundDownloadService.notificationTitle = labels.notificationTitle;

    var successCount = 0;
    final failures = <String, String>{};

    try {
      await BackgroundDownloadService.startDownload(labels.operationName);

      for (var i = 0; i < updates.length; i++) {
        final info = updates[i];
        final key = info['collectionKey'] as String;
        final name = info['collectionName'] as String? ?? key;

        _emit(
          _state.copyWith(
            currentKey: key,
            currentName: name,
            currentIndex: i + 1,
            phase: CatalogDownloadPhase.connecting,
          ),
          force: true,
        );
        BackgroundDownloadService.updateStatus(
          total > 1 ? labels.perCatalog(i + 1, total, name) : name,
        );

        try {
          await _repo.downloadCollectionCatalog(
            key,
            updateInfo: info,
            onProgress: (current, colTotal) {
              final pct =
                  colTotal > 0 ? ((current / colTotal) * 100).toInt() : 0;
              BackgroundDownloadService.updateStatus(
                total > 1
                    ? labels.perCatalogPct(i + 1, total, name, pct)
                    : labels.singlePct(name, pct),
              );
              _emit(_state.copyWith(
                progress: colTotal > 0 ? (i + current / colTotal) / total : i / total,
                phase: CatalogDownloadPhase.downloading,
              ));
            },
            onSaveProgress: (progress) {
              _emit(_state.copyWith(
                progress: (i + progress) / total,
                // 0.85 è il punto in cui il download dei chunk finisce e
                // comincia l'aggancio dei prezzi — vedi
                // DataRepository._pricingProgressShare.
                phase: progress >= 0.85
                    ? CatalogDownloadPhase.saving
                    : CatalogDownloadPhase.downloading,
              ));
            },
          );
          successCount++;
        } catch (e) {
          failures[name] = e.toString();
        }
      }
    } finally {
      await BackgroundDownloadService.stopDownload();
      if (successCount > 0 && !isRestore) {
        await _repo.clearPendingCatalogUpdates();
      }
      _emit(CatalogDownloadState.idle, force: true);
      if (!_outcomeController.isClosed) {
        _outcomeController.add(CatalogDownloadOutcome(
          successCount: successCount,
          failures: failures,
          isRestore: isRestore,
        ));
      }
    }
  }

  // ── Foreground service (solo Android) ──────────────────────────────────────

  /// Su Android il download gira dentro un foreground service, in un isolate
  /// separato che sopravvive alla chiusura dell'app.
  ///
  /// Altrove si resta in-process: iOS non ha un equivalente, e su Windows/Web
  /// il problema non si pone perché il processo non viene congelato.
  static bool get _usesForegroundService =>
      !kIsWeb && Platform.isAndroid;

  bool _serviceInitialized = false;
  bool _callbackRegistered = false;
  bool _isRestoreRun = false;

  Future<void> _startViaForegroundService(
    List<Map<String, dynamic>> updates,
    CatalogDownloadLabels labels,
    bool isRestore,
  ) async {
    _isRestoreRun = isRestore;

    if (!_callbackRegistered) {
      FlutterForegroundTask.addTaskDataCallback(_onTaskData);
      _callbackRegistered = true;
    }

    if (!_serviceInitialized) {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'deck_master_catalog_download',
          channelName: labels.notificationTitle,
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
          onlyAlertOnce: true,
          playSound: false,
          enableVibration: false,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          // Il download è guidato da onStart, non da un timer periodico.
          eventAction: ForegroundTaskEventAction.nothing(),
          // Il wake lock qui è quello vero, sulla CPU: WakelockPlus tiene
          // acceso lo schermo e vale solo con l'activity visibile.
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
      _serviceInitialized = true;
    }

    // Android 13+: senza permesso notifiche il servizio non può mostrare la
    // propria notifica, e senza notifica non può restare in foreground.
    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    // La coda passa dallo storage del plugin: è l'unico canale disponibile
    // prima che l'isolate di servizio esista, e accetta solo primitivi.
    await FlutterForegroundTask.saveData(
      key: CatalogTaskKeys.queue,
      value: jsonEncode(updates),
    );
    await FlutterForegroundTask.saveData(
      key: CatalogTaskKeys.labels,
      value: jsonEncode({'title': labels.notificationTitle}),
    );

    final result = await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.dataSync],
      notificationTitle: labels.notificationTitle,
      notificationText: labels.starting,
      callback: startCatalogDownloadTask,
    );

    if (result is ServiceRequestFailure) {
      debugPrint('[catalog-dl] avvio servizio fallito: ${result.error}');
      _emit(CatalogDownloadState.idle, force: true);
      _outcomeController.add(CatalogDownloadOutcome(
        successCount: 0,
        failures: {'': result.error.toString()},
        isRestore: isRestore,
      ));
    }
  }

  /// Riceve gli aggiornamenti dall'isolate di servizio.
  void _onTaskData(Object data) {
    if (data is! Map) return;
    final map = Map<String, dynamic>.from(data);

    if (map[CatalogTaskKeys.type] == CatalogTaskKeys.typeProgress) {
      _emit(
        CatalogDownloadState(
          isRunning: true,
          currentKey: map[CatalogTaskKeys.currentKey] as String?,
          currentName: map[CatalogTaskKeys.currentName] as String?,
          currentIndex: (map[CatalogTaskKeys.currentIndex] as num?)?.toInt() ?? 0,
          total: (map[CatalogTaskKeys.total] as num?)?.toInt() ?? 0,
          progress: (map[CatalogTaskKeys.progress] as num?)?.toDouble(),
          phase: switch (map[CatalogTaskKeys.phase]) {
            'downloading' => CatalogDownloadPhase.downloading,
            'saving' => CatalogDownloadPhase.saving,
            _ => CatalogDownloadPhase.connecting,
          },
        ),
        force: map[CatalogTaskKeys.progress] == null,
      );
      return;
    }

    if (map[CatalogTaskKeys.type] == CatalogTaskKeys.typeFinished) {
      _emit(CatalogDownloadState.idle, force: true);
      Map<String, String> failures = const {};
      final raw = map[CatalogTaskKeys.failures];
      if (raw is String && raw.isNotEmpty) {
        try {
          failures = Map<String, String>.from(jsonDecode(raw) as Map);
        } catch (_) {}
      }
      if (!_outcomeController.isClosed) {
        _outcomeController.add(CatalogDownloadOutcome(
          successCount: (map[CatalogTaskKeys.successCount] as num?)?.toInt() ?? 0,
          failures: failures,
          isRestore: _isRestoreRun,
        ));
      }
    }
  }

  /// Solo per i test: riporta il servizio allo stato iniziale.
  @visibleForTesting
  void debugReset() {
    _state = CatalogDownloadState.idle;
    _lastEmit = null;
  }
}
