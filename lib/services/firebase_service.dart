import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // --- COORDENADAS DEL INSTITUTO ---
  static const double latitudInstituto = -0.1843090;
  static const double longitudInstituto = -78.4909804;
  static const double rangoMaximoMetros = 40.0;

  // --- FUNCIÓN PARA OBTENER NÚMERO DE MES ---
  int _obtenerNumeroMes(String mes) {
    const meses = {
      "Enero": 1,
      "Febrero": 2,
      "Marzo": 3,
      "Abril": 4,
      "Mayo": 5,
      "Junio": 6,
      "Julio": 7,
      "Agosto": 8,
      "Septiembre": 9,
      "Octubre": 10,
      "Noviembre": 11,
      "Diciembre": 12,
    };
    return meses[mes] ?? DateTime.now().month;
  }

  // --- FUNCIÓN PARA VALIDAR GPS ---

  // Login: Trae al usuario y su lista de horarios
  Future<Map<String, dynamic>?> validarLogin(String correo, String password) async {
  print("Intentando login con: $correo"); // Ver que llega el correo
  
  QuerySnapshot userQuery = await _db
      .collection('usuarios')
      .where('correo', isEqualTo: correo.trim())
      .get();

  print("Documentos encontrados: ${userQuery.docs.length}"); // Si sale 0, el correo no coincide

  if (userQuery.docs.isNotEmpty) {
    var data = userQuery.docs.first.data() as Map<String, dynamic>;
    print("Password en DB: ${data['password']}");
    print("Password ingresada: $password");
    
    if (data['password'] == password) {
      return data;
    }
  }
  return null;
}
  // Marcación: Busca en la lista de la captura con VALIDACIÓN DE ESTADO
  Future<Map<String, String>> registrarMarcacion({
    required String nombreUsuario,
    required List<dynamic> listaHorarios, 
    required bool esEntrada,
  }) async {
    
    // await _validarUbicacionGPS(); // Descomentar cuando se requiera GPS real

    DateTime ahora = DateTime.now();

    // 1. VALIDACIÓN DE DUPLICADOS
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

    // 2. LÓGICA DE HORARIOS
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

    String horaOficialStr = esEntrada ? horarioSeleccionado['entrada'] : horarioSeleccionado['salida'];
    int horaLimite = int.parse(horaOficialStr.split(":")[0]);
    String horaActualStr = DateFormat('HH:mm').format(ahora);

    String estado = "A tiempo";
    if (esEntrada && ahora.hour > horaLimite) {
      estado = "Atraso";
    } else if (!esEntrada && ahora.hour < horaLimite) {
      estado = "Salida Anticipada";
    } else if (!esEntrada) {
      estado = "Completada";
    }

    // 3. GUARDAR REGISTRO
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
      return [];
    }
  }

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
      debugPrint("Error al obtener perfil: $e");
    }
    return null;
  }

  Future<Map<String, int>> obtenerEstadisticasDocente(
  String nombre, {
  String mes = "Todos",
}) async {
    final snapshot = await _db
        .collection('asistencias_realizadas')
        .where('docente', isEqualTo: nombre)
        .get();

    final docs = snapshot.docs
        .map((doc) => doc.data())
        .whereType<Map<String, dynamic>>()
        .toList();

    final List<Map<String, dynamic>> filtrados = mes == "Todos"
        ? docs
        : docs.where((data) {
            final fechaCampo = data['fecha'];
            DateTime? fecha;

            if (fechaCampo is Timestamp) {
              fecha = fechaCampo.toDate();
            } else if (fechaCampo is DateTime) {
              fecha = fechaCampo;
            } else if (fechaCampo is String) {
              try {
                fecha = DateTime.parse(fechaCampo);
              } catch (_) {
                return false;
              }
            }

            if (fecha == null) return false;
            final int numeroMes = _obtenerNumeroMes(mes);
            return fecha.month == numeroMes && fecha.year == DateTime.now().year;
          }).toList();

    int total = filtrados.length;
    int puntual = 0;
    int atraso = 0;
    int salidaAnticipada = 0;

    for (var data in filtrados) {
      final estado = data['estado']?.toString() ?? '';

      if (estado == "A tiempo" || estado == "Puntual") {
        puntual++;
      } else if (estado == "Atraso") {
        atraso++;
      } else if (estado == "Salida Anticipada") {
        salidaAnticipada++;
      }
    }

    return {
      "Total": total,
      "Puntual": puntual,
      "Atraso": atraso,
      "Salida Anticipada": salidaAnticipada,
    };
  }
  // ==========================================
  // LÓGICA DE ALMUERZO (SOLO TIEMPO COMPLETO)
  // ==========================================

  // Registrar salida al almuerzo
  Future<void> registrarInicioAlmuerzo(String correo) async {
    QuerySnapshot userCheck = await _db.collection('usuarios').where('correo', isEqualTo: correo).get();
    
    if (userCheck.docs.isNotEmpty) {
      // CORRECCIÓN AQUÍ: Cambié 'horarios' por 'horarios_asignados' que es como está en tu Firebase
      List<dynamic> horarios = userCheck.docs.first['horarios_asignados'] ?? [];
      bool esTC = horarios.any((h) => h.toString().startsWith("TC"));
      
      if (!esTC) {
        throw Exception("Los docentes de Tiempo Parcial no registran almuerzo.");
      }
    }

    String fechaHoy = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String horaActual = DateFormat('HH:mm:ss').format(DateTime.now());

    // Al usar .add(), Firebase crea la colección 'registros_almuerzo' automáticamente si no existe
    await _db.collection('registros_almuerzo').add({
      'correo_usuario': correo,
      'fecha': fechaHoy,
      'hora_salida': horaActual,
      'hora_regreso': "--:--",
      'estado': "en_almuerzo",
      'timestamp': FieldValue.serverTimestamp(), // Añadido para mejor ordenamiento
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
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      await query.docs.first.reference.update({
        'hora_regreso': horaActual,
        'estado': "finalizado",
      });
    } else {
      throw Exception("No se encontró un inicio de almuerzo activo.");
    }
  }

  // Obtener estado actual del almuerzo
  Future<String> obtenerEstadoAlmuerzoHoy(String correo) async {
    String fechaHoy = DateFormat('yyyy-MM-dd').format(DateTime.now());
    var query = await _db.collection('registros_almuerzo')
        .where('correo_usuario', isEqualTo: correo)
        .where('fecha', isEqualTo: fechaHoy)
        .get();

    if (query.docs.isEmpty) return "pendiente";
    
    for (var doc in query.docs) {
      if (doc['estado'] == "en_almuerzo") return "en_almuerzo";
    }
    
    return "finalizado";
  }
}