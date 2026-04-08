import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart'; 



void main() async {
  // Aseguramos que Flutter cargue los componentes antes de iniciar Firebase
 WidgetsFlutterBinding.ensureInitialized();  
  // Inicialización de la base de datos de Google
    await Firebase.initializeApp(
   options: DefaultFirebaseOptions.currentPlatform,
  );
  
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
        // Color verde institucional del Sudamericano
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2D6A4F)),
        useMaterial3: true,
      ),
      // La aplicación siempre arrancará pidiendo el usuario
      home: const LoginScreen(), 
    );
  }
}