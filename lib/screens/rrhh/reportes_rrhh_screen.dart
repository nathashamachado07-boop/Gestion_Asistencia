import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_config.dart';
import '../../models/app_branding.dart';
import 'rrhh_sede_selector.dart';

class ReportesRRHHScreen extends StatelessWidget {
  const ReportesRRHHScreen({super.key, this.userData});

  final Map<String, dynamic>? userData;

  @override
  Widget build(BuildContext context) {
    return RRHHSedeSelectorPage(
      allowedSedeIds: MatrizApprovalFlow.allowedSedeIdsForUser(userData),
      title: 'Reportes por sede',
      subtitle:
          'Abre los reportes de asistencia de una sede especifica y filtra por estado, tipo, mes y colaborador.',
      icon: Icons.bar_chart_rounded,
      onSelected: (option) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _ReportesSedeDetalle(option: option),
          ),
        );
      },
    );
  }
}

class _ReportesSedeDetalle extends StatefulWidget {
  const _ReportesSedeDetalle({
    required this.option,
  });

  final RRHHSedeOption option;

  @override
  State<_ReportesSedeDetalle> createState() => _ReportesSedeDetalleState();
}

class _ReportesSedeDetalleState extends State<_ReportesSedeDetalle> {
  final TextEditingController _busquedaController = TextEditingController();

  String _estadoFiltro = 'Todos';
  String _tipoFiltro = 'Todos';
  String _mesFiltro = 'Todos';
  String _anioFiltro = 'Todos';

  AppBranding get _branding => widget.option.branding;

