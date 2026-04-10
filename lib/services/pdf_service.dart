import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class PdfService {
  static final _colorPrimario     = PdfColor.fromHex('467879');
  static final _colorPrimarioDark = PdfColor.fromHex('3A6667');
  static final _colorAccent       = PdfColor.fromHex('5DCAA5');
  static final _colorTextoHeader  = PdfColor.fromHex('E1F5EE');
  static final _colorTextoMuted   = PdfColor.fromHex('9FE1CB');

  static final _colorPresente = PdfColor.fromHex('0F6E56');
  static final _bgPresente    = PdfColor.fromHex('E1F5EE');
  static final _colorTardanza = PdfColor.fromHex('854F0B');
  static final _bgTardanza    = PdfColor.fromHex('FAEEDA');
  static final _colorAusencia = PdfColor.fromHex('A32D2D');
  static final _bgAusencia    = PdfColor.fromHex('FCEBEB');
  static final _colorFinde    = PdfColor.fromHex('888780');
  static final _bgFinde       = PdfColor.fromHex('F1EFE8');

  static Future<Uint8List> generarReporteMensual({
    required String mesNombre,
    required int mesNumero,
    required int anio,
    required List<QueryDocumentSnapshot> asistencias,
  }) async {
    final pdf = pw.Document();
    final int diasEnMes = DateTime(anio, mesNumero + 1, 0).day;

    // ── PASO 1: Consolidar por docente/día usando solo ENTRADA ──────────
    // matrizAsistencia[nombre][dia] = 'P' | 'T'
    final Map<String, Map<int, String>> matrizAsistencia = {};

    for (var doc in asistencias) {
      try {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

        // Solo ENTRADA define el estado de asistencia del día
        final tipo = (data['tipo'] ?? '').toString().toUpperCase().trim();
        if (tipo != 'ENTRADA') continue;

        final fechaRaw = data['fecha'];
        if (fechaRaw == null || fechaRaw is! Timestamp) continue;

        final docente = (data['docente'] ?? '').toString().trim();
        if (docente.isEmpty) continue;

        final nombre = docente.toUpperCase();
        final fecha  = fechaRaw.toDate();

        // Verificar que el documento pertenece al mes/año correcto
        if (fecha.month != mesNumero || fecha.year != anio) continue;

        final estado = (data['estado'] ?? '').toString().trim();
        final marca  = (estado == 'Atraso' || estado == 'Tardanza') ? 'T' : 'P';

        matrizAsistencia.putIfAbsent(nombre, () => {});
        // Solo registrar si no hay ya un registro ese día (evita duplicados)
        matrizAsistencia[nombre]!.putIfAbsent(fecha.day, () => marca);

      } catch (e) {
        print("ERROR EN DOC: ${doc.id} -> $e");
      }
    }

    // ── PASO 2: Identificar fines de semana ─────────────────────────────
    final Set<int> fines = {};
    for (int d = 1; d <= diasEnMes; d++) {
      final wd = DateTime(anio, mesNumero, d).weekday;
      if (wd == 6 || wd == 7) fines.add(d);
    }
    final int diasHabiles       = diasEnMes - fines.length;
    final int diasHabilesSeguro = diasHabiles == 0 ? 1 : diasHabiles;

    // ── PASO 3: Calcular totales para tarjetas de resumen ───────────────
    int totalAusencias = 0;
    int sumaAsistencia = 0;
    for (final dias in matrizAsistencia.values) {
      for (int d = 1; d <= diasEnMes; d++) {
        if (fines.contains(d)) continue;
        final v = dias[d] ?? 'A';
        if (v == 'A') totalAusencias++;
        if (v == 'P' || v == 'T') sumaAsistencia++;
      }
    }

    final int    totalDocentes       = matrizAsistencia.length;
    final int    totalDocentesSeguro = totalDocentes == 0 ? 1 : totalDocentes;
    final double promedioAsistencia  =
        (sumaAsistencia / (totalDocentesSeguro * diasHabilesSeguro)) * 100;

    // ── PASO 4: Construir PDF ────────────────────────────────────────────
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: pw.EdgeInsets.zero,
        build: (context) => [
          pw.Container(height: 4, color: _colorAccent),

          // Header
          pw.Container(
            color: _colorPrimario,
            padding: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('INSTITUTO SUPERIOR TECNOLÓGICO SUDAMERICANO',
                        style: pw.TextStyle(color: _colorTextoHeader, fontWeight: pw.FontWeight.bold, fontSize: 13)),
                    pw.SizedBox(height: 3),
                    pw.Text('Reporte mensual de asistencia docente — $mesNombre $anio',
                        style: pw.TextStyle(color: _colorTextoMuted, fontSize: 10)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Generado: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                        style: pw.TextStyle(color: _colorTextoMuted, fontSize: 9)),
                    pw.SizedBox(height: 2),
                    pw.Text('Confidencial — Uso interno',
                        style: pw.TextStyle(color: _colorTextoMuted, fontSize: 9)),
                  ],
                ),
              ],
            ),
          ),

          // Leyenda
          pw.Container(
            color: _colorPrimarioDark,
            padding: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            child: pw.Row(
              children: [
                _legendaItem('P', _bgPresente, _colorPresente, 'Presente'),
                pw.SizedBox(width: 20),
                _legendaItem('T', _bgTardanza, _colorTardanza, 'Tardanza'),
                pw.SizedBox(width: 20),
                _legendaItem('A', _bgAusencia, _colorAusencia, 'Ausencia'),
                pw.SizedBox(width: 20),
                _legendaItem('—', _bgFinde, _colorFinde, 'No laborable'),
              ],
            ),
          ),

          // Tarjetas de resumen
          pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
            ),
            child: pw.Row(
              children: [
                _tarjetaResumen('Total docentes', '$totalDocentes', PdfColors.grey800),
                _tarjetaResumen('Días hábiles', '$diasHabiles', PdfColors.grey800),
                _tarjetaResumen(
                  'Asistencia promedio',
                  '${promedioAsistencia.toStringAsFixed(0)}%',
                  promedioAsistencia >= 90
                      ? _colorPresente
                      : promedioAsistencia >= 75 ? _colorTardanza : _colorAusencia,
                ),
                _tarjetaResumen('Ausencias totales', '$totalAusencias', _colorAusencia),
              ],
            ),
          ),

          pw.SizedBox(height: 8),

          // Tabla
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 16),
            child: pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
              columnWidths: {
                0: const pw.FixedColumnWidth(20),
                1: const pw.FlexColumnWidth(3),
                for (int i = 2; i <= diasEnMes + 1; i++) i: const pw.FixedColumnWidth(13),
                diasEnMes + 2: const pw.FixedColumnWidth(35),
              },
              children: [
                // Cabecera
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: _colorPrimario),
                  children: [
                    _headerCell('N°'),
                    _headerCell('Docente', align: pw.TextAlign.left),
                    for (int d = 1; d <= diasEnMes; d++)
                      _headerCell(
                        d.toString().padLeft(2, '0'),
                        fondo: fines.contains(d) ? _colorPrimarioDark : null,
                      ),
                    _headerCell('% Asist.'),
                  ],
                ),

                // Filas por docente
                ...matrizAsistencia.entries.toList().asMap().entries.map((entry) {
                  final idx    = entry.key;
                  final nombre = entry.value.key;
                  final dias   = entry.value.value;

                  int presentes = 0;
                  for (int d = 1; d <= diasEnMes; d++) {
                    if (fines.contains(d)) continue;
                    if ((dias[d] ?? 'A') != 'A') presentes++;
                  }

                  final double pct    = (presentes / diasHabilesSeguro) * 100;
                  final PdfColor pctColor = pct >= 90
                      ? _colorPresente
                      : pct >= 75 ? _colorTardanza : _colorAusencia;
                  final PdfColor pctBg = pct >= 90
                      ? _bgPresente
                      : pct >= 75 ? _bgTardanza : _bgAusencia;

                  return pw.TableRow(
                    children: [
                      _dataCell('${idx + 1}', color: PdfColors.grey600),
                      _dataCell(nombre, align: pw.TextAlign.left),
                      for (int d = 1; d <= diasEnMes; d++)
                        fines.contains(d)
                            ? _statusCell('—', _bgFinde, _colorFinde)
                            : _statusCell(
                                dias[d] ?? 'A',
                                dias[d] == 'P'
                                    ? _bgPresente
                                    : dias[d] == 'T'
                                        ? _bgTardanza
                                        : _bgAusencia,
                                dias[d] == 'P'
                                    ? _colorPresente
                                    : dias[d] == 'T'
                                        ? _colorTardanza
                                        : _colorAusencia,
                              ),
                      _pctCell('${pct.toStringAsFixed(0)}%', pctColor, pctBg),
                    ],
                  );
                }),
              ],
            ),
          ),

          pw.SizedBox(height: 12),

          // Footer
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 16),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('IST Sudamericano — Sistema de Gestión de Reportes',
                    style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
                pw.Text('Página ${context.pageNumber} de ${context.pagesCount}',
                    style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
              ],
            ),
          ),

          pw.SizedBox(height: 6),
          pw.Container(height: 3, color: _colorAccent),
        ],
      ),
    );

    return pdf.save();
  }

  // ── Widgets auxiliares ───────────────────────────────────────────────────

  static pw.Widget _legendaItem(String marca, PdfColor bg, PdfColor fg, String label) {
    return pw.Row(children: [
      pw.Container(
        width: 14, height: 14,
        decoration: pw.BoxDecoration(color: bg, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3))),
        alignment: pw.Alignment.center,
        child: pw.Text(marca, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: fg)),
      ),
      pw.SizedBox(width: 4),
      pw.Text(label, style: pw.TextStyle(fontSize: 8, color: PdfColor.fromHex('9FE1CB'))),
    ]);
  }

  static pw.Widget _tarjetaResumen(String label, String valor, PdfColor colorValor) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const pw.BoxDecoration(
          border: pw.Border(right: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
            pw.SizedBox(height: 3),
            pw.Text(valor, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: colorValor)),
          ],
        ),
      ),
    );
  }

  static pw.Widget _headerCell(String text,
      {pw.TextAlign align = pw.TextAlign.center, PdfColor? fondo}) {
    return pw.Container(
      color: fondo,
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(text,
          style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 7),
          textAlign: align),
    );
  }

  static pw.Widget _dataCell(String text,
      {pw.TextAlign align = pw.TextAlign.center, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Text(text,
          style: pw.TextStyle(fontSize: 7, color: color ?? PdfColors.grey800),
          textAlign: align),
    );
  }

  static pw.Widget _statusCell(String marca, PdfColor bg, PdfColor fg) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Container(
        decoration: pw.BoxDecoration(
            color: bg, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3))),
        padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        alignment: pw.Alignment.center,
        child: pw.Text(marca,
            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: fg),
            textAlign: pw.TextAlign.center),
      ),
    );
  }

  static pw.Widget _pctCell(String text, PdfColor fg, PdfColor bg) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Container(
        decoration: pw.BoxDecoration(
            color: bg, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10))),
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        alignment: pw.Alignment.center,
        child: pw.Text(text,
            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: fg),
            textAlign: pw.TextAlign.center),
      ),
    );
  }
}