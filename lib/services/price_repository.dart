import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../utils/app_logger.dart';

/// Accesso ai prezzi pubblicati su Realtime Database — unico per tutti i 13
/// cataloghi. Vedi `REQUIREMENTS_prices_unified.md`.
///
/// Schema (scritto da `deck-master-worker/src/lib/rtdb.ts`):
/// ```
/// /v                        → { <catalog>: <versione> }   ~200 byte, l'unico listener
/// /p/{cat}/idx              → { sets: { <set>: <ver> }, n, t }
/// /p/{cat}/s/{set}/{lang}   → { <printId>: [nmCents, anyCents, listings] }
/// /h/{cat}/{printId}        → { "260902": <cents> }
/// ```
///
/// Regola non negoziabile: **non si legge mai un nodo che cresce senza limite**.
/// Niente `/p`, niente `/p/{cat}`, niente `/p/{cat}/s`: solo un set per volta.
/// È la stessa classe di errore che nella 1.3.9 uccise la produzione con un
/// `.get()` unico su `cardtrader_prices` (626 chunk, ~70 MB) — vedi
/// `integration_test/crashes/firestore_oom_test.dart`. Le regole in
/// `database.rules.json` concedono lettura solo a livello di set e lo impediscono
/// anche lato server, ma il codice non deve nemmeno provarci.
class PriceRepository {
  /// L'istanza RTDB sta in europe-west1, quindi NON ha l'URL di default
  /// `<project>-default-rtdb.firebaseio.com`: senza URL esplicito il plugin
  /// punterebbe a un database inesistente.
  static const String databaseUrl =
      'https://deck-master-1a35a-default-rtdb.europe-west1.firebasedatabase.app';

  static const Duration _timeout = Duration(seconds: 10);

  final FirebaseDatabase _db;

  PriceRepository({FirebaseDatabase? database})
      : _db = database ??
            FirebaseDatabase.instanceFor(
              app: Firebase.app(),
              databaseURL: databaseUrl,
            );

  /// Versioni correnti per catalogo, da `/v`. Una sola lettura da ~200 byte per
  /// sapere se qualcosa è cambiato in uno qualsiasi dei 13 cataloghi.
  Future<Map<String, int>> fetchVersions() async {
    try {
      final snap = await _db.ref('v').get().timeout(_timeout);
      return _asVersionMap(snap.value);
    } catch (e) {
      AppLogger.error('fetchVersions failed', tag: 'PriceRepository', error: e);
      return const {};
    }
  }

  /// Stream delle versioni: è l'unico listener che l'app tiene aperto.
  /// Un catalogo cambia ⇒ arriva un evento ⇒ si scaricano solo i set interessati.
  Stream<Map<String, int>> watchVersions() =>
      _db.ref('v').onValue.map((event) => _asVersionMap(event.snapshot.value));

  static Map<String, int> _asVersionMap(Object? value) {
    if (value is! Map) return const {};
    final out = <String, int>{};
    value.forEach((k, v) {
      final version = v is int ? v : int.tryParse('$v');
      if (version != null) out['$k'] = version;
    });
    return out;
  }

  /// Indice di un catalogo: versione per set. Si legge solo per i cataloghi che
  /// l'utente usa davvero, non per tutti e 13.
  Future<CatalogPriceIndex?> fetchIndex(String catalog) async {
    try {
      final snap = await _db.ref('p/$catalog/idx').get().timeout(_timeout);
      final value = snap.value;
      if (value is! Map) return null;
      final rawSets = value['sets'];
      final sets = <String, int>{};
      if (rawSets is Map) {
        rawSets.forEach((k, v) {
          final version = v is int ? v : int.tryParse('$v');
          if (version != null) sets['$k'] = version;
        });
      }
      final n = value['n'];
      return CatalogPriceIndex(
        setVersions: sets,
        prints: n is int ? n : int.tryParse('$n') ?? 0,
        updatedAt: value['t']?.toString(),
      );
    } catch (e) {
      AppLogger.error('fetchIndex($catalog) failed',
          tag: 'PriceRepository', error: e);
      return null;
    }
  }

  /// Prezzi di UN set, tutte le lingue: `/p/{cat}/s/{set}`.
  ///
  /// È l'unità di scaricamento del sistema. Un set pesa tipicamente pochi KB;
  /// i più grandi restano nell'ordine delle centinaia di KB, contro i ~70 MB
  /// del listino completo che il vecchio percorso replicava per intero.
  Future<List<PriceRow>> fetchSet(String catalog, String setCode) async {
    try {
      final snap =
          await _db.ref('p/$catalog/s/$setCode').get().timeout(_timeout);
      return _parseSet(catalog, setCode, snap.value);
    } catch (e) {
      AppLogger.error('fetchSet($catalog/$setCode) failed',
          tag: 'PriceRepository', error: e);
      return const [];
    }
  }

