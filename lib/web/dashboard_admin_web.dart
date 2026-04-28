import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_config.dart';

class DashboardAdminWeb extends StatelessWidget {
  const DashboardAdminWeb({super.key});

  static const Color _primary = Color(0xFF467879);
  static const Color _secondary = Color(0xFF6FA1A0);
  static const Color _primaryDark = Color(0xFF274B4C);
  static const Color _accent = Color(0xFFD8E9E5);
  static const Color _soft = Color(0xFFF3F8F7);
  static const Color _card = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF243133);
  static const Color _muted = Color(0xFF6D8486);
  static const Color _success = Color(0xFF3FA36C);
  static const Color _danger = Color(0xFFD96557);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHero(),
          const SizedBox(height: 24),
          Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [
              _buildStatCard(
                title: 'Personal registrado',
                icon: Icons.groups_2_outlined,
                color: _primary,
                stream: FirebaseFirestore.instance.collection('usuarios').snapshots(),
                shouldCount: (data) =>
                    SedeAccess.matchesSede(data, SedeAccess.matrizId) &&
                    _isTrackedStaff(data),
              ),
              _buildAttendanceCard(
                title: 'Asistencias de hoy',
                icon: Icons.how_to_reg_outlined,
                color: _success,
                countBuilder: (asistencias, nombresPermitidos) {
                  final hoy = DateTime.now();
                  return asistencias.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return _belongsToTrackedUser(data, nombresPermitidos) &&
                        _isSameDay(data['fecha'], hoy);
                  }).length;
                },
              ),
              _buildAttendanceCard(
                title: 'Atrasos detectados',
                icon: Icons.timer_off_outlined,
                color: _danger,
                countBuilder: (asistencias, nombresPermitidos) {
                  return asistencias.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return _belongsToTrackedUser(data, nombresPermitidos) &&
                        _normalize(data['estado']) == 'atraso';
                  }).length;
                },
              ),
            ],
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
                  Expanded(
                    child: _buildRoleBreakdownPanel(),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: _buildRecentLatePanel(),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_primaryDark, _primary, _secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.18),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.start,
        runSpacing: 18,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Text(
                    'Matriz activa',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Panel de control INTESUD',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Interfaz institucional personalizada para RRHH. Recursos Humanos esta gestionando la sede principal desde el mismo acceso central.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required IconData icon,
    required Color color,
    required Stream<QuerySnapshot> stream,
    bool Function(Map<String, dynamic> data)? shouldCount,
  }) {
    return SizedBox(
      width: 320,
      child: StreamBuilder<QuerySnapshot>(
        stream: stream,
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? const [];
          final count = shouldCount == null
              ? docs.length
              : docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return shouldCount(data);
                }).length;

          return Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: color.withOpacity(0.12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
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
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        snapshot.connectionState == ConnectionState.waiting
                            ? '...'
                            : '$count',
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
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
    required String title,
    required IconData icon,
    required Color color,
    required int Function(
      List<QueryDocumentSnapshot> asistencias,
      Set<String> nombresPermitidos,
    ) countBuilder,
  }) {
    return SizedBox(
      width: 320,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('usuarios').snapshots(),
        builder: (context, usuariosSnapshot) {
          final nombresPermitidos =
              _buildAllowedNames(usuariosSnapshot.data?.docs ?? const []);

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('asistencias_realizadas')
                .snapshots(),
            builder: (context, asistenciasSnapshot) {
              final asistencias = asistenciasSnapshot.data?.docs ?? const [];
              final count = countBuilder(asistencias, nombresPermitidos);
              final cargando = usuariosSnapshot.connectionState ==
                      ConnectionState.waiting ||
                  asistenciasSnapshot.connectionState == ConnectionState.waiting;

              return Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: color.withOpacity(0.12)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
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
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            cargando ? '...' : '$count',
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
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
          return SedeAccess.matchesSede(data, SedeAccess.matrizId) &&
              _matchesRole(data, 'Docente');
        }).length;
        final administrativos = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return SedeAccess.matchesSede(data, SedeAccess.matrizId) &&
              _matchesRole(data, 'Administrativo');
        }).length;
        final total = docentes + administrativos;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _accent.withOpacity(0.78)),
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
      },
    );
  }

  Widget _buildRecentLatePanel() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('usuarios').snapshots(),
      builder: (context, usuariosSnapshot) {
        final nombresPermitidos =
            _buildAllowedNames(usuariosSnapshot.data?.docs ?? const []);

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('asistencias_realizadas')
              .snapshots(),
          builder: (context, asistenciasSnapshot) {
            final docs = asistenciasSnapshot.data?.docs ?? const [];
            final atrasos = docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return _belongsToTrackedUser(data, nombresPermitidos) &&
                  _normalize(data['estado']) == 'atraso';
            }).toList()
              ..sort((a, b) {
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
                border: Border.all(color: _accent.withOpacity(0.45)),
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
                          border: Border.all(color: _accent.withOpacity(0.25)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: _danger.withOpacity(0.12),
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
      width: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: _ink,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: _muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Set<String> _buildAllowedNames(List<QueryDocumentSnapshot> docs) {
    return docs
        .map((doc) => doc.data() as Map<String, dynamic>)
        .where((data) =>
            SedeAccess.matchesSede(data, SedeAccess.matrizId) &&
            _isTrackedStaff(data))
        .map((data) => (data['nombre'] ?? '').toString().trim())
        .where((nombre) => nombre.isNotEmpty)
        .toSet();
  }

  bool _belongsToTrackedUser(
    Map<String, dynamic> data,
    Set<String> nombresPermitidos,
  ) {
    final nombreMarcacion = (data['docente'] ?? '').toString().trim();
    return nombresPermitidos.contains(nombreMarcacion);
  }

  bool _isTrackedStaff(Map<String, dynamic> data) {
    return _matchesRole(data, 'Docente') || _matchesRole(data, 'Administrativo');
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
