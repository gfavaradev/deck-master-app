# REQUIREMENTS — Prezzi unificati su Realtime Database

## Obiettivo

Un solo sistema di prezzi per tutti e 13 i cataloghi: i prezzi escono dai chunk del
catalogo, vivono su Realtime Database con una chiave di stampa (`printId`) calcolata
**una volta sola dal worker**, e l'app scarica solo i set che l'utente possiede,
restando aggiornata in tempo reale con un singolo listener da ~200 byte. Lo storico
dei prezzi diventa server-side e condiviso invece che locale per-dispositivo.

## Contesto / stato attuale (misurato il 02/09/2026)

| catalogo | carte | righe prezzo | gate `syncedAt` | dati reali |
|---|---|---|---|---|
| yugioh | 14.520 | 250.316 | **16/04** | 31/08 |
| onepiece | 2.407 | 13.873 | 01/08 | 01/08 |
| pokemon | 29.746 | 7.635 | 28/04 | 28/04 |
| magic | 34.701 | — | — | mai |
| digimon | 4.467 | — | — | mai |
| lorcana | 779 | — | — | mai |
| flesh-and-blood | 4.543 | — | — | mai |
| vanguard | 10.604 | — | — | mai |
| dragon-ball-super | 5.501 | — | — | mai |
| star-wars | 1.162 | — | — | mai |
| riftbound | 358 | — | — | mai |
| gundam | 864 | — | — | mai |
| union-arena | 3.080 | — | — | mai |

Difetti strutturali da cui nasce questo lavoro:

1. **Mirror completo non scalabile.** L'app replica *tutte* le righe prezzo in SQLite:
   `SyncService._syncCardtraderPrices` → `FirestoreService.streamCardtraderPriceRows`.
   Per YuGiOh sono 626 chunk / 69,7 MB per utente a ogni refresh. Esteso ai 13 cataloghi
   supererebbe il milione di righe. Non è ottimizzabile: va sostituito.
2. **Gate di freschezza fragile.** `cardtrader_prices/{cat}` ha `syncedAt` scritto come
   *ultimo* step non atomico di `saveCardtraderPrices`. Su YuGiOh i chunk sono del 31/08
   ma il padre è fermo al 16/04: l'app non scaricherà mai quei prezzi.
3. **13 read a vuoto per utente.** `SyncService._ctCatalogs` interroga 12 cataloghi + magic;
   10 documenti su 13 non esistono.
4. **Matching prezzo↔stampa fatto dal client**, per nome inglese + set + lingua + rarità +
   collector number, con `COALESCE` e fallback. È l'origine dei bug ricorrenti (serial One
   Piece, `set_code` vs `set_id` Pokémon, COALESCE YuGiOh) e con 13 cataloghi sarebbero 13
   varianti da mantenere.
5. **Price embedding nel catalogo inutile.** `CHUNK_EMBED_CATALOGS` riscrive 47 documenti da
   ~890 KB per YuGiOh; il rebuild del 26/08 (`updatedBy: worker-rebuild`) li ha sovrascritti.
   Stampe con prezzo embedded oggi: **0 su 44.439**.
6. **Storico solo locale.** `price_history` (SQLite) registra uno snapshot al giorno solo
   quando arriva un download prezzi; gate fermo ⇒ nessun punto nuovo da aprile, e chi
   reinstalla riparte da zero.

File coinvolti — app: `lib/services/sync_service.dart`, `firestore_service.dart`,
`cardtrader_service.dart`, `database_helper.dart`, `data_repository.dart`.
Worker (`deck-master-worker`): `src/jobs/price-sync.ts`, `src/lib/firebase.ts`.

## La chiave: `printId`

Il worker pubblica il prezzo già associato alla stampa. Il client non fa più matching:
fa lookup. `printId` è **sempre una stringa**, non contiene mai i caratteri vietati da
RTDB (`. $ # [ ] /`), e la lingua sta nel path, non nella chiave.

