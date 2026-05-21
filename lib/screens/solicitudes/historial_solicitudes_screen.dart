import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/app_branding.dart';
import '../../models/solicitud_model.dart';
import '../../services/firebase_service.dart';

class HistorialSolicitudesScreen extends StatefulWidget {
  final String nombreDocente;
  final String? correoUsuario;
  final bool isSedeNorte;
  final String? sedeId;

  const HistorialSolicitudesScreen({
    super.key,
    required this.nombreDocente,
    this.correoUsuario,
    this.isSedeNorte = false,
    this.sedeId,
  });

  @override
  State<HistorialSolicitudesScreen> createState() =>
      _HistorialSolicitudesScreenState();
}

class _HistorialSolicitudesScreenState
    extends State<HistorialSolicitudesScreen> {
  final FirebaseService service = FirebaseService();
  late Future<List<Solicitud>> _solicitudesFuture;
  AppBranding get _branding => AppBranding.fromLegacy(
    isSedeNorte: widget.isSedeNorte,
    sedeId: widget.sedeId,
  );

  @override
  void initState() {
    super.initState();
    _solicitudesFuture = _cargarSolicitudes();
  }

  Future<List<Solicitud>> _cargarSolicitudes() {
    return service.obtenerMisSolicitdes(
      widget.nombreDocente,
      correo: widget.correoUsuario,
      sedeId: widget.sedeId ?? _branding.sedeId,
    );
  }

  Future<void> _refrescarSolicitudes() async {
    final nuevaConsulta = _cargarSolicitudes();
    setState(() {
      _solicitudesFuture = nuevaConsulta;
    });
    await nuevaConsulta;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(color: Colors.white)),

          Column(
            children: [
              _buildEncabezadoHistorial(),
              const SizedBox(height: 10),

              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refrescarSolicitudes,
                  color: _branding.primary,
                  child: FutureBuilder<List<Solicitud>>(
                    future: _solicitudesFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 120),
                            Center(
                              child: CircularProgressIndicator(
                                color: _branding.primary,
                              ),
                            ),
                          ],
                        );
                      }

                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 100),
                            Center(
                              child: Text(
                                "No tienes solicitudes registradas.",
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        );
                      }

                      final solicitudes = snapshot.data!;

                      return ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.all(16),
                        itemCount: solicitudes.length,
                        itemBuilder: (context, index) {
                          final sol = solicitudes[index];
                          final numeroFormulario =
                              (sol.numFormulario ?? '').trim().isEmpty
                              ? '00001'
                              : (int.tryParse(
                                      sol.numFormulario!.trim(),
                                    )?.toString().padLeft(5, '0') ??
                                    sol.numFormulario!.trim());

                          Color estadoColor;
                          switch (sol.estado.toLowerCase()) {
                            case 'aprobado':
                              estadoColor = Colors.green;
                              break;
                            case 'rechazado':
                              estadoColor = Colors.red;
                              break;
                            default:
                              estadoColor = Colors.orange;
                          }

                          return Card(
                            elevation: 8,
                            margin: const EdgeInsets.only(bottom: 12),
                            color: Colors.white,
                            shadowColor: _branding.primary.withValues(
                              alpha: 0.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _branding.primary.withValues(
                                  alpha: 0.1,
                                ),
                                child: Icon(
                                  sol.tipo == 'Vacaciones'
                                      ? Icons.beach_access
                                      : Icons.assignment_ind,
                                  color: _branding.primary,
                                ),
                              ),
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _branding.primary.withValues(
                                        alpha: 0.10,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      'No. $numeroFormulario',
                                      style: TextStyle(
                                        color: _branding.primary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    "${sol.tipo} - ${DateFormat('dd/MM/yyyy').format(sol.fechaInicio)}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text("Motivo: ${sol.motivo}"),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: estadoColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  sol.estado.toUpperCase(),
                                  style: TextStyle(
                                    color: estadoColor,
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
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEncabezadoHistorial() {
    return Container(
      height: 160,
      padding: const EdgeInsets.only(top: 50, left: 10, right: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_branding.primary, _branding.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(35)),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Image.asset(
                _branding.logoSmall,
                height: _branding.mobileHeaderLogoHeight,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                    size: 22,
                  ),
                  onPressed: () => Navigator.pop(
                    context,
                  ), // Ahora regresará al formulario sin pantalla negra
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            "MIS SOLICITUDES",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
