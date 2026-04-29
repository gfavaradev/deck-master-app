import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/models/card_model.dart';

void main() {
  group('CardModel', () {
    final fullMap = {
      'id': 1,
      'firestoreId': 'fs_abc',
      'catalogId': '12345',
      'name': 'Dark Magician',
      'serialNumber': 'LOB-EN005',
      'collection': 'yugioh',
      'albumId': 2,
      'type': 'Monster Card',
      'rarity': 'Ultra Rare',
      'description': 'A powerful wizard.',
      'quantity': 3,
      'value': 4.50,
      'cardtrader_value': 5.99,
      'imageUrl': 'https://example.com/img.jpg',
    };

    // ── fromMap ──────────────────────────────────────────────────────────────
    group('fromMap', () {
      test('parsa tutti i campi correttamente', () {
        final card = CardModel.fromMap(fullMap);
        expect(card.id, 1);
        expect(card.firestoreId, 'fs_abc');
        expect(card.catalogId, '12345');
        expect(card.name, 'Dark Magician');
        expect(card.serialNumber, 'LOB-EN005');
        expect(card.collection, 'yugioh');
        expect(card.albumId, 2);
        expect(card.type, 'Monster Card');
        expect(card.rarity, 'Ultra Rare');
        expect(card.description, 'A powerful wizard.');
        expect(card.quantity, 3);
        expect(card.value, 4.50);
        expect(card.cardtraderValue, 5.99);
        expect(card.imageUrl, 'https://example.com/img.jpg');
      });

      test('usa valori di default se i campi mancano', () {
        final card = CardModel.fromMap({
          'albumId': 1,
          'collection': 'yugioh',
        });
        expect(card.name, '');
        expect(card.serialNumber, '');
        expect(card.type, '');
        expect(card.rarity, '');
        expect(card.description, '');
        expect(card.quantity, 1);
        expect(card.value, 0.0);
        expect(card.cardtraderValue, isNull);
        expect(card.imageUrl, isNull);
        expect(card.albumId, 1);
      });

      test('albumId default -1 se assente', () {
        final card = CardModel.fromMap({'name': 'Test'});
        expect(card.albumId, -1);
      });

      test('value accetta int (num)', () {
        final card = CardModel.fromMap({...fullMap, 'value': 10});
        expect(card.value, 10.0);
      });

      test('cardtrader_value accetta int (num)', () {
        final card = CardModel.fromMap({...fullMap, 'cardtrader_value': 3});
        expect(card.cardtraderValue, 3.0);
      });

      test('cardtrader_value null se chiave assente', () {
        final map = Map<String, dynamic>.from(fullMap)..remove('cardtrader_value');
        final card = CardModel.fromMap(map);
        expect(card.cardtraderValue, isNull);
      });
    });

    // ── toMap ────────────────────────────────────────────────────────────────
    group('toMap', () {
      test('serializza tutti i campi attesi', () {
        final card = CardModel.fromMap(fullMap);
        final map = card.toMap();
        expect(map['id'], 1);
        expect(map['catalogId'], '12345');
        expect(map['name'], 'Dark Magician');
        expect(map['serialNumber'], 'LOB-EN005');
        expect(map['collection'], 'yugioh');
        expect(map['albumId'], 2);
        expect(map['type'], 'Monster Card');
        expect(map['rarity'], 'Ultra Rare');
        expect(map['description'], 'A powerful wizard.');
        expect(map['quantity'], 3);
        expect(map['value'], 4.50);
        expect(map['cardtrader_value'], 5.99);
        expect(map['imageUrl'], 'https://example.com/img.jpg');
      });

      test('NON include added_at', () {
        final card = CardModel.fromMap(fullMap);
        expect(card.toMap().containsKey('added_at'), isFalse);
      });

      test('NON include firestoreId', () {
        final card = CardModel.fromMap(fullMap);
        expect(card.toMap().containsKey('firestoreId'), isFalse);
      });
    });

    // ── toFirestore ──────────────────────────────────────────────────────────
    group('toFirestore', () {
      test('include i campi corretti e albumFirestoreId', () {
        final card = CardModel.fromMap(fullMap);
        final fs = card.toFirestore(albumFirestoreId: 'album_fs_1');
        expect(fs['albumFirestoreId'], 'album_fs_1');
        expect(fs['name'], 'Dark Magician');
        expect(fs['collection'], 'yugioh');
        expect(fs.containsKey('id'), isFalse);
      });

      test('NON include value (prezzo utente non mandato su Firestore da qui)', () {
        final card = CardModel.fromMap(fullMap);
        final fs = card.toFirestore();
        expect(fs.containsKey('value'), isFalse);
      });
    });

    // ── fromFirestore ────────────────────────────────────────────────────────
    group('fromFirestore', () {
      test('parsa correttamente', () {
        final card = CardModel.fromFirestore('doc_id', {
          'catalogId': '999',
          'name': 'Blue-Eyes',
          'serialNumber': 'LOB-001',
          'collection': 'yugioh',
          'albumId': 5,
          'type': 'Monster',
          'rarity': 'Ultra Rare',
          'description': 'A dragon.',
          'quantity': 1,
          'value': 50.0,
          'cardtraderValue': 60.0,
          'imageUrl': 'https://img.url',
        });
        expect(card.firestoreId, 'doc_id');
        expect(card.name, 'Blue-Eyes');
        expect(card.cardtraderValue, 60.0);
      });

      test('usa default per campi mancanti', () {
        final card = CardModel.fromFirestore('id', {});
        expect(card.name, '');
        expect(card.albumId, -1);
        expect(card.quantity, 1);
        expect(card.value, 0.0);
      });
    });

    // ── copyWith ─────────────────────────────────────────────────────────────
    group('copyWith', () {
      test('copia immutabilmente cambiando solo i campi specificati', () {
        final original = CardModel.fromMap(fullMap);
        final copy = original.copyWith(name: 'Kuriboh', quantity: 2);
        expect(copy.name, 'Kuriboh');
        expect(copy.quantity, 2);
        expect(copy.id, original.id);
        expect(copy.collection, original.collection);
        expect(copy.value, original.value);
      });

      test('resetId=true azzera id e firestoreId', () {
        final original = CardModel.fromMap(fullMap);
        final copy = original.copyWith(resetId: true);
        expect(copy.id, isNull);
        expect(copy.firestoreId, isNull);
        expect(copy.name, original.name);
      });

      test('resetId=false (default) preserva id', () {
        final original = CardModel.fromMap(fullMap);
        final copy = original.copyWith(name: 'New');
        expect(copy.id, 1);
        expect(copy.firestoreId, 'fs_abc');
      });
    });

    // ── round-trip ───────────────────────────────────────────────────────────
    test('toMap → fromMap preserva i dati', () {
      final original = CardModel.fromMap(fullMap);
      final roundTrip = CardModel.fromMap(original.toMap());
      expect(roundTrip.name, original.name);
      expect(roundTrip.id, original.id);
      expect(roundTrip.value, original.value);
      expect(roundTrip.cardtraderValue, original.cardtraderValue);
      expect(roundTrip.quantity, original.quantity);
    });
  });
}
