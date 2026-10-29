import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:assignment_studio/workbook_picker_stub.dart';
import 'package:assignment_studio/report_download_stub.dart';

final class MemoryFile extends PlatformFile {
  @override
  final String name;
  final int size;
  final List<Uint8List> chunks;
  MemoryFile(this.name, this.size, this.chunks);
  @override
  Uri get uri => Uri.file('/fixture/$name');
  @override
  Never get xFile => throw UnimplementedError();
  @override
  int lengthSync() => size;
  @override
  Future<int?> length() async => size;
  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList(chunks.expand((e)=>e).toList());
  @override
  Stream<Uint8List> readAsByteStream() async* { for(final chunk in chunks) { yield chunk; } }
}
class NativePicker extends FilePickerPlatform {
  PlatformFile? file;
  Completer<PlatformFile?>? wait;
  int picks=0;
  Uri? saved=Uri.file('/chosen/demo.csv');
  final saves=<Map<String,dynamic>>[];
  @override
  Future<PlatformFile?> pickFile({String? dialogTitle, String? initialDirectory, FileType type=FileType.any,
    List<String>? allowedExtensions, Function(FilePickerStatus)? onFileLoading, int compressionQuality=0,
    AndroidOptions androidOptions=const AndroidOptions(), DarwinOptions darwinOptions=const DarwinOptions(),
    WindowsOptions windowsOptions=const WindowsOptions(), LinuxOptions linuxOptions=const LinuxOptions(), WebOptions webOptions=const WebOptions()}) async {
    picks++;expect(type,FileType.custom);expect(allowedExtensions,['xlsx']);return wait==null?file:wait!.future;
  }
  @override
  Future<Uri?> saveFile({required String fileName, required Uint8List bytes, String mimeType='application/octet-stream',String? dialogTitle,String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,WindowsOptions windowsOptions=const WindowsOptions(),LinuxOptions linuxOptions=const LinuxOptions(),WebOptions webOptions=const WebOptions()}) async {
    saves.add({'filename':fileName,'bytes':bytes,'mime':mimeType});return saved;
  }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NativePicker picker;late FilePickerPlatform previous;
  setUp(() { previous=FilePickerPlatform.instance;picker=NativePicker();FilePickerPlatform.instance=picker; });
  tearDown(() { FilePickerPlatform.instance=previous; });
  Future<void> host(WidgetTester t,void Function(Uint8List,String) picked,void Function(String) error) async {
    await t.pumpWidget(MaterialApp(home:Scaffold(body:WorkbookPicker(disabled:false,onFile:picked,onError:error))));await t.pumpAndSettle();
    await t.tap(find.text('Pilih XLSX'));await t.pumpAndSettle();
  }
  testWidgets('native XLSX picker reads capped stream and preserves name',(t) async {
    picker.file=MemoryFile('fixture.xlsx',4,[Uint8List.fromList([80,75]),Uint8List.fromList([3,4])]);
    Uint8List? bytes;String? name;await host(t,(b,n){bytes=b;name=n;},(e)=>fail(e));
    expect(bytes,[80,75,3,4]);expect(name,'fixture.xlsx');expect(picker.picks,1);
  });
  testWidgets('native cancel does not upload or error',(t) async {
    await host(t,(b,n)=>fail('canceled upload'),(e)=>fail(e));expect(picker.picks,1);
  });
  testWidgets('native picker rejects oversized and wrong extension',(t) async {
    String? error;picker.file=MemoryFile('huge.xlsx',6*1024*1024,[]);
    await host(t,(b,n)=>fail('oversized upload'),(e)=>error=e);expect(error,contains('maksimal'));
    picker.file=MemoryFile('wrong.xls',4,[Uint8List(4)]);await t.tap(find.text('Pilih XLSX'));await t.pumpAndSettle();expect(error,contains('XLSX'));
  });
  testWidgets('file growing during native read is capped',(t) async {
    String? error;picker.file=MemoryFile('growing.xlsx',4,[Uint8List(3*1024*1024),Uint8List(3*1024*1024)]);
    await host(t,(b,n)=>fail('growing upload'),(e)=>error=e);expect(error,contains('melebihi'));
  });
  testWidgets('disposed picker ignores late file after navigation',(t) async {
    picker.wait=Completer<PlatformFile?>();await host(t,(b,n)=>fail('late upload'),(e)=>fail(e));
    await t.pumpWidget(const SizedBox());picker.wait!.complete(MemoryFile('late.xlsx',4,[Uint8List(4)]));await t.pumpAndSettle();expect(t.takeException(),isNull);
  });
  test('native save sends exact bytes MIME and cancellation',( ) async {
    final bytes=Uint8List.fromList([1,2,3]);
    await saveReport(bytes,'report.csv');await saveWorkbook(bytes,'template.xlsx');await saveDataset(bytes,'models.zip');
    expect(picker.saves.map((s)=>s['mime']),['text/csv','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/zip']);
    for(final s in picker.saves) { expect(s['bytes'],bytes); }
    picker.saved=null;await expectLater(saveReport(bytes,'cancel.csv'),throwsA(isA<SaveCancelled>()));
  });
}
