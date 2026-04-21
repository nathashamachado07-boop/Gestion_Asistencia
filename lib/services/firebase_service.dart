import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/solicitud_model.dart';

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
    final doc = userQuery.docs.first;
    var data = doc.data() as Map<String, dynamic>;
    print("Password en DB: ${data['password']}");
    print("Password ingresada: $password");
    
    if (data['password'] == password) {
      return {
        ...data,
        'docId': doc.id,
      };
    }
  }
  return null;
}

  Future<Map<String, dynamic>?> validarLoginPorSede({
    required String correo,
    required String password,
    required String sedeId,
  }) async {
    final userQuery = await _db
        .collection('usuarios')
        .where('correo', isEqualTo: correo.trim())
        .where('sedeId', isEqualTo: sedeId)
        .get();

    if (userQuery.docs.isNotEmpty) {
      final doc = userQuery.docs.first;
      final data = doc.data() as Map<String, dynamic>;

      if (data['password'] == password) {
        return {
          ...data,
          'docId': doc.id,
        };
      }
    }

    return null;
  }

  Future<Map<String, dynamic>> _activarSedeEspecial({
    required Map<String, dynamic> userData,
    required String sedeId,
    required String sedeNombre,
    required String logoAsset,
    required Map<String, String> colores,
  }) async {
    final userDocId = userData['docId']?.toString();
    if (userDocId == null || userDocId.isEmpty) {
      throw Exception('No se encontro el documento del usuario RRHH.');
    }

    await _db.collection('sedes').doc(sedeId).set({
      'nombre': sedeNombre,
      'slug': sedeId,
      'estado': 'activa',
      'colores': colores,
      'branding': {
        'nombreMarca': 'Princesa de Gales',
        'subtitulo': 'ESTETICA INTEGRAL',
        'logoAsset': logoAsset,
      },
      'actualizadoEn': FieldValue.serverTimestamp(),
      'creadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _db.collection('usuarios').doc(userDocId).set({
      'sede': sedeNombre,
      'sedeId': sedeId,
      'dashboardWeb': sedeId,
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return {
      ...userData,
      'sede': sedeNombre,
      'sedeId': sedeId,
      'dashboardWeb': sedeId,
    };
  }

  Future<void> _crearDatosDemoSede({
    required String sedeId,
    required String sedeNombre,
    required String correoDocente,
    required String correoAdministrativo,
    required String nombreDocente,
    required String nombreAdministrativo,
  }) async {
    final docenteRef = _db.collection('usuarios').doc('demo_docente_$sedeId');
    final administrativoRef = _db
        .collection('usuarios')
        .doc('demo_administrativo_$sedeId');

    await docenteRef.set({
      'nombre': nombreDocente,
      'correo': correoDocente,
      'password': 'demo1234',
      'rol': 'Docente',
      'tipo_horario': 'completo',
      'horarios_asignados': ['TC_08_16'],
      'sede': sedeNombre,
      'sedeId': sedeId,
      'dashboardWeb': sedeId,
      'demo': true,
      'creadoEn': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await administrativoRef.set({
      'nombre': nombreAdministrativo,
      'correo': correoAdministrativo,
      'password': 'demo1234',
      'rol': 'Administrativo',
      'tipo_horario': 'administrativo',
      'sede': sedeNombre,
      'sedeId': sedeId,
      'dashboardWeb': sedeId,
      'demo': true,
      'creadoEn': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _db.collection('validaciones_sede').doc('demo_$sedeId').set({
      'sede': sedeNombre,
      'sedeId': sedeId,
      'docenteDemoId': docenteRef.id,
      'administrativoDemoId': administrativoRef.id,
      'descripcion':
          'Documento de validacion para comprobar filtros de docentes y administrativos por sede.',
      'actualizadoEn': FieldValue.serverTimestamp(),
      'creadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _crearUsuariosDemoApp({
    required String sedeId,
    required String sedeNombre,
    required List<Map<String, Object>> usuariosDemo,
  }) async {
    for (final usuario in usuariosDemo) {
      await _db.collection('usuarios').doc(usuario['docId'].toString()).set({
        'nombre': usuario['nombre'],
        'correo': usuario['correo'],
        'password': usuario['password'],
        'rol': usuario['rol'],
        'tipo_horario': usuario['tipo_horario'],
        'horarios_asignados': usuario['horarios_asignados'],
        'telefono': usuario['telefono'],
        'sede': sedeNombre,
        'sedeId': sedeId,
        'dashboardWeb': sedeId,
        'especialidad': usuario['especialidad'] ??
            (usuario['rol'] == 'Docente'
                ? 'Estetica Integral'
                : 'Administracion'),
        'demo': true,
        'actualizadoEn': FieldValue.serverTimestamp(),
        'creadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await _db.collection('validaciones_sede').doc('app_demo_$sedeId').set({
      'sede': sedeNombre,
      'sedeId': sedeId,
      'usuariosDemo': usuariosDemo.map((e) => e['docId']).toList(),
      'descripcion': 'Usuarios demo para la aplicacion movil de $sedeNombre.',
      'actualizadoEn': FieldValue.serverTimestamp(),
      'creadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>> activarSedePrincesaGalesNorte({
    required Map<String, dynamic> userData,
  }) async {
    return _activarSedeEspecial(
      userData: userData,
      sedeId: 'princesa_gales_norte',
      sedeNombre: 'Princesa de Gales Norte',
      logoAsset: 'assets/images/logo_galesnorte.png',
      colores: const {
        'primary': '#6D2745',
        'secondary': '#8A3557',
        'accent': '#F4E9EC',
        'text': '#FFF7F8',
      },
    );
  }

  Future<Map<String, dynamic>> activarSedePrincesaGalesCentro({
    required Map<String, dynamic> userData,
  }) async {
    return _activarSedeEspecial(
      userData: userData,
      sedeId: 'princesa_gales_centro',
      sedeNombre: 'Princesa de Gales Centro',
      logoAsset: 'assets/images/logo_galescentro.png',
      colores: const {
        'primary': '#9C4F73',
        'secondary': '#B6688A',
        'accent': '#F7EAF0',
        'text': '#FFF8FB',
      },
    );
  }

  Future<Map<String, dynamic>> activarSedeInstitutoCreSer({
    required Map<String, dynamic> userData,
  }) async {
    return _activarSedeEspecial(
      userData: userData,
      sedeId: 'instituto_cre_ser',
      sedeNombre: 'Instituto Cre Ser',
      logoAsset: 'assets/images/logo_cre_ser.jpeg',
      colores: const {
        'primary': '#2167AE',
        'secondary': '#4B93D9',
        'accent': '#EAF4FF',
        'text': '#F8FBFF',
      },
    );
  }

  Future<void> crearDatosDemoSedeNorte() async {
    await _crearDatosDemoSede(
      sedeId: 'princesa_gales_norte',
      sedeNombre: 'Princesa de Gales Norte',
      correoDocente: 'demo.docente.norte@intesud.test',
      correoAdministrativo: 'demo.administrativo.norte@intesud.test',
      nombreDocente: 'Docente Demo Norte',
      nombreAdministrativo: 'Administrativo Demo Norte',
    );
  }

  Future<void> crearDatosDemoSedeCentro() async {
    await _crearDatosDemoSede(
      sedeId: 'princesa_gales_centro',
      sedeNombre: 'Princesa de Gales Centro',
      correoDocente: 'demo.docente.centro@intesud.test',
      correoAdministrativo: 'demo.administrativo.centro@intesud.test',
      nombreDocente: 'Docente Demo Centro',
      nombreAdministrativo: 'Administrativo Demo Centro',
    );
  }

  Future<void> crearDatosDemoSedeCreSer() async {
    await _crearDatosDemoSede(
      sedeId: 'instituto_cre_ser',
      sedeNombre: 'Instituto Cre Ser',
      correoDocente: 'demo.docente.creser@intesud.test',
      correoAdministrativo: 'demo.administrativo.creser@intesud.test',
      nombreDocente: 'Docente Demo Cre Ser',
      nombreAdministrativo: 'Administrativo Demo Cre Ser',
    );
  }

  Future<void> crearUsuariosDemoAppNorte() async {
    await _crearUsuariosDemoApp(
      sedeId: 'princesa_gales_norte',
      sedeNombre: 'Princesa de Gales Norte',
      usuariosDemo: const [
      {
        'docId': 'norte_docente_tp_01',
        'nombre': 'Camila Andrade Norte',
        'correo': 'camila.norte@princesadegales.app',
        'password': 'norte1234',
        'rol': 'Docente',
        'tipo_horario': 'medio_tiempo',
        'horarios_asignados': ['TP_08_10'],
        'telefono': '0991001001',
      },
      {
        'docId': 'norte_docente_tp_02',
        'nombre': 'Valeria Mena Norte',
        'correo': 'valeria.norte@princesadegales.app',
        'password': 'norte1234',
        'rol': 'Docente',
        'tipo_horario': 'medio_tiempo',
        'horarios_asignados': ['TP_10_12'],
        'telefono': '0991001002',
      },
      {
        'docId': 'norte_admin_tc_01',
        'nombre': 'Daniela Paredes Norte',
        'correo': 'daniela.admin@princesadegales.app',
        'password': 'norte1234',
        'rol': 'Administrativo',
        'tipo_horario': 'completo',
        'horarios_asignados': ['TC_08_16'],
        'telefono': '0991001003',
      },
      {
        'docId': 'norte_admin_tc_02',
        'nombre': 'Paola Jaramillo Norte',
        'correo': 'paola.admin@princesadegales.app',
        'password': 'norte1234',
        'rol': 'Administrativo',
        'tipo_horario': 'completo',
        'horarios_asignados': ['TC_08_16'],
        'telefono': '0991001004',
      },
      ],
    );
  }

  Future<void> crearUsuariosDemoAppCentro() async {
    await _crearUsuariosDemoApp(
      sedeId: 'princesa_gales_centro',
      sedeNombre: 'Princesa de Gales Centro',
      usuariosDemo: const [
        {
          'docId': 'centro_docente_tp_01',
          'nombre': 'Andrea Cabrera Centro',
          'correo': 'andrea.centro@princesadegales.app',
          'password': 'centro1234',
          'rol': 'Docente',
          'tipo_horario': 'medio_tiempo',
          'horarios_asignados': ['TP_08_10'],
          'telefono': '0992001001',
        },
        {
          'docId': 'centro_docente_tp_02',
          'nombre': 'Melissa Vinueza Centro',
          'correo': 'melissa.centro@princesadegales.app',
          'password': 'centro1234',
          'rol': 'Docente',
          'tipo_horario': 'medio_tiempo',
          'horarios_asignados': ['TP_10_12'],
          'telefono': '0992001002',
        },
        {
          'docId': 'centro_admin_tc_01',
          'nombre': 'Karla Romero Centro',
          'correo': 'karla.admin.centro@princesadegales.app',
          'password': 'centro1234',
          'rol': 'Administrativo',
          'tipo_horario': 'completo',
          'horarios_asignados': ['TC_08_16'],
          'telefono': '0992001003',
        },
        {
          'docId': 'centro_admin_tc_02',
          'nombre': 'Monica Salazar Centro',
          'correo': 'monica.admin.centro@princesadegales.app',
          'password': 'centro1234',
          'rol': 'Administrativo',
          'tipo_horario': 'completo',
          'horarios_asignados': ['TC_08_16'],
          'telefono': '0992001004',
        },
      ],
    );
  }

  Future<void> crearUsuariosDemoAppCreSer() async {
    await _crearUsuariosDemoApp(
      sedeId: 'instituto_cre_ser',
      sedeNombre: 'Instituto Cre Ser',
      usuariosDemo: const [
        {
          'docId': 'creser_docente_tp_01',
          'nombre': 'Lucia Herrera Cre Ser',
          'correo': 'lucia.creser@institutocreser.app',
          'password': 'creser1234',
          'rol': 'Docente',
          'tipo_horario': 'medio_tiempo',
          'horarios_asignados': ['TP_08_10'],
          'telefono': '0993001001',
        },
        {
          'docId': 'creser_docente_tp_02',
          'nombre': 'Patricia Solis Cre Ser',
          'correo': 'patricia.creser@institutocreser.app',
          'password': 'creser1234',
          'rol': 'Docente',
          'tipo_horario': 'medio_tiempo',
          'horarios_asignados': ['TP_10_12'],
          'telefono': '0993001002',
        },
        {
          'docId': 'creser_admin_tc_01',
          'nombre': 'Veronica Montalvo Cre Ser',
          'correo': 'veronica.admin@institutocreser.app',
          'password': 'creser1234',
          'rol': 'Administrativo',
          'tipo_horario': 'completo',
          'horarios_asignados': ['TC_08_16'],
          'telefono': '0993001003',
        },
        {
          'docId': 'creser_admin_tc_02',
          'nombre': 'Diana Merino Cre Ser',
          'correo': 'diana.admin@institutocreser.app',
          'password': 'creser1234',
          'rol': 'Administrativo',
          'tipo_horario': 'completo',
          'horarios_asignados': ['TC_08_16'],
          'telefono': '0993001004',
        },
      ],
    );
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

  // ==========================================
  // LÓGICA DE SOLICITUDES (VACACIONES Y PERMISOS)
  // ==========================================

  // 1. Enviar una nueva solicitud (Desde el Celular)
  // ==========================================
  // LÓGICA DE SOLICITUDES (VACACIONES Y PERMISOS)
  // ==========================================

  // ESTA ES LA ÚNICA VERSIÓN QUE DEBE QUEDAR
  Future<void> enviarSolicitud(Solicitud solicitud) async {
  try {
    await _db.collection('solicitudes').add({
      ...solicitud.toMap(),
      'fecha_solicitud': FieldValue.serverTimestamp(), // Excelente, esto es lo mejor para el orden
    });
  } catch (e) {
    throw Exception("Error al enviar la solicitud: $e");
  }
}

  // 2. Escuchar solicitudes pendientes en tiempo real (Para la Web RRHH)
  Stream<QuerySnapshot> obtenerSolicitudesPendientes() {
    return _db
        .collection('solicitudes')
        .where('estado', isEqualTo: 'pendiente')
        .orderBy('fecha_solicitud', descending: false)
        .snapshots();
  }

  // 3. Actualizar estado (Aceptar o Rechazar desde la Web)
  Future<void> actualizarEstadoSolicitud(String idDoc, String nuevoEstado) async {
    try {
      await _db.collection('solicitudes').doc(idDoc).update({
        'estado': nuevoEstado,
        'fecha_resolucion': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception("Error al actualizar la solicitud: $e");
    }
  }
Future<List<Solicitud>> obtenerMisSolicitdes(String nombre) async {
  try {
    QuerySnapshot snapshot = await _db.collection('solicitudes')
        .where('colaborador', isEqualTo: nombre)
        .get();

    return snapshot.docs.map((doc) => 
      Solicitud.fromMap(doc.id, doc.data() as Map<String, dynamic>)).toList();
  } catch (e) {
    print("Error al obtener solicitudes: $e");
    return [];
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
