# 🚀 Quick Start - Deck Master Multipiattaforma

## Cosa è stato fatto

✅ **App eseguibile su Windows** - Supporto completo Windows desktop
✅ **Interfaccia Admin Desktop** - Vista database professionale per gestione catalogo
✅ **Support Multipiattaforma** - Windows, Web, iOS, Android
✅ **Gestione Platform-Specific** - Auth e features adattate per ogni piattaforma

---

## 📁 File Creati

### Core Features
1. **[lib/pages/admin_catalog_desktop_page.dart](lib/pages/admin_catalog_desktop_page.dart)** - Interfaccia admin desktop/web
2. **[lib/utils/platform_helper.dart](lib/utils/platform_helper.dart)** - Utility per gestire piattaforme
3. **[lib/services/admin_catalog_service.dart](lib/services/admin_catalog_service.dart)** - Servizio admin (aggiornato)
4. **[lib/services/auth_service.dart](lib/services/auth_service.dart)** - Auth con controlli piattaforma
5. **[lib/services/database_helper.dart](lib/services/database_helper.dart)** - Database con supporto FFI Windows

### Documentazione
6. **[WINDOWS_SETUP.md](WINDOWS_SETUP.md)** - Setup Windows completo
7. **[WEB_SETUP.md](WEB_SETUP.md)** - Setup Web e limitazioni
8. **[PLATFORM_ADAPTATION.md](PLATFORM_ADAPTATION.md)** - Guida adattamento UI
9. **[ADMIN_CATALOG_GUIDE.md](ADMIN_CATALOG_GUIDE.md)** - Guida interfaccia admin
10. **[ADMIN_INTEGRATION_EXAMPLE.dart](ADMIN_INTEGRATION_EXAMPLE.dart)** - Esempi integrazione

---

## ⚡ Quick Commands

### Windows
```bash
# 1. Verifica setup
flutter doctor -v

# 2. Abilita Windows
flutter config --enable-windows-desktop

# 3. Esegui su Windows
flutter run -d windows

# 4. Build release
flutter build windows --release
```

**Eseguibile**: `build\windows\x64\runner\Release\deck_master.exe`

### Web
```bash
# 1. Esegui su Chrome
flutter run -d chrome

# 2. Build release
flutter build web --release

# 3. Deploy (opzionale)
firebase deploy --only hosting
```

**Output**: `build/web/`

### Mobile
```bash
# Android
flutter run -d android

# iOS (solo su macOS)
flutter run -d ios
```

---

## 🔧 Setup Richiesto

### Per Windows

1. **Visual Studio 2022** con componenti:
   - ✅ Desktop development with C++
   - ✅ MSVC v142 - VS 2019 C++ build tools
   - ✅ CMake tools for Windows
   - ✅ Windows 10 SDK

2. **Verifica**:
   ```bash
   flutter doctor -v
   ```
   Deve mostrare ✓ per "Visual Studio"

📖 Guida completa: [WINDOWS_SETUP.md](WINDOWS_SETUP.md)

### Per Web

1. **Google Sign-In**: Aggiungi client ID in `web/index.html`
   ```html
   <meta name="google-signin-client_id" content="YOUR_ID.apps.googleusercontent.com">
   ```

2. **Firebase Config**: Verifica inizializzazione in `web/index.html`

📖 Guida completa: [WEB_SETUP.md](WEB_SETUP.md)

---

## 🎯 Interfaccia Admin

### Accesso

La nuova interfaccia admin è in **[admin_catalog_desktop_page.dart](lib/pages/admin_catalog_desktop_page.dart)**

### Caratteristiche

- 📊 **Vista Tabella** - Tutte le colonne del catalogo
- 🔍 **Ricerca Avanzata** - Per nome, ID, archetipo
- ⬆️⬇️ **Ordinamento** - Click su colonna per ordinare
- 📥 **Download Catalogo** - Scarica completo da Firebase
- ✏️ **Modifica Carte** - Dialog per edit
- ➕ **Nuove Carte** - Crea carte custom
- ☁️ **Sync Batch** - Una richiesta Firebase per tutto

### Integrazione

```dart
// Esempio semplice
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const AdminCatalogDesktopPage(),
  ),
);
```

📖 Esempi completi: [ADMIN_INTEGRATION_EXAMPLE.dart](ADMIN_INTEGRATION_EXAMPLE.dart)

---

## 🌐 Differenze per Piattaforma

| Feature | Windows | Web | Mobile |
|---------|---------|-----|--------|
| SQLite Locale | ✅ | ❌ | ✅ |
| Google Sign-In | ✅ | ✅* | ✅ |
| Facebook Auth | ❌ | ❌ | ✅ |
| Apple Sign-In | ❌ | ⚠️ | ✅ iOS |
| Admin Catalog | ✅ | ✅** | ❌*** |
| File System | ✅ | ⚠️ | ✅ |

*Richiede client ID in HTML
**Solo con Firestore (no cache locale)
***Usa layout mobile diverso

---

## 📊 Workflow Admin Tipico

### Su Windows (Consigliato)

```
1. Apri Admin Catalog Desktop Page
2. Download catalogo (salvato locale)
3. Cerca e modifica carte
4. Accumula modifiche (salvate locale)
5. Sincronizza quando pronto
```

