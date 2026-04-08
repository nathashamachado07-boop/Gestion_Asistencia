import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart'; // Asegúrate de tener intl en tu pubspec.yaml

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // --- COORDENADAS DE PRUEBA: SECTOR LA SANTIAGO (JUAN CAMACARO Y COPIAPÓ) ---
  final double latitudPrueba = -0.1843037; 
  final double longitudPrueba = -78.4909586;
  final double rangoMaximoMetros = 100; 

  // --- FUNCIÓN PARA VALIDAR GPS ---
  Future<void> _validarUbicacionGPS() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception("El GPS está desactivado. Por favor, actívalo en los ajustes de tu celular.");
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception("Permiso de ubicación denegado. La app necesita el GPS para validar tu asistencia.");
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      throw Exception("Los permisos de ubicación están bloqueados permanentemente. Actívalos en la configuración.");
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high
    );

    double distanciaEnMetros = Geolocator.distanceBetween(
      position.latitude, 
      position.longitude, 
      latitudPrueba, 
      longitudPrueba
    );

    if (distanciaEnMetros > rangoMaximoMetros) {
      // Actualizado con el nombre de la nueva ubicación
      throw Exception("Fuera de rango (${distanciaEnMetros.toStringAsFixed(0)}m). Debes estar en el sector La Santiago para marcar.");
    }
  }

  // Login: Trae al usuario y su lista de horarios
  Future<Map<String, dynamic>?> validarLogin(String correo, String password) async {
    QuerySnapshot userQuery = await _db
        .collection('usuarios')
        .where('correo', isEqualTo: correo)
        .where('password', isEqualTo: password)
        .get();

    if (userQuery.docs.isNotEmpty) {
      return userQuery.docs.first.data() as Map<String, dynamic>;
    }
    return null;
  }

  // Marcación: Busca en la lista de la captura con VALIDACIÓN DE ESTADO
  Future<Map<String, String>> registrarMarcacion({
    required String nombreUsuario,
    required List<dynamic> listaHorarios, 
    required bool esEntrada,
  }) async {
    
    // --- LLAMADA A LA FUNCIÓN DE GPS ---
    await _validarUbicacionGPS();

    DateTime ahora = DateTime.now();

    // --- 1. NUEVA VALIDACIÓN DE DUPLICADOS ---
    QuerySnapshot ultimoRegistroQuery = await _db
        .collection('asistencias_realizadas')
        .where('docente', isEqualTo: nombreUsuario)
        .orderBy('fecha', descending: true)
        .limit(1)
        .get();

    if (ultimoRegistroQuery.docs.isNotEmpty) {
      var ultimoDoc = ultimoRegistroQuery.docs.first.data() as Map<String, dynamic>;
      String ultimoTipo = ultimoDoc['tipo'] ?? "";

      if (esEntrada && ultimoTipo == "ENTRADA") {
        throw Exception("Ya tienes una ENTRADA activa. Debes marcar SALIDA primero.");
      }
      if (!esEntrada && ultimoTipo == "SALIDA") {
        throw Exception("Ya marcaste SALIDA. Debes esperar a tu siguiente bloque para entrar.");
      }
    } else {
      if (!esEntrada) {
        throw Exception("No puedes marcar SALIDA sin haber registrado una ENTRADA previa.");
      }
    }

    // --- 2. LÓGICA ORIGINAL DE HORARIOS ---
    DocumentSnapshot? horarioSeleccionado;

    for (String id in listaHorarios) {
      DocumentSnapshot doc = await _db.collection('horarios').doc(id).get();
      if (!doc.exists) continue;

      int horaInicio = int.parse(doc['entrada'].split(":")[0]);
      int horaFin = int.parse(doc['salida'].split(":")[0]);

      if (ahora.hour >= (horaInicio - 1) && ahora.hour <= (horaFin + 1)) {
        horarioSeleccionado = doc;
        break;
      }
    }

    if (horarioSeleccionado == null) {
      throw Exception("No tienes clases programadas en este horario.");
    }

    // Validación de tiempos
    String horaOficialStr = esEntrada ? horarioSeleccionado['entrada'] : horarioSeleccionado['salida'];
    int horaLimite = int.parse(horaOficialStr.split(":")[0]);
    String horaActualStr = "${ahora.hour}:${ahora.minute.toString().padLeft(2, '0')}";

    String estado = "A tiempo";
    if (esEntrada && ahora.hour > horaLimite) {
      estado = "Atraso";
    } else if (!esEntrada && ahora.hour < horaLimite) {
      estado = "Salida Anticipada";
    } else if (!esEntrada) {
      estado = "Completada";
    }

    // --- 3. GUARDAR REGISTRO ---
    await _db.collection('asistencias_realizadas').add({
      'docente': nombreUsuario,
      'tipo': esEntrada ? "ENTRADA" : "SALIDA",
      'horario_ref': horarioSeleccionado['nombre'],
      'hora_marcada': horaActualStr,
      'estado': estado,
      'fecha': ahora, 
      'observacion': "Registro realizado correctamente."
    });

    return {
      'estado': estado, 
      'bloque': horarioSeleccionado['nombre'], 
      'hora': horaActualStr
    };
  }

  // ==========================================
  // FUNCIÓN: OBTENER HISTORIAL
  // ==========================================
  Future<List<Map<String, dynamic>>> obtenerHistorialAsistencias(String nombreDocente) async {
    try {
      QuerySnapshot snapshot = await _db
          .collection('asistencias_realizadas')
          .where('docente', isEqualTo: nombreDocente)
          .orderBy('fecha', descending: true) 
          .get();

      return snapshot.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print("Error al obtener el historial: $e");
      QuerySnapshot snapshot = await _db
          .collection('asistencias_realizadas')
          .where('docente', isEqualTo: nombreDocente)
          .get();
      return snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
    }
  }

  // Busca todos los detalles de un usuario por su correo
  Future<Map<String, dynamic>?> obtenerDatosPerfil(String correo) async {
    try {
      QuerySnapshot snapshot = await _db
          .collection('usuarios')
          .where('correo', isEqualTo: correo)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.first.data() as Map<String, dynamic>;
      }
    } catch (e) {
      print("Error al obtener perfil: $e");
    }
    return null;
  }

  // Función para obtener estadísticas del docente
  Future<Map<String, int>> obtenerEstadisticasDocente(String nombreDocente) async {
    try {
      QuerySnapshot snapshot = await _db
          .collection('asistencias_realizadas')
          .where('docente', isEqualTo: nombreDocente)
          .get();

      int aTiempo = 0;
      int atrasos = 0;
      int salidasAnticipadas = 0;

      for (var doc in snapshot.docs) {
        String estado = doc['estado'] ?? "";
        if (estado == "A tiempo" || estado == "Completada") aTiempo++;
        else if (estado == "Atraso") atrasos++;
        else if (estado == "Salida Anticipada") salidasAnticipadas++;
      }

      return {
        'Puntual': aTiempo,
        'Atraso': atrasos,
        'Salida Anticipada': salidasAnticipadas,
        'Total': snapshot.docs.length,
      };
    } catch (e) {
      print("Error en estadísticas: $e");
      return {'Puntual': 0, 'Atraso': 0, 'Salida Anticipada': 0, 'Total': 0};
    }
  }

  // ==========================================
  // NUEVAS FUNCIONES PARA ALMUERZO
  // ==========================================

  // Verifica si el horario del usuario es de tiempo completo
  Future<Map<String, dynamic>?> obtenerInfoHorario(String idHorario) async {
    DocumentSnapshot doc = await _db.collection('horarios').doc(idHorario).get();
    if (doc.exists) {
      return doc.data() as Map<String, dynamic>;
    }
    return null;
  }

  // Registrar salida al almuerzo
  Future<void> registrarInicioAlmuerzo(String correo) async {
    String fechaHoy = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String horaActual = DateFormat('HH:mm:ss').format(DateTime.now());

    await _db.collection('registros_almuerzo').add({
      'correo_usuario': correo,
      'fecha': fechaHoy,
      'hora_salida': horaActual,
      'hora_regreso': "",
      'estado': "en_almuerzo",
    });
  }

  // Registrar regreso del almuerzo
  Future<void> registrarFinAlmuerzo(String correo) async {
    String fechaHoy = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String horaActual = DateFormat('HH:mm:ss').format(DateTime.now());

    var query = await _db.collection('registros_almuerzo')
        .where('correo_usuario', isEqualTo: correo)
        .where('fecha', isEqualTo: fechaHoy)
        .where('estado', isEqualTo: "en_almuerzo")
        .get();

    if (query.docs.isNotEmpty) {
      await query.docs.first.reference.update({
        'hora_regreso': horaActual,
        'estado': "finalizado",
      });
    } else {
      throw Exception("No se encontró un inicio de almuerzo activo para hoy.");
    }
  }

  // Obtener estado actual del almuerzo para la UI
  Future<String> obtenerEstadoAlmuerzoHoy(String correo) async {
    String fechaHoy = DateFormat('yyyy-MM-dd').format(DateTime.now());
    var query = await _db.collection('registros_almuerzo')
        .where('correo_usuario', isEqualTo: correo)
        .where('fecha', isEqualTo: fechaHoy)
        .get();

    if (query.docs.isEmpty) return "pendiente";
    
    // Si hay registros, buscamos si alguno está "en_almuerzo"
    for (var doc in query.docs) {
      if (doc['estado'] == "en_almuerzo") return "en_almuerzo";
    }
    
    return "finalizado";
  }
}