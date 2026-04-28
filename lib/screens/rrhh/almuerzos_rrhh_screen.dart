import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_config.dart';
import '../../models/app_branding.dart';
import 'rrhh_sede_selector.dart';

class AlmuerzosRRHHScreen extends StatelessWidget {
  const AlmuerzosRRHHScreen({super.key, this.userData});

  final Map<String, dynamic>? userData;

  @override
  Widget build(BuildContext context) {
    return RRHHSedeSelectorPage(
      allowedSedeIds: MatrizApprovalFlow.allowedSedeIdsForUser(userData),
      title: 'Almuerzos por sede',
      subtitle:
          'Revisa las salidas y regresos de almuerzo de cada sede por separado.',
      icon: Icons.restaurant_menu_outlined,
      onSelected: (option) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _AlmuerzosSedeDetalle(option: option),
          ),
        );
      },
    );
  }
}

class _AlmuerzosSedeDetalle extends StatefulWidget {
  const _AlmuerzosSedeDetalle({
    required this.option,
  });

  final RRHHSedeOption option;

  @override
  State<_AlmuerzosSedeDetalle> createState() => _AlmuerzosSedeDetalleState();
}

class _AlmuerzosSedeDetalleState extends State<_AlmuerzosSedeDetalle> {
  final TextEditingController _busquedaController = TextEditingController();
  String _estadoFiltro = 'Todos';

  AppBranding get _branding => widget.option.branding;

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

