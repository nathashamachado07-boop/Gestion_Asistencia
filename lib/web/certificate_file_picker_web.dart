// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

export 'certificate_file_picker_stub.dart'
    show PickedCertificateFile, isCertificateFileNameSupported;
import 'certificate_file_picker_stub.dart';

Future<PickedCertificateFile?> readHtmlCertificateFile(html.File file) async {
  if (!isCertificateFileNameSupported(file.name)) {
    return null;
  }

  final reader = html.FileReader();
  final completer = Completer<PickedCertificateFile?>();

  reader.readAsDataUrl(file);
  reader.onLoadEnd.first.then((_) {
    final result = reader.result;
    if (result is! String || result.isEmpty) {
      completer.complete(null);
      return;
    }

    final marker = 'base64,';
    final markerIndex = result.indexOf(marker);
    if (markerIndex < 0) {
      completer.complete(null);
      return;
    }

    final base64Content = result.substring(markerIndex + marker.length).trim();
    if (base64Content.isEmpty) {
      completer.complete(null);
      return;
    }

    Uint8List bytes;
    try {
      bytes = base64Decode(base64Content);
    } catch (_) {
      completer.complete(null);
      return;
    }

    completer.complete(
      PickedCertificateFile(
        bytes: bytes,
        fileName: file.name,
        mimeType: file.type.isEmpty ? 'application/x-pkcs12' : file.type,
      ),
    );
  }).catchError((_) {
    completer.complete(null);
  });

  return completer.future;
}

Future<PickedCertificateFile?> pickCertificateFile() async {
  final input = html.FileUploadInputElement()
    ..accept = '.p12,.pfx,application/x-pkcs12,application/pkcs12'
    ..multiple = false;

  final completer = Completer<PickedCertificateFile?>();
  var changeDetected = false;

  html.window.onFocus.first.then((_) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final files = input.files;
    if (!completer.isCompleted &&
        !changeDetected &&
        (files == null || files.isEmpty)) {
      completer.complete(null);
    }
  });

  input.onChange.first.then((_) {
    changeDetected = true;
    final files = input.files;
    final file = files != null && files.isNotEmpty ? files.first : null;
    if (file == null) {
      completer.complete(null);
      return;
    }

    readHtmlCertificateFile(file).then((picked) {
      if (!completer.isCompleted) {
        completer.complete(picked);
      }
    });
  }).catchError((_) {
    completer.complete(null);
  });

  input.click();
  return completer.future;
}
