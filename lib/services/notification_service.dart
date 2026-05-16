import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

// SharedPreferences keys
const _kEnabled = 'notifications_enabled';
const _kAppUpdates = 'notif_app_updates';
const _kCatalogUpdates = 'notif_catalog_updates';

// ─── Background message handler (top-level, richiesto da FCM) ─────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Non serve fare nulla qui — FCM su Android mostra la notifica automaticamente
  // se c'è un campo "notification" nel payload. Per payload data-only, elaborare qui.

}

// ─── NotificationService ──────────────────────────────────────────────────────

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  SharedPreferences? _prefs;

  // ── Inizializzazione (chiamata una volta in main()) ──────────────────────────

  Future<void> initialize() async {
    if (kIsWeb) return;

    // Pre-carica le SharedPreferences per evitare await ripetuti in seguito
    _prefs = await SharedPreferences.getInstance();

    // Registra handler per messaggi in background
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Configura canale Android per notifiche foreground
    const channel = AndroidNotificationChannel(
      'deck_master_push',
      'Notifiche Deck Master',
      description: 'Aggiornamenti app e catalogo',
      importance: Importance.high,
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Inizializza flutter_local_notifications per mostrare notifiche in foreground
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _local.initialize(settings: initSettings);

    // Mostra notifiche FCM quando l'app è in foreground
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      _local.show(
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'deck_master_push',
            'Notifiche Deck Master',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    });

    // Se le notifiche erano abilitate, rinnova il token FCM.
    // Nota: questo può fallire silenziosamente se l'auth non è ancora pronta
    // (caso tipico dopo un aggiornamento app). Il listener sotto copre quel caso.
    if (_prefs?.getBool(_kEnabled) ?? false) {
      _refreshAndSaveToken();
    }

    // Listener token refresh: salva subito il nuovo token. Può arrivare prima
    // che l'auth sia pronta (es. dopo aggiornamento app) — in quel caso
    // _saveTokenToFirestore ritorna early ma il listener authStateChanges
    // recupera non appena l'utente si autentica.
    _fcm.onTokenRefresh.listen((token) => _saveTokenToFirestore(token));

    // Dopo ogni login (incluso il restore della sessione all'avvio post-update)
    // ri-sincronizza il token FCM se le notifiche sono abilitate.
    // Questo garantisce che un token rigenerato durante l'update venga sempre
    // scritto su Firestore, indipendentemente dalla race condition auth vs FCM.
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && (_prefs?.getBool(_kEnabled) ?? false)) {
        _refreshAndSaveToken();
      }
    });
  }

  // ── Permesso ─────────────────────────────────────────────────────────────────

  /// Richiede il permesso FCM all'utente.
  /// Ritorna true se concesso, false altrimenti.
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;

    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  // ── Abilitazione / Disabilitazione ───────────────────────────────────────────

  Future<bool> enable() async {
    if (kIsWeb) return false;
    final granted = await requestPermission();
    if (!granted) return false;

    await _getPrefs().then((p) => p.setBool(_kEnabled, true));
    await _refreshAndSaveToken();
    return true;
  }

  Future<void> disable() async {
    if (kIsWeb) return;
    await _getPrefs().then((p) => p.setBool(_kEnabled, false));
    await _deleteTokenFromFirestore();
  }

  // ── Sub-preferenze ───────────────────────────────────────────────────────────

  /// Helper interno per ottenere le preferenze garantendo l'inizializzazione
  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<bool> isEnabled() async {
    return (await _getPrefs()).getBool(_kEnabled) ?? false;
  }

  Future<bool> isAppUpdatesEnabled() async {
    return (await _getPrefs()).getBool(_kAppUpdates) ?? true;
  }

  Future<bool> isCatalogUpdatesEnabled() async {
    return (await _getPrefs()).getBool(_kCatalogUpdates) ?? true;
  }

  Future<void> setAppUpdates(bool value) async {
    await (await _getPrefs()).setBool(_kAppUpdates, value);
    await _updateFirestorePreferences();
  }

  Future<void> setCatalogUpdates(bool value) async {
    await (await _getPrefs()).setBool(_kCatalogUpdates, value);
    await _updateFirestorePreferences();
  }

  // ── Token management ─────────────────────────────────────────────────────────

  Future<void> _refreshAndSaveToken() async {
    try {
      // Su iOS serve APNS token prima di poter ottenere FCM token
      if (!kIsWeb && Platform.isIOS) {
        await _fcm.getAPNSToken();
      }
      final token = await _fcm.getToken();
      if (token != null) await _saveTokenToFirestore(token);
    } catch (e) { // ignore: empty_catches

    }
  }

  Future<void> _saveTokenToFirestore(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'fcmToken': token, 'notificationsEnabled': true},
        SetOptions(merge: true),
      );
    } catch (e) { // ignore: empty_catches

    }
  }

  Future<void> _deleteTokenFromFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _fcm.deleteToken();
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'fcmToken': FieldValue.delete(), 'notificationsEnabled': false},
        SetOptions(merge: true),
      );
    } catch (e) { // ignore: empty_catches

    }
  }

  // ── Notifiche locali catalogo ─────────────────────────────────────────────────

  static const int _catalogUpdateNotifId = 2001;
  static const int _catalogReminderNotifId = 2002;
  static const String _catalogChannel = 'catalog_updates';

  Future<void> _ensureCatalogChannel() async {
    if (kIsWeb) return;
    const channel = AndroidNotificationChannel(
      _catalogChannel,
      'Aggiornamenti Catalogo',
      description: 'Notifiche per nuovi aggiornamenti del catalogo carte',
      importance: Importance.defaultImportance,
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  static const String _kPendingCatalogReminder = 'notif_pending_catalog_reminder';
  static const String _kPendingCatalogCollection = 'notif_pending_catalog_collection';
  static const String _kPendingCatalogKey = 'notif_pending_catalog_key';

  /// Returns the collection key saved when user tapped "Più tardi".
  /// Returns null if no navigation is pending.
  Future<String?> getPendingCatalogNavigation() async {
    final prefs = await _getPrefs();
    return prefs.getString(_kPendingCatalogKey);
  }

  /// Clears the pending navigation intent.
  Future<void> clearPendingCatalogNavigation() async {
    final prefs = await _getPrefs();
    await prefs.remove(_kPendingCatalogKey);
  }

  /// Mostra una notifica locale che un aggiornamento del catalogo è disponibile.
  Future<void> showCatalogUpdateAvailable({
    required String collectionName,
    String? sizeMb,
  }) async {
    if (kIsWeb) return;
    await _ensureCatalogChannel();
    final body = sizeMb != null
        ? 'Nuovo aggiornamento disponibile (${sizeMb}MB). Apri l\'app per scaricarlo.'
        : 'Nuovo aggiornamento disponibile. Apri l\'app per scaricarlo.';
    await _local.show(
      id: _catalogUpdateNotifId,
      title: 'Catalogo $collectionName aggiornato',
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _catalogChannel,
          'Aggiornamenti Catalogo',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  /// Salva un reminder pending: al prossimo avvio dell'app viene mostrata la notifica.
  Future<void> scheduleCatalogUpdateReminder({
    required String collectionName,
    String? collectionKey,
  }) async {
    if (kIsWeb) return;
    final prefs = await _getPrefs();
    await prefs.setBool(_kPendingCatalogReminder, true);
    await prefs.setString(_kPendingCatalogCollection, collectionName);
    if (collectionKey != null) {
      await prefs.setString(_kPendingCatalogKey, collectionKey);
    }
  }

  /// Mostra il reminder se era in attesa (chiamare all'avvio dell'app).
  Future<void> checkAndShowPendingCatalogReminder() async {
    if (kIsWeb) return;
    final prefs = await _getPrefs();
    final pending = prefs.getBool(_kPendingCatalogReminder) ?? false;
    if (!pending) return;
    final collection = prefs.getString(_kPendingCatalogCollection) ?? 'catalogo';
    await prefs.remove(_kPendingCatalogReminder);
    await prefs.remove(_kPendingCatalogCollection);
    await _ensureCatalogChannel();
    await _local.show(
      id: _catalogReminderNotifId,
      title: 'Aggiornamento catalogo in attesa',
      body: 'Il catalogo $collection ha un aggiornamento disponibile. Apri l\'app per scaricarlo.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _catalogChannel,
          'Aggiornamenti Catalogo',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  /// Cancella il reminder per l'aggiornamento catalogo.
  Future<void> cancelCatalogReminder() async {
    if (kIsWeb) return;
    final prefs = await _getPrefs();
    await prefs.remove(_kPendingCatalogReminder);
    await prefs.remove(_kPendingCatalogCollection);
    await _local.cancel(id: _catalogReminderNotifId);
    await _local.cancel(id: _catalogUpdateNotifId);
  }

  // ── Notifiche prezzi CardTrader ───────────────────────────────────────────────

  static const int _pricesSyncedNotifId = 2003;
  static const String _pricesSyncChannel = 'price_updates';

  /// Mostra una notifica locale quando i prezzi CardTrader vengono aggiornati.
  /// Da chiamare solo per utenti con la collezione sbloccata.
  Future<void> showPricesSyncedNotification({
    required String collectionName,
    required int updatedCount,
  }) async {
    if (kIsWeb) return;
    const channel = AndroidNotificationChannel(
      _pricesSyncChannel,
      'Prezzi di Mercato',
      description: 'Notifiche aggiornamento valori CardTrader',
      importance: Importance.defaultImportance,
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _local.show(
      id: _pricesSyncedNotifId,
      title: 'Valori di mercato aggiornati',
      body: '$updatedCount carte di $collectionName hanno nuovi prezzi CardTrader.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _pricesSyncChannel,
          'Prezzi di Mercato',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> _updateFirestorePreferences() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final appUpdates = await isAppUpdatesEnabled();
    final catalogUpdates = await isCatalogUpdatesEnabled();
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'notifPreferences': {
            'appUpdates': appUpdates,
            'catalogUpdates': catalogUpdates,
          }
        },
        SetOptions(merge: true),
      );
    } catch (e) { // ignore: empty_catches

    }
  }
}
