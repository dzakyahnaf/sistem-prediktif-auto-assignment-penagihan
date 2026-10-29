import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:assignment_studio/api.dart';
import 'package:assignment_studio/main.dart';
import 'package:assignment_studio/case_detail.dart';

void main() {
  for(final width in [390.0,1440.0]) {
    testWidgets('public viewer reads detail without mutation controls at $width',(t) async {
      t.view.devicePixelRatio=1;t.view.physicalSize=Size(width,844);
      addTearDown(t.view.resetDevicePixelRatio);addTearDown(t.view.resetPhysicalSize);
      final stats={'total':1,'unassigned':0,'active':1,'completed':0,'overdue':0,'amount':1000000,'realized':0};
      final caseData={'id':'TAG-VIEW','kind':'collection','customer':'Demo baca','region_id':'SMG','difficulty':'Low','amount':1000000,'paid':0,'status':'assigned','score':80,'agent_id':'SMG-col-A','cycle':1,'version':2,'due_at':'2026-10-30T02:00:00+00:00'};
      final api=Api(client:MockClient((r) async {
        dynamic data;
        switch(r.url.path) {
          case '/api/auth/login':data={'access_token':'viewer','user':{'id':'V','username':'demo','role':'viewer'}};
          case '/api/dashboard':data={'streams':{'collection':stats,'origination':stats}};
          case '/api/config':data={'regions':[{'id':'SMG','name':'Semarang'}]};
          case '/api/cases':data={'items':[caseData],'total':1};
          case '/api/cases/TAG-VIEW':data={'case':caseData,'assignments':[],'activities':[],'recommendations':[],'target_team':'A'};
          default:throw StateError('Viewer must not request ${r.url.path}');
        }
        return http.Response(jsonEncode(data),200);
      }));
      await api.login('demo','public');expect(api.readOnly,isTrue);expect(api.supervisor,isFalse);
      await t.pumpWidget(AssignmentApp(api:api));await t.pumpAndSettle();
      expect(find.text('Operasi & notifikasi'),findsNothing);expect(find.text('Model & evaluasi'),findsNothing);
      final ctx=t.element(find.byType(Navigator).first);
      unawaited(Navigator.of(ctx).push(MaterialPageRoute<void>(builder:(_)=>CaseDetail(api:api,caseId:'TAG-VIEW'))));
      await t.pumpAndSettle();
      expect(find.text('Demo baca'),findsWidgets);
      for(final label in ['Catat aktivitas','Tindak lanjut simulasi','Penugasan ulang','Pilih petugas tertentu']) {expect(find.text(label),findsNothing);}
      expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());api.dispose();
    });
  }
}
