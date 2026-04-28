import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_config.dart';
import '../models/app_branding.dart';

class AlmuerzosAdminWeb extends StatelessWidget {
  const AlmuerzosAdminWeb({
    super.key,
    this.isSedeNorte = false,
    this.sedeId,
  });

  final bool isSedeNorte;
  final String? sedeId;
  String get _resolvedSedeId =>
      sedeId ??
      (isSedeNorte ? SedeAccess.sedeNorteId : SedeAccess.matrizId);

  AppBranding get _branding => AppBranding.fromSedeId(_resolvedSedeId);

  Color get _primary => _branding.primary;
  Color get _primaryDark => _branding.primaryDark;
  Color get _surface => _branding.surface;
  Color get _softAccent => _branding.softAccent;

  bool _matchesCurrentSede(Map<String, dynamic> data) {
    return SedeAccess.matchesSede(data, _resolvedSedeId);
  }

  bool _isTrackedStaff(Map<String, dynamic> data) {
    final rol = (data['rol'] ?? '').toString().trim().toLowerCase();
    return rol == 'docente' || rol == 'administrativo';
  }

  DateTime _parseMomento(Map<String, dynamic> data) {
    final timestamp = data['timestamp'];
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    }

    final fecha = (data['fecha'] ?? '').toString().trim();
    final hora = (data['hora_salida'] ?? '00:00:00').toString().trim();

