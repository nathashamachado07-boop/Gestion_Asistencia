import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../config/app_config.dart';
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
  bool _cargando = true;
  StreamSubscription<QuerySnapshot>? _avisosSubscription;
  List<_AvisoViewData> _avisos = const [];
  bool get _isWebLayout => kIsWeb;

  AppBranding get _branding => AppBranding.fromLegacy(
        isSedeNorte: widget.isSedeNorte,
        sedeId: widget.sedeId,
      );

  @override
  void initState() {
    super.initState();
    _escucharAvisos();
  }

  @override
  void dispose() {
    _avisosSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refrescarNotificaciones() async {
    await Future.delayed(const Duration(milliseconds: 400));
  }

  String _normalizarCorreo(String value) => value.trim().toLowerCase();

  bool _esAvisoVisible(Map<String, dynamic> data) {
    final destinatario =
        _normalizarCorreo((data['destinatarioCorreo'] ?? '').toString());
    final correoActual = _normalizarCorreo(widget.correoUsuario);
    if (destinatario.isNotEmpty) {
      return destinatario == correoActual;
    }

    if (widget.sedeId == null || widget.sedeId!.trim().isEmpty) {
      return true;
    }

    return SedeAccess.matchesSede(data, widget.sedeId!);
  }

  String _formatearFechaAviso(Map<String, dynamic> data) {
    final timestamp = data['timestamp'];
    if (timestamp is Timestamp) {
      return DateFormat('dd/MM/yyyy HH:mm').format(timestamp.toDate());
    }

    final fecha = (data['fecha'] ?? '').toString().trim();
    return fecha.isEmpty ? 'Reciente' : fecha;
  }

  IconData _iconoAviso(Map<String, dynamic> data) {
    switch ((data['tipo'] ?? '').toString().trim().toLowerCase()) {
      case 'solicitud_aprobada':
        return Icons.check_circle_rounded;
      default:
        return Icons.campaign_rounded;
    }
  }

  void _escucharAvisos() {
    _avisosSubscription?.cancel();
    _avisosSubscription = FirebaseFirestore.instance
        .collection('avisos')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      final visibles = snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return _esAvisoVisible(data);
      }).map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return _AvisoViewData(
          id: doc.id,
          titulo: (data['titulo'] ?? 'Aviso').toString(),
          mensaje: (data['mensaje'] ?? '').toString(),
          fecha: _formatearFechaAviso(data),
          icono: _iconoAviso(data),
        );
      }).toList();

      if (!mounted) {
        return;
      }

      if (_mismaListaAvisos(_avisos, visibles)) {
        if (_cargando) {
          setState(() => _cargando = false);
        }
        return;
      }

      setState(() {
        _avisos = visibles;
        _cargando = false;
      });
    }, onError: (_) {
      if (!mounted) {
        return;
      }
      setState(() => _cargando = false);
    });
  }

  bool _mismaListaAvisos(
    List<_AvisoViewData> actual,
    List<_AvisoViewData> nueva,
  ) {
    if (identical(actual, nueva)) {
      return true;
    }
    if (actual.length != nueva.length) {
      return false;
    }

    for (var i = 0; i < actual.length; i++) {
      if (actual[i] != nueva[i]) {
        return false;
      }
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          _isWebLayout ? const Color(0xFFF4F7F8) : _branding.background,
      body: Stack(
        children: [
          Container(
            color: _isWebLayout
                ? const Color(0xFFF4F7F8)
                : _branding.background,
          ),
          if (!_isWebLayout)
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
          if (!_isWebLayout)
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
                        child: _avisos.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(20),
                                children: [
                                  Text(
                                    'Comunicados Recientes',
                                    style: TextStyle(
                                      color: _branding.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Container(
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(28),
                                      border: Border.all(
                                        color: _isWebLayout
                                            ? const Color(0xFF4D7374)
                                            : _branding.primary.withOpacity(0.18),
                                        width: _isWebLayout ? 1.4 : 1,
                                      ),
                                    ),
                                    child: const Text(
                                      'Todavia no tienes avisos o notificaciones nuevas.',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(20),
                                itemCount: _avisos.length + 1,
                                itemBuilder: (context, index) {
                                  if (index == 0) {
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 15),
                                      child: Text(
                                        'Comunicados Recientes',
                                        style: TextStyle(
                                          color: _branding.primary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                        ),
                                      ),
                                    );
                                  }

                                  final aviso = _avisos[index - 1];
                                  return Padding(
                                    key: ValueKey(aviso.id),
                                    padding: const EdgeInsets.only(bottom: 15),
                                    child: _buildAvisoCard(
                                      aviso.titulo,
                                      aviso.mensaje,
                                      aviso.icono,
                                      aviso.fecha,
                                    ),
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

  Widget _buildAvisoCard(
    String titulo,
    String mensaje,
    IconData icono,
    String fechaAviso,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: _branding.primary.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: _isWebLayout
              ? const Color(0xFF4D7374)
              : _branding.primary.withOpacity(0.24),
          width: _isWebLayout ? 1.4 : 1,
        ),
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _branding.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    fechaAviso,
                    style: TextStyle(
                      color: _branding.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
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

class _AvisoViewData {
  const _AvisoViewData({
    required this.id,
    required this.titulo,
    required this.mensaje,
    required this.fecha,
    required this.icono,
  });

  final String id;
  final String titulo;
  final String mensaje;
  final String fecha;
  final IconData icono;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _AvisoViewData &&
        other.id == id &&
        other.titulo == titulo &&
        other.mensaje == mensaje &&
        other.fecha == fecha &&
        other.icono == icono;
  }

  @override
  int get hashCode => Object.hash(id, titulo, mensaje, fecha, icono);
}
