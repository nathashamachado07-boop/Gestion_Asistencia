import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../config/app_config.dart';
import '../models/app_branding.dart';
import '../services/firebase_service.dart';

class GestionPersonalWeb extends StatefulWidget {
  const GestionPersonalWeb({
    super.key,
    this.isSedeNorte = false,
    this.sedeId,
    this.userData,
  });

  final bool isSedeNorte;
  final String? sedeId;
  final Map<String, dynamic>? userData;

  @override
  State<GestionPersonalWeb> createState() => _GestionPersonalWebState();
}

class _GestionPersonalWebState extends State<GestionPersonalWeb> {
  final FirebaseService _fs = FirebaseService();
  String _filtroActual = 'Pendientes';

  static const Color _primary = Color(0xFF2F6E6F);
  static const Color _primaryDark = Color(0xFF173B3C);
  static const Color _accent = Color(0xFFCFE7E4);
  static const Color _success = Color(0xFF3FA36C);
  static const Color _danger = Color(0xFFD96557);
  static const Color _warning = Color(0xFFF0A64A);
  static const Color _surface = Color(0xFFF6F8FB);
  static const Color _ink = Color(0xFF1E2937);
  static const Color _muted = Color(0xFF6C7A89);

  String _normalize(dynamic value) {
    return value?.toString().trim().toLowerCase() ?? '';
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

  String get _resolvedSedeId =>
      widget.sedeId ??
      (widget.isSedeNorte ? SedeAccess.sedeNorteId : SedeAccess.matrizId);
  AppBranding get _branding => AppBranding.fromSedeId(_resolvedSedeId);

  bool _matchesCurrentSede(Map<String, dynamic> data) {
    return SedeAccess.matchesSede(data, _resolvedSedeId);
  }

  String get _correoActual =>
      MatrizApprovalFlow.normalizeEmail(widget.userData?['correo']);

  String get _nombreUsuarioActual =>
      (widget.userData?['nombre'] ?? 'RRHH').toString().trim();

  bool get _esRevisorPrimarioMatriz =>
      MatrizApprovalFlow.isPrimaryReviewer(_correoActual);

  bool get _esRevisorFinalMatriz =>
      MatrizApprovalFlow.isFinalReviewer(_correoActual);

  String get _sedeLabel =>
      _resolvedSedeId == SedeAccess.matrizId
          ? 'Sede Matriz'
          : SedeAccess.displayNameForId(_resolvedSedeId);
  bool get _isNorth => _useSedeBranding;
  bool get _useSedeBranding => _branding.isCustomSede;
  Color get _bannerColor => _useSedeBranding ? _branding.primary : _primary;
  Color get _bannerSoftColor =>
      _useSedeBranding ? _branding.surface : const Color(0xFFEFF5F4);
  Color get _brandPrimary => _useSedeBranding ? _branding.primary : _primary;
  Color get _brandPrimaryDark =>
      _useSedeBranding ? _branding.primaryDark : _primaryDark;
  Color get _brandAccent => _useSedeBranding ? _branding.softAccent : _accent;
  Color get _pageSurface => _useSedeBranding ? _branding.surface : _surface;
  Color get _panelSurface =>
      _useSedeBranding ? Colors.white.withOpacity(0.94) : Colors.white.withOpacity(0.92);
  Color get _cardSurface => _useSedeBranding ? Colors.white : Colors.white;
  Color get _softPanel => _useSedeBranding ? _branding.surface : _surface;
  Color get _lineColor =>
      _useSedeBranding
          ? _branding.primary.withOpacity(0.24)
          : _brandPrimary.withOpacity(0.18);
  Color get _panelBorderColor =>
      _useSedeBranding ? _branding.primary.withOpacity(0.22) : _brandPrimary.withOpacity(0.18);
  List<Color> get _heroGradient => _useSedeBranding
      ? [
          _branding.primaryDark,
          _branding.primary,
          _branding.primary.withOpacity(0.84),
        ]
      : [_primaryDark, _primary, _primary.withOpacity(0.92)];
  String get _heroLogoAsset => _useSedeBranding
      ? _branding.logoHeader
      : 'assets/images/logo_intesud1.png';
  String get _watermarkAsset => _useSedeBranding
      ? _branding.logoWatermark
      : 'assets/images/logo_intesud2.png';

  Set<String> _allowedCollaborators(List<QueryDocumentSnapshot> docs) {
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

  List<QueryDocumentSnapshot> _filterSolicitudes(
    List<QueryDocumentSnapshot> docs, {
    Set<String>? allowedCollaborators,
  }) {
    if (allowedCollaborators == null) {
      return docs;
    }

    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final colaborador = (data['colaborador'] ?? '').toString().trim();
      return allowedCollaborators.contains(colaborador);
    }).toList();
  }

  bool _usaFlujoMatriz(Map<String, dynamic> data) {
    if (!MatrizApprovalFlow.appliesToRequest(data)) {
      return false;
    }

    final flujo = _normalize(data['flujoAprobacion']);
    final estado = _normalize(data['estado']);
    return flujo == MatrizApprovalFlow.flowId || estado == 'pendiente';
  }

  String _etapaSolicitud(Map<String, dynamic> data) {
    final etapa = _normalize(data['etapaAprobacion']);
    if (etapa.isNotEmpty) {
      return etapa;
    }

    if (_usaFlujoMatriz(data) && _normalize(data['estado']) == 'pendiente') {
      return MatrizApprovalFlow.stagePrimary;
    }

    return etapa;
  }

