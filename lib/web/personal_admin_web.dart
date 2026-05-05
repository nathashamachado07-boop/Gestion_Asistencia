import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/app_branding.dart';
import '../services/firebase_service.dart';

class PersonalAdminWeb extends StatefulWidget {
  const PersonalAdminWeb({
    super.key,
    this.isSedeNorte = false,
    this.sedeId,
  });

  final bool isSedeNorte;
  final String? sedeId;

  @override
  State<PersonalAdminWeb> createState() => _PersonalAdminWebState();
}

class _PersonalAdminWebState extends State<PersonalAdminWeb> {
  final FirebaseService _service = FirebaseService();
  final TextEditingController _busquedaController = TextEditingController();
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

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
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

  List<_PersonalView> _buildUsuarios(List<QueryDocumentSnapshot> docs) {
    final items = <_PersonalView>[];

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (!SedeAccess.matchesSede(data, _resolvedSedeId) ||
          _esAdminGlobal(data) ||
          !_esPersonalGestionable(data)) {
        continue;
      }

      final horarios = (data['horarios_asignados'] as List?)
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
          rol: UserRoleAccess.displayRoleForUser(data),
          telefono: (data['telefono'] ?? '').toString(),
          especialidad: (data['especialidad'] ?? '').toString(),
          horarioId: horarioId,
          tipoHorario: (data['tipo_horario'] ?? '').toString(),
        ),
      );
    }

    items.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    return items;
  }

  List<_PersonalView> _filtrarUsuarios(List<_PersonalView> usuarios) {
    final query = _busquedaController.text.trim().toLowerCase();
    return usuarios.where((usuario) {
      final coincideRol =
          _filtroRol == 'Todos' || usuario.rol.toLowerCase() == _filtroRol.toLowerCase();
      final coincideTexto = query.isEmpty ||
          usuario.nombre.toLowerCase().contains(query) ||
          usuario.correo.toLowerCase().contains(query) ||
          usuario.telefono.toLowerCase().contains(query);
      return coincideRol && coincideTexto;
    }).toList();
  }

  String _labelHorario(String horarioId, String rol) {
    final opciones = UserRoleAccess.isAdministrativeRole(rol) ||
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

  Future<void> _abrirFormulario({_PersonalView? usuario}) async {
    final actualizado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PersonalFormDialog(
        branding: _branding,
        sedeId: _resolvedSedeId,
        service: _service,
        usuario: usuario,
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
        SnackBar(content: Text('${usuario.nombre} fue eliminado correctamente.')),
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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _primaryDark,
        foregroundColor: Colors.white,
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Nuevo personal'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_surface, Colors.white, _softAccent.withOpacity(0.40)],
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
                child: Image.asset(_branding.logoWatermark, width: 360, fit: BoxFit.contain),
              ),
            ),
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('usuarios').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final usuarios = _buildUsuarios(
                snapshot.data?.docs ?? const <QueryDocumentSnapshot>[],
              );
              final filtrados = _filtrarUsuarios(usuarios);
              final docentes =
                  usuarios.where((e) => e.rol.toLowerCase() == 'docente').length;
              final administrativos =
                  usuarios.where((e) => UserRoleAccess.isAdministrativeRole(e.rol)).length;
              final rrhh = usuarios.where((e) => UserRoleAccess.isRrhhRole(e.rol)).length;
              final admin = usuarios.where((e) => UserRoleAccess.isAdminRole(e.rol)).length;

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 96),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHero(),
                    const SizedBox(height: 22),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _buildStatCard('Total personal', usuarios.length, Icons.groups_2_outlined),
                        _buildStatCard('Docentes', docentes, Icons.school_outlined),
                        _buildStatCard('Personal administrativo', administrativos, Icons.badge_outlined),
                        _buildStatCard('RRHH', rrhh, Icons.manage_accounts_outlined),
                        _buildStatCard('Admin', admin, Icons.admin_panel_settings_outlined),
                      ],
                    ),
                    const SizedBox(height: 22),
                    _buildFiltersCard(),
                    const SizedBox(height: 22),
                    if (filtrados.isEmpty)
                      _buildEmptyState()
                    else
                      Column(
                        children: filtrados
                            .map((u) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _buildUserRow(u),
                                ))
                            .toList(),
                      ),
                  ],
                ),
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
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_primaryDark, _primary, _primary.withOpacity(0.88)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: _primary.withOpacity(0.18), blurRadius: 28, offset: const Offset(0, 14)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
            child: const Icon(Icons.manage_accounts_rounded, size: 34, color: Colors.white),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Gestion de personal por sede',
                  style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Administre docentes, personal administrativo, RRHH y Admin de ${SedeAccess.displayNameForId(_resolvedSedeId)}. Desde aqui puede crear, editar o eliminar usuarios sin mezclar informacion de otras sedes.',
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

  Widget _buildStatCard(String label, int value, IconData icon) {
    return Container(
      width: 238,
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _primary.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(color: _primary.withOpacity(0.08), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _softAccent.withOpacity(0.70),
              borderRadius: BorderRadius.circular(16),
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
                    color: _primaryDark.withOpacity(0.72),
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$value',
                  style: TextStyle(color: _primaryDark, fontSize: 30, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _primary.withOpacity(0.10)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 360,
            child: TextField(
              controller: _busquedaController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Buscar por nombre, correo o telefono',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: _surface.withOpacity(0.58),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 240,
            child: DropdownButtonFormField<String>(
              value: _filtroRol,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Rol',
                filled: true,
                fillColor: _surface.withOpacity(0.58),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'Todos', child: Text('Todos', overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: 'Docente', child: Text('Docente', overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(
                  value: 'Personal administrativo',
                  child: Text('Personal administrativo', overflow: TextOverflow.ellipsis),
                ),
                DropdownMenuItem(value: 'RRHH', child: Text('RRHH', overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: 'Admin', child: Text('Admin', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (value) => setState(() => _filtroRol = value ?? 'Todos'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _primary.withOpacity(0.10)),
      ),
      child: Column(
        children: [
          Icon(Icons.group_off_rounded, size: 54, color: _primary.withOpacity(0.60)),
          const SizedBox(height: 14),
          Text(
            'No hay usuarios para mostrar con los filtros actuales.',
            style: TextStyle(color: _primaryDark, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Pruebe con otra busqueda o cree un nuevo usuario para esta sede.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _primaryDark.withOpacity(0.72)),
          ),
        ],
      ),
    );
  }

  Widget _buildUserRow(_PersonalView usuario) {
    final rolEsDocente = UserRoleAccess.isTeacherRole(usuario.rol);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.98),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _primary.withOpacity(0.13), width: 1.2),
        boxShadow: [
          BoxShadow(color: _primary.withOpacity(0.07), blurRadius: 14, offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: _softAccent.withOpacity(0.84), shape: BoxShape.circle),
            child: Center(
              child: Text(
                usuario.nombre.isEmpty ? 'P' : usuario.nombre.substring(0, 1).toUpperCase(),
                style: TextStyle(color: _primaryDark, fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  usuario.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _primaryDark, fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  usuario.correo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _primaryDark.withOpacity(0.65),
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
          Container(width: 1, height: 36, color: _primary.withOpacity(0.12)),
          const SizedBox(width: 16),
          Expanded(
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _buildInfoPill(
                  Icons.phone_outlined,
                  usuario.telefono.isEmpty ? 'Sin telefono' : usuario.telefono,
                ),
                _buildInfoPill(
                  rolEsDocente
                      ? Icons.school_outlined
                      : UserRoleAccess.isAdminRole(usuario.rol)
                          ? Icons.admin_panel_settings_outlined
                          : UserRoleAccess.isRrhhRole(usuario.rol)
                              ? Icons.manage_accounts_outlined
                              : Icons.apartment_outlined,
                  usuario.especialidad.isEmpty ? 'Sin detalle' : usuario.especialidad,
                ),
                _buildInfoPill(
                  Icons.schedule_outlined,
                  _labelHorario(usuario.horarioId, usuario.rol),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: () => _abrirFormulario(usuario: usuario),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Editar'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _confirmarEliminacion(usuario),
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('Eliminar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _surface.withOpacity(0.70),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: _primaryDark),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: _primaryDark, fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ],
      ),
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
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        rol,
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
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
    required this.horariosDocente,
    required this.horariosAdministrativo,
    this.usuario,
  });

  final AppBranding branding;
  final String sedeId;
  final FirebaseService service;
  final _PersonalView? usuario;
  final List<_HorarioOption> horariosDocente;
  final List<_HorarioOption> horariosAdministrativo;

  @override
  State<_PersonalFormDialog> createState() => _PersonalFormDialogState();
}

class _PersonalFormDialogState extends State<_PersonalFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreController;
  late final TextEditingController _correoController;
  late final TextEditingController _telefonoController;
  late final TextEditingController _passwordController;
  late final TextEditingController _especialidadController;
  late final TextEditingController _horarioController;

  late String _horarioId;
  late String _rol;
  bool _guardando = false;

  bool get _esEdicion => widget.usuario != null;

  List<_HorarioOption> get _opcionesHorario =>
      UserRoleAccess.isAdministrativeRole(_rol) ||
              UserRoleAccess.isAdminRole(_rol) ||
              UserRoleAccess.isRrhhRole(_rol)
          ? widget.horariosAdministrativo
          : widget.horariosDocente;

  String _safeHorarioId(String candidato, List<_HorarioOption> opciones) {
    if (opciones.any((o) => o.id == candidato)) return candidato;
    return opciones.first.id;
  }

  @override
  void initState() {
    super.initState();
    final usuario = widget.usuario;
    _rol = UserRoleAccess.displayRole(usuario?.rol);

    final candidato = usuario?.horarioId ?? _opcionesHorario.first.id;
    _horarioId = _safeHorarioId(candidato, _opcionesHorario);

    _nombreController = TextEditingController(text: usuario?.nombre ?? '');
    _correoController = TextEditingController(text: usuario?.correo ?? '');
    _telefonoController = TextEditingController(text: usuario?.telefono ?? '');
    _passwordController = TextEditingController();
    _especialidadController = TextEditingController(text: usuario?.especialidad ?? '');
    _horarioController = TextEditingController(text: _horarioId);
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _correoController.dispose();
    _telefonoController.dispose();
    _passwordController.dispose();
    _especialidadController.dispose();
    _horarioController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);

    try {
      await widget.service.guardarUsuarioPersonalSede(
        usuarioDocId: widget.usuario?.docId,
        nombre: _nombreController.text,
        correo: _correoController.text,
        password: _passwordController.text,
        rol: _rol,
        sedeId: widget.sedeId,
        telefono: _telefonoController.text,
        especialidad: _especialidadController.text,
        horarioAsignadoId: _horarioId,
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
                    color: widget.branding.primaryDark.withOpacity(0.70),
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
                        decoration: const InputDecoration(labelText: 'Nombre completo'),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Ingrese el nombre' : null,
                      ),
                    ),
                    _fieldBox(
                      width: 270,
                      child: TextFormField(
                        controller: _correoController,
                        decoration: const InputDecoration(labelText: 'Correo'),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Ingrese el correo' : null,
                      ),
                    ),
                    _fieldBox(
                      width: 270,
                      child: DropdownButtonFormField<String>(
                        value: _rol,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Rol'),
                        items: const [
                          DropdownMenuItem(
                            value: 'Docente',
                            child: Text('Docente', overflow: TextOverflow.ellipsis),
                          ),
                          DropdownMenuItem(
                            value: 'Personal administrativo',
                            child: Text('Personal administrativo',
                                overflow: TextOverflow.ellipsis),
                          ),
                          DropdownMenuItem(
                            value: 'RRHH',
                            child: Text('RRHH', overflow: TextOverflow.ellipsis),
                          ),
                          DropdownMenuItem(
                            value: 'Admin',
                            child: Text('Admin', overflow: TextOverflow.ellipsis),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _rol = value;
                            _horarioId = _safeHorarioId(_horarioId, _opcionesHorario);
                            _horarioController.text = _horarioId;
                          });
                        },
                      ),
                    ),
                    _fieldBox(
                      width: 270,
                      child: TextFormField(
                        controller: _telefonoController,
                        decoration: const InputDecoration(labelText: 'Telefono'),
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
                          if (v == null || v.trim().isEmpty) return 'Ingrese la contraseña';
                          return null;
                        },
                      ),
                    ),
                    _fieldBox(
                      width: 270,
                      child: TextFormField(
                        controller: _especialidadController,
                        decoration: InputDecoration(
                          labelText: UserRoleAccess.isAdministrativeRole(_rol) ||
                                  UserRoleAccess.isAdminRole(_rol) ||
                                  UserRoleAccess.isRrhhRole(_rol)
                              ? 'Area o cargo'
                              : 'Especialidad',
                        ),
                      ),
                    ),

                    // ── CAMPO MANUAL de horario con fondo sombreado ──
                    _fieldBox(
                      width: 556,
                      child: TextFormField(
                        controller: _horarioController,
                        decoration: InputDecoration(
                          labelText: 'Horario asignado',
                          hintText: 'Ej: TC_08:00_16:45, TP_08:00_12:00, NOCT_18:00_22:00...',
                          prefixIcon: const Icon(Icons.schedule_outlined),
                          filled: true,
                          fillColor: const Color(0xFFE8F0ED),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: widget.branding.primary.withOpacity(0.35),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: widget.branding.primary.withOpacity(0.30),
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
                        validator: (v) =>
                            (v == null || v.trim().isEmpty)
                                ? 'Ingrese un horario'
                                : null,
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
                      onPressed: _guardando ? null : () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: widget.branding.primaryDark),
                      onPressed: _guardando ? null : _guardar,
                      icon: _guardando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.2, color: Colors.white),
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

// ═══════════════════════════════════════════════════════════════════════════════
// Modelos internos
// ═══════════════════════════════════════════════════════════════════════════════

class _PersonalView {
  const _PersonalView({
    required this.docId,
    required this.nombre,
    required this.correo,
    required this.rol,
    required this.telefono,
    required this.especialidad,
    required this.horarioId,
    required this.tipoHorario,
  });

  final String docId;
  final String nombre;
  final String correo;
  final String rol;
  final String telefono;
  final String especialidad;
  final String horarioId;
  final String tipoHorario;
}

class _HorarioOption {
  const _HorarioOption(this.id, this.label);

  final String id;
  final String label;
}