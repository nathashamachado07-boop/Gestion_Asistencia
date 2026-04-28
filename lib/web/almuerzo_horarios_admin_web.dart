import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/app_branding.dart';
import '../services/firebase_service.dart';

class AlmuerzoHorariosAdminWeb extends StatelessWidget {
  const AlmuerzoHorariosAdminWeb({
    super.key,
    this.isSedeNorte = false,
    this.sedeId,
  });

  final bool isSedeNorte;
  final String? sedeId;

  static const List<_AlmuerzoSlotOption> _almuerzoSlots = [
    _AlmuerzoSlotOption(
      inicio: '13:00',
      fin: '13:45',
      label: '13:00 a 13:45',
    ),
    _AlmuerzoSlotOption(
      inicio: '13:45',
      fin: '14:30',
      label: '13:45 a 14:30',
    ),
  ];

  static final FirebaseService _service = FirebaseService();

  String get _resolvedSedeId =>
      sedeId ??
      (isSedeNorte ? SedeAccess.sedeNorteId : SedeAccess.matrizId);

  AppBranding get _branding => AppBranding.fromSedeId(_resolvedSedeId);

  Color get _primary => _branding.primary;
  Color get _primaryDark => _branding.primaryDark;
  Color get _surface => _branding.surface;
  Color get _softAccent => _branding.softAccent;

  bool _matchesCurrentSede(Map<String, dynamic> data) {
    return SedeAccess.matchesSede(data, _resolvedSedeId);
  }

  bool _isAdministrativeStaff(Map<String, dynamic> data) {
    final rol = (data['rol'] ?? '').toString().trim().toLowerCase();
    return rol == 'administrativo';
  }

  List<_AdministrativoAlmuerzoView> _buildAdministrativos(
    List<QueryDocumentSnapshot> usuariosDocs,
  ) {
    final administrativos = <_AdministrativoAlmuerzoView>[];

    for (final doc in usuariosDocs) {
      final data = doc.data() as Map<String, dynamic>;
      if (!_isAdministrativeStaff(data) || !_matchesCurrentSede(data)) {
        continue;
      }

      administrativos.add(
        _AdministrativoAlmuerzoView(
          docId: doc.id,
          nombre: (data['nombre'] ?? 'Sin nombre').toString(),
          correo: (data['correo'] ?? '').toString(),
          horarioAsignado:
              (data['almuerzo_horario_label'] ?? 'Sin asignar').toString(),
        ),
      );
    }

    administrativos.sort((a, b) => a.nombre.compareTo(b.nombre));
    return administrativos;
  }

  Future<void> _asignarHorarioAlmuerzo({
    required BuildContext context,
    required _AdministrativoAlmuerzoView administrativo,
    required _AlmuerzoSlotOption slot,
  }) async {
    try {
      await _service.asignarHorarioAlmuerzoAdministrativo(
        usuarioDocId: administrativo.docId,
        correo: administrativo.correo,
        nombre: administrativo.nombre,
        sedeId: _resolvedSedeId,
        sedeNombre: SedeAccess.displayNameForId(_resolvedSedeId),
        horaInicio: slot.inicio,
        horaFin: slot.fin,
        asignadoPor: 'RRHH',
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Horario de almuerzo ${slot.label} asignado a ${administrativo.nombre}.',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo asignar el horario: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _surface,
                    Colors.white,
                    _softAccent.withOpacity(0.42),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          Positioned(
            right: -40,
            bottom: -20,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.05,
                child: Image.asset(
                  _branding.logoWatermark,
                  width: 320,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('usuarios').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final administrativos = _buildAdministrativos(
                snapshot.data?.docs ?? <QueryDocumentSnapshot>[],
              );

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeroHeader(administrativos.length),
                    const SizedBox(height: 24),
                    if (administrativos.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 24,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.94),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: _primary.withOpacity(0.12)),
                        ),
                        child: Text(
                          'No hay administrativos registrados en ${SedeAccess.displayNameForId(_resolvedSedeId)} para asignar horarios de almuerzo.',
                          style: TextStyle(
                            color: _primaryDark.withOpacity(0.76),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 18,
                        runSpacing: 18,
                        children: administrativos
                            .map(
                              (administrativo) => _buildAdministrativoCard(
                                context,
                                administrativo,
                              ),
                            )
                            .toList(),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeroHeader(int totalAdministrativos) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_primaryDark, _primary, _primary.withOpacity(0.86)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.18),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
            child: const Icon(
              Icons.schedule_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Asignar horarios de almuerzo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Seleccione un bloque de almuerzo para cada administrativo de ${SedeAccess.displayNameForId(_resolvedSedeId)}. Cada asignacion se guarda por sede y envia una notificacion al usuario.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    'Administrativos disponibles: $totalAdministrativos',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdministrativoCard(
    BuildContext context,
    _AdministrativoAlmuerzoView administrativo,
  ) {
    return Container(
      width: 390,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white,
            _surface.withOpacity(0.78),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _primary.withOpacity(0.22), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.12),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              color: _primary.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border(
                bottom: BorderSide(color: _primary.withOpacity(0.10)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _primary.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: _primary.withOpacity(0.18)),
                  ),
                  child: Center(
                    child: Text(
                      administrativo.nombre.isEmpty
                          ? 'A'
                          : administrativo.nombre.substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        color: _primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        administrativo.nombre,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E2937),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        administrativo.correo,
                        style: TextStyle(
                          color: _primaryDark.withOpacity(0.78),
                          fontWeight: FontWeight.w500,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _primary.withOpacity(0.14)),
                    boxShadow: [
                      BoxShadow(
                        color: _primary.withOpacity(0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lunch_dining_outlined,
                        color: _primary,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Horario actual: ${administrativo.horarioAsignado}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF324553),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Seleccionar bloque',
                  style: TextStyle(
                    color: _primaryDark.withOpacity(0.75),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _almuerzoSlots
                      .map(
                        (slot) => OutlinedButton.icon(
                          onPressed: () => _asignarHorarioAlmuerzo(
                            context: context,
                            administrativo: administrativo,
                            slot: slot,
                          ),
                          icon: const Icon(Icons.schedule_rounded, size: 18),
                          label: Text(slot.label),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _primary,
                            backgroundColor: Colors.white.withOpacity(0.9),
                            side: BorderSide(color: _primary.withOpacity(0.24)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _primary.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF415160),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdministrativoAlmuerzoView {
  const _AdministrativoAlmuerzoView({
    required this.docId,
    required this.nombre,
    required this.correo,
    required this.horarioAsignado,
  });

  final String docId;
  final String nombre;
  final String correo;
  final String horarioAsignado;
}

class _AlmuerzoSlotOption {
  const _AlmuerzoSlotOption({
    required this.inicio,
    required this.fin,
    required this.label,
  });

  final String inicio;
  final String fin;
  final String label;
}
