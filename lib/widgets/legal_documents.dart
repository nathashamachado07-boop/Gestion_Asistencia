import 'package:flutter/material.dart';

import '../models/app_branding.dart';
import '../services/firebase_service.dart';
import '../services/password_security_service.dart';

class LegalDocuments {
  static const String version = '2026-05-07';
  static const String lawName =
      'Ley Organica de Proteccion de Datos Personales del Ecuador';

  static List<String> purposesFor(String appName) {
    return <String>[
      'autenticacion y control de acceso al sistema $appName',
      'registro, consulta y auditoria de asistencias, horarios y solicitudes',
      'gestion de notificaciones institucionales y soporte operativo',
      'cumplimiento de obligaciones academicas, administrativas y de seguridad',
    ];
  }
}

Future<void> showLegalDocumentsDialog(
  BuildContext context, {
  required AppBranding branding,
  required String appName,
}) async {
  final purposes = LegalDocuments.purposesFor(appName);

  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        title: Text(
          'Terminos, condiciones y privacidad',
          style: TextStyle(
            color: branding.primaryDark,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _LegalSection(
                  title: '1. Alcance',
                  body:
                      'Este sistema gestiona datos necesarios para autenticar usuarios, administrar asistencias, horarios, solicitudes y notificaciones internas del entorno institucional.',
                ),
                _LegalSection(
                  title: '2. Datos tratados',
                  body:
                      'Pueden tratarse datos como nombre, correo institucional, rol, sede, horarios asignados, telefono, registros de asistencia, solicitudes y metadatos operativos relacionados con el uso del sistema.',
                ),
                _LegalSection(title: '3. Finalidades', bullets: purposes),
                _LegalSection(
                  title: '4. Consentimiento y base informativa',
                  body:
                      'Al aceptar e iniciar sesion, el titular declara haber sido informado sobre el tratamiento de sus datos personales para las finalidades operativas del sistema. Esta referencia se presenta en atencion al derecho de proteccion de datos reconocido en Ecuador y a la ${LegalDocuments.lawName}.',
                ),
                _LegalSection(
                  title: '5. Seguridad y confidencialidad',
                  body:
                      'La institucion adopta medidas tecnicas y organizativas para reducir accesos no autorizados, alteraciones, perdida o divulgacion indebida de la informacion. Las credenciales son personales e intransferibles.',
                ),
                _LegalSection(
                  title: '6. Responsabilidades del usuario',
                  bullets: const <String>[
                    'usar unicamente su cuenta autorizada',
                    'no compartir su contrasena ni permitir accesos de terceros',
                    'reportar incidentes o accesos no reconocidos al administrador o RRHH',
                    'mantener actualizados los datos estrictamente necesarios para su gestion institucional',
                  ],
                ),
                _LegalSection(
                  title: '7. Derechos del titular',
                  body:
                      'El titular puede solicitar revision, actualizacion o correccion de sus datos por los canales internos definidos por la institucion, sin perjuicio de los derechos previstos en la normativa ecuatoriana aplicable.',
                ),
                _LegalSection(
                  title: '8. Soporte y recuperacion de acceso',
                  body:
                      'La recuperacion de acceso utiliza codigos temporales de un solo uso enviados a dispositivos previamente vinculados. Si el titular no dispone de un dispositivo confiable activo, el restablecimiento debe gestionarse por un canal institucional verificado con el administrador del sistema o RRHH.',
                ),
                _LegalSection(
                  title: '9. Version del aviso',
                  body:
                      'Version ${LegalDocuments.version}. Se recomienda que este texto sea revisado y validado por asesoria legal institucional antes del despliegue definitivo.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cerrar', style: TextStyle(color: branding.primary)),
          ),
        ],
      );
    },
  );
}

