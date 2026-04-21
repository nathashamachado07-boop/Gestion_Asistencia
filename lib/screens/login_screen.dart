import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/app_branding.dart';
import '../services/firebase_service.dart';
import '../web/admin_layout.dart';
import 'registro_asistencia_screen.dart';
import 'rrhh/nav_rrhh_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.appConfig = AppConfig.matriz,
  });

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
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  AppBranding get _branding => AppBranding.matriz;

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

  Future<void> _iniciarSesion() async {
    setState(() => _cargando = true);

    final datosUsuario = await _service.validarLogin(
      _correoController.text.trim(),
      _passController.text.trim(),
    );

    setState(() => _cargando = false);

    if (datosUsuario == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Correo o contrasena incorrectos')),
      );
      return;
    }

    if (!mounted) return;

    final rolDB = datosUsuario['rol']?.toString() ?? 'Docente';
    final rolLimpio = rolDB.trim().toUpperCase();
    final usuarioSedeId = SedeAccess.resolveSedeId(datosUsuario);

    if (rolLimpio == 'RRHH') {
      if (kIsWeb) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => AdminLayout(
              userData: datosUsuario,
            ),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => NavRRHHScreen()),
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

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => RegistroAsistenciaScreen(
          nombreDocente: nombre,
          horariosDocente: listaHorarios,
          correoUsuario: correo,
          sedeId: usuarioSedeId,
        ),
      ),
    );
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
                              color: Colors.black.withOpacity(0.1),
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
                              color: Colors.black.withOpacity(0.08),
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
                              hint: 'Contrasena',
                              icon: Icons.lock_outline,
                              isPassword: true,
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {},
                                child: Text(
                                  'Olvidaste tu contrasena?',
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
                        '${_branding.displayName} - Sistema de Gestion',
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
        contentPadding:
            const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
      ),
    );
  }
}
