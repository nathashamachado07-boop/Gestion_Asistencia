import 'dart:math';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/app_branding.dart';
import '../screens/registro_asistencia_screen.dart';
import '../services/firebase_service.dart';
import 'web_storage_stub.dart'
    if (dart.library.html) 'web_storage_web.dart';
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
  static const String _storageCorreo = 'intesud_web_correo';
  static const String _storagePassword = 'intesud_web_password';
  static const String _storageRecordar = 'intesud_web_recordar_password';

  final TextEditingController _correoController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final FirebaseService _service = FirebaseService();
  final Random _random = Random();

  bool _cargando = false;
  bool _recordarme = false;
  bool _mostrarPassword = false;

  String? _codigoRecuperacion;
  String? _correoRecuperacion;
  DateTime? _expiracionCodigo;

  AppBranding get _branding => AppBranding.matriz;

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
    _passController.text = webStorageGet(_storagePassword) ?? '';
    _recordarme = true;
  }

  void _guardarCredencialesRecordadas() {
    webStorageSet(_storageRecordar, _recordarme.toString());

    if (_recordarme) {
      webStorageSet(_storageCorreo, _correoController.text.trim());
      webStorageSet(_storagePassword, _passController.text);
    } else {
      webStorageRemove(_storageCorreo);
      webStorageRemove(_storagePassword);
      webStorageRemove(_storageRecordar);
    }
  }

  String _generarCodigoRecuperacion() {
    return List.generate(6, (_) => _random.nextInt(10)).join();
  }

  Future<void> _iniciarSesionWeb() async {
    setState(() => _cargando = true);

    final datosUsuario = await _service.validarLogin(
      _correoController.text.trim(),
      _passController.text.trim(),
    );

    setState(() => _cargando = false);

    if (datosUsuario == null) {
      _mostrarError('Correo o contrasena incorrectos.');
      return;
    }

    _guardarCredencialesRecordadas();

    final rol = (datosUsuario['rol'] ?? '').toString().trim().toUpperCase();
    if (!mounted) return;

    if (UserRoleAccess.canUseAdminPanel(datosUsuario)) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => AdminLayout(
            userData: datosUsuario,
          ),
        ),
      );
      return;
    }

    if (!UserRoleAccess.canUseEmployeePortal(datosUsuario['rol'])) {
      _mostrarError('Este usuario no tiene acceso habilitado para la web.');
      return;
    }

    final nombre = (datosUsuario['nombre'] ?? 'Usuario').toString();
    final correo =
        (datosUsuario['correo'] ?? _correoController.text.trim()).toString();
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
          sedeId: sedeId,
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
        'Ingrese su correo registrado para generar un codigo temporal de recuperacion.';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> generarCodigo() async {
              final correo = correoController.text.trim().toLowerCase();
              if (correo.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ingrese el correo del usuario.'),
                    backgroundColor: Colors.redAccent,
                  ),
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

                codigoTemporalVisible = codigo;
                mensajeAyuda =
                    'Codigo temporal generado. En esta instalacion aun no hay un servicio de correo configurado, por eso el codigo se muestra aqui para completar la recuperacion en la web.';
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$e'.replaceAll('Exception: ', '')),
                    backgroundColor: Colors.redAccent,
                  ),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Complete todos los campos de recuperacion.'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }

              if (_codigoRecuperacion == null ||
                  _correoRecuperacion == null ||
                  _expiracionCodigo == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Primero debe generar un codigo temporal.'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }

              if (_correoRecuperacion != correo) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'El correo no coincide con el codigo generado.',
                    ),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }

              if (DateTime.now().isAfter(_expiracionCodigo!)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'El codigo temporal ya expiro. Genere uno nuevo.',
                    ),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }

              if (_codigoRecuperacion != codigo) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('El codigo ingresado no es correcto.'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }

              if (nuevaPassword != confirmarPassword) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Las contrasenas no coinciden.'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }

              setDialogState(() => guardandoPassword = true);

              try {
                await _service.actualizarPasswordPorCorreo(
                  correo: correo,
                  nuevaPassword: nuevaPassword,
                );

                if (_recordarme &&
                    _correoController.text.trim().toLowerCase() == correo) {
                  _passController.text = nuevaPassword;
                  _guardarCredencialesRecordadas();
                }

                if (_correoController.text.trim().toLowerCase() == correo) {
                  _passController.text = nuevaPassword;
                }

                if (!context.mounted) return;
                Navigator.pop(context);
                _mostrarInfo(
                  'Contrasena actualizada correctamente. Ya puede iniciar sesion con la nueva clave.',
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$e'.replaceAll('Exception: ', '')),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              } finally {
                setDialogState(() => guardandoPassword = false);
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
              title: Text(
                'Recuperar contrasena',
                style: TextStyle(
                  color: _branding.primaryDark,
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mensajeAyuda,
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.62),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: correoController,
                        decoration: _inputDecoration(
                          hintText: 'Correo registrado',
                        ),
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
                            color: _branding.surface.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: _branding.primary.withOpacity(0.14),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Codigo temporal',
                                style: TextStyle(
                                  color: _branding.primaryDark,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                codigoTemporalVisible,
                                style: TextStyle(
                                  color: _branding.primary,
                                  fontSize: 24,
                                  letterSpacing: 4,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Valido por 10 minutos.',
                                style: TextStyle(
                                  color: Colors.black.withOpacity(0.55),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: codigoController,
                          decoration: _inputDecoration(
                            hintText: 'Ingresa el codigo',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: nuevaPasswordController,
                          obscureText: !mostrarNuevaPassword,
                          decoration: _inputDecoration(
                            hintText: 'Nueva contrasena',
                            suffixIcon: IconButton(
                              onPressed: () {
                                setDialogState(() {
                                  mostrarNuevaPassword = !mostrarNuevaPassword;
                                });
                              },
                              icon: Icon(
                                mostrarNuevaPassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: confirmarPasswordController,
                          obscureText: !mostrarConfirmarPassword,
                          decoration: _inputDecoration(
                            hintText: 'Confirmar contrasena',
                            suffixIcon: IconButton(
                              onPressed: () {
                                setDialogState(() {
                                  mostrarConfirmarPassword =
                                      !mostrarConfirmarPassword;
                                });
                              },
                              icon: Icon(
                                mostrarConfirmarPassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
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
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cerrar'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _branding.primary,
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

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void _mostrarInfo(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
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
                      'Tecnologico Sudamericano',
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
                                'Portal institucional',
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
                              'Iniciar sesion',
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
                              'Accede con tu cuenta autorizada como Admin, RRHH, docente o personal administrativo.',
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
                        'Contrasena',
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
                          hintText: 'Ingresa tu contrasena',
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
                              color: Colors.black.withOpacity(0.35),
                              size: 20,
                            ),
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
                                onChanged: (val) {
                                  setState(() {
                                    _recordarme = val ?? false;
                                  });
                                  _guardarCredencialesRecordadas();
                                },
                              ),
                              const Text(
                                'Recordar contrasena',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: _abrirRecuperacionContrasena,
                            child: Text(
                              'Olvide mi contrasena',
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
                                  'Iniciar sesion',
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
