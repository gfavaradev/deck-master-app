# Price-sync automatico su Cloud Run

Sincronizzazione giornaliera dei prezzi CardTrader → Firestore per i **cataloghi
grandi** (yugioh/pokemon/onepiece), eseguita come **Cloud Run Job** con **Cloud
Scheduler**. Risolve il limite di durata di Vercel (300s): i Cloud Run Job possono
girare fino a 1 ora (configurabile).

Stesso progetto GCP di Firestore (`deck-master-1a35a`), nessuna chiave nel codice:
il job usa le **Application Default Credentials** (service account dedicato) e legge
`CARDTRADER_JWT` da **Secret Manager**.

## Architettura
```
Cloud Scheduler (0 3 * * *, Europe/Rome)
      │  invoca (OAuth, run.invoker)
      ▼
Cloud Run Job  "price-sync"   ← immagine buildata da questo Dockerfile
      │  ADC (SA price-sync-job, roles/datastore.user)
      │  CARDTRADER_JWT (Secret Manager)
      ▼
Firestore: cardtrader_prices/* + embed nei chunk {catalog}_catalog
```

## Deploy (una volta)
Prerequisiti: `gcloud` installato e autenticato, permessi Owner/Editor sul progetto.

```bash
# 1. installa gcloud (se manca)
brew install --cask google-cloud-sdk

# 2. login + progetto
gcloud auth login
gcloud config set project deck-master-1a35a

# 3. deploy completo (API, secret, service account, Job, Scheduler)
cd scripts/price_sync
./deploy-cloudrun.sh
```
Lo script legge `CARDTRADER_JWT` da `../../.env` (oppure `export CARDTRADER_JWT=...`).

## Test e monitoraggio
```bash
# esecuzione manuale immediata
gcloud run jobs execute price-sync --region europe-west1

# lista esecuzioni + stato
gcloud run jobs executions list --job price-sync --region europe-west1

# log dell'ultima esecuzione
gcloud run jobs executions logs read --job price-sync --region europe-west1
```

## Parametri (in `deploy-cloudrun.sh`)
- `CATALOGS` — cataloghi da sincronizzare (default `yugioh,pokemon,onepiece`)
- `SCHEDULE` — cron (default `0 3 * * *`) · `TZ` — `Europe/Rome`
- `task-timeout 3600` (1h), `memory 1Gi`

## Rapporto con Vercel
- L'endpoint admin `POST /api/admin/jobs/price-sync` (dashboard → **Prezzi & Job**)
  resta per i sync **manuali on-demand** di un singolo catalogo (ok fino a ~300s).
- I sync **automatici/programmati** e i cataloghi grandi girano su Cloud Run.
- Lo script `index.js` è lo stesso: in locale usa `serviceAccountKey.json`, su
  Cloud Run usa le ADC (nessun key file nell'immagine).
