import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:assignment_studio/agent_settings.dart';
import 'package:assignment_studio/api.dart';
import 'package:assignment_studio/widgets.dart';

const agent = {
  'id': 'SMG-col-A', 'name': 'Tele Semarang COL', 'capacity': 12,
  'active': 1, 'daily_load': 2, 'active_load': 1,
};

Future<void> openSettings(WidgetTester tester, Api api) async {
  await api.login('supervisor', 'demo');
  await tester.pumpWidget(MaterialApp(theme: studioTheme(), home: Builder(
    builder: (context) => Scaffold(body: TextButton(
      onPressed: () => showDialog<bool>(context: context, barrierDismissible: false,
        builder: (_) => AgentSettingsDialog(api: api, agent: agent)),
      child: const Text('Open settings'),
    )),
  )));
  await tester.tap(find.text('Open settings'));
  await tester.pumpAndSettle();
}

http.Response loginResponse() => http.Response(jsonEncode({
  'access_token': 'demo', 'user': {'role': 'supervisor', 'username': 'supervisor'},
}), 200);

void main() {
  for (final width in [390.0, 1440.0]) {
    testWidgets('capacity validation, conflict recovery and status update at $width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final requests = <Map<String, dynamic>>[];
      final api = Api(client: MockClient((request) async {
        if (request.url.path == '/api/auth/login') return loginResponse();
        expect(request.method, 'PATCH');
        expect(request.url.path, '/api/agents/SMG-col-A');
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return requests.length == 1
          ? http.Response('{"detail":"Kapasitas tidak boleh di bawah beban yang sudah berjalan hari ini."}', 409)
          : http.Response('{"ok":true}', 200);
      }));
      addTearDown(api.dispose);
      await openSettings(tester, api);
      expect(tester.takeException(), isNull);
      for (final invalid in ['0', '101', '12.5']) {
        await tester.enterText(find.byType(TextFormField), invalid);
        await tester.tap(find.text('Simpan pengaturan'));
        await tester.pumpAndSettle();
        expect(find.text('Masukkan bilangan bulat 1–100.'), findsOneWidget);
        expect(requests, isEmpty);
        expect(tester.takeException(), isNull);
      }
      await tester.enterText(find.byType(TextFormField), '1');
      await tester.tap(find.text('Simpan pengaturan'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Kapasitas tidak boleh di bawah'), findsOneWidget);
      expect(find.byType(AgentSettingsDialog), findsOneWidget);
      expect(api.token, 'demo');
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextFormField), '14');
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan pengaturan'));
      await tester.pumpAndSettle();
      expect(requests.last, {'capacity': 14, 'active': false});
      expect(find.byType(AgentSettingsDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('pending save prevents duplicate submission and closing', (tester) async {
    final pending = Completer<http.Response>();
    var writes = 0;
    final api = Api(client: MockClient((request) async {
      if (request.url.path == '/api/auth/login') return loginResponse();
      writes++;
      return pending.future;
    }));
    addTearDown(api.dispose);
    await openSettings(tester, api);
    await tester.tap(find.text('Simpan pengaturan'));
    await tester.pump();
    expect(writes, 1);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Tutup')).onPressed, isNull);
    expect(tester.widget<PopScope>(find.byType(PopScope).last).canPop, isFalse);
    expect(tester.widget<TextFormField>(find.byType(TextFormField)).enabled, isFalse);
    pending.complete(http.Response('{"ok":true}', 200));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(find.byType(AgentSettingsDialog), findsNothing);
  });
}
