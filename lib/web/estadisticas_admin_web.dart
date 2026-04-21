import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../config/app_config.dart';
import '../models/app_branding.dart';

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
    return _normalize(data['rol']) == role.toLowerCase();
  }

  String get _sedeLabel =>
      _resolvedSedeId == SedeAccess.matrizId
          ? 'Sede Matriz'
          : SedeAccess.displayNameForId(_resolvedSedeId);
  Color get _bannerColor => _branding.primary;
  Color get _bannerSoftColor => _branding.surface;
  Color get _panelBorderColor => _branding.primary.withOpacity(0.24);
  Color get _panelShadowColor => _branding.primary.withOpacity(0.10);

  Set<String> _allowedNames(List<QueryDocumentSnapshot> docs) {
    return docs
        .map((doc) => doc.data() as Map<String, dynamic>)
        .where((data) {
          final isValidRole =
              _matchesRole(data, 'Docente') || _matchesRole(data, 'Administrativo');
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

            final allowedNames = _allowedNames(usuariosSnapshot.data?.docs ?? const []);
            final filtrados = _filterAsistencias(
              asistencias,
              allowedNames: allowedNames,
            );

            return _buildContenido(
              filtrados,
              showSedeBanner: true,
            );
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
          if (showSedeBanner)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _bannerSoftColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _bannerColor.withOpacity(0.24)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.people_alt_outlined,
                    color: _bannerColor,
                    size: 18,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Mostrando solo asistencias y alertas del personal de $_sedeLabel.',
                      style: TextStyle(
                        color: _bannerColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
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
                      leftChevronIcon: Icon(Icons.chevron_left, color: Colors.white),
                      rightChevronIcon: Icon(Icons.chevron_right, color: Colors.white),
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
              Expanded(
                flex: 1,
                child: _buildAtrasosPanel(docs),
              ),
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
              color: const Color(0xFF00C0EF).withOpacity(0.3),
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
    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Colors.redAccent,
        child: Icon(Icons.warning, color: Colors.white, size: 15),
      ),
      title: Text(
        nombre,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text('Estado: $estado'),
      trailing: Text(
        hora,
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
    );
  }

  Widget _buildSmallButton(String text, bool active) {
    return Container(
      margin: const EdgeInsets.only(left: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? Colors.white24 : Colors.transparent,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: Colors.white.withOpacity(active ? 0.30 : 0.18),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }
}
