import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'pages/splash_page.dart';
import 'theme/app_colors.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/background_download_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Inizializza App Check (elimina warning "No AppCheckProvider installed")
  await FirebaseAppCheck.instance.activate(
    androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
    appleProvider: AppleProvider.debug,
  );

  // Disabilita la persistence nativa di Firestore (usiamo SQLite come cache locale)
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );

  // Inizializza il servizio per i download in background (solo Android/iOS)
  await BackgroundDownloadService.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Deck Master',
      debugShowCheckedModeBanner: false,
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
          unselectedItemColor: Color(0x80FFFFFF),
          elevation: 0,
        ),
        cardTheme: const CardTheme(
          color: AppColors.bgLight,
          elevation: 2,
        ),
        dialogTheme: const DialogTheme(
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
            borderSide: BorderSide(color: Color(0x40FFFFFF)),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.gold, width: 2),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          textColor: AppColors.textPrimary,
          iconColor: AppColors.textSecondary,
        ),
        dividerColor: Color(0x1FFFFFFF),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: AppColors.textPrimary),
          bodySmall: TextStyle(color: AppColors.textSecondary),
        ),
      ),
      home: const SplashPage(),
    );
  }
}
