import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../models/app_branding.dart';
import '../services/firebase_service.dart';
import 'bootstrap_admin_ui.dart';

const String _roleAcademicUi = 'Personal academico';
const List<String> _matrizAdministrativeDepartments = [
  'Secretaria General y Archivo',
  'Unidad Financiera',
  'Unidad de Bienestar y Admisiones',
  'Departamento de Recursos Humanos',
  'Departamento de IT',
];
const List<String> _matrizAcademicDepartments = [
  'Coordinador carrera de formacion tecnica',
  'Educacion continua',
  'Coordinador de investigacion',
  'Coordinador de vinculacion con la sociedad y Practica Pre Profesionales',
];
const Map<String, String> _matrizLegacyDepartmentAliases = {
  'rrhh': 'Departamento de Recursos Humanos',
  'financiero': 'Unidad Financiera',
  'departamento it': 'Departamento de IT',
};
final List<TextInputFormatter> _tenDigitInputFormatters = [
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(10),
];

String _normalizeDepartmentKey(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n');
}

bool _isLegacyMatrizDepartment(String value) {
  return _matrizLegacyDepartmentAliases.containsKey(
    _normalizeDepartmentKey(value),
  );
}

String _canonicalMatrizDepartmentName(String value) {
  final normalized = _normalizeDepartmentKey(value);
  return _matrizLegacyDepartmentAliases[normalized] ?? value.trim();
}

class PersonalAdminWeb extends StatefulWidget {
  const PersonalAdminWeb({super.key, this.isSedeNorte = false, this.sedeId});

  final bool isSedeNorte;
  final String? sedeId;

  @override
  State<PersonalAdminWeb> createState() => _PersonalAdminWebState();
}

class _PersonalAdminWebState extends State<PersonalAdminWeb> {
  final FirebaseService _service = FirebaseService();
  final TextEditingController _busquedaController = TextEditingController();
  late Stream<QuerySnapshot> _areasStream;
  late Stream<QuerySnapshot> _usuariosStream;
  Timer? _busquedaDebounce;
  String _busquedaAplicada = '';
  String _filtroRol = 'Todos';

  static const List<_HorarioOption> _horariosDocente = [
    _HorarioOption('TC_08:00_16:45', 'TC de 08:00 hasta 16:45'),
    _HorarioOption('TP_08:00_10:00', 'TP de 08:00 hasta 10:00'),
    _HorarioOption('TP_08:00_12:00', 'TP de 08:00 hasta 12:00'),
    _HorarioOption('TP_10:00_12:00', 'TP de 10:00 hasta 12:00'),
    _HorarioOption('NOCT_18:00_22:00', 'Nocturno de 18:00 hasta 22:00'),
  ];

  static const List<_HorarioOption> _horariosAdministrativo = [
    _HorarioOption('TC_08:00_16:45', 'TC de 08:00 hasta 16:45'),
  ];

  String get _resolvedSedeId =>
      widget.sedeId ??
      (widget.isSedeNorte ? SedeAccess.sedeNorteId : SedeAccess.matrizId);

  AppBranding get _branding => AppBranding.fromSedeId(_resolvedSedeId);
  Color get _primary => _branding.primary;
  Color get _primaryDark => _branding.primaryDark;
  Color get _surface => _branding.surface;
  Color get _softAccent => _branding.softAccent;
  bool get _mostrarAdminsEnVista => _resolvedSedeId == SedeAccess.matrizId;
  bool get _usaCatalogoFijoMatriz => _resolvedSedeId == SedeAccess.matrizId;

  // --- Configuración base y fuentes de datos ------------------------------

  bool _isAcademicRole(dynamic value) => UserRoleAccess.isTeacherRole(value);

  String _roleLabelForUi(dynamic value) {
    if (_isAcademicRole(value)) {
      return _roleAcademicUi;
    }
    return UserRoleAccess.displayRole(value);
  }

  @override
  void initState() {
    super.initState();
    _busquedaAplicada = _busquedaController.text;
    _rebuildStreams();
    _asegurarAreasBase();
  }

