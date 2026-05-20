import 'package:flutter/material.dart';

import 'certificate_file_picker_stub.dart';

class CertificateDropZone extends StatelessWidget {
  const CertificateDropZone({
    super.key,
    required this.enabled,
    required this.onFileDropped,
    this.onError,
    this.selectedFileName,
  });

  final bool enabled;
  final ValueChanged<PickedCertificateFile> onFileDropped;
  final ValueChanged<String>? onError;
  final String? selectedFileName;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}