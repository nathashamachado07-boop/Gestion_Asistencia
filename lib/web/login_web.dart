import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/app_branding.dart';
import '../services/firebase_service.dart';
import 'admin_layout.dart';

class LoginWeb extends StatefulWidget {
  const LoginWeb({
    super.key,
    this.appConfig = AppConfig.matriz,
  });

  final AppConfig appConfig;

  @override
  State<LoginWeb> createState() => _LoginWebState();
}

class _LoginWebState extends State<LoginWeb> {
  final TextEditingController _correoController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final FirebaseService _service = FirebaseService();

  bool _cargando = false;
  bool _recordarme = false;

  AppBranding get _branding => AppBranding.matriz;

  @override
  void dispose() {
    _correoController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _iniciarSesionWeb() async {
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

    final rol = (datosUsuario['rol'] ?? '').toString().trim().toUpperCase();
    if (rol != 'RRHH') {
      _mostrarError('Acceso denegado. Este panel es exclusivo para RRHH.');
      return;
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => AdminLayout(
          userData: datosUsuario,
        ),
      ),
    );
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
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
                color: _branding.surface.withOpacity(0.60),
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
                    color: Colors.white.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: _branding.primary.withOpacity(0.10),
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
                        color: Colors.black.withOpacity(0.52),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Yo soy del INTESUD',
                      style: TextStyle(
                        color: Colors.black.withOpacity(0.42),
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
                color: Colors.black.withOpacity(0.35),
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
                _buildFooterLink('Privacidad'),
                const SizedBox(width: 18),
                _buildFooterLink('Soporte'),
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
                    color: Colors.white.withOpacity(0.97),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: _branding.primary.withOpacity(0.10),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _branding.primary.withOpacity(0.12),
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
                          color: _branding.surface.withOpacity(0.96),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: _branding.primary.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Panel institucional',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _branding.primaryDark,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Iniciar sesión',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _branding.primaryDark,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Accede al sistema de asistencia y reportes con tu cuenta autorizada.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black.withOpacity(0.55),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                height: 1.45,
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
                        obscureText: true,
                        decoration: _inputDecoration(
                          hintText: 'Ingresa tu contraseña',
                          suffixIcon: Icon(
                            Icons.visibility_off_outlined,
                            color: Colors.black.withOpacity(0.35),
                            size: 20,
                          ),
                        ),
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
                                onChanged: (val) =>
                                    setState(() => _recordarme = val ?? false),
                              ),
                              const Text(
                                'Mantener sesión',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () {},
                            child: Text(
                              'Olvidé mi contraseña',
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
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: _branding.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _cargando ? null : _iniciarSesionWeb,
                          child: _cargando
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text(
                                  'Iniciar sesión',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
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
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: _branding.surface.withOpacity(0.70),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: _branding.primary.withOpacity(0.10),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: _branding.primary.withOpacity(0.10),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: _branding.primary,
          width: 1.5,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 15,
      ),
    );
  }

  Widget _buildFooterLink(String label) {
    return Text(
      label,
      style: TextStyle(
        color: Colors.black.withOpacity(0.42),
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    );
  }

}
