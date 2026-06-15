// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Deck Master';

  @override
  String get btnContinue => 'Continue';

  @override
  String get btnStart => 'Start';

  @override
  String get btnCancel => 'Cancel';

  @override
  String get btnConfirm => 'Confirm';

  @override
  String get btnSave => 'Save';

  @override
  String get btnDelete => 'Delete';

  @override
  String get btnClose => 'Close';

  @override
  String get btnRetry => 'Retry';

  @override
  String get btnAdd => 'Add';

  @override
  String get btnCreate => 'Create';

  @override
  String get btnEdit => 'Edit';

  @override
  String get btnPublish => 'Publish';

  @override
  String get btnLogout => 'Logout';

  @override
  String get btnLogin => 'Sign In';

  @override
  String get btnRegister => 'Register';

  @override
  String get btnGoPro => 'Go Pro';

  @override
  String get btnMove => 'Move';

  @override
  String get btnSearch => 'Search';

  @override
  String get btnApply => 'Apply';

  @override
  String get btnStart2 => 'Start';

  @override
  String get btnOk => 'OK';

  @override
  String get splashWelcomeFirst => 'Welcome,';

  @override
  String get splashWelcomeBack => 'Welcome back,';

  @override
  String get splashFirstLoginSubtitle =>
      'Your collector adventure starts now. 🎴';

  @override
  String get splashTapToContinue => 'Tap to continue';

  @override
  String get splashReturning1 => 'Your cards were waiting for you.';

  @override
  String get splashReturning2 => 'Your deck is ready for action.';

  @override
  String get splashReturning3 => 'The collection calls, the collector answers.';

  @override
  String get splashReturning4 => 'Every card has a story. What\'s yours today?';

  @override
  String get onboardingSelectLanguageTitle => 'Select language';

  @override
  String get onboardingSelectLanguageSubtitle => 'Choose your language';

  @override
  String get onboardingSelectCurrencyTitle => 'Select currency';

  @override
  String get onboardingSelectCurrencySubtitle =>
      'Select your preferred currency';

  @override
  String get onboardingStep1of2 => '1 / 2';

  @override
  String get onboardingStep2of2 => '2 / 2';

  @override
  String get loginSubtitle => 'Your card collection';

  @override
  String get loginAccessToContinue => 'Sign in to continue';

  @override
  String get loginEmailPlaceholder => 'Email';

  @override
  String get loginPasswordPlaceholder => 'Password';

  @override
  String get loginBtnAccedi => 'SIGN IN';

  @override
  String get loginBtnRegistrati => 'REGISTER';

  @override
  String get loginNoAccount => 'Don\'t have an account? Register';

  @override
  String get loginHasAccount => 'Already have an account? Sign in';

  @override
  String get loginOrContinueWith => 'Or continue with';

  @override
  String get loginContinueOfflineTooltip => 'Continue without connection';

  @override
  String get loginNoInternetTitle => 'No connection';

  @override
  String get loginNoInternetBody =>
      'Unable to reach the internet.\nYou can continue in offline mode or retry.';

  @override
  String get loginBtnRetry => 'Retry';

  @override
  String get loginBtnOfflineAccess => 'Offline mode';

  @override
  String get msgLoginCancelled => 'Login cancelled or failed';

  @override
  String get msgUserNotFound => 'User not found';

  @override
  String get msgInvalidCredentials => 'Invalid credentials';

  @override
  String get msgEmailInUse => 'Email already in use';

  @override
  String get msgLoginCancelledShort => 'Login cancelled';

  @override
  String get msgPopupBlocked =>
      'Popup blocked by browser. Allow popups for this site.';

  @override
  String get msgUnauthorizedDomain =>
      'Domain not authorized in Firebase Console';

  @override
  String get msgNetworkError => 'Network error. Check your connection.';

  @override
  String msgErrorGeneric(String error) {
    return 'Error: $error';
  }

  @override
  String get msgInsertEmailPassword => 'Enter email and password';

  @override
  String get navHome => 'Home';

  @override
  String get navCards => 'Cards';

  @override
  String get navCatalog => 'Catalog';

  @override
  String get navCollection => 'Collection';

  @override
  String get navNews => 'News';

  @override
  String get navMyCards => 'My Cards';

  @override
  String get menuProfile => 'Profile';

  @override
  String get menuWishlist => 'Wishlist';

  @override
  String get menuSettings => 'Settings';

  @override
  String get menuCheckUpdates => 'Check for updates';

  @override
  String get menuDonations => 'Buy me a coffee';

  @override
  String get menuSupport => 'Support';

  @override
  String get tooltipBackToHome => 'Back to Home';

  @override
  String get tooltipScanCard => 'Scan card';

  @override
  String get tooltipWishlist => 'Wishlist';

  @override
  String get tooltipRoi => 'ROI Analysis';

  @override
  String get tooltipNotifications => 'Notifications';

  @override
  String get tooltipCatalogUpdate =>
      'Catalog update available — tap to download';

  @override
  String get tooltipStats => 'Statistics';

  @override
  String get tooltipUserMenu => 'User menu';

  @override
  String msgAppUpdated(String version) {
    return 'App updated to version $version';
  }

  @override
  String get msgAlreadyLatestVersion =>
      'You\'re already on the latest version.';

  @override
  String get msgCatalogUpdatedSuccess => 'Catalog updated successfully!';

  @override
  String get msgCatalogRestoredSuccess => 'Catalog restored successfully!';

  @override
  String msgCatalogRestoreFailed(String error) {
    return 'Restore failed: $error';
  }

  @override
  String msgErrorUpdateCollection(String name, String error) {
    return 'Error updating $name: $error';
  }

  @override
  String msgErrorRestoreCollection(String name, String error) {
    return 'Error restoring $name: $error';
  }

  @override
  String msgLevelUp(int level) {
    return 'You reached level $level! 🎉';
  }

  @override
  String get popoverTapToClose => 'Tap outside to close';

  @override
  String get downloadPhaseConnecting => 'Connecting...';

  @override
  String get downloadPhaseDownloading => 'Downloading...';

  @override
  String get downloadPhaseSaving => 'Saving...';

  @override
  String get downloadYugiohConnecting => 'Connecting to the Shadow Realm...';

  @override
  String get downloadYugiohDownloading =>
      'Maximillion Pegasus is creating the cards...';

  @override
  String get downloadYugiohSaving =>
      'The Pharaoh seals the cards in the Dueling Book...';

  @override
  String get downloadPokemonConnecting => 'Connecting to Prof. Oak\'s Lab...';

  @override
  String get downloadPokemonDownloading =>
      'Prof. Oak is cataloguing the Pokémon...';

  @override
  String get downloadPokemonSaving => 'Archiving in the National Pokédex...';

  @override
  String get downloadOnepieceConnecting => 'Sailing toward the Grand Line...';

  @override
  String get downloadOnepieceDownloading =>
      'Shanks is distributing the cards...';

  @override
  String get downloadOnepieceSaving => 'The Straw Hat Crew loads the cards...';

  @override
  String get downloadMagicConnecting => 'Connecting to the Arcane Archive...';

  @override
  String get downloadMagicDownloading =>
      'The Ravnica Council catalogues the cards...';

  @override
  String get downloadMagicSaving => 'Sealing in the Magic Codex...';

  @override
  String get adminCatalogTitle => 'Admin — Catalog Management';

  @override
  String get homeMyCollections => 'My Collections';

  @override
  String get homeAvailableCollections => 'Available Collections';

  @override
  String get homeComingSoon => 'Coming Soon';

  @override
  String homeUnlockTitle(String name) {
    return 'Unlock $name';
  }

  @override
  String homeUnlockFirstMsg(String name) {
    return 'Do you want to add $name as your first collection? It\'s completely free!';
  }

  @override
  String get homeUnlockProMsg =>
      'With the Pro plan you can unlock all collections without ads.';

  @override
  String get homeUnlockFree => 'FREE';

  @override
  String get homeUnlockBtn => 'Unlock';

  @override
  String homeWatchVideoTitle(String name) {
    return 'Unlock $name';
  }

  @override
  String get homeWatchVideoMsg =>
      'Watch a short video to unlock this collection for free.';

  @override
  String get homeWatchVideoProNote =>
      'With the Pro plan you unlock everything without ads.';

  @override
  String get homeWatchVideoBtn => 'Watch Video';

  @override
  String get msgVideoNotAvailable =>
      'Video not available right now. Try again in a few seconds.';

  @override
  String msgCollectionUnlocked(String name) {
    return '$name unlocked!';
  }

  @override
  String get msgVideoError => 'Error during video. Please try again.';

  @override
  String get tutorialCollectionTitle => 'Your Collection';

  @override
  String get tutorialUnlockCollectionTitle => 'Unlock a Collection';

  @override
  String get tutorialCollectionDesc =>
      'Tap this card to open your collection and start adding your cards!';

  @override
  String get tutorialUnlockCollectionDesc =>
      'Tap this card to unlock your first collection. It\'s completely free!';

  @override
  String get tutorialScannerTitle => 'Card Scanner';

  @override
  String get tutorialScannerDesc =>
      'Scan your physical cards with the camera to add them automatically to your collection.';

  @override
  String get tutorialWishlistTitle => 'Wishlist';

  @override
  String get tutorialWishlistDesc =>
      'Add cards you want to buy and set a target price. You\'ll be notified when the price drops.';

  @override
  String get tutorialRoiTitle => 'ROI Analysis';

  @override
  String get tutorialRoiDesc =>
      'Enter the price you paid for each card and discover how much your investment is worth over time.';

  @override
  String get tutorialSkip => 'SKIP';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsOfflineMode => 'Offline Mode';

  @override
  String get settingsOfflineSubtitle => 'Data is not synced to the cloud';

  @override
  String get settingsSignInOnline => 'Sign in and go online';

  @override
  String get settingsUserNotLogged => 'User not logged in';

  @override
  String get settingsViewProfile => 'View Profile';

  @override
  String get settingsSectionAdmin => 'Administration';

  @override
  String get settingsManageUsers => 'Manage Users';

  @override
  String get settingsManageUsersSubtitle => 'View and edit user roles';

  @override
  String get settingsManageCatalog => 'Manage Catalog';

  @override
  String get settingsManageCatalogSubtitle => 'Add/Edit cards in the catalog';

  @override
  String get settingsSectionCatalogRestore => 'Catalog Restore';

  @override
  String get settingsRestoreCatalog => 'Restore Catalog';

  @override
  String get settingsRestoreCatalogSubtitle =>
      'Re-download from server and update local catalog';

  @override
  String get settingsRestoreDialogTitle => 'Restore Catalog';

  @override
  String get settingsRestoreDialogSubtitle =>
      'The local catalog will be deleted and re-downloaded from the server.';

  @override
  String get settingsRestoreAllCatalogs => 'All Catalogs';

  @override
  String get settingsSectionExport => 'Export Collection';

  @override
  String get settingsExportCsv => 'Export as CSV';

  @override
  String get settingsExportCsvSubtitle => 'Copy to clipboard — requires Pro';

  @override
  String get settingsExportJson => 'Export as JSON';

  @override
  String get settingsExportJsonSubtitle => 'Copy to clipboard — requires Pro';

  @override
  String msgCardsExported(int count, String format) {
    return '$count cards exported as $format (to clipboard)';
  }

  @override
  String get msgExportProRequired => 'Feature coming soon';

  @override
  String msgExportError(String error) {
    return 'Export error: $error';
  }

  @override
  String get settingsSectionSync => 'Synchronization';

  @override
  String get settingsResetSync => 'Reset Synchronization';

  @override
  String get settingsResetSyncSubtitle =>
      'Resolves duplicate items in the cloud';

  @override
  String get dlgResetSyncTitle => 'Reset Synchronization';

  @override
  String get dlgResetSyncMsg =>
      'This operation will deduplicate cards/albums/decks appearing twice, clean up the cloud, and reload the correct data.\n\nOnly proceed if you see duplicate items.';

  @override
  String get msgSyncRestoredSuccess => 'Synchronization restored successfully!';

  @override
  String get msgSyncStarting => 'Starting...';

  @override
  String get settingsSectionGeneral => 'General';

  @override
  String get settingsPushNotifications => 'Push Notifications';

  @override
  String get settingsPushNotificationsSubtitle =>
      'Receive notifications from the app';

  @override
  String get settingsNotifAppUpdates => 'App Updates';

  @override
  String get settingsNotifAppUpdatesSubtitle => 'New versions available';

  @override
  String get settingsNotifCatalogUpdates => 'Catalog Updates';

  @override
  String get settingsNotifCatalogUpdatesSubtitle =>
      'New cards and price updates';

  @override
  String get settingsLanguage => 'App Language';

  @override
  String get settingsLanguageDialogTitle => 'App Language';

  @override
  String get settingsCurrency => 'Currency';

  @override
  String get settingsCurrencyDialogTitle => 'Currency';

  @override
  String get settingsAppGuide => 'App Guide';

  @override
  String get settingsAppGuideSubtitle => 'Review the introductory tutorial';

  @override
  String get settingsSectionDanger => 'Danger Zone';

  @override
  String get settingsDeleteAccount => 'Delete Account';

  @override
  String get settingsDeleteAccountSubtitle =>
      'Permanently delete your account and all data';

  @override
  String get dlgDeleteAccountTitle => 'Delete Account';

  @override
  String get dlgDeleteAccountMsg =>
      'This action is irreversible.\n\nYour account and all associated data will be permanently deleted.';

  @override
  String get msgNotifPermissionDenied =>
      'Notification permission denied. Enable it in system settings.';

  @override
  String get msgNoCollectionToRestore => 'No unlocked collection to restore.';

  @override
  String get msgDeleteAccountRelogin =>
      'For security, sign out and sign back in before deleting your account.';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileNickname => 'Nickname';

  @override
  String get profileNicknameHint => 'Your display name';

  @override
  String get profileSaveNickname => 'Save Nickname';

  @override
  String get profileAvatarSection => 'Avatar';

  @override
  String get profileAvatarSubtitle =>
      'Unlock avatars by collecting cards. Each collection has its exclusive avatars.';

  @override
  String get profileGlobalAvatars => 'Global Avatars';

  @override
  String profileLevelLabel(int level) {
    return 'Level $level';
  }

  @override
  String get profileLevelMax => 'MAX Level';

  @override
  String get profileMaxLevelReached => 'You reached the maximum level!';

  @override
  String profileXpInfo(int xp, int xpToNext) {
    return '$xp total XP · $xpToNext XP to next level';
  }

  @override
  String get msgNicknameSaved => 'Nickname updated!';

  @override
  String get msgNicknameEmpty => 'Nickname cannot be empty';

  @override
  String get catalogTitle => 'Catalog';

  @override
  String get catalogSearchHint => 'Search by name or serial...';

  @override
  String get catalogLanguageTitle => 'Catalog Language';

  @override
  String get catalogLanguageUnavailable =>
      'Greyed-out languages are not yet available in the local catalog.';

  @override
  String get catalogLanguageNotAvailable => 'Not available';

  @override
  String catalogNoCatalogDownloaded(String name) {
    return '$name catalog has not been downloaded yet';
  }

  @override
  String get catalogDownloadPrompt =>
      'Download the catalog to browse and add cards to your collection.';

  @override
  String get catalogDownloadBtn => 'Download catalog';

  @override
  String get catalogDownloaded => 'Catalog downloaded successfully!';

  @override
  String get catalogDownloadBusy =>
      'A download is already in progress. Please wait.';

  @override
  String catalogDownloadError(String error) {
    return 'Download error: $error';
  }

  @override
  String get catalogLoadError => 'Loading error. Check your connection.';

  @override
  String get catalogNoCards => 'No cards found';

  @override
  String get catalogDownloadLabel => 'Download';

  @override
  String get catalogSelectAlbumTitle => 'Select Album';

  @override
  String get catalogNoAlbumAvailable => 'No album available. Create one first.';

  @override
  String get catalogLastUsed => 'Last used';

  @override
  String get catalogAddingProgress => 'Adding...';

  @override
  String catalogCardsProgress(int done, int total) {
    return '$done / $total cards processed';
  }

  @override
  String catalogAlbumFull(String name, int current, int max) {
    return 'Album \"$name\" is full ($current/$max).';
  }

  @override
  String catalogAlbumNearlyFull(int added, int total) {
    return 'Album nearly full: only $added/$total cards added.';
  }

  @override
  String catalogAddResult(int added, int updated, int doppioni) {
    return '$added added, $updated quantities updated, $doppioni duplicates';
  }

  @override
  String get catalogNoChange => 'No changes';

  @override
  String catalogAdded(int n) {
    return '$n added';
  }

  @override
  String catalogUpdatedQty(int n) {
    return '$n quantities updated';
  }

  @override
  String catalogDoppioni(int n) {
    return '$n duplicates';
  }

  @override
  String get catalogSelectAll => 'Select all';

  @override
  String catalogCardsSelected(int n) {
    return '$n cards selected';
  }

  @override
  String get catalogAddingN => 'Adding...';

  @override
  String catalogAddN(int n) {
    return 'Add $n';
  }

  @override
  String get catalogSetCompleted => 'Set completed!';

  @override
  String catalogSetCompletedMsg(String setName, int total, int total2) {
    return '\"$setName\" is complete ($total / $total2 cards).';
  }

  @override
  String get catalogMoveToAlbum =>
      'Do you want to move all cards in this set to a different album?';

  @override
  String get catalogMoveInAlbumLabel => 'Move to album';

  @override
  String get catalogKeepCurrentAlbum => 'Keep current album';

  @override
  String catalogCardsMoved(String setName) {
    return 'Cards from \"$setName\" moved!';
  }

  @override
  String get cardListSearchHint => 'Search by name, serial or rarity...';

  @override
  String get cardListViewTooltipList => 'List View';

  @override
  String get cardListViewTooltipGrid => 'Grid View';

  @override
  String get cardListAlbumOnly =>
      'You are viewing only the cards in this album';

  @override
  String get cardListEmptyAlbum =>
      'You haven\'t added any cards to this album yet.\nAdd cards from the Catalog by selecting this album.';

  @override
  String get cardListEmptyCollection =>
      'You haven\'t added any cards yet.\nUse the Catalog to add cards.';

  @override
  String get cardListNotInCollection => 'Not in collection — found in catalog';

  @override
  String get cardListNotInCatalog => 'Card not available in the catalog';

  @override
  String get cardListNotInCatalogMsg =>
      'This card is not yet in our catalog. You can report it and we\'ll add it as soon as possible.';

  @override
  String get cardListReportMissing => 'Report missing card';

  @override
  String get cardListDoppioneAdded => 'Duplicate added to \"Duplicates\" album';

  @override
  String get cardListAlbumCatalog => 'Catalog';

  @override
  String get cardListAlbumUnknown => 'Unknown';

  @override
  String get selectionSelectCards => 'Select cards';

  @override
  String selectionNSelected(int n) {
    return '$n selected';
  }

  @override
  String get selectionSelectAll => 'Select all';

  @override
  String get selectionDeselectAll => 'Deselect all';

  @override
  String get selectionAlbumBtn => 'Album';

  @override
  String get selectionDeckBtn => 'Deck';

  @override
  String get selectionDeleteBtn => 'Delete';

  @override
  String dlgDeleteNCardsTitle(int n) {
    return 'Delete $n cards';
  }

  @override
  String dlgDeleteNCardsMsg(int n) {
    return 'Do you want to delete the $n selected cards?';
  }

  @override
  String msgNCardsDeleted(int n) {
    return '$n cards deleted';
  }

  @override
  String get dlgMoveToAlbumTitle => 'Move to Album';

  @override
  String get dlgAddToDeckTitle => 'Add to Deck';

  @override
  String msgNCardsAddedToDeck(int n) {
    return '$n cards added to deck';
  }

  @override
  String get msgNoDeckAvailable => 'No deck available. Create a deck first.';

  @override
  String get dlgCapacityExceededTitle => 'Capacity Exceeded';

  @override
  String dlgCapacityExceededMsg(int current, int max) {
    return 'Will exceed maximum capacity ($current/$max). Proceed?';
  }

  @override
  String get btnProceed => 'Proceed';

  @override
  String get cardDetailDeleteTitle => 'Delete card';

  @override
  String cardDetailDeleteMsg(String name) {
    return 'Delete \"$name\" from the collection?';
  }

  @override
  String get cardDetailTooltipDelete => 'Delete';

  @override
  String get cardDetailPriceHistory => 'PRICE HISTORY';

  @override
  String get cardDetailAlbumSection => 'ALBUM';

  @override
  String get cardDetailMarketValue => 'MARKET VALUE';

  @override
  String get cardDetailDeckSection => 'DECK';

  @override
  String get cardDetailDescription => 'DESCRIPTION';

  @override
  String get cardDetailViewOnCardtrader => 'View on CardTrader';

  @override
  String get setDetailNoCards => 'No cards.';

  @override
  String get setDetailRetry => 'Retry';

  @override
  String get setDetailTabAll => 'All';

  @override
  String get setDetailTabOwned => 'Owned';

  @override
  String get setDetailTabMissing => 'Missing';

  @override
  String get setDetailLoadError => 'Loading error';

  @override
  String get nounCards => 'cards';

  @override
  String setCompletionTitle(String name) {
    return 'Expansions — $name';
  }

  @override
  String get setCompletionSearchHint => 'Search expansion...';

  @override
  String get deckListNewDeckTitle => 'New Deck';

  @override
  String get deckListNewDeckHint => 'e.g. AttackDeck';

  @override
  String get deckListNoDecks => 'No decks created.';

  @override
  String get dlgDeleteDeckTitle => 'Delete Deck';

  @override
  String dlgDeleteDeckMsg(String name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String msgDeckDeleted(String name) {
    return 'Deck \"$name\" deleted';
  }

  @override
  String get albumListNoAlbums => 'No albums created.';

  @override
  String get dlgDeleteAlbumTitle => 'Delete Album';

  @override
  String msgAlbumDeleted(String name) {
    return 'Album \"$name\" deleted';
  }

  @override
  String get albumNewAlbumHint => 'e.g. BaseCollection';

  @override
  String get albumCapacityHint => '100';

  @override
  String get albumDeckPageNoAlbums => 'No albums created.';

  @override
  String get albumDeckPageNoDecks => 'No decks created.';

  @override
  String get albumDeckPageAiDeckBuilder => 'AI Deck Builder';

  @override
  String get albumDeckPageNewDeck => 'New Deck';

  @override
  String get albumDeckPageNewAlbum => 'New Album';

  @override
  String get deckDetailSharePro => 'Share (Pro)';

  @override
  String get deckDetailShareProMsg =>
      'Deck sharing is available for Pro users only.';

  @override
  String get deckDetailShareTooltip => 'Share Deck';

  @override
  String get deckDetailShareTooltipPro => 'Share Deck (Pro)';

  @override
  String get deckDetailAddBeforeShare => 'Add cards to the deck before sharing';

  @override
  String get deckDetailSharedTitle => 'Deck Shared!';

  @override
  String get deckDetailCodeCopied => 'Code copied!';

  @override
  String get deckDetailInDeck => 'In Deck';

  @override
  String get deckDetailInDeckHint => 'Detail • − to remove';

  @override
  String get deckDetailOwned => 'Owned';

  @override
  String get deckDetailOwnedHint => 'Tap to add';

  @override
  String get deckDetailSearchHint => 'Search card...';

  @override
  String get wishlistTitle => 'Wishlist';

  @override
  String get wishlistAddCard => 'Add card';

  @override
  String get wishlistAddToWishlistTitle => 'Add to Wishlist';

  @override
  String wishlistItemRemovedMsg(String name) {
    return '$name removed from Wishlist';
  }

  @override
  String get wishlistUndoRemove => 'Undo';

  @override
  String get dlgTargetPriceTitle => 'Target price';

  @override
  String dlgTargetPriceMsg(String name) {
    return 'Set target price for $name';
  }

  @override
  String get dlgTargetPriceLabel => 'Price (€)';

  @override
  String get dlgRemoveWishlistTitle => 'Remove from Wishlist';

  @override
  String dlgRemoveWishlistMsg(String name) {
    return 'Remove \"$name\" from wishlist?';
  }

  @override
  String get btnRemove => 'Remove';

  @override
  String get wishlistNdLabel => 'N/A';

  @override
  String get wishlistCatalogSearchTitle => 'Search catalog';

  @override
  String get wishlistCatalogSearchHint => 'Search by name or set code...';

  @override
  String wishlistItemAddedMsg(String name) {
    return '$name added to Wishlist';
  }

  @override
  String get wishlistAddToWishlistTooltip => 'Add to Wishlist';

  @override
  String get wishlistNoResults => 'No results found';

  @override
  String get statsTitle => 'Statistics';

  @override
  String get statsPerCollection => 'By Collection';

  @override
  String statsCardsCount(int n) {
    return '$n cards';
  }

  @override
  String get statsPerRarity => 'By Rarity (top 10)';

  @override
  String get statsSetsSection => 'Expansions';

  @override
  String get statsTabCollection => 'Collection';

  @override
  String get statsTabGlobal => 'Global';

  @override
  String get roiTitle => 'ROI Analysis';

  @override
  String get roiPortfolio => 'Portfolio';

  @override
  String get roiTotalValue => 'Total value';

  @override
  String get roiSection => 'ROI';

  @override
  String get roiInvested => 'Invested';

  @override
  String get roiValueCt => 'CT Value';

  @override
  String get roiGain => 'Gain';

  @override
  String get roiPercent => 'ROI %';

  @override
  String get roiTrackedCards => 'Tracked cards';

  @override
  String get roiPortfolioTitle => 'Portfolio Value';

  @override
  String get roiPurchasePriceTitle => 'Purchase price';

  @override
  String get roiPurchasePriceLabel => 'Price paid per copy (€)';

  @override
  String roiAddPricesBtn(String label) {
    return 'Add $label prices';
  }

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notifClearAllTitle => 'Clear all';

  @override
  String get notifClearAllMsg => 'Do you want to delete all notifications?';

  @override
  String get notifClearAllTooltip => 'Clear all';

  @override
  String get notifDownloadBtn => 'Download';

  @override
  String get newsTitle => 'News';

  @override
  String get newsNetworkError => 'Network error';

  @override
  String get newsNetworkErrorSubtitle => 'Check your connection and try again.';

  @override
  String get newsNoNews => 'No news';

  @override
  String get newsNoNewsSubtitle => 'There are no updates for your collections.';

  @override
  String get newsRefreshTooltip => 'Refresh';

  @override
  String get newsHighlight => 'FEATURED';

  @override
  String get newsReadMore => 'Read more';

  @override
  String get newsReadAll => 'Read all';

  @override
  String get newsShowLess => 'Show less';

  @override
  String get cardScannerTitle => 'Scan Card';

  @override
  String get cardScannerLimitTitle => 'Scan limit reached';

  @override
  String cardScannerNoAlbum(String collection) {
    return 'No album found for $collection';
  }

  @override
  String cardScannerCardAdded(String name) {
    return '$name added to collection!';
  }

  @override
  String get cardScannerAddToCollection => 'Add to Collection';

  @override
  String get cardScannerScanAnother => 'Scan another card';

  @override
  String get cardScannerOpenCamera => 'Open Camera';

  @override
  String get cardScannerGoToPro => 'Go Pro';

  @override
  String get aiDeckBuilderTitle => 'AI Deck Builder';

  @override
  String get aiDeckBuilderPromptLabel => 'Describe your strategy';

  @override
  String get aiDeckBuilderPromptHint =>
      'e.g. \"An aggressive Dragon deck with fast attacks and powerful fusions. I want to use my Blue-Eyes and a mix of support cards.\"';

  @override
  String get aiDeckBuilderGenerateBtn => 'Generate Deck with AI';

  @override
  String get aiDeckBuilderGenerating => 'Analysing…';

  @override
  String get aiDeckBuilderSaveBtn => 'Save Deck';

  @override
  String aiDeckBuilderDeckSaved(String name, int n) {
    return 'Deck \"$name\" saved! ($n cards added)';
  }

  @override
  String aiDeckBuilderSaveError(String error) {
    return 'Save error: $error';
  }

  @override
  String get aiDeckBuilderMainLabel => 'Main';

  @override
  String get aiDeckBuilderExtraLabel => 'Extra';

  @override
  String get aiDeckBuilderOwnedLabel => 'Owned';

  @override
  String get aiDeckBuilderGoToPro => 'Go Pro';

  @override
  String get aiDeckBuilderNotOwned => 'not owned';

  @override
  String get proTitle => 'Pro';

  @override
  String get proNotAvailable => 'Subscription not available at the moment.';

  @override
  String get proWelcomeMsg => 'Welcome to the Pro plan!';

  @override
  String get proPurchasesRestored => 'Purchases restored!';

  @override
  String get proNoPurchasesToRestore => 'No purchases to restore.';

  @override
  String get proMonthlyLabel => 'Monthly';

  @override
  String get proYearlyLabel => 'Yearly';

  @override
  String get proYearlyTitle => 'Yearly Plan';

  @override
  String get proMonthlyTitle => 'Monthly Plan';

  @override
  String get donationsTitle => 'Support the Project';

  @override
  String get msgCantOpenLink => 'Unable to open link';

  @override
  String get supportTitle => 'Support';

  @override
  String get supportReportBugTitle => 'Report a Problem';

  @override
  String get supportReportBugSubtitle =>
      'Did you encounter a bug or unexpected behaviour?';

  @override
  String get supportMissingCardsTitle => 'Missing Cards';

  @override
  String get supportMissingCardsSubtitle =>
      'Report cards missing or with incorrect data in the catalog.';

  @override
  String get supportSuggestionTitle => 'Suggestion';

  @override
  String get supportSuggestionSubtitle =>
      'Have an idea to improve the app? Write to us!';

  @override
  String get supportSupportProject => 'Support the project';

  @override
  String get msgNoEmailClient => 'No email client found';

  @override
  String get tutorialPageTitle => 'App Guide';

  @override
  String get tutorialStartBtn => 'Start Tutorial';

  @override
  String get tutorialMaybeLater => 'Maybe later';

  @override
  String get sharedDeckTitle => 'Shared Deck';

  @override
  String get sharedDeckNoCards => 'You don\'t own any cards from this deck';

  @override
  String sharedDeckImported(int n) {
    return 'Deck imported! ($n cards added)';
  }

  @override
  String get sharedDeckCodeHint => 'XXXXXX';

  @override
  String get sharedDeckCodeCopied => 'Code copied!';

  @override
  String sharedDeckByOwner(String owner, String collection, int total) {
    return 'by $owner · $collection · $total cards';
  }

  @override
  String get adminHomeCatalogTitle => 'Catalog Management';

  @override
  String get adminHomePublishTooltip => 'Publish changes';

  @override
  String get adminHomeReloadTooltip => 'Reload';

  @override
  String get adminHomeNewCard => 'New Card';

  @override
  String get adminHomeSearchHint => 'Search card (name, archetype, ID)...';

  @override
  String get adminHomeViewBtn => 'View';

  @override
  String get adminHomeSearchPrompt => 'Search a card or add a new one';

  @override
  String get adminCardAdded => 'Card added to changes';

  @override
  String get adminEditAdded => 'Edit added';

  @override
  String get adminDeleteConfirmTitle => 'Confirm deletion';

  @override
  String adminDeleteConfirmMsg(String name) {
    return 'Do you want to delete \"$name\"?\nThe card will be removed at the next update.';
  }

  @override
  String get adminDeleteAdded => 'Deletion added to changes';

  @override
  String get adminPendingChangesTitle => 'Pending changes';

  @override
  String get adminPublishTitle => 'Publish changes';

  @override
  String get adminPublishedSuccess => 'Published successfully';

  @override
  String get adminCollectionTitle => 'Publish Changes';

  @override
  String adminCollectionPublishMsg(int n) {
    return 'Publish $n changes to Firestore?';
  }

  @override
  String get adminCollectionPublishSuccess => 'Changes published successfully!';

  @override
  String get adminCollectionSearchHint => 'Search by name, ID or archetype...';

  @override
  String get adminCollectionNoCards => 'No cards found';

  @override
  String get adminCollectionPublishTooltip => 'Publish changes';

  @override
  String get adminCollectionReloadTooltip => 'Reload from Firestore';

  @override
  String adminCollectionDeleteMsg(String name) {
    return 'Delete \"$name\" from the catalog?';
  }

  @override
  String get adminCollectionCardEditedPending => 'Edit pending publication';

  @override
  String get adminCollectionCardAddedPending =>
      'Card added — pending publication';

  @override
  String get adminExcelTitle => 'Export / Import Excel';

  @override
  String get adminExcelImportConfirmTitle => 'Confirm import';

  @override
  String get adminExcelExportTitle => 'Export to Excel';

  @override
  String get adminExcelExportSubtitle =>
      'Generate an .xlsx file with two sheets:\n';

  @override
  String get adminExcelExportBtn => 'Export and Share';

  @override
  String get adminExcelImportTitle => 'Import from Excel';

  @override
  String get adminExcelImportSubtitle =>
      'Select an .xlsx file exported from this app with ';

  @override
  String get adminExcelSelectFileBtn => 'Select .xlsx file';

  @override
  String adminExcelApplyBtn(int n) {
    return 'Apply $n changes to Firestore';
  }

  @override
  String get adminSetsTitle => 'Expansions & Rarities';

  @override
  String get adminSetsSyncTooltip => 'Sync to Firestore';

  @override
  String get adminSetsSynced => 'Translations synced to Firestore';

  @override
  String get adminSetsEditTooltip => 'Edit translations';

  @override
  String get adminUsersTitle => 'User Management';

  @override
  String get adminUsersReloadTooltip => 'Reload';

  @override
  String get adminUsersNoUsers => 'No users found';

  @override
  String get adminUsersFilterAll => 'All';

  @override
  String get adminUsersFilterAdmin => 'Admin';

  @override
  String get adminUsersFilterUsers => 'Users';

  @override
  String get adminUsersRoleUpdated => 'Role updated successfully';

  @override
  String adminUsersStatusUpdated(String status) {
    return 'Status updated: $status';
  }

  @override
  String get adminUsersDeletedSuccess => 'User deleted successfully';

  @override
  String get adminUsersConfirmRoleTitle => 'Confirm role change';

  @override
  String get adminUsersConfirmDeleteTitle => 'Confirm deletion';

  @override
  String get updateDialogRequired => 'Update required';

  @override
  String get updateDialogAvailable => 'New version available';

  @override
  String get updateDialogForcedMsg =>
      'This version is no longer supported. Update to continue using the app.';

  @override
  String get updateDialogOptionalMsg =>
      'A new version with improvements and fixes is available.';

  @override
  String get updateDialogWhatsNew => 'What\'s new';

  @override
  String get updateDialogUpdateNow => 'Update now';

  @override
  String get updateDialogNotNow => 'Not now';

  @override
  String get cardDialogSelectAlbumLabel => 'Select Album';

  @override
  String get cardDialogDeck => 'Deck';

  @override
  String get cardDialogDescription => 'Description';

  @override
  String get cardDialogDeleteBtn => 'Delete';

  @override
  String get cardDialogCloseBtn => 'Close';

  @override
  String get cardDialogSaveBtn => 'Save';

  @override
  String cardDialogAddToTitle(String collection) {
    return 'Add to $collection';
  }

  @override
  String get cardDialogNoAlbumTitle => 'No Album';

  @override
  String get cardDialogNoAlbumMsg =>
      'You haven\'t created an album for this collection yet. Create an album from the Collection section.';

  @override
  String get cardDialogManageAlbum => 'Manage Album';

  @override
  String get cardDialogSelectFromCatalog => 'Select a card from the catalog';

  @override
  String get cardDialogSelectAlbum => 'Select an album';

  @override
  String get cardDialogNameEmpty => 'The card name cannot be empty.';

  @override
  String get cardDialogQtyMin => 'Quantity must be at least 1.';

  @override
  String get cardDialogAlbumFullTitle => 'Album full';

  @override
  String get cardDialogDoppionAdded =>
      'Card already in collection → added to Duplicates';

  @override
  String get cardItemNdLabel => 'N/A';

  @override
  String get undoBarUndo => 'Undo';

  @override
  String get adminCardEditSaveBtn => 'Save Card';

  @override
  String get adminCardEditImageHint => 'Upload from device →';

  @override
  String get adminCardEditImageTooltip => 'Upload from device';

  @override
  String get adminCardEditUploadFailed => 'Upload failed or timeout';

  @override
  String get adminCardEditStatsNA =>
      'Statistics not applicable for this collection.';

  @override
  String get adminCardEditSpellTrapNA =>
      'Spell and Trap cards have no monster stats';

  @override
  String get adminCardEditNoAttacks => 'No attacks.';

  @override
  String get adminCardEditNoAbilities => 'No abilities.';

  @override
  String get adminCardEditSetsNoData => 'No sets for this language.';

  @override
  String get adminCardEditAddSetTooltip => 'Add set';

  @override
  String get adminCardEditNewAttackTitle => 'New Attack';

  @override
  String get adminCardEditEditAttackTitle => 'Edit Attack';

  @override
  String get adminCardEditNewAbilityTitle => 'New Ability';

  @override
  String get adminCardEditEditAbilityTitle => 'Edit Ability';

  @override
  String get adminCardEditGenerateFromEn => 'Generate from EN';

  @override
  String get adminHomeSessions => 'Session expired. Log out and sign in again.';

  @override
  String get adminHomeOperationCancelled => 'Operation cancelled.';

  @override
  String get adminHomeManageProUsers => 'Manage Pro Users';

  @override
  String get adminHomeCtData => 'Catalog';

  @override
  String get adminHomeCtBlueprint => 'CT blueprint';

  @override
  String get adminHomeCtWithPrice => 'With price';

  @override
  String get adminHomeCtDiff => 'Diff.';

  @override
  String get adminHomeCtNoData => 'No CT data in local cache.';

  @override
  String get adminHomeFilterLabel => 'Filter: ';

  @override
  String get collectionSummaryUnique => 'Unique';

  @override
  String get collectionSummaryDuplicates => 'Duplicates';

  @override
  String get collectionSummaryTotal => 'Total';

  @override
  String get collectionSummaryValue => 'Value';

  @override
  String get statsTotalCards => 'Total Cards';

  @override
  String get statsDuplicateCards => 'Duplicates';

  @override
  String get statsEstimatedValue => 'Estimated Value';

  @override
  String get statsValueTrend => 'Value Trend';

  @override
  String setCompletionNCards(int n) {
    return '$n cards';
  }

  @override
  String setCompletionTotalSets(int n) {
    return '$n expansions total';
  }

  @override
  String setCompletionCompletedStats(int completed, int inProgress) {
    return '$completed completed · $inProgress in progress';
  }

  @override
  String setCompletionOutOf(int n) {
    return 'out of $n expansions';
  }

  @override
  String setCompletionTabInProgress(int n) {
    return 'In progress ($n)';
  }

  @override
  String setCompletionTabCompleted(int n) {
    return 'Completed ($n)';
  }

  @override
  String setCompletionTabAvailable(int n) {
    return 'Available ($n)';
  }

  @override
  String get setCompletionNoCatalog =>
      'Catalog not downloaded yet.\nDownload the catalog from Settings.';

  @override
  String get setCompletionEmptyInProgress => 'No expansions in progress.';

  @override
  String get setCompletionEmptyCompleted => 'No expansions completed.';

  @override
  String get setCompletionEmptyAvailable => 'No expansions available.';

  @override
  String deckDetailCardCount(int n) {
    return '$n cards in deck';
  }

  @override
  String get deckDetailEmptyDeck =>
      'No cards — add them\nfrom your owned cards below';

  @override
  String get deckDetailShareCodeHint => 'Share this code with other players:';

  @override
  String get deckDetailCodeExpiry =>
      'The code is valid until manually removed.';

  @override
  String get newsCollectionAll => 'All';

  @override
  String get newsDateToday => 'Today';

  @override
  String get newsDateYesterday => 'Yesterday';

  @override
  String newsDateDaysAgo(int n) {
    return '$n days ago';
  }

  @override
  String get notifSectionAvailableUpdates => 'Available Updates';

  @override
  String get notifSectionHistory => 'History';

  @override
  String get notifFirstDownload => 'First download available';

  @override
  String notifPartialUpdate(int chunks) {
    return 'Partial update ($chunks chunks)';
  }

  @override
  String get notifFullUpdate => 'Full update available';

  @override
  String get notifLater => 'Later';

  @override
  String get notifNoNotifications => 'No notifications';

  @override
  String get notifNewBadge => 'NEW';

  @override
  String get notifPricesUpdated => 'Market prices updated';

  @override
  String notifNewCardsAdded(int n) {
    return '+$n new cards added';
  }

  @override
  String get scannerFrameInstruction => 'Frame the card and press Scan';

  @override
  String get scannerScanBtn => 'Scan';

  @override
  String get btnAccept => 'Accept';

  @override
  String get ctNoPriceAvailable => 'No price currently available.';

  @override
  String get ctSearchOnCardtrader => 'Search on CardTrader ↗';

  @override
  String ctLastPrice(String date) {
    return 'Last: $date';
  }

  @override
  String get ctHistoryInsufficientData =>
      'Insufficient data for the selected period.';

  @override
  String get ctHistoryWillPopulate =>
      'The chart will populate with each price sync.';

  @override
  String get collectionChartUpdateNote =>
      'The chart updates every time\nyou visit this page.';

  @override
  String get splashDefaultCollector => 'Collector';

  @override
  String get proYearPeriod => 'year';

  @override
  String proYearSubtext(String price) {
    return '€$price/month — save 30%';
  }

  @override
  String get proMonthPeriod => 'month';

  @override
  String get proMonthSubtext => 'Monthly automatic renewal';

  @override
  String get roiPortfolioDescription =>
      'Here you can see the total value of the cards you own. Enter the purchase price of each card to calculate your ROI and discover how much your investment has grown.';

  @override
  String get roiPurchasePriceHelper => 'Enter the price per single copy';

  @override
  String get btnRestore => 'Restore';

  @override
  String get settingsSectionLegal => 'Legal';

  @override
  String get settingsPrivacyPolicy => 'Privacy Policy';

  @override
  String get settingsPrivacyPolicySubtitle =>
      'How we collect and use your data';

  @override
  String get settingsPrivacyOpenError =>
      'Unable to open the page. Please try again later.';

  @override
  String get settingsExportExcel => 'Export to Excel';

  @override
  String get settingsExportExcelSubtitle =>
      'Download your collection as an .xlsx file';

  @override
  String get settingsUpgradePro => 'Go Pro';

  @override
  String get settingsUpgradeProSubtitle => 'Unlock all premium features';

  @override
  String get settingsResetStarting => 'Starting...';

  @override
  String get proPromoBadge => 'LAUNCH OFFER';

  @override
  String get proPromoPriceFrom => 'from €1.67/month';

  @override
  String get proPromoCta => 'Discover Pro';

  @override
  String get proPromoDismiss => 'No thanks';

  @override
  String get proBenefitStats => 'Advanced stats & ROI';

  @override
  String get proBenefitExcel => 'Excel export';

  @override
  String get proBenefitAi => 'AI Deck Builder (Yu-Gi-Oh!)';

  @override
  String get proBenefitAlerts => 'Wishlist price alerts';

  @override
  String get proBenefitNoAds => 'No ads';

  @override
  String get proBenefitShare => 'Deck sharing';

  @override
  String get proHeaderSubtitle => 'Take your collection to the next level';

  @override
  String get proLaunchBadge => 'LAUNCH DISCOUNT — LIMITED OFFER';

  @override
  String get proAllIncluded => 'EVERYTHING INCLUDED IN PRO';

  @override
  String get proChoosePlan => 'CHOOSE YOUR PLAN';

  @override
  String get proSemiannualLabel => 'Semiannual';

  @override
  String get proSemiannualPeriod => '6 months';

  @override
  String get proMonthlyNote => 'Flexible, cancel anytime';

  @override
  String proSaveNote(String price, String percent) {
    return '€$price/month · save $percent%';
  }

  @override
  String get proLaunchTag => 'LAUNCH';

  @override
  String get proProcessing => 'Processing...';

  @override
  String get proSubscribeNow => 'Subscribe now';

  @override
  String get proAlreadySubscribed => '✓ You\'re already a Pro subscriber!';

  @override
  String get proFooterCancel => 'Cancel anytime · No commitment';

  @override
  String get proFooterPayment =>
      'Payment will be charged via App Store / Google Play';

  @override
  String get proRestorePurchases => 'Restore purchases';

  @override
  String get proFeatExcelTitle => 'Excel Export';

  @override
  String get proFeatExcelSub => 'Download your collection as .xlsx';

  @override
  String get proFeatStatsTitle => 'Advanced Statistics';

  @override
  String get proFeatStatsSub => 'Value, rarity, trends over time';

  @override
  String get proFeatRoiTitle => 'ROI & Investment';

  @override
  String get proFeatRoiSub => 'Calculate your collection\'s return';

  @override
  String get proFeatShareTitle => 'Deck Sharing';

  @override
  String get proFeatShareSub => 'Generate shareable links for your decks';

  @override
  String get proFeatAiTitle => 'AI Deck Builder';

  @override
  String get proFeatAiSub => 'Automatic builder for Yu-Gi-Oh!';

  @override
  String get proFeatAlertsTitle => 'Wishlist Price Alerts';

  @override
  String get proFeatAlertsSub => 'Notifications when the price drops';

  @override
  String get proFeatNoAdsTitle => 'No Ads';

  @override
  String get proFeatNoAdsSub => 'A clean, uninterrupted experience';

  @override
  String get proFeatSupportTitle => 'Priority Support';

  @override
  String get proFeatSupportSub => 'Guaranteed response within 24h';

  @override
  String get supportHeaderTitle => 'How can we help?';

  @override
  String get supportHeaderSubtitle => 'Contact us for any issue or suggestion.';

  @override
  String get supportSectionContact => 'CONTACT US';

  @override
  String get supportSectionOpinion => 'YOUR OPINION MATTERS';

  @override
  String get supportSectionFaq => 'FAQ';

  @override
  String get supportSectionOther => 'OTHER';

  @override
  String get supportReviewTitle => 'Leave a review';

  @override
  String get supportReviewSubtitle =>
      'Enjoying the app? Help us with a store rating';

  @override
  String get supportShareTitle => 'Share Deck Master';

  @override
  String get supportShareSubtitle => 'Recommend the app to other collectors';

  @override
  String get supportSuggestionsTitle => 'Suggestions';

  @override
  String get supportSuggestionsSubtitle =>
      'Have ideas to improve the app? Write to us';

  @override
  String get supportGuideTitle => 'Feature guide';

  @override
  String get supportGuideSubtitle =>
      'Discover step by step how to use every app feature';

  @override
  String get supportTutorialTitle => 'Replay the tutorial';

  @override
  String get supportTutorialSubtitle => 'Watch the app intro again';

  @override
  String get supportBugEmailSubject => 'Issue Report - Deck Master';

  @override
  String supportBugEmailBody(String email) {
    return 'Hi,\n\nI encountered the following issue:\n\n[Describe the issue here]\n\n---\nAccount: $email';
  }

  @override
  String get supportMissingEmailSubject => 'Missing Cards - Deck Master';

  @override
  String supportMissingEmailBody(String email) {
    return 'Hi,\n\nI\'d like to report the following missing/incorrect cards:\n\nCollection: [Yu-Gi-Oh! / One Piece / ...]\nCard: [Card name]\nSet: [Set Code]\nReason: [Missing / Wrong data / Wrong image]\n\n---\nAccount: $email';
  }

  @override
  String get supportReviewEmailSubject => 'Review - Deck Master';

  @override
  String supportReviewEmailBody(String email) {
    return 'Hi,\n\nI\'d like to leave the following feedback about the app:\n\nRating: [⭐⭐⭐⭐⭐]\n\n[Write your opinion here]\n\n---\nAccount: $email';
  }

  @override
  String get supportSuggestEmailSubject => 'Suggestions - Deck Master';

  @override
  String supportSuggestEmailBody(String email) {
    return 'Hi,\n\nI\'d like to suggest the following feature or improvement:\n\n[Describe your suggestion here]\n\n---\nAccount: $email';
  }

  @override
  String get supportShareText =>
      '🃏 I manage my card collection with Deck Master!\n\nIt supports Yu-Gi-Oh!, Pokémon, One Piece, Magic and many other TCGs. Updated prices, scanner, deck builder and much more.\n\nDownload it on the App Store and Google Play: search \"Deck Master TCG\"';

  @override
  String get supportFaqQ1 => 'How do I add a card to my collection?';

  @override
  String get supportFaqA1 =>
      'You can add cards in three ways: search the Catalog and tap \"Add\", use the Scanner to photograph the card, or tap a card in the set details. Specify the quantity and confirm.';

  @override
  String get supportFaqQ2 => 'How does the Wishlist work?';

  @override
  String get supportFaqA2 =>
      'Tap the ❤ on any card to add it to your Wishlist. You can set a target price: you\'ll get a push notification when the price drops below your threshold.';

  @override
  String get supportFaqQ3 => 'How do I build a deck?';

  @override
  String get supportFaqA3 =>
      'Go to your collection, select the \"Deck\" tab and tap + to create a new deck. Open the deck and add cards from the \"Owned Cards\" section at the bottom.';

  @override
  String get supportFaqQ4 => 'How do I sync data across multiple devices?';

  @override
  String get supportFaqA4 =>
      'Syncing happens automatically when you\'re connected. Sign in with the same account on each device. You can also force it manually from Settings → Sync.';

  @override
  String get supportFaqQ5 => 'What is the Pro plan?';

  @override
  String get supportFaqA5 =>
      'The Pro plan unlocks: Excel export, advanced statistics, ROI, deck sharing, AI builder for Yu-Gi-Oh! and no ads. You\'ll find it in Settings → Go Pro.';

  @override
  String get supportFaqQ6 => 'How does the scanner work?';

  @override
  String get supportFaqA6 =>
      'Tap the scanner icon at the top. Frame the card with the camera in good lighting and hold it steady. The app recognizes it automatically and offers to add it to your collection.';

  @override
  String get supportFaqQ7 => 'Are prices up to date?';

  @override
  String get supportFaqA7 =>
      'Yes, prices are synced daily from CardTrader. To update manually, go to Settings → Sync and tap \"Update Prices\".';

  @override
  String get guideAppBarTitle => 'Feature Guide';

  @override
  String get guideHeaderTitle => 'How Deck Master works';

  @override
  String get guideHeaderSubtitle =>
      'Tap a feature to discover how to use it step by step.';

  @override
  String get guideCollectionsTitle => 'Collections';

  @override
  String get guideCollectionsDesc =>
      'Each collection represents a card game (Yu-Gi-Oh!, Pokémon, etc.). Unlock the collections you own to start managing them.';

  @override
  String get guideCollectionsStep1 => 'Go to Settings → Manage Collections';

  @override
  String get guideCollectionsStep2 => 'Enable the collections you own';

  @override
  String get guideCollectionsStep3 =>
      'Each collection will appear in the main menu';

  @override
  String get guideCollectionsStep4 =>
      'You can switch the active collection from the selector at the top';

  @override
  String get guideAddTitle => 'Adding Cards';

  @override
  String get guideAddDesc =>
      'There are three ways to add cards to your collection: manually from the catalog, via scanner, or by importing from a file.';

  @override
  String get guideAddStep1 =>
      'Catalog: search for the card, tap \"Add\" and enter the quantity';

  @override
  String get guideAddStep2 =>
      'Scanner: frame the card with the camera for automatic recognition';

  @override
  String get guideAddStep3 =>
      'Use the filter to search by name, set or serial code';

  @override
  String get guideAddStep4 =>
      'Added cards appear in your collection right away';

  @override
  String get guideScannerTitle => 'Card Scanner';

  @override
  String get guideScannerDesc =>
      'Photograph a card with the camera to recognize it automatically and add it to your collection in one tap.';

  @override
  String get guideScannerStep1 => 'Tap the scanner icon in the top bar';

  @override
  String get guideScannerStep2 =>
      'Frame the card well — hold the camera steady';

  @override
  String get guideScannerStep3 =>
      'The app recognizes the card and shows its details';

  @override
  String get guideScannerStep4 =>
      'Confirm the quantity and add to your collection';

  @override
  String get guideScannerStep5 =>
      'Works best with good lighting and a non-reflective card';

  @override
  String get guideCatalogTitle => 'Catalog & Prices';

  @override
  String get guideCatalogDesc =>
      'The catalog shows all available cards with prices updated from CardTrader. You can browse, filter and add directly from the list.';

  @override
  String get guideCatalogStep1 => 'Select the collection and tap \"Catalog\"';

  @override
  String get guideCatalogStep2 => 'Use the search bar to find a specific card';

  @override
  String get guideCatalogStep3 => 'Prices update automatically every day';

  @override
  String get guideCatalogStep4 =>
      'Tap the ❤ to add to your Wishlist directly from the catalog';

  @override
  String get guideCatalogStep5 =>
      'Tap a card to see full details and prices per rarity';

  @override
  String get guideAlbumTitle => 'Albums';

  @override
  String get guideAlbumDesc =>
      'Albums let you organize the cards in your collection into virtual binders, with a customizable maximum capacity.';

  @override
  String get guideAlbumStep1 => 'In your collection, go to the \"Album\" tab';

  @override
  String get guideAlbumStep2 =>
      'Tap + to create a new album and set its name and capacity';

  @override
  String get guideAlbumStep3 => 'Open an album to view the cards it contains';

  @override
  String get guideAlbumStep4 =>
      'Add cards to the album from your main collection';

  @override
  String get guideAlbumStep5 =>
      'Use the counters to track how many cards you\'ve added';

  @override
  String get guideDeckTitle => 'Deck Builder';

  @override
  String get guideDeckDesc =>
      'Build and manage your game decks. Track every card, check the composition and share decks with other players.';

  @override
  String get guideDeckStep1 => 'Go to the \"Deck\" tab of your collection';

  @override
  String get guideDeckStep2 => 'Tap + to create a new deck';

  @override
  String get guideDeckStep3 =>
      'Open the deck and add cards from the \"Owned Cards\" section';

  @override
  String get guideDeckStep4 =>
      'Use the share button to generate a shareable link (Pro)';

  @override
  String get guideDeckStep5 =>
      'For Yu-Gi-Oh! you can use the AI builder for automatic suggestions';

  @override
  String get guideWishlistTitle => 'Wishlist & Price Alerts';

  @override
  String get guideWishlistDesc =>
      'Save the cards you want to buy and get notifications when the price drops below your set threshold.';

  @override
  String get guideWishlistStep1 =>
      'Tap the ❤ on any card to add it to your Wishlist';

  @override
  String get guideWishlistStep2 =>
      'Open the Wishlist from the profile menu at the top right';

  @override
  String get guideWishlistStep3 => 'Set a target price for each card';

  @override
  String get guideWishlistStep4 =>
      'You\'ll get a push notification when the price drops';

  @override
  String get guideWishlistStep5 =>
      'Remove the card from the Wishlist once purchased';

  @override
  String get guideStatsTitle => 'Statistics & ROI';

  @override
  String get guideStatsDesc =>
      'Track the total value of your collection over time and calculate your investment return with detailed charts.';

  @override
  String get guideStatsStep1 =>
      'Tap the chart icon in the top bar for statistics';

  @override
  String get guideStatsStep2 => 'View total value, cards by rarity and trends';

  @override
  String get guideStatsStep3 =>
      'ROI compares the estimated purchase cost with the current value';

  @override
  String get guideStatsStep4 =>
      'Data updates automatically with every price sync';

  @override
  String get guideStatsStep5 => 'Available only with the Pro plan';

  @override
  String get guideNotifTitle => 'Notifications';

  @override
  String get guideNotifDesc =>
      'Deck Master alerts you when prices change, when there are catalog updates or new features available.';

  @override
  String get guideNotifStep1 =>
      'Enable notifications in Settings → Notifications';

  @override
  String get guideNotifStep2 =>
      'Price notifications arrive when a Wishlist item drops';

  @override
  String get guideNotifStep3 =>
      'You can see all past notifications in the Notifications section';

  @override
  String get guideNotifStep4 => 'Tap a notification to go straight to the card';

  @override
  String get guideExportTitle => 'Excel Export';

  @override
  String get guideExportDesc =>
      'Export your entire collection to an Excel file (.xlsx) for external analysis, backup or sharing with other collectors.';

  @override
  String get guideExportStep1 => 'Go to Settings → Export';

  @override
  String get guideExportStep2 => 'Tap \"Export to Excel\"';

  @override
  String get guideExportStep3 =>
      'The file is generated with Name, Code, Collection, Rarity, Quantity and Value';

  @override
  String get guideExportStep4 =>
      'Choose where to save or share the file from the system panel';

  @override
  String get guideExportStep5 => 'Available only with the Pro plan';

  @override
  String get guideSyncTitle => 'Cloud Sync';

  @override
  String get guideSyncDesc =>
      'Your data is automatically synced across all your devices through your account. You\'ll never lose your collection.';

  @override
  String get guideSyncStep1 =>
      'Sync happens automatically at startup and after every change';

  @override
  String get guideSyncStep2 => 'Go to Settings → Sync to force it manually';

  @override
  String get guideSyncStep3 =>
      'If you see the ⚠️ icon there\'s a conflict: choose which version to keep';

  @override
  String get guideSyncStep4 =>
      'Works offline too: changes sync when the connection returns';

  @override
  String dlgDeleteAlbumMsg(String name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String dlgDeleteAlbumWithCardsMsg(String name, int count) {
    return 'Are you sure you want to delete \"$name\"?\n\nAll $count cards it contains will also be deleted.\n\nThis action cannot be undone.';
  }

  @override
  String get comingSoonTitle => 'Coming soon';

  @override
  String get comingSoonMsg => 'Feature under development, coming soon!';

  @override
  String get msgNameRequired => 'Name is required';

  @override
  String get downloadStarting => 'Starting...';

  @override
  String get downloadTitle => 'Deck Master — Download';

  @override
  String get tutorialBtnSkip => 'Skip';

  @override
  String get tutorialBtnNext => 'Next';

  @override
  String get tutorialBtnStart => 'Start!';

  @override
  String get tutorialSlide1Title => 'Welcome to Deck Master';

  @override
  String get tutorialSlide1Desc =>
      'Your app to manage, value and analyze your collectible card collection.\n\nIt supports 13 TCGs: Yu-Gi-Oh!, Pokémon, One Piece, Magic and many more.';

  @override
  String get tutorialSlide2Title => 'Your Collections';

  @override
  String get tutorialSlide2Desc =>
      'Unlock the collections you own. For each collection you can add cards, browse the full catalog and build decks.';

  @override
  String get tutorialSlide3Title => 'Card Catalog';

  @override
  String get tutorialSlide3Desc =>
      'Browse the full catalog with prices updated from CardTrader.\n\nTap the ❤️ on a card to add it to your Wishlist directly from the catalog.';

  @override
  String get tutorialSlide4Title => 'Card Scanner';

  @override
  String get tutorialSlide4Desc =>
      'Frame a card with the camera to recognize it automatically and add it to your collection in one click.';

  @override
  String get tutorialSlide5Title => 'Wishlist & Price Alerts';

  @override
  String get tutorialSlide5Desc =>
      'Add the cards you want to buy to your Wishlist. Set a target price and get a notification when the price drops below your threshold.';

  @override
  String get tutorialSlide6Title => 'Analytics & ROI';

  @override
  String get tutorialSlide6Desc =>
      'Track the total value of your collection over time. Discover your return on investment with detailed charts and statistics.';

  @override
  String get tutorialSlide7Title => 'Deck Builder';

  @override
  String get tutorialSlide7Desc =>
      'Build and manage your decks. Analyze composition, value and keep track of everything you\'ve built.';

  @override
  String get downloadCatalog => 'Catalog';

  @override
  String get downloadRestoreCatalog => 'Catalog restore';

  @override
  String downloadRestoreProgress(int current, int total, String name) {
    return 'Restore $current/$total: $name';
  }

  @override
  String downloadCollectionProgress(int current, int total, String name) {
    return 'Collection $current/$total: $name';
  }

  @override
  String downloadCollectionProgressPct(
    int current,
    int total,
    String name,
    int pct,
  ) {
    return 'Collection $current/$total: $name ($pct%)';
  }

  @override
  String downloadProgressPct(String name, int pct) {
    return '$name ($pct%)';
  }

  @override
  String get cardLabelAlbum => 'Album';

  @override
  String get cardLabelQuantity => 'Quantity';

  @override
  String get cardLabelType => 'Type';

  @override
  String get cardLabelRarity => 'Rarity';

  @override
  String get cardSearchOnCardtrader => 'Search on CardTrader ↗';

  @override
  String cardDialogAlbumFullMsg(String name, int current, int max) {
    return '$name has reached its maximum capacity ($current/$max).\n\nIncrease the album capacity or select another album.';
  }

  @override
  String get albumMaxCapacityLabel => 'MAX CAPACITY';

  @override
  String get scannerPrivacyTitle => 'AI scanner notice';

  @override
  String get scannerPrivacyBody =>
      'To identify your cards, the captured frame is temporarily sent to Google\'s AI services (Gemini) over an encrypted connection.\n\nImages are not retained by Deck Master or Google beyond the time needed to process the single request.\n\nBy continuing you authorize this transfer. You can decline: in that case the scanner won\'t be available.';

  @override
  String get aiDeckOnlyOwnedNote =>
      'The AI will build a deck using only the cards in your collection.';
}
