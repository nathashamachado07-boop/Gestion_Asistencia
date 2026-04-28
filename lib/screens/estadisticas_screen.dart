import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/app_branding.dart';
import '../services/firebase_service.dart';

class EstadisticasScreen extends StatefulWidget {
  const EstadisticasScreen({
    super.key,
    required this.nombreDocente,
    this.isSedeNorte = false,
    this.sedeId,
  });

  final String nombreDocente;
  final bool isSedeNorte;
  final String? sedeId;

  @override
  State<EstadisticasScreen> createState() => _EstadisticasScreenState();
}

class _EstadisticasScreenState extends State<EstadisticasScreen> {
  bool _mostrarGrafica = false;
  final FirebaseService _service = FirebaseService();
  late Future<Map<String, int>> _estadisticasFuture;
  String _mesSeleccionado = 'Todos';
  bool get _isWebLayout => kIsWeb;

  AppBranding get _branding => AppBranding.fromLegacy(
        isSedeNorte: widget.isSedeNorte,
        sedeId: widget.sedeId,
      );

  final List<String> _meses = const [
    'Todos',
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
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
      mes: _mesSeleccionado,
    );
  }

  Future<void> _generarPDF(Map<String, int> dataSummary) async {
    final pdf = pw.Document();
    final ByteData image = await rootBundle.load(_branding.logoPdf);
    final Uint8List logoBytes = image.buffer.asUint8List();
    final pw.MemoryImage logoImage = pw.MemoryImage(logoBytes);

    final QuerySnapshot asistenciaSnapshot = await FirebaseFirestore.instance
        .collection('asistencias_realizadas')
        .where('docente', isEqualTo: widget.nombreDocente)
        .get();

    final registros = asistenciaSnapshot.docs.where((doc) {
      if (_mesSeleccionado == 'Todos') return true;
      final fecha = (doc['fecha'] as Timestamp).toDate();
      final mesDoc = _meses[fecha.month];
      return mesDoc == _mesSeleccionado;
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(35),
        build: (pw.Context context) {
          return [
            pw.Align(
              alignment: pw.Alignment.topLeft,
              child: pw.Image(logoImage, height: 65),
            ),
            pw.SizedBox(height: 15),
            pw.Text(
              'REPORTE DE ASISTENCIA',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Docente: ${widget.nombreDocente.toUpperCase()}',
              style: const pw.TextStyle(fontSize: 12),
            ),
            pw.Text(
              'Mes de consulta: $_mesSeleccionado',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 1, color: PdfColors.grey300),
            pw.SizedBox(height: 10),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Total Registros: ${dataSummary['Total']}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
                pw.Text(
                  'Puntuales: ${dataSummary['Puntual']}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
                pw.Text(
                  'Atrasos: ${dataSummary['Atraso']}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
              headerDecoration: pw.BoxDecoration(
                color: PdfColor.fromInt(_branding.primary.value),
              ),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding: const pw.EdgeInsets.all(5),
              data: <List<String>>[
                ['Fecha', 'Tipo', 'Estado', 'Hora Marcada'],
                ...registros.map((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final fecha = (d['fecha'] as Timestamp).toDate();
                  return [
                    DateFormat('dd/MM/yyyy').format(fecha),
                    d['tipo'] ?? '-',
                    d['estado'] ?? '-',
                    d['hora_marcada'] ?? '--:--',
                  ];
                }),
              ],
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 20),
              child: pw.Center(
                child: pw.Text(
                  'Generado desde aplicacion movil ${_branding.displayName}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
                ),
              ),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Reporte_${widget.nombreDocente}_$_mesSeleccionado.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          _isWebLayout ? Colors.white : _branding.background,
      body: Stack(
        children: [
          Container(
            color: _isWebLayout ? Colors.white : _branding.background,
          ),
          if (!_isWebLayout)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double logoSize = _branding.mobilePatternLogoSize;
                  const double spacing = 75.0;
                  final int cols = (constraints.maxWidth / spacing).ceil() + 1;
                  final int rows = (constraints.maxHeight / spacing).ceil() + 1;

                  return Stack(
                    children: List.generate(rows * cols, (index) {
                      final int row = index ~/ cols;
                      final int col = index % cols;
                      final double offsetX = (row % 2 == 0) ? 0 : spacing / 2;
                      final double left = col * spacing + offsetX - logoSize / 2;
                      final double top = row * spacing - logoSize / 2;

                      return Positioned(
                        left: left,
                        top: top,
                        child: Opacity(
                          opacity: 0.13,
                          child: Image.asset(
                            _branding.logoSmall,
                            width: logoSize,
                            height: logoSize,
                            fit: BoxFit.contain,
                            color: Colors.white,
                            colorBlendMode: BlendMode.srcIn,
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
          if (!_isWebLayout)
            Center(
              child: Opacity(
                opacity: 0.12,
                child: Image.asset(
                  _branding.logoWatermark,
                  width: MediaQuery.of(context).size.width *
                      _branding.mobileWatermarkWidthFactor,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          Column(
            children: [
              Container(
                height: 160,
                padding: const EdgeInsets.only(top: 50, left: 20, right: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_branding.primary, _branding.primaryDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(35)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Image.asset(
                      _branding.logoSmall,
                      height: _branding.mobileHeaderLogoHeight,
                      errorBuilder: (c, e, s) =>
                          const Icon(Icons.school, size: 40, color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'RESUMEN ESTADISTICO',
                      style: TextStyle(
                        fontSize: 18,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<Map<String, int>>(
                  future: _estadisticasFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: CircularProgressIndicator(color: _branding.primary),
                      );
                    }
                    if (snapshot.hasError || !snapshot.hasData) {
                      return const Center(child: Text('Error al cargar datos'));
                    }
                    final data = snapshot.data!;

                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 15),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(15),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: DropdownButton<String>(
                              value: _mesSeleccionado,
                              isExpanded: true,
                              underline: const SizedBox(),
                              items: _meses
                                  .map(
                                    (mes) => DropdownMenuItem(
                                      value: mes,
                                      child: Text(mes),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  _mesSeleccionado = value!;
                                  _cargarDatos();
                                });
                              },
                            ),
                          ),
                          const SizedBox(height: 25),
                          const Text(
                            'Rendimiento de Asistencia',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 200,
                            child: PieChart(
                              PieChartData(
                                sections: [
                                  _sectionData(
                                    data['Puntual'],
                                    Colors.green,
                                    'Puntual',
                                  ),
                                  _sectionData(
                                    data['Atraso'],
                                    Colors.orange,
                                    'Atraso',
                                  ),
                                  _sectionData(
                                    data['Salida Anticipada'],
                                    Colors.redAccent,
                                    'Salida',
                                  ),
                                ],
                                sectionsSpace: 4,
                                centerSpaceRadius: 40,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            alignment: WrapAlignment.center,
                            children: [
                              _buildLegendChip(
                                'Puntuales',
                                Colors.green,
                                '${data['Puntual']}',
                              ),
                              _buildLegendChip(
                                'Atrasos',
                                Colors.orange,
                                '${data['Atraso']}',
                              ),
                              _buildLegendChip(
                                'Salida anticipada',
                                Colors.redAccent,
                                '${data['Salida Anticipada']}',
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _generarPDF(data),
                              icon: const Icon(
                                Icons.picture_as_pdf,
                                color: Colors.white,
                              ),
                              label: const Text(
                                'EXPORTAR REPORTE PDF',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _branding.primary,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
                          _cardEstadistica(
                            'Total Registros',
                            '${data['Total']}',
                            Icons.list_alt,
                            Colors.blueGrey,
                          ),
                          _cardEstadistica(
                            'Asistencias Puntuales',
                            '${data['Puntual']}',
                            Icons.check_circle,
                            Colors.green,
                          ),
                          _cardEstadistica(
                            'Atrasos',
                            '${data['Atraso']}',
                            Icons.access_time_rounded,
                            Colors.orange,
                          ),
                          _cardEstadistica(
                            'Salidas Anticipadas',
                            '${data['Salida Anticipada']}',
                            Icons.logout_rounded,
                            Colors.redAccent,
                          ),
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

  PieChartSectionData _sectionData(int? valor, Color color, String titulo) {
    return PieChartSectionData(
      value: _mostrarGrafica ? (valor?.toDouble() ?? 0) : 0,
      color: color,
      title: _mostrarGrafica ? '$valor' : '',
      radius: 55,
      titleStyle:
          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildLegendChip(String titulo, Color color, String valor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            titulo,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            valor,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardEstadistica(
    String titulo,
    String valor,
    IconData icono,
    Color color,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: _branding.primary.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icono, color: color, size: 24),
        ),
        title: Text(
          titulo,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: Text(
          valor,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: _branding.primary.withOpacity(0.8),
          ),
        ),
      ),
    );
  }
}
