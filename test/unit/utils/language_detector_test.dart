import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/utils/language_detector.dart';

void main() {
  group('LanguageDetector', () {
    // ── detectLanguageFromSetCode ─────────────────────────────────────────
    group('detectLanguageFromSetCode', () {
      // 2-letter codes
      test('EN → EN', () => expect(LanguageDetector.detectLanguageFromSetCode('MP14-EN092'), 'EN'));
      test('IT → IT', () => expect(LanguageDetector.detectLanguageFromSetCode('MP14-IT092'), 'IT'));
      test('FR → FR', () => expect(LanguageDetector.detectLanguageFromSetCode('MP14-FR092'), 'FR'));
      test('DE → DE', () => expect(LanguageDetector.detectLanguageFromSetCode('MP14-DE092'), 'DE'));
      test('PT → PT', () => expect(LanguageDetector.detectLanguageFromSetCode('MP14-PT092'), 'PT'));
      test('ES → ES (spagnolo standard)', () {
        expect(LanguageDetector.detectLanguageFromSetCode('OP01-ES001'), 'ES');
      });
      test('SP → ES (spagnolo alternativo)', () {
        expect(LanguageDetector.detectLanguageFromSetCode('LOB-SP001'), 'ES');
      });
      test('JP → JP', () => expect(LanguageDetector.detectLanguageFromSetCode('LOB-JP001'), 'JP'));
      test('JA → JP (giapponese alternativo)', () {
        expect(LanguageDetector.detectLanguageFromSetCode('LOB-JA001'), 'JP');
      });
      test('KR → KR', () => expect(LanguageDetector.detectLanguageFromSetCode('LOB-KR001'), 'KR'));
      test('KO → KR (coreano alternativo)', () {
        expect(LanguageDetector.detectLanguageFromSetCode('LOB-KO001'), 'KR');
      });
      test('codice 2 lettere sconosciuto → EN (default)', () {
        expect(LanguageDetector.detectLanguageFromSetCode('LOB-ZZ001'), 'EN');
      });

      // 1-letter codes (formato europeo antico)
      test('E → EN (inglese)', () => expect(LanguageDetector.detectLanguageFromSetCode('SDY-E006'), 'EN'));
      test('I → IT (italiano)', () => expect(LanguageDetector.detectLanguageFromSetCode('SDY-I006'), 'IT'));
      test('F → FR (francese)', () => expect(LanguageDetector.detectLanguageFromSetCode('SDY-F006'), 'FR'));
      test('D → DE (tedesco)', () => expect(LanguageDetector.detectLanguageFromSetCode('SDY-D006'), 'DE'));
      test('P → PT (portoghese)', () => expect(LanguageDetector.detectLanguageFromSetCode('SDY-P006'), 'PT'));
      test('lettera sconosciuta → EN', () {
        expect(LanguageDetector.detectLanguageFromSetCode('SDY-X006'), 'EN');
      });

      // Edge cases
      test('senza trattino → EN (default)', () {
        expect(LanguageDetector.detectLanguageFromSetCode('LOBZ001'), 'EN');
      });
      test('stringa vuota → EN', () {
        expect(LanguageDetector.detectLanguageFromSetCode(''), 'EN');
      });
      test('codice lowercase → gestito (toUpperCase interno)', () {
        expect(LanguageDetector.detectLanguageFromSetCode('lob-en001'), 'EN');
      });
      test('spazi attorno → gestito (trim interno)', () {
        expect(LanguageDetector.detectLanguageFromSetCode('  LOB-IT001  '), 'IT');
      });
    });

    // ── getFieldSuffix ────────────────────────────────────────────────────
    group('getFieldSuffix', () {
      test('EN → stringa vuota (base field)', () {
        expect(LanguageDetector.getFieldSuffix('EN'), '');
      });
      test('en (lowercase) → stringa vuota', () {
        expect(LanguageDetector.getFieldSuffix('en'), '');
      });
      test('IT → _it', () => expect(LanguageDetector.getFieldSuffix('IT'), '_it'));
      test('it (lowercase) → _it', () => expect(LanguageDetector.getFieldSuffix('it'), '_it'));
      test('FR → _fr', () => expect(LanguageDetector.getFieldSuffix('FR'), '_fr'));
      test('DE → _de', () => expect(LanguageDetector.getFieldSuffix('DE'), '_de'));
      test('PT → _pt', () => expect(LanguageDetector.getFieldSuffix('PT'), '_pt'));

      test("ES → '_sp' (YuGiOh usa suffisso _sp per lo spagnolo)", () {
        expect(LanguageDetector.getFieldSuffix('ES'), '_sp');
      });
      test("SP → '_sp'", () {
        expect(LanguageDetector.getFieldSuffix('SP'), '_sp');
      });
      test("es (lowercase) → '_sp'", () {
        expect(LanguageDetector.getFieldSuffix('es'), '_sp');
      });

      test('lingua sconosciuta → stringa vuota (fallback)', () {
        expect(LanguageDetector.getFieldSuffix('ZH'), '');
      });
    });

    // ── consistenza detectLanguage → getFieldSuffix ───────────────────────
    group('consistenza pipeline detectLanguage → getFieldSuffix', () {
      test('IT pipeline: set code → suffisso corretto', () {
        final lang = LanguageDetector.detectLanguageFromSetCode('MP14-IT092');
        final suffix = LanguageDetector.getFieldSuffix(lang);
        expect(suffix, '_it');
      });

      test('FR pipeline', () {
        final lang = LanguageDetector.detectLanguageFromSetCode('MP14-FR092');
        expect(LanguageDetector.getFieldSuffix(lang), '_fr');
      });

      test('EN pipeline → suffisso vuoto (base field)', () {
        final lang = LanguageDetector.detectLanguageFromSetCode('LOB-EN001');
        expect(LanguageDetector.getFieldSuffix(lang), '');
      });

      test('ES pipeline: detectLanguage dà ES, getFieldSuffix(ES) → "_sp" (fix applicato)', () {
        final lang = LanguageDetector.detectLanguageFromSetCode('OP01-ES001');
        expect(lang, 'ES');
        expect(LanguageDetector.getFieldSuffix(lang), '_sp');
      });
    });
  });
}
