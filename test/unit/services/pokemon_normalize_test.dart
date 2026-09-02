import 'package:deck_master/services/data_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Le carte Pokémon arrivano dal catalogo con `sets` per lingua e vanno
/// convertite in `prints` prima di finire in SQLite. Due difetti stavano qui:
/// l'immagine veniva cercata in `image_url` mentre il worker la scrive in
/// `artwork`, e in mancanza si ricostruiva un URL pokemontcg.io a partire da
/// `api_id` — che pero' e' "{espansione}-{blueprint CardTrader}", quindi
/// puntava a un numero di carta inesistente: un 404 per ogni carta, che l'app
/// non distingue da un'immagine mancante.
void main() {
  // Carta come la pubblica `rebuild/pokemon.ts` dopo il 03/09/2026.
  Map<String, dynamic> card({String? artwork, String lang = 'en'}) => {
        'api_id': 'pr1-273488',
        'blueprint_id': '273488',
        'name': 'Zapdos',
        'catalog': 'pokemon',
        'rarity': 'Holo Rare',
        'sets': {
          lang: [
            {
              'set_code': '15/62 ©1999',
              'set_name': 'Wizards of the Coast Era Promos',
              'rarity': 'Holo Rare',
              if (artwork != null) 'artwork': artwork,
            },
          ],
        },
      };

  test('l\'immagine della stampa viene da `artwork`', () {
    final out = DataRepository.normalizePokemonCardForSQLite(
      card(artwork: 'https://www.cardtrader.com/uploads/blueprints/image/273488/x.jpg'),
    );
    final prints = out['prints'] as List;
    expect(prints.single['artwork'],
        'https://www.cardtrader.com/uploads/blueprints/image/273488/x.jpg');
    // Serve anche a livello carta, che e' quello che la griglia mostra.
    expect(out['image_url'],
        'https://www.cardtrader.com/uploads/blueprints/image/273488/x.jpg');
  });

  test('il seriale della stampa e\' il collector number vero', () {
    final out = DataRepository.normalizePokemonCardForSQLite(card(artwork: 'https://x/y.jpg'));
    final prints = out['prints'] as List;
    expect(prints.single['set_code'], '15/62 ©1999');
  });

  test('senza immagine non si inventa un URL pokemontcg.io', () {
    final out = DataRepository.normalizePokemonCardForSQLite(card());
    expect(out['image_url'], isNull);
    final prints = out['prints'] as List;
    expect(prints.single['artwork'], isNull);
  });

  test('una carta senza inglese non sparisce', () {
    final out = DataRepository.normalizePokemonCardForSQLite(
      card(artwork: 'https://x/y.jpg', lang: 'ja'),
    );
    final prints = out['prints'] as List?;
    expect(prints, isNotNull);
    expect(prints!.single['set_code'], '15/62 ©1999');
  });

  test('una carta gia\' in forma `prints` passa intatta', () {
    final already = {
      'api_id': 'pr1-273488',
      'prints': [
        {'set_code': '15/62', 'artwork': 'https://x/y.jpg'},
      ],
    };
    expect(DataRepository.normalizePokemonCardForSQLite(already), already);
  });
}
