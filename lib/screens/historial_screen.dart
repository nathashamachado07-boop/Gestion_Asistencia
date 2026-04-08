import 'package:flutter/material.dart';
import '../services/firebase_service.dart';

class HistorialScreen extends StatelessWidget {
  final String nombreDocente;
  final bool esAlmuerzo; // 1. NUEVO PARÁMETRO

  // Actualizamos el constructor para recibir 'esAlmuerzo' (por defecto es false)
  const HistorialScreen({
    super.key, 
    required this.nombreDocente, 
    this.esAlmuerzo = false, // Si no se envía, asume que es asistencia normal
  });

  static const Color _istsColor = Color(0xFF467879);

  void _mostrarDetalle(BuildContext context, Map<String, dynamic> reg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Detalle del Registro", 
          style: TextStyle(color: _istsColor, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _itemDetalle("Docente:", nombreDocente),
            _itemDetalle("Tipo:", reg['tipo'] ?? (esAlmuerzo ? "ALMUERZO" : "No definido")),
            _itemDetalle("Estado:", reg['estado'] ?? "N/A"),
            _itemDetalle("Hora:", reg['hora_marcada'] ?? reg['hora'] ?? reg['hora_salida'] ?? "S/H"),
            if (reg['hora_regreso'] != null) _itemDetalle("Regreso:", reg['hora_regreso']),
            _itemDetalle("Referencia:", reg['horario_ref'] ?? (esAlmuerzo ? "Jornada Almuerzo" : "General")),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cerrar", style: TextStyle(color: _istsColor)),
          )
        ],
      ),
    );
  }

  Widget _itemDetalle(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(etiqueta, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 5),
          Expanded(child: Text(valor, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final FirebaseService service = FirebaseService();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F7),
      appBar: AppBar(
        // 2. TÍTULO DINÁMICO
        title: Text(
          esAlmuerzo ? "Historial de Almuerzo" : "Mis Registros de Asistencia", 
          style: const TextStyle(color: Colors.white, fontSize: 18)
        ),
        backgroundColor: _istsColor,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        // 3. CAMBIO DE FUNCIÓN SEGÚN EL BOOLEANO
        // Debes tener estas dos funciones creadas en tu FirebaseService
        future: service.obtenerHistorialAsistencias(nombreDocente),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _istsColor));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text(esAlmuerzo ? "No hay registros de almuerzo." : "No hay registros de asistencia."));
          }

          final registros = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: registros.length,
            itemBuilder: (context, index) {
              final reg = registros[index];
              
              // Lógica de hora adaptada para almuerzo (salida) o asistencia
              final horaMostrar = reg['hora_marcada'] ?? reg['hora'] ?? reg['hora_salida'] ?? "S/H";
              final tipoRegistro = reg['tipo'] ?? (esAlmuerzo ? "ALMUERZO" : "REGISTRO");
              final esEntrada = tipoRegistro == "ENTRADA";

              return Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ListTile(
                  onTap: () => _mostrarDetalle(context, reg),
                  leading: Icon(
                    esAlmuerzo ? Icons.restaurant_rounded : (esEntrada ? Icons.login_rounded : Icons.logout_rounded),
                    color: _istsColor,
                  ),
                  title: Text(
                    tipoRegistro,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: _istsColor),
                  ),
                  subtitle: Text(esAlmuerzo ? "Salida: $horaMostrar" : "Hora: $horaMostrar"),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: reg['estado'] == "A tiempo" || reg['estado'] == "Completada" || reg['estado'] == "finalizado"
                          ? Colors.green.withOpacity(0.1) 
                          : Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      (reg['estado'] ?? "").toUpperCase(),
                      style: TextStyle(
                        color: reg['estado'] == "A tiempo" || reg['estado'] == "Completada" || reg['estado'] == "finalizado"
                            ? Colors.green 
                            : Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}