import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/services/cardtrader_service.dart';

void main() {
  // ── normalizeLang ──────────────────────────────────────────────────────────
  group('CardtraderService.normalizeLang', () {
    test("'jp' → 'ja' (CT usa 'jp' per giapponese)", () {
      expect(CardtraderService.normalizeLang('jp'), 'ja');
    });
    test("'JP' (uppercase) → 'ja'", () {
      expect(CardtraderService.normalizeLang('JP'), 'ja');
    });
    test("'kr' → 'ko' (CT usa 'kr' per coreano)", () {
      expect(CardtraderService.normalizeLang('kr'), 'ko');
    });
    test("'zh-cn' → 'zh'", () {
      expect(CardtraderService.normalizeLang('zh-cn'), 'zh');
    });
    test("'ZH-CN' (uppercase) → 'zh'", () {
      expect(CardtraderService.normalizeLang('ZH-CN'), 'zh');
    });
    test("'en' → 'en' (passthrough)", () {
      expect(CardtraderService.normalizeLang('en'), 'en');
    });
    test("'EN' → 'en' (lowercase)", () {
      expect(CardtraderService.normalizeLang('EN'), 'en');
    });
    test("'it' → 'it'", () => expect(CardtraderService.normalizeLang('it'), 'it'));
    test("'fr' → 'fr'", () => expect(CardtraderService.normalizeLang('fr'), 'fr'));
    test("'de' → 'de'", () => expect(CardtraderService.normalizeLang('de'), 'de'));
    test("'pt' → 'pt'", () => expect(CardtraderService.normalizeLang('pt'), 'pt'));
    test("'es' → 'es'", () => expect(CardtraderService.normalizeLang('es'), 'es'));
    test('lingua sconosciuta → lowercase passthrough', () {
      expect(CardtraderService.normalizeLang('ZZ'), 'zz');
    });
  });

  // ── languageFromSerial ─────────────────────────────────────────────────────
  group('CardtraderService.languageFromSerial', () {
    group('yugioh', () {
      test("LOB-EN001 → 'en'", () {
        expect(CardtraderService.languageFromSerial('LOB-EN001', 'yugioh'), 'en');
      });
      test("LOB-IT001 → 'it'", () {
        expect(CardtraderService.languageFromSerial('LOB-IT001', 'yugioh'), 'it');
      });
      test("LOB-FR001 → 'fr'", () {
        expect(CardtraderService.languageFromSerial('LOB-FR001', 'yugioh'), 'fr');
      });
      test("LOB-DE001 → 'de'", () {
        expect(CardtraderService.languageFromSerial('LOB-DE001', 'yugioh'), 'de');
      });
      test("LOB-PT001 → 'pt'", () {
        expect(CardtraderService.languageFromSerial('LOB-PT001', 'yugioh'), 'pt');
      });
      test("LOB-SP001 → 'es' (SP è spagnolo in YGO, normalizzato a es)", () {
        expect(CardtraderService.languageFromSerial('LOB-SP001', 'yugioh'), 'es');
      });
      test("senza trattino → 'en' (default)", () {
        expect(CardtraderService.languageFromSerial('LOB001', 'yugioh'), 'en');
      });
    });

    group('onepiece', () {
      test("OP01-001 → 'ja' (default, no lingua nel CN)", () {
        expect(CardtraderService.languageFromSerial('OP01-001', 'onepiece'), 'ja');
      });
      test("OP01-EN001 → 'en'", () {
        expect(CardtraderService.languageFromSerial('OP01-EN001', 'onepiece'), 'en');
      });
      test("OP01-IT001 → 'it'", () {
        expect(CardtraderService.languageFromSerial('OP01-IT001', 'onepiece'), 'it');
      });
      test("senza trattino → 'ja' (default)", () {
        expect(CardtraderService.languageFromSerial('OP01001', 'onepiece'), 'ja');
      });
    });

    group('pokemon', () {
      test("qualsiasi seriale → 'en' (Pokemon non codifica lingua nel seriale)", () {
        expect(CardtraderService.languageFromSerial('swsh1-1', 'pokemon'), 'en');
        expect(CardtraderService.languageFromSerial('base1-4', 'pokemon'), 'en');
      });
    });

    group('other collection', () {
      test("collezione sconosciuta → 'en' (default)", () {
        expect(CardtraderService.languageFromSerial('XXX-001', 'magic'), 'en');
      });
    });
  });

  // ── extractBlueprintImageUrl ───────────────────────────────────────────────
  group('CardtraderService.extractBlueprintImageUrl', () {
    test('image come String diretta', () {
      final bp = {'image': 'https://cdn.cardtrader.com/img.jpg'};
      expect(CardtraderService.extractBlueprintImageUrl(bp),
          'https://cdn.cardtrader.com/img.jpg');
    });

    test('image come Map con chiave show', () {
      final bp = {
        'image': {
          'show': 'https://cdn.cardtrader.com/show.jpg',
          'original': 'https://cdn.cardtrader.com/orig.jpg',
        }
      };
      expect(CardtraderService.extractBlueprintImageUrl(bp),
          'https://cdn.cardtrader.com/show.jpg');
    });

    test('image come Map senza show ma con original', () {
      final bp = {
        'image': {'original': 'https://cdn.cardtrader.com/orig.jpg'}
      };
      expect(CardtraderService.extractBlueprintImageUrl(bp),
          'https://cdn.cardtrader.com/orig.jpg');
    });

    test('fallback a image_url se image è null', () {
      final bp = {'image_url': 'https://cdn.cardtrader.com/fallback.jpg'};
      expect(CardtraderService.extractBlueprintImageUrl(bp),
          'https://cdn.cardtrader.com/fallback.jpg');
    });

    test('null se nessuna immagine presente', () {
      expect(CardtraderService.extractBlueprintImageUrl({}), isNull);
    });

    test('null se image è stringa vuota', () {
      expect(CardtraderService.extractBlueprintImageUrl({'image': ''}), isNull);
    });

    test('null se image_url è stringa vuota', () {
      expect(CardtraderService.extractBlueprintImageUrl({'image_url': ''}), isNull);
    });

    test('null se image è Map vuota', () {
      expect(CardtraderService.extractBlueprintImageUrl({'image': {}}), isNull);
    });

    test('null se image è Map con show vuoto e original assente', () {
      expect(CardtraderService.extractBlueprintImageUrl({'image': {'show': ''}}), isNull);
    });

    test('show ha priorità su original quando entrambi presenti', () {
      final bp = {
        'image': {
          'show': 'https://cdn.cardtrader.com/show.jpg',
          'original': 'https://cdn.cardtrader.com/orig.jpg',
        }
      };
      expect(CardtraderService.extractBlueprintImageUrl(bp),
          'https://cdn.cardtrader.com/show.jpg');
    });
  });

  // ── languagesForCatalog ────────────────────────────────────────────────────
  group('CardtraderService.languagesForCatalog', () {
    test('yugioh ha almeno en, it, fr, de, pt, es', () {
      final langs = CardtraderService.languagesForCatalog('yugioh');
      expect(langs, isNotEmpty);
      expect(langs.keys, containsAll(['en', 'it', 'fr', 'de', 'pt', 'es']));
    });

    test('pokemon restituisce lingue non vuote', () {
      final langs = CardtraderService.languagesForCatalog('pokemon');
      expect(langs, isNotEmpty);
    });

    test('onepiece restituisce lingue non vuote', () {
      final langs = CardtraderService.languagesForCatalog('onepiece');
      expect(langs, isNotEmpty);
    });

    test('catalogo sconosciuto → mappa vuota', () {
      final langs = CardtraderService.languagesForCatalog('unknown_catalog');
      expect(langs, isEmpty);
    });
  });
}
