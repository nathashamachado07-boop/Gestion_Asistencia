import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart';
import 'dart:html' as html;

class ReportesAdminWeb extends StatefulWidget {
  const ReportesAdminWeb({super.key});

  @override
  State<ReportesAdminWeb> createState() => _ReportesAdminWebState();
}

class _ReportesAdminWebState extends State<ReportesAdminWeb> {
  String? mesSeleccionado = DateFormat('MM').format(DateTime.now());
  String? anioSeleccionado = "2026";

  void _exportarExcel(List<QueryDocumentSnapshot> docs) {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Reporte Asistencias'];

    sheetObject.appendRow([
      TextCellValue("Docente"),
      TextCellValue("Fecha"),
      TextCellValue("Hora"),
      TextCellValue("Tipo"),
      TextCellValue("Estado"),
    ]);

    for (var doc in docs) {
      var data = doc.data() as Map<String, dynamic>;
      String fechaExcel = "";
      if (data['fecha'] is Timestamp) {
        fechaExcel = DateFormat('dd-MM-yyyy').format((data['fecha'] as Timestamp).toDate());
      }

      sheetObject.appendRow([
        TextCellValue(data['docente']?.toString() ?? ""),
        TextCellValue(fechaExcel),
        TextCellValue(data['hora_marcada']?.toString() ?? ""),
        TextCellValue(data['tipo']?.toString() ?? ""),
        TextCellValue(data['estado']?.toString() ?? ""),
      ]);
    }

    final bytes = excel.save();
    if (bytes != null) {
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      // Corregimos la advertencia usando el anchor directamente
      html.AnchorElement(href: url)
        ..setAttribute("download", "Reporte_${mesSeleccionado}_$anioSeleccionado.xlsx")
        ..click();
      html.Url.revokeObjectUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Panel de Control RRHH"),
        backgroundColor: const Color(0xFF467879),
      ),
      body: Row(
        children: [
          _buildFiltrosLateral(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('asistencias_realizadas').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                // FILTRADO MEJORADO
                var registrosFiltrados = snapshot.data!.docs.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  if (data['fecha'] != null && data['fecha'] is Timestamp) {
                    DateTime dt = (data['fecha'] as Timestamp).toDate();
                    return DateFormat('MM').format(dt) == mesSeleccionado && 
                           dt.year.toString() == anioSeleccionado;
                  }
                  return false;
                }).toList();

                if (registrosFiltrados.isEmpty) {
                  return const Center(child: Text("No hay registros. Verifica que el mes coincida."));
                }

                return _buildTablaReportes(registrosFiltrados);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {}, // Aquí podrías poner el botón de exportar si prefieres
        child: const Icon(Icons.download),
      ),
    );
  }

  // --- Manten los métodos _buildFiltrosLateral, _getMeses y _buildTablaReportes de tu código anterior ---
  // Solo asegúrate de que en la tabla uses: data['hora_marcada'] y data['fecha'] as Timestamp

  Widget _buildFiltrosLateral() {
    return Container(
      width: 250,
      color: Colors.grey[100],
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Filtros de Reporte", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const Divider(),
          const SizedBox(height: 20),
          const Text("Seleccionar Mes:"),
          DropdownButton<String>(
            value: mesSeleccionado,
            isExpanded: true,
            items: _getMeses(),
            onChanged: (val) => setState(() => mesSeleccionado = val),
          ),
          const SizedBox(height: 20),
          const Text("Seleccionar Año:"),
          DropdownButton<String>(
            value: anioSeleccionado,
            isExpanded: true,
            items: ["2025", "2026", "2027"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (val) => setState(() => anioSeleccionado = val),
          ),
        ],
      ),
    );
  }

  Widget _buildTablaReportes(List<QueryDocumentSnapshot> registros) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
        ),
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(Colors.grey[200]),
          columns: const [
            DataColumn(label: Text('Docente')),
            DataColumn(label: Text('Fecha')),
            DataColumn(label: Text('Hora')),
            DataColumn(label: Text('Tipo')),
            DataColumn(label: Text('Estado')),
          ],
          rows: registros.map((doc) {
            var data = doc.data() as Map<String, dynamic>;
            
            // Formatear la fecha para la tabla
            String fechaTexto = "";
            if (data['fecha'] is Timestamp) {
              fechaTexto = DateFormat('dd-MM-yyyy').format((data['fecha'] as Timestamp).toDate());
            }

            return DataRow(cells: [
              DataCell(Text(data['docente'] ?? "")),
              DataCell(Text(fechaTexto)),
              DataCell(Text(data['hora_marcada'] ?? "")), //
              DataCell(Text(data['tipo'] ?? "")),
              DataCell(
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: data['estado'] == "Atraso" ? Colors.red[100] : Colors.green[100],
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    data['estado'] ?? "",
                    style: TextStyle(color: data['estado'] == "Atraso" ? Colors.red : Colors.green),
                  ),
                ),
              ),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  List<DropdownMenuItem<String>> _getMeses() {
    return const [
      DropdownMenuItem(value: "01", child: Text("Enero")),
      DropdownMenuItem(value: "02", child: Text("Febrero")),
      DropdownMenuItem(value: "03", child: Text("Marzo")),
      DropdownMenuItem(value: "04", child: Text("Abril")),
      DropdownMenuItem(value: "05", child: Text("Mayo")),
      DropdownMenuItem(value: "06", child: Text("Junio")),
      DropdownMenuItem(value: "07", child: Text("Julio")),
      DropdownMenuItem(value: "08", child: Text("Agosto")),
      DropdownMenuItem(value: "09", child: Text("Septiembre")),
      DropdownMenuItem(value: "10", child: Text("Octubre")),
      DropdownMenuItem(value: "11", child: Text("Noviembre")),
      DropdownMenuItem(value: "12", child: Text("Diciembre")),
    ];
  }
}