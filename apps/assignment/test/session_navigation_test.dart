import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:assignment_studio/api.dart';
import 'package:assignment_studio/main.dart';
import 'package:assignment_studio/shell.dart';
import 'package:assignment_studio/case_detail.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(800, 600), const Size(1440, 900)]) {
  testWidgets('session expiry removes routes/dialog at ${size.width.toInt()}px', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final stats = {'total':1,'unassigned':0,'active':1,'completed':0,'overdue':0,'amount':1000000,'realized':0};
    final caseData = {
      'id':'TAG-1','kind':'collection','customer':'Debitur Demo','region_id':'SMG',
      'difficulty':'Low','amount':1000000,'paid':0,'status':'assigned','score':80,
      'agent_id':'SMG-col-A','cycle':1,'version':2,'due_at':'2026-10-30T02:00:00+00:00',
    };
    final api = Api(client: MockClient((req) async {
      dynamic data;
      switch (req.url.path) {
        case '/api/auth/login':
          data = {'access_token':'demo','user':{'id':'U1','username':'supervisor','role':'supervisor'}};
        case '/api/dashboard': data = {'streams':{'collection':stats,'origination':stats}};
        case '/api/config': data = {'regions':[{'id':'SMG','name':'Semarang'}]};
        case '/api/cases': data = {'items':[caseData], 'total':1};
        case '/api/cases/TAG-1': data = {'case':caseData,'assignments':[],'activities':[],'recommendations':[],'target_team':'A'};
        case '/api/agents': data = [];
        case '/api/me': return http.Response('{"detail":"Expired"}',401);
        default: throw StateError('Unexpected path: ${req.url.path}');
      }
      return http.Response(jsonEncode(data),200);
    }));
    await api.login('supervisor','demo');
    await tester.pumpWidget(AssignmentApp(api:api));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), size.width < 1000 ? findsOneWidget : findsNothing);
    expect(tester.takeException(), isNull);
    final context = tester.element(find.byType(Workspace));
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CaseDetail(api:api,caseId:'TAG-1'))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'Detail layout');
    await tester.ensureVisible(find.text('Catat aktivitas'));
    await tester.tap(find.text('Catat aktivitas'));
    await tester.pumpAndSettle();
    expect(find.byType(ActivityDialog),findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'Activity dialog layout');
    await expectLater(api.request('GET','/api/me'),throwsA(isA<ApiException>()));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage),findsOneWidget);
    expect(find.byType(CaseDetail),findsNothing);
    expect(find.byType(ActivityDialog),findsNothing);
    expect(find.text('Sesi Anda berakhir. Silakan masuk kembali.'),findsOneWidget);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
  }
}
