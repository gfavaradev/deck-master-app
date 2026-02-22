# Guida Interfaccia Admin Catalogo Desktop

## Panoramica

L'interfaccia Admin Catalogo Desktop è stata progettata specificamente per **Windows e Web**, offrendo una vista database professionale per la gestione del catalogo delle carte Yu-Gi-Oh.

### Caratteristiche Principali

✅ **Vista Database Completa** - Tabella con tutte le colonne del catalogo
✅ **Ricerca Avanzata** - Cerca per nome, ID o archetipo
✅ **Ordinamento Colonne** - Click su intestazione per ordinare
✅ **Download Catalogo** - Scarica l'intero catalogo da Firebase
✅ **Modifiche Offline** - Tutte le modifiche vengono salvate localmente
✅ **Sincronizzazione Batch** - Una singola richiesta Firebase per pubblicare tutte le modifiche
✅ **Ottimizzato per Desktop** - Layout pensato per schermi grandi

## Accesso all'Interfaccia

### Requisiti

- **Ruolo**: Amministratore
- **Piattaforma**: Windows, macOS, Linux, o Web
- **Autenticazione**: Login con account admin

### Navigazione

```dart
// Da qualsiasi pagina dell'app
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const AdminCatalogDesktopPage(),
  ),
);
```

## Funzionalità Dettagliate

### 1. Download del Catalogo

Al primo accesso, se il catalogo locale è vuoto:

1. **Appare un dialog** che chiede se vuoi scaricare il catalogo
2. **Click su "Scarica"** per avviare il download
3. **Barra di progresso** mostra l'avanzamento
4. **Catalogo salvato** nel database locale per accesso futuro

```dart
// Il download avviene automaticamente in chunks da Firebase
final catalog = await _catalogService.downloadCurrentCatalog(
  'yugioh',
  onProgress: (current, total) {
    // Feedback in tempo reale
  },
);
```

### 2. Ricerca Carte

La barra di ricerca in alto permette di filtrare le carte:

- **Per Nome**: "Blue-Eyes", "Dark Magician"
- **Per ID**: "89631139", "46986414"
- **Per Archetipo**: "Blue-Eyes", "Hero"

La ricerca è **case-insensitive** e filtra in **tempo reale**.

### 3. Visualizzazione Tabella

#### Colonne Visualizzate

| Colonna | Descrizione | Ordinabile | Larghezza |
|---------|-------------|-----------|-----------|
| ID | ID univoco carta | ✅ | 100px |
| Nome | Nome della carta | ✅ | 250px |
| Tipo | Monster/Spell/Trap | ✅ | 120px |
| Archetipo | Famiglia carte | ✅ | 150px |
| Razza | Dragon, Spellcaster, etc. | ✅ | 120px |
| Attributo | DARK, LIGHT, etc. | ✅ | 100px |
| ATK | Punti attacco | ✅ | 80px |
| DEF | Punti difesa | ✅ | 80px |
| Level | Livello/Rank | ✅ | 80px |
| Descrizione | Effetto carta | ❌ | 300px |

#### Ordinamento

- **Click su intestazione** per ordinare per quella colonna
- **Primo click**: ordine ascendente ↑
- **Secondo click**: ordine discendente ↓
- **Indicatore visivo**: freccia mostra direzione ordinamento

### 4. Modifica Carte

#### Modificare una Carta Esistente

1. **Click su una riga** della tabella
2. **Dialog di modifica** si apre con dati precompilati
3. **Modifica i campi** desiderati
4. **Click "Salva Modifiche"**
5. La modifica viene **aggiunta alla coda** (modifiche in sospeso)

#### Campi Modificabili

**Informazioni Base:**
- Nome (obbligatorio)
- Tipo (Monster Card, Spell Card, Trap Card)
- Archetipo
- Razza

**Statistiche:**
- Attributo (DARK, LIGHT, WATER, etc.)
- ATK (punti attacco)
- DEF (punti difesa)
- Level (livello/rank)

**Descrizione:**
- Testo effetto carta (multilinea)

### 5. Aggiungere Nuove Carte

1. **Click FAB** "Nuova Carta" (pulsante viola in basso a destra)
2. **Compila il form** nel dialog
3. **Nome obbligatorio** - tutti gli altri campi opzionali
4. **Click "Aggiungi Carta"**
5. La carta viene **aggiunta alla coda** con ID auto-generato

