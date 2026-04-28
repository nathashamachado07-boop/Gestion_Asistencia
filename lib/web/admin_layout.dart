import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/app_branding.dart';
import '../services/firebase_service.dart';
import 'dashboard_admin_web.dart';
import 'dashboard_princesa_gales_norte_web.dart';
import 'estadisticas_admin_web.dart';
import 'gestion_personal_web.dart';
import 'almuerzos_admin_web.dart';
import 'almuerzo_horarios_admin_web.dart';
import 'personal_admin_web.dart';
import 'browser_notification_stub.dart'
    if (dart.library.html) 'browser_notification_web.dart' as browser_notification;
import 'reportes_admin_web_stub.dart'
    if (dart.library.html) 'reportes_admin_web.dart';

class AdminLayout extends StatefulWidget {
  const AdminLayout({
    super.key,
    this.userData,
  });

  final Map<String, dynamic>? userData;

  @override
  State<AdminLayout> createState() => _AdminLayoutState();
}

class _AdminLayoutState extends State<AdminLayout> {
  int _selectedIndex = 0;
  late Map<String, dynamic>? _userData;
  final FirebaseService _service = FirebaseService();
  bool _creandoDatosDemoSede = false;
  bool _sidebarCollapsed = false;
  String? _sedeVistaForzadaId;
  StreamSubscription<QuerySnapshot>? _solicitudesSubscription;
  final Set<String> _solicitudesConocidas = <String>{};
  final List<_AdminNotificationItem> _notificaciones = <_AdminNotificationItem>[];
  int _notificacionesNuevas = 0;
  String _browserNotificationPermission = 'default';
  bool _listenerSolicitudesInicializado = false;

  static const Color _defaultBase = Color(0xFF467879);
  static const Color _defaultSidebar = Color(0xFF467879);
  static const Color _defaultHeader = Color(0xFF2D4D4E);

  // ── Cre Ser brand colors (white sidebar, blue accents) ──────────────────
  static const Color _creSerBlue = Color(0xFF2B6FB5);
  static const Color _creSerBlueDark = Color(0xFF1A4F8A);

  @override
  void initState() {
    super.initState();
    _userData = widget.userData == null
        ? null
        : Map<String, dynamic>.from(widget.userData!);
    _inicializarNotificacionesWeb();
    _escucharSolicitudesPendientes();
  }

  @override
  void dispose() {
    _solicitudesSubscription?.cancel();
    super.dispose();
  }

  String get _nombreUsuario {
    return UserRoleAccess.displayNameForUser(_userData);
  }

  String get _usuarioSedeId => _userData == null
      ? SedeAccess.matrizId
      : SedeAccess.resolveSedeId(_userData!);

  List<String> get _sedesPermitidasUsuario =>
      MatrizApprovalFlow.allowedSedeIdsForUser(_userData);

  bool get _puedeCambiarSede => _sedesPermitidasUsuario.length > 1;

  String get _sedeActivaId {
    final sedePreferida = _sedeVistaForzadaId ?? _usuarioSedeId;
    if (_sedesPermitidasUsuario.contains(sedePreferida)) {
      return sedePreferida;
    }
    return _sedesPermitidasUsuario.first;
  }

  bool get _mostrarDashboardSede => _sedeActivaId != SedeAccess.matrizId;

  // ── Helper: is the active sede Cre Ser? ─────────────────────────────────
  bool get _isCreSer => _sedeActivaId == SedeAccess.sedeCreSerId;

  AppBranding get _brandingActiva => AppBranding.fromSedeId(_sedeActivaId);

  String get _sedeUsuario => SedeAccess.displayNameForId(_sedeActivaId);

  Color get miColorBase => _mostrarDashboardSede
      ? _brandingActiva.primary
      : _defaultBase;

  // ── Sidebar is WHITE for Cre Ser, brand color otherwise ─────────────────
  Color get sidebarColor => _isCreSer
      ? Colors.white
      : (_mostrarDashboardSede ? _brandingActiva.primary : _defaultSidebar);

  // ── Header inside the sidebar: light blue tint for Cre Ser ───────────────
  Color get headerColor => _isCreSer
      ? const Color(0xFFE8F1FB)
      : (_mostrarDashboardSede ? _brandingActiva.primaryDark : _defaultHeader);

