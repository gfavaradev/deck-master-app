import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../utils/app_logger.dart';
import 'database_helper.dart';
import 'price_repository.dart';

/// Sincronizza i prezzi da Realtime Database verso SQLite — un solo percorso
/// per tutti i 13 cataloghi. Vedi `REQUIREMENTS_prices_unified.md`.
///
/// Il costo di un controllo è **una lettura da ~200 byte** (`/v`), non 13 read
/// su documenti che per 10 cataloghi su 13 non esistono nemmeno, come nel
/// vecchio percorso Firestore. Il costo di un aggiornamento è proporzionale ai
/// set effettivamente cambiati, non all'intero listino: era il difetto per cui
/// un refresh Yu-Gi-Oh scaricava 626 chunk e ~70 MB per utente.
class PriceSyncService {
  static const _versionKeyPrefix = 'rtdb_price_version_';

  final PriceRepository _repo;
  final DatabaseHelper _db;

  PriceSyncService({PriceRepository? repository, DatabaseHelper? database})
      : _repo = repository ?? PriceRepository(),
        _db = database ?? DatabaseHelper();

  /// Cataloghi per cui ha senso scaricare prezzi: quelli di cui l'utente ha
  /// effettivamente il catalogo in locale. Scaricare i prezzi di un gioco che
  /// non colleziona sarebbe traffico buttato.
  Future<List<String>> _activeCatalogs() async {
    final active = <String>[];
    for (final catalog in CatalogConstants.allCatalogs) {
      try {
        if (await _db.getCatalogCardCount(catalog) > 0) active.add(catalog);
      } catch (_) {
        // Un catalogo le cui tabelle non esistono ancora non è un errore:
        // semplicemente non è stato scaricato.
      }
    }
    return active;
  }

  /// Esegue un ciclo di sincronizzazione. Restituisce il numero di set aggiornati.
  ///
  /// [onlyCatalogs], se passato, restringe il lavoro (usato dai test e da un
  /// eventuale refresh mirato).
  Future<int> syncPrices({List<String>? onlyCatalogs}) async {
    final versions = await _repo.fetchVersions();
    if (versions.isEmpty) return 0;

    final prefs = await SharedPreferences.getInstance();
    final catalogs = onlyCatalogs ?? await _activeCatalogs();
    var updatedSets = 0;

    for (final catalog in catalogs) {
      final remote = versions[catalog];
      if (remote == null) continue;

      final localKey = '$_versionKeyPrefix$catalog';
      final local = prefs.getInt(localKey);
      if (local != null && local >= remote) continue;

      try {
        updatedSets += await _syncCatalog(catalog);
        // Il timestamp si scrive SOLO a sincronizzazione riuscita: se il
        // download muore a metà, il prossimo avvio riprende invece di dare per
        // aggiornato ciò che non lo è.
        await prefs.setInt(localKey, remote);
      } catch (e) {
        AppLogger.error('sync prezzi $catalog fallito',
            tag: 'PriceSyncService', error: e);
      }
    }
    return updatedSets;
  }

  /// Scarica i set cambiati di un catalogo, uno alla volta.
  ///
  /// Un set per volta è deliberato: mai una lettura su `/p/{cat}/s`, che
  /// cresce senza limite. È la stessa regola che vale per Firestore dopo
  /// l'OOM della 1.3.9 — le regole in `database.rules.json` la impongono anche
  /// lato server.
  Future<int> _syncCatalog(String catalog) async {
    final index = await _repo.fetchIndex(catalog);
    if (index == null) return 0;

    final localVersions = await _db.getPriceSetVersions(catalog);
    final toFetch = index.setsToFetch(localVersions, const {});
    if (toFetch.isEmpty) return 0;

    var done = 0;
    for (final setCode in toFetch) {
      final rows = await _repo.fetchSet(catalog, setCode);
      if (rows.isEmpty) continue;
      await _db.replaceSetPrices(
        catalog,
        setCode,
        rows.map((r) => r.toMap()).toList(),
      );
      await _db.setPriceSetVersion(
        catalog,
        setCode,
        index.setVersions[setCode] ?? 0,
      );
      done++;
    }
    AppLogger.info(
      'prezzi $catalog: $done/${toFetch.length} set aggiornati',
      tag: 'PriceSyncService',
    );
    return done;
  }
}
