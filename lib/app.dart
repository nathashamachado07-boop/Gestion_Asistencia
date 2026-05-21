import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'config/app_config.dart';
import 'firebase_options.dart';
import 'models/app_branding.dart';
import 'services/push_notification_service.dart';
import 'services/theme_controller.dart';
import 'screens/login_screen.dart';
import 'web/admin_layout.dart';
import 'web/login_web.dart';

Future<void> bootstrapApp(AppConfig appConfig) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  await Future.wait<void>([
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
    AppThemeController.instance.initialize(),
  ]);

  runApp(AttendanceApp(appConfig: appConfig));

  unawaited(initializeDateFormatting('es_ES', null));

  if (!kIsWeb) {
    unawaited(PushNotificationService.instance.initialize());
  }
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key, required this.appConfig});

  final AppConfig appConfig;

  @override
  Widget build(BuildContext context) {
    final branding = AppBranding.fromSedeId(appConfig.defaultSedeId);

    return AnimatedBuilder(
      animation: AppThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          title: appConfig.appName,
          debugShowCheckedModeBanner: false,
          locale: const Locale('es', 'EC'),
          supportedLocales: const [
            Locale('es', 'EC'),
            Locale('es'),
            Locale('en'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: _buildLightTheme(branding),
          darkTheme: _buildDarkTheme(branding),
          themeMode: AppThemeController.instance.themeMode,
          home: kIsWeb
              ? LoginWeb(appConfig: appConfig)
              : LoginScreen(appConfig: appConfig),
          routes: {
            '/login': (context) => kIsWeb
                ? LoginWeb(appConfig: appConfig)
                : LoginScreen(appConfig: appConfig),
            '/admin': (context) => const AdminLayout(),
          },
        );
      },
    );
  }

  ThemeData _buildLightTheme(AppBranding branding) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: branding.primary,
      brightness: Brightness.light,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: branding.surface,
      canvasColor: branding.surface,
      cardColor: Colors.white,
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        modalBackgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );
  }

  ThemeData _buildDarkTheme(AppBranding branding) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: branding.primary,
      brightness: Brightness.dark,
    );
    final surface = Color.alphaBlend(
      branding.primaryDark.withValues(alpha: 0.32),
      const Color(0xFF0C1316),
    );
    final cardSurface = Color.alphaBlend(
      branding.primary.withValues(alpha: 0.12),
      const Color(0xFF172126),
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: surface,
      canvasColor: surface,
      cardColor: cardSurface,
      dialogTheme: DialogThemeData(
        backgroundColor: cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardSurface,
        modalBackgroundColor: cardSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );
  }
}
