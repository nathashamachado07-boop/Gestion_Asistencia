import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../config/app_config.dart';
import '../models/app_branding.dart';
import 'bootstrap_admin_ui.dart';

class EstadisticasAdminWeb extends StatelessWidget {
  const EstadisticasAdminWeb({
    super.key,
    this.isSedeNorte = false,
    this.sedeId,
  });

  final bool isSedeNorte;
  final String? sedeId;

  String _normalize(dynamic value) {
    return value?.toString().trim().toLowerCase() ?? '';
  }

  String get _resolvedSedeId =>
      sedeId ?? (isSedeNorte ? SedeAccess.sedeNorteId : SedeAccess.matrizId);
  AppBranding get _branding => AppBranding.fromSedeId(_resolvedSedeId);

  bool _matchesCurrentSede(Map<String, dynamic> data) {
    return SedeAccess.matchesSede(data, _resolvedSedeId);
  }

  bool _matchesRole(Map<String, dynamic> data, String role) {
    if (UserRoleAccess.isAdministrativeRole(role)) {
      return UserRoleAccess.isAdministrativeRole(data['rol']);
    }
    if (UserRoleAccess.isTeacherRole(role)) {
      return UserRoleAccess.isTeacherRole(data['rol']);
    }
    return _normalize(data['rol']) == role.toLowerCase();
  }

  String get _sedeLabel => _resolvedSedeId == SedeAccess.matrizId
      ? 'Sede Matriz'
      : SedeAccess.displayNameForId(_resolvedSedeId);
  Color get _bannerColor => _branding.primary;
  Color get _bannerSoftColor => _branding.surface;
  Color get _panelBorderColor => _branding.primary.withValues(alpha: 0.24);
  Color get _panelShadowColor => _branding.primary.withValues(alpha: 0.10);

  Set<String> _allowedNames(List<QueryDocumentSnapshot> docs) {
    return docs
        .map((doc) => doc.data() as Map<String, dynamic>)
        .where((data) {
          final isValidRole =
              _matchesRole(data, 'Docente') ||
              _matchesRole(data, 'Administrativo');
          return _matchesCurrentSede(data) && isValidRole;
        })
        .map((data) => (data['nombre'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  List<QueryDocumentSnapshot> _filterAsistencias(
    List<QueryDocumentSnapshot> docs, {
    Set<String>? allowedNames,
  }) {
    if (allowedNames == null) {
      return docs;
    }

    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final docente = (data['docente'] ?? '').toString().trim();
      return allowedNames.contains(docente);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('asistencias_realizadas')
          .snapshots(),
      builder: (context, asistenciasSnapshot) {
        if (asistenciasSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF00C0EF)),
          );
        }

        final asistencias = asistenciasSnapshot.data?.docs ?? const [];

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('usuarios').snapshots(),
          builder: (context, usuariosSnapshot) {
            if (usuariosSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF00C0EF)),
              );
            }

            final allowedNames = _allowedNames(
              usuariosSnapshot.data?.docs ?? const [],
            );
            final filtrados = _filterAsistencias(
              asistencias,
              allowedNames: allowedNames,
            );

            return _buildContenido(filtrados, showSedeBanner: true);
          },
        );
      },
    );
  }

  Widget _buildContenido(
    List<QueryDocumentSnapshot> docs, {
    bool showSedeBanner = false,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(15),
      child: Column(
        children: [
          BootstrapAdminHero(
            branding: _branding,
            icon: Icons.analytics_rounded,
            eyebrow: _sedeLabel,
            title: 'Indicadores y estadisticas',
            subtitle:
                'Analiza asistencia, comportamiento y tendencias del personal de $_sedeLabel desde una vista mas clara y consistente.',
          ),
          const SizedBox(height: 18),
          if (showSedeBanner)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: BootstrapAdminAlertBar(
                icon: Icons.people_alt_outlined,
                message:
                    'Mostrando solo asistencias y alertas del personal de $_sedeLabel.',
                accentColor: _bannerColor,
                backgroundColor: _bannerSoftColor,
              ),
            ),
          Container(
            height: 350,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: _panelBorderColor),
              boxShadow: [
                BoxShadow(
                  color: _panelShadowColor,
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 10,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFF00C0EF),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(5),
                      topRight: Radius.circular(5),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Flujo de Asistencias Real',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          _buildSmallButton('Area', true),
                          _buildSmallButton('Donut', false),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: docs.isEmpty
                        ? const Center(child: Text('Sin datos para graficar'))
                        : _buildAreaChart(docs),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF00A65A),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: _panelBorderColor),
                  ),
                  child: TableCalendar(
                    firstDay: DateTime.utc(2025, 1, 1),
                    lastDay: DateTime.utc(2030, 12, 31),
                    focusedDay: DateTime.now(),
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                      leftChevronIcon: Icon(
                        Icons.chevron_left,
                        color: Colors.white,
                      ),
                      rightChevronIcon: Icon(
                        Icons.chevron_right,
                        color: Colors.white,
                      ),
                    ),
                    calendarStyle: const CalendarStyle(
                      todayDecoration: BoxDecoration(
                        color: Colors.white30,
                        shape: BoxShape.circle,
                      ),
                      defaultTextStyle: TextStyle(color: Colors.white),
                      weekendTextStyle: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(flex: 1, child: _buildAtrasosPanel(docs)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAreaChart(List<QueryDocumentSnapshot> docs) {
    final puntos = <FlSpot>[];
    for (int i = 0; i < docs.length; i++) {
      puntos.add(FlSpot(i.toDouble(), (i + 2).toDouble()));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(show: true),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: puntos.isEmpty ? [const FlSpot(0, 0)] : puntos,
            isCurved: true,
            color: const Color(0xFF00C0EF),
            barWidth: 4,
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFF00C0EF).withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAtrasosPanel(List<QueryDocumentSnapshot> docs) {
    final atrasos = docs.where((d) => d['estado'] == 'Atraso').toList();

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: _panelBorderColor),
        boxShadow: [
          BoxShadow(
            color: _panelShadowColor,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Alertas de Atrasos (${atrasos.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Divider(),
          if (atrasos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No hay atrasos registrados',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ...atrasos.map((doc) {
              return _atrasoItem(
                doc['docente'] ?? 'Sin nombre',
                doc['estado'] ?? 'Atraso',
                doc['hora_marcada'] ?? '--:--',
              );
            }),
        ],
      ),
    );
  }

  Widget _atrasoItem(String nombre, String estado, String hora) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.timer_off_outlined,
              color: Colors.redAccent,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E2937),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Estado: $estado',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              hora,
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallButton(String text, bool active) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? Colors.white.withValues(alpha: 0.22) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: active ? 0.40 : 0.18),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: active ? 1.0 : 0.70),
          fontSize: 11,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}
