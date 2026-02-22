# 🎴 Deck Master - Multiplatform Card Collection Manager

Applicazione Flutter multipiattaforma per gestire collezioni di carte (Yu-Gi-Oh, Pokemon, Magic, etc.)

## 🌟 Caratteristiche

- 📱 **Mobile**: iOS e Android
- 💻 **Desktop**: Windows, macOS, Linux
- 🌐 **Web**: Browser moderni
- 🔐 **Authentication**: Google, Email/Password (Facebook e Apple su mobile)
- ☁️ **Cloud Sync**: Firebase Firestore
- 💾 **Offline**: SQLite locale (Desktop/Mobile)
- 👑 **Admin Interface**: Gestione catalogo professionale

---

## 📦 Installazione

### Prerequisiti

- Flutter SDK 3.7+ ([Installa Flutter](https://docs.flutter.dev/get-started/install))
- Dart SDK (incluso con Flutter)
- Firebase project configurato

### Clone Repository

```bash
git clone <your-repo-url>
cd deck_master
flutter pub get
```

---

## 🚀 Quick Start

### 1. Windows Desktop

**Requisiti**: Visual Studio 2022 con C++ tools

```bash
flutter config --enable-windows-desktop
flutter run -d windows
```

📖 Guida completa: **[WINDOWS_SETUP.md](WINDOWS_SETUP.md)**

### 2. Web

**Requisiti**: Google Client ID configurato

```bash
flutter run -d chrome
```

📖 Guida completa: **[WEB_SETUP.md](WEB_SETUP.md)**

### 3. Mobile

```bash
# Android
flutter run -d android

# iOS (macOS only)
flutter run -d ios
```

---

## 📖 Documentazione

### Setup Guide

| Documento | Descrizione |
|-----------|-------------|
| **[QUICK_START.md](QUICK_START.md)** | 🚀 Inizio rapido per tutte le piattaforme |
| **[WINDOWS_SETUP.md](WINDOWS_SETUP.md)** | 💻 Setup Windows con Visual Studio |
| **[WEB_SETUP.md](WEB_SETUP.md)** | 🌐 Setup Web e Firebase |

### Development Guide

| Documento | Descrizione |
|-----------|-------------|
| **[PLATFORM_ADAPTATION.md](PLATFORM_ADAPTATION.md)** | 🎨 Adattare UI per piattaforme |
| **[ADMIN_CATALOG_GUIDE.md](ADMIN_CATALOG_GUIDE.md)** | 👑 Guida interfaccia admin |
| **[ADMIN_INTEGRATION_EXAMPLE.dart](ADMIN_INTEGRATION_EXAMPLE.dart)** | 📝 Esempi integrazione |

### Optimization Guide

| Documento | Descrizione |
|-----------|-------------|
| **[OPTIMIZATION_GUIDE.md](OPTIMIZATION_GUIDE.md)** | ⚡ Ottimizzazioni performance |
| **[OPTIMIZATION_SUMMARY.md](OPTIMIZATION_SUMMARY.md)** | 📊 Riepilogo ottimizzazioni |
| **[REFACTORING_EXAMPLES.md](REFACTORING_EXAMPLES.md)** | 🔧 Esempi refactoring |

---

## 🏗️ Architettura

### Struttura Directory

```
deck_master/
├── lib/
│   ├── models/           # Data models
│   ├── pages/            # UI pages
│   │   ├── admin_catalog_desktop_page.dart  ⭐ NEW
│   │   ├── admin_catalog_page.dart
│   │   ├── catalog_page.dart
│   │   └── settings_page.dart
│   ├── services/         # Business logic
│   │   ├── admin_catalog_service.dart       ⭐ UPDATED
│   │   ├── auth_service.dart                ⭐ UPDATED
│   │   ├── database_helper.dart             ⭐ UPDATED
│   │   ├── firestore_service.dart
│   │   └── sync_service.dart
│   ├── utils/            # Utilities
│   │   ├── platform_helper.dart             ⭐ NEW
│   │   ├── app_logger.dart
│   │   └── validators.dart
│   ├── widgets/          # Reusable widgets
│   ├── config/           # Configuration
│   └── main.dart
├── windows/              # Windows platform code
├── web/                  # Web platform code
├── android/              # Android platform code
├── ios/                  # iOS platform code
└── docs/                 # Documentation
```

⭐ = Nuovi file o modifiche recenti

### Stack Tecnologico

- **Framework**: Flutter 3.29+
- **State Management**: Provider
- **Database Locale**: SQLite (sqflite_common_ffi)
- **Database Cloud**: Firebase Firestore
- **Authentication**: Firebase Auth
- **Storage**: SharedPreferences

---

## 🎯 Features per Piattaforma

### Windows (Desktop)

✅ SQLite database locale
✅ Admin catalog desktop interface
✅ Google Sign-In
✅ Email/Password auth
✅ Offline mode completo
✅ File system access

❌ Facebook Auth
❌ Apple Sign-In
❌ Push notifications

### Web

✅ Admin catalog (Firestore diretto)
✅ Google Sign-In (con config)
✅ Email/Password auth
✅ Responsive UI

❌ SQLite (usa Firestore)
❌ Facebook Auth
❌ Apple Sign-In
❌ Offline persistente

### Mobile (iOS/Android)

✅ Tutte le features
✅ SQLite locale
✅ Tutti i metodi auth
✅ Push notifications
✅ Biometrics
✅ Camera access

---

## 👑 Admin Interface

### Desktop/Web Admin Catalog

Interfaccia professionale per gestione catalogo:

**Features**:
- Vista tabella database completa
- Ricerca avanzata (nome, ID, archetipo)
- Ordinamento colonne
- Download catalogo da Firebase
- Modifica/Creazione carte
- Sincronizzazione batch

**Accesso**:
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const AdminCatalogDesktopPage(),
  ),
);
```

📖 **[ADMIN_CATALOG_GUIDE.md](ADMIN_CATALOG_GUIDE.md)**

### Mobile Admin (legacy)

Per mobile, usa `AdminCatalogPage` (layout ottimizzato mobile)

---

## 🔧 Build & Deploy

### Development Build

```bash
# Windows
flutter run -d windows

