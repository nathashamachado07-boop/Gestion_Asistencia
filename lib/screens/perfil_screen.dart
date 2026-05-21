import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/app_branding.dart';
import '../services/firebase_service.dart';
import '../services/theme_controller.dart';
import '../widgets/legal_documents.dart';
import '../web/certificate_drop_zone_stub.dart'
    if (dart.library.html) '../web/certificate_drop_zone_web.dart';
import '../web/certificate_file_picker_stub.dart'
    if (dart.library.html) '../web/certificate_file_picker_web.dart';

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({
    super.key,
    required this.correoUsuario,
    this.isSedeNorte = false,
    this.sedeId,
  });

  final String correoUsuario;
  final bool isSedeNorte;
  final String? sedeId;

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  late Future<Map<String, dynamic>?> _perfilFuture;
  final FirebaseService _service = FirebaseService();

  bool get _isWebLayout => kIsWeb;
  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;

  AppBranding get _branding => AppBranding.fromLegacy(
    isSedeNorte: widget.isSedeNorte,
    sedeId: widget.sedeId,
  );

  Color get _pageBackground => _isDarkMode
      ? Color.alphaBlend(
          _branding.primaryDark.withValues(alpha: 0.28),
          const Color(0xFF0C1316),
        )
      : _branding.surface;

  Color get _cardBackground =>
      _isDarkMode ? Theme.of(context).cardColor : Colors.white;

  Color get _cardForeground =>
      _isDarkMode ? Colors.white : const Color(0xFF243435);

  Color get _mutedForeground =>
      _isDarkMode ? Colors.white70 : const Color(0xFF5C6A6B);

  Color get _softPanel => _isDarkMode
      ? _branding.primary.withValues(alpha: 0.14)
      : _branding.surface;

  Color get _outlineColor => _isDarkMode
      ? Colors.white.withValues(alpha: 0.16)
      : _branding.primary.withValues(alpha: 0.18);

  @override
  void initState() {
    super.initState();
    _perfilFuture = _loadProfile();
  }

  @override
  void didUpdateWidget(covariant PerfilScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.correoUsuario != widget.correoUsuario ||
        oldWidget.sedeId != widget.sedeId ||
        oldWidget.isSedeNorte != widget.isSedeNorte) {
      _perfilFuture = _loadProfile();
    }
  }

  Future<Map<String, dynamic>?> _loadProfile() {
    return _service.obtenerDatosPerfil(
      widget.correoUsuario,
      sedeId: widget.sedeId ?? _branding.sedeId,
    );
  }

  String _resolveDepartment(Map<String, dynamic> datos) {
    final areaNombre = (datos['areaNombre'] ?? '').toString().trim();
    if (areaNombre.isNotEmpty) {
      return areaNombre;
    }

    final especialidad = (datos['especialidad'] ?? '').toString().trim();
    if (especialidad.isNotEmpty) {
      return especialidad;
    }

    return 'Sin departamento';
  }

  String _resolveCargo(Map<String, dynamic> datos) {
    final cargo = (datos['cargo'] ?? '').toString().trim();
    if (cargo.isNotEmpty) {
      return cargo;
    }

    final especialidad = (datos['especialidad'] ?? '').toString().trim();
    if (especialidad.isNotEmpty &&
        especialidad.toLowerCase() != _resolveDepartment(datos).toLowerCase()) {
      return especialidad;
    }

    return 'Sin cargo';
  }

  String _resolveCedula(Map<String, dynamic> datos) {
    final cedula = (datos['cedula'] ?? '').toString().trim();
    return cedula.isEmpty ? 'Sin cedula' : cedula;
  }

  String _resolveTelefono(Map<String, dynamic> datos) {
    final telefono = (datos['telefono'] ?? '').toString().trim();
    return telefono.isEmpty ? 'Sin telefono' : telefono;
  }

  String _resolveCorreo(Map<String, dynamic> datos) {
    final correo = (datos['correo'] ?? '').toString().trim();
    return correo.isEmpty ? widget.correoUsuario : correo;
  }

  String _resolveSede(Map<String, dynamic> datos) {
    final sede = (datos['sede'] ?? '').toString().trim();
    if (sede.isNotEmpty) {
      return sede;
    }

    return SedeAccess.displayNameForId(widget.sedeId ?? _branding.sedeId);
  }

  Future<void> _handleChangePassword() async {
    final messenger = ScaffoldMessenger.of(context);
    final changed = await showChangePasswordDialog(
      context,
      branding: _branding,
      service: _service,
      correo: widget.correoUsuario,
    );

    if (!mounted || !changed) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: const Text('Contrasena actualizada correctamente.'),
        backgroundColor: _branding.primary,
      ),
    );
  }

  bool _certificadoDigitalConfigurado(Map<String, dynamic>? certificado) {
    if (certificado == null) {
      return false;
    }

    return (certificado['fileName'] ?? '').toString().trim().isNotEmpty;
  }

  String _descripcionCertificadoDigital(Map<String, dynamic>? certificado) {
    if (certificado == null) {
      return 'Aun no tienes un certificado .p12 registrado.';
    }

    final fileName = (certificado['fileName'] ?? '').toString().trim();
    final subject = (certificado['subject'] ?? '').toString().trim();
    final validTo = certificado['validTo'];
    String vigencia = '';
    if (validTo is Timestamp) {
      vigencia = 'Valido hasta ${_formatearFechaCertificado(validTo.toDate())}';
    } else if (validTo is DateTime) {
      vigencia = 'Valido hasta ${_formatearFechaCertificado(validTo)}';
    } else if (validTo != null &&
        validTo.toString().trim().isNotEmpty &&
        DateTime.tryParse(validTo.toString()) != null) {
      vigencia =
          'Valido hasta ${_formatearFechaCertificado(DateTime.parse(validTo.toString()))}';
    }

    final partes = <String>[
      if (fileName.isNotEmpty) fileName,
      if (subject.isNotEmpty) subject,
      if (vigencia.isNotEmpty) vigencia,
    ];
    return partes.isEmpty
        ? 'Certificado digital .p12 registrado.'
        : partes.join('\n');
  }

  Future<Map<String, dynamic>?> _obtenerCertificadoDigitalActual() {
    return _service.obtenerCertificadoDigitalUsuario(
      correo: widget.correoUsuario,
      sedeId: widget.sedeId ?? _branding.sedeId,
    );
  }

  String _formatearFechaCertificado(DateTime value) {
    final local = value.isUtc ? value.toLocal() : value;
    final dia = local.day.toString().padLeft(2, '0');
    final mes = local.month.toString().padLeft(2, '0');
    final anio = local.year.toString().padLeft(4, '0');
    return '$dia/$mes/$anio';
  }

  Future<void> _handleManageDigitalCertificate() async {
    final certificadoActual = await _obtenerCertificadoDigitalActual();
    if (!mounted) {
      return;
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

    await showDialog<void>(
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
                  error = 'Selecciona el archivo .p12 o .pfx de tu certificado.';
                });
                return;
              }

              setDialogState(() {
                guardando = true;
                error = null;
              });

              try {
                await _service.registrarCertificadoDigitalUsuario(
                  correo: widget.correoUsuario,
                  sedeId: widget.sedeId ?? _branding.sedeId,
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

                setDialogState(() {
                  certificadoGuardado = actualizado;
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
                await _service.eliminarCertificadoDigitalUsuario(
                  correo: widget.correoUsuario,
                  sedeId: widget.sedeId ?? _branding.sedeId,
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
                'Certificado digital .p12',
                style: TextStyle(
                  color: _branding.primaryDark,
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
                        'Registra tu certificado legal .p12 o .pfx para usarlo al firmar documentos del sistema. La clave del certificado se te pedira al momento de firmar.',
                        style: TextStyle(color: _mutedForeground, height: 1.45),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _softPanel,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: _outlineColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _certificadoDigitalConfigurado(certificadoGuardado)
                                  ? 'Certificado registrado'
                                  : 'Aun no tienes un certificado registrado',
                              style: TextStyle(
                                color: _cardForeground,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              selectedFile?.fileName ??
                                  _descripcionCertificadoDigital(
                                    certificadoGuardado,
                                  ),
                              style: TextStyle(
                                color: _mutedForeground,
                                height: 1.45,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (kIsWeb) ...[
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
                      ],
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
                          hintText: 'Se te pedira cada vez que firmes',
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
                          style: const TextStyle(
                            color: Colors.redAccent,
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
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    'Cerrar',
                    style: TextStyle(color: _branding.primary),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _branding.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: guardando || eliminando
                      ? null
                      : guardarCertificado,
                  child: guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Guardar certificado'),
                ),
              ],
            );
          },
        );
      },
    );

    accountPasswordController.dispose();
    certificatePasswordController.dispose();
  }

  void _handleLogout() {
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  Future<void> _showSettingsPanel() async {
    if (_isWebLayout) {
      await showDialog<void>(
        context: context,
        builder: (panelContext) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: _buildSettingsContent(panelContext, isDialog: true),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (panelContext) =>
          _buildSettingsContent(panelContext, isDialog: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _perfilFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: _branding.primary),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Ocurrio un error inesperado',
              style: TextStyle(color: _cardForeground),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return Center(
            child: Text(
              'No se pudo cargar la informacion',
              style: TextStyle(color: _cardForeground),
            ),
          );
        }

        final datos = snapshot.data!;
        final nombre = UserRoleAccess.displayNameForUser(datos);
        final rol = UserRoleAccess.displayRoleForUser(datos);
        final sede = _resolveSede(datos);
        final descripcion = _buildProfileDescription(datos);

        if (_isWebLayout) {
          return _buildWebLayout(
            datos: datos,
            nombre: nombre,
            rol: rol,
            sede: sede,
            descripcion: descripcion,
          );
        }

        return _buildMobileLayout(
          datos: datos,
          nombre: nombre,
          rol: rol,
          sede: sede,
          descripcion: descripcion,
        );
      },
    );
  }

  Widget _buildMobileLayout({
    required Map<String, dynamic> datos,
    required String nombre,
    required String rol,
    required String sede,
    required String descripcion,
  }) {
    return Scaffold(
      backgroundColor: _pageBackground,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              children: [
                Container(
                  height: 320,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_branding.primary, _branding.primaryDark],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(45),
                      bottomRight: Radius.circular(45),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const SizedBox(width: 48),
                            const Expanded(
                              child: Center(
                                child: Text(
                                  'MI PERFIL',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            _buildHeaderSettingsButton(),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.white24,
                            shape: BoxShape.circle,
                          ),
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.white,
                            child: Icon(
                              Icons.person_outline_rounded,
                              size: 60,
                              color: _branding.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          nombre,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _buildHeaderChip(rol.toUpperCase()),
                            _buildHeaderChip(sede),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildSectionIntro(
                  title: 'Informacion del perfil',
                  subtitle: descripcion,
                ),
                const SizedBox(height: 20),
                _buildMobileSection(
                  title: 'Perfil laboral',
                  items: _buildLaborFields(datos, rol),
                ),
                const SizedBox(height: 22),
                _buildMobileSection(
                  title: 'Contacto y cuenta',
                  items: _buildContactFields(datos, sede),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebLayout({
    required Map<String, dynamic> datos,
    required String nombre,
    required String rol,
    required String sede,
    required String descripcion,
  }) {
    return Container(
      color: _pageBackground,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWebHero(nombre: nombre, rol: rol, sede: sede),
                const SizedBox(height: 24),
                _buildSectionIntro(
                  title: 'Informacion del perfil',
                  subtitle: descripcion,
                ),
                const SizedBox(height: 18),
                _buildWebSection(
                  title: 'Perfil laboral',
                  items: _buildLaborFields(datos, rol),
                ),
                const SizedBox(height: 22),
                _buildWebSection(
                  title: 'Contacto y cuenta',
                  items: _buildContactFields(datos, sede),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_ProfileField> _buildLaborFields(
    Map<String, dynamic> datos,
    String rol,
  ) {
    return [
      _ProfileField(
        icon: Icons.apartment_outlined,
        label: 'Departamento',
        value: _resolveDepartment(datos),
        fullWidth: true,
      ),
      _ProfileField(
        icon: Icons.badge_outlined,
        label: 'Cargo',
        value: _resolveCargo(datos),
        fullWidth: true,
      ),
      _ProfileField(
        icon: Icons.verified_user_outlined,
        label: 'Rol',
        value: rol,
      ),
    ];
  }

  List<_ProfileField> _buildContactFields(
    Map<String, dynamic> datos,
    String sede,
  ) {
    return [
      _ProfileField(
        icon: Icons.badge_rounded,
        label: 'Cedula',
        value: _resolveCedula(datos),
      ),
      _ProfileField(
        icon: Icons.email_outlined,
        label: 'Correo institucional',
        value: _resolveCorreo(datos),
        fullWidth: true,
      ),
      _ProfileField(
        icon: Icons.smartphone_rounded,
        label: 'Telefono',
        value: _resolveTelefono(datos),
      ),
      _ProfileField(
        icon: Icons.location_on_outlined,
        label: 'Sede',
        value: sede,
      ),
    ];
  }

  String _buildProfileDescription(Map<String, dynamic> datos) {
    final departamento = _resolveDepartment(datos);
    final cargo = _resolveCargo(datos);
    return 'Los datos de departamento, cargo y cedula se sincronizan desde Gestion de personal. Actualmente estas asignado a $departamento${cargo == 'Sin cargo' ? '' : ' como $cargo'}.';
  }

  Widget _buildWebHero({
    required String nombre,
    required String rol,
    required String sede,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_branding.primary, _branding.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: _branding.primary.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'MI PERFIL',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              _buildHeaderSettingsButton(),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white38),
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  color: Colors.white,
                  size: 42,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _buildHeaderChip(rol.toUpperCase()),
                        _buildHeaderChip(sede),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionIntro({required String title, required String subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: _isWebLayout ? 22 : 18,
            fontWeight: FontWeight.w800,
            color: _cardForeground,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(fontSize: 14, height: 1.45, color: _mutedForeground),
        ),
      ],
    );
  }

  Widget _buildMobileSection({
    required String title,
    required List<_ProfileField> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: _branding.primary,
          ),
        ),
        const SizedBox(height: 14),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _buildInfoCard(item),
          ),
        ),
      ],
    );
  }

  Widget _buildWebSection({
    required String title,
    required List<_ProfileField> items,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 860;
        final halfWidth = wide
            ? (constraints.maxWidth - 16) / 2
            : constraints.maxWidth;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _cardForeground,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: items
                  .map(
                    (item) => SizedBox(
                      width: item.fullWidth || !wide
                          ? constraints.maxWidth
                          : halfWidth,
                      child: _buildWebInfoCard(item),
                    ),
                  )
                  .toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeaderSettingsButton() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _showSettingsPanel,
      child: Ink(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white38),
        ),
        child: const Icon(
          Icons.settings_outlined,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }

  Widget _buildHeaderChip(String label) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white38),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsContent(
    BuildContext panelContext, {
    required bool isDialog,
  }) {
    return AnimatedBuilder(
      animation: AppThemeController.instance,
      builder: (context, _) {
        final mediaQuery = MediaQuery.of(context);
        final maxHeight =
            mediaQuery.size.height -
            mediaQuery.viewInsets.vertical -
            (isDialog ? 48 : 24);

        return SafeArea(
          child: SizedBox(
            width: isDialog ? 420 : double.infinity,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: maxHeight < 320 ? 320 : maxHeight,
              ),
              child: Scrollbar(
                thumbVisibility: isDialog,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Configuracion de cuenta',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: _cardForeground,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () => Navigator.of(panelContext).pop(),
                            icon: Icon(
                              Icons.close_rounded,
                              color: _mutedForeground,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Desde aqui puedes cambiar tu contrasena, administrar tu certificado digital, cerrar sesion o activar el modo oscuro.',
                        style: TextStyle(color: _mutedForeground, height: 1.4),
                      ),
                      const SizedBox(height: 18),
                      _buildSettingsActionCard(
                        icon: Icons.lock_reset_rounded,
                        title: 'Cambiar contrasena',
                        subtitle:
                            'Actualiza tu clave de acceso de forma segura.',
                        onTap: () async {
                          Navigator.of(panelContext).pop();
                          await _handleChangePassword();
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildSettingsActionCard(
                        icon: Icons.verified_user_outlined,
                        title: 'Certificado .p12',
                        subtitle:
                            'Registra tu certificado digital legal para firmar PDFs con validez criptografica.',
                        onTap: () async {
                          Navigator.of(panelContext).pop();
                          await _handleManageDigitalCertificate();
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildThemeToggleCard(),
                      const SizedBox(height: 12),
                      _buildSettingsActionCard(
                        icon: Icons.logout_rounded,
                        title: 'Cerrar sesion',
                        subtitle: 'Salir de la aplicacion y volver al inicio.',
                        accentColor: Colors.redAccent,
                        onTap: () {
                          Navigator.of(panelContext).pop();
                          _handleLogout();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? accentColor,
  }) {
    final color = accentColor ?? _branding.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _outlineColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _isDarkMode ? 0.12 : 0.04),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
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
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: accentColor == null ? _cardForeground : color,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: _mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: _mutedForeground),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeToggleCard() {
    final enabled = AppThemeController.instance.isDarkMode;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _outlineColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDarkMode ? 0.12 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _branding.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              enabled ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              color: _branding.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Modo oscuro',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _cardForeground,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  enabled
                      ? 'La aplicacion usara el tema oscuro.'
                      : 'La aplicacion usara el tema claro.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: _mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: enabled,
            activeThumbColor: _branding.primary,
            onChanged: AppThemeController.instance.toggleDarkMode,
          ),
        ],
      ),
    );
  }

  Widget _buildWebInfoCard(_ProfileField item) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _outlineColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDarkMode ? 0.10 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: _branding.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(item.icon, color: _branding.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _mutedForeground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _cardForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(_ProfileField item) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _outlineColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDarkMode ? 0.10 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _softPanel,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(item.icon, color: _branding.primary, size: 22),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: _mutedForeground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _cardForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileField {
  const _ProfileField({
    required this.icon,
    required this.label,
    required this.value,
    this.fullWidth = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool fullWidth;
}
