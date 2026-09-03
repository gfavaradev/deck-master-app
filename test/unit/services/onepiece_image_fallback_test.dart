import 'package:deck_master/models/card_model.dart';
import 'package:deck_master/services/data_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// `fixOnepieceCardImage` ricostruisce un URL Backblaze dal seriale per le
/// carte One Piece senza immagine. L'URL è **ricostruito, non verificato**:
/// finché i seriali erano surrogati a sei cifre ("OP01-244442") il regex non
/// combaciava mai e la funzione era inerte, ma dal rebuild del 03/09/2026 i
/// seriali sono veri ("OP01-064") e combaciano. Se sovrascrivesse un'immagine
/// esistente, scambierebbe un URL che carica con uno che quasi sempre non c'è.
void main() {
  CardModel card({String? imageUrl, String serial = 'OP01-064'}) => CardModel(
        name: 'Alvida',
        serialNumber: serial,
        collection: 'onepiece',
        catalogId: '77',
        imageUrl: imageUrl,
        quantity: 1,
        rarity: '',
        value: 0,
        albumId: 1,
        type: '',
        description: '',
      );

  test('un\'immagine CardTrader non viene sostituita', () {
    const url = 'https://www.cardtrader.com/uploads/blueprints/image/244442/alvida.jpg';
    expect(fixOnepieceCardImage(card(imageUrl: url)).imageUrl, url);
  });

  test('un\'immagine Backblaze resta com\'è', () {
    const url = 'https://f003.backblazeb2.com/file/deckmastercollections/x.jpg';
    expect(fixOnepieceCardImage(card(imageUrl: url)).imageUrl, url);
  });

  test('senza immagine si ricostruisce l\'URL dal seriale', () {
    final fixed = fixOnepieceCardImage(card(imageUrl: null));
    expect(fixed.imageUrl, contains('collections/onepiece/77_OP01-064.jpg'));
  });

  test('un seriale surrogato non produce nessun URL', () {
    // I blueprint senza collector number tengono il seriale surrogato: per
    // quelli non esiste un file col nome ricostruito.
    final fixed = fixOnepieceCardImage(card(imageUrl: null, serial: 'PROMO-244185'));
    expect(fixed.imageUrl, isNull);
  });
}
