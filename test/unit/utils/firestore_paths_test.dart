import 'package:flutter_test/flutter_test.dart';
import 'package:deck_master/utils/firestore_paths.dart';

void main() {
  group('FirestorePaths', () {
    const uid = 'user_abc123';
    const albumId = 'album_xyz';
    const cardId = 'card_001';
    const deckId = 'deck_001';

    // ── catalog ───────────────────────────────────────────────────────────────
    group('catalog', () {
      test("yugioh → 'yugioh_catalog'", () {
        expect(FirestorePaths.catalog('yugioh'), 'yugioh_catalog');
      });
      test("pokemon → 'pokemon_catalog'", () {
        expect(FirestorePaths.catalog('pokemon'), 'pokemon_catalog');
      });
      test("onepiece → 'onepiece_catalog'", () {
        expect(FirestorePaths.catalog('onepiece'), 'onepiece_catalog');
      });
      test("magic → 'magic_catalog'", () {
        expect(FirestorePaths.catalog('magic'), 'magic_catalog');
      });
    });

    // ── catalogMetadata ───────────────────────────────────────────────────────
    group('catalogMetadata', () {
      test('formato: {catalog}/metadata', () {
        expect(FirestorePaths.catalogMetadata('yugioh'), 'yugioh_catalog/metadata');
      });
      test('pokemon', () {
        expect(FirestorePaths.catalogMetadata('pokemon'), 'pokemon_catalog/metadata');
      });
    });

    // ── catalogChunks ─────────────────────────────────────────────────────────
    group('catalogChunks', () {
      test('formato: {catalog}/chunks/items', () {
        expect(FirestorePaths.catalogChunks('yugioh'), 'yugioh_catalog/chunks/items');
      });
    });

    // ── catalogChunk ──────────────────────────────────────────────────────────
    group('catalogChunk', () {
      test('chunk 0 → .../chunk_000', () {
        expect(FirestorePaths.catalogChunk('yugioh', 0), 'yugioh_catalog/chunks/items/chunk_000');
      });
      test('chunk 5 → .../chunk_005', () {
        expect(FirestorePaths.catalogChunk('pokemon', 5), 'pokemon_catalog/chunks/items/chunk_005');
      });
      test('chunk 100 → .../chunk_100', () {
        expect(FirestorePaths.catalogChunk('onepiece', 100), 'onepiece_catalog/chunks/items/chunk_100');
      });
    });

    // ── user ──────────────────────────────────────────────────────────────────
    group('user', () {
      test('formato: users/{uid}', () {
        expect(FirestorePaths.user(uid), 'users/$uid');
      });
    });

    // ── userCollections ───────────────────────────────────────────────────────
    group('userCollections', () {
      test('formato: users/{uid}/collections', () {
        expect(FirestorePaths.userCollections(uid), 'users/$uid/collections');
      });
    });

    // ── userCollection ────────────────────────────────────────────────────────
    group('userCollection', () {
      test('formato: users/{uid}/collections/{key}', () {
        expect(FirestorePaths.userCollection(uid, 'yugioh'), 'users/$uid/collections/yugioh');
      });
    });

    // ── userAlbums ────────────────────────────────────────────────────────────
    group('userAlbums', () {
      test('formato: users/{uid}/albums', () {
        expect(FirestorePaths.userAlbums(uid), 'users/$uid/albums');
      });
    });

    // ── userAlbum ─────────────────────────────────────────────────────────────
    group('userAlbum', () {
      test('formato: users/{uid}/albums/{albumId}', () {
        expect(FirestorePaths.userAlbum(uid, albumId), 'users/$uid/albums/$albumId');
      });
    });

    // ── userCards ─────────────────────────────────────────────────────────────
    group('userCards', () {
      test('formato: users/{uid}/cards', () {
        expect(FirestorePaths.userCards(uid), 'users/$uid/cards');
      });
    });

    // ── userCard ──────────────────────────────────────────────────────────────
    group('userCard', () {
      test('formato: users/{uid}/cards/{cardId}', () {
        expect(FirestorePaths.userCard(uid, cardId), 'users/$uid/cards/$cardId');
      });
    });

    // ── userDecks ─────────────────────────────────────────────────────────────
    group('userDecks', () {
      test('formato: users/{uid}/decks', () {
        expect(FirestorePaths.userDecks(uid), 'users/$uid/decks');
      });
    });

    // ── userDeck ──────────────────────────────────────────────────────────────
    group('userDeck', () {
      test('formato: users/{uid}/decks/{deckId}', () {
        expect(FirestorePaths.userDeck(uid, deckId), 'users/$uid/decks/$deckId');
      });
    });

    // ── consistenza path gerarchica ───────────────────────────────────────────
    group('consistenza gerarchica', () {
      test('userCard è figlio di userCards', () {
        final parent = FirestorePaths.userCards(uid);
        final child = FirestorePaths.userCard(uid, cardId);
        expect(child, startsWith(parent));
        expect(child, '$parent/$cardId');
      });

      test('userAlbum è figlio di userAlbums', () {
        expect(FirestorePaths.userAlbum(uid, albumId),
            '${FirestorePaths.userAlbums(uid)}/$albumId');
      });

      test('userDeck è figlio di userDecks', () {
        expect(FirestorePaths.userDeck(uid, deckId),
            '${FirestorePaths.userDecks(uid)}/$deckId');
      });

      test('catalogChunk è figlio di catalogChunks', () {
        expect(FirestorePaths.catalogChunk('yugioh', 0),
            '${FirestorePaths.catalogChunks('yugioh')}/chunk_000');
      });
    });

    // ── nessun slash finale ───────────────────────────────────────────────────
    test('nessun path termina con /', () {
      final paths = [
        FirestorePaths.catalog('yugioh'),
        FirestorePaths.catalogMetadata('yugioh'),
        FirestorePaths.catalogChunks('yugioh'),
        FirestorePaths.catalogChunk('yugioh', 0),
        FirestorePaths.user(uid),
        FirestorePaths.userCollections(uid),
        FirestorePaths.userCollection(uid, 'yugioh'),
        FirestorePaths.userAlbums(uid),
        FirestorePaths.userAlbum(uid, albumId),
        FirestorePaths.userCards(uid),
        FirestorePaths.userCard(uid, cardId),
        FirestorePaths.userDecks(uid),
        FirestorePaths.userDeck(uid, deckId),
      ];
      for (final p in paths) {
        expect(p.endsWith('/'), isFalse, reason: '$p non dovrebbe terminare con /');
      }
    });
  });
}
