import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/services/price_repository.dart';

void main() {
  group('PriceRow.fromTuple', () {
    PriceRow? parse(Object? tuple, {String printId = '168145'}) =>
        PriceRow.fromTuple(
          catalog: 'digimon',
          setCode: 'btv1',
          lang: 'en',
          printId: printId,
          tuple: tuple,
        );

    test('legge la tupla compatta pubblicata dal worker', () {
      final row = parse([500, 400, 3])!;
      expect(row.nmCents, 500);
      expect(row.anyCents, 400);
      expect(row.listings, 3);
      expect(row.bestCents, 500);
      expect(row.catalog, 'digimon');
      expect(row.setCode, 'btv1');
    });

    test('NM assente: il prezzo migliore è quello di qualsiasi condizione', () {
      final row = parse([null, 27564, 2])!;
      expect(row.nmCents, isNull);
      expect(row.bestCents, 27564);
    });

    test('una riga corrotta non fa fallire il set, torna null', () {
      expect(parse(null), isNull);
      expect(parse('non-una-lista'), isNull);
      expect(parse(const []), isNull);
      expect(parse(const [null, null, 0]), isNull);
      expect(parse([500, 400, 3], printId: ''), isNull);
    });

    test('tupla corta: i campi mancanti degradano senza eccezioni', () {
      final row = parse([500])!;
      expect(row.nmCents, 500);
      expect(row.anyCents, isNull);
      expect(row.listings, 0);
    });

    test('numeri arrivati come stringa vengono convertiti', () {
      final row = parse(['500', '400', '3'])!;
      expect(row.nmCents, 500);
      expect(row.anyCents, 400);
      expect(row.listings, 3);
    });

    test('toMap produce le colonne di card_prices', () {
      final map = parse([500, 400, 3])!.toMap();
      expect(map.keys.toSet(), {
        'catalog', 'print_id', 'set_code', 'lang', 'nm_cents', 'any_cents', 'listings',
      });
      expect(map['print_id'], '168145');
      expect(map['nm_cents'], 500);
    });
  });

  group('CatalogPriceIndex.setsToFetch', () {
    final index = CatalogPriceIndex(
      setVersions: const {'lob': 3, 'mrd': 1, 'jush': 7},
      prints: 100,
    );

    test('scarica solo i set con versione più recente di quella locale', () {
      final toFetch = index.setsToFetch(const {'lob': 3, 'mrd': 1, 'jush': 6}, const {});
      expect(toFetch, ['jush']);
    });

    test('primo sync: nessuna versione locale ⇒ tutti i set', () {
      final toFetch = index.setsToFetch(const {}, const {});
      expect(toFetch.toSet(), {'lob', 'mrd', 'jush'});
    });

    test('tutto allineato ⇒ nessun download (è il gate anti-traffico)', () {
      expect(index.setsToFetch(const {'lob': 3, 'mrd': 1, 'jush': 7}, const {}), isEmpty);
    });

    test('una versione locale più avanti del remoto non riscarica', () {
      expect(index.setsToFetch(const {'lob': 99, 'mrd': 99, 'jush': 99}, const {}), isEmpty);
    });

    test('il filtro sui set posseduti restringe il download', () {
      final toFetch = index.setsToFetch(const {}, const {'lob', 'jush'});
      expect(toFetch.toSet(), {'lob', 'jush'});
    });

    test('filtro vuoto significa "tutti", non "nessuno"', () {
      expect(index.setsToFetch(const {}, const {}).length, 3);
    });
  });
}
