import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:assignment_studio/api.dart';
import 'package:assignment_studio/main.dart';

Map<String, dynamic> record(int i, {String kind = 'collection', String status = 'new'}) => {
  'id': 'TEST-${i.toString().padLeft(3, '0')}', 'customer': 'Pagination Demo $i',
  'kind': kind, 'status': status, 'region_id': 'SMG', 'amount': 1000, 'paid': 0,
  'difficulty': 'Low', 'score': 84, 'agent_id': null, 'cycle': 0, 'version': 1,
  'due_at': null, 'income': 5000, 'interest': 3, 'documents_complete': 1,
};

class QueueFixture {
  final List<Map<String, dynamic>> cases;
  final queries = <Map<String, String>>[];
  List<dynamic>? assigned;
  Future<http.Response>? Function(http.Request)? intercept;
  late final Api api;

  QueueFixture([int count = 225]) : cases = List.generate(count, (i) => record(i)) {
    api = Api(client: MockClient((request) async {
      final intercepted = intercept?.call(request);
      if (intercepted != null) return intercepted;
      dynamic result;
      switch (request.url.path) {
        case '/api/auth/login': result = {'access_token': 'demo', 'user': {'role': 'supervisor', 'username': 'supervisor'}};
        case '/api/dashboard':
          final stats = {'total': cases.length, 'unassigned': cases.length, 'active': 0, 'completed': 0, 'overdue': 0, 'realized': 0};
          result = {'streams': {'collection': stats, 'origination': stats}};
        case '/api/config': result = {'regions': [{'id': 'SMG', 'name': 'Semarang'}]};
        case '/api/agents': result = [];
        case '/api/cases':
          final q = request.url.queryParameters;
          if (q.containsKey('kind')) queries.add(Map.of(q));
          final offset = int.parse(q['offset'] ?? '0');
          final limit = int.parse(q['limit'] ?? '50');
          final matches = cases.where((c) =>
            (!q.containsKey('kind') || c['kind'] == q['kind']) &&
            (!q.containsKey('status') || c['status'] == q['status']) &&
            (!q.containsKey('q') || '${c['id']} ${c['customer']} ${c['region_id']}'.toLowerCase().contains(q['q']!.toLowerCase()))).toList();
          result = {'items': matches.skip(offset).take(limit).toList(), 'total': matches.length, 'offset': offset, 'limit': limit};
        case '/api/assignments':
          assigned = (jsonDecode(request.body) as Map)['case_ids'] as List;
          result = {'results': assigned!.map((id) => {'case_id': id, 'assigned': false, 'reason': 'Demo'}).toList()};
        default:
          final id = request.url.path.split('/').last;
          final c = cases.firstWhere((c) => c['id'] == id);
          result = {'case': c, 'target_team': 'A', 'assignments': [], 'activities': [], 'recommendations': []};
      }
      return http.Response(jsonEncode(result), 200);
    }));
  }

  Future<void> open(WidgetTester tester, {double width = 1440}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(api.dispose);
    await api.login('supervisor', 'demo');
    await tester.pumpWidget(AssignmentApp(api: api));
    await tester.pumpAndSettle();
    if (width < 1000) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Penagihan')));
    } else {
      await tester.tap(find.widgetWithText(ListTile, 'Penagihan'));
    }
    await tester.pumpAndSettle();
  }
}

Future<void> next(WidgetTester tester) async {
  await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Berikutnya').first);
  await tester.tap(find.widgetWithText(OutlinedButton, 'Berikutnya').first);
  await tester.pumpAndSettle();
}