  static List<PriceRow> _parseSet(
      String catalog, String setCode, Object? value) {
    if (value is! Map) return const [];
    final rows = <PriceRow>[];
    value.forEach((lang, byPrint) {
      if (byPrint is! Map) return;
      byPrint.forEach((printId, tuple) {
        final row = PriceRow.fromTuple(
          catalog: catalog,
          setCode: setCode,
          lang: '$lang',
          printId: '$printId',
          tuple: tuple,
        );
        if (row != null) rows.add(row);
      });
    });
    return rows;
  }

  /// Storico di UNA stampa, letto solo all'apertura della scheda carta.
  /// Chiavi "YYMMDD" → prezzo in centesimi.
  Future<List<PricePoint>> fetchHistory(String catalog, String printId) async {
    if (printId.isEmpty) return const [];
    try {
      final snap =
          await _db.ref('h/$catalog/$printId').get().timeout(_timeout);
      final value = snap.value;
      if (value is! Map) return const [];
      final points = <PricePoint>[];
      value.forEach((date, cents) {
        final c = cents is int ? cents : int.tryParse('$cents');
        final d = _parseHistoryDate('$date');
        if (c != null && d != null) points.add(PricePoint(date: d, cents: c));
      });
      points.sort((a, b) => a.date.compareTo(b.date));
      return points;
    } catch (e) {
      AppLogger.error('fetchHistory($catalog/$printId) failed',
          tag: 'PriceRepository', error: e);
      return const [];
    }
  }

  /// "260902" → 2026-09-02. Le chiavi storico sono compatte per stare in pochi
  /// byte per punto: il secolo è implicito.
  static DateTime? _parseHistoryDate(String key) {
    if (key.length != 6) return null;
    final y = int.tryParse(key.substring(0, 2));
    final m = int.tryParse(key.substring(2, 4));
    final d = int.tryParse(key.substring(4, 6));
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime(2000 + y, m, d);
  }
}

/// Indice dei set di un catalogo, da `/p/{cat}/idx`.
class CatalogPriceIndex {
  final Map<String, int> setVersions;
  final int prints;
  final String? updatedAt;

  const CatalogPriceIndex({
    required this.setVersions,
    required this.prints,
    this.updatedAt,
  });

  /// Set la cui versione è più recente di quella già in locale — gli unici da
  /// riscaricare. [local] è la mappa set→versione salvata dall'ultimo sync.
  List<String> setsToFetch(Map<String, int> local, Set<String> wanted) {
    final out = <String>[];
    for (final entry in setVersions.entries) {
      if (wanted.isNotEmpty && !wanted.contains(entry.key)) continue;
      if ((local[entry.key] ?? -1) < entry.value) out.add(entry.key);
    }
    return out;
  }
}

/// Una riga prezzo pronta per SQLite.
class PriceRow {
  final String catalog;
  final String printId;
  final String setCode;
  final String lang;
  final int? nmCents;
  final int? anyCents;
  final int listings;

  const PriceRow({
    required this.catalog,
    required this.printId,
    required this.setCode,
    required this.lang,
    required this.nmCents,
    required this.anyCents,
    required this.listings,
  });

  /// Miglior prezzo disponibile: NM se c'è, altrimenti qualsiasi condizione.
  int? get bestCents => nmCents ?? anyCents;

  /// Il worker pubblica `[nmCents, anyCents, listings]` per non ripetere i nomi
  /// dei campi su ogni riga. Un valore malformato produce `null` invece di
  /// un'eccezione: una riga corrotta non deve far fallire l'intero set.
  static PriceRow? fromTuple({
    required String catalog,
    required String setCode,
    required String lang,
    required String printId,
    required Object? tuple,
  }) {
    if (printId.isEmpty || tuple is! List || tuple.isEmpty) return null;
    int? at(int i) {
      if (i >= tuple.length) return null;
      final v = tuple[i];
      return v is int ? v : int.tryParse('${v ?? ''}');
    }

    final nm = at(0);
    final any = at(1);
    if (nm == null && any == null) return null;
    return PriceRow(
      catalog: catalog,
      printId: printId,
      setCode: setCode,
      lang: lang,
      nmCents: nm,
      anyCents: any,
      listings: at(2) ?? 0,
    );
  }

  Map<String, Object?> toMap() => {
        'catalog': catalog,
        'print_id': printId,
        'set_code': setCode,
        'lang': lang,
        'nm_cents': nmCents,
        'any_cents': anyCents,
        'listings': listings,
      };
}

/// Un punto dello storico prezzi.
class PricePoint {
  final DateTime date;
  final int cents;

  const PricePoint({required this.date, required this.cents});
}