**Verificato contro l'API CardTrader il 02/09/2026: 12 cataloghi su 13 contengono già il
blueprint id CardTrader nell'identificatore di stampa.** Il join prezzo↔stampa è quindi
*esatto*, non euristico — è il fatto che rende possibile un sistema unico:

- digimon `btv1`: 50/50 `api_id` sono blueprint CT
- pokemon `pr1`: 31/31, `popr`: 49/49 (suffisso di `api_id`)
- onepiece `promo`: 32/32, `jp`: 49/49 (suffisso di `card_set_id`)

| famiglia | cataloghi | forma carta | `printId` |
|---|---|---|---|
| **flat-CT** | digimon, lorcana, flesh-and-blood, vanguard, dragon-ball-super, star-wars, riftbound, gundam, union-arena | `{id, api_id, name, set_code, rarity}` — 1 carta = 1 stampa | `api_id` (= blueprint CT) |
| **pokemon** | pokemon | `api_id: "pr1-273488"` | suffisso dopo l'ultimo `-` (= blueprint CT) |
| **onepiece** | onepiece | `prints[].card_set_id: "UP-244190"` | suffisso dopo l'ultimo `-` (= blueprint CT) |
| **magic** | magic | `api_id: <uuid scryfall>` — fonte Scryfall, non CT | `{api_id}-n` / `{api_id}-f` (foil = stampa distinta) |
| **yugioh** | yugioh | `{id, sets:{lang:[{set_code:"JUSH-EN040", rarity_code}]}}` — fonte YGOProDeck, **nessun blueprint** | `{id}-{set_code}-{rarity_code}` normalizzato |

Per 11 cataloghi su 13 il `printId` è dunque il blueprint CardTrader come stringa numerica,
e il prezzo vi si aggancia per uguaglianza diretta con `blueprint_id`. Solo **yugioh**
conserva il matching euristico di oggi (nome EN + lingua, fallback collector number), ma lo
esegue il worker una volta sola invece di ogni client a ogni sync.

Normalizzazione comune (`normalizePrintId`): trim → lowercase → sostituzione di ogni
carattere fuori da `[a-z0-9_-]` con `-` → collasso dei `-` ripetuti.

Il client sa già calcolare queste chiavi dai suoi dati: `yugioh_prints.set_code` +
`rarity_code`, `onepiece_prints.card_set_id` (UNIQUE), `api_id` per le altre famiglie.

## Schema RTDB

```
/v                            → { yugioh: 1725, pokemon: 88, … }      13 interi, ~200 byte
/p/{cat}/idx                  → { sets: { <set>: <ver> }, n: <righe>, t: <iso> }
/p/{cat}/s/{set}/{lang}       → { <printId>: [nmCents, anyCents, listings] }
/h/{cat}/{printId}            → { "260831": 1793, "260901": 1750 }
```

- `/v` è l'**unico listener** dell'app: dice quale catalogo si è mosso, senza polling
  e senza una read per catalogo.
- `/p/{cat}/idx` si legge solo per i cataloghi che l'utente usa davvero.
- `/p/{cat}/s/{set}/{lang}` si scarica solo per i set posseduti e solo se la versione è salita.
- `/h/{cat}/{printId}` si legge **solo** all'apertura della scheda carta; una entry viene
  scritta **solo quando il prezzo cambia** (append di delta, non snapshot giornalieri).
- Prezzi in **centesimi interi**, mai float. `null` ammesso per `nmCents`.

## Requisiti funzionali

### Worker (`deck-master-worker`)
- [x] `printId` calcolato per famiglia, in un modulo isolato e testato (`src/lib/print-id.ts`).
- [x] Il job pubblica su RTDB: `/p/{cat}/s/{set}/{lang}`, aggiorna `/p/{cat}/idx` e `/v`
      (`src/lib/rtdb.ts`, `src/lib/price-publish.ts`, `src/lib/price-entries.ts`).
