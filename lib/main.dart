import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart'; 
import 'web/login_web.dart'; 
import 'web/admin_layout.dart'; // Asegúrate de importar tu Layout
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();  
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await initializeDateFormatting('es_ES', null); 
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sistema Asistencia ISTS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2D6A4F)),
        useMaterial3: true,
      ),
      // 1. Definimos la pantalla inicial
      home: kIsWeb ? const LoginWeb() : const LoginScreen(),

      // 2. Agregamos el mapa de rutas para que el botón "Cerrar Sesión" funcione
      routes: {
        '/login': (context) => kIsWeb ? const LoginWeb() : const LoginScreen(),
        '/admin': (context) => const AdminLayout(),
      },
    );
  }
}