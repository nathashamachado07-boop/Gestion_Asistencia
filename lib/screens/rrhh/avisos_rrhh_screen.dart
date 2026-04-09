import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AvisosRRHHScreen extends StatelessWidget {
  const AvisosRRHHScreen({super.key});

  final Color _primary = const Color(0xFF467879);

  // Función genérica para enviar avisos a la colección que leen los docentes
  Future<void> _enviarAviso(BuildContext context, String titulo, String mensaje) async {
    try {
      await FirebaseFirestore.instance.collection('avisos').add({
        'titulo': titulo,
        'mensaje': mensaje,
        'fecha': DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
        'timestamp': FieldValue.serverTimestamp(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Aviso enviado: $titulo"), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error al enviar"), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F7),
      appBar: AppBar(
        title: const Text("Panel de Avisos Rápidos", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: _primary,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("COMUNICADOS GENERALES", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 15),
            
            // BOTÓN: MAÑANA NO SE TRABAJA
            _buildBotonAviso(
              context,
              "Mañana no se trabaja",
              "Se comunica a todo el personal que el día de mañana se suspenden las actividades laborales.",
              Icons.event_busy,
              Colors.redAccent,
            ),
            
            const SizedBox(height: 15),
            
            // BOTÓN: REUNIÓN GENERAL
            _buildBotonAviso(
              context,
              "Reunión General",
              "Estimados docentes, se les convoca a una reunión obligatoria en el salón de eventos a las 10:00 AM.",
              Icons.groups,
              _primary,
            ),

            const SizedBox(height: 40),
            const Text("GESTIÓN DE ALMUERZOS", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 15),

            // BOTÓN: ENVIAR HORARIO DE ALMUERZO
            _buildBotonAviso(
              context,
              "Horario de Almuerzo Activado",
              "Se ha habilitado el registro de almuerzo. Por favor, registren su salida y entrada en la pestaña correspondiente.",
              Icons.restaurant,
              Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotonAviso(BuildContext context, String titulo, String mensaje, IconData icono, Color color) {
    return Container(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 20),
          backgroundColor: Colors.white,
          foregroundColor: color,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(color: color.withOpacity(0.3)),
          ),
        ),
        onPressed: () => _confirmarEnvio(context, titulo, mensaje),
        icon: Icon(icono, size: 28),
        label: Text(
          titulo.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );
  }

  void _confirmarEnvio(BuildContext context, String titulo, String mensaje) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("¿Enviar aviso?"),
        content: Text("Se enviará el mensaje: '$titulo' a todos los usuarios."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _primary),
            onPressed: () {
              Navigator.pop(ctx);
              _enviarAviso(context, titulo, mensaje);
            },
            child: const Text("SÍ, ENVIAR", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}