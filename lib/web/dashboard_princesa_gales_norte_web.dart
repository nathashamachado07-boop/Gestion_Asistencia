import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_config.dart';
import '../models/app_branding.dart';
import 'bootstrap_admin_ui.dart';

class DashboardPrincesaGalesNorteWeb extends StatelessWidget {
  const DashboardPrincesaGalesNorteWeb({
    super.key,
    required this.sedeId,
    required this.branding,
    this.nombreUsuario = 'Recursos Humanos',
    this.showBrandLogo = false,
  });

  final String sedeId;
  final AppBranding branding;
  final String nombreUsuario;
  final bool showBrandLogo;

  Color get _primary => branding.primary;
  Color get _secondary => branding.primary.withValues(alpha: 0.82);
  Color get _accent => branding.softAccent;
  Color get _soft => branding.surface;
  Color get _card => Colors.white.withValues(alpha: 0.95);
  static const Color _ink = Color(0xFF3D1D2E);
  static const Color _muted = Color(0xFF8A6676);
  static const Color _success = Color(0xFF3FA36C);
  static const Color _danger = Color(0xFFD96557);
  String get _sedeNombre => SedeAccess.displayNameForId(sedeId);
  bool get _isCentro => sedeId == SedeAccess.sedeCentroId;
  bool get _isCreSer => sedeId == SedeAccess.sedeCreSerId;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BootstrapAdminHero(
            branding: branding,
            icon: Icons.apartment_rounded,
            eyebrow: 'Sede activa',
            title: _sedeNombre,
            subtitle:
                'Interfaz institucional para RRHH. $nombreUsuario esta gestionando esta sede desde un acceso principal mas claro y consistente.',
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final statCardWidth = constraints.maxWidth < 720
                  ? constraints.maxWidth
                  : 320.0;

              return Wrap(
                spacing: 18,
                runSpacing: 18,
                children: [
                  _buildStatCard(
                    width: statCardWidth,
                    title: 'Personal registrado',
                    icon: Icons.groups_2_outlined,
                    color: _primary,
                    stream: FirebaseFirestore.instance
                        .collection('usuarios')
                        .snapshots(),
                    shouldCount: (data) =>
                        SedeAccess.matchesSede(data, sedeId) &&
                        _isTrackedStaff(data),
                  ),
                  _buildAttendanceCard(
                    width: statCardWidth,
                    title: 'Asistencias de hoy',
                    icon: Icons.how_to_reg_outlined,
                    color: _success,
                    countBuilder: (asistencias, nombresPermitidos) {
                      final hoy = DateTime.now();
                      return _countUniqueTrackedPeople(
                        asistencias,
                        nombresPermitidos,
                        predicate: (data) => _isSameDay(data['fecha'], hoy),
                      );
                    },
                  ),
                  _buildAttendanceCard(
                    width: statCardWidth,
                    title: 'Atrasos detectados',
                    icon: Icons.timer_off_outlined,
                    color: _danger,
                    countBuilder: (asistencias, nombresPermitidos) {
                      final hoy = DateTime.now();
                      return _countUniqueTrackedPeople(
                        asistencias,
                        nombresPermitidos,
                        predicate: (data) =>
                            _isSameDay(data['fecha'], hoy) &&
                            _normalize(data['estado']) == 'atraso',
                      );
                    },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final compacto = constraints.maxWidth < 1100;
              if (compacto) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRoleBreakdownPanel(),
                    const SizedBox(height: 18),
                    _buildRecentLatePanel(),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildRoleBreakdownPanel()),
                  const SizedBox(width: 18),
                  Expanded(child: _buildRecentLatePanel()),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildBrandPanel() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 150),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [branding.primaryDark, branding.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: showBrandLogo
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: EdgeInsets.all(
                        _isCentro ? 2 : (_isCreSer ? 6 : 10),
                      ),
                      child: Image.asset(
                        branding.logoHeader,
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        scale: _isCentro ? 0.5 : (_isCreSer ? 0.66 : 0.78),
                        errorBuilder: (context, error, stackTrace) =>
                            _buildLogoFallback(),
                      ),
                    ),
                  )
                : _buildLogoFallback(),
          ),
          const SizedBox(height: 12),
          const Text(
            'Dashboard por sede',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Colores, logo e identidad de ${branding.displayName} aplicados solo a ${_sedeNombre.toLowerCase()}.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoFallback() {
    return Container(
      padding: const EdgeInsets.all(14),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 12,
            right: 18,
            child: Icon(Icons.auto_awesome, size: 16, color: Colors.white70),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                branding.isPrincesaDeGales
                    ? Icons.spa_outlined
                    : Icons.school_outlined,
                size: 50,
                color: Colors.white,
              ),
              const SizedBox(height: 8),
              Text(
                branding.displayName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                branding.subtitle.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'Comprometidos con la Excelencia',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 7,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required double width,
    required String title,
    required IconData icon,
    required Color color,
    required Stream<QuerySnapshot> stream,
    bool Function(Map<String, dynamic> data)? shouldCount,
  }) {
    return SizedBox(
      width: width,
      child: StreamBuilder<QuerySnapshot>(
        stream: stream,
        builder: (context, snapshot) {
          final isLoading =
              snapshot.connectionState == ConnectionState.waiting;
          final docs = snapshot.data?.docs ?? const [];
          final count = shouldCount == null
              ? docs.length
              : docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return shouldCount(data);
                }).length;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: color.withValues(alpha: 0.14)),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: color.withValues(alpha: 0.18)),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      isLoading
                          ? Container(
                              width: 60,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            )
                          : Text(
                              '$count',
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                height: 1.0,
                              ),
                            ),
                    ],
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isLoading
                        ? Colors.grey.shade300
                        : color.withValues(alpha: 0.60),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAttendanceCard({
    required double width,
    required String title,
    required IconData icon,
    required Color color,
    required int Function(
      List<QueryDocumentSnapshot> asistencias,
      Set<String> nombresPermitidos,
    )
    countBuilder,
  }) {
    return SizedBox(
      width: width,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('usuarios').snapshots(),
        builder: (context, usuariosSnapshot) {
          final nombresPermitidos = _buildAllowedNames(
            usuariosSnapshot.data?.docs ?? const [],
          );

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('asistencias_realizadas')
                .snapshots(),
            builder: (context, asistenciasSnapshot) {
              final asistencias = asistenciasSnapshot.data?.docs ?? const [];
              final count = countBuilder(asistencias, nombresPermitidos);
              final cargando =
                  usuariosSnapshot.connectionState == ConnectionState.waiting ||
                  asistenciasSnapshot.connectionState ==
                      ConnectionState.waiting;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: color.withValues(alpha: 0.14)),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: color.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Icon(icon, color: color),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          cargando
                              ? Container(
                                  width: 60,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                )
                              : Text(
                                  '$count',
                                  style: const TextStyle(
                                    color: _ink,
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                    height: 1.0,
                                  ),
                                ),
                        ],
                      ),
                    ),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cargando
                            ? Colors.grey.shade300
                            : color.withValues(alpha: 0.60),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildRoleBreakdownPanel() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('usuarios').snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        final docentes = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return SedeAccess.matchesSede(data, sedeId) &&
              _matchesRole(data, 'Docente');
        }).length;
        final administrativos = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return SedeAccess.matchesSede(data, sedeId) &&
              _matchesRole(data, 'Administrativo');
        }).length;
        final total = docentes + administrativos;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFF0D8E2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Personal de la sede',
                style: TextStyle(
                  color: _ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Resumen rapido del personal registrado en $_sedeNombre.',
                style: TextStyle(
                  color: _muted,
                  fontSize: 14,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _buildMiniMetric(
                    'Docentes',
                    '$docentes',
                    Icons.school_outlined,
                    _primary,
                  ),
                  _buildMiniMetric(
                    'Personal administrativo',
                    '$administrativos',
                    Icons.badge_outlined,
                    _secondary,
                  ),
                  _buildMiniMetric(
                    'Total',
                    '$total',
                    Icons.groups_2_outlined,
                    _accent,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecentLatePanel() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('usuarios').snapshots(),
      builder: (context, usuariosSnapshot) {
        final nombresPermitidos = _buildAllowedNames(
          usuariosSnapshot.data?.docs ?? const [],
        );

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('asistencias_realizadas')
              .snapshots(),
          builder: (context, asistenciasSnapshot) {
            final docs = asistenciasSnapshot.data?.docs ?? const [];
            final atrasos =
                docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return _belongsToTrackedUser(data, nombresPermitidos) &&
                      _normalize(data['estado']) == 'atraso';
                }).toList()..sort((a, b) {
                  final fechaA =
                      ((a.data() as Map<String, dynamic>)['fecha']
                              as Timestamp?)
                          ?.toDate();
                  final fechaB =
                      ((b.data() as Map<String, dynamic>)['fecha']
                              as Timestamp?)
                          ?.toDate();
                  return (fechaB ?? DateTime(2000)).compareTo(
                    fechaA ?? DateTime(2000),
                  );
                });

            final recientes = atrasos.take(5).toList();

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _accent.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Alertas de atrasos',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ultimos ${recientes.length} registros con atraso detectados en ${_sedeNombre.toLowerCase()}.',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 13,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (recientes.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _soft,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Text(
                        'No hay atrasos registrados para esta sede por el momento.',
                        style: TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    ...recientes.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final fecha = (data['fecha'] as Timestamp?)?.toDate();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _soft,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: _accent.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: _danger.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.timer_off_outlined,
                                color: _danger,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (data['docente'] ?? 'Sin nombre')
                                        .toString(),
                                    style: const TextStyle(
                                      color: _ink,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    fecha == null
                                        ? 'Fecha no disponible'
                                        : DateFormat(
                                            "d 'de' MMMM 'de' yyyy",
                                            'es_ES',
                                          ).format(fecha),
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              (data['hora_marcada'] ?? '--:--').toString(),
                              style: const TextStyle(
                                color: _danger,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMiniMetric(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              color: _ink,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: const TextStyle(
              color: _muted,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Set<String> _buildAllowedNames(List<QueryDocumentSnapshot> docs) {
    return docs
        .map((doc) => doc.data() as Map<String, dynamic>)
        .where(
          (data) =>
              SedeAccess.matchesSede(data, sedeId) && _isTrackedStaff(data),
        )
        .map((data) => _normalizeAttendanceName(data['nombre']))
        .where((nombre) => nombre.isNotEmpty)
        .toSet();
  }

  int _countUniqueTrackedPeople(
    List<QueryDocumentSnapshot> asistencias,
    Set<String> nombresPermitidos, {
    required bool Function(Map<String, dynamic> data) predicate,
  }) {
    final personas = <String>{};

    for (final doc in asistencias) {
      final data = doc.data() as Map<String, dynamic>;
      if (!_belongsToTrackedUser(data, nombresPermitidos)) {
        continue;
      }
      if (!predicate(data)) {
        continue;
      }

      final nombre = _normalizeAttendanceName(data['docente']);
      if (nombre.isEmpty) {
        continue;
      }
      personas.add(nombre);
    }

    return personas.length;
  }

  bool _belongsToTrackedUser(
    Map<String, dynamic> data,
    Set<String> nombresPermitidos,
  ) {
    final nombreMarcacion = _normalizeAttendanceName(data['docente']);
    if (nombreMarcacion.isEmpty) {
      return false;
    }

    final sedeRegistro = SedeAccess.normalize(data['sedeId']);
    if (sedeRegistro.isNotEmpty) {
      return sedeRegistro == sedeId &&
          nombresPermitidos.contains(nombreMarcacion);
    }

    return nombresPermitidos.contains(nombreMarcacion);
  }

  String _normalizeAttendanceName(dynamic value) {
    return value?.toString().trim().toLowerCase() ?? '';
  }

  bool _isTrackedStaff(Map<String, dynamic> data) {
    return _matchesRole(data, 'Docente') ||
        _matchesRole(data, 'Administrativo');
  }

  bool _isSameDay(dynamic value, DateTime target) {
    if (value is! Timestamp) return false;
    final fecha = value.toDate();
    return fecha.day == target.day &&
        fecha.month == target.month &&
        fecha.year == target.year;
  }

  String _normalize(dynamic value) {
    return value?.toString().trim().toLowerCase() ?? '';
  }

  bool _matchesRole(Map<String, dynamic> data, String role) {
    if (UserRoleAccess.isAdministrativeRole(role)) {
      return UserRoleAccess.isAdministrativeRole(data['rol']);
    }
    if (UserRoleAccess.isTeacherRole(role)) {
      return UserRoleAccess.isTeacherRole(data['rol']);
    }
    return (data['rol'] ?? '').toString().trim().toLowerCase() ==
        role.toLowerCase();
  }
}
