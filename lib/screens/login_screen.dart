import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import 'registro_asistencia_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _correoController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final FirebaseService _service = FirebaseService();
  bool _cargando = false;
  bool _mostrarPassword = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  // --- NUEVA PALETA DE COLORES CLARA Y PROFESIONAL ---
  static const Color _primary = Color(0xFF467879); // Tu color identidad
  static const Color _bgSoft = Color(0xFFF0F4F4); // Fondo muy claro para limpieza

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

  void _iniciarSesion() async {
    setState(() => _cargando = true);

    var docente = await _service.validarLogin(
      _correoController.text.trim(),
      _passController.text.trim(),
    );

    setState(() => _cargando = false);

    if (docente != null) {
      if (!mounted) return;
      Navigator.pushReplacement(
  context,
  MaterialPageRoute(
    builder: (context) => RegistroAsistenciaScreen(
      nombreDocente: docente['nombre'],
      horariosDocente: docente['horarios_asignados'], 
      // Usamos el correo que viene directamente del documento de la DB
      correoUsuario: docente['correo'], 
    ),
  ),
);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text("Correo o contraseña incorrectos", style: TextStyle(color: Colors.white),),
            ],
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgSoft, // Fondo general claro
      body: Stack(
        children: [
          // SECCIÓN SUPERIOR: Panel curvo con tu color de identidad
          Container(
            height: MediaQuery.of(context).size.height * 0.45,
            decoration: const BoxDecoration(
              color: _primary,
              borderRadius: BorderRadius.only(
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
                      // LOGO E INSTITUCIÓN
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/logo_intesud.png',
                          width: 90,
                          height: 90,
                          errorBuilder: (context, error, stackTrace) => 
                              const Icon(Icons.school, color: _primary, size: 50),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        "INTESUD",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const Text(
                        "Instituto Superior Tecnológico Sudamericano",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      
                      const SizedBox(height: 35),

                      // TARJETA BLANCA: El cuadro que pediste para los datos
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
                            )
                          ],
                        ),
                        child: Column(
                          children: [
                            const Text(
                              "Bienvenido",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: _primary,
                              ),
                            ),
                            const SizedBox(height: 25),
                            
                            // Campo Correo
                            _buildTextField(
                              controller: _correoController,
                              hint: "Correo Institucional",
                              icon: Icons.email_outlined,
                            ),

                            const SizedBox(height: 18),

                            // Campo Contraseña
                            _buildTextField(
                              controller: _passController,
                              hint: "Contraseña",
                              icon: Icons.lock_outline,
                              isPassword: true,
                            ),

                            const SizedBox(height: 10),
                            
                            // Olvidar contraseña
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {},
                                child: const Text(
                                  "¿Olvidaste tu contraseña?",
                                  style: TextStyle(color: _primary, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // BOTÓN DE ACCIÓN SÓLIDO
                            SizedBox(
                              width: double.infinity,
                              height: 55,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primary,
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
                                        "INICIAR SESIÓN",
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

                      // FOOTER
                      const Text(
                        "INTESUD - Sistema de Gestión",
                        style: TextStyle(
                          color: _primary,
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
        prefixIcon: Icon(icon, color: _primary, size: 22),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _mostrarPassword ? Icons.visibility : Icons.visibility_off,
                  color: Colors.grey,
                  size: 22,
                ),
                onPressed: () => setState(() => _mostrarPassword = !_mostrarPassword),
              )
            : null,
        filled: true,
        fillColor: _bgSoft, // Color suave dentro del cuadro
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: _primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
      ),
    );
  }
}