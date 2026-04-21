import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/app_branding.dart';
import '../services/firebase_service.dart';
import 'dashboard_admin_web.dart';
import 'dashboard_princesa_gales_norte_web.dart';
import 'estadisticas_admin_web.dart';
import 'gestion_personal_web.dart';
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

  static const Color _defaultBase = Color(0xFF467879);
  static const Color _defaultSidebar = Color(0xFF467879);
  static const Color _defaultHeader = Color(0xFF2D4D4E);

  @override
  void initState() {
    super.initState();
    _userData = widget.userData == null
        ? null
        : Map<String, dynamic>.from(widget.userData!);
  }

  String get _nombreUsuario {
    final nombre = _userData?['nombre']?.toString().trim();
    if (nombre != null && nombre.isNotEmpty) {
      return nombre;
    }
    return 'Recursos Humanos';
  }

  String get _usuarioSedeId => _userData == null
      ? SedeAccess.matrizId
      : SedeAccess.resolveSedeId(_userData!);

  String get _sedeActivaId => _sedeVistaForzadaId ?? _usuarioSedeId;

  bool get _mostrarDashboardSede => _sedeActivaId != SedeAccess.matrizId;

  AppBranding get _brandingActiva => AppBranding.fromSedeId(_sedeActivaId);

  String get _sedeUsuario => SedeAccess.displayNameForId(_sedeActivaId);

  Color get miColorBase => _mostrarDashboardSede
      ? _brandingActiva.primary
      : _defaultBase;

  Color get sidebarColor => _mostrarDashboardSede
      ? _brandingActiva.primary
      : _defaultSidebar;

  Color get headerColor => _mostrarDashboardSede
      ? _brandingActiva.primaryDark
      : _defaultHeader;

  double get _sidebarHeaderHeight => _sidebarCollapsed ? 154 : 348;
  double get _sidebarLogoHeight => _sidebarCollapsed ? 46 : 108;

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
        GestionPersonalWeb(sedeId: _sedeActivaId),
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

  @override
  Widget build(BuildContext context) {
    final rol = (_userData?['rol'] ?? '').toString().trim().toUpperCase();
    if (_userData == null || rol != 'RRHH') {
      return _buildAccessDenied(
        'Debes iniciar sesion como RRHH para entrar a este panel.',
      );
    }

    return Scaffold(
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: _sidebarCollapsed ? 94 : 260,
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
                              color: headerColor,
                              border: const Border(
                                bottom: BorderSide(color: Colors.white10),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset(
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
                                if (!_sidebarCollapsed) ...[
                                  const SizedBox(height: 15),
                                  Text(
                                    _brandingActiva.displayName,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  Text(
                                    _mostrarDashboardSede
                                        ? _brandingActiva.subtitle.toUpperCase()
                                        : 'Gestion de Reportes',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _sedeUsuario,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white60,
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
                                      color: Colors.white.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: Colors.white12),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.home_outlined,
                                          color: Colors.white70,
                                          size: 16,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          'Ir al inicio',
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else ...[
                                  const SizedBox(height: 12),
                                  const Icon(
                                    Icons.home_outlined,
                                    color: Colors.white70,
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
                            'Gestion Personal',
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
                              unselectedWidgetColor: Colors.white60,
                            ),
                            child: ExpansionTile(
                              initiallyExpanded: _selectedIndex != 0,
                              leading: const Icon(
                                Icons.apps_outlined,
                                color: Colors.white,
                                size: 22,
                              ),
                              title: const Text(
                                'Aplicacion de Asistencia',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              iconColor: Colors.white,
                              collapsedIconColor: Colors.white,
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
                                  'Gestion Personal',
                                ),
                              ],
                            ),
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
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
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
                              if (_userData != null) ...[
                                const SizedBox(width: 16),
                                PopupMenuButton<String>(
                                  tooltip: 'Cambiar sede',
                                  initialValue: _sedeActivaId,
                                  offset: const Offset(0, 46),
                                  onSelected: _cambiarSedeVista,
                                  itemBuilder: (context) => [
                                    _buildSedeMenuItem(
                                      sedeId: SedeAccess.matrizId,
                                      icon: Icons.account_balance_outlined,
                                    ),
                                    _buildSedeMenuItem(
                                      sedeId: SedeAccess.sedeNorteId,
                                      icon: Icons.spa_outlined,
                                    ),
                                    _buildSedeMenuItem(
                                      sedeId: SedeAccess.sedeCentroId,
                                      icon: Icons.location_city_outlined,
                                    ),
                                    _buildSedeMenuItem(
                                      sedeId: SedeAccess.sedeCreSerId,
                                      icon: Icons.school_outlined,
                                    ),
                                  ],
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
      onSelected: (value) {
        switch (value) {
          case 'estadisticas':
            setState(() => _selectedIndex = 1);
            break;
          case 'reportes':
            setState(() => _selectedIndex = 2);
            break;
          case 'gestion':
            setState(() => _selectedIndex = 3);
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          enabled: false,
          value: 'titulo',
          child: Text(
            'Centro de notificaciones',
            style: TextStyle(fontWeight: FontWeight.w700),
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
            title: Text('Ir a gestion personal'),
            subtitle: Text('Revisa solicitudes pendientes'),
          ),
        ),
      ],
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
              Positioned(
                right: 9,
                top: 9,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
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
        return 'Administracion de Personal';
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
        color: isSelected ? Colors.white : Colors.transparent,
      ),
      child: ListTile(
        onTap: () => setState(() => _selectedIndex = index),
        leading: Icon(
          icon,
          color: isSelected ? miColorBase : Colors.white,
          size: 22,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? miColorBase : Colors.white,
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
        color: isSelected ? Colors.white.withOpacity(0.9) : Colors.transparent,
      ),
      child: ListTile(
        onTap: () => setState(() => _selectedIndex = index),
        dense: true,
        leading: Icon(
          icon,
          color: isSelected ? miColorBase : Colors.white70,
          size: 18,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? miColorBase : Colors.white70,
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
          color: isSelected ? Colors.white : Colors.white.withOpacity(0.04),
        ),
        child: IconButton(
          onPressed: () => setState(() => _selectedIndex = index),
          icon: Icon(
            icon,
            color: isSelected ? miColorBase : Colors.white,
            size: 22,
          ),
          tooltip: tooltip,
        ),
      ),
    );
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
