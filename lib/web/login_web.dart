import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/app_branding.dart';
import '../screens/registro_asistencia_screen.dart';
import '../services/firebase_service.dart';
import '../widgets/legal_documents.dart';
import 'web_storage_stub.dart' if (dart.library.html) 'web_storage_web.dart';
import 'admin_layout.dart';

class LoginWeb extends StatefulWidget {
  const LoginWeb({super.key, this.appConfig = AppConfig.matriz});

  final AppConfig appConfig;

  @override
  State<LoginWeb> createState() => _LoginWebState();
}

class _LoginWebState extends State<LoginWeb> {
  static const String _storageCorreo = 'intesud_web_correo';
  static const String _storagePassword = 'intesud_web_password';
  static const String _storageRecordar = 'intesud_web_recordar_password';

  final TextEditingController _correoController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final FirebaseService _service = FirebaseService();

  bool _cargando = false;
  bool _recordarme = false;
  bool _mostrarPassword = false;
  bool _aceptaTerminos = false;

  AppBranding get _branding =>
      AppBranding.fromSedeId(widget.appConfig.defaultSedeId);

  @override
  void initState() {
    super.initState();
    _cargarCredencialesRecordadas();
  }

  @override
  void dispose() {
    _correoController.dispose();
    _passController.dispose();
    super.dispose();
  }

  void _cargarCredencialesRecordadas() {
    final recordar = webStorageGet(_storageRecordar) == 'true';
    if (!recordar) {
      return;
    }

    _correoController.text = webStorageGet(_storageCorreo) ?? '';
    webStorageRemove(_storagePassword);
    _recordarme = true;
  }

  void _guardarCredencialesRecordadas() {
    webStorageSet(_storageRecordar, _recordarme.toString());

    if (_recordarme) {
      webStorageSet(_storageCorreo, _correoController.text.trim());
      webStorageRemove(_storagePassword);
    } else {
      webStorageRemove(_storageCorreo);
      webStorageRemove(_storagePassword);
      webStorageRemove(_storageRecordar);
    }
  }