  double get _sidebarHeaderHeight => _sidebarCollapsed ? 154 : (_isCreSer ? 400 : 348);
  // ── Larger logo height for Cre Ser ───────────────────────────────────────
  double get _sidebarLogoHeight => _sidebarCollapsed ? 46 : (_isCreSer ? 160 : 108);

  List<Widget> get _dashboards => [
        _mostrarDashboardSede
            ? DashboardPrincesaGalesNorteWeb(
                sedeId: _sedeActivaId,
                branding: _brandingActiva,
                nombreUsuario: _nombreUsuario,
                showBrandLogo: true,
                onCreateDemoData: _crearDatosDemoSedeActiva,
                isCreatingDemoData: _creandoDatosDemoSede,
              )
            : const DashboardAdminWeb(),
        EstadisticasAdminWeb(sedeId: _sedeActivaId),
        ReportesAdminWeb(sedeId: _sedeActivaId),
        GestionPersonalWeb(
          sedeId: _sedeActivaId,
          userData: _userData,
        ),
        AlmuerzosAdminWeb(sedeId: _sedeActivaId),
        AlmuerzoHorariosAdminWeb(sedeId: _sedeActivaId),
        PersonalAdminWeb(sedeId: _sedeActivaId),
      ];

  Future<void> _crearDatosDemoSedeActiva() async {
    if (_creandoDatosDemoSede) return;

    setState(() => _creandoDatosDemoSede = true);

    try {
      if (_sedeActivaId == SedeAccess.sedeNorteId) {
        await _service.crearDatosDemoSedeNorte();
        await _service.crearUsuariosDemoAppNorte();
      } else if (_sedeActivaId == SedeAccess.sedeCentroId) {
        await _service.crearDatosDemoSedeCentro();
        await _service.crearUsuariosDemoAppCentro();
      } else if (_sedeActivaId == SedeAccess.sedeCreSerId) {
        await _service.crearDatosDemoSedeCreSer();
        await _service.crearUsuariosDemoAppCreSer();
      } else {
        throw Exception('Selecciona una sede distinta a Matriz para crear demos.');
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Se crearon las credenciales demo de ${SedeAccess.displayNameForId(_sedeActivaId)}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudieron crear los datos demo: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _creandoDatosDemoSede = false);
      }
    }
  }

  void _cambiarSedeVista(String sedeId) {
    if (!_sedesPermitidasUsuario.contains(sedeId)) {
      return;
    }
    setState(() {
      _sedeVistaForzadaId = sedeId == _usuarioSedeId ? null : sedeId;
      _selectedIndex = 0;
    });
  }

  void _irAPaginaPrincipal() {
    if (_selectedIndex == 0) return;
    setState(() => _selectedIndex = 0);
  }

  void _toggleSidebar() {
    setState(() => _sidebarCollapsed = !_sidebarCollapsed);
  }

  Future<void> _inicializarNotificacionesWeb() async {
    final permission = await browser_notification.browserNotificationPermission();
    if (!mounted) return;
    setState(() => _browserNotificationPermission = permission);

    if (permission == 'default') {
      final nuevaPermission =
          await browser_notification.requestBrowserNotificationPermission();
      if (!mounted) return;
      setState(() => _browserNotificationPermission = nuevaPermission);
    }
  }

  void _escucharSolicitudesPendientes() {
    _solicitudesSubscription?.cancel();
    _solicitudesSubscription = FirebaseFirestore.instance
        .collection('avisos')
        .orderBy('timestamp', descending: true)
        .limit(30)
        .snapshots()
        .listen(_procesarSnapshotSolicitudesPendientes);
  }

  void _procesarSnapshotSolicitudesPendientes(QuerySnapshot snapshot) {
    if (!_listenerSolicitudesInicializado) {
      final visibles = snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return _esAvisoVisibleParaUsuario(data);
      }).toList();

      _solicitudesConocidas
        ..clear()
        ..addAll(visibles.map((doc) => doc.id));
      _notificaciones
        ..clear()
        ..addAll(
          visibles.take(8).map(
            (doc) => _mapNotificationItem(
              doc.id,
              doc.data() as Map<String, dynamic>,
            ),
          ),
        );
      _listenerSolicitudesInicializado = true;
      return;
    }

    final nuevasSolicitudes = snapshot.docChanges
        .where(
          (change) =>
              change.type == DocumentChangeType.added ||
              change.type == DocumentChangeType.modified,
        )
        .map((change) => change.doc)
        .where(
          (doc) {
            final data = doc.data() as Map<String, dynamic>;
            return _esAvisoVisibleParaUsuario(data) &&
                !_solicitudesConocidas.contains(doc.id);
          },
        )
        .toList();

    for (final doc in nuevasSolicitudes) {
      _solicitudesConocidas.add(doc.id);
      final data = doc.data() as Map<String, dynamic>;
      _registrarNotificacionSolicitud(doc.id, data);
    }

    final idsPendientes = snapshot.docs
        .where(
          (doc) => _esAvisoVisibleParaUsuario(doc.data() as Map<String, dynamic>),
        )
        .map((doc) => doc.id)
        .toSet();
    _solicitudesConocidas.removeWhere((id) => !idsPendientes.contains(id));
  }

  bool _esAvisoVisibleParaUsuario(Map<String, dynamic> data) {
    final destinatario = MatrizApprovalFlow.normalizeEmail(
      data['destinatarioCorreo'],
    );
    final correoActual = MatrizApprovalFlow.normalizeEmail(_userData?['correo']);
    if (destinatario.isNotEmpty) {
      return destinatario == correoActual;
    }

    final sedeId = SedeAccess.resolveSedeId(data);
    return _sedesPermitidasUsuario.contains(sedeId);
  }

  _AdminNotificationItem _mapNotificationItem(
    String id,
    Map<String, dynamic> data,
  ) {
    final title = (data['titulo'] ?? 'Nueva notificacion').toString().trim();
    final body = (data['mensaje'] ?? 'Tienes una novedad nueva.')
        .toString()
        .trim();
    final routeKey = (data['accionRuta'] ?? 'gestion').toString().trim();
    final timestamp = data['timestamp'];
    final createdAt =
        timestamp is Timestamp ? timestamp.toDate() : DateTime.now();

    return _AdminNotificationItem(
      id: id,
      title: title.isEmpty ? 'Nueva notificacion' : title,
      body: body.isEmpty ? 'Tienes una novedad nueva.' : body,
      routeKey: routeKey.isEmpty ? 'gestion' : routeKey,
      createdAt: createdAt,
    );
  }

  void _registrarNotificacionSolicitud(String id, Map<String, dynamic> data) {
    if (!_esAvisoVisibleParaUsuario(data)) {
      return;
    }

    /*
        ? '$colaborador • $tipo • $sedeLabel'
        : '$colaborador • $tipo • $sedeLabel\nMotivo: $motivo';
    */
    final item = _mapNotificationItem(id, data);
    if (mounted) {
      setState(() {
        _notificaciones.removeWhere((existing) => existing.id == id);
        _notificaciones.insert(0, item);
        if (_notificaciones.length > 8) {
          _notificaciones.removeRange(8, _notificaciones.length);
        }
        _notificacionesNuevas += 1;
      });
    } else {
      _notificaciones.removeWhere((existing) => existing.id == id);
      _notificaciones.insert(0, item);
      if (_notificaciones.length > 8) {
        _notificaciones.removeRange(8, _notificaciones.length);
      }
      _notificacionesNuevas += 1;
    }

    browser_notification.showBrowserNotification(
      title: item.title,
      body: item.body,
    );
  }

  Future<void> _habilitarNotificacionesNavegador() async {
    final permission =
        await browser_notification.requestBrowserNotificationPermission();
    if (!mounted) return;
    setState(() => _browserNotificationPermission = permission);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          permission == 'granted'
              ? 'Notificaciones del navegador activadas.'
              : 'No se pudieron activar las notificaciones del navegador.',
        ),
      ),
    );
  }

  void _marcarNotificacionesComoLeidas() {
    if (_notificacionesNuevas == 0) return;
    setState(() => _notificacionesNuevas = 0);
  }

  void _abrirDesdeNotificacion(String value) {
    switch (value) {
      case 'habilitar_notificaciones':
        _habilitarNotificacionesNavegador();
        return;
      case 'estadisticas':
        setState(() => _selectedIndex = 1);
        return;
      case 'reportes':
        setState(() => _selectedIndex = 2);
        return;
      case 'gestion':
        setState(() => _selectedIndex = 3);
        return;
      case 'almuerzos':
        setState(() => _selectedIndex = 4);
        return;
      case 'almuerzo_horarios':
        setState(() => _selectedIndex = 5);
        return;
      case 'personal':
        setState(() => _selectedIndex = 6);
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!UserRoleAccess.canUseAdminPanel(_userData)) {
      return _buildAccessDenied(
        'Debes iniciar sesion como Admin o RRHH para entrar a este panel.',
      );
    }

    return Scaffold(
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: _sidebarCollapsed ? 94 : 260,
            // ── WHITE background for Cre Ser, brand color for others ──────
            color: sidebarColor,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        InkWell(
                          onTap: _irAPaginaPrincipal,
                          child: Container(
                            width: double.infinity,
                            height: _sidebarHeaderHeight,
                            padding: const EdgeInsets.symmetric(
                              vertical: 30,
                              horizontal: 10,
                            ),
                            decoration: BoxDecoration(
                              // ── Light blue tint header for Cre Ser ────────
                              color: headerColor,
                              border: Border(
                                bottom: BorderSide(
                                  color: _isCreSer
                                      ? _creSerBlue.withOpacity(0.15)
                                      : Colors.white10,
                                ),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // ── Cre Ser: show logo_cre_ser.png, large, no white card ──
                                if (_isCreSer)
                                  Image.asset(
                                    'assets/images/logo_cre_ser.png',
                                    height: _sidebarLogoHeight,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) =>
                                        Icon(
                                      Icons.school_outlined,
                                      color: _creSerBlue,
                                      size: _sidebarCollapsed ? 34 : 58,
                                    ),
                                  )
                                else
                                  Container(
                                    padding: EdgeInsets.all(
                                      _sedeActivaId == SedeAccess.sedeCreSerId
                                          ? 10
                                          : 0,
                                    ),
                                    decoration: _sedeActivaId == SedeAccess.sedeCreSerId
                                        ? BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(18),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.12),
                                                blurRadius: 16,
                                                offset: const Offset(0, 8),
                                              ),
                                            ],
                                          )
                                        : null,
                                    child: Image.asset(
                                      _brandingActiva.logoHeader,
                                      height: _sidebarLogoHeight,
                                      fit: BoxFit.contain,
                                      errorBuilder: (context, error, stackTrace) => Icon(
                                        _mostrarDashboardSede
                                            ? (_brandingActiva.isPrincesaDeGales
                                                ? Icons.spa_outlined
                                                : Icons.school_outlined)
                                            : Icons.account_balance,
                                        color: Colors.white,
                                        size: _sidebarCollapsed ? 34 : 58,
                                      ),
                                    ),
                                  ),
                                if (!_sidebarCollapsed) ...[
                                  const SizedBox(height: 15),
                                  Text(
                                    _brandingActiva.displayName,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      // ── Blue text for Cre Ser ────────────
                                      color: _isCreSer ? _creSerBlueDark : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: _sedeActivaId == SedeAccess.sedeCreSerId
                                          ? 17
                                          : 20,
                                      letterSpacing: _sedeActivaId ==
                                              SedeAccess.sedeCreSerId
                                          ? 0.6
                                          : 1.5,
                                    ),
                                  ),
                                  Text(
                                    _mostrarDashboardSede
                                        ? _brandingActiva.subtitle.toUpperCase()
                                        : 'Gestion de Reportes',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _isCreSer
                                          ? _creSerBlue.withOpacity(0.75)
                                          : Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _sedeUsuario,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _isCreSer
                                          ? _creSerBlue.withOpacity(0.60)
                                          : Colors.white60,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _isCreSer
                                          ? _creSerBlue.withOpacity(0.10)
                                          : Colors.white.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: _isCreSer
                                            ? _creSerBlue.withOpacity(0.25)
                                            : Colors.white12,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.home_outlined,
                                          color: _isCreSer ? _creSerBlue : Colors.white70,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Ir al inicio',
                                          style: TextStyle(
                                            color: _isCreSer ? _creSerBlue : Colors.white70,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else ...[
                                  const SizedBox(height: 12),
                                  Icon(
                                    Icons.home_outlined,
                                    color: _isCreSer ? _creSerBlue : Colors.white70,
                                    size: 20,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_sidebarCollapsed) ...[
                          _compactMenuItem(
                            0,
                            Icons.dashboard_customize_outlined,
                            'Menu General',
                          ),
                          _compactMenuItem(
                            1,
                            Icons.analytics_outlined,
                            'Estadisticas',
                          ),
                          _compactMenuItem(
                            2,
                            Icons.file_copy_outlined,
                            'Reportes de Asistencia',
                          ),
                          _compactMenuItem(
                            3,
                            Icons.group_outlined,
                            'Gestion de solicitudes',
                          ),
                          _compactMenuItem(
                            4,
                            Icons.restaurant_menu_outlined,
                            'Registros de Almuerzo',
                          ),
                          _compactMenuItem(
                            5,
                            Icons.schedule_rounded,
                            'Asignar Horarios de Almuerzo',
                          ),
                          _compactMenuItem(
                            6,
                            Icons.manage_accounts_outlined,
                            'Gestion de personal',
                          ),
                        ] else ...[
                          _menuItem(
                            0,
                            Icons.dashboard_customize_outlined,
                            'Menu General',
                          ),
                          Theme(
                            data: Theme.of(context).copyWith(
                              dividerColor: Colors.transparent,
                              // ── Cre Ser: blue unselected icon/chevron ────
                              unselectedWidgetColor: _isCreSer
                                  ? _creSerBlue.withOpacity(0.60)
                                  : Colors.white60,
                            ),
                            child: ExpansionTile(
                              initiallyExpanded: _selectedIndex != 0,
                              leading: Icon(
                                Icons.apps_outlined,
                                color: _isCreSer ? _creSerBlue : Colors.white,
                                size: 22,
                              ),
                              title: Text(
                                'Aplicacion de Asistencia',
                                style: TextStyle(
                                  color: _isCreSer ? _creSerBlueDark : Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              iconColor: _isCreSer ? _creSerBlue : Colors.white,
                              collapsedIconColor: _isCreSer ? _creSerBlue : Colors.white,
                              children: [
                                _subMenuItem(
                                  1,
                                  Icons.analytics_outlined,
                                  'Estadisticas',
                                ),
                                _subMenuItem(
                                  2,
                                  Icons.file_copy_outlined,
                                  'Reportes de Asistencia',
                                ),
                                _subMenuItem(
                                  3,
                                  Icons.group_outlined,
                                  'Gestion de solicitudes',
                                ),
                              ],
                            ),
                          ),
                          _menuItem(
                            4,
                            Icons.restaurant_menu_outlined,
                            'Registros de Almuerzo',
                          ),
                          _menuItem(
                            5,
                            Icons.schedule_rounded,
                            'Asignar Horarios de Almuerzo',
                          ),
                          _menuItem(
                            6,
                            Icons.manage_accounts_outlined,
                            'Gestion de personal',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text(
                    _sidebarCollapsed ? 'v1.0.2' : 'v1.0.2 - 2026',
                    style: TextStyle(
                      color: _isCreSer
                          ? _creSerBlue.withOpacity(0.40)
                          : Colors.white38,
                      fontSize: 10,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 65,
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 5,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: _sidebarCollapsed
                                    ? 'Mostrar menu lateral'
                                    : 'Ocultar menu lateral',
                                onPressed: _toggleSidebar,
                                icon: Icon(
                                  _sidebarCollapsed
                                      ? Icons.menu_rounded
                                      : Icons.menu_open,
                                  color: miColorBase,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 20),
                              Text(
                                _getSectionTitle(),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              if (_userData != null && _puedeCambiarSede) ...[
                                const SizedBox(width: 16),
                                PopupMenuButton<String>(
                                  tooltip: 'Cambiar sede',
                                  initialValue: _sedeActivaId,
                                  offset: const Offset(0, 46),
                                  onSelected: _cambiarSedeVista,
                                  itemBuilder: (context) => _sedesPermitidasUsuario
                                      .map(
                                        (sedeId) => _buildSedeMenuItem(
                                          sedeId: sedeId,
                                          icon: _iconForSede(sedeId),
                                        ),
                                      )
                                      .toList(),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: miColorBase.withOpacity(0.2),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.swap_horiz_rounded,
                                          size: 18,
                                          color: miColorBase,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Cambiar sede',
                                          style: TextStyle(
                                            color: miColorBase,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              if (_selectedIndex != 0) ...[
                                const SizedBox(width: 16),
                                OutlinedButton.icon(
                                  onPressed: _irAPaginaPrincipal,
                                  icon: const Icon(Icons.home_outlined, size: 18),
                                  label: const Text('Pagina principal'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: miColorBase,
                                    side: BorderSide(
                                      color: miColorBase.withOpacity(0.2),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      _buildNotificationButton(),
                      const SizedBox(width: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: miColorBase.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: miColorBase,
                              child: const Icon(
                                Icons.person,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _nombreUsuario,
                              style: TextStyle(
                                color: miColorBase,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 15),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pushReplacementNamed(context, '/login');
                        },
                        icon: const Icon(
                          Icons.logout,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        label: const Text(
                          'Cerrar Sesion',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          backgroundColor: Colors.redAccent.withOpacity(0.05),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: const Color(0xFFF4F6F9),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _dashboards[_selectedIndex],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessDenied(String message) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                color: Colors.redAccent,
                size: 52,
              ),
              const SizedBox(height: 16),
              const Text(
                'Acceso restringido',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/login');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: miColorBase,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Volver al login'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationButton() {
    return PopupMenuButton<String>(
      tooltip: 'Notificaciones',
      offset: const Offset(0, 46),
      onOpened: _marcarNotificacionesComoLeidas,
      onSelected: _abrirDesdeNotificacion,
      itemBuilder: (context) {
        final entries = <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          enabled: false,
          value: 'titulo',
          child: Text(
            'Centro de notificaciones',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const PopupMenuDivider(),
        if (_browserNotificationPermission != 'granted')
          PopupMenuItem<String>(
            value: 'habilitar_notificaciones',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.notifications_active_outlined,
                color: miColorBase,
              ),
              title: const Text('Activar notificaciones'),
              subtitle: Text(
                _browserNotificationPermission == 'denied'
                    ? 'El navegador las tiene bloqueadas'
                    : 'Permite avisos en tu computadora',
              ),
            ),
          ),
        if (_browserNotificationPermission != 'granted')
          const PopupMenuDivider(),
        if (_notificaciones.isEmpty)
          const PopupMenuItem<String>(
            enabled: false,
            value: 'sin_novedades',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.notifications_off_outlined),
              title: Text('Sin notificaciones nuevas'),
              subtitle: Text('Cuando llegue una solicitud aparecerá aquí'),
            ),
          )
        else
          ..._notificaciones.take(3).map(
            (item) => PopupMenuItem<String>(
              value: item.routeKey,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.markunread_mailbox_outlined,
                  color: miColorBase,
                ),
                title: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  item.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'estadisticas',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.analytics_outlined),
            title: Text('Ver estadisticas'),
            subtitle: Text('Revisa el resumen del dia'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'reportes',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.file_copy_outlined),
            title: Text('Abrir reportes'),
            subtitle: Text('Consulta atrasos y asistencias'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'gestion',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.group_outlined),
            title: Text('Ir a gestion de solicitudes'),
            subtitle: Text('Revisa solicitudes pendientes'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'almuerzos',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.restaurant_menu_outlined),
            title: Text('Abrir almuerzos'),
            subtitle: Text('Consulta salidas y regresos'),
          ),
        ),
      ];
        return entries;
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: null,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: miColorBase.withOpacity(0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: miColorBase.withOpacity(0.24),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.notifications_none_rounded,
                color: miColorBase,
                size: 22,
              ),
              if (_notificacionesNuevas > 0)
                Positioned(
                  right: 4,
                  top: 3,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _notificacionesNuevas > 9
                            ? '9+'
                            : _notificacionesNuevas.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  String _getSectionTitle() {
    switch (_selectedIndex) {
      case 0:
        return _mostrarDashboardSede
            ? 'Panel - ${SedeAccess.displayNameForId(_sedeActivaId)}'
            : 'Panel de Control General';
      case 1:
        return 'Analisis Estadistico';
      case 2:
        return 'Reportes de Asistencia Mensual';
      case 3:
        return 'Gestion de solicitudes';
      case 4:
        return 'Registros de Almuerzo';
      case 5:
        return 'Asignar Horarios de Almuerzo';
      case 6:
        return 'Gestion de personal';
      default:
        return 'Sistema INTESUD';
    }
  }

  Widget _menuItem(int index, IconData icon, String title) {
    final isSelected = _selectedIndex == index;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        // ── Cre Ser selected: blue fill; unselected: transparent ────────
        color: isSelected
            ? (_isCreSer ? _creSerBlue : Colors.white)
            : Colors.transparent,
      ),
      child: ListTile(
        onTap: () => setState(() => _selectedIndex = index),
        leading: Icon(
          icon,
          // ── Cre Ser: selected = white icon on blue; unselected = blue icon
          color: isSelected
              ? (_isCreSer ? Colors.white : miColorBase)
              : (_isCreSer ? _creSerBlue : Colors.white),
          size: 22,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected
                ? (_isCreSer ? Colors.white : miColorBase)
                : (_isCreSer ? _creSerBlueDark : Colors.white),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _subMenuItem(int index, IconData icon, String title) {
    final isSelected = _selectedIndex == index;
    return Container(
      margin: const EdgeInsets.only(left: 30, right: 12, top: 2, bottom: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: isSelected
            ? (_isCreSer
                ? _creSerBlue.withOpacity(0.15)
                : Colors.white.withOpacity(0.9))
            : Colors.transparent,
      ),
      child: ListTile(
        onTap: () => setState(() => _selectedIndex = index),
        dense: true,
        leading: Icon(
          icon,
          color: isSelected
              ? (_isCreSer ? _creSerBlue : miColorBase)
              : (_isCreSer ? _creSerBlue.withOpacity(0.65) : Colors.white70),
          size: 18,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected
                ? (_isCreSer ? _creSerBlueDark : miColorBase)
                : (_isCreSer ? _creSerBlueDark.withOpacity(0.75) : Colors.white70),
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _compactMenuItem(int index, IconData icon, String tooltip) {
    final isSelected = _selectedIndex == index;
    return Tooltip(
      message: tooltip,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isSelected
              ? (_isCreSer ? _creSerBlue : Colors.white)
              : (_isCreSer
                  ? _creSerBlue.withOpacity(0.08)
                  : Colors.white.withOpacity(0.04)),
        ),
        child: IconButton(
          onPressed: () => setState(() => _selectedIndex = index),
          icon: Icon(
            icon,
            color: isSelected
                ? (_isCreSer ? Colors.white : miColorBase)
                : (_isCreSer ? _creSerBlue : Colors.white),
            size: 22,
          ),
          tooltip: tooltip,
        ),
      ),
    );
  }

  IconData _iconForSede(String sedeId) {
    switch (sedeId) {
      case SedeAccess.sedeNorteId:
        return Icons.spa_outlined;
      case SedeAccess.sedeCentroId:
        return Icons.location_city_outlined;
      case SedeAccess.sedeCreSerId:
        return Icons.school_outlined;
      default:
        return Icons.account_balance_outlined;
    }
  }

  PopupMenuItem<String> _buildSedeMenuItem({
    required String sedeId,
    required IconData icon,
  }) {
    final isActive = _sedeActivaId == sedeId;
    final color = isActive
        ? AppBranding.fromSedeId(sedeId).primary
        : Colors.black87;

    return PopupMenuItem<String>(
      value: sedeId,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              SedeAccess.displayNameForId(sedeId),
              style: TextStyle(
                color: color,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (isActive)
            Icon(
              Icons.check_circle,
              size: 18,
              color: AppBranding.fromSedeId(sedeId).primary,
            ),
        ],
      ),
    );
  }
}

class _AdminNotificationItem {
  const _AdminNotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.routeKey,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final String routeKey;
  final DateTime createdAt;
}
