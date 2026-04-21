import 'package:flutter/material.dart';

import '../models/app_branding.dart';

class NotificacionesScreen extends StatefulWidget {
  const NotificacionesScreen({
    super.key,
    required this.correoUsuario,
    this.isSedeNorte = false,
    this.sedeId,
  });

  final String correoUsuario;
  final bool isSedeNorte;
  final String? sedeId;

  @override
  State<NotificacionesScreen> createState() => _NotificacionesScreenState();
}

class _NotificacionesScreenState extends State<NotificacionesScreen> {
  bool _cargando = false;

  AppBranding get _branding => AppBranding.fromLegacy(
        isSedeNorte: widget.isSedeNorte,
        sedeId: widget.sedeId,
      );

  Future<void> _refrescarNotificaciones() async {
    setState(() => _cargando = true);
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) setState(() => _cargando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _branding.background,
      body: Stack(
        children: [
          Container(color: _branding.background),
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
                        opacity: 0.2,
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
          Center(
            child: Opacity(
              opacity: 0.12,
              child: ShaderMask(
                shaderCallback: (rect) {
                  return LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _branding.primary.withOpacity(0.8),
                      Colors.transparent,
                    ],
                  ).createShader(rect);
                },
                blendMode: BlendMode.srcATop,
                child: Image.asset(
                  _branding.logoWatermark,
                  width: MediaQuery.of(context).size.width *
                      _branding.mobileWatermarkWidthFactor,
                  fit: BoxFit.contain,
                ),
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
                      'AVISOS Y NOTIFICACIONES',
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
                child: _cargando
                    ? Center(
                        child: CircularProgressIndicator(color: _branding.primary),
                      )
                    : RefreshIndicator(
                        onRefresh: _refrescarNotificaciones,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Comunicados Recientes',
                                style: TextStyle(
                                  color: _branding.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 15),
                              _buildAvisoCard(
                                'Cambio de Horario',
                                'Estimados, se les recuerda que esta semana el bloque de almuerzo inicia 15 min antes.',
                                Icons.campaign_rounded,
                                'Hace 2 horas',
                              ),
                              const SizedBox(height: 15),
                              _buildAvisoCard(
                                'Mantenimiento del Sistema',
                                'El dia sabado el sistema de asistencia entrara en mantenimiento de 08:00 a 12:00.',
                                Icons.settings_suggest_rounded,
                                'Ayer',
                              ),
                              const SizedBox(height: 15),
                              _buildAvisoCard(
                                'Evento Institucional',
                                'No olvides participar en la casa abierta este viernes.',
                                Icons.event_available_rounded,
                                'Hace 3 dias',
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvisoCard(
    String titulo,
    String mensaje,
    IconData icono,
    String tiempo,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: _branding.primary.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border(left: BorderSide(color: _branding.primary, width: 5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _branding.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icono, color: _branding.primary, size: 24),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      tiempo,
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  mensaje,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
