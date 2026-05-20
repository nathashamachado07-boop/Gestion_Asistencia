import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class PickedCertificateFile {
  const PickedCertificateFile({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}

bool isCertificateFileNameSupported(String value) {
  final lower = value.trim().toLowerCase();
  return lower.endsWith('.p12') || lower.endsWith('.pfx');
}

String _certificateMimeTypeFromFileName(String value) {
  return 'application/x-pkcs12';
}

Future<PickedCertificateFile?> pickCertificateFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowMultiple: false,
    withData: true,
    allowedExtensions: const ['p12', 'pfx'],
  );

  if (result == null || result.files.isEmpty) {
    return null;
  }

  final file = result.files.first;
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) {
    return null;
  }

  if (!isCertificateFileNameSupported(file.name)) {
    return null;
  }

  return PickedCertificateFile(
    bytes: bytes,
    fileName: file.name,
    mimeType: _certificateMimeTypeFromFileName(file.name),
  );
}
