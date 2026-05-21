import 'dart:convert';

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
import 'bootstrap_admin_ui.dart';
import 'certificate_drop_zone_stub.dart'
    if (dart.library.html) 'certificate_drop_zone_web.dart';
import 'certificate_file_picker_stub.dart'
    if (dart.library.html) 'certificate_file_picker_web.dart';

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
  bool _sincronizandoNumeracionSolicitudes = false;
  late Stream<QuerySnapshot> _solicitudesStream;
  late Stream<QuerySnapshot> _usuariosStream;
  int? _ultimaHuellaUsuarios;
  Set<String>? _allowedCollaboratorsCache;
  int? _ultimaHuellaSolicitudesSincronizadas;

  static const Color _primary = Color(0xFF2F6E6F);
  static const Color _primaryDark = Color(0xFF173B3C);
  static const Color _accent = Color(0xFFCFE7E4);
  static const Color _success = Color(0xFF3FA36C);
  static const Color _danger = Color(0xFFD96557);
  static const Color _warning = Color(0xFFF0A64A);
  static const Color _surface = Color(0xFFF6F8FB);
  static const Color _ink = Color(0xFF1E2937);
  static const Color _muted = Color(0xFF6C7A89);

  // --- Helpers base de sesion, branding y texto ---------------------------

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

  String get _sedeLabel => _resolvedSedeId == SedeAccess.matrizId
      ? 'Sede Matriz'
      : SedeAccess.displayNameForId(_resolvedSedeId);
  bool get _isNorth => _useSedeBranding;
  bool get _useSedeBranding => _branding.isCustomSede;
  Color get _bannerColor => _useSedeBranding ? _branding.primary : _primary;
  Color get _bannerSoftColor =>
      _useSedeBranding ? _branding.surface : const Color(0xFFEFF5F4);
  Color get _brandPrimary => _useSedeBranding ? _branding.primary : _primary;

  // --- Ciclo de vida y fuentes de datos en vivo ---------------------------

  @override
  void initState() {
    super.initState();
    _rebuildStreams();
  }

  @override
  void didUpdateWidget(covariant GestionPersonalWeb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sedeId != widget.sedeId ||
        oldWidget.isSedeNorte != widget.isSedeNorte) {
      _rebuildStreams();
    }
  }

  Query<Map<String, dynamic>> _buildSolicitudesQuery() {
    var query = FirebaseFirestore.instance
        .collection('solicitudes')
        .where('sedeId', isEqualTo: _resolvedSedeId);
    if (_filtroActual == 'Pendientes') {
      query = query.where('estado', isEqualTo: 'pendiente');
    }
    return query;
  }

  Stream<QuerySnapshot> _buildSolicitudesStream() {
    return _buildSolicitudesQuery().snapshots();
  }

  Stream<QuerySnapshot> _buildUsuariosStream() {
    return FirebaseFirestore.instance
        .collection('usuarios')
        .where('sedeId', isEqualTo: _resolvedSedeId)
        .where(
          'rol',
          whereIn: const [
            'Docente',
            'Personal administrativo',
            'Administrativo',
            'RRHH',
            'Admin',
          ],
        )
        .snapshots();
  }

  void _rebuildStreams() {
    _solicitudesStream = _buildSolicitudesStream();
    _usuariosStream = _buildUsuariosStream();
  }

  void _actualizarFiltroSolicitudes(String value) {
    if (_filtroActual == value) {
      return;
    }
    setState(() {
      _filtroActual = value;
      _rebuildStreams();
    });
  }

  Color get _brandPrimaryDark =>
      _useSedeBranding ? _branding.primaryDark : _primaryDark;
  Color get _brandAccent => _useSedeBranding ? _branding.softAccent : _accent;
  Color get _pageSurface => _useSedeBranding ? _branding.surface : _surface;
  Color get _panelSurface => _useSedeBranding
      ? Colors.white.withValues(alpha: 0.94)
      : Colors.white.withValues(alpha: 0.92);
  Color get _cardSurface => _useSedeBranding ? Colors.white : Colors.white;
  Color get _softPanel => _useSedeBranding ? _branding.surface : _surface;
  Color get _lineColor => _useSedeBranding
      ? _branding.primary.withValues(alpha: 0.34)
      : _brandPrimary.withValues(alpha: 0.28);
  Color get _panelBorderColor => _useSedeBranding
      ? _branding.primary.withValues(alpha: 0.32)
      : _brandPrimary.withValues(alpha: 0.28);
  List<Color> get _heroGradient => _useSedeBranding
      ? [
          _branding.primaryDark,
          _branding.primary,
          _branding.primary.withValues(alpha: 0.84),
        ]
      : [_primaryDark, _primary, _primary.withValues(alpha: 0.92)];
  String get _heroLogoAsset => _useSedeBranding
      ? _branding.logoHeader
      : 'assets/images/logo_intesud1.png';
  String get _watermarkAsset => _useSedeBranding
      ? _branding.logoWatermark
      : 'assets/images/logo_intesud2.png';

  // --- Reglas de visibilidad y aprobacion ---------------------------------

  Set<String> _allowedCollaborators(List<QueryDocumentSnapshot> docs) {
    final huella = Object.hashAll(docs.map((doc) => doc.id));
    if (_ultimaHuellaUsuarios == huella && _allowedCollaboratorsCache != null) {
      return _allowedCollaboratorsCache!;
    }

    final resultado = docs
        .map((doc) => doc.data() as Map<String, dynamic>)
        .where((data) {
          final isValidRole =
              _matchesRole(data, 'Docente') ||
              _matchesRole(data, 'Administrativo') ||
              UserRoleAccess.isRrhhRole(data['rol']) ||
              UserRoleAccess.isAdminRole(data['rol']);
          return _matchesCurrentSede(data) && isValidRole;
        })
        .map((data) => (data['nombre'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty)
        .toSet();

    _ultimaHuellaUsuarios = huella;
    _allowedCollaboratorsCache = resultado;
    return resultado;
  }

  List<QueryDocumentSnapshot> _filterSolicitudes(
    List<QueryDocumentSnapshot> docs, {
    Set<String>? allowedCollaborators,
  }) {
    if (allowedCollaborators == null) {
      return docs;
    }

    // La bandeja final solo expone solicitudes de colaboradores visibles
    // para la sede y el rol que esta usando el administrador actual.
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
    if (!_usaFlujoMatriz(data)) {
      return etapa;
    }

    if (etapa.isNotEmpty) {
      return etapa;
    }

    if (_normalize(data['estado']) == 'pendiente') {
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
          ? 'Pendiente de tu aprobacion previa'
          : 'Pendiente de aprobacion previa RRHH';
    }
    if (etapa == MatrizApprovalFlow.stageFinal) {
      return _esRevisorFinalMatriz
          ? 'Pendiente de tu aceptacion'
          : 'Pendiente de aceptacion final RRHH';
    }

    return 'Solicitud pendiente';
  }

  String _labelBotonAprobar(Map<String, dynamic> data) {
    if (_usaFlujoMatriz(data) &&
        _etapaSolicitud(data) == MatrizApprovalFlow.stagePrimary) {
      return 'Aprobacion';
    }
    if (_usaFlujoMatriz(data) &&
        _etapaSolicitud(data) == MatrizApprovalFlow.stageFinal) {
      return 'Aceptar';
    }
    return 'Aprobar';
  }

  String _labelBotonFirmar(Map<String, dynamic> data, String nuevoEstado) {
    final base = _labelBotonAprobar(data);
    if (nuevoEstado == 'cancel') {
      return 'Firmar rechazo';
    }

    if (base == 'Aprobacion') {
      return 'Firmar revision';
    }
    if (base == 'Aceptar') {
      return 'Firmar y aceptar';
    }
    return 'Firmar y aprobar';
  }

  Future<void> _resolverSolicitud(
    String idDoc,
    String nuevoEstado, {
    Map<String, dynamic>? reviewerUserDataOverride,
    String? signingPassword,
  }) async {
    try {
      await _fs.actualizarEstadoSolicitud(
        idDoc,
        nuevoEstado,
        reviewerEmail: _correoActual,
        reviewerName: _nombreUsuarioActual,
        reviewerUserData: reviewerUserDataOverride ?? widget.userData,
        signingPassword: signingPassword,
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

  // --- Certificado digital y firma ----------------------------------------

  void _programarSincronizacionNumeracionSolicitudes(
    List<QueryDocumentSnapshot> docs,
  ) {
    if (_sincronizandoNumeracionSolicitudes || docs.isEmpty) {
      return;
    }

    final huella = Object.hashAll(docs.map((doc) => doc.id));
    if (_ultimaHuellaSolicitudesSincronizadas == huella) {
      return;
    }

    _sincronizandoNumeracionSolicitudes = true;
    Future<void>(() async {
      try {
        await _fs.sincronizarNumeracionSolicitudesDesdeDocs(
          docs,
          sedeId: _resolvedSedeId,
        );
        _ultimaHuellaSolicitudesSincronizadas = huella;
      } finally {
        _sincronizandoNumeracionSolicitudes = false;
      }
    });
  }

  Future<Map<String, dynamic>?> _obtenerCertificadoDigitalActual() {
    return _fs.obtenerCertificadoDigitalUsuario(
      userDocId: widget.userData?['docId']?.toString(),
      correo: _correoActual,
      sedeId: _resolvedSedeId,
    );
  }

  bool _debeFirmarPdfAlExportar(Map<String, dynamic>? certificadoDigital) {
    // La firma automatica del PDF queda preparada para activarse despues,
    // pero por ahora el flujo oficial sigue exportando sin firma criptografica.
    return false;
  }

  bool _certificadoDigitalConfigurado(Map<String, dynamic>? certificado) {
    if (certificado == null) {
      return false;
    }

    return (certificado['fileName'] ?? '').toString().trim().isNotEmpty;
  }

  String _formatearFechaCertificado(dynamic value) {
    DateTime? fecha;
    if (value is Timestamp) {
      fecha = value.toDate();
    } else if (value is DateTime) {
      fecha = value;
    } else if (value != null) {
      fecha = DateTime.tryParse(value.toString());
    }

    if (fecha == null) {
      return '';
    }

    return DateFormat('dd/MM/yyyy').format(fecha);
  }

  String _descripcionCertificadoDigital(Map<String, dynamic>? certificado) {
    if (certificado == null) {
      return 'Todavia no has registrado un certificado .p12.';
    }

    final partes = <String>[
      (certificado['fileName'] ?? '').toString().trim(),
      (certificado['subject'] ?? '').toString().trim(),
    ]..removeWhere((item) => item.isEmpty);

    final validoHasta = _formatearFechaCertificado(certificado['validTo']);
    if (validoHasta.isNotEmpty) {
      partes.add('Valido hasta $validoHasta');
    }

    return partes.isEmpty
        ? 'Certificado digital .p12 registrado.'
        : partes.join('\n');
  }

  Future<Map<String, dynamic>?> _abrirGestorCertificadoDialog() async {
    final certificadoActual = await _obtenerCertificadoDigitalActual();
    if (!mounted) {
      return certificadoActual;
    }

    final accountPasswordController = TextEditingController();
    final certificatePasswordController = TextEditingController();
    PickedCertificateFile? selectedFile;
    bool guardando = false;
    bool eliminando = false;
    bool ocultarClaveCuenta = true;
    bool ocultarClaveCertificado = true;
    String? error;
    var certificadoGuardado = certificadoActual;

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> seleccionarArchivo() async {
              final picked = await pickCertificateFile();
              if (picked == null) {
                return;
              }

              setDialogState(() {
                selectedFile = picked;
                error = null;
              });
            }

            Future<void> guardarCertificado() async {
              if (selectedFile == null) {
                setDialogState(() {
                  error = 'Selecciona tu archivo .p12 o .pfx.';
                });
                return;
              }

              setDialogState(() {
                guardando = true;
                error = null;
              });

              try {
                await _fs.registrarCertificadoDigitalUsuario(
                  userDocId: widget.userData?['docId']?.toString(),
                  correo: _correoActual,
                  sedeId: _resolvedSedeId,
                  accountPassword: accountPasswordController.text,
                  certificatePassword: certificatePasswordController.text,
                  fileBytes: selectedFile!.bytes,
                  fileName: selectedFile!.fileName,
                  mimeType: selectedFile!.mimeType,
                );

                final actualizado = await _obtenerCertificadoDigitalActual();
                if (!dialogContext.mounted) {
                  return;
                }
                if (!mounted) {
                  return;
                }

                setDialogState(() {
                  certificadoGuardado = actualizado;
                  selectedFile = null;
                  accountPasswordController.clear();
                  certificatePasswordController.clear();
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Tu certificado digital .p12 quedo registrado.',
                    ),
                  ),
                );
              } catch (e) {
                if (!dialogContext.mounted) {
                  return;
                }
                setDialogState(() {
                  error = e.toString().replaceFirst('Exception: ', '');
                });
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() => guardando = false);
                }
              }
            }

            Future<void> eliminarCertificado() async {
              setDialogState(() {
                eliminando = true;
                error = null;
              });

              try {
                await _fs.eliminarCertificadoDigitalUsuario(
                  userDocId: widget.userData?['docId']?.toString(),
                  correo: _correoActual,
                  sedeId: _resolvedSedeId,
                  accountPassword: accountPasswordController.text,
                );

                if (!dialogContext.mounted) {
                  return;
                }

                setDialogState(() {
                  certificadoGuardado = null;
                  selectedFile = null;
                  accountPasswordController.clear();
                  certificatePasswordController.clear();
                });
              } catch (e) {
                if (!dialogContext.mounted) {
                  return;
                }
                setDialogState(() {
                  error = e.toString().replaceFirst('Exception: ', '');
                });
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() => eliminando = false);
                }
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
              title: Text(
                'Mi certificado digital .p12',
                style: GoogleFonts.manrope(
                  color: _brandPrimaryDark,
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Registra aqui tu certificado legal .p12 o .pfx. El sistema usara tu clave del certificado para validar y firmar PDFs desde la API interna.',
                        style: GoogleFonts.manrope(
                          color: _muted,
                          fontSize: 13,
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _softPanel,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: _panelBorderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _certificadoDigitalConfigurado(certificadoGuardado)
                                  ? 'Certificado registrado'
                                  : 'Todavia no has registrado un certificado',
                              style: GoogleFonts.manrope(
                                color: _ink,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              selectedFile?.fileName ??
                                  _descripcionCertificadoDigital(
                                    certificadoGuardado,
                                  ),
                              style: GoogleFonts.manrope(
                                color: _muted,
                                fontSize: 12.5,
                                height: 1.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      CertificateDropZone(
                        enabled: !(guardando || eliminando),
                        selectedFileName: selectedFile?.fileName,
                        onFileDropped: (picked) {
                          setDialogState(() {
                            selectedFile = picked;
                            error = null;
                          });
                        },
                        onError: (message) {
                          setDialogState(() {
                            error = message;
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: guardando || eliminando
                            ? null
                            : seleccionarArchivo,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Seleccionar certificado .p12 o .pfx'),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: accountPasswordController,
                        obscureText: ocultarClaveCuenta,
                        decoration: InputDecoration(
                          labelText: 'Clave actual de la cuenta',
                          hintText: 'Confirma tu clave para guardar o eliminar',
                          suffixIcon: IconButton(
                            tooltip: ocultarClaveCuenta
                                ? 'Mostrar clave'
                                : 'Ocultar clave',
                            onPressed: () {
                              setDialogState(() {
                                ocultarClaveCuenta = !ocultarClaveCuenta;
                              });
                            },
                            icon: Icon(
                              ocultarClaveCuenta
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: certificatePasswordController,
                        obscureText: ocultarClaveCertificado,
                        decoration: InputDecoration(
                          labelText: 'Clave del certificado .p12',
                          hintText: 'Se pedira cada vez que firmes el PDF',
                          suffixIcon: IconButton(
                            tooltip: ocultarClaveCertificado
                                ? 'Mostrar clave'
                                : 'Ocultar clave',
                            onPressed: () {
                              setDialogState(() {
                                ocultarClaveCertificado =
                                    !ocultarClaveCertificado;
                              });
                            },
                            icon: Icon(
                              ocultarClaveCertificado
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          error!,
                          style: GoogleFonts.manrope(
                            color: _danger,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                if (_certificadoDigitalConfigurado(certificadoGuardado))
                  TextButton.icon(
                    onPressed: guardando || eliminando
                        ? null
                        : eliminarCertificado,
                    icon: eliminando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline_rounded),
                    label: const Text('Eliminar'),
                  ),
                TextButton(
                  onPressed: guardando || eliminando
                      ? null
                      : () => Navigator.of(dialogContext).pop(
                          certificadoGuardado,
                        ),
                  child: const Text('Cerrar'),
                ),
                FilledButton.icon(
                  onPressed: guardando || eliminando
                      ? null
                      : guardarCertificado,
                  icon: guardando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.verified_user_outlined),
                  label: Text(
                    guardando
                        ? 'Guardando...'
                        : 'Guardar certificado .p12',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    accountPasswordController.dispose();
    certificatePasswordController.dispose();
    return result ?? certificadoGuardado;
  }

  Future<String?> _solicitarClaveCertificadoDialog({
    required String titulo,
    required String descripcion,
  }) async {
    final certificado = await _obtenerCertificadoDigitalActual();
    if (!mounted) {
      return null;
    }
    if (!_certificadoDigitalConfigurado(certificado)) {
      final actualizado = await _abrirGestorCertificadoDialog();
      if (!_certificadoDigitalConfigurado(actualizado) || !mounted) {
        return null;
      }
    }

    final certificatePasswordController = TextEditingController();
    var ocultarClaveCertificado = true;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
              title: Text(
                titulo,
                style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      descripcion,
                      style: GoogleFonts.manrope(
                        color: _muted,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: certificatePasswordController,
                      obscureText: ocultarClaveCertificado,
                      decoration: InputDecoration(
                        labelText: 'Clave del certificado .p12',
                        hintText: 'La misma clave de tu certificado legal',
                        suffixIcon: IconButton(
                          tooltip: ocultarClaveCertificado
                              ? 'Mostrar clave'
                              : 'Ocultar clave',
                          onPressed: () {
                            setDialogState(() {
                              ocultarClaveCertificado =
                                  !ocultarClaveCertificado;
                            });
                          },
                          icon: Icon(
                            ocultarClaveCertificado
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(''),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(
                    certificatePasswordController.text,
                  ),
                  child: const Text('Continuar'),
                ),
              ],
            );
          },
        );
      },
    );

    certificatePasswordController.dispose();
    final password = result?.trim() ?? '';
    return password.isEmpty ? null : password;
  }

  // --- Construccion de pantalla principal ---------------------------------

  Future<void> _firmarSolicitud(
    Map<String, dynamic> data,
    String idDoc,
    String nuevoEstado,
  ) async {
    final signingPassword =
        (await _solicitarClaveCertificadoDialog(
      titulo: _labelBotonFirmar(data, nuevoEstado),
      descripcion:
          'La solicitud N° ${_resolverNumeroFormulario(data)} de ${(data['colaborador'] ?? 'colaborador').toString().trim()} se firmara electronicamente con tu certificado digital .p12 y quedara vinculada a un QR unico de trazabilidad.',
    )) ??
        '';
    if (signingPassword.isEmpty || !mounted) {
      return;
    }

    await _resolverSolicitud(
      idDoc,
      nuevoEstado,
      reviewerUserDataOverride: widget.userData,
      signingPassword: signingPassword,
    );
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
                stream: _solicitudesStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  _programarSincronizacionNumeracionSolicitudes(
                    snapshot.data?.docs ?? const <QueryDocumentSnapshot>[],
                  );

                  return StreamBuilder<QuerySnapshot>(
                    stream: _usuariosStream,
                    builder: (context, usuariosSnapshot) {
                      if (usuariosSnapshot.connectionState ==
                          ConnectionState.waiting) {
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

  _SolicitudListSummary _resumirSolicitudes(
    List<QueryDocumentSnapshot> solicitudes,
  ) {
    var cantPendientes = 0;
    var cantAprobadas = 0;
    var cantRechazadas = 0;
    final solicitudesPendientes = <QueryDocumentSnapshot>[];

    for (final doc in solicitudes) {
      final data = doc.data() as Map<String, dynamic>;
      final estado = (data['estado'] ?? '').toString().trim();
      final esPendiente = _mostrarComoPendienteParaUsuario(data);

      if (esPendiente) {
        cantPendientes++;
        solicitudesPendientes.add(doc);
      }

      if (estado == 'aprobado') {
        cantAprobadas++;
      } else if (estado == 'rechazado' || estado == 'cancel') {
        cantRechazadas++;
      }
    }

    return _SolicitudListSummary(
      cantPendientes: cantPendientes,
      cantAprobadas: cantAprobadas,
      cantRechazadas: cantRechazadas,
      solicitudesPendientes: solicitudesPendientes,
    );
  }

  Widget _buildSolicitudesView(
    List<QueryDocumentSnapshot> todasLasSolicitudes, {
    bool showSedeBanner = false,
  }) {
    final resumen = _resumirSolicitudes(todasLasSolicitudes);
    final solicitudesAMostrar = _filtroActual == 'Pendientes'
        ? resumen.solicitudesPendientes
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
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: BootstrapAdminAlertBar(
                      icon: Icons.groups_2_outlined,
                      accentColor: _bannerColor,
                      backgroundColor: _bannerSoftColor,
                      message: _resolvedSedeId == SedeAccess.matrizId &&
                              (_esRevisorPrimarioMatriz ||
                                  _esRevisorFinalMatriz)
                          ? 'Gestionando solo solicitudes del personal de $_sedeLabel con flujo de aprobacion por etapas.'
                          : 'Gestionando solo solicitudes del personal de $_sedeLabel.',
                    ),
                  ),
                _buildHeroHeader(
                  pendientes: resumen.cantPendientes,
                  total: todasLasSolicitudes.length,
                ),
                const SizedBox(height: 24),
                _buildKpiSection(
                  pendientes: resumen.cantPendientes,
                  aprobadas: resumen.cantAprobadas,
                  rechazadas: resumen.cantRechazadas,
                  total: todasLasSolicitudes.length,
                ),
                const SizedBox(height: 24),
                _buildFilterPanel(
                  pendientes: resumen.cantPendientes,
                  total: todasLasSolicitudes.length,
                  aprobadas: resumen.cantAprobadas,
                  rechazadas: resumen.cantRechazadas,
                ),
                const SizedBox(height: 24),
                _buildSolicitudesGrid(solicitudesAMostrar, contentWidth),
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
              color: _brandAccent.withValues(alpha: _isNorth ? 0.8 : 0.55),
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
                color: const Color(0xFFDCA7C0).withValues(alpha: 0.28),
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
              color: _brandPrimary.withValues(alpha: _isNorth ? 0.12 : 0.08),
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
                  color: Colors.white.withValues(alpha: 0.24),
                ),
              ),
            ),
          ),
        Center(
          child: Opacity(
            opacity: _isNorth ? 0.055 : 0.045,
            child: Image.asset(_watermarkAsset, width: _isNorth ? 360 : 420),
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
            gradient: LinearGradient(colors: _heroGradient),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: _brandPrimary.withValues(alpha: 0.34)),
            boxShadow: [
              BoxShadow(
                color: _brandPrimary.withValues(alpha: _isNorth ? 0.28 : 0.18),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(
                          alpha: _isNorth ? 0.18 : 0.12,
                        ),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white38),
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
                            color: Colors.white.withValues(
                              alpha: _isNorth ? 0.18 : 0.1,
                            ),
                            borderRadius: BorderRadius.circular(
                              _isNorth ? 28 : 22,
                            ),
                            border: Border.all(
                              color: _isNorth
                                  ? Colors.white.withValues(alpha: 0.46)
                                  : Colors.white38,
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
                                  color: Colors.white.withValues(alpha: 0.82),
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
                        color: Colors.white.withValues(alpha: 0.72),
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
          color: Colors.white.withValues(alpha: _isNorth ? 0.16 : 0.12),
          borderRadius: BorderRadius.circular(_isNorth ? 28 : 24),
          border: Border.all(
            color: _isNorth
                ? Colors.white.withValues(alpha: 0.34)
                : Colors.white38,
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
                color: Colors.white.withValues(alpha: 0.8),
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
              ? color.withValues(alpha: 0.40)
              : color.withValues(alpha: 0.34),
        ),
        boxShadow: [
          BoxShadow(
            color: (_isNorth ? color : Colors.black).withValues(
              alpha: _isNorth ? 0.10 : 0.04,
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
                  color: color.withValues(alpha: 0.12),
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
            border: Border.all(color: _panelBorderColor),
            boxShadow: [
              BoxShadow(
                color: _brandPrimary.withValues(alpha: _isNorth ? 0.08 : 0.035),
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
                          accentColor: _warning,
                          icon: Icons.pending_actions_rounded,
                          onTap: () =>
                              _actualizarFiltroSolicitudes('Pendientes'),
                        ),
                        _buildFilterChip(
                          label: 'Todas ($total)',
                          selected: _filtroActual == 'Todas',
                          accentColor: _brandPrimary,
                          icon: Icons.layers_outlined,
                          onTap: () => _actualizarFiltroSolicitudes('Todas'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            _abrirGestorCertificadoDialog();
                          },
                          icon: const Icon(
                            Icons.verified_user_outlined,
                            size: 18,
                          ),
                          label: const Text('Mi certificado .p12'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _brandPrimaryDark,
                            side: BorderSide(color: _panelBorderColor),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
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
                        backgroundColor: _brandAccent.withValues(alpha: 0.55),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _brandPrimary,
                        ),
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
    required Color accentColor,
    IconData? icon,
  }) {
    final borderColor = accentColor.withValues(alpha: _isNorth ? 0.30 : 0.22);
    final softColor = accentColor.withValues(alpha: _isNorth ? 0.10 : 0.08);
    final deepColor =
        Color.lerp(accentColor, Colors.black, 0.10) ?? accentColor;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(colors: [deepColor, accentColor])
              : null,
          color: selected ? null : softColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? Colors.transparent : borderColor,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: _isNorth ? 0.28 : 0.22),
                    blurRadius: _isNorth ? 20 : 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.white : accentColor,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: GoogleFonts.manrope(
                color: selected ? Colors.white : accentColor,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSolicitudesGrid(
    List<QueryDocumentSnapshot> solicitudes,
    double width,
  ) {
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
      final right = hasRight
          ? solicitudes[i + 1].data() as Map<String, dynamic>
          : null;
      final rightId = hasRight ? solicitudes[i + 1].id : null;

      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
        color: _cardSurface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(_isNorth ? 32 : 28),
        border: Border.all(color: _panelBorderColor),
      ),
      child: Column(
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: _brandAccent.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(_isNorth ? 28 : 24),
            ),
            child: Icon(
              Icons.inbox_rounded,
              size: 34,
              color: _brandPrimaryDark,
            ),
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
    final numeroFormulario = _resolverNumeroFormulario(data);
    final firmasRegistradas = _etiquetasFirmasElectronicas(data);

    return Container(
      decoration: BoxDecoration(
        color: _cardSurface,
        borderRadius: BorderRadius.circular(_isNorth ? 24 : 20),
        border: Border.all(color: badge.color.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: badge.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'No. $numeroFormulario',
                    style: GoogleFonts.manrope(
                      color: badge.color,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar inicial
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: badge.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          (data['colaborador'] ?? '?')
                                  .toString()
                                  .trim()
                                  .isNotEmpty
                              ? (data['colaborador'] as String)
                                    .trim()[0]
                                    .toUpperCase()
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
                                color: _brandPrimary.withValues(alpha: 0.10),
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
                const SizedBox(height: 12),
                _buildFirmaResumenSection(firmasRegistradas),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // ── Pie: PDF + acciones ───────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: _softPanel.withValues(alpha: 0.6),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              border: Border(top: BorderSide(color: _panelBorderColor)),
            ),
            child: Row(
              children: [
                _buildPdfButton(data, idDoc),
                const Spacer(),
                if (_puedeResolverSolicitud(data)) ...[
                  _buildActionButton(
                    label: _labelBotonFirmar(data, 'aprobado'),
                    color: _success,
                    onPressed: () => _firmarSolicitud(data, idDoc, 'aprobado'),
                  ),
                  if (!_usaFlujoMatriz(data) ||
                      _etapaSolicitud(data) ==
                          MatrizApprovalFlow.stageFinal) ...[
                    const SizedBox(width: 10),
                    _buildActionButton(
                      label: _labelBotonFirmar(data, 'cancel'),
                      color: _danger,
                      outlined: true,
                      onPressed: () => _firmarSolicitud(data, idDoc, 'cancel'),
                    ),
                  ],
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

  Widget _buildFirmaChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _brandPrimary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _brandPrimary.withValues(alpha: 0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_outlined, size: 14, color: _brandPrimary),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.manrope(
              color: _brandPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFirmaResumenSection(List<String> firmasRegistradas) {
    return SizedBox(
      height: 82,
      child: firmasRegistradas.isEmpty
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _softPanel.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _panelBorderColor),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.pending_actions_outlined,
                    size: 18,
                    color: _warning,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Firmas pendientes por completar',
                      style: GoogleFonts.manrope(
                        color: _muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : Align(
              alignment: Alignment.topLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: firmasRegistradas
                    .map((label) => _buildFirmaChip(label))
                    .toList(),
              ),
            ),
    );
  }

  Widget _buildPdfButton(Map<String, dynamic> data, String idDoc) {
    return TextButton.icon(
      onPressed: () => _generarPDF(idDoc, data),
      style: TextButton.styleFrom(
        foregroundColor: _danger,
        backgroundColor: _isNorth
            ? const Color(0xFFFCECF2)
            : _danger.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
        backgroundColor: outlined ? color.withValues(alpha: 0.08) : color,
        foregroundColor: outlined ? color : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: outlined
              ? BorderSide(color: color.withValues(alpha: 0.30))
              : BorderSide.none,
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 12),
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

  dynamic _serializarValorPdfToken(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().millisecondsSinceEpoch;
    }
    if (value is DateTime) {
      return value.millisecondsSinceEpoch;
    }
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return {
        for (final entry in entries)
          entry.key.toString(): _serializarValorPdfToken(entry.value),
      };
    }
    if (value is Iterable) {
      return value.map(_serializarValorPdfToken).toList();
    }
    return value;
  }

  Map<String, dynamic> _normalizarFirmasParaPdfToken(Map<String, dynamic> data) {
    final firmas = data['firmasElectronicas'];
    if (firmas is! Map) {
      return const <String, dynamic>{};
    }

    final resultado = <String, dynamic>{};
    final keys = firmas.keys.map((e) => e.toString()).toList()..sort();
    for (final key in keys) {
      final value = firmas[key];
      if (value is! Map) {
        continue;
      }

      final firmaNormalizada = <String, dynamic>{};
      final nestedKeys = value.keys.map((e) => e.toString()).toList()..sort();
      for (final nestedKey in nestedKeys) {
        if (nestedKey == 'imageBase64') {
          continue;
        }
        firmaNormalizada[nestedKey] = _serializarValorPdfToken(value[nestedKey]);
      }
      resultado[key] = firmaNormalizada;
    }

    return resultado;
  }

  // Este token resume el estado visible de la solicitud. Si cambia, el sistema
  // sabe que el PDF final almacenado debe regenerarse.
  String _buildPdfSnapshotToken(Map<String, dynamic> data) {
    final payload = <String, dynamic>{
      'templateVersion': 9,
      'tipo': data['tipo'],
      'estado': data['estado'],
      'etapaAprobacion': data['etapaAprobacion'],
      'numFormulario': data['numFormulario'],
      'colaborador': data['colaborador'],
      'motivo': data['motivo'],
      'fechaInicio': _serializarValorPdfToken(data['fechaInicio']),
      'fechaFin': _serializarValorPdfToken(data['fechaFin']),
      'fechaSolicitud': _serializarValorPdfToken(data['fechaSolicitud']),
      'fechaPermiso': _serializarValorPdfToken(data['fechaPermiso']),
      'horasPermiso': data['horasPermiso'],
      'horarioPermiso': data['horarioPermiso'],
      'descontarDe': data['descontarDe'],
      'diasDisponibles': data['diasDisponibles'],
      'diasATomar': data['diasATomar'],
      'anioVacaciones': data['anioVacaciones'],
      'diasAcumulados': data['diasAcumulados'],
      'saldoDias': data['saldoDias'],
      'fechaRetorno': _serializarValorPdfToken(data['fechaRetorno']),
      'firmasElectronicas': _normalizarFirmasParaPdfToken(data),
    };

    return base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll(
      '=',
      '',
    );
  }

  String _buildPdfFileName(Map<String, dynamic> data, String numFormulario) {
    final tipo = _esSolicitudVacaciones(data) ? 'vacaciones' : 'permiso';
    final colaborador = (data['colaborador'] ?? 'colaborador')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    final nombreBase = colaborador.isEmpty ? 'colaborador' : colaborador;
    return 'solicitud_${tipo}_${numFormulario}_$nombreBase.pdf';
  }

  dynamic _resolverFechaPermiso(Map<String, dynamic> data) {
    return data['fechaPermiso'] ?? data['fechaInicio'] ?? data['fechaFin'];
  }

  String _extraerRangoHorarioPermiso(String value) {
    final match = RegExp(
      r'(\d{1,2}):(\d{2})\s*(?:a|-)\s*(\d{1,2}):(\d{2})',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) {
      return value.trim();
    }

    final inicioHora = int.tryParse(match.group(1)!);
    final inicioMinuto = int.tryParse(match.group(2)!);
    final finHora = int.tryParse(match.group(3)!);
    final finMinuto = int.tryParse(match.group(4)!);
    if (inicioHora == null ||
        inicioMinuto == null ||
        finHora == null ||
        finMinuto == null) {
      return value.trim();
    }

    final inicio =
        '${inicioHora.toString().padLeft(2, '0')}:${inicioMinuto.toString().padLeft(2, '0')}';
    final fin =
        '${finHora.toString().padLeft(2, '0')}:${finMinuto.toString().padLeft(2, '0')}';
    return '$inicio a $fin';
  }

  String _resolverHorarioPermiso(Map<String, dynamic> data) {
    final horario =
        data['horarioPermiso']?.toString() ??
        data['horasPermiso']?.toString() ??
        '';
    return _extraerRangoHorarioPermiso(horario);
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

  Map<String, dynamic>? _resolverFirmaElectronica(
    Map<String, dynamic> data,
    String key,
  ) {
    final firmas = data['firmasElectronicas'];
    if (firmas is! Map) {
      return null;
    }

    final firma = firmas[key];
    if (firma is! Map) {
      return null;
    }

    return firma.map(
      (nestedKey, value) => MapEntry(nestedKey.toString(), value),
    );
  }

  List<String> _etiquetasFirmasElectronicas(Map<String, dynamic> data) {
    final etiquetas = <String>[];

    if (_resolverFirmaElectronica(data, 'solicitante') != null) {
      etiquetas.add('Solicitante firmado');
    }
    if (_resolverFirmaElectronica(data, 'revisionPrimaria') != null) {
      etiquetas.add('Revision RRHH firmada');
    }
    if (_resolverFirmaElectronica(data, 'resolucion') != null) {
      etiquetas.add('Resolucion firmada');
    }
    if (_resolverFirmaElectronica(data, 'autorizacionFinal') != null) {
      etiquetas.add('Rector / Gerencia General firmado');
    }

    return etiquetas;
  }

  Future<void> _generarPDF(String idDoc, Map<String, dynamic> data) async {
    final dataPdf = await _fs.asegurarNumeroFormularioSolicitud(idDoc, data);
    final snapshotToken = _buildPdfSnapshotToken(dataPdf);
    final documentoGuardado = await _fs.obtenerDocumentoPdfFinalSolicitud(idDoc);
    final documentoGuardadoToken = (documentoGuardado?['snapshotToken'] ?? '')
        .toString()
        .trim();
    final bytesGuardados = _fs.extraerBytesDocumentoPdfFinalSolicitud(
      documentoGuardado,
    );

    if (bytesGuardados != null &&
        bytesGuardados.isNotEmpty &&
        documentoGuardadoToken == snapshotToken) {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytesGuardados,
      );
      return;
    }

    final pdf = pw.Document();
    final numFormulario = _resolverNumeroFormulario(dataPdf);

    final logoAsset = _branding.isMatriz
        ? _branding.logoHeader
        : _branding.logoPdf;
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

    Uint8List pdfBytes = await pdf.save();
    var firmadoDigitalmente = false;
    final certificadoDigital = await _obtenerCertificadoDigitalActual();
    if (_debeFirmarPdfAlExportar(certificadoDigital) &&
        _certificadoDigitalConfigurado(certificadoDigital) &&
        mounted) {
      final certificatePassword = await _solicitarClaveCertificadoDialog(
        titulo: 'Firmar PDF con certificado .p12',
        descripcion:
            'Si continuas, el PDF exportado se firmara criptograficamente con tu certificado digital legal.',
      );

      if (certificatePassword != null && mounted) {
        try {
          pdfBytes = await _fs.firmarPdfConCertificadoDigital(
            userDocId: widget.userData?['docId']?.toString(),
            correo: _correoActual,
            sedeId: _resolvedSedeId,
            certificatePassword: certificatePassword,
            pdfBytes: pdfBytes,
            signerName: _nombreUsuarioActual,
            reason:
                'Solicitud ${(dataPdf['tipo'] ?? 'Documento').toString().trim()} N° $numFormulario',
            location: _resolvedSedeId,
            contactInfo: _correoActual,
          );
          firmadoDigitalmente = true;
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'No se pudo firmar digitalmente el PDF. Se exportara la version interna. ${e.toString().replaceFirst('Exception: ', '')}',
                ),
                backgroundColor: _danger,
              ),
            );
          }
        }
      }
    }

    try {
      await _fs.guardarPdfFinalSolicitud(
        idDoc: idDoc,
        pdfBytes: pdfBytes,
        fileName: _buildPdfFileName(dataPdf, numFormulario),
        snapshotToken: snapshotToken,
        firmadoDigitalmente: firmadoDigitalmente,
        localPreviewOnly: certificadoDigital?['localPreviewOnly'] == true,
        generatedByEmail: _correoActual,
        generatedByName: _nombreUsuarioActual,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'El PDF se genero, pero no se pudo guardar como documento final. ${e.toString().replaceFirst('Exception: ', '')}',
            ),
            backgroundColor: _warning,
          ),
        );
      }
    }

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
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
                  child: _campoPdf('Horas:', _resolverCantidadHoras(data)),
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
            pw.SizedBox(height: 28),
            _buildFirmasElectronicasSectionPdf(data),
            pw.Spacer(),
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
            _buildFirmasElectronicasSectionPdf(data),
          ],
        ),
      ),
    );
  }

  pw.Widget _itemCheckPdf(
    String etiqueta,
    bool marcado, {
    bool multiline = false,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      crossAxisAlignment: multiline
          ? pw.CrossAxisAlignment.start
          : pw.CrossAxisAlignment.center,
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

  pw.Widget _buildFirmasElectronicasSectionPdf(Map<String, dynamic> data) {
    final firmaSolicitante = _resolverFirmaElectronica(data, 'solicitante');
    final firmaJefeInmediato = _resolverFirmaElectronica(
      data,
      'autorizacionJefeInmediato',
    );
    final firmaRevisionPrimaria = _resolverFirmaElectronica(
      data,
      'revisionPrimaria',
    );
    final firmaResolucion = _resolverFirmaElectronica(data, 'resolucion');
    final firmaAutorizacionFinal = _resolverFirmaElectronica(
      data,
      'autorizacionFinal',
    );
    final firmaRevision = firmaRevisionPrimaria ?? firmaResolucion;
    final mostrarAutorizacionFinal =
        firmaAutorizacionFinal != null ||
        _etapaSolicitud(data) == MatrizApprovalFlow.stageFinal ||
        _normalizarTextoComparable(data['aprobadoPrimarioPorEmail']).isNotEmpty ||
        _normalizarTextoComparable(data['aprobadoPrimarioPorNombre']).isNotEmpty;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _firmaElectronicaPdf(
                titulo: 'Firma del trabajador',
                firma: firmaSolicitante,
                pendienteTexto: 'Pendiente de firma del trabajador',
                firmaArriba: true,
                mostrarCedulaDebajo: true,
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: _firmaElectronicaPdf(
                titulo: 'Autoriza Jefe inmediato',
                firma: firmaJefeInmediato,
                pendienteTexto: 'Pendiente de autorizacion del jefe inmediato',
                firmaArriba: true,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _firmaElectronicaPdf(
                titulo: 'Revision Recursos Humanos',
                firma: firmaRevision,
                pendienteTexto: 'Pendiente de revision de Recursos Humanos',
                firmaArriba: true,
              ),
            ),
            if (mostrarAutorizacionFinal) ...[
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _firmaElectronicaPdf(
                  titulo: 'Rector\nGerencia General',
                  firma: firmaAutorizacionFinal,
                  pendienteTexto: 'Pendiente de autorizacion final',
                  firmaArriba: true,
                  mostrarCuadrosLaterales: true,
                ),
              ),
            ] else ...[
              pw.SizedBox(width: 12),
              pw.Expanded(child: pw.SizedBox()),
            ],
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Documento generado con firma electronica validada mediante certificado digital .p12 y QR unico de trazabilidad.',
          style: pw.TextStyle(
            fontSize: 7.5,
            color: PdfColors.grey700,
            fontStyle: pw.FontStyle.italic,
          ),
        ),
      ],
    );
  }

  pw.Widget _firmaElectronicaPdf({
    required String titulo,
    required Map<String, dynamic>? firma,
    required String pendienteTexto,
    bool firmaArriba = false,
    bool mostrarCedulaDebajo = false,
    bool mostrarCuadrosLaterales = false,
  }) {
    final firmada =
        firma != null &&
        _normalizarTextoComparable(firma['estado']) == 'firmado';
    final cedula = (firma?['cedula'] ?? '').toString().trim();
    final qrData = (firma?['qrData'] ?? firma?['firmaId'] ?? '')
        .toString()
        .trim();

    pw.Widget qrFirmaWidget() {
      if (qrData.isEmpty) {
        return pw.Container(
          width: 52,
          height: 52,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
          ),
        );
      }

      return pw.Container(
        width: 52,
        height: 52,
        padding: const pw.EdgeInsets.all(2),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey700, width: 0.6),
        ),
        child: pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: qrData,
        ),
      );
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
      ),
      child: pw.Column(
        crossAxisAlignment: firmaArriba
            ? pw.CrossAxisAlignment.center
            : pw.CrossAxisAlignment.start,
        children: [
          if (!firmaArriba) ...[
            pw.Text(
              titulo.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 7),
          ],
          if (!firmada)
            pw.Column(
              crossAxisAlignment: firmaArriba
                  ? pw.CrossAxisAlignment.center
                  : pw.CrossAxisAlignment.start,
              children: [
                if (firmaArriba) ...[
                  pw.SizedBox(height: 52),
                  _buildTituloFirmaPdf(
                    titulo: titulo,
                    mostrarCuadrosLaterales: mostrarCuadrosLaterales,
                    fontSize: 8.8,
                  ),
                  if (mostrarCedulaDebajo) ...[
                    pw.SizedBox(height: 3),
                    pw.Text(
                      cedula.isNotEmpty
                          ? 'No. Cedula: $cedula'
                          : 'No. Cedula: ....................',
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 8.2),
                    ),
                  ],
                  pw.SizedBox(height: 6),
                ],
                pw.Text(
                  pendienteTexto,
                  textAlign: firmaArriba ? pw.TextAlign.center : null,
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    color: PdfColors.grey700,
                    fontStyle: pw.FontStyle.italic,
                  ),
                ),
              ],
            )
          else ...[
            if (!firmaArriba) pw.SizedBox(height: 8),
            pw.Container(
              width: double.infinity,
              alignment: firmaArriba
                  ? pw.Alignment.center
                  : pw.Alignment.centerLeft,
              child: qrFirmaWidget(),
            ),
            if (firmaArriba) ...[
              pw.SizedBox(height: 8),
              _buildTituloFirmaPdf(
                titulo: titulo,
                mostrarCuadrosLaterales: mostrarCuadrosLaterales,
                fontSize: 8.8,
              ),
              if (mostrarCedulaDebajo) ...[
                pw.SizedBox(height: 3),
                pw.Text(
                  cedula.isNotEmpty
                      ? 'No. Cedula: $cedula'
                      : 'No. Cedula: ....................',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 8.2),
                ),
              ],
              pw.SizedBox(height: 5),
              pw.Text(
                'QR unico de validacion',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 7.2,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 4),
            ] else ...[
              pw.Text(
                'Firma validada con certificado digital .p12',
                style: pw.TextStyle(
                  fontSize: 7.6,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 3),
            ],
            if (cedula.isNotEmpty && !mostrarCedulaDebajo) ...[
              pw.SizedBox(height: 2),
              pw.Text(
                'Cedula: $cedula',
                textAlign: firmaArriba ? pw.TextAlign.center : null,
                style: const pw.TextStyle(fontSize: 8.2),
              ),
            ],
          ],
        ],
      ),
    );
  }

  pw.Widget _buildTituloFirmaPdf({
    required String titulo,
    required bool mostrarCuadrosLaterales,
    required double fontSize,
  }) {
    final texto = pw.Text(
      titulo,
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold),
    );

    if (!mostrarCuadrosLaterales) {
      return texto;
    }

    pw.Widget cuadro() {
      return pw.Container(
        width: 12,
        height: 12,
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
      );
    }

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Expanded(child: pw.SizedBox()),
        pw.Expanded(flex: 3, child: texto),
        pw.SizedBox(width: 8),
        pw.Column(
          children: [
            cuadro(),
            pw.SizedBox(height: 4),
            cuadro(),
          ],
        ),
        pw.Expanded(child: pw.SizedBox()),
      ],
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

class _SolicitudListSummary {
  final int cantPendientes;
  final int cantAprobadas;
  final int cantRechazadas;
  final List<QueryDocumentSnapshot> solicitudesPendientes;

  const _SolicitudListSummary({
    required this.cantPendientes,
    required this.cantAprobadas,
    required this.cantRechazadas,
    required this.solicitudesPendientes,
  });
}