# Web
flutter run -d chrome

# Android
flutter run -d android
```

### Production Build

```bash
# Windows
flutter build windows --release
# Output: build\windows\x64\runner\Release\deck_master.exe

# Web
flutter build web --release
# Output: build/web/

# Android
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk

# iOS (macOS only)
flutter build ios --release
```

### Deploy

**Windows**: Distribuisci `.exe` o crea installer con:
- Inno Setup
- MSIX package

**Web**: Deploy su:
- Firebase Hosting
- Netlify
- Vercel
- GitHub Pages

```bash
# Firebase
firebase deploy --only hosting
```

---

## 🛠️ Development

### Setup Development Environment

1. **Installa Flutter**
   ```bash
   flutter doctor -v
   ```

2. **Abilita piattaforme**
   ```bash
   flutter config --enable-windows-desktop
   flutter config --enable-web
   ```

3. **Installa dipendenze**
   ```bash
   flutter pub get
   ```

4. **Setup Firebase** ([Guide](https://firebase.google.com/docs/flutter/setup))

5. **Per Windows**: Installa Visual Studio 2022

### Code Organization

**Models**: Data structures
```dart
lib/models/
├── card_model.dart
├── album_model.dart
├── user_model.dart
└── pending_catalog_change.dart
```

**Services**: Business logic separato da UI
```dart
lib/services/
├── auth_service.dart
├── database_helper.dart
├── firestore_service.dart
└── admin_catalog_service.dart
```

**Utils**: Helper functions
```dart
lib/utils/
├── platform_helper.dart      // Platform checks
├── app_logger.dart            // Logging
└── validators.dart            // Input validation
```

### Platform-Aware Code

Usa `PlatformHelper` per codice platform-specific:

```dart
import 'package:deck_master/utils/platform_helper.dart';

if (PlatformHelper.isWindows) {
  // Windows-specific code
}

