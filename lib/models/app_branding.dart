import 'package:flutter/material.dart';

class AppBranding {
  const AppBranding({
    required this.sedeId,
    required this.primary,
    required this.primaryDark,
    required this.background,
    required this.surface,
    required this.softAccent,
    required this.logoSmall,
    required this.logoHeader,
    required this.logoWatermark,
    required this.logoPdf,
    required this.displayName,
    required this.sedeName,
    required this.subtitle,
  });

  final String sedeId;
  final Color primary;
  final Color primaryDark;
  final Color background;
  final Color surface;
  final Color softAccent;
  final String logoSmall;
  final String logoHeader;
  final String logoWatermark;
  final String logoPdf;
  final String displayName;
  final String sedeName;
  final String subtitle;

  bool get isMatriz => sedeId == 'matriz';
  bool get isSedeCentro => sedeId == sedeCentro.sedeId;
  bool get isPrincesaDeGales =>
      sedeId == sedeNorte.sedeId || sedeId == sedeCentro.sedeId;
  bool get isCustomSede => !isMatriz;
  double get mobileHeaderLogoHeight => isSedeCentro ? 62 : 55;
  double get mobilePatternLogoSize => isSedeCentro ? 60 : 55;
  double get mobileWatermarkWidthFactor => isSedeCentro ? 1.02 : 0.95;
  double get mobileFormWatermarkWidthFactor => isSedeCentro ? 0.96 : 0.85;

  static const AppBranding matriz = AppBranding(
    sedeId: 'matriz',
    primary: Color(0xFF467879),
    primaryDark: Color(0xFF2A4D4E),
    background: Color(0xFF8CBAB3),
    surface: Color(0xFFF0F4F4),
    softAccent: Color(0xFFD1D9D9),
    logoSmall: 'assets/images/logo_intesud1.png',
    logoHeader: 'assets/images/logo_intesud.png',
    logoWatermark: 'assets/images/logo_intesud2.png',
    logoPdf: 'assets/images/logo_intesud3.png',
    displayName: 'INTESUD',
    sedeName: 'Matriz',
    subtitle: 'Instituto Superior Tecnologico Sudamericano',
  );

  static const AppBranding sedeNorte = AppBranding(
    sedeId: 'princesa_gales_norte',
    primary: Color(0xFF8B3D66),
    primaryDark: Color(0xFF612543),
    background: Color(0xFFD8B5C6),
    surface: Color(0xFFF9EFF3),
    softAccent: Color(0xFFF1DCE5),
    logoSmall: 'assets/images/logo_galesnorte.png',
    logoHeader: 'assets/images/logo_galesnorte.png',
    logoWatermark: 'assets/images/logo_galesnorte.png',
    logoPdf: 'assets/images/logo_galesnorte.png',
    displayName: 'Princesa de Gales Norte',
    sedeName: 'Princesa de Gales Norte',
    subtitle: 'Estetica Integral',
  );

  static const AppBranding sedeCentro = AppBranding(
    sedeId: 'princesa_gales_centro',
    primary: Color(0xFF9C4F73),
    primaryDark: Color(0xFF6F2E50),
    background: Color(0xFFE6C5D4),
    surface: Color(0xFFFCF3F7),
    softAccent: Color(0xFFF4E4EB),
    logoSmall: 'assets/images/logo_galescentro.png',
    logoHeader: 'assets/images/logo_galescentro.png',
    logoWatermark: 'assets/images/logo_galescentro.png',
    logoPdf: 'assets/images/logo_galescentro.png',
    displayName: 'Princesa de Gales Centro',
    sedeName: 'Princesa de Gales Centro',
    subtitle: 'Tricologia - Cosmetria',
  );

  static const AppBranding sedeCreSer = AppBranding(
    sedeId: 'instituto_cre_ser',
    primary: Color(0xFF2167AE),
    primaryDark: Color(0xFF123B6D),
    background: Color(0xFFDCEBFA),
    surface: Color(0xFFF5FAFF),
    softAccent: Color(0xFFE6F0FB),
    logoSmall: 'assets/images/logo_cre_ser.png',
    logoHeader: 'assets/images/logo_cre_ser.png',
    logoWatermark: 'assets/images/logo_cre_ser.png',
    logoPdf: 'assets/images/logo_cre_ser.png',
    displayName: 'Instituto Superior Tecnologico Cre Ser',
    sedeName: 'Instituto Superior Tecnologico Cre Ser',
    subtitle: 'Formacion Integral',
  );

  static AppBranding fromSede(bool isSedeNorte) {
    return isSedeNorte ? sedeNorte : matriz;
  }

  static AppBranding fromSedeId(String? sedeId) {
    switch ((sedeId ?? '').trim().toLowerCase()) {
      case 'princesa_gales_norte':
        return sedeNorte;
      case 'princesa_gales_centro':
        return sedeCentro;
      case 'instituto_cre_ser':
        return sedeCreSer;
      default:
        return matriz;
    }
  }

  static AppBranding fromLegacy({
    required bool isSedeNorte,
    String? sedeId,
  }) {
    return fromSedeId(
      sedeId ?? (isSedeNorte ? sedeNorte.sedeId : matriz.sedeId),
    );
  }
}
