import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:assignment_studio/api.dart';
import 'package:assignment_studio/master_page.dart';
import 'package:assignment_studio/override_dialog.dart';
import 'package:assignment_studio/widgets.dart';

const regions = [{'id':'SMG','name':'Semarang','active':1,'version':1,'active_cases':2,'active_agents':4,'case_count':50}];
Map<String,dynamic> options([int version=2]) => {'case_id':'TAG-S6','expected_version':version,'previous_agent':'OLD','score':55.5,'target_team':'B','options':[
  {'agent_id':'S6-B','name':'Petugas Sintetis Tujuan','remaining':3,'eligible':true,'reason':'Cocok','active_load':0,'daily_load':0,'capacity':3},
  {'agent_id':'OLD','name':'Petugas Lama','remaining':0,'eligible':false,'reason':'Petugas saat ini; kapasitas penuh','active_load':3,'daily_load':3,'capacity':3},
]};
http.Response response(dynamic data, [int code=200]) => http.Response(jsonEncode(data),code,headers:{'content-type':'application/json'});
http.Response login() => response({'access_token':'token','user':{'role':'supervisor','username':'supervisor'}});
Future<void> host(WidgetTester tester, Api api, Widget dialog, {bool direct=false}) async {
  await api.login('supervisor','demo');
  await tester.pumpWidget(MaterialApp(theme:studioTheme(),home:direct ? dialog : Builder(builder:(ctx)=>Scaffold(body:TextButton(
    onPressed:()=>showDialog<void>(context:ctx,barrierDismissible:false,builder:(_)=>dialog),child:const Text('Open'))))));
  if (!direct) { await tester.tap(find.text('Open')); }
  await tester.pumpAndSettle();
}
Future<void> fill(WidgetTester tester, String key, String text) async {
  final target=find.byKey(ValueKey('master-$key'));
  await tester.ensureVisible(target); await tester.pumpAndSettle(); await tester.enterText(target,text);
}
Future<void> chooseTarget(WidgetTester tester) async {
  await tester.tap(find.text('Petugas tujuan')); await tester.pumpAndSettle();
  await tester.tap(find.text('Petugas Sintetis Tujuan · S6-B · sisa 3').last); await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).last,'Pengalihan petugas untuk pemeriksaan');
}

