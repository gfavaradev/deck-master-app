import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'pages/splash_page.dart';
import 'theme/app_colors.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'services/app_preferences.dart';
import 'services/background_download_service.dart';
import 'services/notification_service.dart';
import 'services/ad_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Limita la cache immagini in memoria a 60MB per evitare OOM su dispositivi con heap 256MB.
  // Il default Flutter (100MB) sommato ad Ads SDK e dati SQLite portava a OOM.
  // In debug the Flutter overhead is ~40MB higher than release; cap lower.
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      kDebugMode ? 30 * 1024 * 1024 : 60 * 1024 * 1024;

  // Disabilita il download dei font da internet: usa solo gli asset bundlati.
  // Senza questo, google_fonts tenta di scaricare i font da fonts.gstatic.com
  // causando eccezioni non gestite su dispositivi senza connessione o con DNS limitato.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Rendering edge-to-edge: il contenuto si estende sotto status bar e nav bar.
  // Funziona sia con gesture navigation che con la barra 3 pulsanti.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  ));

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // AppCheck: in debug non lo attiviamo per evitare che blocchi Firestore su
  // dispositivi nuovi il cui debug token non è ancora registrato in Firebase Console.
  // In release usa Play Integrity per verificare l'autenticità dell'app.
  if (!kIsWeb && !kDebugMode) {
    FirebaseAppCheck.instance.activate(
      providerAndroid: const AndroidPlayIntegrityProvider(),
      providerApple: const AppleAppAttestProvider(),
    ).catchError((_) {});
  }

  // Disabilita la persistence nativa di Firestore (usiamo SQLite come cache locale)
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );

  await AppPreferences.init();

  // AdMob deve essere inizializzato PRIMA di runApp per evitare race condition
  // con il primo caricamento del banner.
  await AdService.initialize().catchError((_) {});

  // Avvia in background — non bloccano runApp, errori non critici ignorati
  BackgroundDownloadService.initialize().catchError((_) {});
  NotificationService().initialize().catchError((_) {});
  // Mostra reminder catalogo se era stato posticipato nella sessione precedente
  NotificationService().checkAndShowPendingCatalogReminder().catchError((_) {});

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Locale _locale = AppPreferences.instance.languageCode == 'en'
      ? const Locale('en')
      : const Locale('it');

  @override
  void initState() {
    super.initState();
    AppPreferences.localeNotifier.addListener(_onLocaleChange);
  }

  @override
  void dispose() {
    AppPreferences.localeNotifier.removeListener(_onLocaleChange);
    super.dispose();
  }

  void _onLocaleChange() {
    setState(() => _locale = AppPreferences.localeNotifier.value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Deck Master',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: const [Locale('it'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.gold,
          onPrimary: AppColors.bgDark,
          secondary: AppColors.blue,
          onSecondary: AppColors.textPrimary,
          surface: AppColors.bgLight,
          onSurface: AppColors.textPrimary,
          inversePrimary: AppColors.bgMedium,
        ),
        scaffoldBackgroundColor: AppColors.bgDark,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.bgMedium,
          foregroundColor: AppColors.textPrimary,
          iconTheme: IconThemeData(color: AppColors.textPrimary),
          elevation: 0,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.bgMedium,
          selectedItemColor: AppColors.gold,
          unselectedItemColor: AppColors.textHint,
          elevation: 0,
        ),
        cardTheme: const CardThemeData(
          color: AppColors.bgLight,
          elevation: 2,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: AppColors.bgLight,
          titleTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
          contentTextStyle: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: AppColors.bgDark,
          border: OutlineInputBorder(),
          labelStyle: TextStyle(color: AppColors.textSecondary),
          hintStyle: TextStyle(color: AppColors.textHint),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.gold, width: 2),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          textColor: AppColors.textPrimary,
          iconColor: AppColors.textSecondary,
        ),
        dividerColor: AppColors.divider,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: AppColors.textPrimary),
          bodySmall: TextStyle(color: AppColors.textSecondary),
        ),
      ),
      home: const SplashPage(),
    );
  }
}
