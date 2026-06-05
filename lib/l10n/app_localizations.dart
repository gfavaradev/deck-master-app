import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('it'),
  ];

  /// Application name
  ///
  /// In it, this message translates to:
  /// **'Deck Master'**
  String get appName;

  /// Continue button
  ///
  /// In it, this message translates to:
  /// **'Continua'**
  String get btnContinue;

  /// Start button
  ///
  /// In it, this message translates to:
  /// **'Inizia'**
  String get btnStart;

  /// Cancel button
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get btnCancel;

  /// Confirm button
  ///
  /// In it, this message translates to:
  /// **'Conferma'**
  String get btnConfirm;

  /// Save button
  ///
  /// In it, this message translates to:
  /// **'Salva'**
  String get btnSave;

  /// Delete button
  ///
  /// In it, this message translates to:
  /// **'Elimina'**
  String get btnDelete;

  /// Close button
  ///
  /// In it, this message translates to:
  /// **'Chiudi'**
  String get btnClose;

  /// Retry button
  ///
  /// In it, this message translates to:
  /// **'Riprova'**
  String get btnRetry;

  /// Add button
  ///
  /// In it, this message translates to:
  /// **'Aggiungi'**
  String get btnAdd;

  /// Create button
  ///
  /// In it, this message translates to:
  /// **'Crea'**
  String get btnCreate;

  /// Edit button
  ///
  /// In it, this message translates to:
  /// **'Modifica'**
  String get btnEdit;

  /// Publish button
  ///
  /// In it, this message translates to:
  /// **'Pubblica'**
  String get btnPublish;

  /// Logout button
  ///
  /// In it, this message translates to:
  /// **'Logout'**
  String get btnLogout;

  /// Login button
  ///
  /// In it, this message translates to:
  /// **'Accedi'**
  String get btnLogin;

  /// Register button
  ///
  /// In it, this message translates to:
  /// **'Registrati'**
  String get btnRegister;

  /// Go Pro button
  ///
  /// In it, this message translates to:
  /// **'Vai Pro'**
  String get btnGoPro;

  /// Move button
  ///
  /// In it, this message translates to:
  /// **'Sposta'**
  String get btnMove;

  /// Search button
  ///
  /// In it, this message translates to:
  /// **'Cerca'**
  String get btnSearch;

  /// Apply button
  ///
  /// In it, this message translates to:
  /// **'Applica'**
  String get btnApply;

  /// Start/launch button
  ///
  /// In it, this message translates to:
  /// **'Avvia'**
  String get btnStart2;

  /// OK button
  ///
  /// In it, this message translates to:
  /// **'OK'**
  String get btnOk;

  /// Greeting for first login
  ///
  /// In it, this message translates to:
  /// **'Benvenuto,'**
  String get splashWelcomeFirst;

  /// Greeting for returning user
  ///
  /// In it, this message translates to:
  /// **'Bentornato,'**
  String get splashWelcomeBack;

  /// Subtitle shown on first login
  ///
  /// In it, this message translates to:
  /// **'La tua avventura da collezionista inizia ora. 🎴'**
  String get splashFirstLoginSubtitle;

  /// Prompt to tap to continue on splash
  ///
  /// In it, this message translates to:
  /// **'Tocca per continuare'**
  String get splashTapToContinue;

  /// Returning user message 1
  ///
  /// In it, this message translates to:
  /// **'Le tue carte ti stavano aspettando.'**
  String get splashReturning1;

  /// Returning user message 2
  ///
  /// In it, this message translates to:
  /// **'Il tuo mazzo è pronto per l\'azione.'**
  String get splashReturning2;

  /// Returning user message 3
  ///
  /// In it, this message translates to:
  /// **'La collezione chiama, il collezionista risponde.'**
  String get splashReturning3;

  /// Returning user message 4
  ///
  /// In it, this message translates to:
  /// **'Ogni carta ha una storia. Qual è la tua di oggi?'**
  String get splashReturning4;

  /// Onboarding step 1 title - language selection
  ///
  /// In it, this message translates to:
  /// **'Seleziona la lingua'**
  String get onboardingSelectLanguageTitle;

  /// Onboarding step 1 subtitle in English
  ///
  /// In it, this message translates to:
  /// **'Choose your language'**
  String get onboardingSelectLanguageSubtitle;

  /// Onboarding step 2 title - currency selection
  ///
  /// In it, this message translates to:
  /// **'Seleziona la valuta'**
  String get onboardingSelectCurrencyTitle;

  /// Onboarding step 2 subtitle in English
  ///
  /// In it, this message translates to:
  /// **'Select your preferred currency'**
  String get onboardingSelectCurrencySubtitle;

  /// Step indicator 1 of 2
  ///
  /// In it, this message translates to:
  /// **'1 / 2'**
  String get onboardingStep1of2;

  /// Step indicator 2 of 2
  ///
  /// In it, this message translates to:
  /// **'2 / 2'**
  String get onboardingStep2of2;

  /// Login page subtitle
  ///
  /// In it, this message translates to:
  /// **'La tua collezione di carte'**
  String get loginSubtitle;

  /// Login prompt
  ///
  /// In it, this message translates to:
  /// **'Accedi per continuare'**
  String get loginAccessToContinue;

  /// Email field placeholder
  ///
  /// In it, this message translates to:
  /// **'Email'**
  String get loginEmailPlaceholder;

  /// Password field placeholder
  ///
  /// In it, this message translates to:
  /// **'Password'**
  String get loginPasswordPlaceholder;

  /// Login button uppercase
  ///
  /// In it, this message translates to:
  /// **'ACCEDI'**
  String get loginBtnAccedi;

  /// Register button uppercase
  ///
  /// In it, this message translates to:
  /// **'REGISTRATI'**
  String get loginBtnRegistrati;

  /// No account link
  ///
  /// In it, this message translates to:
  /// **'Non hai un account? Registrati'**
  String get loginNoAccount;

  /// Already have account link
  ///
  /// In it, this message translates to:
  /// **'Hai già un account? Accedi'**
  String get loginHasAccount;

  /// Or continue with divider text
  ///
  /// In it, this message translates to:
  /// **'Oppure continua con'**
  String get loginOrContinueWith;

  /// Offline button tooltip
  ///
  /// In it, this message translates to:
  /// **'Continua senza connessione'**
  String get loginContinueOfflineTooltip;

  /// Login cancelled snackbar
  ///
  /// In it, this message translates to:
  /// **'Accesso annullato o non riuscito'**
  String get msgLoginCancelled;

  /// User not found error
  ///
  /// In it, this message translates to:
  /// **'Utente non trovato'**
  String get msgUserNotFound;

  /// Invalid credentials error
  ///
  /// In it, this message translates to:
  /// **'Credenziali non valide'**
  String get msgInvalidCredentials;

  /// Email already in use error
  ///
  /// In it, this message translates to:
  /// **'Email già in uso'**
  String get msgEmailInUse;

  /// Login cancelled short message
  ///
  /// In it, this message translates to:
  /// **'Accesso annullato'**
  String get msgLoginCancelledShort;

  /// Popup blocked error
  ///
  /// In it, this message translates to:
  /// **'Popup bloccato dal browser. Consenti i popup per questo sito.'**
  String get msgPopupBlocked;

  /// Unauthorized domain error
  ///
  /// In it, this message translates to:
  /// **'Dominio non autorizzato in Firebase Console'**
  String get msgUnauthorizedDomain;

  /// Network error message
  ///
  /// In it, this message translates to:
  /// **'Errore di rete. Controlla la connessione.'**
  String get msgNetworkError;

  /// Generic error with details
  ///
  /// In it, this message translates to:
  /// **'Errore: {error}'**
  String msgErrorGeneric(String error);

  /// Missing email/password snackbar
  ///
  /// In it, this message translates to:
  /// **'Inserisci email e password'**
  String get msgInsertEmailPassword;

  /// Home navigation label
  ///
  /// In it, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Cards navigation label
  ///
  /// In it, this message translates to:
  /// **'Carte'**
  String get navCards;

  /// Catalog navigation label
  ///
  /// In it, this message translates to:
  /// **'Catalogo'**
  String get navCatalog;

  /// Collection navigation label
  ///
  /// In it, this message translates to:
  /// **'Raccolta'**
  String get navCollection;

  /// News navigation label
  ///
  /// In it, this message translates to:
  /// **'News'**
  String get navNews;

  /// My cards label in app bar
  ///
  /// In it, this message translates to:
  /// **'Le mie Carte'**
  String get navMyCards;

  /// Profile menu item
  ///
  /// In it, this message translates to:
  /// **'Profilo'**
  String get menuProfile;

  /// Settings menu item
  ///
  /// In it, this message translates to:
  /// **'Impostazioni'**
  String get menuSettings;

  /// Check for updates menu item
  ///
  /// In it, this message translates to:
  /// **'Controlla aggiornamenti'**
  String get menuCheckUpdates;

  /// Donations menu item
  ///
  /// In it, this message translates to:
  /// **'Offrimi un caffè'**
  String get menuDonations;

  /// Support menu item
  ///
  /// In it, this message translates to:
  /// **'Supporto'**
  String get menuSupport;

  /// Back to home tooltip
  ///
  /// In it, this message translates to:
  /// **'Torna alla Home'**
  String get tooltipBackToHome;

  /// Scan card tooltip
  ///
  /// In it, this message translates to:
  /// **'Scansiona carta'**
  String get tooltipScanCard;

  /// Wishlist tooltip
  ///
  /// In it, this message translates to:
  /// **'Wishlist'**
  String get tooltipWishlist;

  /// ROI analysis tooltip
  ///
  /// In it, this message translates to:
  /// **'Analisi ROI'**
  String get tooltipRoi;

  /// Notifications tooltip
  ///
  /// In it, this message translates to:
  /// **'Notifiche'**
  String get tooltipNotifications;

  /// Catalog update tooltip
  ///
  /// In it, this message translates to:
  /// **'Aggiornamento catalogo disponibile — tocca per scaricare'**
  String get tooltipCatalogUpdate;

  /// Statistics tooltip
  ///
  /// In it, this message translates to:
  /// **'Statistiche'**
  String get tooltipStats;

  /// User menu tooltip
  ///
  /// In it, this message translates to:
  /// **'Menu utente'**
  String get tooltipUserMenu;

  /// App updated snackbar
  ///
  /// In it, this message translates to:
  /// **'App aggiornata alla versione {version}'**
  String msgAppUpdated(String version);

  /// Already on latest version snackbar
  ///
  /// In it, this message translates to:
  /// **'Sei già all\'ultima versione disponibile.'**
  String get msgAlreadyLatestVersion;

  /// Catalog updated successfully snackbar
  ///
  /// In it, this message translates to:
  /// **'Catalogo aggiornato con successo!'**
  String get msgCatalogUpdatedSuccess;

  /// Catalog restored successfully snackbar
  ///
  /// In it, this message translates to:
  /// **'Catalogo ripristinato con successo!'**
  String get msgCatalogRestoredSuccess;

  /// Catalog restore failed snackbar
  ///
  /// In it, this message translates to:
  /// **'Ripristino fallito: {error}'**
  String msgCatalogRestoreFailed(String error);

  /// Error updating collection
  ///
  /// In it, this message translates to:
  /// **'Errore aggiornamento {name}: {error}'**
  String msgErrorUpdateCollection(String name, String error);

  /// Error restoring collection
  ///
  /// In it, this message translates to:
  /// **'Errore ripristino {name}: {error}'**
  String msgErrorRestoreCollection(String name, String error);

  /// Level up snackbar
  ///
  /// In it, this message translates to:
  /// **'Sei salito al livello {level}! 🎉'**
  String msgLevelUp(int level);

  /// Download popover tap to close hint
  ///
  /// In it, this message translates to:
  /// **'Tocca fuori per chiudere'**
  String get popoverTapToClose;

  /// Generic connecting phase message
  ///
  /// In it, this message translates to:
  /// **'Connessione in corso...'**
  String get downloadPhaseConnecting;

  /// Generic downloading phase message
  ///
  /// In it, this message translates to:
  /// **'Download in corso...'**
  String get downloadPhaseDownloading;

  /// Generic saving phase message
  ///
  /// In it, this message translates to:
  /// **'Salvataggio in corso...'**
  String get downloadPhaseSaving;

  /// YuGiOh connecting message
  ///
  /// In it, this message translates to:
  /// **'Connessione al Mondo delle Ombre...'**
  String get downloadYugiohConnecting;

  /// YuGiOh downloading message
  ///
  /// In it, this message translates to:
  /// **'Maximillion Pegasus sta creando le carte...'**
  String get downloadYugiohDownloading;

  /// YuGiOh saving message
  ///
  /// In it, this message translates to:
  /// **'Il Faraone sigilla le carte nel Dueling Book...'**
  String get downloadYugiohSaving;

  /// Pokemon connecting message
  ///
  /// In it, this message translates to:
  /// **'Connessione al Lab. del Prof. Oak...'**
  String get downloadPokemonConnecting;

  /// Pokemon downloading message
  ///
  /// In it, this message translates to:
  /// **'Il Prof. Oak sta catalogando i Pokémon...'**
  String get downloadPokemonDownloading;

  /// Pokemon saving message
  ///
  /// In it, this message translates to:
  /// **'Archiviazione nel Pokédex Nazionale...'**
  String get downloadPokemonSaving;

  /// One Piece connecting message
  ///
  /// In it, this message translates to:
  /// **'Navigazione verso il Grand Line...'**
  String get downloadOnepieceConnecting;

  /// One Piece downloading message
  ///
  /// In it, this message translates to:
  /// **'Shanks sta distribuendo le carte...'**
  String get downloadOnepieceDownloading;

  /// One Piece saving message
  ///
  /// In it, this message translates to:
  /// **'Il Mugiwara Crew carica le carte...'**
  String get downloadOnepieceSaving;

  /// Magic connecting message
  ///
  /// In it, this message translates to:
  /// **'Connessione all\'Arxivio Arcano...'**
  String get downloadMagicConnecting;

  /// Magic downloading message
  ///
  /// In it, this message translates to:
  /// **'Il Consiglio di Ravnica cataloga le carte...'**
  String get downloadMagicDownloading;

  /// Magic saving message
  ///
  /// In it, this message translates to:
  /// **'Sigillatura nel Codex Magico...'**
  String get downloadMagicSaving;

  /// Admin catalog appbar title
  ///
  /// In it, this message translates to:
  /// **'Admin — Gestione Catalogo'**
  String get adminCatalogTitle;

  /// My collections section title
  ///
  /// In it, this message translates to:
  /// **'Le mie Collezioni'**
  String get homeMyCollections;

  /// Available collections section title
  ///
  /// In it, this message translates to:
  /// **'Collezioni Disponibili'**
  String get homeAvailableCollections;

  /// Coming soon badge on locked collections
  ///
  /// In it, this message translates to:
  /// **'Prossimamente'**
  String get homeComingSoon;

  /// Unlock collection dialog title
  ///
  /// In it, this message translates to:
  /// **'Sblocca {name}'**
  String homeUnlockTitle(String name);

  /// First unlock dialog message
  ///
  /// In it, this message translates to:
  /// **'Vuoi aggiungere {name} come tua prima collezione? È completamente gratuita!'**
  String homeUnlockFirstMsg(String name);

  /// Pro unlock dialog message
  ///
  /// In it, this message translates to:
  /// **'Con il piano Pro sblocchi tutte le collezioni senza pubblicità.'**
  String get homeUnlockProMsg;

  /// Free badge on collection
  ///
  /// In it, this message translates to:
  /// **'GRATIS'**
  String get homeUnlockFree;

  /// Unlock button label
  ///
  /// In it, this message translates to:
  /// **'Sblocca'**
  String get homeUnlockBtn;

  /// Watch video to unlock dialog title
  ///
  /// In it, this message translates to:
  /// **'Sblocca {name}'**
  String homeWatchVideoTitle(String name);

  /// Watch video dialog message
  ///
  /// In it, this message translates to:
  /// **'Guarda un breve video per sbloccare questa collezione gratuitamente.'**
  String get homeWatchVideoMsg;

  /// Pro note in watch video dialog
  ///
  /// In it, this message translates to:
  /// **'Con il piano Pro sblocchi tutto senza pubblicità.'**
  String get homeWatchVideoProNote;

  /// Watch video button
  ///
  /// In it, this message translates to:
  /// **'Guarda Video'**
  String get homeWatchVideoBtn;

  /// Video not available snackbar
  ///
  /// In it, this message translates to:
  /// **'Video non disponibile al momento. Riprova tra qualche secondo.'**
  String get msgVideoNotAvailable;

  /// Collection unlocked snackbar
  ///
  /// In it, this message translates to:
  /// **'{name} sbloccata!'**
  String msgCollectionUnlocked(String name);

  /// Video error snackbar
  ///
  /// In it, this message translates to:
  /// **'Errore durante il video. Riprova.'**
  String get msgVideoError;

  /// Tutorial phase 0 unlocked title
  ///
  /// In it, this message translates to:
  /// **'La tua Collezione'**
  String get tutorialCollectionTitle;

  /// Tutorial phase 0 locked title
  ///
  /// In it, this message translates to:
  /// **'Sblocca una Collezione'**
  String get tutorialUnlockCollectionTitle;

  /// Tutorial phase 0 unlocked description
  ///
  /// In it, this message translates to:
  /// **'Tocca questa card per aprire la tua collezione e iniziare ad aggiungere le tue carte!'**
  String get tutorialCollectionDesc;

  /// Tutorial phase 0 locked description
  ///
  /// In it, this message translates to:
  /// **'Tocca questa card per sbloccare la tua prima collezione. È completamente gratuita!'**
  String get tutorialUnlockCollectionDesc;

  /// Tutorial scanner title
  ///
  /// In it, this message translates to:
  /// **'Scanner Carta'**
  String get tutorialScannerTitle;

  /// Tutorial scanner description
  ///
  /// In it, this message translates to:
  /// **'Scansiona le tue carte fisiche con la fotocamera per aggiungerle automaticamente alla collezione.'**
  String get tutorialScannerDesc;

  /// Tutorial wishlist title
  ///
  /// In it, this message translates to:
  /// **'Wishlist'**
  String get tutorialWishlistTitle;

  /// Tutorial wishlist description
  ///
  /// In it, this message translates to:
  /// **'Aggiungi le carte che vuoi acquistare e imposta un prezzo obiettivo. Riceverai un avviso quando il prezzo scende.'**
  String get tutorialWishlistDesc;

  /// Tutorial ROI title
  ///
  /// In it, this message translates to:
  /// **'Analisi ROI'**
  String get tutorialRoiTitle;

  /// Tutorial ROI description
  ///
  /// In it, this message translates to:
  /// **'Inserisci il prezzo pagato per ogni carta e scopri quanto vale il tuo investimento nel tempo.'**
  String get tutorialRoiDesc;

  /// Tutorial skip button text
  ///
  /// In it, this message translates to:
  /// **'SALTA'**
  String get tutorialSkip;

  /// Settings page title
  ///
  /// In it, this message translates to:
  /// **'Impostazioni'**
  String get settingsTitle;

  /// Offline mode label
  ///
  /// In it, this message translates to:
  /// **'Modalità Offline'**
  String get settingsOfflineMode;

  /// Offline mode subtitle
  ///
  /// In it, this message translates to:
  /// **'I dati non sono sincronizzati sul cloud'**
  String get settingsOfflineSubtitle;

  /// Sign in and go online button
  ///
  /// In it, this message translates to:
  /// **'Accedi e torna online'**
  String get settingsSignInOnline;

  /// User not logged label
  ///
  /// In it, this message translates to:
  /// **'Utente non loggato'**
  String get settingsUserNotLogged;

  /// View profile link
  ///
  /// In it, this message translates to:
  /// **'Vedi Profilo'**
  String get settingsViewProfile;

  /// Admin section header
  ///
  /// In it, this message translates to:
  /// **'Amministrazione'**
  String get settingsSectionAdmin;

  /// Manage users tile
  ///
  /// In it, this message translates to:
  /// **'Gestisci Utenti'**
  String get settingsManageUsers;

  /// Manage users subtitle
  ///
  /// In it, this message translates to:
  /// **'Visualizza e modifica ruoli utenti'**
  String get settingsManageUsersSubtitle;

  /// Manage catalog tile
  ///
  /// In it, this message translates to:
  /// **'Gestisci Catalogo'**
  String get settingsManageCatalog;

  /// Manage catalog subtitle
  ///
  /// In it, this message translates to:
  /// **'Aggiungi/Modifica carte nel catalogo'**
  String get settingsManageCatalogSubtitle;

  /// Catalog restore section header
  ///
  /// In it, this message translates to:
  /// **'Ripristino Catalogo'**
  String get settingsSectionCatalogRestore;

  /// Restore catalog tile
  ///
  /// In it, this message translates to:
  /// **'Ripristina Catalogo'**
  String get settingsRestoreCatalog;

  /// Restore catalog subtitle
  ///
  /// In it, this message translates to:
  /// **'Riscarica dal server e aggiorna il catalogo locale'**
  String get settingsRestoreCatalogSubtitle;

  /// Restore catalog bottom sheet title
  ///
  /// In it, this message translates to:
  /// **'Ripristina Catalogo'**
  String get settingsRestoreDialogTitle;

  /// Restore catalog bottom sheet subtitle
  ///
  /// In it, this message translates to:
  /// **'Il catalogo locale verrà cancellato e riscaricato dal server.'**
  String get settingsRestoreDialogSubtitle;

  /// Restore all catalogs option
  ///
  /// In it, this message translates to:
  /// **'Tutti i Cataloghi'**
  String get settingsRestoreAllCatalogs;

  /// Export section header
  ///
  /// In it, this message translates to:
  /// **'Esporta Collezione'**
  String get settingsSectionExport;

  /// Export as CSV tile
  ///
  /// In it, this message translates to:
  /// **'Esporta come CSV'**
  String get settingsExportCsv;

  /// Export CSV subtitle
  ///
  /// In it, this message translates to:
  /// **'Copia negli appunti — richiede Pro'**
  String get settingsExportCsvSubtitle;

  /// Export as JSON tile
  ///
  /// In it, this message translates to:
  /// **'Esporta come JSON'**
  String get settingsExportJson;

  /// Export JSON subtitle
  ///
  /// In it, this message translates to:
  /// **'Copia negli appunti — richiede Pro'**
  String get settingsExportJsonSubtitle;

  /// Cards exported snackbar
  ///
  /// In it, this message translates to:
  /// **'{count} carte esportate come {format} (negli appunti)'**
  String msgCardsExported(int count, String format);

  /// Export pro required snackbar
  ///
  /// In it, this message translates to:
  /// **'Funzione disponibile a breve'**
  String get msgExportProRequired;

  /// Export error snackbar
  ///
  /// In it, this message translates to:
  /// **'Errore esportazione: {error}'**
  String msgExportError(String error);

  /// Sync section header
  ///
  /// In it, this message translates to:
  /// **'Sincronizzazione'**
  String get settingsSectionSync;

  /// Reset sync tile
  ///
  /// In it, this message translates to:
  /// **'Ripristina Sincronizzazione'**
  String get settingsResetSync;

  /// Reset sync subtitle
  ///
  /// In it, this message translates to:
  /// **'Risolve elementi duplicati nel cloud'**
  String get settingsResetSyncSubtitle;

  /// Reset sync dialog title
  ///
  /// In it, this message translates to:
  /// **'Ripristina Sincronizzazione'**
  String get dlgResetSyncTitle;

  /// Reset sync dialog message
  ///
  /// In it, this message translates to:
  /// **'Questa operazione deduplicerà le carte/album/deck presenti due volte, ripulirà il cloud e ricaricherà i dati corretti.\n\nProcedi solo se vedi elementi duplicati.'**
  String get dlgResetSyncMsg;

  /// Sync restored successfully snackbar
  ///
  /// In it, this message translates to:
  /// **'Sincronizzazione ripristinata con successo!'**
  String get msgSyncRestoredSuccess;

  /// Sync starting status
  ///
  /// In it, this message translates to:
  /// **'Avvio...'**
  String get msgSyncStarting;

  /// General section header
  ///
  /// In it, this message translates to:
  /// **'Generale'**
  String get settingsSectionGeneral;

  /// Push notifications toggle tile
  ///
  /// In it, this message translates to:
  /// **'Notifiche Push'**
  String get settingsPushNotifications;

  /// Push notifications subtitle
  ///
  /// In it, this message translates to:
  /// **'Ricevi notifiche dall\'app'**
  String get settingsPushNotificationsSubtitle;

  /// App updates notification toggle
  ///
  /// In it, this message translates to:
  /// **'Aggiornamenti App'**
  String get settingsNotifAppUpdates;

  /// App updates notification subtitle
  ///
  /// In it, this message translates to:
  /// **'Nuove versioni disponibili'**
  String get settingsNotifAppUpdatesSubtitle;

  /// Catalog updates notification toggle
  ///
  /// In it, this message translates to:
  /// **'Aggiornamenti Catalogo'**
  String get settingsNotifCatalogUpdates;

  /// Catalog updates notification subtitle
  ///
  /// In it, this message translates to:
  /// **'Nuove carte e aggiornamenti prezzi'**
  String get settingsNotifCatalogUpdatesSubtitle;

  /// App language tile
  ///
  /// In it, this message translates to:
  /// **'Lingua App'**
  String get settingsLanguage;

  /// Language picker sheet title
  ///
  /// In it, this message translates to:
  /// **'Lingua App'**
  String get settingsLanguageDialogTitle;

  /// Currency tile
  ///
  /// In it, this message translates to:
  /// **'Valuta'**
  String get settingsCurrency;

  /// Currency picker sheet title
  ///
  /// In it, this message translates to:
  /// **'Valuta'**
  String get settingsCurrencyDialogTitle;

  /// App guide tile
  ///
  /// In it, this message translates to:
  /// **'Guida all\'App'**
  String get settingsAppGuide;

  /// App guide subtitle
  ///
  /// In it, this message translates to:
  /// **'Rivedi il tutorial introduttivo'**
  String get settingsAppGuideSubtitle;

  /// Danger zone section header
  ///
  /// In it, this message translates to:
  /// **'Zona Pericolosa'**
  String get settingsSectionDanger;

  /// Delete account tile
  ///
  /// In it, this message translates to:
  /// **'Elimina Account'**
  String get settingsDeleteAccount;

  /// Delete account subtitle
  ///
  /// In it, this message translates to:
  /// **'Elimina definitivamente il tuo account e tutti i dati'**
  String get settingsDeleteAccountSubtitle;

  /// Delete account dialog title
  ///
  /// In it, this message translates to:
  /// **'Elimina Account'**
  String get dlgDeleteAccountTitle;

  /// Delete account dialog message
  ///
  /// In it, this message translates to:
  /// **'Questa azione è irreversibile.\n\nIl tuo account e tutti i dati associati verranno eliminati definitivamente.'**
  String get dlgDeleteAccountMsg;

  /// Notification permission denied snackbar
  ///
  /// In it, this message translates to:
  /// **'Permesso notifiche negato. Abilitalo nelle impostazioni di sistema.'**
  String get msgNotifPermissionDenied;

  /// No collection to restore snackbar
  ///
  /// In it, this message translates to:
  /// **'Nessuna collezione sbloccata da ripristinare.'**
  String get msgNoCollectionToRestore;

  /// Requires recent login for delete account
  ///
  /// In it, this message translates to:
  /// **'Per sicurezza, esci e accedi di nuovo prima di eliminare l\'account.'**
  String get msgDeleteAccountRelogin;

  /// Profile page title
  ///
  /// In it, this message translates to:
  /// **'Profilo'**
  String get profileTitle;

  /// Nickname label
  ///
  /// In it, this message translates to:
  /// **'Nickname'**
  String get profileNickname;

  /// Nickname hint text
  ///
  /// In it, this message translates to:
  /// **'Il tuo nome visualizzato'**
  String get profileNicknameHint;

  /// Save nickname button
  ///
  /// In it, this message translates to:
  /// **'Salva Nickname'**
  String get profileSaveNickname;

  /// Avatar section header
  ///
  /// In it, this message translates to:
  /// **'Avatar'**
  String get profileAvatarSection;

  /// Avatar section subtitle
  ///
  /// In it, this message translates to:
  /// **'Sblocca avatar collezionando carte. Ogni collezione ha i suoi avatar esclusivi.'**
  String get profileAvatarSubtitle;

  /// Global avatars section
  ///
  /// In it, this message translates to:
  /// **'Avatar Globali'**
  String get profileGlobalAvatars;

  /// Level label
  ///
  /// In it, this message translates to:
  /// **'Livello {level}'**
  String profileLevelLabel(int level);

  /// Max level reached label
  ///
  /// In it, this message translates to:
  /// **'Livello MAX'**
  String get profileLevelMax;

  /// Max level reached message
  ///
  /// In it, this message translates to:
  /// **'Hai raggiunto il livello massimo!'**
  String get profileMaxLevelReached;

  /// XP info text
  ///
  /// In it, this message translates to:
  /// **'{xp} XP totali · ancora {xpToNext} XP al prossimo livello'**
  String profileXpInfo(int xp, int xpToNext);

  /// Nickname saved snackbar
  ///
  /// In it, this message translates to:
  /// **'Nickname aggiornato!'**
  String get msgNicknameSaved;

  /// Nickname empty snackbar
  ///
  /// In it, this message translates to:
  /// **'Il nickname non può essere vuoto'**
  String get msgNicknameEmpty;

  /// Catalog page title
  ///
  /// In it, this message translates to:
  /// **'Catalogo'**
  String get catalogTitle;

  /// Catalog search hint
  ///
  /// In it, this message translates to:
  /// **'Cerca per nome o seriale...'**
  String get catalogSearchHint;

  /// Catalog language picker title
  ///
  /// In it, this message translates to:
  /// **'Lingua Catalogo'**
  String get catalogLanguageTitle;

  /// Catalog language unavailable hint
  ///
  /// In it, this message translates to:
  /// **'Le lingue grigie non sono ancora disponibili nel catalogo locale.'**
  String get catalogLanguageUnavailable;

  /// Language not available label
  ///
  /// In it, this message translates to:
  /// **'Non disponibile'**
  String get catalogLanguageNotAvailable;

  /// Catalog not downloaded title
  ///
  /// In it, this message translates to:
  /// **'Catalogo {name} non è ancora stato scaricato'**
  String catalogNoCatalogDownloaded(String name);

  /// Catalog download prompt
  ///
  /// In it, this message translates to:
  /// **'Scarica il catalogo per sfogliare e aggiungere carte alla tua collezione.'**
  String get catalogDownloadPrompt;

  /// Download catalog button
  ///
  /// In it, this message translates to:
  /// **'Scarica catalogo'**
  String get catalogDownloadBtn;

  /// Catalog downloaded snackbar
  ///
  /// In it, this message translates to:
  /// **'Catalogo scaricato con successo!'**
  String get catalogDownloaded;

  /// Download busy snackbar
  ///
  /// In it, this message translates to:
  /// **'Un download è già in corso. Attendi il completamento.'**
  String get catalogDownloadBusy;

  /// Catalog download error
  ///
  /// In it, this message translates to:
  /// **'Errore download: {error}'**
  String catalogDownloadError(String error);

  /// Catalog load error
  ///
  /// In it, this message translates to:
  /// **'Errore di caricamento. Controlla la connessione.'**
  String get catalogLoadError;

  /// No cards found in catalog
  ///
  /// In it, this message translates to:
  /// **'Nessuna carta trovata'**
  String get catalogNoCards;

  /// Download label in catalog missing state
  ///
  /// In it, this message translates to:
  /// **'Download'**
  String get catalogDownloadLabel;

  /// Select album dialog title
  ///
  /// In it, this message translates to:
  /// **'Seleziona Album'**
  String get catalogSelectAlbumTitle;

  /// No album available message
  ///
  /// In it, this message translates to:
  /// **'Nessun album disponibile. Creane uno prima.'**
  String get catalogNoAlbumAvailable;

  /// Last used album label
  ///
  /// In it, this message translates to:
  /// **'Ultimo usato'**
  String get catalogLastUsed;

  /// Adding cards in progress dialog title
  ///
  /// In it, this message translates to:
  /// **'Aggiunta in corso...'**
  String get catalogAddingProgress;

  /// Cards progress text
  ///
  /// In it, this message translates to:
  /// **'{done} / {total} carte elaborate'**
  String catalogCardsProgress(int done, int total);

  /// Album full snackbar
  ///
  /// In it, this message translates to:
  /// **'Album \"{name}\" è pieno ({current}/{max}).'**
  String catalogAlbumFull(String name, int current, int max);

  /// Album nearly full snackbar
  ///
  /// In it, this message translates to:
  /// **'Album quasi pieno: aggiunte solo {added}/{total} carte.'**
  String catalogAlbumNearlyFull(int added, int total);

  /// Add result snackbar — actually built dynamically, used as reference
  ///
  /// In it, this message translates to:
  /// **'{added} aggiunte, {updated} quantità aggiornate, {doppioni} nei Doppioni'**
  String catalogAddResult(int added, int updated, int doppioni);

  /// No change result
  ///
  /// In it, this message translates to:
  /// **'Nessuna modifica'**
  String get catalogNoChange;

  /// N cards added
  ///
  /// In it, this message translates to:
  /// **'{n} aggiunte'**
  String catalogAdded(int n);

  /// N quantities updated
  ///
  /// In it, this message translates to:
  /// **'{n} quantità aggiornate'**
  String catalogUpdatedQty(int n);

  /// N duplicates
  ///
  /// In it, this message translates to:
  /// **'{n} nei Doppioni'**
  String catalogDoppioni(int n);

  /// Select all tooltip
  ///
  /// In it, this message translates to:
  /// **'Seleziona tutto'**
  String get catalogSelectAll;

  /// N cards selected banner
  ///
  /// In it, this message translates to:
  /// **'{n} carte selezionate'**
  String catalogCardsSelected(int n);

  /// Adding in progress FAB label
  ///
  /// In it, this message translates to:
  /// **'Aggiungendo...'**
  String get catalogAddingN;

  /// Add N cards FAB label
  ///
  /// In it, this message translates to:
  /// **'Aggiungi {n}'**
  String catalogAddN(int n);

  /// Set completed dialog title
  ///
  /// In it, this message translates to:
  /// **'Set completato!'**
  String get catalogSetCompleted;

  /// Set completed dialog message
  ///
  /// In it, this message translates to:
  /// **'\"{setName}\" è completo ({total} / {total2} carte).'**
  String catalogSetCompletedMsg(String setName, int total, int total2);

  /// Move to album prompt
  ///
  /// In it, this message translates to:
  /// **'Vuoi spostare tutte le carte di questo set in un album diverso?'**
  String get catalogMoveToAlbum;

  /// Move in album dropdown label
  ///
  /// In it, this message translates to:
  /// **'Sposta in album'**
  String get catalogMoveInAlbumLabel;

  /// Keep current album hint
  ///
  /// In it, this message translates to:
  /// **'Mantieni album corrente'**
  String get catalogKeepCurrentAlbum;

  /// Cards moved snackbar
  ///
  /// In it, this message translates to:
  /// **'Carte di \"{setName}\" spostate!'**
  String catalogCardsMoved(String setName);

  /// Card list search hint
  ///
  /// In it, this message translates to:
  /// **'Cerca per nome, seriale o rarità...'**
  String get cardListSearchHint;

  /// List view tooltip
  ///
  /// In it, this message translates to:
  /// **'Vista Lista'**
  String get cardListViewTooltipList;

  /// Grid view tooltip
  ///
  /// In it, this message translates to:
  /// **'Vista Griglia'**
  String get cardListViewTooltipGrid;

  /// Album filter banner subtitle
  ///
  /// In it, this message translates to:
  /// **'Stai visualizzando solo le carte di questo album'**
  String get cardListAlbumOnly;

  /// Empty state for album view
  ///
  /// In it, this message translates to:
  /// **'Non hai ancora aggiunto carte a questo album.\nAggiungi carte dal Catalogo selezionando questo album.'**
  String get cardListEmptyAlbum;

  /// Empty state for collection view
  ///
  /// In it, this message translates to:
  /// **'Non hai ancora aggiunto carte.\nUsa il Catalogo per aggiungere carte.'**
  String get cardListEmptyCollection;

  /// Catalog suggestion header
  ///
  /// In it, this message translates to:
  /// **'Non in collezione — trovata nel catalogo'**
  String get cardListNotInCollection;

  /// Card not in catalog title
  ///
  /// In it, this message translates to:
  /// **'Carta non disponibile nel catalogo'**
  String get cardListNotInCatalog;

  /// Card not in catalog message
  ///
  /// In it, this message translates to:
  /// **'Questa carta non è ancora presente nel nostro catalogo. Puoi segnalarcela e la aggiungeremo il prima possibile.'**
  String get cardListNotInCatalogMsg;

  /// Report missing card button
  ///
  /// In it, this message translates to:
  /// **'Segnala carta mancante'**
  String get cardListReportMissing;

  /// Doppione added snackbar
  ///
  /// In it, this message translates to:
  /// **'Doppione aggiunto all\'album \"Doppioni\"'**
  String get cardListDoppioneAdded;

  /// Catalog album label
  ///
  /// In it, this message translates to:
  /// **'Catalogo'**
  String get cardListAlbumCatalog;

  /// Unknown album label
  ///
  /// In it, this message translates to:
  /// **'Sconosciuto'**
  String get cardListAlbumUnknown;

  /// Selection mode header - no selection
  ///
  /// In it, this message translates to:
  /// **'Seleziona carte'**
  String get selectionSelectCards;

  /// N cards selected
  ///
  /// In it, this message translates to:
  /// **'{n} selezionate'**
  String selectionNSelected(int n);

  /// Select all button
  ///
  /// In it, this message translates to:
  /// **'Seleziona tutto'**
  String get selectionSelectAll;

  /// Deselect all button
  ///
  /// In it, this message translates to:
  /// **'Deseleziona tutto'**
  String get selectionDeselectAll;

  /// Album button in selection bar
  ///
  /// In it, this message translates to:
  /// **'Album'**
  String get selectionAlbumBtn;

  /// Deck button in selection bar
  ///
  /// In it, this message translates to:
  /// **'Deck'**
  String get selectionDeckBtn;

  /// Delete button in selection bar
  ///
  /// In it, this message translates to:
  /// **'Elimina'**
  String get selectionDeleteBtn;

  /// Delete N cards dialog title
  ///
  /// In it, this message translates to:
  /// **'Elimina {n} carte'**
  String dlgDeleteNCardsTitle(int n);

  /// Delete N cards dialog message
  ///
  /// In it, this message translates to:
  /// **'Vuoi eliminare le {n} carte selezionate?'**
  String dlgDeleteNCardsMsg(int n);

  /// N cards deleted snackbar
  ///
  /// In it, this message translates to:
  /// **'{n} carte eliminate'**
  String msgNCardsDeleted(int n);

  /// Move to album dialog title
  ///
  /// In it, this message translates to:
  /// **'Sposta in Album'**
  String get dlgMoveToAlbumTitle;

  /// Add to deck dialog title
  ///
  /// In it, this message translates to:
  /// **'Aggiungi a Deck'**
  String get dlgAddToDeckTitle;

  /// N cards added to deck snackbar
  ///
  /// In it, this message translates to:
  /// **'{n} carte aggiunte al deck'**
  String msgNCardsAddedToDeck(int n);

  /// No deck available snackbar
  ///
  /// In it, this message translates to:
  /// **'Nessun deck disponibile. Crea prima un deck.'**
  String get msgNoDeckAvailable;

  /// Capacity exceeded dialog title
  ///
  /// In it, this message translates to:
  /// **'Capacità Superata'**
  String get dlgCapacityExceededTitle;

  /// Capacity exceeded dialog message
  ///
  /// In it, this message translates to:
  /// **'Supererà la capacità massima ({current}/{max}). Procedere?'**
  String dlgCapacityExceededMsg(int current, int max);

  /// Proceed button
  ///
  /// In it, this message translates to:
  /// **'Procedi'**
  String get btnProceed;

  /// Delete card dialog title
  ///
  /// In it, this message translates to:
  /// **'Elimina carta'**
  String get cardDetailDeleteTitle;

  /// Delete card dialog message
  ///
  /// In it, this message translates to:
  /// **'Eliminare \"{name}\" dalla collezione?'**
  String cardDetailDeleteMsg(String name);

  /// Delete tooltip on card detail
  ///
  /// In it, this message translates to:
  /// **'Elimina'**
  String get cardDetailTooltipDelete;

  /// Price history section title
  ///
  /// In it, this message translates to:
  /// **'ANDAMENTO PREZZI'**
  String get cardDetailPriceHistory;

  /// Album section title on card detail
  ///
  /// In it, this message translates to:
  /// **'ALBUM'**
  String get cardDetailAlbumSection;

  /// Market value section title
  ///
  /// In it, this message translates to:
  /// **'VALORE DI MERCATO'**
  String get cardDetailMarketValue;

  /// Deck section title on card detail
  ///
  /// In it, this message translates to:
  /// **'DECK'**
  String get cardDetailDeckSection;

  /// Description section title on card detail
  ///
  /// In it, this message translates to:
  /// **'DESCRIZIONE'**
  String get cardDetailDescription;

  /// View on CardTrader button
  ///
  /// In it, this message translates to:
  /// **'Vedi su CardTrader'**
  String get cardDetailViewOnCardtrader;

  /// No cards in set detail
  ///
  /// In it, this message translates to:
  /// **'Nessuna carta.'**
  String get setDetailNoCards;

  /// Retry button in set detail
  ///
  /// In it, this message translates to:
  /// **'Riprova'**
  String get setDetailRetry;

  /// Set completion page title
  ///
  /// In it, this message translates to:
  /// **'Espansioni — {name}'**
  String setCompletionTitle(String name);

  /// Set completion search hint
  ///
  /// In it, this message translates to:
  /// **'Cerca espansione...'**
  String get setCompletionSearchHint;

  /// New deck dialog title
  ///
  /// In it, this message translates to:
  /// **'Nuovo Deck'**
  String get deckListNewDeckTitle;

  /// New deck name hint
  ///
  /// In it, this message translates to:
  /// **'Es. MazzoAttacco'**
  String get deckListNewDeckHint;

  /// No decks created empty state
  ///
  /// In it, this message translates to:
  /// **'Nessun deck creato.'**
  String get deckListNoDecks;

  /// Delete deck dialog title
  ///
  /// In it, this message translates to:
  /// **'Elimina Deck'**
  String get dlgDeleteDeckTitle;

  /// Delete deck dialog message
  ///
  /// In it, this message translates to:
  /// **'Sei sicuro di voler eliminare \"{name}\"?'**
  String dlgDeleteDeckMsg(String name);

  /// Deck deleted snackbar
  ///
  /// In it, this message translates to:
  /// **'Deck \"{name}\" eliminato'**
  String msgDeckDeleted(String name);

  /// No albums created empty state
  ///
  /// In it, this message translates to:
  /// **'Nessun album creato.'**
  String get albumListNoAlbums;

  /// Delete album dialog title
  ///
  /// In it, this message translates to:
  /// **'Elimina Album'**
  String get dlgDeleteAlbumTitle;

  /// Album deleted snackbar
  ///
  /// In it, this message translates to:
  /// **'Album \"{name}\" eliminato'**
  String msgAlbumDeleted(String name);

  /// New album name hint
  ///
  /// In it, this message translates to:
  /// **'Es. CollezioneBase'**
  String get albumNewAlbumHint;

  /// Album capacity hint
  ///
  /// In it, this message translates to:
  /// **'100'**
  String get albumCapacityHint;

  /// No albums in album/deck page
  ///
  /// In it, this message translates to:
  /// **'Nessun album creato.'**
  String get albumDeckPageNoAlbums;

  /// No decks in album/deck page
  ///
  /// In it, this message translates to:
  /// **'Nessun deck creato.'**
  String get albumDeckPageNoDecks;

  /// AI Deck Builder button label
  ///
  /// In it, this message translates to:
  /// **'AI Deck Builder'**
  String get albumDeckPageAiDeckBuilder;

  /// New deck button label
  ///
  /// In it, this message translates to:
  /// **'Nuovo Deck'**
  String get albumDeckPageNewDeck;

  /// New album button label
  ///
  /// In it, this message translates to:
  /// **'Nuovo Album'**
  String get albumDeckPageNewAlbum;

  /// Share deck pro dialog title
  ///
  /// In it, this message translates to:
  /// **'Condivisione Pro'**
  String get deckDetailSharePro;

  /// Share deck pro message
  ///
  /// In it, this message translates to:
  /// **'La condivisione del deck è disponibile solo per gli utenti Pro.'**
  String get deckDetailShareProMsg;

  /// Share deck tooltip
  ///
  /// In it, this message translates to:
  /// **'Condividi Deck'**
  String get deckDetailShareTooltip;

  /// Share deck pro tooltip
  ///
  /// In it, this message translates to:
  /// **'Condividi Deck (Pro)'**
  String get deckDetailShareTooltipPro;

  /// Add cards before sharing snackbar
  ///
  /// In it, this message translates to:
  /// **'Aggiungi carte al deck prima di condividerlo'**
  String get deckDetailAddBeforeShare;

  /// Deck shared dialog title
  ///
  /// In it, this message translates to:
  /// **'Deck Condiviso!'**
  String get deckDetailSharedTitle;

  /// Code copied snackbar
  ///
  /// In it, this message translates to:
  /// **'Codice copiato!'**
  String get deckDetailCodeCopied;

  /// In deck label
  ///
  /// In it, this message translates to:
  /// **'Nel Deck'**
  String get deckDetailInDeck;

  /// In deck hint
  ///
  /// In it, this message translates to:
  /// **'Dettaglio • − per rimuovere'**
  String get deckDetailInDeckHint;

  /// Owned cards label
  ///
  /// In it, this message translates to:
  /// **'Possedute'**
  String get deckDetailOwned;

  /// Owned cards hint
  ///
  /// In it, this message translates to:
  /// **'Tocca per aggiungere'**
  String get deckDetailOwnedHint;

  /// Deck detail search hint
  ///
  /// In it, this message translates to:
  /// **'Cerca carta...'**
  String get deckDetailSearchHint;

  /// Wishlist page title
  ///
  /// In it, this message translates to:
  /// **'Wishlist'**
  String get wishlistTitle;

  /// Add card to wishlist button
  ///
  /// In it, this message translates to:
  /// **'Aggiungi carta'**
  String get wishlistAddCard;

  /// Add to wishlist dialog title
  ///
  /// In it, this message translates to:
  /// **'Aggiungi alla Wishlist'**
  String get wishlistAddToWishlistTitle;

  /// Item removed from wishlist snackbar
  ///
  /// In it, this message translates to:
  /// **'{name} rimossa dalla Wishlist'**
  String wishlistItemRemovedMsg(String name);

  /// Undo remove from wishlist
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get wishlistUndoRemove;

  /// Target price dialog title
  ///
  /// In it, this message translates to:
  /// **'Prezzo obiettivo'**
  String get dlgTargetPriceTitle;

  /// Target price dialog message
  ///
  /// In it, this message translates to:
  /// **'Imposta il prezzo obiettivo per {name}'**
  String dlgTargetPriceMsg(String name);

  /// Target price input label
  ///
  /// In it, this message translates to:
  /// **'Prezzo (€)'**
  String get dlgTargetPriceLabel;

  /// Remove from wishlist dialog title
  ///
  /// In it, this message translates to:
  /// **'Rimuovi dalla Wishlist'**
  String get dlgRemoveWishlistTitle;

  /// Remove from wishlist dialog message
  ///
  /// In it, this message translates to:
  /// **'Rimuovere \"{name}\" dalla wishlist?'**
  String dlgRemoveWishlistMsg(String name);

  /// Remove button
  ///
  /// In it, this message translates to:
  /// **'Rimuovi'**
  String get btnRemove;

  /// N/A label in wishlist
  ///
  /// In it, this message translates to:
  /// **'N/D'**
  String get wishlistNdLabel;

  /// Wishlist catalog picker title
  ///
  /// In it, this message translates to:
  /// **'Cerca nel catalogo'**
  String get wishlistCatalogSearchTitle;

  /// Wishlist catalog search hint
  ///
  /// In it, this message translates to:
  /// **'Cerca per nome o codice set...'**
  String get wishlistCatalogSearchHint;

  /// Item added to wishlist snackbar
  ///
  /// In it, this message translates to:
  /// **'{name} aggiunta alla Wishlist'**
  String wishlistItemAddedMsg(String name);

  /// Add to wishlist tooltip
  ///
  /// In it, this message translates to:
  /// **'Aggiungi alla Wishlist'**
  String get wishlistAddToWishlistTooltip;

  /// No results in wishlist catalog search
  ///
  /// In it, this message translates to:
  /// **'Nessun risultato trovato'**
  String get wishlistNoResults;

  /// Stats page title
  ///
  /// In it, this message translates to:
  /// **'Statistiche'**
  String get statsTitle;

  /// Stats by collection section
  ///
  /// In it, this message translates to:
  /// **'Per Collezione'**
  String get statsPerCollection;

  /// Cards count in stats
  ///
  /// In it, this message translates to:
  /// **'{n} carte'**
  String statsCardsCount(int n);

  /// Stats by rarity section
  ///
  /// In it, this message translates to:
  /// **'Per Rarità (top 10)'**
  String get statsPerRarity;

  /// Sets section in stats
  ///
  /// In it, this message translates to:
  /// **'Espansioni'**
  String get statsSetsSection;

  /// Collection tab in stats
  ///
  /// In it, this message translates to:
  /// **'Collezione'**
  String get statsTabCollection;

  /// Global tab in stats
  ///
  /// In it, this message translates to:
  /// **'Globale'**
  String get statsTabGlobal;

  /// ROI page title
  ///
  /// In it, this message translates to:
  /// **'Analisi ROI'**
  String get roiTitle;

  /// Portfolio section in ROI
  ///
  /// In it, this message translates to:
  /// **'Portafoglio'**
  String get roiPortfolio;

  /// Total value label in ROI
  ///
  /// In it, this message translates to:
  /// **'Valore totale'**
  String get roiTotalValue;

  /// ROI section title
  ///
  /// In it, this message translates to:
  /// **'ROI'**
  String get roiSection;

  /// Invested label in ROI
  ///
  /// In it, this message translates to:
  /// **'Investito'**
  String get roiInvested;

  /// CT value label in ROI
  ///
  /// In it, this message translates to:
  /// **'Valore CT'**
  String get roiValueCt;

  /// Gain label in ROI
  ///
  /// In it, this message translates to:
  /// **'Guadagno'**
  String get roiGain;

  /// ROI % label
  ///
  /// In it, this message translates to:
  /// **'ROI %'**
  String get roiPercent;

  /// Tracked cards section
  ///
  /// In it, this message translates to:
  /// **'Carte tracciate'**
  String get roiTrackedCards;

  /// Portfolio value dialog title
  ///
  /// In it, this message translates to:
  /// **'Valore Portfolio'**
  String get roiPortfolioTitle;

  /// Purchase price dialog title
  ///
  /// In it, this message translates to:
  /// **'Prezzo d\'acquisto'**
  String get roiPurchasePriceTitle;

  /// Purchase price label
  ///
  /// In it, this message translates to:
  /// **'Prezzo pagato per copia (€)'**
  String get roiPurchasePriceLabel;

  /// Add prices button in ROI
  ///
  /// In it, this message translates to:
  /// **'Aggiungi prezzi {label}'**
  String roiAddPricesBtn(String label);

  /// Notifications page title
  ///
  /// In it, this message translates to:
  /// **'Notifiche'**
  String get notificationsTitle;

  /// Clear all notifications dialog title
  ///
  /// In it, this message translates to:
  /// **'Cancella tutto'**
  String get notifClearAllTitle;

  /// Clear all notifications dialog message
  ///
  /// In it, this message translates to:
  /// **'Vuoi eliminare tutte le notifiche?'**
  String get notifClearAllMsg;

  /// Clear all tooltip
  ///
  /// In it, this message translates to:
  /// **'Cancella tutto'**
  String get notifClearAllTooltip;

  /// Download button in notifications
  ///
  /// In it, this message translates to:
  /// **'Scarica'**
  String get notifDownloadBtn;

  /// News page title
  ///
  /// In it, this message translates to:
  /// **'News'**
  String get newsTitle;

  /// Network error title in news
  ///
  /// In it, this message translates to:
  /// **'Errore di rete'**
  String get newsNetworkError;

  /// Network error subtitle in news
  ///
  /// In it, this message translates to:
  /// **'Controlla la connessione e riprova.'**
  String get newsNetworkErrorSubtitle;

  /// No news title
  ///
  /// In it, this message translates to:
  /// **'Nessuna news'**
  String get newsNoNews;

  /// No news subtitle
  ///
  /// In it, this message translates to:
  /// **'Non ci sono aggiornamenti per le tue collezioni.'**
  String get newsNoNewsSubtitle;

  /// Refresh tooltip in news
  ///
  /// In it, this message translates to:
  /// **'Aggiorna'**
  String get newsRefreshTooltip;

  /// Featured badge in news
  ///
  /// In it, this message translates to:
  /// **'IN EVIDENZA'**
  String get newsHighlight;

  /// Read more link in news
  ///
  /// In it, this message translates to:
  /// **'Leggi di più'**
  String get newsReadMore;

  /// Card scanner page title
  ///
  /// In it, this message translates to:
  /// **'Scansiona Carta'**
  String get cardScannerTitle;

  /// Scanner limit dialog title
  ///
  /// In it, this message translates to:
  /// **'Limite scansioni raggiunto'**
  String get cardScannerLimitTitle;

  /// No album found for collection
  ///
  /// In it, this message translates to:
  /// **'Nessun album trovato per {collection}'**
  String cardScannerNoAlbum(String collection);

  /// Card added to collection snackbar
  ///
  /// In it, this message translates to:
  /// **'{name} aggiunta alla collezione!'**
  String cardScannerCardAdded(String name);

  /// Add to collection button in scanner
  ///
  /// In it, this message translates to:
  /// **'Aggiungi a Collezione'**
  String get cardScannerAddToCollection;

  /// Scan another card button
  ///
  /// In it, this message translates to:
  /// **'Scansiona un\'altra carta'**
  String get cardScannerScanAnother;

  /// Open camera button
  ///
  /// In it, this message translates to:
  /// **'Apri Fotocamera'**
  String get cardScannerOpenCamera;

  /// Go to Pro button in scanner limit
  ///
  /// In it, this message translates to:
  /// **'Passa a Pro'**
  String get cardScannerGoToPro;

  /// AI Deck Builder page title
  ///
  /// In it, this message translates to:
  /// **'AI Deck Builder'**
  String get aiDeckBuilderTitle;

  /// AI prompt label
  ///
  /// In it, this message translates to:
  /// **'Descrivi la tua strategia'**
  String get aiDeckBuilderPromptLabel;

  /// AI prompt hint text
  ///
  /// In it, this message translates to:
  /// **'Es: \"Un deck aggressivo Dragon con attacchi rapidi e fusioni potenti. Voglio usare i miei Blue-Eyes e un misto di carte di supporto.\"'**
  String get aiDeckBuilderPromptHint;

  /// Generate deck with AI button
  ///
  /// In it, this message translates to:
  /// **'Genera Deck con AI'**
  String get aiDeckBuilderGenerateBtn;

  /// AI generating in progress label
  ///
  /// In it, this message translates to:
  /// **'Analisi in corso…'**
  String get aiDeckBuilderGenerating;

  /// Save deck button in AI builder
  ///
  /// In it, this message translates to:
  /// **'Salva Deck'**
  String get aiDeckBuilderSaveBtn;

  /// Deck saved snackbar
  ///
  /// In it, this message translates to:
  /// **'Deck \"{name}\" salvato! ({n} carte aggiunte)'**
  String aiDeckBuilderDeckSaved(String name, int n);

  /// Save error snackbar
  ///
  /// In it, this message translates to:
  /// **'Errore nel salvare: {error}'**
  String aiDeckBuilderSaveError(String error);

  /// Main deck label
  ///
  /// In it, this message translates to:
  /// **'Main'**
  String get aiDeckBuilderMainLabel;

  /// Extra deck label
  ///
  /// In it, this message translates to:
  /// **'Extra'**
  String get aiDeckBuilderExtraLabel;

  /// Owned cards label in AI builder
  ///
  /// In it, this message translates to:
  /// **'Possedute'**
  String get aiDeckBuilderOwnedLabel;

  /// Go to Pro button in AI builder
  ///
  /// In it, this message translates to:
  /// **'Passa a Pro'**
  String get aiDeckBuilderGoToPro;

  /// Card not owned label in AI builder
  ///
  /// In it, this message translates to:
  /// **'non posseduta'**
  String get aiDeckBuilderNotOwned;

  /// Pro page reference
  ///
  /// In it, this message translates to:
  /// **'Pro'**
  String get proTitle;

  /// Pro subscription not available snackbar
  ///
  /// In it, this message translates to:
  /// **'Abbonamento non disponibile al momento.'**
  String get proNotAvailable;

  /// Pro welcome snackbar
  ///
  /// In it, this message translates to:
  /// **'Benvenuto nel piano Pro!'**
  String get proWelcomeMsg;

  /// Purchases restored snackbar
  ///
  /// In it, this message translates to:
  /// **'Acquisti ripristinati!'**
  String get proPurchasesRestored;

  /// No purchases to restore snackbar
  ///
  /// In it, this message translates to:
  /// **'Nessun acquisto da ripristinare.'**
  String get proNoPurchasesToRestore;

  /// Monthly plan label
  ///
  /// In it, this message translates to:
  /// **'Mensile'**
  String get proMonthlyLabel;

  /// Yearly plan label
  ///
  /// In it, this message translates to:
  /// **'Annuale'**
  String get proYearlyLabel;

  /// Yearly plan title
  ///
  /// In it, this message translates to:
  /// **'Piano Annuale'**
  String get proYearlyTitle;

  /// Monthly plan title
  ///
  /// In it, this message translates to:
  /// **'Piano Mensile'**
  String get proMonthlyTitle;

  /// Donations page title
  ///
  /// In it, this message translates to:
  /// **'Supporta il Progetto'**
  String get donationsTitle;

  /// Cannot open link snackbar
  ///
  /// In it, this message translates to:
  /// **'Impossibile aprire il link'**
  String get msgCantOpenLink;

  /// Support page title
  ///
  /// In it, this message translates to:
  /// **'Supporto'**
  String get supportTitle;

  /// Report bug section title
  ///
  /// In it, this message translates to:
  /// **'Segnala un Problema'**
  String get supportReportBugTitle;

  /// Report bug section subtitle
  ///
  /// In it, this message translates to:
  /// **'Hai riscontrato un bug o un comportamento inatteso?'**
  String get supportReportBugSubtitle;

  /// Missing cards section title
  ///
  /// In it, this message translates to:
  /// **'Carte Mancanti'**
  String get supportMissingCardsTitle;

  /// Missing cards section subtitle
  ///
  /// In it, this message translates to:
  /// **'Segnala carte assenti o con dati errati nel catalogo.'**
  String get supportMissingCardsSubtitle;

  /// Suggestion section title
  ///
  /// In it, this message translates to:
  /// **'Suggerimento'**
  String get supportSuggestionTitle;

  /// Suggestion section subtitle
  ///
  /// In it, this message translates to:
  /// **'Hai un\'idea per migliorare l\'app? Scrivici!'**
  String get supportSuggestionSubtitle;

  /// Support project button
  ///
  /// In it, this message translates to:
  /// **'Supporta il progetto'**
  String get supportSupportProject;

  /// No email client snackbar
  ///
  /// In it, this message translates to:
  /// **'Nessun client email trovato'**
  String get msgNoEmailClient;

  /// Tutorial page title
  ///
  /// In it, this message translates to:
  /// **'Guida all\'App'**
  String get tutorialPageTitle;

  /// Start tutorial button
  ///
  /// In it, this message translates to:
  /// **'Inizia il Tutorial'**
  String get tutorialStartBtn;

  /// Maybe later button on tutorial page
  ///
  /// In it, this message translates to:
  /// **'Forse dopo'**
  String get tutorialMaybeLater;

  /// Shared deck view page title
  ///
  /// In it, this message translates to:
  /// **'Deck Condiviso'**
  String get sharedDeckTitle;

  /// No cards owned from shared deck
  ///
  /// In it, this message translates to:
  /// **'Non possiedi nessuna carta di questo deck'**
  String get sharedDeckNoCards;

  /// Deck imported snackbar
  ///
  /// In it, this message translates to:
  /// **'Deck importato! ({n} carte aggiunte)'**
  String sharedDeckImported(int n);

  /// Shared deck code hint
  ///
  /// In it, this message translates to:
  /// **'XXXXXX'**
  String get sharedDeckCodeHint;

  /// Code copied snackbar in shared deck
  ///
  /// In it, this message translates to:
  /// **'Codice copiato!'**
  String get sharedDeckCodeCopied;

  /// Shared deck info line
  ///
  /// In it, this message translates to:
  /// **'di {owner} · {collection} · {total} carte'**
  String sharedDeckByOwner(String owner, String collection, int total);

  /// Admin catalog page title
  ///
  /// In it, this message translates to:
  /// **'Gestione Catalogo'**
  String get adminHomeCatalogTitle;

  /// Publish changes tooltip
  ///
  /// In it, this message translates to:
  /// **'Pubblica modifiche'**
  String get adminHomePublishTooltip;

  /// Reload tooltip
  ///
  /// In it, this message translates to:
  /// **'Ricarica'**
  String get adminHomeReloadTooltip;

  /// New card button in admin
  ///
  /// In it, this message translates to:
  /// **'Nuova Carta'**
  String get adminHomeNewCard;

  /// Search hint in admin catalog
  ///
  /// In it, this message translates to:
  /// **'Cerca carta (nome, archetipo, ID)...'**
  String get adminHomeSearchHint;

  /// View button in admin catalog
  ///
  /// In it, this message translates to:
  /// **'Visualizza'**
  String get adminHomeViewBtn;

  /// Search prompt in admin catalog
  ///
  /// In it, this message translates to:
  /// **'Cerca una carta o aggiungi una nuova'**
  String get adminHomeSearchPrompt;

  /// Card added to changes snackbar
  ///
  /// In it, this message translates to:
  /// **'Carta aggiunta alle modifiche'**
  String get adminCardAdded;

  /// Edit added to changes snackbar
  ///
  /// In it, this message translates to:
  /// **'Modifica aggiunta'**
  String get adminEditAdded;

  /// Confirm deletion dialog title in admin
  ///
  /// In it, this message translates to:
  /// **'Conferma eliminazione'**
  String get adminDeleteConfirmTitle;

  /// Confirm deletion dialog message in admin
  ///
  /// In it, this message translates to:
  /// **'Vuoi eliminare \"{name}\"?\nLa carta sarà rimossa al prossimo aggiornamento.'**
  String adminDeleteConfirmMsg(String name);

  /// Deletion added to changes snackbar
  ///
  /// In it, this message translates to:
  /// **'Eliminazione aggiunta alle modifiche'**
  String get adminDeleteAdded;

  /// Pending changes dialog title
  ///
  /// In it, this message translates to:
  /// **'Modifiche in sospeso'**
  String get adminPendingChangesTitle;

  /// Publish changes dialog title
  ///
  /// In it, this message translates to:
  /// **'Pubblica modifiche'**
  String get adminPublishTitle;

  /// Published successfully snackbar
  ///
  /// In it, this message translates to:
  /// **'Pubblicato con successo'**
  String get adminPublishedSuccess;

  /// Admin collection publish dialog title
  ///
  /// In it, this message translates to:
  /// **'Pubblica Modifiche'**
  String get adminCollectionTitle;

  /// Publish N changes message
  ///
  /// In it, this message translates to:
  /// **'Pubblicare {n} modifiche su Firestore?'**
  String adminCollectionPublishMsg(int n);

  /// Changes published successfully snackbar
  ///
  /// In it, this message translates to:
  /// **'Modifiche pubblicate con successo!'**
  String get adminCollectionPublishSuccess;

  /// Search hint in admin collection
  ///
  /// In it, this message translates to:
  /// **'Cerca per nome, ID o archetipo...'**
  String get adminCollectionSearchHint;

  /// No cards found in admin collection
  ///
  /// In it, this message translates to:
  /// **'Nessuna carta trovata'**
  String get adminCollectionNoCards;

  /// Publish changes tooltip in admin collection
  ///
  /// In it, this message translates to:
  /// **'Pubblica modifiche'**
  String get adminCollectionPublishTooltip;

  /// Reload from Firestore tooltip
  ///
  /// In it, this message translates to:
  /// **'Ricarica da Firestore'**
  String get adminCollectionReloadTooltip;

  /// Delete card from catalog dialog message
  ///
  /// In it, this message translates to:
  /// **'Eliminare \"{name}\" dal catalogo?'**
  String adminCollectionDeleteMsg(String name);

  /// Card edit pending snackbar
  ///
  /// In it, this message translates to:
  /// **'Modifica in attesa di pubblicazione'**
  String get adminCollectionCardEditedPending;

  /// Card added pending snackbar
  ///
  /// In it, this message translates to:
  /// **'Carta aggiunta — in attesa di pubblicazione'**
  String get adminCollectionCardAddedPending;

  /// Admin Excel page title
  ///
  /// In it, this message translates to:
  /// **'Export / Import Excel'**
  String get adminExcelTitle;

  /// Import confirmation dialog title
  ///
  /// In it, this message translates to:
  /// **'Conferma importazione'**
  String get adminExcelImportConfirmTitle;

  /// Export to Excel section title
  ///
  /// In it, this message translates to:
  /// **'Esporta in Excel'**
  String get adminExcelExportTitle;

  /// Export to Excel subtitle
  ///
  /// In it, this message translates to:
  /// **'Genera un file .xlsx con due fogli:\n'**
  String get adminExcelExportSubtitle;

  /// Export and share button
  ///
  /// In it, this message translates to:
  /// **'Esporta e Condividi'**
  String get adminExcelExportBtn;

  /// Import from Excel section title
  ///
  /// In it, this message translates to:
  /// **'Importa da Excel'**
  String get adminExcelImportTitle;

  /// Import from Excel subtitle
  ///
  /// In it, this message translates to:
  /// **'Seleziona un file .xlsx esportato da questa app con le '**
  String get adminExcelImportSubtitle;

  /// Select xlsx file button
  ///
  /// In it, this message translates to:
  /// **'Seleziona file .xlsx'**
  String get adminExcelSelectFileBtn;

  /// Apply N changes button
  ///
  /// In it, this message translates to:
  /// **'Applica {n} modifiche su Firestore'**
  String adminExcelApplyBtn(int n);

  /// Admin sets & rarities page title
  ///
  /// In it, this message translates to:
  /// **'Espansioni & Rarità'**
  String get adminSetsTitle;

  /// Sync to Firestore tooltip
  ///
  /// In it, this message translates to:
  /// **'Sincronizza su Firestore'**
  String get adminSetsSyncTooltip;

  /// Translations synced snackbar
  ///
  /// In it, this message translates to:
  /// **'Traduzioni sincronizzate su Firestore'**
  String get adminSetsSynced;

  /// Edit translations tooltip
  ///
  /// In it, this message translates to:
  /// **'Modifica traduzioni'**
  String get adminSetsEditTooltip;

  /// Admin users page title
  ///
  /// In it, this message translates to:
  /// **'Gestione Utenti'**
  String get adminUsersTitle;

  /// Reload tooltip in admin users
  ///
  /// In it, this message translates to:
  /// **'Ricarica'**
  String get adminUsersReloadTooltip;

  /// No users found label
  ///
  /// In it, this message translates to:
  /// **'Nessun utente trovato'**
  String get adminUsersNoUsers;

  /// Filter all label
  ///
  /// In it, this message translates to:
  /// **'Tutti'**
  String get adminUsersFilterAll;

  /// Filter admin label
  ///
  /// In it, this message translates to:
  /// **'Admin'**
  String get adminUsersFilterAdmin;

  /// Filter users label
  ///
  /// In it, this message translates to:
  /// **'Utenti'**
  String get adminUsersFilterUsers;

  /// Role updated snackbar
  ///
  /// In it, this message translates to:
  /// **'Ruolo aggiornato con successo'**
  String get adminUsersRoleUpdated;

  /// Status updated snackbar
  ///
  /// In it, this message translates to:
  /// **'Stato aggiornato: {status}'**
  String adminUsersStatusUpdated(String status);

  /// User deleted successfully snackbar
  ///
  /// In it, this message translates to:
  /// **'Utente eliminato con successo'**
  String get adminUsersDeletedSuccess;

  /// Confirm role change dialog title
  ///
  /// In it, this message translates to:
  /// **'Conferma cambio ruolo'**
  String get adminUsersConfirmRoleTitle;

  /// Confirm delete user dialog title
  ///
  /// In it, this message translates to:
  /// **'Conferma eliminazione'**
  String get adminUsersConfirmDeleteTitle;

  /// Forced update title
  ///
  /// In it, this message translates to:
  /// **'Aggiornamento richiesto'**
  String get updateDialogRequired;

  /// Update available title
  ///
  /// In it, this message translates to:
  /// **'Nuova versione disponibile'**
  String get updateDialogAvailable;

  /// Forced update message
  ///
  /// In it, this message translates to:
  /// **'Questa versione non è più supportata. Aggiorna per continuare a usare l\'app.'**
  String get updateDialogForcedMsg;

  /// Optional update message
  ///
  /// In it, this message translates to:
  /// **'È disponibile una nuova versione con miglioramenti e correzioni.'**
  String get updateDialogOptionalMsg;

  /// What's new section title in update dialog
  ///
  /// In it, this message translates to:
  /// **'Novità'**
  String get updateDialogWhatsNew;

  /// Update now button
  ///
  /// In it, this message translates to:
  /// **'Aggiorna ora'**
  String get updateDialogUpdateNow;

  /// Not now button
  ///
  /// In it, this message translates to:
  /// **'Non ora'**
  String get updateDialogNotNow;

  /// Select album dropdown label in card dialog
  ///
  /// In it, this message translates to:
  /// **'Seleziona Album'**
  String get cardDialogSelectAlbumLabel;

  /// Deck label in card dialog
  ///
  /// In it, this message translates to:
  /// **'Deck'**
  String get cardDialogDeck;

  /// Description label in card dialog
  ///
  /// In it, this message translates to:
  /// **'Descrizione'**
  String get cardDialogDescription;

  /// Delete button in card dialog
  ///
  /// In it, this message translates to:
  /// **'Elimina'**
  String get cardDialogDeleteBtn;

  /// Close button in card dialog
  ///
  /// In it, this message translates to:
  /// **'Chiudi'**
  String get cardDialogCloseBtn;

  /// Save button in card dialog
  ///
  /// In it, this message translates to:
  /// **'Salva'**
  String get cardDialogSaveBtn;

  /// Add to collection dialog title
  ///
  /// In it, this message translates to:
  /// **'Aggiungi a {collection}'**
  String cardDialogAddToTitle(String collection);

  /// No album dialog title
  ///
  /// In it, this message translates to:
  /// **'Nessun Album'**
  String get cardDialogNoAlbumTitle;

  /// No album dialog message
  ///
  /// In it, this message translates to:
  /// **'Non hai ancora creato un album per questa collezione. Crea un album dalla sezione Raccolta.'**
  String get cardDialogNoAlbumMsg;

  /// Manage album button in card dialog
  ///
  /// In it, this message translates to:
  /// **'Gestisci Album'**
  String get cardDialogManageAlbum;

  /// Select from catalog snackbar
  ///
  /// In it, this message translates to:
  /// **'Seleziona una carta dal catalogo'**
  String get cardDialogSelectFromCatalog;

  /// Select an album snackbar
  ///
  /// In it, this message translates to:
  /// **'Seleziona un album'**
  String get cardDialogSelectAlbum;

  /// Card name empty snackbar
  ///
  /// In it, this message translates to:
  /// **'Il nome della carta non può essere vuoto.'**
  String get cardDialogNameEmpty;

  /// Quantity min snackbar
  ///
  /// In it, this message translates to:
  /// **'La quantità deve essere almeno 1.'**
  String get cardDialogQtyMin;

  /// Album full dialog title in card dialog
  ///
  /// In it, this message translates to:
  /// **'Album pieno'**
  String get cardDialogAlbumFullTitle;

  /// Card added to doppioni snackbar
  ///
  /// In it, this message translates to:
  /// **'Carta già presente nella collezione → aggiunta ai Doppioni'**
  String get cardDialogDoppionAdded;

  /// N/A value label in card item
  ///
  /// In it, this message translates to:
  /// **'N/D'**
  String get cardItemNdLabel;

  /// Undo button in top undo bar
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get undoBarUndo;

  /// Save card button in admin edit dialog
  ///
  /// In it, this message translates to:
  /// **'Salva Carta'**
  String get adminCardEditSaveBtn;

  /// Image URL hint in admin card edit
  ///
  /// In it, this message translates to:
  /// **'Carica dal dispositivo →'**
  String get adminCardEditImageHint;

  /// Upload from device tooltip
  ///
  /// In it, this message translates to:
  /// **'Carica dal dispositivo'**
  String get adminCardEditImageTooltip;

  /// Upload failed snackbar
  ///
  /// In it, this message translates to:
  /// **'Upload non riuscito o timeout'**
  String get adminCardEditUploadFailed;

  /// Stats not applicable message
  ///
  /// In it, this message translates to:
  /// **'Statistiche non applicabili per questa collezione.'**
  String get adminCardEditStatsNA;

  /// Spell/trap no stats message
  ///
  /// In it, this message translates to:
  /// **'Le Spell e Trap non hanno statistiche mostro'**
  String get adminCardEditSpellTrapNA;

  /// No attacks label
  ///
  /// In it, this message translates to:
  /// **'Nessun attacco.'**
  String get adminCardEditNoAttacks;

  /// No abilities label
  ///
  /// In it, this message translates to:
  /// **'Nessuna abilità.'**
  String get adminCardEditNoAbilities;

  /// No sets for this language
  ///
  /// In it, this message translates to:
  /// **'Nessun set per questa lingua.'**
  String get adminCardEditSetsNoData;

  /// Add set tooltip
  ///
  /// In it, this message translates to:
  /// **'Aggiungi set'**
  String get adminCardEditAddSetTooltip;

  /// New attack dialog title
  ///
  /// In it, this message translates to:
  /// **'Nuovo Attacco'**
  String get adminCardEditNewAttackTitle;

  /// Edit attack dialog title
  ///
  /// In it, this message translates to:
  /// **'Modifica Attacco'**
  String get adminCardEditEditAttackTitle;

  /// New ability dialog title
  ///
  /// In it, this message translates to:
  /// **'Nuova Abilità'**
  String get adminCardEditNewAbilityTitle;

  /// Edit ability dialog title
  ///
  /// In it, this message translates to:
  /// **'Modifica Abilità'**
  String get adminCardEditEditAbilityTitle;

  /// Generate from EN button
  ///
  /// In it, this message translates to:
  /// **'Genera da EN'**
  String get adminCardEditGenerateFromEn;

  /// Session expired message
  ///
  /// In it, this message translates to:
  /// **'Sessione scaduta. Fai il logout e accedi di nuovo.'**
  String get adminHomeSessions;

  /// Operation cancelled snackbar
  ///
  /// In it, this message translates to:
  /// **'Operazione annullata.'**
  String get adminHomeOperationCancelled;

  /// Manage Pro users button
  ///
  /// In it, this message translates to:
  /// **'Gestisci Utenti Pro'**
  String get adminHomeManageProUsers;

  /// Catalog column header in CT data
  ///
  /// In it, this message translates to:
  /// **'Catalogo'**
  String get adminHomeCtData;

  /// CT blueprint column header
  ///
  /// In it, this message translates to:
  /// **'CT blueprint'**
  String get adminHomeCtBlueprint;

  /// With price column header
  ///
  /// In it, this message translates to:
  /// **'Con prezzo'**
  String get adminHomeCtWithPrice;

  /// Difference column header
  ///
  /// In it, this message translates to:
  /// **'Diff.'**
  String get adminHomeCtDiff;

  /// No CT data in local cache
  ///
  /// In it, this message translates to:
  /// **'Nessun dato CT in cache locale.'**
  String get adminHomeCtNoData;

  /// Filter label in admin users
  ///
  /// In it, this message translates to:
  /// **'Filtro: '**
  String get adminHomeFilterLabel;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
