import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class PickedSignatureFile {
  const PickedSignatureFile({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}

bool isSignatureFileNameSupported(String value) {
  final lower = value.trim().toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp');
}

String _signatureMimeTypeFromFileName(String value) {
  final lower = value.trim().toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  return 'image/png';
}

Future<PickedSignatureFile?> pickSignatureFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowMultiple: false,
    withData: true,
    allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
  );

  if (result == null || result.files.isEmpty) {
    return null;
  }

  final file = result.files.first;
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) {
    return null;
  }

  if (!isSignatureFileNameSupported(file.name)) {
    return null;
  }

  return PickedSignatureFile(
    bytes: bytes,
    fileName: file.name,
    mimeType: _signatureMimeTypeFromFileName(file.name),
  );
}
