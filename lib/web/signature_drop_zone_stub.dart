import 'package:flutter/material.dart';

import 'signature_file_picker_stub.dart';

class SignatureDropZone extends StatelessWidget {
  const SignatureDropZone({
    super.key,
    required this.enabled,
    required this.onFileDropped,
    this.onError,
    this.selectedFileName,
  });

  final bool enabled;
  final ValueChanged<PickedSignatureFile> onFileDropped;
  final ValueChanged<String>? onError;
  final String? selectedFileName;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}