import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import '../services/firebase_service.dart';
import 'historial_screen.dart';
import 'perfil_screen.dart';
import 'estadisticas_screen.dart';
import 'notificaciones_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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
  
  static const double latitudInstituto = -0.1843090;
  static const double longitudInstituto = -78.4909804;

  final FirebaseService _service = FirebaseService();
  int _indiceActual = 0; 
  int _pestanaInternaActiva = 0;

  late String _horaActual;
  late String _fechaActual;
  Timer? _timer;

  String _estadoAlmuerzo = "pendiente"; 
  String _horaAlmuerzoInicio = "--:--";
  String _horaAlmuerzoFin = "--:--";

  final LatLng _ubicacionInstituto = LatLng(latitudInstituto, longitudInstituto);
  
  Position? _posicionActual;
  final Color colorInstitucional = const Color(0xFF467879);
  final Color colorFondoSubtil = const Color(0xFFF4F7F7);

  // Determina si el docente tiene contrato de Tiempo Completo
  bool _esTiempoCompleto() {
    return widget.horariosDocente.any((horario) => horario.toString().startsWith("TC"));
  }
  // NUEVO: Detectar si es horario nocturno (HORARIO NOCTURNO)
bool _esNocturno() {
  return widget.horariosDocente.any((horario) => horario.toString().startsWith("NOCT"));
}

  // --- VALIDACIÓN DE HORARIO DE ALMUERZO ---
  Future<bool> _validarHorarioAlmuerzo() async {
    try {
      String idHorarioTC = widget.horariosDocente.firstWhere(
        (h) => h.toString().startsWith("TC"), 
        orElse: () => ""
      );

      if (idHorarioTC.isEmpty) return false;

      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('horarios')
          .doc(idHorarioTC)
          .get();

      if (!doc.exists) return false;

      String inicioStr = doc['almuerzo_inicio']; 
      String finStr = doc['almuerzo_fin'];       

      final ahora = DateTime.now();
      final horaActualMinutos = ahora.hour * 60 + ahora.minute;

      final partesInicio = inicioStr.split(':');
      final inicioMinutos = int.parse(partesInicio[0]) * 60 + int.parse(partesInicio[1]);

      final partesFin = finStr.split(':');
      final finMinutos = int.parse(partesFin[0]) * 60 + int.parse(partesFin[1]);

      return (horaActualMinutos >= inicioMinutos && horaActualMinutos <= finMinutos);
    } catch (e) {
      debugPrint("Error validando horario: $e");
      return false;
    }
  }

  Future<void> _obtenerUbicacion() async {
    bool servicioActivo = await Geolocator.isLocationServiceEnabled();
    if (!servicioActivo) return;

    LocationPermission permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied) return;
    }

    if (permiso == LocationPermission.deniedForever) return;

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
    );
    Position posicion = await Geolocator.getCurrentPosition(
      locationSettings: locationSettings,
    );

    if (!mounted) return;
    setState(() {
      _posicionActual = posicion;
    });
  }

  Future<bool> _estaEnElInstituto() async {
    bool servicioActivo = await Geolocator.isLocationServiceEnabled();
    if (!servicioActivo) {
      throw Exception("Activa el GPS del dispositivo.");
    }

    LocationPermission permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied) {
        throw Exception("Permiso de ubicación denegado.");
      }
    }

    if (permiso == LocationPermission.deniedForever) {
      throw Exception("Permisos bloqueados. Actívalos desde configuración.");
    }

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
    );
    Position posicion = await Geolocator.getCurrentPosition(
      locationSettings: locationSettings,
    );

    double distancia = Geolocator.distanceBetween(
      latitudInstituto,
      longitudInstituto,
      posicion.latitude,
      posicion.longitude,
    );

    debugPrint("Distancia al instituto: $distancia metros");

    if (distancia <= 40) {
      return true;
    } else {
      throw Exception("Debes estar dentro del instituto (40 metros).");
    }
  }

  @override
  void initState() {
    super.initState();
    _actualizarTiempo();
    _obtenerUbicacion();
    if (_esTiempoCompleto()) _escucharEstadoAlmuerzo();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _actualizarTiempo());
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
      bool esHorarioValido = await _validarHorarioAlmuerzo();

      if (!esHorarioValido) {
        _mostrarAlerta(
          "Horario no permitido", 
          "Aún no es su hora de almuerzo.", 
          Colors.orange
        );
        return;
      }

    if (!_esNocturno()) {
  bool dentro = await _estaEnElInstituto();
  if (!dentro) return;
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
      if (!_esNocturno()) {
  await _estaEnElInstituto();
}
      var res = await _service.registrarMarcacion(
        nombreUsuario: widget.nombreDocente,
        listaHorarios: widget.horariosDocente,
        esEntrada: esEntrada,
      );

      _mostrarAlerta(
        esEntrada ? "Entrada Registrada" : "Salida Registrada",
        "Bloque: ${res['bloque']}\nEstado: ${res['estado']}\nHora: ${res['hora']}",
        res['estado'] == "A tiempo" || res['estado'] == "Completada" ? Colors.green : Colors.orange
      );
    } catch (e) {
      _mostrarAlerta("Atención", e.toString().replaceAll("Exception: ", ""), Colors.redAccent);
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
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(30))),
        title: Image.asset('assets/images/logo_intesud1.png', height: 50, errorBuilder: (c, e, s) => const Icon(Icons.school, size: 40, color: Colors.white)),
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
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: estaActivo ? colorInstitucional : Colors.transparent, 
            borderRadius: BorderRadius.circular(12)
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                texto, 
                textAlign: TextAlign.center, 
                style: TextStyle(
                  fontSize: 10, 
                  fontWeight: estaActivo ? FontWeight.bold : FontWeight.normal, 
                  color: estaActivo ? Colors.white : Colors.grey[700]
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapaMini() {
  return Container(
    height: 180,
    margin: const EdgeInsets.symmetric(vertical: 15),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white, width: 4),
      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)]
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: FlutterMap(
        options: MapOptions(
          initialCenter: _posicionActual != null
              ? LatLng(_posicionActual!.latitude, _posicionActual!.longitude)
              : _ubicacionInstituto,
          initialZoom: 16,
        ),
        children: [
          // 🗺️ MAPA BASE (CartoDB Voyager)
          TileLayer(
            urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
            subdomains: const ['a', 'b', 'c', 'd'],
            userAgentPackageName: 'com.example.app',
          ),

          // 📍 MARCADOR DEL INSTITUTO
          MarkerLayer(
            markers: [
              Marker(
                point: _ubicacionInstituto,
                width: 40,
                height: 40,
                child: const Icon(Icons.location_on, color: Colors.red, size: 35),
              ),

              // 📍 TU UBICACIÓN ACTUAL
              if (_posicionActual != null)
                Marker(
                  point: LatLng(
                    _posicionActual!.latitude,
                    _posicionActual!.longitude,
                  ),
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.person_pin_circle, color: Colors.blue, size: 35),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

  Widget _construirContenidoAsistencia() {
    return Column(
      children: [
        _buildRelojCard(),
        const SizedBox(height: 15),
        // --- TARJETA DE ESTADO DE JORNADA ---
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: colorInstitucional.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            children: [
              Icon(Icons.wb_sunny_outlined, color: colorInstitucional, size: 24),
              const SizedBox(width: 15),
              const Expanded(
                child: Text(
                  "Hoy entraste a las 08:00 AM. Te faltan 3 horas para completar tu jornada.",
                  style: TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ),
            ],
          ),
        ),
        if (!_esNocturno()) _buildMapaMini(),
        const SizedBox(height: 10),
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
        _botonHistorial(false),
      ],
    );
  }

  Widget _construirContenidoAlmuerzoSolo() {
    return Column(
      children: [
        _buildRelojCard(),
        if (!_esNocturno()) _buildMapaMini(),
        const SizedBox(height: 10),
        _construirSeccionAlmuerzoCard(),
        const SizedBox(height: 25),
        _botonHistorial(true),
      ],
    );
  }

  Widget _buildRelojCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: colorInstitucional.withValues(alpha: 0.1))),
      child: Column(
        children: [
          Text(_horaActual, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300, color: colorInstitucional, letterSpacing: 2)),
          Text(_fechaActual.toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _construirSeccionAlmuerzoCard() {
    bool finalizado = _estadoAlmuerzo == "finalizado";
    bool enCurso = _estadoAlmuerzo == "en_almuerzo";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15, offset: const Offset(0, 8))], border: Border.all(color: colorInstitucional.withValues(alpha: 0.05))),
      child: Column(
        children: [
          Icon(Icons.restaurant_menu_rounded, color: colorInstitucional, size: 40),
          const SizedBox(height: 15),
          const Text("CONTROL DE JORNADA DE ALMUERZO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          const Text(
            "Recuerda registrar el inicio y fin de tu tiempo de descanso.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 25),
          if (_horaAlmuerzoInicio != "--:--") Text("Salida: $_horaAlmuerzoInicio | Regreso: $_horaAlmuerzoFin", style: const TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 15),
          if (finalizado)
            const Text("¡Almuerzo completado hoy!", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _gestionarAlmuerzo,
                style: ElevatedButton.styleFrom(
                  backgroundColor: enCurso ? Colors.redAccent : Colors.orange, 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  padding: const EdgeInsets.symmetric(vertical: 12)
                ),
                child: Text(enCurso ? "FINALIZAR ALMUERZO" : "INICIAR HORA DE ALMUERZO"),
              ),
            ),
        ],
      ),
    );
  }

  Widget _botonHistorial(bool esAlmuerzo) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => HistorialScreen(nombreDocente: widget.nombreDocente, esAlmuerzo: esAlmuerzo))),
        icon: const Icon(Icons.history),
        label: Text(esAlmuerzo ? "HISTORIAL ALMUERZO" : "HISTORIAL REGISTROS"),
        style: OutlinedButton.styleFrom(foregroundColor: colorInstitucional, side: BorderSide(color: colorInstitucional.withValues(alpha: 0.5)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
      ),
    );
  }

  Widget _botonAsistencia({required String titulo, required String subtitulo, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)]),
        child: Row(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(width: 20),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
              Text(subtitulo, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ],
        ),
      ),
    );
  }
}