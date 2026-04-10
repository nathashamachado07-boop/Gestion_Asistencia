import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class DashboardAdminWeb extends StatelessWidget {
  const DashboardAdminWeb({super.key});

  @override
  Widget build(BuildContext context) {
    // Formato de fecha para coincidir con tu Firebase: "9 de abril de 2026"
    // Nota: Ajusta el locale si es necesario para que coincida exactamente con el texto en tu DB
    String hoy = DateFormat("d 'de' MMMM 'de' yyyy", 'es_ES').format(DateTime.now());

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "PANEL DE CONTROL - INTESUD",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF467879)),
          ),
          const SizedBox(height: 25),
          
          // --- TARJETAS DE RESUMEN (KPIs) ---
          Row(
            children: [
              _buildStatCard(
                "Docentes Registrados",
                FirebaseFirestore.instance.collection('usuarios').where('rol', isEqualTo: 'Docente').snapshots(),
                const Color(0xFF467879),
                Icons.person_search_outlined,
              ),
              _buildStatCard(
                "Asistencias de Hoy",
                // Filtramos por la fecha actual que coincida con el campo 'fecha' de tu Firebase
                FirebaseFirestore.instance.collection('asistencias_realizadas').snapshots(), 
                Colors.green,
                Icons.how_to_reg_outlined,
                filterToday: true,
              ),
              _buildStatCard(
                "Atrasos Detectados",
                FirebaseFirestore.instance.collection('asistencias_realizadas').where('estado', isEqualTo: 'Atraso').snapshots(),
                Colors.redAccent,
                Icons.timer_off_outlined,
              ),
            ],
          ),
          
          const SizedBox(height: 40),
          const Text("Accesos Directos", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 15),
          
          // --- BOTONES DE ACCIÓN RÁPIDA ---
          Row(
            children: [
              _buildQuickButton(
                context, 
                "VER REPORTES", 
                Icons.analytics_outlined, 
                const Color(0xFF467879),
                2, // Índice de la sesión de Reportes
              ),
              const SizedBox(width: 15),
              _buildQuickButton(
                context, 
                "GESTIÓN PERSONAL", 
                Icons.badge_outlined, 
                const Color(0xFF6C757D),
                3, // Índice de la sesión de Personal
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, Stream<QuerySnapshot> stream, Color color, IconData icon, {bool filterToday = false}) {
    return Expanded(
      child: StreamBuilder<QuerySnapshot>(
        stream: stream,
        builder: (context, snapshot) {
          int count = 0;
          if (snapshot.hasData) {
            if (filterToday) {
              // Lógica para contar solo los de hoy si no se filtra directamente en la query
              DateTime now = DateTime.now();
              count = snapshot.data!.docs.where((doc) {
                var data = doc.data() as Map<String, dynamic>;
                if (data['fecha'] is Timestamp) {
                  DateTime dt = (data['fecha'] as Timestamp).toDate();
                  return dt.day == now.day && dt.month == now.month && dt.year == now.year;
                }
                return false;
              }).length;
            } else {
              count = snapshot.data!.docs.length;
            }
          }

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
              border: Border(left: BorderSide(color: color, width: 6)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 5),
                    Text(
                      snapshot.connectionState == ConnectionState.waiting ? "..." : "$count",
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Icon(icon, color: color.withOpacity(0.5), size: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuickButton(BuildContext context, String label, IconData icon, Color color, int targetIndex) {
    return ElevatedButton.icon(
      onPressed: () {
        // Aquí debes llamar a la función que cambia el índice en tu AdminLayout
        // Si usas un Provider o un Callback, dispáralo aquí.
      },
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}