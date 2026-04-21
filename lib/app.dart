import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'config/app_config.dart';
import 'firebase_options.dart';
import 'models/app_branding.dart';
import 'screens/login_screen.dart';
import 'web/admin_layout.dart';
import 'web/login_web.dart';

Future<void> bootstrapApp(AppConfig appConfig) async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await initializeDateFormatting('es_ES', null);

  runApp(AttendanceApp(appConfig: appConfig));
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({
    super.key,
    required this.appConfig,
  });

  final AppConfig appConfig;

  @override
  Widget build(BuildContext context) {
    final branding = AppBranding.fromSedeId(appConfig.defaultSedeId);

    return MaterialApp(
      title: appConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: branding.primary),
        useMaterial3: true,
      ),
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
  }
}
