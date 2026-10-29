import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:assignment_studio/api.dart';
import 'package:assignment_studio/operations_page.dart';
import 'package:assignment_studio/operation_dialogs.dart';
import 'package:assignment_studio/widgets.dart';

class Fixture {
  late final Api api;
  final posts=<Map<String,dynamic>>[];final paths=<String>[];
  int? failure;bool read=false;int revision=0;
  Future<http.Response>? Function(http.Request)? intercept;
  Fixture({String role='supervisor'}){
    api=Api(client:MockClient((r) async {
      http.Response response(Object v,[int status=200])=>http.Response(jsonEncode(v),status);
      paths.add('${r.method} ${r.url.path}?${r.url.query}');
      if(r.url.path.endsWith('login'))return response({'access_token':'demo','user':{'role':role}});
      if(r.method!='GET'){
        posts.add({'path':r.url.path,'body':r.body.isEmpty?null:jsonDecode(r.body)});
        if(failure!=null)return response({'detail':'Operasi gagal $failure'},failure!);
        if(r.url.path.endsWith('read'))read=true;
        if(r.url.path.contains('accounts'))revision++;
        return response(r.url.path.endsWith('process')?{'processed':1}:r.url.path.endsWith('scan')?{'created':1}:{'ok':true},r.url.path.endsWith('integrations')?201:200);
      }
      final override=intercept?.call(r);if(override!=null)return override;
      if(r.url.path.contains('notifications'))return response({'items':[{'id':'NTF-1','title':'Assignment baru','body':'Penugasan sintetis',
        'case_id':'CASE-1','created_at':'2026-10-29T00:00:00Z','read_at':read?'2026-10-29T01:00:00Z':null,'can_open':false}], 'total':26,'unread':read?0:1});
      if(r.url.path.contains('accounts'))return response({'items':[{'id':'USER-1','username':'smg-col-a','agent_id':'SMG-col-A','name':'Tele sintetis','active':1,'version':revision,'active_cases':2}]});
      return response({'items':[{'id':'JOB-1','case_id':'CASE-1','cycle':1,'channel':'telephony','state':'retry','attempts':1,'attempt_limit':3,
        'version':2,'available_at':'2026-10-29T00:00:00Z','receipt_id':null,'attempt_history':[{'attempt':1,'state':'retry','detail':'Adapter tiruan gagal','created_at':'2026-10-29T00:00:00Z'}]}],'total':1});
    }));
  }
  Future<void> host(WidgetTester t,{double width=390,Widget? dialog}) async {
    t.view.physicalSize=Size(width,844);t.view.devicePixelRatio=1;
    addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);addTearDown(api.dispose);
    await api.login('demo','demo');
    await t.pumpWidget(MaterialApp(theme:studioTheme(),home:dialog==null?OperationsPage(api:api):Builder(builder:(c)=>Scaffold(body:TextButton(onPressed:()=>showDialog<void>(context:c,builder:(_)=>dialog),child:const Text('Open'))))));
    await t.pumpAndSettle();if(dialog!=null){await t.tap(find.text('Open'));await t.pumpAndSettle();}
  }
}
Future<void> tap(WidgetTester t,Finder f) async {
  if(f.evaluate().isEmpty)await t.scrollUntilVisible(f,400,scrollable:find.byType(Scrollable).first,maxScrolls:30);
  await t.ensureVisible(f);await t.pumpAndSettle();await t.tap(f);await t.pumpAndSettle();
}
Finder field(String label)=>find.byWidgetPredicate((w)=>w is TextField&&w.decoration?.labelText==label);
Future<void> fill(WidgetTester t,String label,String text) async {await t.ensureVisible(field(label));await t.pumpAndSettle();await t.enterText(field(label),text);await t.pumpAndSettle();}
void main(){
  for(final width in [390.0,1440.0]){
    testWidgets('inbox read paging and supervisor mock batch review at $width',(t) async {
      final f=Fixture();await f.host(t,width:width);
      expect(find.text('Kasus tidak lagi dalam scope akun ini.'),findsOneWidget);expect(find.text('Buka kasus'),findsNothing);
      await tap(t,find.text('Tandai dibaca'));expect(f.read,isTrue);
      await tap(t,find.text('Berikutnya'));expect(f.paths.last,contains('offset=25'));
      await tap(t,find.text('Integrasi'));await tap(t,find.text('Proses job siap'));await tap(t,find.text('Batal'));expect(f.posts.length,1);
      await tap(t,find.text('Proses job siap'));await tap(t,find.text('Jalankan'));expect(f.posts.last['path'],'/api/integrations/process');
      await tap(t,find.text('Histori percobaan'));expect(find.textContaining('Adapter tiruan gagal'),findsOneWidget);expect(t.takeException(),isNull);
    });
    testWidgets('account reset review masks password and disposes dialog at $width',(t) async {
      final f=Fixture();await f.host(t,width:width);await tap(t,find.text('Akun petugas'));await tap(t,find.text('Kontrol akun'));
      await fill(t,'Password baru (opsional)','NewDemoPassword!2026');await fill(t,'Alasan operasi','Reset akun petugas untuk pengujian');
      await tap(t,find.widgetWithText(FilledButton,'Tinjau operasi'));
      final texts=t.widgetList<Text>(find.descendant(of:find.byType(AlertDialog).last,matching:find.byType(Text))).map((x)=>x.data??'').join();expect(texts,contains('reset password ya'));expect(texts, isNot(contains('NewDemoPassword!2026')));
      await tap(t,find.text('Batal'));expect(f.posts,isEmpty);
      await tap(t,find.widgetWithText(FilledButton,'Tinjau operasi'));await tap(t,find.text('Konfirmasi operasi'));
      expect((f.posts.single['body'] as Map)['expected_version'],0);expect(f.revision,1);expect(t.takeException(),isNull);
    });
  }
  testWidgets('ambiguous worker retry preserves request key and locks other tabs',(t) async {
    final f=Fixture();await f.host(t);await tap(t,find.text('Integrasi'));f.failure=503;
    await tap(t,find.text('Proses job siap'));await tap(t,find.text('Jalankan'));final original=Map.of(f.posts.single);
    await t.tap(find.text('Akun petugas'),warnIfMissed:false);await t.pumpAndSettle();expect(t.state<OperationsPageState>(find.byType(OperationsPage)).tab,1);
    f.failure=null;await tap(t,find.text('Periksa / ulangi batch'));expect(f.posts,[original,original]);
  });
  testWidgets('agent contact review and ambiguous retry never adds failure scenario controls',(t) async {
    final f=Fixture(role:'agent');await f.host(t,dialog:OperationDialog(api:f.api,record:const {'id':'CASE-1','cycle':1,'version':4}));
    expect(find.text('Skenario adapter'),findsNothing);f.failure=503;
    await tap(t,find.widgetWithText(FilledButton,'Tinjau operasi'));await tap(t,find.text('Konfirmasi operasi'));final original=Map.of(f.posts.single);
    f.failure=null;await tap(t,find.text('Periksa / ulangi operasi'));expect(f.posts,[original,original]);expect((original['body'] as Map)['scenario'],'success');
  });
  testWidgets('stale job retry requires closing and reloading',(t) async {
    final f=Fixture();await f.host(t);await tap(t,find.text('Integrasi'));await tap(t,find.text('Jadwalkan ulang'));
    f.failure=409;await fill(t,'Alasan operasi','Pemulihan konflik job simulasi');await tap(t,find.widgetWithText(FilledButton,'Tinjau operasi'));await tap(t,find.text('Konfirmasi operasi'));
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton,'Tinjau operasi')).onPressed,isNull);
    await tap(t,find.text('Tutup & muat ulang'));expect(find.byType(OperationDialog),findsNothing);
  });
  testWidgets('agent inbox hides account and worker controls and GET error hides stale rows',(t) async {
    final f=Fixture(role:'agent');await f.host(t);expect(find.text('Akun petugas'),findsNothing);expect(find.text('Pindai SLA'),findsNothing);
    f.intercept=(r)=>Future.value(http.Response('{"detail":"Koneksi inbox gagal"}',503));await tap(t,find.byTooltip('Muat operasi terbaru'));
    expect(find.text('Assignment baru'),findsNothing);expect(f.api.token,isNotNull);expect(find.text('Koneksi inbox gagal'),findsWidgets);
  });
}

