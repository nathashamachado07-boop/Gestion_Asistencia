import 'dart:html' as html;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xls;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../config/app_config.dart';
import '../models/app_branding.dart';

class ReportesAdminWeb extends StatefulWidget {
  const ReportesAdminWeb({
    super.key,
    this.isSedeNorte = false,
    this.sedeId,
  });

  final bool isSedeNorte;
  final String? sedeId;

  @override
  State<ReportesAdminWeb> createState() => _ReportesAdminWebState();
}

class _ReportesAdminWebState extends State<ReportesAdminWeb> {
  String mesSeleccionado = 'Abril';
  int anioSeleccionado = 2026;
  String estadoSeleccionado = 'Todos';

  final List<String> meses = const [
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

  final Map<String, int> mesesMap = const {
    'Enero': 1,
    'Febrero': 2,
    'Marzo': 3,
    'Abril': 4,
    'Mayo': 5,
    'Junio': 6,
    'Julio': 7,
    'Agosto': 8,
    'Septiembre': 9,
    'Octubre': 10,
    'Noviembre': 11,
    'Diciembre': 12,
  };

  final List<String> estados = const [
    'Todos',
    'A tiempo',
    'Atraso',
    'Salida Anticipada',
    'Completada',
  ];

  String get _resolvedSedeId =>
      widget.sedeId ??
      (widget.isSedeNorte ? SedeAccess.sedeNorteId : SedeAccess.matrizId);
  AppBranding get _branding => AppBranding.fromSedeId(_resolvedSedeId);
  String get _logoAsset => _branding.logoPdf;
  String get _sedeNombre => _resolvedSedeId == SedeAccess.matrizId
      ? 'Sede Matriz'
      : SedeAccess.displayNameForId(_resolvedSedeId);
  String get _tituloSistema => _branding.displayName;
  Color get _primaryColor => _branding.primary;
  Color get _secondaryColor => _branding.primaryDark;
  Color get _excelHeaderColor => _branding.primary;
  Color get _excelSoftColor => _branding.surface;

  String _normalizarTexto(dynamic value) {
    return value?.toString().trim().toLowerCase() ?? '';
  }

  bool _matchesRole(Map<String, dynamic> data, String role) {
    return _normalizarTexto(data['rol']) == role.toLowerCase();
  }

  bool _matchesCurrentSede(Map<String, dynamic> data) {
    return SedeAccess.matchesSede(data, _resolvedSedeId);
  }

  Set<String> _obtenerUsuariosPermitidosPorSede(
    List<QueryDocumentSnapshot> docs,
  ) {
    return docs
        .map((doc) => doc.data() as Map<String, dynamic>)
        .where((data) {
          final esDeSede = _matchesCurrentSede(data);
          final esRolValido =
              _matchesRole(data, 'Docente') || _matchesRole(data, 'Administrativo');
          return esDeSede && esRolValido;
        })
        .map((data) => (data['nombre'] ?? '').toString().trim())
        .where((nombre) => nombre.isNotEmpty)
        .toSet();
  }

  List<QueryDocumentSnapshot> _filtrarRegistros(
    List<QueryDocumentSnapshot> docs, {
    Set<String>? nombresPermitidos,
  }) {
    final int numMes = mesesMap[mesSeleccionado] ?? 4;

    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['fecha'] == null || data['fecha'] is! Timestamp) {
        return false;
      }

      final fecha = (data['fecha'] as Timestamp).toDate();
      final coincidePeriodo =
          fecha.month == numMes && fecha.year == anioSeleccionado;

      if (!coincidePeriodo) return false;

      if (nombresPermitidos != null) {
        final nombreMarcacion = (data['docente'] ?? '').toString().trim();
        if (!nombresPermitidos.contains(nombreMarcacion)) {
          return false;
        }
      }

      if (estadoSeleccionado == 'Todos') return true;

      return (data['estado'] ?? '').toString() == estadoSeleccionado;
    }).toList();
  }

  Future<void> descargarReporte(List<QueryDocumentSnapshot> asistencias) async {
    final pdf = pw.Document();

    final ByteData image = await rootBundle.load(_logoAsset);
    final Uint8List logoBytes = image.buffer.asUint8List();
    final pw.MemoryImage logoImage = pw.MemoryImage(logoBytes);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Image(
                logoImage,
                height: _resolvedSedeId == SedeAccess.matrizId ? 70 : 80,
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    _tituloSistema,
                    style: pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    _sedeNombre,
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Divider(
            thickness: 1,
            color: PdfColor.fromInt(_primaryColor.value),
          ),
          pw.SizedBox(height: 10),
          pw.Center(
            child: pw.Text(
              'REPORTE MENSUAL DE ASISTENCIA',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Center(
            child: pw.Text(
              'Periodo: $mesSeleccionado $anioSeleccionado | Estado: $estadoSeleccionado',
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
            headerDecoration: pw.BoxDecoration(
              color: PdfColor.fromInt(_primaryColor.value),
            ),
            cellHeight: 30,
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.center,
              2: pw.Alignment.center,
              3: pw.Alignment.center,
              4: pw.Alignment.center,
            },
            data: <List<String>>[
              ['Docente', 'Fecha', 'Tipo', 'Estado', 'Hora'],
              ...asistencias.map((doc) {
                final data = doc.data() as Map<String, dynamic>;

                String fechaStr = '--/--/----';
                if (data['fecha'] != null && data['fecha'] is Timestamp) {
                  fechaStr = DateFormat('dd/MM/yyyy')
                      .format((data['fecha'] as Timestamp).toDate());
                }

                return [
                  (data['docente'] ?? 'N/A').toString(),
                  fechaStr,
                  (data['tipo'] ?? '-').toString(),
                  (data['estado'] ?? '-').toString(),
                  (data['hora_marcada'] ?? '--:--').toString(),
                ];
              }),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Generado por: Sistema de Gestion $_tituloSistema',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
            ),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Reporte_Asistencia_${mesSeleccionado}_$anioSeleccionado.pdf',
    );
  }

  Future<void> descargarExcel(List<QueryDocumentSnapshot> asistencias) async {
    final excel = xls.Excel.createExcel();
    final sheet = excel['Reporte'];
    excel.delete('Sheet1');

    sheet.merge(
      xls.CellIndex.indexByString('A1'),
      xls.CellIndex.indexByString('E1'),
    );
    sheet.merge(
      xls.CellIndex.indexByString('A2'),
      xls.CellIndex.indexByString('E2'),
    );
    sheet.merge(
      xls.CellIndex.indexByString('A3'),
      xls.CellIndex.indexByString('E3'),
    );

    sheet.cell(xls.CellIndex.indexByString('A1')).value =
        xls.TextCellValue(_tituloSistema.toUpperCase());
    sheet.cell(xls.CellIndex.indexByString('A2')).value =
        xls.TextCellValue('REPORTE MENSUAL DE ASISTENCIA');
    sheet.cell(xls.CellIndex.indexByString('A3')).value = xls.TextCellValue(
      'Sede: $_sedeNombre | Periodo: $mesSeleccionado $anioSeleccionado | Estado: $estadoSeleccionado',
    );

    final titleStyle = xls.CellStyle(
      bold: true,
      fontSize: 16,
      horizontalAlign: xls.HorizontalAlign.Center,
      verticalAlign: xls.VerticalAlign.Center,
      backgroundColorHex: xls.ExcelColor.fromHexString(
        '#${_excelHeaderColor.value.toRadixString(16).substring(2).toUpperCase()}',
      ),
      fontColorHex: xls.ExcelColor.white,
    );
    final subtitleStyle = xls.CellStyle(
      bold: true,
      fontSize: 13,
      horizontalAlign: xls.HorizontalAlign.Center,
      verticalAlign: xls.VerticalAlign.Center,
      backgroundColorHex: xls.ExcelColor.fromHexString(
        '#${_secondaryColor.value.toRadixString(16).substring(2).toUpperCase()}',
      ),
      fontColorHex: xls.ExcelColor.white,
    );
    final infoStyle = xls.CellStyle(
      italic: true,
      fontSize: 11,
      horizontalAlign: xls.HorizontalAlign.Center,
      verticalAlign: xls.VerticalAlign.Center,
      backgroundColorHex: xls.ExcelColor.fromHexString(
        '#${_excelSoftColor.value.toRadixString(16).substring(2).toUpperCase()}',
      ),
      fontColorHex: xls.ExcelColor.fromHexString('FF4A4A4A'),
    );

    sheet.cell(xls.CellIndex.indexByString('A1')).cellStyle = titleStyle;
    sheet.cell(xls.CellIndex.indexByString('A2')).cellStyle = subtitleStyle;
    sheet.cell(xls.CellIndex.indexByString('A3')).cellStyle = infoStyle;

    final headerRow = 5;
    final headers = ['Docente', 'Fecha', 'Tipo', 'Estado', 'Hora'];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        xls.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: headerRow - 1),
      );
      cell.value = xls.TextCellValue(headers[i]);
      cell.cellStyle = xls.CellStyle(
        bold: true,
        fontColorHex: xls.ExcelColor.white,
        backgroundColorHex: xls.ExcelColor.fromHexString(
          '#${_excelHeaderColor.value.toRadixString(16).substring(2).toUpperCase()}',
        ),
        horizontalAlign: xls.HorizontalAlign.Center,
        verticalAlign: xls.VerticalAlign.Center,
        leftBorder: xls.Border(borderStyle: xls.BorderStyle.Thin),
        rightBorder: xls.Border(borderStyle: xls.BorderStyle.Thin),
        topBorder: xls.Border(borderStyle: xls.BorderStyle.Thin),
        bottomBorder: xls.Border(borderStyle: xls.BorderStyle.Thin),
      );
    }

    for (var i = 0; i < asistencias.length; i++) {
      final rowIndex = headerRow + i;
      final data = asistencias[i].data() as Map<String, dynamic>;

      String fechaStr = '--/--/----';
      if (data['fecha'] != null && data['fecha'] is Timestamp) {
        fechaStr = DateFormat('dd/MM/yyyy')
            .format((data['fecha'] as Timestamp).toDate());
      }

      final values = [
        (data['docente'] ?? 'N/A').toString(),
        fechaStr,
        (data['tipo'] ?? '-').toString(),
        (data['estado'] ?? '-').toString(),
        (data['hora_marcada'] ?? '--:--').toString(),
      ];

      for (var col = 0; col < values.length; col++) {
        final cell = sheet.cell(
          xls.CellIndex.indexByColumnRow(
            columnIndex: col,
            rowIndex: rowIndex - 1,
          ),
        );
        cell.value = xls.TextCellValue(values[col]);
        cell.cellStyle = xls.CellStyle(
          backgroundColorHex: xls.ExcelColor.fromHexString(
            i.isEven
                ? '#FFFFFF'
                : '#${_excelSoftColor.value.toRadixString(16).substring(2).toUpperCase()}',
          ),
          horizontalAlign:
              col == 0 ? xls.HorizontalAlign.Left : xls.HorizontalAlign.Center,
          verticalAlign: xls.VerticalAlign.Center,
          leftBorder: xls.Border(borderStyle: xls.BorderStyle.Thin),
          rightBorder: xls.Border(borderStyle: xls.BorderStyle.Thin),
          topBorder: xls.Border(borderStyle: xls.BorderStyle.Thin),
          bottomBorder: xls.Border(borderStyle: xls.BorderStyle.Thin),
        );
      }
    }

    sheet.setColumnWidth(0, 28);
    sheet.setColumnWidth(1, 16);
    sheet.setColumnWidth(2, 18);
    sheet.setColumnWidth(3, 24);
    sheet.setColumnWidth(4, 14);

    final bytes = excel.encode();
    if (bytes == null) return;

    final blob = html.Blob(
      [Uint8List.fromList(bytes)],
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..download = 'Reporte_Asistencia_${mesSeleccionado}_$anioSeleccionado.xlsx'
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('asistencias_realizadas')
            .snapshots(),
        builder: (context, asistenciasSnapshot) {
          if (asistenciasSnapshot.hasError) {
            return const Center(child: Text('Error de conexion'));
          }
          if (!asistenciasSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('usuarios').snapshots(),
            builder: (context, usuariosSnapshot) {
              if (usuariosSnapshot.hasError) {
                return const Center(
                  child: Text('Error al cargar usuarios por sede'),
                );
              }
              if (!usuariosSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final nombresPermitidos = _obtenerUsuariosPermitidosPorSede(
                usuariosSnapshot.data!.docs,
              );
              final registrosFiltrados = _filtrarRegistros(
                asistenciasSnapshot.data!.docs,
                nombresPermitidos: nombresPermitidos,
              );

              return _buildContenido(
                registrosFiltrados,
                mostrarAvisoSede: true,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildContenido(
    List<QueryDocumentSnapshot> registrosFiltrados, {
    required bool mostrarAvisoSede,
  }) {
    final atrasos = registrosFiltrados.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return (data['estado'] ?? '').toString() == 'Atraso';
    }).length;
    final completos = registrosFiltrados.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return (data['estado'] ?? '').toString() == 'Completada';
    }).length;
    final entradas = registrosFiltrados.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return (data['tipo'] ?? '').toString() == 'ENTRADA';
    }).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 48,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _secondaryColor,
                  _primaryColor,
                  _primaryColor.withOpacity(0.82),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: _primaryColor.withOpacity(0.24)),
              boxShadow: [
                BoxShadow(
                  color: _primaryColor.withOpacity(0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 18,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          _sedeNombre,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Reportes de asistencia',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Consulta mensual de marcaciones, atrasos y registros completados con una vista adaptada a $_sedeNombre.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 260,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Resumen del periodo',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildHeroMetric(label: 'Registros', value: '${registrosFiltrados.length}'),
                      const SizedBox(height: 10),
                      _buildHeroMetric(label: 'Atrasos', value: '$atrasos'),
                      const SizedBox(height: 10),
                      _buildHeroMetric(label: 'Completadas', value: '$completos'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (mostrarAvisoSede) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: _excelSoftColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _primaryColor.withOpacity(0.24)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.location_city_outlined,
                    color: _primaryColor,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Mostrando solo registros de $_sedeNombre.',
                      style: TextStyle(
                        color: _primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _primaryColor.withOpacity(0.20)),
              boxShadow: [
                BoxShadow(
                  color: _primaryColor.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _primaryColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.tune_rounded,
                        color: _primaryColor,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Filtros del reporte',
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Ajusta mes, año y estado antes de exportar o revisar la tabla.',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 12,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 16,
                  runSpacing: 14,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildFilterField(
                      label: 'Mes',
                      icon: Icons.calendar_month_outlined,
                      child: DropdownButton<String>(
                        value: mesSeleccionado,
                        isDense: true,
                        underline: const SizedBox(),
                        items: meses
                            .map((m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(m),
                                ))
                            .toList(),
                        onChanged: (val) => setState(() => mesSeleccionado = val!),
                      ),
                    ),
                    _buildFilterField(
                      label: 'Año',
                      icon: Icons.event_note_outlined,
                      child: DropdownButton<int>(
                        value: anioSeleccionado,
                        isDense: true,
                        underline: const SizedBox(),
                        items: [2024, 2025, 2026]
                            .map((a) => DropdownMenuItem(
                                  value: a,
                                  child: Text(a.toString()),
                                ))
                            .toList(),
                        onChanged: (val) => setState(() => anioSeleccionado = val!),
                      ),
                    ),
                    _buildFilterField(
                      label: 'Estado',
                      icon: Icons.flag_outlined,
                      child: DropdownButton<String>(
                        value: estadoSeleccionado,
                        isDense: true,
                        underline: const SizedBox(),
                        items: estados
                            .map((e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(e),
                                ))
                            .toList(),
                        onChanged: (val) => setState(() => estadoSeleccionado = val!),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => descargarExcel(registrosFiltrados),
                      icon: const Icon(Icons.table_view_rounded, size: 18),
                      label: const Text('Descargar Excel'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => descargarReporte(registrosFiltrados),
                      icon: const Icon(Icons.picture_as_pdf, size: 18),
                      label: const Text('Descargar PDF'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final chipWidth = width < 700
                  ? (width - 14) / 2
                  : width < 1100
                      ? (width - 28) / 3
                      : (width - 42) / 4;

              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _buildSummaryChip(
                    label: 'Total',
                    value: '${registrosFiltrados.length}',
                    color: _primaryColor,
                    width: chipWidth,
                  ),
                  _buildSummaryChip(
                    label: 'Entradas',
                    value: '$entradas',
                    color: _secondaryColor,
                    width: chipWidth,
                  ),
                  _buildSummaryChip(
                    label: 'Atrasos',
                    value: '$atrasos',
                    color: const Color(0xFFD32F2F),
                    width: chipWidth,
                  ),
                  _buildSummaryChip(
                    label: 'Completadas',
                    value: '$completos',
                    color: const Color(0xFF2E7D32),
                    width: chipWidth,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 320),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _primaryColor.withOpacity(0.20)),
              boxShadow: [
                BoxShadow(
                  color: _primaryColor.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: registrosFiltrados.isEmpty
                ? _buildEmptyState()
                : LayoutBuilder(
                    builder: (context, constraints) {
                      const columnSpacing = 36.0;
                      const horizontalMargin = 18.0;
                      const minDocente = 240.0;
                      const minFecha = 130.0;
                      const minTipo = 120.0;
                      const minEstado = 150.0;
                      const minHora = 100.0;
                      final usableWidth = constraints.maxWidth - 32;
                      final minTableWidth = minDocente +
                          minFecha +
                          minTipo +
                          minEstado +
                          minHora +
                          (columnSpacing * 4) +
                          (horizontalMargin * 2);
                      final tableWidth =
                          usableWidth > minTableWidth ? usableWidth : minTableWidth;
                      final contentWidth =
                          tableWidth - (columnSpacing * 4) - (horizontalMargin * 2);
                      final docenteWidth = contentWidth * 0.34;
                      final fechaWidth = contentWidth * 0.16;
                      final tipoWidth = contentWidth * 0.15;
                      final estadoWidth = contentWidth * 0.20;
                      final horaWidth = contentWidth * 0.15;

                      return ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.all(16),
                          child: SizedBox(
                            width: tableWidth,
                            child: DataTableTheme(
                              data: DataTableThemeData(
                                headingRowColor: MaterialStatePropertyAll(
                                  _excelSoftColor.withOpacity(0.85),
                                ),
                                headingTextStyle: TextStyle(
                                  color: _secondaryColor,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                                dataTextStyle: const TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
                                dividerThickness: 0.7,
                                headingRowHeight: 62,
                                dataRowMinHeight: 68,
                                dataRowMaxHeight: 76,
                              ),
                              child: DataTable(
                                columnSpacing: columnSpacing,
                                horizontalMargin: horizontalMargin,
                                columns: [
                                  _buildWideColumn('Docente', docenteWidth),
                                  _buildWideColumn('Fecha', fechaWidth),
                                  _buildWideColumn('Tipo', tipoWidth),
                                  _buildWideColumn('Estado', estadoWidth),
                                  _buildWideColumn('Hora', horaWidth),
                                ],
                                rows: registrosFiltrados.map((doc) {
                                  final data = doc.data() as Map<String, dynamic>;
                                  final fecha = data['fecha'] != null
                                      ? (data['fecha'] as Timestamp).toDate()
                                      : null;
                                  final estado =
                                      (data['estado'] ?? '-').toString();

                                  return DataRow(
                                    cells: [
                                      DataCell(
                                        _buildWideCell(
                                          (data['docente'] ?? 'N/A').toString(),
                                          docenteWidth,
                                        ),
                                      ),
                                      DataCell(
                                        _buildWideCell(
                                          fecha != null
                                              ? DateFormat('dd/MM/yyyy')
                                                  .format(fecha)
                                              : '--',
                                          fechaWidth,
                                        ),
                                      ),
                                      DataCell(
                                        _buildWideCell(
                                          (data['tipo'] ?? '-').toString(),
                                          tipoWidth,
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: estadoWidth,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: _buildStatusChip(estado),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        _buildWideCell(
                                          (data['hora_marcada'] ?? '--:--')
                                              .toString(),
                                          horaWidth,
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeroMetric({
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterField({
    required String label,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _excelSoftColor.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primaryColor.withOpacity(0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: _primaryColor),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w700,
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _buildSummaryChip({
    required String label,
    required String value,
    required Color color,
    double? width,
  }) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 90),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.insights_outlined, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String estado) {
    final color = switch (estado) {
      'Atraso' => const Color(0xFFD32F2F),
      'Completada' => const Color(0xFF2E7D32),
      'A tiempo' => const Color(0xFF1565C0),
      'Salida Anticipada' => const Color(0xFFEF6C00),
      _ => Colors.black87,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Text(
        estado,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  DataColumn _buildWideColumn(String label, double width) {
    return DataColumn(
      label: SizedBox(
        width: width,
        child: Text(label),
      ),
    );
  }

  Widget _buildWideCell(String text, double width) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _excelSoftColor,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                Icons.inbox_outlined,
                color: _primaryColor,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No hay registros de asistencia para $_sedeNombre con los filtros seleccionados.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w700,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