  static const List<String> _meses = [
    'Todos',
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  String _normalize(dynamic value) {
    return value?.toString().trim().toLowerCase() ?? '';
  }

  bool _isTrackedUser(Map<String, dynamic> data) {
    return UserRoleAccess.isTeacherRole(data['rol']) ||
        UserRoleAccess.isAdministrativeRole(data['rol']);
  }

  bool _belongsToSede({
    required Map<String, dynamic> record,
    required String sedeId,
    required Set<String> allowedNames,
  }) {
    if (SedeAccess.matchesSede(record, sedeId)) {
      return true;
    }

    final nombre = (record['docente'] ?? '').toString().trim();
    return allowedNames.contains(nombre);
  }

  DateTime? _extractFecha(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String && value.trim().isNotEmpty) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  List<QueryDocumentSnapshot> _filterAsistencias({
    required List<QueryDocumentSnapshot> asistencias,
    required Set<String> allowedNames,
  }) {
    final busqueda = _normalize(_busquedaController.text);

    return asistencias.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

      if (!_belongsToSede(
        record: data,
        sedeId: widget.option.sedeId,
        allowedNames: allowedNames,
      )) {
        return false;
      }

      final nombre = (data['docente'] ?? '').toString().trim();
      final estado = (data['estado'] ?? '').toString().trim();
      final tipo = (data['tipo'] ?? '').toString().trim();
      final fecha = _extractFecha(data['fecha']);

      if (busqueda.isNotEmpty && !_normalize(nombre).contains(busqueda)) {
        return false;
      }

      if (_estadoFiltro != 'Todos' && estado != _estadoFiltro) {
        return false;
      }

      if (_tipoFiltro != 'Todos' && tipo != _tipoFiltro) {
        return false;
      }

      if (_mesFiltro != 'Todos') {
        if (fecha == null) return false;
        final mesNumero = _meses.indexOf(_mesFiltro);
        if (mesNumero <= 0 || fecha.month != mesNumero) {
          return false;
        }
      }

      if (_anioFiltro != 'Todos') {
        if (fecha == null || fecha.year.toString() != _anioFiltro) {
          return false;
        }
      }

      return true;
    }).toList()
      ..sort((a, b) {
        final dataA = a.data() as Map<String, dynamic>;
        final dataB = b.data() as Map<String, dynamic>;
        final fechaA =
            _extractFecha(dataA['fecha']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final fechaB =
            _extractFecha(dataB['fecha']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return fechaB.compareTo(fechaA);
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _branding.background,
      appBar: AppBar(
        backgroundColor: _branding.primary,
        elevation: 0,
        title: Text(
          'Reportes - ${widget.option.title}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Stack(
        children: [
          _buildBackground(),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('usuarios').snapshots(),
            builder: (context, usuariosSnapshot) {
              if (usuariosSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final usuariosDocs =
                  usuariosSnapshot.data?.docs ?? <QueryDocumentSnapshot>[];
              final allowedNames = usuariosDocs
                  .map((doc) => doc.data() as Map<String, dynamic>)
                  .where((data) =>
                      _isTrackedUser(data) &&
                      SedeAccess.matchesSede(data, widget.option.sedeId))
                  .map((data) => (data['nombre'] ?? '').toString().trim())
                  .where((name) => name.isNotEmpty)
                  .toSet();

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('asistencias_realizadas')
                    .orderBy('fecha', descending: true)
                    .snapshots(),
                builder: (context, asistenciasSnapshot) {
                  if (asistenciasSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (asistenciasSnapshot.hasError) {
                    return const Center(child: Text('Error al cargar reportes.'));
                  }

                  final asistencias =
                      asistenciasSnapshot.data?.docs ?? <QueryDocumentSnapshot>[];
                  final estados = <String>{
                    'Todos',
                    ...asistencias
                        .map((doc) => (doc.data() as Map<String, dynamic>)['estado'])
                        .whereType<String>()
                        .where((value) => value.trim().isNotEmpty),
                  }.toList();
                  final tipos = <String>{
                    'Todos',
                    ...asistencias
                        .map((doc) => (doc.data() as Map<String, dynamic>)['tipo'])
                        .whereType<String>()
                        .where((value) => value.trim().isNotEmpty),
                  }.toList();
                  final anios = <String>{
                    'Todos',
                    ...asistencias
                        .map((doc) => _extractFecha(
                            (doc.data() as Map<String, dynamic>)['fecha']))
                        .whereType<DateTime>()
                        .map((fecha) => fecha.year.toString()),
                  }.toList()
                    ..sort((a, b) {
                      if (a == 'Todos') return -1;
                      if (b == 'Todos') return 1;
                      return b.compareTo(a);
                    });

                  final registros = _filterAsistencias(
                    asistencias: asistencias,
                    allowedNames: allowedNames,
                  );

                  return Column(
                    children: [
                      _buildHeader(registros.length),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                          child: Column(
                            children: [
                              _buildFiltros(estados, tipos, anios),
                              const SizedBox(height: 16),
                              if (registros.isEmpty)
                                _buildEmptyState()
                              else
                                ...registros.map((doc) {
                                  final data = doc.data() as Map<String, dynamic>;
                                  return _buildReportCard(data);
                                }),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _branding.background,
                  _branding.surface,
                  _branding.softAccent.withOpacity(0.78),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 86.0;
                final cols = (constraints.maxWidth / spacing).ceil() + 1;
                final rows = (constraints.maxHeight / spacing).ceil() + 1;

                return Opacity(
                  opacity: 0.08,
                  child: Stack(
                    children: List.generate(rows * cols, (index) {
                      final row = index ~/ cols;
                      final col = index % cols;
                      final offsetX = row.isEven ? 0.0 : spacing / 2;

                      return Positioned(
                        left: col * spacing + offsetX,
                        top: row * spacing,
                        child: Image.asset(
                          _branding.logoSmall,
                          width: 40,
                          height: 40,
                          fit: BoxFit.contain,
                        ),
                      );
                    }),
                  ),
                );
              },
            ),
          ),
        ),
        Positioned(
          right: -40,
          top: 150,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.13,
              child: Image.asset(
                _branding.logoWatermark,
                width: 240,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(int total) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_branding.primary, _branding.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Resumen por sede',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.option.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              height: 1.02,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Registros encontrados: $total',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildHeaderPill(
                Icons.calendar_today_outlined,
                DateFormat('dd MMM, yyyy').format(DateTime.now()),
              ),
              _buildHeaderPill(
                Icons.location_on_outlined,
                widget.option.title,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltros(
    List<String> estados,
    List<String> tipos,
    List<String> anios,
  ) {
    final estadoValue = estados.contains(_estadoFiltro) ? _estadoFiltro : 'Todos';
    final tipoValue = tipos.contains(_tipoFiltro) ? _tipoFiltro : 'Todos';
    final anioValue = anios.contains(_anioFiltro) ? _anioFiltro : 'Todos';
    final mesValue = _meses.contains(_mesFiltro) ? _mesFiltro : 'Todos';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.84),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.9)),
        boxShadow: [
          BoxShadow(
            color: _branding.primary.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Filtros de busqueda',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Color(0xFF22343D),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Ordena el reporte por estado, tipo y periodo con un bloque visual mas limpio.',
            style: TextStyle(
              color: _branding.primaryDark.withOpacity(0.72),
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _busquedaController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar colaborador',
              prefixIcon: Icon(Icons.search, color: _branding.primary),
              filled: true,
              fillColor: Colors.white.withOpacity(0.94),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildDropdown(
                    width: width,
                    label: 'Estado',
                    value: estadoValue,
                    items: estados,
                    onChanged: (value) => setState(() => _estadoFiltro = value!),
                  ),
                  _buildDropdown(
                    width: width,
                    label: 'Tipo',
                    value: tipoValue,
                    items: tipos,
                    onChanged: (value) => setState(() => _tipoFiltro = value!),
                  ),
                  _buildDropdown(
                    width: width,
                    label: 'Mes',
                    value: mesValue,
                    items: _meses,
                    onChanged: (value) => setState(() => _mesFiltro = value!),
                  ),
                  _buildDropdown(
                    width: width,
                    label: 'Año',
                    value: anioValue,
                    items: anios,
                    onChanged: (value) => setState(() => _anioFiltro = value!),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required double width,
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white.withOpacity(0.94),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        ),
        items: items
            .map(
              (item) => DropdownMenuItem<String>(
                value: item,
                child: Text(
                  item,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> data) {
    final estado = (data['estado'] ?? '').toString();
    final tipo = (data['tipo'] ?? '').toString();
    final horario = (data['horario_ref'] ?? 'Sin bloque').toString();
    final fecha = _extractFecha(data['fecha']);
    final esEntrada = tipo == 'ENTRADA';

    Color colorEstado = Colors.teal;
    if (estado == 'Atraso') {
      colorEstado = Colors.redAccent;
    } else if (estado == 'Salida Anticipada') {
      colorEstado = Colors.orange;
    } else if (estado == 'Completada') {
      colorEstado = Colors.green;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.92)),
        boxShadow: [
          BoxShadow(
            color: _branding.primary.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: _branding.primary.withOpacity(0.12),
                child: Icon(
                  esEntrada ? Icons.login_rounded : Icons.logout_rounded,
                  color: _branding.primary,
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
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$horario • $tipo',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colorEstado.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  estado,
                  style: TextStyle(
                    color: colorEstado,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildInfoChip(
                Icons.calendar_month_outlined,
                fecha == null
                    ? 'Sin fecha'
                    : DateFormat('dd/MM/yyyy').format(fecha),
              ),
              _buildInfoChip(
                Icons.access_time_outlined,
                'Hora: ${(data['hora_marcada'] ?? '--:--').toString()}',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Obs: ${(data['observacion'] ?? 'Sin observacion').toString()}',
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _branding.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: _branding.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 42),
      child: Column(
        children: [
          Icon(
            Icons.history_toggle_off_rounded,
            size: 78,
            color: _branding.primary.withOpacity(0.42),
          ),
          const SizedBox(height: 12),
          const Text(
            'No hay registros con esos filtros.',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF53646D),
            ),
          ),
        ],
      ),
    );
  }
}
