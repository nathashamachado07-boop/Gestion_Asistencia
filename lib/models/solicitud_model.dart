import 'package:cloud_firestore/cloud_firestore.dart';

class Solicitud {
  String id;
  String colaborador;
  String motivo;
  String tipo; // 'Vacaciones' o 'Permiso'
  DateTime fechaInicio;
  DateTime fechaFin;
  String estado; // 'pendiente', 'aprobado', 'rechazado'

  // --- CAMPOS PARA PERMISOS Y VACACIONES ---
  String? horasPermiso;    
  String? descontarDe;     
  int? diasDisponibles;    
  int? diasATomar;         
  DateTime? fechaSolicitud; 
  int? anioVacaciones;
  int? diasAcumulados;
  int? saldoDias;
  DateTime? fechaRetorno;
  String? sedeId;
  String? sede;
  String? numFormulario;
  String? colaboradorCorreo;

  Solicitud({
    required this.id,
    required this.colaborador,
    required this.motivo,
    required this.tipo,
    required this.fechaInicio,
    required this.fechaFin,
    this.estado = 'pendiente',
    this.horasPermiso,
    this.descontarDe,
    this.diasDisponibles,
    this.diasATomar,
    this.fechaSolicitud,
    this.anioVacaciones,
    this.diasAcumulados,
    this.saldoDias,
    this.fechaRetorno,
    this.sedeId,
    this.sede,
    this.numFormulario,
    this.colaboradorCorreo,
  });

  Map<String, dynamic> toMap() => {
    'colaborador': colaborador,
    'motivo': motivo,
    'tipo': tipo,
    'fechaInicio': fechaInicio,
    'fechaFin': fechaFin,
    'estado': estado,
    'horasPermiso': horasPermiso,
    'descontarDe': descontarDe,
    'diasDisponibles': diasDisponibles,
    'diasATomar': diasATomar,
    'fechaSolicitud': fechaSolicitud ?? DateTime.now(),
    'fechaPermiso': tipo == 'Permiso' ? fechaInicio : null,
    'horarioPermiso': horasPermiso,
    'anioVacaciones':
        tipo == 'Vacaciones' ? (anioVacaciones ?? fechaInicio.year) : null,
    'diasAcumulados':
        tipo == 'Vacaciones' ? (diasAcumulados ?? diasDisponibles) : null,
    'saldoDias': tipo == 'Vacaciones'
        ? (saldoDias ?? ((diasDisponibles ?? 0) - (diasATomar ?? 0)))
        : null,
    'fechaRetorno': tipo == 'Vacaciones'
        ? (fechaRetorno ?? fechaFin.add(const Duration(days: 1)))
        : null,
    'sedeId': sedeId,
    'sede': sede,
    'numFormulario': numFormulario,
    'colaboradorCorreo': colaboradorCorreo,
  };

  factory Solicitud.fromMap(String id, Map<String, dynamic> map) {
    return Solicitud(
      id: id,
      colaborador: map['colaborador'] ?? '',
      motivo: map['motivo'] ?? '',
      tipo: map['tipo'] ?? '',
      fechaInicio: (map['fechaInicio'] as Timestamp).toDate(),
      fechaFin: (map['fechaFin'] as Timestamp).toDate(),
      estado: map['estado'] ?? 'pendiente',
      horasPermiso: map['horasPermiso'],
      descontarDe: map['descontarDe'],
      diasDisponibles: map['diasDisponibles'],
      diasATomar: map['diasATomar'],
      fechaSolicitud: map['fechaSolicitud'] != null 
          ? (map['fechaSolicitud'] as Timestamp).toDate() 
          : null,
      anioVacaciones: (map['anioVacaciones'] as num?)?.toInt(),
      diasAcumulados: (map['diasAcumulados'] as num?)?.toInt(),
      saldoDias: (map['saldoDias'] as num?)?.toInt(),
      fechaRetorno: map['fechaRetorno'] != null
          ? (map['fechaRetorno'] as Timestamp).toDate()
          : null,
      sedeId: map['sedeId'],
      sede: map['sede'],
      numFormulario: map['numFormulario']?.toString(),
      colaboradorCorreo: map['colaboradorCorreo']?.toString(),
    );
  }
}
