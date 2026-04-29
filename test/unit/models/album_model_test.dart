import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/models/album_model.dart';

void main() {
  group('AlbumModel', () {
    final fullMap = {
      'id': 10,
      'firestoreId': 'fs_album_1',
      'name': 'Album Principale',
      'collection': 'yugioh',
      'maxCapacity': 500,
      'currentCount': 42,
    };

    // ── fromMap ──────────────────────────────────────────────────────────────
    group('fromMap', () {
      test('parsa tutti i campi', () {
        final album = AlbumModel.fromMap(fullMap);
        expect(album.id, 10);
        expect(album.firestoreId, 'fs_album_1');
        expect(album.name, 'Album Principale');
        expect(album.collection, 'yugioh');
        expect(album.maxCapacity, 500);
        expect(album.currentCount, 42);
      });

      test('currentCount default 0 se assente', () {
        final album = AlbumModel.fromMap({
          'name': 'Test',
          'collection': 'pokemon',
          'maxCapacity': 100,
        });
        expect(album.currentCount, 0);
      });
    });

    // ── toMap ────────────────────────────────────────────────────────────────
    group('toMap', () {
      test('non include currentCount (non persisto in DB albums table)', () {
        final album = AlbumModel.fromMap(fullMap);
        expect(album.toMap().containsKey('currentCount'), isFalse);
      });

      test('include i campi attesi', () {
        final album = AlbumModel.fromMap(fullMap);
        final map = album.toMap();
        expect(map['id'], 10);
        expect(map['name'], 'Album Principale');
        expect(map['collection'], 'yugioh');
        expect(map['maxCapacity'], 500);
      });
    });

    // ── toFirestore / fromFirestore ──────────────────────────────────────────
    group('Firestore', () {
      test('toFirestore non include id né firestoreId', () {
        final album = AlbumModel.fromMap(fullMap);
        final fs = album.toFirestore();
        expect(fs.containsKey('id'), isFalse);
        expect(fs.containsKey('firestoreId'), isFalse);
        expect(fs['name'], 'Album Principale');
        expect(fs['collection'], 'yugioh');
        expect(fs['maxCapacity'], 500);
      });

      test('fromFirestore imposta firestoreId dal docId', () {
        final album = AlbumModel.fromFirestore('fs_doc_99', {
          'name': 'Binder',
          'collection': 'onepiece',
          'maxCapacity': 200,
        });
        expect(album.firestoreId, 'fs_doc_99');
        expect(album.name, 'Binder');
        expect(album.maxCapacity, 200);
        expect(album.id, isNull);
      });

      test('fromFirestore usa maxCapacity default 100 se assente', () {
        final album = AlbumModel.fromFirestore('id', {'name': 'X', 'collection': 'pokemon'});
        expect(album.maxCapacity, 100);
      });
    });

    // ── copyWith ─────────────────────────────────────────────────────────────
    group('copyWith', () {
      test('cambia solo i campi specificati', () {
        final original = AlbumModel.fromMap(fullMap);
        final copy = original.copyWith(name: 'Nuovo Album', maxCapacity: 300);
        expect(copy.name, 'Nuovo Album');
        expect(copy.maxCapacity, 300);
        expect(copy.id, original.id);
        expect(copy.collection, original.collection);
        expect(copy.currentCount, original.currentCount);
      });
    });

    // ── round-trip ───────────────────────────────────────────────────────────
    test('toMap → fromMap preserva i dati (eccetto currentCount da DB)', () {
      final original = AlbumModel.fromMap(fullMap);
      final rt = AlbumModel.fromMap(original.toMap());
      expect(rt.id, original.id);
      expect(rt.name, original.name);
      expect(rt.collection, original.collection);
      expect(rt.maxCapacity, original.maxCapacity);
      // currentCount non è in toMap → default 0 sul round-trip
      expect(rt.currentCount, 0);
    });
  });
}
