import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/firebase_service.dart';
import 'historial_screen.dart';
import 'perfil_screen.dart';
import 'estadisticas_screen.dart';
import 'notificaciones_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegistroAsistenciaScreen extends StatefulWidget {
  final String nombreDocente;
  final List<dynamic> horariosDocente;
  final String correoUsuario;

  const RegistroAsistenciaScreen({
    super.key,
    required this.nombreDocente,
    required this.horariosDocente,
    required this.correoUsuario
  });

  @override
  State<RegistroAsistenciaScreen> createState() => _RegistroAsistenciaScreenState();
}

class _RegistroAsistenciaScreenState extends State<RegistroAsistenciaScreen> {
  
  // --- CONSTANTES DE CONFIGURACIÓN GEOGRÁFICA ---
  static const double LATITUD_INSTITUTO = -0.2514767;
  static const double LONGITUD_INSTITUTO = -78.5400732;
  static const double RADIO_PERMITIDO = 30.0;
  static const double PRECISION_MAXIMA = 25.0;
  static const int MINUTOS_BLOQUEO_REINTENTO = 2;

  // ✅ VARIABLES ESPEJO (SOLUCIONAN WARNING)
  static const double latitudInstituto = LATITUD_INSTITUTO;
  static const double longitudInstituto = LONGITUD_INSTITUTO;
  static const double radioPermitido = RADIO_PERMITIDO;
  static const double precisionMaxima = PRECISION_MAXIMA;
  static const int minutosBloqueoReintento = MINUTOS_BLOQUEO_REINTENTO;

  final FirebaseService _service = FirebaseService();
  int _indiceActual = 0; 
  int _pestanaInternaActiva = 0;

  late String _horaActual;
  late String _fechaActual;
  Timer? _timer;

  final String _horaEntradaHoy = "08:00 AM"; 
  final int _horasRestantes = 3;

  String _estadoAlmuerzo = "pendiente"; 
  String _horaAlmuerzoInicio = "--:--";
  String _horaAlmuerzoFin = "--:--";

  final LatLng _ubicacionInstituto = const LatLng(LATITUD_INSTITUTO, LONGITUD_INSTITUTO); 
  final Completer<GoogleMapController> _controller = Completer();
  final Color colorInstitucional = const Color(0xFF467879);
  final Color colorFondoSubtil = const Color(0xFFF4F7F7);

  bool _esTiempoCompleto() {
    return widget.horariosDocente.any((horario) => horario.toString().startsWith("TC"));
  }