  bool _puedeResolverSolicitud(Map<String, dynamic> data) {
    if (_normalize(data['estado']) != 'pendiente') {
      return false;
    }

    if (!_usaFlujoMatriz(data)) {
      return true;
    }

    final etapa = _etapaSolicitud(data);
    if (etapa == MatrizApprovalFlow.stagePrimary) {
      return _esRevisorPrimarioMatriz;
    }
    if (etapa == MatrizApprovalFlow.stageFinal) {
      return _esRevisorFinalMatriz;
    }

    return false;
  }

  bool _mostrarComoPendienteParaUsuario(Map<String, dynamic> data) {
    if (_normalize(data['estado']) != 'pendiente') {
      return false;
    }

    if (!_usaFlujoMatriz(data)) {
      return true;
    }

    final etapa = _etapaSolicitud(data);
    if (etapa == MatrizApprovalFlow.stagePrimary) {
      return _esRevisorPrimarioMatriz;
    }
    if (etapa == MatrizApprovalFlow.stageFinal) {
      return _esRevisorFinalMatriz;
    }

    return false;
  }

  String _textoEtapaPendiente(Map<String, dynamic> data) {
    if (!_usaFlujoMatriz(data) || _normalize(data['estado']) != 'pendiente') {
      return 'Solicitud pendiente';
    }

    final etapa = _etapaSolicitud(data);
    if (etapa == MatrizApprovalFlow.stagePrimary) {
      return _esRevisorPrimarioMatriz
          ? 'Pendiente de tu revision inicial'
          : 'Pendiente de revision inicial RRHH';
    }
    if (etapa == MatrizApprovalFlow.stageFinal) {
      return _esRevisorFinalMatriz
          ? 'Pendiente de tu autorizacion final'
          : 'Pendiente de autorizacion final';
    }

    return 'Solicitud pendiente';
  }

  String _labelBotonAprobar(Map<String, dynamic> data) {
    if (_usaFlujoMatriz(data) &&
        _etapaSolicitud(data) == MatrizApprovalFlow.stagePrimary) {
      return 'Enviar a final';
    }
    if (_usaFlujoMatriz(data) &&
        _etapaSolicitud(data) == MatrizApprovalFlow.stageFinal) {
      return 'Aprobar final';
    }
    return 'Aprobar';
  }