### 6. Modifiche in Sospeso

Tutte le modifiche (aggiunte, modifiche, eliminazioni) vengono salvate **localmente** fino alla sincronizzazione.

#### Banner Modifiche

Quando ci sono modifiche in sospeso:
- **Banner arancione** appare sotto l'AppBar
- **Contatore** mostra numero modifiche
- **Pulsante "Visualizza"** per vedere dettagli

#### Visualizzare le Modifiche

Click su "Visualizza" per aprire dialog con:
- **Lista completa** modifiche in sospeso
- **Tipo operazione** (Aggiungi/Modifica/Elimina)
- **Data e ora** della modifica
- **Pulsante elimina** per rimuovere singole modifiche

#### Badge nell'AppBar

Indicatore arancione mostra numero modifiche pendenti:
```
🟠 3 modifiche
```

### 7. Sincronizzazione con Firebase

#### Quando Sincronizzare

Sincronizza quando:
- ✅ Hai finito tutte le modifiche
- ✅ Vuoi rendere le modifiche disponibili a tutti
- ✅ Vuoi fare backup del tuo lavoro

#### Come Sincronizzare

1. **Click icona cloud** ☁️ nell'AppBar
2. **Dialog di conferma** appare
3. **Review**: vedi numero modifiche da pubblicare
4. **Click "Sincronizza"**
5. **Attendi**: processo di sincronizzazione batch
6. **Successo**: modifiche pubblicate, coda svuotata

#### Cosa Succede Durante la Sincronizzazione

1. **Download catalogo corrente** da Firebase
2. **Applicazione modifiche** nell'ordine cronologico
3. **Upload catalogo aggiornato** in chunks ottimizzati
4. **Aggiornamento metadata** (versione, timestamp, admin)
5. **Pulizia coda locale** modifiche

```dart
// Sincronizzazione batch ottimizzata
final result = await _catalogService.publishChanges(
  adminUid: currentUserId,
  onProgress: (current, total) {
    // Feedback progresso
  },
);
```

## Workflow Tipico

### Scenario 1: Aggiungere Nuove Carte Custom

```
1. Apri interfaccia admin
2. Click "Nuova Carta"
3. Compila:
   - Nome: "My Custom Card"
   - Tipo: "Monster Card"
   - ATK: 2500
   - DEF: 2000
   - Descrizione: "Effect text..."
4. Salva
5. Ripeti per altre carte
6. Click sincronizza quando finito
```

### Scenario 2: Correggere Errori nel Catalogo

```
1. Cerca carta con errore (es. "Blue-Eyes")
2. Click sulla riga
3. Correggi campo errato
4. Salva modifica
5. Ripeti per altre correzioni
6. Sincronizza tutte le correzioni insieme
```

### Scenario 3: Aggiornamento Massivo

```
1. Download catalogo completo
2. Cerca e modifica carte per categoria (es. tutti i Dragons)
3. Accumula modifiche nella coda
4. Review modifiche pendenti
5. Sincronizza tutto con una singola operazione
```

## Ottimizzazione e Performance

### Download Catalogo

- **Chunked**: catalogo scaricato in blocchi da 1000 carte
- **Progress**: feedback visivo in tempo reale
- **Cache**: salvato localmente per accessi futuri
- **Efficiente**: solo al primo utilizzo o refresh manuale

### Sincronizzazione Batch

- **Single Request**: tutte le modifiche in una operazione
- **Atomica**: tutto succede o niente succede
- **Versioning**: sistema di versioni previene conflitti
- **Notifiche**: tutti gli utenti ricevono aggiornamento

### Tabella Database

- **Scroll Virtualization**: carica solo righe visibili
- **Sort In-Memory**: ordinamento veloce lato client
- **Filter On-Type**: filtro istantaneo mentre scrivi
- **Responsive**: layout adattivo per schermi grandi

## Sicurezza

### Controllo Accesso

```dart
// Solo admin possono accedere
final isAdmin = await _authService.isCurrentUserAdmin();
if (!isAdmin) {
  // Redirect o errore
}
```

### Tracking Modifiche

