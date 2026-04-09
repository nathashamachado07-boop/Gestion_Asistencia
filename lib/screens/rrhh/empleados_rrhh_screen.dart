import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EmpleadosRRHHScreen extends StatelessWidget {
  const EmpleadosRRHHScreen({super.key});

  final Color _primary = const Color(0xFF467879);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F7),
      appBar: AppBar(
        title: const Text("Directorio de Empleados", 
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: _primary,
        elevation: 0,
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Consultamos la colección donde guardas a los usuarios (docentes)
        stream: FirebaseFirestore.instance.collection('usuarios').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No hay empleados registrados."));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var empleado = snapshot.data!.docs[index];
              return _buildCardEmpleado(empleado);
            },
          );
        },
      ),
    );
  }

  Widget _buildCardEmpleado(DocumentSnapshot doc) {
    // Extraemos datos (ajusta los nombres de los campos según tu Firebase)
    String nombre = doc['nombre'] ?? 'Sin nombre';
    String correo = doc['correo'] ?? 'Sin correo';
    String rol = doc['rol'] ?? 'Docente';
    List<dynamic> horarios = doc['horarios_asignados'] ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 5))
        ],
      ),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: _primary.withOpacity(0.1),
          child: Text(nombre[0].toUpperCase(), 
            style: TextStyle(color: _primary, fontWeight: FontWeight.bold)),
        ),
        title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(correo, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: rol == 'RRHH' ? Colors.blue.withOpacity(0.1) : Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(rol, style: TextStyle(fontSize: 10, color: rol == 'RRHH' ? Colors.blue : Colors.green, fontWeight: FontWeight.bold)),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(15.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const Text("HORARIOS ASIGNADOS:", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: horarios.map((h) => Chip(
                    label: Text(h.toString(), style: const TextStyle(fontSize: 10)),
                    backgroundColor: Colors.grey[100],
                    side: BorderSide.none,
                  )).toList(),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        // Aquí podrías agregar lógica para editar al empleado
                      },
                      icon: const Icon(Icons.edit_note, size: 20),
                      label: const Text("Editar Perfil"),
                    ),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}