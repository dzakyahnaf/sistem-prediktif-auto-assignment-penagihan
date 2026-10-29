import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<void> saveReport(Uint8List bytes, String filename) => _save(bytes, filename, 'text/csv;charset=utf-8');
Future<void> saveWorkbook(Uint8List bytes, String filename) => _save(bytes, filename, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
Future<void> saveDataset(Uint8List bytes, String filename) => _save(bytes, filename, 'application/zip');

Future<void> _save(Uint8List bytes, String filename, String mime) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()..href = url..download = filename;
  try {
    web.document.body!.append(anchor);
    anchor.click();
  } finally {
    anchor.remove();
    // Give the browser time to start the download before releasing its bytes.
    Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  }
}
