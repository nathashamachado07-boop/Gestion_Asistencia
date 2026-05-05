import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/app_branding.dart';
import '../services/firebase_service.dart';
import '../services/push_notification_service.dart';
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
  final Random _random = Random();
  bool _cargando = false;
  bool _mostrarPassword = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  String? _codigoRecuperacion;
  String? _correoRecuperacion;
  DateTime? _expiracionCodigo;

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

  String _generarCodigoRecuperacion() {
    return List.generate(6, (_) => _random.nextInt(10)).join();
  }

  void _mostrarMensaje(
    String mensaje, {
    Color backgroundColor = Colors.black87,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: backgroundColor,
      ),
    );
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
    final usuarioSedeId = SedeAccess.resolveSedeId(datosUsuario);

    if (!kIsWeb) {
      await PushNotificationService.instance.identifyUser(
        correo: _correoController.text.trim(),
        sedeId: usuarioSedeId,
      );
    }

    if (UserRoleAccess.canUseAdminPanel(datosUsuario)) {
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
        const SnackBar(content: Text('Este usuario no tiene acceso habilitado.')),
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
          sedeId: usuarioSedeId,
        ),
      ),
    );
  }

  Future<void> _abrirRecuperacionContrasena() async {
    final correoController = TextEditingController(
      text: _correoController.text.trim(),
    );
    final codigoController = TextEditingController();
    final nuevaPasswordController = TextEditingController();
    final confirmarPasswordController = TextEditingController();

    bool generandoCodigo = false;
    bool guardandoPassword = false;
    bool mostrarNuevaPassword = false;
    bool mostrarConfirmarPassword = false;
    String codigoTemporalVisible = '';
    String mensajeAyuda =
        'Ingrese su correo registrado para generar un codigo temporal de 6 digitos.';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> generarCodigo() async {
              final correo = correoController.text.trim().toLowerCase();
              if (correo.isEmpty) {
                _mostrarMensaje(
                  'Ingrese el correo del usuario.',
                  backgroundColor: Colors.redAccent,
                );
                return;
              }

              setDialogState(() => generandoCodigo = true);

              try {
                final usuario = await _service.obtenerUsuarioPorCorreo(correo);
                if (usuario == null) {
                  throw Exception(
                    'No existe un usuario registrado con ese correo.',
                  );
                }

                final codigo = _generarCodigoRecuperacion();
                _codigoRecuperacion = codigo;
                _correoRecuperacion = correo;
                _expiracionCodigo = DateTime.now().add(
                  const Duration(minutes: 10),
                );

                setDialogState(() {
                  codigoTemporalVisible = codigo;
                  mensajeAyuda =
                      'Se genero un codigo temporal de 6 digitos. Ingreselo para poder cambiar la contrasena.';
                });
              } catch (e) {
                _mostrarMensaje(
                  '$e'.replaceAll('Exception: ', ''),
                  backgroundColor: Colors.redAccent,
                );
              } finally {
                setDialogState(() => generandoCodigo = false);
              }
            }

            Future<void> actualizarPassword() async {
              final correo = correoController.text.trim().toLowerCase();
              final codigo = codigoController.text.trim();
              final nuevaPassword = nuevaPasswordController.text.trim();
              final confirmarPassword =
                  confirmarPasswordController.text.trim();

              if (correo.isEmpty ||
                  codigo.isEmpty ||
                  nuevaPassword.isEmpty ||
                  confirmarPassword.isEmpty) {
                _mostrarMensaje(
                  'Complete todos los campos de recuperacion.',
                  backgroundColor: Colors.redAccent,
                );
                return;
              }

              if (_codigoRecuperacion == null ||
                  _correoRecuperacion == null ||
                  _expiracionCodigo == null) {
                _mostrarMensaje(
                  'Primero debe generar un codigo temporal.',
                  backgroundColor: Colors.redAccent,
                );
                return;
              }

              if (_correoRecuperacion != correo) {
                _mostrarMensaje(
                  'El correo no coincide con el codigo generado.',
                  backgroundColor: Colors.redAccent,
                );
                return;
              }

              if (DateTime.now().isAfter(_expiracionCodigo!)) {
                _mostrarMensaje(
                  'El codigo temporal ya expiro. Genere uno nuevo.',
                  backgroundColor: Colors.redAccent,
                );
                return;
              }

              if (_codigoRecuperacion != codigo) {
                _mostrarMensaje(
                  'El codigo ingresado no es correcto.',
                  backgroundColor: Colors.redAccent,
                );
                return;
              }

              if (nuevaPassword != confirmarPassword) {
                _mostrarMensaje(
                  'Las contrasenas no coinciden.',
                  backgroundColor: Colors.redAccent,
                );
                return;
              }

              setDialogState(() => guardandoPassword = true);

              try {
                await _service.actualizarPasswordPorCorreo(
                  correo: correo,
                  nuevaPassword: nuevaPassword,
                );

                _correoController.text = correo;
                _passController.text = nuevaPassword;
                _codigoRecuperacion = null;
                _correoRecuperacion = null;
                _expiracionCodigo = null;

                if (!mounted) return;
                Navigator.of(dialogContext).pop();
                _mostrarMensaje(
                  'Contrasena actualizada correctamente. Ya puede iniciar sesion con la nueva clave.',
                  backgroundColor: _branding.primary,
                );
              } catch (e) {
                _mostrarMensaje(
                  '$e'.replaceAll('Exception: ', ''),
                  backgroundColor: Colors.redAccent,
                );
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() => guardandoPassword = false);
                }
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
              title: Text(
                'Recuperar contrasena',
                style: TextStyle(
                  color: _branding.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mensajeAyuda,
                        style: const TextStyle(
                          color: Colors.black54,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildDialogTextField(
                        controller: correoController,
                        hint: 'Correo registrado',
                        icon: Icons.email_outlined,
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: generandoCodigo ? null : generarCodigo,
                          icon: generandoCodigo
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.mark_email_read_outlined),
                          label: Text(
                            generandoCodigo
                                ? 'Generando codigo...'
                                : 'Generar codigo',
                          ),
                        ),
                      ),
                      if (codigoTemporalVisible.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _branding.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: _branding.primary.withOpacity(0.18),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Codigo temporal',
                                style: TextStyle(
                                  color: _branding.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                codigoTemporalVisible,
                                style: TextStyle(
                                  color: _branding.primary,
                                  fontSize: 24,
                                  letterSpacing: 6,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Valido por 10 minutos.',
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _buildDialogTextField(
                          controller: codigoController,
                          hint: 'Codigo de 6 digitos',
                          icon: Icons.verified_user_outlined,
                        ),
                        const SizedBox(height: 12),
                        _buildDialogTextField(
                          controller: nuevaPasswordController,
                          hint: 'Nueva contrasena',
                          icon: Icons.lock_reset_outlined,
                          obscureText: !mostrarNuevaPassword,
                          suffixIcon: IconButton(
                            onPressed: () {
                              setDialogState(() {
                                mostrarNuevaPassword = !mostrarNuevaPassword;
                              });
                            },
                            icon: Icon(
                              mostrarNuevaPassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildDialogTextField(
                          controller: confirmarPasswordController,
                          hint: 'Confirmar contrasena',
                          icon: Icons.lock_outline,
                          obscureText: !mostrarConfirmarPassword,
                          suffixIcon: IconButton(
                            onPressed: () {
                              setDialogState(() {
                                mostrarConfirmarPassword =
                                    !mostrarConfirmarPassword;
                              });
                            },
                            icon: Icon(
                              mostrarConfirmarPassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(color: _branding.primary),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _branding.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: guardandoPassword || codigoTemporalVisible.isEmpty
                      ? null
                      : actualizarPassword,
                  child: guardandoPassword
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Cambiar contrasena'),
                ),
              ],
            );
          },
        );
      },
    );

    correoController.dispose();
    codigoController.dispose();
    nuevaPasswordController.dispose();
    confirmarPasswordController.dispose();
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
                                onPressed: _abrirRecuperacionContrasena,
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

  Widget _buildDialogTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: _branding.primary),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: _branding.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _branding.primary, width: 1.4),
        ),
      ),
    );
  }
}
