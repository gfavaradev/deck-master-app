# Setup Web per Deck Master

## Limitazioni Web

L'app su **Web** ha alcune limitazioni rispetto alle versioni desktop/mobile:

### ❌ Non Supportato su Web
- **SQLite Database locale** - Web non supporta SQLite
- **Facebook Authentication** - Non disponibile su Web
- **Apple Sign-In** - Limitato (richiede configurazione speciale)
- **File System locale** - Accesso limitato

### ✅ Supportato su Web
- **Firebase Authentication** (Google, Email/Password)
- **Firestore Database** (cloud)
- **Admin Catalog Desktop** (con Firestore diretto)
- **UI Responsive**

---

## Configurazione Firebase per Web

### 1. Aggiungi Google Sign-In Client ID

Apri il file `web/index.html` e aggiungi il meta tag con il tuo Google Client ID:

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">

  <!-- IMPORTANTE: Aggiungi questo per Google Sign-In -->
  <meta name="google-signin-client_id" content="YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com">

  <title>Deck Master</title>
  <!-- ... resto del file ... -->
</head>
<body>
  <!-- ... -->
</body>
</html>
```

### 2. Ottieni il Google Client ID

1. Vai su [Firebase Console](https://console.firebase.google.com)
2. Seleziona il tuo progetto
3. Vai su **Authentication** → **Sign-in method**
4. Click su **Google**
5. Trova il **Web Client ID** (termina con `.apps.googleusercontent.com`)
6. Copialo e incollalo nel meta tag sopra

---

## Configurazione Firebase Web SDK

### 1. Inizializzazione Firebase

Verifica che `web/index.html` includa la configurazione Firebase:

```html
<body>
  <!-- ... -->

  <script>
    // Your web app's Firebase configuration
    const firebaseConfig = {
      apiKey: "YOUR_API_KEY",
      authDomain: "your-project.firebaseapp.com",
      projectId: "your-project-id",
      storageBucket: "your-project.appspot.com",
      messagingSenderId: "123456789",
      appId: "1:123456789:web:abcdef123456"
    };

    // Initialize Firebase
    firebase.initializeApp(firebaseConfig);
  </script>

  <script src="main.dart.js" type="application/javascript"></script>
</body>
```

### 2. Aggiungi Firebase SDK

Assicurati che siano inclusi gli script Firebase necessari:

```html
<head>
  <!-- ... -->

  <!-- Firebase App (core) -->
  <script src="https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js"></script>

  <!-- Firebase Auth -->
  <script src="https://www.gstatic.com/firebasejs/10.7.0/firebase-auth-compat.js"></script>

  <!-- Firebase Firestore -->
  <script src="https://www.gstatic.com/firebasejs/10.7.0/firebase-firestore-compat.js"></script>
</head>
```

---

## Admin Catalog su Web

L'interfaccia **Admin Catalog Desktop** funziona su Web con alcune differenze:

### Differenze rispetto a Desktop

| Funzione | Desktop (Windows) | Web |
|----------|------------------|-----|
| Database locale | ✅ SQLite | ❌ Non disponibile |
| Ricerca carte | ✅ Query SQL locale | ❌ Deve scaricare da Firestore |
| Download catalogo | ✅ Cache locale permanente | ⚠️ Cache temporanea browser |
| Modifiche offline | ✅ Persistenti | ⚠️ Solo durante sessione |
| Sincronizzazione | ✅ Batch Firebase | ✅ Batch Firebase |

### Workflow su Web

1. **Apri interfaccia admin** - La pagina si carica
2. **Download automatico** - Scarica catalogo da Firestore (nessuna cache locale)
3. **Modifica in memoria** - Le carte sono solo in RAM
4. **Modifiche in SharedPreferences** - Salvate nel browser storage
5. **Sincronizza** - Pubblica su Firebase

### Limitazioni

⚠️ **Cache Browser Temporanea**
- Il catalogo scaricato è solo in memoria
- Refresh della pagina = download nuovo
- Nessuna persistenza tra sessioni

⚠️ **Modifiche Pending**
- Salvate in browser storage (può essere cancellato)
- Consiglio: sincronizza subito, non lasciare modifiche pending

---

## Build Web

### Development

```bash
flutter run -d chrome
```

### Production Build

```bash
flutter build web --release
```

I file compilati saranno in `build/web/`.

### Deploy

#### Firebase Hosting (consigliato)

```bash
# Installa Firebase CLI
npm install -g firebase-tools

