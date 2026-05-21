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
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';
import 'solicitudes/solicitud_form_screen.dart';
import '../web/browser_notification_stub.dart'
    if (dart.library.html) '../web/browser_notification_web.dart'
    as browser_notification;

class RegistroAsistenciaScreen extends StatefulWidget {
  final String nombreDocente;
  final List<dynamic> horariosDocente;
  final String correoUsuario;
  final String? rolUsuario;
  final bool isSedeNorte;
  final String? sedeId;

  const RegistroAsistenciaScreen({
    super.key,
    required this.nombreDocente,
    required this.horariosDocente,
    required this.correoUsuario,
    this.rolUsuario,
    this.isSedeNorte = false,
    this.sedeId,
  });

  @override
  State<RegistroAsistenciaScreen> createState() =>
      _RegistroAsistenciaScreenState();
}

class _RegistroAsistenciaScreenState extends State<RegistroAsistenciaScreen> {
  final FirebaseService _service = FirebaseService();
  final GlobalKey<ScaffoldState> _webPortalScaffoldKey =
      GlobalKey<ScaffoldState>();
  int _indiceActual = 0;
  int _pestanaInternaActiva = 0;

  StreamSubscription<QuerySnapshot>? _avisosSubscription;
  StreamSubscription<QuerySnapshot>? _almuerzoSubscription;
  StreamSubscription<QuerySnapshot>? _usuarioHorarioSubscription;
  final Set<String> _avisosConocidos = <String>{};
  bool _avisosInicializados = false;
  bool _procesandoEntrada = false;
  bool _procesandoSalida = false;
  late List<dynamic> _horariosAsignados;
  List<Map<String, dynamic>> _vinculacionesAsistencia =
      <Map<String, dynamic>>[];
  late String _rolUsuario;
  bool _requiereGeolocalizacion = true;
  bool _webSidebarCollapsed = false;
  bool _almuerzoHabilitado = false;

  String _estadoAlmuerzo = "pendiente";
  String _horaAlmuerzoInicio = "--:--";
  String _horaAlmuerzoFin = "--:--";
  Position? _posicionActual;
  AppBranding get _branding => AppBranding.fromLegacy(
    isSedeNorte: widget.isSedeNorte,
    sedeId: widget.sedeId,
  );
  SedeGeoConfig get _geoConfig => SedeGeoConfig.fromSedeId(_branding.sedeId);
  LatLng get _ubicacionInstituto =>
      LatLng(_geoConfig.latitude, _geoConfig.longitude);
  Color get colorInstitucional => _branding.primary;
  Color get colorFondoVariacion => _branding.softAccent;
  bool get _isWebPortal => kIsWeb;
  double get _webViewportWidth => MediaQuery.sizeOf(context).width;
  bool get _isPhoneWebLayout => _isWebPortal && _webViewportWidth < 600;
  bool get _isCompactWebLayout => _isWebPortal && _webViewportWidth < 900;
  bool get _isNarrowWebLayout => _isWebPortal && _webViewportWidth < 720;

  double _webSectionMaxWidth({
    double compact = 760,
    double regular = 860,
    double wide = 960,
  }) {
    final width = MediaQuery.of(context).size.width;

    if (width >= 1500) {
      return wide;
    }

    if (width >= 1180) {
      return regular;
    }

    return compact;
  }

