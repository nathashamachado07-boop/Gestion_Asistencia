import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/app_branding.dart';
import '../services/firebase_service.dart';
import '../services/push_notification_service.dart';
import '../widgets/legal_documents.dart';
import '../web/admin_layout.dart';
import 'registro_asistencia_screen.dart';
import 'rrhh/nav_rrhh_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.appConfig = AppConfig.matriz});

  final AppConfig appConfig;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _correoController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final FirebaseService _service = FirebaseService();
  bool _cargando = false;
  bool _mostrarPassword = false;
  bool _aceptaTerminos = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  AppBranding get _branding =>
      AppBranding.fromSedeId(widget.appConfig.defaultSedeId);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _correoController.dispose();
    _passController.dispose();
    super.dispose();
  }

  void _mostrarMensaje(
    String mensaje, {
    Color backgroundColor = Colors.black87,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: backgroundColor),
    );
  }

  Future<void> _iniciarSesion() async {
    if (!_aceptaTerminos) {
      _mostrarMensaje(
        'Debe aceptar los terminos y la politica de datos antes de iniciar sesion.',
        backgroundColor: Colors.redAccent,
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Correo o contraseña incorrectos')),
      );
      return;
    }

    if (!mounted) return;

    await _registrarAceptacionLegal(datosUsuario);
    if (!mounted) return;

    final rolDB = datosUsuario['rol']?.toString() ?? 'Docente';
    final usuarioSedeId = SedeAccess.resolveSedeId(datosUsuario);

    if (!kIsWeb) {
      await PushNotificationService.instance.identifyUser(
        correo: _correoController.text.trim(),
        sedeId: usuarioSedeId,
      );
    }
    if (!mounted) return;

    if (UserRoleAccess.canUseAdminPanel(datosUsuario)) {
      if (kIsWeb) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => AdminLayout(userData: datosUsuario),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => NavRRHHScreen(userData: datosUsuario),
          ),
        );
      }
      return;
    }

    final nombre = datosUsuario['nombre'] ?? 'Usuario';
    final correo = _correoController.text.trim();

    List<String> listaHorarios = [];
    if (datosUsuario['horarios_asignados'] != null &&
        datosUsuario['horarios_asignados'] is List) {
      listaHorarios = List<String>.from(datosUsuario['horarios_asignados']);
    } else {
      listaHorarios = ['Sin horario asignado'];
    }

    if (!UserRoleAccess.canUseEmployeePortal(rolDB)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este usuario no tiene acceso habilitado.'),
        ),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => RegistroAsistenciaScreen(
          nombreDocente: nombre,
          horariosDocente: listaHorarios,
          correoUsuario: correo,
          rolUsuario: rolDB,
          sedeId: usuarioSedeId,
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

    _mostrarMensaje(
      'Contrasena actualizada correctamente. Ya puedes iniciar sesion con la nueva clave.',
      backgroundColor: _branding.primary,
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
        canal: 'app',
      );
    } catch (_) {
      // No bloquea el acceso si falla el registro de consentimiento.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _branding.surface,
      body: Stack(
        children: [
          Container(
            height: MediaQuery.of(context).size.height * 0.45,
            decoration: BoxDecoration(
              color: _branding.primary,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(60),
                bottomRight: Radius.circular(60),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: Image.asset(
                          _branding.logoHeader,
                          width: 90,
                          height: 90,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            Icons.school,
                            color: _branding.primary,
                            size: 50,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _branding.displayName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      Text(
                        _branding.subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 35),
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 25,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Bienvenido',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: _branding.primary,
                              ),
                            ),
                            const SizedBox(height: 25),
                            _buildTextField(
                              controller: _correoController,
                              hint: 'Correo institucional',
                              icon: Icons.email_outlined,
                            ),
                            const SizedBox(height: 18),
                            _buildTextField(
                              controller: _passController,
                              hint: 'Contraseña',
                              icon: Icons.lock_outline,
                              isPassword: true,
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
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _abrirRecuperacionContrasena,
                                child: Text(
                                  'Olvidaste tu contraseña?',
                                  style: TextStyle(
                                    color: _branding.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              height: 55,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _branding.primary,
                                  foregroundColor: Colors.white,
                                  elevation: 4,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                onPressed: _cargando ? null : _iniciarSesion,
                                child: _cargando
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : const Text(
                                        'INICIAR SESION',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          letterSpacing: 1,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                      Text(
                        '${_branding.displayName} - Sistema de Gestión',
                        style: TextStyle(
                          color: _branding.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 24),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword && !_mostrarPassword,
      style: const TextStyle(fontSize: 15, color: Colors.black87),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
        prefixIcon: Icon(icon, color: _branding.primary, size: 22),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _mostrarPassword ? Icons.visibility : Icons.visibility_off,
                  color: Colors.grey,
                  size: 22,
                ),
                onPressed: () =>
                    setState(() => _mostrarPassword = !_mostrarPassword),
              )
            : null,
        filled: true,
        fillColor: _branding.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: _branding.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 18,
          horizontal: 20,
        ),
      ),
    );
  }
}
