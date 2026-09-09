import 'dart:io';

import 'package:deck_master/models/card_model.dart';
import 'package:deck_master/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// `deleteCard`/`deleteDeck` non ripulivano mai `deck_cards`: lo schema
/// dichiara `ON DELETE CASCADE`, ma `PRAGMA foreign_keys` non viene mai
/// attivato in questo file, quindi le cascade sono inerti. Le righe orfane
/// restavano per sempre e falsavano i conteggi dei mazzi
/// (getDecksByCollection le contava, getDeckCards con la sua INNER JOIN no).
void main() {
  late DatabaseHelper helper;
  late Database db;
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('dm_deck_card_deletion_');
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
  });

  Future<int> addCard({int albumId = 1}) => helper.insertCard(CardModel(
        name: 'Carta test',
        serialNumber: 'SN-1',
        collection: 'yugioh',
        albumId: albumId,
        type: '',
        rarity: '',
        description: '',
        quantity: 1,
        value: 0,
      ));

  test('deleteCard rimuove anche le righe deck_cards che la referenziano', () async {
    final deckId = await helper.insertDeck('Mazzo', 'yugioh');
    final cardId = await addCard();
    await helper.addCardToDeck(deckId, cardId, 2);

    await helper.deleteCard(cardId);

    final remaining = await db.query('deck_cards', where: 'cardId = ?', whereArgs: [cardId]);
    expect(remaining, isEmpty);
  });

  test('deleteDeck rimuove tutte le righe deck_cards di quel mazzo', () async {
    final deckId = await helper.insertDeck('Mazzo', 'yugioh');
    final cardId1 = await addCard();
    final cardId2 = await addCard();
    await helper.addCardToDeck(deckId, cardId1, 1);
    await helper.addCardToDeck(deckId, cardId2, 3);

    await helper.deleteDeck(deckId);

    final remaining = await db.query('deck_cards', where: 'deckId = ?', whereArgs: [deckId]);
    expect(remaining, isEmpty);
  });

  test('deleteDeck non tocca le righe deck_cards di un altro mazzo', () async {
    final deckA = await helper.insertDeck('Mazzo A', 'yugioh');
    final deckB = await helper.insertDeck('Mazzo B', 'yugioh');
    final cardId = await addCard();
    await helper.addCardToDeck(deckA, cardId, 1);
    await helper.addCardToDeck(deckB, cardId, 1);

    await helper.deleteDeck(deckA);

    final remaining = await db.query('deck_cards', where: 'deckId = ?', whereArgs: [deckB]);
    expect(remaining, hasLength(1));
  });

  test('deleteCard su una riga con quantity NULL non lancia (schema senza NOT NULL)', () async {
    final id = await db.insert('cards', {
      'name': 'Carta senza quantity',
      'serialNumber': 'SN-2',
      'collection': 'pokemon', // non-yugioh: passa dal ramo catalog_card_sets
      'albumId': 1,
      'quantity': null,
      'value': 0.0,
      'rarity': '',
      'catalogId': null,
    });

    await expectLater(helper.deleteCard(id), completes);
  });

  test('updateCard su vecchia riga con quantity NULL non lancia', () async {
    final id = await db.insert('cards', {
      'name': 'Carta senza quantity',
      'serialNumber': 'SN-3',
      'collection': 'pokemon',
      'albumId': 1,
      'quantity': null,
      'value': 0.0,
      'rarity': '',
      'catalogId': 'cat-1',
    });

    final updated = CardModel(
      id: id,
      name: 'Carta senza quantity',
      serialNumber: 'SN-3',
      collection: 'pokemon',
      albumId: 1,
      type: '',
      rarity: '',
      description: '',
      quantity: 2,
      value: 0,
      catalogId: 'cat-1',
    );

    await expectLater(helper.updateCard(updated), completes);
  });
}
