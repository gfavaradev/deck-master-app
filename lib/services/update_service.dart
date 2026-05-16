import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';

/// Informazioni sull'aggiornamento disponibile.
class UpdateInfo {
  final String currentVersion;
  final String latestVersion;

  /// Se true l'utente è sotto la versione minima e non può usare l'app.
  final bool isForced;

  final String androidUrl;
  final String windowsUrl;
  final String releaseNotes;

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.isForced,
    required this.androidUrl,
    required this.windowsUrl,
    required this.releaseNotes,
  });

  /// URL corretto per la piattaforma corrente.
  String get storeUrl {
    if (!kIsWeb && Platform.isAndroid) return androidUrl;
    if (!kIsWeb && Platform.isWindows) return windowsUrl;
    return androidUrl; // fallback
  }
}

class UpdateService {
  static const _docPath = 'app_config/version';
  static const _lastCheckKey = 'update_last_check_at';
  // Controlla al massimo una volta ogni 6 ore per non sprecare letture Firestore
  static const _checkCooldown = Duration(hours: 6);

  /// Controlla se è disponibile un aggiornamento.
  ///
  /// Ritorna [UpdateInfo] se c'è un update da mostrare, altrimenti null.
  /// [force] bypassa il cooldown (utile dal menu impostazioni).
  static Future<UpdateInfo?> checkForUpdate({bool force = false}) async {
    // Web non ha store, skip
    if (kIsWeb) return null;

    try {
      if (!force) {
        final prefs = await SharedPreferences.getInstance();
        final lastStr = prefs.getString(_lastCheckKey);
        if (lastStr != null) {
          final last = DateTime.tryParse(lastStr);
          if (last != null && DateTime.now().difference(last) < _checkCooldown) return null;
        }
      }

      final doc = await FirebaseFirestore.instance
          .doc(_docPath)
          .get()
          .timeout(const Duration(seconds: 8));

      // Salva il timestamp del check indipendentemente dall'esito
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastCheckKey, DateTime.now().toIso8601String());

      if (!doc.exists || doc.data() == null) return null;
      final data = doc.data()!;

      final latestVersion  = (data['latestVersion']  as String?)?.trim() ?? '';
      final minVersion     = (data['minVersion']      as String?)?.trim() ?? '1.0.0';
      final forceOverride  = data['forceUpdate']      as bool? ?? false;
      final androidUrl     = (data['androidUrl']      as String?)?.trim() ?? '';
      final windowsUrl     = (data['windowsUrl']      as String?)?.trim() ?? '';
      final releaseNotes   = (data['releaseNotes']    as String?)?.trim() ?? '';

      if (latestVersion.isEmpty) return null;

      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;

      final updateAvailable = _isNewer(latestVersion, currentVersion);
      final belowMin        = _isNewer(minVersion, currentVersion);

      if (!updateAvailable && !belowMin && !forceOverride) return null;

      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion:  latestVersion,
        isForced:       forceOverride || belowMin,
        androidUrl:     androidUrl,
        windowsUrl:     windowsUrl,
        releaseNotes:   releaseNotes,
      );
    } catch (e) {
      AppLogger.warning('checkForUpdate failed (offline?)', tag: 'UpdateService');
      return null;
    }
  }

  /// Ritorna true se [a] è strettamente più recente di [b] (confronto semver).
  static bool _isNewer(String a, String b) {
    final aParts = _parts(a);
    final bParts = _parts(b);
    for (int i = 0; i < 3; i++) {
      if (aParts[i] > bParts[i]) return true;
      if (aParts[i] < bParts[i]) return false;
    }
    return false;
  }

  static List<int> _parts(String version) {
    final clean = version.split('+').first;
    final parts = clean.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    while (parts.length < 3) { parts.add(0); }
    return parts;
  }
}