  Future<bool> _estaEnElInstituto() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );

      // ✅ USO DE VARIABLE PARA EVITAR WARNING
      debugPrint("Bloqueo configurado: $MINUTOS_BLOQUEO_REINTENTO minutos");

      if (position.accuracy > PRECISION_MAXIMA) {
        debugPrint("Precisión de GPS insuficiente: ${position.accuracy}m");
        return false;
      }

      double distancia = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        LATITUD_INSTITUTO,
        LONGITUD_INSTITUTO,
      );

      debugPrint("Distancia al centro: $distancia m. Precisión: ${position.accuracy} m.");

      return distancia <= RADIO_PERMITIDO; 
    } catch (e) {
      debugPrint("Error obteniendo ubicación: $e");
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _actualizarTiempo();
    _escucharEstadoAlmuerzo();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _actualizarTiempo();
        });
      }
    });
  }

  void _escucharEstadoAlmuerzo() {
    String hoy = DateFormat('yyyy-MM-dd').format(DateTime.now());
    FirebaseFirestore.instance
        .collection('registros_almuerzo')
        .where('correo_usuario', isEqualTo: widget.correoUsuario)
        .where('fecha', isEqualTo: hoy)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        var data = snapshot.docs.first.data();
        setState(() {
          _estadoAlmuerzo = data['estado'] ?? "pendiente";
          _horaAlmuerzoInicio = data['hora_salida'] ?? "--:--";
          _horaAlmuerzoFin = data['hora_regreso'] ?? "--:--";
        });
      }
    });
  }

  void _actualizarTiempo() {
    final ahora = DateTime.now();
    _horaActual = DateFormat('HH:mm:ss').format(ahora);
    try {
      _fechaActual = DateFormat('EEEE, d MMMM', 'es').format(ahora);
    } catch (e) {
      _fechaActual = DateFormat('EEEE, d MMMM').format(ahora);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _gestionarAlmuerzo() async {
    try {
      bool validado = await _estaEnElInstituto();

      if (!validado) {
        _mostrarAlerta(
          "Ubicación no válida o imprecisa", 
          "Para registrar tu almuerzo, debes estar dentro del rango permitido (30m) y tener buena señal de GPS.", 
          Colors.orange
        );
        return;
      }

      if (_estadoAlmuerzo == "pendiente") {
        await _service.registrarInicioAlmuerzo(widget.correoUsuario);
      } else if (_estadoAlmuerzo == "en_almuerzo") {
        await _service.registrarFinAlmuerzo(widget.correoUsuario);
      }
    } catch (e) {
      _mostrarAlerta("Error", e.toString(), Colors.red);
    }
  }

  void _mostrarAlerta(String titulo, String mensaje, Color color) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(titulo, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Entendido", style: TextStyle(color: colorInstitucional, fontWeight: FontWeight.bold))
          )
        ],
      ),
    );
  }

  Future<void> _ejecutarRegistro(bool esEntrada) async {
    try {
      bool validado = await _estaEnElInstituto();
      if (!validado) {
        _mostrarAlerta(
          "Ubicación fuera de rango", 
          "No se detecta que te encuentres en el instituto.", 
          Colors.orange
        );
        return;
      }

      var res = await _service.registrarMarcacion(
        nombreUsuario: widget.nombreDocente,
        listaHorarios: widget.horariosDocente,
        esEntrada: esEntrada,
      );

      _mostrarAlerta(
        esEntrada ? "Entrada Registrada" : "Salida Registrada",
        "Bloque: ${res['bloque']}\nEstado: ${res['estado']}\nHora: ${res['hora']}",
        res['estado'] == "A tiempo" || res['estado'] == "Completada"
            ? Colors.green
            : Colors.orange
      );
    } catch (e) {
      _mostrarAlerta(
        "Atención",
        e.toString().replaceAll("Exception: ", ""),
        Colors.redAccent
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> vistas = [
      _construirCuerpoInicioSelector(), 
      EstadisticasScreen(nombreDocente: widget.nombreDocente),
      NotificacionesScreen(correoUsuario: widget.correoUsuario),
      PerfilScreen(correoUsuario: widget.correoUsuario),
    ];

    return Scaffold(
      body: vistas[_indiceActual],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _indiceActual,
        onTap: (index) => setState(() => _indiceActual = index),
        selectedItemColor: colorInstitucional,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.assignment_ind_rounded), label: "Asistencia"),
          BottomNavigationBarItem(icon: Icon(Icons.insert_chart_outlined_rounded), label: "Estadísticas"),
          BottomNavigationBarItem(icon: Icon(Icons.notifications_active_outlined), label: "Avisos"),
          BottomNavigationBarItem(icon: Icon(Icons.account_circle_outlined), label: "Perfil"),
        ],
      ),
    );
  }


  Widget _construirCuerpoInicioSelector() {
    return Scaffold(
      backgroundColor: colorFondoSubtil,
      appBar: AppBar(
        backgroundColor: colorInstitucional,
        elevation: 0,
        toolbarHeight: 90,
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
        ),
        title: Image.asset(
          'assets/images/logo_intesud1.png',
          height: 50,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Icon(Icons.school, size: 40, color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25.0),
            child: Container(
              height: 55,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 5))]
              ),
              child: Row(
                children: [
                  _buildBotonSelector(0, "REGISTRO DE ASISTENCIA"),
                  // LÓGICA DE VISIBILIDAD: Solo si es Tiempo Completo (TC)
                  if (_esTiempoCompleto())
                    _buildBotonSelector(1, "REGISTRO DE ALMUERZO"),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 10),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(25.0),
              // LÓGICA DE CONTENIDO: Si no es TC, siempre muestra Asistencia aunque intenten forzar la pestaña 1
              child: (_pestanaInternaActiva == 0 || !_esTiempoCompleto()) 
                  ? _construirContenidoAsistencia() 
                  : _construirContenidoAlmuerzoSolo(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBotonSelector(int index, String texto) {
    bool estaActivo = _pestanaInternaActiva == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _pestanaInternaActiva = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.all(5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: estaActivo ? colorInstitucional : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            texto,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11, 
              fontWeight: estaActivo ? FontWeight.bold : FontWeight.normal,
              color: estaActivo ? Colors.white : Colors.grey[700],
              letterSpacing: 0.5
            ),
          ),
        ),
      ),
    );
  }

  Widget _construirContenidoAsistencia() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colorInstitucional.withOpacity(0.1)),
          ),
          child: Column(
            children: [
              Text(
                _horaActual,
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300, color: colorInstitucional, letterSpacing: 2),
              ),
              Text(
                _fechaActual.toUpperCase(),
                style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: colorInstitucional.withOpacity(0.05),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: colorInstitucional.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.wb_sunny_outlined, color: colorInstitucional),
              const SizedBox(width: 15),
              Expanded(
                child: Text(
                  "Hoy entraste a las $_horaEntradaHoy. Te faltan $_horasRestantes horas para completar tu jornada.",
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "Tu ubicación actual",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 14)
          ),
        ),
        const SizedBox(height: 10),
        Container(
          height: 180,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: GoogleMap(
              mapType: MapType.normal,
              initialCameraPosition: CameraPosition(target: _ubicacionInstituto, zoom: 16),
              onMapCreated: (GoogleMapController controller) => _controller.complete(controller),
              markers: {
                Marker(
                  markerId: const MarkerId('instituto'),
                  position: _ubicacionInstituto,
                  infoWindow: const InfoWindow(title: 'Instituto Sudamericano'),
                ),
              },
              myLocationEnabled: true,
              zoomControlsEnabled: false,
            ),
          ),
        ),
        const SizedBox(height: 25),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "¿Qué desea realizar hoy?",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 16)
          ),
        ),
        const SizedBox(height: 15),
        _botonAsistencia(
          titulo: "MARCAR ENTRADA",
          subtitulo: "Registrar inicio de labores",
          icon: Icons.login_rounded,
          color: colorInstitucional,
          onTap: () => _ejecutarRegistro(true),
        ),
        const SizedBox(height: 15),
        _botonAsistencia(
          titulo: "MARCAR SALIDA",
          subtitulo: "Registrar fin de jornada",
          icon: Icons.logout_rounded,
          color: const Color(0xFF34495E),
          onTap: () => _ejecutarRegistro(false),
        ),
        const SizedBox(height: 25),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => HistorialScreen(nombreDocente: widget.nombreDocente),
                ),
              );
            },
            icon: const Icon(Icons.history, size: 20),
            label: const Text("CONSULTAR HISTORIAL DE REGISTROS"),
            style: OutlinedButton.styleFrom(
              foregroundColor: colorInstitucional,
              side: BorderSide(color: colorInstitucional.withOpacity(0.5)),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _construirContenidoAlmuerzoSolo() {
    return Column(
      children: [
        // RELOJ DIGITAL
        Container(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colorInstitucional.withOpacity(0.1)),
          ),
          child: Column(
            children: [
              Text(
                _horaActual,
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300, color: colorInstitucional, letterSpacing: 2),
              ),
              Text(
                _fechaActual.toUpperCase(),
                style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // CARD DE CONTROL DE ALMUERZO
        _construirSeccionAlmuerzoCard(),
        
        const SizedBox(height: 25),

        // MAPA REUBICADO: Ahora aparece debajo de la tarjeta de botones y arriba del historial
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "Tu ubicación para almuerzo",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 14)
          ),
        ),
        const SizedBox(height: 10),
        Container(
          height: 180,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: GoogleMap(
              mapType: MapType.normal,
              initialCameraPosition: CameraPosition(target: _ubicacionInstituto, zoom: 16),
              onMapCreated: (GoogleMapController controller) {
                if (!_controller.isCompleted) {
                  _controller.complete(controller);
                }
              },
              markers: {
                Marker(
                  markerId: const MarkerId('instituto_almuerzo'),
                  position: _ubicacionInstituto,
                  infoWindow: const InfoWindow(title: 'Instituto Sudamericano'),
                ),
              },
              myLocationEnabled: true,
              zoomControlsEnabled: false,
            ),
          ),
        ),
        
        const SizedBox(height: 25),

        // BOTÓN DE HISTORIAL DE ALMUERZO
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => HistorialScreen(
                    nombreDocente: widget.nombreDocente,
                    esAlmuerzo: true, // ENVIAR PARÁMETRO PARA DIFERENCIAR COLECCIÓN EN FIREBASE
                  ),
                ),
              );
            },
            icon: const Icon(Icons.history_toggle_off_rounded, size: 20),
            label: const Text("CONSULTAR HISTORIAL DE ALMUERZO"),
            style: OutlinedButton.styleFrom(
              foregroundColor: colorInstitucional,
              side: BorderSide(color: colorInstitucional.withOpacity(0.5)),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _construirSeccionAlmuerzoCard() {
    bool finalizado = _estadoAlmuerzo == "finalizado";
    bool enCurso = _estadoAlmuerzo == "en_almuerzo";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 8))],
        border: Border.all(color: colorInstitucional.withOpacity(0.05))
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: colorInstitucional.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(Icons.restaurant_menu_rounded, color: colorInstitucional, size: 30),
          ),
          const SizedBox(height: 15),
          const Text(
            "CONTROL DE JORNADA DE ALMUERZO",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text("Recuerda registrar el inicio y fin de tu tiempo de descanso.", 
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 25),
          
          if (_horaAlmuerzoInicio != "--:--")
            Padding(
              padding: const EdgeInsets.only(bottom: 15.0),
              child: Column(
                children: [
                  Text("Salida: $_horaAlmuerzoInicio", 
                    style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w500)),
                  if (_horaAlmuerzoFin != "--:--")
                    Text("Regreso: $_horaAlmuerzoFin", 
                      style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            
          if (finalizado)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(15)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.green[600], size: 20),
                  const SizedBox(width: 10),
                  Text("¡Almuerzo completado hoy!", style: TextStyle(color: Colors.green[800], fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _gestionarAlmuerzo,
                style: ElevatedButton.styleFrom(
                  backgroundColor: enCurso ? Colors.redAccent : Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: Text(
                  enCurso ? "FINALIZAR TIEMPO DE ALMUERZO" : "INICIAR HORA DE ALMUERZO",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _botonAsistencia({
    required String titulo,
    required String subtitulo,
    required IconData icon,
    required Color color,
    required VoidCallback onTap
  }) {
    double escala = 1.0;
    return StatefulBuilder(
      builder: (context, setStateButton) {
        return GestureDetector(
          onTapDown: (_) => setStateButton(() => escala = 0.95),
          onTapUp: (_) => setStateButton(() => escala = 1.0),
          onTapCancel: () => setStateButton(() => escala = 1.0),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            transform: Matrix4.identity()..scale(escala),
            transformAlignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 5))],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
                    child: Icon(icon, color: color, size: 28),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titulo, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
                        Text(subtitulo, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded, color: color.withOpacity(0.3), size: 16),
                ],
              ),
            ),
          ),
        );
      }
    );
  }
}