// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import 'certificate_file_picker_web.dart';

int _certificateDropZoneCounter = 0;

class CertificateDropZone extends StatefulWidget {
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
  State<CertificateDropZone> createState() => _CertificateDropZoneState();
}

class _CertificateDropZoneState extends State<CertificateDropZone> {
  late final String _viewType =
      'certificate-drop-zone-${_certificateDropZoneCounter++}';
  html.DivElement? _root;
  html.DivElement? _title;
  html.DivElement? _subtitle;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (viewId) {
      final root = html.DivElement()
        ..style.width = '100%'
        ..style.height = '124px'
        ..style.boxSizing = 'border-box'
        ..style.borderRadius = '18px'
        ..style.border = '2px dashed #9BBDBB'
        ..style.background = '#F7FBFB'
        ..style.display = 'flex'
        ..style.flexDirection = 'column'
        ..style.alignItems = 'center'
        ..style.justifyContent = 'center'
        ..style.padding = '14px'
        ..style.cursor = widget.enabled ? 'pointer' : 'not-allowed'
        ..style.transition = 'all 120ms ease';

      final title = html.DivElement()
        ..style.fontSize = '14px'
        ..style.fontWeight = '700'
        ..style.color = '#1E2937'
        ..style.textAlign = 'center';

      final subtitle = html.DivElement()
        ..style.fontSize = '12px'
        ..style.fontWeight = '500'
        ..style.color = '#5F6B76'
        ..style.textAlign = 'center'
        ..style.marginTop = '6px'
        ..style.lineHeight = '1.45';

      root.children.addAll([title, subtitle]);

      root.onClick.listen((_) async {
        if (!widget.enabled) {
          return;
        }
        final picked = await pickCertificateFile();
        if (!mounted || picked == null) {
          return;
        }
        widget.onFileDropped(picked);
      });

      root.onDragOver.listen((event) {
        if (!widget.enabled) {
          return;
        }
        event.preventDefault();
        _isDragging = true;
        _applyStyles();
      });

      root.onDragEnter.listen((event) {
        if (!widget.enabled) {
          return;
        }
        event.preventDefault();
        _isDragging = true;
        _applyStyles();
      });

      root.onDragLeave.listen((event) {
        if (!widget.enabled) {
          return;
        }
        _isDragging = false;
        _applyStyles();
      });

      root.onDrop.listen((event) async {
        if (!widget.enabled) {
          return;
        }
        event.preventDefault();
        _isDragging = false;
        _applyStyles();

        final files = event.dataTransfer.files;
        final file = files != null && files.isNotEmpty ? files.first : null;
        if (file == null) {
          widget.onError?.call(
            'No se detecto un archivo. Arrastra un .p12 o .pfx valido.',
          );
          return;
        }
        if (!isCertificateFileNameSupported(file.name)) {
          widget.onError?.call(
            'El archivo debe estar en formato .p12 o .pfx.',
          );
          return;
        }

        final picked = await readHtmlCertificateFile(file);
        if (!mounted || picked == null) {
          widget.onError?.call(
            'No se pudo leer el archivo. Intenta con otro certificado.',
          );
          return;
        }
        widget.onFileDropped(picked);
      });

      _root = root;
      _title = title;
      _subtitle = subtitle;
      _applyStyles();
      return root;
    });
  }

  @override
  void didUpdateWidget(covariant CertificateDropZone oldWidget) {
    super.didUpdateWidget(oldWidget);
    _applyStyles();
  }

  void _applyStyles() {
    final root = _root;
    final title = _title;
    final subtitle = _subtitle;
    if (root == null || title == null || subtitle == null) {
      return;
    }

    final hasFile = (widget.selectedFileName ?? '').isNotEmpty;
    final borderColor = _isDragging
        ? '#2F6E6F'
        : (hasFile ? '#4D8B82' : '#9BBDBB');
    final background = _isDragging
        ? '#EAF5F3'
        : (hasFile ? '#F0F8F6' : '#F7FBFB');

    root.style.borderColor = borderColor;
    root.style.background = background;
    root.style.opacity = widget.enabled ? '1' : '0.60';
    root.style.cursor = widget.enabled ? 'pointer' : 'not-allowed';

    title.text = hasFile
        ? 'Archivo listo: ${widget.selectedFileName}'
        : 'Arrastra aqui tu certificado .p12 o .pfx';
    subtitle.text = hasFile
        ? 'Tambien puedes hacer clic para reemplazarlo.'
        : 'Tambien puedes hacer clic aqui para seleccionarlo desde tu equipo.';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 124,
      width: double.infinity,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
