import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/models/pending_catalog_change.dart';

void main() {
  final baseTimestamp = DateTime(2026, 4, 28, 12, 0, 0);

  group('PendingCatalogChange', () {
    Map<String, dynamic> baseMap(String type) => {
      'changeId': 'change_001',
      'type': type,
      'cardData': {'id': 123, 'name': 'Dark Magician'},
      'originalCardId': 123,
      'timestamp': baseTimestamp.toIso8601String(),
      'adminUid': 'admin_uid_xyz',
    };

    // ── fromMap ──────────────────────────────────────────────────────────────
    group('fromMap', () {
      test('parsa un cambiamento di tipo add', () {
        final change = PendingCatalogChange.fromMap(baseMap('add'));
        expect(change.changeId, 'change_001');
        expect(change.type, ChangeType.add);
        expect(change.cardData['name'], 'Dark Magician');
        expect(change.originalCardId, 123);
        expect(change.timestamp, baseTimestamp);
        expect(change.adminUid, 'admin_uid_xyz');
      });

      test('parsa tipo edit', () {
        final change = PendingCatalogChange.fromMap(baseMap('edit'));
        expect(change.type, ChangeType.edit);
      });

      test('parsa tipo delete', () {
        final change = PendingCatalogChange.fromMap(baseMap('delete'));
        expect(change.type, ChangeType.delete);
      });

      test('originalCardId può essere null', () {
        final map = Map<String, dynamic>.from(baseMap('add'))..remove('originalCardId');
        final change = PendingCatalogChange.fromMap(map);
        expect(change.originalCardId, isNull);
      });

      test('tipo non riconosciuto → throws (firstWhere senza orElse)', () {
        final map = {...baseMap('add'), 'type': 'unknown'};
        expect(() => PendingCatalogChange.fromMap(map), throwsStateError);
      });
    });

    // ── toMap ────────────────────────────────────────────────────────────────
    group('toMap', () {
      test('serializza tutti i campi', () {
        final change = PendingCatalogChange(
          changeId: 'change_001',
          type: ChangeType.add,
          cardData: {'id': 123, 'name': 'Dark Magician'},
          originalCardId: 123,
          timestamp: baseTimestamp,
          adminUid: 'admin_uid_xyz',
        );
        final map = change.toMap();
        expect(map['changeId'], 'change_001');
        expect(map['type'], 'add');
        expect((map['cardData'] as Map)['name'], 'Dark Magician');
        expect(map['originalCardId'], 123);
        expect(map['timestamp'], baseTimestamp.toIso8601String());
        expect(map['adminUid'], 'admin_uid_xyz');
      });

      test('type serializzato come stringa (non enum)', () {
        final change = PendingCatalogChange(
          changeId: 'id', type: ChangeType.edit,
          cardData: {}, timestamp: baseTimestamp, adminUid: 'uid',
        );
        expect(change.toMap()['type'], 'edit');
        expect(change.toMap()['type'], isA<String>());
      });
    });

    // ── round-trip ───────────────────────────────────────────────────────────
    test('toMap → fromMap round-trip', () {
      final original = PendingCatalogChange(
        changeId: 'change_abc',
        type: ChangeType.delete,
        cardData: {'id': 999, 'name': 'Test'},
        originalCardId: 999,
        timestamp: baseTimestamp,
        adminUid: 'uid_test',
      );
      final rt = PendingCatalogChange.fromMap(original.toMap());
      expect(rt.changeId, original.changeId);
      expect(rt.type, original.type);
      expect(rt.originalCardId, original.originalCardId);
      expect(rt.timestamp, original.timestamp);
      expect(rt.adminUid, original.adminUid);
    });
  });

  // ── ChangeType enum ──────────────────────────────────────────────────────────
  group('ChangeType', () {
    test('contiene i valori attesi', () {
      expect(ChangeType.values, containsAll([ChangeType.add, ChangeType.edit, ChangeType.delete]));
      expect(ChangeType.values.length, 3);
    });

    test('nomi corrispondono alle stringhe usate in toMap', () {
      expect(ChangeType.add.toString().split('.').last, 'add');
      expect(ChangeType.edit.toString().split('.').last, 'edit');
      expect(ChangeType.delete.toString().split('.').last, 'delete');
    });
  });
}
