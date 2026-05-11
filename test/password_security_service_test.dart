import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/password_security_service.dart';

void main() {
  group('PasswordSecurityService', () {
    final service = PasswordSecurityService();

    test('hash y verificacion correcta funcionan', () async {
      final result = await service.hashPassword('ClaveSegura123');

      final verified = await service.verifyPassword(
        password: 'ClaveSegura123',
        expectedHash: result.hash,
        salt: result.salt,
      );

      expect(verified, isTrue);
      expect(result.algorithm, PasswordSecurityService.algorithm);
      expect(result.version, PasswordSecurityService.version);
    });

    test('falla la verificacion con password incorrecta', () async {
      final result = await service.hashPassword('ClaveSegura123');

      final verified = await service.verifyPassword(
        password: 'OtraClave456',
        expectedHash: result.hash,
        salt: result.salt,
      );

      expect(verified, isFalse);
    });

    test('valida fortaleza minima de contrasena', () {
      expect(
        PasswordSecurityService.validatePasswordStrength('corta1A'),
        isNull,
      );
      expect(
        PasswordSecurityService.validatePasswordStrength('abcdefghi'),
        isNotNull,
      );
      expect(
        PasswordSecurityService.validatePasswordStrength('ABCDEFGHI1'),
        isNotNull,
      );
      expect(
        PasswordSecurityService.validatePasswordStrength('Abcdefghi'),
        isNotNull,
      );
    });
  });
}
