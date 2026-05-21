import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../config/app_config.dart';
import '../models/solicitud_model.dart';
import 'password_security_service.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final PasswordSecurityService _passwordSecurity = PasswordSecurityService();
  static const String _functionsRegion = 'us-central1';
  static const String _localPreviewCertificateField =
      'certificadoDigitalP12LocalPreview';
  static const int _passwordRecoveryExpirationMinutes = 10;
  static const int _passwordRecoveryMaxAttempts = 5;
  static const String _gpsTemporalDesactivadoHastaField =
      'gpsTemporalDesactivadoHasta';
  static const int _firmaPerfilMaxBytes = 180 * 1024;
  static const int _certificadoDigitalMaxBytes = 512 * 1024;
  static const int _pdfFinalFirestoreMaxBytes = 850 * 1024;

  // --- COORDENADAS DEL INSTITUTO ---
  static const double latitudInstituto = -0.1843090;
  static const double longitudInstituto = -78.4909804;
  static const double rangoMaximoMetros = 40.0;

  // --- FUNCIÓN PARA OBTENER NÚMERO DE MES ---
  int _obtenerNumeroMes(String mes) {
    const meses = {
      "Enero": 1,
      "Febrero": 2,
      "Marzo": 3,
      "Abril": 4,
      "Mayo": 5,
      "Junio": 6,
      "Julio": 7,
      "Agosto": 8,
      "Septiembre": 9,
      "Octubre": 10,
      "Noviembre": 11,
      "Diciembre": 12,
    };
    return meses[mes] ?? DateTime.now().month;
  }

  // --- FUNCIÓN PARA VALIDAR GPS ---
  String _normalizarCorreo(String correo) {
    return correo.trim().toLowerCase();
  }

  DateTime _proximaMedianocheLocal([DateTime? base]) {
    final ahora = (base ?? DateTime.now()).toLocal();
    return DateTime(ahora.year, ahora.month, ahora.day + 1);
  }

  DateTime? _toLocalDateTime(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Timestamp) {
      return value.toDate().toLocal();
    }
    if (value is DateTime) {
      return value.isUtc ? value.toLocal() : value;
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed.isUtc ? parsed.toLocal() : parsed;
      }
    }
    return null;
  }

  DateTime? _gpsTemporalDesactivadoHastaActivo(
    Map<String, dynamic>? data, {
    required String gpsField,
  }) {
    if (data == null || data[gpsField] != false) {
      return null;
    }

    final desactivadoHasta = _toLocalDateTime(
      data[_gpsTemporalDesactivadoHastaField],
    );
    if (desactivadoHasta == null) {
      return null;
    }

    final ahora = DateTime.now().toLocal();
    return ahora.isBefore(desactivadoHasta) ? desactivadoHasta : null;
  }

  Map<String, dynamic> _buildGpsTemporalPayload({
    required bool requiereGeolocalizacion,
    required String gpsField,
  }) {
    return {
      gpsField: requiereGeolocalizacion,
      _gpsTemporalDesactivadoHastaField: requiereGeolocalizacion
          ? FieldValue.delete()
          : Timestamp.fromDate(_proximaMedianocheLocal()),
    };
  }

  bool _requiereGeolocalizacionEfectiva(
    Map<String, dynamic>? data, {
    required String gpsField,
  }) {
    if (data == null || data[gpsField] != false) {
      return true;
    }

    if (_gpsTemporalDesactivadoHastaActivo(data, gpsField: gpsField) != null) {
      return false;
    }

    return _toLocalDateTime(data[_gpsTemporalDesactivadoHastaField]) != null;
  }

  bool requiereGeolocalizacionUsuarioEfectiva(Map<String, dynamic>? userData) {
    return _requiereGeolocalizacionEfectiva(
      userData,
      gpsField: 'requiereGeolocalizacion',
    );
  }

  bool requiereGeolocalizacionAreaEfectiva(Map<String, dynamic>? areaData) {
    return _requiereGeolocalizacionEfectiva(
      areaData,
      gpsField: 'requiereGeolocalizacionPorDefecto',
    );
  }

  DateTime? obtenerGpsTemporalDesactivadoHastaUsuario(
    Map<String, dynamic>? userData,
  ) {
    return _gpsTemporalDesactivadoHastaActivo(
      userData,
      gpsField: 'requiereGeolocalizacion',
    );
  }

  DateTime? obtenerGpsTemporalDesactivadoHastaArea(
    Map<String, dynamic>? areaData,
  ) {
    return _gpsTemporalDesactivadoHastaActivo(
      areaData,
      gpsField: 'requiereGeolocalizacionPorDefecto',
    );
  }

  Map<String, dynamic> _sanitizarDatosUsuario(Map<String, dynamic> data) {
    final certificado = _extraerCertificadoDigitalP12(data);
    final limpio = Map<String, dynamic>.from(data);
    limpio.remove('password');
    limpio.remove('passwordHash');
    limpio.remove('passwordSalt');
    limpio.remove('passwordAlgorithm');
    limpio.remove('passwordVersion');
    limpio.remove('passwordIterations');
    limpio.remove(_localPreviewCertificateField);
    if (certificado != null) {
      limpio['certificadoDigitalP12'] = _sanitizarCertificadoDigitalP12(
        certificado,
      );
    } else {
      limpio.remove('certificadoDigitalP12');
    }
    return limpio;
  }

  Future<Map<String, dynamic>> _crearPayloadPasswordSeguro(
    String password,
  ) async {
    final hash = await _passwordSecurity.hashPassword(password);
    return hash.toMap();
  }

  void _validarPasswordSeguraOrThrow(String password) {
    final validationMessage = PasswordSecurityService.validatePasswordStrength(
      password,
    );

    if (validationMessage != null) {
      throw Exception(validationMessage);
    }
  }

  Uri _buildFunctionUri(String functionName) {
    final projectId = Firebase.app().options.projectId;

    if (kIsWeb) {
      final host = Uri.base.host.toLowerCase();
      final isLocalHost =
          host == 'localhost' || host == '127.0.0.1' || host == '0.0.0.0';

      // In Firebase Hosting we prefer same-origin rewrites to avoid
      // browser CORS/preflight failures when calling secure functions.
      if (!isLocalHost) {
        return Uri(path: '/api/$functionName');
      }
    }

    return Uri.https(
      '$_functionsRegion-$projectId.cloudfunctions.net',
      '/$functionName',
    );
  }

  Future<Map<String, dynamic>> _callSecurePasswordFunction(
    String functionName, {
    required Map<String, dynamic> payload,
  }) async {
    return _callSecureFunction(functionName, payload: payload);
  }

  Future<Map<String, dynamic>> _callSecureFunction(
    String functionName, {
    required Map<String, dynamic> payload,
  }) async {
    late final http.Response response;

    try {
      response = await http.post(
        _buildFunctionUri(functionName),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(payload),
      );
    } catch (error) {
      debugPrint(
        '_callSecureFunction fallo en $functionName '
        '(payloadKeys=${payload.keys.join(",")}): $error',
      );
      throw Exception(
        'No se pudo conectar con el servicio seguro. Recarga la pagina e intenta nuevamente.',
      );
    }

    Map<String, dynamic> body = const {};
    if (response.body.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          body = decoded;
        }
      } catch (error) {
        debugPrint(
          '_callSecureFunction recibio JSON invalido en $functionName '
          '(status=${response.statusCode}): $error',
        );
        body = const {};
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    final message = (body['message'] ?? '').toString().trim();
    if (message.isNotEmpty) {
      throw Exception(message);
    }

    throw Exception('No se pudo completar la operacion segura solicitada.');
  }

  bool _canUseLocalPasswordRecoveryFallback() {
    if (kDebugMode) {
      return true;
    }

    if (!kIsWeb) {
      return false;
    }

    final host = Uri.base.host.toLowerCase();
    return host == 'localhost' || host == '127.0.0.1' || host == '0.0.0.0';
  }

  bool _isLocalHostWeb() {
    if (!kIsWeb) {
      return false;
    }

    final host = Uri.base.host.toLowerCase();
    return host == 'localhost' || host == '127.0.0.1' || host == '0.0.0.0';
  }

  bool _canUseLocalDigitalCertificateFallback() {
    return _isLocalHostWeb();
  }

  bool _shouldUseLocalDigitalCertificateFallback(Object error) {
    if (!_canUseLocalDigitalCertificateFallback()) {
      return false;
    }

    final message = error.toString().toLowerCase();
    return message.contains('no se pudo conectar con el servicio seguro') ||
        message.contains('no se pudo completar la operacion segura solicitada');
  }

  String _generateRecoveryCode() {
    final random = Random.secure();
    return random.nextInt(1000000).toString().padLeft(6, '0');
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _findUserDocByEmail(
    String correo,
  ) async {
    final query = await _db
        .collection('usuarios')
        .where('correo', isEqualTo: correo)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      return null;
    }

    return query.docs.first;
  }

  Future<PasswordRecoveryStartResult> _solicitarRecuperacionPasswordEnFirestore(
    String correo,
  ) async {
    final userDoc = await _findUserDocByEmail(correo);
    if (userDoc == null) {
      return const PasswordRecoveryStartResult(
        codeSent: false,
        requiresSupport: true,
        message:
            'No se pudo validar la cuenta solicitada. Verifica el correo o contacta a RRHH o al administrador.',
      );
    }

    final data = userDoc.data();
    final recoveryData = Map<String, dynamic>.from(
      (data['passwordRecovery'] as Map<String, dynamic>?) ?? const {},
    );
    final requestedAt = recoveryData['requestedAt'];
    final requestedDate = requestedAt is Timestamp
        ? requestedAt.toDate()
        : null;

    if (requestedDate != null) {
      final elapsedSeconds = DateTime.now().difference(requestedDate).inSeconds;
      if (elapsedSeconds < 60) {
        final waitSeconds = 60 - elapsedSeconds;
        throw Exception(
          'Espera $waitSeconds segundos antes de solicitar un nuevo codigo.',
        );
      }
    }

    final code = _generateRecoveryCode();
    final codePayload = await _passwordSecurity.hashPassword(code);

    await userDoc.reference.set({
      'passwordRecovery': {
        'codeHash': codePayload.hash,
        'codeSalt': codePayload.salt,
        'codeAlgorithm': codePayload.algorithm,
        'codeVersion': codePayload.version,
        'codeIterations': codePayload.iterations,
        'requestedAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(
            const Duration(minutes: _passwordRecoveryExpirationMinutes),
          ),
        ),
        'attempts': 0,
        'maxAttempts': _passwordRecoveryMaxAttempts,
        'status': 'pending',
        'delivery': 'local_debug',
      },
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return PasswordRecoveryStartResult(
      codeSent: true,
      requiresSupport: false,
      message:
          'Modo local de recuperacion activado. Usa el codigo temporal $code para continuar. Caduca en $_passwordRecoveryExpirationMinutes minutos.',
    );
  }

  Future<void> _confirmarRecuperacionPasswordEnFirestore({
    required String correo,
    required String codigo,
    required String nuevaPassword,
  }) async {
    final userDoc = await _findUserDocByEmail(correo);
    if (userDoc == null) {
      throw Exception('No se pudo validar la recuperacion solicitada.');
    }

    final data = userDoc.data();
    final recoveryData = Map<String, dynamic>.from(
      (data['passwordRecovery'] as Map<String, dynamic>?) ?? const {},
    );
    final codeHash = (recoveryData['codeHash'] ?? '').toString();
    final codeSalt = (recoveryData['codeSalt'] ?? '').toString();
    final expiresAtValue = recoveryData['expiresAt'];
    final expiresAt = expiresAtValue is Timestamp
        ? expiresAtValue.toDate()
        : null;
    final attempts = (recoveryData['attempts'] as num?)?.toInt() ?? 0;
    final maxAttempts =
        (recoveryData['maxAttempts'] as num?)?.toInt() ??
        _passwordRecoveryMaxAttempts;

    if (codeHash.isEmpty || codeSalt.isEmpty || expiresAt == null) {
      throw Exception('Solicita un nuevo codigo temporal antes de continuar.');
    }

    if (DateTime.now().isAfter(expiresAt)) {
      await userDoc.reference.update({'passwordRecovery': FieldValue.delete()});
      throw Exception('El codigo temporal ya expiro. Solicita uno nuevo.');
    }

    if (attempts >= maxAttempts) {
      throw Exception(
        'Se agotaron los intentos permitidos. Solicita un nuevo codigo temporal.',
      );
    }

    final codeIsValid = await _passwordSecurity.verifyPassword(
      password: codigo,
      expectedHash: codeHash,
      salt: codeSalt,
    );

    if (!codeIsValid) {
      final nextAttempts = attempts + 1;
      await userDoc.reference.set({
        'passwordRecovery': {
          ...recoveryData,
          'attempts': nextAttempts,
          'lastFailedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      throw Exception(
        nextAttempts >= maxAttempts
            ? 'Se agotaron los intentos permitidos. Solicita un nuevo codigo temporal.'
            : 'El codigo temporal ingresado no es correcto.',
      );
    }

    final passwordPayload = await _crearPayloadPasswordSeguro(nuevaPassword);
    await userDoc.reference.set({
      ...passwordPayload,
      'password': FieldValue.delete(),
      'passwordRecovery': FieldValue.delete(),
      'passwordChangedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _cambiarPasswordConActualEnFirestore({
    required String correo,
    required String passwordActual,
    required String nuevaPassword,
  }) async {
    final query = await _db
        .collection('usuarios')
        .where('correo', isEqualTo: correo)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw Exception('No existe un usuario registrado con ese correo.');
    }

    final userDoc = query.docs.first;
    final data = userDoc.data();
    final passwordValida = await _validarPasswordUsuario(
      userRef: userDoc.reference,
      data: data,
      password: passwordActual,
    );

    if (!passwordValida) {
      throw Exception('La contrasena actual no es correcta.');
    }

    final passwordPayload = await _crearPayloadPasswordSeguro(nuevaPassword);
    await userDoc.reference.update({
      ...passwordPayload,
      'password': FieldValue.delete(),
      'passwordRecovery': FieldValue.delete(),
      'passwordChangedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _eliminarPasswordLegacy(
    DocumentReference<Map<String, dynamic>> userRef,
  ) async {
    await userRef.update({'password': FieldValue.delete()});
  }

  Future<void> _migrarPasswordLegacy({
    required DocumentReference<Map<String, dynamic>> userRef,
    required String password,
  }) async {
    try {
      final passwordPayload = await _crearPayloadPasswordSeguro(password);
      await userRef.update({
        ...passwordPayload,
        'password': FieldValue.delete(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      debugPrint(
        'No se pudo migrar la contrasena legacy del usuario ${userRef.id}: $error',
      );
    }
  }

  Future<bool> _validarPasswordUsuario({
    required DocumentReference<Map<String, dynamic>> userRef,
    required Map<String, dynamic> data,
    required String password,
  }) async {
    final hash = (data['passwordHash'] ?? '').toString();
    final salt = (data['passwordSalt'] ?? '').toString();

    if (hash.isNotEmpty && salt.isNotEmpty) {
      return _passwordSecurity.verifyPassword(
        password: password,
        expectedHash: hash,
        salt: salt,
      );
    }

    final legacyPassword = (data['password'] ?? '').toString();
    if (legacyPassword.isEmpty || legacyPassword != password) {
      return false;
    }

    await _migrarPasswordLegacy(userRef: userRef, password: password);
    return true;
  }

  // Login: Trae al usuario y su lista de horarios
  Future<Map<String, dynamic>?> validarLogin(
    String correo,
    String password,
  ) async {
    final correoLimpio = _normalizarCorreo(correo);
    final passwordLimpia = password.trim();

    if (correoLimpio.isEmpty || passwordLimpia.isEmpty) {
      return null;
    }

    final userQuery = await _db
        .collection('usuarios')
        .where('correo', isEqualTo: correoLimpio)
        .limit(1)
        .get();

    if (userQuery.docs.isEmpty) {
      return null;
    }

    final doc = userQuery.docs.first;
    final data = doc.data();
    final passwordValida = await _validarPasswordUsuario(
      userRef: doc.reference,
      data: data,
      password: passwordLimpia,
    );

    if (!passwordValida) {
      return null;
    }

    return {..._sanitizarDatosUsuario(data), 'docId': doc.id};
  }

  Future<Map<String, dynamic>?> validarLoginPorSede({
    required String correo,
    required String password,
    required String sedeId,
  }) async {
    final correoLimpio = _normalizarCorreo(correo);
    final passwordLimpia = password.trim();

    if (correoLimpio.isEmpty || passwordLimpia.isEmpty) {
      return null;
    }

    final userQuery = await _db
        .collection('usuarios')
        .where('correo', isEqualTo: correoLimpio)
        .where('sedeId', isEqualTo: sedeId)
        .limit(1)
        .get();

    if (userQuery.docs.isEmpty) {
      return null;
    }

    final doc = userQuery.docs.first;
    final data = doc.data();
    final passwordValida = await _validarPasswordUsuario(
      userRef: doc.reference,
      data: data,
      password: passwordLimpia,
    );

    if (!passwordValida) {
      return null;
    }

    return {..._sanitizarDatosUsuario(data), 'docId': doc.id};
  }

  Future<Map<String, dynamic>> _activarSedeEspecial({
    required Map<String, dynamic> userData,
    required String sedeId,
    required String sedeNombre,
    required String logoAsset,
    required Map<String, String> colores,
  }) async {
    final userDocId = userData['docId']?.toString();
    if (userDocId == null || userDocId.isEmpty) {
      throw Exception('No se encontro el documento del usuario RRHH.');
    }

    await _db.collection('sedes').doc(sedeId).set({
      'nombre': sedeNombre,
      'slug': sedeId,
      'estado': 'activa',
      'colores': colores,
      'branding': {
        'nombreMarca': 'Princesa de Gales',
        'subtitulo': 'ESTETICA INTEGRAL',
        'logoAsset': logoAsset,
      },
      'actualizadoEn': FieldValue.serverTimestamp(),
      'creadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _db.collection('usuarios').doc(userDocId).set({
      'sede': sedeNombre,
      'sedeId': sedeId,
      'dashboardWeb': sedeId,
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return {
      ...userData,
      'sede': sedeNombre,
      'sedeId': sedeId,
      'dashboardWeb': sedeId,
    };
  }

  Future<Map<String, dynamic>> activarSedePrincesaGalesNorte({
    required Map<String, dynamic> userData,
  }) async {
    return _activarSedeEspecial(
      userData: userData,
      sedeId: 'princesa_gales_norte',
      sedeNombre: 'Princesa de Gales Norte',
      logoAsset: 'assets/images/logo_galesnorte.png',
      colores: const {
        'primary': '#6D2745',
        'secondary': '#8A3557',
        'accent': '#F4E9EC',
        'text': '#FFF7F8',
      },
    );
  }

  Future<Map<String, dynamic>> activarSedePrincesaGalesCentro({
    required Map<String, dynamic> userData,
  }) async {
    return _activarSedeEspecial(
      userData: userData,
      sedeId: 'princesa_gales_centro',
      sedeNombre: 'Princesa de Gales Centro',
      logoAsset: 'assets/images/logo_galescentro.png',
      colores: const {
        'primary': '#9C4F73',
        'secondary': '#B6688A',
        'accent': '#F7EAF0',
        'text': '#FFF8FB',
      },
    );
  }

  Future<Map<String, dynamic>> activarSedeInstitutoCreSer({
    required Map<String, dynamic> userData,
  }) async {
    return _activarSedeEspecial(
      userData: userData,
      sedeId: 'instituto_cre_ser',
      sedeNombre: 'Instituto Cre Ser',
      logoAsset: 'assets/images/logo_cre_ser.jpeg',
      colores: const {
        'primary': '#2167AE',
        'secondary': '#4B93D9',
        'accent': '#EAF4FF',
        'text': '#F8FBFF',
      },
    );
  }

  static const int _registroMarcacionToleranciaMinutos = 10;
  static const int _horarioEspecialToleranciaSalidaAntesDefault = 10;
  static const int _horarioEspecialToleranciaSalidaDespuesDefault = 10;

  int _horaEnMinutos(String hora) {
    final partes = hora.split(':');
    final horas = int.tryParse(partes[0]) ?? 0;
    final minutos = partes.length > 1 ? int.tryParse(partes[1]) ?? 0 : 0;
    return (horas * 60) + minutos;
  }

  String _minutosAHora(int totalMinutos) {
    final minutosNormalizados = totalMinutos.clamp(0, (23 * 60) + 59);
    final horas = minutosNormalizados ~/ 60;
    final minutos = minutosNormalizados % 60;
    return '${horas.toString().padLeft(2, '0')}:${minutos.toString().padLeft(2, '0')}';
  }

  ({int inicio, int fin}) _ventanaMarcacionDesdeReferencia(int referenciaMin) {
    final inicio = (referenciaMin - _registroMarcacionToleranciaMinutos).clamp(
      0,
      (23 * 60) + 59,
    );
    final fin = (referenciaMin + _registroMarcacionToleranciaMinutos).clamp(
      0,
      (23 * 60) + 59,
    );
    return (inicio: inicio, fin: fin);
  }

  String _etiquetaVentanaMarcacion(int inicioMin, int finMin) {
    return '${_minutosAHora(inicioMin)} a ${_minutosAHora(finMin)}';
  }

  int _resolverToleranciaHorarioEspecial(dynamic value, int fallback) {
    if (value is int && value >= 0) {
      return value;
    }
    return fallback;
  }

  Future<Map<String, dynamic>?> _obtenerUsuarioPorCorreo(String correo) async {
    final correoNormalizado = _normalizarCorreo(correo);
    if (correoNormalizado.isEmpty) {
      return null;
    }

    final query = await _db
        .collection('usuarios')
        .where('correo', isEqualTo: correoNormalizado)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      return null;
    }

    return _sanitizarDatosUsuario(query.docs.first.data());
  }

  Future<Map<String, dynamic>?> obtenerUsuarioPorCorreo(String correo) async {
    return _obtenerUsuarioPorCorreo(correo);
  }

  Map<String, dynamic>? _extraerFirmaPerfil(Map<String, dynamic>? userData) {
    final firma = userData?['firmaPerfil'];
    if (firma is! Map) {
      return null;
    }

    return firma.map((key, value) => MapEntry(key.toString(), value));
  }

  Map<String, dynamic>? _extraerCertificadoDigitalP12(
    Map<String, dynamic>? userData,
  ) {
    final certificado = userData?['certificadoDigitalP12'];
    if (certificado is Map) {
      return certificado.map((key, value) => MapEntry(key.toString(), value));
    }

    if (_canUseLocalDigitalCertificateFallback()) {
      final localPreview = userData?[_localPreviewCertificateField];
      if (localPreview is Map) {
        return localPreview.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    }

    return null;
  }

  Map<String, dynamic>? extraerDocumentoPdfFinalSolicitud(
    Map<String, dynamic>? solicitudData,
  ) {
    if (solicitudData == null) {
      return null;
    }

    if (solicitudData.containsKey('blob') ||
        solicitudData.containsKey('base64') ||
        solicitudData.containsKey('mimeType')) {
      return Map<String, dynamic>.from(solicitudData);
    }

    final documento = solicitudData['documentoPdfFinal'];
    if (documento is! Map) {
      return null;
    }

    return documento.map((key, value) => MapEntry(key.toString(), value));
  }

  Uint8List? extraerBytesDocumentoPdfFinalSolicitud(
    Map<String, dynamic>? solicitudData,
  ) {
    final documento = extraerDocumentoPdfFinalSolicitud(solicitudData);
    if (documento == null) {
      return null;
    }

    final blob = documento['blob'];
    if (blob is Blob) {
      return blob.bytes;
    }
    if (blob is Uint8List) {
      return blob;
    }
    if (blob is List<int>) {
      return Uint8List.fromList(blob);
    }

    final base64Value = (documento['base64'] ?? '').toString().trim();
    if (base64Value.isEmpty) {
      return null;
    }

    try {
      return base64Decode(base64Value);
    } catch (error) {
      debugPrint(
        'extraerBytesDocumentoPdfFinalSolicitud fallo al decodificar base64 '
        '(base64Length=${base64Value.length}): $error',
      );
      return null;
    }
  }

  Future<Map<String, dynamic>?> obtenerDocumentoPdfFinalSolicitud(
    String idDoc,
  ) async {
    final snapshot = await _db
        .collection('solicitudes')
        .doc(idDoc)
        .collection('documentos')
        .doc('pdf_final')
        .get();

    if (snapshot.exists) {
      return snapshot.data();
    }

    return null;
  }

  Future<Uint8List?> obtenerBytesDocumentoPdfFinalSolicitud(String idDoc) async {
    final documento = await obtenerDocumentoPdfFinalSolicitud(idDoc);
    return extraerBytesDocumentoPdfFinalSolicitud(documento);
  }

  Map<String, dynamic> _sanitizarCertificadoDigitalP12(
    Map<String, dynamic> certificado,
  ) {
    final limpio = Map<String, dynamic>.from(certificado);
    for (final key in const [
      'encryptedBase64',
      'encryptionSalt',
      'encryptionIv',
      'encryptionAuthTag',
      'passwordHash',
      'passwordSalt',
      'passwordAlgorithm',
      'passwordVersion',
      'passwordIterations',
    ]) {
      limpio.remove(key);
    }
    return limpio;
  }

  bool _firmaPerfilTieneImagen(Map<String, dynamic>? firmaPerfil) {
    if (firmaPerfil == null) {
      return false;
    }

    final estado = (firmaPerfil['estado'] ?? 'activa').toString().trim();
    final imageBase64 = (firmaPerfil['imageBase64'] ?? '').toString().trim();
    return estado.toLowerCase() != 'inactiva' && imageBase64.isNotEmpty;
  }

  bool _firmaPerfilTieneClaveFirma(Map<String, dynamic>? firmaPerfil) {
    if (firmaPerfil == null) {
      return false;
    }

    final hash = (firmaPerfil['claveFirmaHash'] ?? '').toString().trim();
    final salt = (firmaPerfil['claveFirmaSalt'] ?? '').toString().trim();
    return hash.isNotEmpty && salt.isNotEmpty;
  }

  bool _certificadoDigitalConfigurado(
    Map<String, dynamic>? certificadoDigitalP12,
  ) {
    if (certificadoDigitalP12 == null) {
      return false;
    }

    final estado = (certificadoDigitalP12['estado'] ?? 'activo')
        .toString()
        .trim()
        .toLowerCase();
    final encryptedBase64 = (certificadoDigitalP12['encryptedBase64'] ?? '')
        .toString()
        .trim();
    return estado != 'inactivo' && encryptedBase64.isNotEmpty;
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _findUserSnapshotByIdentity({
    String? userDocId,
    required String correo,
    String? sedeId,
  }) async {
    final correoNormalizado = _normalizarCorreo(correo);
    final docId = (userDocId ?? '').trim();

    if (docId.isNotEmpty) {
      final snapshot = await _db.collection('usuarios').doc(docId).get();
      if (snapshot.exists) {
        return snapshot;
      }
    }

    if (correoNormalizado.isEmpty) {
      return null;
    }

    final query = await _db
        .collection('usuarios')
        .where('correo', isEqualTo: correoNormalizado)
        .get();

    if (query.docs.isEmpty) {
      return null;
    }

    final sedeNormalizada = SedeAccess.normalize(sedeId);
    if (sedeNormalizada.isNotEmpty) {
      for (final doc in query.docs) {
        if (SedeAccess.matchesSede(doc.data(), sedeNormalizada)) {
          return doc;
        }
      }
    }

    return query.docs.first;
  }

  Future<Map<String, dynamic>?> obtenerFirmaPerfilUsuario({
    String? userDocId,
    required String correo,
    String? sedeId,
  }) async {
    final snapshot = await _findUserSnapshotByIdentity(
      userDocId: userDocId,
      correo: correo,
      sedeId: sedeId,
    );
    if (snapshot == null || !snapshot.exists) {
      return null;
    }

    return _extraerFirmaPerfil(snapshot.data());
  }

  Future<Map<String, dynamic>?> obtenerCertificadoDigitalUsuario({
    String? userDocId,
    required String correo,
    String? sedeId,
  }) async {
    final snapshot = await _findUserSnapshotByIdentity(
      userDocId: userDocId,
      correo: correo,
      sedeId: sedeId,
    );
    if (snapshot == null || !snapshot.exists) {
      return null;
    }

    final certificado = _extraerCertificadoDigitalP12(snapshot.data());
    if (certificado == null) {
      return null;
    }

    return _sanitizarCertificadoDigitalP12(certificado);
  }

  Future<Map<String, dynamic>> registrarCertificadoDigitalUsuario({
    String? userDocId,
    required String correo,
    String? sedeId,
    required String accountPassword,
    required String certificatePassword,
    required Uint8List fileBytes,
    required String fileName,
    required String mimeType,
  }) async {
    final normalizedFileName = fileName.trim();
    final normalizedMimeType = mimeType.trim().toLowerCase();

    if (accountPassword.trim().isEmpty) {
      throw Exception(
        'Ingresa tu clave actual de la cuenta para registrar el certificado.',
      );
    }

    if (certificatePassword.trim().isEmpty) {
      throw Exception('Ingresa la clave del certificado .p12.');
    }

    if (fileBytes.isEmpty) {
      throw Exception('Selecciona un archivo .p12 o .pfx valido.');
    }

    if (fileBytes.lengthInBytes > _certificadoDigitalMaxBytes) {
      throw Exception(
        'El certificado supera el tamano permitido. Usa un archivo .p12 o .pfx de hasta 512 KB.',
      );
    }

    final lowerName = normalizedFileName.toLowerCase();
    if (!(lowerName.endsWith('.p12') || lowerName.endsWith('.pfx'))) {
      throw Exception('El certificado debe estar en formato .p12 o .pfx.');
    }

    final userDocIdValue = userDocId?.trim() ?? '';
    final sedeIdValue = sedeId?.trim() ?? '';

    try {
      final response = await _callSecureFunction(
        'registerDigitalCertificate',
        payload: {
          if (userDocIdValue.isNotEmpty) 'userDocId': userDocIdValue,
          'correo': _normalizarCorreo(correo),
          if (sedeIdValue.isNotEmpty) 'sedeId': sedeIdValue,
          'passwordActual': accountPassword.trim(),
          'certificatePassword': certificatePassword.trim(),
          'certificateBase64': base64Encode(fileBytes),
          'fileName': normalizedFileName,
          'mimeType': normalizedMimeType.isEmpty
              ? 'application/x-pkcs12'
              : normalizedMimeType,
        },
      );

      final certificado = response['certificadoDigitalP12'];
      if (certificado is Map<String, dynamic>) {
        return certificado;
      }
      if (certificado is Map) {
        return certificado.map((key, value) => MapEntry(key.toString(), value));
      }
      return <String, dynamic>{};
    } catch (error) {
      if (_shouldUseLocalDigitalCertificateFallback(error)) {
        return _registrarCertificadoDigitalUsuarioEnLocal(
          userDocId: userDocId,
          correo: correo,
          sedeId: sedeId,
          accountPassword: accountPassword,
          certificatePassword: certificatePassword,
          fileBytes: fileBytes,
          fileName: normalizedFileName,
          mimeType: normalizedMimeType.isEmpty
              ? 'application/x-pkcs12'
              : normalizedMimeType,
        );
      }
      rethrow;
    }
  }

  Future<void> eliminarCertificadoDigitalUsuario({
    String? userDocId,
    required String correo,
    String? sedeId,
    required String accountPassword,
  }) async {
    if (accountPassword.trim().isEmpty) {
      throw Exception(
        'Ingresa tu clave actual de la cuenta para eliminar el certificado.',
      );
    }

    final userDocIdValue = userDocId?.trim() ?? '';
    final sedeIdValue = sedeId?.trim() ?? '';

    try {
      await _callSecureFunction(
        'deleteDigitalCertificate',
        payload: {
          if (userDocIdValue.isNotEmpty) 'userDocId': userDocIdValue,
          'correo': _normalizarCorreo(correo),
          if (sedeIdValue.isNotEmpty) 'sedeId': sedeIdValue,
          'passwordActual': accountPassword.trim(),
        },
      );
    } catch (error) {
      if (_shouldUseLocalDigitalCertificateFallback(error)) {
        await _eliminarCertificadoDigitalUsuarioEnLocal(
          userDocId: userDocId,
          correo: correo,
          sedeId: sedeId,
          accountPassword: accountPassword,
        );
        return;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> validarCertificadoDigitalUsuario({
    String? userDocId,
    required String correo,
    String? sedeId,
    required String certificatePassword,
  }) async {
    if (certificatePassword.trim().isEmpty) {
      throw Exception('Ingresa la clave del certificado .p12.');
    }

    final userDocIdValue = userDocId?.trim() ?? '';
    final sedeIdValue = sedeId?.trim() ?? '';

    try {
      final response = await _callSecureFunction(
        'verifyDigitalCertificatePassword',
        payload: {
          if (userDocIdValue.isNotEmpty) 'userDocId': userDocIdValue,
          'correo': _normalizarCorreo(correo),
          if (sedeIdValue.isNotEmpty) 'sedeId': sedeIdValue,
          'certificatePassword': certificatePassword.trim(),
        },
      );

      final certificado = response['certificadoDigitalP12'];
      if (certificado is Map<String, dynamic>) {
        return certificado;
      }
      if (certificado is Map) {
        return certificado.map((key, value) => MapEntry(key.toString(), value));
      }
      return <String, dynamic>{};
    } catch (error) {
      if (_shouldUseLocalDigitalCertificateFallback(error)) {
        return _validarCertificadoDigitalUsuarioEnLocal(
          userDocId: userDocId,
          correo: correo,
          sedeId: sedeId,
          certificatePassword: certificatePassword,
        );
      }
      rethrow;
    }
  }

  Future<Uint8List> firmarPdfConCertificadoDigital({
    String? userDocId,
    required String correo,
    String? sedeId,
    required String certificatePassword,
    required Uint8List pdfBytes,
    String? reason,
    String? signerName,
    String? location,
    String? contactInfo,
  }) async {
    if (pdfBytes.isEmpty) {
      throw Exception('No se recibio un PDF valido para firmar.');
    }

    final userDocIdValue = userDocId?.trim() ?? '';
    final sedeIdValue = sedeId?.trim() ?? '';
    final reasonValue = reason?.trim() ?? '';
    final signerNameValue = signerName?.trim() ?? '';
    final locationValue = location?.trim() ?? '';
    final contactInfoValue = contactInfo?.trim() ?? '';

    try {
      final response = await _callSecureFunction(
        'signPdfWithDigitalCertificate',
        payload: {
          if (userDocIdValue.isNotEmpty) 'userDocId': userDocIdValue,
          'correo': _normalizarCorreo(correo),
          if (sedeIdValue.isNotEmpty) 'sedeId': sedeIdValue,
          'certificatePassword': certificatePassword.trim(),
          'pdfBase64': base64Encode(pdfBytes),
          if (reasonValue.isNotEmpty) 'reason': reasonValue,
          if (signerNameValue.isNotEmpty) 'signerName': signerNameValue,
          if (locationValue.isNotEmpty) 'location': locationValue,
          if (contactInfoValue.isNotEmpty) 'contactInfo': contactInfoValue,
        },
      );

      final signedPdfBase64 = (response['signedPdfBase64'] ?? '')
          .toString()
          .trim();
      if (signedPdfBase64.isEmpty) {
        throw Exception('La API no devolvio un PDF firmado.');
      }

      try {
        return base64Decode(signedPdfBase64);
      } catch (_) {
        throw Exception('No se pudo leer el PDF firmado devuelto por la API.');
      }
    } catch (error) {
      if (_shouldUseLocalDigitalCertificateFallback(error)) {
        return _firmarPdfConCertificadoDigitalEnLocal(
          userDocId: userDocId,
          correo: correo,
          sedeId: sedeId,
          certificatePassword: certificatePassword,
          pdfBytes: pdfBytes,
        );
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _registrarCertificadoDigitalUsuarioEnLocal({
    String? userDocId,
    required String correo,
    String? sedeId,
    required String accountPassword,
    required String certificatePassword,
    required Uint8List fileBytes,
    required String fileName,
    required String mimeType,
  }) async {
    final snapshot = await _findUserSnapshotByIdentity(
      userDocId: userDocId,
      correo: correo,
      sedeId: sedeId,
    );
    if (snapshot == null || !snapshot.exists) {
      throw Exception('No se encontro el perfil del usuario.');
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final passwordValida = await _validarPasswordUsuario(
      userRef: snapshot.reference,
      data: data,
      password: accountPassword.trim(),
    );
    if (!passwordValida) {
      throw Exception('La clave actual de la cuenta no es correcta.');
    }

    final passwordPayload = await _crearPayloadPasswordSeguro(
      certificatePassword.trim(),
    );
    final now = DateTime.now();
    final fingerprint = base64Url
        .encode(
          utf8.encode(
            '${fileName.trim().toLowerCase()}|${fileBytes.lengthInBytes}|${now.toIso8601String()}',
          ),
        )
        .replaceAll('=', '');

    final certificadoLocal = <String, dynamic>{
      'estado': 'activo',
      'provider': 'p12_localhost_preview',
      'localPreviewOnly': true,
      'fileName': fileName.trim().isEmpty ? 'certificado_local.p12' : fileName,
      'mimeType': mimeType.trim().isEmpty
          ? 'application/x-pkcs12'
          : mimeType.trim(),
      'encryptedBase64': base64Encode(fileBytes),
      ...passwordPayload,
      'subject': 'Vista previa localhost',
      'issuer': 'Vista previa localhost',
      'serialNumber': fingerprint,
      'fingerprintSha256': fingerprint,
      'validFrom': Timestamp.fromDate(now),
      'validTo': Timestamp.fromDate(now.add(const Duration(days: 365))),
      'actualizadoEn': FieldValue.serverTimestamp(),
    };

    await snapshot.reference.set({
      _localPreviewCertificateField: certificadoLocal,
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return _sanitizarCertificadoDigitalP12(certificadoLocal);
  }

  Future<void> _eliminarCertificadoDigitalUsuarioEnLocal({
    String? userDocId,
    required String correo,
    String? sedeId,
    required String accountPassword,
  }) async {
    final snapshot = await _findUserSnapshotByIdentity(
      userDocId: userDocId,
      correo: correo,
      sedeId: sedeId,
    );
    if (snapshot == null || !snapshot.exists) {
      throw Exception('No se encontro el perfil del usuario.');
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final passwordValida = await _validarPasswordUsuario(
      userRef: snapshot.reference,
      data: data,
      password: accountPassword.trim(),
    );
    if (!passwordValida) {
      throw Exception('La clave actual de la cuenta no es correcta.');
    }

    await snapshot.reference.set({
      _localPreviewCertificateField: FieldValue.delete(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>> _validarCertificadoDigitalUsuarioEnLocal({
    String? userDocId,
    required String correo,
    String? sedeId,
    required String certificatePassword,
  }) async {
    final snapshot = await _findUserSnapshotByIdentity(
      userDocId: userDocId,
      correo: correo,
      sedeId: sedeId,
    );
    if (snapshot == null || !snapshot.exists) {
      throw Exception('No se encontro el perfil del usuario.');
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final certificado = _extraerCertificadoDigitalP12(data);
    if (!_certificadoDigitalConfigurado(certificado)) {
      throw Exception('No tienes un certificado digital .p12 registrado.');
    }

    final hash = (certificado?['passwordHash'] ?? '').toString().trim();
    final salt = (certificado?['passwordSalt'] ?? '').toString().trim();
    if (hash.isEmpty || salt.isEmpty) {
      throw Exception(
        'El certificado de prueba no tiene una clave valida configurada.',
      );
    }

    final passwordValida = await _passwordSecurity.verifyPassword(
      password: certificatePassword.trim(),
      expectedHash: hash,
      salt: salt,
    );
    if (!passwordValida) {
      throw Exception('La clave del certificado .p12 no es correcta.');
    }

    return _sanitizarCertificadoDigitalP12(certificado!);
  }

  Future<Uint8List> _firmarPdfConCertificadoDigitalEnLocal({
    String? userDocId,
    required String correo,
    String? sedeId,
    required String certificatePassword,
    required Uint8List pdfBytes,
  }) async {
    await _validarCertificadoDigitalUsuarioEnLocal(
      userDocId: userDocId,
      correo: correo,
      sedeId: sedeId,
      certificatePassword: certificatePassword,
    );

    return Uint8List.fromList(pdfBytes);
  }

  Future<void> guardarPdfFinalSolicitud({
    required String idDoc,
    required Uint8List pdfBytes,
    required String fileName,
    required String snapshotToken,
    bool firmadoDigitalmente = false,
    bool localPreviewOnly = false,
    String? generatedByEmail,
    String? generatedByName,
  }) async {
    if (pdfBytes.isEmpty) {
      throw Exception('No se recibio un PDF valido para guardar.');
    }

    if (pdfBytes.lengthInBytes > _pdfFinalFirestoreMaxBytes) {
      throw Exception(
        'El PDF final supera el tamano permitido para guardado interno. Reduce el peso de las firmas o usa una version mas liviana.',
      );
    }

    final solicitudRef = _db.collection('solicitudes').doc(idDoc);
    final documentoRef = solicitudRef.collection('documentos').doc('pdf_final');
    final now = DateTime.now();
    final generatedByEmailValue = generatedByEmail?.trim() ?? '';
    final generatedByNameValue = generatedByName?.trim() ?? '';
    await documentoRef.set({
      'estado': 'activo',
      'mimeType': 'application/pdf',
      'fileName': fileName.trim().isEmpty ? 'solicitud_firmada.pdf' : fileName,
      'blob': Blob(pdfBytes),
      'tamanoBytes': pdfBytes.lengthInBytes,
      'snapshotToken': snapshotToken.trim(),
      'firmadoDigitalmente': firmadoDigitalmente,
      'localPreviewOnly': localPreviewOnly,
      if (generatedByEmailValue.isNotEmpty)
        'generatedByEmail': generatedByEmailValue,
      if (generatedByNameValue.isNotEmpty)
        'generatedByName': generatedByNameValue,
      'generadoEn': FieldValue.serverTimestamp(),
      'generadoEnCliente': Timestamp.fromDate(now),
    }, SetOptions(merge: true));

    await solicitudRef.set({
      'pdfFinalDisponible': true,
      'pdfFinalSnapshotToken': snapshotToken.trim(),
      'pdfFinalFirmadoDigitalmente': firmadoDigitalmente,
      'pdfFinalActualizadoEn': FieldValue.serverTimestamp(),
      'documentoPdfFinal': FieldValue.delete(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> guardarFirmaPerfilUsuario({
    String? userDocId,
    required String correo,
    String? sedeId,
    required String passwordActual,
    required String signingPassword,
    required Uint8List fileBytes,
    required String fileName,
    required String mimeType,
  }) async {
    final password = passwordActual.trim();
    final signingKey = signingPassword.trim();
    final normalizedMimeType = mimeType.trim().toLowerCase();
    final normalizedFileName = fileName.trim();

    if (password.isEmpty) {
      throw Exception('Ingresa tu clave actual para guardar la firma.');
    }

    if (signingKey.isEmpty) {
      throw Exception('Define la clave de firma que usaras al firmar.');
    }

    if (signingKey.length < 4) {
      throw Exception(
        'La clave de firma debe tener al menos 4 caracteres.',
      );
    }

    if (fileBytes.isEmpty) {
      throw Exception('Selecciona un archivo de firma valido.');
    }

    if (fileBytes.lengthInBytes > _firmaPerfilMaxBytes) {
      throw Exception(
        'La firma supera el tamano permitido. Usa una imagen PNG o JPG liviana de hasta 180 KB.',
      );
    }

    const allowedMimeTypes = <String>{
      'image/png',
      'image/jpeg',
      'image/jpg',
      'image/webp',
    };
    if (!allowedMimeTypes.contains(normalizedMimeType)) {
      throw Exception('La firma debe estar en formato PNG, JPG o WEBP.');
    }

    final snapshot = await _findUserSnapshotByIdentity(
      userDocId: userDocId,
      correo: correo,
      sedeId: sedeId,
    );
    if (snapshot == null || !snapshot.exists) {
      throw Exception('No se encontro el perfil del usuario.');
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final passwordValida = await _validarPasswordUsuario(
      userRef: snapshot.reference,
      data: data,
      password: password,
    );
    if (!passwordValida) {
      throw Exception('La clave actual no es correcta.');
    }

    final signingKeyPayload = await _passwordSecurity.hashPassword(signingKey);

    await snapshot.reference.set({
      'firmaPerfil': {
        'estado': 'activa',
        'metodo': 'firma_interna_con_clave',
        'requiereClaveFirma': true,
        'fileName': normalizedFileName.isEmpty
            ? 'firma.png'
            : normalizedFileName,
        'mimeType': normalizedMimeType,
        'imageBase64': base64Encode(fileBytes),
        'tamanoBytes': fileBytes.lengthInBytes,
        'claveFirmaHash': signingKeyPayload.hash,
        'claveFirmaSalt': signingKeyPayload.salt,
        'claveFirmaAlgorithm': signingKeyPayload.algorithm,
        'claveFirmaVersion': signingKeyPayload.version,
        'claveFirmaIterations': signingKeyPayload.iterations,
        'actualizadoEn': FieldValue.serverTimestamp(),
      },
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> eliminarFirmaPerfilUsuario({
    String? userDocId,
    required String correo,
    String? sedeId,
    required String passwordActual,
  }) async {
    final password = passwordActual.trim();
    if (password.isEmpty) {
      throw Exception('Ingresa tu clave actual para eliminar la firma.');
    }

    final snapshot = await _findUserSnapshotByIdentity(
      userDocId: userDocId,
      correo: correo,
      sedeId: sedeId,
    );
    if (snapshot == null || !snapshot.exists) {
      throw Exception('No se encontro el perfil del usuario.');
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final passwordValida = await _validarPasswordUsuario(
      userRef: snapshot.reference,
      data: data,
      password: password,
    );
    if (!passwordValida) {
      throw Exception('La clave actual no es correcta.');
    }

    await snapshot.reference.set({
      'firmaPerfil': FieldValue.delete(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>> autorizarFirmaPerfilUsuario({
    String? userDocId,
    required String correo,
    String? sedeId,
    required String signingPassword,
    bool requireDigitalCertificate = false,
  }) async {
    final signingKey = signingPassword.trim();
    if (signingKey.isEmpty) {
      throw Exception(
        requireDigitalCertificate
            ? 'Ingresa la clave del certificado .p12 para continuar.'
            : 'Ingresa tu clave de firma para continuar.',
      );
    }

    final snapshot = await _findUserSnapshotByIdentity(
      userDocId: userDocId,
      correo: correo,
      sedeId: sedeId,
    );
    if (snapshot == null || !snapshot.exists) {
      throw Exception('No se encontro el perfil del usuario.');
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final firmaPerfil = _extraerFirmaPerfil(data);
    final certificadoDigitalP12 = _extraerCertificadoDigitalP12(data);
    if (requireDigitalCertificate) {
      if (!_certificadoDigitalConfigurado(certificadoDigitalP12)) {
        throw Exception(
          'Debes registrar primero tu certificado digital .p12 en tu perfil.',
        );
      }

      final certificadoValidado = await validarCertificadoDigitalUsuario(
        userDocId: snapshot.id,
        correo: correo,
        sedeId: sedeId,
        certificatePassword: signingKey,
      );

      return {
        ..._sanitizarDatosUsuario(data),
        'docId': snapshot.id,
        '_metodoFirmaAutorizado': 'certificado_digital_p12',
        'certificadoDigitalP12': certificadoValidado,
      };
    }

    if (!_firmaPerfilTieneImagen(firmaPerfil)) {
      throw Exception(
        'Debes registrar primero tu archivo de firma en tu perfil.',
      );
    }

    final claveValida = await _validarClaveFirmaPerfil(
      userRef: snapshot.reference,
      data: data,
      signingPassword: signingKey,
    );
    if (!claveValida) {
      if (_firmaPerfilTieneClaveFirma(firmaPerfil)) {
        throw Exception('La clave de firma no es correcta.');
      }
      throw Exception(
        'Tu firma guardada todavia no tiene clave de firma. Actualizala desde tu perfil para continuar.',
      );
    }

    return {
      ..._sanitizarDatosUsuario(data),
      'docId': snapshot.id,
    };
  }

  Future<bool> _validarClaveFirmaPerfil({
    required DocumentReference<Map<String, dynamic>> userRef,
    required Map<String, dynamic> data,
    required String signingPassword,
  }) async {
    final firmaPerfil = _extraerFirmaPerfil(data);
    final hash = (firmaPerfil?['claveFirmaHash'] ?? '').toString().trim();
    final salt = (firmaPerfil?['claveFirmaSalt'] ?? '').toString().trim();

    if (hash.isNotEmpty && salt.isNotEmpty) {
      return _passwordSecurity.verifyPassword(
        password: signingPassword,
        expectedHash: hash,
        salt: salt,
      );
    }

    return _validarPasswordUsuario(
      userRef: userRef,
      data: data,
      password: signingPassword,
    );
  }

  Future<Map<String, dynamic>> _resolverDatosFirmaElectronica({
    String? correo,
    String? nombre,
    Map<String, dynamic>? fallbackUserData,
    String? sedeIdFallback,
  }) async {
    final now = DateTime.now();
    final fallback = fallbackUserData == null
        ? null
        : Map<String, dynamic>.from(fallbackUserData);

    var correoNormalizado = MatrizApprovalFlow.normalizeEmail(
      correo ?? fallback?['correo'],
    );
    Map<String, dynamic>? userData = fallback;

    if ((userData == null || userData.isEmpty) && correoNormalizado.isNotEmpty) {
      userData = await _obtenerUsuarioPorCorreo(correoNormalizado);
    }

    correoNormalizado = MatrizApprovalFlow.normalizeEmail(
      correoNormalizado.isNotEmpty ? correoNormalizado : userData?['correo'],
    );

    final nombreFallback = (nombre ?? '').trim();
    final nombreFirmante = userData != null
        ? UserRoleAccess.displayNameForUser(userData)
        : (nombreFallback.isNotEmpty
              ? nombreFallback
              : (correoNormalizado.isNotEmpty ? correoNormalizado : 'Usuario'));

    final rolFirmante = userData != null
        ? UserRoleAccess.displayRoleForUser(userData)
        : '';
    final cargoFirmante =
        (userData?['cargo'] ?? userData?['especialidad'] ?? '')
            .toString()
            .trim();
    final cedulaFirmante = (userData?['cedula'] ?? '').toString().trim();
    final sedeId = userData != null
        ? SedeAccess.resolveSedeId(userData)
        : SedeAccess.normalize(sedeIdFallback);
    final certificadoDigitalP12 = _extraerCertificadoDigitalP12(userData);
    final metodoAutorizado = (userData?['_metodoFirmaAutorizado'] ?? '')
        .toString()
        .trim();
    final firmaIdBase =
        '${correoNormalizado.isEmpty ? nombreFirmante : correoNormalizado}|${now.toIso8601String()}';
    final firmaId = base64Url
        .encode(utf8.encode(firmaIdBase))
        .replaceAll('=', '');
    final metodoFirma = metodoAutorizado.isNotEmpty
        ? metodoAutorizado
        : (_certificadoDigitalConfigurado(certificadoDigitalP12)
              ? 'certificado_digital_p12'
              : 'firma_interna_con_clave');
    final fingerprintCertificado =
        (certificadoDigitalP12?['fingerprintSha256'] ?? '').toString().trim();
    final serialCertificado =
        (certificadoDigitalP12?['serialNumber'] ?? '').toString().trim();
    final qrData = <String>[
      'INTESUD-FIRMA',
      firmaId,
      metodoFirma,
      if (correoNormalizado.isNotEmpty) correoNormalizado,
      if (cedulaFirmante.isNotEmpty) cedulaFirmante,
      if (sedeId.isNotEmpty) sedeId,
      now.toIso8601String(),
      if (fingerprintCertificado.isNotEmpty)
        fingerprintCertificado.substring(
          0,
          fingerprintCertificado.length > 24
              ? 24
              : fingerprintCertificado.length,
        ),
    ].join('|');

    return {
      'nombre': nombreFirmante,
      if (correoNormalizado.isNotEmpty) 'correo': correoNormalizado,
      if (rolFirmante.isNotEmpty) 'rol': rolFirmante,
      if (cargoFirmante.isNotEmpty) 'cargo': cargoFirmante,
      if (cedulaFirmante.isNotEmpty) 'cedula': cedulaFirmante,
      if (sedeId.isNotEmpty) 'sedeId': sedeId,
      if (sedeId.isNotEmpty) 'sede': SedeAccess.displayNameForId(sedeId),
      if (fingerprintCertificado.isNotEmpty)
        'certFingerprint': fingerprintCertificado,
      if (serialCertificado.isNotEmpty) 'certSerialNumber': serialCertificado,
      'metodo': metodoFirma,
      'firmaId': firmaId,
      'qrData': qrData,
      'firmadoEnCliente': Timestamp.fromDate(now),
    };
  }

  Map<String, dynamic> _buildFirmaElectronicaMap({
    required Map<String, dynamic> signerData,
    required String etapa,
    required String accion,
  }) {
    final metodo = (signerData['metodo'] ?? '').toString().trim();
    final payload = <String, dynamic>{
      'estado': 'firmado',
      'etapa': etapa,
      'accion': accion,
      'metodo': metodo.isEmpty ? 'certificado_digital_p12' : metodo,
      'version': 2,
      'firmadoEn': FieldValue.serverTimestamp(),
      'firmadoEnCliente':
          signerData['firmadoEnCliente'] ?? Timestamp.fromDate(DateTime.now()),
    };

    for (final key in const [
      'nombre',
      'correo',
      'rol',
      'cargo',
      'cedula',
      'sedeId',
      'sede',
      'firmaId',
      'qrData',
      'certFingerprint',
      'certSerialNumber',
    ]) {
      final value = signerData[key];
      if (value == null) {
        continue;
      }
      if (value is String && value.trim().isEmpty) {
        continue;
      }
      payload[key] = value;
    }

    return payload;
  }

  Map<String, dynamic> _buildFirmaElectronicaUpdatePayload({
    required String prefix,
    required Map<String, dynamic> signerData,
    required String etapa,
    required String accion,
  }) {
    final firma = _buildFirmaElectronicaMap(
      signerData: signerData,
      etapa: etapa,
      accion: accion,
    );
    final payload = <String, dynamic>{};
    firma.forEach((key, value) {
      payload['$prefix.$key'] = value;
    });
    return payload;
  }

  bool _tieneArchivoFirmaElectronica(Map<String, dynamic> signerData) {
    return (signerData['firmaId'] ?? '').toString().trim().isNotEmpty;
  }

  Future<void> registrarAceptacionTerminos({
    required String userDocId,
    required String correo,
    required String version,
    required String canal,
  }) async {
    final docId = userDocId.trim();
    final correoNormalizado = _normalizarCorreo(correo);

    if (docId.isEmpty || correoNormalizado.isEmpty || version.trim().isEmpty) {
      return;
    }

    await _db.collection('usuarios').doc(docId).set({
      'consentimientoDatos': {
        'aceptado': true,
        'correo': correoNormalizado,
        'version': version.trim(),
        'canal': canal.trim().isEmpty ? 'desconocido' : canal.trim(),
        'aceptadoEn': FieldValue.serverTimestamp(),
      },
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<PasswordRecoveryStartResult> solicitarRecuperacionPassword({
    required String correo,
  }) async {
    final correoNormalizado = _normalizarCorreo(correo);

    if (correoNormalizado.isEmpty) {
      throw Exception('Ingrese un correo valido.');
    }

    try {
      final response = await _callSecurePasswordFunction(
        'requestPasswordRecovery',
        payload: {'correo': correoNormalizado},
      );

      return PasswordRecoveryStartResult(
        codeSent: response['delivery'] == 'device',
        requiresSupport: response['delivery'] != 'device',
        message:
            (response['message'] ??
                    'Si tu cuenta tiene un dispositivo confiable vinculado, recibiras un codigo temporal.')
                .toString(),
      );
    } catch (error) {
      if (!_canUseLocalPasswordRecoveryFallback()) {
        rethrow;
      }

      debugPrint(
        'No se pudo usar la recuperacion segura remota. '
        'Se aplicara el respaldo local de desarrollo: $error',
      );
      return _solicitarRecuperacionPasswordEnFirestore(correoNormalizado);
    }
  }

  Future<void> confirmarRecuperacionPassword({
    required String correo,
    required String codigo,
    required String nuevaPassword,
  }) async {
    final correoNormalizado = _normalizarCorreo(correo);
    final codigoLimpio = codigo.trim();
    final nuevaPasswordLimpia = nuevaPassword.trim();

    if (correoNormalizado.isEmpty) {
      throw Exception('Ingrese un correo valido.');
    }

    if (codigoLimpio.length != 6) {
      throw Exception('Ingrese el codigo temporal de 6 digitos.');
    }

    _validarPasswordSeguraOrThrow(nuevaPasswordLimpia);

    try {
      await _callSecurePasswordFunction(
        'confirmPasswordRecovery',
        payload: {
          'correo': correoNormalizado,
          'codigo': codigoLimpio,
          'nuevaPassword': nuevaPasswordLimpia,
        },
      );
      return;
    } catch (error) {
      if (!_canUseLocalPasswordRecoveryFallback()) {
        rethrow;
      }

      debugPrint(
        'No se pudo confirmar la recuperacion segura remota. '
        'Se aplicara el respaldo local de desarrollo: $error',
      );
    }

    await _confirmarRecuperacionPasswordEnFirestore(
      correo: correoNormalizado,
      codigo: codigoLimpio,
      nuevaPassword: nuevaPasswordLimpia,
    );
  }

  Future<void> cambiarPasswordConActual({
    required String correo,
    required String passwordActual,
    required String nuevaPassword,
  }) async {
    final correoNormalizado = _normalizarCorreo(correo);
    final actualLimpia = passwordActual.trim();
    final nuevaPasswordLimpia = nuevaPassword.trim();

    if (correoNormalizado.isEmpty) {
      throw Exception('Ingrese un correo valido.');
    }

    if (actualLimpia.isEmpty) {
      throw Exception('Ingrese su contrasena actual.');
    }

    _validarPasswordSeguraOrThrow(nuevaPasswordLimpia);

    if (actualLimpia == nuevaPasswordLimpia) {
      throw Exception(
        'La nueva contrasena debe ser diferente de la contrasena actual.',
      );
    }

    try {
      await _callSecurePasswordFunction(
        'changePasswordWithCurrentPassword',
        payload: {
          'correo': correoNormalizado,
          'passwordActual': actualLimpia,
          'nuevaPassword': nuevaPasswordLimpia,
        },
      );
      return;
    } catch (error) {
      debugPrint(
        'No se pudo usar la funcion segura de cambio de contrasena. '
        'Se aplicara el respaldo en Firestore: $error',
      );
    }

    await _cambiarPasswordConActualEnFirestore(
      correo: correoNormalizado,
      passwordActual: actualLimpia,
      nuevaPassword: nuevaPasswordLimpia,
    );
  }

  Future<void> actualizarPasswordPorCorreo({
    required String correo,
    required String nuevaPassword,
  }) async {
    final correoNormalizado = _normalizarCorreo(correo);
    final passwordLimpia = nuevaPassword.trim();

    if (correoNormalizado.isEmpty) {
      throw Exception('Ingrese un correo valido.');
    }

    if (passwordLimpia.isEmpty) {
      throw Exception('Ingrese una nueva contrasena.');
    }

    _validarPasswordSeguraOrThrow(passwordLimpia);

    final query = await _db
        .collection('usuarios')
        .where('correo', isEqualTo: correoNormalizado)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw Exception('No existe un usuario registrado con ese correo.');
    }

    final passwordPayload = await _crearPayloadPasswordSeguro(passwordLimpia);

    await query.docs.first.reference.update({
      ...passwordPayload,
      'password': FieldValue.delete(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    });
  }

  bool _esHorarioTiempoCompleto(String idHorario, Map<String, dynamic> data) {
    if (idHorario.toUpperCase().startsWith('TC')) {
      return true;
    }

    final valor = data['es_tiempo_completo'];
    if (valor is bool) {
      return valor;
    }

    return false;
  }

  String _normalizarHoraDesdeTexto(String value) {
    final partes = value.trim().split(':');
    if (partes.length < 2) {
      return value.trim();
    }

    final horas = int.tryParse(partes[0]) ?? 0;
    final minutos = int.tryParse(partes[1]) ?? 0;
    return '${horas.toString().padLeft(2, '0')}:${minutos.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic>? _crearHorarioFallbackDesdeIdentificador(
    String idHorario,
  ) {
    final raw = idHorario.trim();
    if (raw.isEmpty) {
      return null;
    }

    final matches = RegExp(r'(\d{1,2}:\d{2})').allMatches(raw).toList();
    if (matches.length < 2) {
      return null;
    }

    final entrada = _normalizarHoraDesdeTexto(matches[0].group(1) ?? '');
    final salida = _normalizarHoraDesdeTexto(matches[1].group(1) ?? '');
    if (entrada.isEmpty || salida.isEmpty) {
      return null;
    }

    final horarioNormalizado = raw.toUpperCase();
    return {
      'nombre': raw,
      'entrada': entrada,
      'salida': salida,
      'es_tiempo_completo': horarioNormalizado.startsWith('TC'),
      'origen': 'fallback_identificador',
    };
  }

  Map<String, String>? _resolverHorarioAlmuerzoAsignado(
    Map<String, dynamic>? usuarioData,
  ) {
    if (usuarioData == null) {
      return null;
    }

    final inicio = (usuarioData['almuerzo_inicio_asignado'] ?? '')
        .toString()
        .trim();
    final fin = (usuarioData['almuerzo_fin_asignado'] ?? '').toString().trim();
    final label = (usuarioData['almuerzo_horario_label'] ?? '')
        .toString()
        .trim();

    if (inicio.isEmpty || fin.isEmpty) {
      return null;
    }

    return {
      'inicio': inicio,
      'fin': fin,
      'label': label.isEmpty ? '$inicio a $fin' : label,
      'origen': 'asignado',
    };
  }

  Future<Map<String, String>?> _resolverHorarioAlmuerzoPorHorario(
    List<dynamic> listaHorarios,
  ) async {
    final idHorarioTC = listaHorarios.firstWhere(
      (h) => h.toString().trim().toUpperCase().startsWith('TC'),
      orElse: () => '',
    );

    if (idHorarioTC.toString().trim().isEmpty) {
      return null;
    }

    final doc = await _db.collection('horarios').doc(idHorarioTC).get();
    if (!doc.exists) {
      return null;
    }

    final inicio = (doc['almuerzo_inicio'] ?? '').toString().trim();
    final fin = (doc['almuerzo_fin'] ?? '').toString().trim();
    if (inicio.isEmpty || fin.isEmpty) {
      return null;
    }

    return {
      'inicio': inicio,
      'fin': fin,
      'label': '$inicio a $fin',
      'origen': 'horario_general',
    };
  }

  Future<Map<String, String>?> _resolverHorarioAlmuerzoUsuario({
    required Map<String, dynamic>? usuarioData,
    required List<dynamic> listaHorarios,
  }) async {
    final asignado = _resolverHorarioAlmuerzoAsignado(usuarioData);
    if (asignado != null) {
      return asignado;
    }

    return _resolverHorarioAlmuerzoPorHorario(listaHorarios);
  }

  Future<Map<String, String>?> obtenerHorarioAlmuerzoUsuario({
    required String correo,
    required List<dynamic> listaHorarios,
  }) async {
    final usuarioData = await _obtenerUsuarioPorCorreo(correo);
    return _resolverHorarioAlmuerzoUsuario(
      usuarioData: usuarioData,
      listaHorarios: listaHorarios,
    );
  }

  List<String> resolverHorariosDisponiblesAlmuerzoUsuario(
    Map<String, dynamic>? usuarioData,
  ) {
    final horariosPrincipales = _sanitizarListaHorariosDesdeUsuario(usuarioData);
    final vinculaciones = resolverVinculacionesAsistenciaUsuario(usuarioData);
    final horariosVinculados = vinculaciones
        .map((vinculacion) => (vinculacion['horarioId'] ?? '').toString().trim())
        .where((horario) => horario.isNotEmpty)
        .toList();

    return {
      ...horariosPrincipales,
      ...horariosVinculados,
    }.toList();
  }

  bool usuarioTieneAlmuerzoHabilitado(Map<String, dynamic>? usuarioData) {
    if (_resolverHorarioAlmuerzoAsignado(usuarioData) != null) {
      return true;
    }

    return resolverHorariosDisponiblesAlmuerzoUsuario(
      usuarioData,
    ).any((horario) => horario.trim().toUpperCase().startsWith('TC'));
  }

  Future<Map<String, Map<String, dynamic>>> _obtenerHorariosPorIds(
    List<dynamic> listaHorarios,
  ) async {
    final ids = listaHorarios
        .map((horario) => horario.toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final resultados = await Future.wait(
      ids.map((id) async {
        final doc = await _db.collection('horarios').doc(id).get();
        if (!doc.exists) {
          return MapEntry<String, Map<String, dynamic>?>(
            id,
            _crearHorarioFallbackDesdeIdentificador(id),
          );
        }

        final data = doc.data() as Map<String, dynamic>;
        return MapEntry<String, Map<String, dynamic>?>(id, {
          ...data,
          'nombre': (data['nombre'] ?? '').toString().trim().isEmpty
              ? id
              : data['nombre'],
        });
      }),
    );

    return {
      for (final entry in resultados)
        if (entry.value != null) entry.key: entry.value!,
    };
  }

  String _mensajeFueraDeHorario({
    required DateTime ahora,
    required List<Map<String, dynamic>> horariosEvaluados,
    required bool esEntrada,
  }) {
    final accion = esEntrada ? 'entrada' : 'salida';

    if (horariosEvaluados.isEmpty) {
      return 'No tienes horarios programados para registrar $accion.';
    }

    horariosEvaluados.sort(
      (a, b) => (a['ventanaInicioMin'] as int).compareTo(
        b['ventanaInicioMin'] as int,
      ),
    );

    final ahoraMin = (ahora.hour * 60) + ahora.minute;
    final primerHorario = horariosEvaluados.first;
    final ultimoHorario = horariosEvaluados.last;
    final primerInicioVentana = primerHorario['ventanaInicioMin'] as int;
    final ultimoFinVentana = ultimoHorario['ventanaFinMin'] as int;

    if (ahoraMin < primerInicioVentana) {
      if (esEntrada) {
        return 'La entrada se habilita 10 minutos antes del horario asignado. Tu proxima ventana sera de ${primerHorario['ventana']} para el horario ${primerHorario['rango']}.';
      }
      return 'Las marcaciones de $accion solo se habilitan 10 minutos antes y 10 minutos despues del horario asignado. Tu proxima ventana es de ${primerHorario['ventana']} para el horario ${primerHorario['rango']}.';
    }

    if (ahoraMin > ultimoFinVentana) {
      return 'La ultima ventana disponible para registrar $accion fue de ${ultimoHorario['ventana']} para el horario ${ultimoHorario['rango']}.';
    }

    Map<String, dynamic>? siguienteHorario;
    for (final horario in horariosEvaluados) {
      if (ahoraMin < (horario['ventanaInicioMin'] as int)) {
        siguienteHorario = horario;
        break;
      }
    }

    if (siguienteHorario != null) {
      if (esEntrada) {
        return 'En este momento no tienes una jornada disponible para registrar entrada. Tu siguiente ventana sera de ${siguienteHorario['ventana']} para el horario ${siguienteHorario['rango']}.';
      }
      return 'En este momento no tienes una ventana activa para registrar $accion. Tu siguiente ventana sera de ${siguienteHorario['ventana']} para el horario ${siguienteHorario['rango']}.';
    }

    if (esEntrada) {
      return 'En este momento no tienes una jornada disponible para registrar entrada.';
    }

    return 'En este momento no tienes una ventana activa para registrar $accion.';
  }

  // Marcación: Busca en la lista de la captura con VALIDACIÓN DE ESTADO
  ({int inicio, int fin})? _parseRangoPermisoHoras(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final matches = RegExp(r'(\d{1,2}):(\d{2})').allMatches(value).toList();
    if (matches.length < 2) {
      return null;
    }

    final inicioHoras = int.tryParse(matches[0].group(1)!);
    final inicioMinutos = int.tryParse(matches[0].group(2)!);
    final finHoras = int.tryParse(matches[1].group(1)!);
    final finMinutos = int.tryParse(matches[1].group(2)!);

    if (inicioHoras == null ||
        inicioMinutos == null ||
        finHoras == null ||
        finMinutos == null) {
      return null;
    }

    return (
      inicio: (inicioHoras * 60) + inicioMinutos,
      fin: (finHoras * 60) + finMinutos,
    );
  }

  bool _mismaFechaCalendario(dynamic fechaSolicitud, DateTime fechaReferencia) {
    DateTime? fecha;

    if (fechaSolicitud is Timestamp) {
      fecha = fechaSolicitud.toDate();
    } else if (fechaSolicitud is DateTime) {
      fecha = fechaSolicitud;
    } else if (fechaSolicitud != null) {
      fecha = DateTime.tryParse(fechaSolicitud.toString());
    }

    if (fecha == null) {
      return false;
    }

    return fecha.year == fechaReferencia.year &&
        fecha.month == fechaReferencia.month &&
        fecha.day == fechaReferencia.day;
  }

  Future<Map<String, String>?> _obtenerPermisoAprobadoVigente({
    required String nombreUsuario,
    String? correoUsuario,
    required DateTime ahora,
    required int ahoraMin,
    String? sedeId,
  }) async {
    final correoNormalizado = _normalizarCorreo(correoUsuario ?? '');
    Query<Map<String, dynamic>> query = _db
        .collection('solicitudes')
        .where('tipo', isEqualTo: 'Permiso')
        .where('estado', isEqualTo: 'aprobado');

    if (sedeId != null && sedeId.trim().isNotEmpty) {
      query = query.where('sedeId', isEqualTo: sedeId.trim());
    }

    QuerySnapshot<Map<String, dynamic>> snapshot;
    if (correoNormalizado.isNotEmpty) {
      snapshot = await query
          .where('colaboradorCorreo', isEqualTo: correoNormalizado)
          .get();
      if (snapshot.docs.isEmpty) {
        snapshot = await query.where('colaborador', isEqualTo: nombreUsuario).get();
      }
    } else {
      snapshot = await query.where('colaborador', isEqualTo: nombreUsuario).get();
    }

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final fechaPermiso =
          data['fechaPermiso'] ?? data['fechaInicio'] ?? data['fechaSolicitud'];
      if (!_mismaFechaCalendario(fechaPermiso, ahora)) {
        continue;
      }

      final horarioPermiso =
          (data['horarioPermiso'] ?? data['horasPermiso'] ?? '')
              .toString()
              .trim();
      final rango = _parseRangoPermisoHoras(horarioPermiso);
      if (rango == null) {
        continue;
      }

      if (ahoraMin >= rango.inicio && ahoraMin <= rango.fin) {
        return {
          'horario': horarioPermiso,
          'motivo': (data['motivo'] ?? '').toString().trim(),
          'documentoId': doc.id,
        };
      }
    }

    return null;
  }

  String _segmentoDocIdSeguro(dynamic value, {String fallback = 'general'}) {
    final limpio = value?.toString().trim().toLowerCase() ?? '';
    final normalizado = limpio.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final compacto = normalizado.replaceAll(RegExp(r'_+'), '_').replaceAll(
      RegExp(r'^_|_$'),
      '',
    );
    return compacto.isEmpty ? fallback : compacto;
  }

  String _claveIdentidadRegistro({
    required String nombreUsuario,
    String? correoUsuario,
  }) {
    final correoNormalizado = _normalizarCorreo(correoUsuario ?? '');
    if (correoNormalizado.isNotEmpty) {
      return _segmentoDocIdSeguro(correoNormalizado, fallback: 'usuario');
    }
    return _segmentoDocIdSeguro(nombreUsuario, fallback: 'usuario');
  }

  String _claveFechaRegistro(DateTime fecha) {
    return DateFormat('yyyyMMdd').format(fecha);
  }

  String _docIdMarcacion({
    required String nombreUsuario,
    String? correoUsuario,
    required DateTime fecha,
    required bool esEntrada,
    required String horarioClave,
    String? tipoVinculacion,
  }) {
    final identidad = _claveIdentidadRegistro(
      nombreUsuario: nombreUsuario,
      correoUsuario: correoUsuario,
    );
    final fechaClave = _claveFechaRegistro(fecha);
    final tipoClave = esEntrada ? 'entrada' : 'salida';
    final horarioSegmento = _segmentoDocIdSeguro(horarioClave);
    final vinculacionSegmento = _segmentoDocIdSeguro(
      tipoVinculacion,
      fallback: 'general',
    );
    return 'marcacion_${identidad}_${fechaClave}_${tipoClave}_${horarioSegmento}_$vinculacionSegmento';
  }

  String _docIdAlmuerzo({
    required String correoUsuario,
    String? nombreUsuario,
    required DateTime fecha,
  }) {
    final identidad = _claveIdentidadRegistro(
      nombreUsuario: nombreUsuario ?? correoUsuario,
      correoUsuario: correoUsuario,
    );
    return 'almuerzo_${identidad}_${_claveFechaRegistro(fecha)}';
  }

  Future<void> _guardarMarcacionIdempotente({
    required String nombreUsuario,
    String? correoUsuario,
    required DateTime fecha,
    required bool esEntrada,
    required String horarioClave,
    String? tipoVinculacion,
    required Map<String, dynamic> payload,
  }) async {
    final docId = _docIdMarcacion(
      nombreUsuario: nombreUsuario,
      correoUsuario: correoUsuario,
      fecha: fecha,
      esEntrada: esEntrada,
      horarioClave: horarioClave,
      tipoVinculacion: tipoVinculacion,
    );
    final ref = _db.collection('asistencias_realizadas').doc(docId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (snapshot.exists) {
        return;
      }

      transaction.set(ref, {
        ...payload,
        'registro_estable': true,
        'idempotencyKey': docId,
      }, SetOptions(merge: true));
    });
  }

  Future<Map<String, String>> registrarMarcacion({
    required String nombreUsuario,
    String? correoUsuario,
    required List<dynamic> listaHorarios,
    required bool esEntrada,
    String? sedeId,
    String? sedeNombre,
    List<Map<String, dynamic>>? vinculacionesAsistencia,
    Map<String, dynamic>? contextoSeleccionado,
  }) async {
    // await _validarUbicacionGPS(); // Descomentar cuando se requiera GPS real

    DateTime ahora = DateTime.now();
    final correoNormalizado = _normalizarCorreo(correoUsuario ?? '');

    // 1. VALIDACIÓN DE DUPLICADOS
    QuerySnapshot ultimoRegistroQuery;
    if (correoNormalizado.isNotEmpty) {
      ultimoRegistroQuery = await _db
          .collection('asistencias_realizadas')
          .where('correo_usuario', isEqualTo: correoNormalizado)
          .orderBy('fecha', descending: true)
          .limit(1)
          .get();
      if (ultimoRegistroQuery.docs.isEmpty) {
        ultimoRegistroQuery = await _db
            .collection('asistencias_realizadas')
            .where('docente', isEqualTo: nombreUsuario)
            .orderBy('fecha', descending: true)
            .limit(1)
            .get();
      }
    } else {
      ultimoRegistroQuery = await _db
          .collection('asistencias_realizadas')
          .where('docente', isEqualTo: nombreUsuario)
          .orderBy('fecha', descending: true)
          .limit(1)
          .get();
    }

    Map<String, dynamic>? ultimoDoc;
    String ultimoTipo = '';
    if (ultimoRegistroQuery.docs.isNotEmpty) {
      ultimoDoc = ultimoRegistroQuery.docs.first.data() as Map<String, dynamic>;
      ultimoTipo = (ultimoDoc['tipo'] ?? "").toString();

      if (esEntrada && ultimoTipo == "ENTRADA") {
        throw Exception(
          "Ya tienes una ENTRADA activa. Debes marcar SALIDA primero.",
        );
      }
      if (!esEntrada && ultimoTipo == "SALIDA") {
        throw Exception(
          "Ya marcaste SALIDA. Debes esperar a tu siguiente bloque para entrar.",
        );
      }
    } else {
      if (!esEntrada) {
        throw Exception(
          "No puedes marcar SALIDA sin haber registrado una ENTRADA previa.",
        );
      }
    }

    // 2. LÓGICA DE HORARIOS
    final usarVinculacionesMultiples =
        (vinculacionesAsistencia != null &&
            vinculacionesAsistencia.isNotEmpty) ||
        contextoSeleccionado != null;

    if (usarVinculacionesMultiples) {
      final ahoraMin = (ahora.hour * 60) + ahora.minute;
      final permisoActivoFuture = _obtenerPermisoAprobadoVigente(
        nombreUsuario: nombreUsuario,
        correoUsuario: correoUsuario,
        ahora: ahora,
        ahoraMin: ahoraMin,
        sedeId: sedeId,
      );
      final vinculacionesNormalizadas =
          vinculacionesAsistencia?.whereType<Map<String, dynamic>>().toList() ??
          listaHorarios
              .map(
                (horario) => _buildVinculacionAsistencia(
                  tipoVinculacion: 'academico',
                  rol: UserRoleAccess.roleTeacher,
                  horarioId: horario.toString(),
                  areaId: '',
                  areaNombre: '',
                  cargo: '',
                ),
              )
              .toList();

      final evaluacion = await _evaluarContextosMarcacion(
        ahora: ahora,
        esEntrada: esEntrada,
        vinculacionesAsistencia: vinculacionesNormalizadas,
        sedeId: sedeId,
      );
      final horariosEvaluados = List<Map<String, dynamic>>.from(
        evaluacion['horariosEvaluados'] as List? ??
            const <Map<String, dynamic>>[],
      );
      final contextosActivos = List<Map<String, dynamic>>.from(
        evaluacion['activos'] as List? ?? const <Map<String, dynamic>>[],
      );
      final horarioEspecial =
          evaluacion['horarioEspecial'] as Map<String, dynamic>?;
      final toleranciaSalidaAntesMinutos =
          evaluacion['toleranciaSalidaAntesMinutos'] as int? ??
          _horarioEspecialToleranciaSalidaAntesDefault;
      final toleranciaSalidaDespuesMinutos =
          evaluacion['toleranciaSalidaDespuesMinutos'] as int? ??
          _horarioEspecialToleranciaSalidaDespuesDefault;
      final ventanaSalidaEspecialInicio =
          evaluacion['ventanaSalidaEspecialInicio'] as int?;
      final ventanaSalidaEspecialFin =
          evaluacion['ventanaSalidaEspecialFin'] as int?;
      final ventanaSalidaEspecialLabel =
          (evaluacion['ventanaSalidaEspecialLabel'] ?? '').toString();

      Map<String, dynamic>? horarioSeleccionado;
      if (contextoSeleccionado != null) {
        final horarioIdForzado = (contextoSeleccionado['horarioId'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
        final tipoForzado = _normalizarTipoVinculacion(
          contextoSeleccionado['tipoVinculacion'],
        );
        for (final contexto in contextosActivos) {
          if ((contexto['horarioId'] ?? '').toString().trim().toUpperCase() ==
                  horarioIdForzado &&
              _normalizarTipoVinculacion(contexto['tipoVinculacion']) ==
                  tipoForzado) {
            horarioSeleccionado = contexto;
            break;
          }
        }
      } else if (contextosActivos.length == 1) {
        horarioSeleccionado = contextosActivos.first;
      } else if (contextosActivos.length > 1) {
        throw Exception(
          'Tienes mas de una jornada disponible en este momento. Debes seleccionar si registras como administrativo o como personal academico.',
        );
      }

      if (!esEntrada && horarioSeleccionado == null) {
        horarioSeleccionado = await _resolverContextoDesdeUltimaEntrada(
          ultimoRegistro: ultimoDoc,
          vinculacionesAsistencia: vinculacionesNormalizadas,
          horarioEspecial: horarioEspecial,
          horaEntradaEspecial: (evaluacion['horaEntradaEspecial'] ?? '')
              .toString(),
          horaSalidaEspecial: (evaluacion['horaSalidaEspecial'] ?? '')
              .toString(),
          ventanaSalidaEspecialLabel: ventanaSalidaEspecialLabel,
        );
      }

      if (!esEntrada &&
          horarioEspecial != null &&
          ventanaSalidaEspecialInicio != null &&
          ventanaSalidaEspecialFin != null &&
          ahoraMin < ventanaSalidaEspecialInicio) {
        throw Exception(
          'La salida especial de hoy se habilita desde ${_minutosAHora(ventanaSalidaEspecialInicio)} y permanece disponible hasta ${_minutosAHora(ventanaSalidaEspecialFin)}.',
        );
      }

      if (horarioSeleccionado == null) {
        if (!esEntrada &&
            horarioEspecial != null &&
            ventanaSalidaEspecialInicio != null &&
            ventanaSalidaEspecialFin != null) {
          if (ahoraMin > ventanaSalidaEspecialFin) {
            throw Exception(
              'La ventana para registrar la salida especial fue de ${_minutosAHora(ventanaSalidaEspecialInicio)} a ${_minutosAHora(ventanaSalidaEspecialFin)}.',
            );
          }
        }

        throw Exception(
          _mensajeFueraDeHorario(
            ahora: ahora,
            horariosEvaluados: horariosEvaluados,
            esEntrada: esEntrada,
          ),
        );
      }

      final horaEntradaAplicada = (horarioSeleccionado['entrada'] ?? '00:00')
          .toString();
      final horaSalidaAplicada = (horarioSeleccionado['salida'] ?? '00:00')
          .toString();
      final horaEntradaBase =
          (horarioSeleccionado['entrada_base'] ?? horaEntradaAplicada)
              .toString();
      final horaSalidaBase =
          (horarioSeleccionado['salida_base'] ?? horaSalidaAplicada).toString();
      final entradaAplicadaMin = _horaEnMinutos(horaEntradaAplicada);
      final salidaAplicadaMin = _horaEnMinutos(horaSalidaAplicada);
      final entradaPuntualFinMin =
          entradaAplicadaMin + _registroMarcacionToleranciaMinutos;
      final salidaCompletaInicioMin =
          salidaAplicadaMin - _registroMarcacionToleranciaMinutos;
      final salidaCompletaFinMin =
          salidaAplicadaMin + _registroMarcacionToleranciaMinutos;
      final horaActualStr = DateFormat('HH:mm').format(ahora);
      final salidaBaseMin = _horaEnMinutos(horaSalidaBase);
      final salidaEspecialDentroDeVentana =
          !esEntrada &&
          horarioEspecial != null &&
          ventanaSalidaEspecialInicio != null &&
          ventanaSalidaEspecialFin != null &&
          ahoraMin >= ventanaSalidaEspecialInicio &&
          ahoraMin <= ventanaSalidaEspecialFin;

      var estado = 'A tiempo';
      var estadoVisible = estado;
      if (esEntrada && ahoraMin > entradaPuntualFinMin) {
        estado = 'Atraso';
        estadoVisible = estado;
      } else if (!esEntrada && salidaEspecialDentroDeVentana) {
        estado = salidaAplicadaMin < salidaBaseMin
            ? 'Salida anticipada autorizada'
            : 'Completada';
        estadoVisible = estado;
      } else if (!esEntrada && ahoraMin < salidaCompletaInicioMin) {
        estado = 'Salida Anticipada';
        estadoVisible = estado;
      } else if (!esEntrada && ahoraMin > salidaCompletaFinMin) {
        estado = 'Completada';
        estadoVisible = 'Salida con retraso';
      } else if (!esEntrada) {
        estado = horarioEspecial != null && salidaAplicadaMin < salidaBaseMin
            ? 'Salida anticipada autorizada'
            : 'Completada';
        estadoVisible = estado;
      }

      final permisoActivo = await permisoActivoFuture;
      final rangoHorarioEspecial = horarioEspecial == null
          ? ''
          : '$horaEntradaAplicada a $horaSalidaAplicada';
      final tipoVinculacion = _normalizarTipoVinculacion(
        horarioSeleccionado['tipoVinculacion'],
      );
      final tipoVinculacionLabel =
          (horarioSeleccionado['tipoVinculacionLabel'] ?? '')
              .toString()
              .trim()
              .isEmpty
          ? _etiquetaTipoVinculacion(tipoVinculacion)
          : (horarioSeleccionado['tipoVinculacionLabel'] ?? '')
                .toString()
                .trim();

      final payload = {
        'docente': nombreUsuario,
        'correo_usuario': correoNormalizado,
        'tipo': esEntrada ? 'ENTRADA' : 'SALIDA',
        'horario_ref': horarioSeleccionado['nombre'],
        'horario_id': (horarioSeleccionado['horarioId'] ?? '')
            .toString()
            .trim(),
        'tipo_vinculacion': tipoVinculacion,
        'tipo_vinculacion_label': tipoVinculacionLabel,
        'rol_vinculado': (horarioSeleccionado['rolVinculado'] ?? '')
            .toString()
            .trim(),
        'cargo_vinculado': (horarioSeleccionado['cargoVinculado'] ?? '')
            .toString()
            .trim(),
        'area_vinculada': (horarioSeleccionado['areaVinculada'] ?? '')
            .toString()
            .trim(),
        'vinculacion_secundaria': horarioSeleccionado['esSecundaria'] == true,
        'hora_marcada': horaActualStr,
        'estado': estado,
        'estado_visible': estadoVisible,
        'fecha': ahora,
        'observacion': 'Registro realizado correctamente.',
        'sedeId': sedeId,
        'sede': sedeNombre,
        'hora_entrada_oficial': horaEntradaAplicada,
        'hora_salida_oficial': horaSalidaAplicada,
        'hora_entrada_base': horaEntradaBase,
        'hora_salida_base': horaSalidaBase,
        'horario_especial_activo': horarioEspecial != null,
        'horario_especial_documento_id':
            horarioSeleccionado['horario_especial_documento_id'],
        'horario_especial_fecha_clave':
            horarioSeleccionado['horario_especial_fecha_clave'],
        'horario_especial_motivo':
            horarioSeleccionado['horario_especial_motivo'],
        'horario_especial_hora_entrada':
            horarioSeleccionado['horario_especial_entrada'],
        'horario_especial_hora_salida':
            horarioSeleccionado['horario_especial_salida'],
        'horario_especial_tolerancia_antes_minutos':
            toleranciaSalidaAntesMinutos,
        'horario_especial_tolerancia_despues_minutos':
            toleranciaSalidaDespuesMinutos,
        'horario_especial_ventana_salida': ventanaSalidaEspecialLabel,
        'horario_especial_rango': rangoHorarioEspecial,
        'permiso_aprobado_activo': permisoActivo != null,
        'permiso_horario': permisoActivo?['horario'],
        'permiso_motivo': permisoActivo?['motivo'],
        'permiso_documento_id': permisoActivo?['documentoId'],
      };

      await _guardarMarcacionIdempotente(
        nombreUsuario: nombreUsuario,
        correoUsuario: correoUsuario,
        fecha: ahora,
        esEntrada: esEntrada,
        horarioClave: (horarioSeleccionado['horarioId'] ??
                horarioSeleccionado['nombre'] ??
                'general')
            .toString(),
        tipoVinculacion: tipoVinculacion,
        payload: payload,
      );

      return {
        'estado': estadoVisible,
        'estadoBase': estado,
        'bloque': '${horarioSeleccionado['nombre']} · $tipoVinculacionLabel',
        'hora': horaActualStr,
        'tipoVinculacion': tipoVinculacion,
        'tipoVinculacionLabel': tipoVinculacionLabel,
        'permisoActivo': permisoActivo != null ? 'true' : 'false',
        'horarioPermiso': permisoActivo?['horario'] ?? '',
        'motivoPermiso': permisoActivo?['motivo'] ?? '',
        'horarioEspecialActivo': horarioEspecial != null ? 'true' : 'false',
        'horarioEspecialRango': rangoHorarioEspecial,
        'horarioEspecialVentanaSalida': ventanaSalidaEspecialLabel,
        'motivoHorarioEspecial':
            (horarioSeleccionado['horario_especial_motivo'] ?? '').toString(),
      };
    }

    Map<String, dynamic>? horarioSeleccionado;
    final ahoraMin = (ahora.hour * 60) + ahora.minute;
    final List<Map<String, dynamic>> horariosEvaluados = [];
    final permisoActivoFuture = _obtenerPermisoAprobadoVigente(
      nombreUsuario: nombreUsuario,
      correoUsuario: correoUsuario,
      ahora: ahora,
      ahoraMin: ahoraMin,
      sedeId: sedeId,
    );
    final horarioEspecial = sedeId != null && sedeId.trim().isNotEmpty
        ? await obtenerHorarioEspecialSede(sedeId: sedeId.trim(), fecha: ahora)
        : null;
    final horaEntradaEspecial = (horarioEspecial?['horaEntradaEspecial'] ?? '')
        .toString()
        .trim();
    final horaSalidaEspecial = (horarioEspecial?['horaSalidaEspecial'] ?? '')
        .toString()
        .trim();
    final toleranciaSalidaAntesMinutos = _resolverToleranciaHorarioEspecial(
      horarioEspecial?['toleranciaSalidaAntesMinutos'],
      _horarioEspecialToleranciaSalidaAntesDefault,
    );
    final toleranciaSalidaDespuesMinutos = _resolverToleranciaHorarioEspecial(
      horarioEspecial?['toleranciaSalidaDespuesMinutos'],
      _horarioEspecialToleranciaSalidaDespuesDefault,
    );
    final salidaEspecialMin = horaSalidaEspecial.isEmpty
        ? null
        : _horaEnMinutos(horaSalidaEspecial);
    final ventanaSalidaEspecialInicio = salidaEspecialMin == null
        ? null
        : salidaEspecialMin - toleranciaSalidaAntesMinutos;
    final ventanaSalidaEspecialFin = salidaEspecialMin == null
        ? null
        : salidaEspecialMin + toleranciaSalidaDespuesMinutos;
    final ventanaSalidaEspecialLabel =
        ventanaSalidaEspecialInicio == null || ventanaSalidaEspecialFin == null
        ? ''
        : '${_minutosAHora(ventanaSalidaEspecialInicio)} a ${_minutosAHora(ventanaSalidaEspecialFin)}';
    final horariosDisponibles = await _obtenerHorariosPorIds(listaHorarios);

    for (final horario in listaHorarios) {
      final id = horario.toString();
      final data = horariosDisponibles[id];
      if (data == null) continue;
      final entradaBase = data['entrada']?.toString() ?? '00:00';
      final salidaBase = data['salida']?.toString() ?? '00:00';
      final entrada = horaEntradaEspecial.isNotEmpty
          ? horaEntradaEspecial
          : entradaBase;
      final salida = horaSalidaEspecial.isNotEmpty
          ? horaSalidaEspecial
          : salidaBase;
      final entradaMin = _horaEnMinutos(entrada);
      final salidaMin = _horaEnMinutos(salida);
      final esTiempoCompleto = _esHorarioTiempoCompleto(id, data);
      final referenciaMarcacionMin = esEntrada ? entradaMin : salidaMin;
      final ventanaNormal = _ventanaMarcacionDesdeReferencia(
        referenciaMarcacionMin,
      );
      final ventanaMarcacionInicio =
          !esEntrada &&
              horarioEspecial != null &&
              ventanaSalidaEspecialInicio != null &&
              ventanaSalidaEspecialFin != null
          ? ventanaSalidaEspecialInicio
          : ventanaNormal.inicio;
      final ventanaMarcacionFin =
          !esEntrada &&
              horarioEspecial != null &&
              ventanaSalidaEspecialInicio != null &&
              ventanaSalidaEspecialFin != null
          ? ventanaSalidaEspecialFin
          : ventanaNormal.fin;

      horariosEvaluados.add({
        'id': id,
        'entradaMin': entradaMin,
        'salidaMin': salidaMin,
        'rango': '$entrada a $salida',
        'esTiempoCompleto': esTiempoCompleto,
        'ventanaInicioMin': ventanaMarcacionInicio,
        'ventanaFinMin': ventanaMarcacionFin,
        'ventana': _etiquetaVentanaMarcacion(
          ventanaMarcacionInicio,
          ventanaMarcacionFin,
        ),
      });

      final horarioActivo =
          ahoraMin >= ventanaMarcacionInicio && ahoraMin <= ventanaMarcacionFin;

      if (horarioActivo) {
        horarioSeleccionado = {
          ...data,
          'entrada': entrada,
          'salida': salida,
          'entrada_base': entradaBase,
          'salida_base': salidaBase,
          'horario_especial_documento_id': horarioEspecial?['documentoId'],
          'horario_especial_fecha_clave': horarioEspecial?['fechaClave'],
          'horario_especial_motivo': horarioEspecial?['motivo'],
          'horario_especial_entrada': horaEntradaEspecial,
          'horario_especial_salida': horaSalidaEspecial,
        };
        break;
      }
    }

    if (horarioSeleccionado == null) {
      if (!esEntrada &&
          horarioEspecial != null &&
          ventanaSalidaEspecialInicio != null &&
          ventanaSalidaEspecialFin != null) {
        if (ahoraMin < ventanaSalidaEspecialInicio) {
          throw Exception(
            'La salida especial de hoy se habilita desde ${_minutosAHora(ventanaSalidaEspecialInicio)} y permanece disponible hasta ${_minutosAHora(ventanaSalidaEspecialFin)}.',
          );
        }

        if (ahoraMin > ventanaSalidaEspecialFin) {
          throw Exception(
            'La ventana para registrar la salida especial fue de ${_minutosAHora(ventanaSalidaEspecialInicio)} a ${_minutosAHora(ventanaSalidaEspecialFin)}.',
          );
        }
      }

      throw Exception(
        _mensajeFueraDeHorario(
          ahora: ahora,
          horariosEvaluados: horariosEvaluados,
          esEntrada: esEntrada,
        ),
      );
    }

    final horaEntradaAplicada = (horarioSeleccionado['entrada'] ?? '00:00')
        .toString();
    final horaSalidaAplicada = (horarioSeleccionado['salida'] ?? '00:00')
        .toString();
    final horaEntradaBase =
        (horarioSeleccionado['entrada_base'] ?? horaEntradaAplicada).toString();
    final horaSalidaBase =
        (horarioSeleccionado['salida_base'] ?? horaSalidaAplicada).toString();

    String horaOficialStr = esEntrada
        ? horaEntradaAplicada
        : horaSalidaAplicada;
    int horaLimite = _horaEnMinutos(horaOficialStr);
    String horaActualStr = DateFormat('HH:mm').format(ahora);
    final salidaAplicadaMin = _horaEnMinutos(horaSalidaAplicada);
    final salidaBaseMin = _horaEnMinutos(horaSalidaBase);
    final salidaEspecialDentroDeVentana =
        !esEntrada &&
        horarioEspecial != null &&
        ventanaSalidaEspecialInicio != null &&
        ventanaSalidaEspecialFin != null &&
        ahoraMin >= ventanaSalidaEspecialInicio &&
        ahoraMin <= ventanaSalidaEspecialFin;

    String estado = "A tiempo";
    if (esEntrada && ahoraMin > horaLimite) {
      estado = "Atraso";
    } else if (!esEntrada && salidaEspecialDentroDeVentana) {
      estado = salidaAplicadaMin < salidaBaseMin
          ? "Salida anticipada autorizada"
          : "Completada";
    } else if (!esEntrada && ahoraMin < horaLimite) {
      estado = "Salida Anticipada";
    } else if (!esEntrada) {
      estado = horarioEspecial != null && salidaAplicadaMin < salidaBaseMin
          ? "Salida anticipada autorizada"
          : "Completada";
    }

    final permisoActivo = await permisoActivoFuture;
    final rangoHorarioEspecial = horarioEspecial == null
        ? ''
        : '$horaEntradaAplicada a $horaSalidaAplicada';

    // 3. GUARDAR REGISTRO
    final payload = {
      'docente': nombreUsuario,
      'correo_usuario': correoNormalizado,
      'tipo': esEntrada ? "ENTRADA" : "SALIDA",
      'horario_ref': horarioSeleccionado['nombre'],
      'hora_marcada': horaActualStr,
      'estado': estado,
      'fecha': ahora,
      'observacion': "Registro realizado correctamente.",
      'sedeId': sedeId,
      'sede': sedeNombre,
      'hora_entrada_oficial': horaEntradaAplicada,
      'hora_salida_oficial': horaSalidaAplicada,
      'hora_entrada_base': horaEntradaBase,
      'hora_salida_base': horaSalidaBase,
      'horario_especial_activo': horarioEspecial != null,
      'horario_especial_documento_id':
          horarioSeleccionado['horario_especial_documento_id'],
      'horario_especial_fecha_clave':
          horarioSeleccionado['horario_especial_fecha_clave'],
      'horario_especial_motivo': horarioSeleccionado['horario_especial_motivo'],
      'horario_especial_hora_entrada':
          horarioSeleccionado['horario_especial_entrada'],
      'horario_especial_hora_salida':
          horarioSeleccionado['horario_especial_salida'],
      'horario_especial_tolerancia_antes_minutos': toleranciaSalidaAntesMinutos,
      'horario_especial_tolerancia_despues_minutos':
          toleranciaSalidaDespuesMinutos,
      'horario_especial_ventana_salida': ventanaSalidaEspecialLabel,
      'horario_especial_rango': rangoHorarioEspecial,
      'permiso_aprobado_activo': permisoActivo != null,
      'permiso_horario': permisoActivo?['horario'],
      'permiso_motivo': permisoActivo?['motivo'],
      'permiso_documento_id': permisoActivo?['documentoId'],
    };

    await _guardarMarcacionIdempotente(
      nombreUsuario: nombreUsuario,
      correoUsuario: correoUsuario,
      fecha: ahora,
      esEntrada: esEntrada,
      horarioClave:
          (horarioSeleccionado['horarioId'] ?? horarioSeleccionado['nombre'] ?? 'general')
              .toString(),
      payload: payload,
    );

    return {
      'estado': estado,
      'bloque': horarioSeleccionado['nombre'],
      'hora': horaActualStr,
      'permisoActivo': permisoActivo != null ? 'true' : 'false',
      'horarioPermiso': permisoActivo?['horario'] ?? '',
      'motivoPermiso': permisoActivo?['motivo'] ?? '',
      'horarioEspecialActivo': horarioEspecial != null ? 'true' : 'false',
      'horarioEspecialRango': rangoHorarioEspecial,
      'horarioEspecialVentanaSalida': ventanaSalidaEspecialLabel,
      'motivoHorarioEspecial':
          (horarioSeleccionado['horario_especial_motivo'] ?? '').toString(),
    };
  }

  Future<List<Map<String, dynamic>>> obtenerHistorialAsistencias(
    String nombreDocente,
    {String? correoUsuario}
  ) async {
    try {
      final correoNormalizado = _normalizarCorreo(correoUsuario ?? '');
      QuerySnapshot snapshot;
      if (correoNormalizado.isNotEmpty) {
        snapshot = await _db
            .collection('asistencias_realizadas')
            .where('correo_usuario', isEqualTo: correoNormalizado)
            .orderBy('fecha', descending: true)
            .get();
        if (snapshot.docs.isEmpty) {
          snapshot = await _db
              .collection('asistencias_realizadas')
              .where('docente', isEqualTo: nombreDocente)
              .orderBy('fecha', descending: true)
              .get();
        }
      } else {
        snapshot = await _db
            .collection('asistencias_realizadas')
            .where('docente', isEqualTo: nombreDocente)
            .orderBy('fecha', descending: true)
            .get();
      }

      return snapshot.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      debugPrint(
        'obtenerHistorialAsistencias fallo '
        '(nombre=$nombreDocente, correo=${_normalizarCorreo(correoUsuario ?? "")}): $e',
      );
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> obtenerHistorialAlmuerzo(
    String correo,
  ) async {
    try {
      QuerySnapshot snapshot = await _db
          .collection('registros_almuerzo')
          .where('correo_usuario', isEqualTo: correo)
          .orderBy('timestamp', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      debugPrint(
        'obtenerHistorialAlmuerzo fallo (correo=${_normalizarCorreo(correo)}): $e',
      );
      return [];
    }
  }

  Future<Map<String, dynamic>?> obtenerDatosPerfil(
    String correo, {
    String? sedeId,
  }) async {
    try {
      QuerySnapshot snapshot = await _db
          .collection('usuarios')
          .where('correo', isEqualTo: correo)
          .get();

      if (snapshot.docs.isNotEmpty) {
        QueryDocumentSnapshot? perfilDoc;
        final sedeObjetivo = SedeAccess.normalize(sedeId);

        if (sedeObjetivo.isNotEmpty) {
          for (final doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (SedeAccess.matchesSede(data, sedeObjetivo)) {
              perfilDoc = doc;
              break;
            }
          }
        }

        perfilDoc ??= snapshot.docs.first;
        return _sanitizarDatosUsuario(perfilDoc.data() as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint(
        'obtenerDatosPerfil fallo '
        '(correo=${_normalizarCorreo(correo)}, sedeId=${SedeAccess.normalize(sedeId)}): $e',
      );
    }
    return null;
  }

  Future<Map<String, int>> obtenerEstadisticasDocente(
    String nombre, {
    String? correoUsuario,
    String mes = "Todos",
  }) async {
    final correoNormalizado = _normalizarCorreo(correoUsuario ?? '');
    QuerySnapshot snapshot;
    if (correoNormalizado.isNotEmpty) {
      snapshot = await _db
          .collection('asistencias_realizadas')
          .where('correo_usuario', isEqualTo: correoNormalizado)
          .get();
      if (snapshot.docs.isEmpty) {
        snapshot = await _db
            .collection('asistencias_realizadas')
            .where('docente', isEqualTo: nombre)
            .get();
      }
    } else {
      snapshot = await _db
          .collection('asistencias_realizadas')
          .where('docente', isEqualTo: nombre)
          .get();
    }

    final docs = snapshot.docs
        .map((doc) => doc.data())
        .whereType<Map<String, dynamic>>()
        .toList();

    final List<Map<String, dynamic>> filtrados = mes == "Todos"
        ? docs
        : docs.where((data) {
            final fechaCampo = data['fecha'];
            DateTime? fecha;

            if (fechaCampo is Timestamp) {
              fecha = fechaCampo.toDate();
            } else if (fechaCampo is DateTime) {
              fecha = fechaCampo;
            } else if (fechaCampo is String) {
              try {
                fecha = DateTime.parse(fechaCampo);
              } catch (_) {
                return false;
              }
            }

            if (fecha == null) return false;
            final int numeroMes = _obtenerNumeroMes(mes);
            return fecha.month == numeroMes &&
                fecha.year == DateTime.now().year;
          }).toList();

    int total = filtrados.length;
    int puntual = 0;
    int atraso = 0;
    int salidaAnticipada = 0;

    for (var data in filtrados) {
      final estado = data['estado']?.toString() ?? '';

      if (estado == "A tiempo" || estado == "Puntual") {
        puntual++;
      } else if (estado == "Atraso") {
        atraso++;
      } else if (estado == "Salida Anticipada") {
        salidaAnticipada++;
      }
    }

    return {
      "Total": total,
      "Puntual": puntual,
      "Atraso": atraso,
      "Salida Anticipada": salidaAnticipada,
    };
  }
  // ==========================================
  // LÓGICA DE ALMUERZO (SOLO TIEMPO COMPLETO)
  // ==========================================

  // Registrar salida al almuerzo
  Future<void> registrarInicioAlmuerzo(String correo) async {
    final usuarioData = await _obtenerUsuarioPorCorreo(correo);
    final List<dynamic> horarios = resolverHorariosDisponiblesAlmuerzoUsuario(
      usuarioData,
    );
    final bool esTC = horarios.any(
      (h) => h.toString().trim().toUpperCase().startsWith("TC"),
    );
    final horarioAlmuerzo = await _resolverHorarioAlmuerzoUsuario(
      usuarioData: usuarioData,
      listaHorarios: horarios,
    );

    if (!esTC && horarioAlmuerzo == null) {
      // CORRECCIÓN AQUÍ: Cambié 'horarios' por 'horarios_asignados' que es como está en tu Firebase
      throw Exception("Los docentes de Tiempo Parcial no registran almuerzo.");
    }

    final ahora = DateTime.now();
    String fechaHoy = DateFormat('yyyy-MM-dd').format(ahora);
    String horaActual = DateFormat('HH:mm:ss').format(ahora);

    final legacyActivo = await _db
        .collection('registros_almuerzo')
        .where('correo_usuario', isEqualTo: correo)
        .where('fecha', isEqualTo: fechaHoy)
        .where('estado', isEqualTo: "en_almuerzo")
        .limit(1)
        .get();
    if (legacyActivo.docs.isNotEmpty) {
      return;
    }

    final docId = _docIdAlmuerzo(
      correoUsuario: correo,
      nombreUsuario: usuarioData?['nombre']?.toString(),
      fecha: ahora,
    );
    final ref = _db.collection('registros_almuerzo').doc(docId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (snapshot.exists) {
        final data = snapshot.data() ?? {};
        final estadoActual = (data['estado'] ?? '').toString().trim();
        if (estadoActual == 'en_almuerzo') {
          return;
        }
        if (estadoActual == 'finalizado') {
          throw Exception("Ya registraste tu almuerzo de hoy.");
        }
      }

      transaction.set(ref, {
        'correo_usuario': correo,
        'nombre_usuario': usuarioData?['nombre'],
        'fecha': fechaHoy,
        'hora_salida': horaActual,
        'hora_regreso': "--:--",
        'estado': "en_almuerzo",
        'sedeId': usuarioData?['sedeId'],
        'sede': usuarioData?['sede'],
        'tipo_horario': usuarioData?['tipo_horario'],
        'almuerzo_horario': horarioAlmuerzo?['label'],
        'almuerzo_inicio_asignado': horarioAlmuerzo?['inicio'],
        'almuerzo_fin_asignado': horarioAlmuerzo?['fin'],
        'timestamp': FieldValue.serverTimestamp(),
        'registro_estable': true,
        'idempotencyKey': docId,
      }, SetOptions(merge: true));
    });
  }

  // Registrar regreso del almuerzo
  Future<void> registrarFinAlmuerzo(String correo) async {
    final ahora = DateTime.now();
    String fechaHoy = DateFormat('yyyy-MM-dd').format(ahora);
    String horaActual = DateFormat('HH:mm:ss').format(ahora);
    QuerySnapshot userCheck = await _db
        .collection('usuarios')
        .where('correo', isEqualTo: correo)
        .limit(1)
        .get();
    Map<String, dynamic>? usuarioData;

    if (userCheck.docs.isNotEmpty) {
      usuarioData = userCheck.docs.first.data() as Map<String, dynamic>;
    }

    final docId = _docIdAlmuerzo(
      correoUsuario: correo,
      nombreUsuario: usuarioData?['nombre']?.toString(),
      fecha: ahora,
    );
    final ref = _db.collection('registros_almuerzo').doc(docId);
    var actualizado = false;

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) {
        return;
      }

      final data = snapshot.data() ?? {};
      final estadoActual = (data['estado'] ?? '').toString().trim();
      if (estadoActual == 'finalizado') {
        actualizado = true;
        return;
      }
      if (estadoActual != 'en_almuerzo') {
        return;
      }

      transaction.update(ref, {
        'hora_regreso': horaActual,
        'estado': "finalizado",
        'nombre_usuario': usuarioData?['nombre'],
        'sedeId': usuarioData?['sedeId'],
        'sede': usuarioData?['sede'],
        'tipo_horario': usuarioData?['tipo_horario'],
      });
      actualizado = true;
    });

    if (actualizado) {
      return;
    }

    var query = await _db
        .collection('registros_almuerzo')
        .where('correo_usuario', isEqualTo: correo)
        .where('fecha', isEqualTo: fechaHoy)
        .where('estado', isEqualTo: "en_almuerzo")
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      await query.docs.first.reference.update({
        'hora_regreso': horaActual,
        'estado': "finalizado",
        'nombre_usuario': usuarioData?['nombre'],
        'sedeId': usuarioData?['sedeId'],
        'sede': usuarioData?['sede'],
        'tipo_horario': usuarioData?['tipo_horario'],
      });
      return;
    }

    throw Exception("No se encontró un inicio de almuerzo activo.");
  }

  // ==========================================
  // LÓGICA DE SOLICITUDES (VACACIONES Y PERMISOS)
  // ==========================================

  // 1. Enviar una nueva solicitud (Desde el Celular)
  // ==========================================
  // LÓGICA DE SOLICITUDES (VACACIONES Y PERMISOS)
  // ==========================================

  // ESTA ES LA ÚNICA VERSIÓN QUE DEBE QUEDAR
  Future<void> enviarSolicitud(
    Solicitud solicitud, {
    String? signingPassword,
  }) async {
    try {
      final solicitudesRef = _db.collection('solicitudes');
      final nuevaSolicitudRef = solicitudesRef.doc();
      final usaFlujoMatriz = MatrizApprovalFlow.appliesToSedeId(
        solicitud.sedeId,
      );
      final tipoSolicitud = _resolverTipoSolicitud(solicitud.tipo);
      final sedeSolicitud = _resolverSedeSolicitud(solicitud.sedeId);
      Map<String, dynamic>? firmaSolicitante;
      final signingKey = signingPassword?.trim() ?? '';
      final correoSolicitante = MatrizApprovalFlow.normalizeEmail(
        solicitud.colaboradorCorreo,
      );
      if (signingKey.isNotEmpty) {
        if (correoSolicitante.isEmpty) {
          throw Exception(
            'No se pudo identificar el correo del solicitante para aplicar la firma.',
          );
        }

        final userDataFirmante = await autorizarFirmaPerfilUsuario(
          correo: correoSolicitante,
          sedeId: solicitud.sedeId,
          signingPassword: signingKey,
          requireDigitalCertificate: true,
        );
        firmaSolicitante = await _resolverDatosFirmaElectronica(
          correo: correoSolicitante,
          nombre: solicitud.colaborador,
          fallbackUserData: userDataFirmante,
          sedeIdFallback: solicitud.sedeId,
        );
      }
      final siguienteNumero = await _obtenerSiguienteNumeroFormularioPorTipo(
        tipoSolicitud: tipoSolicitud,
        sedeId: sedeSolicitud,
      );
      final numeroFormularioGenerado = _formatearNumeroFormulario(
        siguienteNumero,
      );

      final payload = <String, dynamic>{
        ...solicitud.toMap(),
        'numFormulario': numeroFormularioGenerado,
        'numFormularioSecuencia': siguienteNumero,
        'numFormularioTipo': tipoSolicitud,
        'numFormularioSedeId': sedeSolicitud,
        'fecha_solicitud': FieldValue.serverTimestamp(),
        'flujoAprobacion': usaFlujoMatriz
            ? MatrizApprovalFlow.flowId
            : 'simple',
        'etapaAprobacion': usaFlujoMatriz
            ? MatrizApprovalFlow.stagePrimary
            : 'simple',
        'aprobadorPrimarioEmail': usaFlujoMatriz
            ? MatrizApprovalFlow.primaryReviewerEmail
            : null,
        'aprobadoresFinalesEmails': usaFlujoMatriz
            ? MatrizApprovalFlow.finalReviewerEmails.toList()
            : null,
      };

      if (firmaSolicitante != null &&
          _tieneArchivoFirmaElectronica(firmaSolicitante)) {
        payload['firmasElectronicas'] = {
          'solicitante': _buildFirmaElectronicaMap(
            signerData: firmaSolicitante,
            etapa: 'solicitante',
            accion: 'envio',
          ),
        };
      }

      await nuevaSolicitudRef.set(payload);

      await _crearAvisosNuevaSolicitudRRHH(
        idDoc: nuevaSolicitudRef.id,
        solicitud: solicitud,
        numeroFormulario: numeroFormularioGenerado,
        usaFlujoMatriz: usaFlujoMatriz,
      );
    } catch (e) {
      throw Exception("Error al enviar la solicitud: $e");
    }
  }

  Future<Map<String, dynamic>> asegurarNumeroFormularioSolicitud(
    String idDoc,
    Map<String, dynamic> data,
  ) async {
    final solicitudRef = _db.collection('solicitudes').doc(idDoc);

    try {
      return await _asegurarNumeroFormularioEnSolicitudRef(
        solicitudRef,
        fallbackData: data,
      );
    } catch (e) {
      throw Exception("Error al generar el numero del formulario: $e");
    }
  }

  String _resolverTipoSolicitud(dynamic tipo) {
    final texto = tipo?.toString().trim();
    if (texto == null || texto.isEmpty) {
      return 'Solicitud';
    }
    return texto;
  }

  String _resolverSedeSolicitud(dynamic sedeId) {
    final normalizada = SedeAccess.normalize(sedeId);
    if (normalizada.isEmpty) {
      return SedeAccess.matrizId;
    }
    return normalizada;
  }

  String _claveGrupoSolicitud({
    required String tipoSolicitud,
    required String sedeId,
  }) {
    return '${_resolverSedeSolicitud(sedeId)}||${_resolverTipoSolicitud(tipoSolicitud)}';
  }

  ({String sedeId, String tipoSolicitud}) _parseClaveGrupoSolicitud(
    String value,
  ) {
    final parts = value.split('||');
    final sedeId = parts.isNotEmpty ? parts.first : SedeAccess.matrizId;
    final tipoSolicitud = parts.length > 1 ? parts[1] : 'Solicitud';
    return (
      sedeId: _resolverSedeSolicitud(sedeId),
      tipoSolicitud: _resolverTipoSolicitud(tipoSolicitud),
    );
  }

  String _formatearNumeroFormulario(int numero) {
    return numero.toString().padLeft(5, '0');
  }

  String _slugNumeroFormulario(String value) {
    final limpio = value.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '_',
    );
    return limpio.isEmpty ? 'solicitud' : limpio.replaceAll(RegExp(r'_+'), '_');
  }

  DocumentReference<Map<String, dynamic>> _contadorSolicitudesRef({
    required String tipoSolicitud,
    required String sedeId,
  }) {
    final sedeNormalizada = _resolverSedeSolicitud(sedeId);
    final tipoNormalizado = _resolverTipoSolicitud(tipoSolicitud);
    final docId =
        'solicitudes_${_slugNumeroFormulario(sedeNormalizada)}_${_slugNumeroFormulario(tipoNormalizado)}';
    return _db.collection('_counters').doc(docId);
  }

  int? _leerSecuenciaFormulario(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    final secuencia = (data['numFormularioSecuencia'] as num?)?.toInt();
    if (secuencia != null && secuencia > 0) {
      return secuencia;
    }

    final numero = (data['numFormulario'] ?? '').toString().trim();
    final numeroParseado = int.tryParse(numero);
    if (numeroParseado != null && numeroParseado > 0) {
      return numeroParseado;
    }
    return null;
  }

  bool _tieneNumeracionFormularioValida(
    Map<String, dynamic>? data, {
    required String tipoSolicitud,
    required String sedeId,
  }) {
    if (data == null) {
      return false;
    }

    final secuencia = _leerSecuenciaFormulario(data);
    if (secuencia == null) {
      return false;
    }

    final numeroActual = (data['numFormulario'] ?? '').toString().trim();
    final tipoActual = _resolverTipoSolicitud(data['numFormularioTipo']);
    final sedeActual = _resolverSedeSolicitud(data['numFormularioSedeId']);

    return numeroActual == _formatearNumeroFormulario(secuencia) &&
        tipoActual == tipoSolicitud &&
        sedeActual == sedeId;
  }

  DateTime _resolverFechaOrdenSolicitud(Map<String, dynamic> data) {
    final fecha =
        data['fecha_solicitud'] ??
        data['fechaSolicitud'] ??
        data['fechaInicio'];

    if (fecha is Timestamp) {
      return fecha.toDate();
    }
    if (fecha is DateTime) {
      return fecha;
    }
    if (fecha != null) {
      final parseada = DateTime.tryParse(fecha.toString());
      if (parseada != null) {
        return parseada;
      }
    }

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<int> _obtenerSiguienteNumeroFormularioPorTipo({
    required String tipoSolicitud,
    required String sedeId,
  }) async {
    final tipoNormalizado = _resolverTipoSolicitud(tipoSolicitud);
    final sedeNormalizada = _resolverSedeSolicitud(sedeId);
    final maximoExistente = await _obtenerMaxNumeroFormularioExistente(
      tipoSolicitud: tipoNormalizado,
      sedeId: sedeNormalizada,
    );
    final contadorRef = _contadorSolicitudesRef(
      tipoSolicitud: tipoNormalizado,
      sedeId: sedeNormalizada,
    );

    return _db.runTransaction<int>((transaction) async {
      final counterSnapshot = await transaction.get(contadorRef);
      final actualCounter =
          (counterSnapshot.data()?['ultimoNumero'] as num?)?.toInt() ?? 0;
      final baseActual = max(actualCounter, maximoExistente);
      final siguiente = baseActual + 1;

      transaction.set(contadorRef, {
        'ultimoNumero': siguiente,
        'tipoSolicitud': tipoNormalizado,
        'sedeId': sedeNormalizada,
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return siguiente;
    });
  }

  Future<int> _obtenerMaxNumeroFormularioExistente({
    required String tipoSolicitud,
    required String sedeId,
  }) async {
    final snapshotSecuencia = await _db
        .collection('solicitudes')
        .where('tipo', isEqualTo: tipoSolicitud)
        .where('sedeId', isEqualTo: sedeId)
        .orderBy('numFormularioSecuencia', descending: true)
        .limit(1)
        .get();

    final maximoPorSecuencia = snapshotSecuencia.docs.isEmpty
        ? 0
        : (_leerSecuenciaFormulario(snapshotSecuencia.docs.first.data()) ?? 0);
    if (maximoPorSecuencia > 0) {
      return maximoPorSecuencia;
    }

    final snapshotNumero = await _db
        .collection('solicitudes')
        .where('tipo', isEqualTo: tipoSolicitud)
        .where('sedeId', isEqualTo: sedeId)
        .orderBy('numFormulario', descending: true)
        .limit(1)
        .get();

    if (snapshotNumero.docs.isEmpty) {
      return 0;
    }

    return _leerSecuenciaFormulario(snapshotNumero.docs.first.data()) ?? 0;
  }

  Future<Map<String, dynamic>> _asegurarNumeroFormularioEnSolicitudRef(
    DocumentReference<Map<String, dynamic>> solicitudRef, {
    Map<String, dynamic>? fallbackData,
  }) async {
    final solicitudSnapshot = await solicitudRef.get();
    final solicitudBase = solicitudSnapshot.data() ?? fallbackData ?? <String, dynamic>{};
    final tipoSolicitud = _resolverTipoSolicitud(solicitudBase['tipo']);
    final sedeSolicitud = _resolverSedeSolicitud(solicitudBase['sedeId']);
    final maximoExistente = await _obtenerMaxNumeroFormularioExistente(
      tipoSolicitud: tipoSolicitud,
      sedeId: sedeSolicitud,
    );
    final contadorRef = _contadorSolicitudesRef(
      tipoSolicitud: tipoSolicitud,
      sedeId: sedeSolicitud,
    );

    return _db.runTransaction<Map<String, dynamic>>((transaction) async {
      final solicitudTxSnapshot = await transaction.get(solicitudRef);
      final solicitudData =
          solicitudTxSnapshot.data() ?? fallbackData ?? <String, dynamic>{};
      final tipoActual = _resolverTipoSolicitud(solicitudData['tipo']);
      final sedeActual = _resolverSedeSolicitud(solicitudData['sedeId']);

      if (_tieneNumeracionFormularioValida(
        solicitudData,
        tipoSolicitud: tipoActual,
        sedeId: sedeActual,
      )) {
        return solicitudData;
      }

      final secuenciaExistente = _leerSecuenciaFormulario(solicitudData);
      if (secuenciaExistente != null && secuenciaExistente > 0) {
        final numeroFormulario = _formatearNumeroFormulario(secuenciaExistente);
        transaction.set(solicitudRef, {
          'numFormulario': numeroFormulario,
          'numFormularioSecuencia': secuenciaExistente,
          'numFormularioTipo': tipoActual,
          'numFormularioSedeId': sedeActual,
        }, SetOptions(merge: true));

        return {
          ...solicitudData,
          'numFormulario': numeroFormulario,
          'numFormularioSecuencia': secuenciaExistente,
          'numFormularioTipo': tipoActual,
          'numFormularioSedeId': sedeActual,
        };
      }

      final contadorSnapshot = await transaction.get(contadorRef);
      final actualCounter =
          (contadorSnapshot.data()?['ultimoNumero'] as num?)?.toInt() ?? 0;
      final baseActual = max(actualCounter, maximoExistente);
      final siguiente = baseActual + 1;
      final numeroFormulario = _formatearNumeroFormulario(siguiente);

      transaction.set(contadorRef, {
        'ultimoNumero': siguiente,
        'tipoSolicitud': tipoActual,
        'sedeId': sedeActual,
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      transaction.set(solicitudRef, {
        'numFormulario': numeroFormulario,
        'numFormularioSecuencia': siguiente,
        'numFormularioTipo': tipoActual,
        'numFormularioSedeId': sedeActual,
      }, SetOptions(merge: true));

      return {
        ...solicitudData,
        'numFormulario': numeroFormulario,
        'numFormularioSecuencia': siguiente,
        'numFormularioTipo': tipoActual,
        'numFormularioSedeId': sedeActual,
      };
    });
  }

  Future<void> _aplicarNumeracionSecuencialSolicitudesDocs(
    List<QueryDocumentSnapshot> docs, {
    required String tipoSolicitud,
    required String sedeId,
  }) async {
    if (docs.isEmpty) {
      return;
    }

    docs.sort((a, b) {
      final fechaA = _resolverFechaOrdenSolicitud(
        a.data() as Map<String, dynamic>,
      );
      final fechaB = _resolverFechaOrdenSolicitud(
        b.data() as Map<String, dynamic>,
      );
      final comparacionFecha = fechaA.compareTo(fechaB);
      if (comparacionFecha != 0) {
        return comparacionFecha;
      }
      return a.id.compareTo(b.id);
    });

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (_tieneNumeracionFormularioValida(
        data,
        tipoSolicitud: tipoSolicitud,
        sedeId: sedeId,
      )) {
        continue;
      }

      await _asegurarNumeroFormularioEnSolicitudRef(
        _db.collection('solicitudes').doc(doc.id),
        fallbackData: data,
      );
    }
  }

  Future<void> reenumerarSolicitudesPorGrupo({
    required String tipoSolicitud,
    required String sedeId,
  }) async {
    final tipoNormalizado = _resolverTipoSolicitud(tipoSolicitud);
    final sedeNormalizada = _resolverSedeSolicitud(sedeId);
    final snapshot = await _db
        .collection('solicitudes')
        .where('tipo', isEqualTo: tipoNormalizado)
        .where('sedeId', isEqualTo: sedeNormalizada)
        .get();

    await _aplicarNumeracionSecuencialSolicitudesDocs(
      snapshot.docs,
      tipoSolicitud: tipoNormalizado,
      sedeId: sedeNormalizada,
    );
  }

  Future<void> sincronizarNumeracionSolicitudesDesdeDocs(
    Iterable<QueryDocumentSnapshot> docs, {
    String? sedeId,
  }) async {
    final sedeFiltro = SedeAccess.normalize(sedeId);
    final grupos = <String, List<QueryDocumentSnapshot>>{};

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final sedeSolicitud = _resolverSedeSolicitud(data['sedeId']);
      if (sedeFiltro.isNotEmpty && sedeSolicitud != sedeFiltro) {
        continue;
      }

      final tipoSolicitud = _resolverTipoSolicitud(data['tipo']);
      final clave = _claveGrupoSolicitud(
        tipoSolicitud: tipoSolicitud,
        sedeId: sedeSolicitud,
      );
      grupos.putIfAbsent(clave, () => <QueryDocumentSnapshot>[]).add(doc);
    }

    for (final entry in grupos.entries) {
      final grupo = _parseClaveGrupoSolicitud(entry.key);
      await _aplicarNumeracionSecuencialSolicitudesDocs(
        entry.value,
        tipoSolicitud: grupo.tipoSolicitud,
        sedeId: grupo.sedeId,
      );
    }
  }

  Future<void> sincronizarNumeracionSolicitudesPorColaborador({
    required String nombre,
    String? correo,
    String? sedeId,
  }) async {
    final sedeFiltro = SedeAccess.normalize(sedeId);
    final correoNormalizado = _normalizarCorreo(correo ?? '');
    QuerySnapshot<Map<String, dynamic>> snapshot;
    if (correoNormalizado.isNotEmpty) {
      snapshot = await _db
          .collection('solicitudes')
          .where('colaboradorCorreo', isEqualTo: correoNormalizado)
          .get();
      if (snapshot.docs.isEmpty) {
        snapshot = await _db
            .collection('solicitudes')
            .where('colaborador', isEqualTo: nombre)
            .get();
      }
    } else {
      snapshot = await _db
          .collection('solicitudes')
          .where('colaborador', isEqualTo: nombre)
          .get();
    }

    final grupos = <String>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final sedeSolicitud = _resolverSedeSolicitud(data['sedeId']);
      if (sedeFiltro.isNotEmpty && sedeSolicitud != sedeFiltro) {
        continue;
      }

      grupos.add(
        _claveGrupoSolicitud(
          tipoSolicitud: _resolverTipoSolicitud(data['tipo']),
          sedeId: sedeSolicitud,
        ),
      );
    }

    for (final clave in grupos) {
      final grupo = _parseClaveGrupoSolicitud(clave);
      await reenumerarSolicitudesPorGrupo(
        tipoSolicitud: grupo.tipoSolicitud,
        sedeId: grupo.sedeId,
      );
    }
  }

  // 2. Escuchar solicitudes pendientes en tiempo real (Para la Web RRHH)
  Stream<QuerySnapshot> obtenerSolicitudesPendientes() {
    return _db
        .collection('solicitudes')
        .where('estado', isEqualTo: 'pendiente')
        .orderBy('fecha_solicitud', descending: false)
        .snapshots();
  }

  // 3. Actualizar estado (Aceptar o Rechazar desde la Web)
  Future<void> actualizarEstadoSolicitud(
    String idDoc,
    String nuevoEstado, {
    String? reviewerEmail,
    String? reviewerName,
    Map<String, dynamic>? reviewerUserData,
    String? signingPassword,
  }) async {
    try {
      final solicitudRef = _db.collection('solicitudes').doc(idDoc);
      final normalizedEmail = MatrizApprovalFlow.normalizeEmail(reviewerEmail);
      final reviewerDocId = reviewerUserData?['docId']?.toString();
      final reviewerSedeId = reviewerUserData == null
          ? null
          : SedeAccess.resolveSedeId(reviewerUserData);
      final reviewerDataAutorizado = await autorizarFirmaPerfilUsuario(
        userDocId: reviewerDocId,
        correo: normalizedEmail,
        sedeId: reviewerSedeId,
        signingPassword: signingPassword ?? '',
        requireDigitalCertificate: true,
      );
      final firmaRevisor = await _resolverDatosFirmaElectronica(
        correo: normalizedEmail,
        nombre: reviewerName,
        fallbackUserData: reviewerDataAutorizado,
      );
      Map<String, dynamic>? solicitudFinal;
      var debeNotificarAprobacion = false;

      await _db.runTransaction((transaction) async {
        final snapshot = await transaction.get(solicitudRef);
        final data = snapshot.data();
        if (data == null) {
          throw Exception('La solicitud ya no existe.');
        }

        final usaFlujoMatriz =
            MatrizApprovalFlow.appliesToRequest(data) &&
            (SedeAccess.normalize(data['flujoAprobacion']) ==
                    MatrizApprovalFlow.flowId ||
                SedeAccess.normalize(data['estado']) == 'pendiente');

        if (!usaFlujoMatriz) {
          final firmaResolucion = _buildFirmaElectronicaUpdatePayload(
            prefix: 'firmasElectronicas.resolucion',
            signerData: firmaRevisor,
            etapa: 'resolucion',
            accion: nuevoEstado,
          );
          transaction.update(solicitudRef, {
            ...firmaResolucion,
            'estado': nuevoEstado,
            'fecha_resolucion': FieldValue.serverTimestamp(),
            'resueltoPorEmail': normalizedEmail.isEmpty
                ? null
                : normalizedEmail,
            'resueltoPorNombre': reviewerName,
          });
          solicitudFinal = {...data, 'estado': nuevoEstado};
          debeNotificarAprobacion = nuevoEstado == 'aprobado';
          return;
        }

        final estadoActual = SedeAccess.normalize(data['estado']);
        if (estadoActual != 'pendiente') {
          throw Exception('La solicitud ya fue procesada anteriormente.');
        }

        final etapaActual =
            SedeAccess.normalize(data['etapaAprobacion']).isEmpty
            ? MatrizApprovalFlow.stagePrimary
            : SedeAccess.normalize(data['etapaAprobacion']);

        if (etapaActual == MatrizApprovalFlow.stagePrimary) {
          if (!MatrizApprovalFlow.isPrimaryReviewer(normalizedEmail)) {
            throw Exception(
              'Solo ${MatrizApprovalFlow.primaryReviewerEmail} puede hacer la aprobacion previa de Matriz.',
            );
          }

          if (nuevoEstado == 'aprobado') {
            final firmaRevisionPrimaria = _buildFirmaElectronicaUpdatePayload(
              prefix: 'firmasElectronicas.revisionPrimaria',
              signerData: firmaRevisor,
              etapa: MatrizApprovalFlow.stagePrimary,
              accion: nuevoEstado,
            );
            transaction.update(solicitudRef, {
              ...firmaRevisionPrimaria,
              'estado': 'pendiente',
              'flujoAprobacion': MatrizApprovalFlow.flowId,
              'etapaAprobacion': MatrizApprovalFlow.stageFinal,
              'aprobadoPrimarioPorEmail': normalizedEmail,
              'aprobadoPrimarioPorNombre': reviewerName,
              'fecha_revision_primaria': FieldValue.serverTimestamp(),
              'ultimaActualizacionFlujo': FieldValue.serverTimestamp(),
            });
            solicitudFinal = {
              ...data,
              'estado': 'pendiente',
              'flujoAprobacion': MatrizApprovalFlow.flowId,
              'etapaAprobacion': MatrizApprovalFlow.stageFinal,
            };
            return;
          }

          final firmaRevisionPrimaria = _buildFirmaElectronicaUpdatePayload(
            prefix: 'firmasElectronicas.revisionPrimaria',
            signerData: firmaRevisor,
            etapa: MatrizApprovalFlow.stagePrimary,
            accion: nuevoEstado,
          );
          transaction.update(solicitudRef, {
            ...firmaRevisionPrimaria,
            'estado': nuevoEstado,
            'flujoAprobacion': MatrizApprovalFlow.flowId,
            'etapaAprobacion': MatrizApprovalFlow.stageCompleted,
            'rechazadoPrimarioPorEmail': normalizedEmail,
            'rechazadoPrimarioPorNombre': reviewerName,
            'fecha_resolucion': FieldValue.serverTimestamp(),
          });
          solicitudFinal = {
            ...data,
            'estado': nuevoEstado,
            'etapaAprobacion': MatrizApprovalFlow.stageCompleted,
          };
          return;
        }

        if (!MatrizApprovalFlow.isFinalReviewer(normalizedEmail)) {
          throw Exception(
            'Solo Oscar Toscano o Yadira Martinez pueden hacer la autorizacion final de Matriz.',
          );
        }

        final firmaAutorizacionFinal = _buildFirmaElectronicaUpdatePayload(
          prefix: 'firmasElectronicas.autorizacionFinal',
          signerData: firmaRevisor,
          etapa: MatrizApprovalFlow.stageFinal,
          accion: nuevoEstado,
        );
        transaction.update(solicitudRef, {
          ...firmaAutorizacionFinal,
          'estado': nuevoEstado,
          'flujoAprobacion': MatrizApprovalFlow.flowId,
          'etapaAprobacion': MatrizApprovalFlow.stageCompleted,
          'aprobadoFinalPorEmail': nuevoEstado == 'aprobado'
              ? normalizedEmail
              : null,
          'aprobadoFinalPorNombre': nuevoEstado == 'aprobado'
              ? reviewerName
              : null,
          'rechazadoFinalPorEmail': nuevoEstado == 'aprobado'
              ? null
              : normalizedEmail,
          'rechazadoFinalPorNombre': nuevoEstado == 'aprobado'
              ? null
              : reviewerName,
          'fecha_resolucion': FieldValue.serverTimestamp(),
        });
        solicitudFinal = {
          ...data,
          'estado': nuevoEstado,
          'etapaAprobacion': MatrizApprovalFlow.stageCompleted,
        };
        debeNotificarAprobacion = nuevoEstado == 'aprobado';
      });

      if (debeNotificarAprobacion && solicitudFinal != null) {
        await _crearAvisoSolicitudAprobada(
          idDoc: idDoc,
          solicitudData: solicitudFinal!,
          reviewerName: reviewerName,
          reviewerEmail: normalizedEmail,
        );
      }

      final cambioAEtapaFinal =
          solicitudFinal != null &&
          SedeAccess.normalize(solicitudFinal!['estado']) == 'pendiente' &&
          SedeAccess.normalize(solicitudFinal!['etapaAprobacion']) ==
              MatrizApprovalFlow.stageFinal;

      if (cambioAEtapaFinal && solicitudFinal != null) {
        await _crearAvisosSolicitudAutorizacionFinal(
          idDoc: idDoc,
          solicitudData: solicitudFinal!,
        );
      }
    } catch (e) {
      throw Exception("Error al actualizar la solicitud: $e");
    }
  }

  Future<List<Map<String, dynamic>>> _obtenerDestinatariosRrhhSolicitud({
    required String sedeId,
    required String etapa,
  }) async {
    final snapshot = await _db
        .collection('usuarios')
        .where('rol', whereIn: const ['RRHH', 'Admin'])
        .get();

    return snapshot.docs.map((doc) => {...doc.data(), 'docId': doc.id}).where((
      data,
    ) {
      final correo = MatrizApprovalFlow.normalizeEmail(data['correo']);
      if (correo.isEmpty) {
        return false;
      }

      if (sedeId == SedeAccess.matrizId) {
        if (etapa == MatrizApprovalFlow.stagePrimary) {
          return MatrizApprovalFlow.isPrimaryReviewer(correo);
        }
        if (etapa == MatrizApprovalFlow.stageFinal) {
          return MatrizApprovalFlow.isFinalReviewer(correo);
        }
      }

      final sedesPermitidas = MatrizApprovalFlow.allowedSedeIdsForUser(data);
      return sedesPermitidas.contains(sedeId);
    }).toList();
  }

  Future<void> _crearAvisosNuevaSolicitudRRHH({
    required String idDoc,
    required Solicitud solicitud,
    required String numeroFormulario,
    required bool usaFlujoMatriz,
  }) async {
    final sedeId = SedeAccess.normalize(solicitud.sedeId).isEmpty
        ? SedeAccess.matrizId
        : SedeAccess.normalize(solicitud.sedeId);
    final sedeNombre = SedeAccess.displayNameForId(sedeId);
    final tipoSolicitud = solicitud.tipo.trim().isEmpty
        ? 'Solicitud'
        : solicitud.tipo.trim();
    final colaborador = solicitud.colaborador.trim().isEmpty
        ? 'Colaborador'
        : solicitud.colaborador.trim();
    final motivo = solicitud.motivo.trim();
    final etapaDestino = usaFlujoMatriz
        ? MatrizApprovalFlow.stagePrimary
        : 'simple';
    final destinatarios = await _obtenerDestinatariosRrhhSolicitud(
      sedeId: sedeId,
      etapa: etapaDestino,
    );

    if (destinatarios.isEmpty) {
      return;
    }

    final mensajeBase = numeroFormulario.isEmpty
        ? 'Se envio una solicitud de $tipoSolicitud de $colaborador.'
        : 'Se envio una solicitud N° $numeroFormulario de $tipoSolicitud de $colaborador.';
    final mensaje = motivo.isEmpty
        ? '$mensajeBase Sede: $sedeNombre.'
        : '$mensajeBase Sede: $sedeNombre. Motivo: $motivo.';

    final batch = _db.batch();
    final now = DateTime.now();

    for (final destinatario in destinatarios) {
      final correoDestino = MatrizApprovalFlow.normalizeEmail(
        destinatario['correo'],
      );
      if (correoDestino.isEmpty) {
        continue;
      }

      final avisoRef = _db.collection('avisos').doc();
      batch.set(avisoRef, {
        'titulo': 'Se envio una solicitud',
        'mensaje': mensaje,
        'fecha': DateFormat('dd/MM/yyyy HH:mm').format(now),
        'timestamp': FieldValue.serverTimestamp(),
        'sedeId': sedeId,
        'sede': sedeNombre,
        'destinatarioCorreo': correoDestino,
        'destinatarioNombre': destinatario['nombre'],
        'tipo': 'solicitud_nueva',
        'solicitudId': idDoc,
        'solicitudTipo': tipoSolicitud,
        'numFormulario': numeroFormulario,
        'accionRuta': 'gestion',
        'leido': false,
      });
    }

    await batch.commit();
  }

  Future<void> _crearAvisosSolicitudAutorizacionFinal({
    required String idDoc,
    required Map<String, dynamic> solicitudData,
  }) async {
    final sedeId = SedeAccess.resolveSedeId(solicitudData);
    final destinatarios = await _obtenerDestinatariosRrhhSolicitud(
      sedeId: sedeId,
      etapa: MatrizApprovalFlow.stageFinal,
    );

    if (destinatarios.isEmpty) {
      return;
    }

    final colaborador = (solicitudData['colaborador'] ?? 'Colaborador')
        .toString()
        .trim();
    final tipoSolicitud = (solicitudData['tipo'] ?? 'Solicitud')
        .toString()
        .trim();
    final numeroFormulario = (solicitudData['numFormulario'] ?? '')
        .toString()
        .trim();
    final sedeNombre = SedeAccess.displayNameForId(sedeId);
    final motivo = (solicitudData['motivo'] ?? '').toString().trim();
    final mensajeBase = numeroFormulario.isEmpty
        ? 'La solicitud de $tipoSolicitud de $colaborador esta lista para autorizacion final.'
        : 'La solicitud N° $numeroFormulario de $tipoSolicitud de $colaborador esta lista para autorizacion final.';
    final mensaje = motivo.isEmpty
        ? '$mensajeBase Sede: $sedeNombre.'
        : '$mensajeBase Sede: $sedeNombre. Motivo: $motivo.';

    final batch = _db.batch();
    final now = DateTime.now();

    for (final destinatario in destinatarios) {
      final correoDestino = MatrizApprovalFlow.normalizeEmail(
        destinatario['correo'],
      );
      if (correoDestino.isEmpty) {
        continue;
      }

      final avisoRef = _db.collection('avisos').doc();
      batch.set(avisoRef, {
        'titulo': 'Solicitud por autorizar',
        'mensaje': mensaje,
        'fecha': DateFormat('dd/MM/yyyy HH:mm').format(now),
        'timestamp': FieldValue.serverTimestamp(),
        'sedeId': sedeId,
        'sede': sedeNombre,
        'destinatarioCorreo': correoDestino,
        'destinatarioNombre': destinatario['nombre'],
        'tipo': 'solicitud_por_autorizar',
        'solicitudId': idDoc,
        'solicitudTipo': tipoSolicitud,
        'numFormulario': numeroFormulario,
        'accionRuta': 'gestion',
        'leido': false,
      });
    }

    await batch.commit();
  }

  Future<void> _crearAvisoSolicitudAprobada({
    required String idDoc,
    required Map<String, dynamic> solicitudData,
    String? reviewerName,
    String? reviewerEmail,
  }) async {
    final colaborador = (solicitudData['colaborador'] ?? '').toString().trim();
    if (colaborador.isEmpty) {
      return;
    }

    final sedeId = SedeAccess.resolveSedeId(solicitudData);
    final sedeNombre = SedeAccess.displayNameForId(sedeId);
    var correoDestino = (solicitudData['colaboradorCorreo'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    if (correoDestino.isEmpty) {
      Query<Map<String, dynamic>> query = _db
          .collection('usuarios')
          .where('nombre', isEqualTo: colaborador)
          .limit(5);

      try {
        final snapshot = await query.get();
        final match = snapshot.docs.firstWhere(
          (doc) => SedeAccess.matchesSede(doc.data(), sedeId),
          orElse: () => snapshot.docs.isNotEmpty
              ? snapshot.docs.first
              : throw StateError('Sin coincidencias'),
        );
        correoDestino = (match.data()['correo'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
      } catch (error) {
        debugPrint(
          '_crearAvisosSolicitudAutorizacionFinal no pudo resolver correo destino '
          '(colaborador=$colaborador, sedeId=$sedeId): $error',
        );
        correoDestino = '';
      }
    }

    if (correoDestino.isEmpty) {
      return;
    }

    final tipoSolicitud = (solicitudData['tipo'] ?? 'solicitud')
        .toString()
        .trim();
    final numeroFormulario = (solicitudData['numFormulario'] ?? '')
        .toString()
        .trim();
    final aprobador = (reviewerName ?? reviewerEmail ?? 'RRHH')
        .toString()
        .trim();
    final titulo = 'Solicitud aprobada';
    final mensaje = numeroFormulario.isEmpty
        ? 'Tu solicitud de $tipoSolicitud fue aprobada por $aprobador.'
        : 'Tu solicitud N° $numeroFormulario de $tipoSolicitud fue aprobada por $aprobador.';

    await _db.collection('avisos').add({
      'titulo': titulo,
      'mensaje': mensaje,
      'fecha': DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
      'timestamp': FieldValue.serverTimestamp(),
      'sedeId': sedeId,
      'sede': sedeNombre,
      'destinatarioCorreo': correoDestino,
      'destinatarioNombre': colaborador,
      'tipo': 'solicitud_aprobada',
      'solicitudId': idDoc,
      'solicitudTipo': tipoSolicitud,
      'creadoPor': aprobador,
      'leido': false,
    });
  }

  Future<void> asignarHorarioAlmuerzoAdministrativo({
    required String usuarioDocId,
    required String correo,
    required String nombre,
    required String sedeId,
    required String sedeNombre,
    required String horaInicio,
    required String horaFin,
    String? asignadoPor,
  }) async {
    final userRef = _db.collection('usuarios').doc(usuarioDocId);
    final userSnapshot = await userRef.get();
    final actual = userSnapshot.data() ?? {};
    final horarioAnterior = (actual['almuerzo_horario_label'] ?? '')
        .toString()
        .trim();
    final nuevoHorario = '$horaInicio a $horaFin';

    await userRef.set({
      'almuerzo_inicio_asignado': horaInicio,
      'almuerzo_fin_asignado': horaFin,
      'almuerzo_horario_label': nuevoHorario,
      'almuerzo_actualizado_en': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final correoDestino = correo.trim().toLowerCase();
    if (correoDestino.isEmpty) {
      return;
    }

    final esActualizacion =
        horarioAnterior.isNotEmpty && horarioAnterior != nuevoHorario;
    final titulo = esActualizacion
        ? 'Horario de almuerzo actualizado'
        : 'Horario de almuerzo asignado';
    final mensaje = esActualizacion
        ? 'Su horario de almuerzo fue actualizado a $nuevoHorario.'
        : 'Se le asignó su horario de almuerzo de $nuevoHorario.';

    await _db.collection('avisos').add({
      'titulo': titulo,
      'mensaje': mensaje,
      'fecha': DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
      'timestamp': FieldValue.serverTimestamp(),
      'sedeId': sedeId,
      'sede': sedeNombre,
      'destinatarioCorreo': correoDestino,
      'destinatarioNombre': nombre,
      'tipo': 'almuerzo_asignado',
      'accionRuta': 'almuerzos',
      'creadoPor': (asignadoPor ?? 'RRHH').toString().trim(),
      'leido': false,
    });
  }

  String _resolverRolPersonal(dynamic value) {
    if (UserRoleAccess.isAdminRole(value)) {
      return UserRoleAccess.roleAdmin;
    }
    if (UserRoleAccess.isRrhhRole(value)) {
      return UserRoleAccess.roleRrhh;
    }
    if (UserRoleAccess.isAdministrativeRole(value)) {
      return UserRoleAccess.roleAdministrative;
    }
    return UserRoleAccess.roleTeacher;
  }

  String _resolverTipoHorarioPersonal({
    required String rol,
    required String horarioId,
  }) {
    final rolNormalizado = rol.trim().toLowerCase();
    final horarioNormalizado = horarioId.trim().toUpperCase();

    if (rolNormalizado == 'personal administrativo' ||
        rolNormalizado == 'administrativo' ||
        rolNormalizado == 'rrhh' ||
        rolNormalizado == 'admin') {
      return 'administrativo';
    }

    if (horarioNormalizado.startsWith('NOCT')) {
      return 'nocturno';
    }

    if (horarioNormalizado.startsWith('TC')) {
      return 'completo';
    }

    return 'medio_tiempo';
  }

  String _normalizarAreaTexto(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n');
  }

  String _slugArea(String value) {
    final normalized = _normalizarAreaTexto(value)
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return normalized.isEmpty ? 'general' : normalized;
  }

  String _defaultAreaNombreForRole(String rol) {
    if (UserRoleAccess.isTeacherRole(rol)) {
      return 'Docencia';
    }
    if (UserRoleAccess.isAdministrativeRole(rol)) {
      return 'Administracion';
    }
    if (UserRoleAccess.isRrhhRole(rol)) {
      return 'RRHH';
    }
    if (UserRoleAccess.isAdminRole(rol)) {
      return 'Administracion';
    }
    return 'General';
  }

  String _defaultCargoForRole(String rol) {
    if (UserRoleAccess.isTeacherRole(rol)) {
      return 'Docente';
    }
    if (UserRoleAccess.isAdministrativeRole(rol)) {
      return 'Administrativo';
    }
    if (UserRoleAccess.isRrhhRole(rol)) {
      return 'Analista RRHH';
    }
    if (UserRoleAccess.isAdminRole(rol)) {
      return 'Administrador';
    }
    return 'Colaborador';
  }

  String _buildEspecialidadLegacy({
    required String areaNombre,
    required String cargo,
  }) {
    if (areaNombre.isEmpty && cargo.isEmpty) {
      return '';
    }
    if (areaNombre.isEmpty) {
      return cargo;
    }
    if (cargo.isEmpty) {
      return areaNombre;
    }
    if (_normalizarAreaTexto(areaNombre) == _normalizarAreaTexto(cargo)) {
      return cargo;
    }
    return '$areaNombre - $cargo';
  }

  String _resolverTipoVinculacionDesdeRol(dynamic rol) {
    if (UserRoleAccess.isAdministrativeRole(rol) ||
        UserRoleAccess.isRrhhRole(rol) ||
        UserRoleAccess.isAdminRole(rol)) {
      return 'administrativo';
    }
    return 'academico';
  }

  String _normalizarTipoVinculacion(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    if (normalized == 'administrativo') {
      return 'administrativo';
    }
    return 'academico';
  }

  String _etiquetaTipoVinculacion(String tipo) {
    return tipo == 'administrativo'
        ? UserRoleAccess.roleAdministrative
        : 'Personal academico';
  }

  List<String> _sanitizarListaHorariosDesdeUsuario(Map<String, dynamic>? data) {
    return (data?['horarios_asignados'] as List? ?? const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Map<String, dynamic> _buildVinculacionAsistencia({
    required String tipoVinculacion,
    required String rol,
    required String horarioId,
    required String areaId,
    required String areaNombre,
    required String cargo,
    bool esSecundaria = false,
  }) {
    return {
      'tipoVinculacion': _normalizarTipoVinculacion(tipoVinculacion),
      'rol': rol.trim(),
      'horarioId': horarioId.trim().toUpperCase(),
      'areaId': areaId.trim(),
      'areaNombre': areaNombre.trim(),
      'cargo': cargo.trim(),
      'esSecundaria': esSecundaria,
    };
  }

  List<Map<String, dynamic>> resolverVinculacionesAsistenciaUsuario(
    Map<String, dynamic>? usuarioData,
  ) {
    if (usuarioData == null) {
      return const <Map<String, dynamic>>[];
    }

    final raw = usuarioData['vinculacionesAsistencia'];
    if (raw is List) {
      final items = raw
          .whereType<Map>()
          .map(
            (entry) => _buildVinculacionAsistencia(
              tipoVinculacion:
                  (entry['tipoVinculacion'] ??
                          _resolverTipoVinculacionDesdeRol(entry['rol']))
                      .toString(),
              rol: (entry['rol'] ?? '').toString(),
              horarioId: (entry['horarioId'] ?? '').toString(),
              areaId: (entry['areaId'] ?? '').toString(),
              areaNombre: (entry['areaNombre'] ?? '').toString(),
              cargo: (entry['cargo'] ?? '').toString(),
              esSecundaria: entry['esSecundaria'] == true,
            ),
          )
          .where((entry) => (entry['horarioId'] ?? '').toString().isNotEmpty)
          .toList();

      if (items.isNotEmpty) {
        return items;
      }
    }

    final rolPrincipal = _resolverRolPersonal(usuarioData['rol']);
    final horariosPrincipales = _sanitizarListaHorariosDesdeUsuario(
      usuarioData,
    );
    final horarioPrincipal = horariosPrincipales.isNotEmpty
        ? horariosPrincipales.first
        : '';
    final areaIdPrincipal = (usuarioData['areaId'] ?? '').toString().trim();
    final areaNombrePrincipal = (usuarioData['areaNombre'] ?? '')
        .toString()
        .trim();
    final cargoPrincipal =
        ((usuarioData['cargo'] ?? '').toString().trim().isNotEmpty
                ? usuarioData['cargo']
                : usuarioData['especialidad'])
            .toString();

    final vinculaciones = <Map<String, dynamic>>[];
    if (horarioPrincipal.isNotEmpty) {
      vinculaciones.add(
        _buildVinculacionAsistencia(
          tipoVinculacion: _resolverTipoVinculacionDesdeRol(rolPrincipal),
          rol: rolPrincipal,
          horarioId: horarioPrincipal,
          areaId: areaIdPrincipal,
          areaNombre: areaNombrePrincipal,
          cargo: cargoPrincipal,
        ),
      );
    }

    final tieneSecundaria =
        usuarioData['tieneVinculacionAcademicaSecundaria'] == true;
    final horarioSecundario =
        (usuarioData['horarioAcademicoSecundarioId'] ?? '')
            .toString()
            .trim()
            .toUpperCase();

    if (tieneSecundaria && horarioSecundario.isNotEmpty) {
      vinculaciones.add(
        _buildVinculacionAsistencia(
          tipoVinculacion: 'academico',
          rol: UserRoleAccess.roleTeacher,
          horarioId: horarioSecundario,
          areaId: (usuarioData['areaAcademicaSecundariaId'] ?? '')
              .toString()
              .trim(),
          areaNombre: (usuarioData['areaAcademicaSecundariaNombre'] ?? '')
              .toString()
              .trim(),
          cargo: (usuarioData['cargoAcademicoSecundario'] ?? '')
              .toString()
              .trim(),
          esSecundaria: true,
        ),
      );
    }

    return vinculaciones;
  }

  Future<Map<String, dynamic>> _evaluarContextosMarcacion({
    required DateTime ahora,
    required bool esEntrada,
    required List<Map<String, dynamic>> vinculacionesAsistencia,
    String? sedeId,
  }) async {
    final ahoraMin = (ahora.hour * 60) + ahora.minute;
    final horarioEspecial = sedeId != null && sedeId.trim().isNotEmpty
        ? await obtenerHorarioEspecialSede(sedeId: sedeId.trim(), fecha: ahora)
        : null;
    final horaEntradaEspecial = (horarioEspecial?['horaEntradaEspecial'] ?? '')
        .toString()
        .trim();
    final horaSalidaEspecial = (horarioEspecial?['horaSalidaEspecial'] ?? '')
        .toString()
        .trim();
    final toleranciaSalidaAntesMinutos = _resolverToleranciaHorarioEspecial(
      horarioEspecial?['toleranciaSalidaAntesMinutos'],
      _horarioEspecialToleranciaSalidaAntesDefault,
    );
    final toleranciaSalidaDespuesMinutos = _resolverToleranciaHorarioEspecial(
      horarioEspecial?['toleranciaSalidaDespuesMinutos'],
      _horarioEspecialToleranciaSalidaDespuesDefault,
    );
    final salidaEspecialMin = horaSalidaEspecial.isEmpty
        ? null
        : _horaEnMinutos(horaSalidaEspecial);
    final ventanaSalidaEspecialInicio = salidaEspecialMin == null
        ? null
        : salidaEspecialMin - toleranciaSalidaAntesMinutos;
    final ventanaSalidaEspecialFin = salidaEspecialMin == null
        ? null
        : salidaEspecialMin + toleranciaSalidaDespuesMinutos;
    final ventanaSalidaEspecialLabel =
        ventanaSalidaEspecialInicio == null || ventanaSalidaEspecialFin == null
        ? ''
        : '${_minutosAHora(ventanaSalidaEspecialInicio)} a ${_minutosAHora(ventanaSalidaEspecialFin)}';

    final horariosDisponibles = await _obtenerHorariosPorIds(
      vinculacionesAsistencia
          .map((v) => (v['horarioId'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .toList(),
    );

    final horariosEvaluados = <Map<String, dynamic>>[];
    final contextosActivos = <Map<String, dynamic>>[];

    for (final vinculacion in vinculacionesAsistencia) {
      final horarioId = (vinculacion['horarioId'] ?? '').toString().trim();
      if (horarioId.isEmpty) {
        continue;
      }

      final data = horariosDisponibles[horarioId];
      if (data == null) {
        continue;
      }

      final entradaBase = data['entrada']?.toString() ?? '00:00';
      final salidaBase = data['salida']?.toString() ?? '00:00';
      final entrada = horaEntradaEspecial.isNotEmpty
          ? horaEntradaEspecial
          : entradaBase;
      final salida = horaSalidaEspecial.isNotEmpty
          ? horaSalidaEspecial
          : salidaBase;
      final entradaMin = _horaEnMinutos(entrada);
      final salidaMin = _horaEnMinutos(salida);
      final esTiempoCompleto = _esHorarioTiempoCompleto(horarioId, data);
      final tipoVinculacion = _normalizarTipoVinculacion(
        vinculacion['tipoVinculacion'],
      );
      final referenciaMarcacionMin = esEntrada ? entradaMin : salidaMin;
      final ventanaNormal = _ventanaMarcacionDesdeReferencia(
        referenciaMarcacionMin,
      );
      final ventanaMarcacionInicio =
          !esEntrada &&
              horarioEspecial != null &&
              ventanaSalidaEspecialInicio != null &&
              ventanaSalidaEspecialFin != null
          ? ventanaSalidaEspecialInicio
          : ventanaNormal.inicio;
      final ventanaMarcacionFin =
          !esEntrada &&
              horarioEspecial != null &&
              ventanaSalidaEspecialInicio != null &&
              ventanaSalidaEspecialFin != null
          ? ventanaSalidaEspecialFin
          : (esEntrada ? salidaMin : ventanaNormal.fin);

      horariosEvaluados.add({
        'id': horarioId,
        'entradaMin': entradaMin,
        'salidaMin': salidaMin,
        'rango': '$entrada a $salida',
        'esTiempoCompleto': esTiempoCompleto,
        'tipoVinculacion': tipoVinculacion,
        'ventanaInicioMin': ventanaMarcacionInicio,
        'ventanaFinMin': ventanaMarcacionFin,
        'ventana': _etiquetaVentanaMarcacion(
          ventanaMarcacionInicio,
          ventanaMarcacionFin,
        ),
      });

      final horarioActivo =
          ahoraMin >= ventanaMarcacionInicio && ahoraMin <= ventanaMarcacionFin;

      if (!horarioActivo) {
        continue;
      }

      contextosActivos.add({
        ...data,
        'horarioId': horarioId,
        'tipoVinculacion': tipoVinculacion,
        'tipoVinculacionLabel': _etiquetaTipoVinculacion(tipoVinculacion),
        'rolVinculado': (vinculacion['rol'] ?? '').toString().trim(),
        'cargoVinculado': (vinculacion['cargo'] ?? '').toString().trim(),
        'areaVinculada': (vinculacion['areaNombre'] ?? '').toString().trim(),
        'esSecundaria': vinculacion['esSecundaria'] == true,
        'entrada': entrada,
        'salida': salida,
        'entrada_base': entradaBase,
        'salida_base': salidaBase,
        'horario_especial_documento_id': horarioEspecial?['documentoId'],
        'horario_especial_fecha_clave': horarioEspecial?['fechaClave'],
        'horario_especial_motivo': horarioEspecial?['motivo'],
        'horario_especial_entrada': horaEntradaEspecial,
        'horario_especial_salida': horaSalidaEspecial,
        'horario_especial_ventana_salida': ventanaSalidaEspecialLabel,
      });
    }

    return {
      'activos': contextosActivos,
      'horariosEvaluados': horariosEvaluados,
      'horarioEspecial': horarioEspecial,
      'horaEntradaEspecial': horaEntradaEspecial,
      'horaSalidaEspecial': horaSalidaEspecial,
      'toleranciaSalidaAntesMinutos': toleranciaSalidaAntesMinutos,
      'toleranciaSalidaDespuesMinutos': toleranciaSalidaDespuesMinutos,
      'ventanaSalidaEspecialInicio': ventanaSalidaEspecialInicio,
      'ventanaSalidaEspecialFin': ventanaSalidaEspecialFin,
      'ventanaSalidaEspecialLabel': ventanaSalidaEspecialLabel,
      'ahoraMin': ahoraMin,
    };
  }

  Future<Map<String, dynamic>?> _resolverContextoDesdeUltimaEntrada({
    required Map<String, dynamic>? ultimoRegistro,
    required List<Map<String, dynamic>> vinculacionesAsistencia,
    required Map<String, dynamic>? horarioEspecial,
    required String horaEntradaEspecial,
    required String horaSalidaEspecial,
    required String ventanaSalidaEspecialLabel,
  }) async {
    if (ultimoRegistro == null) {
      return null;
    }

    final horarioIdUltimo = (ultimoRegistro['horario_id'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    final tipoUltimo = _normalizarTipoVinculacion(
      ultimoRegistro['tipo_vinculacion'],
    );

    Map<String, dynamic>? vinculacionSeleccionada;
    for (final vinculacion in vinculacionesAsistencia) {
      final horarioId = (vinculacion['horarioId'] ?? '').toString().trim();
      if (horarioId.isEmpty) {
        continue;
      }

      final coincideHorario =
          horarioIdUltimo.isNotEmpty &&
          horarioId.toUpperCase() == horarioIdUltimo;
      final coincideTipo =
          _normalizarTipoVinculacion(vinculacion['tipoVinculacion']) ==
          tipoUltimo;

      if (coincideHorario && coincideTipo) {
        vinculacionSeleccionada = vinculacion;
        break;
      }
    }

    if (vinculacionSeleccionada == null &&
        vinculacionesAsistencia.length == 1 &&
        horarioIdUltimo.isEmpty) {
      vinculacionSeleccionada = vinculacionesAsistencia.first;
    }

    if (vinculacionSeleccionada == null) {
      return null;
    }

    final horarioId = (vinculacionSeleccionada['horarioId'] ?? '')
        .toString()
        .trim();
    if (horarioId.isEmpty) {
      return null;
    }

    final horariosDisponibles = await _obtenerHorariosPorIds([horarioId]);
    final data = horariosDisponibles[horarioId];
    if (data == null) {
      return null;
    }

    final entradaBase = data['entrada']?.toString() ?? '00:00';
    final salidaBase = data['salida']?.toString() ?? '00:00';
    final entrada = horaEntradaEspecial.isNotEmpty
        ? horaEntradaEspecial
        : entradaBase;
    final salida = horaSalidaEspecial.isNotEmpty ? horaSalidaEspecial : salidaBase;
    final tipoVinculacion = _normalizarTipoVinculacion(
      vinculacionSeleccionada['tipoVinculacion'],
    );

    return {
      ...data,
      'horarioId': horarioId,
      'tipoVinculacion': tipoVinculacion,
      'tipoVinculacionLabel': _etiquetaTipoVinculacion(tipoVinculacion),
      'rolVinculado': (vinculacionSeleccionada['rol'] ?? '').toString().trim(),
      'cargoVinculado': (vinculacionSeleccionada['cargo'] ?? '')
          .toString()
          .trim(),
      'areaVinculada': (vinculacionSeleccionada['areaNombre'] ?? '')
          .toString()
          .trim(),
      'esSecundaria': vinculacionSeleccionada['esSecundaria'] == true,
      'entrada': entrada,
      'salida': salida,
      'entrada_base': entradaBase,
      'salida_base': salidaBase,
      'horario_especial_documento_id': horarioEspecial?['documentoId'],
      'horario_especial_fecha_clave': horarioEspecial?['fechaClave'],
      'horario_especial_motivo': horarioEspecial?['motivo'],
      'horario_especial_entrada': horaEntradaEspecial,
      'horario_especial_salida': horaSalidaEspecial,
      'horario_especial_ventana_salida': ventanaSalidaEspecialLabel,
    };
  }

  Future<List<Map<String, dynamic>>> obtenerContextosMarcacionActivos({
    required List<Map<String, dynamic>> vinculacionesAsistencia,
    required bool esEntrada,
    String? sedeId,
  }) async {
    final evaluacion = await _evaluarContextosMarcacion(
      ahora: DateTime.now(),
      esEntrada: esEntrada,
      vinculacionesAsistencia: vinculacionesAsistencia,
      sedeId: sedeId,
    );

    return List<Map<String, dynamic>>.from(
      evaluacion['activos'] as List? ?? const <Map<String, dynamic>>[],
    );
  }

  String _catalogoAreasVersion(String sedeId) {
    if (SedeAccess.normalize(sedeId) == SedeAccess.matrizId) {
      return 'matriz_fijo_v1';
    }
    return 'default_v1';
  }

  List<Map<String, dynamic>> _defaultAreasForSedeCatalog(String sedeId) {
    if (SedeAccess.normalize(sedeId) == SedeAccess.matrizId) {
      return const [
        {
          'nombre': 'Secretaria General y Archivo',
          'requiereGeolocalizacionPorDefecto': true,
        },
        {
          'nombre': 'Unidad Financiera',
          'requiereGeolocalizacionPorDefecto': true,
        },
        {
          'nombre': 'Unidad de Bienestar y Admisiones',
          'requiereGeolocalizacionPorDefecto': true,
        },
        {
          'nombre': 'Departamento de Recursos Humanos',
          'requiereGeolocalizacionPorDefecto': true,
        },
        {
          'nombre': 'Departamento de IT',
          'requiereGeolocalizacionPorDefecto': true,
        },
        {
          'nombre': 'Coordinador carrera de formacion tecnica',
          'requiereGeolocalizacionPorDefecto': true,
        },
        {
          'nombre': 'Educacion continua',
          'requiereGeolocalizacionPorDefecto': true,
        },
        {
          'nombre': 'Coordinador de investigacion',
          'requiereGeolocalizacionPorDefecto': true,
        },
        {
          'nombre':
              'Coordinador de vinculacion con la sociedad y Practica Pre Profesionales',
          'requiereGeolocalizacionPorDefecto': true,
        },
      ];
    }

    return const [
      {'nombre': 'Administracion', 'requiereGeolocalizacionPorDefecto': true},
      {'nombre': 'Docencia', 'requiereGeolocalizacionPorDefecto': true},
      {'nombre': 'Financiero', 'requiereGeolocalizacionPorDefecto': true},
      {'nombre': 'Marketing', 'requiereGeolocalizacionPorDefecto': false},
      {'nombre': 'RRHH', 'requiereGeolocalizacionPorDefecto': true},
    ];
  }

  Future<void> asegurarAreasBasePersonalSede({required String sedeId}) async {
    final markerRef = _db
        .collection('areas')
        .doc('${sedeId}__seed_marker_${_catalogoAreasVersion(sedeId)}');
    final marker = await markerRef.get();
    if (marker.exists) {
      return;
    }

    final sedeNombre = SedeAccess.displayNameForId(sedeId);
    final batch = _db.batch();

    for (final area in _defaultAreasForSedeCatalog(sedeId)) {
      final nombre = (area['nombre'] ?? '').toString().trim();
      if (nombre.isEmpty) {
        continue;
      }

      final slug = _slugArea(nombre);
      final ref = _db.collection('areas').doc('${sedeId}_$slug');
      batch.set(ref, {
        'nombre': nombre,
        'nombreNormalizado': _normalizarAreaTexto(nombre),
        'slug': slug,
        'activa': true,
        'requiereGeolocalizacionPorDefecto':
            area['requiereGeolocalizacionPorDefecto'] == true,
        'sedeId': sedeId,
        'sede': sedeNombre,
        'actualizadoEn': FieldValue.serverTimestamp(),
        'creadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    batch.set(markerRef, {
      'tipo': 'seed_marker',
      'sedeId': sedeId,
      'sede': sedeNombre,
      'actualizadoEn': FieldValue.serverTimestamp(),
      'creadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> guardarAreaPersonalSede({
    String? areaDocId,
    required String sedeId,
    required String nombre,
    required bool requiereGeolocalizacionPorDefecto,
    bool activa = true,
  }) async {
    final nombreLimpio = nombre.trim();
    if (nombreLimpio.isEmpty) {
      throw Exception('Ingrese el nombre del area.');
    }

    final slug = _slugArea(nombreLimpio);
    final targetId = (areaDocId == null || areaDocId.trim().isEmpty)
        ? '${sedeId}_$slug'
        : areaDocId.trim();

    final ref = _db.collection('areas').doc(targetId);
    final payload = <String, dynamic>{
      'nombre': nombreLimpio,
      'nombreNormalizado': _normalizarAreaTexto(nombreLimpio),
      'slug': slug,
      'activa': activa,
      'sedeId': sedeId,
      'sede': SedeAccess.displayNameForId(sedeId),
      'actualizadoEn': FieldValue.serverTimestamp(),
      'creadoEn': FieldValue.serverTimestamp(),
    };
    payload.addAll(
      _buildGpsTemporalPayload(
        requiereGeolocalizacion: requiereGeolocalizacionPorDefecto,
        gpsField: 'requiereGeolocalizacionPorDefecto',
      ),
    );
    await ref.set(payload, SetOptions(merge: true));
  }

  Future<void> eliminarAreaPersonalSede({
    required String areaDocId,
    required String sedeId,
    required String nombre,
  }) async {
    final targetId = areaDocId.trim();
    final nombreLimpio = nombre.trim();
    if (targetId.isEmpty) {
      throw Exception('No se encontro el departamento a eliminar.');
    }

    final usuariosPorId = await _db
        .collection('usuarios')
        .where('sedeId', isEqualTo: sedeId)
        .where('areaId', isEqualTo: targetId)
        .limit(1)
        .get();
    if (usuariosPorId.docs.isNotEmpty) {
      throw Exception(
        'No se puede eliminar este departamento porque tiene personal asignado.',
      );
    }

    if (nombreLimpio.isNotEmpty) {
      final usuariosPorNombre = await _db
          .collection('usuarios')
          .where('sedeId', isEqualTo: sedeId)
          .where('areaNombre', isEqualTo: nombreLimpio)
          .limit(1)
          .get();
      if (usuariosPorNombre.docs.isNotEmpty) {
        throw Exception(
          'No se puede eliminar este departamento porque tiene personal asignado.',
        );
      }
    }

    await _db.collection('areas').doc(targetId).delete();
  }

  String _fechaClaveHorarioEspecial(DateTime fecha) {
    final soloFecha = DateTime(fecha.year, fecha.month, fecha.day);
    return DateFormat('yyyy-MM-dd').format(soloFecha);
  }

  String _docIdHorarioEspecial({
    required String sedeId,
    required DateTime fecha,
  }) {
    return '${sedeId.trim()}_${_fechaClaveHorarioEspecial(fecha)}';
  }

  bool _horaEspecialValida(String value) {
    return RegExp(r'^\d{1,2}:\d{2}$').hasMatch(value.trim());
  }

  Future<void> guardarHorarioEspecialSede({
    required String sedeId,
    required DateTime fecha,
    required String horaEntradaEspecial,
    required String horaSalidaEspecial,
    required String motivo,
    bool activo = true,
    String? registradoPor,
    int toleranciaSalidaAntesMinutos =
        _horarioEspecialToleranciaSalidaAntesDefault,
    int toleranciaSalidaDespuesMinutos =
        _horarioEspecialToleranciaSalidaDespuesDefault,
  }) async {
    final sedeLimpia = sedeId.trim();
    final entradaLimpia = _normalizarHoraDesdeTexto(horaEntradaEspecial);
    final salidaLimpia = _normalizarHoraDesdeTexto(horaSalidaEspecial);
    final motivoLimpio = motivo.trim();

    if (sedeLimpia.isEmpty) {
      throw Exception('No se encontro la sede para el horario especial.');
    }
    if (!_horaEspecialValida(entradaLimpia)) {
      throw Exception('Ingrese una hora de entrada valida en formato HH:mm.');
    }
    if (!_horaEspecialValida(salidaLimpia)) {
      throw Exception('Ingrese una hora de salida valida en formato HH:mm.');
    }
    if (_horaEnMinutos(salidaLimpia) <= _horaEnMinutos(entradaLimpia)) {
      throw Exception(
        'La hora de salida especial debe ser mayor que la hora de entrada.',
      );
    }
    if (motivoLimpio.isEmpty) {
      throw Exception('Ingrese el motivo del horario especial.');
    }

    final fechaBase = DateTime(fecha.year, fecha.month, fecha.day);
    final docId = _docIdHorarioEspecial(sedeId: sedeLimpia, fecha: fechaBase);
    final ref = _db.collection('horarios_especiales').doc(docId);
    final existing = await ref.get();
    final responsable = (registradoPor ?? '').trim();

    final payload = <String, dynamic>{
      'sedeId': sedeLimpia,
      'sede': SedeAccess.displayNameForId(sedeLimpia),
      'fecha': Timestamp.fromDate(fechaBase),
      'fechaClave': _fechaClaveHorarioEspecial(fechaBase),
      'horaEntradaEspecial': entradaLimpia,
      'horaSalidaEspecial': salidaLimpia,
      'toleranciaSalidaAntesMinutos': toleranciaSalidaAntesMinutos < 0
          ? _horarioEspecialToleranciaSalidaAntesDefault
          : toleranciaSalidaAntesMinutos,
      'toleranciaSalidaDespuesMinutos': toleranciaSalidaDespuesMinutos < 0
          ? _horarioEspecialToleranciaSalidaDespuesDefault
          : toleranciaSalidaDespuesMinutos,
      'motivo': motivoLimpio,
      'activo': activo,
      'aplicaATodaLaSede': true,
      'tipo': 'salida_anticipada_autorizada',
      'actualizadoEn': FieldValue.serverTimestamp(),
    };

    if (responsable.isNotEmpty) {
      payload['actualizadoPor'] = responsable;
    }

    if (!existing.exists) {
      payload['creadoEn'] = FieldValue.serverTimestamp();
      if (responsable.isNotEmpty) {
        payload['creadoPor'] = responsable;
      }
    }

    await ref.set(payload, SetOptions(merge: true));
  }

  Future<void> actualizarHorarioEspecialSedeEstado({
    required String docId,
    required bool activo,
    String? actualizadoPor,
  }) async {
    final targetId = docId.trim();
    if (targetId.isEmpty) {
      throw Exception('No se encontro el horario especial a actualizar.');
    }

    final payload = <String, dynamic>{
      'activo': activo,
      'actualizadoEn': FieldValue.serverTimestamp(),
    };
    final responsable = (actualizadoPor ?? '').trim();
    if (responsable.isNotEmpty) {
      payload['actualizadoPor'] = responsable;
    }

    await _db
        .collection('horarios_especiales')
        .doc(targetId)
        .set(payload, SetOptions(merge: true));
  }

  Future<void> eliminarHorarioEspecialSede({required String docId}) async {
    final targetId = docId.trim();
    if (targetId.isEmpty) {
      throw Exception('No se encontro el horario especial a eliminar.');
    }

    await _db.collection('horarios_especiales').doc(targetId).delete();
  }

  Future<Map<String, dynamic>?> obtenerHorarioEspecialSede({
    required String sedeId,
    required DateTime fecha,
  }) async {
    final sedeLimpia = sedeId.trim();
    if (sedeLimpia.isEmpty) {
      return null;
    }

    final docId = _docIdHorarioEspecial(
      sedeId: sedeLimpia,
      fecha: DateTime(fecha.year, fecha.month, fecha.day),
    );
    final doc = await _db.collection('horarios_especiales').doc(docId).get();
    if (!doc.exists) {
      return null;
    }

    final data = doc.data() as Map<String, dynamic>;
    if (data['activo'] == false) {
      return null;
    }

    return {...data, 'documentoId': doc.id};
  }

  Future<void> guardarUsuarioPersonalSede({
    String? usuarioDocId,
    required String nombre,
    required String correo,
    String? cedula,
    String? password,
    required String rol,
    required String sedeId,
    String? telefono,
    String? especialidad,
    String? horarioAsignadoId,
    String? areaId,
    String? areaNombre,
    String? cargo,
    bool? requiereGeolocalizacion,
    bool tieneVinculacionAcademicaSecundaria = false,
    String? horarioAcademicoSecundarioId,
    String? areaAcademicaSecundariaId,
    String? areaAcademicaSecundariaNombre,
    String? cargoAcademicoSecundario,
  }) async {
    final nombreLimpio = nombre.trim();
    final correoLimpio = correo.trim().toLowerCase();
    final cedulaLimpia = (cedula ?? '').trim();
    final passwordLimpio = password?.trim() ?? '';
    final rolLimpio = _resolverRolPersonal(rol);
    final horarioLimpio = (horarioAsignadoId ?? '').trim().toUpperCase();
    final telefonoLimpio = telefono?.trim() ?? '';
    final especialidadLimpia = especialidad?.trim() ?? '';
    final areaNombreLimpia = areaNombre?.trim() ?? '';
    final cargoLimpio = cargo?.trim() ?? '';
    final horarioAcademicoSecundarioLimpio =
        (horarioAcademicoSecundarioId ?? '').trim().toUpperCase();
    final areaAcademicaSecundariaIdLimpia = (areaAcademicaSecundariaId ?? '')
        .trim();
    final areaAcademicaSecundariaNombreLimpia =
        (areaAcademicaSecundariaNombre ?? '').trim();
    final cargoAcademicoSecundarioLimpio = (cargoAcademicoSecundario ?? '')
        .trim();
    final esNuevo = usuarioDocId == null || usuarioDocId.trim().isEmpty;

    if (nombreLimpio.isEmpty) {
      throw Exception('Ingrese el nombre del colaborador.');
    }

    if (correoLimpio.isEmpty) {
      throw Exception('Ingrese el correo del colaborador.');
    }

    if (!RegExp(r'^\d{10}$').hasMatch(cedulaLimpia)) {
      throw Exception('La cedula debe tener exactamente 10 digitos.');
    }

    if (!RegExp(r'^\d{10}$').hasMatch(telefonoLimpio)) {
      throw Exception('El telefono debe tener exactamente 10 digitos.');
    }

    if (esNuevo && passwordLimpio.isEmpty) {
      throw Exception('Ingrese la contraseña del colaborador.');
    }

    if (passwordLimpio.isNotEmpty) {
      _validarPasswordSeguraOrThrow(passwordLimpio);
    }

    if (horarioLimpio.isEmpty) {
      throw Exception('Ingrese el horario asignado.');
    }

    if (tieneVinculacionAcademicaSecundaria &&
        horarioAcademicoSecundarioLimpio.isEmpty) {
      throw Exception(
        'Ingrese el horario academico secundario del colaborador.',
      );
    }

    final existentes = await _db
        .collection('usuarios')
        .where('correo', isEqualTo: correoLimpio)
        .limit(10)
        .get();

    for (final doc in existentes.docs) {
      if (!esNuevo && doc.id == usuarioDocId) {
        continue;
      }
      throw Exception('Ya existe un usuario registrado con ese correo.');
    }

    final ref = esNuevo
        ? _db.collection('usuarios').doc()
        : _db.collection('usuarios').doc(usuarioDocId.trim());

    final tipoHorario = _resolverTipoHorarioPersonal(
      rol: rolLimpio,
      horarioId: horarioLimpio,
    );

    final areaFinal = areaNombreLimpia.isNotEmpty
        ? areaNombreLimpia
        : (especialidadLimpia.isNotEmpty
              ? especialidadLimpia
              : _defaultAreaNombreForRole(rolLimpio));
    final cargoFinal = cargoLimpio.isNotEmpty
        ? cargoLimpio
        : (especialidadLimpia.isNotEmpty
              ? especialidadLimpia
              : _defaultCargoForRole(rolLimpio));
    final areaIdLimpia = areaId?.trim() ?? '';
    final areaIdFinal = areaIdLimpia.isNotEmpty
        ? areaIdLimpia
        : '${sedeId}_${_slugArea(areaFinal)}';
    final requiereGeoFinal = requiereGeolocalizacion ?? true;
    final tieneSecundariaFinal =
        UserRoleAccess.isAdministrativeRole(rolLimpio) &&
        tieneVinculacionAcademicaSecundaria &&
        horarioAcademicoSecundarioLimpio.isNotEmpty;
    final areaAcademicaSecundariaNombreFinal =
        areaAcademicaSecundariaNombreLimpia.isNotEmpty
        ? areaAcademicaSecundariaNombreLimpia
        : _defaultAreaNombreForRole(UserRoleAccess.roleTeacher);
    final areaAcademicaSecundariaIdFinal =
        areaAcademicaSecundariaIdLimpia.isNotEmpty
        ? areaAcademicaSecundariaIdLimpia
        : '${sedeId}_${_slugArea(areaAcademicaSecundariaNombreFinal)}';
    final cargoAcademicoSecundarioFinal =
        cargoAcademicoSecundarioLimpio.isNotEmpty
        ? cargoAcademicoSecundarioLimpio
        : _defaultCargoForRole(UserRoleAccess.roleTeacher);
    final vinculacionesAsistencia = <Map<String, dynamic>>[
      _buildVinculacionAsistencia(
        tipoVinculacion: _resolverTipoVinculacionDesdeRol(rolLimpio),
        rol: rolLimpio,
        horarioId: horarioLimpio,
        areaId: areaIdFinal,
        areaNombre: areaFinal,
        cargo: cargoFinal,
      ),
      if (tieneSecundariaFinal)
        _buildVinculacionAsistencia(
          tipoVinculacion: 'academico',
          rol: UserRoleAccess.roleTeacher,
          horarioId: horarioAcademicoSecundarioLimpio,
          areaId: areaAcademicaSecundariaIdFinal,
          areaNombre: areaAcademicaSecundariaNombreFinal,
          cargo: cargoAcademicoSecundarioFinal,
          esSecundaria: true,
        ),
    ];

    final payload = <String, dynamic>{
      'nombre': nombreLimpio,
      'correo': correoLimpio,
      'cedula': cedulaLimpia,
      'rol': rolLimpio,
      'tipo_horario': tipoHorario,
      'horarios_asignados': [horarioLimpio],
      'telefono': telefonoLimpio,
      'areaId': areaIdFinal,
      'areaNombre': areaFinal,
      'cargo': cargoFinal,
      'especialidad': _buildEspecialidadLegacy(
        areaNombre: areaFinal,
        cargo: cargoFinal,
      ),
      'sede': SedeAccess.displayNameForId(sedeId),
      'sedeId': sedeId,
      'dashboardWeb': sedeId,
      'tieneVinculacionAcademicaSecundaria': tieneSecundariaFinal,
      'horarioAcademicoSecundarioId': tieneSecundariaFinal
          ? horarioAcademicoSecundarioLimpio
          : FieldValue.delete(),
      'areaAcademicaSecundariaId': tieneSecundariaFinal
          ? areaAcademicaSecundariaIdFinal
          : FieldValue.delete(),
      'areaAcademicaSecundariaNombre': tieneSecundariaFinal
          ? areaAcademicaSecundariaNombreFinal
          : FieldValue.delete(),
      'cargoAcademicoSecundario': tieneSecundariaFinal
          ? cargoAcademicoSecundarioFinal
          : FieldValue.delete(),
      'vinculacionesAsistencia': vinculacionesAsistencia,
      'actualizadoEn': FieldValue.serverTimestamp(),
    };
    payload.addAll(
      _buildGpsTemporalPayload(
        requiereGeolocalizacion: requiereGeoFinal,
        gpsField: 'requiereGeolocalizacion',
      ),
    );

    if (passwordLimpio.isNotEmpty) {
      payload.addAll(await _crearPayloadPasswordSeguro(passwordLimpio));
    }

    if (esNuevo) {
      payload['creadoEn'] = FieldValue.serverTimestamp();
    }

    if (UserRoleAccess.isAdminRole(rolLimpio)) {
      payload['allowedSedeIds'] = const [
        SedeAccess.matrizId,
        SedeAccess.sedeNorteId,
        SedeAccess.sedeCentroId,
        SedeAccess.sedeCreSerId,
      ];
    } else if (UserRoleAccess.isRrhhRole(rolLimpio)) {
      payload['allowedSedeIds'] = [sedeId];
    } else {
      payload['allowedSedeIds'] = FieldValue.delete();
    }

    await ref.set(payload, SetOptions(merge: true));

    if (passwordLimpio.isNotEmpty) {
      await _eliminarPasswordLegacy(ref);
    }
  }

  Future<void> eliminarUsuarioPersonalSede({
    required String usuarioDocId,
  }) async {
    final ref = _db.collection('usuarios').doc(usuarioDocId.trim());
    final snapshot = await ref.get();

    if (!snapshot.exists) {
      return;
    }

    final data = snapshot.data() ?? {};
    final rol = (data['rol'] ?? '').toString().trim().toUpperCase();
    if (rol == 'RRHH') {
      throw Exception(
        'No se puede eliminar un usuario RRHH desde este apartado.',
      );
    }

    await ref.delete();
  }

  Future<void> registrarTokenNotificacion({
    required String correo,
    required String token,
    String? sedeId,
  }) async {
    final correoNormalizado = correo.trim().toLowerCase();
    final tokenNormalizado = token.trim();

    if (correoNormalizado.isEmpty || tokenNormalizado.isEmpty) {
      return;
    }

    final query = await _db
        .collection('usuarios')
        .where('correo', isEqualTo: correoNormalizado)
        .get();

    if (query.docs.isEmpty) {
      return;
    }

    QueryDocumentSnapshot<Map<String, dynamic>>? match;
    if (sedeId != null && sedeId.trim().isNotEmpty) {
      for (final doc in query.docs) {
        if (SedeAccess.matchesSede(doc.data(), sedeId.trim())) {
          match = doc;
          break;
        }
      }
    }

    match ??= query.docs.first;

    await match.reference.set({
      'fcmTokens': FieldValue.arrayUnion([tokenNormalizado]),
      'ultimoTokenFcm': tokenNormalizado,
      'tokenActualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<Solicitud>> obtenerMisSolicitdes(
    String nombre, {
    String? correo,
    String? sedeId,
  }) async {
    try {
      await sincronizarNumeracionSolicitudesPorColaborador(
        nombre: nombre,
        correo: correo,
        sedeId: sedeId,
      );

      final correoNormalizado = _normalizarCorreo(correo ?? '');
      QuerySnapshot snapshot;
      if (correoNormalizado.isNotEmpty) {
        snapshot = await _db
            .collection('solicitudes')
            .where('colaboradorCorreo', isEqualTo: correoNormalizado)
            .get();
        if (snapshot.docs.isEmpty) {
          snapshot = await _db
              .collection('solicitudes')
              .where('colaborador', isEqualTo: nombre)
              .get();
        }
      } else {
        snapshot = await _db
            .collection('solicitudes')
            .where('colaborador', isEqualTo: nombre)
            .get();
      }

      final sedeFiltro = SedeAccess.normalize(sedeId);
      final docs =
          snapshot.docs.where((doc) {
            if (sedeFiltro.isEmpty) {
              return true;
            }
            return SedeAccess.matchesSede(
              doc.data() as Map<String, dynamic>,
              sedeFiltro,
            );
          }).toList()..sort((a, b) {
            final fechaA = _resolverFechaOrdenSolicitud(
              a.data() as Map<String, dynamic>,
            );
            final fechaB = _resolverFechaOrdenSolicitud(
              b.data() as Map<String, dynamic>,
            );
            final comparacionFecha = fechaB.compareTo(fechaA);
            if (comparacionFecha != 0) {
              return comparacionFecha;
            }
            return b.id.compareTo(a.id);
          });

      return docs
          .map(
            (doc) =>
                Solicitud.fromMap(doc.id, doc.data() as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      debugPrint(
        'obtenerMisSolicitdes fallo '
        '(nombre=$nombre, correo=${_normalizarCorreo(correo ?? "")}, sedeId=${SedeAccess.normalize(sedeId)}): $e',
      );
      return [];
    }
  }

  // Obtener estado actual del almuerzo
  Future<String> obtenerEstadoAlmuerzoHoy(String correo) async {
    String fechaHoy = DateFormat('yyyy-MM-dd').format(DateTime.now());
    var query = await _db
        .collection('registros_almuerzo')
        .where('correo_usuario', isEqualTo: correo)
        .where('fecha', isEqualTo: fechaHoy)
        .get();

    if (query.docs.isEmpty) return "pendiente";

    for (var doc in query.docs) {
      if (doc['estado'] == "en_almuerzo") return "en_almuerzo";
    }

    return "finalizado";
  }
}

class PasswordRecoveryStartResult {
  const PasswordRecoveryStartResult({
    required this.codeSent,
    required this.requiresSupport,
    required this.message,
  });

  final bool codeSent;
  final bool requiresSupport;
  final String message;
}