  Widget _wrapWebSection(Widget child, {double? maxWidth}) {
    if (!_isWebPortal) {
      return child;
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? _webSectionMaxWidth(),
        ),
        child: child,
      ),
    );
  }

  bool _esTiempoCompleto() {
    if (_almuerzoHabilitado) {
      return true;
    }

    return _horariosDisponiblesParaAlmuerzo().any(
      (horario) => horario.toString().trim().toUpperCase().startsWith("TC"),
    );
  }

  bool _esNocturno() {
    return _horariosAsignados.any(
      (horario) => horario.toString().trim().toUpperCase().startsWith("NOCT"),
    );
  }

  bool _esHorarioNocturno(String horarioId) {
    return horarioId.trim().toUpperCase().startsWith('NOCT');
  }

  List<dynamic> _sanitizarHorarios(List<dynamic> horarios) {
    return horarios
        .map((horario) => horario.toString().trim())
        .where(
          (horario) =>
              horario.isNotEmpty &&
              horario.toLowerCase() != 'sin horario asignado',
        )
        .toList();
  }

  List<dynamic> _horariosDesdeVinculaciones(
    List<Map<String, dynamic>> vinculaciones,
  ) {
    return vinculaciones
        .map((v) => (v['horarioId'] ?? '').toString().trim())
        .where((horario) => horario.isNotEmpty)
        .toSet()
        .toList();
  }

  List<dynamic> _horariosDisponiblesParaAlmuerzo() {
    return {
      ..._horariosAsignados.map((horario) => horario.toString().trim()),
      ..._horariosDesdeVinculaciones(
        _vinculacionesAsistencia,
      ).map((horario) => horario.toString().trim()),
    }.where((horario) => horario.isNotEmpty).toList();
  }

  String _normalizarTipoVinculacion(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    return normalized == 'administrativo' ? 'administrativo' : 'academico';
  }

  String _etiquetaTipoVinculacion(String? value) {
    return _normalizarTipoVinculacion(value) == 'administrativo'
        ? UserRoleAccess.roleAdministrative
        : 'Personal academico';
  }

  bool _mismosHorarios(List<dynamic> a, List<dynamic> b) {
    if (a.length != b.length) {
      return false;
    }

    for (var i = 0; i < a.length; i++) {
      if (a[i].toString().trim() != b[i].toString().trim()) {
        return false;
      }
    }

    return true;
  }

  bool get _debeValidarUbicacion => _requiereGeolocalizacion && !_esNocturno();

  void _aplicarConfiguracionUsuario({
    required List<dynamic> horarios,
    required bool requiereGeolocalizacion,
    required List<Map<String, dynamic>> vinculacionesAsistencia,
    required String rolUsuario,
    required bool almuerzoHabilitado,
  }) {
    final horariosSinCambios = _mismosHorarios(_horariosAsignados, horarios);
    final geoSinCambios = _requiereGeolocalizacion == requiereGeolocalizacion;
    final mismoRol = _rolUsuario == rolUsuario;
    final mismoAlmuerzo = _almuerzoHabilitado == almuerzoHabilitado;
    final mismasVinculaciones =
        _vinculacionesAsistencia.length == vinculacionesAsistencia.length &&
        _vinculacionesAsistencia.every(
          (actual) => vinculacionesAsistencia.any(
            (nuevo) =>
                (nuevo['horarioId'] ?? '').toString() ==
                    (actual['horarioId'] ?? '').toString() &&
                _normalizarTipoVinculacion(
                      (nuevo['tipoVinculacion'] ?? '').toString(),
                    ) ==
                    _normalizarTipoVinculacion(
                      (actual['tipoVinculacion'] ?? '').toString(),
                    ),
          ),
        );

    if (horariosSinCambios &&
        geoSinCambios &&
        mismoRol &&
        mismoAlmuerzo &&
        mismasVinculaciones) {
      _configurarEscuchaAlmuerzo();
      return;
    }

    if (!mounted) {
      _horariosAsignados = horarios;
      _requiereGeolocalizacion = requiereGeolocalizacion;
      _vinculacionesAsistencia = vinculacionesAsistencia;
      _rolUsuario = rolUsuario;
      _almuerzoHabilitado = almuerzoHabilitado;
      return;
    }

    setState(() {
      _horariosAsignados = horarios;
      _requiereGeolocalizacion = requiereGeolocalizacion;
      _vinculacionesAsistencia = vinculacionesAsistencia;
      _rolUsuario = rolUsuario;
      _almuerzoHabilitado = almuerzoHabilitado;
      if (!_almuerzoHabilitado && _pestanaInternaActiva == 1) {
        _pestanaInternaActiva = 0;
      }
    });
    _configurarEscuchaAlmuerzo();

    if (_debeValidarUbicacion) {
      unawaited(_obtenerUbicacion());
    }
  }

  void _aplicarConfiguracionDesdeUsuario(Map<String, dynamic> usuario) {
    final remotos = _sanitizarHorarios(
      List<dynamic>.from(usuario['horarios_asignados'] as List? ?? const []),
    );
    final vinculaciones = _service.resolverVinculacionesAsistenciaUsuario(
      usuario,
    );
    final horariosVinculados = _sanitizarHorarios(
      _horariosDesdeVinculaciones(vinculaciones),
    );
    final requiereGeolocalizacion = _service
        .requiereGeolocalizacionUsuarioEfectiva(usuario);
    final almuerzoHabilitado = _service.usuarioTieneAlmuerzoHabilitado(usuario);

    _aplicarConfiguracionUsuario(
      horarios: remotos.isNotEmpty ? remotos : horariosVinculados,
      requiereGeolocalizacion: requiereGeolocalizacion,
      vinculacionesAsistencia: vinculaciones,
      rolUsuario: (usuario['rol'] ?? _rolUsuario).toString(),
      almuerzoHabilitado: almuerzoHabilitado,
    );
  }

  Future<void> _sincronizarHorariosUsuario() async {
    try {
      final usuario = await _service.obtenerUsuarioPorCorreo(
        widget.correoUsuario,
      );
      if (!mounted || usuario == null) {
        return;
      }
      _aplicarConfiguracionDesdeUsuario(usuario);
    } catch (e) {
      debugPrint('No se pudo sincronizar el horario del usuario: $e');
    }
  }

  void _escucharHorarioUsuario() {
    _usuarioHorarioSubscription?.cancel();

    final correoNormalizado = _normalizarCorreo(widget.correoUsuario);
    if (correoNormalizado.isEmpty) {
      return;
    }

    _usuarioHorarioSubscription = FirebaseFirestore.instance
        .collection('usuarios')
        .where('correo', isEqualTo: correoNormalizado)
        .snapshots()
        .listen((snapshot) {
          if (!mounted || snapshot.docs.isEmpty) {
            return;
          }

          QueryDocumentSnapshot<Map<String, dynamic>>? usuarioDoc;
          for (final doc in snapshot.docs) {
            if (SedeAccess.matchesSede(doc.data(), _branding.sedeId)) {
              usuarioDoc = doc;
              break;
            }
          }

          usuarioDoc ??= snapshot.docs.first;
          _aplicarConfiguracionDesdeUsuario(usuarioDoc.data());
        });
  }

  void _configurarEscuchaAlmuerzo() {
    _almuerzoSubscription?.cancel();

    if (!_esTiempoCompleto()) {
      if (mounted &&
          (_estadoAlmuerzo != "pendiente" ||
              _horaAlmuerzoInicio != "--:--" ||
              _horaAlmuerzoFin != "--:--")) {
        setState(() {
          _estadoAlmuerzo = "pendiente";
          _horaAlmuerzoInicio = "--:--";
          _horaAlmuerzoFin = "--:--";
        });
      }
      return;
    }

    _escucharEstadoAlmuerzo();
  }

  Future<Map<String, String>> _validarHorarioAlmuerzo() async {
    try {
      final horarioAlmuerzo = await _service.obtenerHorarioAlmuerzoUsuario(
        correo: widget.correoUsuario,
        listaHorarios: _horariosDisponiblesParaAlmuerzo(),
      );

      if (horarioAlmuerzo == null) {
        return {
          'permitido': 'false',
          'titulo': 'Horario no disponible',
          'mensaje':
              'No se encuentra un horario de almuerzo configurado para su jornada.',
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
              'No se encuentra un horario de almuerzo configurado para su jornada.',
        };
      }

      String inicioStr = doc['almuerzo_inicio']; 
      String finStr = doc['almuerzo_fin'];       

      */
      final ahora = DateTime.now();
      final horaActualMinutos = ahora.hour * 60 + ahora.minute;

      final partesInicio = inicioStr.split(':');
      final inicioMinutos =
          int.parse(partesInicio[0]) * 60 + int.parse(partesInicio[1]);

      final partesFin = finStr.split(':');
      final finMinutos = int.parse(partesFin[0]) * 60 + int.parse(partesFin[1]);

      if (horaActualMinutos < inicioMinutos) {
        return {
          'permitido': 'false',
          'titulo': 'Horario no permitido',
          'mensaje':
              'Su horario de almuerzo aun no inicia. Podra¡ registrarlo desde las $inicioStr.',
        };
      }

      if (horaActualMinutos > finMinutos) {
        return {
          'permitido': 'false',
          'titulo': 'Horario finalizado',
          'mensaje':
              'El tiempo asignado para registrar su almuerzo ya terminó. Su horario habilitado era de $inicioStr a $finStr.',
        };
      }

      return {'permitido': 'true', 'titulo': '', 'mensaje': ''};
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
    if (!_debeValidarUbicacion) {
      return true;
    }

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
      _geoConfig.latitude,
      _geoConfig.longitude,
      posicion.latitude,
      posicion.longitude,
    );

    if (distancia <= _geoConfig.radiusMeters) {
      return true;
    } else {
      throw Exception(
        "Debes estar dentro del instituto (${_geoConfig.radiusMeters.toStringAsFixed(0)} metros).",
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _horariosAsignados = _sanitizarHorarios(widget.horariosDocente);
    _rolUsuario = widget.rolUsuario ?? UserRoleAccess.roleTeacher;
    _vinculacionesAsistencia = _horariosAsignados
        .map(
          (horario) => {
            'tipoVinculacion': UserRoleAccess.isAdministrativeRole(_rolUsuario)
                ? 'administrativo'
                : 'academico',
            'rol': _rolUsuario,
            'horarioId': horario.toString().trim(),
            'areaId': '',
            'areaNombre': '',
            'cargo': '',
            'esSecundaria': false,
          },
          )
        .toList();
    _almuerzoHabilitado = _horariosAsignados.any(
      (horario) => horario.toString().trim().toUpperCase().startsWith('TC'),
    );
    _configurarEscuchaAlmuerzo();
    _escucharAvisosUsuario();
    _escucharHorarioUsuario();
  }

  void _escucharEstadoAlmuerzo() {
    String hoy = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _almuerzoSubscription = FirebaseFirestore.instance
        .collection('registros_almuerzo')
        .where('correo_usuario', isEqualTo: widget.correoUsuario)
        .where('fecha', isEqualTo: hoy)
        .snapshots()
        .listen((snapshot) {
          var nextEstado = "pendiente";
          var nextHoraInicio = "--:--";
          var nextHoraFin = "--:--";
          if (snapshot.docs.isNotEmpty) {
            var data = snapshot.docs.first.data();
            nextEstado = (data['estado'] ?? "pendiente").toString();
            nextHoraInicio = (data['hora_salida'] ?? "--:--").toString();
            nextHoraFin = (data['hora_regreso'] ?? "--:--").toString();
          }
          if (!mounted) {
            return;
          }
          if (_estadoAlmuerzo == nextEstado &&
              _horaAlmuerzoInicio == nextHoraInicio &&
              _horaAlmuerzoFin == nextHoraFin) {
            return;
          }
          setState(() {
            _estadoAlmuerzo = nextEstado;
            _horaAlmuerzoInicio = nextHoraInicio;
            _horaAlmuerzoFin = nextHoraFin;
          });
        });
  }

  @override
  void dispose() {
    _avisosSubscription?.cancel();
    _almuerzoSubscription?.cancel();
    _usuarioHorarioSubscription?.cancel();
    super.dispose();
  }

  String _normalizarCorreo(String value) => value.trim().toLowerCase();

  bool _esAvisoVisibleParaUsuario(Map<String, dynamic> data) {
    final destinatario = _normalizarCorreo(
      (data['destinatarioCorreo'] ?? '').toString(),
    );
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
            return _esAvisoVisibleParaUsuario(data) &&
                _esAvisoNotificable(data);
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

            final data = change.doc.data();
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
    final esAprobacion =
        (data['tipo'] ?? '').toString().trim().toLowerCase() ==
        'solicitud_aprobada';
    final messenger = ScaffoldMessenger.of(context);

    if (kIsWeb) {
      final permission = await browser_notification
          .browserNotificationPermission();
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
              color: Colors.white.withValues(alpha: 0.97),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: (esAprobacion ? Colors.green : colorInstitucional)
                    .withValues(alpha: 0.30),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
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
                          .withValues(alpha: 0.12),
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
              icon: Icon(Icons.close_rounded, color: Colors.grey[600]),
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
      await _sincronizarHorariosUsuario();
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

      if (_debeValidarUbicacion) {
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

  bool _esSalidaAnticipadaAutorizada(Map<String, String> res) =>
      (res['estado'] ?? '').trim() == 'Salida anticipada autorizada';

  bool _esSalidaConRetraso(Map<String, String> res) =>
      (res['estado'] ?? '').trim() == 'Salida con retraso';

  String _tituloDialogoRegistro(bool esEntrada, Map<String, String> res) {
    if (_tienePermisoActivo(res)) {
      return esEntrada
          ? "Entrada registrada con permiso"
          : "Salida registrada con permiso";
    }
    if (!esEntrada && _esSalidaAnticipadaAutorizada(res)) {
      return "Salida registrada con horario especial";
    }
    if (!esEntrada && _esSalidaConRetraso(res)) {
      return "Salida registrada con retraso";
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
    if (_esSalidaAnticipadaAutorizada(res)) {
      return colorInstitucional;
    }
    if (_esSalidaConRetraso(res)) {
      return Colors.orange;
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
    final horarioEspecial = (res['horarioEspecialRango'] ?? '').trim();
    final ventanaHorarioEspecial = (res['horarioEspecialVentanaSalida'] ?? '')
        .trim();
    final motivoHorarioEspecial = (res['motivoHorarioEspecial'] ?? '').trim();

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

    if (!esEntrada && _esSalidaAnticipadaAutorizada(res)) {
      final buffer = StringBuffer()
        ..writeln(
          'Tu salida fue registrada correctamente con un horario especial autorizado para esta sede.',
        )
        ..writeln()
        ..writeln('Bloque asignado: $bloque')
        ..writeln('Hora registrada: $hora')
        ..writeln('Estado del registro: $estadoVisible');

      if (horarioEspecial.isNotEmpty) {
        buffer.writeln('Horario especial aplicado: $horarioEspecial');
      }

      if (ventanaHorarioEspecial.isNotEmpty) {
        buffer.writeln('Ventana valida de salida: $ventanaHorarioEspecial');
      }

      if (motivoHorarioEspecial.isNotEmpty) {
        buffer.writeln('Motivo institucional: $motivoHorarioEspecial');
      }

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

    if (_esSalidaConRetraso(res)) {
      return 'Tu salida fue registrada correctamente, pero quedo fuera de la tolerancia de 10 minutos del horario asignado.\n\n'
          'Bloque asignado: $bloque\n'
          'Hora registrada: $hora\n'
          'Estado del registro: Salida con retraso';
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
        title: Text(
          titulo,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              "Entendido",
              style: TextStyle(
                color: colorInstitucional,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _debeValidarUbicacionParaContexto(Map<String, dynamic>? contexto) {
    if (!_requiereGeolocalizacion) {
      return false;
    }
    if (contexto == null) {
      return !_esNocturno();
    }
    final horarioId = (contexto['horarioId'] ?? '').toString();
    return !_esHorarioNocturno(horarioId);
  }

  Future<Map<String, dynamic>?> _mostrarDialogoSeleccionVinculacion(
    List<Map<String, dynamic>> contextos,
  ) async {
    if (!mounted) {
      return null;
    }

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Selecciona la jornada a registrar'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: contextos.map((contexto) {
              final tipo = _etiquetaTipoVinculacion(
                (contexto['tipoVinculacion'] ?? '').toString(),
              );
              final horario = (contexto['nombre'] ?? 'Horario').toString();
              final rango =
                  '${(contexto['entrada'] ?? '--:--').toString()} a ${(contexto['salida'] ?? '--:--').toString()}';
              final area = (contexto['areaVinculada'] ?? '').toString().trim();
              final cargo = (contexto['cargoVinculado'] ?? '')
                  .toString()
                  .trim();

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(14),
                    alignment: Alignment.centerLeft,
                    side: BorderSide(
                      color: colorInstitucional.withValues(alpha: 0.36),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx, contexto),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tipo,
                        style: TextStyle(
                          color: colorInstitucional,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        horario,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(rango, style: TextStyle(color: Colors.grey[700])),
                      if (area.isNotEmpty || cargo.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          [
                            area,
                            cargo,
                          ].where((item) => item.trim().isNotEmpty).join(' · '),
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>?> _seleccionarContextoMarcacion(
    bool esEntrada,
  ) async {
    if (_vinculacionesAsistencia.isEmpty) {
      return null;
    }

    final contextos = await _service.obtenerContextosMarcacionActivos(
      vinculacionesAsistencia: _vinculacionesAsistencia,
      esEntrada: esEntrada,
      sedeId: _branding.sedeId,
    );

    if (contextos.length <= 1) {
      return contextos.isEmpty ? null : contextos.first;
    }

    return _mostrarDialogoSeleccionVinculacion(contextos);
  }

  Future<void> _ejecutarRegistro(bool esEntrada) async {
    final bool yaProcesando = esEntrada
        ? _procesandoEntrada
        : _procesandoSalida;
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
      await _sincronizarHorariosUsuario();
      final contextoSeleccionado = await _seleccionarContextoMarcacion(
        esEntrada,
      );
      if (!mounted) return;

      final requiereResolverHorarioPrimero =
          _vinculacionesAsistencia.length > 1 && contextoSeleccionado == null;

      if (!requiereResolverHorarioPrimero &&
          _debeValidarUbicacionParaContexto(contextoSeleccionado)) {
        await _estaEnElInstituto();
      }

      final res = await _service.registrarMarcacion(
        nombreUsuario: widget.nombreDocente,
        correoUsuario: widget.correoUsuario,
        listaHorarios: _horariosAsignados,
        esEntrada: esEntrada,
        sedeId: _branding.sedeId,
        sedeNombre: _branding.sedeName,
        vinculacionesAsistencia: _vinculacionesAsistencia,
        contextoSeleccionado: contextoSeleccionado,
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
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_ind_rounded),
            label: "Asistencia",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.insert_chart_outlined_rounded),
            label: "Estadísticas",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_active_outlined),
            label: "Avisos",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.description_outlined),
            label: "Solicitudes",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_circle_outlined),
            label: "Perfil",
          ),
        ],
      ),
    );
  }

  // --- MÃ‰TODO MODIFICADO: SOLO EL FONDO CAMBIA ---
  Widget _construirCuerpoInicioSelector() {
    final bool isCentro = _branding.sedeId == AppBranding.sedeCentro.sedeId;
    final String tituloAsistencia =
        _branding.sedeId == AppBranding.sedeNorte.sedeId
        ? "ASISTENCIA SEDE NORTE"
        : isCentro
        ? "ASISTENCIA SEDE CENTRO"
        : _branding.sedeId == AppBranding.sedeCreSer.sedeId
        ? "ASISTENCIA CRE SER"
        : "REGISTRO DE ASISTENCIA";

    if (_isWebPortal) {
      return _buildWebAttendanceHome(tituloAsistencia);
    }

    return Scaffold(
      body: Stack(
        children: [
          // 1. FONDO BASE
          Container(color: _branding.background),

          // 2. PATRÓN DE FONDO Y MARCA DE AGUA SOLO EN MOVIL
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

          Center(
            child: Opacity(
              opacity: 0.12,
              child: ShaderMask(
                shaderCallback: (rect) {
                  return LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colorInstitucional.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ).createShader(rect);
                },
                blendMode: BlendMode.srcATop,
                child: Image.asset(
                  _branding.logoWatermark,
                  width:
                      MediaQuery.of(context).size.width *
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
                maxWidth: _isWebPortal ? 980 : double.infinity,
              ),
              child: Column(
                children: [
                  Center(
                    child: SizedBox(
                      width: _isWebPortal ? 320 : double.infinity,
                      child: Container(
                        height: 160,
                        padding: const EdgeInsets.only(
                          top: 50,
                          left: 20,
                          right: 20,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [colorInstitucional, _branding.primaryDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(35),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Image.asset(
                              _branding.logoSmall,
                              height: _branding.mobileHeaderLogoHeight,
                              errorBuilder: (c, e, s) => const Icon(
                                Icons.school,
                                size: 40,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
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
                    padding: EdgeInsets.symmetric(
                      horizontal: _isWebPortal ? 0 : 25.0,
                    ),
                    child: _wrapWebSection(
                      Container(
                        height: _isWebPortal ? 52 : 55,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            _buildBotonSelector(0, "ASISTENCIA"),
                            if (_esTiempoCompleto())
                              _buildBotonSelector(1, "ALMUERZO"),
                          ],
                        ),
                      ),
                      maxWidth: _isWebPortal ? 560 : null,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.all(_isWebPortal ? 28.0 : 25.0),
                      child:
                          (_pestanaInternaActiva == 0 || !_esTiempoCompleto())
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

  Widget _buildWebAttendanceHome(String tituloAsistencia) {
    final contenido = (_pestanaInternaActiva == 0 || !_esTiempoCompleto())
        ? _construirContenidoAsistencia()
        : _construirContenidoAlmuerzoSolo();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < 560;
        final pagePadding = isPhone ? 14.0 : 28.0;

        return Container(
          color: const Color(0xFFF4F7F8),
          child: SingleChildScrollView(
            primary: true,
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  pagePadding,
                  pagePadding,
                  pagePadding,
                  isPhone ? 24 : 34,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _wrapWebSection(
                      _buildWebAttendanceHero(tituloAsistencia),
                      maxWidth: 1120,
                    ),
                    SizedBox(height: isPhone ? 16 : 22),
                    _wrapWebSection(_buildWebAttendanceTabs(), maxWidth: 560),
                    SizedBox(height: isPhone ? 16 : 22),
                    contenido,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWebAttendanceHero(String tituloAsistencia) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(_isPhoneWebLayout ? 18 : 28),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colorInstitucional.withValues(alpha: 0.32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 840;
          final phone = constraints.maxWidth < 520;

          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Panel de asistencia',
                style: TextStyle(
                  color: colorInstitucional,
                  fontSize: phone ? 12 : 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                tituloAsistencia,
                style: TextStyle(
                  color: Color(0xFF223334),
                  fontSize: phone ? 22 : 30,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Registra entradas, salidas y almuerzos desde una vista mas clara para escritorio. El desplazamiento ahora funciona sobre toda la pagina principal.',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.62),
                  fontSize: phone ? 13 : 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildWebAttendancePill(
                    Icons.apartment_outlined,
                    SedeAccess.displayNameForId(_branding.sedeId),
                  ),
                  _buildWebAttendancePill(
                    Icons.schedule_outlined,
                    _esTiempoCompleto()
                        ? 'Almuerzo habilitado'
                        : 'Solo asistencia',
                  ),
                ],
              ),
            ],
          );

          final sidePanel = Container(
            constraints: phone ? null : const BoxConstraints(maxWidth: 300),
            padding: EdgeInsets.all(phone ? 18 : 22),
            decoration: BoxDecoration(
              color: colorInstitucional.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: colorInstitucional.withValues(alpha: 0.22),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Image.asset(
                    _branding.logoSmall,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        Icon(Icons.school_rounded, color: colorInstitucional),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Sesion activa',
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.50),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.nombreDocente,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF223334),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Usa los modulos de asistencia y almuerzo sin cambiar de vista.',
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.60),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [info, const SizedBox(height: 20), sidePanel],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: info),
              const SizedBox(width: 24),
              sidePanel,
            ],
          );
        },
      ),
    );
  }

  Widget _buildWebAttendanceTabs() {
    return Container(
      padding: EdgeInsets.all(_isPhoneWebLayout ? 4 : 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_isPhoneWebLayout ? 18 : 20),
        border: Border.all(color: colorInstitucional.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildBotonSelector(0, "ASISTENCIA"),
          if (_esTiempoCompleto()) _buildBotonSelector(1, "ALMUERZO"),
        ],
      ),
    );
  }

  Widget _buildWebAttendancePill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorInstitucional.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorInstitucional),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: colorInstitucional,
              fontSize: 12,
              fontWeight: FontWeight.w700,
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
          margin: EdgeInsets.symmetric(
            horizontal: _isPhoneWebLayout ? 3 : (_isWebPortal ? 5 : 6),
            vertical: 6,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: estaActivo ? colorInstitucional : Colors.transparent,
            borderRadius: BorderRadius.circular(
              _isPhoneWebLayout ? 14 : (_isWebPortal ? 16 : 15),
            ),
            boxShadow: estaActivo
                ? [
                    BoxShadow(
                      color: colorInstitucional.withValues(alpha: 0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Text(
            texto,
            style: TextStyle(
              fontSize: _isPhoneWebLayout ? 11 : (_isWebPortal ? 12 : 11),
              fontWeight: FontWeight.bold,
              color: estaActivo
                  ? Colors.white
                  : colorInstitucional.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapaMini() {
    final tileProvider = kIsWeb ? CancellableNetworkTileProvider() : null;

    final mapCard = Container(
      height: _isPhoneWebLayout ? 180 : (_isWebPortal ? 230 : 180),
      margin: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white, width: 5),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
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
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              retinaMode: RetinaMode.isHighDensity(context),
              tileProvider: tileProvider,
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: _ubicacionInstituto,
                  width: 45,
                  height: 45,
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 40,
                  ),
                ),
                if (_posicionActual != null)
                  Marker(
                    point: LatLng(
                      _posicionActual!.latitude,
                      _posicionActual!.longitude,
                    ),
                    width: 45,
                    height: 45,
                    child: const Icon(
                      Icons.person_pin_circle,
                      color: Colors.blue,
                      size: 40,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    return _wrapWebSection(
      mapCard,
      maxWidth: _webSectionMaxWidth(compact: 720, regular: 820, wide: 860),
    );
  }

  Widget _construirContenidoAsistencia() {
    final showStackedActions = _isNarrowWebLayout;

    return Column(
      children: [
        _wrapWebSection(
          _buildRelojCard(),
          maxWidth: _webSectionMaxWidth(compact: 720, regular: 820, wide: 860),
        ),
        const SizedBox(height: 15),
        _wrapWebSection(
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colorInstitucional.withValues(alpha: 0.22),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorInstitucional.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.wb_sunny_rounded,
                    color: colorInstitucional,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 15),
                const Expanded(
                  child: Text(
                    "Tu jornada está activa. Recuerda marcar a tiempo tus ingresos y salidas.",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black87,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          maxWidth: _webSectionMaxWidth(compact: 720, regular: 820, wide: 860),
        ),
        if (!_esNocturno()) _buildMapaMini(),
        const SizedBox(height: 10),
        if (_isWebPortal)
          _wrapWebSection(
            showStackedActions
                ? Column(
                    children: [
                      _botonAsistencia(
                        titulo: "MARCAR ENTRADA",
                        subtitulo: "Iniciar registro de hoy",
                        icon: Icons.login_rounded,
                        color: colorInstitucional,
                        procesando: _procesandoEntrada,
                        onTap: () => _ejecutarRegistro(true),
                      ),
                      const SizedBox(height: 14),
                      _botonAsistencia(
                        titulo: "MARCAR SALIDA",
                        subtitulo: "Finalizar labores",
                        icon: Icons.logout_rounded,
                        color: const Color(0xFF2C3E50),
                        procesando: _procesandoSalida,
                        onTap: () => _ejecutarRegistro(false),
                      ),
                    ],
                  )
                : Row(
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
                      const SizedBox(width: 16),
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
                  ),
            maxWidth: _webSectionMaxWidth(
              compact: 720,
              regular: 820,
              wide: 860,
            ),
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
          _wrapWebSection(
            SizedBox(width: 320, child: _botonHistorial(false)),
            maxWidth: 320,
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
        _wrapWebSection(
          _buildRelojCard(),
          maxWidth: _webSectionMaxWidth(compact: 720, regular: 820, wide: 860),
        ),
        if (!_esNocturno()) _buildMapaMini(),
        const SizedBox(height: 10),
        if (_isWebPortal)
          _wrapWebSection(
            almuerzoCard,
            maxWidth: _webSectionMaxWidth(
              compact: 720,
              regular: 820,
              wide: 860,
            ),
          )
        else
          almuerzoCard,
        const SizedBox(height: 25),
        if (_isWebPortal)
          _wrapWebSection(
            SizedBox(width: 320, child: _botonHistorial(true)),
            maxWidth: 320,
          )
        else
          _botonHistorial(true),
      ],
    );
  }

  Widget _buildRelojCard() {
    return _PortalClockCard(
      isPhoneWebLayout: _isPhoneWebLayout,
      isCompactWebLayout: _isCompactWebLayout,
      isWebPortal: _isWebPortal,
      colorInstitucional: colorInstitucional,
    );
  }

  Widget _buildWebPortal(Widget activeView) {
    final isAttendancePage = _indiceActual == 0;

    if (_isCompactWebLayout ||
        _webSidebarCollapsed ||
        _webViewportWidth < 1100) {
      return _buildResponsiveWebPortal(
        activeView: activeView,
        isAttendancePage: isAttendancePage,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F8),
      body: Row(
        children: [
          Container(
            width: 220,
            color: _branding.primaryDark,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
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
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                    Text(
                      'Portal del usuario',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white38),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sesión actual',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.68),
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
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            SedeAccess.displayNameForId(_branding.sedeId),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
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
                        color: Colors.white.withValues(alpha: 0.32),
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
                  height: 74,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
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
                      _buildWebHeaderAction(
                        icon: Icons.menu_open_rounded,
                        onTap: () {
                          setState(() {
                            _webSidebarCollapsed = true;
                          });
                        },
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
                          color: colorInstitucional.withValues(alpha: 0.08),
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
                    padding: isAttendancePage
                        ? EdgeInsets.zero
                        : const EdgeInsets.fromLTRB(18, 18, 22, 22),
                    child: isAttendancePage
                        ? activeView
                        : DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 22,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.92),
                                width: 1,
                              ),
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

  Widget _buildResponsiveWebPortal({
    required Widget activeView,
    required bool isAttendancePage,
  }) {
    final isMobileShell = _isCompactWebLayout;
    final isPhone = _isPhoneWebLayout;
    final sidebarWidth = isMobileShell ? 0.0 : 96.0;

    final content = isAttendancePage || isMobileShell
        ? activeView
        : DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.92),
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: activeView,
            ),
          );

    return Scaffold(
      key: _webPortalScaffoldKey,
      backgroundColor: const Color(0xFFF4F7F8),
      drawer: isMobileShell
          ? Drawer(
              width: isPhone ? _webViewportWidth * 0.86 : 320,
              child: _buildWebSidebar(collapsed: false, isDrawer: true),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (!isMobileShell)
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: sidebarWidth,
                color: _branding.primaryDark,
                child: _buildWebSidebar(collapsed: true, isDrawer: false),
              ),
            Expanded(
              child: Column(
                children: [
                  Container(
                    height: isPhone ? 68 : 74,
                    padding: EdgeInsets.symmetric(horizontal: isPhone ? 12 : 20),
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
                        _buildWebHeaderAction(
                          icon: isMobileShell
                              ? Icons.menu_rounded
                              : Icons.chevron_right_rounded,
                          onTap: () {
                            if (isMobileShell) {
                              _webPortalScaffoldKey.currentState?.openDrawer();
                              return;
                            }
                            setState(() {
                              _webSidebarCollapsed = false;
                            });
                          },
                        ),
                        SizedBox(width: isPhone ? 10 : 14),
                        Expanded(
                          child: Text(
                            _webSectionTitle(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xFF223334),
                              fontSize: isPhone ? 16 : 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (!isPhone)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: colorInstitucional.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.person_outline_rounded,
                                  color: colorInstitucional,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 180,
                                  ),
                                  child: Text(
                                    widget.nombreDocente,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colorInstitucional,
                                      fontWeight: FontWeight.w700,
                                    ),
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
                      padding: isAttendancePage || isMobileShell
                          ? EdgeInsets.zero
                          : const EdgeInsets.fromLTRB(18, 18, 22, 22),
                      child: content,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebSidebar({
    required bool collapsed,
    required bool isDrawer,
  }) {
    final initial = widget.nombreDocente.trim().isEmpty
        ? 'U'
        : widget.nombreDocente.trim()[0].toUpperCase();

    return ColoredBox(
      color: _branding.primaryDark,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            collapsed ? 12 : 16,
            18,
            collapsed ? 12 : 16,
            16,
          ),
          child: Column(
            crossAxisAlignment: collapsed
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: collapsed
                      ? Container(
                          width: 60,
                          height: 60,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Image.asset(
                            _branding.logoSmall,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.school,
                                  color: Colors.white,
                                  size: 30,
                                ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 96,
                              height: 96,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
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
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                            Text(
                              'Portal del usuario',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _buildWebSidebarIconButton(
                    icon: isDrawer
                        ? Icons.close_rounded
                        : (collapsed
                              ? Icons.chevron_right_rounded
                              : Icons.chevron_left_rounded),
                    onTap: () {
                      if (isDrawer) {
                        Navigator.of(context).pop();
                        return;
                      }
                      setState(() {
                        _webSidebarCollapsed = !collapsed;
                      });
                    },
                  ),
                ),
              ],
            ),
            SizedBox(height: collapsed ? 14 : 18),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(collapsed ? 10 : 13),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white38),
              ),
              child: collapsed
                  ? Column(
                      children: [
                        const Icon(
                          Icons.person_outline_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sesion actual',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.68),
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
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          SedeAccess.displayNameForId(_branding.sedeId),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
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
                      collapsed: collapsed,
                      onTap: isDrawer ? () => Navigator.of(context).pop() : null,
                    ),
                    const SizedBox(height: 10),
                    _buildWebNavItem(
                      index: 1,
                      icon: Icons.insert_chart_outlined_rounded,
                      label: 'Estadisticas',
                      collapsed: collapsed,
                      onTap: isDrawer ? () => Navigator.of(context).pop() : null,
                    ),
                    const SizedBox(height: 10),
                    _buildWebNavItem(
                      index: 2,
                      icon: Icons.notifications_active_outlined,
                      label: 'Avisos',
                      collapsed: collapsed,
                      onTap: isDrawer ? () => Navigator.of(context).pop() : null,
                    ),
                    const SizedBox(height: 10),
                    _buildWebNavItem(
                      index: 3,
                      icon: Icons.description_outlined,
                      label: 'Solicitudes',
                      collapsed: collapsed,
                      onTap: isDrawer ? () => Navigator.of(context).pop() : null,
                    ),
                    const SizedBox(height: 10),
                    _buildWebNavItem(
                      index: 4,
                      icon: Icons.account_circle_outlined,
                      label: 'Perfil',
                      collapsed: collapsed,
                      onTap: isDrawer ? () => Navigator.of(context).pop() : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (!collapsed)
              Text(
                'v1.0.2 - portal web',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.32),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebHeaderAction({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: colorInstitucional.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(icon, color: colorInstitucional, size: 22),
      ),
    );
  }

  Widget _buildWebSidebarIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _buildWebNavItem({
    required int index,
    required IconData icon,
    required String label,
    bool collapsed = false,
    VoidCallback? onTap,
  }) {
    final isActive = _indiceActual == index;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        setState(() => _indiceActual = index);
        onTap?.call();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: collapsed ? 10 : 14,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: isActive ? 0.0 : 0.18),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isActive
                    ? colorInstitucional.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                size: 20,
                color: isActive ? colorInstitucional : Colors.white,
              ),
            ),
            if (!collapsed) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isActive ? colorInstitucional : Colors.white,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: isActive
                    ? colorInstitucional.withValues(alpha: 0.90)
                    : Colors.white.withValues(alpha: 0.55),
                size: 22,
              ),
            ],
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
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
          ),
        ],
        border: Border.all(color: colorInstitucional.withValues(alpha: 0.30)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: colorInstitucional.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.restaurant_rounded,
              color: colorInstitucional,
              size: 35,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "JORNADA DE ALMUERZO",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 1,
            ),
          ),
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
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "Salida: $_horaAlmuerzoInicio  â€¢  Regreso: $_horaAlmuerzoFin",
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 20),
          if (finalizado)
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 18),
                SizedBox(width: 8),
                Text(
                  "Almuerzo registrado correctamente",
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _gestionarAlmuerzo,
                style: ElevatedButton.styleFrom(
                  backgroundColor: enCurso
                      ? Colors.redAccent
                      : Colors.orange[700],
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  enCurso ? "FINALIZAR ALMUERZO" : "INICIAR ALMUERZO",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
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
        label: Text(
          esAlmuerzo ? "HISTORIAL DE ALMUERZOS" : "HISTORIAL DE REGISTROS",
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: colorInstitucional,
          side: BorderSide(
            color: colorInstitucional.withValues(alpha: 0.52),
            width: 1.5,
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
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
          padding: EdgeInsets.all(_isWebPortal ? 18 : 20),
          decoration: BoxDecoration(
            color: procesando
                ? color.withValues(alpha: 0.10)
                : Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(_isWebPortal ? 22 : 25),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: procesando
                  ? color.withValues(alpha: 0.42)
                  : color.withValues(alpha: 0.22),
              width: procesando ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: EdgeInsets.all(_isWebPortal ? 11 : 12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: procesando ? 0.18 : 0.1),
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
              SizedBox(width: _isWebPortal ? 16 : 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      procesando ? "PROCESANDO..." : titulo,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontSize: _isWebPortal ? 14 : 15,
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

class _PortalClockCard extends StatefulWidget {
  const _PortalClockCard({
    required this.isPhoneWebLayout,
    required this.isCompactWebLayout,
    required this.isWebPortal,
    required this.colorInstitucional,
  });

  final bool isPhoneWebLayout;
  final bool isCompactWebLayout;
  final bool isWebPortal;
  final Color colorInstitucional;

  @override
  State<_PortalClockCard> createState() => _PortalClockCardState();
}

class _PortalClockCardState extends State<_PortalClockCard> {
  late Timer _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String get _horaActual => DateFormat('HH:mm:ss').format(_now);

  String get _fechaActual {
    try {
      return DateFormat('EEEE, d MMMM', 'es').format(_now).toUpperCase();
    } catch (_) {
      return DateFormat('EEEE, d MMMM').format(_now).toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = widget.isPhoneWebLayout
        ? 34.0
        : (widget.isCompactWebLayout
              ? 44.0
              : (widget.isWebPortal ? 54.0 : 40.0));

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        vertical: widget.isWebPortal ? 28 : 20,
        horizontal: 20,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: widget.colorInstitucional.withValues(alpha: 0.32),
        ),
      ),
      child: Column(
        children: [
          Text(
            _horaActual,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w200,
              color: widget.colorInstitucional,
              letterSpacing: widget.isPhoneWebLayout
                  ? 2
                  : (widget.isWebPortal ? 4 : 3),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _fechaActual,
            style: TextStyle(
              fontSize: widget.isPhoneWebLayout
                  ? 11
                  : (widget.isWebPortal ? 13 : 11),
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
              letterSpacing: widget.isPhoneWebLayout ? 1.1 : 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