### Su Web

```
1. Apri Admin Catalog Desktop Page
2. Download catalogo (solo RAM)
3. Cerca e modifica carte
4. Modifiche in browser storage
5. Sincronizza SUBITO (non lasciare pending)
6. Refresh = download nuovo
```

---

## ⚠️ Problemi Comuni

### Windows: "Unable to find Visual Studio toolchain"

**Soluzione**: Installa Visual Studio 2022 con componenti C++

📖 [WINDOWS_SETUP.md](WINDOWS_SETUP.md)

### Web: "ClientID not set" (Google Sign-In)

**Soluzione**: Aggiungi meta tag in `web/index.html`

📖 [WEB_SETUP.md](WEB_SETUP.md)

### Web: "databaseFactory not initialized"

**Normale**: SQLite non supportato su Web. L'app usa Firestore.

### Modifiche Pending Perse (Web)

**Causa**: Browser storage cancellato

**Soluzione**: Sincronizza subito, non lasciare pending

---

## 🎨 Platform Helper Utility

Usa `PlatformHelper` per adattare UI:

```dart
import 'package:deck_master/utils/platform_helper.dart';

// Check piattaforma
if (PlatformHelper.isWindows) {
  // Codice Windows
}

if (PlatformHelper.isMobile) {
  // Codice Mobile
}

// Check feature support
if (PlatformHelper.supportsFacebookAuth) {
  // Mostra login Facebook
}

// Valori adattivi
final padding = PlatformHelper.defaultPadding;
final buttonHeight = PlatformHelper.defaultButtonHeight;
```

📖 [PLATFORM_ADAPTATION.md](PLATFORM_ADAPTATION.md)

---

## 📚 Documentazione Completa

### Setup
- **[WINDOWS_SETUP.md](WINDOWS_SETUP.md)** - Setup Windows passo-passo
- **[WEB_SETUP.md](WEB_SETUP.md)** - Setup Web e Firebase

### Development
- **[PLATFORM_ADAPTATION.md](PLATFORM_ADAPTATION.md)** - Adattare UI per piattaforme
- **[ADMIN_CATALOG_GUIDE.md](ADMIN_CATALOG_GUIDE.md)** - Guida interfaccia admin completa

### Examples
- **[ADMIN_INTEGRATION_EXAMPLE.dart](ADMIN_INTEGRATION_EXAMPLE.dart)** - 6 esempi integrazione

---

## 🚀 Prossimi Passi

### 1. Test Windows

```bash
# Installa Visual Studio (vedi WINDOWS_SETUP.md)
flutter doctor -v
flutter run -d windows
```

### 2. Integra Admin Interface

Aggiungi al tuo menu admin/settings:

```dart
ListTile(
  title: Text('Admin Catalog'),
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => AdminCatalogDesktopPage(),
    ),
  ),
)
```

### 3. Testa Workflow

1. Apri admin interface
2. Scarica catalogo
3. Cerca una carta
4. Modifica campo
5. Sincronizza

### 4. Deploy (Opzionale)

**Windows**:
- Distribuisci `build\windows\x64\runner\Release\deck_master.exe`
- Crea installer con Inno Setup o MSIX

**Web**:
- `flutter build web --release`
- Deploy su Firebase Hosting / Netlify / Vercel

---

## 💡 Best Practices

### Development

✅ **DO**:
- Usa `PlatformHelper` per check piattaforma
- Testa su tutte le piattaforme target
- Gestisci features mancanti con grazia
- Fornisci alternative quando possibile

❌ **DON'T**:
- Non assumere SQLite disponibile (Web!)
- Non assumere tutte le auth disponibili
- Non testare solo su una piattaforma

### Admin Operations

✅ **DO**:
- Usa Windows per operazioni massive
- Sincronizza frequentemente
- Testa modifiche prima di sync
- Backup prima di modifiche grandi

❌ **DON'T**:
- Non lasciare modifiche pending su Web
- Non modificare catalogo con connessione instabile
- Non chiudere app con modifiche non salvate

---

## 🔍 Debug

### Verbose Output

```bash
flutter run -d windows --verbose
flutter run -d chrome --verbose
```

### Logs

Windows:
```
C:\Users\<user>\AppData\Local\Temp\flutter_logs
```

Web:
```
Chrome DevTools → Console
```

### Common Checks

```bash
# Verifica piattaforme abilitate
flutter config

# Verifica dispositivi disponibili
flutter devices

# Verifica dipendenze
flutter pub get

# Pulisci build
flutter clean
```

---

## 📞 Support

### Issues

Per problemi o bug:
1. Controlla questa documentazione
2. Esegui `flutter doctor -v`
3. Controlla i log

### Riferimenti

- **Firebase**: https://console.firebase.google.com
- **Flutter Docs**: https://docs.flutter.dev
- **Visual Studio**: https://visualstudio.microsoft.com

---

## ✨ Features Complete

- ✅ Windows desktop support
- ✅ Web support (con limitazioni)
- ✅ Admin catalog desktop interface
- ✅ Platform-aware authentication
- ✅ Batch synchronization
- ✅ Complete documentation
- ✅ Integration examples

**Tutto pronto per iniziare! 🎉**

---

*Ultimo aggiornamento: 2026-02-18*
