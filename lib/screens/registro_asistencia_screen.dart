import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import '../models/app_branding.dart';
import '../services/firebase_service.dart';
import 'historial_screen.dart';
import 'perfil_screen.dart';
import 'estadisticas_screen.dart';
import 'notificaciones_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'solicitudes/solicitud_form_screen.dart';
import 'dart:ui';

class RegistroAsistenciaScreen extends StatefulWidget {
  final String nombreDocente;
  final List<dynamic> horariosDocente;
  final String correoUsuario;
  final bool isSedeNorte;
  final String? sedeId;

  const RegistroAsistenciaScreen({
    super.key,
    required this.nombreDocente,
    required this.horariosDocente,
    required this.correoUsuario,
    this.isSedeNorte = false,
    this.sedeId,
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
  AppBranding get _branding => AppBranding.fromLegacy(
        isSedeNorte: widget.isSedeNorte,
        sedeId: widget.sedeId,
      );
  Color get colorInstitucional => _branding.primary;
  Color get colorFondoVariacion => _branding.softAccent;

  bool _esTiempoCompleto() {
    return widget.horariosDocente.any((horario) => horario.toString().startsWith("TC"));
  }

  bool _esNocturno() {
    return widget.horariosDocente.any((horario) => horario.toString().startsWith("NOCT"));
  }

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
        _mostrarAlerta("Horario no permitido", "Aún no es su hora de almuerzo.", Colors.orange);
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
    EstadisticasScreen(
      nombreDocente: widget.nombreDocente,
      sedeId: _branding.sedeId,
    ),
    NotificacionesScreen(
      correoUsuario: widget.correoUsuario,
      sedeId: _branding.sedeId,
    ),
    SolicitudFormScreen(
      nombreDocente: widget.nombreDocente,
      sedeId: _branding.sedeId,
    ),
    PerfilScreen(
      correoUsuario: widget.correoUsuario,
      sedeId: _branding.sedeId,
    ),
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
          BottomNavigationBarItem(icon: Icon(Icons.description_outlined), label: "Solicitudes"),
          BottomNavigationBarItem(icon: Icon(Icons.account_circle_outlined), label: "Perfil"),
        ],
      ),
    );
  }

  // --- MÉTODO MODIFICADO: SOLO EL FONDO CAMBIA ---
  Widget _construirCuerpoInicioSelector() {
    final bool isCentro = _branding.sedeId == AppBranding.sedeCentro.sedeId;
    final String tituloAsistencia = _branding.sedeId == AppBranding.sedeNorte.sedeId
        ? "ASISTENCIA SEDE NORTE"
        : isCentro
            ? "ASISTENCIA SEDE CENTRO"
            : _branding.sedeId == AppBranding.sedeCreSer.sedeId
                ? "ASISTENCIA CRE SER"
                : "REGISTRO DE ASISTENCIA";

    return Scaffold(
      body: Stack(
        children: [
          // 1. FONDO BASE CON COLOR #8CBAB3
          Container(color: _branding.background),

          // 2. PATRÓN DE "S" PEQUEÑAS REPETIDAS EN EL FONDO (logo_intesud2.png)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double logoSize = _branding.mobilePatternLogoSize;
                const double spacing = 75.0;
                final int cols = (constraints.maxWidth / spacing).ceil() + 1;
                final int rows = (constraints.maxHeight / spacing).ceil() + 1;

                return Stack(
                  children: List.generate(rows * cols, (index) {
                    final int row = index ~/ cols;
                    final int col = index % cols;
                    final double offsetX = (row % 2 == 0) ? 0 : spacing / 2;
                    final double left = col * spacing + offsetX - logoSize / 2;
                    final double top = row * spacing - logoSize / 2;

                    return Positioned(
                      left: left,
                      top: top,
                      child: Opacity(
                        opacity: 0.13,
                        child: Image.asset(
  _branding.logoSmall,
  width: logoSize,
  height: logoSize,
  fit: BoxFit.contain,
  color: Colors.white,                 // <-- CAMBIO
  colorBlendMode: BlendMode.srcIn,
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),

          // 3. LOGO GRANDE DE FONDO CENTRAL (logo_intesud2.png) — se mantiene igual
          Center(
            child: Opacity(
              opacity: 0.12,
              child: ShaderMask(
                shaderCallback: (rect) {
                  return LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colorInstitucional.withOpacity(0.8),
                      Colors.transparent,
                    ],
                  ).createShader(rect);
                },
                blendMode: BlendMode.srcATop,
                child: Image.asset(
                  _branding.logoWatermark,
                  width: MediaQuery.of(context).size.width *
                      _branding.mobileWatermarkWidthFactor,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),

          // 4. CONTENIDO PRINCIPAL — sin ningún cambio
          Column(
            children: [
              Container(
                height: 160,
                padding: const EdgeInsets.only(top: 50, left: 20, right: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colorInstitucional, _branding.primaryDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(35)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    )
                  ],
                ),
                child: Column(
                  children: [
                    Image.asset(
                      _branding.logoSmall,
                      height: _branding.mobileHeaderLogoHeight,
                      errorBuilder: (c, e, s) => const Icon(Icons.school, size: 40, color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                      tituloAsistencia,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isCentro ? 16 : 18,
                        letterSpacing: isCentro ? 0.8 : 1.2,
                        height: 1.15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25.0),
                child: Container(
                  height: 55,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 4))
                    ]
                  ),
                  child: Row(
                    children: [
                      _buildBotonSelector(0, "ASISTENCIA"),
                      if (_esTiempoCompleto()) 
                        _buildBotonSelector(1, "ALMUERZO"),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(25.0),
                  child: (_pestanaInternaActiva == 0 || !_esTiempoCompleto())
                      ? _construirContenidoAsistencia()
                      : _construirContenidoAlmuerzoSolo(),
                ),
              ),
            ],
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
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: estaActivo ? colorInstitucional : Colors.transparent, 
            borderRadius: BorderRadius.circular(15),
            boxShadow: estaActivo ? [BoxShadow(color: colorInstitucional.withOpacity(0.4), blurRadius: 4)] : null,
          ),
          child: Text(
            texto, 
            style: TextStyle(
              fontSize: 11, 
              fontWeight: FontWeight.bold, 
              color: estaActivo ? Colors.white : colorInstitucional.withOpacity(0.6)
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
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white, width: 5),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 12, offset: const Offset(0, 5))]
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: _posicionActual != null
                ? LatLng(_posicionActual!.latitude, _posicionActual!.longitude)
                : _ubicacionInstituto,
            initialZoom: 16,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: _ubicacionInstituto,
                  width: 45,
                  height: 45,
                  child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                ),
                if (_posicionActual != null)
                  Marker(
                    point: LatLng(_posicionActual!.latitude, _posicionActual!.longitude),
                    width: 45,
                    height: 45,
                    child: const Icon(Icons.person_pin_circle, color: Colors.blue, size: 40),
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
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colorInstitucional.withOpacity(0.1)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)]
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: colorInstitucional.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(Icons.wb_sunny_rounded, color: colorInstitucional, size: 22),
              ),
              const SizedBox(width: 15),
              const Expanded(
                child: Text(
                  "Tu jornada está activa. Recuerda marcar a tiempo tus ingresos y salidas.",
                  style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        if (!_esNocturno()) _buildMapaMini(),
        const SizedBox(height: 10),
        _botonAsistencia(
          titulo: "MARCAR ENTRADA",
          subtitulo: "Iniciar registro de hoy",
          icon: Icons.login_rounded,
          color: colorInstitucional,
          onTap: () => _ejecutarRegistro(true),
        ),
        const SizedBox(height: 15),
        _botonAsistencia(
          titulo: "MARCAR SALIDA",
          subtitulo: "Finalizar labores",
          icon: Icons.logout_rounded,
          color: const Color(0xFF2C3E50),
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
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85), 
        borderRadius: BorderRadius.circular(25), 
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 4))],
        border: Border.all(color: colorInstitucional.withOpacity(0.1))
      ),
      child: Column(
        children: [
          Text(
            _horaActual, 
            style: TextStyle(fontSize: 40, fontWeight: FontWeight.w200, color: colorInstitucional, letterSpacing: 3)
          ),
          const SizedBox(height: 5),
          Text(
            _fechaActual.toUpperCase(), 
            style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.bold, letterSpacing: 1.5)
          ),
        ],
      ),
    );
  }

  Widget _construirSeccionAlmuerzoCard() {
    bool finalizado = _estadoAlmuerzo == "finalizado";
    bool enCurso = _estadoAlmuerzo == "en_almuerzo";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85), 
        borderRadius: BorderRadius.circular(30), 
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20)], 
        border: Border.all(color: colorInstitucional.withOpacity(0.08))
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: colorInstitucional.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(Icons.restaurant_rounded, color: colorInstitucional, size: 35),
          ),
          const SizedBox(height: 20),
          const Text("JORNADA DE ALMUERZO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1)),
          const SizedBox(height: 10),
          const Text(
            "Gestione sus tiempos de descanso conforme a su horario asignado.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 25),
          if (_horaAlmuerzoInicio != "--:--") 
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
              child: Text("Salida: $_horaAlmuerzoInicio  •  Regreso: $_horaAlmuerzoFin", style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 12)),
            ),
          const SizedBox(height: 20),
          if (finalizado)
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 18),
                SizedBox(width: 8),
                Text("Almuerzo registrado correctamente", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _gestionarAlmuerzo,
                style: ElevatedButton.styleFrom(
                  backgroundColor: enCurso ? Colors.redAccent : Colors.orange[700], 
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  padding: const EdgeInsets.symmetric(vertical: 16)
                ),
                child: Text(
                  enCurso ? "FINALIZAR ALMUERZO" : "INICIAR ALMUERZO",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
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
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (c) => HistorialScreen(
              nombreDocente: widget.nombreDocente,
              esAlmuerzo: esAlmuerzo,
              sedeId: _branding.sedeId,
            ),
          ),
        ),
        icon: const Icon(Icons.history_rounded),
        label: Text(esAlmuerzo ? "HISTORIAL DE ALMUERZOS" : "HISTORIAL DE REGISTROS"),
        style: OutlinedButton.styleFrom(
          foregroundColor: colorInstitucional, 
          side: BorderSide(color: colorInstitucional.withOpacity(0.4), width: 1.5), 
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))
        ),
      ),
    );
  }

  Widget _botonAsistencia({required String titulo, required String subtitulo, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9), 
          borderRadius: BorderRadius.circular(25), 
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
          border: Border.all(color: color.withOpacity(0.1))
        ),
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
                  Text(titulo, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(subtitulo, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ]
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}
