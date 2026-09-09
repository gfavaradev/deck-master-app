import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/models/user_model.dart';

void main() {
  final baseDate = DateTime(2026, 1, 1);

  Map<String, dynamic> baseData({
    String role = 'user',
    bool isPro = false,
    String? proExpiresAt,
  }) =>
      {
        'uid': 'uid_123',
        'email': 'test@example.com',
        'displayName': 'Mario Rossi',
        'photoUrl': null,
        'role': role,
        'createdAt': baseDate.toIso8601String(),
        'lastLoginAt': null,
        'isActive': true,
        'isPro': isPro,
        'proSource': null,
        'proExpiresAt': proExpiresAt,
      };

  group('UserModel', () {
    // ── fromFirestore / toFirestore round-trip ────────────────────────────
    group('serializzazione Firestore', () {
      test('round-trip preserva tutti i campi', () {
        final data = baseData(role: 'administrator', isPro: true);
        final user = UserModel.fromFirestore(data);
        final back = UserModel.fromFirestore(user.toFirestore());
        expect(back.uid, user.uid);
        expect(back.email, user.email);
        expect(back.role, user.role);
        expect(back.isPro, user.isPro);
      });

      test('role sconosciuto diventa user', () {
        final user = UserModel.fromFirestore(baseData(role: 'unknown_role'));
        expect(user.role, UserRole.user);
      });

      test('isActive default true se assente', () {
        final data = Map<String, dynamic>.from(baseData())..remove('isActive');
        final user = UserModel.fromFirestore(data);
        expect(user.isActive, isTrue);
      });

      test('isPro default false se assente', () {
        final data = Map<String, dynamic>.from(baseData())..remove('isPro');
        final user = UserModel.fromFirestore(data);
        expect(user.isPro, isFalse);
      });

      // Un documento utente modificato a mano in console (o scritto da una
      // versione più vecchia dello schema) può avere uid/email mancanti o un
      // createdAt malformato: prima fromFirestore andava in TypeError non
      // catturato su ogni caricamento (subscription_service, user_service).
      test('uid mancante non lancia, diventa stringa vuota', () {
        final data = Map<String, dynamic>.from(baseData())..remove('uid');
        final user = UserModel.fromFirestore(data);
        expect(user.uid, '');
      });

      test('email mancante non lancia, diventa stringa vuota', () {
        final data = Map<String, dynamic>.from(baseData())..remove('email');
        final user = UserModel.fromFirestore(data);
        expect(user.email, '');
      });

      test('createdAt mancante non lancia, ripiega su un default', () {
        final data = Map<String, dynamic>.from(baseData())..remove('createdAt');
        expect(() => UserModel.fromFirestore(data), returnsNormally);
      });

      test('createdAt malformato non lancia, ripiega su un default', () {
        final data = Map<String, dynamic>.from(baseData())..['createdAt'] = 'non-una-data';
        expect(() => UserModel.fromFirestore(data), returnsNormally);
      });

      test('lastLoginAt malformato non lancia, resta null', () {
        final data = Map<String, dynamic>.from(baseData())..['lastLoginAt'] = 'non-una-data';
        final user = UserModel.fromFirestore(data);
        expect(user.lastLoginAt, isNull);
      });
    });

    // ── isAdmin / isUser ─────────────────────────────────────────────────
    group('ruolo', () {
      test('isAdmin true per administrator', () {
        final user = UserModel.fromFirestore(baseData(role: 'administrator'));
        expect(user.isAdmin, isTrue);
        expect(user.isUser, isFalse);
      });

      test('isUser true per user', () {
        final user = UserModel.fromFirestore(baseData(role: 'user'));
        expect(user.isUser, isTrue);
        expect(user.isAdmin, isFalse);
      });
    });

    // ── hasProAccess ──────────────────────────────────────────────────────
    group('hasProAccess', () {
      test('admin ha sempre accesso pro', () {
        final user = UserModel.fromFirestore(baseData(role: 'administrator', isPro: false));
        expect(user.hasProAccess, isTrue);
      });

      test('utente non-pro → false', () {
        final user = UserModel.fromFirestore(baseData(isPro: false));
        expect(user.hasProAccess, isFalse);
      });

      test('utente pro senza scadenza → true', () {
        final user = UserModel.fromFirestore(baseData(isPro: true, proExpiresAt: null));
        expect(user.hasProAccess, isTrue);
      });

      test('utente pro con scadenza futura → true', () {
        final future = DateTime.now().add(const Duration(days: 30)).toIso8601String();
        final user = UserModel.fromFirestore(baseData(isPro: true, proExpiresAt: future));
        expect(user.hasProAccess, isTrue);
      });

      test('utente pro con scadenza passata → false', () {
        final past = DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
        final user = UserModel.fromFirestore(baseData(isPro: true, proExpiresAt: past));
        expect(user.hasProAccess, isFalse);
      });
    });

    // ── copyWith ─────────────────────────────────────────────────────────
    group('copyWith', () {
      test('cambia solo i campi specificati', () {
        final original = UserModel.fromFirestore(baseData());
        final copy = original.copyWith(displayName: 'Nuovo Nome', isPro: true);
        expect(copy.displayName, 'Nuovo Nome');
        expect(copy.isPro, isTrue);
        expect(copy.uid, original.uid);
        expect(copy.email, original.email);
        expect(copy.role, original.role);
      });
    });
  });
}
