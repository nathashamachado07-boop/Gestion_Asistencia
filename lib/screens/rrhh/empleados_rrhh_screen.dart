import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../models/app_branding.dart';
import 'rrhh_sede_selector.dart';

class EmpleadosRRHHScreen extends StatelessWidget {
  const EmpleadosRRHHScreen({super.key, this.userData});

  final Map<String, dynamic>? userData;

  @override
  Widget build(BuildContext context) {
    return RRHHSedeSelectorPage(
      allowedSedeIds: MatrizApprovalFlow.allowedSedeIdsForUser(userData),
      title: 'Personal por sede',
      subtitle:
          'Selecciona una sede para ver al personal en tarjetas con sus datos, horarios y rol.',
      icon: Icons.people_alt_outlined,
      onSelected: (option) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _EmpleadosSedeDetalle(option: option),
          ),
        );
      },
    );
  }
}

class _EmpleadosSedeDetalle extends StatefulWidget {
  const _EmpleadosSedeDetalle({
    required this.option,
  });

  final RRHHSedeOption option;

  @override
  State<_EmpleadosSedeDetalle> createState() => _EmpleadosSedeDetalleState();
}

class _EmpleadosSedeDetalleState extends State<_EmpleadosSedeDetalle> {
  final TextEditingController _busquedaController = TextEditingController();
  String _rolFiltro = 'Todos';

  AppBranding get _branding => widget.option.branding;

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  String _normalize(dynamic value) {
    return value?.toString().trim().toLowerCase() ?? '';
  }

  List<QueryDocumentSnapshot> _filtrarUsuarios(List<QueryDocumentSnapshot> docs) {
    final busqueda = _normalize(_busquedaController.text);

    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

      if (!SedeAccess.matchesSede(data, widget.option.sedeId)) {
        return false;
      }

      final nombre = (data['nombre'] ?? '').toString();
      final correo = (data['correo'] ?? '').toString();
      final rol = UserRoleAccess.displayRoleForUser(data);

      if (_rolFiltro != 'Todos' && rol != _rolFiltro) {
        return false;
      }

      if (busqueda.isNotEmpty &&
          !_normalize(nombre).contains(busqueda) &&
          !_normalize(correo).contains(busqueda)) {
        return false;
      }

      return true;
    }).toList()
      ..sort((a, b) {
        final dataA = a.data() as Map<String, dynamic>;
        final dataB = b.data() as Map<String, dynamic>;
        final nombreA = (dataA['nombre'] ?? '').toString();
        final nombreB = (dataB['nombre'] ?? '').toString();
        return nombreA.compareTo(nombreB);
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
          'Personal - ${widget.option.title}',
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
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final usuarios = snapshot.data?.docs ?? <QueryDocumentSnapshot>[];
              final roles = <String>{
                'Todos',
                ...usuarios
                    .map(
                      (doc) => UserRoleAccess.displayRoleForUser(
                        doc.data() as Map<String, dynamic>,
                      ),
                    )
                    .where((rol) => rol.trim().isNotEmpty),
              }.toList();
              final rolValue = roles.contains(_rolFiltro) ? _rolFiltro : 'Todos';
              final filtrados = _filtrarUsuarios(usuarios);

              return Column(
                children: [
                  _buildHeader(filtrados.length),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: Column(
                        children: [
                          _buildFiltros(roles, rolValue),
                          const SizedBox(height: 16),
                          if (filtrados.isEmpty)
                            _buildEmptyState()
                          else
                            ...filtrados.map(_buildEmpleadoCard),
                        ],
                      ),
                    ),
                  ),
                ],
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
              'Vista de personal',
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
            'Personal encontrado: $total',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltros(List<String> roles, String rolValue) {
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
            'Busqueda y rol',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Color(0xFF22343D),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Filtra el personal por nombre, correo o rol con una presentacion mas despejada.',
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
              hintText: 'Buscar por nombre o correo',
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
          DropdownButtonFormField<String>(
            value: rolValue,
            decoration: InputDecoration(
              labelText: 'Rol',
              filled: true,
              fillColor: Colors.white.withOpacity(0.94),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            ),
            items: roles
                .map(
                  (rol) => DropdownMenuItem<String>(
                    value: rol,
                    child: Text(rol),
                  ),
                )
                .toList(),
            onChanged: (value) =>
                setState(() => _rolFiltro = value ?? 'Todos'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpleadoCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final nombre = (data['nombre'] ?? 'Sin nombre').toString();
    final correo = (data['correo'] ?? 'Sin correo').toString();
    final rol = UserRoleAccess.displayRoleForUser(data);
    final tipoHorario = (data['tipo_horario'] ?? 'Sin tipo').toString();
    final telefono = (data['telefono'] ?? 'No registrado').toString();
    final horarios = (data['horarios_asignados'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .toList();

    Color badgeColor = Colors.green;
    if (UserRoleAccess.isRrhhRole(rol)) {
      badgeColor = Colors.blue;
    } else if (UserRoleAccess.isAdministrativeRole(rol)) {
      badgeColor = Colors.teal;
    } else if (UserRoleAccess.isAdminRole(rol)) {
      badgeColor = Colors.indigo;
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
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _branding.primary.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    nombre.isEmpty ? '?' : nombre[0].toUpperCase(),
                    style: TextStyle(
                      color: _branding.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
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
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      correo,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  rol,
                  style: TextStyle(
                    color: badgeColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildInfoChip(Icons.schedule_outlined, tipoHorario),
              _buildInfoChip(Icons.phone_outlined, telefono),
              _buildInfoChip(Icons.apartment_outlined, widget.option.title),
            ],
          ),
          if (horarios.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Horarios asignados',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF3A4B54),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: horarios
                  .map(
                    (horario) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _branding.surface.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        horario,
                        style: TextStyle(
                          fontSize: 11,
                          color: _branding.primaryDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
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
            Icons.people_outline_rounded,
            size: 78,
            color: _branding.primary.withOpacity(0.38),
          ),
          const SizedBox(height: 12),
          const Text(
            'No hay personal con esos filtros.',
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
