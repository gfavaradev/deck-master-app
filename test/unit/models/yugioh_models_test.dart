import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/models/yugioh_models.dart';

void main() {
  // ── YugiohCard ──────────────────────────────────────────────────────────────
  group('YugiohCard', () {
    Map<String, dynamic> baseMap({
      String? nameIt, String? descIt,
      String? nameFr, String? descFr,
      String? nameDe, String? descDe,
      String? namePt, String? descPt,
    }) =>
        {
          'id': 46986414,
          'type': 'Monster Card',
          'human_readable_type': 'Normal Monster',
          'frame_type': 'normal',
          'race': 'Spellcaster',
          'archetype': 'Dark Magician',
          'ygoprodeck_url': 'https://ygoprodeck.com/card/dark-magician',
          'atk': 2500,
          'def': 2100,
          'level': 7,
          'attribute': 'DARK',
          'scale': null,
          'linkval': null,
          'linkmarkers': null,
          'name': 'Dark Magician',
          'description': 'The ultimate wizard in terms of attack and defense.',
          'name_it': nameIt,
          'description_it': descIt,
          'name_fr': nameFr,
          'description_fr': descFr,
          'name_de': nameDe,
          'description_de': descDe,
          'name_pt': namePt,
          'description_pt': descPt,
        };

    // ── fromMap ────────────────────────────────────────────────────────────
    group('fromMap', () {
      test('parsa tutti i campi base', () {
        final card = YugiohCard.fromMap(baseMap());
        expect(card.id, 46986414);
        expect(card.type, 'Monster Card');
        expect(card.race, 'Spellcaster');
        expect(card.name, 'Dark Magician');
        expect(card.description, contains('ultimate wizard'));
        expect(card.atk, 2500);
        expect(card.def, 2100);
        expect(card.level, 7);
        expect(card.attribute, 'DARK');
      });

      test('campi opzionali null se assenti', () {
        final card = YugiohCard.fromMap(baseMap());
        expect(card.scale, isNull);
        expect(card.linkval, isNull);
        expect(card.linkmarkers, isNull);
        expect(card.nameIt, isNull);
        expect(card.nameIt, isNull);
      });

      test('traduzioni parsate se presenti', () {
        final card = YugiohCard.fromMap(baseMap(
          nameIt: 'Mago Nero',
          descIt: 'Il mago supremo.',
          nameFr: 'Magicien Sombre',
        ));
        expect(card.nameIt, 'Mago Nero');
        expect(card.descriptionIt, 'Il mago supremo.');
        expect(card.nameFr, 'Magicien Sombre');
        expect(card.descriptionFr, isNull);
      });

      test('defaults per name e description se null', () {
        final card = YugiohCard.fromMap({'id': 1, 'type': 'T', 'race': 'R'});
        expect(card.name, '');
        expect(card.description, '');
      });
    });

    // ── getLocalizedName ───────────────────────────────────────────────────
    group('getLocalizedName', () {
      final card = YugiohCard.fromMap(baseMap(
        nameIt: 'Mago Nero', nameFr: 'Magicien Sombre',
        nameDe: 'Dunkler Magier', namePt: 'Mago Negro',
      ));

      test('IT → nameIt', () => expect(card.getLocalizedName('IT'), 'Mago Nero'));
      test('it (lowercase) → nameIt', () => expect(card.getLocalizedName('it'), 'Mago Nero'));
      test('FR → nameFr', () => expect(card.getLocalizedName('FR'), 'Magicien Sombre'));
      test('DE → nameDe', () => expect(card.getLocalizedName('DE'), 'Dunkler Magier'));
      test('PT → namePt', () => expect(card.getLocalizedName('PT'), 'Mago Negro'));
      test('EN → name base', () => expect(card.getLocalizedName('EN'), 'Dark Magician'));
      test('lingua sconosciuta → name base', () => expect(card.getLocalizedName('ZH'), 'Dark Magician'));

      test('fallback a base se traduzione è null', () {
        final noTransCard = YugiohCard.fromMap(baseMap());
        expect(noTransCard.getLocalizedName('IT'), 'Dark Magician');
        expect(noTransCard.getLocalizedName('FR'), 'Dark Magician');
      });
    });

    // ── getLocalizedDescription ────────────────────────────────────────────
    group('getLocalizedDescription', () {
      final card = YugiohCard.fromMap(baseMap(
        descIt: 'Il mago supremo.', descFr: 'Le mage suprême.',
        descDe: 'Der ultimative Zauberer.', descPt: 'O mago supremo.',
      ));

      test('IT → descriptionIt', () => expect(card.getLocalizedDescription('IT'), 'Il mago supremo.'));
      test('FR → descriptionFr', () => expect(card.getLocalizedDescription('FR'), 'Le mage suprême.'));
      test('DE → descriptionDe', () => expect(card.getLocalizedDescription('DE'), 'Der ultimative Zauberer.'));
      test('PT → descriptionPt', () => expect(card.getLocalizedDescription('PT'), 'O mago supremo.'));
      test('EN → description base', () {
        expect(card.getLocalizedDescription('EN'), contains('ultimate wizard'));
      });
      test('fallback a base se null', () {
        final noDesc = YugiohCard.fromMap(baseMap());
        expect(noDesc.getLocalizedDescription('IT'), contains('ultimate wizard'));
      });
    });

    // ── toMap round-trip ───────────────────────────────────────────────────
    group('toMap round-trip', () {
      test('preserva tutti i campi', () {
        final original = YugiohCard.fromMap(baseMap(nameIt: 'Mago Nero'));
        final rt = YugiohCard.fromMap(original.toMap());
        expect(rt.id, original.id);
        expect(rt.name, original.name);
        expect(rt.nameIt, original.nameIt);
        expect(rt.atk, original.atk);
        expect(rt.level, original.level);
        expect(rt.attribute, original.attribute);
      });
    });
  });

  // ── YugiohPrint ─────────────────────────────────────────────────────────────
  group('YugiohPrint', () {
    final fullMap = {
      'id': 5,
      'card_id': 46986414,
      'set_code': 'LOB-EN005',
      'set_name': 'Legend of Blue Eyes White Dragon',
      'rarity': 'Ultra Rare',
      'rarity_code': 'UR',
      'set_price': 12.50,
      'artwork': 'https://firebasestorage.googleapis.com/v0/b/test/artwork.jpg',
      'set_name_it': 'Leggenda dell\'Occhio Blu',
      'set_code_it': 'LOB-IT005',
      'rarity_it': 'Ultra Rara',
      'rarity_code_it': 'UR',
      'set_price_it': 11.00,
      'set_name_fr': 'Légende de l\'Oeil Blanc',
      'set_code_fr': 'LOB-FR005',
      'rarity_fr': 'Ultra Rare',
      'rarity_code_fr': 'UR',
      'set_price_fr': 10.50,
      'set_name_de': 'Legende des Blauen Auges',
      'set_code_de': 'LOB-DE005',
      'rarity_de': 'Ultra Selten',
      'rarity_code_de': 'UR',
      'set_price_de': 9.80,
      'set_name_pt': 'Lenda do Olho Azul',
      'set_code_pt': 'LOB-PT005',
      'rarity_pt': 'Ultra Rara',
      'rarity_code_pt': 'UR',
      'set_price_pt': 10.00,
    };

    group('fromMap', () {
      test('parsa tutti i campi EN', () {
        final print = YugiohPrint.fromMap(fullMap);
        expect(print.cardId, 46986414);
        expect(print.setCode, 'LOB-EN005');
        expect(print.setName, 'Legend of Blue Eyes White Dragon');
        expect(print.rarity, 'Ultra Rare');
        expect(print.rarityCode, 'UR');
        expect(print.setPrice, 12.50);
      });

      test('parsa tutti i campi IT', () {
        final print = YugiohPrint.fromMap(fullMap);
        expect(print.setCodeIt, 'LOB-IT005');
        expect(print.setNameIt, 'Leggenda dell\'Occhio Blu');
        expect(print.rarityIt, 'Ultra Rara');
        expect(print.setPriceIt, 11.00);
      });

      test('defaults vuoti per setCode/setName/rarity', () {
        final print = YugiohPrint.fromMap({'card_id': 1});
        expect(print.setCode, '');
        expect(print.setName, '');
        expect(print.rarity, '');
      });
    });

    group('getLocalizedSetName', () {
      final print = YugiohPrint.fromMap(fullMap);
      test('IT → setNameIt', () => expect(print.getLocalizedSetName('IT'), 'Leggenda dell\'Occhio Blu'));
      test('FR → setNameFr', () => expect(print.getLocalizedSetName('FR'), 'Légende de l\'Oeil Blanc'));
      test('DE → setNameDe', () => expect(print.getLocalizedSetName('DE'), 'Legende des Blauen Auges'));
      test('PT → setNamePt', () => expect(print.getLocalizedSetName('PT'), 'Lenda do Olho Azul'));
      test('EN → setName base', () => expect(print.getLocalizedSetName('EN'), contains('Legend of Blue Eyes')));
      test('fallback a base se null', () {
        final noTrans = YugiohPrint.fromMap({'card_id': 1, 'set_code': 'X', 'set_name': 'Base', 'rarity': 'R'});
        expect(noTrans.getLocalizedSetName('IT'), 'Base');
      });
    });

    group('getLocalizedSetCode', () {
      final print = YugiohPrint.fromMap(fullMap);
      test('IT → setCodeIt', () => expect(print.getLocalizedSetCode('IT'), 'LOB-IT005'));
      test('FR → setCodeFr', () => expect(print.getLocalizedSetCode('FR'), 'LOB-FR005'));
      test('EN → setCode base', () => expect(print.getLocalizedSetCode('EN'), 'LOB-EN005'));
      test('lingua sconosciuta → setCode base', () => expect(print.getLocalizedSetCode('ZH'), 'LOB-EN005'));
    });

    group('getLocalizedRarity', () {
      final print = YugiohPrint.fromMap(fullMap);
      test('IT → rarityIt', () => expect(print.getLocalizedRarity('IT'), 'Ultra Rara'));
      test('DE → rarityDe', () => expect(print.getLocalizedRarity('DE'), 'Ultra Selten'));
      test('EN → rarity base', () => expect(print.getLocalizedRarity('EN'), 'Ultra Rare'));
    });

    group('getLocalizedRarityCode', () {
      final print = YugiohPrint.fromMap(fullMap);
      test('IT → rarityCodeIt', () => expect(print.getLocalizedRarityCode('IT'), 'UR'));
      test('EN → rarityCode base', () => expect(print.getLocalizedRarityCode('EN'), 'UR'));
      test('null se rarity code non presente', () {
        final noCode = YugiohPrint.fromMap({'card_id': 1, 'set_code': 'X', 'set_name': 'Y', 'rarity': 'R'});
        expect(noCode.getLocalizedRarityCode('IT'), isNull);
      });
    });

    group('getLocalizedPrice', () {
      final print = YugiohPrint.fromMap(fullMap);
      test('IT → setPriceIt', () => expect(print.getLocalizedPrice('IT'), 11.00));
      test('FR → setPriceFr', () => expect(print.getLocalizedPrice('FR'), 10.50));
      test('DE → setPriceDe', () => expect(print.getLocalizedPrice('DE'), 9.80));
      test('PT → setPricePt', () => expect(print.getLocalizedPrice('PT'), 10.00));
      test('EN → setPrice base', () => expect(print.getLocalizedPrice('EN'), 12.50));
      test('fallback a setPrice se traduzione è null', () {
        final noItPrice = YugiohPrint.fromMap({
          'card_id': 1, 'set_code': 'X', 'set_name': 'Y', 'rarity': 'R', 'set_price': 5.0,
        });
        expect(noItPrice.getLocalizedPrice('IT'), 5.0);
      });
      test('null se nessun prezzo disponibile', () {
        final noPrice = YugiohPrint.fromMap({'card_id': 1, 'set_code': 'X', 'set_name': 'Y', 'rarity': 'R'});
        expect(noPrice.getLocalizedPrice('EN'), isNull);
        expect(noPrice.getLocalizedPrice('IT'), isNull);
      });
    });

    group('round-trip', () {
      test('toMap → fromMap preserva tutti i campi', () {
        final original = YugiohPrint.fromMap(fullMap);
        final rt = YugiohPrint.fromMap(original.toMap());
        expect(rt.setCode, original.setCode);
        expect(rt.setCodeIt, original.setCodeIt);
        expect(rt.setPrice, original.setPrice);
        expect(rt.setPriceIt, original.setPriceIt);
        expect(rt.rarityCode, original.rarityCode);
        expect(rt.artwork, original.artwork);
      });
    });
  });

  // ── YugiohPrice ─────────────────────────────────────────────────────────────
  group('YugiohPrice', () {
    final fullMap = {
      'id': 1,
      'print_id': 5,
      'language': 'EN',
      'cardmarket_price': 12.50,
      'tcgplayer_price': 14.00,
      'ebay_price': 11.00,
      'amazon_price': 13.00,
      'coolstuffinc_price': 10.50,
    };

    test('fromMap parsa tutti i campi', () {
      final price = YugiohPrice.fromMap(fullMap);
      expect(price.id, 1);
      expect(price.printId, 5);
      expect(price.language, 'EN');
      expect(price.cardmarketPrice, 12.50);
      expect(price.tcgplayerPrice, 14.00);
      expect(price.ebayPrice, 11.00);
      expect(price.amazonPrice, 13.00);
      expect(price.coolstuffincPrice, 10.50);
    });

    test('prezzi null se assenti', () {
      final price = YugiohPrice.fromMap({'print_id': 1});
      expect(price.language, 'EN');
      expect(price.cardmarketPrice, isNull);
      expect(price.tcgplayerPrice, isNull);
    });

    test('prezzi accettano int (num → double)', () {
      final price = YugiohPrice.fromMap({'print_id': 1, 'cardmarket_price': 10});
      expect(price.cardmarketPrice, 10.0);
    });

    test('round-trip toMap → fromMap', () {
      final original = YugiohPrice.fromMap(fullMap);
      final rt = YugiohPrice.fromMap(original.toMap());
      expect(rt.printId, original.printId);
      expect(rt.language, original.language);
      expect(rt.cardmarketPrice, original.cardmarketPrice);
      expect(rt.tcgplayerPrice, original.tcgplayerPrice);
    });
  });
}