Future<PasswordRecoveryDialogResult?> showPasswordRecoveryDialog(
  BuildContext context, {
  required AppBranding branding,
  required FirebaseService service,
  String initialEmail = '',
}) async {
  final correoController = TextEditingController(text: initialEmail.trim());
  final codigoController = TextEditingController();
  final nuevaPasswordController = TextEditingController();
  final confirmarPasswordController = TextEditingController();

  bool solicitandoCodigo = false;
  bool guardandoPassword = false;
  bool codigoEnviado = false;
  bool requiereSoporte = false;
  bool mostrarNuevaPassword = false;
  bool mostrarConfirmarPassword = false;
  String mensajeEstado =
      'Solicita un codigo temporal. Lo enviaremos al dispositivo movil que ya haya sido vinculado previamente con tu cuenta.';
  bool mensajeEsError = false;

  final result = await showDialog<PasswordRecoveryDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> solicitarCodigo() async {
            final correo = correoController.text.trim().toLowerCase();
            if (correo.isEmpty) {
              setDialogState(() {
                mensajeEstado = 'Ingresa el correo institucional del usuario.';
                mensajeEsError = true;
              });
              return;
            }

            setDialogState(() {
              solicitandoCodigo = true;
              mensajeEsError = false;
            });

            try {
              final response = await service.solicitarRecuperacionPassword(
                correo: correo,
              );

              if (!dialogContext.mounted) return;

              setDialogState(() {
                codigoEnviado = response.codeSent;
                requiereSoporte = response.requiresSupport;
                mensajeEstado = response.message;
                mensajeEsError = false;
              });
            } catch (error) {
              if (!dialogContext.mounted) return;

              setDialogState(() {
                mensajeEstado = '$error'.replaceAll('Exception: ', '');
                mensajeEsError = true;
              });
            } finally {
              if (dialogContext.mounted) {
                setDialogState(() => solicitandoCodigo = false);
              }
            }
          }

          Future<void> restablecerPassword() async {
            var cierreExitoso = false;
            final correo = correoController.text.trim().toLowerCase();
            final codigo = codigoController.text.trim();
            final nuevaPassword = nuevaPasswordController.text.trim();
            final confirmarPassword = confirmarPasswordController.text.trim();

            if (correo.isEmpty ||
                codigo.isEmpty ||
                nuevaPassword.isEmpty ||
                confirmarPassword.isEmpty) {
              setDialogState(() {
                mensajeEstado = 'Completa todos los campos de recuperacion.';
                mensajeEsError = true;
              });
              return;
            }

            if (nuevaPassword != confirmarPassword) {
              setDialogState(() {
                mensajeEstado = 'Las contrasenas no coinciden.';
                mensajeEsError = true;
              });
              return;
            }

            final validationMessage =
                PasswordSecurityService.validatePasswordStrength(nuevaPassword);
            if (validationMessage != null) {
              setDialogState(() {
                mensajeEstado = validationMessage;
                mensajeEsError = true;
              });
              return;
            }

            setDialogState(() {
              guardandoPassword = true;
              mensajeEsError = false;
            });

            try {
              await service.confirmarRecuperacionPassword(
                correo: correo,
                codigo: codigo,
                nuevaPassword: nuevaPassword,
              );

              if (!dialogContext.mounted) return;

              cierreExitoso = true;
              Navigator.of(dialogContext).pop(
                PasswordRecoveryDialogResult(
                  correo: correo,
                  nuevaPassword: nuevaPassword,
                ),
              );
            } catch (error) {
              if (!dialogContext.mounted) return;

              setDialogState(() {
                mensajeEstado = '$error'.replaceAll('Exception: ', '');
                mensajeEsError = true;
              });
            } finally {
              if (dialogContext.mounted && !cierreExitoso) {
                setDialogState(() => guardandoPassword = false);
              }
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
            ),
            title: Text(
              'Recuperacion segura de acceso',
              style: TextStyle(
                color: branding.primaryDark,
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
                    _buildStatusCard(
                      message: mensajeEstado,
                      branding: branding,
                      isError: mensajeEsError,
                    ),
                    const SizedBox(height: 16),
                    _buildDialogTextField(
                      controller: correoController,
                      hint: 'Correo institucional',
                      icon: Icons.email_outlined,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: solicitandoCodigo ? null : solicitarCodigo,
                        icon: solicitandoCodigo
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.phonelink_lock_outlined),
                        label: Text(
                          solicitandoCodigo
                              ? 'Enviando codigo...'
                              : 'Enviar codigo a mi dispositivo',
                        ),
                      ),
                    ),
                    if (codigoEnviado) ...[
                      const SizedBox(height: 16),
                      _buildDialogTextField(
                        controller: codigoController,
                        hint: 'Codigo temporal de 6 digitos',
                        icon: Icons.verified_user_outlined,
                        keyboardType: TextInputType.number,
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
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
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
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'La nueva contrasena debe tener minimo 8 caracteres, una mayuscula, una minuscula y un numero.',
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.58),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ] else if (requiereSoporte) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Si tu cuenta no tiene un dispositivo confiable activo, el restablecimiento debe gestionarse con RRHH o el administrador.',
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.60),
                          fontSize: 12.5,
                          height: 1.45,
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
                  'Cerrar',
                  style: TextStyle(color: branding.primary),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: branding.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: guardandoPassword || !codigoEnviado
                    ? null
                    : restablecerPassword,
                child: guardandoPassword
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Restablecer contrasena'),
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

  return result;
}