# Login
firebase login

# Inizializza (se non già fatto)
firebase init hosting

# Deploy
firebase deploy --only hosting
```

#### Altri Hosting

Puoi hostare i file in `build/web/` su qualsiasi server web statico:
- Netlify
- Vercel
- GitHub Pages
- AWS S3 + CloudFront

---

## Testing su Web

### Test Locale

```bash
# Esegui in Chrome
flutter run -d chrome

# Oppure in Edge
flutter run -d edge
```

### Test Produzione Locale

```bash
# Build
flutter build web --release

# Servi con Python
cd build/web
python -m http.server 8000

# Oppure con Node.js
npx serve -s build/web
```

Apri: http://localhost:8000

---

## Risoluzione Problemi Web

### Google Sign-In non funziona

**Errore**: `ClientID not set`

**Soluzione**:
1. Verifica che il meta tag `google-signin-client_id` sia in `web/index.html`
2. Usa il **Web Client ID** (non Android/iOS Client ID)
3. Il Client ID deve terminare con `.apps.googleusercontent.com`
4. Assicurati che il dominio sia autorizzato in Firebase Console

### Database Error

**Errore**: `databaseFactory not initialized`

**Spiegazione**: Normale su Web - SQLite non è supportato

**Soluzione**:
- L'app usa automaticamente Firestore su Web
- L'interfaccia admin scarica sempre da Firestore
- Non c'è bisogno di fare nulla

### Modifiche Pending Perse

**Problema**: Le modifiche pending scompaiono dopo refresh

**Causa**: Browser storage può essere cancellato

**Soluzione**:
1. Sincronizza le modifiche prima di chiudere la pagina
2. Non lasciare modifiche pending per lunghi periodi
3. Su desktop, usa l'app Windows nativa per maggiore affidabilità

### CORS Errors

**Errore**: `CORS policy: No 'Access-Control-Allow-Origin' header`

**Soluzione**:
1. Verifica configurazione Firebase
2. Aggiungi il tuo dominio in Firebase Console → Settings → Authorized domains
3. Per localhost, aggiungi `localhost` e `127.0.0.1`

---

## Best Practices Web

### Per Admin

✅ **DO**:
- Sincronizza modifiche frequentemente
- Usa connessione stabile
- Testa su desktop prima di modifiche massive
- Backup modifiche importanti

❌ **DON'T**:
- Non lasciare modifiche pending overnight
- Non fare modifiche massive su connessione lenta
- Non chiudere il tab con modifiche non sincronizzate

### Per Utenti

✅ **DO**:
- Usa Google Sign-In (più affidabile su web)
- Connessione internet stabile
- Browser moderni (Chrome, Edge, Firefox)

❌ **DON'T**:
- Evita modalità incognito (storage limitato)
- Non usare browser vecchi (IE, Safari vecchio)

---

## Configurazione CORS per API Esterne

Se usi API esterne (es. YGOPRODeck API):

### Firebase Functions Proxy (consigliato)

Crea una Cloud Function come proxy:

```javascript
// functions/index.js
const functions = require('firebase-functions');
const axios = require('axios');

