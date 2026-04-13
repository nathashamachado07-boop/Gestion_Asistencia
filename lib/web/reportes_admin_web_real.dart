import 'dart:html' as html;

void descargarArchivoWeb(List<int> bytes, String nombre) {
  try {
    final blob = html.Blob([bytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute("download", nombre)
      ..click();
    html.Url.revokeObjectUrl(url);
  } catch (e) {
    print("Error en descarga web: $e");
  }
}