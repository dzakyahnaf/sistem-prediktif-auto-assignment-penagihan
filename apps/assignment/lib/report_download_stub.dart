import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

class SaveCancelled implements Exception {
  @override
  String toString() => 'Penyimpanan dibatalkan.';
}

Future<void> saveReport(Uint8List bytes, String filename) async {
  final extension = filename.split('.').last.toLowerCase();
  final mime = {'csv':'text/csv', 'zip':'application/zip', 'xlsx':'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}[extension] ?? 'application/octet-stream';
  final result = await FilePicker.saveFile(fileName: filename, bytes: bytes, mimeType: mime,
    dialogTitle: 'Simpan berkas Assignment Studio');
  if (result == null) throw SaveCancelled();
}

Future<void> saveWorkbook(Uint8List bytes, String filename) => saveReport(bytes, filename);
Future<void> saveDataset(Uint8List bytes, String filename) => saveReport(bytes, filename);