  @override
  void didUpdateWidget(covariant PersonalAdminWeb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sedeId != widget.sedeId ||
        oldWidget.isSedeNorte != widget.isSedeNorte) {
      _rebuildStreams();
      _asegurarAreasBase();
    }
  }

  @override
  void dispose() {
    _busquedaDebounce?.cancel();
    _busquedaController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot> _buildAreasStream() {
    return FirebaseFirestore.instance
        .collection('areas')
        .where('sedeId', isEqualTo: _resolvedSedeId)
        .snapshots();
  }

  Stream<QuerySnapshot> _buildUsuariosStream() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('usuarios')
        .where('sedeId', isEqualTo: _resolvedSedeId);

    final filtroRolBase = !_mostrarAdminsEnVista && _filtroRol == 'Admin'
        ? 'Todos'
        : _filtroRol;
    final filtroRolActual = filtroRolBase == _roleAcademicUi
        ? 'Docente'
        : filtroRolBase;

    if (filtroRolActual == 'Docente') {
      query = query.where('rol', isEqualTo: 'Docente');
    } else if (filtroRolActual == 'Personal administrativo') {
      query = query.where(
        'rol',
        whereIn: const ['Personal administrativo', 'Administrativo'],
      );
    } else if (filtroRolActual == 'RRHH') {
      query = query.where('rol', isEqualTo: 'RRHH');
    } else if (filtroRolActual == 'Admin') {
      query = query.where('rol', isEqualTo: 'Admin');
    } else {
      query = query.where(
        'rol',
        whereIn: const [
          'Docente',
          'Personal administrativo',
          'Administrativo',
          'RRHH',
          'Admin',
        ],
      );
    }

    return query.snapshots();
  }

  void _rebuildStreams() {
    _areasStream = _buildAreasStream();
    _usuariosStream = _buildUsuariosStream();
  }

  void _actualizarFiltroRol(String value) {
    if (_filtroRol == value) {
      return;
    }
    setState(() {
      _filtroRol = value;
      _rebuildStreams();
    });
  }

  void _programarBusquedaDiferida(String value) {
    _busquedaDebounce?.cancel();
    _busquedaDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted || _busquedaAplicada == value) {
        return;
      }
      setState(() => _busquedaAplicada = value);
    });
  }

  Future<void> _asegurarAreasBase() async {
    try {
      await _service.asegurarAreasBasePersonalSede(sedeId: _resolvedSedeId);
    } catch (e) {
      debugPrint('No se pudieron asegurar las areas base: $e');
    }
  }

  bool _esPersonalGestionable(Map<String, dynamic> data) {
    final rol = data['rol'];
    return UserRoleAccess.isTeacherRole(rol) ||
        UserRoleAccess.isAdministrativeRole(rol) ||
        UserRoleAccess.isRrhhRole(rol) ||
        UserRoleAccess.isAdminRole(rol);
  }

  bool _esAdminGlobal(Map<String, dynamic> data) {
    return MatrizApprovalFlow.isPrimaryReviewer(data['correo']);
  }

  // --- Adaptadores de Firestore a modelos de UI ---------------------------

  List<_AreaOption> _buildAreas(List<QueryDocumentSnapshot> docs) {
    final items = <_AreaOption>[];

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (!SedeAccess.matchesSede(data, _resolvedSedeId)) {
        continue;
      }

      final nombre = (data['nombre'] ?? '').toString().trim();
      if (nombre.isEmpty) {
        continue;
      }
      if (_usaCatalogoFijoMatriz && _isLegacyMatrizDepartment(nombre)) {
        continue;
      }

      items.add(
        _AreaOption(
          docId: doc.id,
          nombre: nombre,
          requiereGeolocalizacionPorDefecto:
              _service.requiereGeolocalizacionAreaEfectiva(data),
          gpsTemporalDesactivadoHasta: _service
              .obtenerGpsTemporalDesactivadoHastaArea(data),
          activa: data['activa'] != false,
        ),
      );
    }

    items.sort(
      (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
    );
    return items;
  }

  List<_PersonalView> _buildUsuarios(List<QueryDocumentSnapshot> docs) {
    final items = <_PersonalView>[];

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (!SedeAccess.matchesSede(data, _resolvedSedeId) ||
          _esAdminGlobal(data) ||
          (!_mostrarAdminsEnVista && UserRoleAccess.isAdminRole(data['rol'])) ||
          !_esPersonalGestionable(data)) {
        continue;
      }

      final horarios =
          (data['horarios_asignados'] as List?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const <String>[];
      final horarioId = horarios.isNotEmpty ? horarios.first : 'TC_08:00_16:45';

      items.add(
        _PersonalView(
          docId: doc.id,
          nombre: UserRoleAccess.displayNameForUser(data),
          correo: (data['correo'] ?? '').toString(),
          rol: _roleLabelForUi(UserRoleAccess.displayRoleForUser(data)),
          cedula: (data['cedula'] ?? '').toString(),
          telefono: (data['telefono'] ?? '').toString(),
          areaId: (data['areaId'] ?? '').toString(),
          areaNombre: (data['areaNombre'] ?? '').toString(),
          cargo:
              ((data['cargo'] ?? '').toString().trim().isNotEmpty
                      ? data['cargo']
                      : data['especialidad'])
                  .toString(),
          especialidad: (data['especialidad'] ?? '').toString(),
          horarioId: horarioId,
          tipoHorario: (data['tipo_horario'] ?? '').toString(),
          requiereGeolocalizacion: _service
              .requiereGeolocalizacionUsuarioEfectiva(data),
          gpsTemporalDesactivadoHasta: _service
              .obtenerGpsTemporalDesactivadoHastaUsuario(data),
          tieneVinculacionAcademicaSecundaria:
              data['tieneVinculacionAcademicaSecundaria'] == true,
          horarioAcademicoSecundarioId:
              (data['horarioAcademicoSecundarioId'] ?? '').toString(),
          areaAcademicaSecundariaId: (data['areaAcademicaSecundariaId'] ?? '')
              .toString(),
          areaAcademicaSecundariaNombre:
              (data['areaAcademicaSecundariaNombre'] ?? '').toString(),
          cargoAcademicoSecundario: (data['cargoAcademicoSecundario'] ?? '')
              .toString(),
        ),
      );
    }

    items.sort(
      (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
    );
    return items;
  }

  List<_PersonalView> _filtrarUsuarios(List<_PersonalView> usuarios) {
    final query = _normalizarBusqueda(_busquedaAplicada);
    final queryNumerica = _soloDigitos(_busquedaAplicada);
    final filtroRolBase = !_mostrarAdminsEnVista && _filtroRol == 'Admin'
        ? 'Todos'
        : _filtroRol;
    final filtroRolActual = filtroRolBase == 'Docente'
        ? _roleAcademicUi
        : filtroRolBase;
    return usuarios.where((usuario) {
      final coincideRol =
          filtroRolActual == 'Todos' ||
          usuario.rol.toLowerCase() == filtroRolActual.toLowerCase();
      final nombre = _normalizarBusqueda(usuario.nombre);
      final correo = _normalizarBusqueda(usuario.correo);
      final cedula = _normalizarBusqueda(usuario.cedula);
      final cedulaDigitos = _soloDigitos(usuario.cedula);
      final telefono = _normalizarBusqueda(usuario.telefono);
      final telefonoDigitos = _soloDigitos(usuario.telefono);
      final coincideTexto =
          query.isEmpty ||
          nombre.contains(query) ||
          correo.contains(query) ||
          cedula.contains(query) ||
          telefono.contains(query) ||
          (queryNumerica.isNotEmpty &&
              (telefonoDigitos.contains(queryNumerica) ||
                  cedulaDigitos.contains(queryNumerica)));
      return coincideRol && coincideTexto;
    }).toList();
  }

  String _normalizarBusqueda(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n');
  }

  String _soloDigitos(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String _labelHorario(String horarioId, String rol) {
    final opciones =
        UserRoleAccess.isAdministrativeRole(rol) ||
            UserRoleAccess.isAdminRole(rol) ||
            UserRoleAccess.isRrhhRole(rol)
        ? _horariosAdministrativo
        : _horariosDocente;
    for (final item in opciones) {
      if (item.id == horarioId) {
        return item.label;
      }
    }
    return horarioId;
  }

  Future<void> _abrirFormulario({
    _PersonalView? usuario,
    required List<_AreaOption> areas,
  }) async {
    final actualizado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PersonalFormDialog(
        branding: _branding,
        sedeId: _resolvedSedeId,
        service: _service,
        usuario: usuario,
        areas: areas,
        horariosDocente: _horariosDocente,
        horariosAdministrativo: _horariosAdministrativo,
      ),
    );

    if (!mounted || actualizado != true) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          usuario == null
              ? 'Usuario creado correctamente.'
              : 'Datos del usuario actualizados.',
        ),
      ),
    );
  }

  Future<void> _abrirGestorAreas() async {
    if (_usaCatalogoFijoMatriz) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AreasManagerDialog(
        branding: _branding,
        sedeId: _resolvedSedeId,
        service: _service,
      ),
    );
  }

  Future<void> _confirmarEliminacion(_PersonalView usuario) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Eliminar usuario'),
        content: Text(
          'Se eliminara el acceso de ${usuario.nombre} en ${SedeAccess.displayNameForId(_resolvedSedeId)}. Los registros historicos no se borraran.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    try {
      await _service.eliminarUsuarioPersonalSede(usuarioDocId: usuario.docId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${usuario.nombre} fue eliminado correctamente.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo eliminar el usuario: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
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
                    _softAccent.withValues(alpha: 0.40),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          Positioned(
            left: -10,
            top: 90,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.05,
                child: Image.asset(
                  _branding.logoWatermark,
                  width: 360,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          StreamBuilder<QuerySnapshot>(
            stream: _areasStream,
            builder: (context, areasSnapshot) {
              final areas = _buildAreas(
                areasSnapshot.data?.docs ?? const <QueryDocumentSnapshot>[],
              );
              final areasActivas = areas.where((area) => area.activa).toList();

              return StreamBuilder<QuerySnapshot>(
                stream: _usuariosStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final usuarios = _buildUsuarios(
                    snapshot.data?.docs ?? const <QueryDocumentSnapshot>[],
                  );
                  final filtrados = _filtrarUsuarios(usuarios);
                  final docentes = usuarios
                      .where((e) => _isAcademicRole(e.rol))
                      .length;
                  final administrativos = usuarios
                      .where((e) => UserRoleAccess.isAdministrativeRole(e.rol))
                      .length;
                  final rrhh = usuarios
                      .where((e) => UserRoleAccess.isRrhhRole(e.rol))
                      .length;
                  final admin = usuarios
                      .where((e) => UserRoleAccess.isAdminRole(e.rol))
                      .length;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 96),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHero(),
                        const SizedBox(height: 22),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final statCardWidth = constraints.maxWidth < 720
                                ? constraints.maxWidth
                                : 238.0;

                            return Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children: [
                                _buildStatCard(
                                  'Total personal',
                                  usuarios.length,
                                  Icons.groups_2_outlined,
                                  width: statCardWidth,
                                ),
                                _buildStatCard(
                                  'Personal academico',
                                  docentes,
                                  Icons.school_outlined,
                                  width: statCardWidth,
                                ),
                                _buildStatCard(
                                  'Personal administrativo',
                                  administrativos,
                                  Icons.badge_outlined,
                                  width: statCardWidth,
                                ),
                                _buildStatCard(
                                  'RRHH',
                                  rrhh,
                                  Icons.manage_accounts_outlined,
                                  width: statCardWidth,
                                ),
                                if (_mostrarAdminsEnVista)
                                  _buildStatCard(
                                    'Admin',
                                    admin,
                                    Icons.admin_panel_settings_outlined,
                                    width: statCardWidth,
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 22),
                        _buildFiltersCard(areasActivas.length),
                        const SizedBox(height: 22),
                        if (filtrados.isEmpty)
                          _buildEmptyState()
                        else
                          Column(
                            children: filtrados
                                .map(
                                  (u) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _buildUserRow(u, areasActivas),
                                  ),
                                )
                                .toList(),
                          ),
                        const SizedBox(height: 18),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: _primaryDark,
                            ),
                            onPressed: () =>
                                _abrirFormulario(areas: areasActivas),
                            icon: const Icon(Icons.person_add_alt_1_rounded),
                            label: const Text('Nuevo personal'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return BootstrapAdminHero(
      branding: _branding,
      icon: Icons.manage_accounts_rounded,
      eyebrow: 'Panel de administracion',
      title: 'Gestion de personal por sede',
      subtitle: _mostrarAdminsEnVista
          ? 'Administre personal academico, personal administrativo, RRHH y Admin de ${SedeAccess.displayNameForId(_resolvedSedeId)} desde una vista mas limpia, rapida y consistente.'
          : 'Administre personal academico, personal administrativo y RRHH de ${SedeAccess.displayNameForId(_resolvedSedeId)} desde una vista mas limpia, rapida y consistente.',
    );
  }

  Widget _buildStatCard(
    String label,
    int value,
    IconData icon, {
    required double width,
  }) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _primary.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: _primary.withValues(alpha: 0.09),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 6,
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
              color: _softAccent.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _primary.withValues(alpha: 0.26),
              ),
            ),
            child: Icon(icon, color: _primaryDark),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _primaryDark.withValues(alpha: 0.65),
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    height: 1.25,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '$value',
                  style: TextStyle(
                    color: _primaryDark,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersCard(int totalAreas) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 760;
        final searchWidth = isCompact
            ? constraints.maxWidth
            : math.min(360.0, constraints.maxWidth);
        final roleWidth = isCompact ? constraints.maxWidth : 240.0;
        final filtroRolBase = !_mostrarAdminsEnVista && _filtroRol == 'Admin'
            ? 'Todos'
            : _filtroRol;
        final filtroRolActual = filtroRolBase == 'Docente'
            ? _roleAcademicUi
            : filtroRolBase;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _primary.withValues(alpha: 0.34)),
          ),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
        SizedBox(
          width: searchWidth,
          child: TextField(
            controller: _busquedaController,
            onChanged: _programarBusquedaDiferida,
            decoration: InputDecoration(
                    labelText: 'Buscar por nombre, correo, telefono o cedula',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: _surface.withValues(alpha: 0.58),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: roleWidth,
                child: DropdownButtonFormField<String>(
                  initialValue: filtroRolActual,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Rol',
                    filled: true,
                    fillColor: _surface.withValues(alpha: 0.58),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'Todos',
                      child: Text('Todos', overflow: TextOverflow.ellipsis),
                    ),
                    const DropdownMenuItem(
                      value: _roleAcademicUi,
                      child: Text(
                        _roleAcademicUi,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const DropdownMenuItem(
                      value: 'Personal administrativo',
                      child: Text(
                        'Personal administrativo',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const DropdownMenuItem(
                      value: 'RRHH',
                      child: Text('RRHH', overflow: TextOverflow.ellipsis),
                    ),
                    if (_mostrarAdminsEnVista)
                      const DropdownMenuItem(
                        value: 'Admin',
                        child: Text('Admin', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (value) =>
                      _actualizarFiltroRol(value ?? 'Todos'),
                ),
              ),
              if (!_usaCatalogoFijoMatriz)
                OutlinedButton.icon(
                  onPressed: _abrirGestorAreas,
                  icon: const Icon(Icons.domain_add_outlined),
                  label: Text('Gestionar departamentos ($totalAreas)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryDark,
                    side: BorderSide(color: _primary.withValues(alpha: 0.34)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 15,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _primary.withValues(alpha: 0.24)),
        boxShadow: [
          BoxShadow(
            color: _primary.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(
              Icons.group_off_rounded,
              size: 36,
              color: _primary.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No hay usuarios para mostrar con los filtros actuales.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _primaryDark,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Pruebe con otra busqueda o cree un nuevo usuario para esta sede.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _primaryDark.withValues(alpha: 0.60),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  String _areaLabel(_PersonalView usuario, List<_AreaOption> areas) {
    if (usuario.areaNombre.trim().isNotEmpty) {
      return _usaCatalogoFijoMatriz
          ? _canonicalMatrizDepartmentName(usuario.areaNombre)
          : usuario.areaNombre;
    }

    for (final area in areas) {
      if (area.docId == usuario.areaId) {
        return _usaCatalogoFijoMatriz
            ? _canonicalMatrizDepartmentName(area.nombre)
            : area.nombre;
      }
    }

    return 'Sin departamento';
  }

  Widget _buildUserRow(_PersonalView usuario, List<_AreaOption> areas) {
    final rolEsDocente = UserRoleAccess.isTeacherRole(usuario.rol);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 980;
        final isMobile = constraints.maxWidth < 680;
        final pillMaxWidth = isMobile
            ? math.max(180.0, constraints.maxWidth - 48)
            : (isCompact ? math.max(220.0, constraints.maxWidth - 120) : 280.0);

        final infoWrap = Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            _buildInfoPill(
              Icons.badge_rounded,
              usuario.cedula.isEmpty ? 'Sin cedula' : usuario.cedula,
              maxWidth: pillMaxWidth,
            ),
            _buildInfoPill(
              Icons.phone_outlined,
              usuario.telefono.isEmpty ? 'Sin telefono' : usuario.telefono,
              maxWidth: pillMaxWidth,
            ),
            _buildInfoPill(
              rolEsDocente
                  ? Icons.school_outlined
                  : UserRoleAccess.isAdminRole(usuario.rol)
                  ? Icons.admin_panel_settings_outlined
                  : UserRoleAccess.isRrhhRole(usuario.rol)
                  ? Icons.manage_accounts_outlined
                  : Icons.apartment_outlined,
              _areaLabel(usuario, areas),
              maxWidth: pillMaxWidth,
            ),
            _buildInfoPill(
              Icons.badge_outlined,
              usuario.cargo.isEmpty ? 'Sin cargo' : usuario.cargo,
              maxWidth: pillMaxWidth,
            ),
            _buildInfoPill(
              Icons.schedule_outlined,
              _labelHorario(usuario.horarioId, usuario.rol),
              maxWidth: pillMaxWidth,
            ),
            if (usuario.tieneVinculacionAcademicaSecundaria &&
                usuario.horarioAcademicoSecundarioId.trim().isNotEmpty)
              _buildInfoPill(
                Icons.auto_stories_outlined,
                'Academico: ${_labelHorario(usuario.horarioAcademicoSecundarioId, _roleAcademicUi)}',
                maxWidth: pillMaxWidth,
              ),
            _buildInfoPill(
              usuario.requiereGeolocalizacion
                  ? Icons.location_on_outlined
                  : Icons.location_off_outlined,
              usuario.requiereGeolocalizacion
                  ? 'GPS requerido'
                  : (usuario.gpsTemporalDesactivadoHasta != null
                        ? 'GPS libre hasta media noche'
                        : 'GPS libre'),
              maxWidth: pillMaxWidth,
            ),
          ],
        );

        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _abrirFormulario(usuario: usuario, areas: areas),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Editar'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => _confirmarEliminacion(usuario),
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('Eliminar'),
            ),
          ],
        );

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _primary.withValues(alpha: 0.25),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: _primary.withValues(alpha: 0.07),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: _softAccent.withValues(alpha: 0.84),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              usuario.nombre.isEmpty
                                  ? 'P'
                                  : usuario.nombre
                                        .substring(0, 1)
                                        .toUpperCase(),
                              style: TextStyle(
                                color: _primaryDark,
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                usuario.nombre,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _primaryDark,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                usuario.correo,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _primaryDark.withValues(alpha: 0.65),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildRoleChip(usuario.rol),
                    const SizedBox(height: 12),
                    infoWrap,
                    const SizedBox(height: 12),
                    actions,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _softAccent.withValues(alpha: 0.84),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          usuario.nombre.isEmpty
                              ? 'P'
                              : usuario.nombre.substring(0, 1).toUpperCase(),
                          style: TextStyle(
                            color: _primaryDark,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            usuario.nombre,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _primaryDark,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            usuario.correo,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _primaryDark.withValues(alpha: 0.65),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildRoleChip(usuario.rol),
                    const SizedBox(width: 16),
                    Container(
                      width: 1,
                      height: 36,
                      color: _primary.withValues(alpha: 0.12),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: infoWrap),
                    const SizedBox(width: 12),
                    actions,
                  ],
                ),
        );
      },
    );
  }

  Widget _buildInfoPill(IconData icon, String label, {double? maxWidth}) {
    final content = maxWidth == null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: _primaryDark),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: _primaryDark,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          )
        : ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 15, color: _primaryDark),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _primaryDark,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(999),
      ),
      child: content,
    );
  }

  Widget _buildRoleChip(String rol) {
    final esDocente = UserRoleAccess.isTeacherRole(rol);
    final esAdmin = UserRoleAccess.isAdminRole(rol);
    final esRrhh = UserRoleAccess.isRrhhRole(rol);
    final color = esDocente
        ? const Color(0xFF2F8F63)
        : esAdmin
        ? const Color(0xFF325CA8)
        : esRrhh
        ? const Color(0xFF7E3F98)
        : const Color(0xFF8A5A14);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        rol,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DIALOG
// ═══════════════════════════════════════════════════════════════════════════════

class _PersonalFormDialog extends StatefulWidget {
  const _PersonalFormDialog({
    required this.branding,
    required this.sedeId,
    required this.service,
    required this.areas,
    required this.horariosDocente,
    required this.horariosAdministrativo,
    this.usuario,
  });

  final AppBranding branding;
  final String sedeId;
  final FirebaseService service;
  final _PersonalView? usuario;
  final List<_AreaOption> areas;
  final List<_HorarioOption> horariosDocente;
  final List<_HorarioOption> horariosAdministrativo;

  @override
  State<_PersonalFormDialog> createState() => _PersonalFormDialogState();
}

class _PersonalFormDialogState extends State<_PersonalFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreController;
  late final TextEditingController _correoController;
  late final TextEditingController _cedulaController;
  late final TextEditingController _telefonoController;
  late final TextEditingController _passwordController;
  late final TextEditingController _cargoController;
  late final TextEditingController _horarioController;
  late final TextEditingController _cargoAcademicoSecundarioController;
  late final TextEditingController _horarioAcademicoSecundarioController;

  late String _areaId;
  late String _areaAcademicaSecundariaId;
  late String _horarioId;
  late String _rol;
  late bool _requiereGeolocalizacion;
  late bool _tieneVinculacionAcademicaSecundaria;
  bool _guardando = false;

  bool get _esEdicion => widget.usuario != null;
  List<_AreaOption> get _areasActivas =>
      widget.areas.where((area) => area.activa).toList();
  bool get _usaCatalogoFijoMatriz => widget.sedeId == SedeAccess.matrizId;
  bool get _mostrarRolAdmin =>
      widget.sedeId == SedeAccess.matrizId || UserRoleAccess.isAdminRole(_rol);

  bool get _rolAcademicoSeleccionado => UserRoleAccess.isTeacherRole(_rol);
  bool get _rolAdministrativoSeleccionado =>
      UserRoleAccess.isAdministrativeRole(_rol);

  List<String> get _departamentosPermitidosPorRol {
    if (!_usaCatalogoFijoMatriz) {
      return const <String>[];
    }
    if (UserRoleAccess.isAdministrativeRole(_rol)) {
      return _matrizAdministrativeDepartments;
    }
    if (_rolAcademicoSeleccionado) {
      return _matrizAcademicDepartments;
    }
    return const <String>[];
  }

  List<_AreaOption> get _areasDisponibles {
    final areas = _areasActivas;
    final departamentos = _departamentosPermitidosPorRol;
    if (departamentos.isEmpty) {
      return areas;
    }

    final permitidos = departamentos.map(_normalizarTexto).toSet();

    return areas
        .where((area) => permitidos.contains(_normalizarTexto(area.nombre)))
        .toList();
  }

  List<_AreaOption> get _areasAcademicasDisponibles {
    final areas = _areasActivas;
    if (!_usaCatalogoFijoMatriz) {
      return areas;
    }

    final permitidos = _matrizAcademicDepartments.map(_normalizarTexto).toSet();
    return areas
        .where((area) => permitidos.contains(_normalizarTexto(area.nombre)))
        .toList();
  }

  List<_HorarioOption> get _opcionesHorario =>
      UserRoleAccess.isAdministrativeRole(_rol) ||
          UserRoleAccess.isAdminRole(_rol) ||
          UserRoleAccess.isRrhhRole(_rol)
      ? widget.horariosAdministrativo
      : widget.horariosDocente;

  String get _rolPersistente =>
      _rolAcademicoSeleccionado ? UserRoleAccess.roleTeacher : _rol;

  String _safeRolUiValue(String? value) {
    if (UserRoleAccess.isTeacherRole(value) || value == _roleAcademicUi) {
      return _roleAcademicUi;
    }
    if (UserRoleAccess.isAdministrativeRole(value)) {
      return UserRoleAccess.roleAdministrative;
    }
    if (UserRoleAccess.isRrhhRole(value)) {
      return UserRoleAccess.roleRrhh;
    }
    if (UserRoleAccess.isAdminRole(value)) {
      return UserRoleAccess.roleAdmin;
    }
    return _roleAcademicUi;
  }

  String _safeHorarioId(String candidato, List<_HorarioOption> opciones) {
    final limpio = candidato.trim();
    if (limpio.isNotEmpty) {
      return limpio;
    }
    return opciones.first.id;
  }

  String _safeAreaId(String? candidate) {
    final areasDisponibles = _areasDisponibles;
    if (areasDisponibles.isEmpty) {
      return '';
    }
    for (final area in areasDisponibles) {
      if (area.docId == candidate) {
        return area.docId;
      }
    }
    if (_usaCatalogoFijoMatriz) {
      final canonicalName = _canonicalMatrizDepartmentName(
        widget.usuario?.areaNombre ?? '',
      );
      final normalizedCanonical = _normalizeDepartmentKey(canonicalName);
      for (final area in areasDisponibles) {
        if (_normalizeDepartmentKey(area.nombre) == normalizedCanonical) {
          return area.docId;
        }
      }
    }
    return areasDisponibles.first.docId;
  }

  String _safeAcademicAreaId(String? candidate) {
    final areasDisponibles = _areasAcademicasDisponibles;
    if (areasDisponibles.isEmpty) {
      return '';
    }
    for (final area in areasDisponibles) {
      if (area.docId == candidate) {
        return area.docId;
      }
    }
    if (_usaCatalogoFijoMatriz) {
      final normalizedLegacy = _normalizeDepartmentKey(
        widget.usuario?.areaAcademicaSecundariaNombre ?? '',
      );
      for (final area in areasDisponibles) {
        if (_normalizeDepartmentKey(area.nombre) == normalizedLegacy) {
          return area.docId;
        }
      }
    }
    return areasDisponibles.first.docId;
  }

  String _normalizarTexto(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n');
  }

  _AreaOption? _findAreaById(String id) {
    for (final area in widget.areas) {
      if (area.docId == id) {
        return area;
      }
    }
    return null;
  }

  String _defaultCargoForRole() {
    if (_rolAcademicoSeleccionado) {
      return _roleAcademicUi;
    }
    if (UserRoleAccess.isAdministrativeRole(_rol)) {
      return 'Administrativo';
    }
    if (UserRoleAccess.isRrhhRole(_rol)) {
      return 'Analista RRHH';
    }
    return 'Administrador';
  }

  String _defaultCargoAcademicoSecundario() {
    return _roleAcademicUi;
  }

  String? _validarNumeroDiezDigitos(String? value, String campo) {
    final digits = _soloDigitos(value ?? '');
    if (digits.length != 10) {
      return 'Ingrese $campo de 10 digitos';
    }
    return null;
  }

  String _soloDigitos(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  @override
  void initState() {
    super.initState();
    final usuario = widget.usuario;
    _rol = _safeRolUiValue(usuario?.rol.toString());

    final candidato = usuario?.horarioId ?? _opcionesHorario.first.id;
    _horarioId = _safeHorarioId(candidato, _opcionesHorario);
    _areaId = _safeAreaId(usuario?.areaId);
    _tieneVinculacionAcademicaSecundaria =
        usuario?.tieneVinculacionAcademicaSecundaria == true &&
        _rolAdministrativoSeleccionado;
    _areaAcademicaSecundariaId = _safeAcademicAreaId(
      usuario?.areaAcademicaSecundariaId,
    );
    _requiereGeolocalizacion =
        usuario?.requiereGeolocalizacion ??
        _findAreaById(_areaId)?.requiereGeolocalizacionPorDefecto ??
        true;

    _nombreController = TextEditingController(text: usuario?.nombre ?? '');
    _correoController = TextEditingController(text: usuario?.correo ?? '');
    _cedulaController = TextEditingController(
      text: _soloDigitos(usuario?.cedula ?? ''),
    );
    _telefonoController = TextEditingController(
      text: _soloDigitos(usuario?.telefono ?? ''),
    );
    _passwordController = TextEditingController();
    _cargoController = TextEditingController(
      text: usuario?.cargo.isNotEmpty == true
          ? usuario!.cargo
          : (usuario?.especialidad.isNotEmpty == true
                ? usuario!.especialidad
                : _defaultCargoForRole()),
    );
    _cargoAcademicoSecundarioController = TextEditingController(
      text: usuario?.cargoAcademicoSecundario.trim().isNotEmpty == true
          ? usuario!.cargoAcademicoSecundario
          : _defaultCargoAcademicoSecundario(),
    );
    _horarioController = TextEditingController(text: _horarioId);
    _horarioAcademicoSecundarioController = TextEditingController(
      text: usuario?.horarioAcademicoSecundarioId.trim().isNotEmpty == true
          ? usuario!.horarioAcademicoSecundarioId
          : widget.horariosDocente.first.id,
    );
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _correoController.dispose();
    _cedulaController.dispose();
    _telefonoController.dispose();
    _passwordController.dispose();
    _cargoController.dispose();
    _horarioController.dispose();
    _cargoAcademicoSecundarioController.dispose();
    _horarioAcademicoSecundarioController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);

    try {
      final areaSeleccionada = _findAreaById(_areaId);
      if (areaSeleccionada == null) {
        throw Exception('Seleccione un departamento valido.');
      }

      await widget.service.guardarUsuarioPersonalSede(
        usuarioDocId: widget.usuario?.docId,
        nombre: _nombreController.text,
        correo: _correoController.text,
        cedula: _cedulaController.text,
        password: _passwordController.text,
        rol: _rolPersistente,
        sedeId: widget.sedeId,
        telefono: _telefonoController.text,
        horarioAsignadoId: _horarioId,
        areaId: areaSeleccionada.docId,
        areaNombre: areaSeleccionada.nombre,
        cargo: _cargoController.text,
        requiereGeolocalizacion: _requiereGeolocalizacion,
        tieneVinculacionAcademicaSecundaria:
            _rolAdministrativoSeleccionado &&
            _tieneVinculacionAcademicaSecundaria,
        horarioAcademicoSecundarioId:
            _rolAdministrativoSeleccionado &&
                _tieneVinculacionAcademicaSecundaria
            ? _horarioAcademicoSecundarioController.text
            : null,
        areaAcademicaSecundariaId:
            _rolAdministrativoSeleccionado &&
                _tieneVinculacionAcademicaSecundaria
            ? _areaAcademicaSecundariaId
            : null,
        areaAcademicaSecundariaNombre:
            _rolAdministrativoSeleccionado &&
                _tieneVinculacionAcademicaSecundaria
            ? (_findAreaById(_areaAcademicaSecundariaId)?.nombre ?? '')
            : null,
        cargoAcademicoSecundario:
            _rolAdministrativoSeleccionado &&
                _tieneVinculacionAcademicaSecundaria
            ? _cargoAcademicoSecundarioController.text
            : null,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar el usuario: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
      setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Container(
        width: 620,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _esEdicion ? 'Editar personal' : 'Nuevo personal',
                  style: TextStyle(
                    color: widget.branding.primaryDark,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sede: ${SedeAccess.displayNameForId(widget.sedeId)}',
                  style: TextStyle(
                    color: widget.branding.primaryDark.withValues(alpha: 0.70),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _fieldBox(
                      width: 270,
                      child: TextFormField(
                        controller: _nombreController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre completo',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Ingrese el nombre'
                            : null,
                      ),
                    ),
                    _fieldBox(
                      width: 270,
                      child: TextFormField(
                        controller: _correoController,
                        decoration: const InputDecoration(labelText: 'Correo'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Ingrese el correo'
                            : null,
                      ),
                    ),
                    _fieldBox(
                      width: 270,
                      child: TextFormField(
                        controller: _cedulaController,
                        keyboardType: TextInputType.number,
                        inputFormatters: _tenDigitInputFormatters,
                        decoration: const InputDecoration(labelText: 'Cedula'),
                        validator: (v) =>
                            _validarNumeroDiezDigitos(v, 'la cedula'),
                      ),
                    ),
                    _fieldBox(
                      width: 270,
                      child: DropdownButtonFormField<String>(
                        initialValue: _safeRolUiValue(_rol),
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Rol'),
                        items: [
                          const DropdownMenuItem(
                            value: _roleAcademicUi,
                            child: Text(
                              _roleAcademicUi,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const DropdownMenuItem(
                            value: 'Personal administrativo',
                            child: Text(
                              'Personal administrativo',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const DropdownMenuItem(
                            value: 'RRHH',
                            child: Text(
                              'RRHH',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_mostrarRolAdmin)
                            const DropdownMenuItem(
                              value: 'Admin',
                              child: Text(
                                'Admin',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _rol = value;
                            _areaId = _safeAreaId(_areaId);
                            if (!_rolAdministrativoSeleccionado) {
                              _tieneVinculacionAcademicaSecundaria = false;
                            }
                            _areaAcademicaSecundariaId = _safeAcademicAreaId(
                              _areaAcademicaSecundariaId,
                            );
                            _horarioId = _safeHorarioId(
                              _horarioId,
                              _opcionesHorario,
                            );
                            _horarioController.text = _horarioId;
                            final area = _findAreaById(_areaId);
                            if (area != null) {
                              _requiereGeolocalizacion =
                                  area.requiereGeolocalizacionPorDefecto;
                            }
                            if (_cargoController.text.trim().isEmpty) {
                              _cargoController.text = _defaultCargoForRole();
                            }
                          });
                        },
                      ),
                    ),
                    _fieldBox(
                      width: 270,
                      child: TextFormField(
                        controller: _telefonoController,
                        keyboardType: TextInputType.number,
                        inputFormatters: _tenDigitInputFormatters,
                        decoration: const InputDecoration(
                          labelText: 'Telefono',
                        ),
                        validator: (v) =>
                            _validarNumeroDiezDigitos(v, 'el telefono'),
                      ),
                    ),
                    _fieldBox(
                      width: 270,
                      child: TextFormField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: _esEdicion
                              ? 'Nueva contraseña (opcional)'
                              : 'Contraseña',
                        ),
                        validator: (v) {
                          if (_esEdicion) return null;
                          if (v == null || v.trim().isEmpty) {
                            return 'Ingrese la contraseña';
                          }
                          return null;
                        },
                      ),
                    ),
                    _fieldBox(
                      width: 556,
                      child: DropdownButtonFormField<String>(
                        initialValue: _areaId.isEmpty ? null : _areaId,
                        isExpanded: true,
                        itemHeight: null,
                        menuMaxHeight: 320,
                        decoration: const InputDecoration(
                          labelText: 'Departamento',
                        ),
                        selectedItemBuilder: (context) => _areasDisponibles
                            .map(
                              (area) => Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  area.nombre,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        items: _areasDisponibles
                            .map(
                              (area) => DropdownMenuItem<String>(
                                value: area.docId,
                                child: SizedBox(
                                  width: 360,
                                  child: Text(
                                    area.nombre,
                                    maxLines: 3,
                                    softWrap: true,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          final area = _findAreaById(value);
                          setState(() {
                            _areaId = value;
                            if (area != null) {
                              _requiereGeolocalizacion =
                                  area.requiereGeolocalizacionPorDefecto;
                            }
                          });
                        },
                        validator: (value) => (value == null || value.isEmpty)
                            ? 'Seleccione un departamento'
                            : null,
                      ),
                    ),
                    _fieldBox(
                      width: 270,
                      child: TextFormField(
                        controller: _cargoController,
                        decoration: const InputDecoration(labelText: 'Cargo'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Ingrese el cargo'
                            : null,
                      ),
                    ),

                    // ── CAMPO MANUAL de horario con fondo sombreado ──
                    if (_rolAdministrativoSeleccionado)
                      _fieldBox(
                        width: 556,
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _tieneVinculacionAcademicaSecundaria,
                          title: const Text(
                            'Tambien tiene jornada de personal academico',
                          ),
                          subtitle: const Text(
                            'Activa un segundo horario para registrar asistencia y calcular la jornada academica.',
                          ),
                          activeThumbColor: widget.branding.primary,
                          onChanged: (value) {
                            setState(() {
                              _tieneVinculacionAcademicaSecundaria = value;
                              _areaAcademicaSecundariaId = _safeAcademicAreaId(
                                _areaAcademicaSecundariaId,
                              );
                              if (_cargoAcademicoSecundarioController.text
                                  .trim()
                                  .isEmpty) {
                                _cargoAcademicoSecundarioController.text =
                                    _defaultCargoAcademicoSecundario();
                              }
                              if (_horarioAcademicoSecundarioController.text
                                  .trim()
                                  .isEmpty) {
                                _horarioAcademicoSecundarioController.text =
                                    widget.horariosDocente.first.id;
                              }
                            });
                          },
                        ),
                      ),
                    if (_rolAdministrativoSeleccionado &&
                        _tieneVinculacionAcademicaSecundaria)
                      _fieldBox(
                        width: 556,
                        child: DropdownButtonFormField<String>(
                          initialValue: _areaAcademicaSecundariaId.isEmpty
                              ? null
                              : _areaAcademicaSecundariaId,
                          isExpanded: true,
                          itemHeight: null,
                          menuMaxHeight: 320,
                          decoration: const InputDecoration(
                            labelText: 'Departamento academico',
                          ),
                          selectedItemBuilder: (context) =>
                              _areasAcademicasDisponibles
                                  .map(
                                    (area) => Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        area.nombre,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                          items: _areasAcademicasDisponibles
                              .map(
                                (area) => DropdownMenuItem<String>(
                                  value: area.docId,
                                  child: SizedBox(
                                    width: 360,
                                    child: Text(
                                      area.nombre,
                                      maxLines: 3,
                                      softWrap: true,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _areaAcademicaSecundariaId = value;
                            });
                          },
                          validator: (value) {
                            if (!_tieneVinculacionAcademicaSecundaria) {
                              return null;
                            }
                            return (value == null || value.isEmpty)
                                ? 'Seleccione el departamento academico'
                                : null;
                          },
                        ),
                      ),
                    if (_rolAdministrativoSeleccionado &&
                        _tieneVinculacionAcademicaSecundaria)
                      _fieldBox(
                        width: 270,
                        child: TextFormField(
                          controller: _cargoAcademicoSecundarioController,
                          decoration: const InputDecoration(
                            labelText: 'Cargo academico',
                          ),
                          validator: (v) {
                            if (!_tieneVinculacionAcademicaSecundaria) {
                              return null;
                            }
                            return (v == null || v.trim().isEmpty)
                                ? 'Ingrese el cargo academico'
                                : null;
                          },
                        ),
                      ),
                    if (_rolAdministrativoSeleccionado &&
                        _tieneVinculacionAcademicaSecundaria)
                      _fieldBox(
                        width: 556,
                        child: TextFormField(
                          controller: _horarioAcademicoSecundarioController,
                          decoration: InputDecoration(
                            labelText: 'Horario academico secundario',
                            hintText: 'Ej: TP_08:00_12:00, NOCT_18:00_22:00...',
                            prefixIcon: const Icon(Icons.auto_stories_outlined),
                            filled: true,
                            fillColor: const Color(0xFFF3F7F5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: widget.branding.primary.withValues(
                                    alpha: 0.34,
                                  ),
                                ),
                            ),
                          ),
                          validator: (v) {
                            if (!_tieneVinculacionAcademicaSecundaria) {
                              return null;
                            }
                            return (v == null || v.trim().isEmpty)
                                ? 'Ingrese el horario academico secundario'
                                : null;
                          },
                        ),
                      ),
                    _fieldBox(
                      width: 556,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _horarioController,
                            decoration: InputDecoration(
                              labelText: 'Horario asignado',
                              hintText:
                                  'Ej: TC_08:00_16:45, TP_08:00_12:00, NOCT_18:00_22:00...',
                              prefixIcon: const Icon(Icons.schedule_outlined),
                              filled: true,
                              fillColor: const Color(0xFFE8F0ED),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: widget.branding.primary.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: widget.branding.primary.withValues(
                                    alpha: 0.42,
                                  ),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: widget.branding.primary,
                                  width: 1.8,
                                ),
                              ),
                            ),
                            onChanged: (value) {
                              setState(() => _horarioId = value.trim());
                            },
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Ingrese un horario'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _requiereGeolocalizacion,
                            title: const Text(
                              'Validar ubicacion al marcar asistencia',
                            ),
                            subtitle: Text(
                              _requiereGeolocalizacion
                                  ? 'Si, este usuario debe marcar dentro de la sede.'
                                  : 'No, este usuario puede marcar sin geolocalizacion hasta medianoche.',
                            ),
                            activeThumbColor: widget.branding.primary,
                            onChanged: (value) {
                              setState(() {
                                _requiereGeolocalizacion = value;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    // ─────────────────────────────────────────────────
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _guardando
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.branding.primaryDark,
                      ),
                      onPressed: _guardando ? null : _guardar,
                      icon: _guardando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_guardando ? 'Guardando...' : 'Guardar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldBox({required double width, required Widget child}) =>
      SizedBox(width: width, child: child);
}

class _AreasManagerDialog extends StatefulWidget {
  const _AreasManagerDialog({
    required this.branding,
    required this.sedeId,
    required this.service,
  });

  final AppBranding branding;
  final String sedeId;
  final FirebaseService service;

  @override
  State<_AreasManagerDialog> createState() => _AreasManagerDialogState();
}

class _AreasManagerDialogState extends State<_AreasManagerDialog> {
  late final TextEditingController _nombreController;
  bool _requiereGeoPorDefecto = true;
  bool _guardando = false;
  String? _errorNombreArea;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController();
    _nombreController.addListener(() {
      if (_errorNombreArea != null &&
          _nombreController.text.trim().isNotEmpty &&
          mounted) {
        setState(() => _errorNombreArea = null);
      }
    });
  }

  @override
  void dispose() {
    _nombreController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot> _buildAreasStream() {
    return FirebaseFirestore.instance
        .collection('areas')
        .where('sedeId', isEqualTo: widget.sedeId)
        .snapshots();
  }

  List<_AreaOption> _buildAreas(List<QueryDocumentSnapshot> docs) {
    final areas = <_AreaOption>[];
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (!SedeAccess.matchesSede(data, widget.sedeId)) {
        continue;
      }

      final nombre = (data['nombre'] ?? '').toString().trim();
      if (nombre.isEmpty) {
        continue;
      }

      areas.add(
        _AreaOption(
          docId: doc.id,
          nombre: nombre,
          requiereGeolocalizacionPorDefecto:
              widget.service.requiereGeolocalizacionAreaEfectiva(data),
          gpsTemporalDesactivadoHasta: widget.service
              .obtenerGpsTemporalDesactivadoHastaArea(data),
          activa: data['activa'] != false,
        ),
      );
    }

    areas.sort(
      (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
    );
    return areas;
  }

  Future<void> _guardarNuevaArea() async {
    final nombre = _nombreController.text.trim();
    if (nombre.isEmpty) {
      setState(() => _errorNombreArea = 'Ingrese el nombre del departamento.');
      return;
    }

    setState(() {
      _guardando = true;
      _errorNombreArea = null;
    });
    try {
      await widget.service.guardarAreaPersonalSede(
        sedeId: widget.sedeId,
        nombre: nombre,
        requiereGeolocalizacionPorDefecto: _requiereGeoPorDefecto,
      );
      _nombreController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Departamento guardado correctamente.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar el departamento: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  Future<void> _actualizarArea(
    _AreaOption area, {
    bool? activa,
    bool? requiereGeoPorDefecto,
  }) async {
    try {
      await widget.service.guardarAreaPersonalSede(
        areaDocId: area.docId,
        sedeId: widget.sedeId,
        nombre: area.nombre,
        requiereGeolocalizacionPorDefecto:
            requiereGeoPorDefecto ?? area.requiereGeolocalizacionPorDefecto,
        activa: activa ?? area.activa,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo actualizar el departamento: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // ignore: unused_element
  String _normalizarDepartamento(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n');
  }

  Future<void> _eliminarArea(_AreaOption area) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Eliminar departamento'),
        content: Text(
          'Se eliminara el departamento ${area.nombre}. Esta accion lo quitara del selector de personal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) {
      return;
    }

    try {
      await widget.service.eliminarAreaPersonalSede(
        areaDocId: area.docId,
        sedeId: widget.sedeId,
        nombre: area.nombre,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Departamento ${area.nombre} eliminado correctamente.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo eliminar el departamento: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Widget _buildAreaSwitch({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: widget.branding.primaryDark.withValues(alpha: 0.72),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Switch(
          value: value,
          activeThumbColor: widget.branding.primary,
          onChanged: onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Container(
        width: 760,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gestionar departamentos',
              style: TextStyle(
                color: widget.branding.primaryDark,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sede: ${SedeAccess.displayNameForId(widget.sedeId)}',
              style: TextStyle(
                color: widget.branding.primaryDark.withValues(alpha: 0.70),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 290,
                  child: TextField(
                    controller: _nombreController,
                    decoration: InputDecoration(
                      labelText: 'Nuevo departamento',
                      hintText: 'Ej: Marketing, Financiero, Compras...',
                      errorText: _errorNombreArea,
                    ),
                  ),
                ),
                SizedBox(
                  width: 250,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('GPS por defecto'),
                    subtitle: Text(_requiereGeoPorDefecto ? 'Si' : 'No'),
                    value: _requiereGeoPorDefecto,
                    activeThumbColor: widget.branding.primary,
                    onChanged: (value) {
                      setState(() => _requiereGeoPorDefecto = value);
                    },
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.branding.primaryDark,
                  ),
                  onPressed: _guardando ? null : _guardarNuevaArea,
                  icon: _guardando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add_circle_outline),
                  label: Text(
                    _guardando ? 'Guardando...' : 'Agregar departamento',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Flexible(
              child: StreamBuilder<QuerySnapshot>(
                stream: _buildAreasStream(),
                builder: (context, snapshot) {
                  final areas = _buildAreas(
                    snapshot.data?.docs ?? const <QueryDocumentSnapshot>[],
                  );

                  if (areas.isEmpty) {
                    return const Center(
                      child: Text(
                        'Todavia no hay departamentos registrados para esta sede.',
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: areas.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final area = areas[index];
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: widget.branding.surface.withValues(
                            alpha: 0.65,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: widget.branding.primary.withValues(
                              alpha: 0.24,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    area.nombre,
                                    style: TextStyle(
                                      color: widget.branding.primaryDark,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    area.requiereGeolocalizacionPorDefecto
                                        ? 'GPS por defecto: Si'
                                        : (area.gpsTemporalDesactivadoHasta !=
                                                  null
                                              ? 'GPS por defecto: No hasta media noche'
                                              : 'GPS por defecto: No'),
                                    style: TextStyle(
                                      color: widget.branding.primaryDark
                                          .withValues(alpha: 0.68),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Wrap(
                              spacing: 14,
                              children: [
                                _buildAreaSwitch(
                                  label: 'GPS',
                                  value: area.requiereGeolocalizacionPorDefecto,
                                  onChanged: (value) => _actualizarArea(
                                    area,
                                    requiereGeoPorDefecto: value,
                                  ),
                                ),
                                _buildAreaSwitch(
                                  label: 'Activa',
                                  value: area.activa,
                                  onChanged: (value) =>
                                      _actualizarArea(area, activa: value),
                                ),
                                IconButton(
                                  tooltip: 'Eliminar departamento',
                                  onPressed: () => _eliminarArea(area),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.redAccent,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Modelos internos
// ═══════════════════════════════════════════════════════════════════════════════

class _PersonalView {
  const _PersonalView({
    required this.docId,
    required this.nombre,
    required this.correo,
    required this.rol,
    required this.cedula,
    required this.telefono,
    required this.areaId,
    required this.areaNombre,
    required this.cargo,
    required this.especialidad,
    required this.horarioId,
    required this.tipoHorario,
    required this.requiereGeolocalizacion,
    this.gpsTemporalDesactivadoHasta,
    required this.tieneVinculacionAcademicaSecundaria,
    required this.horarioAcademicoSecundarioId,
    required this.areaAcademicaSecundariaId,
    required this.areaAcademicaSecundariaNombre,
    required this.cargoAcademicoSecundario,
  });

  final String docId;
  final String nombre;
  final String correo;
  final String rol;
  final String cedula;
  final String telefono;
  final String areaId;
  final String areaNombre;
  final String cargo;
  final String especialidad;
  final String horarioId;
  final String tipoHorario;
  final bool requiereGeolocalizacion;
  final DateTime? gpsTemporalDesactivadoHasta;
  final bool tieneVinculacionAcademicaSecundaria;
  final String horarioAcademicoSecundarioId;
  final String areaAcademicaSecundariaId;
  final String areaAcademicaSecundariaNombre;
  final String cargoAcademicoSecundario;
}

class _AreaOption {
  const _AreaOption({
    required this.docId,
    required this.nombre,
    required this.requiereGeolocalizacionPorDefecto,
    this.gpsTemporalDesactivadoHasta,
    required this.activa,
  });

  final String docId;
  final String nombre;
  final bool requiereGeolocalizacionPorDefecto;
  final DateTime? gpsTemporalDesactivadoHasta;
  final bool activa;
}

class _HorarioOption {
  const _HorarioOption(this.id, this.label);

  final String id;
  final String label;
}
