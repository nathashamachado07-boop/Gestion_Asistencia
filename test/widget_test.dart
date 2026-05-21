import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/config/app_config.dart';
import 'package:flutter_application_1/screens/login_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/firebase_core'), (
      methodCall,
    ) async {
      switch (methodCall.method) {
        case 'Firebase#initializeCore':
          return [
            {
              'name': '[DEFAULT]',
              'options': <String, Object?>{},
              'pluginConstants': <String, Object?>{},
            },
          ];
        case 'Firebase#initializeApp':
          return {
            'name': '[DEFAULT]',
            'options': <String, Object?>{},
            'pluginConstants': <String, Object?>{},
          };
      }
      return null;
    });
    await Firebase.initializeApp();
  });

  testWidgets('muestra la pantalla base de login matriz', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LoginScreen(appConfig: AppConfig.matriz),
      ),
    );

    await tester.pump(const Duration(milliseconds: 1100));

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Bienvenido'), findsOneWidget);
    expect(find.text('Correo institucional'), findsOneWidget);
    expect(find.text('INICIAR SESION'), findsOneWidget);
  });
}
