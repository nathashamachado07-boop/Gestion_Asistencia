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
    );
  }
}