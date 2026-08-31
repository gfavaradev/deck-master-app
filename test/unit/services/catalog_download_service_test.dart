import 'package:deck_master/services/catalog_download_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Il download era di proprietà dello `State` di una pagina: uscire dalla
/// collezione o tornare in home smontava la pagina e con essa spariva ogni
/// traccia del download, che intanto continuava a girare invisibile. Questi
/// test fissano il contratto che rende il download riagganciabile.
void main() {
  group('CatalogDownloadState', () {
    test('lo stato a riposo non è in esecuzione', () {
      expect(CatalogDownloadState.idle.isRunning, isFalse);
      expect(CatalogDownloadState.idle.progress, isNull);
      expect(CatalogDownloadState.idle.currentKey, isNull);
      expect(CatalogDownloadState.idle.phase, CatalogDownloadPhase.connecting);
    });

    test('copyWith conserva i campi non passati', () {
      const base = CatalogDownloadState(
        isRunning: true,
        currentKey: 'yugioh',
        currentName: 'Yu-Gi-Oh!',
        currentIndex: 2,
        total: 3,
        progress: 0.4,
        phase: CatalogDownloadPhase.downloading,
      );

      final next = base.copyWith(progress: 0.9);

      expect(next.progress, 0.9);
      expect(next.currentKey, 'yugioh');
      expect(next.currentName, 'Yu-Gi-Oh!');
      expect(next.currentIndex, 2);
      expect(next.total, 3);
      expect(next.isRunning, isTrue);
      expect(next.phase, CatalogDownloadPhase.downloading);
    });
  });

  group('CatalogDownloadOutcome', () {
    test('senza fallimenti hasFailures è falso', () {
      const outcome = CatalogDownloadOutcome(
        successCount: 2,
        failures: {},
        isRestore: false,
      );
      expect(outcome.hasFailures, isFalse);
    });

    test('un fallimento resta associato al nome del catalogo', () {
      const outcome = CatalogDownloadOutcome(
        successCount: 1,
        failures: {'Pokémon': 'rete assente'},
        isRestore: true,
      );
      expect(outcome.hasFailures, isTrue);
      expect(outcome.failures['Pokémon'], 'rete assente');
      expect(outcome.isRestore, isTrue);
    });
  });

  group('CatalogDownloadService', () {
    final service = CatalogDownloadService();

    setUp(service.debugReset);
    tearDown(service.debugReset);

    test('è un singleton: due riferimenti vedono lo stesso stato', () {
      // È il presupposto di tutto: se ogni pagina ne costruisse uno proprio,
      // il download resterebbe invisibile esattamente come prima.
      expect(identical(CatalogDownloadService(), CatalogDownloadService()),
          isTrue);
    });

    test('parte da fermo', () {
      expect(service.state.isRunning, isFalse);
    });

    test('una coda vuota non avvia nulla', () async {
      await service.start(
        updates: const [],
        labels: _labels,
      );
      expect(service.state.isRunning, isFalse);
    });

    test('lo stream di stato è broadcast: più pagine possono ascoltarlo',
        () async {
      // MainLayout e CatalogPage si sottoscrivono entrambe, e una CatalogPage
      // viene montata e smontata a ogni ingresso in collezione: con uno stream
      // a singolo ascoltatore la seconda sottoscrizione lancerebbe.
      final first = service.onStateChanged.listen((_) {});
      final second = service.onStateChanged.listen((_) {});
      addTearDown(first.cancel);
      addTearDown(second.cancel);
      expect(service.onStateChanged.isBroadcast, isTrue);
      expect(service.onFinished.isBroadcast, isTrue);
    });
  });
}

const _labels = CatalogDownloadLabels(
  notificationTitle: 'Deck Master',
  starting: 'Avvio…',
  operationName: 'Download catalogo',
  perCatalog: _perCatalog,
  perCatalogPct: _perCatalogPct,
  singlePct: _singlePct,
);

String _perCatalog(int i, int t, String n) => '$i/$t $n';
String _perCatalogPct(int i, int t, String n, int p) => '$i/$t $n $p%';
String _singlePct(String n, int p) => '$n $p%';