if (PlatformHelper.isMobile) {
  // Mobile-specific code
}

if (PlatformHelper.supportsFacebookAuth) {
  // Show Facebook login
}
```

📖 **[PLATFORM_ADAPTATION.md](PLATFORM_ADAPTATION.md)**

---

## 🧪 Testing

### Unit Tests

```bash
flutter test
```

### Integration Tests

```bash
flutter test integration_test/
```

### Platform Tests

```bash
# Test su Windows
flutter run -d windows

# Test su Web
flutter run -d chrome

# Test su Android
flutter run -d android
```

---

## 📊 Performance

### Ottimizzazioni Implementate

- ✅ Lazy loading liste
- ✅ Image caching
- ✅ Database indexing
- ✅ Batch operations
- ✅ Async/await corretto
- ✅ StreamBuilder ottimizzati

📖 **[OPTIMIZATION_GUIDE.md](OPTIMIZATION_GUIDE.md)**

### Monitoring

```bash
# Profile mode
flutter run --profile -d windows

# Performance overlay
flutter run --trace-startup
```

---

## 🔐 Security

### Best Practices Implementate

- ✅ Firebase Security Rules
- ✅ Admin role verification
- ✅ Input validation
- ✅ SQL injection prevention
- ✅ XSS protection
- ✅ Secure storage (flutter_secure_storage)

### Environment Variables

Usa `.env` per secrets:

```env
FIREBASE_API_KEY=your_api_key
GOOGLE_CLIENT_ID=your_client_id
```

⚠️ **Non committare `.env` in git!**

---

## 🐛 Troubleshooting

### Problemi Comuni

| Problema | Soluzione | Guida |
|----------|-----------|-------|
| Visual Studio toolchain not found | Installa VS 2022 con C++ | [WINDOWS_SETUP.md](WINDOWS_SETUP.md) |
| Google Sign-In ClientID error | Configura meta tag in HTML | [WEB_SETUP.md](WEB_SETUP.md) |
| Database error su Web | Normale - Web usa Firestore | [WEB_SETUP.md](WEB_SETUP.md) |
| Facebook Auth non funziona | Solo supportato su mobile | [PLATFORM_ADAPTATION.md](PLATFORM_ADAPTATION.md) |

### Debug

```bash
# Verbose output
flutter run -d windows --verbose

# Clear build
flutter clean
flutter pub get

# Doctor
flutter doctor -v
```

---

## 🤝 Contributing

### Workflow

1. Fork repository
2. Create feature branch
3. Commit changes
4. Push to branch
5. Open Pull Request

### Code Style

- Usa `flutter format .`
- Segui [Effective Dart](https://dart.dev/guides/language/effective-dart)
- Commenta codice complesso
- Scrivi tests per nuove features

---

## 📄 License

[Inserisci la tua licenza]

---

## 🙏 Credits

- Flutter Team
- Firebase Team
- Community Contributors

---

## 📞 Support

- **Issues**: [GitHub Issues](link)
- **Docs**: Vedi sezione Documentazione sopra
- **Community**: [Discord/Forum link]

---

## 🗺️ Roadmap

### In Sviluppo

- [ ] Modifica inline celle tabella admin
- [ ] Selezione multipla carte
- [ ] Import/Export CSV
- [ ] History & Rollback modifiche

### Future

- [ ] Desktop Linux support completo
- [ ] macOS native app
- [ ] Real-time collaboration
- [ ] Advanced analytics dashboard

---

## 📝 Changelog

### v1.1.0 (2026-02-18)

- ✨ NEW: Windows desktop support
- ✨ NEW: Admin Catalog Desktop interface
- ✨ NEW: Platform Helper utility
- 🔧 IMPROVED: Multi-platform auth handling
- 🔧 IMPROVED: Database initialization (FFI)
- 📖 NEW: Complete documentation
- 🐛 FIX: Web compatibility issues

### v1.0.0 (2024-XX-XX)

- 🎉 Initial release

---

**Made with ❤️ and Flutter**

*Ultimo aggiornamento: 2026-02-18*
