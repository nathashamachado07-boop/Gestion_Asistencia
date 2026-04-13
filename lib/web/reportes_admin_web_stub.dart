import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Definimos la función vacía para que Android no de error de compilación
void descargarArchivoWeb(List<int> bytes, String nombre) {
  // No hace nada en dispositivos móviles
}

class ReportesAdminWeb extends StatelessWidget {
  const ReportesAdminWeb({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox();
}