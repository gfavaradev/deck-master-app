// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appName => 'Deck Master';

  @override
  String get btnContinue => 'Continua';

  @override
  String get btnStart => 'Inizia';

  @override
  String get btnCancel => 'Annulla';

  @override
  String get btnConfirm => 'Conferma';

  @override
  String get btnSave => 'Salva';

  @override
  String get btnDelete => 'Elimina';

  @override
  String get btnClose => 'Chiudi';

  @override
  String get btnRetry => 'Riprova';

  @override
  String get btnAdd => 'Aggiungi';

  @override
  String get btnCreate => 'Crea';

  @override
  String get btnEdit => 'Modifica';

  @override
  String get btnPublish => 'Pubblica';

  @override
  String get btnLogout => 'Logout';

  @override
  String get btnLogin => 'Accedi';

  @override
  String get btnRegister => 'Registrati';

  @override
  String get btnGoPro => 'Vai Pro';

  @override
  String get btnMove => 'Sposta';

  @override
  String get btnSearch => 'Cerca';

  @override
  String get btnApply => 'Applica';

  @override
  String get btnStart2 => 'Avvia';

  @override
  String get btnOk => 'OK';

  @override
  String get splashWelcomeFirst => 'Benvenuto,';

  @override
  String get splashWelcomeBack => 'Bentornato,';

  @override
  String get splashFirstLoginSubtitle =>
      'La tua avventura da collezionista inizia ora. 🎴';

  @override
  String get splashTapToContinue => 'Tocca per continuare';

  @override
  String get splashReturning1 => 'Le tue carte ti stavano aspettando.';

  @override
  String get splashReturning2 => 'Il tuo mazzo è pronto per l\'azione.';

  @override
  String get splashReturning3 =>
      'La collezione chiama, il collezionista risponde.';

  @override
  String get splashReturning4 =>
      'Ogni carta ha una storia. Qual è la tua di oggi?';

  @override
  String get onboardingSelectLanguageTitle => 'Seleziona la lingua';

  @override
  String get onboardingSelectLanguageSubtitle => 'Choose your language';

  @override
  String get onboardingSelectCurrencyTitle => 'Seleziona la valuta';

  @override
  String get onboardingSelectCurrencySubtitle =>
      'Select your preferred currency';

  @override
  String get onboardingStep1of2 => '1 / 2';

  @override
  String get onboardingStep2of2 => '2 / 2';

  @override
  String get loginSubtitle => 'La tua collezione di carte';

  @override
  String get loginAccessToContinue => 'Accedi per continuare';

  @override
  String get loginEmailPlaceholder => 'Email';

  @override
  String get loginPasswordPlaceholder => 'Password';

  @override
  String get loginBtnAccedi => 'ACCEDI';

  @override
  String get loginBtnRegistrati => 'REGISTRATI';

  @override
  String get loginNoAccount => 'Non hai un account? Registrati';

  @override
  String get loginHasAccount => 'Hai già un account? Accedi';

  @override
  String get loginOrContinueWith => 'Oppure continua con';

  @override
  String get loginContinueOfflineTooltip => 'Continua senza connessione';

  @override
  String get msgLoginCancelled => 'Accesso annullato o non riuscito';

  @override
  String get msgUserNotFound => 'Utente non trovato';

  @override
  String get msgInvalidCredentials => 'Credenziali non valide';

  @override
  String get msgEmailInUse => 'Email già in uso';

  @override
  String get msgLoginCancelledShort => 'Accesso annullato';

  @override
  String get msgPopupBlocked =>
      'Popup bloccato dal browser. Consenti i popup per questo sito.';

  @override
  String get msgUnauthorizedDomain =>
      'Dominio non autorizzato in Firebase Console';

  @override
  String get msgNetworkError => 'Errore di rete. Controlla la connessione.';

  @override
  String msgErrorGeneric(String error) {
    return 'Errore: $error';
  }

  @override
  String get msgInsertEmailPassword => 'Inserisci email e password';

  @override
  String get navHome => 'Home';

  @override
  String get navCards => 'Carte';

  @override
  String get navCatalog => 'Catalogo';

  @override
  String get navCollection => 'Raccolta';

  @override
  String get navNews => 'News';

  @override
  String get navMyCards => 'Le mie Carte';

  @override
  String get menuProfile => 'Profilo';

  @override
  String get menuSettings => 'Impostazioni';

  @override
  String get menuCheckUpdates => 'Controlla aggiornamenti';

  @override
  String get menuDonations => 'Offrimi un caffè';

  @override
  String get menuSupport => 'Supporto';

  @override
  String get tooltipBackToHome => 'Torna alla Home';

  @override
  String get tooltipScanCard => 'Scansiona carta';

  @override
  String get tooltipWishlist => 'Wishlist';

  @override
  String get tooltipRoi => 'Analisi ROI';

  @override
  String get tooltipNotifications => 'Notifiche';

  @override
  String get tooltipCatalogUpdate =>
      'Aggiornamento catalogo disponibile — tocca per scaricare';

  @override
  String get tooltipStats => 'Statistiche';

  @override
  String get tooltipUserMenu => 'Menu utente';

  @override
  String msgAppUpdated(String version) {
    return 'App aggiornata alla versione $version';
  }

  @override
  String get msgAlreadyLatestVersion =>
      'Sei già all\'ultima versione disponibile.';

  @override
  String get msgCatalogUpdatedSuccess => 'Catalogo aggiornato con successo!';

  @override
  String get msgCatalogRestoredSuccess => 'Catalogo ripristinato con successo!';

  @override
  String msgCatalogRestoreFailed(String error) {
    return 'Ripristino fallito: $error';
  }

  @override
  String msgErrorUpdateCollection(String name, String error) {
    return 'Errore aggiornamento $name: $error';
  }

  @override
  String msgErrorRestoreCollection(String name, String error) {
    return 'Errore ripristino $name: $error';
  }

  @override
  String msgLevelUp(int level) {
    return 'Sei salito al livello $level! 🎉';
  }

  @override
  String get popoverTapToClose => 'Tocca fuori per chiudere';

  @override
  String get downloadPhaseConnecting => 'Connessione in corso...';

  @override
  String get downloadPhaseDownloading => 'Download in corso...';

  @override
  String get downloadPhaseSaving => 'Salvataggio in corso...';

  @override
  String get downloadYugiohConnecting => 'Connessione al Mondo delle Ombre...';

  @override
  String get downloadYugiohDownloading =>
      'Maximillion Pegasus sta creando le carte...';

  @override
  String get downloadYugiohSaving =>
      'Il Faraone sigilla le carte nel Dueling Book...';

  @override
  String get downloadPokemonConnecting =>
      'Connessione al Lab. del Prof. Oak...';

  @override
  String get downloadPokemonDownloading =>
      'Il Prof. Oak sta catalogando i Pokémon...';

  @override
  String get downloadPokemonSaving => 'Archiviazione nel Pokédex Nazionale...';

  @override
  String get downloadOnepieceConnecting => 'Navigazione verso il Grand Line...';

  @override
  String get downloadOnepieceDownloading =>
      'Shanks sta distribuendo le carte...';

  @override
  String get downloadOnepieceSaving => 'Il Mugiwara Crew carica le carte...';

  @override
  String get downloadMagicConnecting => 'Connessione all\'Arxivio Arcano...';

  @override
  String get downloadMagicDownloading =>
      'Il Consiglio di Ravnica cataloga le carte...';

  @override
  String get downloadMagicSaving => 'Sigillatura nel Codex Magico...';

  @override
  String get adminCatalogTitle => 'Admin — Gestione Catalogo';

  @override
  String get homeMyCollections => 'Le mie Collezioni';

  @override
  String get homeAvailableCollections => 'Collezioni Disponibili';

  @override
  String get homeComingSoon => 'Prossimamente';

  @override
  String homeUnlockTitle(String name) {
    return 'Sblocca $name';
  }

  @override
  String homeUnlockFirstMsg(String name) {
    return 'Vuoi aggiungere $name come tua prima collezione? È completamente gratuita!';
  }

  @override
  String get homeUnlockProMsg =>
      'Con il piano Pro sblocchi tutte le collezioni senza pubblicità.';

  @override
  String get homeUnlockFree => 'GRATIS';

  @override
  String get homeUnlockBtn => 'Sblocca';

  @override
  String homeWatchVideoTitle(String name) {
    return 'Sblocca $name';
  }

  @override
  String get homeWatchVideoMsg =>
      'Guarda un breve video per sbloccare questa collezione gratuitamente.';

  @override
  String get homeWatchVideoProNote =>
      'Con il piano Pro sblocchi tutto senza pubblicità.';

  @override
  String get homeWatchVideoBtn => 'Guarda Video';

  @override
  String get msgVideoNotAvailable =>
      'Video non disponibile al momento. Riprova tra qualche secondo.';

  @override
  String msgCollectionUnlocked(String name) {
    return '$name sbloccata!';
  }

  @override
  String get msgVideoError => 'Errore durante il video. Riprova.';

  @override
  String get tutorialCollectionTitle => 'La tua Collezione';

  @override
  String get tutorialUnlockCollectionTitle => 'Sblocca una Collezione';

  @override
  String get tutorialCollectionDesc =>
      'Tocca questa card per aprire la tua collezione e iniziare ad aggiungere le tue carte!';

  @override
  String get tutorialUnlockCollectionDesc =>
      'Tocca questa card per sbloccare la tua prima collezione. È completamente gratuita!';

  @override
  String get tutorialScannerTitle => 'Scanner Carta';

  @override
  String get tutorialScannerDesc =>
      'Scansiona le tue carte fisiche con la fotocamera per aggiungerle automaticamente alla collezione.';

  @override
  String get tutorialWishlistTitle => 'Wishlist';

  @override
  String get tutorialWishlistDesc =>
      'Aggiungi le carte che vuoi acquistare e imposta un prezzo obiettivo. Riceverai un avviso quando il prezzo scende.';

  @override
  String get tutorialRoiTitle => 'Analisi ROI';

  @override
  String get tutorialRoiDesc =>
      'Inserisci il prezzo pagato per ogni carta e scopri quanto vale il tuo investimento nel tempo.';

  @override
  String get tutorialSkip => 'SALTA';

  @override
  String get settingsTitle => 'Impostazioni';

  @override
  String get settingsOfflineMode => 'Modalità Offline';

  @override
  String get settingsOfflineSubtitle =>
      'I dati non sono sincronizzati sul cloud';

  @override
  String get settingsSignInOnline => 'Accedi e torna online';

  @override
  String get settingsUserNotLogged => 'Utente non loggato';

  @override
  String get settingsViewProfile => 'Vedi Profilo';

  @override
  String get settingsSectionAdmin => 'Amministrazione';

  @override
  String get settingsManageUsers => 'Gestisci Utenti';

  @override
  String get settingsManageUsersSubtitle =>
      'Visualizza e modifica ruoli utenti';

  @override
  String get settingsManageCatalog => 'Gestisci Catalogo';

  @override
  String get settingsManageCatalogSubtitle =>
      'Aggiungi/Modifica carte nel catalogo';

  @override
  String get settingsSectionCatalogRestore => 'Ripristino Catalogo';

  @override
  String get settingsRestoreCatalog => 'Ripristina Catalogo';

  @override
  String get settingsRestoreCatalogSubtitle =>
      'Riscarica dal server e aggiorna il catalogo locale';

  @override
  String get settingsRestoreDialogTitle => 'Ripristina Catalogo';

  @override
  String get settingsRestoreDialogSubtitle =>
      'Il catalogo locale verrà cancellato e riscaricato dal server.';

  @override
  String get settingsRestoreAllCatalogs => 'Tutti i Cataloghi';

  @override
  String get settingsSectionExport => 'Esporta Collezione';

  @override
  String get settingsExportCsv => 'Esporta come CSV';

  @override
  String get settingsExportCsvSubtitle => 'Copia negli appunti — richiede Pro';

  @override
  String get settingsExportJson => 'Esporta come JSON';

  @override
  String get settingsExportJsonSubtitle => 'Copia negli appunti — richiede Pro';

  @override
  String msgCardsExported(int count, String format) {
    return '$count carte esportate come $format (negli appunti)';
  }

  @override
  String get msgExportProRequired => 'Funzione disponibile a breve';

  @override
  String msgExportError(String error) {
    return 'Errore esportazione: $error';
  }

  @override
  String get settingsSectionSync => 'Sincronizzazione';

  @override
  String get settingsResetSync => 'Ripristina Sincronizzazione';

  @override
  String get settingsResetSyncSubtitle =>
      'Risolve elementi duplicati nel cloud';

  @override
  String get dlgResetSyncTitle => 'Ripristina Sincronizzazione';

  @override
  String get dlgResetSyncMsg =>
      'Questa operazione deduplicerà le carte/album/deck presenti due volte, ripulirà il cloud e ricaricherà i dati corretti.\n\nProcedi solo se vedi elementi duplicati.';

  @override
  String get msgSyncRestoredSuccess =>
      'Sincronizzazione ripristinata con successo!';

  @override
  String get msgSyncStarting => 'Avvio...';

  @override
  String get settingsSectionGeneral => 'Generale';

  @override
  String get settingsPushNotifications => 'Notifiche Push';

  @override
  String get settingsPushNotificationsSubtitle => 'Ricevi notifiche dall\'app';

  @override
  String get settingsNotifAppUpdates => 'Aggiornamenti App';

  @override
  String get settingsNotifAppUpdatesSubtitle => 'Nuove versioni disponibili';

  @override
  String get settingsNotifCatalogUpdates => 'Aggiornamenti Catalogo';

  @override
  String get settingsNotifCatalogUpdatesSubtitle =>
      'Nuove carte e aggiornamenti prezzi';

  @override
  String get settingsLanguage => 'Lingua App';

  @override
  String get settingsLanguageDialogTitle => 'Lingua App';

  @override
  String get settingsCurrency => 'Valuta';

  @override
  String get settingsCurrencyDialogTitle => 'Valuta';

  @override
  String get settingsAppGuide => 'Guida all\'App';

  @override
  String get settingsAppGuideSubtitle => 'Rivedi il tutorial introduttivo';

  @override
  String get settingsSectionDanger => 'Zona Pericolosa';

  @override
  String get settingsDeleteAccount => 'Elimina Account';

  @override
  String get settingsDeleteAccountSubtitle =>
      'Elimina definitivamente il tuo account e tutti i dati';

  @override
  String get dlgDeleteAccountTitle => 'Elimina Account';

  @override
  String get dlgDeleteAccountMsg =>
      'Questa azione è irreversibile.\n\nIl tuo account e tutti i dati associati verranno eliminati definitivamente.';

  @override
  String get msgNotifPermissionDenied =>
      'Permesso notifiche negato. Abilitalo nelle impostazioni di sistema.';

  @override
  String get msgNoCollectionToRestore =>
      'Nessuna collezione sbloccata da ripristinare.';

  @override
  String get msgDeleteAccountRelogin =>
      'Per sicurezza, esci e accedi di nuovo prima di eliminare l\'account.';

  @override
  String get profileTitle => 'Profilo';

  @override
  String get profileNickname => 'Nickname';

  @override
  String get profileNicknameHint => 'Il tuo nome visualizzato';

  @override
  String get profileSaveNickname => 'Salva Nickname';

  @override
  String get profileAvatarSection => 'Avatar';

  @override
  String get profileAvatarSubtitle =>
      'Sblocca avatar collezionando carte. Ogni collezione ha i suoi avatar esclusivi.';

  @override
  String get profileGlobalAvatars => 'Avatar Globali';

  @override
  String profileLevelLabel(int level) {
    return 'Livello $level';
  }

  @override
  String get profileLevelMax => 'Livello MAX';

  @override
  String get profileMaxLevelReached => 'Hai raggiunto il livello massimo!';

  @override
  String profileXpInfo(int xp, int xpToNext) {
    return '$xp XP totali · ancora $xpToNext XP al prossimo livello';
  }

  @override
  String get msgNicknameSaved => 'Nickname aggiornato!';

  @override
  String get msgNicknameEmpty => 'Il nickname non può essere vuoto';

  @override
  String get catalogTitle => 'Catalogo';

  @override
  String get catalogSearchHint => 'Cerca per nome o seriale...';

  @override
  String get catalogLanguageTitle => 'Lingua Catalogo';

  @override
  String get catalogLanguageUnavailable =>
      'Le lingue grigie non sono ancora disponibili nel catalogo locale.';

  @override
  String get catalogLanguageNotAvailable => 'Non disponibile';

  @override
  String catalogNoCatalogDownloaded(String name) {
    return 'Catalogo $name non è ancora stato scaricato';
  }

  @override
  String get catalogDownloadPrompt =>
      'Scarica il catalogo per sfogliare e aggiungere carte alla tua collezione.';

  @override
  String get catalogDownloadBtn => 'Scarica catalogo';

  @override
  String get catalogDownloaded => 'Catalogo scaricato con successo!';

  @override
  String get catalogDownloadBusy =>
      'Un download è già in corso. Attendi il completamento.';

  @override
  String catalogDownloadError(String error) {
    return 'Errore download: $error';
  }

  @override
  String get catalogLoadError =>
      'Errore di caricamento. Controlla la connessione.';

  @override
  String get catalogNoCards => 'Nessuna carta trovata';

  @override
  String get catalogDownloadLabel => 'Download';

  @override
  String get catalogSelectAlbumTitle => 'Seleziona Album';

  @override
  String get catalogNoAlbumAvailable =>
      'Nessun album disponibile. Creane uno prima.';

  @override
  String get catalogLastUsed => 'Ultimo usato';

  @override
  String get catalogAddingProgress => 'Aggiunta in corso...';

  @override
  String catalogCardsProgress(int done, int total) {
    return '$done / $total carte elaborate';
  }

  @override
  String catalogAlbumFull(String name, int current, int max) {
    return 'Album \"$name\" è pieno ($current/$max).';
  }

  @override
  String catalogAlbumNearlyFull(int added, int total) {
    return 'Album quasi pieno: aggiunte solo $added/$total carte.';
  }

  @override
  String catalogAddResult(int added, int updated, int doppioni) {
    return '$added aggiunte, $updated quantità aggiornate, $doppioni nei Doppioni';
  }

  @override
  String get catalogNoChange => 'Nessuna modifica';

  @override
  String catalogAdded(int n) {
    return '$n aggiunte';
  }

  @override
  String catalogUpdatedQty(int n) {
    return '$n quantità aggiornate';
  }

  @override
  String catalogDoppioni(int n) {
    return '$n nei Doppioni';
  }

  @override
  String get catalogSelectAll => 'Seleziona tutto';

  @override
  String catalogCardsSelected(int n) {
    return '$n carte selezionate';
  }

  @override
  String get catalogAddingN => 'Aggiungendo...';

  @override
  String catalogAddN(int n) {
    return 'Aggiungi $n';
  }

  @override
  String get catalogSetCompleted => 'Set completato!';

  @override
  String catalogSetCompletedMsg(String setName, int total, int total2) {
    return '\"$setName\" è completo ($total / $total2 carte).';
  }

  @override
  String get catalogMoveToAlbum =>
      'Vuoi spostare tutte le carte di questo set in un album diverso?';

  @override
  String get catalogMoveInAlbumLabel => 'Sposta in album';

  @override
  String get catalogKeepCurrentAlbum => 'Mantieni album corrente';

  @override
  String catalogCardsMoved(String setName) {
    return 'Carte di \"$setName\" spostate!';
  }

  @override
  String get cardListSearchHint => 'Cerca per nome, seriale o rarità...';

  @override
  String get cardListViewTooltipList => 'Vista Lista';

  @override
  String get cardListViewTooltipGrid => 'Vista Griglia';

  @override
  String get cardListAlbumOnly =>
      'Stai visualizzando solo le carte di questo album';

  @override
  String get cardListEmptyAlbum =>
      'Non hai ancora aggiunto carte a questo album.\nAggiungi carte dal Catalogo selezionando questo album.';

  @override
  String get cardListEmptyCollection =>
      'Non hai ancora aggiunto carte.\nUsa il Catalogo per aggiungere carte.';

  @override
  String get cardListNotInCollection =>
      'Non in collezione — trovata nel catalogo';

  @override
  String get cardListNotInCatalog => 'Carta non disponibile nel catalogo';

  @override
  String get cardListNotInCatalogMsg =>
      'Questa carta non è ancora presente nel nostro catalogo. Puoi segnalarcela e la aggiungeremo il prima possibile.';

  @override
  String get cardListReportMissing => 'Segnala carta mancante';

  @override
  String get cardListDoppioneAdded =>
      'Doppione aggiunto all\'album \"Doppioni\"';

  @override
  String get cardListAlbumCatalog => 'Catalogo';

  @override
  String get cardListAlbumUnknown => 'Sconosciuto';

  @override
  String get selectionSelectCards => 'Seleziona carte';

  @override
  String selectionNSelected(int n) {
    return '$n selezionate';
  }

  @override
  String get selectionSelectAll => 'Seleziona tutto';

  @override
  String get selectionDeselectAll => 'Deseleziona tutto';

  @override
  String get selectionAlbumBtn => 'Album';

  @override
  String get selectionDeckBtn => 'Deck';

  @override
  String get selectionDeleteBtn => 'Elimina';

  @override
  String dlgDeleteNCardsTitle(int n) {
    return 'Elimina $n carte';
  }

  @override
  String dlgDeleteNCardsMsg(int n) {
    return 'Vuoi eliminare le $n carte selezionate?';
  }

  @override
  String msgNCardsDeleted(int n) {
    return '$n carte eliminate';
  }

  @override
  String get dlgMoveToAlbumTitle => 'Sposta in Album';

  @override
  String get dlgAddToDeckTitle => 'Aggiungi a Deck';

  @override
  String msgNCardsAddedToDeck(int n) {
    return '$n carte aggiunte al deck';
  }

  @override
  String get msgNoDeckAvailable =>
      'Nessun deck disponibile. Crea prima un deck.';

  @override
  String get dlgCapacityExceededTitle => 'Capacità Superata';

  @override
  String dlgCapacityExceededMsg(int current, int max) {
    return 'Supererà la capacità massima ($current/$max). Procedere?';
  }

  @override
  String get btnProceed => 'Procedi';

  @override
  String get cardDetailDeleteTitle => 'Elimina carta';

  @override
  String cardDetailDeleteMsg(String name) {
    return 'Eliminare \"$name\" dalla collezione?';
  }

  @override
  String get cardDetailTooltipDelete => 'Elimina';

  @override
  String get cardDetailPriceHistory => 'ANDAMENTO PREZZI';

  @override
  String get cardDetailAlbumSection => 'ALBUM';

  @override
  String get cardDetailMarketValue => 'VALORE DI MERCATO';

  @override
  String get cardDetailDeckSection => 'DECK';

  @override
  String get cardDetailDescription => 'DESCRIZIONE';

  @override
  String get cardDetailViewOnCardtrader => 'Vedi su CardTrader';

  @override
  String get setDetailNoCards => 'Nessuna carta.';

  @override
  String get setDetailRetry => 'Riprova';

  @override
  String get setDetailTabAll => 'Tutte';

  @override
  String get setDetailTabOwned => 'Possedute';

  @override
  String get setDetailTabMissing => 'Mancanti';

  @override
  String get setDetailLoadError => 'Errore nel caricamento';

  @override
  String get nounCards => 'carte';

  @override
  String setCompletionTitle(String name) {
    return 'Espansioni — $name';
  }

  @override
  String get setCompletionSearchHint => 'Cerca espansione...';

  @override
  String get deckListNewDeckTitle => 'Nuovo Deck';

  @override
  String get deckListNewDeckHint => 'Es. MazzoAttacco';

  @override
  String get deckListNoDecks => 'Nessun deck creato.';

  @override
  String get dlgDeleteDeckTitle => 'Elimina Deck';

  @override
  String dlgDeleteDeckMsg(String name) {
    return 'Sei sicuro di voler eliminare \"$name\"?';
  }

  @override
  String msgDeckDeleted(String name) {
    return 'Deck \"$name\" eliminato';
  }

  @override
  String get albumListNoAlbums => 'Nessun album creato.';

  @override
  String get dlgDeleteAlbumTitle => 'Elimina Album';

  @override
  String msgAlbumDeleted(String name) {
    return 'Album \"$name\" eliminato';
  }

  @override
  String get albumNewAlbumHint => 'Es. CollezioneBase';

  @override
  String get albumCapacityHint => '100';

  @override
  String get albumDeckPageNoAlbums => 'Nessun album creato.';

  @override
  String get albumDeckPageNoDecks => 'Nessun deck creato.';

  @override
  String get albumDeckPageAiDeckBuilder => 'AI Deck Builder';

  @override
  String get albumDeckPageNewDeck => 'Nuovo Deck';

  @override
  String get albumDeckPageNewAlbum => 'Nuovo Album';

  @override
  String get deckDetailSharePro => 'Condivisione Pro';

  @override
  String get deckDetailShareProMsg =>
      'La condivisione del deck è disponibile solo per gli utenti Pro.';

  @override
  String get deckDetailShareTooltip => 'Condividi Deck';

  @override
  String get deckDetailShareTooltipPro => 'Condividi Deck (Pro)';

  @override
  String get deckDetailAddBeforeShare =>
      'Aggiungi carte al deck prima di condividerlo';

  @override
  String get deckDetailSharedTitle => 'Deck Condiviso!';

  @override
  String get deckDetailCodeCopied => 'Codice copiato!';

  @override
  String get deckDetailInDeck => 'Nel Deck';

  @override
  String get deckDetailInDeckHint => 'Dettaglio • − per rimuovere';

  @override
  String get deckDetailOwned => 'Possedute';

  @override
  String get deckDetailOwnedHint => 'Tocca per aggiungere';

  @override
  String get deckDetailSearchHint => 'Cerca carta...';

  @override
  String get wishlistTitle => 'Wishlist';

  @override
  String get wishlistAddCard => 'Aggiungi carta';

  @override
  String get wishlistAddToWishlistTitle => 'Aggiungi alla Wishlist';

  @override
  String wishlistItemRemovedMsg(String name) {
    return '$name rimossa dalla Wishlist';
  }

  @override
  String get wishlistUndoRemove => 'Annulla';

  @override
  String get dlgTargetPriceTitle => 'Prezzo obiettivo';

  @override
  String dlgTargetPriceMsg(String name) {
    return 'Imposta il prezzo obiettivo per $name';
  }

  @override
  String get dlgTargetPriceLabel => 'Prezzo (€)';

  @override
  String get dlgRemoveWishlistTitle => 'Rimuovi dalla Wishlist';

  @override
  String dlgRemoveWishlistMsg(String name) {
    return 'Rimuovere \"$name\" dalla wishlist?';
  }

  @override
  String get btnRemove => 'Rimuovi';

  @override
  String get wishlistNdLabel => 'N/D';

  @override
  String get wishlistCatalogSearchTitle => 'Cerca nel catalogo';

  @override
  String get wishlistCatalogSearchHint => 'Cerca per nome o codice set...';

  @override
  String wishlistItemAddedMsg(String name) {
    return '$name aggiunta alla Wishlist';
  }

  @override
  String get wishlistAddToWishlistTooltip => 'Aggiungi alla Wishlist';

  @override
  String get wishlistNoResults => 'Nessun risultato trovato';

  @override
  String get statsTitle => 'Statistiche';

  @override
  String get statsPerCollection => 'Per Collezione';

  @override
  String statsCardsCount(int n) {
    return '$n carte';
  }

  @override
  String get statsPerRarity => 'Per Rarità (top 10)';

  @override
  String get statsSetsSection => 'Espansioni';

  @override
  String get statsTabCollection => 'Collezione';

  @override
  String get statsTabGlobal => 'Globale';

  @override
  String get roiTitle => 'Analisi ROI';

  @override
  String get roiPortfolio => 'Portafoglio';

  @override
  String get roiTotalValue => 'Valore totale';

  @override
  String get roiSection => 'ROI';

  @override
  String get roiInvested => 'Investito';

  @override
  String get roiValueCt => 'Valore CT';

  @override
  String get roiGain => 'Guadagno';

  @override
  String get roiPercent => 'ROI %';

  @override
  String get roiTrackedCards => 'Carte tracciate';

  @override
  String get roiPortfolioTitle => 'Valore Portfolio';

  @override
  String get roiPurchasePriceTitle => 'Prezzo d\'acquisto';

  @override
  String get roiPurchasePriceLabel => 'Prezzo pagato per copia (€)';

  @override
  String roiAddPricesBtn(String label) {
    return 'Aggiungi prezzi $label';
  }

  @override
  String get notificationsTitle => 'Notifiche';

  @override
  String get notifClearAllTitle => 'Cancella tutto';

  @override
  String get notifClearAllMsg => 'Vuoi eliminare tutte le notifiche?';

  @override
  String get notifClearAllTooltip => 'Cancella tutto';

  @override
  String get notifDownloadBtn => 'Scarica';

  @override
  String get newsTitle => 'News';

  @override
  String get newsNetworkError => 'Errore di rete';

  @override
  String get newsNetworkErrorSubtitle => 'Controlla la connessione e riprova.';

  @override
  String get newsNoNews => 'Nessuna news';

  @override
  String get newsNoNewsSubtitle =>
      'Non ci sono aggiornamenti per le tue collezioni.';

  @override
  String get newsRefreshTooltip => 'Aggiorna';

  @override
  String get newsHighlight => 'IN EVIDENZA';

  @override
  String get newsReadMore => 'Leggi di più';

  @override
  String get cardScannerTitle => 'Scansiona Carta';

  @override
  String get cardScannerLimitTitle => 'Limite scansioni raggiunto';

  @override
  String cardScannerNoAlbum(String collection) {
    return 'Nessun album trovato per $collection';
  }

  @override
  String cardScannerCardAdded(String name) {
    return '$name aggiunta alla collezione!';
  }

  @override
  String get cardScannerAddToCollection => 'Aggiungi a Collezione';

  @override
  String get cardScannerScanAnother => 'Scansiona un\'altra carta';

  @override
  String get cardScannerOpenCamera => 'Apri Fotocamera';

  @override
  String get cardScannerGoToPro => 'Passa a Pro';

  @override
  String get aiDeckBuilderTitle => 'AI Deck Builder';

  @override
  String get aiDeckBuilderPromptLabel => 'Descrivi la tua strategia';

  @override
  String get aiDeckBuilderPromptHint =>
      'Es: \"Un deck aggressivo Dragon con attacchi rapidi e fusioni potenti. Voglio usare i miei Blue-Eyes e un misto di carte di supporto.\"';

  @override
  String get aiDeckBuilderGenerateBtn => 'Genera Deck con AI';

  @override
  String get aiDeckBuilderGenerating => 'Analisi in corso…';

  @override
  String get aiDeckBuilderSaveBtn => 'Salva Deck';

  @override
  String aiDeckBuilderDeckSaved(String name, int n) {
    return 'Deck \"$name\" salvato! ($n carte aggiunte)';
  }

  @override
  String aiDeckBuilderSaveError(String error) {
    return 'Errore nel salvare: $error';
  }

  @override
  String get aiDeckBuilderMainLabel => 'Main';

  @override
  String get aiDeckBuilderExtraLabel => 'Extra';

  @override
  String get aiDeckBuilderOwnedLabel => 'Possedute';

  @override
  String get aiDeckBuilderGoToPro => 'Passa a Pro';

  @override
  String get aiDeckBuilderNotOwned => 'non posseduta';

  @override
  String get proTitle => 'Pro';

  @override
  String get proNotAvailable => 'Abbonamento non disponibile al momento.';

  @override
  String get proWelcomeMsg => 'Benvenuto nel piano Pro!';

  @override
  String get proPurchasesRestored => 'Acquisti ripristinati!';

  @override
  String get proNoPurchasesToRestore => 'Nessun acquisto da ripristinare.';

  @override
  String get proMonthlyLabel => 'Mensile';

  @override
  String get proYearlyLabel => 'Annuale';

  @override
  String get proYearlyTitle => 'Piano Annuale';

  @override
  String get proMonthlyTitle => 'Piano Mensile';

  @override
  String get donationsTitle => 'Supporta il Progetto';

  @override
  String get msgCantOpenLink => 'Impossibile aprire il link';

  @override
  String get supportTitle => 'Supporto';

  @override
  String get supportReportBugTitle => 'Segnala un Problema';

  @override
  String get supportReportBugSubtitle =>
      'Hai riscontrato un bug o un comportamento inatteso?';

  @override
  String get supportMissingCardsTitle => 'Carte Mancanti';

  @override
  String get supportMissingCardsSubtitle =>
      'Segnala carte assenti o con dati errati nel catalogo.';

  @override
  String get supportSuggestionTitle => 'Suggerimento';

  @override
  String get supportSuggestionSubtitle =>
      'Hai un\'idea per migliorare l\'app? Scrivici!';

  @override
  String get supportSupportProject => 'Supporta il progetto';

  @override
  String get msgNoEmailClient => 'Nessun client email trovato';

  @override
  String get tutorialPageTitle => 'Guida all\'App';

  @override
  String get tutorialStartBtn => 'Inizia il Tutorial';

  @override
  String get tutorialMaybeLater => 'Forse dopo';

  @override
  String get sharedDeckTitle => 'Deck Condiviso';

  @override
  String get sharedDeckNoCards => 'Non possiedi nessuna carta di questo deck';

  @override
  String sharedDeckImported(int n) {
    return 'Deck importato! ($n carte aggiunte)';
  }

  @override
  String get sharedDeckCodeHint => 'XXXXXX';

  @override
  String get sharedDeckCodeCopied => 'Codice copiato!';

  @override
  String sharedDeckByOwner(String owner, String collection, int total) {
    return 'di $owner · $collection · $total carte';
  }

  @override
  String get adminHomeCatalogTitle => 'Gestione Catalogo';

  @override
  String get adminHomePublishTooltip => 'Pubblica modifiche';

  @override
  String get adminHomeReloadTooltip => 'Ricarica';

  @override
  String get adminHomeNewCard => 'Nuova Carta';

  @override
  String get adminHomeSearchHint => 'Cerca carta (nome, archetipo, ID)...';

  @override
  String get adminHomeViewBtn => 'Visualizza';

  @override
  String get adminHomeSearchPrompt => 'Cerca una carta o aggiungi una nuova';

  @override
  String get adminCardAdded => 'Carta aggiunta alle modifiche';

  @override
  String get adminEditAdded => 'Modifica aggiunta';

  @override
  String get adminDeleteConfirmTitle => 'Conferma eliminazione';

  @override
  String adminDeleteConfirmMsg(String name) {
    return 'Vuoi eliminare \"$name\"?\nLa carta sarà rimossa al prossimo aggiornamento.';
  }

  @override
  String get adminDeleteAdded => 'Eliminazione aggiunta alle modifiche';

  @override
  String get adminPendingChangesTitle => 'Modifiche in sospeso';

  @override
  String get adminPublishTitle => 'Pubblica modifiche';

  @override
  String get adminPublishedSuccess => 'Pubblicato con successo';

  @override
  String get adminCollectionTitle => 'Pubblica Modifiche';

  @override
  String adminCollectionPublishMsg(int n) {
    return 'Pubblicare $n modifiche su Firestore?';
  }

  @override
  String get adminCollectionPublishSuccess =>
      'Modifiche pubblicate con successo!';

  @override
  String get adminCollectionSearchHint => 'Cerca per nome, ID o archetipo...';

  @override
  String get adminCollectionNoCards => 'Nessuna carta trovata';

  @override
  String get adminCollectionPublishTooltip => 'Pubblica modifiche';

  @override
  String get adminCollectionReloadTooltip => 'Ricarica da Firestore';

  @override
  String adminCollectionDeleteMsg(String name) {
    return 'Eliminare \"$name\" dal catalogo?';
  }

  @override
  String get adminCollectionCardEditedPending =>
      'Modifica in attesa di pubblicazione';

  @override
  String get adminCollectionCardAddedPending =>
      'Carta aggiunta — in attesa di pubblicazione';

  @override
  String get adminExcelTitle => 'Export / Import Excel';

  @override
  String get adminExcelImportConfirmTitle => 'Conferma importazione';

  @override
  String get adminExcelExportTitle => 'Esporta in Excel';

  @override
  String get adminExcelExportSubtitle =>
      'Genera un file .xlsx con due fogli:\n';

  @override
  String get adminExcelExportBtn => 'Esporta e Condividi';

  @override
  String get adminExcelImportTitle => 'Importa da Excel';

  @override
  String get adminExcelImportSubtitle =>
      'Seleziona un file .xlsx esportato da questa app con le ';

  @override
  String get adminExcelSelectFileBtn => 'Seleziona file .xlsx';

  @override
  String adminExcelApplyBtn(int n) {
    return 'Applica $n modifiche su Firestore';
  }

  @override
  String get adminSetsTitle => 'Espansioni & Rarità';

  @override
  String get adminSetsSyncTooltip => 'Sincronizza su Firestore';

  @override
  String get adminSetsSynced => 'Traduzioni sincronizzate su Firestore';

  @override
  String get adminSetsEditTooltip => 'Modifica traduzioni';

  @override
  String get adminUsersTitle => 'Gestione Utenti';

  @override
  String get adminUsersReloadTooltip => 'Ricarica';

  @override
  String get adminUsersNoUsers => 'Nessun utente trovato';

  @override
  String get adminUsersFilterAll => 'Tutti';

  @override
  String get adminUsersFilterAdmin => 'Admin';

  @override
  String get adminUsersFilterUsers => 'Utenti';

  @override
  String get adminUsersRoleUpdated => 'Ruolo aggiornato con successo';

  @override
  String adminUsersStatusUpdated(String status) {
    return 'Stato aggiornato: $status';
  }

  @override
  String get adminUsersDeletedSuccess => 'Utente eliminato con successo';

  @override
  String get adminUsersConfirmRoleTitle => 'Conferma cambio ruolo';

  @override
  String get adminUsersConfirmDeleteTitle => 'Conferma eliminazione';

  @override
  String get updateDialogRequired => 'Aggiornamento richiesto';

  @override
  String get updateDialogAvailable => 'Nuova versione disponibile';

  @override
  String get updateDialogForcedMsg =>
      'Questa versione non è più supportata. Aggiorna per continuare a usare l\'app.';

  @override
  String get updateDialogOptionalMsg =>
      'È disponibile una nuova versione con miglioramenti e correzioni.';

  @override
  String get updateDialogWhatsNew => 'Novità';

  @override
  String get updateDialogUpdateNow => 'Aggiorna ora';

  @override
  String get updateDialogNotNow => 'Non ora';

  @override
  String get cardDialogSelectAlbumLabel => 'Seleziona Album';

  @override
  String get cardDialogDeck => 'Deck';

  @override
  String get cardDialogDescription => 'Descrizione';

  @override
  String get cardDialogDeleteBtn => 'Elimina';

  @override
  String get cardDialogCloseBtn => 'Chiudi';

  @override
  String get cardDialogSaveBtn => 'Salva';

  @override
  String cardDialogAddToTitle(String collection) {
    return 'Aggiungi a $collection';
  }

  @override
  String get cardDialogNoAlbumTitle => 'Nessun Album';

  @override
  String get cardDialogNoAlbumMsg =>
      'Non hai ancora creato un album per questa collezione. Crea un album dalla sezione Raccolta.';

  @override
  String get cardDialogManageAlbum => 'Gestisci Album';

  @override
  String get cardDialogSelectFromCatalog => 'Seleziona una carta dal catalogo';

  @override
  String get cardDialogSelectAlbum => 'Seleziona un album';

  @override
  String get cardDialogNameEmpty => 'Il nome della carta non può essere vuoto.';

  @override
  String get cardDialogQtyMin => 'La quantità deve essere almeno 1.';

  @override
  String get cardDialogAlbumFullTitle => 'Album pieno';

  @override
  String get cardDialogDoppionAdded =>
      'Carta già presente nella collezione → aggiunta ai Doppioni';

  @override
  String get cardItemNdLabel => 'N/D';

  @override
  String get undoBarUndo => 'Annulla';

  @override
  String get adminCardEditSaveBtn => 'Salva Carta';

  @override
  String get adminCardEditImageHint => 'Carica dal dispositivo →';

  @override
  String get adminCardEditImageTooltip => 'Carica dal dispositivo';

  @override
  String get adminCardEditUploadFailed => 'Upload non riuscito o timeout';

  @override
  String get adminCardEditStatsNA =>
      'Statistiche non applicabili per questa collezione.';

  @override
  String get adminCardEditSpellTrapNA =>
      'Le Spell e Trap non hanno statistiche mostro';

  @override
  String get adminCardEditNoAttacks => 'Nessun attacco.';

  @override
  String get adminCardEditNoAbilities => 'Nessuna abilità.';

  @override
  String get adminCardEditSetsNoData => 'Nessun set per questa lingua.';

  @override
  String get adminCardEditAddSetTooltip => 'Aggiungi set';

  @override
  String get adminCardEditNewAttackTitle => 'Nuovo Attacco';

  @override
  String get adminCardEditEditAttackTitle => 'Modifica Attacco';

  @override
  String get adminCardEditNewAbilityTitle => 'Nuova Abilità';

  @override
  String get adminCardEditEditAbilityTitle => 'Modifica Abilità';

  @override
  String get adminCardEditGenerateFromEn => 'Genera da EN';

  @override
  String get adminHomeSessions =>
      'Sessione scaduta. Fai il logout e accedi di nuovo.';

  @override
  String get adminHomeOperationCancelled => 'Operazione annullata.';

  @override
  String get adminHomeManageProUsers => 'Gestisci Utenti Pro';

  @override
  String get adminHomeCtData => 'Catalogo';

  @override
  String get adminHomeCtBlueprint => 'CT blueprint';

  @override
  String get adminHomeCtWithPrice => 'Con prezzo';

  @override
  String get adminHomeCtDiff => 'Diff.';

  @override
  String get adminHomeCtNoData => 'Nessun dato CT in cache locale.';

  @override
  String get adminHomeFilterLabel => 'Filtro: ';
}
