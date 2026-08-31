# REQUIREMENTS — Download catalogo che sopravvive alla chiusura dell'app

## Obiettivo
Il download di un catalogo deve proseguire quando l'utente cambia schermata, blocca il
dispositivo, manda l'app in background o **la chiude**, e la UI deve poterlo ritrovare
al rientro invece di ripartire da zero.

## Contesto / stato attuale

Oggi il download non ha un proprietario stabile: vive dentro lo `State` di una pagina.

- `_MainLayoutState._startCatalogDownload()` / `._startRestoreDownload()` tengono
  `_isCatalogDownloading`, `_catalogDownloadProgress`, `_currentDownloading*`,
  `_downloadPhase`, `_pendingUpdates`.
- `_CatalogPageState._downloadUpdate()` tiene `_isDownloadingUpdate`,
  `_downloadProgress`, `_downloadMessage`.
- `DataRepository._isDownloadingCatalog` è l'unico stato che sopravvive: un lock
  `static bool`, senza progresso né identità del catalogo in corso.

Tre conseguenze, tutte osservate in produzione sulla 1.3.12:

1. **Cambio schermata.** Le tre schede dentro una collezione stanno in un
   `IndexedStack`, quindi restano vive. Ma uscire dalla collezione
   (`_exitCollection`) o cambiarla smonta `CatalogPage` — la `ValueKey` sul
   `_currentCollectionKey` forza la ricostruzione. Il `Future` del download **non
   viene annullato** (niente `CancelableOperation`, `dispose()` non tocca nulla):
   continua a girare, ma ogni callback di progresso cade su `if (!mounted) return`.
   Al rientro la pagina si ricrea con `_isDownloadingUpdate = false`, `_init()`
   rileva il catalogo incompleto e ripropone il bottone di download; premerlo
   sbatte contro il lock statico e restituisce `CatalogDownloadBusyException`
   ("un altro download è già in corso"). Per l'utente: si è interrotto.

2. **Blocco schermo / background.** Non esiste nessun foreground service: il
   manifest dichiara i permessi `FOREGROUND_SERVICE` e
   `FOREGROUND_SERVICE_DATA_SYNC` ma **nessun elemento `<service>`**.
   `BackgroundDownloadService` mostra solo una notifica locale con `ongoing: true`
   (grafica, nessuna priorità di processo) e chiama `WakelockPlus.enable()`, che su
   Android imposta `FLAG_KEEP_SCREEN_ON` sulla finestra dell'activity — tiene
   acceso lo schermo finché l'activity è visibile, non la CPU. Backgroundando,
   Android sposta il processo tra i cached e da Android 12 lo congela: l'isolate
   Dart smette di eseguire.

3. **App chiusa.** L'activity viene distrutta e con essa il `FlutterEngine`:
   l'isolate principale muore e il download con lui. Nessun lavoro parziale viene
   ripreso, perché il progresso non è persistito.

## Requisiti funzionali
- [ ] Il download prosegue cambiando scheda, uscendo dalla collezione e tornando alla home.
- [ ] Il download prosegue a schermo bloccato e con app in background.
- [ ] Il download prosegue con app chiusa (rimossa dai recenti).
- [ ] Qualunque pagina montata dopo l'avvio si riaggancia allo stato corrente
      (catalogo, indice N di M, percentuale, fase) senza doverlo ricostruire.
- [ ] La notifica mostra il progresso reale ed è l'unico punto da cui annullare.
- [ ] Un download interrotto da una morte di processo riparte **dal chunk raggiunto**,
      non da zero. — **NON implementato.** Con il foreground service la morte di
      processo diventa rara; la ripresa resta come miglioramento successivo,
      perché interagisce con la potatura di `redownload*` (che cancella le carte
      con `updated_at` più vecchio dell'inizio del download: riprendendo a metà,
      i chunk già scaricati risulterebbero "vecchi" e verrebbero cancellati).
      Va risolto persistendo anche il timestamp di inizio insieme al punto di
      ripresa, oppure saltando la potatura quando il download è ripreso.
