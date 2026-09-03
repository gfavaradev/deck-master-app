import 'package:deck_master/services/data_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// La derivazione dei set code localizzati ("JUSH-EN040" → "JUSH-IT040")
/// esiste in DUE implementazioni: il worker la usa per scrivere il catalogo
/// (`rebuild/yugioh.ts`, `convertSetCodeLang`), l'app per ritrovare la stampa
/// localizzata a partire da quella inglese (`toLocalCode`). Se divergono, le
/// colonne `set_code_it` e simili restano vuote e Yu-Gi-Oh torna monolingue.
///
/// La carta qui sotto è reale: presa da `yugioh_catalog` dopo il rebuild del
/// 03/09/2026, che ha riportato il catalogo a cinque lingue dopo che ne aveva
/// due (`en` e una manciata di `pt`).
void main() {
  Map<String, dynamic> jushCard() => {
        'id': 80181649,
        'name': '"A Case for K9"',
        'sets': {
          'en': [
            {
              'set_code': 'JUSH-EN040',
              'print_code': 'JUSH-EN040',
              'set_name': 'Justice Hunters',
              'rarity': 'Starlight Rare',
              'rarity_code': '(StR)',
            },
          ],
          for (final l in ['it', 'fr', 'de', 'pt'])
            l: [
              {
                'set_code': 'JUSH-${l.toUpperCase()}040',
                'print_code': 'JUSH-${l.toUpperCase()}040',
                'set_name': 'Justice Hunters',
                'rarity': 'Starlight Rare',
                'rarity_code': '(StR)',
              },
            ],
        },
      };

  test('le stampe localizzate si agganciano a quella inglese', () {
    final out = DataRepository.normalizeYugiohCardForSQLite(jushCard());
    final print = (out['prints'] as List).single as Map<String, dynamic>;

    expect(print['set_code'], 'JUSH-EN040');
    expect(print['set_code_it'], 'JUSH-IT040');
    expect(print['set_code_fr'], 'JUSH-FR040');
    expect(print['set_code_de'], 'JUSH-DE040');
    expect(print['set_code_pt'], 'JUSH-PT040');
  });

  test('il rarity_code sopravvive: entra nel printId del prezzo', () {
    final out = DataRepository.normalizeYugiohCardForSQLite(jushCard());
    final print = (out['prints'] as List).single as Map<String, dynamic>;
    expect(print['rarity_code'], '(StR)');
    expect(print['rarity_code_it'], '(StR)');
  });

  test('la rarità discrimina due stampe con lo stesso set_code', () {
    // Stessa carta, stesso set, due rarità con prezzi molto distanti: se il
    // match ignorasse la rarità, la Starlight prenderebbe il prezzo della Super.
    final card = jushCard();
    (card['sets'] as Map)['en'] = [
      {'set_code': 'JUSH-EN040', 'rarity': 'Starlight Rare', 'rarity_code': '(StR)'},
      {'set_code': 'JUSH-EN040', 'rarity': 'Super Rare', 'rarity_code': '(SR)'},
    ];
    (card['sets'] as Map)['it'] = [
      {'set_code': 'JUSH-IT040', 'rarity': 'Starlight Rare', 'rarity_code': '(StR)'},
      {'set_code': 'JUSH-IT040', 'rarity': 'Super Rare', 'rarity_code': '(SR)'},
    ];

    final prints = (DataRepository.normalizeYugiohCardForSQLite(card)['prints'] as List)
        .cast<Map<String, dynamic>>();
    expect(prints.length, 2);
    for (final p in prints) {
      expect(p['rarity_code_it'], p['rarity_code'],
          reason: 'la stampa italiana deve essere quella della stessa rarità');
    }
  });

  test('una stampa senza controparte localizzata non ne inventa una', () {
    final card = jushCard();
    (card['sets'] as Map).remove('it');
    final print = (DataRepository.normalizeYugiohCardForSQLite(card)['prints'] as List)
        .single as Map<String, dynamic>;
    expect(print['set_code_it'], isNull);
    expect(print['set_code_fr'], 'JUSH-FR040');
  });
}
