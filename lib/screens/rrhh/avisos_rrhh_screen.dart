import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_config.dart';
import '../../models/app_branding.dart';
import 'rrhh_sede_selector.dart';

class AvisosRRHHScreen extends StatelessWidget {
  const AvisosRRHHScreen({super.key, this.userData});

  final Map<String, dynamic>? userData;

  @override
  Widget build(BuildContext context) {
    return RRHHSedeSelectorPage(
      allowedSedeIds: MatrizApprovalFlow.allowedSedeIdsForUser(userData),
      title: 'Avisos por sede',
      subtitle:
          'Selecciona una sede para enviar comunicados y revisar solo los avisos de ese personal.',
      icon: Icons.campaign_outlined,
      onSelected: (option) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _AvisosSedeDetalle(option: option),
          ),
        );
      },
    );
  }
}

class _AvisosSedeDetalle extends StatelessWidget {
  const _AvisosSedeDetalle({
    required this.option,
  });

  final RRHHSedeOption option;

  AppBranding get _branding => option.branding;

  Future<void> _enviarAviso(
    BuildContext context, {
    required String titulo,
    required String mensaje,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('avisos').add({
        'titulo': titulo,
        'mensaje': mensaje,
        'fecha': DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
        'timestamp': FieldValue.serverTimestamp(),
        'sedeId': option.sedeId,
        'sede': option.title,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Aviso enviado a ${option.title}: $titulo'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al enviar el aviso.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _branding.primary,
        elevation: 0,
        title: Text(
          'Avisos - ${option.title}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_branding.primary, _branding.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            child: Text(
              'Los comunicados que envies aqui quedaran asociados solo a ${option.title}.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.92),
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Comunicados rapidos',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF22343D),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildBotonAviso(
                    context,
                    titulo: 'Mañana no se trabaja',
                    mensaje:
                        'Se comunica al personal de esta sede que mañana se suspenden las actividades laborales.',
                    icono: Icons.event_busy_outlined,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(height: 12),
                  _buildBotonAviso(
                    context,
                    titulo: 'Reunión general',
                    mensaje:
                        'Se convoca al personal de esta sede a una reunión obligatoria en el horario establecido por RRHH.',
                    icono: Icons.groups_outlined,
                    color: _branding.primary,
                  ),
                  const SizedBox(height: 12),
                  _buildBotonAviso(
                    context,
                    titulo: 'Horario de almuerzo activado',
                    mensaje:
                        'Se habilita el registro de almuerzo para el personal de esta sede.',
                    icono: Icons.restaurant_outlined,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Avisos recientes de esta sede',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF22343D),
                    ),
                  ),
                  const SizedBox(height: 14),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('avisos')
                        .orderBy('timestamp', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = (snapshot.data?.docs ?? <QueryDocumentSnapshot>[])
                          .where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final destinatario =
                            (data['destinatarioCorreo'] ?? '').toString().trim();
                        return destinatario.isEmpty &&
                            SedeAccess.matchesSede(data, option.sedeId);
                      }).toList();

                      if (docs.isEmpty) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Todavia no hay avisos registrados para esta sede.',
                            style: TextStyle(
                              color: Color(0xFF53646D),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }

                      return Column(
                        children: docs.take(8).map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return _buildAvisoCard(
                            titulo: (data['titulo'] ?? 'Sin titulo').toString(),
                            mensaje: (data['mensaje'] ?? '').toString(),
                            fecha: (data['fecha'] ?? '').toString(),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBotonAviso(
    BuildContext context, {
    required String titulo,
    required String mensaje,
    required IconData icono,
    required Color color,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
          backgroundColor: Colors.white,
          foregroundColor: color,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: color.withOpacity(0.24)),
          ),
        ),
        onPressed: () => _confirmarEnvio(
          context,
          titulo: titulo,
          mensaje: mensaje,
        ),
        icon: Icon(icono, size: 24),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            titulo.toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }

  void _confirmarEnvio(
    BuildContext context, {
    required String titulo,
    required String mensaje,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Enviar aviso?'),
        content: Text('El aviso "$titulo" se enviará solo a ${option.title}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _branding.primary),
            onPressed: () {
              Navigator.pop(ctx);
              _enviarAviso(
                context,
                titulo: titulo,
                mensaje: mensaje,
              );
            },
            child: const Text(
              'Enviar',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvisoCard({
    required String titulo,
    required String mensaje,
    required String fecha,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _branding.primary.withOpacity(0.15),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                fecha,
                style: const TextStyle(
                  color: Colors.black45,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            mensaje,
            style: const TextStyle(
              color: Colors.black54,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
