# Guida Admin — Sync Catalogo (post-fix giugno 2026)

Questa guida descrive l'ordine corretto delle operazioni nella pagina Admin
dopo il fix ai sync CardTrader (seriali reali, immagini immediate,
incrementalità). Riferimento implementazione: `lib/services/admin_catalog_service.dart`,
piano: `.claude/plans/concurrent-wishing-spindle.md`.

## Cosa è cambiato

- I sync da CardTrader (Pokémon, One Piece, giochi generici) non salvano più
  un id interno CardTrader come "numero carta" quando CT non ha il dato
  ufficiale: cercano il seriale reale sull'API ufficiale del gioco
  (TCGDex per Pokémon, OPTCG per One Piece) e, se non lo trovano, scartano
  la carta invece di salvare un dato falso.
- Le immagini vengono caricate su Backblaze B2 **subito**, durante il sync,
  non più ricostruite a posteriori da un id che poteva essere sporco.
- Tutti i sync CardTrader sono **incrementali di default**: rilanciandoli
  periodicamente vengono aggiunte solo le carte nuove o ancora incomplete
  (senza seriale reale o senza immagine), senza ri-scaricare tutto.
- Nuovo strumento di **riparazione** per correggere le carte già sporche
  presenti nei catalogi Pokémon/One Piece esistenti.

## Passaggio una tantum — riparare i dati già esistenti

Da fare **una volta**, prima di riprendere i sync periodici, solo per
Pokémon e One Piece (i catalogi già popolati con il bug):

1. **Anteprima Riparazione Seriali** (dry-run, non scrive nulla) — mostra
   quante carte hanno un seriale CardTrader fittizio e quante sono
   risolvibili tramite l'API ufficiale. Controllare il numero di "non
   risolte" e la lista di esempio mostrata nel risultato.
2. Se il numero ha senso, lanciare **Ripara Seriali Sporchi** (scrittura
   reale): ogni carta riparabile viene aggiornata con il seriale ufficiale
   reale e la relativa immagine viene caricata su Backblaze. Le carte non
   risolvibili **non vengono cancellate**, restano con il vecchio dato e
   vanno revisionate manualmente (compaiono nel report `unresolvedSample`).
3. Ripetere per l'altro catalogo (Pokémon → One Piece o viceversa).

## Sync periodico (da ripetere ogni volta che si vuole aggiornare il catalogo)

Per **Pokémon** e **One Piece**:

1. **Aggiorna Catalogo da CardTrader** — scarica solo le espansioni/carte
   nuove o ancora incomplete da CardTrader, risolve il seriale reale (con
   fallback automatico a TCGDex/OPTCG se CT non lo espone) e carica le
   immagini su Backblaze immediatamente. Le carte già complete vengono
   saltate. Il risultato mostra: carte nuove, carte aggiornate, carte già
   complete (saltate), carte scartate (nessun seriale ufficiale trovato in
   nessuna fonte).
2. Se necessario integrare dati non coperti da CardTrader (es. lingue
   aggiuntive, sincronizzazione prezzi), continuare a usare gli altri
   pulsanti già esistenti (Aggiorna Nuove Carte da pokemontcg.io/OPTCG,
   sync prezzi CT) come prima — non sono stati modificati.
3. **Migra Immagini** resta disponibile come strumento di backfill per
   eventuali immagini ancora mancanti (es. da vecchi sync prima del fix),
   ma con il nuovo flusso non dovrebbe più essere necessario dopo un sync
   da CardTrader.

Per i **giochi generici** (Digimon, Lorcana, FAB, Vanguard, Dragon Ball
Super, Star Wars, Riftbound, Gundam, Union Arena):

1. **Aggiorna [Gioco] (CardTrader)** — stesso comportamento: incrementale,
   immagini immediate, scarta le carte senza numero ufficiale CT (per questi
   giochi non esiste un'API ufficiale alternativa, quindi se CT non ha il
   dato la carta resta esclusa fino a quando CT non lo aggiunge).

## Sync completo forzato (raro — solo se necessario)

I sync CardTrader incrementali bastano per l'uso normale. Un rebuild
completo (sovrascrive l'intero catalogo) non è più esposto direttamente in
UI per Pokémon/OnePiece dopo questo fix; se in futuro serve, il parametro
`incremental: false` è disponibile lato servizio (`downloadCatalogFromCardtrader`,
`downloadCardtraderGenericCatalog`) ma va usato con cautela perché elimina e
ricrea tutti i chunk Firestore.

## Diagnostica rapida

- "Catalogo già aggiornato: nessuna carta nuova o incompleta trovata" →
  tutto a posto, non serve rilanciare nulla.
- "$N carte scartate (nessun seriale ufficiale risolvibile)" → CardTrader e
  l'API ufficiale non hanno trovato quella carta; normale per alcune carte
  promo/rare, ma se il numero è alto vale la pena controllare manualmente
  l'espansione su CardTrader.
- Riparazione con molte "non risolte" → probabile problema di matching nome
  carta/espansione tra CT e l'API ufficiale (nomi tradotti diversamente,
  espansioni con nomi non standard); il report elenca nome carta + id sporco
  per la verifica manuale.
