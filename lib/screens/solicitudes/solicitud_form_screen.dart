import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/app_branding.dart';
import '../../models/solicitud_model.dart';
import '../../services/firebase_service.dart';
import 'historial_solicitudes_screen.dart';

class SolicitudFormScreen extends StatefulWidget {
  final String nombreDocente;
  final bool isSedeNorte;
  final String? sedeId;

  const SolicitudFormScreen({
    super.key,
    required this.nombreDocente,
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

  String _tipoSeleccionado = 'Permiso';
  String _motivo = '';
  DateTime _fechaSolicitud = DateTime.now();
  DateTime _fechaInicio = DateTime.now();
  DateTime _fechaFin = DateTime.now();

  String _horasPermiso = '';
  String _descontarDe = 'Vacaciones';

  int _diasDisponibles = 0;
  int _diasATomar = 0;

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
        if (tipo == 'inicio') _fechaInicio = picked;
        if (tipo == 'fin') _fechaFin = picked;
      });
    }
  }

  void _enviarFormulario() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      Solicitud nuevaSolicitud = Solicitud(
        id: '',
        colaborador: _nombreController.text,
        motivo: _motivo,
        tipo: _tipoSeleccionado,
        fechaInicio: _fechaInicio,
        fechaFin: _fechaFin,
        estado: 'pendiente',
        horasPermiso: _tipoSeleccionado == 'Permiso' ? _horasPermiso : null,
        descontarDe: _tipoSeleccionado == 'Permiso' ? _descontarDe : null,
        diasDisponibles: _tipoSeleccionado == 'Vacaciones' ? _diasDisponibles : null,
        diasATomar: _tipoSeleccionado == 'Vacaciones' ? _diasATomar : null,
        fechaSolicitud: _fechaSolicitud,
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
      backgroundColor: _branding.background,
      body: Stack(
        children: [
          Container(decoration: BoxDecoration(color: _branding.background)),
          _buildPatronS(),
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
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
                              color: Colors.white.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(color: Colors.white, width: 2),
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
                        TextFormField(
                          controller: _nombreController,
                          decoration: _inputStyle("Nombre del Colaborador", Icons.person),
                        ),
                        const SizedBox(height: 15),
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
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _inputStyle(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: _branding.primary, fontWeight: FontWeight.bold),
      prefixIcon: Icon(icon, color: _branding.primary),
      filled: true,
      fillColor: Colors.white.withOpacity(0.85),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.white, width: 2)),
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
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 22),
                  onPressed: () => Navigator.pop(context),
                ),
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
        TextFormField(
          decoration: _inputStyle("Motivo del Permiso", Icons.edit),
          maxLines: 2,
          validator: (val) => val!.isEmpty ? 'Ingrese el motivo' : null,
          onSaved: (val) => _motivo = val!,
        ),
        const SizedBox(height: 15),
        Text("Fecha del permiso:", style: TextStyle(color: _branding.primary, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ListTile(
          tileColor: Colors.white.withOpacity(0.7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text(DateFormat('dd/MM/yyyy').format(_fechaInicio)),
          trailing: Icon(Icons.calendar_today, color: _branding.primary),
          onTap: () => _seleccionarFecha(context, 'inicio'),
        ),
        const SizedBox(height: 15),
        TextFormField(
          decoration: _inputStyle("Horario (Ej: 08:00 a 10:00)", Icons.timer),
          onChanged: (val) => _horasPermiso = val,
        ),
        const SizedBox(height: 20),
        Text("Descontar de:", style: TextStyle(color: _branding.primary, fontWeight: FontWeight.bold)),
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
      children: [
        Row(
          children: [
            Expanded(child: TextFormField(decoration: _inputStyle("Disponibles", Icons.beach_access), keyboardType: TextInputType.number, onChanged: (val) => _diasDisponibles = int.tryParse(val) ?? 0)),
            const SizedBox(width: 10),
            Expanded(child: TextFormField(decoration: _inputStyle("A Tomar", Icons.add), keyboardType: TextInputType.number, onChanged: (val) => _diasATomar = int.tryParse(val) ?? 0)),
          ],
        ),
        const SizedBox(height: 10),
        ListTile(
          tileColor: Colors.white.withOpacity(0.7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text("Desde: ${DateFormat('dd/MM/yyyy').format(_fechaInicio)}"),
          onTap: () => _seleccionarFecha(context, 'inicio'),
        ),
      ],
    );
  }
}
