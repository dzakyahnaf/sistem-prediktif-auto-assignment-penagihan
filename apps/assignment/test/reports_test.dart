import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:assignment_studio/api.dart';
import 'package:assignment_studio/reports_page.dart';
import 'package:assignment_studio/widgets.dart';

http.Response loginResponse() => http.Response('{"access_token":"demo","user":{"role":"supervisor"}}', 200);
http.Response csvResponse() => http.Response.bytes(utf8.encode('\ufeffid,customer\r\n1,Demo Ω\r\n'), 200, headers: {'content-type': 'text/csv; charset=utf-8'});

class ReportFixture {
  late final Api api;
  final queries = <Map<String, String>>[];
  Map<String, String>? exported;
  Future<http.Response>? Function(http.Request)? intercept;
  Uint8List? saved;
  String? filename;
  int count = 211, downloads = 0;
  ReportFixture() {
    api = Api(client: MockClient((request) async {
      final override = intercept?.call(request);
      if (override != null) return override;
      if (request.url.path.endsWith('login')) return loginResponse();
      if (request.url.path.endsWith('export')) { exported = Map.of(request.url.queryParameters); return csvResponse(); }
      final q = request.url.queryParameters;
      queries.add(Map.of(q));
      final start = int.parse(q['offset'] ?? '0');
      final cycles = q['view'] == 'cycles';
      final total = cycles ? 2 : count;
      final rows = List.generate(total, (i) => {
        'id': 'TAG-$i', 'case_id': 'TAG-$i', 'customer': 'Demo laporan $i', 'region_name': 'Semarang', 'agent_name': 'Petugas Demo',
        'amount': 1000000, 'paid': 200000, 'status': 'in_progress', 'created_at': '2026-10-27T17:00:00+00:00',
        'cycle': 1, 'outcome': 'success', 'overdue': false, 'assigned_at': '2026-10-28T00:00:00+00:00', 'ended_at': null,
        'realized': 200000, 'activity_count': 1, 'case_status': 'paid',
      }).skip(start).take(25).toList();
      final summary = cycles ? {'total': total, 'success': 1, 'no_success': 0, 'superseded': 1, 'active': 0, 'overdue': 0, 'realized': 1000000, 'success_rate': 100.0}
        : {'total': total, 'amount': total * 1000000, 'realized': total * 200000, 'outstanding': total * 800000, 'unassigned': 0, 'active': total, 'completed': 0, 'rejected': 0};
      return http.Response(jsonEncode({'total': total, 'items': rows, 'summary': summary, 'by_agent': [], 'generated_at': '2026-10-28T00:00:00+00:00'}), 200);
    }));
  }
  Future<void> open(WidgetTester tester, {double width = 1440}) async {
    tester.view.physicalSize = Size(width, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio); addTearDown(api.dispose);
    await api.login('supervisor', 'demo');
    await tester.pumpWidget(MaterialApp(theme: studioTheme(), home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(20), child:
      ReportsPage(api: api, regions: const [{'id': 'SMG', 'name': 'Semarang'}, {'id': 'BDG', 'name': 'Bandung'}], agents: const [
        {'id': 'SMG-col-A', 'name': 'Petugas Penagihan Semarang', 'kind': 'collection', 'region_id': 'SMG'},
        {'id': 'SMG-ori-A', 'name': 'Petugas Pengajuan Semarang', 'kind': 'origination', 'region_id': 'SMG'},
      ], save: (bytes, name) async { saved = bytes; filename = name; downloads++; }),
    ))));
    await tester.pumpAndSettle();
  }
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder); await tester.tap(finder); await tester.pumpAndSettle();
}

Finder field(String label) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label);

Future<void> choose(WidgetTester tester, String label, String value) async {
  final drop = find.byWidgetPredicate((w) => w is DropdownButtonFormField<String> && w.decoration.labelText == label);
  await tap(tester, drop);
  await tester.tap(find.text(value).last); await tester.pumpAndSettle();
}

