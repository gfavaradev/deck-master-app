import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/services/language_service.dart';

void main() {
  // ── supportedLanguages ─────────────────────────────────────────────────────
  group('LanguageService.supportedLanguages', () {
    test('contiene EN, IT, FR, DE, PT, SP', () {
      expect(LanguageService.supportedLanguages,
          containsAll(['EN', 'IT', 'FR', 'DE', 'PT', 'SP']));
    });
    test('usa UPPERCASE', () {
      for (final l in LanguageService.supportedLanguages) {
        expect(l, l.toUpperCase(), reason: '$l dovrebbe essere uppercase');
      }
    });
    test('non contiene duplicati', () {
      final set = LanguageService.supportedLanguages.toSet();
      expect(set.length, LanguageService.supportedLanguages.length);
    });
  });

  // ── collectionLanguages ────────────────────────────────────────────────────
  group('LanguageService.collectionLanguages', () {
    test('yugioh ha lingue', () {
      expect(LanguageService.collectionLanguages['yugioh'], isNotEmpty);
    });
    test('lingue di ogni collezione sono uppercase', () {
      for (final entry in LanguageService.collectionLanguages.entries) {
        for (final lang in entry.value) {
          expect(lang, lang.toUpperCase(),
              reason: 'Lingua ${entry.key}:$lang dovrebbe essere uppercase');
        }
      }
    });
    test('One Piece include JP che NON è in supportedLanguages (lingua originale TCG)', () {
      // JP è una lingua specifica di One Piece (origine giapponese del TCG)
      // ma non fa parte delle lingue "display" globali dell'app.
      final onepieceLangs = LanguageService.collectionLanguages['onepiece'] ?? [];
      expect(onepieceLangs, contains('JP'),
          reason: 'One Piece deve avere JP tra le sue lingue');
      expect(LanguageService.supportedLanguages.contains('JP'), isFalse,
          reason: 'JP non è una lingua display globale');
    });

    test('lingue esclusive One Piece (JP, KO, ZH) non sono in supportedLanguages (lista globale YGO)', () {
      // supportedLanguages è la lista globale basata su YGO. One Piece ha lingue
      // aggiuntive (JP, KO, ZH) che non fanno parte del set globale — è corretto.
      const opOnly = {'JP', 'KO', 'ZH'};
      for (final entry in LanguageService.collectionLanguages.entries) {
        for (final lang in entry.value) {
          if (opOnly.contains(lang)) continue; // eccezioni documentate per One Piece
          expect(LanguageService.supportedLanguages, contains(lang),
              reason: '$lang (${entry.key}) dovrebbe essere in supportedLanguages');
        }
      }
    });
  });

  // ── languageLabels ─────────────────────────────────────────────────────────
  group('LanguageService.languageLabels', () {
    test('ha label per EN', () => expect(LanguageService.languageLabels['EN'], isNotNull));
    test('ha label per IT', () => expect(LanguageService.languageLabels['IT'], isNotNull));
    test('ha label per SP', () => expect(LanguageService.languageLabels['SP'], isNotNull));
    test('label non vuote', () {
      for (final label in LanguageService.languageLabels.values) {
        expect(label, isNotEmpty);
      }
    });
  });

  // ── flagEmoji ──────────────────────────────────────────────────────────────
  group('LanguageService.flagEmoji', () {
    test('ha flag per EN', () => expect(LanguageService.flagEmoji['EN'], isNotNull));
    test('ha flag per IT', () => expect(LanguageService.flagEmoji['IT'], isNotNull));
    test('flag non vuote', () {
      for (final flag in LanguageService.flagEmoji.values) {
        expect(flag, isNotEmpty);
      }
    });
  });

  // ── detectLanguageFromQuery ────────────────────────────────────────────────
  group('LanguageService.detectLanguageFromQuery', () {
    test("'LOB-EN001' → 'EN'", () {
      expect(LanguageService.detectLanguageFromQuery('LOB-EN001'), 'EN');
    });
    test("'LOB-IT001' → 'IT'", () {
      expect(LanguageService.detectLanguageFromQuery('LOB-IT001'), 'IT');
    });
    test("'LOB-FR001' → 'FR'", () {
      expect(LanguageService.detectLanguageFromQuery('LOB-FR001'), 'FR');
    });
    test("'LOB-DE001' → 'DE'", () {
      expect(LanguageService.detectLanguageFromQuery('LOB-DE001'), 'DE');
    });
    test("'LOB-PT001' → 'PT'", () {
      expect(LanguageService.detectLanguageFromQuery('LOB-PT001'), 'PT');
    });
    test("'LOB-SP001' → 'SP'", () {
      expect(LanguageService.detectLanguageFromQuery('LOB-SP001'), 'SP');
    });
    test("'SDAZ-IT042' → 'IT'", () {
      expect(LanguageService.detectLanguageFromQuery('SDAZ-IT042'), 'IT');
    });
    test("lowercase 'lob-en001' → 'EN'", () {
      expect(LanguageService.detectLanguageFromQuery('lob-en001'), 'EN');
    });
    test("spazi attorno → trimmed", () {
      expect(LanguageService.detectLanguageFromQuery('  LOB-IT001  '), 'IT');
    });
    test("'DarkMagician' senza trattino → null", () {
      expect(LanguageService.detectLanguageFromQuery('DarkMagician'), isNull);
    });
    test("stringa vuota → null", () {
      expect(LanguageService.detectLanguageFromQuery(''), isNull);
    });
    test("codice lingua non in supportedLanguages → null", () {
      // ZH non è in supportedLanguages
      expect(LanguageService.detectLanguageFromQuery('LOB-ZH001'), isNull);
    });
    test("'001' senza prefisso → null", () {
      expect(LanguageService.detectLanguageFromQuery('001'), isNull);
    });
  });
}
