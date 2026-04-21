import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/app.dart';
import 'package:flutter_application_1/config/app_config.dart';

void main() {
  testWidgets('muestra el login de la app matriz', (WidgetTester tester) async {
    await tester.pumpWidget(
      const AttendanceApp(appConfig: AppConfig.matriz),
    );

    expect(find.text('Bienvenido'), findsOneWidget);
    expect(find.text('Correo institucional'), findsOneWidget);
    expect(find.text('INICIAR SESION'), findsOneWidget);
  });
}