- [x] Versione del set incrementata **solo se il contenuto cambia** (confronto hash), così
      i client non riscaricano set fermi. `/v` non si tocca se nessun set è cambiato.
- [x] Storico: append su `/h/{cat}/{printId}` solo se il prezzo differisce dall'ultimo punto.
- [x] Ordine di scrittura sicuro: prima i set, poi `idx`, infine `/v`.
- [x] Rimozione di `syncPricesToCatalogChunks` e `CHUNK_EMBED_CATALOGS` (122 righe).
- [x] Magic passa dallo stesso percorso; foil come stampa distinta.
- [x] Dual-write Firestore dietro `PRICE_LEGACY_FIRESTORE` (default acceso) per non
      lasciare senza prezzi le app ≤ 1.3.15.

### App (`deck-master-app`)
- [x] `PriceRepository` unico su RTDB, identico per i 13 cataloghi; nessun ramo per catalogo
      fuori dal calcolo di `printId`.
- [x] Tabella SQLite unica `card_prices(catalog, print_id, lang, nm_cents, any_cents,
      listings, updated_at)` + `price_set_versions` (migrazione v41).
- [x] Un solo listener/lettura su `/v`; nessuna read per catalogo non usato
      (`PriceSyncService._activeCatalogs`).
- [x] **La UI legge i prezzi da `card_prices` per `printId`**: il cambio è dentro
      `CardtraderService`, quindi nessuna pagina è stata riscritta — cambiano solo le
      firme, che ora ricevono anche `serialNumber`. Se la stampa non è risolvibile o il
      prezzo non è ancora sceso, si ricade sul percorso storico: il passaggio non fa
      sparire prezzi già visibili.
- [x] `DatabaseHelper.resolvePrintId`: il ponte fra carta posseduta e prezzo pubblicato,
      con una strada per famiglia (17 test su forme reali).
- [x] Storico letto da `/h/{cat}/{printId}`: **condiviso fra tutti gli utenti** e completo
      anche prima dell'installazione, mentre `price_history` in SQLite parte dal primo sync
      su quel dispositivo e riparte da zero a ogni reinstallazione.
- [x] Valore della collezione ricalcolato iterando **le carte dell'utente**
      (`PriceSyncService.updateCollectionValues`) invece delle 44.000 righe di stampa del
      catalogo.
- [ ] Rimozione del vecchio percorso (`streamCardtraderPriceRows`,
      `syncCatalogPricesFromCardtrader`, `_createPriceMatchKeys`) — resta come fallback
      deliberato finché i 13 cataloghi non sono popolati su RTDB.

### Infrastruttura
- [x] Istanza RTDB creata in **europe-west1**:
      `https://deck-master-1a35a-default-rtdb.europe-west1.firebasedatabase.app`
      (ha richiesto l'abilitazione di `firebasedatabase.googleapis.com`).
- [x] `database.rules.json` + blocco `database` in `firebase.json`, deployate: lettura per
      utenti autenticati **solo a livello di singolo set** (`/p/{cat}/s/{set}`) e di singola
      stampa per lo storico, scrittura negata a tutti. Le regole rendono impossibile lato
      server la lettura di un intero catalogo prezzi — la classe di errore che causò l'OOM
      della 1.3.9.
- [ ] App Check attivato anche su RTDB (oggi è enforced solo su Firestore).

## Stato — verificato il 02/09/2026

Il percorso worker → RTDB è **completo e provato end-to-end su Lorcana**:

| esecuzione | risultato |
|---|---|
| primo sync | 27 set, 3.720 stampe, 3.720 punti storico, `v1`, 119 s |
| secondo sync (subito dopo) | **0 set cambiati, 0 punti storico**, nessuna riscrittura |
| terzo sync | versione **invariata** a `v2`: nessun client viene svegliato per niente |

Test: 35 nel worker (`npm test`), 43 nuovi nell'app (`print_id_test.dart`,
`price_repository_test.dart`, `resolve_print_id_test.dart`), suite completa a **334 verdi**,
`flutter analyze` pulito. I vettori di conformità del `printId` girano identici nei due
linguaggi.

