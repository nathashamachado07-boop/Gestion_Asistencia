import 'package:flutter/material.dart';

class NotificacionesScreen extends StatefulWidget {
  final String correoUsuario;

  const NotificacionesScreen({super.key, required this.correoUsuario});

  @override
  State<NotificacionesScreen> createState() => _NotificacionesScreenState();
}

class _NotificacionesScreenState extends State<NotificacionesScreen> {
  // Colores corporativos del ISTS
  static const Color _istsColor = Color(0xFF467879);
  static const Color _fondoSuave = Color(0xFFF2F5F5);

  bool _cargando = false;

  Future<void> _refrescarNotificaciones() async {
    setState(() => _cargando = true);
    // Simulación de recarga de datos
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) setState(() => _cargando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fondoSuave,
      appBar: AppBar(
        title: const Text(
          "AVISOS Y NOTIFICACIONES",
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: _istsColor,
        centerTitle: true,
        elevation: 0,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: _istsColor))
          : RefreshIndicator(
              onRefresh: _refrescarNotificaciones,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Comunicados Recientes",
                      style: TextStyle(color: _istsColor, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 15),
                    
                    _buildAvisoCard(
                      "Cambio de Horario",
                      "Estimados, se les recuerda que esta semana el bloque de almuerzo inicia 15 min antes.",
                      Icons.campaign_rounded,
                      "Hace 2 horas",
                    ),
                    const SizedBox(height: 15),
                    
                    _buildAvisoCard(
                      "Mantenimiento del Sistema",
                      "El día sábado el sistema de asistencia entrará en mantenimiento de 08:00 a 12:00.",
                      Icons.settings_suggest_rounded,
                      "Ayer",
                    ),
                    const SizedBox(height: 15),
                    
                    _buildAvisoCard(
                      "Evento Institucional",
                      "No olvides participar en la casa abierta de Software este viernes en el patio principal.",
                      Icons.event_available_rounded,
                      "Hace 3 días",
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAvisoCard(String titulo, String mensaje, IconData icono, String tiempo) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        border: const Border(left: BorderSide(color: _istsColor, width: 5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _istsColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icono, color: _istsColor, size: 24),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(tiempo, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  mensaje,
                  style: TextStyle(color: Colors.grey[700], fontSize: 13, height: 1.4),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}