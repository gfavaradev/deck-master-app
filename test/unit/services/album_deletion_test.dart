import 'dart:io';

import 'package:deck_master/models/album_model.dart';
import 'package:deck_master/models/card_model.dart';
import 'package:deck_master/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// `DataRepository.deleteAlbum` cancellava solo la riga `albums`: le carte
/// che ci stavano dentro restavano con un `albumId` che non esisteva più e
/// riapparivano senza album nella vista generale della collezione (che
/// mostra tutto tranne l'album Doppioni). Questi test coprono la parte
/// SQLite del fix: la query dei figli da cascare, la pulizia di
/// `batchDeleteCardsByIds` (che non toccava mai `deck_cards`, stesso difetto
/// già corretto per `deleteCard` singolo) e il self-heal per gli orfani
/// creati dal bug prima di questo fix.
void main() {
  late DatabaseHelper helper;
  late Database db;
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('dm_album_deletion_');
    await databaseFactory.setDatabasesPath(tempDir.path);
    helper = DatabaseHelper();
    db = await helper.database;
  });

  tearDownAll(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await db.delete('deck_cards');
    await db.delete('decks');
    await db.delete('cards');
    await db.delete('albums');
  });

  Future<int> addAlbum(String name) =>
      helper.insertAlbum(AlbumModel(name: name, collection: 'yugioh', maxCapacity: 100));

  Future<int> addCard({required int albumId, String serial = 'SN-1'}) =>
      helper.insertCard(CardModel(
        name: 'Carta test',
        serialNumber: serial,
        collection: 'yugioh',
        albumId: albumId,
        type: '',
        rarity: '',
        description: '',
        quantity: 1,
        value: 0,
      ));

  test('getCardsByAlbumId restituisce solo le carte di quell\'album', () async {
    final albumA = await addAlbum('Album A');
    final albumB = await addAlbum('Album B');
    await addCard(albumId: albumA, serial: 'A-1');
    await addCard(albumId: albumA, serial: 'A-2');
    await addCard(albumId: albumB, serial: 'B-1');

    final cardsInA = await helper.getCardsByAlbumId(albumA);

    expect(cardsInA, hasLength(2));
    expect(cardsInA.map((c) => c.serialNumber), containsAll(['A-1', 'A-2']));
  });

  test('batchDeleteCardsByIds ripulisce anche le righe deck_cards che referenziano le carte', () async {
    final albumId = await addAlbum('Album');
    final cardId = await addCard(albumId: albumId);
    final deckId = await helper.insertDeck('Mazzo', 'yugioh');
    await helper.addCardToDeck(deckId, cardId, 2);

    await helper.batchDeleteCardsByIds([cardId]);

    final remaining = await db.query('deck_cards', where: 'cardId = ?', whereArgs: [cardId]);
    expect(remaining, isEmpty);
  });

  group('getCardsWithInvalidAlbum — self-heal degli orfani da album cancellati', () {
    test('trova le carte il cui albumId non corrisponde a nessun album', () async {
      final albumId = await addAlbum('Album da cancellare');
      final cardId = await addCard(albumId: albumId);
      // Simula il bug pre-fix: la riga album viene rimossa senza cascare le carte.
      await db.delete('albums', where: 'id = ?', whereArgs: [albumId]);

      final orphans = await helper.getCardsWithInvalidAlbum();

      expect(orphans.map((c) => c.id), contains(cardId));
    });

    test('ignora le carte di catalogo (albumId = -1)', () async {
      await addCard(albumId: -1);

      final orphans = await helper.getCardsWithInvalidAlbum();

      expect(orphans, isEmpty);
    });

    test('ignora le carte il cui album esiste ancora', () async {
      final albumId = await addAlbum('Album vivo');
      await addCard(albumId: albumId);

      final orphans = await helper.getCardsWithInvalidAlbum();

      expect(orphans, isEmpty);
    });
  });
}
