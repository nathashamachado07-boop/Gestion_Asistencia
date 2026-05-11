import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/app_branding.dart';
import '../services/firebase_service.dart';
import '../widgets/legal_documents.dart';

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({
    super.key,
    required this.correoUsuario,
    this.isSedeNorte = false,
    this.sedeId,
  });

  final String correoUsuario;
  final bool isSedeNorte;
  final String? sedeId;

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  late Future<Map<String, dynamic>?> _perfilFuture;
  final FirebaseService _service = FirebaseService();
  bool get _isWebLayout => kIsWeb;

  AppBranding get _branding => AppBranding.fromLegacy(
    isSedeNorte: widget.isSedeNorte,
    sedeId: widget.sedeId,
  );

  @override
  void initState() {
    super.initState();
    _perfilFuture = _service.obtenerDatosPerfil(widget.correoUsuario);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _perfilFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: _branding.primary),
          );
        }

        if (snapshot.hasError) {
          return const Center(child: Text('Ocurrio un error inesperado'));
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return const Center(
            child: Text('No se pudo cargar la informacion'),
          );
        }

        final datos = snapshot.data!;
        final sede = (datos['sede'] ?? 'Matriz').toString();

        if (_isWebLayout) {
          return _buildWebLayout(datos, sede);
        }

        return Scaffold(
          backgroundColor: _branding.surface,
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    Container(
                      height: 300,
                      decoration: BoxDecoration(
                        color: _branding.primary,
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(45),
                          bottomRight: Radius.circular(45),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Column(
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 15),
                            child: Center(
                              child: Text(
                                'MI PERFIL',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Center(
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.white24,
                                    shape: BoxShape.circle,
                                  ),
                                  child: CircleAvatar(
                                    radius: 50,
                                    backgroundColor: Colors.white,
                                    child: Icon(
                                      Icons.person_outline_rounded,
                                      size: 60,
                                      color: _branding.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 15),
                                Text(
                                  datos['nombre'] ?? 'Usuario',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(
                                      sigmaX: 10,
                                      sigmaY: 10,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.2,
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.3,
                                          ),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Text(
                                        datos['rol']?.toUpperCase() ??
                                            'SIN ROL',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 25,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Text(
                      'Informacion Academica',
                      style: TextStyle(
                        color: _branding.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildInfoCard(
                      Icons.business_center_outlined,
                      'AREA',
                      datos['especialidad'] ?? 'No asignada',
                    ),
                    const SizedBox(height: 14),
                    _buildInfoCard(
                      Icons.email_outlined,
                      'Correo Institucional',
                      datos['correo'] ?? widget.correoUsuario,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoCard(
                            Icons.smartphone_rounded,
                            'Telefono',
                            datos['telefono'] ?? 'N/A',
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _buildInfoCard(
                            Icons.location_on_outlined,
                            'Sede',
                            sede,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: ElevatedButton(
                        onPressed: () async {
                          final changed = await showChangePasswordDialog(
                            context,
                            branding: _branding,
                            service: _service,
                            correo: widget.correoUsuario,
                          );

                          if (!mounted || !changed) return;

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'Contrasena actualizada correctamente.',
                              ),
                              backgroundColor: _branding.primary,
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _branding.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_reset_rounded, size: 20),
                            SizedBox(width: 12),
                            Text(
                              'CAMBIAR CONTRASENA',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pushNamedAndRemoveUntil(
                            context,
                            '/login',
                            (route) => false,
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: Colors.redAccent,
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          backgroundColor: Colors.redAccent.withValues(
                            alpha: 0.02,
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.logout_rounded,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            SizedBox(width: 12),
                            Text(
                              'CERRAR SESION',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWebLayout(Map<String, dynamic> datos, String sede) {
    return Container(
      color: const Color(0xFFF4F7F8),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 860;
                final actionWidth = wide
                    ? (constraints.maxWidth - 14) / 2
                    : constraints.maxWidth;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_branding.primary, _branding.primaryDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: _branding.primary.withOpacity(0.22),
                            blurRadius: 24,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: const Icon(
                              Icons.person_outline_rounded,
                              color: Colors.white,
                              size: 42,
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (datos['nombre'] ?? 'Usuario').toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    _buildWebHeaderChip(
                                      (datos['rol'] ?? 'Sin rol')
                                          .toString()
                                          .toUpperCase(),
                                    ),
                                    _buildWebHeaderChip(sede),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Informacion academica',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF243435),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Consulta y gestiona los datos principales de tu cuenta desde esta vista.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: Colors.black.withOpacity(0.58),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: constraints.maxWidth,
                          child: _buildWebInfoCard(
                            Icons.business_center_outlined,
                            'Area',
                            (datos['especialidad'] ?? 'No asignada').toString(),
                          ),
                        ),
                        SizedBox(
                          width: constraints.maxWidth,
                          child: _buildWebInfoCard(
                            Icons.email_outlined,
                            'Correo institucional',
                            (datos['correo'] ?? widget.correoUsuario).toString(),
                          ),
                        ),
                        SizedBox(
                          width: wide
                              ? (constraints.maxWidth - 16) / 2
                              : constraints.maxWidth,
                          child: _buildWebInfoCard(
                            Icons.smartphone_rounded,
                            'Telefono',
                            (datos['telefono'] ?? 'N/A').toString(),
                          ),
                        ),
                        SizedBox(
                          width: wide
                              ? (constraints.maxWidth - 16) / 2
                              : constraints.maxWidth,
                          child: _buildWebInfoCard(
                            Icons.location_on_outlined,
                            'Sede',
                            sede,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        SizedBox(
                          width: actionWidth,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final changed = await showChangePasswordDialog(
                                context,
                                branding: _branding,
                                service: _service,
                                correo: widget.correoUsuario,
                              );

                              if (!mounted || !changed) return;

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Contrasena actualizada correctamente.',
                                  ),
                                  backgroundColor: _branding.primary,
                                ),
                              );
                            },
                            icon: const Icon(Icons.lock_reset_rounded),
                            label: const Text('Cambiar contrasena'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _branding.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: actionWidth,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pushNamedAndRemoveUntil(
                                context,
                                '/login',
                                (route) => false,
                              );
                            },
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text('Cerrar sesion'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: BorderSide(
                                color: Colors.redAccent.withOpacity(0.55),
                                width: 1.4,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWebHeaderChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildWebInfoCard(IconData icono, String label, String valor) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: _branding.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icono, color: _branding.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black.withOpacity(0.45),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  valor,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF243435),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(IconData icono, String label, String valor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _branding.surface,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                const BoxShadow(
                  color: Colors.white,
                  offset: Offset(-2, -2),
                  blurRadius: 4,
                ),
                BoxShadow(
                  color: _branding.primary.withValues(alpha: 0.15),
                  offset: const Offset(2, 2),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Icon(icono, color: _branding.primary, size: 22),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valor,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF2D3E3E),
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
