import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Asegúrate de tener intl en tu pubspec.yaml
import '../../models/solicitud_model.dart';
import '../../services/firebase_service.dart';

class SolicitudFormScreen extends StatefulWidget {
  final String nombreDocente; // Pasamos el nombre desde el perfil o login

  const SolicitudFormScreen({super.key, required this.nombreDocente});

  @override
  State<SolicitudFormScreen> createState() => _SolicitudFormScreenState();
}

class _SolicitudFormScreenState extends State<SolicitudFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseService _firebaseService = FirebaseService();

  // Variables del formulario
  String _tipoSeleccionado = 'Permiso';
  String _motivo = '';
  DateTime _fechaInicio = DateTime.now();
  DateTime _fechaFin = DateTime.now();

  // Función para mostrar el calendario
  Future<void> _seleccionarFecha(BuildContext context, bool esInicio) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2027),
    );
    if (picked != null) {
      setState(() {
        if (esInicio) _fechaInicio = picked; else _fechaFin = picked;
      });
    }
  }

  void _enviarFormulario() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      // Creamos el objeto basado en tu modelo
      Solicitud nuevaSolicitud = Solicitud(
        id: '', // Firestore lo genera solo
        colaborador: widget.nombreDocente,
        motivo: _motivo,
        tipo: _tipoSeleccionado,
        fechaInicio: _fechaInicio,
        fechaFin: _fechaFin,
        estado: 'pendiente',
      );

      try {
        await _firebaseService.enviarSolicitud(nuevaSolicitud);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Solicitud enviada con éxito')),
          );
          Navigator.pop(context); // Regresa a la pantalla anterior
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Nueva Solicitud"),
        backgroundColor: const Color(0xFF467879),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Text("Detalle de la solicitud", 
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),

              // Selección de Tipo
              DropdownButtonFormField<String>(
                value: _tipoSeleccionado,
                decoration: const InputDecoration(labelText: "Tipo de trámite"),
                items: ['Permiso', 'Vacaciones'].map((String value) {
                  return DropdownMenuItem<String>(value: value, child: Text(value));
                }).toList(),
                onChanged: (val) => setState(() => _tipoSeleccionado = val!),
              ),

              const SizedBox(height: 20),

              // Motivo
              TextFormField(
                decoration: const InputDecoration(
                  labelText: "Motivo / Justificación",
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                validator: (val) => val!.isEmpty ? 'Escriba un motivo' : null,
                onSaved: (val) => _motivo = val!,
              ),

              const SizedBox(height: 20),

              // Fechas
              ListTile(
                title: Text("Desde: ${DateFormat('dd/MM/yyyy').format(_fechaInicio)}"),
                trailing: const Icon(Icons.calendar_month),
                onTap: () => _seleccionarFecha(context, true),
              ),
              ListTile(
                title: Text("Hasta: ${DateFormat('dd/MM/yyyy').format(_fechaFin)}"),
                trailing: const Icon(Icons.calendar_month),
                onTap: () => _seleccionarFecha(context, false),
              ),

              const SizedBox(height: 30),

              ElevatedButton(
                onPressed: _enviarFormulario,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF467879),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: const Text("ENVIAR A RECURSOS HUMANOS", 
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}