# REQUIREMENTS — Admin Web Dashboard (Next.js su Vercel)

> Spec-Driven Development doc per il refactor dell'amministrazione da in-app (Flutter)
> a dashboard web esterna. Creato 2026-07-02.

## Obiettivo
Sostituire le pagine admin dentro l'app Flutter (~12.000 righe) con una **dashboard web
avanzata su Next.js/Vercel** che comunica direttamente con Firebase, Backblaze e CardTrader
tramite un backend server-side, permette di gestire il catalogo/news/prezzi con operazioni
anche **automatizzate e sempre attive** (cron), e mostra **statistiche complete** dell'app
(dati Firestore, uso, download store, salute catalogo/prezzi).

## Contesto / stato attuale
- **Admin in-app** (da dismettere lato mobile): `lib/pages/admin_*.dart` (6 pagine),
  `lib/widgets/admin_card_edit_dialog.dart` (1756 righe), `lib/services/admin_*.dart`
  (`admin_catalog_service.dart` 4960 righe, `admin_excel_service.dart`, `admin_translation_service.dart`).
- **Problema che ha innescato il refactor:** App Check **enforcement attivo su Firestore**.
  Le build client senza token App Check valido (es. debug) vanno in timeout su ogni lettura
  Firestore. Un **backend server-side con Firebase Admin SDK bypassa App Check e le security
  rules**, eliminando il problema alla radice per l'admin.
- **Automazione esistente (Node.js, `scripts/`):** `price_sync` (CardTrader→Firestore prezzi
  yugioh/pokemon/onepiece), `populate_firestore` (seed cataloghi), `news_sync`,
  `update_app_version`. Logica riutilizzabile quasi tale e quale nel backend Next.js.
- **Vetrina:** sito HTML statico su Vercel (progetto `deck-master`, org
  `team_5Fvf5CNDRJauT6L9eHnHxf07`, `site/`). La dashboard sarà un progetto Vercel
  (nuovo, o sotto-path) nello stesso account.
- **Modello dati Firestore:** cataloghi per-TCG (`yugioh_catalog`, …), `cardtrader_prices/{catalog}`,
  `app_config/*`, `news/*`, `users/{uid}` (campo `role: "administrator"`, allowlist email nelle rules).

## Architettura target
- **Frontend:** Next.js (App Router) su Vercel. Login **Firebase Auth** ristretto alle email
  admin (allowlist `g.favara.dev@gmail.com`, `vivianaferreri98@gmail.com`).
- **Backend:** Vercel Functions / Route Handlers server-side con **firebase-admin** (service
  account) → accesso pieno a Firestore/Storage senza App Check. Integrazioni Backblaze B2 e
  CardTrader (JWT) lato server. La logica dei job in `scripts/` viene portata/condivisa qui.
- **Automazione sempre attiva:** **Vercel Cron** (es. price sync giornaliero, sostituisce il
  cron `0 3 * * *`). Ogni job registra ultimo esito/timestamp su Firestore per la dashboard.
- **Segreti:** service account Firebase, `CARDTRADER_JWT`, credenziali Backblaze, chiavi
  analytics — solo in Vercel Environment Variables (server-side), **mai** nel bundle client.

## Requisiti funzionali

### Auth & sicurezza (Milestone 1)
- [ ] Login admin via Firebase Auth (Google + email/password), accesso consentito **solo** alle
      email in allowlist; ogni altro utente rifiutato con messaggio chiaro.
- [ ] Verifica del ruolo lato server su ogni chiamata API (no fiducia nel client).
- [ ] Sessione/protezione route: pagine dashboard non accessibili senza auth admin.

### Scheletro dashboard (Milestone 1)
- [ ] Layout base (nav laterale, header, tema) + deploy funzionante su Vercel.
- [ ] Sezioni placeholder: Panoramica, Catalogo, News, Prezzi/Job, Utenti, Statistiche.
- [ ] Health check backend (connessione Firestore/Backblaze/CardTrader OK).

