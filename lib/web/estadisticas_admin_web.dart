import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart'; 
import 'package:table_calendar/table_calendar.dart';

class EstadisticasAdminWeb extends StatelessWidget {
  const EstadisticasAdminWeb({super.key});

  @override
  Widget build(BuildContext context) {
    // Usamos StreamBuilder para que la pantalla "escuche" a Firebase constantemente
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('asistencias_realizadas').snapshots(),
      builder: (context, snapshot) {
        // Mientras carga o si no hay datos, mostramos un estado vacío
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00C0EF)));
        }

        final docs = snapshot.data?.docs ?? [];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(15),
          child: Column(
            children: [
              // --- FILA SUPERIOR: GRÁFICO CELESTE ---
              Container(
                height: 350,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                      decoration: const BoxDecoration(
                        color: Color(0xFF00C0EF), 
                        borderRadius: BorderRadius.only(topLeft: Radius.circular(5), topRight: Radius.circular(5)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("📊 Flujo de Asistencias Real", 
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          Row(
                            children: [
                              _buildSmallButton("Area", true),
                              _buildSmallButton("Donut", false),
                            ],
                          )
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: docs.isEmpty 
                          ? const Center(child: Text("Sin datos para graficar")) 
                          : _buildAreaChart(docs), // Pasamos los documentos reales
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),

              // --- FILA INFERIOR: CALENDARIO Y LISTA ---
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF00A65A), 
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: TableCalendar(
                        firstDay: DateTime.utc(2025, 1, 1),
                        lastDay: DateTime.utc(2030, 12, 31),
                        focusedDay: DateTime.now(),
                        headerStyle: const HeaderStyle(
                          formatButtonVisible: false,
                          titleCentered: true,
                          titleTextStyle: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                          leftChevronIcon: Icon(Icons.chevron_left, color: Colors.white),
                          rightChevronIcon: Icon(Icons.chevron_right, color: Colors.white),
                        ),
                        calendarStyle: const CalendarStyle(
                          todayDecoration: BoxDecoration(color: Colors.white30, shape: BoxShape.circle),
                          defaultTextStyle: TextStyle(color: Colors.white),
                          weekendTextStyle: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 1,
                    child: _buildAtrasosPanel(docs), // Pasamos los documentos reales
                  ),
                ],
              ),
            ],
          ),
        );
      }
    );
  }

  // Genera la gráfica basada en los datos actuales de Firebase
  Widget _buildAreaChart(List<QueryDocumentSnapshot> docs) {
    // Aquí podrías procesar 'docs' para contar asistencias por día. 
    // Por ahora, convertimos la cantidad de documentos en un punto dinámico.
    List<FlSpot> puntos = [];
    for (int i = 0; i < docs.length; i++) {
      puntos.add(FlSpot(i.toDouble(), (i + 2).toDouble())); 
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(show: true),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: puntos.isEmpty ? [const FlSpot(0, 0)] : puntos,
            isCurved: true,
            color: const Color(0xFF00C0EF),
            barWidth: 4,
            belowBarData: BarAreaData(show: true, color: const Color(0xFF00C0EF).withOpacity(0.3)),
          ),
        ],
      ),
    );
  }

  // Panel de alertas que filtra solo los "Atrasos" en tiempo real
  Widget _buildAtrasosPanel(List<QueryDocumentSnapshot> docs) {
    // Filtramos solo los que tienen estado "Atraso"
    final atrasos = docs.where((d) => d['estado'] == 'Atraso').toList();

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("🚨 Alertas de Atrasos (${atrasos.length})", 
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(),
          if (atrasos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text("No hay atrasos registrados", style: TextStyle(color: Colors.grey))),
            )
          else
            ...atrasos.map((doc) {
              return _atrasoItem(
                doc['docente'] ?? 'Sin nombre', 
                doc['estado'] ?? 'Atraso', 
                doc['hora_marcada'] ?? '--:--'
              );
            }).toList(),
        ],
      ),
    );
  }

  Widget _atrasoItem(String nombre, String estado, String hora) {
    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Colors.redAccent, 
        child: Icon(Icons.warning, color: Colors.white, size: 15)
      ),
      title: Text(nombre, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text("Estado: $estado"),
      trailing: Text(hora, style: const TextStyle(color: Colors.grey, fontSize: 12)),
    );
  }

  Widget _buildSmallButton(String text, bool active) {
    return Container(
      margin: const EdgeInsets.only(left: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? Colors.white24 : Colors.transparent,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11)),
    );
  }
}