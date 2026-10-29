import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

class WorkbookPicker extends StatefulWidget {
  final bool disabled;
  final void Function(Uint8List, String) onFile;
  final void Function(String) onError;
  const WorkbookPicker({super.key, required this.disabled, required this.onFile, required this.onError});
  @override
  State<WorkbookPicker> createState() => _WorkbookPickerState();
}

class _WorkbookPickerState extends State<WorkbookPicker> {
  bool picking = false;
  Future<void> pick() async {
    if (picking || widget.disabled) return;
    setState(() => picking = true);
    try {
      final file = await FilePicker.pickFile(dialogTitle: 'Pilih XLSX operasional', type: FileType.custom, allowedExtensions: ['xlsx']);
      if (file == null || !mounted || widget.disabled) return;
      const limit = 5 * 1024 * 1024;
      final length = file.lengthSync() ?? await file.length();
      if (!file.name.toLowerCase().endsWith('.xlsx') || length == null || length <= 0 || length > limit) {
        throw const FormatException('Pilih XLSX tidak kosong, maksimal5MiB.');
      }
      final bytes = BytesBuilder(copy: false); int size = 0;
      await for (final chunk in file.readAsByteStream()) {
        size += chunk.length;
        if (size > limit) throw const FormatException('Berkas melebihi5MiB.');
        bytes.add(chunk);
      }
      if (!mounted || widget.disabled) return;
      if (size == 0) throw const FormatException('Berkas kosong.');
      widget.onFile(bytes.takeBytes(), file.name);
    } catch (e) { if (mounted) widget.onError(e is FormatException ? e.message : 'Tidak dapat membaca berkas: $e'); }
    finally { if (mounted) setState(() => picking = false); }
  }
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(onPressed: widget.disabled || picking ? null : pick,
    icon: const Icon(Icons.upload_file_outlined), label: Text(picking ? 'Membaca berkas…' : 'Pilih XLSX'));
}
