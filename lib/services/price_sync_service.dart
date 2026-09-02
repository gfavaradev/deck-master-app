import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../utils/app_logger.dart';
import 'cardtrader_service.dart';
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

      try {
        if (local == null || local < remote) {
          updatedSets += await _syncCatalog(catalog);
          // Il timestamp si scrive SOLO a sincronizzazione riuscita: se il
          // download muore a metà, il prossimo avvio riprende invece di dare
          // per aggiornato ciò che non lo è.
          await prefs.setInt(localKey, remote);
        }
      } catch (e) {
        AppLogger.error('sync prezzi $catalog fallito',
            tag: 'PriceSyncService', error: e);
      }

      // Fuori dal gate di versione, e di proposito: il valore di una carta va
      // scritto anche quando i prezzi non sono cambiati, perché a cambiare può
      // essere la collezione. Legandolo al bump di versione, una carta aggiunta
      // dopo l'ultimo sync restava a `cardtrader_value` nullo per sempre — il
      // prezzo compariva nella riga (che lo cerca al volo) ma il totale della
      // collezione lo ignorava. Costa una passata sulle carte possedute.
      try {
        await updateCollectionValues(catalog);
      } catch (e) {
        AppLogger.error('valori collezione $catalog falliti',
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

    // Solo i set di cui l'utente possiede almeno una carta: su Yu-Gi-Oh sono
    // una manciata invece di 490, e il costo del sync diventa proporzionale
    // alla collezione, non al catalogo.
    var wanted = await _db.getOwnedSetCodes(catalog);
    // Se nessuno dei set posseduti compare nell'indice, il criterio è sbagliato
    // (seriali di un catalogo vecchio, codici che non combaciano): meglio
    // scaricare tutto che lasciare la collezione senza prezzi.
    if (wanted.isNotEmpty && !wanted.any(index.setVersions.containsKey)) {
      AppLogger.info(
        'prezzi $catalog: nessun set posseduto riconosciuto, scarico tutto',
        tag: 'PriceSyncService',
      );
      wanted = const {};
    }

    final localVersions = await _db.getPriceSetVersions(catalog);
    final toFetch = index.setsToFetch(localVersions, wanted);
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

  /// Ricalcola `cardtrader_value` per le carte in collezione di [catalog].
  ///
  /// Itera **le carte dell'utente** (centinaia) risolvendone la stampa, invece
  /// di aggiornare in blocco le tabelle di stampa del catalogo — 44.000 righe
  /// per il solo Yu-Gi-Oh, con passate per lingua e colonne di normalizzazione
  /// (`name_norm`, `cn_lc`) che esistevano solo per rendere sopportabile quel
  /// matching. Con il printId il costo diventa proporzionale a quanto uno
  /// possiede, che e' la proprieta' che rende il sistema estendibile a 13
  /// cataloghi.
  Future<int> updateCollectionValues(String catalog) async {
    final cards = await _db.getCollectionCardsForPricing(catalog);
    if (cards.isEmpty) return 0;

    final values = <int, double?>{};
    for (final card in cards) {
      final serial = card['serialNumber'] as String? ?? '';
      final printId = await _db.resolvePrintId(
        catalog: catalog,
        catalogId: card['catalogId'] as String?,
        serialNumber: serial,
        rarity: card['rarity'] as String?,
      );
      if (printId.isEmpty) continue;

      final row = await _db.getUnifiedPrice(
        catalog: catalog,
        printId: printId,
        lang: CardtraderService.languageFromSerial(serial, catalog),
      );
      final cents = (row?['nm_cents'] as int?) ?? (row?['any_cents'] as int?);
      if (cents == null) continue;

      final id = card['id'] as int?;
      if (id == null) continue;
      final newValue = cents / 100;
      // Scrive solo se il valore cambia davvero: un UPDATE per ogni carta a
      // ogni sync sporcherebbe il WAL senza motivo.
      final current = (card['cardtrader_value'] as num?)?.toDouble();
      if (current != null && (current - newValue).abs() < 0.005) continue;
      values[id] = newValue;
    }
    if (values.isEmpty) return 0;
    final updated = await _db.updateCardtraderValues(values);
    AppLogger.info(
      'valori collezione $catalog: $updated carte aggiornate su ${cards.length}',
      tag: 'PriceSyncService',
    );
    return updated;
  }
}
