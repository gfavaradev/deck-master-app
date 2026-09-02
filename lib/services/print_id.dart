/// Chiave di stampa condivisa con il worker che pubblica i prezzi.
///
/// Il worker (`deck-master-worker/src/lib/print-id.ts`) pubblica i prezzi già
/// agganciati alla stampa; qui si fa solo lookup. Perché funzioni, le due
/// implementazioni devono produrre la STESSA stringa per la stessa stampa: i
/// vettori di conformità stanno in `test/unit/services/print_id_test.dart` e,
/// identici, in `print-id.test.ts`. Toccando una regola qui, aggiorna entrambi.
///
/// Verificato contro l'API CardTrader (02/09/2026): 12 cataloghi su 13 hanno il
/// blueprint id CT già dentro l'identificatore di stampa, quindi il prezzo si
/// aggancia per uguaglianza esatta e non per euristica sul nome:
///   - flat (9 cataloghi): `api_id`              = blueprint (digimon btv1: 50/50)
///   - pokemon:            `api_id` "pr1-273488" → 273488    (pr1: 31/31, popr: 49/49)
///   - onepiece:      `card_set_id` "UP-244190"  → 244190    (promo: 32/32, jp: 49/49)
/// Fanno eccezione magic (fonte Scryfall) e yugioh (fonte YGOProDeck): nessun
/// blueprint nel catalogo, quindi yugioh resta l'unico con matching euristico —
/// che però esegue il worker, non l'app.
library;

enum PrintFamily { flat, pokemon, onepiece, magic, yugioh }

const Map<String, PrintFamily> _families = {
  'yugioh': PrintFamily.yugioh,
  'pokemon': PrintFamily.pokemon,
  'onepiece': PrintFamily.onepiece,
  'magic': PrintFamily.magic,
  'digimon': PrintFamily.flat,
  'lorcana': PrintFamily.flat,
  'flesh-and-blood': PrintFamily.flat,
  'vanguard': PrintFamily.flat,
  'dragon-ball-super': PrintFamily.flat,
  'star-wars': PrintFamily.flat,
  'riftbound': PrintFamily.flat,
  'gundam': PrintFamily.flat,
  'union-arena': PrintFamily.flat,
};

/// Famiglia di [catalog]; i cataloghi non elencati si comportano come "flat".
PrintFamily familyOf(String catalog) =>
    _families[catalog] ?? PrintFamily.flat;

final RegExp _invalidKeyChars = RegExp(r'[^a-z0-9_-]+');
final RegExp _repeatedDashes = RegExp(r'-+');
final RegExp _edgeDashes = RegExp(r'^-|-$');
final RegExp _digitsOnly = RegExp(r'^\d+$');

/// Normalizza una chiave perché sia usabile come chiave RTDB.
///
/// RTDB vieta `. $ # [ ] /` e distingue maiuscole/minuscole: si forza il
/// minuscolo, si sostituisce ogni carattere fuori da `[a-z0-9_-]` con `-`, si
/// collassano i `-` ripetuti e si tagliano quelli ai bordi.
String normalizeKey(Object? raw) {
  if (raw == null) return '';
  return raw
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll(_invalidKeyChars, '-')
      .replaceAll(_repeatedDashes, '-')
      .replaceAll(_edgeDashes, '');
}

/// Estrae il blueprint CardTrader da un identificatore "{set}-{blueprint}".
///
/// Se non c'è un suffisso numerico restituisce la stringa normalizzata, così un
/// dato inatteso degrada in una chiave stabile invece di sparire.
String blueprintFromCompositeId(Object? raw) {
  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty) return '';
  final dash = s.lastIndexOf('-');
  if (dash > 0) {
    final tail = s.substring(dash + 1);
    if (_digitsOnly.hasMatch(tail)) return tail;
  }
  return _digitsOnly.hasMatch(s) ? s : normalizeKey(s);
}

/// Codice espansione di una carta pokemon: prefisso di `api_id`
/// ("pr1-273488" → "pr1").
String pokemonSetCode(Object? apiId) {
  final s = apiId?.toString().trim() ?? '';
  final dash = s.lastIndexOf('-');
  return normalizeKey(dash > 0 ? s.substring(0, dash) : s);
}

/// Codice espansione yugioh: prefisso del set_code ("JUSH-EN040" → "jush").
String yugiohSetCode(Object? setCode) {
  final s = setCode?.toString().trim() ?? '';
  final dash = s.indexOf('-');
  return normalizeKey(dash > 0 ? s.substring(0, dash) : s);
}

/// printId di una stampa yugioh, dai campi conservati in `yugioh_prints`.
String yugiohPrintId(Object? cardId, Object? setCode, Object? rarityCode) {
  final parts = [
    normalizeKey(cardId),
    normalizeKey(setCode),
    normalizeKey(rarityCode),
  ].where((p) => p.isNotEmpty);
  return parts.join('-');
}

/// printId di una stampa magic: il foil è una stampa distinta.
String magicPrintId(Object? apiId, {required bool foil}) {
  final base = normalizeKey(apiId);
  if (base.isEmpty) return '';
  return '$base-${foil ? 'f' : 'n'}';
}

/// printId dalle famiglie in cui l'identificatore di stampa contiene già il
/// blueprint CardTrader.
///
/// [card] e [print] sono le mappe grezze del catalogo (o le righe SQLite, che
/// conservano gli stessi campi).
String printIdFromCatalogCard(
  String catalog,
  Map<String, dynamic> card, [
  Map<String, dynamic>? print,
]) {
  switch (familyOf(catalog)) {
    case PrintFamily.flat:
      return blueprintFromCompositeId(card['api_id'] ?? card['id']);
    case PrintFamily.pokemon:
      return blueprintFromCompositeId(card['api_id']);
    case PrintFamily.onepiece:
      return blueprintFromCompositeId(print?['card_set_id']);
    case PrintFamily.magic:
      return magicPrintId(card['api_id'] ?? card['id'], foil: false);
    case PrintFamily.yugioh:
      return yugiohPrintId(
        card['id'],
        print?['set_code'],
        print?['rarity_code'],
      );
  }
}

/// printId a partire da un blueprint CardTrader. Vuoto per yugioh, che non ha
/// blueprint nel catalogo, e per `0`, che non è un blueprint valido.
String printIdFromBlueprint(String catalog, Object? blueprintId) {
  if (familyOf(catalog) == PrintFamily.yugioh) return '';
  final s = blueprintId?.toString().trim() ?? '';
  return _digitsOnly.hasMatch(s) && s != '0' ? s : '';
}
