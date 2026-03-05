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
  debugPrint('[FCM] Background message: ${message.messageId}');
}

// ─── NotificationService ──────────────────────────────────────────────────────

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  // ── Inizializzazione (chiamata una volta in main()) ──────────────────────────

  Future<void> initialize() async {
    if (kIsWeb) return;

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

    // Se le notifiche erano abilitate, rinnova il token FCM
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kEnabled) ?? false) {
      await _refreshAndSaveToken();
    }

    // Listener per aggiornamenti del token
    _fcm.onTokenRefresh.listen((token) => _saveTokenToFirestore(token));
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

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, true);
    await _refreshAndSaveToken();
    return true;
  }

  Future<void> disable() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, false);
    await _deleteTokenFromFirestore();
  }

  // ── Sub-preferenze ───────────────────────────────────────────────────────────

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabled) ?? false;
  }

  Future<bool> isAppUpdatesEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAppUpdates) ?? true;
  }

  Future<bool> isCatalogUpdatesEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kCatalogUpdates) ?? true;
  }

  Future<void> setAppUpdates(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAppUpdates, value);
    await _updateFirestorePreferences();
  }

  Future<void> setCatalogUpdates(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCatalogUpdates, value);
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
    } catch (e) {
      debugPrint('[FCM] Token refresh failed: $e');
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
    } catch (e) {
      debugPrint('[FCM] Firestore token save failed: $e');
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
    } catch (e) {
      debugPrint('[FCM] Firestore token delete failed: $e');
    }
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
    } catch (e) {
      debugPrint('[FCM] Preferences update failed: $e');
    }
  }
}
