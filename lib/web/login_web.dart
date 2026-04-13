import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import 'admin_layout.dart';

class LoginWeb extends StatefulWidget {
  const LoginWeb({super.key});

  @override
  State<LoginWeb> createState() => _LoginWebState();
}

class _LoginWebState extends State<LoginWeb> {
  final TextEditingController _correoController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final FirebaseService _service = FirebaseService();
  bool _cargando = false;
  bool _recordarme = false; // Para el checkbox

  // El color institucional exacto del diseño
  static const Color _primary = Color(0xFF467879);

  void _iniciarSesionWeb() async {
    setState(() => _cargando = true);

    var datosUsuario = await _service.validarLogin(
      _correoController.text.trim(),
      _passController.text.trim(),
    );

    setState(() => _cargando = false);

    if (datosUsuario != null) {
      String rol = (datosUsuario['rol'] ?? '').toString().trim().toUpperCase();

      if (rol == 'RRHH') {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const AdminLayout()),
        );
      } else {
        _mostrarError("Acceso denegado. Este panel es exclusivo para RRHH.");
      }
    } else {
      _mostrarError("Correo o contraseña incorrectos.");
    }
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // Fondo ligeramente gris para que resalte la tarjeta
      body: Center(
        child: Container(
          width: 900, // Ancho fijo para que parezca una tarjeta central
          height: 550,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                spreadRadius: 5,
              )
            ],
          ),
          child: Row(
            children: [
              // PANEL IZQUIERDO: Imagen y fondo verde
              Expanded(
                flex: 1,
                child: Container(
                  color: _primary,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/logo_intesud1.png',
                        width: 200,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.book, size: 100, color: Colors.white),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        "Instituto Superior Tecnológico",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
              // PANEL DERECHO: Formulario (Tal cual el Wireframe)
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 50),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Instituto Superior Tecnológico Sudamericano",
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _primary),
                      ),
                      const Text(
                        "Sistema de Reportes",
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 30),
                      
                      // Campo Usuario
                      const Text("Usuario", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _correoController,
                        decoration: InputDecoration(
                          hintText: "Ingresa tu usuario",
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 15),
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      // Campo Contraseña
                      const Text("Contraseña", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _passController,
                        obscureText: true,
                        decoration: InputDecoration(
                          hintText: "Ingresa tu contraseña",
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 15),
                        ),
                      ),
                      const SizedBox(height: 15),
                      
                      // Recordarme y Olvidaste tu contraseña
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Checkbox(
                                value: _recordarme,
                                activeColor: _primary,
                                onChanged: (val) => setState(() => _recordarme = val!),
                              ),
                              const Text("Recordarme"),
                            ],
                          ),
                          TextButton(
                            onPressed: () {}, // Lógica de recuperar pass
                            child: const Text(
                              "¿Olvidaste tu contraseña?",
                              style: TextStyle(color: _primary, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      
                      // Botón Iniciar Sesión
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _cargando ? null : _iniciarSesionWeb,
                          child: _cargando
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text(
                                  "Iniciar Sesión",
                                  style: TextStyle(color: Colors.white, fontSize: 18),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}