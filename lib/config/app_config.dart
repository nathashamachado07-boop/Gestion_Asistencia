class AppConfig {
  const AppConfig({
    required this.appName,
    required this.defaultSedeId,
  });

  final String appName;
  final String defaultSedeId;

  bool get isSedeNorteApp => defaultSedeId == SedeAccess.sedeNorteId;
  bool get isSedeCentroApp => defaultSedeId == SedeAccess.sedeCentroId;
  bool get isSedeCreSerApp => defaultSedeId == SedeAccess.sedeCreSerId;

  static const AppConfig matriz = AppConfig(
    appName: 'Sistema Asistencia ISTS',
    defaultSedeId: SedeAccess.matrizId,
  );

  static const AppConfig sedeNorte = AppConfig(
    appName: 'Sistema Asistencia Sede Norte',
    defaultSedeId: SedeAccess.sedeNorteId,
  );

  static const AppConfig sedeCentro = AppConfig(
    appName: 'Sistema Asistencia Sede Centro',
    defaultSedeId: SedeAccess.sedeCentroId,
  );

  static const AppConfig sedeCreSer = AppConfig(
    appName: 'Sistema Asistencia Cre Ser',
    defaultSedeId: SedeAccess.sedeCreSerId,
  );

  String get loginRestrictionMessage {
    switch (defaultSedeId) {
      case SedeAccess.sedeNorteId:
        return 'Esta aplicacion corresponde solo a Princesa de Gales Norte.';
      case SedeAccess.sedeCentroId:
        return 'Esta aplicacion corresponde solo a Princesa de Gales Centro.';
      case SedeAccess.sedeCreSerId:
        return 'Esta aplicacion corresponde solo a Instituto Cre Ser.';
      default:
        return 'Esta aplicacion corresponde solo a la sede matriz.';
    }
  }

  static AppConfig fromPackageName(
    String packageName, {
    AppConfig fallback = AppConfig.matriz,
  }) {
    final normalized = packageName.trim().toLowerCase();

    if (normalized.endsWith('.norte')) {
      return AppConfig.sedeNorte;
    }

    if (normalized.endsWith('.centro')) {
      return AppConfig.sedeCentro;
    }

    if (normalized.endsWith('.creser') ||
        normalized.endsWith('.cre_ser')) {
      return AppConfig.sedeCreSer;
    }

    if (normalized.endsWith('.matriz')) {
      return AppConfig.matriz;
    }

    return fallback;
  }
}

class SedeAccess {
  static const String matrizId = 'matriz';
  static const String sedeNorteId = 'princesa_gales_norte';
  static const String sedeCentroId = 'princesa_gales_centro';
  static const String sedeCreSerId = 'instituto_cre_ser';

  static String normalize(dynamic value) {
    return value?.toString().trim().toLowerCase() ?? '';
  }

  static String resolveSedeId(Map<String, dynamic> data) {
    final sedeId = normalize(data['sedeId']);
    if (sedeId == sedeNorteId ||
        sedeId == sedeCentroId ||
        sedeId == sedeCreSerId) {
      return sedeId;
    }

    final sedeNombre = normalize(
      data['sede'] ??
          data['cede'] ??
          data['campus'] ??
          data['sucursal'] ??
          data['institucion_sede'],
    );

    if (sedeNombre.contains('princesa de gales norte')) {
      return sedeNorteId;
    }

    if (sedeNombre.contains('princesa de gales centro')) {
      return sedeCentroId;
    }

    if (sedeNombre.contains('instituto cre ser') ||
        sedeNombre.contains('cre ser')) {
      return sedeCreSerId;
    }

    return matrizId;
  }

  static bool isSedeNorte(Map<String, dynamic> data) {
    return resolveSedeId(data) == sedeNorteId;
  }

  static bool isSedeCentro(Map<String, dynamic> data) {
    return resolveSedeId(data) == sedeCentroId;
  }

  static bool isSedeEspecial(Map<String, dynamic> data) {
    return resolveSedeId(data) != matrizId;
  }

  static bool matchesSede(Map<String, dynamic> data, String sedeId) {
    return resolveSedeId(data) == sedeId;
  }

  static String displayNameForId(String sedeId) {
    switch (sedeId) {
      case sedeNorteId:
        return 'Princesa de Gales Norte';
      case sedeCentroId:
        return 'Princesa de Gales Centro';
      case sedeCreSerId:
        return 'Instituto Cre Ser';
      default:
        return 'Matriz';
    }
  }

  static bool matchesApp(Map<String, dynamic> data, AppConfig config) {
    return matchesSede(data, config.defaultSedeId);
  }
}

