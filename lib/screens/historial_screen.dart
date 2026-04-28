import 'package:flutter/material.dart';

import '../models/app_branding.dart';
import '../services/firebase_service.dart';

class HistorialScreen extends StatelessWidget {
  const HistorialScreen({
    super.key,
    required this.nombreDocente,
    required this.correoUsuario,
    this.esAlmuerzo = false,
    this.isSedeNorte = false,
    this.sedeId,
  });

  final String nombreDocente;
  final String correoUsuario;
  final bool esAlmuerzo;
  final bool isSedeNorte;
  final String? sedeId;

  AppBranding get _branding => AppBranding.fromLegacy(
        isSedeNorte: isSedeNorte,
        sedeId: sedeId,
      );

  void _mostrarDetalle(BuildContext context, Map<String, dynamic> reg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          'Detalle del Registro',
          style: TextStyle(
            color: _branding.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _itemDetalle('Docente:', nombreDocente),
            _itemDetalle(
              'Tipo:',
              reg['tipo'] ??
                  (esAlmuerzo
                      ? (reg['estado'] == 'finalizado' ? 'REGRESO' : 'SALIDA')
                      : 'No definido'),
            ),
            _itemDetalle('Estado:', reg['estado'] ?? 'N/A'),
            _itemDetalle(
              esAlmuerzo ? 'Salida:' : 'Hora:',
              reg['hora_marcada'] ?? reg['hora'] ?? reg['hora_salida'] ?? 'S/H',
            ),
            if (reg['hora_regreso'] != null)
              _itemDetalle('Regreso:', reg['hora_regreso']),
            _itemDetalle(
              'Referencia:',
              reg['horario_ref'] ?? (esAlmuerzo ? 'Jornada Almuerzo' : 'General'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cerrar',
              style: TextStyle(color: _branding.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemDetalle(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            etiqueta,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(width: 5),
          Expanded(child: Text(valor, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final FirebaseService service = FirebaseService();

    return Scaffold(
      backgroundColor: _branding.surface,
      appBar: AppBar(
        title: Text(
          esAlmuerzo ? 'Historial de Almuerzo' : 'Mis Registros de Asistencia',
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        backgroundColor: _branding.primary,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: esAlmuerzo
            ? service.obtenerHistorialAlmuerzo(correoUsuario)
            : service.obtenerHistorialAsistencias(nombreDocente),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: _branding.primary),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Text(
                esAlmuerzo
                    ? 'No hay registros de almuerzo.'
                    : 'No hay registros de asistencia.',
              ),
            );
          }

          final registros = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: registros.length,
            itemBuilder: (context, index) {
              final reg = registros[index];
              final horaMostrar = esAlmuerzo
                  ? (reg['hora_salida'] ?? 'S/H')
                  : (reg['hora_marcada'] ?? reg['hora'] ?? 'S/H');
              final tipoRegistro = esAlmuerzo
                  ? ((reg['estado'] == 'finalizado') ? 'REGRESO' : 'SALIDA')
                  : (reg['tipo'] ?? 'REGISTRO');
              final esEntrada = tipoRegistro == 'ENTRADA';
              final estadoTexto = (reg['estado'] ?? '').toString();
              final estadoNormalizado = estadoTexto.toLowerCase();
              final esEstadoPositivo = estadoNormalizado == 'a tiempo' ||
                  estadoNormalizado == 'completada' ||
                  estadoNormalizado == 'finalizado';

              return Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: ListTile(
                  onTap: () => _mostrarDetalle(context, reg),
                  leading: Icon(
                    esAlmuerzo
                        ? Icons.restaurant_rounded
                        : (esEntrada
                            ? Icons.login_rounded
                            : Icons.logout_rounded),
                    color: _branding.primary,
                  ),
                  title: Text(
                    tipoRegistro,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _branding.primary,
                    ),
                  ),
                  subtitle: Text(
                    esAlmuerzo
                        ? 'Salida: $horaMostrar'
                        : 'Hora: $horaMostrar',
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: esEstadoPositivo
                          ? Colors.green.withOpacity(0.1)
                          : Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      estadoTexto.toUpperCase(),
                      style: TextStyle(
                        color: esEstadoPositivo
                            ? Colors.green
                            : Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
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
