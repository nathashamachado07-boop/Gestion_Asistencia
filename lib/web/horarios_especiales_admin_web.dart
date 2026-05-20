import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_config.dart';
import '../models/app_branding.dart';
import '../services/firebase_service.dart';
import 'bootstrap_admin_ui.dart';

class HorariosEspecialesAdminWeb extends StatefulWidget {
  const HorariosEspecialesAdminWeb({
    super.key,
    this.isSedeNorte = false,
    this.sedeId,
    this.userData,
  });

  final bool isSedeNorte;
  final String? sedeId;
  final Map<String, dynamic>? userData;

  @override
  State<HorariosEspecialesAdminWeb> createState() =>
      _HorariosEspecialesAdminWebState();
}

class _HorariosEspecialesAdminWebState
    extends State<HorariosEspecialesAdminWeb> {
  static const int _toleranciaSalidaAntesMinutos = 5;
  static const int _toleranciaSalidaDespuesMinutos = 5;

  final FirebaseService _service = FirebaseService();
  late final TextEditingController _entradaController;
  late final TextEditingController _salidaController;
  late final TextEditingController _motivoController;

  DateTime _fechaSeleccionada = DateTime.now();
  bool _activo = true;
  bool _guardando = false;
  String? _editingDocId;

  String get _resolvedSedeId =>
      widget.sedeId ??
      (widget.isSedeNorte ? SedeAccess.sedeNorteId : SedeAccess.matrizId);
  AppBranding get _branding => AppBranding.fromSedeId(_resolvedSedeId);
  Color get _primary => _branding.primary;
  Color get _primaryDark => _branding.primaryDark;
  Color get _surface => _branding.surface;
  Color get _softAccent => _branding.softAccent;
  String get _responsable =>
      UserRoleAccess.displayNameForUser(widget.userData).trim();

  @override
  void initState() {
    super.initState();
    _entradaController = TextEditingController(text: '08:00');
    _salidaController = TextEditingController(text: '13:00');
    _motivoController = TextEditingController();
    _entradaController.addListener(_notificarCambioFormulario);
    _salidaController.addListener(_notificarCambioFormulario);
    _motivoController.addListener(_notificarCambioFormulario);
  }

  @override
  void dispose() {
    _entradaController.dispose();
    _salidaController.dispose();
    _motivoController.dispose();
    super.dispose();
  }

  void _notificarCambioFormulario() {
    if (mounted) {
      setState(() {});
    }
  }

  String _docIdParaFecha(DateTime fecha) {
    return '${_resolvedSedeId}_${DateFormat('yyyy-MM-dd').format(DateTime(fecha.year, fecha.month, fecha.day))}';
  }

  DateTime _extraerFecha(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return DateTime.now();
  }

  int? _horaTextoAMinutos(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (match == null) {
      return null;
    }

    final horas = int.tryParse(match.group(1) ?? '');
    final minutos = int.tryParse(match.group(2) ?? '');
    if (horas == null || minutos == null || horas > 23 || minutos > 59) {
      return null;
    }

    return (horas * 60) + minutos;
  }

  String _minutosAHora(int totalMinutos) {
    final minutosNormalizados = math.max(
      0,
      math.min((23 * 60) + 59, totalMinutos),
    );
    final horas = minutosNormalizados ~/ 60;
    final minutos = minutosNormalizados % 60;
    return '${horas.toString().padLeft(2, '0')}:${minutos.toString().padLeft(2, '0')}';
  }

  String _ventanaSalidaLabel(String horaSalida) {
    final salidaMin = _horaTextoAMinutos(horaSalida);
    if (salidaMin == null) {
      return '--:-- a --:--';
    }

    final inicio = _minutosAHora(salidaMin - _toleranciaSalidaAntesMinutos);
    final fin = _minutosAHora(salidaMin + _toleranciaSalidaDespuesMinutos);
    return '$inicio a $fin';
  }

  List<_HorarioEspecialView> _buildItems(List<QueryDocumentSnapshot> docs) {
    final items = <_HorarioEspecialView>[];

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (!SedeAccess.matchesSede(data, _resolvedSedeId)) {
        continue;
      }

      items.add(
        _HorarioEspecialView(
          docId: doc.id,
          fecha: _extraerFecha(data['fecha']),
          horaEntrada: (data['horaEntradaEspecial'] ?? '').toString().trim(),
          horaSalida: (data['horaSalidaEspecial'] ?? '').toString().trim(),
          motivo: (data['motivo'] ?? '').toString().trim(),
          activo: data['activo'] != false,
          actualizadoPor: (data['actualizadoPor'] ?? data['creadoPor'] ?? '')
              .toString()
              .trim(),
        ),
      );
    }

    items.sort((a, b) => b.fecha.compareTo(a.fecha));
    return items;
  }

  void _resetForm() {
    setState(() {
      _editingDocId = null;
      _fechaSeleccionada = DateTime.now();
      _entradaController.text = '08:00';
      _salidaController.text = '13:00';
      _motivoController.clear();
      _activo = true;
    });
  }

  void _cargarHorario(_HorarioEspecialView item) {
    setState(() {
      _editingDocId = item.docId;
      _fechaSeleccionada = item.fecha;
      _entradaController.text = item.horaEntrada;
      _salidaController.text = item.horaSalida;
      _motivoController.text = item.motivo;
      _activo = item.activo;
    });
  }

  Future<void> _seleccionarFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaSeleccionada,
      firstDate: DateTime(2025),
      lastDate: DateTime(2032),
      locale: const Locale('es'),
    );

    if (picked == null) {
      return;
    }

    setState(() => _fechaSeleccionada = picked);
  }

  Future<void> _seleccionarHora({
    required TextEditingController controller,
  }) async {
    final actual = controller.text.trim();
    final partes = actual.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(partes.isNotEmpty ? partes[0] : '') ?? 8,
      minute: int.tryParse(partes.length > 1 ? partes[1] : '') ?? 0,
    );

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (picked == null) {
      return;
    }

    controller.text =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _guardarHorarioEspecial() async {
    final motivo = _motivoController.text.trim();
    if (motivo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingrese el motivo del horario especial.'),
        ),
      );
      return;
    }

    setState(() => _guardando = true);
    final oldDocId = _editingDocId;
    final newDocId = _docIdParaFecha(_fechaSeleccionada);

    try {
      await _service.guardarHorarioEspecialSede(
        sedeId: _resolvedSedeId,
        fecha: _fechaSeleccionada,
        horaEntradaEspecial: _entradaController.text,
        horaSalidaEspecial: _salidaController.text,
        motivo: motivo,
        activo: _activo,
        registradoPor: _responsable,
        toleranciaSalidaAntesMinutos: _toleranciaSalidaAntesMinutos,
        toleranciaSalidaDespuesMinutos: _toleranciaSalidaDespuesMinutos,
      );

      if (oldDocId != null && oldDocId != newDocId) {
        await _service.eliminarHorarioEspecialSede(docId: oldDocId);
      }

      if (!mounted) return;
      _resetForm();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            oldDocId == null
                ? 'Horario especial guardado correctamente.'
                : 'Horario especial actualizado correctamente.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar el horario especial: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  Future<void> _cambiarEstado(_HorarioEspecialView item, bool value) async {
    try {
      await _service.actualizarHorarioEspecialSedeEstado(
        docId: item.docId,
        activo: value,
        actualizadoPor: _responsable,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo actualizar el horario especial: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _eliminarHorario(_HorarioEspecialView item) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Eliminar horario especial'),
        content: Text(
          'Se eliminara el horario especial del ${DateFormat('dd/MM/yyyy').format(item.fecha)} para ${SedeAccess.displayNameForId(_resolvedSedeId)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) {
      return;
    }

    try {
      await _service.eliminarHorarioEspecialSede(docId: item.docId);
      if (_editingDocId == item.docId) {
        _resetForm();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Horario especial eliminado correctamente.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo eliminar el horario especial: $e'),
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
                    _softAccent.withValues(alpha: 0.35),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('horarios_especiales')
                .where('sedeId', isEqualTo: _resolvedSedeId)
                .snapshots(),
            builder: (context, snapshot) {
              final items = _buildItems(
                snapshot.data?.docs ?? const <QueryDocumentSnapshot>[],
              );

              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHero(),
                    const SizedBox(height: 22),
                    _buildFormCard(),
                    const SizedBox(height: 22),
                    if (items.isEmpty)
                      _buildEmptyState()
                    else
                      _buildList(items),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return BootstrapAdminHero(
      branding: _branding,
      icon: Icons.event_available_rounded,
      eyebrow: 'Jornadas especiales',
      title: 'Horarios especiales de la sede',
      subtitle:
          'Crea jornadas especiales por fecha para ${SedeAccess.displayNameForId(_resolvedSedeId)}. Cuando una salida ocurra dentro del horario especial, se registrara como salida anticipada autorizada en reportes de asistencia.',
    );
  }

  Widget _buildFormCard() {
    final fechaLabel = DateFormat('dd/MM/yyyy').format(_fechaSeleccionada);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _primary.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: _primary.withValues(alpha: 0.07),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _editingDocId == null
                          ? 'Nuevo horario especial'
                          : 'Editar horario especial',
                      style: TextStyle(
                        color: _primaryDark,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Este horario aplica a todos los departamentos de la sede activa.',
                      style: TextStyle(
                        color: _primaryDark.withValues(alpha: 0.68),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (_editingDocId != null)
                TextButton.icon(
                  onPressed: _guardando ? null : _resetForm,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Limpiar'),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _actionField(
                width: 220,
                label: 'Fecha',
                value: fechaLabel,
                icon: Icons.calendar_month_outlined,
                onTap: _seleccionarFecha,
              ),
              _actionField(
                width: 180,
                label: 'Entrada especial',
                value: _entradaController.text,
                icon: Icons.login_rounded,
                onTap: () => _seleccionarHora(controller: _entradaController),
              ),
              _actionField(
                width: 180,
                label: 'Salida especial',
                value: _salidaController.text,
                icon: Icons.logout_rounded,
                onTap: () => _seleccionarHora(controller: _salidaController),
              ),
              SizedBox(
                width: 260,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _activo,
                  title: const Text('Horario activo'),
                  subtitle: Text(_activo ? 'Si' : 'No'),
                  activeThumbColor: _primary,
                  onChanged: (value) => setState(() => _activo = value),
                ),
              ),
              SizedBox(
                width: 620,
                child: TextField(
                  controller: _motivoController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Motivo institucional',
                    hintText:
                        'Ej: Dia del trabajador, reunion institucional, evento de sede...',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildPreviewCard(),
          const SizedBox(height: 18),
          Row(
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _primaryDark),
                onPressed: _guardando ? null : _guardarHorarioEspecial,
                icon: _guardando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _editingDocId == null
                            ? Icons.add_task_rounded
                            : Icons.save_as_rounded,
                      ),
                label: Text(
                  _guardando
                      ? 'Guardando...'
                      : _editingDocId == null
                      ? 'Guardar horario especial'
                      : 'Actualizar horario especial',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard() {
    final motivo = _motivoController.text.trim();
    final fechaResumen = DateFormat('dd/MM/yyyy').format(_fechaSeleccionada);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _primary.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen previo',
            style: TextStyle(
              color: _primaryDark,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Asi se guardara el horario especial antes de confirmar.',
            style: TextStyle(
              color: _primaryDark.withValues(alpha: 0.65),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _summaryPill(Icons.calendar_today_outlined, fechaResumen),
              _summaryPill(
                Icons.schedule_outlined,
                '${_entradaController.text.trim()} a ${_salidaController.text.trim()}',
              ),
              _summaryPill(
                Icons.timer_outlined,
                'Salida valida: ${_ventanaSalidaLabel(_salidaController.text)}',
              ),
              _summaryPill(
                _activo ? Icons.verified_outlined : Icons.pause_circle_outline,
                _activo
                    ? 'Se guardara como activo'
                    : 'Se guardara como inactivo',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              motivo.isEmpty
                  ? 'Agrega un motivo institucional para completar el resumen antes de guardar.'
                  : motivo,
              style: TextStyle(
                color: motivo.isEmpty
                    ? _primaryDark.withValues(alpha: 0.55)
                    : _primaryDark.withValues(alpha: 0.82),
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _primary.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: _primary.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(
              Icons.event_busy_outlined,
              color: _primary.withValues(alpha: 0.70),
              size: 36,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Todavia no hay horarios especiales para esta sede.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _primaryDark,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Cuando necesites una salida institucional anticipada para toda la sede, registrala aqui.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _primaryDark.withValues(alpha: 0.60),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<_HorarioEspecialView> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: _primary,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Programaciones registradas',
              style: TextStyle(
                color: _primaryDark,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${items.length}',
                style: TextStyle(
                  color: _primaryDark,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.98),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _primary.withValues(alpha: 0.12)),
                boxShadow: [
                  BoxShadow(
                    color: _primary.withValues(alpha: 0.06),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat(
                            'EEEE, dd MMMM yyyy',
                            'es',
                          ).format(item.fecha),
                          style: TextStyle(
                            color: _primaryDark,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            _infoPill(
                              Icons.access_time_rounded,
                              '${item.horaEntrada} a ${item.horaSalida}',
                            ),
                            _infoPill(
                              Icons.timer_outlined,
                              'Salida valida: ${_ventanaSalidaLabel(item.horaSalida)}',
                            ),
                            _infoPill(Icons.apartment_rounded, 'Toda la sede'),
                            _infoPill(
                              item.activo
                                  ? Icons.verified_outlined
                                  : Icons.pause_circle_outline,
                              item.activo ? 'Activo' : 'Inactivo',
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          item.motivo,
                          style: TextStyle(
                            color: _primaryDark.withValues(alpha: 0.78),
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (item.actualizadoPor.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Actualizado por: ${item.actualizadoPor}',
                            style: TextStyle(
                              color: _primaryDark.withValues(alpha: 0.55),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Switch(
                        value: item.activo,
                        activeThumbColor: _primary,
                        onChanged: (value) => _cambiarEstado(item, value),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _cargarHorario(item),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Editar'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                        ),
                        onPressed: () => _eliminarHorario(item),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                        ),
                        label: const Text('Eliminar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _actionField({
    required double width,
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: _surface.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _primary.withValues(alpha: 0.16)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: _primaryDark),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: _primaryDark.withValues(alpha: 0.58),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: TextStyle(
                        color: _primaryDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: _primaryDark),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: _primaryDark,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _primary.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _primaryDark),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: _primaryDark,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _HorarioEspecialView {
  const _HorarioEspecialView({
    required this.docId,
    required this.fecha,
    required this.horaEntrada,
    required this.horaSalida,
    required this.motivo,
    required this.activo,
    required this.actualizadoPor,
  });

  final String docId;
  final DateTime fecha;
  final String horaEntrada;
  final String horaSalida;
  final String motivo;
  final bool activo;
  final String actualizadoPor;
}
