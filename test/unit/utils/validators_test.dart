import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/utils/validators.dart';

void main() {
  group('Validators', () {
    // ── validateCardName ──────────────────────────────────────────────────
    group('validateCardName', () {
      test('null → errore', () => expect(Validators.validateCardName(null), isNotNull));
      test('vuoto → errore', () => expect(Validators.validateCardName(''), isNotNull));
      test('solo spazi → errore', () => expect(Validators.validateCardName('   '), isNotNull));
      test('nome valido → null', () => expect(Validators.validateCardName('Dark Magician'), isNull));
      test('singolo carattere → null (min=1)', () => expect(Validators.validateCardName('A'), isNull));
      test('200 caratteri → null (al limite)', () {
        expect(Validators.validateCardName('A' * 200), isNull);
      });
      test('201 caratteri → errore (supera max)', () {
        expect(Validators.validateCardName('A' * 201), isNotNull);
      });
    });

    // ── validateDescription ───────────────────────────────────────────────
    group('validateDescription', () {
      test('null → errore', () => expect(Validators.validateDescription(null), isNotNull));
      test('vuoto → errore', () => expect(Validators.validateDescription(''), isNotNull));
      test('testo valido → null', () => expect(Validators.validateDescription('Una carta magica'), isNull));
      test('2000 caratteri → null (al limite)', () {
        expect(Validators.validateDescription('X' * 2000), isNull);
      });
      test('2001 caratteri → errore', () {
        expect(Validators.validateDescription('X' * 2001), isNotNull);
      });
    });

    // ── validateOptionalText ──────────────────────────────────────────────
    group('validateOptionalText', () {
      test('null → null (campo opzionale)', () => expect(Validators.validateOptionalText(null), isNull));
      test('vuoto → null', () => expect(Validators.validateOptionalText(''), isNull));
      test('solo spazi → null', () => expect(Validators.validateOptionalText('   '), isNull));
      test('testo valido senza maxLength → null', () {
        expect(Validators.validateOptionalText('ciao'), isNull);
      });
      test('testo entro maxLength → null', () {
        expect(Validators.validateOptionalText('abc', maxLength: 5), isNull);
      });
      test('testo supera maxLength → errore', () {
        expect(Validators.validateOptionalText('abcdef', maxLength: 5), isNotNull);
      });
    });

    // ── validateAlbumCapacity ─────────────────────────────────────────────
    group('validateAlbumCapacity', () {
      test('vuoto → errore', () => expect(Validators.validateAlbumCapacity(''), isNotNull));
      test('null → errore', () => expect(Validators.validateAlbumCapacity(null), isNotNull));
      test('non numerico → errore', () => expect(Validators.validateAlbumCapacity('abc'), isNotNull));
      test('0 → errore', () => expect(Validators.validateAlbumCapacity('0'), isNotNull));
      test('negativo → errore', () => expect(Validators.validateAlbumCapacity('-1'), isNotNull));
      test('1 → null', () => expect(Validators.validateAlbumCapacity('1'), isNull));
      test('1000 → null (al limite)', () => expect(Validators.validateAlbumCapacity('1000'), isNull));
      test('1001 → errore (supera max)', () => expect(Validators.validateAlbumCapacity('1001'), isNotNull));
      test('500 → null', () => expect(Validators.validateAlbumCapacity('500'), isNull));
    });

    // ── validateCardValue ─────────────────────────────────────────────────
    group('validateCardValue', () {
      test('null → null (opzionale)', () => expect(Validators.validateCardValue(null), isNull));
      test('vuoto → null', () => expect(Validators.validateCardValue(''), isNull));
      test('non numerico → errore', () => expect(Validators.validateCardValue('abc'), isNotNull));
      test('0 → null', () => expect(Validators.validateCardValue('0'), isNull));
      test('negativo → errore', () => expect(Validators.validateCardValue('-0.01'), isNotNull));
      test('valore valido → null', () => expect(Validators.validateCardValue('9.99'), isNull));
      test('max esatto → null', () => expect(Validators.validateCardValue('999999.99'), isNull));
      test('sopra max → errore', () => expect(Validators.validateCardValue('1000000'), isNotNull));
    });

    // ── validatePositiveInt ───────────────────────────────────────────────
    group('validatePositiveInt', () {
      test('null senza required → null', () {
        expect(Validators.validatePositiveInt(null), isNull);
      });
      test('vuoto senza required → null', () {
        expect(Validators.validatePositiveInt(''), isNull);
      });
      test('vuoto con required=true → errore', () {
        expect(Validators.validatePositiveInt('', required: true), isNotNull);
      });
      test('non intero → errore', () {
        expect(Validators.validatePositiveInt('abc'), isNotNull);
      });
      test('negativo → errore', () {
        expect(Validators.validatePositiveInt('-1'), isNotNull);
      });
      test('0 → null (zero è ammesso)', () {
        expect(Validators.validatePositiveInt('0'), isNull);
      });
      test('positivo → null', () {
        expect(Validators.validatePositiveInt('42'), isNull);
      });
    });

    // ── validateEmail ─────────────────────────────────────────────────────
    group('validateEmail', () {
      test('null → errore', () => expect(Validators.validateEmail(null), isNotNull));
      test('vuoto → errore', () => expect(Validators.validateEmail(''), isNotNull));
      test('senza @ → errore', () => expect(Validators.validateEmail('noemail'), isNotNull));
      test('senza dominio → errore', () => expect(Validators.validateEmail('user@'), isNotNull));
      test('email valida → null', () => expect(Validators.validateEmail('user@example.com'), isNull));
      test('email con punto → null', () {
        expect(Validators.validateEmail('first.last@domain.it'), isNull);
      });
      test('email con trattino → null', () {
        expect(Validators.validateEmail('user-name@sub.domain.org'), isNull);
      });
    });

    // ── validatePassword ──────────────────────────────────────────────────
    group('validatePassword', () {
      test('null → errore', () => expect(Validators.validatePassword(null), isNotNull));
      test('vuoto → errore', () => expect(Validators.validatePassword(''), isNotNull));
      test('5 caratteri con minLength=6 → errore', () {
        expect(Validators.validatePassword('12345'), isNotNull);
      });
      test('6 caratteri → null', () {
        expect(Validators.validatePassword('123456'), isNull);
      });
      test('minLength personalizzato', () {
        expect(Validators.validatePassword('12', minLength: 3), isNotNull);
        expect(Validators.validatePassword('123', minLength: 3), isNull);
      });
    });

    // ── validateCardCode ──────────────────────────────────────────────────
    group('validateCardCode', () {
      test('vuoto con required=true → errore', () {
        expect(Validators.validateCardCode('', required: true), isNotNull);
      });
      test('vuoto con required=false → null', () {
        expect(Validators.validateCardCode('', required: false), isNull);
      });
      test('null con required=false → null', () {
        expect(Validators.validateCardCode(null, required: false), isNull);
      });
      test('codice valido → null', () {
        expect(Validators.validateCardCode('LOB-EN005'), isNull);
      });
      test('51 caratteri → errore', () {
        expect(Validators.validateCardCode('A' * 51), isNotNull);
      });
      test('50 caratteri → null (al limite)', () {
        expect(Validators.validateCardCode('A' * 50), isNull);
      });
    });

    // ── isValidCatalog ────────────────────────────────────────────────────
    group('isValidCatalog', () {
      test('yugioh → true', () => expect(Validators.isValidCatalog('yugioh'), isTrue));
      test('pokemon → true', () => expect(Validators.isValidCatalog('pokemon'), isTrue));
      test('onepiece → true', () => expect(Validators.isValidCatalog('onepiece'), isTrue));
      test('magic → true', () => expect(Validators.isValidCatalog('magic'), isTrue));
      test('invalid → false', () => expect(Validators.isValidCatalog('digimon'), isFalse));
      test('null → false', () => expect(Validators.isValidCatalog(null), isFalse));
      test('YUGIOH maiuscolo → false (case-sensitive)', () {
        expect(Validators.isValidCatalog('YUGIOH'), isFalse);
      });
    });

    // ── isValidLanguage ───────────────────────────────────────────────────
    group('isValidLanguage', () {
      test('en → true', () => expect(Validators.isValidLanguage('en'), isTrue));
      test('it → true', () => expect(Validators.isValidLanguage('it'), isTrue));
      test('fr → true', () => expect(Validators.isValidLanguage('fr'), isTrue));
      test('de → true', () => expect(Validators.isValidLanguage('de'), isTrue));
      test('pt → true', () => expect(Validators.isValidLanguage('pt'), isTrue));
      test('sp → true', () => expect(Validators.isValidLanguage('sp'), isTrue));
      test('null → false', () => expect(Validators.isValidLanguage(null), isFalse));
      test('IT maiuscolo → false (case-sensitive)', () {
        expect(Validators.isValidLanguage('IT'), isFalse);
      });
      // BUG POTENZIALE: 'es' non è in allLanguages (usa 'sp' per lo spagnolo)
      test("'es' NON è una lingua valida secondo LanguageConstants (usa 'sp')", () {
        expect(Validators.isValidLanguage('es'), isFalse);
      });
    });
  });

  // ── StringValidation extension ────────────────────────────────────────────
  group('StringValidation extension', () {
    test('null è isNullOrEmpty', () {
      const String? s = null;
      expect(s.isNullOrEmpty, isTrue);
    });

    test('stringa vuota è isNullOrEmpty', () {
      expect(''.isNullOrEmpty, isTrue);
    });

    test('solo spazi è isNullOrEmpty', () {
      expect('   '.isNullOrEmpty, isTrue);
    });

    test('stringa non vuota NON è isNullOrEmpty', () {
      expect('hello'.isNullOrEmpty, isFalse);
    });

    test('isNotNullOrEmpty è il contrario di isNullOrEmpty', () {
      expect('hello'.isNotNullOrEmpty, isTrue);
      expect(''.isNotNullOrEmpty, isFalse);
    });
  });
}
