import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import '../config/app_config.dart';
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
import '../web/browser_notification_stub.dart'
    if (dart.library.html) '../web/browser_notification_web.dart'
        as browser_notification;

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
  StreamSubscription<QuerySnapshot>? _avisosSubscription;
  final Set<String> _avisosConocidos = <String>{};
  bool _avisosInicializados = false;
  bool _procesandoEntrada = false;
  bool _procesandoSalida = false;

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
  bool get _isWebPortal => kIsWeb;

  bool _esTiempoCompleto() {
    return widget.horariosDocente.any((horario) => horario.toString().startsWith("TC"));
  }

  bool _esNocturno() {
    return widget.horariosDocente.any((horario) => horario.toString().startsWith("NOCT"));
  }

  Future<Map<String, String>> _validarHorarioAlmuerzo() async {
    try {
      final horarioAlmuerzo = await _service.obtenerHorarioAlmuerzoUsuario(
        correo: widget.correoUsuario,
        listaHorarios: widget.horariosDocente,
      );

      if (horarioAlmuerzo == null) {
        return {
          'permitido': 'false',
          'titulo': 'Horario no disponible',
          'mensaje':
              'No se encontrÃ³ un horario de almuerzo configurado para su jornada.',
        };
      }

      final inicioStr = (horarioAlmuerzo['inicio'] ?? '').trim();
      final finStr = (horarioAlmuerzo['fin'] ?? '').trim();
      /*
          .collection('horarios')
          .doc(idHorarioTC)
          .get();

      if (!doc.exists) {
        return {
          'permitido': 'false',
          'titulo': 'Horario no disponible',
          'mensaje':
              'No se encontrÃ³ un horario de almuerzo configurado para su jornada.',
        };
      }

      String inicioStr = doc['almuerzo_inicio']; 
      String finStr = doc['almuerzo_fin'];       

      */
      final ahora = DateTime.now();
      final horaActualMinutos = ahora.hour * 60 + ahora.minute;

      final partesInicio = inicioStr.split(':');
      final inicioMinutos = int.parse(partesInicio[0]) * 60 + int.parse(partesInicio[1]);

      final partesFin = finStr.split(':');
      final finMinutos = int.parse(partesFin[0]) * 60 + int.parse(partesFin[1]);

      if (horaActualMinutos < inicioMinutos) {
        return {
          'permitido': 'false',
          'titulo': 'Horario no permitido',
          'mensaje':
              'Su horario de almuerzo aÃºn no inicia. PodrÃ¡ registrarlo desde las $inicioStr.',
        };
      }

      if (horaActualMinutos > finMinutos) {
        return {
          'permitido': 'false',
          'titulo': 'Horario finalizado',
          'mensaje':
              'El tiempo asignado para registrar su almuerzo ya terminÃ³. Su horario habilitado era de $inicioStr a $finStr.',
        };
      }

      return {
        'permitido': 'true',
        'titulo': '',
        'mensaje': '',
      };
    } catch (e) {
      debugPrint("Error validando horario: $e");
      return {
        'permitido': 'false',
        'titulo': 'Error de horario',
        'mensaje':
            'No fue posible validar el horario de almuerzo en este momento. Intente nuevamente.',
      };
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
        throw Exception("Permiso de ubicaciÃ³n denegado.");
      }
    }

    if (permiso == LocationPermission.deniedForever) {
      throw Exception("Permisos bloqueados. ActÃ­valos desde configuraciÃ³n.");
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
    if (!_esNocturno()) {
      _obtenerUbicacion();
    }
    if (_esTiempoCompleto()) _escucharEstadoAlmuerzo();
    _escucharAvisosUsuario();
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
    _avisosSubscription?.cancel();
    super.dispose();
  }

  String _normalizarCorreo(String value) => value.trim().toLowerCase();

  bool _esAvisoVisibleParaUsuario(Map<String, dynamic> data) {
    final destinatario =
        _normalizarCorreo((data['destinatarioCorreo'] ?? '').toString());
    if (destinatario.isNotEmpty) {
      return destinatario == _normalizarCorreo(widget.correoUsuario);
    }

    return SedeAccess.matchesSede(data, _branding.sedeId);
  }

  bool _esAvisoNotificable(Map<String, dynamic> data) {
    final titulo = (data['titulo'] ?? '').toString().trim();
    final mensaje = (data['mensaje'] ?? '').toString().trim();
    final tipo = (data['tipo'] ?? '').toString().trim().toLowerCase();
    final contenido = '$titulo $mensaje'.toLowerCase();

    if (tipo == 'solicitud_aprobada') {
      return true;
    }

    if (tipo.contains('almuerzo') || contenido.contains('almuerzo')) {
      return true;
    }

    if (tipo.isEmpty || tipo == 'aviso' || tipo == 'comunicado') {
      return titulo.isNotEmpty || mensaje.isNotEmpty;
    }

    return false;
  }

  void _escucharAvisosUsuario() {
    _avisosSubscription?.cancel();
    _avisosSubscription = FirebaseFirestore.instance
        .collection('avisos')
        .orderBy('timestamp', descending: true)
        .limit(30)
        .snapshots()
        .listen((snapshot) {
      final visibles = snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) {
          return false;
        }
        return _esAvisoVisibleParaUsuario(data) && _esAvisoNotificable(data);
      }).toList();

      if (!_avisosInicializados) {
        _avisosConocidos
          ..clear()
          ..addAll(visibles.map((doc) => doc.id));
        _avisosInicializados = true;
        return;
      }

      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) {
          continue;
        }

        final data = change.doc.data() as Map<String, dynamic>?;
        if (data == null) {
          continue;
        }
        if (!_esAvisoVisibleParaUsuario(data) ||
            !_esAvisoNotificable(data) ||
            _avisosConocidos.contains(change.doc.id)) {
          continue;
        }

        _avisosConocidos.add(change.doc.id);
        _mostrarNotificacionAviso(data);
      }
    });
  }

  Future<void> _mostrarNotificacionAviso(Map<String, dynamic> data) async {
    if (!mounted) return;

    final titulo = (data['titulo'] ?? 'Nuevo aviso').toString().trim();
    final mensaje = (data['mensaje'] ?? '').toString().trim();
    final esAprobacion = (data['tipo'] ?? '').toString().trim().toLowerCase() ==
        'solicitud_aprobada';
    final messenger = ScaffoldMessenger.of(context);

    if (kIsWeb) {
      final permission = await browser_notification.browserNotificationPermission();
      if (permission == 'default') {
        await browser_notification.requestBrowserNotificationPermission();
      }

      browser_notification.showBrowserNotification(
        title: titulo,
        body: mensaje.isEmpty ? 'Tienes una notificacion nueva.' : mensaje,
      );
    }

    messenger
      ..hideCurrentSnackBar()
      ..hideCurrentMaterialBanner()
      ..showMaterialBanner(
        MaterialBanner(
          backgroundColor: Colors.transparent,
          elevation: 0,
          forceActionsBelow: false,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          content: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.97),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: (esAprobacion ? Colors.green : colorInstitucional)
                    .withOpacity(0.18),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: (esAprobacion ? Colors.green : colorInstitucional)
                          .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      esAprobacion
                          ? Icons.verified_rounded
                          : Icons.notifications_active_rounded,
                      color: esAprobacion ? Colors.green : colorInstitucional,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          titulo,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: Color(0xFF203133),
                          ),
                        ),
                        if (mensaje.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            mensaje,
                            style: TextStyle(
                              color: Colors.grey[700],
                              height: 1.32,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                messenger.hideCurrentMaterialBanner();
                if (!mounted) return;
                setState(() => _indiceActual = 2);
              },
              child: Text(
                'Ver',
                style: TextStyle(
                  color: esAprobacion ? Colors.green : colorInstitucional,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Cerrar',
              onPressed: messenger.hideCurrentMaterialBanner,
              icon: Icon(
                Icons.close_rounded,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );

    Future.delayed(const Duration(seconds: 6), () {
      if (!mounted) return;
      messenger.hideCurrentMaterialBanner();
    });
  }

  Future<void> _gestionarAlmuerzo() async {
    try {
      final validacionHorario = await _validarHorarioAlmuerzo();
      final esHorarioValido =
          (validacionHorario['permitido'] ?? '').toLowerCase() == 'true';

      if (!esHorarioValido) {
        _mostrarAlerta(
          validacionHorario['titulo'] ?? "Horario no permitido",
          validacionHorario['mensaje'] ??
              "Su horario de almuerzo no se encuentra disponible en este momento.",
          Colors.orange,
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

  bool _tienePermisoActivo(Map<String, String> res) =>
      (res['permisoActivo'] ?? '').toLowerCase() == 'true';

  String _tituloDialogoRegistro(bool esEntrada, Map<String, String> res) {
    if (_tienePermisoActivo(res)) {
      return esEntrada
          ? "Entrada registrada con permiso"
          : "Salida registrada con permiso";
    }

    final estado = res['estado'] ?? '';
    if (esEntrada) {
      return estado == "A tiempo"
          ? "Entrada registrada correctamente"
          : "Entrada registrada";
    }

    return estado == "Completada"
        ? "Salida registrada correctamente"
        : "Salida registrada";
  }

  Color _colorDialogoRegistro(Map<String, String> res) {
    if (_tienePermisoActivo(res)) {
      return colorInstitucional;
    }

    final estado = res['estado'] ?? '';
    if (estado == "A tiempo" || estado == "Completada") {
      return Colors.green;
    }

    return Colors.orange;
  }

  String _estadoVisibleRegistro(bool esEntrada, Map<String, String> res) {
    if (_tienePermisoActivo(res)) {
      return esEntrada ? "Con permiso aprobado" : "Salida con permiso aprobado";
    }

    return res['estado'] ?? '';
  }

  String _mensajeRegistro(bool esEntrada, Map<String, String> res) {
    final bloque = (res['bloque'] ?? 'Bloque asignado').trim();
    final hora = (res['hora'] ?? '--:--').trim();
    final estadoVisible = _estadoVisibleRegistro(esEntrada, res);
    final permisoHorario = (res['horarioPermiso'] ?? '').trim();
    final motivoPermiso = (res['motivoPermiso'] ?? '').trim();

    if (_tienePermisoActivo(res)) {
      final accion = esEntrada ? 'entrada' : 'salida';
      final buffer = StringBuffer()
        ..writeln('Tu $accion fue registrada correctamente.')
        ..writeln()
        ..writeln('Bloque asignado: $bloque')
        ..writeln('Hora registrada: $hora')
        ..writeln('Estado del registro: $estadoVisible');

      if (permisoHorario.isNotEmpty) {
        buffer.writeln('Horario autorizado: $permisoHorario');
      }

      if (motivoPermiso.isNotEmpty) {
        buffer.writeln('Motivo aprobado: $motivoPermiso');
      }

      buffer
        ..writeln()
        ..write(
          'La marcacion se encontro dentro del horario del permiso aprobado.',
        );

      return buffer.toString().trim();
    }

    if (esEntrada) {
      if ((res['estado'] ?? '') == "A tiempo") {
        return 'Tu entrada fue registrada correctamente dentro del horario asignado.\n\n'
            'Bloque asignado: $bloque\n'
            'Hora registrada: $hora\n'
            'Estado del registro: A tiempo';
      }

      return 'Tu entrada fue registrada, pero quedo marcada fuera del horario asignado.\n\n'
          'Bloque asignado: $bloque\n'
          'Hora registrada: $hora\n'
          'Estado del registro: ${res['estado'] ?? 'Atraso'}';
    }

    if ((res['estado'] ?? '') == "Completada") {
      return 'Tu salida fue registrada correctamente dentro del horario asignado.\n\n'
          'Bloque asignado: $bloque\n'
          'Hora registrada: $hora\n'
          'Estado del registro: Completada';
    }

    return 'Tu salida fue registrada antes de la hora oficial del bloque.\n\n'
        'Bloque asignado: $bloque\n'
        'Hora registrada: $hora\n'
        'Estado del registro: ${res['estado'] ?? 'Salida Anticipada'}';
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
    final bool yaProcesando =
        esEntrada ? _procesandoEntrada : _procesandoSalida;
    if (yaProcesando) {
      return;
    }

    if (mounted) {
      setState(() {
        if (esEntrada) {
          _procesandoEntrada = true;
        } else {
          _procesandoSalida = true;
        }
      });
    }

    try {
      if (!_esNocturno()) {
        await _estaEnElInstituto();
      }
      final res = await _service.registrarMarcacion(
        nombreUsuario: widget.nombreDocente,
        listaHorarios: widget.horariosDocente,
        esEntrada: esEntrada,
        sedeId: _branding.sedeId,
        sedeNombre: _branding.sedeName,
      );

      _mostrarAlerta(
        _tituloDialogoRegistro(esEntrada, res),
        _mensajeRegistro(esEntrada, res),
        _colorDialogoRegistro(res),
      );
    } catch (e) {
      _mostrarAlerta(
        "Atencion",
        e.toString().replaceAll("Exception: ", ""),
        Colors.redAccent,
      );
    } finally {
      if (mounted) {
        setState(() {
          if (esEntrada) {
            _procesandoEntrada = false;
          } else {
            _procesandoSalida = false;
          }
        });
      }
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
      correoUsuario: widget.correoUsuario,
      sedeId: _branding.sedeId,
    ),
      PerfilScreen(
        correoUsuario: widget.correoUsuario,
        sedeId: _branding.sedeId,
      ),
  ];

    if (_isWebPortal) {
      return _buildWebPortal(vistas[_indiceActual]);
    }

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
          BottomNavigationBarItem(icon: Icon(Icons.insert_chart_outlined_rounded), label: "EstadÃ­sticas"),
          BottomNavigationBarItem(icon: Icon(Icons.notifications_active_outlined), label: "Avisos"),
          BottomNavigationBarItem(icon: Icon(Icons.description_outlined), label: "Solicitudes"),
          BottomNavigationBarItem(icon: Icon(Icons.account_circle_outlined), label: "Perfil"),
        ],
      ),
    );
  }

  // --- MÃ‰TODO MODIFICADO: SOLO EL FONDO CAMBIA ---
  Widget _construirCuerpoInicioSelector() {
    final bool isCentro = _branding.sedeId == AppBranding.sedeCentro.sedeId;
    final bool showDecorativeBackground = !_isWebPortal;
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
          // 1. FONDO BASE
          Container(
            color: showDecorativeBackground
                ? _branding.background
                : const Color(0xFFF4F7F8),
          ),

          // 2. PATRÓN DE FONDO Y MARCA DE AGUA SOLO EN MOVIL
          if (showDecorativeBackground)
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
                            color: Colors.white,
                            colorBlendMode: BlendMode.srcIn,
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),

          if (showDecorativeBackground)
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

          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: _isWebPortal ? 1080 : double.infinity,
              ),
              child: Column(
                children: [
                  Center(
                    child: SizedBox(
                      width: _isWebPortal ? 320 : double.infinity,
                      child: Container(
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
                    ),
                  ),
                  SizedBox(height: _isWebPortal ? 26 : 20),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: _isWebPortal ? 0 : 25.0),
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
                          if (_esTiempoCompleto()) _buildBotonSelector(1, "ALMUERZO"),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.all(_isWebPortal ? 32.0 : 25.0),
                      child: (_pestanaInternaActiva == 0 || !_esTiempoCompleto())
                          ? _construirContenidoAsistencia()
                          : _construirContenidoAlmuerzoSolo(),
                    ),
                  ),
                ],
              ),
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
      height: _isWebPortal ? 230 : 180,
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
                  "Tu jornada estÃ¡ activa. Recuerda marcar a tiempo tus ingresos y salidas.",
                  style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        if (!_esNocturno()) _buildMapaMini(),
        const SizedBox(height: 10),
        if (_isWebPortal)
          Row(
            children: [
              Expanded(
                child: _botonAsistencia(
                  titulo: "MARCAR ENTRADA",
                  subtitulo: "Iniciar registro de hoy",
                  icon: Icons.login_rounded,
                  color: colorInstitucional,
                  procesando: _procesandoEntrada,
                  onTap: () => _ejecutarRegistro(true),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _botonAsistencia(
                  titulo: "MARCAR SALIDA",
                  subtitulo: "Finalizar labores",
                  icon: Icons.logout_rounded,
                  color: const Color(0xFF2C3E50),
                  procesando: _procesandoSalida,
                  onTap: () => _ejecutarRegistro(false),
                ),
              ),
            ],
          )
        else ...[
          _botonAsistencia(
            titulo: "MARCAR ENTRADA",
            subtitulo: "Iniciar registro de hoy",
            icon: Icons.login_rounded,
            color: colorInstitucional,
            procesando: _procesandoEntrada,
            onTap: () => _ejecutarRegistro(true),
          ),
          const SizedBox(height: 15),
          _botonAsistencia(
            titulo: "MARCAR SALIDA",
            subtitulo: "Finalizar labores",
            icon: Icons.logout_rounded,
            color: const Color(0xFF2C3E50),
            procesando: _procesandoSalida,
            onTap: () => _ejecutarRegistro(false),
          ),
        ],
        const SizedBox(height: 25),
        if (_isWebPortal)
          Center(
            child: SizedBox(
              width: 360,
              child: _botonHistorial(false),
            ),
          )
        else
          _botonHistorial(false),
      ],
    );
  }

  Widget _construirContenidoAlmuerzoSolo() {
    final almuerzoCard = _construirSeccionAlmuerzoCard();

    return Column(
      children: [
        _buildRelojCard(),
        if (!_esNocturno()) _buildMapaMini(),
        const SizedBox(height: 10),
        if (_isWebPortal)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: almuerzoCard,
            ),
          )
        else
          almuerzoCard,
        const SizedBox(height: 25),
        if (_isWebPortal)
          Center(
            child: SizedBox(
              width: 360,
              child: _botonHistorial(true),
            ),
          )
        else
          _botonHistorial(true),
      ],
    );
  }

  Widget _buildRelojCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        vertical: _isWebPortal ? 28 : 20,
        horizontal: 20,
      ),
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
            style: TextStyle(
              fontSize: _isWebPortal ? 54 : 40,
              fontWeight: FontWeight.w200,
              color: colorInstitucional,
              letterSpacing: _isWebPortal ? 4 : 3,
            )
          ),
          const SizedBox(height: 5),
          Text(
            _fechaActual.toUpperCase(), 
            style: TextStyle(
              fontSize: _isWebPortal ? 13 : 11,
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            )
          ),
        ],
      ),
    );
  }

  Widget _buildWebPortal(Widget activeView) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F8),
      body: Row(
        children: [
          Container(
            width: 238,
            color: _branding.primaryDark,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 108,
                      height: 108,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Image.asset(
                        _branding.logoSmall,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                          Icons.school,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'INTESUD',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                    Text(
                      'Portal del usuario',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.72),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sesion actual',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.68),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.nombreDocente,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            SedeAccess.displayNameForId(_branding.sedeId),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.78),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            _buildWebNavItem(
                              index: 0,
                              icon: Icons.assignment_ind_rounded,
                              label: 'Asistencia',
                            ),
                            const SizedBox(height: 10),
                            _buildWebNavItem(
                              index: 1,
                              icon: Icons.insert_chart_outlined_rounded,
                              label: 'Estadisticas',
                            ),
                            const SizedBox(height: 10),
                            _buildWebNavItem(
                              index: 2,
                              icon: Icons.notifications_active_outlined,
                              label: 'Avisos',
                            ),
                            const SizedBox(height: 10),
                            _buildWebNavItem(
                              index: 3,
                              icon: Icons.description_outlined,
                              label: 'Solicitudes',
                            ),
                            const SizedBox(height: 10),
                            _buildWebNavItem(
                              index: 4,
                              icon: Icons.account_circle_outlined,
                              label: 'Perfil',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'v1.0.2 - portal web',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.32),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 72,
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x11000000),
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.menu_open_rounded,
                        color: colorInstitucional,
                        size: 24,
                      ),
                      const SizedBox(width: 14),
                      Text(
                        _webSectionTitle(),
                        style: const TextStyle(
                          color: Color(0xFF223334),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: colorInstitucional.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.person_outline_rounded,
                              color: colorInstitucional,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              widget.nombreDocente,
                              style: TextStyle(
                                color: colorInstitucional,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: activeView,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebNavItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isActive = _indiceActual == index;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _indiceActual = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(isActive ? 0.0 : 0.06)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isActive
                    ? colorInstitucional.withOpacity(0.12)
                    : Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                size: 22,
                color: isActive ? colorInstitucional : Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isActive ? colorInstitucional : Colors.white,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isActive
                  ? colorInstitucional.withOpacity(0.90)
                  : Colors.white.withOpacity(0.55),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  String _webSectionTitle() {
    switch (_indiceActual) {
      case 1:
        return 'Resumen estadistico';
      case 2:
        return 'Avisos y notificaciones';
      case 3:
        return 'Gestion de solicitudes';
      case 4:
        return 'Perfil del usuario';
      default:
        return 'Registro de asistencia';
    }
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
              child: Text("Salida: $_horaAlmuerzoInicio  â€¢  Regreso: $_horaAlmuerzoFin", style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 12)),
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
              correoUsuario: widget.correoUsuario,
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

  Widget _botonAsistencia({
    required String titulo,
    required String subtitulo,
    required IconData icon,
    required Color color,
    required bool procesando,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: procesando ? null : onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: procesando ? 0.88 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: procesando
                ? color.withOpacity(0.10)
                : Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: procesando
                  ? color.withOpacity(0.30)
                  : color.withOpacity(0.1),
              width: procesando ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(procesando ? 0.18 : 0.1),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: procesando
                    ? SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      )
                    : Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      procesando ? "PROCESANDO..." : titulo,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      procesando
                          ? "Espere un momento, estamos registrando su marcacion."
                          : subtitulo,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: procesando
                    ? Icon(
                        Icons.hourglass_top_rounded,
                        key: const ValueKey('loading'),
                        color: color,
                      )
                    : Icon(
                        Icons.chevron_right_rounded,
                        key: const ValueKey('arrow'),
                        color: Colors.grey[400],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


