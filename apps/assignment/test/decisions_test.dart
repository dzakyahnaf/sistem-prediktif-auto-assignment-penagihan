import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:assignment_studio/api.dart';
import 'package:assignment_studio/decisions_page.dart';
import 'package:assignment_studio/widgets.dart';

class Fixture {
  late final Api api;
  final posts = <Map<String, dynamic>>[];
  final Map<String, dynamic> config = {'medium_threshold': 60.0, 'collection_followup_hours': 72, 'origination_followup_hours': 72,
    'collection_base': 84.0, 'dpd_penalty': .43, 'interest_weight': 11.0, 'document_bonus': 18.0, 'income_bonus': 12.0, 'segment_release_id': null};
  int revision = 0; bool trained = false;
  int? failure;
  Map<String, dynamic> get segment => {'id': 'SEG-TEST', 'model_id': 'MOD-TEST', 'artifact_sha256': 'checksum', 'created_at': '2026-10-29T00:00:00Z',
    'report': {'warning': 'Segmen deskriptif sintetis.', 'models': [for (final key in ['collection_initial','origination_initial'])
      {'key': key, 'k': 2, 'stability_ari': [.9,.8,.9], 'subsets': {'train': {'n': 100,'silhouette': .2,'counts': {'S1':50,'S2':50}}},
        'profiles': [{'segment':'S1','n':50,'means':{'amount':5000000},'categories':{'difficulty':{'Low':50}}}], 'train_candidates': [{'k':2,'silhouette':.2}]}
    ]}};
  Fixture({String role = 'supervisor'}) {
    api = Api(client: MockClient((r) async {
      http.Response response(dynamic v, [int status = 200]) => http.Response(jsonEncode(v), status);
      if (r.url.path.endsWith('login')) return response({'access_token':'demo','user':{'role':role}});
      if (r.method == 'POST') {
        posts.add(Map<String,dynamic>.from(jsonDecode(r.body) as Map));
        if (failure != null) return response({'detail':'Keputusan gagal $failure'},failure!);
        if (r.url.path.endsWith('segments')) { trained = true; return response(segment,201); }
        revision++; config.addAll(posts.last['config'] as Map<String,dynamic>); return response({'revision':revision,'config':config});
      }
      return response({'policy':{'revision':revision,'config':config},'segments':trained ? [segment] : [],'history':[],'model_ids':['MOD-TEST']});
    }));
  }
  Future<void> open(WidgetTester t, [double width = 390]) async {
    t.view.physicalSize=Size(width,844);t.view.devicePixelRatio=1;
    addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);addTearDown(api.dispose);
    await api.login('demo','demo');await t.pumpWidget(MaterialApp(theme:studioTheme(),home:DecisionsPage(api:api)));await t.pumpAndSettle();
  }
}
Finder field(String label) => find.byWidgetPredicate((w)=>w is TextField && w.decoration?.labelText==label);
Future<void> tap(WidgetTester t, Finder f) async {
  if(f.evaluate().isEmpty) await t.scrollUntilVisible(f,450,scrollable:find.byType(Scrollable).first,maxScrolls:25);
  await t.ensureVisible(f);await t.pumpAndSettle();await t.tap(f);await t.pumpAndSettle();
}
Future<void> fill(WidgetTester t,String label,String value) async {
  final f=field(label);if(f.evaluate().isEmpty) await t.scrollUntilVisible(f,400,scrollable:find.byType(Scrollable).first,maxScrolls:25);
  await t.ensureVisible(f);await t.pumpAndSettle();await t.enterText(f,value);await t.pumpAndSettle();
}
void main() {
  for(final width in [390.0,1440.0]) {
    testWidgets('policy validation review cancel publish and segments at $width',(t) async {
      final f=Fixture();await f.open(t,width);
      await fill(t,'Ambang Medium ke Tim A','100');await fill(t,'Alasan kebijakan','Kebijakan sintetis untuk review');
      await tap(t,find.text('Tinjau kebijakan'));expect(f.posts,isEmpty);
      await t.drag(find.byType(ListView).first,const Offset(0,1500));await t.pumpAndSettle();
      await fill(t,'Ambang Medium ke Tim A','65');await tap(t,find.text('Tinjau kebijakan'));await tap(t,find.text('Batal'));expect(f.posts,isEmpty);
      await tap(t,find.text('Tinjau kebijakan'));await tap(t,find.text('Terbitkan'));expect(f.revision,1);expect(f.posts.single['config']['medium_threshold'],65);
      await tap(t,find.text('Tinjau training segmen'));await tap(t,find.text('Latih segmen'));expect(f.posts.last['model_id'],'MOD-TEST');
      await tap(t,find.text('Profil segmen collection_initial'));
      expect(find.textContaining('Rata-rata:'),findsOneWidget);expect(t.takeException(),isNull);
    });
  }
  testWidgets('ambiguous policy retries identical payload and key',(t) async {
    final f=Fixture();await f.open(t);f.failure=503;
    await fill(t,'Alasan kebijakan','Alasan pengujian retry kebijakan');await tap(t,find.text('Tinjau kebijakan'));await tap(t,find.text('Terbitkan'));
    final original=Map.of(f.posts.single);expect(t.state<DecisionsPageState>(find.byType(DecisionsPage)).pending,isNotNull);
    f.failure=null;await t.drag(find.byType(ListView).first,const Offset(0,2000));await t.pumpAndSettle();
    await tap(t,find.text('Periksa / ulangi keputusan'));expect(f.posts,[original,original]);expect(f.revision,1);
  });
  testWidgets('stale policy unlocks form and refresh loads current revision',(t) async {
    final f=Fixture();await f.open(t);f.failure=409;
    await fill(t,'Alasan kebijakan','Alasan konflik revisi kebijakan');await tap(t,find.text('Tinjau kebijakan'));await tap(t,find.text('Terbitkan'));
    expect(t.state<DecisionsPageState>(find.byType(DecisionsPage)).pending,isNull);
    f.failure=null;f.revision=3;f.config['medium_threshold']=77.0;
    await tap(t,find.byTooltip('Muat kebijakan terbaru'));await t.drag(find.byType(ListView).first,const Offset(0,2000));await t.pumpAndSettle();
    expect(t.widget<TextField>(field('Ambang Medium ke Tim A')).controller!.text,'77.0');expect(t.takeException(),isNull);
  });
  testWidgets('ambiguous segment training retains source payload',(t) async {
    final f=Fixture();await f.open(t);f.failure=503;
    await tap(t,find.text('Tinjau training segmen'));await tap(t,find.text('Latih segmen'));final original=Map.of(f.posts.single);
    f.failure=null;await t.drag(find.byType(ListView).first,const Offset(0,2000));await t.pumpAndSettle();
    await tap(t,find.text('Periksa / ulangi keputusan'));expect(f.posts,[original,original]);expect(f.trained,isTrue);
  });
  testWidgets('agent cannot load supervisor decision tools',(t) async {
    final f=Fixture(role:'agent');await f.open(t);expect(find.text('Keputusan memerlukan supervisor.'),findsOneWidget);expect(f.posts,isEmpty);
  });
}
