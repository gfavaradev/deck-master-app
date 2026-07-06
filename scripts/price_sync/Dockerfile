# Cloud Run Job: sync prezzi CardTrader → Firestore per i cataloghi grandi
# (yugioh/pokemon), senza il limite di durata delle funzioni serverless.
FROM node:20-slim

WORKDIR /app

# Dipendenze (solo prod): sfrutta la cache Docker sui layer
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Codice del job
COPY index.js ./

# Su Cloud Run non c'è serviceAccountKey.json: firebase-admin usa le Application
# Default Credentials (il service account del runtime). CARDTRADER_JWT e CATALOGS
# arrivano come variabili d'ambiente (vedi deploy-cloudrun.sh).
ENTRYPOINT ["node", "index.js"]