Future<bool> showChangePasswordDialog(
  BuildContext context, {
  required AppBranding branding,
  required FirebaseService service,
  required String correo,
}) async {
  final actualController = TextEditingController();
  final nuevaPasswordController = TextEditingController();
  final confirmarPasswordController = TextEditingController();

  bool guardando = false;
  bool mostrarActual = false;
  bool mostrarNueva = false;
  bool mostrarConfirmar = false;
  String mensajeEstado =
      'Confirma tu contrasena actual y define una nueva clave segura para tu cuenta.';
  bool mensajeEsError = false;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> cambiarPassword() async {
            var cierreExitoso = false;
            final actual = actualController.text.trim();
            final nueva = nuevaPasswordController.text.trim();
            final confirmar = confirmarPasswordController.text.trim();

            if (actual.isEmpty || nueva.isEmpty || confirmar.isEmpty) {
              setDialogState(() {
                mensajeEstado = 'Completa todos los campos.';
                mensajeEsError = true;
              });
              return;
            }

            if (nueva != confirmar) {
              setDialogState(() {
                mensajeEstado = 'Las contrasenas no coinciden.';
                mensajeEsError = true;
              });
              return;
            }

            final validationMessage =
                PasswordSecurityService.validatePasswordStrength(nueva);
            if (validationMessage != null) {
              setDialogState(() {
                mensajeEstado = validationMessage;
                mensajeEsError = true;
              });
              return;
            }

            setDialogState(() {
              guardando = true;
              mensajeEsError = false;
            });

            try {
              await service.cambiarPasswordConActual(
                correo: correo,
                passwordActual: actual,
                nuevaPassword: nueva,
              );

              if (!dialogContext.mounted) return;
              cierreExitoso = true;
              Navigator.of(dialogContext).pop(true);
            } catch (error) {
              if (!dialogContext.mounted) return;

              setDialogState(() {
                mensajeEstado = '$error'.replaceAll('Exception: ', '');
                mensajeEsError = true;
              });
            } finally {
              if (dialogContext.mounted && !cierreExitoso) {
                setDialogState(() => guardando = false);
              }
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
            ),
            title: Text(
              'Cambiar contrasena',
              style: TextStyle(
                color: branding.primaryDark,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatusCard(
                      message: mensajeEstado,
                      branding: branding,
                      isError: mensajeEsError,
                    ),
                    const SizedBox(height: 16),
                    _buildDialogTextField(
                      controller: actualController,
                      hint: 'Contrasena actual',
                      icon: Icons.lock_clock_outlined,
                      obscureText: !mostrarActual,
                      suffixIcon: IconButton(
                        onPressed: () {
                          setDialogState(() {
                            mostrarActual = !mostrarActual;
                          });
                        },
                        icon: Icon(
                          mostrarActual
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildDialogTextField(
                      controller: nuevaPasswordController,
                      hint: 'Nueva contrasena',
                      icon: Icons.lock_reset_outlined,
                      obscureText: !mostrarNueva,
                      suffixIcon: IconButton(
                        onPressed: () {
                          setDialogState(() {
                            mostrarNueva = !mostrarNueva;
                          });
                        },
                        icon: Icon(
                          mostrarNueva
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildDialogTextField(
                      controller: confirmarPasswordController,
                      hint: 'Confirmar nueva contrasena',
                      icon: Icons.lock_outline,
                      obscureText: !mostrarConfirmar,
                      suffixIcon: IconButton(
                        onPressed: () {
                          setDialogState(() {
                            mostrarConfirmar = !mostrarConfirmar;
                          });
                        },
                        icon: Icon(
                          mostrarConfirmar
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'La nueva contrasena debe tener minimo 8 caracteres, una mayuscula, una minuscula y un numero.',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.58),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(
                  'Cancelar',
                  style: TextStyle(color: branding.primary),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: branding.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: guardando ? null : cambiarPassword,
                child: guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Guardar contrasena'),
              ),
            ],
          );
        },
      );
    },
  );

  actualController.dispose();
  nuevaPasswordController.dispose();
  confirmarPasswordController.dispose();

  return result ?? false;
}

class PasswordRecoveryDialogResult {
  const PasswordRecoveryDialogResult({
    required this.correo,
    required this.nuevaPassword,
  });

  final String correo;
  final String nuevaPassword;
}

class LegalAcceptanceSection extends StatelessWidget {
  const LegalAcceptanceSection({
    super.key,
    required this.branding,
    required this.accepted,
    required this.onChanged,
    required this.onViewDocuments,
  });

  final AppBranding branding;
  final bool accepted;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onViewDocuments;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: branding.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accepted
              ? branding.primary.withValues(alpha: 0.28)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: accepted,
                activeColor: branding.primary,
                onChanged: onChanged,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'He leido y acepto los terminos, condiciones de uso y el aviso de proteccion de datos personales.',
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.72),
                      fontSize: 12.5,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: onViewDocuments,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Ver terminos y privacidad',
                    style: TextStyle(
                      color: branding.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  'Referencia informativa: ${LegalDocuments.lawName}.',
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.46),
                    fontSize: 11,
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

Widget _buildStatusCard({
  required String message,
  required AppBranding branding,
  required bool isError,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: isError
          ? Colors.redAccent.withValues(alpha: 0.08)
          : branding.surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: isError
            ? Colors.redAccent.withValues(alpha: 0.20)
            : branding.primary.withValues(alpha: 0.14),
      ),
    ),
    child: Text(
      message,
      style: TextStyle(
        color: isError
            ? Colors.redAccent
            : Colors.black.withValues(alpha: 0.72),
        height: 1.45,
        fontWeight: isError ? FontWeight.w600 : FontWeight.w500,
      ),
    ),
  );
}

Widget _buildDialogTextField({
  required TextEditingController controller,
  required String hint,
  required IconData icon,
  bool obscureText = false,
  Widget? suffixIcon,
  TextInputType? keyboardType,
}) {
  return TextField(
    controller: controller,
    obscureText: obscureText,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.grey[700]),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF6F7F8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade400, width: 1.2),
      ),
    ),
  );
}

class _LegalSection extends StatelessWidget {
  const _LegalSection({required this.title, this.body, this.bullets});

  final String title;
  final String? body;
  final List<String>? bullets;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 8),
          if (body != null) Text(body!, style: const TextStyle(height: 1.5)),
          if (bullets != null)
            ...bullets!.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('- $item', style: const TextStyle(height: 1.45)),
              ),
            ),
        ],
      ),
    );
  }
}