    try {
      return DateFormat('yyyy-MM-dd HH:mm:ss').parse('$fecha $hora');
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  bool _isToday(String fecha) {
    final hoy = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return fecha == hoy;
  }

  String _formatFecha(String fecha) {
    if (fecha.isEmpty) return '--';
    try {
      return DateFormat('dd/MM/yyyy').format(DateFormat('yyyy-MM-dd').parse(fecha));
    } catch (_) {
      return fecha;
    }
  }

  String _resolveEstadoLabel(String estado) {
    switch (estado.trim().toLowerCase()) {
      case 'en_almuerzo':
        return 'En almuerzo';
      case 'finalizado':
        return 'Finalizado';
      default:
        return estado.isEmpty ? 'Sin estado' : estado;
    }
  }

  Color _estadoColor(String estado) {
    switch (estado.trim().toLowerCase()) {
      case 'en_almuerzo':
        return const Color(0xFFF0A64A);
      case 'finalizado':
        return const Color(0xFF3FA36C);
      default:
        return _primary;
    }
  }

  List<_AlmuerzoRegistroView> _buildRegistros({
    required List<QueryDocumentSnapshot> almuerzosDocs,
    required List<QueryDocumentSnapshot> usuariosDocs,
  }) {
    final usuariosPorCorreo = <String, Map<String, dynamic>>{};

    for (final doc in usuariosDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final correo = (data['correo'] ?? '').toString().trim().toLowerCase();
      if (correo.isEmpty || !_isTrackedStaff(data)) continue;
      usuariosPorCorreo[correo] = data;
    }

    final registros = <_AlmuerzoRegistroView>[];

    for (final doc in almuerzosDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final correo = (data['correo_usuario'] ?? '').toString().trim();
      final correoKey = correo.toLowerCase();
      final usuario = usuariosPorCorreo[correoKey];

      final pertenecePorRegistro = _matchesCurrentSede(data);
      final pertenecePorUsuario =
          usuario != null && _matchesCurrentSede(usuario);

      if (!pertenecePorRegistro && !pertenecePorUsuario) {
        continue;
      }

      registros.add(
        _AlmuerzoRegistroView(
          colaborador: (data['nombre_usuario'] ?? usuario?['nombre'] ?? 'Sin nombre')
              .toString(),
          correo: correo,
          fecha: (data['fecha'] ?? '').toString(),
          horaSalida: (data['hora_salida'] ?? '--:--').toString(),
          horaRegreso: (data['hora_regreso'] ?? '--:--').toString(),
          estado: (data['estado'] ?? '').toString(),
          tipoHorario: (data['tipo_horario'] ?? usuario?['tipo_horario'] ?? '--')
              .toString(),
          horarioAlmuerzo:
              (data['almuerzo_horario'] ?? usuario?['almuerzo_horario_label'] ?? '--')
                  .toString(),
          momento: _parseMomento(data),
        ),
      );
    }

    registros.sort((a, b) => b.momento.compareTo(a.momento));
    return registros;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _surface,
                    Colors.white,
                    _softAccent.withOpacity(0.42),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          Positioned(
            right: -40,
            bottom: -20,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.05,
                child: Image.asset(
                  _branding.logoWatermark,
                  width: 320,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('registros_almuerzo')
                .snapshots(),
            builder: (context, almuerzosSnapshot) {
              if (almuerzosSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('usuarios').snapshots(),
                builder: (context, usuariosSnapshot) {
                  if (usuariosSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final registros = _buildRegistros(
                    almuerzosDocs:
                        almuerzosSnapshot.data?.docs ?? <QueryDocumentSnapshot>[],
                    usuariosDocs:
                        usuariosSnapshot.data?.docs ?? <QueryDocumentSnapshot>[],
                  );
                  final total = registros.length;
                  final enAlmuerzo = registros
                      .where((r) => r.estado.trim().toLowerCase() == 'en_almuerzo')
                      .length;
                  final finalizados = registros
                      .where((r) => r.estado.trim().toLowerCase() == 'finalizado')
                      .length;
                  final hoy = registros.where((r) => _isToday(r.fecha)).length;

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final compacto = constraints.maxWidth < 980;

                      return SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          constraints.maxWidth > 1200 ? 36 : 20,
                          28,
                          constraints.maxWidth > 1200 ? 36 : 20,
                          36,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeroHeader(),
                            const SizedBox(height: 22),
                            Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children: [
                                _buildStatCard(
                                  'Total registros',
                                  total.toString(),
                                  Icons.restaurant_menu_rounded,
                                  _primary,
                                ),
                                _buildStatCard(
                                  'En almuerzo',
                                  enAlmuerzo.toString(),
                                  Icons.lunch_dining_outlined,
                                  const Color(0xFFF0A64A),
                                ),
                                _buildStatCard(
                                  'Finalizados',
                                  finalizados.toString(),
                                  Icons.task_alt_rounded,
                                  const Color(0xFF3FA36C),
                                ),
                                _buildStatCard(
                                  'Registros de hoy',
                                  hoy.toString(),
                                  Icons.today_outlined,
                                  _primaryDark,
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.94),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: _primary.withOpacity(0.14),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _primary.withOpacity(0.08),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: _softAccent.withOpacity(0.72),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: Icon(
                                          Icons.receipt_long_outlined,
                                          color: _primary,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Registros de almuerzo',
                                              style: TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF1E2937),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Visualizando solo almuerzos del personal de ${SedeAccess.displayNameForId(_resolvedSedeId)}.',
                                              style: TextStyle(
                                                color: _primaryDark.withOpacity(0.74),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  if (registros.isEmpty)
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 26,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _surface,
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: _primary.withOpacity(0.12),
                                        ),
                                      ),
                                      child: Text(
                                        'No hay registros de almuerzo para esta sede todavia.',
                                        style: TextStyle(
                                          color: _primaryDark.withOpacity(0.76),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    )
                                  else if (compacto)
                                    Column(
                                      children: registros
                                          .map((registro) => _buildRegistroCard(registro))
                                          .toList(),
                                    )
                                  else
                                    _buildTabla(registros),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeroHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_primaryDark, _primary, _primary.withOpacity(0.86)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.18),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
            child: const Icon(
              Icons.restaurant_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Control de almuerzos',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Consulta las salidas y regresos de almuerzo del personal de ${SedeAccess.displayNameForId(_resolvedSedeId)} sin mezclar informacion de otras sedes.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    height: 1.45,
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

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF6C7A89),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF1E2937),
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
  }

  Widget _buildTabla(List<_AlmuerzoRegistroView> registros) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: MaterialStatePropertyAll(_softAccent.withOpacity(0.82)),
        dataRowMinHeight: 68,
        dataRowMaxHeight: 78,
        columns: const [
          DataColumn(label: Text('Colaborador')),
          DataColumn(label: Text('Fecha')),
          DataColumn(label: Text('Salida')),
          DataColumn(label: Text('Regreso')),
          DataColumn(label: Text('Estado')),
          DataColumn(label: Text('Bloque almuerzo')),
          DataColumn(label: Text('Horario')),
          DataColumn(label: Text('Correo')),
        ],
        rows: registros
            .map(
              (registro) => DataRow(
                cells: [
                  DataCell(Text(registro.colaborador)),
                  DataCell(Text(_formatFecha(registro.fecha))),
                  DataCell(Text(registro.horaSalida)),
                  DataCell(Text(registro.horaRegreso)),
                  DataCell(_buildEstadoChip(registro.estado)),
                  DataCell(Text(registro.horarioAlmuerzo)),
                  DataCell(Text(registro.tipoHorario)),
                  DataCell(SizedBox(
                    width: 220,
                    child: Text(
                      registro.correo,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildRegistroCard(_AlmuerzoRegistroView registro) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface.withOpacity(0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _primary.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  registro.colaborador,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E2937),
                  ),
                ),
              ),
              _buildEstadoChip(registro.estado),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildInfoPill(Icons.calendar_today_outlined, _formatFecha(registro.fecha)),
              _buildInfoPill(Icons.logout_rounded, 'Salida: ${registro.horaSalida}'),
              _buildInfoPill(Icons.login_rounded, 'Regreso: ${registro.horaRegreso}'),
              _buildInfoPill(Icons.lunch_dining_outlined, registro.horarioAlmuerzo),
              _buildInfoPill(Icons.schedule_outlined, registro.tipoHorario),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            registro.correo,
            style: TextStyle(
              color: _primaryDark.withOpacity(0.74),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _primary.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _primary),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF415160),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstadoChip(String estado) {
    final color = _estadoColor(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Text(
        _resolveEstadoLabel(estado),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _AlmuerzoRegistroView {
  const _AlmuerzoRegistroView({
    required this.colaborador,
    required this.correo,
    required this.fecha,
    required this.horaSalida,
    required this.horaRegreso,
    required this.estado,
    required this.tipoHorario,
    required this.horarioAlmuerzo,
    required this.momento,
  });

  final String colaborador;
  final String correo;
  final String fecha;
  final String horaSalida;
  final String horaRegreso;
  final String estado;
  final String tipoHorario;
  final String horarioAlmuerzo;
  final DateTime momento;
}