Future<void> search(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [390.0, 1440.0]) {
    testWidgets('browse beyond 200 with bounded pages at $width', (tester) async {
      final f = QueueFixture();
      await f.open(tester, width: width);
      expect(find.text('1–25 dari 225 kasus'), findsOneWidget);
      for (var page = 2; page <= 9; page++) { await next(tester); }
      expect(find.text('201–225 dari 225 kasus'), findsOneWidget);
      expect(find.text('Pagination Demo 224'), findsOneWidget);
      expect(find.text('Pagination Demo 0'), findsNothing);
      expect(f.queries.last['offset'], '200');
      expect(f.queries.every((q) => q['limit'] == '25'), isTrue);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Berikutnya').first).onPressed, isNull);
      await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Sebelumnya').first);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Sebelumnya').first);
      await tester.pumpAndSettle();
      expect(find.text('176–200 dari 225 kasus'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('server search resets page, encodes query and supports origination filters', (tester) async {
    final f = QueueFixture();
    f.cases.last['customer'] = 'Target & 100%_';
    f.cases.addAll([record(300, kind: 'origination', status: 'documents'), record(301, kind: 'origination', status: 'rejected')]);
    await f.open(tester);
    await next(tester);
    await search(tester, 'Target & 100%_');
    expect(f.queries.last['q'], 'Target & 100%_');
    expect(f.queries.last['offset'], '0');
    expect(find.text('1–1 dari 1 kasus'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Text && w.data == 'Target & 100%_'), findsOneWidget);
    await search(tester, 'SMG');
    expect(find.text('1–25 dari 225 kasus'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Pengajuan'));
    await tester.pumpAndSettle();
    expect(f.queries.last.containsKey('q'), isFalse);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Dokumen lengkap'));
    await tester.pumpAndSettle();
    expect(f.queries.last['status'], 'documents');
    expect(find.text('1–1 dari 1 kasus'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Ditolak'));
    await tester.pumpAndSettle();
    expect(f.queries.last['status'], 'rejected');
    expect(find.text('Pagination Demo 301'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final duringDebounce in [true, false]) {
    testWidgets('stale search ignored ${duringDebounce ? 'during debounce' : 'after new response'}', (tester) async {
      final f = QueueFixture();
      await f.open(tester);
      final old = Completer<http.Response>();
      f.intercept = (request) => request.url.queryParameters['q'] == 'lama' ? old.future : null;
      await tester.enterText(find.byType(TextField), 'lama');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Pagination Demo 224');
      if (!duringDebounce) {
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
      }
      old.complete(http.Response(jsonEncode({'items': [record(999)], 'total': 1}), 200));
      await tester.pump();
      expect(find.text('Pagination Demo 999'), findsNothing);
      if (duringDebounce) { await tester.pump(const Duration(milliseconds: 350)); }
      await tester.pumpAndSettle();
      expect(find.byWidgetPredicate((w) => w is Text && w.data == 'Pagination Demo 224'), findsOneWidget);
      expect(find.text('Pagination Demo 999'), findsNothing);
    });
  }

  testWidgets('shrinking last page recovers after returning from detail', (tester) async {
    final f = QueueFixture(26);
    await f.open(tester);
    await next(tester);
    await tester.tap(find.text('Pagination Demo 25'));
    await tester.pumpAndSettle();
    f.cases.removeLast();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('1–25 dari 25 kasus'), findsOneWidget);
    expect(f.queries.map((q) => q['offset']).toList(), ['0', '25', '25', '0']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed page hides stale rows and retries the same offset', (tester) async {
    final f = QueueFixture();
    await f.open(tester);
    var failed = false;
    f.intercept = (request) {
      if (request.url.queryParameters['offset'] == '25' && !failed) {
        failed = true;
        return Future.value(http.Response('{"detail":"Layanan sementara tidak tersedia."}', 503));
      }
      return null;
    };
    await next(tester);
    expect(find.text('Layanan sementara tidak tersedia.'), findsOneWidget);
    expect(find.text('Pagination Demo 0'), findsNothing);
    final assignment = find.widgetWithText(FilledButton, 'Tinjau & tugaskan (0)');
    expect(tester.widget<FilledButton>(assignment).onPressed, isNull);
    await tester.tap(find.text('Coba lagi antrean'));
    await tester.pumpAndSettle();
    expect(find.text('26–50 dari 225 kasus'), findsOneWidget);
    expect(f.queries.last['offset'], '25');
  });

  testWidgets('late collection response cannot replace origination queue', (tester) async {
    final f = QueueFixture();
    f.cases.add(record(500, kind: 'origination'));
    await f.open(tester);
    final old = Completer<http.Response>();
    f.intercept = (request) => request.url.queryParameters['q'] == 'lama' ? old.future : null;
    await tester.enterText(find.byType(TextField), 'lama');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'Pengajuan'));
    await tester.pumpAndSettle();
    old.complete(http.Response(jsonEncode({'items': [record(999)], 'total': 1}), 200));
    await tester.pumpAndSettle();
    expect(find.text('Pagination Demo 500'), findsOneWidget);
    expect(find.text('Pagination Demo 999'), findsNothing);
    expect(find.text('1–1 dari 1 kasus'), findsOneWidget);
  });

  testWidgets('batch assignment sends only current page and preserves offset', (tester) async {
    final f = QueueFixture();
    await f.open(tester);
    await next(tester);
    await tester.tap(find.text('Pilih halaman ini'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tinjau & tugaskan (25)'));
    await tester.pumpAndSettle();
    expect(find.text('Tugaskan 25 kasus terpilih?'), findsOneWidget);
    await tester.tap(find.text('Tugaskan'));
    await tester.pumpAndSettle();
    expect(f.assigned, f.cases.skip(25).take(25).map((c) => c['id']).toList());
    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();
    expect(find.text('26–50 dari 225 kasus'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 1440.0]) {
    testWidgets('explicit selection across pages, review cancel and partial result at $width', (tester) async {
      final f = QueueFixture();
      await f.open(tester, width: width);
      await tester.ensureVisible(find.byKey(const ValueKey('select-TEST-000')));
      await tester.tap(find.byKey(const ValueKey('select-TEST-000')));
      await tester.pumpAndSettle();
      await next(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('select-TEST-025')));
      await tester.tap(find.byKey(const ValueKey('select-TEST-025')));
      await tester.pumpAndSettle();
      final review = find.text('Tinjau & tugaskan (2)');
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(find.textContaining('1 pilihan dari halaman lain'), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Pagination Demo 0')), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Pagination Demo 25')), findsOneWidget);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(f.assigned, isNull);
      expect(review, findsOneWidget);
      f.intercept = (request) {
        if (request.url.path != '/api/assignments') return null;
        f.assigned = (jsonDecode(request.body) as Map)['case_ids'] as List;
        f.cases[0]['agent_id'] = 'SMG-col-A'; f.cases[0]['status'] = 'assigned';
        return Future.value(http.Response(jsonEncode({'results': [
          {'case_id': 'TEST-000', 'assigned': true, 'agent_id': 'SMG-col-A'},
          {'case_id': 'TEST-025', 'assigned': false, 'reason': 'Kapasitas penuh'},
        ]}), 200));
      };
      await tester.tap(review);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tugaskan'));
      await tester.pumpAndSettle();
      expect(f.assigned, ['TEST-000', 'TEST-025']);
      expect(find.text('1 ditugaskan · 1 belum ditugaskan.'), findsOneWidget);
      expect(find.text('Kapasitas penuh'), findsOneWidget);
      await tester.tap(find.text('Tutup'));
      await tester.pumpAndSettle();
      expect(find.text('Tinjau & tugaskan (1)'), findsOneWidget);
      expect(find.text('26–50 dari 225 kasus'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('selection capped at 100 with deselection and visible page deduplication', (tester) async {
    final f = QueueFixture();
    await f.open(tester);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Pilih halaman ini'));
      await tester.pumpAndSettle();
      await next(tester);
    }
    expect(find.text('100/100 kasus terpilih · 100 dari halaman lain'), findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Pilih halaman ini')).onPressed, isNull);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('select-TEST-100'))).onChanged, isNull);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sebelumnya').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('select-TEST-075')));
    await tester.tap(find.byKey(const ValueKey('select-TEST-075')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Pilih halaman ini'));
    await tester.tap(find.text('Pilih halaman ini'));
    await tester.pumpAndSettle();
    expect(find.text('Tinjau & tugaskan (100)'), findsOneWidget);
    await tester.ensureVisible(find.text('Tinjau & tugaskan (100)'));
    await tester.tap(find.text('Tinjau & tugaskan (100)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tugaskan'));
    await tester.pumpAndSettle();
    expect(f.assigned!.length, 100);
    expect(f.assigned!.toSet().length, 100);
    expect(f.assigned!.toSet(), f.cases.take(100).map((c) => c['id']).toSet());
    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();
  });

  testWidgets('selection clears on search, filter and domain; terminal or assigned unavailable', (tester) async {
    final f = QueueFixture();
    f.cases[0]['agent_id'] = 'SMG-col-A'; f.cases[0]['status'] = 'assigned';
    f.cases[1]['status'] = 'paid';
    await f.open(tester);
    for (final id in ['TEST-000', 'TEST-001']) {
      expect(tester.widget<CheckboxListTile>(find.byKey(ValueKey('select-$id'))).onChanged, isNull);
    }
    await tester.tap(find.text('Pilih halaman ini')); await tester.pumpAndSettle();
    expect(find.text('Tinjau & tugaskan (23)'), findsOneWidget);
    await search(tester, 'SMG');
    expect(find.text('Tinjau & tugaskan (0)'), findsOneWidget);
    await tester.tap(find.text('Pilih halaman ini')); await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Belum ditugaskan')); await tester.pumpAndSettle();
    expect(find.text('Tinjau & tugaskan (0)'), findsOneWidget);
    await tester.tap(find.text('Pilih halaman ini')); await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Pengajuan')); await tester.pumpAndSettle();
    expect(find.text('Tinjau & tugaskan (0)'), findsOneWidget);
  });

  testWidgets('in-flight batch submits once and refresh removes externally assigned selection', (tester) async {
    final f = QueueFixture();
    await f.open(tester);
    await tester.tap(find.text('Pilih halaman ini')); await tester.pumpAndSettle();
    await tester.tap(find.text('Tinjau & tugaskan (25)')); await tester.pumpAndSettle();
    final pending = Completer<http.Response>();
    var posts = 0;
    f.intercept = (request) {
      if (request.url.path == '/api/assignments') { posts++; return pending.future; }
      return null;
    };
    await tester.tap(find.text('Tugaskan')); await tester.pump();
    expect(posts, 1);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Memproses…')).onPressed, isNull);
    f.cases[0]['agent_id'] = 'SMG-col-A'; f.cases[0]['status'] = 'assigned';
    pending.complete(http.Response('{"detail":"Hasil belum pasti"}', 503));
    await tester.pumpAndSettle();
    expect(find.text('Tinjau & tugaskan (24)'), findsOneWidget);
    expect(find.textContaining('Pilihan disimpan'), findsOneWidget);
    expect(posts, 1);
  });

  testWidgets('agent sees no selection controls', (tester) async {
    final f = QueueFixture();
    f.intercept = (request) => request.url.path == '/api/auth/login'
      ? Future.value(http.Response('{"access_token":"demo","user":{"role":"agent","username":"smg-col-a"}}', 200)) : null;
    await f.open(tester);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('Pilih halaman ini'), findsNothing);
    expect(find.textContaining('Tinjau & tugaskan'), findsNothing);
  });
}