void main() {
  for (final width in [390.0, 1440.0]) {
    testWidgets('report pagination and complete CSV with confirmation at $width', (tester) async {
      final f = ReportFixture(); await f.open(tester, width: width);
      expect(find.text('211 baris ditemukan · 25 baris per halaman'), findsOneWidget);
      await tap(tester, find.widgetWithText(OutlinedButton, 'Berikutnya').first);
      expect(f.queries.last['offset'], '25');
      expect(find.text('Demo laporan 25'), findsOneWidget);
      expect(find.text('Demo laporan 0'), findsNothing);
      final button = find.text('Unduh CSV (211 baris)');
      await tap(tester, button);
      expect(find.textContaining('211 baris pada seluruh halaman'), findsOneWidget);
      await tap(tester, find.text('Batal'));
      expect(f.exported, isNull);
      await tap(tester, button); await tap(tester, find.text('Unduh'));
      expect(f.exported, {'kind': 'collection', 'view': 'cases'});
      expect(utf8.decode(f.saved!), contains('Demo Ω'));
      expect(f.filename, 'collection-cases-demo.csv');
      expect(f.downloads, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('draft filters hide old data, validate dates and export applied query only', (tester) async {
    final f = ReportFixture(); await f.open(tester);
    await tester.enterText(field('Tanggal awal (WIB)'), '2026-02-30');
    await tester.pumpAndSettle();
    expect(find.textContaining('Unduh CSV ('), findsNothing);
    await tap(tester, find.text('Tampilkan laporan'));
    expect(find.text('Gunakan YYYY-MM-DD (1900–2100).'), findsOneWidget);
    await tester.enterText(field('Tanggal awal (WIB)'), '2026-10-29');
    await tester.enterText(field('Tanggal akhir (WIB)'), '2026-10-28');
    await tap(tester, find.text('Tampilkan laporan'));
    expect(find.text('Tanggal awal tidak boleh melewati tanggal akhir.'), findsOneWidget);
    await tester.enterText(field('Tanggal awal (WIB)'), '2026-10-28');
    await tester.enterText(field('Cari ID atau nama'), 'Target & 100%_');
    await choose(tester, 'Wilayah', 'Semarang');
    await choose(tester, 'Petugas', 'Petugas Penagihan Semarang');
    await choose(tester, 'Status kasus', 'Lunas');
    await tap(tester, find.text('Tampilkan laporan'));
    final expected = {'kind': 'collection', 'view': 'cases', 'region_id': 'SMG', 'agent_id': 'SMG-col-A', 'status': 'paid', 'date_from': '2026-10-28', 'date_to': '2026-10-28', 'q': 'Target & 100%_'};
    expect(f.queries.last, {...expected, 'offset': '0', 'limit': '25'});
    await tap(tester, find.text('Unduh CSV (211 baris)')); await tap(tester, find.text('Unduh'));
    expect(f.exported, expected);
    await choose(tester, 'Wilayah', 'Bandung');
    await choose(tester, 'Alur', 'Pengajuan');
    await choose(tester, 'Jenis laporan', 'Siklus assignment');
    await tap(tester, find.text('Tampilkan laporan'));
    expect(f.queries.last.containsKey('agent_id'), isFalse);
    expect(f.queries.last.containsKey('status'), isFalse);
    expect(f.queries.last['view'], 'cycles');
    expect(find.text('Keberhasilan hasil final'), findsOneWidget);
    expect(find.text('100.0%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale preview cannot replace changed filters; failure hides data and retries', (tester) async {
    final f = ReportFixture(); await f.open(tester);
    final pending = Completer<http.Response>();
    f.intercept = (r) => r.url.path == '/api/reports' ? pending.future : null;
    await tester.ensureVisible(find.text('Tampilkan laporan'));
    await tester.tap(find.text('Tampilkan laporan')); await tester.pump();
    await choose(tester, 'Alur', 'Pengajuan');
    pending.complete(http.Response('{"total":999}', 200)); await tester.pumpAndSettle();
    expect(find.textContaining('Unduh CSV ('), findsNothing);
    f.intercept = (r) => Future.value(http.Response('{"detail":"Gangguan laporan"}', 503));
    await tap(tester, find.text('Tampilkan laporan'));
    expect(find.text('Gangguan laporan'), findsOneWidget);
    expect(find.text('Demo laporan 0'), findsNothing);
    f.intercept = null; f.count = 0;
    await tap(tester, find.text('Coba lagi laporan'));
    expect(find.text('Tidak ada hasil laporan'), findsOneWidget);
    await tap(tester, find.text('Unduh CSV (0 baris)')); await tap(tester, find.text('Unduh'));
    expect(f.exported!['kind'], 'origination');
    expect(f.downloads, 1);
  });

  testWidgets('reset restores default domain/view and clears invalid dates without old dropdown callbacks', (tester) async {
    final f = ReportFixture(); await f.open(tester);
    await choose(tester, 'Alur', 'Pengajuan');
    await choose(tester, 'Jenis laporan', 'Siklus assignment');
    await choose(tester, 'Wilayah', 'Semarang');
    await choose(tester, 'Petugas', 'Petugas Pengajuan Semarang');
    await choose(tester, 'Hasil siklus', 'Berhasil');
    await tester.enterText(field('Tanggal awal (WIB)'), '2026-02-30');
    await tester.enterText(field('Cari ID atau nama'), 'Target');
    await tap(tester, find.text('Tampilkan laporan'));
    expect(find.text('Gunakan YYYY-MM-DD (1900–2100).'), findsOneWidget);
    await tap(tester, find.text('Reset filter'));
    expect(f.queries.last, {'kind': 'collection', 'view': 'cases', 'offset': '0', 'limit': '25'});
    expect(find.text('Gunakan YYYY-MM-DD (1900–2100).'), findsNothing);
    expect(tester.widget<TextField>(field('Tanggal awal (WIB)')).controller!.text, isEmpty);
    expect(tester.widget<TextField>(field('Cari ID atau nama')).controller!.text, isEmpty);
    await tap(tester, find.text('Unduh CSV (211 baris)')); await tap(tester, find.text('Unduh'));
    expect(f.exported, {'kind': 'collection', 'view': 'cases'});
  });

  testWidgets('pending download prevents duplicates and stale session never saves bytes', (tester) async {
    final f = ReportFixture(); await f.open(tester);
    final pending = Completer<http.Response>(); var exports = 0;
    f.intercept = (r) { if (r.url.path.endsWith('export')) { exports++; return pending.future; } return null; };
    await tap(tester, find.text('Unduh CSV (211 baris)'));
    await tester.tap(find.text('Unduh')); await tester.pumpAndSettle();
    expect(exports, 1);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Menyiapkan CSV…')).onPressed, isNull);
    f.api.clearSession(); await f.api.login('second', 'demo');
    pending.complete(csvResponse()); await tester.pumpAndSettle();
    expect(f.downloads, 0); expect(exports, 1);
  });

  test('binary export validates MIME and keeps session on 403 or invalid response', () async {
    var result = csvResponse();
    final api = Api(client: MockClient((r) async => r.url.path.endsWith('login') ? loginResponse() : result));
    addTearDown(api.dispose); await api.login('supervisor', 'demo');
    expect((await api.exportCsv('/api/reports/export?kind=collection')).take(3), [239, 187, 191]);
    result = http.Response('<html>Error</html>', 200, headers: {'content-type': 'text/html'});
    await expectLater(api.exportCsv('/api/reports/export'), throwsA(isA<ApiException>())); expect(api.token, isNotNull);
    result = http.Response('{"detail":"Supervisor saja"}', 403);
    await expectLater(api.exportCsv('/api/reports/export'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 403))); expect(api.token, isNotNull);
    result = http.Response('Expired', 401);
    await expectLater(api.exportCsv('/api/reports/export'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401))); expect(api.token, isNull);
  });
}