void main() {
  for (final width in [390.0,1440.0]) {
    testWidgets('create operational agent with login and scroll at $width',(tester) async {
      tester.view.devicePixelRatio=1; tester.view.physicalSize=Size(width,844);
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      final writes=<Map<String,dynamic>>[];
      final api=Api(client:MockClient((r) async {
        if(r.url.path=='/api/auth/login') return login();
        expect(r.url.path,'/api/master/agents');expect(r.method,'POST');
        writes.add(jsonDecode(r.body) as Map<String,dynamic>);return response({'id':'SMG-S6'},201);
      }));addTearDown(api.dispose);
      await host(tester,api,MasterDialog(api:api,agent:true,regions:regions));
      await tester.tap(find.text('Simpan master'));await tester.pumpAndSettle();expect(writes,isEmpty);
      for(final entry in {'id':'SMG-S6','name':'Petugas Sintetis','approach':'Pendampingan','capacity':'3','username':'smg-s6','password':'DemoAssignment!2026'}.entries) {
        await fill(tester,entry.key,entry.value);
      }
      await tester.tap(find.text('Simpan master'));await tester.pumpAndSettle();
      expect(writes.single,{'id':'SMG-S6','name':'Petugas Sintetis','region_id':'SMG','kind':'collection','team':'A','channel':'Tele','approach':'Pendampingan','capacity':3,'active':true,'username':'smg-s6','password':'DemoAssignment!2026'});
      expect(find.byType(MasterDialog),findsNothing);expect(tester.takeException(),isNull);
    });

    testWidgets('override review cancel explicit payload and locked pending request at $width',(tester) async {
      tester.view.devicePixelRatio=1;tester.view.physicalSize=Size(width,844);
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      final pending=Completer<http.Response>();final writes=<Map<String,dynamic>>[];
      final api=Api(client:MockClient((r) async {
        if(r.url.path=='/api/auth/login')return login();
        if(r.method=='GET')return response(options());
        writes.add(jsonDecode(r.body) as Map<String,dynamic>);return pending.future;
      }));addTearDown(api.dispose);
      await host(tester,api,OverrideDialog(api:api,caseId:'TAG-S6'));
      await tester.tap(find.text('Tinjau override'));await tester.pumpAndSettle();expect(writes,isEmpty);
      await chooseTarget(tester);
      await tester.tap(find.text('Tinjau override'));await tester.pump(const Duration(milliseconds:400));
      expect(find.text('Konfirmasi override assignment'),findsOneWidget);
      await tester.tap(find.text('Batal'));await tester.pumpAndSettle();expect(writes,isEmpty);
      await tester.tap(find.text('Tinjau override'));await tester.pump(const Duration(milliseconds:400));
      await tester.tap(find.text('Terapkan override'));await tester.pump();
      expect(writes.length,1);expect(writes.single['agent_id'],'S6-B');expect(writes.single['expected_version'],2);
      expect((writes.single['request_key'] as String).length,greaterThanOrEqualTo(16));
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton,'Tutup')).onPressed,isNull);
      pending.complete(response({'assigned':true}));await tester.pumpAndSettle();
      expect(find.byType(OverrideDialog),findsNothing);expect(tester.takeException(),isNull);
    });
  }

  testWidgets('ambiguous override retries identical key and payload without reopening review',(tester) async {
    final writes=<String>[];
    final api=Api(client:MockClient((r) async {
      if(r.url.path=='/api/auth/login')return login();
      if(r.method=='GET')return response(options());
      writes.add(r.body);return writes.length==1 ? response({'detail':'Gateway unavailable'},503) : response({'assigned':true,'replayed':true});
    }));addTearDown(api.dispose);
    await host(tester,api,OverrideDialog(api:api,caseId:'TAG-S6'));await chooseTarget(tester);
    await tester.tap(find.text('Tinjau override'));await tester.pump(const Duration(milliseconds:400));
    await tester.tap(find.text('Terapkan override'));await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(find.byType(TextFormField).last).enabled,false);
    await tester.tap(find.text('Kirim ulang override'));await tester.pumpAndSettle();
    expect(writes.length,2);expect(writes[0],writes[1]);expect(find.byType(OverrideDialog),findsNothing);expect(api.token,'token');
  });

  testWidgets('stale master conflict refreshes revision and clears reason before retry',(tester) async {
    var gets=0;final writes=<Map<String,dynamic>>[];
    final api=Api(client:MockClient((r) async {
      if(r.url.path=='/api/auth/login')return login();
      if(r.method=='GET'){gets++;return response([{...regions.first,'version':2,'name':'Semarang terbaru'}]);}
      writes.add(jsonDecode(r.body) as Map<String,dynamic>);
      return writes.length==1 ? response({'detail':'Wilayah berubah. Muat ulang master.'},409) : response({'version':3});
    }));addTearDown(api.dispose);
    await host(tester,api,MasterDialog(api:api,agent:false,regions:regions,record:regions.first));
    await fill(tester,'reason','Perubahan nama wilayah demo');await tester.tap(find.text('Simpan master'));await tester.pumpAndSettle();
    expect(find.textContaining('Wilayah berubah.'),findsOneWidget);expect(api.token,'token');
    await tester.tap(find.text('Muat versi terbaru'));await tester.pumpAndSettle();expect(gets,1);
    await tester.tap(find.text('Simpan master'));await tester.pumpAndSettle();expect(writes.length,1);
    await fill(tester,'reason','Tinjau perubahan setelah refresh');await tester.tap(find.text('Simpan master'));await tester.pumpAndSettle();
    expect(writes.last['expected_version'],2);expect(writes.last['name'],'Semarang terbaru');expect(tester.takeException(),isNull);
  });

  testWidgets('master filters audit and network error hides stale list then retry',(tester) async {
    var failed=false;
    final api=Api(client:MockClient((r) async {
      if(r.url.path=='/api/auth/login')return login();
      if(failed) return response({'detail':'Layanan gagal'},503);
      if(r.url.path=='/api/master/regions')return response(regions);
      if(r.url.path=='/api/master/audit')return response([{'action':'override_assignment','username':'supervisor','case_id':'TAG-S6','created_at':'2026-10-28T02:00:00Z','detail':{'previous_agent':'OLD','agent_id':'NEW','cycle':2,'reason':'Alokasi petugas untuk demo'}}]);
      return response([{'id':'NEW','name':'Petugas Sintetis','active':1,'version':1,'kind':'collection','team':'B','channel':'Lapangan','region_id':'SMG','username':'new-demo','approach':'Pendampingan','capacity':3,'daily_load':0,'active_load':0}]);
    }));addTearDown(api.dispose);
    await host(tester,api,MasterPage(api:api),direct:true);expect(find.text('Petugas Sintetis'),findsOneWidget);
    await tester.enterText(find.byType(TextField),'absent');await tester.pumpAndSettle();expect(find.text('Tidak ada hasil'),findsOneWidget);
    await tester.tap(find.text('Audit perubahan'));await tester.pumpAndSettle();expect(find.text('OLD → NEW · siklus 2'),findsOneWidget);
    failed=true;await tester.tap(find.byTooltip('Muat ulang master'));await tester.pumpAndSettle();
    expect(find.text('OLD → NEW · siklus 2'),findsNothing);expect(find.text('Coba lagi master'),findsOneWidget);
    failed=false;await tester.tap(find.text('Coba lagi master'));await tester.pumpAndSettle();expect(find.text('OLD → NEW · siklus 2'),findsOneWidget);
  });

  testWidgets('definitive override conflict unlocks refresh with latest case version',(tester) async {
    var gets=0;var writes=0;
    final api=Api(client:MockClient((r) async {
      if(r.url.path=='/api/auth/login')return login();
      if(r.method=='GET')return response(options(++gets));
      writes++;return response({'detail':'Kapasitas penuh; kasus berubah'},409);
    }));addTearDown(api.dispose);
    await host(tester,api,OverrideDialog(api:api,caseId:'TAG-S6'));await chooseTarget(tester);
    await tester.tap(find.text('Tinjau override'));await tester.pump(const Duration(milliseconds:400));
    await tester.tap(find.text('Terapkan override'));await tester.pumpAndSettle();
    expect(writes,1);expect(tester.widget<TextFormField>(find.byType(TextFormField).last).enabled,true);
    await tester.tap(find.text('Muat pilihan terbaru'));await tester.pumpAndSettle();expect(gets,2);
    expect(find.textContaining('Versi kasus 2'),findsOneWidget);expect(tester.takeException(),isNull);
  });
}