class UserRoleAccess {
  static const String roleTeacher = 'Docente';
  static const String roleAdministrative = 'Personal administrativo';
  static const String legacyAdministrative = 'Administrativo';
  static const String roleRrhh = 'RRHH';
  static const String roleAdmin = 'Admin';

  static String normalizeRole(dynamic value) {
    return value?.toString().trim().toLowerCase() ?? '';
  }

  static bool isTeacherRole(dynamic value) {
    return normalizeRole(value) == 'docente';
  }

  static bool isAdministrativeRole(dynamic value) {
    final normalized = normalizeRole(value);
    return normalized == 'personal administrativo' ||
        normalized == 'administrativo';
  }

  static bool isRrhhRole(dynamic value) {
    return normalizeRole(value) == 'rrhh';
  }

  static bool isAdminRole(dynamic value) {
    return normalizeRole(value) == 'admin';
  }

  static bool canUseAdminPanel(Map<String, dynamic>? userData) {
    if (userData == null) {
      return false;
    }
    final effectiveRole = displayRoleForUser(userData);
    return effectiveRole == roleAdmin || effectiveRole == roleRrhh;
  }

  static bool canUseEmployeePortal(dynamic value) {
    return isTeacherRole(value) || isAdministrativeRole(value);
  }

  static String displayRole(dynamic value) {
    if (isAdminRole(value)) {
      return roleAdmin;
    }
    if (isRrhhRole(value)) {
      return roleRrhh;
    }
    if (isAdministrativeRole(value)) {
      return roleAdministrative;
    }
    return roleTeacher;
  }

  static String displayRoleForUser(Map<String, dynamic>? userData) {
    final correo = MatrizApprovalFlow.normalizeEmail(userData?['correo']);
    if (MatrizApprovalFlow.isPrimaryReviewer(correo)) {
      return roleAdmin;
    }
    return displayRole(userData?['rol']);
  }

  static String displayNameForUser(Map<String, dynamic>? userData) {
    final rawName = userData?['nombre']?.toString().trim() ?? '';
    final normalizedName = rawName.toLowerCase();
    final effectiveRole = displayRoleForUser(userData);

    if (effectiveRole == roleAdmin &&
        (rawName.isEmpty || normalizedName == 'recursos humanos')) {
      return 'Admin general';
    }

    if (effectiveRole == roleRrhh &&
        (rawName.isEmpty || normalizedName == 'recursos humanos')) {
      return 'RRHH';
    }

    if (rawName.isNotEmpty) {
      return rawName;
    }

    return effectiveRole;
  }
}

class MatrizApprovalFlow {
  static const String primaryReviewerEmail = 'nathashamachado07@gmail.com';
  static const Set<String> finalReviewerEmails = {
    'oscar@sudamericano.edu.ec',
    'yadira@sudamericano.edu.ec',
  };

  static const String flowId = 'matriz_rrhh_doble';
  static const String stagePrimary = 'revision_rrhh_matriz';
  static const String stageFinal = 'autorizacion_final_matriz';
  static const String stageCompleted = 'finalizado';

  static String normalizeEmail(dynamic value) {
    return value?.toString().trim().toLowerCase() ?? '';
  }

  static bool appliesToSedeId(String? sedeId) {
    return SedeAccess.normalize(sedeId) == SedeAccess.matrizId;
  }

  static bool appliesToRequest(Map<String, dynamic> data) {
    return SedeAccess.resolveSedeId(data) == SedeAccess.matrizId;
  }

  static bool isPrimaryReviewer(dynamic email) {
    return normalizeEmail(email) == primaryReviewerEmail;
  }

  static bool isFinalReviewer(dynamic email) {
    return finalReviewerEmails.contains(normalizeEmail(email));
  }

  static bool isRestrictedToMatriz(dynamic email) {
    return isFinalReviewer(email);
  }

  static List<String> allowedSedeIdsForUser(Map<String, dynamic>? userData) {
    final email = normalizeEmail(userData?['correo']);
    final role = UserRoleAccess.normalizeRole(userData?['rol']);
    if (UserRoleAccess.isAdminRole(role) || isPrimaryReviewer(email)) {
      return const [
        SedeAccess.matrizId,
        SedeAccess.sedeNorteId,
        SedeAccess.sedeCentroId,
        SedeAccess.sedeCreSerId,
      ];
    }
    if (isFinalReviewer(email)) {
      return const [SedeAccess.matrizId];
    }

    final raw = userData?['allowedSedeIds'];
    if (raw is List) {
      final ids = raw
          .map(SedeAccess.normalize)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (ids.isNotEmpty) {
        return ids;
      }
    }

    final sedeId = userData == null
        ? SedeAccess.matrizId
        : SedeAccess.resolveSedeId(userData);
    return [sedeId];
  }
}
