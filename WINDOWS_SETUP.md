# Guida per eseguire Deck Master su Windows

## Requisiti Visual Studio

Per compilare ed eseguire l'app su Windows, devi installare i seguenti componenti in Visual Studio 2022:

### Come installare i componenti mancanti:

1. **Apri Visual Studio Installer**
   - Cerca "Visual Studio Installer" nel menu Start
   - Oppure vai su: `C:\Program Files (x86)\Microsoft Visual Studio\Installer\vs_installer.exe`

2. **Modifica l'installazione**
   - Clicca sul pulsante "Modifica" per Visual Studio Community 2022

3. **Installa il workload "Sviluppo di applicazioni desktop con C++"**
   - Nella scheda "Carichi di lavoro", seleziona:
     - ☑️ **Sviluppo di applicazioni desktop con C++** (Desktop development with C++)

4. **Verifica i componenti individuali**
   - Vai alla scheda "Singoli componenti"
   - Assicurati che siano selezionati:
     - ☑️ **MSVC v142 - VS 2019 C++ x64/x86 build tools** (o versione più recente)
     - ☑️ **Strumenti CMake C++ per Windows** (C++ CMake tools for Windows)
     - ☑️ **Windows 10 SDK** (versione 10.0.22621.0 o superiore)

5. **Installa**
   - Clicca su "Modifica" e attendi il completamento dell'installazione

## Dopo l'installazione

Una volta completata l'installazione, verifica che tutto sia configurato correttamente:

```bash
flutter doctor -v
```

Dovresti vedere un segno di spunta verde ✓ per "Visual Studio".

## Compilare l'app per Windows

### Build di debug
```bash
flutter run -d windows
```

### Build di release
```bash
flutter build windows --release
```

L'eseguibile finale si troverà in:
```
build\windows\x64\runner\Release\deck_master.exe
```

## Note importanti sulle dipendenze

Alcune dipendenze dell'app sono specifiche per mobile e potrebbero non funzionare su Windows:

### Dipendenze con supporto limitato su Windows:

1. **flutter_facebook_auth** - Non completamente supportato su Windows
2. **sign_in_with_apple** - Disponibile solo su iOS/macOS/web

### Soluzione

Il codice dovrebbe gestire queste limitazioni usando il pattern di platform checking. Esempio:

```dart
import 'dart:io';
import 'package:flutter/foundation.dart';

// Verifica se la piattaforma supporta una funzionalità
if (kIsWeb || Platform.isIOS || Platform.isAndroid) {
  // Usa il login con Facebook/Apple
} else {
  // Mostra solo opzioni disponibili su Windows
}
```

## Eseguire l'app

Dopo l'installazione dei componenti Visual Studio, puoi eseguire l'app con:

```bash
# Esegui su Windows
flutter run -d windows

# Oppure con hot reload
flutter run -d windows --debug
```

## Build per distribuzione

Per creare un installer distribuibile:

1. **Build di release**
   ```bash
   flutter build windows --release
   ```

2. **L'eseguibile si trova in:**
   ```
   build\windows\x64\runner\Release\
   ```

3. **Per creare un installer**, puoi usare strumenti come:
   - [Inno Setup](https://jrsoftware.org/isinfo.php)
   - [MSIX](https://docs.flutter.dev/deployment/windows#msix-packaging)

### Creare un pacchetto MSIX (per Microsoft Store)

```bash
# Aggiungi la dipendenza
flutter pub add msix

# Configura in pubspec.yaml
msix_config:
  display_name: Deck Master
  publisher_display_name: Your Name
  identity_name: com.yourcompany.deckmaster
  msix_version: 1.0.0.0

# Crea il pacchetto MSIX
flutter pub run msix:create
```

## Risoluzione problemi comuni

### Errore: "Unable to find suitable Visual Studio toolchain"
- Assicurati di aver installato tutti i componenti elencati sopra
- Riavvia il computer dopo l'installazione di Visual Studio
- Esegui `flutter doctor` per verificare

### Errore durante la build
- Pulisci la build cache: `flutter clean`
- Ricarica le dipendenze: `flutter pub get`
- Riprova la build: `flutter build windows`

### L'app non si avvia
- Verifica che tutti i file DLL necessari siano nella stessa cartella dell'eseguibile
- Controlla i log in `build\windows\x64\runner\Debug\` o `Release\`

## Performance

Per ottimizzare le performance su Windows:

1. **Usa sempre build di release** per test di performance
2. **Abilita le ottimizzazioni** del compilatore C++
3. **Considera il profiling** con DevTools

```bash
flutter run -d windows --profile
```
