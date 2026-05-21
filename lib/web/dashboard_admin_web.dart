import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_config.dart';
import '../models/app_branding.dart';
import 'bootstrap_admin_ui.dart';

class DashboardAdminWeb extends StatelessWidget {
  const DashboardAdminWeb({super.key});

  static const Color _primary = Color(0xFF467879);
  static const Color _secondary = Color(0xFF6FA1A0);
  static const Color _accent = Color(0xFFD8E9E5);
  static const Color _soft = Color(0xFFF3F8F7);
  static const Color _card = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF243133);
  static const Color _muted = Color(0xFF6D8486);
  static const Color _success = Color(0xFF3FA36C);
  static const Color _danger = Color(0xFFD96557);

  Stream<QuerySnapshot> _buildUsuariosStream() {
    return FirebaseFirestore.instance
        .collection('usuarios')
        .where('sedeId', isEqualTo: SedeAccess.matrizId)
        .where(
          'rol',
          whereIn: const [
            'Docente',
            'Personal administrativo',
            'Administrativo',
          ],
        )
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _buildUsuariosStream(),
      builder: (context, usuariosSnapshot) {
        final usuarios = usuariosSnapshot.data?.docs ?? const [];
        final nombresPermitidos = _buildAllowedNames(usuarios);

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('asistencias_realizadas')
              .snapshots(),
          builder: (context, asistenciasSnapshot) {
            final asistencias = asistenciasSnapshot.data?.docs ?? const [];
            final isLoading =
                usuariosSnapshot.connectionState == ConnectionState.waiting ||
                asistenciasSnapshot.connectionState == ConnectionState.waiting;

            final hoy = DateTime.now();
            final totalPersonal = usuarios.length;
            final asistenciasHoy = _countUniqueTrackedPeople(
              asistencias,
              nombresPermitidos,
              predicate: (data) => _isSameDay(data['fecha'], hoy),
            );
            final atrasosHoy = _countUniqueTrackedPeople(
              asistencias,
              nombresPermitidos,
              predicate: (data) =>
                  _isSameDay(data['fecha'], hoy) &&
                  _normalize(data['estado']) == 'atraso',
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHero(),
                  const SizedBox(height: 28),
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
                            value: '$totalPersonal',
                            isLoading: usuariosSnapshot.connectionState ==
                                ConnectionState.waiting,
                          ),
                          _buildStatCard(
                            width: statCardWidth,
                            title: 'Asistencias de hoy',
                            icon: Icons.how_to_reg_outlined,
                            color: _success,
                            value: '$asistenciasHoy',
                            isLoading: isLoading,
                          ),
                          _buildStatCard(
                            width: statCardWidth,
                            title: 'Atrasos detectados',
                            icon: Icons.timer_off_outlined,
                            color: _danger,
                            value: '$atrasosHoy',
                            isLoading: isLoading,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  BootstrapAdminSectionHeading(
                    icon: Icons.groups_2_outlined,
                    title: 'Resumen del personal',
                    subtitle:
                        'Vista ejecutiva del personal, la asistencia y las alertas del dia.',
                    accentColor: _primary,
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compacto = constraints.maxWidth < 1100;
                      if (compacto) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildRoleBreakdownPanel(usuarios),
                            const SizedBox(height: 18),
                            _buildRecentLatePanel(asistencias, nombresPermitidos),
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildRoleBreakdownPanel(usuarios)),
                          const SizedBox(width: 18),
                          Expanded(
                            child: _buildRecentLatePanel(
                              asistencias,
                              nombresPermitidos,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHero() {
    return BootstrapAdminHero(
      branding: AppBranding.fromSedeId(SedeAccess.matrizId),
      icon: Icons.dashboard_customize_rounded,
      eyebrow: 'Matriz activa',
      title: 'Panel de control INTESUD',
      subtitle:
          'Interfaz institucional para RRHH. Recursos Humanos esta gestionando la sede principal desde un acceso mas claro, rapido y consistente.',
    );
  }

  Widget _buildStatCard({
    required double width,
    required String title,
    required IconData icon,
    required Color color,
    required String value,
    required bool isLoading,
  }) {
    return SizedBox(
      width: width,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: 0.26)),
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
                  color: color.withValues(alpha: 0.30),
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
                  isLoading
                      ? Container(
                          width: 60,
                          height: 28,
                          decoration: BoxDecoration(
                            color: _soft,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        )
                      : Text(
                          value,
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
      ),
    );
  }

  Widget _buildRoleBreakdownPanel(List<QueryDocumentSnapshot> docs) {
    final docentes = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return _matchesRole(data, 'Docente');
    }).length;
    final administrativos = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return _matchesRole(data, 'Administrativo');
    }).length;
    final total = docentes + administrativos;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _accent.withValues(alpha: 0.78)),
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
          const Text(
            'Resumen rapido del personal registrado en Matriz.',
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
                const Color(0xFF7DA49C),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentLatePanel(
    List<QueryDocumentSnapshot> docs,
    Set<String> nombresPermitidos,
  ) {
    final atrasos =
        docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return _belongsToTrackedUser(data, nombresPermitidos) &&
              _normalize(data['estado']) == 'atraso';
        }).toList()..sort((a, b) {
          final fechaA =
              ((a.data() as Map<String, dynamic>)['fecha'] as Timestamp?)
                  ?.toDate();
          final fechaB =
              ((b.data() as Map<String, dynamic>)['fecha'] as Timestamp?)
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
        border: Border.all(color: _accent.withValues(alpha: 0.58)),
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
            'Ultimos ${recientes.length} registros con atraso detectados en matriz.',
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
                'No hay atrasos registrados para matriz por el momento.',
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
                    color: _accent.withValues(alpha: 0.38),
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
                            (data['docente'] ?? 'Sin nombre').toString(),
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
        border: Border.all(color: color.withValues(alpha: 0.30)),
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
            style: TextStyle(
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
              SedeAccess.matchesSede(data, SedeAccess.matrizId) &&
              _isTrackedStaff(data),
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
      return sedeRegistro == SedeAccess.matrizId &&
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
