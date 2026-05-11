import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class PasswordSecurityService {
  static const String algorithm = 'pbkdf2-sha256';
  static const int version = 1;
  static const int _iterations = 60000;
  static const int _saltLength = 16;
  static const int _derivedKeyLength = 32;

  static String? validatePasswordStrength(String password) {
    final value = password.trim();

    if (value.length < 8) {
      return 'La contrasena debe tener al menos 8 caracteres.';
    }

    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'La contrasena debe incluir al menos una letra mayuscula.';
    }

    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'La contrasena debe incluir al menos una letra minuscula.';
    }

    if (!RegExp(r'\d').hasMatch(value)) {
      return 'La contrasena debe incluir al menos un numero.';
    }

    return null;
  }

  Future<PasswordHashResult> hashPassword(String password) async {
    final saltBytes = _generateSalt();
    return _buildHash(password: password, saltBytes: saltBytes);
  }

  Future<bool> verifyPassword({
    required String password,
    required String expectedHash,
    required String salt,
  }) async {
    if (expectedHash.trim().isEmpty || salt.trim().isEmpty) {
      return false;
    }

    try {
      final saltBytes = base64Decode(salt);
      final result = await _buildHash(password: password, saltBytes: saltBytes);
      return _constantTimeEquals(result.hash, expectedHash);
    } catch (_) {
      return false;
    }
  }

  Future<PasswordHashResult> _buildHash({
    required String password,
    required List<int> saltBytes,
  }) async {
    final hmac = Hmac(sha256, utf8.encode(password));
    final hashBytes = _pbkdf2(
      hmac: hmac,
      salt: saltBytes,
      iterations: _iterations,
      keyLength: _derivedKeyLength,
    );

    return PasswordHashResult(
      hash: base64Encode(hashBytes),
      salt: base64Encode(saltBytes),
      algorithm: algorithm,
      version: version,
      iterations: _iterations,
    );
  }

  List<int> _generateSalt() {
    final random = Random.secure();
    return List<int>.generate(_saltLength, (_) => random.nextInt(256));
  }

  List<int> _pbkdf2({
    required Hmac hmac,
    required List<int> salt,
    required int iterations,
    required int keyLength,
  }) {
    final hashLength = hmac.convert(const <int>[]).bytes.length;
    final blocks = (keyLength / hashLength).ceil();
    final output = BytesBuilder(copy: false);

    for (var blockIndex = 1; blockIndex <= blocks; blockIndex++) {
      final initialInput = BytesBuilder(copy: false)
        ..add(salt)
        ..add(_int32Block(blockIndex));

      var u = hmac.convert(initialInput.toBytes()).bytes;
      final t = List<int>.from(u);

      for (var iteration = 1; iteration < iterations; iteration++) {
        u = hmac.convert(u).bytes;
        for (var i = 0; i < t.length; i++) {
          t[i] ^= u[i];
        }
      }

      output.add(t);
    }

    return output.toBytes().sublist(0, keyLength);
  }

  List<int> _int32Block(int value) {
    return <int>[
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ];
  }

  bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) {
      return false;
    }

    var mismatch = 0;
    for (var i = 0; i < left.length; i++) {
      mismatch |= left.codeUnitAt(i) ^ right.codeUnitAt(i);
    }
    return mismatch == 0;
  }
}

class PasswordHashResult {
  const PasswordHashResult({
    required this.hash,
    required this.salt,
    required this.algorithm,
    required this.version,
    required this.iterations,
  });

  final String hash;
  final String salt;
  final String algorithm;
  final int version;
  final int iterations;

  Map<String, dynamic> toMap() {
    return {
      'passwordHash': hash,
      'passwordSalt': salt,
      'passwordAlgorithm': algorithm,
      'passwordVersion': version,
      'passwordIterations': iterations,
    };
  }
}
