import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/firebase_service.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class EstadisticasScreen extends StatefulWidget {
  final String nombreDocente;
  const EstadisticasScreen({super.key, required this.nombreDocente});

  @override
  State<EstadisticasScreen> createState() => _EstadisticasScreenState();
}

class _EstadisticasScreenState extends State<EstadisticasScreen> {
  static const Color _istsColor = Color(0xFF467879);
  bool _mostrarGrafica = false;

  // 👇 LO DEMÁS SIGUE NORMAL
  final FirebaseService _service = FirebaseService();
  late Future<Map<String, int>> _estadisticasFuture;
  String _mesSeleccionado = "Todos";

  final List<String> _meses = [
    "Todos",
    "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
    "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"
  ];

  @override
  void initState() {
    super.initState();
    _cargarDatos();

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _mostrarGrafica = true);
    });
  }

  void _cargarDatos() {
    _estadisticasFuture = _service.obtenerEstadisticasDocente(
      widget.nombreDocente,
      mes: _mesSeleccionado, // 👈 IMPORTANTE (debes adaptarlo en FirebaseService)
    );
  }

  // 📄 GENERAR PDF
  Future<void> _generarPDF(Map<String, int> data) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text("Reporte de Asistencia",
                  style: pw.TextStyle(fontSize: 20)),
              pw.SizedBox(height: 10),
              pw.Text("Docente: ${widget.nombreDocente}"),
              pw.Text("Mes: $_mesSeleccionado"),
              pw.SizedBox(height: 20),

              pw.Text("Total Registros: ${data['Total']}"),
              pw.Text("Puntuales: ${data['Puntual']}"),
              pw.Text("Atrasos: ${data['Atraso']}"),
              pw.Text("Salidas Anticipadas: ${data['Salida Anticipada']}"),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F7),
      appBar: AppBar(
        title: const Text("Resumen Estadístico",
            style: TextStyle(color: Colors.white, fontSize: 18)),
        backgroundColor: _istsColor,
        centerTitle: true,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.04,
              child: Icon(Icons.grid_4x4_rounded,
                  size: 400, color: _istsColor),
            ),
          ),
          Column(
            children: [
              // 🔽 FILTRO POR MES
              Padding(
                padding: const EdgeInsets.all(15),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: DropdownButton<String>(
                    value: _mesSeleccionado,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: _meses.map((mes) {
                      return DropdownMenuItem(
                        value: mes,
                        child: Text(mes),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _mesSeleccionado = value!;
                        _cargarDatos(); // 🔥 recarga datos
                      });
                    },
                  ),
                ),
              ),

              Expanded(
                child: FutureBuilder<Map<String, int>>(
                  future: _estadisticasFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: _istsColor));
                    }

                    if (snapshot.hasError || !snapshot.hasData) {
                      return Center(
                          child: Text("Error al cargar datos: ${snapshot.error}"));
                    }

                    final data = snapshot.data!;

                    if (data['Total'] == 0) {
                      return const Center(
                          child: Text(
                              "No hay datos suficientes para generar estadísticas."));
                    }

                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Text("Rendimiento de Asistencia",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                          const SizedBox(height: 20),

                          // 📊 GRÁFICA
                          SizedBox(
                            height: 220,
                            child: PieChart(
                              PieChartData(
                                sections: [
                                  PieChartSectionData(
                                    value: _mostrarGrafica
                                        ? (data['Puntual']
                                                ?.toDouble() ??
                                            0)
                                        : 0,
                                    color: Colors.green,
                                    title: _mostrarGrafica
                                        ? '${data['Puntual']}'
                                        : '',
                                    radius: 55,
                                  ),
                                  PieChartSectionData(
                                    value: _mostrarGrafica
                                        ? (data['Atraso']
                                                ?.toDouble() ??
                                            0)
                                        : 0,
                                    color: Colors.orange,
                                    title: _mostrarGrafica
                                        ? '${data['Atraso']}'
                                        : '',
                                    radius: 55,
                                  ),
                                  PieChartSectionData(
                                    value: _mostrarGrafica
                                        ? (data['Salida Anticipada']
                                                ?.toDouble() ??
                                            0)
                                        : 0,
                                    color: Colors.redAccent,
                                    title: _mostrarGrafica
                                        ? '${data['Salida Anticipada']}'
                                        : '',
                                    radius: 55,
                                  ),
                                ],
                                sectionsSpace: 4,
                                centerSpaceRadius: 40,
                              ),
                            ),
                          ),

                          const SizedBox(height: 30),

                          // 📄 BOTÓN PDF
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _generarPDF(data),
                              icon: const Icon(Icons.picture_as_pdf),
                              label: const Text("EXPORTAR REPORTE PDF"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _istsColor,
                                padding:
                                    const EdgeInsets.symmetric(
                                        vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(15),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 30),

                          _cardEstadistica("Total Registros",
                              "${data['Total']}",
                              Icons.list_alt, Colors.blueGrey),
                          _cardEstadistica("Asistencias Puntuales",
                              "${data['Puntual']}",
                              Icons.check_circle, Colors.green),
                          _cardEstadistica("Atrasos Detectados",
                              "${data['Atraso']}",
                              Icons.warning_amber_rounded,
                              Colors.orange),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cardEstadistica(
      String titulo, String valor, IconData icono, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _istsColor.withValues(alpha: 0.08),
            blurRadius: 15,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icono, color: color, size: 24),
        ),
        title: Text(titulo,
            style: const TextStyle(
                fontSize: 13,
                color: Colors.grey,
                fontWeight: FontWeight.w500)),
        trailing: Text(
          valor,
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _istsColor.withValues(alpha: 0.8)),
        ),
      ),
    );
  }
}