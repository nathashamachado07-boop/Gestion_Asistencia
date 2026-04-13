import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firebase_service.dart'; // Verifica que la ruta sea correcta según tu carpeta

class GestionPersonalWeb extends StatefulWidget {
  const GestionPersonalWeb({super.key});

  @override
  State<GestionPersonalWeb> createState() => _GestionPersonalWebState();
}

class _GestionPersonalWebState extends State<GestionPersonalWeb> {
  final FirebaseService _fs = FirebaseService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3E9DC), // Color crema de tu diseño
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ENCABEZADO ESTILO TU DISEÑO
          Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "GESTIÓN DE PERSONAL DOCENTE",
                  style: TextStyle(
                    fontSize: 40, 
                    fontWeight: FontWeight.bold, 
                    color: Color(0xFF4A4A4A),
                    fontFamily: 'Serif', // O la fuente que uses en tu logo
                  ),
                ),
                Text(
                  "Solicitudes de Permisos y Vacaciones",
                  style: TextStyle(fontSize: 18, color: Colors.brown.shade400),
                ),
              ],
            ),
          ),

          // LISTADO DE TARJETAS (MOSAICOS)
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _fs.obtenerSolicitudesPendientes(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text("No hay solicitudes pendientes por revisar ☕"),
                  );
                }

                var solicitudes = snapshot.data!.docs;

                return GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, // 3 tarjetas por fila
                    crossAxisSpacing: 25,
                    mainAxisSpacing: 25,
                    childAspectRatio: 0.7, // Ajuste para que la tarjeta sea alargada
                  ),
                  itemCount: solicitudes.length,
                  itemBuilder: (context, index) {
                    var data = solicitudes[index].data() as Map<String, dynamic>;
                    String idDoc = solicitudes[index].id;

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          )
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Align(
                              alignment: Alignment.topRight,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD4A373).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text("PENDIENTE", 
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFD4A373))),
                              ),
                            ),
                            const CircleAvatar(
                              radius: 40,
                              backgroundColor: Color(0xFFE5E5E5),
                              child: Icon(Icons.person, size: 50, color: Colors.white),
                            ),
                            const SizedBox(height: 15),
                            Text(
                              data['nombre_empleado'] ?? "Sin Nombre",
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              data['cargo'] ?? "Docente",
                              style: const TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 15),
                            // Etiqueta de tipo (Vacaciones/Enfermedad)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1FAEE),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Text(data['tipo'] ?? "Permiso", 
                                style: const TextStyle(color: Color(0xFF457B9D), fontWeight: FontWeight.bold)),
                            ),
                            const Spacer(),
                            const Divider(),
                            Text(data['motivo'] ?? "Sin motivo especificado", 
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: const TextStyle(fontSize: 13, color: Colors.black54),
                            ),
                            const Spacer(),
                            // BOTÓN APROBAR (Como en tu imagen)
                            SizedBox(
                              width: double.infinity,
                              height: 45,
                              child: ElevatedButton.icon(
                                onPressed: () => _fs.actualizarEstadoSolicitud(idDoc, 'aprobado'),
                                icon: const Icon(Icons.check, color: Colors.white),
                                label: const Text("Aprobar", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF52B788),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}