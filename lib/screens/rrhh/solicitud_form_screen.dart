import 'package:flutter/material.dart';
import '../../models/solicitud_model.dart';
import '../../services/firebase_service.dart';

class SolicitudFormScreen extends StatefulWidget {
  @override
  _SolicitudFormScreenState createState() => _SolicitudFormScreenState();
}

class _SolicitudFormScreenState extends State<SolicitudFormScreen> {
  final _formKey = GlobalKey<FormState>();
  String _tipo = 'Permiso'; // O 'Vacaciones'
  String _motivo = '';
  DateTime _fechaInicio = DateTime.now();
  DateTime _fechaFin = DateTime.now();

  void _enviar() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      
      Solicitud nueva = Solicitud(
        id: '', // Firestore genera el ID automático
        colaborador: "Nombre del Docente Logueado", // Aquí usarás el nombre del usuario actual
        motivo: _motivo,
        tipo: _tipo,
        fechaInicio: _fechaInicio,
        fechaFin: _fechaFin,
      );

      await FirebaseService().enviarSolicitud(nueva);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Solicitud enviada automáticamente al panel web')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Nueva Solicitud")),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(16),
          children: [
            DropdownButtonFormField(
              value: _tipo,
              items: ['Permiso', 'Vacaciones'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (val) => setState(() => _tipo = val.toString()),
              decoration: InputDecoration(labelText: "Tipo de Solicitud"),
            ),
            TextFormField(
              decoration: InputDecoration(labelText: "Motivo (ej. Consulta Médica)"),
              onSaved: (val) => _motivo = val ?? '',
              validator: (val) => val!.isEmpty ? 'Campo obligatorio' : null,
            ),
            // Aquí puedes añadir selectores de fecha para fechaInicio y fechaFin
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _enviar,
              child: Text("ENVIAR SOLICITUD"),
              style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF1B3944)),
            )
          ],
        ),
      ),
    );
  }
}