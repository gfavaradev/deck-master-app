# Guida all'adattamento multipiattaforma

Questa guida spiega come gestire le differenze tra piattaforme nell'app Deck Master.

## Utilizzo di PlatformHelper

La classe `PlatformHelper` fornisce metodi utili per verificare la piattaforma corrente e adattare il comportamento dell'app.

### Importazione

```dart
import 'package:deck_master/utils/platform_helper.dart';
```

### Controlli di piattaforma base

```dart
// Verifica il tipo di piattaforma
if (PlatformHelper.isWindows) {
  // Codice specifico per Windows
}

if (PlatformHelper.isMobile) {
  // Codice per iOS e Android
}

if (PlatformHelper.isDesktop) {
  // Codice per Windows, macOS, Linux
}
```

### Verificare il supporto di funzionalità

```dart
// Verifica se una funzionalità è supportata
if (PlatformHelper.supportsFacebookAuth) {
  // Mostra il pulsante di login con Facebook
}

if (PlatformHelper.supportsAppleSignIn) {
  // Mostra il pulsante di login con Apple
}

if (PlatformHelper.supportsBiometrics) {
  // Offri autenticazione biometrica
}
```

## Esempio: Schermata di login adattiva

```dart
import 'package:flutter/material.dart';
import 'package:deck_master/utils/platform_helper.dart';
import 'package:deck_master/services/auth_service.dart';

class LoginPage extends StatelessWidget {
  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Login')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Google Sign-In - supportato su tutte le piattaforme
            ElevatedButton.icon(
              onPressed: () => _authService.signInWithGoogle(),
              icon: Icon(Icons.login),
              label: Text('Login con Google'),
            ),

            SizedBox(height: 16),

            // Facebook Sign-In - solo mobile
            if (PlatformHelper.supportsFacebookAuth)
              ElevatedButton.icon(
                onPressed: () => _authService.signInWithFacebook(),
                icon: Icon(Icons.facebook),
                label: Text('Login con Facebook'),
              ),

            SizedBox(height: 16),

            // Apple Sign-In - solo iOS e macOS
            if (PlatformHelper.supportsAppleSignIn)
              ElevatedButton.icon(
                onPressed: () => _authService.signInWithApple(),
                icon: Icon(Icons.apple),
                label: Text('Login con Apple'),
              ),

            SizedBox(height: 24),

            // Email/Password - supportato ovunque
            ElevatedButton(
              onPressed: () => _showEmailLogin(context),
              child: Text('Login con Email'),
            ),

            // Desktop-specific: mostra informazioni aggiuntive
            if (PlatformHelper.isDesktop)
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Stai usando Deck Master su ${PlatformHelper.platformName}',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showEmailLogin(BuildContext context) {
    // Implementazione login con email
  }
}
```

## Valori adattivi per UI

Usa `platformValue` per fornire valori diversi per ogni piattaforma:

```dart
// Padding diverso per piattaforma
final padding = PlatformHelper.platformValue(
  windows: 16.0,
  macos: 20.0,
  android: 16.0,
  ios: 20.0,
  fallback: 16.0,
);

// Usa valori predefiniti
final padding = PlatformHelper.defaultPadding;
final buttonHeight = PlatformHelper.defaultButtonHeight;
```

## Best Practices

### 1. Graceful Degradation

Fornisci sempre un'alternativa quando una funzionalità non è disponibile:

```dart
Future<void> authenticate() async {
  if (PlatformHelper.supportsBiometrics) {
    // Prova autenticazione biometrica
    final authenticated = await _tryBiometric();
    if (authenticated) return;
  }

  // Fallback su password tradizionale
  await _showPasswordDialog();
}
```

### 2. UI Adattiva

Adatta il layout in base al tipo di dispositivo:

```dart
Widget build(BuildContext context) {
  if (PlatformHelper.isMobile) {
    return _buildMobileLayout();
  } else if (PlatformHelper.isDesktop) {
    return _buildDesktopLayout();
  } else {
    return _buildWebLayout();
  }
}
```

### 3. Gestione errori specifica per piattaforma

```dart
try {
  await someOperation();
} catch (e) {
  if (PlatformHelper.isWindows) {
    // Gestione errore specifica per Windows
    showDialog(...);
  } else if (PlatformHelper.isMobile) {
    // Gestione errore per mobile
    showBottomSheet(...);
  }
}
```

## Funzionalità specifiche per Windows

### File System Access

```dart
if (PlatformHelper.supportsFileSystem) {
  // Accesso diretto al file system
  import 'dart:io';

  final file = File('path/to/file.txt');
  await file.writeAsString('content');
}
```

### Multiple Windows

```dart
if (PlatformHelper.supportsMultipleWindows) {
  // Supporto per finestre multiple
  // (richiede package aggiuntivi come desktop_window)
}
```

## Dipendenze condizionali

Per evitare problemi con dipendenze non supportate, usa i controlli di piattaforma:

### Nel codice

```dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

// Import condizionale
Future<void> initializePlatformFeatures() async {
  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
    // Inizializza solo su mobile
    await initializeMobileSpecificFeature();
  }
}
```

### In pubspec.yaml (opzionale)

Alcune dipendenze possono essere dichiarate condizionalmente, ma generalmente è meglio gestirle nel codice.

## Testing su Windows

### Eseguire l'app

```bash
# Esegui su Windows
flutter run -d windows

# Build di release
flutter build windows --release
```

### Debug

```dart
void debugPlatformInfo() {
  print('Platform: ${PlatformHelper.platformName}');
  print('Is Desktop: ${PlatformHelper.isDesktop}');
  print('Supports Facebook Auth: ${PlatformHelper.supportsFacebookAuth}');
  print('Supports Google Sign-In: ${PlatformHelper.supportsGoogleSignIn}');
}
```

## Problemi comuni e soluzioni

### Problema: Crash al tentativo di usare Facebook Auth su Windows

**Soluzione**: Usa sempre i controlli di supporto prima di chiamare metodi specifici:

```dart
if (_authService.isFacebookAuthSupported) {
  await _authService.signInWithFacebook();
} else {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Non disponibile'),
      content: Text('Facebook login non è supportato su questa piattaforma'),
    ),
  );
}
```

### Problema: UI non ottimizzata per schermi desktop

**Soluzione**: Usa `LayoutBuilder` e `PlatformHelper`:

```dart
Widget build(BuildContext context) {
  return LayoutBuilder(
    builder: (context, constraints) {
      if (PlatformHelper.isDesktop && constraints.maxWidth > 600) {
        // Layout a due colonne per desktop
        return Row(...);
      } else {
        // Layout a colonna singola per mobile
        return Column(...);
      }
    },
  );
}
```

## Risorse aggiuntive

- [Flutter Platform Channels](https://docs.flutter.dev/development/platform-integration/platform-channels)
- [Flutter Desktop](https://docs.flutter.dev/development/platform-integration/desktop)
- [Adaptive Design](https://docs.flutter.dev/development/ui/layout/adaptive-responsive)