### Operazioni admin (milestone successive — porting da `admin_*`)
- [ ] Gestione catalogo: add/edit/delete carte, upload immagini (Backblaze/Cloudinary),
      chunking Firestore (<1MB), traduzioni multi-lingua. (da `admin_catalog_service`)
- [ ] Import Excel catalogo. (da `admin_excel_service`)
- [ ] Set & rarità. (da `admin_sets_rarities_page`)
- [ ] Gestione news. (da `admin_news_page` / `news_sync`)
- [ ] Gestione utenti (ruoli, stato attivo, Pro). (da `admin_users_page`)
- [ ] Sync prezzi CardTrader on-demand + schedulato. (da `price_sync`)
- [ ] Pubblicazione versione app (`app_config/version`). (da `update_app_version`)

### Statistiche / dashboard analitica ("tutto")
- [ ] **Dati app (Firestore):** utenti registrati, Pro attivi, n. collezioni/carte per TCG,
      dimensioni cataloghi, conteggio news.
- [ ] **Uso app (Firebase Analytics / GA4):** DAU/MAU, retention, schermate più usate
      (via GA4 Data API o export BigQuery — da definire, vedi Domande aperte).
- [ ] **Download store:** installazioni/download Google Play + App Store
      (Play Developer Reporting API / App Store Connect API).
- [ ] **Salute catalogo/prezzi:** stato ultimi job, carte senza prezzo/immagine, prezzi stale.

## Vincoli tecnici
- Backend **server-side** con firebase-admin per bypassare App Check; nessuna chiave sensibile
  nel client. Se servono chiamate Firebase client-side, configurare App Check ReCaptcha per il web app.
- Riusare, non duplicare, la logica dei job Node in `scripts/` (estrarre in moduli condivisi).
- Le security rules Firestore restano invariate per l'app mobile; il backend le bypassa via Admin SDK.
- Non rimuovere il codice admin dall'app Flutter **finché** la dashboard non copre l'operazione
  equivalente (dismissione graduale, per evitare finestre senza strumenti admin).
- Localizzazione: dashboard admin **non** localizzata (coerente con la convenzione admin del repo).

## Criteri di accettazione
- [ ] Build Next.js pulita (lint/tsc) e deploy Vercel riuscito.
- [ ] Login admin funziona end-to-end; utente non-admin correttamente respinto.
- [ ] Le operazioni migrate scrivono su Firestore/Storage **senza** errori App Check.
- [ ] I job cron girano su Vercel e registrano l'esito, visibile in dashboard.
- [ ] Verifica manuale (screenshot) delle schermate principali.

## Milestone
1. **Auth + scheletro dashboard** (SELEZIONATO come primo) — setup progetto Vercel, Firebase
   Auth admin, layout, health check, deploy.
2. Migrazione operazioni admin core (catalogo, news, prezzi) + Vercel Cron.
3. Dashboard analitica completa (Firestore → Analytics → download store → salute).
4. Dismissione graduale delle pagine admin dall'app Flutter.

## Fuori scope (per ora)
- Rimozione immediata del codice admin dall'app (avviene solo dopo copertura equivalente).
- Modifiche alle security rules Firestore per l'app mobile.
- Localizzazione IT/EN della dashboard.

## Domande aperte (da risolvere prima delle milestone rilevanti)
- Service account Firebase per il backend: da generare/fornire (Vercel env).
- Firebase Analytics: è attivo GA4? Esiste già un export **BigQuery**? (determina come leggere l'uso app)
- Credenziali **Play Developer Reporting API** e **App Store Connect API** per i download.
- Nuovo progetto Vercel dedicato vs estensione del progetto `deck-master` della vetrina.
- Dove vivono i moduli condivisi dei job (monorepo `scripts/` ↔ dashboard) per evitare duplicazione.