Ogni modifica registra:
- **Admin UID**: chi ha fatto la modifica
- **Timestamp**: quando è stata fatta
- **Change Type**: tipo di operazione
- **Original Data**: dati originali (per rollback futuro)

### Audit Log

Nel metadata Firebase:
```json
{
  "version": 42,
  "lastUpdated": "2026-02-18T10:30:00Z",
  "updatedBy": "admin_uid_123",
  "totalCards": 15234
}
```

## Troubleshooting

### Il catalogo non si carica

**Problema**: Tabella vuota al primo accesso
**Soluzione**: Click "Scarica" quando richiesto, oppure usa pulsante download nell'AppBar

### Modifiche non vengono salvate

**Problema**: Le modifiche scompaiono
**Soluzione**: Verifica di aver cliccato "Salva" nel dialog. Le modifiche sono nella coda locale fino alla sincronizzazione.

### Errore durante sincronizzazione

**Problema**: Sincronizzazione fallisce
**Soluzioni**:
1. Verifica connessione internet
2. Controlla permessi Firebase
3. Verifica di essere autenticato come admin
4. Controlla i log per errori specifici

### Performance lenta

**Problema**: Tabella lenta con molte carte
**Soluzioni**:
1. Usa filtro di ricerca per ridurre righe visualizzate
2. Evita ordinamenti frequenti su dataset grandi
3. Considera pagination futura per cataloghi enormi

## Sviluppi Futuri

### Funzionalità Pianificate

- [ ] **Modifica Inline**: edit celle direttamente nella tabella
- [ ] **Selezione Multipla**: seleziona e modifica più carte insieme
- [ ] **Import/Export CSV**: importa/esporta carte in batch
- [ ] **History/Rollback**: visualizza storico e ripristina versioni precedenti
- [ ] **Advanced Filters**: filtri complessi per tipo, rarità, etc.
- [ ] **Bulk Operations**: operazioni su selezioni multiple
- [ ] **Image Upload**: carica immagini carte direttamente
- [ ] **Preview Mode**: anteprima modifiche prima di sincronizzare

### Miglioramenti UI/UX

- [ ] **Dark Mode**: tema scuro per sessioni lunghe
- [ ] **Keyboard Shortcuts**: navigazione rapida da tastiera
- [ ] **Column Customization**: nascondi/mostra colonne
- [ ] **Resize Columns**: larghezze colonne personalizzabili
- [ ] **Pagination**: naviga tra pagine per cataloghi enormi
- [ ] **Export Report**: genera report delle modifiche

## Integrazione nell'App

### Aggiungi al Menu Admin

```dart
// In settings_page.dart o admin_page.dart
if (isAdmin) {
  ListTile(
    leading: Icon(Icons.table_chart),
    title: Text('Gestione Catalogo (Desktop)'),
    subtitle: Text('Interfaccia database completa'),
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const AdminCatalogDesktopPage(),
        ),
      );
    },
  ),
}
```

### Protezione Route

```dart
// Verifica admin prima di mostrare
class AdminCatalogRoute extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AuthService().isCurrentUserAdmin(),
      builder: (context, snapshot) {
        if (snapshot.data == true) {
          return AdminCatalogDesktopPage();
        }
        return Scaffold(
          body: Center(
            child: Text('Accesso negato - Solo amministratori'),
          ),
        );
      },
    );
  }
}
```

## Supporto

Per problemi o domande:
- Controlla i log dell'app con `flutter run --verbose`
- Verifica stato Firebase Console
- Controlla permessi utente in Firestore

## Note Tecniche

### Stack Tecnologico

- **Flutter**: Framework UI
- **Firebase Firestore**: Database cloud
- **SQLite**: Cache locale
- **SharedPreferences**: Coda modifiche locale

### Struttura Dati

```dart
// PendingCatalogChange
{
  'changeId': 'timestamp_random',
  'type': 'add|edit|delete',
  'cardData': {...},
  'originalCardId': 123,
  'timestamp': '2026-02-18T10:30:00Z',
  'adminUid': 'admin_123'
}
```

### Performance Metrics

- **Download**: ~5-10 sec per 10,000 carte
- **Sync**: ~10-20 sec per 100 modifiche
- **Search**: <100ms per query
- **Sort**: <200ms per 10,000 righe
