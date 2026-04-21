import 'package:flutter/material.dart';

// Esta clase es un cascarón vacío para que Android no falle.
// Solo se mostrará si por error alguien llega aquí en móvil.
class ReportesAdminWeb extends StatelessWidget {
  const ReportesAdminWeb({
    super.key,
    this.isSedeNorte = false,
    this.sedeId,
  });

  final bool isSedeNorte;
  final String? sedeId;

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text("Panel no disponible en móvil")),
    );
  }
}
