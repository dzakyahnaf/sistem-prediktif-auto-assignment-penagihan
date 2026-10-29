// Native adapter probe: an operator confirms the OS Save/Open dialogs on the
// isolated emulator. Business workflows run separately in workflows_test.dart.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:assignment_studio/api.dart';
import 'package:assignment_studio/report_download.dart';
import 'package:assignment_studio/workbook_picker.dart';

class NativeFilesProbe extends StatefulWidget {
  final Uint8List bytes;
  const NativeFilesProbe({super.key,required this.bytes});
  @override
  State<NativeFilesProbe> createState()=>_NativeFilesProbeState();
}
class _NativeFilesProbeState extends State<NativeFilesProbe> {
  String status='Siap menyimpan XLSX';bool saved=false;
  @override
  Widget build(BuildContext context)=>MaterialApp(home:Scaffold(appBar:AppBar(title:const Text('UAT berkas native')),
    body:Padding(padding:const EdgeInsets.all(20),child:Column(children:[
      Text(status),
      FilledButton(onPressed:saved?null:() async {
        setState(()=>status='Dialog simpan sistem terbuka');
        try { await saveWorkbook(widget.bytes,'s11-native-${DateTime.now().millisecondsSinceEpoch}.xlsx');if(mounted) setState((){saved=true;status='Simpan selesai';}); }
        catch(e){if(mounted) setState(()=>status='Gagal: $e');}
      },child:const Text('Simpan XLSX native')),
      if(saved) WorkbookPicker(disabled:false,onFile:(bytes,name){setState(()=>status=listEquals(bytes,widget.bytes)?'Berkas identik: $name':'Gagal: isi berbeda');},onError:(e)=>setState(()=>status='Gagal: $e')),
    ]))));
}
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real Android OS save then pick retains exact XLSX bytes',(t) async {
    expect(const bool.fromEnvironment('UAT_ISOLATED'),isTrue);
    final api=Api();await api.login('supervisor','DemoAssignment!2026');
    final bytes=await api.exportWorkbook('/api/imports/template?kind=collection');
    await t.pumpWidget(NativeFilesProbe(bytes:bytes));await t.pumpAndSettle();
    await t.tap(find.text('Simpan XLSX native'));await t.pumpAndSettle();
    for(int i=0;i<900 && find.text('Simpan selesai').evaluate().isEmpty;i++) { await t.pump(const Duration(milliseconds:100)); }
    expect(find.text('Simpan selesai'),findsOneWidget);
    await t.tap(find.text('Pilih XLSX'));await t.pumpAndSettle();
    for(int i=0;i<900 && find.textContaining('Berkas identik:').evaluate().isEmpty;i++) { await t.pump(const Duration(milliseconds:100)); }
    expect(find.textContaining('Berkas identik:'),findsOneWidget);expect(t.takeException(),isNull);api.dispose();
  },timeout:const Timeout(Duration(minutes:5)));
}
