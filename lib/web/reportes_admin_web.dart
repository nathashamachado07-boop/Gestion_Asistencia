import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:html' as html;
import '../services/pdf_service.dart';

class ReportesAdminWeb extends StatefulWidget {
  const ReportesAdminWeb({super.key});

  @override
  State<ReportesAdminWeb> createState() => _ReportesAdminWebState();
}

class _ReportesAdminWebState extends State<ReportesAdminWeb> {
  String? mesSeleccionado = DateFormat('MM').format(DateTime.now());
  String? anioSeleccionado = DateTime.now().year.toString();

  static const Color primaryColor = Color(0xFF467879);

  // Filtra documentos válidos del mes/año seleccionado (ENTRADA y SALIDA)
  List<QueryDocumentSnapshot> _filtrarDocs(List<QueryDocumentSnapshot> docs) {
    return docs.where((doc) {
      try {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) return false;
        if (data['fecha'] == null || data['fecha'] is! Timestamp) return false;
        if (data['docente'] == null) return false;

        final dt = (data['fecha'] as Timestamp).toDate();
        return DateFormat('MM').format(dt) == mesSeleccionado &&
               dt.year.toString() == anioSeleccionado;
      } catch (_) {
        return false;
      }
    }).toList();
  }

  void _exportarPDF(List<QueryDocumentSnapshot> docs) async {
    try {
      if (mesSeleccionado == null || anioSeleccionado == null) {
        throw "Seleccione un mes y año válidos.";
      }

      // Pasar TODOS los docs filtrados por mes/año — el pdf_service
      // internamente usa solo los de tipo ENTRADA para la matriz,
      // ignorando SALIDA y SALIDA ANTICIPADA de forma segura.
      if (docs.isEmpty) {
        throw "No hay registros de asistencia para el período seleccionado.";
      }

      final bytes = await PdfService.generarReporteMensual(
        mesNombre: _getNombreMes(mesSeleccionado!),
        mesNumero: int.parse(mesSeleccionado!),
        anio: int.parse(anioSeleccionado!),
        asistencias: docs,
      );

      if (bytes.isEmpty) throw "No se pudo generar el PDF.";

      // Descarga en el navegador
      final blob = html.Blob([bytes], 'application/pdf');
      final url  = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute("download",
            "Reporte_Asistencia_${_getNombreMes(mesSeleccionado!)}_$anioSeleccionado.pdf")
        ..click();
      html.Url.revokeObjectUrl(url);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("PDF descargado correctamente"),
            backgroundColor: primaryColor,
          ),
        );
      }
    } catch (e) {
      print("Error PDF: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al generar el PDF: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getNombreMes(String num) {
    const meses = {
      "01": "Enero",    "02": "Febrero", "03": "Marzo",
      "04": "Abril",    "05": "Mayo",    "06": "Junio",
      "07": "Julio",    "08": "Agosto",  "09": "Septiembre",
      "10": "Octubre",  "11": "Noviembre","12": "Diciembre",
    };
    return meses[num] ?? "Reporte";
  }

  String _getEstadoLabel(String estado) {
    switch (estado.trim()) {
      case 'Puntual':           return 'Puntual';
      case 'Atraso':            return 'Tardanza';
      case 'Tardanza':          return 'Tardanza';
      case 'Salida Anticipada': return 'Salida Anticipada';
      case 'Salida':            return 'Salida';
      default:                  return estado;
    }
  }

  Color _getEstadoColor(String estado) {
    switch (estado.trim()) {
      case 'Puntual':           return const Color(0xFF0F6E56);
      case 'Atraso':
      case 'Tardanza':          return const Color(0xFF854F0B);
      case 'Salida Anticipada': return const Color(0xFFA32D2D);
      default:                  return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Panel de filtros y botón PDF ──────────────────────────────
        Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
            border: const Border(top: BorderSide(color: primaryColor, width: 4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("REPORTES DE ASISTENCIA",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryColor)),
              const SizedBox(height: 20),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('asistencias_realizadas')
                    .snapshots(),
                builder: (context, snapshot) {
                  final docs = snapshot.hasData ? _filtrarDocs(snapshot.data!.docs) : [];

                  return Row(
                    children: [
                      const Icon(Icons.filter_alt_outlined, color: primaryColor),
                      const SizedBox(width: 10),
                      const Text("Mes: ", style: TextStyle(fontWeight: FontWeight.w500)),
                      DropdownButton<String>(
                        value: mesSeleccionado,
                        items: _getMeses(),
                        onChanged: (val) => setState(() => mesSeleccionado = val),
                      ),
                      const SizedBox(width: 24),
                      const Text("Año: ", style: TextStyle(fontWeight: FontWeight.w500)),
                      DropdownButton<String>(
                        value: anioSeleccionado,
                        items: ["2024", "2025", "2026", "2027"]
                            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                            .toList(),
                        onChanged: (val) => setState(() => anioSeleccionado = val),
                      ),
                      const Spacer(),

                      // Contador de registros
                      if (snapshot.hasData)
                        Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: Text(
                            "${docs.length} registro(s)",
                            style: const TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ),

                      // Botón PDF
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                          disabledBackgroundColor: Colors.grey[300],
                        ),
                        onPressed: docs.isEmpty ? null : () => _exportarPDF(docs as List<QueryDocumentSnapshot>),
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text("DESCARGAR PDF",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),

        // ── Tabla de previsualización ─────────────────────────────────
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
            ),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('asistencias_realizadas')
                  .orderBy('fecha', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final registros = _filtrarDocs(snapshot.data!.docs);

                if (registros.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text("No hay registros para este período.",
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                return SingleChildScrollView(
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                        const Color(0xFF467879).withOpacity(0.08)),
                    columns: const [
                      DataColumn(label: Text('Docente',    style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Fecha',      style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Tipo',       style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Estado',     style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Hora',       style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: registros.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final estado = (data['estado'] ?? '').toString();
                      final tipo   = (data['tipo']   ?? '').toString();

                      return DataRow(cells: [
                        DataCell(Text(data['docente'] ?? '')),
                        DataCell(Text(DateFormat('dd/MM/yyyy')
                            .format((data['fecha'] as Timestamp).toDate()))),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: tipo.toUpperCase() == 'ENTRADA'
                                  ? const Color(0xFFE1F5EE)
                                  : const Color(0xFFFAEEDA),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              tipo,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: tipo.toUpperCase() == 'ENTRADA'
                                    ? const Color(0xFF0F6E56)
                                    : const Color(0xFF854F0B),
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            _getEstadoLabel(estado),
                            style: TextStyle(
                              color: _getEstadoColor(estado),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        DataCell(Text(data['hora_marcada'] ?? '')),
                      ]);
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
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