- [ ] Un secondo avvio mentre uno è in corso non parte e lo dice, invece di
      fallire con un'eccezione generica.

## Vincoli tecnici

**Piattaforme.** Solo Android. Su iOS non esistono foreground service equivalenti;
su Windows/Web il download resta com'è. Gate via `PlatformHelper`.

**Isolate separato.** `flutter_foreground_task` esegue il `TaskHandler` in un
isolate distinto da quello della UI, con il proprio `FlutterEngine` e il proprio
registrant dei plugin. Tre conseguenze da risolvere prima di scrivere codice:

- **Firebase** va inizializzato dentro quell'isolate
  (`Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`).
- **App Check** va **attivato lì dentro**. L'enforcement è ON su Firestore: senza
  attivazione ogni lettura viene rifiutata e — con la persistence disabilitata —
  non ritorna e non lancia, resta appesa. È già costato una diagnosi sbagliata in
  passato (vedi il commento in `main.dart`). È il rischio numero uno di questa
  feature.
- **sqflite** aprirebbe una **seconda connessione nativa** allo stesso file. WAL è
  già attivo (letture concorrenti ok), ma il download è a scrittura pesante e due
  scrittori possono dare `SQLITE_BUSY`. Serve `PRAGMA busy_timeout` e la garanzia
  che l'isolate principale non scriva sul catalogo mentre il servizio lavora.

**Play policy.** Il tipo FGS `dataSync` richiede una dichiarazione d'uso in Play
Console a ogni rilascio, ed è soggetto al tetto di ~6h/giorno introdotto da
Android 14. Il caso d'uso (scaricare un catalogo di decine di MB) rientra, ma va
compilato.

**Servizi.** La logica di download resta in `lib/services/`; le pagine non devono
possedere stato di download, solo sottoscriverlo.

**Localizzazione.** Testi di notifica e stati in IT/EN via `AppLocalizations`.
`BackgroundDownloadService` oggi ha stringhe iniettate dalla UI: nell'isolate di
servizio non c'è `BuildContext`, quindi vanno passate all'avvio o risolte da
`AppPreferences.languageCode`.

## Piano in due fasi — stato: entrambe implementate (01/09/2026)

**Fase 1 — proprietà del download fuori dalle pagine. ✅** Un singleton
`CatalogDownloadService` con lo stato corrente e uno `Stream` broadcast di
progresso; `MainLayout` e `CatalogPage` si sottoscrivono invece di possedere.
Persistenza del chunk raggiunto per la ripresa. Copre il requisito 1 e prepara il
resto. Nessuna dipendenza nativa, nessuna modifica alle policy.

**Fase 2 — foreground service. ✅** `flutter_foreground_task`, `<service>` nel
manifest con `foregroundServiceType="dataSync"`, `TaskHandler` che esegue il
download della Fase 1 con Firebase + App Check + sqflite inizializzati
nell'isolate. Copre i requisiti 2 e 3.

## Criteri di accettazione
- [ ] `flutter analyze` pulito.
- [ ] Test unitari su `CatalogDownloadService`: stato riagganciabile, ripresa dal
      chunk, rifiuto del secondo avvio.
- [ ] Verifica su dispositivo reale, con `adb logcat`, dei tre scenari: cambio
      schermata, blocco schermo, app rimossa dai recenti.
- [ ] Verifica che una lettura Firestore dall'isolate di servizio **non** venga
      rifiutata da App Check.
- [ ] Nessun `SQLITE_BUSY` con app aperta e servizio attivo insieme.

## Fuori scope
- iOS: nessun equivalente, il download resta legato alla sessione in foreground.
- Download di immagini/migrazione Backblaze: solo il catalogo.
- Ripresa automatica al riavvio del dispositivo (`BOOT_COMPLETED`).
