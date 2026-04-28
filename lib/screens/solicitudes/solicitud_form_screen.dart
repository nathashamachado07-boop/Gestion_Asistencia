import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../models/app_branding.dart';
import '../../models/solicitud_model.dart';
import '../../services/firebase_service.dart';
import 'historial_solicitudes_screen.dart';

class SolicitudFormScreen extends StatefulWidget {
  final String nombreDocente;
  final String? correoUsuario;
  final bool isSedeNorte;
  final String? sedeId;

  const SolicitudFormScreen({
    super.key,
    required this.nombreDocente,
    this.correoUsuario,
    this.isSedeNorte = false,
    this.sedeId,
  });

  @override
  State<SolicitudFormScreen> createState() => _SolicitudFormScreenState();
}

class _SolicitudFormScreenState extends State<SolicitudFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseService _firebaseService = FirebaseService();
  late TextEditingController _nombreController;
  AppBranding get _branding => AppBranding.fromLegacy(
        isSedeNorte: widget.isSedeNorte,
        sedeId: widget.sedeId,
      );
  bool get _isWebLayout => kIsWeb;

  String _tipoSeleccionado = 'Permiso';
  String _motivo = '';
  DateTime _fechaSolicitud = DateTime.now();
  DateTime _fechaInicio = DateTime.now();
  DateTime _fechaFin = DateTime.now();

  String _horasPermiso = '';
  String _modoPermiso = 'horas';
  String _rangoHorasPermiso = '';
  String _descontarDe = 'Vacaciones';
  int _cantidadHorasPermiso = 0;
  int _cantidadDiasPermiso = 1;

  int _diasDisponibles = 0;
  int _diasATomar = 0;

  int get _saldoDiasVacaciones => _diasDisponibles - _diasATomar;
  int get _anioVacaciones => _fechaInicio.year;
  DateTime get _fechaRetornoVacaciones => _fechaFin.add(const Duration(days: 1));

  String _construirDescripcionPermiso() {
    if (_modoPermiso == 'dias') {
      final fechaDesde = DateFormat('dd/MM/yyyy').format(_fechaInicio);
      final fechaHasta = DateFormat('dd/MM/yyyy').format(_fechaFin);
      final diasTexto = _cantidadDiasPermiso == 1 ? '1 dia' : '$_cantidadDiasPermiso dias';
      return 'Por dias: $diasTexto ($fechaDesde al $fechaHasta)';
    }

    final horasTexto = _cantidadHorasPermiso == 1 ? '1 hora' : '$_cantidadHorasPermiso horas';
    if (_rangoHorasPermiso.trim().isEmpty) {
      return 'Por horas: $horasTexto';
    }
    return 'Por horas: $horasTexto | ${_rangoHorasPermiso.trim()}';
  }

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.nombreDocente);
  }

  @override
  void dispose() {
    _nombreController.dispose();
    super.dispose();
  }

  Future<void> _seleccionarFecha(BuildContext context, String tipo) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2027),
    );
    if (picked != null) {
      setState(() {
        if (tipo == 'solicitud') _fechaSolicitud = picked;
        if (tipo == 'inicio') {
          _fechaInicio = picked;
          if (_fechaFin.isBefore(_fechaInicio)) {
            _fechaFin = _fechaInicio;
          }
        }
        if (tipo == 'fin') {
          _fechaFin = picked.isBefore(_fechaInicio) ? _fechaInicio : picked;
        }
      });
    }
  }

  void _enviarFormulario() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      final descripcionPermiso =
          _tipoSeleccionado == 'Permiso' ? _construirDescripcionPermiso() : null;
      final fechaFinSolicitud = _tipoSeleccionado == 'Permiso' && _modoPermiso == 'horas'
          ? _fechaInicio
          : _fechaFin;

      Solicitud nuevaSolicitud = Solicitud(
        id: '',
        colaborador: _nombreController.text,
        motivo: _motivo,
        tipo: _tipoSeleccionado,
        fechaInicio: _fechaInicio,
        fechaFin: fechaFinSolicitud,
        estado: 'pendiente',
        horasPermiso: descripcionPermiso,
        descontarDe: _tipoSeleccionado == 'Permiso' ? _descontarDe : null,
        diasDisponibles: _tipoSeleccionado == 'Vacaciones' ? _diasDisponibles : null,
        diasATomar: _tipoSeleccionado == 'Vacaciones' ? _diasATomar : null,
        fechaSolicitud: _fechaSolicitud,
        anioVacaciones: _tipoSeleccionado == 'Vacaciones' ? _anioVacaciones : null,
        diasAcumulados: _tipoSeleccionado == 'Vacaciones' ? _diasDisponibles : null,
        saldoDias: _tipoSeleccionado == 'Vacaciones' ? _saldoDiasVacaciones : null,
        fechaRetorno: _tipoSeleccionado == 'Vacaciones' ? _fechaRetornoVacaciones : null,
        sedeId: _branding.sedeId,
        sede: _branding.sedeName,
        colaboradorCorreo: widget.correoUsuario,
      );

      try {
        await _firebaseService.enviarSolicitud(nuevaSolicitud);
        _mostrarDialogoExito(nuevaSolicitud);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e')));
      }
    }
  }

  void _mostrarDialogoExito(Solicitud sol) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 60),
            const SizedBox(height: 15),
            const Text("¡Solicitud Enviada!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 20),
            Card(
              color: Colors.grey[100],
              child: Padding(
                padding: const EdgeInsets.all(15.0),
                child: Column(
                  children: [
                    Text("Tipo: ${sol.tipo}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Divider(),
                    Text("Estado: ${sol.estado.toUpperCase()}", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                    Text("Fecha: ${DateFormat('dd/MM/yyyy').format(sol.fechaInicio)}"),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _branding.primary),
              onPressed: () {
                Navigator.pop(context); 
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HistorialSolicitudesScreen(
                      nombreDocente: widget.nombreDocente,
                      sedeId: _branding.sedeId,
                    ),
                  ),
                );
              },
              child: const Text("Ver Historial", style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          _isWebLayout ? const Color(0xFFF4F7F8) : _branding.background,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: _isWebLayout
                  ? const Color(0xFFF4F7F8)
                  : _branding.background,
            ),
          ),
          if (!_isWebLayout) _buildPatronS(),
          if (!_isWebLayout)
            Center(
              child: Opacity(
                opacity: 0.12,
                child: Image.asset(
                  _branding.logoWatermark,
                  width: MediaQuery.of(context).size.width *
                      _branding.mobileFormWatermarkWidthFactor,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          Column(
            children: [
              _buildEncabezadoFormulario(),
              const SizedBox(height: 20),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: _isWebLayout ? 940 : double.infinity,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: _isWebLayout ? 24 : 20,
                      ),
                      child: Form(
                        key: _formKey,
                        child: ListView(
                          physics: const BouncingScrollPhysics(),
                          children: [
                        Text("Fecha de Solicitud:", style: TextStyle(color: _branding.primary, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () => _seleccionarFecha(context, 'solicitud'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: _isWebLayout
                                    ? const Color(0xFF4D7374)
                                    : Colors.white,
                                width: _isWebLayout ? 1.4 : 2,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(DateFormat('dd/MM/yyyy').format(_fechaSolicitud), style: const TextStyle(fontSize: 16)),
                                Icon(Icons.calendar_today, color: _branding.primary),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildFieldTitle("Nombre del colaborador"),
                        TextFormField(
                          controller: _nombreController,
                          decoration: _inputStyle("Nombre del Colaborador", Icons.person),
                        ),
                        const SizedBox(height: 15),
                        _buildFieldTitle("Tipo de tramite"),
                        DropdownButtonFormField<String>(
                          value: _tipoSeleccionado,
                          decoration: _inputStyle("Tipo de trámite", Icons.list_alt),
                          items: ['Permiso', 'Vacaciones'].map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
                          onChanged: (val) => setState(() => _tipoSeleccionado = val!),
                        ),
                        const SizedBox(height: 20),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _tipoSeleccionado == 'Permiso' ? _buildFormPermiso() : _buildFormVacaciones(),
                        ),
                        const SizedBox(height: 30),
                        ElevatedButton(
                          onPressed: _enviarFormulario,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _branding.primary,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                          ),
                          child: const Text("ENVIAR SOLICITUD", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 20),
                          ],
                        ),
                      ),
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

  InputDecoration _inputStyle(String label, IconData icon) {
    return InputDecoration(
      hintText: label,
      hintStyle: TextStyle(
        color: _branding.primary.withOpacity(0.72),
        fontWeight: FontWeight.w600,
      ),
      prefixIcon: Icon(icon, color: _branding.primary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      filled: true,
      fillColor: Colors.white,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: _isWebLayout ? const Color(0xFF4D7374) : Colors.white,
          width: _isWebLayout ? 1.4 : 2,
        ),
      ),
    );
  }

  Widget _buildFieldTitle(String titulo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        titulo,
        style: TextStyle(
          color: _branding.primary,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildPermissionModeChip({
    required String label,
    required IconData icon,
    required String value,
  }) {
    final selected = _modoPermiso == value;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        setState(() {
          _modoPermiso = value;
          if (value == 'horas') {
            _fechaFin = _fechaInicio;
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _branding.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? Colors.white : _branding.primary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : _branding.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEncabezadoFormulario() {
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 5)
          )
        ],
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
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.history, color: Colors.white, size: 28),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => HistorialSolicitudesScreen(
                          nombreDocente: _nombreController.text,
                          sedeId: _branding.sedeId,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            "NUEVA SOLICITUD",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1.2,
            ),
          ),
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

  Widget _buildFormPermiso() {
    return Column(
      key: const ValueKey('permiso'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldTitle("Motivo del permiso"),
        TextFormField(
          decoration: _inputStyle("Motivo del Permiso", Icons.edit),
          maxLines: 2,
          validator: (val) => val!.isEmpty ? 'Ingrese el motivo' : null,
          onSaved: (val) => _motivo = val!,
        ),
        const SizedBox(height: 15),
        _buildFieldTitle("Modalidad del permiso"),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.74),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildPermissionModeChip(
                  label: "Por horas",
                  icon: Icons.schedule_rounded,
                  value: 'horas',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPermissionModeChip(
                  label: "Por dias",
                  icon: Icons.date_range_rounded,
                  value: 'dias',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text("Fecha del permiso:", style: TextStyle(color: _branding.primary, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ListTile(
          tileColor: Colors.white.withOpacity(0.7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Text(DateFormat('dd/MM/yyyy').format(_fechaInicio)),
          trailing: Icon(Icons.calendar_today, color: _branding.primary),
          onTap: () => _seleccionarFecha(context, 'inicio'),
        ),
        const SizedBox(height: 15),
        if (_modoPermiso == 'horas') ...[
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldTitle("Cuantas horas se necesitan"),
                    TextFormField(
                      initialValue: _cantidadHorasPermiso == 0
                          ? ''
                          : _cantidadHorasPermiso.toString(),
                      decoration: _inputStyle("Cantidad de horas", Icons.hourglass_top_rounded),
                      keyboardType: TextInputType.number,
                      validator: (val) {
                        if (_tipoSeleccionado != 'Permiso' || _modoPermiso != 'horas') {
                          return null;
                        }
                        final cantidad = int.tryParse((val ?? '').trim()) ?? 0;
                        if (cantidad <= 0) {
                          return 'Ingrese las horas';
                        }
                        return null;
                      },
                      onChanged: (val) => _cantidadHorasPermiso = int.tryParse(val) ?? 0,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          _buildFieldTitle("Horario del permiso"),
          TextFormField(
            decoration: _inputStyle("Ej: 08:00 a 10:00", Icons.timer),
            validator: (val) {
              if (_tipoSeleccionado != 'Permiso' || _modoPermiso != 'horas') {
                return null;
              }
              if ((val ?? '').trim().isEmpty) {
                return 'Ingrese el horario';
              }
              return null;
            },
            onChanged: (val) {
              _rangoHorasPermiso = val;
              _horasPermiso = val;
            },
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldTitle("Cuantos dias se necesitan"),
                    TextFormField(
                      initialValue: _cantidadDiasPermiso.toString(),
                      decoration: _inputStyle("Cantidad de dias", Icons.calendar_month_rounded),
                      keyboardType: TextInputType.number,
                      validator: (val) {
                        if (_tipoSeleccionado != 'Permiso' || _modoPermiso != 'dias') {
                          return null;
                        }
                        final cantidad = int.tryParse((val ?? '').trim()) ?? 0;
                        if (cantidad <= 0) {
                          return 'Ingrese los dias';
                        }
                        return null;
                      },
                      onChanged: (val) => _cantidadDiasPermiso = int.tryParse(val) ?? 0,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          _buildFieldTitle("Hasta que fecha se necesita"),
          ListTile(
            tileColor: Colors.white.withOpacity(0.7),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            title: Text(DateFormat('dd/MM/yyyy').format(_fechaFin)),
            trailing: Icon(Icons.event_available_rounded, color: _branding.primary),
            onTap: () => _seleccionarFecha(context, 'fin'),
          ),
        ],
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.72),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _branding.primary.withOpacity(0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Resumen del permiso",
                style: TextStyle(
                  color: _branding.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _modoPermiso == 'horas'
                    ? (_cantidadHorasPermiso <= 0
                        ? 'Completa cuantas horas y el horario solicitado.'
                        : _construirDescripcionPermiso())
                    : (_cantidadDiasPermiso <= 0
                        ? 'Completa cuantos dias y la fecha final del permiso.'
                        : _construirDescripcionPermiso()),
                style: TextStyle(
                  color: Colors.grey[700],
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text("Se necesita descontar de:", style: TextStyle(color: _branding.primary, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            children: [
              RadioListTile<String>(
                title: const Text("Vacaciones"),
                value: "Vacaciones",
                groupValue: _descontarDe,
                activeColor: _branding.primary,
                onChanged: (val) => setState(() => _descontarDe = val!),
              ),
              RadioListTile<String>(
                title: const Text("Remuneración"),
                value: "Remuneración",
                groupValue: _descontarDe,
                activeColor: _branding.primary,
                onChanged: (val) => setState(() => _descontarDe = val!),
              ),
              RadioListTile<String>(
                title: const Text("Sin Descuento"),
                value: "Sin Descuento",
                groupValue: _descontarDe,
                activeColor: _branding.primary,
                onChanged: (val) => setState(() => _descontarDe = val!),
              ),
              RadioListTile<String>(
                title: const Text("Recuperación de horas"),
                value: "Recuperación de horas",
                groupValue: _descontarDe,
                activeColor: _branding.primary,
                onChanged: (val) => setState(() => _descontarDe = val!),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFormVacaciones() {
    return Column(
      key: const ValueKey('vacaciones'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _buildFieldTitle("Dias disponibles")),
            const SizedBox(width: 10),
            Expanded(child: _buildFieldTitle("Dias a tomar")),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                decoration: _inputStyle("Días disponibles", Icons.beach_access),
                keyboardType: TextInputType.number,
                validator: (val) =>
                    (val == null || val.trim().isEmpty) ? 'Ingrese los dias' : null,
                onChanged: (val) => setState(() {
                  _diasDisponibles = int.tryParse(val) ?? 0;
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                decoration: _inputStyle("Días a tomar", Icons.add),
                keyboardType: TextInputType.number,
                validator: (val) =>
                    (val == null || val.trim().isEmpty) ? 'Ingrese los dias' : null,
                onChanged: (val) => setState(() {
                  _diasATomar = int.tryParse(val) ?? 0;
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ListTile(
          tileColor: Colors.white.withOpacity(0.7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Text("Desde: ${DateFormat('dd/MM/yyyy').format(_fechaInicio)}"),
          onTap: () => _seleccionarFecha(context, 'inicio'),
        ),
        const SizedBox(height: 10),
        ListTile(
          tileColor: Colors.white.withOpacity(0.7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Text("Hasta: ${DateFormat('dd/MM/yyyy').format(_fechaFin)}"),
          onTap: () => _seleccionarFecha(context, 'fin'),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.72),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Resumen de vacaciones",
                style: TextStyle(
                  color: _branding.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text("Año: $_anioVacaciones"),
              const SizedBox(height: 4),
              Text("Días acumulados: $_diasDisponibles"),
              const SizedBox(height: 4),
              Text(
                "Fecha de retorno: ${DateFormat('dd/MM/yyyy').format(_fechaRetornoVacaciones)}",
              ),
              const SizedBox(height: 4),
              Text("Saldo de días: $_saldoDiasVacaciones"),
            ],
          ),
        ),
      ],
    );
  }
}
