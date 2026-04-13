class Solicitud {
  String id;
  String colaborador;
  String motivo;
  String tipo; // 'Vacaciones' o 'Permiso'
  DateTime fechaInicio;
  DateTime fechaFin;
  String estado; // 'Pendiente', 'Aprobado', 'Rechazado'

  Solicitud({
    required this.id,
    required this.colaborador,
    required this.motivo,
    required this.tipo,
    required this.fechaInicio,
    required this.fechaFin,
    this.estado = 'Pendiente',
  });

  Map<String, dynamic> toMap() => {
    'colaborador': colaborador,
    'motivo': motivo,
    'tipo': tipo,
    'fechaInicio': fechaInicio, // Quita el .toIso8601String()
    'fechaFin': fechaFin,       // Quita el .toIso8601String()
    'estado': estado,
};
}