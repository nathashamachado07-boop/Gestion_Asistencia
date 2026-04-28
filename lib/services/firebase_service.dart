import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../config/app_config.dart';
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
      .limit(1)
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
        .limit(1)
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

  int _horaEnMinutos(String hora) {
    final partes = hora.split(':');
    final horas = int.tryParse(partes[0]) ?? 0;
    final minutos = partes.length > 1 ? int.tryParse(partes[1]) ?? 0 : 0;
    return (horas * 60) + minutos;
  }

  Future<Map<String, dynamic>?> _obtenerUsuarioPorCorreo(String correo) async {
    final correoNormalizado = correo.trim().toLowerCase();
    if (correoNormalizado.isEmpty) {
      return null;
    }

    final query = await _db
        .collection('usuarios')
        .where('correo', isEqualTo: correoNormalizado)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      return null;
    }

    return query.docs.first.data() as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> obtenerUsuarioPorCorreo(String correo) async {
    return _obtenerUsuarioPorCorreo(correo);
  }

  Future<void> actualizarPasswordPorCorreo({
    required String correo,
    required String nuevaPassword,
  }) async {
    final correoNormalizado = correo.trim().toLowerCase();
    final passwordLimpia = nuevaPassword.trim();

    if (correoNormalizado.isEmpty) {
      throw Exception('Ingrese un correo valido.');
    }

    if (passwordLimpia.isEmpty) {
      throw Exception('Ingrese una nueva contrasena.');
    }

    final query = await _db
        .collection('usuarios')
        .where('correo', isEqualTo: correoNormalizado)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw Exception('No existe un usuario registrado con ese correo.');
    }

    await query.docs.first.reference.set({
      'password': passwordLimpia,
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  bool _esHorarioTiempoCompleto(String idHorario, Map<String, dynamic> data) {
    if (idHorario.toUpperCase().startsWith('TC')) {
      return true;
    }

    final valor = data['es_tiempo_completo'];
    if (valor is bool) {
      return valor;
    }

    return false;
  }

  String _formatearRangoHorario(Map<String, dynamic> data) {
    final entrada = data['entrada']?.toString() ?? '--:--';
    final salida = data['salida']?.toString() ?? '--:--';
    return '$entrada a $salida';
  }

  Map<String, String>? _resolverHorarioAlmuerzoAsignado(
    Map<String, dynamic>? usuarioData,
  ) {
    if (usuarioData == null) {
      return null;
    }

    final inicio =
        (usuarioData['almuerzo_inicio_asignado'] ?? '').toString().trim();
    final fin = (usuarioData['almuerzo_fin_asignado'] ?? '').toString().trim();
    final label =
        (usuarioData['almuerzo_horario_label'] ?? '').toString().trim();

    if (inicio.isEmpty || fin.isEmpty) {
      return null;
    }

    return {
      'inicio': inicio,
      'fin': fin,
      'label': label.isEmpty ? '$inicio a $fin' : label,
      'origen': 'asignado',
    };
  }

  Future<Map<String, String>?> _resolverHorarioAlmuerzoPorHorario(
    List<dynamic> listaHorarios,
  ) async {
    final idHorarioTC = listaHorarios.firstWhere(
      (h) => h.toString().startsWith('TC'),
      orElse: () => '',
    );

    if (idHorarioTC.toString().trim().isEmpty) {
      return null;
    }

    final doc = await _db.collection('horarios').doc(idHorarioTC).get();
    if (!doc.exists) {
      return null;
    }

    final inicio = (doc['almuerzo_inicio'] ?? '').toString().trim();
    final fin = (doc['almuerzo_fin'] ?? '').toString().trim();
    if (inicio.isEmpty || fin.isEmpty) {
      return null;
    }

    return {
      'inicio': inicio,
      'fin': fin,
      'label': '$inicio a $fin',
      'origen': 'horario_general',
    };
  }

  Future<Map<String, String>?> _resolverHorarioAlmuerzoUsuario({
    required Map<String, dynamic>? usuarioData,
    required List<dynamic> listaHorarios,
  }) async {
    final asignado = _resolverHorarioAlmuerzoAsignado(usuarioData);
    if (asignado != null) {
      return asignado;
    }

    return _resolverHorarioAlmuerzoPorHorario(listaHorarios);
  }

  Future<Map<String, String>?> obtenerHorarioAlmuerzoUsuario({
    required String correo,
    required List<dynamic> listaHorarios,
  }) async {
    final usuarioData = await _obtenerUsuarioPorCorreo(correo);
    return _resolverHorarioAlmuerzoUsuario(
      usuarioData: usuarioData,
      listaHorarios: listaHorarios,
    );
  }

  Future<Map<String, Map<String, dynamic>>> _obtenerHorariosPorIds(
    List<dynamic> listaHorarios,
  ) async {
    final ids = listaHorarios
        .map((horario) => horario.toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final resultados = await Future.wait(
      ids.map((id) async {
        final doc = await _db.collection('horarios').doc(id).get();
        if (!doc.exists) {
          return MapEntry<String, Map<String, dynamic>?>(id, null);
        }

        return MapEntry<String, Map<String, dynamic>?>(
          id,
          doc.data() as Map<String, dynamic>,
        );
      }),
    );

    return {
      for (final entry in resultados)
        if (entry.value != null) entry.key: entry.value!,
    };
  }

  String _mensajeFueraDeHorario({
    required DateTime ahora,
    required List<Map<String, dynamic>> horariosEvaluados,
  }) {
    if (horariosEvaluados.isEmpty) {
      return "No tienes clases programadas en este horario.";
    }

    horariosEvaluados
        .sort((a, b) => (a['entradaMin'] as int).compareTo(b['entradaMin'] as int));

    final ahoraMin = (ahora.hour * 60) + ahora.minute;
    final primerHorario = horariosEvaluados.first;
    final ultimoHorario = horariosEvaluados.last;

    if (ahoraMin < (primerHorario['entradaMin'] as int)) {
      return "Tu horario habilitado inicia de ${primerHorario['rango']}. Aun no puedes registrar asistencia.";
    }

    if (ahoraMin > (ultimoHorario['salidaMin'] as int)) {
      return "Tu horario habilitado de ${ultimoHorario['rango']} ya termino. Ya no puedes registrar asistencia.";
    }

    Map<String, dynamic>? siguienteHorario;
    for (final horario in horariosEvaluados) {
      if (ahoraMin < (horario['entradaMin'] as int)) {
        siguienteHorario = horario;
        break;
      }
    }

    if (siguienteHorario != null) {
      return "En este momento no tienes un bloque activo. Tu siguiente horario es de ${siguienteHorario['rango']}.";
    }

    return "No tienes clases programadas en este horario.";
  }
  // Marcación: Busca en la lista de la captura con VALIDACIÓN DE ESTADO
  ({int inicio, int fin})? _parseRangoPermisoHoras(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final matches = RegExp(r'(\d{1,2}):(\d{2})').allMatches(value).toList();
    if (matches.length < 2) {
      return null;
    }

    final inicioHoras = int.tryParse(matches[0].group(1)!);
    final inicioMinutos = int.tryParse(matches[0].group(2)!);
    final finHoras = int.tryParse(matches[1].group(1)!);
    final finMinutos = int.tryParse(matches[1].group(2)!);

    if (inicioHoras == null ||
        inicioMinutos == null ||
        finHoras == null ||
        finMinutos == null) {
      return null;
    }

    return (
      inicio: (inicioHoras * 60) + inicioMinutos,
      fin: (finHoras * 60) + finMinutos,
    );
  }

  bool _mismaFechaCalendario(dynamic fechaSolicitud, DateTime fechaReferencia) {
    DateTime? fecha;

    if (fechaSolicitud is Timestamp) {
      fecha = fechaSolicitud.toDate();
    } else if (fechaSolicitud is DateTime) {
      fecha = fechaSolicitud;
    } else if (fechaSolicitud != null) {
      fecha = DateTime.tryParse(fechaSolicitud.toString());
    }

    if (fecha == null) {
      return false;
    }

    return fecha.year == fechaReferencia.year &&
        fecha.month == fechaReferencia.month &&
        fecha.day == fechaReferencia.day;
  }

  Future<Map<String, String>?> _obtenerPermisoAprobadoVigente({
    required String nombreUsuario,
    required DateTime ahora,
    required int ahoraMin,
    String? sedeId,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection('solicitudes')
        .where('colaborador', isEqualTo: nombreUsuario)
        .where('tipo', isEqualTo: 'Permiso')
        .where('estado', isEqualTo: 'aprobado');

    if (sedeId != null && sedeId.trim().isNotEmpty) {
      query = query.where('sedeId', isEqualTo: sedeId.trim());
    }

    final snapshot = await query.get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final fechaPermiso =
          data['fechaPermiso'] ?? data['fechaInicio'] ?? data['fechaSolicitud'];
      if (!_mismaFechaCalendario(fechaPermiso, ahora)) {
        continue;
      }

      final horarioPermiso =
          (data['horarioPermiso'] ?? data['horasPermiso'] ?? '').toString().trim();
      final rango = _parseRangoPermisoHoras(horarioPermiso);
      if (rango == null) {
        continue;
      }

      if (ahoraMin >= rango.inicio && ahoraMin <= rango.fin) {
        return {
          'horario': horarioPermiso,
          'motivo': (data['motivo'] ?? '').toString().trim(),
          'documentoId': doc.id,
        };
      }
    }

    return null;
  }

  Future<Map<String, String>> registrarMarcacion({
    required String nombreUsuario,
    required List<dynamic> listaHorarios, 
    required bool esEntrada,
    String? sedeId,
    String? sedeNombre,
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
    Map<String, dynamic>? horarioSeleccionado;
    final ahoraMin = (ahora.hour * 60) + ahora.minute;
    final List<Map<String, dynamic>> horariosEvaluados = [];
    final permisoActivoFuture = _obtenerPermisoAprobadoVigente(
      nombreUsuario: nombreUsuario,
      ahora: ahora,
      ahoraMin: ahoraMin,
      sedeId: sedeId,
    );
    final horariosDisponibles = await _obtenerHorariosPorIds(listaHorarios);

    for (final horario in listaHorarios) {
      final id = horario.toString();
      final data = horariosDisponibles[id];
      if (data == null) continue;
      final entrada = data['entrada']?.toString() ?? '00:00';
      final salida = data['salida']?.toString() ?? '00:00';
      final entradaMin = _horaEnMinutos(entrada);
      final salidaMin = _horaEnMinutos(salida);
      final esTiempoCompleto = _esHorarioTiempoCompleto(id, data);

      horariosEvaluados.add({
        'id': id,
        'entradaMin': entradaMin,
        'salidaMin': salidaMin,
        'rango': _formatearRangoHorario(data),
        'esTiempoCompleto': esTiempoCompleto,
      });

      final bool horarioActivo;
      if (esTiempoCompleto) {
        final horaInicio = int.parse(entrada.split(":")[0]);
        final horaFin = int.parse(salida.split(":")[0]);
        horarioActivo =
            ahora.hour >= (horaInicio - 1) && ahora.hour <= (horaFin + 1);
      } else {
        horarioActivo = ahoraMin >= entradaMin && ahoraMin <= salidaMin;
      }

      if (horarioActivo) {
        horarioSeleccionado = data;
        break;
      }
    }

    if (horarioSeleccionado == null) {
      throw Exception(
        _mensajeFueraDeHorario(
          ahora: ahora,
          horariosEvaluados: horariosEvaluados,
        ),
      );
    }

    String horaOficialStr =
        esEntrada ? horarioSeleccionado['entrada'] : horarioSeleccionado['salida'];
    int horaLimite = _horaEnMinutos(horaOficialStr);
    String horaActualStr = DateFormat('HH:mm').format(ahora);

    String estado = "A tiempo";
    if (esEntrada && ahoraMin > horaLimite) {
      estado = "Atraso";
    } else if (!esEntrada && ahoraMin < horaLimite) {
      estado = "Salida Anticipada";
    } else if (!esEntrada) {
      estado = "Completada";
    }

    final permisoActivo = await permisoActivoFuture;

    // 3. GUARDAR REGISTRO
    await _db.collection('asistencias_realizadas').add({
      'docente': nombreUsuario,
      'tipo': esEntrada ? "ENTRADA" : "SALIDA",
      'horario_ref': horarioSeleccionado['nombre'],
      'hora_marcada': horaActualStr,
      'estado': estado,
      'fecha': ahora, 
      'observacion': "Registro realizado correctamente.",
      'sedeId': sedeId,
      'sede': sedeNombre,
      'permiso_aprobado_activo': permisoActivo != null,
      'permiso_horario': permisoActivo?['horario'],
      'permiso_motivo': permisoActivo?['motivo'],
      'permiso_documento_id': permisoActivo?['documentoId'],
    });

    return {
      'estado': estado, 
      'bloque': horarioSeleccionado['nombre'], 
      'hora': horaActualStr,
      'permisoActivo': permisoActivo != null ? 'true' : 'false',
      'horarioPermiso': permisoActivo?['horario'] ?? '',
      'motivoPermiso': permisoActivo?['motivo'] ?? '',
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

  Future<List<Map<String, dynamic>>> obtenerHistorialAlmuerzo(String correo) async {
    try {
      QuerySnapshot snapshot = await _db
          .collection('registros_almuerzo')
          .where('correo_usuario', isEqualTo: correo)
          .orderBy('timestamp', descending: true)
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
          .limit(1)
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
    final usuarioData = await _obtenerUsuarioPorCorreo(correo);
    final List<dynamic> horarios = usuarioData?['horarios_asignados'] ?? [];
    final bool esTC = horarios.any((h) => h.toString().startsWith("TC"));
    final horarioAlmuerzo = await _resolverHorarioAlmuerzoUsuario(
      usuarioData: usuarioData,
      listaHorarios: horarios,
    );

    if (!esTC && horarioAlmuerzo == null) {
      // CORRECCIÓN AQUÍ: Cambié 'horarios' por 'horarios_asignados' que es como está en tu Firebase
      throw Exception("Los docentes de Tiempo Parcial no registran almuerzo.");
    }

    String fechaHoy = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String horaActual = DateFormat('HH:mm:ss').format(DateTime.now());

    // Al usar .add(), Firebase crea la colección 'registros_almuerzo' automáticamente si no existe
    await _db.collection('registros_almuerzo').add({
      'correo_usuario': correo,
      'nombre_usuario': usuarioData?['nombre'],
      'fecha': fechaHoy,
      'hora_salida': horaActual,
      'hora_regreso': "--:--",
      'estado': "en_almuerzo",
      'sedeId': usuarioData?['sedeId'],
      'sede': usuarioData?['sede'],
      'tipo_horario': usuarioData?['tipo_horario'],
      'almuerzo_horario': horarioAlmuerzo?['label'],
      'almuerzo_inicio_asignado': horarioAlmuerzo?['inicio'],
      'almuerzo_fin_asignado': horarioAlmuerzo?['fin'],
      'timestamp': FieldValue.serverTimestamp(), // Añadido para mejor ordenamiento
    });
  }

  // Registrar regreso del almuerzo
  Future<void> registrarFinAlmuerzo(String correo) async {
    String fechaHoy = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String horaActual = DateFormat('HH:mm:ss').format(DateTime.now());
    QuerySnapshot userCheck = await _db
        .collection('usuarios')
        .where('correo', isEqualTo: correo)
        .limit(1)
        .get();
    Map<String, dynamic>? usuarioData;

    if (userCheck.docs.isNotEmpty) {
      usuarioData = userCheck.docs.first.data() as Map<String, dynamic>;
    }

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
        'nombre_usuario': usuarioData?['nombre'],
        'sedeId': usuarioData?['sedeId'],
        'sede': usuarioData?['sede'],
        'tipo_horario': usuarioData?['tipo_horario'],
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
      final solicitudesRef = _db.collection('solicitudes');
      final nuevaSolicitudRef = solicitudesRef.doc();
      final usaFlujoMatriz =
          MatrizApprovalFlow.appliesToSedeId(solicitud.sedeId);
      final tipoSolicitud = _resolverTipoSolicitud(solicitud.tipo);
      final sedeSolicitud = _resolverSedeSolicitud(solicitud.sedeId);
      final siguienteNumero =
          await _obtenerSiguienteNumeroFormularioPorTipo(
        tipoSolicitud: tipoSolicitud,
        sedeId: sedeSolicitud,
      );
      final numeroFormularioGenerado =
          _formatearNumeroFormulario(siguienteNumero);

      await nuevaSolicitudRef.set({
        ...solicitud.toMap(),
        'numFormulario': numeroFormularioGenerado,
        'numFormularioSecuencia': siguienteNumero,
        'numFormularioTipo': tipoSolicitud,
        'numFormularioSedeId': sedeSolicitud,
        'fecha_solicitud': FieldValue.serverTimestamp(),
        'flujoAprobacion': usaFlujoMatriz
            ? MatrizApprovalFlow.flowId
            : 'simple',
        'etapaAprobacion': usaFlujoMatriz
            ? MatrizApprovalFlow.stagePrimary
            : 'simple',
        'aprobadorPrimarioEmail': usaFlujoMatriz
            ? MatrizApprovalFlow.primaryReviewerEmail
            : null,
        'aprobadoresFinalesEmails': usaFlujoMatriz
            ? MatrizApprovalFlow.finalReviewerEmails.toList()
            : null,
      });

      await _crearAvisosNuevaSolicitudRRHH(
        idDoc: nuevaSolicitudRef.id,
        solicitud: solicitud,
        numeroFormulario: numeroFormularioGenerado,
        usaFlujoMatriz: usaFlujoMatriz,
      );
    } catch (e) {
      throw Exception("Error al enviar la solicitud: $e");
    }
  }

  Future<Map<String, dynamic>> asegurarNumeroFormularioSolicitud(
    String idDoc,
    Map<String, dynamic> data,
  ) async {
    final solicitudRef = _db.collection('solicitudes').doc(idDoc);

    try {
      final solicitudSnapshot = await solicitudRef.get();
      final solicitudData =
          solicitudSnapshot.data() as Map<String, dynamic>? ?? data;
      final tipoSolicitud = _resolverTipoSolicitud(solicitudData['tipo']);
      final sedeSolicitud = _resolverSedeSolicitud(solicitudData['sedeId']);
      final secuenciaActual = await _obtenerNumeroFormularioActualPorTipo(
        tipoSolicitud: tipoSolicitud,
        sedeId: sedeSolicitud,
        solicitudId: idDoc,
      );
      final numeroFormateado = _formatearNumeroFormulario(secuenciaActual);
      final numeroExistente =
          solicitudData['numFormulario']?.toString().trim() ?? '';
      final secuenciaExistente =
          (solicitudData['numFormularioSecuencia'] as num?)?.toInt();

      if (numeroExistente == numeroFormateado &&
          secuenciaExistente == secuenciaActual) {
        return solicitudData;
      }

      await solicitudRef.set({
        'numFormulario': numeroFormateado,
        'numFormularioSecuencia': secuenciaActual,
        'numFormularioTipo': tipoSolicitud,
        'numFormularioSedeId': sedeSolicitud,
      }, SetOptions(merge: true));

      return {
        ...solicitudData,
        'numFormulario': numeroFormateado,
        'numFormularioSecuencia': secuenciaActual,
        'numFormularioTipo': tipoSolicitud,
        'numFormularioSedeId': sedeSolicitud,
      };
    } catch (e) {
      throw Exception("Error al generar el numero del formulario: $e");
    }
  }

  String _resolverTipoSolicitud(dynamic tipo) {
    final texto = tipo?.toString().trim();
    if (texto == null || texto.isEmpty) {
      return 'Solicitud';
    }
    return texto;
  }

  String _resolverSedeSolicitud(dynamic sedeId) {
    final normalizada = SedeAccess.normalize(sedeId);
    if (normalizada.isEmpty) {
      return SedeAccess.matrizId;
    }
    return normalizada;
  }

  String _formatearNumeroFormulario(int numero) {
    return numero.toString().padLeft(5, '0');
  }

  DateTime _resolverFechaOrdenSolicitud(Map<String, dynamic> data) {
    final fecha =
        data['fecha_solicitud'] ?? data['fechaSolicitud'] ?? data['fechaInicio'];

    if (fecha is Timestamp) {
      return fecha.toDate();
    }
    if (fecha is DateTime) {
      return fecha;
    }
    if (fecha != null) {
      final parseada = DateTime.tryParse(fecha.toString());
      if (parseada != null) {
        return parseada;
      }
    }

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<int> _obtenerSiguienteNumeroFormularioPorTipo({
    required String tipoSolicitud,
    required String sedeId,
  }) async {
    final snapshot = await _db
        .collection('solicitudes')
        .where('tipo', isEqualTo: tipoSolicitud)
        .where('sedeId', isEqualTo: sedeId)
        .get();

    return snapshot.docs.length + 1;
  }

  Future<int> _obtenerNumeroFormularioActualPorTipo({
    required String tipoSolicitud,
    required String sedeId,
    required String solicitudId,
  }) async {
    final snapshot = await _db
        .collection('solicitudes')
        .where('tipo', isEqualTo: tipoSolicitud)
        .where('sedeId', isEqualTo: sedeId)
        .get();

    final docs = snapshot.docs.toList()
      ..sort((a, b) {
        final fechaA = _resolverFechaOrdenSolicitud(a.data());
        final fechaB = _resolverFechaOrdenSolicitud(b.data());
        final comparacionFecha = fechaA.compareTo(fechaB);
        if (comparacionFecha != 0) {
          return comparacionFecha;
        }
        return a.id.compareTo(b.id);
      });

    final index = docs.indexWhere((doc) => doc.id == solicitudId);
    if (index >= 0) {
      return index + 1;
    }

    return docs.length + 1;
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
  Future<void> actualizarEstadoSolicitud(
    String idDoc,
    String nuevoEstado, {
    String? reviewerEmail,
    String? reviewerName,
  }) async {
    try {
      final solicitudRef = _db.collection('solicitudes').doc(idDoc);
      final normalizedEmail = MatrizApprovalFlow.normalizeEmail(reviewerEmail);
      Map<String, dynamic>? solicitudFinal;
      var debeNotificarAprobacion = false;

      await _db.runTransaction((transaction) async {
        final snapshot = await transaction.get(solicitudRef);
        final data = snapshot.data();
        if (data == null) {
          throw Exception('La solicitud ya no existe.');
        }

        final usaFlujoMatriz =
            MatrizApprovalFlow.appliesToRequest(data) &&
            (SedeAccess.normalize(data['flujoAprobacion']) ==
                    MatrizApprovalFlow.flowId ||
                SedeAccess.normalize(data['estado']) == 'pendiente');

        if (!usaFlujoMatriz) {
          transaction.update(solicitudRef, {
            'estado': nuevoEstado,
            'fecha_resolucion': FieldValue.serverTimestamp(),
            'resueltoPorEmail': normalizedEmail.isEmpty ? null : normalizedEmail,
            'resueltoPorNombre': reviewerName,
          });
          solicitudFinal = {
            ...data,
            'estado': nuevoEstado,
          };
          debeNotificarAprobacion = nuevoEstado == 'aprobado';
          return;
        }

        final estadoActual = SedeAccess.normalize(data['estado']);
        if (estadoActual != 'pendiente') {
          throw Exception('La solicitud ya fue procesada anteriormente.');
        }

        final etapaActual = SedeAccess.normalize(
          data['etapaAprobacion'],
        ).isEmpty
            ? MatrizApprovalFlow.stagePrimary
            : SedeAccess.normalize(data['etapaAprobacion']);

        if (etapaActual == MatrizApprovalFlow.stagePrimary) {
          if (!MatrizApprovalFlow.isPrimaryReviewer(normalizedEmail)) {
            throw Exception(
              'Solo ${MatrizApprovalFlow.primaryReviewerEmail} puede hacer la primera revision de Matriz.',
            );
          }

          if (nuevoEstado == 'aprobado') {
            transaction.update(solicitudRef, {
              'estado': 'pendiente',
              'flujoAprobacion': MatrizApprovalFlow.flowId,
              'etapaAprobacion': MatrizApprovalFlow.stageFinal,
              'aprobadoPrimarioPorEmail': normalizedEmail,
              'aprobadoPrimarioPorNombre': reviewerName,
              'fecha_revision_primaria': FieldValue.serverTimestamp(),
              'ultimaActualizacionFlujo': FieldValue.serverTimestamp(),
            });
            solicitudFinal = {
              ...data,
              'estado': 'pendiente',
              'flujoAprobacion': MatrizApprovalFlow.flowId,
              'etapaAprobacion': MatrizApprovalFlow.stageFinal,
            };
            return;
          }

          transaction.update(solicitudRef, {
            'estado': nuevoEstado,
            'flujoAprobacion': MatrizApprovalFlow.flowId,
            'etapaAprobacion': MatrizApprovalFlow.stageCompleted,
            'rechazadoPrimarioPorEmail': normalizedEmail,
            'rechazadoPrimarioPorNombre': reviewerName,
            'fecha_resolucion': FieldValue.serverTimestamp(),
          });
          solicitudFinal = {
            ...data,
            'estado': nuevoEstado,
            'etapaAprobacion': MatrizApprovalFlow.stageCompleted,
          };
          return;
        }

        if (!MatrizApprovalFlow.isFinalReviewer(normalizedEmail)) {
          throw Exception(
            'Solo Oscar Toscano o Yadira Martinez pueden hacer la autorizacion final de Matriz.',
          );
        }

        transaction.update(solicitudRef, {
          'estado': nuevoEstado,
          'flujoAprobacion': MatrizApprovalFlow.flowId,
          'etapaAprobacion': MatrizApprovalFlow.stageCompleted,
          'aprobadoFinalPorEmail':
              nuevoEstado == 'aprobado' ? normalizedEmail : null,
          'aprobadoFinalPorNombre':
              nuevoEstado == 'aprobado' ? reviewerName : null,
          'rechazadoFinalPorEmail':
              nuevoEstado == 'aprobado' ? null : normalizedEmail,
          'rechazadoFinalPorNombre':
              nuevoEstado == 'aprobado' ? null : reviewerName,
          'fecha_resolucion': FieldValue.serverTimestamp(),
        });
        solicitudFinal = {
          ...data,
          'estado': nuevoEstado,
          'etapaAprobacion': MatrizApprovalFlow.stageCompleted,
        };
        debeNotificarAprobacion = nuevoEstado == 'aprobado';
      });

      if (debeNotificarAprobacion && solicitudFinal != null) {
        await _crearAvisoSolicitudAprobada(
          idDoc: idDoc,
          solicitudData: solicitudFinal!,
          reviewerName: reviewerName,
          reviewerEmail: normalizedEmail,
        );
      }

      final cambioAEtapaFinal =
          solicitudFinal != null &&
          SedeAccess.normalize(solicitudFinal!['estado']) == 'pendiente' &&
          SedeAccess.normalize(solicitudFinal!['etapaAprobacion']) ==
              MatrizApprovalFlow.stageFinal;

      if (cambioAEtapaFinal && solicitudFinal != null) {
        await _crearAvisosSolicitudAutorizacionFinal(
          idDoc: idDoc,
          solicitudData: solicitudFinal!,
        );
      }
    } catch (e) {
      throw Exception("Error al actualizar la solicitud: $e");
    }
  }

  Future<List<Map<String, dynamic>>> _obtenerDestinatariosRrhhSolicitud({
    required String sedeId,
    required String etapa,
  }) async {
    final snapshot = await _db
        .collection('usuarios')
        .where('rol', whereIn: const ['RRHH', 'Admin'])
        .get();

    return snapshot.docs
        .map((doc) => {
              ...doc.data(),
              'docId': doc.id,
            })
        .where((data) {
          final correo = MatrizApprovalFlow.normalizeEmail(data['correo']);
          if (correo.isEmpty) {
            return false;
          }

          if (sedeId == SedeAccess.matrizId) {
            if (etapa == MatrizApprovalFlow.stagePrimary) {
              return MatrizApprovalFlow.isPrimaryReviewer(correo);
            }
            if (etapa == MatrizApprovalFlow.stageFinal) {
              return MatrizApprovalFlow.isFinalReviewer(correo);
            }
          }

          final sedesPermitidas =
              MatrizApprovalFlow.allowedSedeIdsForUser(data);
          return sedesPermitidas.contains(sedeId);
        })
        .toList();
  }

  Future<void> _crearAvisosNuevaSolicitudRRHH({
    required String idDoc,
    required Solicitud solicitud,
    required String numeroFormulario,
    required bool usaFlujoMatriz,
  }) async {
    final sedeId = SedeAccess.normalize(solicitud.sedeId).isEmpty
        ? SedeAccess.matrizId
        : SedeAccess.normalize(solicitud.sedeId);
    final sedeNombre = SedeAccess.displayNameForId(sedeId);
    final tipoSolicitud = solicitud.tipo.trim().isEmpty
        ? 'Solicitud'
        : solicitud.tipo.trim();
    final colaborador = solicitud.colaborador.trim().isEmpty
        ? 'Colaborador'
        : solicitud.colaborador.trim();
    final motivo = solicitud.motivo.trim();
    final etapaDestino = usaFlujoMatriz
        ? MatrizApprovalFlow.stagePrimary
        : 'simple';
    final destinatarios = await _obtenerDestinatariosRrhhSolicitud(
      sedeId: sedeId,
      etapa: etapaDestino,
    );

    if (destinatarios.isEmpty) {
      return;
    }

    final mensajeBase = numeroFormulario.isEmpty
        ? 'Se envio una solicitud de $tipoSolicitud de $colaborador.'
        : 'Se envio una solicitud N° $numeroFormulario de $tipoSolicitud de $colaborador.';
    final mensaje = motivo.isEmpty
        ? '$mensajeBase Sede: $sedeNombre.'
        : '$mensajeBase Sede: $sedeNombre. Motivo: $motivo.';

    final batch = _db.batch();
    final now = DateTime.now();

    for (final destinatario in destinatarios) {
      final correoDestino = MatrizApprovalFlow.normalizeEmail(
        destinatario['correo'],
      );
      if (correoDestino.isEmpty) {
        continue;
      }

      final avisoRef = _db.collection('avisos').doc();
      batch.set(avisoRef, {
        'titulo': 'Se envio una solicitud',
        'mensaje': mensaje,
        'fecha': DateFormat('dd/MM/yyyy HH:mm').format(now),
        'timestamp': FieldValue.serverTimestamp(),
        'sedeId': sedeId,
        'sede': sedeNombre,
        'destinatarioCorreo': correoDestino,
        'destinatarioNombre': destinatario['nombre'],
        'tipo': 'solicitud_nueva',
        'solicitudId': idDoc,
        'solicitudTipo': tipoSolicitud,
        'numFormulario': numeroFormulario,
        'accionRuta': 'gestion',
        'leido': false,
      });
    }

    await batch.commit();
  }

  Future<void> _crearAvisosSolicitudAutorizacionFinal({
    required String idDoc,
    required Map<String, dynamic> solicitudData,
  }) async {
    final sedeId = SedeAccess.resolveSedeId(solicitudData);
    final destinatarios = await _obtenerDestinatariosRrhhSolicitud(
      sedeId: sedeId,
      etapa: MatrizApprovalFlow.stageFinal,
    );

    if (destinatarios.isEmpty) {
      return;
    }

    final colaborador = (solicitudData['colaborador'] ?? 'Colaborador')
        .toString()
        .trim();
    final tipoSolicitud = (solicitudData['tipo'] ?? 'Solicitud')
        .toString()
        .trim();
    final numeroFormulario = (solicitudData['numFormulario'] ?? '')
        .toString()
        .trim();
    final sedeNombre = SedeAccess.displayNameForId(sedeId);
    final motivo = (solicitudData['motivo'] ?? '').toString().trim();
    final mensajeBase = numeroFormulario.isEmpty
        ? 'La solicitud de $tipoSolicitud de $colaborador esta lista para autorizacion final.'
        : 'La solicitud N° $numeroFormulario de $tipoSolicitud de $colaborador esta lista para autorizacion final.';
    final mensaje = motivo.isEmpty
        ? '$mensajeBase Sede: $sedeNombre.'
        : '$mensajeBase Sede: $sedeNombre. Motivo: $motivo.';

    final batch = _db.batch();
    final now = DateTime.now();

    for (final destinatario in destinatarios) {
      final correoDestino = MatrizApprovalFlow.normalizeEmail(
        destinatario['correo'],
      );
      if (correoDestino.isEmpty) {
        continue;
      }

      final avisoRef = _db.collection('avisos').doc();
      batch.set(avisoRef, {
        'titulo': 'Solicitud por autorizar',
        'mensaje': mensaje,
        'fecha': DateFormat('dd/MM/yyyy HH:mm').format(now),
        'timestamp': FieldValue.serverTimestamp(),
        'sedeId': sedeId,
        'sede': sedeNombre,
        'destinatarioCorreo': correoDestino,
        'destinatarioNombre': destinatario['nombre'],
        'tipo': 'solicitud_por_autorizar',
        'solicitudId': idDoc,
        'solicitudTipo': tipoSolicitud,
        'numFormulario': numeroFormulario,
        'accionRuta': 'gestion',
        'leido': false,
      });
    }

    await batch.commit();
  }

  Future<void> _crearAvisoSolicitudAprobada({
    required String idDoc,
    required Map<String, dynamic> solicitudData,
    String? reviewerName,
    String? reviewerEmail,
  }) async {
    final colaborador = (solicitudData['colaborador'] ?? '').toString().trim();
    if (colaborador.isEmpty) {
      return;
    }

    final sedeId = SedeAccess.resolveSedeId(solicitudData);
    final sedeNombre = SedeAccess.displayNameForId(sedeId);
    var correoDestino = (solicitudData['colaboradorCorreo'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    if (correoDestino.isEmpty) {
      Query<Map<String, dynamic>> query = _db
          .collection('usuarios')
          .where('nombre', isEqualTo: colaborador)
          .limit(5);

      try {
        final snapshot = await query.get();
        final match = snapshot.docs.firstWhere(
          (doc) => SedeAccess.matchesSede(doc.data(), sedeId),
          orElse: () => snapshot.docs.isNotEmpty
              ? snapshot.docs.first
              : throw StateError('Sin coincidencias'),
        );
        correoDestino =
            (match.data()['correo'] ?? '').toString().trim().toLowerCase();
      } catch (_) {
        correoDestino = '';
      }
    }

    if (correoDestino.isEmpty) {
      return;
    }

    final tipoSolicitud =
        (solicitudData['tipo'] ?? 'solicitud').toString().trim();
    final numeroFormulario =
        (solicitudData['numFormulario'] ?? '').toString().trim();
    final aprobador = (reviewerName ?? reviewerEmail ?? 'RRHH').toString().trim();
    final titulo = 'Solicitud aprobada';
    final mensaje = numeroFormulario.isEmpty
        ? 'Tu solicitud de $tipoSolicitud fue aprobada por $aprobador.'
        : 'Tu solicitud N° $numeroFormulario de $tipoSolicitud fue aprobada por $aprobador.';

    await _db.collection('avisos').add({
      'titulo': titulo,
      'mensaje': mensaje,
      'fecha': DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
      'timestamp': FieldValue.serverTimestamp(),
      'sedeId': sedeId,
      'sede': sedeNombre,
      'destinatarioCorreo': correoDestino,
      'destinatarioNombre': colaborador,
      'tipo': 'solicitud_aprobada',
      'solicitudId': idDoc,
      'solicitudTipo': tipoSolicitud,
      'creadoPor': aprobador,
      'leido': false,
    });
  }

  Future<void> asignarHorarioAlmuerzoAdministrativo({
    required String usuarioDocId,
    required String correo,
    required String nombre,
    required String sedeId,
    required String sedeNombre,
    required String horaInicio,
    required String horaFin,
    String? asignadoPor,
  }) async {
    final userRef = _db.collection('usuarios').doc(usuarioDocId);
    final userSnapshot = await userRef.get();
    final actual = userSnapshot.data() as Map<String, dynamic>? ?? {};
    final horarioAnterior =
        (actual['almuerzo_horario_label'] ?? '').toString().trim();
    final nuevoHorario = '$horaInicio a $horaFin';

    await userRef.set({
      'almuerzo_inicio_asignado': horaInicio,
      'almuerzo_fin_asignado': horaFin,
      'almuerzo_horario_label': nuevoHorario,
      'almuerzo_actualizado_en': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final correoDestino = correo.trim().toLowerCase();
    if (correoDestino.isEmpty) {
      return;
    }

    final esActualizacion =
        horarioAnterior.isNotEmpty && horarioAnterior != nuevoHorario;
    final titulo = esActualizacion
        ? 'Horario de almuerzo actualizado'
        : 'Horario de almuerzo asignado';
    final mensaje = esActualizacion
        ? 'Su horario de almuerzo fue actualizado a $nuevoHorario.'
        : 'Se le asignó su horario de almuerzo de $nuevoHorario.';

    await _db.collection('avisos').add({
      'titulo': titulo,
      'mensaje': mensaje,
      'fecha': DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
      'timestamp': FieldValue.serverTimestamp(),
      'sedeId': sedeId,
      'sede': sedeNombre,
      'destinatarioCorreo': correoDestino,
      'destinatarioNombre': nombre,
      'tipo': 'almuerzo_asignado',
      'accionRuta': 'almuerzos',
      'creadoPor': (asignadoPor ?? 'RRHH').toString().trim(),
      'leido': false,
    });
  }

  String _resolverRolPersonal(dynamic value) {
    if (UserRoleAccess.isAdminRole(value)) {
      return UserRoleAccess.roleAdmin;
    }
    if (UserRoleAccess.isRrhhRole(value)) {
      return UserRoleAccess.roleRrhh;
    }
    if (UserRoleAccess.isAdministrativeRole(value)) {
      return UserRoleAccess.roleAdministrative;
    }
    return UserRoleAccess.roleTeacher;
  }

  String _resolverTipoHorarioPersonal({
    required String rol,
    required String horarioId,
  }) {
    final rolNormalizado = rol.trim().toLowerCase();
    final horarioNormalizado = horarioId.trim().toUpperCase();

    if (rolNormalizado == 'personal administrativo' ||
        rolNormalizado == 'administrativo' ||
        rolNormalizado == 'rrhh' ||
        rolNormalizado == 'admin') {
      return 'administrativo';
    }

    if (horarioNormalizado.startsWith('NOCT')) {
      return 'nocturno';
    }

    if (horarioNormalizado.startsWith('TC')) {
      return 'completo';
    }

    return 'medio_tiempo';
  }

  Future<void> guardarUsuarioPersonalSede({
    String? usuarioDocId,
    required String nombre,
    required String correo,
    String? password,
    required String rol,
    required String sedeId,
    String? telefono,
    String? especialidad,
    String? horarioAsignadoId,
  }) async {
    final nombreLimpio = nombre.trim();
    final correoLimpio = correo.trim().toLowerCase();
    final passwordLimpio = password?.trim() ?? '';
    final rolLimpio = _resolverRolPersonal(rol);
    final horarioLimpio = (horarioAsignadoId ?? '').trim().toUpperCase();
    final telefonoLimpio = telefono?.trim() ?? '';
    final especialidadLimpia = especialidad?.trim() ?? '';
    final esNuevo = usuarioDocId == null || usuarioDocId.trim().isEmpty;

    if (nombreLimpio.isEmpty) {
      throw Exception('Ingrese el nombre del colaborador.');
    }

    if (correoLimpio.isEmpty) {
      throw Exception('Ingrese el correo del colaborador.');
    }

    if (esNuevo && passwordLimpio.isEmpty) {
      throw Exception('Ingrese la contraseña del colaborador.');
    }

    if (horarioLimpio.isEmpty) {
      throw Exception('Ingrese el horario asignado.');
    }

    final existentes = await _db
        .collection('usuarios')
        .where('correo', isEqualTo: correoLimpio)
        .limit(10)
        .get();

    for (final doc in existentes.docs) {
      if (!esNuevo && doc.id == usuarioDocId) {
        continue;
      }
      throw Exception('Ya existe un usuario registrado con ese correo.');
    }

    final ref = esNuevo
        ? _db.collection('usuarios').doc()
        : _db.collection('usuarios').doc(usuarioDocId!.trim());

    final tipoHorario = _resolverTipoHorarioPersonal(
      rol: rolLimpio,
      horarioId: horarioLimpio,
    );

    final payload = <String, dynamic>{
      'nombre': nombreLimpio,
      'correo': correoLimpio,
      'rol': rolLimpio,
      'tipo_horario': tipoHorario,
      'horarios_asignados': [horarioLimpio],
      'telefono': telefonoLimpio,
      'especialidad': especialidadLimpia.isNotEmpty
          ? especialidadLimpia
          : (UserRoleAccess.isAdministrativeRole(rolLimpio) ||
                  UserRoleAccess.isAdminRole(rolLimpio) ||
                  UserRoleAccess.isRrhhRole(rolLimpio)
              ? 'Administracion'
              : 'Docencia'),
      'sede': SedeAccess.displayNameForId(sedeId),
      'sedeId': sedeId,
      'dashboardWeb': sedeId,
      'actualizadoEn': FieldValue.serverTimestamp(),
    };

    if (passwordLimpio.isNotEmpty) {
      payload['password'] = passwordLimpio;
    }

    if (esNuevo) {
      payload['creadoEn'] = FieldValue.serverTimestamp();
    }

    if (UserRoleAccess.isAdminRole(rolLimpio)) {
      payload['allowedSedeIds'] = const [
        SedeAccess.matrizId,
        SedeAccess.sedeNorteId,
        SedeAccess.sedeCentroId,
        SedeAccess.sedeCreSerId,
      ];
    } else if (UserRoleAccess.isRrhhRole(rolLimpio)) {
      payload['allowedSedeIds'] = [sedeId];
    } else {
      payload['allowedSedeIds'] = FieldValue.delete();
    }

    await ref.set(payload, SetOptions(merge: true));
  }

  Future<void> eliminarUsuarioPersonalSede({
    required String usuarioDocId,
  }) async {
    final ref = _db.collection('usuarios').doc(usuarioDocId.trim());
    final snapshot = await ref.get();

    if (!snapshot.exists) {
      return;
    }

    final data = snapshot.data() as Map<String, dynamic>? ?? {};
    final rol = (data['rol'] ?? '').toString().trim().toUpperCase();
    if (rol == 'RRHH') {
      throw Exception('No se puede eliminar un usuario RRHH desde este apartado.');
    }

    await ref.delete();
  }

  Future<void> registrarTokenNotificacion({
    required String correo,
    required String token,
    String? sedeId,
  }) async {
    final correoNormalizado = correo.trim().toLowerCase();
    final tokenNormalizado = token.trim();

    if (correoNormalizado.isEmpty || tokenNormalizado.isEmpty) {
      return;
    }

    final query = await _db
        .collection('usuarios')
        .where('correo', isEqualTo: correoNormalizado)
        .get();

    if (query.docs.isEmpty) {
      return;
    }

    QueryDocumentSnapshot<Map<String, dynamic>>? match;
    if (sedeId != null && sedeId.trim().isNotEmpty) {
      for (final doc in query.docs) {
        if (SedeAccess.matchesSede(doc.data(), sedeId.trim())) {
          match = doc;
          break;
        }
      }
    }

    match ??= query.docs.first;

    await match.reference.set({
      'fcmTokens': FieldValue.arrayUnion([tokenNormalizado]),
      'ultimoTokenFcm': tokenNormalizado,
      'tokenActualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