exports.proxyAPI = functions.https.onRequest(async (req, res) => {
  // CORS headers
  res.set('Access-Control-Allow-Origin', '*');

  try {
    const response = await axios.get('https://db.ygoprodeck.com/api/v7/cardinfo.php');
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});
```

### Alternative: CORS Anywhere

Per sviluppo locale:
```bash
npm install -g cors-anywhere
cors-anywhere
```

---

## Performance Web

### Ottimizzazioni

1. **Code Splitting**
   ```bash
   flutter build web --release --split-debug-info=debug-info
   ```

2. **Compressione**
   - Abilita gzip sul server
   - Usa Brotli se disponibile

3. **Caching**
   - Service Worker per PWA
   - Cache-Control headers

### PWA (Progressive Web App)

Abilita PWA per installazione su desktop:

```yaml
# web/manifest.json
{
  "name": "Deck Master",
  "short_name": "DeckMaster",
  "start_url": ".",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#673AB7",
  "description": "Gestisci la tua collezione di carte",
  "orientation": "any",
  "icons": [
    {
      "src": "icons/icon-192.png",
      "sizes": "192x192",
      "type": "image/png"
    },
    {
      "src": "icons/icon-512.png",
      "sizes": "512x512",
      "type": "image/png"
    }
  ]
}
```

---

## Esempio Completo index.html

```html
<!DOCTYPE html>
<html>
<head>
  <base href="$FLUTTER_BASE_HREF">
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="description" content="Deck Master - Gestione collezione carte">

  <!-- Google Sign-In -->
  <meta name="google-signin-client_id" content="123456789-abcdefg.apps.googleusercontent.com">

  <title>Deck Master</title>
  <link rel="manifest" href="manifest.json">

  <!-- Firebase SDK -->
  <script src="https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js"></script>
  <script src="https://www.gstatic.com/firebasejs/10.7.0/firebase-auth-compat.js"></script>
  <script src="https://www.gstatic.com/firebasejs/10.7.0/firebase-firestore-compat.js"></script>

  <script>
    // Flutter initialization
    window.addEventListener('load', function(ev) {
      // Download main.dart.js
      _flutter.loader.loadEntrypoint({
        serviceWorker: {
          serviceWorkerVersion: serviceWorkerVersion,
        }
      }).then(function(engineInitializer) {
        return engineInitializer.initializeEngine();
      }).then(function(appRunner) {
        return appRunner.runApp();
      });
    });
  </script>
</head>
<body>
  <script>
    // Firebase Configuration
    const firebaseConfig = {
      apiKey: "YOUR_API_KEY",
      authDomain: "your-project.firebaseapp.com",
      projectId: "your-project-id",
      storageBucket: "your-project.appspot.com",
      messagingSenderId: "123456789",
      appId: "1:123456789:web:abcdef"
    };

    firebase.initializeApp(firebaseConfig);
  </script>
</body>
</html>
```

---

## Checklist Deploy Web

Prima di fare deploy in produzione:

- [ ] Google Client ID configurato in `index.html`
- [ ] Firebase config aggiornato
- [ ] Domini autorizzati in Firebase Console
- [ ] Build ottimizzata (`--release`)
- [ ] Test su Chrome, Edge, Firefox
- [ ] Test Google Sign-In
- [ ] Test Admin Catalog (download, sync)
- [ ] HTTPS abilitato (richiesto per auth)
- [ ] Service Worker configurato (PWA)
- [ ] Manifest.json compilato

---

## Supporto Browser

### Supportati
- ✅ Chrome 90+
- ✅ Edge 90+
- ✅ Firefox 88+
- ✅ Safari 14+

### Non Supportati
- ❌ Internet Explorer (qualsiasi versione)
- ❌ Browser obsoleti

---

## Risorse

- [Flutter Web Documentation](https://docs.flutter.dev/platform-integration/web)
- [Firebase Web Setup](https://firebase.google.com/docs/web/setup)
- [Google Sign-In Web](https://developers.google.com/identity/sign-in/web)
- [PWA Guide](https://web.dev/progressive-web-apps/)