  Future<void> _resolverSolicitud(String idDoc, String nuevoEstado) async {
    try {
      await _fs.actualizarEstadoSolicitud(
        idDoc,
        nuevoEstado,
        reviewerEmail: _correoActual,
        reviewerName: _nombreUsuarioActual,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: _danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        textTheme: GoogleFonts.manropeTextTheme(),
      ),
      child: Scaffold(
        backgroundColor: _pageSurface,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: _buildBackground()),
            Positioned.fill(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('solicitudes').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('usuarios').snapshots(),
                    builder: (context, usuariosSnapshot) {
                      if (usuariosSnapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final allowedCollaborators = _allowedCollaborators(
                        usuariosSnapshot.data?.docs ?? const [],
                      );
                      final filtradas = _filterSolicitudes(
                        snapshot.data?.docs ?? const [],
                        allowedCollaborators: allowedCollaborators,
                      );

                      return _buildSolicitudesView(
                        filtradas,
                        showSedeBanner: true,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSolicitudesView(
    List<QueryDocumentSnapshot> todasLasSolicitudes, {
    bool showSedeBanner = false,
  }) {
    final cantPendientes = todasLasSolicitudes
        .where(
          (doc) => _mostrarComoPendienteParaUsuario(
            doc.data() as Map<String, dynamic>,
          ),
        )
        .length;
    final cantAprobadas = todasLasSolicitudes
        .where((doc) => doc['estado'] == 'aprobado')
        .length;
    final cantRechazadas = todasLasSolicitudes
        .where((doc) => doc['estado'] == 'rechazado' || doc['estado'] == 'cancel')
        .length;

    final solicitudesAMostrar = _filtroActual == 'Pendientes'
        ? todasLasSolicitudes
            .where(
              (doc) => _mostrarComoPendienteParaUsuario(
                doc.data() as Map<String, dynamic>,
              ),
            )
            .toList()
        : todasLasSolicitudes;

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth;

        return SingleChildScrollView(
          primary: true,
          padding: EdgeInsets.fromLTRB(
            contentWidth > 1200 ? 36 : 20,
            28,
            contentWidth > 1200 ? 36 : 20,
            36,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: contentWidth,
              minHeight: constraints.maxHeight,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showSedeBanner)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 18),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _bannerSoftColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _bannerColor.withOpacity(0.24),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.groups_2_outlined,
                          color: _bannerColor,
                          size: 18,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _resolvedSedeId == SedeAccess.matrizId &&
                                    (_esRevisorPrimarioMatriz ||
                                        _esRevisorFinalMatriz)
                                ? 'Gestionando solo solicitudes del personal de $_sedeLabel con flujo de aprobacion por etapas.'
                                : 'Gestionando solo solicitudes del personal de $_sedeLabel.',
                            style: TextStyle(
                              color: _bannerColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                _buildHeroHeader(
                  pendientes: cantPendientes,
                  total: todasLasSolicitudes.length,
                ),
                const SizedBox(height: 24),
                _buildKpiSection(
                  pendientes: cantPendientes,
                  aprobadas: cantAprobadas,
                  rechazadas: cantRechazadas,
                  total: todasLasSolicitudes.length,
                ),
                const SizedBox(height: 24),
                _buildFilterPanel(
                  pendientes: cantPendientes,
                  total: todasLasSolicitudes.length,
                  aprobadas: cantAprobadas,
                  rechazadas: cantRechazadas,
                ),
                const SizedBox(height: 24),
                _buildSolicitudesGrid(
                  solicitudesAMostrar,
                  contentWidth,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBackground() {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _isNorth
                  ? const [
                      Color(0xFFFFF7FA),
                      Color(0xFFF9EDF3),
                      Color(0xFFF4E0EA),
                    ]
                  : const [
                      Color(0xFFF8FBFC),
                      Color(0xFFEFF4F6),
                      Color(0xFFE5EFED),
                    ],
            ),
          ),
        ),
        Positioned(
          top: -80,
          right: -40,
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _brandAccent.withOpacity(_isNorth ? 0.8 : 0.55),
            ),
          ),
        ),
        if (_isNorth)
          Positioned(
            top: 90,
            left: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFDCA7C0).withOpacity(0.28),
              ),
            ),
          ),
        Positioned(
          left: -120,
          bottom: -120,
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _brandPrimary.withOpacity(_isNorth ? 0.12 : 0.08),
            ),
          ),
        ),
        if (_isNorth)
          Positioned(
            right: 140,
            top: 120,
            child: Transform.rotate(
              angle: -0.18,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(48),
                  color: Colors.white.withOpacity(0.24),
                ),
              ),
            ),
          ),
        Center(
          child: Opacity(
            opacity: _isNorth ? 0.055 : 0.045,
            child: Image.asset(
              _watermarkAsset,
              width: _isNorth ? 360 : 420,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroHeader({required int pendientes, required int total}) {
    final hoy = DateFormat(
      "EEEE, d 'de' MMMM 'de' yyyy",
      'es_ES',
    ).format(DateTime.now());

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1040;
        final veryCompact = constraints.maxWidth < 720;

        return Container(
          padding: EdgeInsets.all(veryCompact ? 22 : 28),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _heroGradient,
          ),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: _brandPrimary.withOpacity(0.22)),
          boxShadow: [
            BoxShadow(
              color: _brandPrimary.withOpacity(_isNorth ? 0.28 : 0.18),
                blurRadius: _isNorth ? 40 : 30,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Flex(
            direction: compact ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: compact ? 1 : 3,
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(_isNorth ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    _isNorth
                        ? 'Atelier de solicitudes'
                        : 'Centro de gestión de solicitudes',
                    style: GoogleFonts.manrope(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Flex(
                  direction: veryCompact ? Axis.vertical : Axis.horizontal,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(_isNorth ? 0.18 : 0.1),
                        borderRadius: BorderRadius.circular(_isNorth ? 28 : 22),
                        border: Border.all(
                          color: _isNorth
                              ? Colors.white.withOpacity(0.34)
                              : Colors.white24,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Image.asset(_heroLogoAsset),
                      ),
                    ),
                    SizedBox(
                      width: veryCompact ? 0 : 18,
                      height: veryCompact ? 16 : 0,
                    ),
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Gestión del Personal',
                            style: GoogleFonts.manrope(
                              color: Colors.white,
                              fontSize: veryCompact ? 28 : 34,
                              fontWeight: FontWeight.w800,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Revisa, aprueba y da seguimiento a permisos, vacaciones y solicitudes internas desde un panel más claro y profesional.',
                            style: GoogleFonts.manrope(
                              color: Colors.white.withOpacity(0.82),
                              fontSize: 14,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  hoy[0].toUpperCase() + hoy.substring(1),
                  style: GoogleFonts.manrope(
                    color: Colors.white.withOpacity(0.72),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
              ),
              SizedBox(width: compact ? 0 : 24, height: compact ? 20 : 0),
              SizedBox(
                width: compact ? double.infinity : null,
                child: Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: compact ? WrapAlignment.start : WrapAlignment.end,
                  children: [
                    _buildHeroStat(
                      value: '$pendientes',
                      label: 'Pendientes',
                      icon: Icons.hourglass_top_rounded,
                    ),
                    _buildHeroStat(
                      value: '$total',
                      label: 'Solicitudes totales',
                      icon: Icons.stacked_bar_chart_rounded,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeroStat({
    required String value,
    required String label,
    required IconData icon,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 170, maxWidth: 220),
      child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(_isNorth ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(_isNorth ? 28 : 24),
        border: Border.all(
          color: _isNorth
              ? Colors.white.withOpacity(0.22)
              : Colors.white24,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(height: 18),
          Text(
            value,
            style: GoogleFonts.manrope(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.manrope(
              color: Colors.white.withOpacity(0.8),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildKpiSection({
    required int pendientes,
    required int aprobadas,
    required int rechazadas,
    required int total,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildKpiCard(
            title: 'Pendientes',
            subtitle: 'Por resolver',
            value: pendientes,
            color: _warning,
            icon: Icons.pending_actions_rounded,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _buildKpiCard(
            title: 'Aprobadas',
            subtitle: 'Gestión completada',
            value: aprobadas,
            color: _success,
            icon: Icons.verified_rounded,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _buildKpiCard(
            title: 'Rechazadas',
            subtitle: 'Requieren seguimiento',
            value: rechazadas,
            color: _danger,
            icon: Icons.highlight_off_rounded,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _buildKpiCard(
            title: 'Total',
            subtitle: 'Volumen general',
            value: total,
            color: _brandPrimary,
            icon: Icons.assessment_rounded,
          ),
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String subtitle,
    required int value,
    required Color color,
    required IconData icon,
  }) {
      return Container(
        padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _cardSurface,
        borderRadius: BorderRadius.circular(_isNorth ? 30 : 24),
        border: Border.all(
            color: _isNorth
                ? color.withOpacity(0.28)
                : color.withOpacity(0.22),
          ),
          boxShadow: [
            BoxShadow(
              color: (_isNorth ? color : Colors.black).withOpacity(
                _isNorth ? 0.10 : 0.04,
              ),
              blurRadius: _isNorth ? 24 : 18,
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
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  title.toUpperCase(),
                  textAlign: TextAlign.right,
                  style: GoogleFonts.manrope(
                    color: _muted,
                    fontSize: 11,
                    letterSpacing: 0.9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Text(
            '$value',
            style: GoogleFonts.manrope(
              color: _ink,
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.manrope(
              color: _muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPanel({
    required int pendientes,
    required int total,
    required int aprobadas,
    required int rechazadas,
  }) {
    final tasaResolucion = total == 0
        ? 0
        : (((aprobadas + rechazadas) / total) * 100).round();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 980;

        return Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _panelSurface,
            borderRadius: BorderRadius.circular(_isNorth ? 32 : 28),
            border: Border.all(
              color: _panelBorderColor,
            ),
            boxShadow: [
              BoxShadow(
                color: _brandPrimary.withOpacity(_isNorth ? 0.08 : 0.035),
                blurRadius: _isNorth ? 24 : 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Flex(
            direction: compact ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: compact ? 1 : 3,
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bandeja operativa',
                  style: GoogleFonts.manrope(
                    color: _isNorth ? _brandPrimaryDark : _ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Filtra la cola de trabajo y prioriza las solicitudes que necesitan atención inmediata.',
                  style: GoogleFonts.manrope(
                    color: _muted,
                    fontSize: 13,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildFilterChip(
                      label: 'Pendientes ($pendientes)',
                      selected: _filtroActual == 'Pendientes',
                      onTap: () => setState(() => _filtroActual = 'Pendientes'),
                    ),
                    _buildFilterChip(
                      label: 'Todas ($total)',
                      selected: _filtroActual == 'Todas',
                      onTap: () => setState(() => _filtroActual = 'Todas'),
                      outlined: true,
                    ),
                  ],
                ),
              ],
            ),
              ),
              SizedBox(width: compact ? 0 : 20, height: compact ? 18 : 0),
                Container(
                  width: compact ? double.infinity : 250,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _softPanel,
                    borderRadius: BorderRadius.circular(_isNorth ? 26 : 22),
                    border: Border.all(color: _lineColor),
                  ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Indicador del día',
                      style: GoogleFonts.manrope(
                        color: _muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '$tasaResolucion%',
                      style: GoogleFonts.manrope(
                        color: _ink,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'de solicitudes ya fueron resueltas',
                      style: GoogleFonts.manrope(
                        color: _muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 10,
                        value: tasaResolucion / 100,
                        backgroundColor: _brandAccent.withOpacity(0.55),
                        valueColor: AlwaysStoppedAnimation<Color>(_brandPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool outlined = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        gradient: selected
            ? LinearGradient(colors: [_brandPrimaryDark, _brandPrimary])
            : null,
          color: selected ? null : (_isNorth ? const Color(0xFFFFFCFD) : Colors.white),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : outlined
                    ? (_isNorth ? const Color(0xFFDFAFC8) : _panelBorderColor)
                    : (_isNorth ? const Color(0xFFE6C0D4) : _panelBorderColor),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _brandPrimary.withOpacity(_isNorth ? 0.28 : 0.22),
                    blurRadius: _isNorth ? 20 : 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            color: selected ? Colors.white : _ink,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildSolicitudesGrid(List<QueryDocumentSnapshot> solicitudes, double width) {
    if (solicitudes.isEmpty) {
      return _buildEmptyState();
    }

    // Para pantallas anchas usamos 2 columnas; angostas, 1 columna
    final useTwoColumns = width > 800;

    if (!useTwoColumns) {
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: solicitudes.length,
        itemBuilder: (context, index) {
          final data = solicitudes[index].data() as Map<String, dynamic>;
          return Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: _buildSolicitudCard(data, solicitudes[index].id),
          );
        },
      );
    }

    // Grid de 2 columnas
    final rows = <Widget>[];
    for (var i = 0; i < solicitudes.length; i += 2) {
      final left = solicitudes[i].data() as Map<String, dynamic>;
      final leftId = solicitudes[i].id;
      final hasRight = i + 1 < solicitudes.length;
      final right = hasRight ? solicitudes[i + 1].data() as Map<String, dynamic> : null;
      final rightId = hasRight ? solicitudes[i + 1].id : null;

      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildSolicitudCard(left, leftId)),
              const SizedBox(width: 18),
              Expanded(
                child: hasRight
                    ? _buildSolicitudCard(right!, rightId!)
                    : const SizedBox(),
              ),
            ],
          ),
        ),
      );
    }

    return Column(children: rows);
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 42),
      decoration: BoxDecoration(
        color: _cardSurface.withOpacity(0.96),
        borderRadius: BorderRadius.circular(_isNorth ? 32 : 28),
        border: Border.all(color: _panelBorderColor),
      ),
      child: Column(
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: _brandAccent.withOpacity(0.55),
              borderRadius: BorderRadius.circular(_isNorth ? 28 : 24),
            ),
            child: Icon(Icons.inbox_rounded, size: 34, color: _brandPrimaryDark),
          ),
          const SizedBox(height: 18),
          Text(
            'No hay solicitudes por revisar',
            style: GoogleFonts.manrope(
              fontSize: 22,
              color: _ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Cuando ingresen nuevas solicitudes aparecerán aquí con sus acciones disponibles.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: _muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── CARD vertical estilo imagen 1 ─────────────────────────────────────────
  Widget _buildSolicitudCard(Map<String, dynamic> data, String idDoc) {
    final badge = _badgeStyle(data);
    final tipo = (data['tipo'] ?? '').toString().trim().toUpperCase();

    return Container(
      decoration: BoxDecoration(
        color: _cardSurface,
        borderRadius: BorderRadius.circular(_isNorth ? 24 : 20),
        border: Border.all(color: badge.color.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabecera: avatar + nombre + tipo badge + estado ───────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar inicial
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: badge.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      (data['colaborador'] ?? '?').toString().trim().isNotEmpty
                          ? (data['colaborador'] as String).trim()[0].toUpperCase()
                          : '?',
                      style: GoogleFonts.manrope(
                        color: badge.color,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
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
                        data['colaborador'] ?? 'Colaborador',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          color: _ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Badge tipo (PERMISO / VACACIONES)
                      if (tipo.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _brandPrimary.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            tipo,
                            style: GoogleFonts.manrope(
                              color: _brandPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Badge estado (esquina superior derecha)
                _buildStatusBadge(data),
              ],
            ),
          ),

          // ── Divisor ──────────────────────────────────────────────────
          Divider(
            height: 1,
            thickness: 1,
            color: _panelBorderColor,
            indent: 20,
            endIndent: 20,
          ),

          // ── Fechas con iconos ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _buildDateChip(
                  icon: Icons.calendar_today_outlined,
                  label: 'Inicio',
                  value: _formatearFechaSimple(data['fechaInicio']),
                ),
                _buildDateChip(
                  icon: Icons.event_outlined,
                  label: 'Fin',
                  value: _formatearFechaSimple(data['fechaFin']),
                ),
              ],
            ),
          ),

          // ── Motivo ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Motivo',
                  style: GoogleFonts.manrope(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data['motivo'] ?? 'Sin motivo especificado',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    color: _ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // ── Pie: PDF + acciones ───────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: _softPanel.withOpacity(0.6),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              border: Border(
                top: BorderSide(color: _panelBorderColor),
              ),
            ),
            child: Row(
              children: [
                _buildPdfButton(data, idDoc),
                const Spacer(),
                if (_puedeResolverSolicitud(data)) ...[
                  _buildActionButton(
                    label: _labelBotonAprobar(data),
                    color: _success,
                    onPressed: () => _resolverSolicitud(idDoc, 'aprobado'),
                  ),
                  const SizedBox(width: 10),
                  _buildActionButton(
                    label: 'Rechazar',
                    color: _danger,
                    outlined: true,
                    onPressed: () => _resolverSolicitud(idDoc, 'cancel'),
                  ),
                ] else
                  Text(
                    _estadoTextoPlano(data),
                    style: GoogleFonts.manrope(
                      color: badge.color,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Chip de fecha con icono ───────────────────────────────────────────────
  Widget _buildDateChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _softPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _panelBorderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _brandPrimary),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.manrope(
                  color: _muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                value,
                style: GoogleFonts.manrope(
                  color: _ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPill({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _isNorth ? const Color(0xFFFFF7FA) : Colors.white,
        borderRadius: BorderRadius.circular(_isNorth ? 18 : 16),
        border: Border.all(
          color: _isNorth ? const Color(0xFFE0B5C9) : _panelBorderColor,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _brandPrimary),
          const SizedBox(width: 8),
          RichText(
            text: TextSpan(
              style: GoogleFonts.manrope(),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 12,
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

  Widget _buildStatusBadge(Map<String, dynamic> data) {
    final badge = _badgeStyle(data);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: badge.softColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        badge.label,
        style: GoogleFonts.manrope(
          color: badge.color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildPdfButton(Map<String, dynamic> data, String idDoc) {
    return TextButton.icon(
      onPressed: () => _generarPDF(idDoc, data),
      style: TextButton.styleFrom(
        foregroundColor: _danger,
        backgroundColor:
            _isNorth ? const Color(0xFFFCECF2) : _danger.withOpacity(0.08),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
      label: Text(
        'PDF',
        style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required Color color,
    required VoidCallback onPressed,
    bool outlined = false,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: outlined ? color.withOpacity(0.08) : color,
        foregroundColor: outlined ? color : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: outlined
              ? BorderSide(color: color.withOpacity(0.18))
              : BorderSide.none,
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  _StatusBadgeStyle _badgeStyle(Map<String, dynamic> data) {
    final estado = _normalize(data['estado']);
    switch (estado) {
      case 'aprobado':
        return const _StatusBadgeStyle(
          label: 'Aprobada',
          color: _success,
          softColor: Color(0xFFE8F6EE),
        );
      case 'rechazado':
      case 'cancel':
        return const _StatusBadgeStyle(
          label: 'Rechazada',
          color: _danger,
          softColor: Color(0xFFFCEBE7),
        );
      default:
        return _StatusBadgeStyle(
          label: _textoEtapaPendiente(data),
          color: _warning,
          softColor: const Color(0xFFFFF4E4),
        );
    }
  }

  String _estadoTextoPlano(Map<String, dynamic> data) {
    final estado = _normalize(data['estado']);
    switch (estado) {
      case 'aprobado':
        return 'Solicitud aprobada';
      case 'rechazado':
      case 'cancel':
        return 'Solicitud rechazada';
      default:
        return _textoEtapaPendiente(data);
    }
  }

  String _formatearFechaSimple(dynamic f) {
    if (f == null) return 'N/A';
    final dt = (f is Timestamp) ? f.toDate() : DateTime.parse(f.toString());
    return DateFormat('dd/MM/yyyy').format(dt);
  }

  String _normalizarTextoComparable(dynamic value) {
    final texto = value?.toString().trim().toLowerCase() ?? '';
    return texto
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
  }

  String _resolverNumeroFormulario(Map<String, dynamic> data) {
    final valor = data['numFormulario'];
    if (valor == null) return '00001';

    final texto = valor.toString().trim();
    final numero = int.tryParse(texto);
    return numero?.toString().padLeft(5, '0') ?? texto;
  }

  dynamic _resolverFechaPermiso(Map<String, dynamic> data) {
    return data['fechaPermiso'] ?? data['fechaInicio'] ?? data['fechaFin'];
  }

  String _resolverHorarioPermiso(Map<String, dynamic> data) {
    return data['horarioPermiso']?.toString() ??
        data['horasPermiso']?.toString() ??
        '';
  }

  String _resolverCantidadHoras(Map<String, dynamic> data) {
    final horario = _resolverHorarioPermiso(data);
    final match = RegExp(
      r'(\d{1,2}):(\d{2})\s*(?:a|-)\s*(\d{1,2}):(\d{2})',
      caseSensitive: false,
    ).firstMatch(horario);

    if (match == null) {
      return 'N/A';
    }

    final horaInicio = int.parse(match.group(1)!);
    final minutoInicio = int.parse(match.group(2)!);
    final horaFin = int.parse(match.group(3)!);
    final minutoFin = int.parse(match.group(4)!);

    final inicio = DateTime(2000, 1, 1, horaInicio, minutoInicio);
    var fin = DateTime(2000, 1, 1, horaFin, minutoFin);
    if (fin.isBefore(inicio)) {
      fin = fin.add(const Duration(days: 1));
    }

    final duracion = fin.difference(inicio);
    final horas = duracion.inHours;
    final minutos = duracion.inMinutes.remainder(60);

    if (minutos == 0) {
      return '$horas h';
    }

    return '${horas}h ${minutos}m';
  }

  bool _opcionDescuentoSeleccionada(dynamic actual, String esperado) {
    return _normalizarTextoComparable(actual) ==
        _normalizarTextoComparable(esperado);
  }

  bool _esSolicitudVacaciones(Map<String, dynamic> data) {
    return _normalizarTextoComparable(data['tipo']) == 'vacaciones';
  }

  int _resolverEntero(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  int _resolverDiasDisponibles(Map<String, dynamic> data) {
    return _resolverEntero(data['diasDisponibles']);
  }

  int _resolverDiasATomar(Map<String, dynamic> data) {
    return _resolverEntero(data['diasATomar']);
  }

  int _resolverDiasAcumulados(Map<String, dynamic> data) {
    final valor = _resolverEntero(data['diasAcumulados'], fallback: -1);
    return valor >= 0 ? valor : _resolverDiasDisponibles(data);
  }

  int _resolverSaldoDias(Map<String, dynamic> data) {
    final valor = _resolverEntero(data['saldoDias'], fallback: 1 << 30);
    if (valor != (1 << 30)) return valor;
    return _resolverDiasDisponibles(data) - _resolverDiasATomar(data);
  }

  int _resolverAnioVacaciones(Map<String, dynamic> data) {
    final valor = _resolverEntero(data['anioVacaciones'], fallback: -1);
    if (valor > 0) return valor;
    final fecha = data['fechaInicio'];
    if (fecha is Timestamp) return fecha.toDate().year;
    if (fecha != null) return DateTime.parse(fecha.toString()).year;
    return DateTime.now().year;
  }

  DateTime _resolverFechaRetorno(Map<String, dynamic> data) {
    final fecha = data['fechaRetorno'];
    if (fecha is Timestamp) return fecha.toDate();
    if (fecha != null) return DateTime.parse(fecha.toString());
    final fechaFin = data['fechaFin'];
    if (fechaFin is Timestamp) {
      return fechaFin.toDate().add(const Duration(days: 1));
    }
    if (fechaFin != null) {
      return DateTime.parse(fechaFin.toString()).add(const Duration(days: 1));
    }
    return DateTime.now();
  }

  Future<void> _generarPDF(String idDoc, Map<String, dynamic> data) async {
    final dataPdf = await _fs.asegurarNumeroFormularioSolicitud(idDoc, data);
    final pdf = pw.Document();
    final numFormulario = _resolverNumeroFormulario(dataPdf);

    final logoAsset =
        _branding.isMatriz ? _branding.logoHeader : _branding.logoPdf;
    final image = await rootBundle.load(logoAsset);
    final logoBytes = image.buffer.asUint8List();
    final logoImage = pw.MemoryImage(logoBytes);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.only(
          top: 2.50 * 28.35,
          bottom: 2.50 * 28.35,
          left: 3.0 * 28.35,
          right: 3.0 * 28.35,
        ),
        build: (pw.Context ctx) => _esSolicitudVacaciones(dataPdf)
            ? _buildPaginaVacaciones(dataPdf, numFormulario, logoImage)
            : _buildPaginaFormulario(dataPdf, numFormulario, logoImage),
      ),
    );


    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  pw.Widget _buildPaginaFormulario(
    Map<String, dynamic> data,
    String numFormulario,
    pw.MemoryImage logo,
  ) {
    const verdeIsts = PdfColor.fromInt(0xFF467879);
    final descontarDe = data['descontarDe'] ?? '';
    final headerLogoWidth = _branding.isMatriz ? 86.0 : 62.0;
    final headerLogoHeight = _branding.isMatriz ? 34.0 : 62.0;
    final headerSpacing = _branding.isMatriz ? 8.0 : 10.0;
    final textoNumero = 'N° $numFormulario';

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 1.3, color: PdfColors.black),
      ),
      padding: const pw.EdgeInsets.all(10),
      child: pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.8, color: PdfColors.black),
        ),
        padding: const pw.EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Align(
              alignment: pw.Alignment.center,
              child: pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Image(
                    logo,
                    width: headerLogoWidth,
                    height: headerLogoHeight,
                    fit: pw.BoxFit.contain,
                  ),
                  pw.SizedBox(width: headerSpacing),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.Text(
                        _branding.subtitle.toUpperCase(),
                        style: pw.TextStyle(fontSize: 6.5, letterSpacing: 0.3),
                      ),
                      pw.Text(
                        _branding.displayName.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 11.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'Yo soy del INTESUD',
                        style: pw.TextStyle(
                          fontSize: 7,
                          fontStyle: pw.FontStyle.italic,
                          color: verdeIsts,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'SOLICITUD DE PERMISOS',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'POR HORAS',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Text(
                  textoNumero,
                  style: pw.TextStyle(
                    color: PdfColors.red,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 18),
        _campoPdf(
          'Nombre del colaborador:',
          data['colaborador']?.toString().toUpperCase() ?? '',
        ),
        _campoPdf('Motivo del permiso:', data['motivo']?.toString() ?? ''),
        _campoPdf(
          'Fecha de solicitud:',
          _formatearFechaSimple(data['fechaSolicitud'] ?? DateTime.now()),
        ),
        _campoPdf(
          'Fecha de permiso:',
          _formatearFechaSimple(_resolverFechaPermiso(data)),
        ),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.SizedBox(
                  width: 130,
                  child: _campoPdf(
                    'Horas:',
                    _resolverCantidadHoras(data),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: _campoPdf(
                    'Horario del permiso:',
                    _resolverHorarioPermiso(data),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 18),
                    child: pw.Text(
                      'DESCONTAR DE:',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(
                  width: 220,
                  child: pw.Column(
                    children: [
                      _itemCheckPdf(
                        'VACACIONES',
                        _opcionDescuentoSeleccionada(descontarDe, 'Vacaciones'),
                      ),
                      pw.SizedBox(height: 7),
                      _itemCheckPdf(
                        'REMUNERACION',
                        _opcionDescuentoSeleccionada(
                          descontarDe,
                          'Remuneracion',
                        ),
                      ),
                      pw.SizedBox(height: 7),
                      _itemCheckPdf(
                        'SIN DESCUENTO\n(Licencias)',
                        _opcionDescuentoSeleccionada(
                          descontarDe,
                          'Sin Descuento',
                        ),
                        multiline: true,
                      ),
                      pw.SizedBox(height: 7),
                      _itemCheckPdf(
                        'RECUPERACION DE HORAS',
                        _opcionDescuentoSeleccionada(
                          descontarDe,
                          'Recuperacion de horas',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 42),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _firmaBloquePdf('Firma del trabajador\nNo. Cedula: ...............'),
            _firmaBloquePdf('Autoriza\nJefe inmediato'),
          ],
        ),
        pw.SizedBox(height: 42),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _firmaBloquePdf('Revisado\nRecursos Humanos'),
            _firmaBloquePdfConCuadros('Rector', 'Gerencia General'),
          ],
        ),
        pw.Spacer(),
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 10),
          padding: const pw.EdgeInsets.only(top: 4),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(width: 0.6, color: PdfColors.black),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'FORMATO INTERNO DE SOLICITUD',
                style: const pw.TextStyle(fontSize: 6),
              ),
              pw.Text(
                'Documento generado por NatyApp',
                style: const pw.TextStyle(fontSize: 6),
              ),
            ],
          ),
        ),
          ],
        ),
      ),
    );
  }

  pw.Widget _buildPaginaVacaciones(
    Map<String, dynamic> data,
    String numFormulario,
    pw.MemoryImage logo,
  ) {
    final headerLogoWidth = _branding.isMatriz ? 86.0 : 62.0;
    final headerLogoHeight = _branding.isMatriz ? 34.0 : 62.0;
    final headerSpacing = _branding.isMatriz ? 8.0 : 10.0;
    final textoNumero = 'N° $numFormulario';
    final diasDisponibles = _resolverDiasDisponibles(data);
    final diasATomar = _resolverDiasATomar(data);
    final diasAcumulados = _resolverDiasAcumulados(data);
    final saldoDias = _resolverSaldoDias(data);
    final anioVacaciones = _resolverAnioVacaciones(data);
    final fechaRetorno = _resolverFechaRetorno(data);

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 1.3, color: PdfColors.black),
      ),
      padding: const pw.EdgeInsets.all(10),
      child: pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.8, color: PdfColors.black),
        ),
        padding: const pw.EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Align(
              alignment: pw.Alignment.center,
              child: pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Image(
                    logo,
                    width: headerLogoWidth,
                    height: headerLogoHeight,
                    fit: pw.BoxFit.contain,
                  ),
                  pw.SizedBox(width: headerSpacing),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.Text(
                        _branding.subtitle.toUpperCase(),
                        style: pw.TextStyle(fontSize: 6.5, letterSpacing: 0.3),
                      ),
                      pw.Text(
                        _branding.displayName.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 11.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'Yo soy del INTESUD',
                        style: pw.TextStyle(
                          fontSize: 7,
                          fontStyle: pw.FontStyle.italic,
                          color: const PdfColor.fromInt(0xFF467879),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'SOLICITUD DE VACACIONES',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Text(
                  textoNumero,
                  style: pw.TextStyle(
                    color: PdfColors.red,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 22),
            _campoPdf(
              'Nombre del colaborador:',
              data['colaborador']?.toString().toUpperCase() ?? '',
            ),
            _campoPdf(
              'Fecha de solicitud:',
              _formatearFechaSimple(data['fechaSolicitud'] ?? DateTime.now()),
            ),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(
                  child: _campoPdf(
                    'Dispone de N° de dias:',
                    '$diasDisponibles',
                  ),
                ),
                pw.SizedBox(width: 14),
                pw.SizedBox(
                  width: 120,
                  child: _campoPdf('Año:', '$anioVacaciones'),
                ),
              ],
            ),
            _campoPdf('Dias acumulados:', '$diasAcumulados'),
            _campoPdf('N° de dias a tomar:', '$diasATomar'),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(
                  child: _campoPdf(
                    'Desde:',
                    _formatearFechaSimple(data['fechaInicio']),
                  ),
                ),
                pw.SizedBox(width: 14),
                pw.Expanded(
                  child: _campoPdf(
                    'Hasta:',
                    _formatearFechaSimple(data['fechaFin']),
                  ),
                ),
              ],
            ),
            _campoPdf(
              'Fecha de retorno:',
              DateFormat('dd/MM/yyyy').format(fechaRetorno),
            ),
            _campoPdf('Saldo dias:', '$saldoDias'),
            pw.Spacer(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _firmaBloquePdf('Firma del trabajador\nNo. Cedula: ...............'),
                _firmaBloquePdf('Autoriza\nJefe inmediato'),
              ],
            ),
            pw.SizedBox(height: 42),
            pw.Align(
              alignment: pw.Alignment.center,
              child: _firmaBloquePdf('Revisado\nRecursos Humanos'),
            ),
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 10),
              padding: const pw.EdgeInsets.only(top: 4),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  top: pw.BorderSide(width: 0.6, color: PdfColors.black),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'FORMATO INTERNO DE VACACIONES',
                    style: const pw.TextStyle(fontSize: 6),
                  ),
                  pw.Text(
                    'Documento generado por NatyApp',
                    style: const pw.TextStyle(fontSize: 6),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _itemCheckPdf(String etiqueta, bool marcado, {bool multiline = false}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      crossAxisAlignment:
          multiline ? pw.CrossAxisAlignment.start : pw.CrossAxisAlignment.center,
      children: [
        pw.Expanded(
          child: pw.Text(
            etiqueta,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: multiline ? 8.5 : 9.5,
              fontWeight: pw.FontWeight.bold,
              lineSpacing: 1.2,
            ),
          ),
        ),
        pw.SizedBox(width: 9),
        pw.Container(
          width: 16,
          height: 16,
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
          child: marcado
              ? pw.Center(
                  child: pw.Text(
                    'X',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                )
              : null,
        ),
      ],
    );
  }

  pw.Widget _campoPdf(String label, String valor) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 1),
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(width: 0.7)),
              ),
              child: pw.Text(
                valor,
                style: const pw.TextStyle(fontSize: 9.5),
                maxLines: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _firmaBloquePdf(String cargo) {
    return pw.Column(
      children: [
        pw.Container(
          width: 150,
          child: pw.Text(
            '.................................',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 8, letterSpacing: 0.6),
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          cargo,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  pw.Widget _firmaBloquePdfConCuadros(String linea1, String linea2) {
    return pw.Column(
      children: [
        pw.Container(
          width: 150,
          child: pw.Text(
            '.................................',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 8, letterSpacing: 0.6),
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  linea1,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  linea2,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            pw.SizedBox(width: 10),
            pw.Column(
              children: [
                _cajaVaciaPdf(),
                pw.SizedBox(height: 4),
                _cajaVaciaPdf(),
              ],
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _cajaVaciaPdf() {
    return pw.Container(
      width: 14,
      height: 14,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.8),
      ),
    );
  }
}

class _StatusBadgeStyle {
  final String label;
  final Color color;
  final Color softColor;

  const _StatusBadgeStyle({
    required this.label,
    required this.color,
    required this.softColor,
  });
}