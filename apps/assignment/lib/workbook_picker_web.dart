import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class WorkbookPicker extends StatefulWidget {
  final bool disabled;
  final void Function(Uint8List, String) onFile;
  final void Function(String) onError;
  const WorkbookPicker({super.key, required this.disabled, required this.onFile, required this.onError});
  @override
  State<WorkbookPicker> createState() => _WorkbookPickerState();
}

class _WorkbookPickerState extends State<WorkbookPicker> {
  late final web.HTMLInputElement input;
  StreamSubscription<web.Event>? subscription;
  bool reading = false;
  @override
  void initState() {
    super.initState();
    input = web.HTMLInputElement()..type = 'file'..accept = '.xlsx'..id = 'studio-xlsx-import';
    input.style.display = 'none'; input.disabled = widget.disabled;
    web.document.body!.append(input);
    subscription = input.onChange.listen((_) async {
      if (widget.disabled || reading) return;
      final file = input.files?.item(0);
      if (file == null) return;
      setState(() => reading = true);
      try {
        if (!file.name.toLowerCase().endsWith('.xlsx') || file.size > 5 * 1024 * 1024) {
          widget.onError('Pilih berkas .xlsx maksimal 5 MB.'); return;
        }
        final buffer = await file.arrayBuffer().toDart;
        if (mounted && !widget.disabled) widget.onFile(buffer.toDart.asUint8List(), file.name);
      } catch (_) {
        if (mounted) widget.onError('Berkas tidak dapat dibaca. Pilih ulang workbook.');
      } finally {
        input.value = '';
        if (mounted) setState(() => reading = false);
      }
    });
  }
  @override
  void didUpdateWidget(covariant WorkbookPicker oldWidget) { super.didUpdateWidget(oldWidget); input.disabled = widget.disabled; }
  @override
  void dispose() { subscription?.cancel(); input.remove(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FilledButton.icon(onPressed: widget.disabled || reading ? null : () => input.click(),
    icon: const Icon(Icons.upload_file), label: Text(reading ? 'Membaca berkas…' : 'Pilih workbook Excel'));
}
