import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/models/collection_model.dart';

void main() {
  group('CollectionModel', () {
    // ── fromMap ──────────────────────────────────────────────────────────────
    group('fromMap', () {
      test('parsa tutti i campi (isUnlocked = 1)', () {
        final col = CollectionModel.fromMap({'id': 'yugioh', 'name': 'Yu-Gi-Oh!', 'isUnlocked': 1});
        expect(col.key, 'yugioh');
        expect(col.name, 'Yu-Gi-Oh!');
        expect(col.isUnlocked, isTrue);
      });

      test('isUnlocked false se valore 0', () {
        final col = CollectionModel.fromMap({'id': 'pokemon', 'name': 'Pokémon', 'isUnlocked': 0});
        expect(col.isUnlocked, isFalse);
      });

      test('isUnlocked default false se assente', () {
        final col = CollectionModel.fromMap({'id': 'magic', 'name': 'Magic'});
        expect(col.isUnlocked, isFalse);
      });
    });

    // ── toMap ────────────────────────────────────────────────────────────────
    group('toMap', () {
      test('usa chiave id per key', () {
        final col = CollectionModel(key: 'onepiece', name: 'One Piece', isUnlocked: true);
        final map = col.toMap();
        expect(map['id'], 'onepiece');
        expect(map['name'], 'One Piece');
        expect(map['isUnlocked'], 1);
      });

      test('isUnlocked false → 0', () {
        final col = CollectionModel(key: 'magic', name: 'Magic', isUnlocked: false);
        expect(col.toMap()['isUnlocked'], 0);
      });
    });

    // ── toFirestore / fromFirestore ──────────────────────────────────────────
    group('toFirestore', () {
      test('non include key (usa docId come chiave Firestore)', () {
        final col = CollectionModel(key: 'yugioh', name: 'Yu-Gi-Oh!', isUnlocked: true);
        final fs = col.toFirestore();
        expect(fs.containsKey('id'), isFalse);
        expect(fs['name'], 'Yu-Gi-Oh!');
        expect(fs['isUnlocked'], isTrue);
      });

      test('isUnlocked come bool (non int) su Firestore', () {
        final col = CollectionModel(key: 'pokemon', name: 'Pokémon', isUnlocked: true);
        expect(col.toFirestore()['isUnlocked'], isTrue);
        expect(col.toFirestore()['isUnlocked'], isNot(1));
      });
    });

    group('fromFirestore', () {
      test('imposta key da docId', () {
        final col = CollectionModel.fromFirestore('yugioh', {'name': 'Yu-Gi-Oh!', 'isUnlocked': true});
        expect(col.key, 'yugioh');
        expect(col.name, 'Yu-Gi-Oh!');
        expect(col.isUnlocked, isTrue);
      });

      test('name fallback a docId se assente', () {
        final col = CollectionModel.fromFirestore('magic', {});
        expect(col.name, 'magic');
        expect(col.isUnlocked, isFalse);
      });
    });

    // ── round-trip ───────────────────────────────────────────────────────────
    test('toMap → fromMap round-trip (campo id → key)', () {
      final original = CollectionModel(key: 'onepiece', name: 'One Piece TCG', isUnlocked: true);
      final rt = CollectionModel.fromMap(original.toMap());
      expect(rt.key, original.key);
      expect(rt.name, original.name);
      expect(rt.isUnlocked, original.isUnlocked);
    });
  });
}
