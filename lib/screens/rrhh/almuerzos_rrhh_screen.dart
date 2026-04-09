import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AlmuerzosRRHHScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Gestión de Almuerzos'),
        backgroundColor: Color(0xFF426A6C),
      ),
      body: StreamBuilder(
        // Solo filtramos a los que tienen horario completo
        stream: FirebaseFirestore.instance
            .collection('usuarios')
            .where('tipo_horario', isEqualTo: 'completo')
            .snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
          
          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var empleado = snapshot.data!.docs[index];
              return Card(
                margin: EdgeInsets.all(10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: Color(0xFF426A6C), child: Icon(Icons.person, color: Colors.white)),
                  title: Text(empleado['nombre']),
                  subtitle: Text('Horario: ${empleado['tipo_horario']}'),
                  trailing: IconButton(
                    icon: Icon(Icons.send, color: Color(0xFF426A6C)),
                    onPressed: () {
                      // Aquí agregarás la lógica para enviar el horario
                      print('Enviando horario a ${empleado['nombre']}');
                    },
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