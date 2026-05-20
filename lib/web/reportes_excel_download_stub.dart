Future<void> descargarExcelEnNavegador(List<int> bytes, String fileName) async {
  if (bytes.isEmpty || fileName.isEmpty) {
    return;
  }

  throw UnsupportedError(
    'La descarga web solo esta disponible en Flutter Web.',
  );
}