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

  /// No description provided for @loginNoInternetTitle.
  ///
  /// In it, this message translates to:
  /// **'Nessuna connessione'**
  String get loginNoInternetTitle;

  /// No description provided for @loginNoInternetBody.
  ///
  /// In it, this message translates to:
  /// **'Impossibile raggiungere internet.\nPuoi continuare in modalità offline o riprovare.'**
  String get loginNoInternetBody;

  /// No description provided for @loginBtnRetry.
  ///
  /// In it, this message translates to:
  /// **'Riprova'**
  String get loginBtnRetry;

  /// No description provided for @loginBtnOfflineAccess.
  ///
  /// In it, this message translates to:
  /// **'Modalità offline'**
  String get loginBtnOfflineAccess;

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

  /// Card scanner navigation label
  ///
  /// In it, this message translates to:
  /// **'Scansiona'**
  String get navScan;

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

  /// Wishlist menu item
  ///
  /// In it, this message translates to:
  /// **' Preferiti'**
  String get menuWishlist;

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

  /// Shown when the selected language has no localized catalog cards yet and the app falls back to English
  ///
  /// In it, this message translates to:
  /// **'Nessuna carta tradotta in questa lingua per ora — mostro le carte in inglese.'**
  String get catalogLanguageFallbackToEn;

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

  /// Set detail tab — all cards
  ///
  /// In it, this message translates to:
  /// **'Tutte'**
  String get setDetailTabAll;

  /// Set detail tab — owned cards
  ///
  /// In it, this message translates to:
  /// **'Possedute'**
  String get setDetailTabOwned;

  /// Set detail tab — missing cards
  ///
  /// In it, this message translates to:
  /// **'Mancanti'**
  String get setDetailTabMissing;

  /// Set detail load error label
  ///
  /// In it, this message translates to:
  /// **'Errore nel caricamento'**
  String get setDetailLoadError;

  /// Plural noun for cards (used in capacity labels)
  ///
  /// In it, this message translates to:
  /// **'carte'**
  String get nounCards;

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

  /// Wishlist empty state title
  ///
  /// In it, this message translates to:
  /// **'Non hai ancora aggiunto carte ai preferiti'**
  String get wishlistEmptyTitle;

  /// Wishlist empty state message
  ///
  /// In it, this message translates to:
  /// **'Vai al catalogo e tocca il cuore\nsulle carte che vuoi acquistare.'**
  String get wishlistEmptyMsg;

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

  /// Notifications page header title
  ///
  /// In it, this message translates to:
  /// **'Le tue novità'**
  String get notifHeaderTitle;

  /// Notifications page header subtitle
  ///
  /// In it, this message translates to:
  /// **'Aggiornamenti dell\'app e delle collezioni, tutti in un posto.'**
  String get notifHeaderSubtitle;

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

  /// Expand full news body
  ///
  /// In it, this message translates to:
  /// **'Leggi tutto'**
  String get newsReadAll;

  /// Collapse news body
  ///
  /// In it, this message translates to:
  /// **'Mostra meno'**
  String get newsShowLess;

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

  /// Unique cards label in collection summary
  ///
  /// In it, this message translates to:
  /// **'Uniche'**
  String get collectionSummaryUnique;

  /// Duplicates label in collection summary
  ///
  /// In it, this message translates to:
  /// **'Doppioni'**
  String get collectionSummaryDuplicates;

  /// Total cards label in collection summary
  ///
  /// In it, this message translates to:
  /// **'Totali'**
  String get collectionSummaryTotal;

  /// Value label in collection summary
  ///
  /// In it, this message translates to:
  /// **'Valore'**
  String get collectionSummaryValue;

  /// Total cards stat card label
  ///
  /// In it, this message translates to:
  /// **'Carte Totali'**
  String get statsTotalCards;

  /// Duplicate cards stat card label
  ///
  /// In it, this message translates to:
  /// **'Doppioni'**
  String get statsDuplicateCards;

  /// Estimated value stat card label
  ///
  /// In it, this message translates to:
  /// **'Valore Stimato'**
  String get statsEstimatedValue;

  /// Value trend chart title
  ///
  /// In it, this message translates to:
  /// **'Andamento Valore'**
  String get statsValueTrend;

  /// N cards label in set completion
  ///
  /// In it, this message translates to:
  /// **'{n} carte'**
  String setCompletionNCards(int n);

  /// N total expansions label
  ///
  /// In it, this message translates to:
  /// **'{n} espansioni totali'**
  String setCompletionTotalSets(int n);

  /// Completed and in-progress expansions stats
  ///
  /// In it, this message translates to:
  /// **'{completed} completate · {inProgress} in corso'**
  String setCompletionCompletedStats(int completed, int inProgress);

  /// Out of N expansions label
  ///
  /// In it, this message translates to:
  /// **'su {n} espansioni'**
  String setCompletionOutOf(int n);

  /// In progress tab label
  ///
  /// In it, this message translates to:
  /// **'In corso ({n})'**
  String setCompletionTabInProgress(int n);

  /// Completed tab label
  ///
  /// In it, this message translates to:
  /// **'Completate ({n})'**
  String setCompletionTabCompleted(int n);

  /// Available tab label
  ///
  /// In it, this message translates to:
  /// **'Disponibili ({n})'**
  String setCompletionTabAvailable(int n);

  /// Catalog not downloaded empty state
  ///
  /// In it, this message translates to:
  /// **'Catalogo non ancora scaricato.\nScarica il catalogo dalle Impostazioni.'**
  String get setCompletionNoCatalog;

  /// No in-progress expansions
  ///
  /// In it, this message translates to:
  /// **'Nessuna espansione in corso.'**
  String get setCompletionEmptyInProgress;

  /// No completed expansions
  ///
  /// In it, this message translates to:
  /// **'Nessuna espansione completata.'**
  String get setCompletionEmptyCompleted;

  /// No available expansions
  ///
  /// In it, this message translates to:
  /// **'Nessuna espansione disponibile.'**
  String get setCompletionEmptyAvailable;

  /// Card count in deck subtitle
  ///
  /// In it, this message translates to:
  /// **'{n} carte nel deck'**
  String deckDetailCardCount(int n);

  /// Empty deck state
  ///
  /// In it, this message translates to:
  /// **'Nessuna carta — aggiungile\ndalle carte possedute qui sotto'**
  String get deckDetailEmptyDeck;

  /// Share code instruction
  ///
  /// In it, this message translates to:
  /// **'Condividi questo codice con altri giocatori:'**
  String get deckDetailShareCodeHint;

  /// Code expiry info
  ///
  /// In it, this message translates to:
  /// **'Il codice è valido fino alla rimozione manuale.'**
  String get deckDetailCodeExpiry;

  /// All collections label in news
  ///
  /// In it, this message translates to:
  /// **'Tutti'**
  String get newsCollectionAll;

  /// Today date label in news
  ///
  /// In it, this message translates to:
  /// **'Oggi'**
  String get newsDateToday;

  /// Yesterday date label in news
  ///
  /// In it, this message translates to:
  /// **'Ieri'**
  String get newsDateYesterday;

  /// N days ago date label in news
  ///
  /// In it, this message translates to:
  /// **'{n} giorni fa'**
  String newsDateDaysAgo(int n);

  /// Available updates section header
  ///
  /// In it, this message translates to:
  /// **'Aggiornamenti Disponibili'**
  String get notifSectionAvailableUpdates;

  /// History section header in notifications
  ///
  /// In it, this message translates to:
  /// **'Storico'**
  String get notifSectionHistory;

  /// First download available subtitle
  ///
  /// In it, this message translates to:
  /// **'Primo download disponibile'**
  String get notifFirstDownload;

  /// Partial update subtitle
  ///
  /// In it, this message translates to:
  /// **'Aggiornamento parziale ({chunks} chunk)'**
  String notifPartialUpdate(int chunks);

  /// Full update available subtitle
  ///
  /// In it, this message translates to:
  /// **'Aggiornamento completo disponibile'**
  String get notifFullUpdate;

  /// Later button in notification
  ///
  /// In it, this message translates to:
  /// **'Più tardi'**
  String get notifLater;

  /// No notifications empty state
  ///
  /// In it, this message translates to:
  /// **'Nessuna notifica'**
  String get notifNoNotifications;

  /// New notification badge label
  ///
  /// In it, this message translates to:
  /// **'NUOVA'**
  String get notifNewBadge;

  /// Prices updated notification detail
  ///
  /// In it, this message translates to:
  /// **'Prezzi di mercato aggiornati'**
  String get notifPricesUpdated;

  /// N new cards added notification detail
  ///
  /// In it, this message translates to:
  /// **'+{n} nuove carte aggiunte'**
  String notifNewCardsAdded(int n);

  /// Scanner frame instruction
  ///
  /// In it, this message translates to:
  /// **'Inquadra la carta e premi Scansiona'**
  String get scannerFrameInstruction;

  /// Scan button label
  ///
  /// In it, this message translates to:
  /// **'Scansiona'**
  String get scannerScanBtn;

  /// Accept/I accept button
  ///
  /// In it, this message translates to:
  /// **'Accetto'**
  String get btnAccept;

  /// No CT price available message
  ///
  /// In it, this message translates to:
  /// **'Attualmente nessun prezzo disponibile.'**
  String get ctNoPriceAvailable;

  /// Search on CardTrader link
  ///
  /// In it, this message translates to:
  /// **'Cerca su CardTrader ↗'**
  String get ctSearchOnCardtrader;

  /// Last price date label
  ///
  /// In it, this message translates to:
  /// **'Ultimo: {date}'**
  String ctLastPrice(String date);

  /// Insufficient data for chart period
  ///
  /// In it, this message translates to:
  /// **'Dati insufficienti per il periodo selezionato.'**
  String get ctHistoryInsufficientData;

  /// Chart will populate with price syncs
  ///
  /// In it, this message translates to:
  /// **'Il grafico si popolerà ad ogni sincronizzazione prezzi.'**
  String get ctHistoryWillPopulate;

  /// Collection value chart update note
  ///
  /// In it, this message translates to:
  /// **'Il grafico si aggiorna ogni volta che\nvisiti questa pagina.'**
  String get collectionChartUpdateNote;

  /// Default user type name in splash
  ///
  /// In it, this message translates to:
  /// **'Collezionista'**
  String get splashDefaultCollector;

  /// Year period label in pro page
  ///
  /// In it, this message translates to:
  /// **'anno'**
  String get proYearPeriod;

  /// Yearly plan subtext with monthly price
  ///
  /// In it, this message translates to:
  /// **'€{price}/mese — risparmia il 30%'**
  String proYearSubtext(String price);

  /// Month period label in pro page
  ///
  /// In it, this message translates to:
  /// **'mese'**
  String get proMonthPeriod;

  /// Monthly renewal subtext in pro page
  ///
  /// In it, this message translates to:
  /// **'Rinnovo automatico mensile'**
  String get proMonthSubtext;

  /// ROI portfolio description
  ///
  /// In it, this message translates to:
  /// **'Qui vedi il valore totale delle carte che possiedi. Inserisci il prezzo d\'acquisto di ogni carta per calcolare il tuo ROI e scoprire quanto è cresciuto il tuo investimento.'**
  String get roiPortfolioDescription;

  /// Purchase price helper text in ROI
  ///
  /// In it, this message translates to:
  /// **'Inserisci il prezzo per singola copia'**
  String get roiPurchasePriceHelper;

  /// Restore button label
  ///
  /// In it, this message translates to:
  /// **'Ripristina'**
  String get btnRestore;

  /// Legal section title in settings
  ///
  /// In it, this message translates to:
  /// **'Legale'**
  String get settingsSectionLegal;

  /// Privacy policy tile title
  ///
  /// In it, this message translates to:
  /// **'Informativa sulla Privacy'**
  String get settingsPrivacyPolicy;

  /// Privacy policy tile subtitle
  ///
  /// In it, this message translates to:
  /// **'Come raccogliamo e utilizziamo i tuoi dati'**
  String get settingsPrivacyPolicySubtitle;

  /// Error when privacy page cannot open
  ///
  /// In it, this message translates to:
  /// **'Impossibile aprire la pagina. Riprova più tardi.'**
  String get settingsPrivacyOpenError;

  /// Export to Excel tile title
  ///
  /// In it, this message translates to:
  /// **'Esporta in Excel'**
  String get settingsExportExcel;

  /// Export to Excel tile subtitle
  ///
  /// In it, this message translates to:
  /// **'Scarica la raccolta come file .xlsx'**
  String get settingsExportExcelSubtitle;

  /// Upgrade to Pro tile title in settings
  ///
  /// In it, this message translates to:
  /// **'Passa a Pro'**
  String get settingsUpgradePro;

  /// Upgrade to Pro tile subtitle in settings
  ///
  /// In it, this message translates to:
  /// **'Sblocca tutte le funzionalità premium'**
  String get settingsUpgradeProSubtitle;

  /// Initial status text when an operation starts
  ///
  /// In it, this message translates to:
  /// **'Avvio...'**
  String get settingsResetStarting;

  /// Launch discount badge in pro promo
  ///
  /// In it, this message translates to:
  /// **'SCONTO LANCIO'**
  String get proPromoBadge;

  /// Starting price label in pro promo
  ///
  /// In it, this message translates to:
  /// **'da €1.67/mese'**
  String get proPromoPriceFrom;

  /// CTA button in pro promo sheet
  ///
  /// In it, this message translates to:
  /// **'Scopri Pro'**
  String get proPromoCta;

  /// Dismiss button in pro promo sheet
  ///
  /// In it, this message translates to:
  /// **'No grazie'**
  String get proPromoDismiss;

  /// Pro promo dialog headline
  ///
  /// In it, this message translates to:
  /// **'Sblocca il massimo dalla tua collezione'**
  String get proPromoHeadline;

  /// Pro promo dialog subheadline
  ///
  /// In it, this message translates to:
  /// **'Statistiche avanzate, niente pubblicità e strumenti AI — tutto incluso.'**
  String get proPromoSubheadline;

  /// Pro promo dialog note next to price about annual billing
  ///
  /// In it, this message translates to:
  /// **'Fatturato\nannualmente'**
  String get proPromoBilledAnnually;

  /// Pro benefit: advanced stats and ROI
  ///
  /// In it, this message translates to:
  /// **'Statistiche & ROI avanzati'**
  String get proBenefitStats;

  /// Pro benefit: Excel export
  ///
  /// In it, this message translates to:
  /// **'Esportazione Excel'**
  String get proBenefitExcel;

  /// Pro benefit: AI deck builder
  ///
  /// In it, this message translates to:
  /// **'AI Deck Builder (Yu-Gi-Oh!)'**
  String get proBenefitAi;

  /// Pro benefit: wishlist price alerts
  ///
  /// In it, this message translates to:
  /// **'Avvisi prezzi Wishlist'**
  String get proBenefitAlerts;

  /// Pro benefit: no ads
  ///
  /// In it, this message translates to:
  /// **'Zero pubblicità'**
  String get proBenefitNoAds;

  /// Pro benefit: deck sharing
  ///
  /// In it, this message translates to:
  /// **'Condivisione deck'**
  String get proBenefitShare;

  /// Pro page header subtitle
  ///
  /// In it, this message translates to:
  /// **'Porta la tua collezione al livello successivo'**
  String get proHeaderSubtitle;

  /// Launch discount badge in pro page header
  ///
  /// In it, this message translates to:
  /// **'SCONTO LANCIO — OFFERTA LIMITATA'**
  String get proLaunchBadge;

  /// Features section title in pro page
  ///
  /// In it, this message translates to:
  /// **'TUTTO INCLUSO NEL PRO'**
  String get proAllIncluded;

  /// Pricing section title in pro page
  ///
  /// In it, this message translates to:
  /// **'SCEGLI IL TUO PIANO'**
  String get proChoosePlan;

  /// Semiannual plan title
  ///
  /// In it, this message translates to:
  /// **'Semestrale'**
  String get proSemiannualLabel;

  /// Semiannual plan period
  ///
  /// In it, this message translates to:
  /// **'6 mesi'**
  String get proSemiannualPeriod;

  /// Monthly plan note
  ///
  /// In it, this message translates to:
  /// **'Flessibile, disdici quando vuoi'**
  String get proMonthlyNote;

  /// Plan saving note. price arrives already formatted with the store currency symbol, do not add one
  ///
  /// In it, this message translates to:
  /// **'{price}/mese · risparmia il {percent}%'**
  String proSaveNote(String price, String percent);

  /// Launch tag on plan card
  ///
  /// In it, this message translates to:
  /// **'LANCIO'**
  String get proLaunchTag;

  /// Purchase processing label
  ///
  /// In it, this message translates to:
  /// **'Elaborazione...'**
  String get proProcessing;

  /// Subscribe CTA button
  ///
  /// In it, this message translates to:
  /// **'Abbonati ora'**
  String get proSubscribeNow;

  /// Already subscribed message
  ///
  /// In it, this message translates to:
  /// **'✓ Sei già abbonato a Pro!'**
  String get proAlreadySubscribed;

  /// Footer cancel anytime
  ///
  /// In it, this message translates to:
  /// **'Annulla in qualsiasi momento · Nessun vincolo'**
  String get proFooterCancel;

  /// Footer payment disclaimer
  ///
  /// In it, this message translates to:
  /// **'Il pagamento verrà addebitato tramite App Store / Google Play'**
  String get proFooterPayment;

  /// Restore purchases button
  ///
  /// In it, this message translates to:
  /// **'Ripristina acquisti'**
  String get proRestorePurchases;

  /// Pro feature title: Excel export
  ///
  /// In it, this message translates to:
  /// **'Esportazione Excel'**
  String get proFeatExcelTitle;

  /// Pro feature subtitle: Excel export
  ///
  /// In it, this message translates to:
  /// **'Scarica la raccolta in .xlsx'**
  String get proFeatExcelSub;

  /// Pro feature title: advanced stats
  ///
  /// In it, this message translates to:
  /// **'Statistiche Avanzate'**
  String get proFeatStatsTitle;

  /// Pro feature subtitle: advanced stats
  ///
  /// In it, this message translates to:
  /// **'Valore, rarità, trend nel tempo'**
  String get proFeatStatsSub;

  /// Pro feature title: ROI
  ///
  /// In it, this message translates to:
  /// **'ROI & Investimento'**
  String get proFeatRoiTitle;

  /// Pro feature subtitle: ROI
  ///
  /// In it, this message translates to:
  /// **'Calcola il rendimento della raccolta'**
  String get proFeatRoiSub;

  /// Pro feature title: deck sharing
  ///
  /// In it, this message translates to:
  /// **'Condivisione Deck'**
  String get proFeatShareTitle;

  /// Pro feature subtitle: deck sharing
  ///
  /// In it, this message translates to:
  /// **'Genera link condivisibili per i mazzi'**
  String get proFeatShareSub;

  /// Pro feature title: AI deck builder
  ///
  /// In it, this message translates to:
  /// **'AI Deck Builder'**
  String get proFeatAiTitle;

  /// Pro feature subtitle: AI deck builder
  ///
  /// In it, this message translates to:
  /// **'Costruttore automatico per Yu-Gi-Oh!'**
  String get proFeatAiSub;

  /// Pro feature title: wishlist price alerts
  ///
  /// In it, this message translates to:
  /// **'Avvisi Prezzi Wishlist'**
  String get proFeatAlertsTitle;

  /// Pro feature subtitle: wishlist price alerts
  ///
  /// In it, this message translates to:
  /// **'Notifiche quando il prezzo scende'**
  String get proFeatAlertsSub;

  /// Pro feature title: no ads
  ///
  /// In it, this message translates to:
  /// **'Senza Pubblicità'**
  String get proFeatNoAdsTitle;

  /// Pro feature subtitle: no ads
  ///
  /// In it, this message translates to:
  /// **'Esperienza pulita senza interruzioni'**
  String get proFeatNoAdsSub;

  /// Pro feature title: priority support
  ///
  /// In it, this message translates to:
  /// **'Supporto Prioritario'**
  String get proFeatSupportTitle;

  /// Pro feature subtitle: priority support
  ///
  /// In it, this message translates to:
  /// **'Risposta garantita entro 24h'**
  String get proFeatSupportSub;

  /// Support page header title
  ///
  /// In it, this message translates to:
  /// **'Come possiamo aiutarti?'**
  String get supportHeaderTitle;

  /// Support page header subtitle
  ///
  /// In it, this message translates to:
  /// **'Contattaci per qualsiasi problema o suggerimento.'**
  String get supportHeaderSubtitle;

  /// Support contact section label
  ///
  /// In it, this message translates to:
  /// **'CONTATTACI'**
  String get supportSectionContact;

  /// Support opinion section label
  ///
  /// In it, this message translates to:
  /// **'LA TUA OPINIONE CONTA'**
  String get supportSectionOpinion;

  /// Support FAQ section label
  ///
  /// In it, this message translates to:
  /// **'DOMANDE FREQUENTI'**
  String get supportSectionFaq;

  /// Support other section label
  ///
  /// In it, this message translates to:
  /// **'ALTRO'**
  String get supportSectionOther;

  /// Leave a review tile title
  ///
  /// In it, this message translates to:
  /// **'Lascia una recensione'**
  String get supportReviewTitle;

  /// Leave a review tile subtitle
  ///
  /// In it, this message translates to:
  /// **'Hai apprezzato l\'app? Aiutaci con una valutazione sullo store'**
  String get supportReviewSubtitle;

  /// Share app tile title
  ///
  /// In it, this message translates to:
  /// **'Condividi Deck Master'**
  String get supportShareTitle;

  /// Share app tile subtitle
  ///
  /// In it, this message translates to:
  /// **'Consiglia l\'app ad altri collezionisti'**
  String get supportShareSubtitle;

  /// Suggestions tile title
  ///
  /// In it, this message translates to:
  /// **'Suggerimenti'**
  String get supportSuggestionsTitle;

  /// Suggestions tile subtitle
  ///
  /// In it, this message translates to:
  /// **'Hai idee per migliorare l\'app? Scrivici'**
  String get supportSuggestionsSubtitle;

  /// Feature guide tile title
  ///
  /// In it, this message translates to:
  /// **'Guida alle funzionalità'**
  String get supportGuideTitle;

  /// Feature guide tile subtitle
  ///
  /// In it, this message translates to:
  /// **'Scopri passo per passo come usare ogni funzione dell\'app'**
  String get supportGuideSubtitle;

  /// Replay tutorial tile title
  ///
  /// In it, this message translates to:
  /// **'Rivedi il tutorial'**
  String get supportTutorialTitle;

  /// Replay tutorial tile subtitle
  ///
  /// In it, this message translates to:
  /// **'Guarda di nuovo la presentazione iniziale dell\'app'**
  String get supportTutorialSubtitle;

  /// Bug report email subject
  ///
  /// In it, this message translates to:
  /// **'Segnalazione Problema - Deck Master'**
  String get supportBugEmailSubject;

  /// Bug report email body
  ///
  /// In it, this message translates to:
  /// **'Ciao,\n\nHo riscontrato il seguente problema:\n\n[Descrivi il problema qui]\n\n---\nAccount: {email}'**
  String supportBugEmailBody(String email);

  /// Missing cards email subject
  ///
  /// In it, this message translates to:
  /// **'Carte Mancanti - Deck Master'**
  String get supportMissingEmailSubject;

  /// Missing cards email body
  ///
  /// In it, this message translates to:
  /// **'Ciao,\n\nVorrei segnalare le seguenti carte mancanti/errate:\n\nCollezione: [Yu-Gi-Oh! / One Piece / ...]\nCarta: [Nome carta]\nSet: [Numero Codice]\nMotivo: [Mancante / Dati errati / Immagine sbagliata]\n\n---\nAccount: {email}'**
  String supportMissingEmailBody(String email);

  /// Review email subject
  ///
  /// In it, this message translates to:
  /// **'Recensione - Deck Master'**
  String get supportReviewEmailSubject;

  /// Review email body
  ///
  /// In it, this message translates to:
  /// **'Ciao,\n\nVorrei lasciare il seguente feedback sull\'app:\n\nValutazione: [⭐⭐⭐⭐⭐]\n\n[Scrivi qui la tua opinione]\n\n---\nAccount: {email}'**
  String supportReviewEmailBody(String email);

  /// Suggestion email subject
  ///
  /// In it, this message translates to:
  /// **'Suggerimenti - Deck Master'**
  String get supportSuggestEmailSubject;

  /// Suggestion email body
  ///
  /// In it, this message translates to:
  /// **'Ciao,\n\nVorrei suggerire la seguente funzionalità o miglioramento:\n\n[Descrivi il suggerimento qui]\n\n---\nAccount: {email}'**
  String supportSuggestEmailBody(String email);

  /// Share app text
  ///
  /// In it, this message translates to:
  /// **'🃏 Gestisco la mia collezione di carte con Deck Master!\n\nSupporta Yu-Gi-Oh!, Pokémon, One Piece, Magic e molti altri TCG. Prezzi aggiornati, scanner, deck builder e tanto altro.\n\nScaricalo su App Store e Google Play: cerca \"Deck Master TCG\"'**
  String get supportShareText;

  /// FAQ question 1
  ///
  /// In it, this message translates to:
  /// **'Come aggiungo una carta alla mia collezione?'**
  String get supportFaqQ1;

  /// FAQ answer 1
  ///
  /// In it, this message translates to:
  /// **'Puoi aggiungere carte in tre modi: cerca dal Catalogo e tocca \"Aggiungi\", usa lo Scanner per fotografare la carta, oppure tocca una carta nel dettaglio del set. Specifica la quantità e conferma.'**
  String get supportFaqA1;

  /// FAQ question 2
  ///
  /// In it, this message translates to:
  /// **'Come funziona la Wishlist?'**
  String get supportFaqQ2;

  /// FAQ answer 2
  ///
  /// In it, this message translates to:
  /// **'Tocca il ❤ su qualsiasi carta per aggiungerla alla Wishlist. Puoi impostare un prezzo obiettivo: riceverai una notifica push quando il prezzo scende sotto la soglia impostata.'**
  String get supportFaqA2;

  /// FAQ question 3
  ///
  /// In it, this message translates to:
  /// **'Come costruisco un deck?'**
  String get supportFaqQ3;

  /// FAQ answer 3
  ///
  /// In it, this message translates to:
  /// **'Vai nella raccolta della tua collezione, seleziona la tab \"Deck\" e tocca + per creare un nuovo mazzo. Apri il deck e aggiungi le carte dalla sezione \"Carte Possedute\" in basso.'**
  String get supportFaqA3;

  /// FAQ question 4
  ///
  /// In it, this message translates to:
  /// **'Come sincronizzo i dati su più dispositivi?'**
  String get supportFaqQ4;

  /// FAQ answer 4
  ///
  /// In it, this message translates to:
  /// **'La sincronizzazione avviene automaticamente quando sei connesso. Accedi con lo stesso account su ogni dispositivo. Puoi anche forzarla manualmente da Impostazioni → Sincronizzazione.'**
  String get supportFaqA4;

  /// FAQ question 5
  ///
  /// In it, this message translates to:
  /// **'Cos\'è il piano Pro?'**
  String get supportFaqQ5;

  /// FAQ answer 5
  ///
  /// In it, this message translates to:
  /// **'Il piano Pro sblocca: esportazione Excel, statistiche avanzate, ROI, condivisione deck, costruttore AI per Yu-Gi-Oh! e nessuna pubblicità. Lo trovi in Impostazioni → Passa a Pro.'**
  String get supportFaqA5;

  /// FAQ question 6
  ///
  /// In it, this message translates to:
  /// **'Come funziona lo scanner?'**
  String get supportFaqQ6;

  /// FAQ answer 6
  ///
  /// In it, this message translates to:
  /// **'Tocca l\'icona scanner in alto. Inquadra la carta con la fotocamera in buona illuminazione e tienila ferma. L\'app la riconosce automaticamente e ti propone di aggiungerla alla raccolta.'**
  String get supportFaqA6;

  /// FAQ question 7
  ///
  /// In it, this message translates to:
  /// **'I prezzi sono aggiornati?'**
  String get supportFaqQ7;

  /// FAQ answer 7
  ///
  /// In it, this message translates to:
  /// **'Sì, i prezzi vengono sincronizzati ogni giorno da CardTrader. Se vuoi aggiornare manualmente, vai in Impostazioni → Sincronizzazione e tocca \"Aggiorna Prezzi\".'**
  String get supportFaqA7;

  /// App guide appbar title
  ///
  /// In it, this message translates to:
  /// **'Guida alle Funzionalità'**
  String get guideAppBarTitle;

  /// App guide header title
  ///
  /// In it, this message translates to:
  /// **'Come funziona Deck Master'**
  String get guideHeaderTitle;

  /// App guide header subtitle
  ///
  /// In it, this message translates to:
  /// **'Tocca una funzionalità per scoprire come usarla passo per passo.'**
  String get guideHeaderSubtitle;

  /// Guide: collections title
  ///
  /// In it, this message translates to:
  /// **'Le Collezioni'**
  String get guideCollectionsTitle;

  /// Guide: collections description
  ///
  /// In it, this message translates to:
  /// **'Ogni collezione rappresenta un gioco di carte (Yu-Gi-Oh!, Pokémon, ecc.). Sblocca le collezioni che possiedi per iniziare a gestirle.'**
  String get guideCollectionsDesc;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Vai nelle Impostazioni → Gestione Collezioni'**
  String get guideCollectionsStep1;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Attiva le collezioni che possiedi'**
  String get guideCollectionsStep2;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Ogni collezione apparirà nel menu principale'**
  String get guideCollectionsStep3;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Puoi cambiare la collezione attiva dal selettore in alto'**
  String get guideCollectionsStep4;

  /// Guide: add cards title
  ///
  /// In it, this message translates to:
  /// **'Aggiungere Carte'**
  String get guideAddTitle;

  /// Guide: add cards description
  ///
  /// In it, this message translates to:
  /// **'Ci sono tre modi per aggiungere carte alla tua collezione: manualmente dal catalogo, tramite scanner o importando da file.'**
  String get guideAddDesc;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Catalogo: cerca la carta, tocca \"Aggiungi\" e inserisci la quantità'**
  String get guideAddStep1;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Scanner: inquadra la carta con la fotocamera per un riconoscimento automatico'**
  String get guideAddStep2;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Usa il filtro per cercare per nome, set o codice seriale'**
  String get guideAddStep3;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Le carte aggiunte appaiono subito nella tua raccolta'**
  String get guideAddStep4;

  /// Guide: scanner title
  ///
  /// In it, this message translates to:
  /// **'Scanner Carte'**
  String get guideScannerTitle;

  /// Guide: scanner description
  ///
  /// In it, this message translates to:
  /// **'Fotografa una carta con la fotocamera per riconoscerla automaticamente e aggiungerla alla collezione in un tocco.'**
  String get guideScannerDesc;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Tocca l\'icona scanner nella barra in alto'**
  String get guideScannerStep1;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Inquadra bene la carta — tieni la fotocamera ferma'**
  String get guideScannerStep2;

  /// step
  ///
  /// In it, this message translates to:
  /// **'L\'app riconosce la carta e mostra i dettagli'**
  String get guideScannerStep3;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Conferma la quantità e aggiungi alla collezione'**
  String get guideScannerStep4;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Funziona meglio con buona illuminazione e carta non riflettente'**
  String get guideScannerStep5;

  /// Guide: catalog title
  ///
  /// In it, this message translates to:
  /// **'Catalogo & Prezzi'**
  String get guideCatalogTitle;

  /// Guide: catalog description
  ///
  /// In it, this message translates to:
  /// **'Il catalogo mostra tutte le carte disponibili con prezzi aggiornati da CardTrader. Puoi sfogliare, filtrare e aggiungere direttamente dalla lista.'**
  String get guideCatalogDesc;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Seleziona la collezione e tocca \"Catalogo\"'**
  String get guideCatalogStep1;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Usa la barra di ricerca per trovare una carta specifica'**
  String get guideCatalogStep2;

  /// step
  ///
  /// In it, this message translates to:
  /// **'I prezzi si aggiornano automaticamente ogni giorno'**
  String get guideCatalogStep3;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Tocca il ❤ per aggiungere alla Wishlist direttamente dal catalogo'**
  String get guideCatalogStep4;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Tocca una carta per vedere il dettaglio completo e i prezzi per rarità'**
  String get guideCatalogStep5;

  /// Guide: album title
  ///
  /// In it, this message translates to:
  /// **'Album'**
  String get guideAlbumTitle;

  /// Guide: album description
  ///
  /// In it, this message translates to:
  /// **'Gli album ti permettono di organizzare le carte della tua raccolta in raccoglitori virtuali, con una capacità massima personalizzabile.'**
  String get guideAlbumDesc;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Nella raccolta, vai nella tab \"Album\"'**
  String get guideAlbumStep1;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Tocca + per creare un nuovo album e imposta nome e capacità'**
  String get guideAlbumStep2;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Apri un album per vedere le carte contenute'**
  String get guideAlbumStep3;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Aggiungi carte all\'album dalla raccolta principale'**
  String get guideAlbumStep4;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Usa i contatori per sapere quante carte hai inserito'**
  String get guideAlbumStep5;

  /// Guide: deck title
  ///
  /// In it, this message translates to:
  /// **'Deck Builder'**
  String get guideDeckTitle;

  /// Guide: deck description
  ///
  /// In it, this message translates to:
  /// **'Costruisci e gestisci i tuoi mazzi da gioco. Tieni traccia di ogni carta, controlla la composizione e condividi i deck con altri giocatori.'**
  String get guideDeckDesc;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Vai nella tab \"Deck\" della tua raccolta'**
  String get guideDeckStep1;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Tocca + per creare un nuovo deck'**
  String get guideDeckStep2;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Apri il deck e aggiungi carte dalla sezione \"Carte Possedute\"'**
  String get guideDeckStep3;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Usa il pulsante condividi per generare un link condivisibile (Pro)'**
  String get guideDeckStep4;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Per Yu-Gi-Oh! puoi usare il costruttore AI per suggerimenti automatici'**
  String get guideDeckStep5;

  /// Guide: wishlist title
  ///
  /// In it, this message translates to:
  /// **'Wishlist & Avvisi Prezzi'**
  String get guideWishlistTitle;

  /// Guide: wishlist description
  ///
  /// In it, this message translates to:
  /// **'Salva le carte che vuoi acquistare e ricevi notifiche quando il prezzo scende sotto la soglia che hai impostato.'**
  String get guideWishlistDesc;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Tocca il ❤ su qualsiasi carta per aggiungerla alla Wishlist'**
  String get guideWishlistStep1;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Apri la Wishlist dal menu profilo in alto a destra'**
  String get guideWishlistStep2;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Imposta un prezzo obiettivo per ogni carta'**
  String get guideWishlistStep3;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Riceverai una notifica push quando il prezzo scende'**
  String get guideWishlistStep4;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Rimuovi la carta dalla Wishlist una volta acquistata'**
  String get guideWishlistStep5;

  /// Guide: stats title
  ///
  /// In it, this message translates to:
  /// **'Statistiche & ROI'**
  String get guideStatsTitle;

  /// Guide: stats description
  ///
  /// In it, this message translates to:
  /// **'Monitora il valore totale della tua collezione nel tempo e calcola il rendimento del tuo investimento con grafici dettagliati.'**
  String get guideStatsDesc;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Tocca l\'icona grafico nella barra in alto per le statistiche'**
  String get guideStatsStep1;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Visualizza il valore totale, le carte per rarità e i trend'**
  String get guideStatsStep2;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Il ROI confronta il costo stimato di acquisto con il valore attuale'**
  String get guideStatsStep3;

  /// step
  ///
  /// In it, this message translates to:
  /// **'I dati si aggiornano automaticamente con ogni sync prezzi'**
  String get guideStatsStep4;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Disponibile solo con piano Pro'**
  String get guideStatsStep5;

  /// Guide: notifications title
  ///
  /// In it, this message translates to:
  /// **'Notifiche'**
  String get guideNotifTitle;

  /// Guide: notifications description
  ///
  /// In it, this message translates to:
  /// **'Deck Master ti avvisa quando i prezzi cambiano, quando ci sono aggiornamenti del catalogo o nuove funzionalità disponibili.'**
  String get guideNotifDesc;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Abilita le notifiche nelle Impostazioni → Notifiche'**
  String get guideNotifStep1;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Le notifiche di prezzo arrivano quando un articolo in Wishlist scende'**
  String get guideNotifStep2;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Puoi vedere tutte le notifiche passate nella sezione Notifiche'**
  String get guideNotifStep3;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Tocca una notifica per andare direttamente alla carta'**
  String get guideNotifStep4;

  /// Guide: export title
  ///
  /// In it, this message translates to:
  /// **'Esportazione Excel'**
  String get guideExportTitle;

  /// Guide: export description
  ///
  /// In it, this message translates to:
  /// **'Esporta tutta la tua raccolta in un file Excel (.xlsx) per analisi esterne, backup o condivisione con altri collezionisti.'**
  String get guideExportDesc;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Vai in Impostazioni → Esportazione'**
  String get guideExportStep1;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Tocca \"Esporta in Excel\"'**
  String get guideExportStep2;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Il file viene generato con Nome, Codice, Collezione, Rarità, Quantità e Valore'**
  String get guideExportStep3;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Scegli dove salvare o condividere il file dal pannello di sistema'**
  String get guideExportStep4;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Disponibile solo con piano Pro'**
  String get guideExportStep5;

  /// Guide: sync title
  ///
  /// In it, this message translates to:
  /// **'Sincronizzazione Cloud'**
  String get guideSyncTitle;

  /// Guide: sync description
  ///
  /// In it, this message translates to:
  /// **'I tuoi dati vengono sincronizzati automaticamente su tutti i dispositivi tramite il tuo account. Non perderai mai la tua raccolta.'**
  String get guideSyncDesc;

  /// step
  ///
  /// In it, this message translates to:
  /// **'La sync avviene automaticamente all\'avvio e dopo ogni modifica'**
  String get guideSyncStep1;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Vai in Impostazioni → Sincronizzazione per forzarla manualmente'**
  String get guideSyncStep2;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Se vedi l\'icona ⚠️ c\'è un conflitto: scegli quale versione tenere'**
  String get guideSyncStep3;

  /// step
  ///
  /// In it, this message translates to:
  /// **'Funziona anche offline: le modifiche si sincronizzano al ritorno della connessione'**
  String get guideSyncStep4;

  /// Delete album confirm message
  ///
  /// In it, this message translates to:
  /// **'Sei sicuro di voler eliminare \"{name}\"?'**
  String dlgDeleteAlbumMsg(String name);

  /// Delete album with cards confirm message
  ///
  /// In it, this message translates to:
  /// **'Sei sicuro di voler eliminare \"{name}\"?\n\nVerranno eliminate anche tutte le {count} carte contenute.\n\nQuesta azione non può essere annullata.'**
  String dlgDeleteAlbumWithCardsMsg(String name, int count);

  /// Coming soon dialog title
  ///
  /// In it, this message translates to:
  /// **'In arrivo'**
  String get comingSoonTitle;

  /// Coming soon dialog message
  ///
  /// In it, this message translates to:
  /// **'Funzionalità in fase di sviluppo, arriverà a breve!'**
  String get comingSoonMsg;

  /// Name required validation
  ///
  /// In it, this message translates to:
  /// **'Il nome è obbligatorio'**
  String get msgNameRequired;

  /// Download starting status
  ///
  /// In it, this message translates to:
  /// **'Avvio...'**
  String get downloadStarting;

  /// Download notification title
  ///
  /// In it, this message translates to:
  /// **'Deck Master — Download'**
  String get downloadTitle;

  /// Tutorial skip button
  ///
  /// In it, this message translates to:
  /// **'Salta'**
  String get tutorialBtnSkip;

  /// Tutorial next button
  ///
  /// In it, this message translates to:
  /// **'Avanti'**
  String get tutorialBtnNext;

  /// Tutorial start button
  ///
  /// In it, this message translates to:
  /// **'Inizia!'**
  String get tutorialBtnStart;

  /// Tutorial slide 1 title
  ///
  /// In it, this message translates to:
  /// **'Benvenuto in Deck Master'**
  String get tutorialSlide1Title;

  /// Tutorial slide 1 description
  ///
  /// In it, this message translates to:
  /// **'La tua app per gestire, valorizzare e analizzare la tua collezione di carte collezionabili.\n\nSupporta 13 TCG: Yu-Gi-Oh!, Pokémon, One Piece, Magic e molti altri.'**
  String get tutorialSlide1Desc;

  /// Tutorial slide 2 title
  ///
  /// In it, this message translates to:
  /// **'Le tue Collezioni'**
  String get tutorialSlide2Title;

  /// Tutorial slide 2 description
  ///
  /// In it, this message translates to:
  /// **'Sblocca le collezioni che possiedi. Per ogni collezione puoi aggiungere carte, sfogliare il catalogo completo e costruire mazzi.'**
  String get tutorialSlide2Desc;

  /// Tutorial slide 3 title
  ///
  /// In it, this message translates to:
  /// **'Catalogo Carte'**
  String get tutorialSlide3Title;

  /// Tutorial slide 3 description
  ///
  /// In it, this message translates to:
  /// **'Sfoglia il catalogo completo con prezzi aggiornati da CardTrader.\n\nTocca il ❤️ su una carta per aggiungerla alla Wishlist direttamente dal catalogo.'**
  String get tutorialSlide3Desc;

  /// Tutorial slide 4 title
  ///
  /// In it, this message translates to:
  /// **'Scanner Carte'**
  String get tutorialSlide4Title;

  /// Tutorial slide 4 description
  ///
  /// In it, this message translates to:
  /// **'Inquadra una carta con la fotocamera per riconoscerla automaticamente e aggiungerla alla tua collezione in un click.'**
  String get tutorialSlide4Desc;

  /// Tutorial slide 5 title
  ///
  /// In it, this message translates to:
  /// **'Wishlist & Avvisi Prezzi'**
  String get tutorialSlide5Title;

  /// Tutorial slide 5 description
  ///
  /// In it, this message translates to:
  /// **'Aggiungi le carte che vuoi acquistare alla Wishlist. Imposta un prezzo obiettivo e ricevi una notifica quando il prezzo scende sotto la soglia.'**
  String get tutorialSlide5Desc;

  /// Tutorial slide 6 title
  ///
  /// In it, this message translates to:
  /// **'Analisi & ROI'**
  String get tutorialSlide6Title;

  /// Tutorial slide 6 description
  ///
  /// In it, this message translates to:
  /// **'Monitora il valore totale della tua collezione nel tempo. Scopri il tuo ritorno sull\'investimento con grafici e statistiche dettagliate.'**
  String get tutorialSlide6Desc;

  /// Tutorial slide 7 title
  ///
  /// In it, this message translates to:
  /// **'Deck Builder'**
  String get tutorialSlide7Title;

  /// Tutorial slide 7 description
  ///
  /// In it, this message translates to:
  /// **'Costruisci e gestisci i tuoi mazzi. Analizza la composizione, il valore e tieni traccia di tutto quello che hai costruito.'**
  String get tutorialSlide7Desc;

  /// Catalog download operation label
  ///
  /// In it, this message translates to:
  /// **'Catalogo'**
  String get downloadCatalog;

  /// Catalog restore operation label
  ///
  /// In it, this message translates to:
  /// **'Ripristino catalogo'**
  String get downloadRestoreCatalog;

  /// Catalog restore progress
  ///
  /// In it, this message translates to:
  /// **'Ripristino {current}/{total}: {name}'**
  String downloadRestoreProgress(int current, int total, String name);

  /// Collection download progress
  ///
  /// In it, this message translates to:
  /// **'Collezione {current}/{total}: {name}'**
  String downloadCollectionProgress(int current, int total, String name);

  /// Collection download progress with percent
  ///
  /// In it, this message translates to:
  /// **'Collezione {current}/{total}: {name} ({pct}%)'**
  String downloadCollectionProgressPct(
    int current,
    int total,
    String name,
    int pct,
  );

  /// Single collection download progress with percent
  ///
  /// In it, this message translates to:
  /// **'{name} ({pct}%)'**
  String downloadProgressPct(String name, int pct);

  /// Card info row label: album
  ///
  /// In it, this message translates to:
  /// **'Album'**
  String get cardLabelAlbum;

  /// Card info row label: quantity
  ///
  /// In it, this message translates to:
  /// **'Quantità'**
  String get cardLabelQuantity;

  /// Card info row label: type
  ///
  /// In it, this message translates to:
  /// **'Tipo'**
  String get cardLabelType;

  /// Card info row label: rarity
  ///
  /// In it, this message translates to:
  /// **'Rarità'**
  String get cardLabelRarity;

  /// Search on CardTrader link
  ///
  /// In it, this message translates to:
  /// **'Cerca su CardTrader ↗'**
  String get cardSearchOnCardtrader;

  /// Album full message
  ///
  /// In it, this message translates to:
  /// **'{name} ha raggiunto la capacità massima ({current}/{max}).\n\nAumenta la capacità dell\'album oppure seleziona un altro album.'**
  String cardDialogAlbumFullMsg(String name, int current, int max);

  /// Album max capacity field label
  ///
  /// In it, this message translates to:
  /// **'CAPACITÀ MASSIMA'**
  String get albumMaxCapacityLabel;

  /// AI scanner privacy dialog title
  ///
  /// In it, this message translates to:
  /// **'Informativa scanner AI'**
  String get scannerPrivacyTitle;

  /// AI scanner privacy dialog body
  ///
  /// In it, this message translates to:
  /// **'Per identificare le tue carte, il fotogramma acquisito viene inviato temporaneamente ai servizi AI di Google (Gemini) tramite connessione cifrata.\n\nLe immagini non vengono conservate da Deck Master né da Google oltre il tempo necessario all\'elaborazione della singola richiesta.\n\nContinuando autorizzi questo trasferimento. Puoi rifiutare: in quel caso lo scanner non sarà disponibile.'**
  String get scannerPrivacyBody;

  /// AI deck builder note about using only owned cards
  ///
  /// In it, this message translates to:
  /// **'L\'AI costruirà un deck usando solo le carte nella tua collezione.'**
  String get aiDeckOnlyOwnedNote;
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
