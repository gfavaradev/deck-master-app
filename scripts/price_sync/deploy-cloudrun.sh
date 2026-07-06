#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Deploy del price-sync come Cloud Run Job + Cloud Scheduler (esecuzione
# giornaliera), stesso progetto GCP di Firestore. Idempotente: puoi rilanciarlo.
#
# Prerequisiti:
#   - gcloud CLI installato e autenticato:  gcloud auth login
#   - permessi Owner/Editor sul progetto
#   - CARDTRADER_JWT disponibile (lo legge da ../../.env, oppure export CARDTRADER_JWT=...)
#
# Uso:   cd scripts/price_sync && ./deploy-cloudrun.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Parametri (modificabili) ────────────────────────────────────────────────
PROJECT="deck-master-1a35a"
REGION="europe-west1"
JOB="price-sync"
CATALOGS="yugioh,pokemon,onepiece"     # cataloghi da sincronizzare in automatico
SCHEDULE="0 3 * * *"                    # ogni giorno alle 03:00
TZ="Europe/Rome"
RUNTIME_SA="price-sync-job@${PROJECT}.iam.gserviceaccount.com"
SCHED_SA="price-sync-scheduler@${PROJECT}.iam.gserviceaccount.com"
SECRET="cardtrader-jwt"

echo "▶ Progetto: $PROJECT · Regione: $REGION · Job: $JOB"
gcloud config set project "$PROJECT" >/dev/null

# ── 1) API necessarie ───────────────────────────────────────────────────────
echo "▶ Abilito le API…"
gcloud services enable \
  run.googleapis.com cloudscheduler.googleapis.com artifactregistry.googleapis.com \
  cloudbuild.googleapis.com secretmanager.googleapis.com firestore.googleapis.com

# ── 2) Secret CARDTRADER_JWT ────────────────────────────────────────────────
JWT="${CARDTRADER_JWT:-}"
if [ -z "$JWT" ] && [ -f ../../.env ]; then
  # legge CARDTRADER_JWT da ../../.env e toglie eventuali apici/virgolette esterne
  JWT="$(grep -E '^CARDTRADER_JWT=' ../../.env | head -1 | sed -E 's/^CARDTRADER_JWT=//; s/^["'\'']//; s/["'\'']$//')"
fi
if [ -z "$JWT" ]; then echo "❌ CARDTRADER_JWT non trovato (export CARDTRADER_JWT=... o in ../../.env)"; exit 1; fi
if gcloud secrets describe "$SECRET" >/dev/null 2>&1; then
  printf '%s' "$JWT" | gcloud secrets versions add "$SECRET" --data-file=-
else
  printf '%s' "$JWT" | gcloud secrets create "$SECRET" --replication-policy=automatic --data-file=-
fi

# ── 3) Service account del job (accesso Firestore + lettura secret) ─────────
gcloud iam service-accounts describe "$RUNTIME_SA" >/dev/null 2>&1 || \
  gcloud iam service-accounts create price-sync-job --display-name="Price Sync Cloud Run Job"
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${RUNTIME_SA}" --role="roles/datastore.user" --condition=None >/dev/null
gcloud secrets add-iam-policy-binding "$SECRET" \
  --member="serviceAccount:${RUNTIME_SA}" --role="roles/secretmanager.secretAccessor" >/dev/null

# ── 4) Deploy del Cloud Run Job (build da sorgente via Cloud Build) ─────────
echo "▶ Build + deploy del Job…"
gcloud run jobs deploy "$JOB" \
  --source . \
  --region "$REGION" \
  --service-account "$RUNTIME_SA" \
  --set-env-vars "CATALOGS=${CATALOGS}" \
  --set-secrets "CARDTRADER_JWT=${SECRET}:latest" \
  --task-timeout 3600 \
  --max-retries 1 \
  --memory 1Gi \
  --cpu 1

# ── 5) Cloud Scheduler → esegue il Job ogni giorno ─────────────────────────
gcloud iam service-accounts describe "$SCHED_SA" >/dev/null 2>&1 || \
  gcloud iam service-accounts create price-sync-scheduler --display-name="Price Sync Scheduler"
# lo scheduler deve poter invocare il Job
gcloud run jobs add-iam-policy-binding "$JOB" --region "$REGION" \
  --member="serviceAccount:${SCHED_SA}" --role="roles/run.invoker" >/dev/null

RUN_URI="https://${REGION}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${PROJECT}/jobs/${JOB}:run"
if gcloud scheduler jobs describe "${JOB}-daily" --location "$REGION" >/dev/null 2>&1; then
  gcloud scheduler jobs update http "${JOB}-daily" --location "$REGION" \
    --schedule "$SCHEDULE" --time-zone "$TZ" --uri "$RUN_URI" --http-method POST \
    --oauth-service-account-email "$SCHED_SA"
else
  gcloud scheduler jobs create http "${JOB}-daily" --location "$REGION" \
    --schedule "$SCHEDULE" --time-zone "$TZ" --uri "$RUN_URI" --http-method POST \
    --oauth-service-account-email "$SCHED_SA"
fi

echo ""
echo "✅ Fatto."
echo "   Test manuale del job:   gcloud run jobs execute $JOB --region $REGION"
echo "   Log ultima esecuzione:  gcloud run jobs executions list --job $JOB --region $REGION"
echo "   Scheduler:              $SCHEDULE ($TZ) → esegue '$JOB' (cataloghi: $CATALOGS)"
