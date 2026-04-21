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