### Come si risolve la stampa di una carta posseduta

Una carta in collezione (`cards`) ha `catalogId` e `serialNumber`, e da lì si arriva al
`printId` con una strada diversa per famiglia — verificate sulle query di catalogo reali:

| catalogo | strada | query? |
|---|---|---|
| flat (9) | `getGenericCatalogCards` espone `api_id AS id` ⇒ `catalogId` **è** il blueprint | no, ma si consulta la tabella perché un id locale autoincrement è anch'esso numerico |
| onepiece | `getOnepieceCatalogCards` espone `op.card_set_id AS setCode` ⇒ il seriale contiene il blueprint (`UP-244190`) | no |
| pokemon | `catalogId` è l'id locale ⇒ salto ad `api_id` (`pr1-273488`) | sì |
| magic | uuid Scryfall, con suffisso di finitura | solo se arriva un id locale |
| yugioh | unico composito: servono `set_code` e `rarity_code` **della lingua giusta**, e il seriale posseduto è quello localizzato (`JUSH-IT040`) | sì, su tutte le colonne per lingua |

Il caso Yu-Gi-Oh merita attenzione: la stessa carta nello stesso set esiste con rarità
diverse e prezzi molto distanti, quindi `cards.rarity` serve a discriminare. Se non
combacia si ripiega su una stampa dello stesso seriale, mai su una di un altro seriale.

### Cosa resta

- App Check su RTDB.
- Rimozione del vecchio percorso Firestore, quando i 13 cataloghi saranno popolati.
- Far girare il sync sui 10 cataloghi ancora senza prezzi (finora solo lorcana).

## Vincoli tecnici

- **`firebase_database` è una dipendenza nativa nuova** (non presente in `pubspec.yaml`).
  Da CLAUDE.md: la CI non copre iOS e `google_mobile_ads` dà già grane di module map ⇒
  build iOS pulita da verificare a mano prima del merge.
- Piattaforme: Android/iOS/Windows/Web. Su Web il sync prezzi resta disabilitato come oggi
  (`SyncService.syncOnLogin` esce su `kIsWeb`).
- Nessun accesso diretto a RTDB dalle pagine: solo `PriceRepository`.
- Mai una `.get()` unica su un nodo che cresce — vale per RTDB quanto per Firestore.
  Le letture sono per set+lingua, mai per catalogo intero.
- Il worker resta l'unico writer. L'app non scrive mai prezzi.

## Criteri di accettazione

- [ ] `flutter analyze` pulito.
- [ ] Test unitari per `printId` in **entrambi** i linguaggi, sugli stessi vettori
      (`test/unit/services/print_id_test.dart` ↔ `src/lib/print-id.test.ts`): stessa carta
      reale di ogni famiglia ⇒ stessa chiave. È il contratto che tiene insieme i due repo.
- [ ] Test di regressione: un sync prezzi non deve mai caricare un intero catalogo in
      memoria (estende la classe di crash già coperta da `integration_test/crashes/firestore_oom_test.dart`).
- [ ] Verifica end-to-end su un catalogo piccolo (lorcana, 779 carte) prima di YuGiOh.
- [ ] Un utente con collezione mista vede i prezzi di tutti i suoi cataloghi, e il primo
      sync scarica ordini di grandezza meno di 69,7 MB.

## Fuori scope

- Riprogettare le tabelle `*_prints` (schema "wide" con colonne per lingua): resta com'è,
  cambia solo da dove arrivano i prezzi.
- Rebuild dei cataloghi e migrazione immagini.
- Cambiare la UI dei prezzi: `CardtraderPrice` resta il modello esposto alle pagine.