  List<_RegistroAlmuerzoView> _filtrarRegistros({
    required List<QueryDocumentSnapshot> docs,
    required Map<String, Map<String, dynamic>> usuariosPorCorreo,
  }) {
    final busqueda = _normalize(_busquedaController.text);

    final registros = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final correo = (data['correo_usuario'] ?? '').toString().trim().toLowerCase();
      final usuario = usuariosPorCorreo[correo];
      final coincideRegistro = SedeAccess.matchesSede(data, widget.option.sedeId);
      final coincideUsuario =
          usuario != null && SedeAccess.matchesSede(usuario, widget.option.sedeId);

      if (!coincideRegistro && !coincideUsuario) {
        return false;
      }

      final estado = (data['estado'] ?? '').toString().trim();
      final nombre =
          (data['nombre_usuario'] ?? usuario?['nombre'] ?? '').toString().trim();

      if (_estadoFiltro != 'Todos' && estado != _estadoFiltro) {
        return false;
      }

      if (busqueda.isNotEmpty &&
          !_normalize(nombre).contains(busqueda) &&
          !correo.contains(busqueda)) {
        return false;
      }

      return true;
    }).map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final correo = (data['correo_usuario'] ?? '').toString().trim().toLowerCase();
      final usuario = usuariosPorCorreo[correo];
      return _RegistroAlmuerzoView(
        nombre:
            (data['nombre_usuario'] ?? usuario?['nombre'] ?? 'Sin nombre').toString(),
        correo: (data['correo_usuario'] ?? '').toString(),
        fecha: (data['fecha'] ?? '').toString(),
        horaSalida: (data['hora_salida'] ?? '--:--').toString(),
        horaRegreso: (data['hora_regreso'] ?? '--:--').toString(),
        estado: (data['estado'] ?? '').toString(),
        tipoHorario:
            (data['tipo_horario'] ?? usuario?['tipo_horario'] ?? '--').toString(),
        momento: _parseMomento(data),
      );
    }).toList()
      ..sort((a, b) => b.momento.compareTo(a.momento));

    return registros;
  }

  String _formatFecha(String fecha) {
    if (fecha.isEmpty) return '--';
    try {
      return DateFormat('dd/MM/yyyy').format(DateFormat('yyyy-MM-dd').parse(fecha));
    } catch (_) {
      return fecha;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _branding.surface,
      appBar: AppBar(
        backgroundColor: _branding.primary,
        elevation: 0,
        title: Text(
          'Almuerzos - ${widget.option.title}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('usuarios').snapshots(),
        builder: (context, usuariosSnapshot) {
          if (usuariosSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final usuariosPorCorreo = <String, Map<String, dynamic>>{};
          for (final doc in usuariosSnapshot.data?.docs ?? <QueryDocumentSnapshot>[]) {
            final data = doc.data() as Map<String, dynamic>;
            if (!_isTrackedUser(data)) continue;
            final correo = (data['correo'] ?? '').toString().trim().toLowerCase();
            if (correo.isNotEmpty) {
              usuariosPorCorreo[correo] = data;
            }
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('registros_almuerzo')
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ?? <QueryDocumentSnapshot>[];
              final estados = <String>{
                'Todos',
                ...docs
                    .map((doc) => (doc.data() as Map<String, dynamic>)['estado'])
                    .whereType<String>()
                    .where((value) => value.trim().isNotEmpty),
              }.toList();
              final estadoValue =
                  estados.contains(_estadoFiltro) ? _estadoFiltro : 'Todos';
              final registros = _filtrarRegistros(
                docs: docs,
                usuariosPorCorreo: usuariosPorCorreo,
              );

              return Column(
                children: [
                  _buildHeader(registros),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: _branding.primary.withOpacity(0.08),
                                  blurRadius: 14,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                TextField(
                                  controller: _busquedaController,
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    hintText: 'Buscar colaborador o correo',
                                    prefixIcon:
                                        Icon(Icons.search, color: _branding.primary),
                                    filled: true,
                                    fillColor: _branding.surface,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                DropdownButtonFormField<String>(
                                  value: estadoValue,
                                  decoration: InputDecoration(
                                    labelText: 'Estado',
                                    filled: true,
                                    fillColor: _branding.surface,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  items: estados
                                      .map(
                                        (estado) => DropdownMenuItem<String>(
                                          value: estado,
                                          child: Text(estado),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) => setState(
                                    () => _estadoFiltro = value ?? 'Todos',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (registros.isEmpty)
                            _buildEmptyState()
                          else
                            ...registros.map(_buildRegistroCard),
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
    );
  }

  Widget _buildHeader(List<_RegistroAlmuerzoView> registros) {
    final enAlmuerzo = registros
        .where((registro) => _normalize(registro.estado) == 'en_almuerzo')
        .length;
    final finalizados = registros
        .where((registro) => _normalize(registro.estado) == 'finalizado')
        .length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_branding.primary, _branding.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.option.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildHeaderPill('Total', registros.length.toString()),
              _buildHeaderPill('En almuerzo', enAlmuerzo.toString()),
              _buildHeaderPill('Finalizados', finalizados.toString()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildRegistroCard(_RegistroAlmuerzoView registro) {
    final colorEstado = _normalize(registro.estado) == 'finalizado'
        ? Colors.green
        : Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _branding.primary.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _branding.primary.withOpacity(0.12),
                child: Icon(
                  Icons.restaurant_menu_outlined,
                  color: _branding.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      registro.nombre,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      registro.correo,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colorEstado.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _normalize(registro.estado) == 'finalizado'
                      ? 'Finalizado'
                      : 'En almuerzo',
                  style: TextStyle(
                    color: colorEstado,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
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
              _buildInfoChip(Icons.calendar_today_outlined, _formatFecha(registro.fecha)),
              _buildInfoChip(Icons.logout_rounded, 'Salida: ${registro.horaSalida}'),
              _buildInfoChip(Icons.login_rounded, 'Regreso: ${registro.horaRegreso}'),
              _buildInfoChip(Icons.schedule_outlined, registro.tipoHorario),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _branding.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: _branding.primary),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
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
            Icons.restaurant_outlined,
            size: 78,
            color: _branding.primary.withOpacity(0.38),
          ),
          const SizedBox(height: 12),
          const Text(
            'No hay registros de almuerzo con esos filtros.',
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

class _RegistroAlmuerzoView {
  const _RegistroAlmuerzoView({
    required this.nombre,
    required this.correo,
    required this.fecha,
    required this.horaSalida,
    required this.horaRegreso,
    required this.estado,
    required this.tipoHorario,
    required this.momento,
  });

  final String nombre;
  final String correo;
  final String fecha;
  final String horaSalida;
  final String horaRegreso;
  final String estado;
  final String tipoHorario;
  final DateTime momento;
}
