import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/models/onepiece_models.dart';

void main() {
  // ── OnePieceCard ────────────────────────────────────────────────────────────
  group('OnePieceCard', () {
    final fullMap = {
      'id': 1,
      'name': 'Monkey D. Luffy',
      'card_type': 'Leader',
      'color': 'Red',
      'cost': 5,
      'power': 5000,
      'life': 4,
      'sub_types': 'Straw Hat Crew',
      'counter_amount': 1000,
      'attribute': 'Strike',
      'card_text': 'Activate: Main If this Leader has 2 or more rested DON!! cards attached...',
      'image_url': 'https://optcg.example.com/images/OP01-001.png',
    };

    group('fromMap', () {
      test('parsa tutti i campi', () {
        final card = OnePieceCard.fromMap(fullMap);
        expect(card.id, 1);
        expect(card.name, 'Monkey D. Luffy');
        expect(card.cardType, 'Leader');
        expect(card.color, 'Red');
        expect(card.cost, 5);
        expect(card.power, 5000);
        expect(card.life, 4);
        expect(card.subTypes, 'Straw Hat Crew');
        expect(card.counterAmount, 1000);
        expect(card.attribute, 'Strike');
        expect(card.cardText, contains('Activate'));
        expect(card.imageUrl, contains('OP01-001'));
      });

      test('id null se assente', () {
        final card = OnePieceCard.fromMap({'name': 'Test'});
        expect(card.id, isNull);
      });

      test('name default vuoto se assente', () {
        final card = OnePieceCard.fromMap({});
        expect(card.name, '');
      });

      test('campi opzionali null se assenti', () {
        final card = OnePieceCard.fromMap({'name': 'Zoro'});
        expect(card.cardType, isNull);
        expect(card.color, isNull);
        expect(card.cost, isNull);
        expect(card.power, isNull);
        expect(card.life, isNull);
        expect(card.subTypes, isNull);
        expect(card.counterAmount, isNull);
        expect(card.attribute, isNull);
        expect(card.cardText, isNull);
        expect(card.imageUrl, isNull);
      });
    });

    group('toMap', () {
      test('include tutti i campi attesi', () {
        final card = OnePieceCard.fromMap(fullMap);
        final map = card.toMap();
        expect(map['id'], 1);
        expect(map['name'], 'Monkey D. Luffy');
        expect(map['card_type'], 'Leader');
        expect(map['color'], 'Red');
        expect(map['cost'], 5);
        expect(map['power'], 5000);
        expect(map['life'], 4);
        expect(map['sub_types'], 'Straw Hat Crew');
        expect(map['counter_amount'], 1000);
        expect(map['attribute'], 'Strike');
        expect(map['image_url'], contains('OP01-001'));
      });

      test('include created_at e updated_at (auto-generati)', () {
        final card = OnePieceCard.fromMap(fullMap);
        final map = card.toMap();
        expect(map['created_at'], isNotNull);
        expect(map['updated_at'], isNotNull);
        expect(() => DateTime.parse(map['created_at'] as String), returnsNormally);
      });
    });

    group('round-trip toMap → fromMap', () {
      test('preserva tutti i campi', () {
        final original = OnePieceCard.fromMap(fullMap);
        final rt = OnePieceCard.fromMap(original.toMap());
        expect(rt.id, original.id);
        expect(rt.name, original.name);
        expect(rt.cardType, original.cardType);
        expect(rt.color, original.color);
        expect(rt.cost, original.cost);
        expect(rt.power, original.power);
        expect(rt.life, original.life);
      });
    });
  });

  // ── OnePiecePrint ───────────────────────────────────────────────────────────
  group('OnePiecePrint', () {
    final fullMap = {
      'id': 10,
      'card_id': 1,
      'card_set_id': 'OP01-001',
      'set_id': 'OP01',
      'set_name': 'ROMANCE DAWN',
      'rarity': 'L',
      'inventory_price': 12.50,
      'market_price': 15.00,
      'artwork': 'https://firebasestorage.googleapis.com/v0/b/deck-master.appspot.com/...',
    };

    group('fromMap', () {
      test('parsa tutti i campi', () {
        final print = OnePiecePrint.fromMap(fullMap);
        expect(print.id, 10);
        expect(print.cardId, 1);
        expect(print.cardSetId, 'OP01-001');
        expect(print.setId, 'OP01');
        expect(print.setName, 'ROMANCE DAWN');
        expect(print.rarity, 'L');
        expect(print.inventoryPrice, 12.50);
        expect(print.marketPrice, 15.00);
        expect(print.artwork, contains('firebasestorage'));
      });

      test('prezzi null se assenti', () {
        final print = OnePiecePrint.fromMap({
          'card_id': 1,
          'card_set_id': 'OP01-001',
        });
        expect(print.inventoryPrice, isNull);
        expect(print.marketPrice, isNull);
        expect(print.artwork, isNull);
      });

      test('prezzi accettano int (num → double)', () {
        final print = OnePiecePrint.fromMap({
          'card_id': 1,
          'card_set_id': 'OP01-001',
          'inventory_price': 10,
          'market_price': 20,
        });
        expect(print.inventoryPrice, 10.0);
        expect(print.marketPrice, 20.0);
      });
    });

    group('toMap', () {
      test('serializza tutti i campi con chiavi corrette', () {
        final print = OnePiecePrint.fromMap(fullMap);
        final map = print.toMap();
        expect(map['id'], 10);
        expect(map['card_id'], 1);
        expect(map['card_set_id'], 'OP01-001');
        expect(map['set_id'], 'OP01');
        expect(map['set_name'], 'ROMANCE DAWN');
        expect(map['rarity'], 'L');
        expect(map['inventory_price'], 12.50);
        expect(map['market_price'], 15.00);
        expect(map['artwork'], contains('firebasestorage'));
      });
    });

    group('round-trip', () {
      test('toMap → fromMap preserva i dati', () {
        final original = OnePiecePrint.fromMap(fullMap);
        final rt = OnePiecePrint.fromMap(original.toMap());
        expect(rt.cardId, original.cardId);
        expect(rt.cardSetId, original.cardSetId);
        expect(rt.setId, original.setId);
        expect(rt.rarity, original.rarity);
        expect(rt.marketPrice, original.marketPrice);
        expect(rt.artwork, original.artwork);
      });
    });
  });
}
