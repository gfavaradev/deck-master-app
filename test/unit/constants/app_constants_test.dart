import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/constants/app_constants.dart';

void main() {
  // ── CatalogConstants ──────────────────────────────────────────────────────
  group('CatalogConstants', () {
    test('allCatalogs contiene tutti e 4 i cataloghi', () {
      expect(CatalogConstants.allCatalogs, containsAll(['yugioh', 'pokemon', 'onepiece', 'magic']));
      expect(CatalogConstants.allCatalogs.length, 4);
    });

    group('getCollectionName', () {
      test('yugioh → yugioh_catalog', () {
        expect(CatalogConstants.getCollectionName('yugioh'), 'yugioh_catalog');
      });
      test('pokemon → pokemon_catalog', () {
        expect(CatalogConstants.getCollectionName('pokemon'), 'pokemon_catalog');
      });
      test('pattern generico: [catalog]_catalog', () {
        expect(CatalogConstants.getCollectionName('test'), 'test_catalog');
      });
    });

    group('getDisplayName', () {
      test("yugioh → 'Yu-Gi-Oh!'", () {
        expect(CatalogConstants.getDisplayName('yugioh'), 'Yu-Gi-Oh!');
      });
      test("pokemon → 'Pokémon'", () {
        expect(CatalogConstants.getDisplayName('pokemon'), 'Pokémon');
      });
      test("magic → 'Magic: The Gathering'", () {
        expect(CatalogConstants.getDisplayName('magic'), 'Magic: The Gathering');
      });
      test("onepiece → 'One Piece TCG'", () {
        expect(CatalogConstants.getDisplayName('onepiece'), 'One Piece TCG');
      });
      test('sconosciuto → ritorna il valore stesso', () {
        expect(CatalogConstants.getDisplayName('unknown'), 'unknown');
      });
    });
  });

  // ── LanguageConstants ─────────────────────────────────────────────────────
  group('LanguageConstants', () {
    test('allLanguages contiene 6 lingue', () {
      expect(LanguageConstants.allLanguages.length, 6);
    });

    test('allLanguages include en, it, fr, de, pt, sp', () {
      expect(LanguageConstants.allLanguages, containsAll(['en', 'it', 'fr', 'de', 'pt', 'sp']));
    });

    test("allLanguages NON include 'es' (usa 'sp' per lo spagnolo — possibile inconsistenza)", () {
      expect(LanguageConstants.allLanguages.contains('es'), isFalse);
    });

    group('getFieldName', () {
      test("campo + 'en' → campo base (senza suffisso)", () {
        expect(LanguageConstants.getFieldName('name', 'en'), 'name');
      });
      test("campo + 'it' → name_it", () {
        expect(LanguageConstants.getFieldName('name', 'it'), 'name_it');
      });
      test("campo + 'fr' → name_fr", () {
        expect(LanguageConstants.getFieldName('description', 'fr'), 'description_fr');
      });
      test("campo + 'sp' → name_sp", () {
        expect(LanguageConstants.getFieldName('set_code', 'sp'), 'set_code_sp');
      });
    });

    test('languageNames contiene tutti i nomi', () {
      expect(LanguageConstants.languageNames['en'], 'English');
      expect(LanguageConstants.languageNames['it'], 'Italiano');
      expect(LanguageConstants.languageNames['fr'], 'Français');
      expect(LanguageConstants.languageNames['de'], 'Deutsch');
      expect(LanguageConstants.languageNames['pt'], 'Português');
      expect(LanguageConstants.languageNames['sp'], 'Español');
    });
  });

  // ── ValidationConstants ───────────────────────────────────────────────────
  group('ValidationConstants', () {
    test('minNameLength = 1', () => expect(ValidationConstants.minNameLength, 1));
    test('maxNameLength = 200', () => expect(ValidationConstants.maxNameLength, 200));
    test('maxDescriptionLength = 2000', () => expect(ValidationConstants.maxDescriptionLength, 2000));
    test('maxAlbumCapacity = 1000', () => expect(ValidationConstants.maxAlbumCapacity, 1000));
    test('minCardValue = 0.0', () => expect(ValidationConstants.minCardValue, 0.0));
    test('maxCardValue = 999999.99', () => expect(ValidationConstants.maxCardValue, 999999.99));
    test('minCardValue < maxCardValue', () {
      expect(ValidationConstants.minCardValue, lessThan(ValidationConstants.maxCardValue));
    });
  });

  // ── IdRangeConstants ──────────────────────────────────────────────────────
  group('IdRangeConstants', () {
    test('customCardIdBase = 900000000', () {
      expect(IdRangeConstants.customCardIdBase, 900000000);
    });

    test('generateCustomCardId >= base', () {
      final id = IdRangeConstants.generateCustomCardId();
      expect(id, greaterThanOrEqualTo(IdRangeConstants.customCardIdBase));
    });

    test('generateCustomCardId < base + modulo', () {
      final id = IdRangeConstants.generateCustomCardId();
      expect(id, lessThan(IdRangeConstants.customCardIdBase + IdRangeConstants.customCardIdModulo));
    });

    test('due chiamate possono produrre valori diversi o uguali (ma nel range)', () {
      final id1 = IdRangeConstants.generateCustomCardId();
      final id2 = IdRangeConstants.generateCustomCardId();
      expect(id1, greaterThanOrEqualTo(IdRangeConstants.customCardIdBase));
      expect(id2, greaterThanOrEqualTo(IdRangeConstants.customCardIdBase));
    });
  });

  // ── FirestoreConstants ────────────────────────────────────────────────────
  group('FirestoreConstants', () {
    group('getChunkId', () {
      test('0 → chunk_000', () => expect(FirestoreConstants.getChunkId(0), 'chunk_000'));
      test('1 → chunk_001', () => expect(FirestoreConstants.getChunkId(1), 'chunk_001'));
      test('9 → chunk_009', () => expect(FirestoreConstants.getChunkId(9), 'chunk_009'));
      test('10 → chunk_010', () => expect(FirestoreConstants.getChunkId(10), 'chunk_010'));
      test('99 → chunk_099', () => expect(FirestoreConstants.getChunkId(99), 'chunk_099'));
      test('100 → chunk_100', () => expect(FirestoreConstants.getChunkId(100), 'chunk_100'));
      test('999 → chunk_999', () => expect(FirestoreConstants.getChunkId(999), 'chunk_999'));
    });

    test('catalogChunkSize = 1000', () {
      expect(FirestoreConstants.catalogChunkSize, 1000);
    });
  });

  // ── YugiohRarities ────────────────────────────────────────────────────────
  group('YugiohRarities', () {
    test('contiene le rarità principali', () {
      expect(YugiohRarities.commonRarities, contains('Common'));
      expect(YugiohRarities.commonRarities, contains('Ultra Rare'));
      expect(YugiohRarities.commonRarities, contains('Secret Rare'));
      expect(YugiohRarities.commonRarities, contains('Ghost Rare'));
    });
  });

  // ── YugiohAttributes ─────────────────────────────────────────────────────
  group('YugiohAttributes', () {
    test('allAttributes contiene i 7 attributi', () {
      expect(YugiohAttributes.allAttributes.length, 7);
      expect(YugiohAttributes.allAttributes, contains('DARK'));
      expect(YugiohAttributes.allAttributes, contains('LIGHT'));
      expect(YugiohAttributes.allAttributes, contains('DIVINE'));
    });
  });

  // ── UIConstants ───────────────────────────────────────────────────────────
  group('UIConstants', () {
    test('catalogPageSize > 0', () => expect(UIConstants.catalogPageSize, greaterThan(0)));
    test('searchDebounce è una durata positiva', () {
      expect(UIConstants.searchDebounce.inMilliseconds, greaterThan(0));
    });
  });
}