  Future<void> _iniciarSesionWeb() async {
    if (!_aceptaTerminos) {
      _mostrarError(
        'Debe aceptar los terminos y la politica de datos antes de iniciar sesión.',
      );
      return;
    }

    setState(() => _cargando = true);

    final datosUsuario = await _service.validarLogin(
      _correoController.text.trim(),
      _passController.text.trim(),
    );

    setState(() => _cargando = false);

    if (datosUsuario == null) {
      _mostrarError('Correo o contraseña incorrectos.');
      return;
    }

    await _registrarAceptacionLegal(datosUsuario);
    if (!mounted) return;
    _guardarCredencialesRecordadas();

    if (UserRoleAccess.canUseAdminPanel(datosUsuario)) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => AdminLayout(userData: datosUsuario),
        ),
      );
      return;
    }

    if (!UserRoleAccess.canUseEmployeePortal(datosUsuario['rol'])) {
      _mostrarError('Este usuario no tiene acceso habilitado para la web.');
      return;
    }

    final nombre = (datosUsuario['nombre'] ?? 'Usuario').toString();
    final correo = (datosUsuario['correo'] ?? _correoController.text.trim())
        .toString();
    final sedeId = SedeAccess.resolveSedeId(datosUsuario);
    final listaHorarios =
        (datosUsuario['horarios_asignados'] is List &&
            (datosUsuario['horarios_asignados'] as List).isNotEmpty)
        ? List<String>.from(datosUsuario['horarios_asignados'])
        : <String>['Sin horario asignado'];

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => RegistroAsistenciaScreen(
          nombreDocente: nombre,
          horariosDocente: listaHorarios,
          correoUsuario: correo,
          rolUsuario: datosUsuario['rol']?.toString(),
          sedeId: sedeId,
        ),
      ),
    );
  }

  Future<void> _abrirRecuperacionContrasena() async {
    final result = await showPasswordRecoveryDialog(
      context,
      branding: _branding,
      service: _service,
      initialEmail: _correoController.text,
    );

    if (result == null || !mounted) return;

    _correoController.text = result.correo;
    _passController.text = result.nuevaPassword;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Contraseña actualizada correctamente. Ya puedes iniciar sesión con la nueva clave.',
        ),
        backgroundColor: _branding.primary,
      ),
    );
  }

  Future<void> _mostrarTerminosYPrivacidad() async {
    await showLegalDocumentsDialog(
      context,
      branding: _branding,
      appName: widget.appConfig.appName,
    );
  }

  Future<void> _registrarAceptacionLegal(
    Map<String, dynamic> datosUsuario,
  ) async {
    final userDocId = (datosUsuario['docId'] ?? '').toString().trim();
    final correo = (datosUsuario['correo'] ?? _correoController.text.trim())
        .toString();

    if (userDocId.isEmpty || correo.trim().isEmpty) {
      return;
    }

    try {
      await _service.registrarAceptacionTerminos(
        userDocId: userDocId,
        correo: correo,
        version: LegalDocuments.version,
        canal: 'web',
      );
    } catch (_) {
      // No bloquea el acceso si falla el registro de consentimiento.
    }
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.46,
              child: Image.asset(
                'assets/images/imagen_fondo.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _branding.surface.withValues(alpha: 0.60),
              ),
            ),
          ),
          Positioned(
            left: 36,
            top: 28,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: _branding.primary.withValues(alpha: 0.10),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      'assets/images/logo_intesud.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Instituto Superior',
                      style: TextStyle(
                        color: _branding.primaryDark,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Tecnológico Sudamericano',
                      style: TextStyle(
                        color: _branding.primaryDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Quito',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.52),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Yo soy del INTESUD',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.42),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            left: 58,
            bottom: 20,
            child: Text(
              'Sistema institucional de asistencia',
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.35),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Positioned(
            right: 40,
            bottom: 20,
            child: Row(
              children: [
                _buildFooterLink(
                  'Privacidad',
                  onTap: _mostrarTerminosYPrivacidad,
                ),
                const SizedBox(width: 18),
                _buildFooterLink(
                  'Soporte',
                  onTap: _abrirRecuperacionContrasena,
                ),
              ],
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Container(
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.97),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: _branding.primary.withValues(alpha: 0.10),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _branding.primary.withValues(alpha: 0.12),
                        blurRadius: 36,
                        offset: const Offset(0, 20),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _branding.surface.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _branding.primary.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: _branding.primary.withValues(alpha: 0.18),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _branding.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    'Portal institucional',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _branding.primaryDark,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Iniciar sesión',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _branding.primaryDark,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                height: 1.05,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Accede con tu cuenta autorizada como Admin, RRHH, docente o personal administrativo.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black.withValues(alpha: 0.55),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),
                      const Text(
                        'Usuario',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF233133),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _correoController,
                        decoration: _inputDecoration(
                          hintText: 'Ingresa tu usuario',
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Contraseña',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF233133),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _passController,
                        obscureText: !_mostrarPassword,
                        decoration: _inputDecoration(
                          hintText: 'Ingresa tu contraseña',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _mostrarPassword = !_mostrarPassword;
                              });
                            },
                            icon: Icon(
                              _mostrarPassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: Colors.black.withValues(alpha: 0.35),
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      LegalAcceptanceSection(
                        branding: _branding,
                        accepted: _aceptaTerminos,
                        onChanged: (value) {
                          setState(() {
                            _aceptaTerminos = value ?? false;
                          });
                        },
                        onViewDocuments: _mostrarTerminosYPrivacidad,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Checkbox(
                                value: _recordarme,
                                activeColor: _branding.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                onChanged: (val) {
                                  setState(() {
                                    _recordarme = val ?? false;
                                  });
                                  _guardarCredencialesRecordadas();
                                },
                              ),
                              const Text(
                                'Recordar correo',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: _abrirRecuperacionContrasena,
                            child: Text(
                              'Olvide mi contraseña',
                              style: TextStyle(
                                color: _branding.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: _branding.primary,
                            shadowColor: _branding.primary.withValues(alpha: 0.35),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _cargando ? null : _iniciarSesionWeb,
                          child: _cargando
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.2,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'Iniciando sesión...',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      'Iniciar sesión',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.arrow_forward_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: Colors.black.withValues(alpha: 0.35),
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: _branding.surface.withValues(alpha: 0.70),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: _branding.primary.withValues(alpha: 0.10),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: _branding.primary.withValues(alpha: 0.12),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _branding.primary, width: 1.8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  Widget _buildFooterLink(String label, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.42),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}