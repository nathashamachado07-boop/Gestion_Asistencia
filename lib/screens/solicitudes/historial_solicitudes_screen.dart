import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/app_branding.dart';
import '../../models/solicitud_model.dart';
import '../../services/firebase_service.dart';

class HistorialSolicitudesScreen extends StatefulWidget {
  final String nombreDocente;
  final bool isSedeNorte;
  final String? sedeId;

  const HistorialSolicitudesScreen({
    super.key,
    required this.nombreDocente,
    this.isSedeNorte = false,
    this.sedeId,
  });

  @override
  State<HistorialSolicitudesScreen> createState() => _HistorialSolicitudesScreenState();
}

class _HistorialSolicitudesScreenState extends State<HistorialSolicitudesScreen> {
  final FirebaseService service = FirebaseService();
  AppBranding get _branding => AppBranding.fromLegacy(
        isSedeNorte: widget.isSedeNorte,
        sedeId: widget.sedeId,
      );
  
  Future<void> _refrescarSolicitudes() async {
    setState(() {}); 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(decoration: BoxDecoration(color: _branding.background)),

          // PATRÓN DE "S"
          _buildPatronS(),

          // LOGO GRANDE CENTRAL DE FONDO
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
              _buildEncabezadoHistorial(),
              const SizedBox(height: 10),

              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refrescarSolicitudes,
                  color: _branding.primary,
                  child: FutureBuilder<List<Solicitud>>(
                    future: service.obtenerMisSolicitdes(widget.nombreDocente), 
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator(color: _branding.primary));
                      }

                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return ListView(
                          children: const [
                            SizedBox(height: 100),
                            Center(child: Text("No tienes solicitudes registradas.", style: TextStyle(fontWeight: FontWeight.w500))),
                          ],
                        );
                      }

                      final solicitudes = snapshot.data!;

                      return ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: solicitudes.length,
                        itemBuilder: (context, index) {
                          final sol = solicitudes[index];
                          
                          Color estadoColor;
                          switch (sol.estado.toLowerCase()) {
                            case 'aprobado': estadoColor = Colors.green; break;
                            case 'rechazado': estadoColor = Colors.red; break;
                            default: estadoColor = Colors.orange; 
                          }

                          return Card(
                            elevation: 3,
                            margin: const EdgeInsets.only(bottom: 12),
                            color: Colors.white.withOpacity(0.88),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _branding.primary.withOpacity(0.1),
                                child: Icon(
                                  sol.tipo == 'Vacaciones' ? Icons.beach_access : Icons.assignment_ind,
                                  color: _branding.primary,
                                ),
                              ),
                              title: Text("${sol.tipo} - ${DateFormat('dd/MM/yyyy').format(sol.fechaInicio)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text("Motivo: ${sol.motivo}"),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(color: estadoColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                                child: Text(sol.estado.toUpperCase(), style: TextStyle(color: estadoColor, fontWeight: FontWeight.bold, fontSize: 10)),
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
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 22),
                  onPressed: () => Navigator.pop(context), // Ahora regresará al formulario sin pantalla negra
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text("MIS SOLICITUDES", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildPatronS() {
    return Positioned.fill(
      child: LayoutBuilder(builder: (context, constraints) {
        return Opacity(
          opacity: 0.13,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5),
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.all(15.0),
              child: Image.asset(
                _branding.logoSmall,
                color: Colors.white,
                width: _branding.mobilePatternLogoSize,
                height: _branding.mobilePatternLogoSize,
                fit: BoxFit.contain,
              ),
            ),
          ),
        );
      }),
    );
  }
}
