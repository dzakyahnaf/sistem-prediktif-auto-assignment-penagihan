import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:assignment_studio/api.dart';
import 'package:assignment_studio/imports_page.dart';
import 'package:assignment_studio/widgets.dart';

const mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

class ImportFixture {
  late final Api api;
  final key = GlobalKey<ImportsPageState>();
  final previews = <Map<String, dynamic>>[];
  final commits = <Map<String, dynamic>>[];
  final gets = <String>[];
  http.Request? uploaded;
  Future<http.Response>? Function(http.Request)? intercept;
  Map<String, dynamic>? current;
  int total = 2, invalid = 0, downloads = 0;
  bool ignored = false;

  ImportFixture() {
    api = Api(client: MockClient((request) async {
      final response = intercept?.call(request);
      if (response != null) return response;
      dynamic result;
      final path = request.url.path;
      if (path.endsWith('login')) return http.Response('{"access_token":"demo","user":{"role":"supervisor"}}', 200);
      if (path.endsWith('template')) return http.Response.bytes([80, 75, 3, 4], 200, headers: {'content-type': mime});
      if (request.method == 'GET') gets.add(request.url.toString());
      if (path.endsWith('/upload')) {
        uploaded = request;
        current = {'id': 'IMP-1', 'kind': request.url.queryParameters['kind'], 'filename': request.url.queryParameters['filename'], 'state': 'uploaded',
          'revision': 0, 'created_at': '2026-10-28T00:00:00Z', 'expires_at': '2026-10-29T00:00:00Z',
          'metadata': {'suggested_sheet': 'Data', 'suggested_header_row': 1, 'sheets': [{'name': 'Data', 'hidden': false}], 'warnings': []}};
        result = current;
      } else if (path.endsWith('/layout')) {
        result = {'sheet': 'Data', 'header_row': 1, 'fields': [
          for (final n in ['source_ref', 'customer', 'region_id', 'difficulty', 'amount', 'dpd']) {'name': n, 'label': fieldLabel(n), 'help': 'Isian demo', 'required': n != 'dpd'},
        ], 'columns': [for (var i = 1; i <= (ignored ? 7 : 6); i++) {'index': i, 'letter': String.fromCharCode(64 + i), 'header': 'Kolom $i'}],
          'mapping': {'source_ref': 1, 'customer': 2, 'region_id': 3, 'difficulty': 4, 'amount': 5, 'dpd': 6}};
      } else if (path.endsWith('/preview')) {
        final payload = jsonDecode(request.body) as Map<String, dynamic>; previews.add(payload);
        current!['revision'] = (current!['revision'] as int) + 1; current!['state'] = 'previewed';
        current!['preview'] = {'sheet': 'Data', 'header_row': 1, 'mapping': payload['mapping'], 'total': total, 'valid': total - invalid, 'invalid': invalid,
          'amount': (total - invalid) * 1000000, 'can_commit': invalid == 0, 'ignored_columns': ignored ? [{'index': 7, 'letter': 'G', 'header': 'Hasil Call'}] : [],
          'items': previewRows(0)};
        result = current;
      } else if (path.endsWith('/commit')) {
        commits.add(jsonDecode(request.body) as Map<String, dynamic>);
        makeCommitted(); result = current;
      } else if (path.endsWith('/discard')) {
        current!['state'] = 'discarded'; current!.remove('preview'); result = current;
      } else if (path == '/api/imports') {
        result = current == null ? [] : [{...current!, 'total': current!['result']?['total'] ?? 0}];
      } else {
        final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
        result = jsonDecode(jsonEncode(current));
        if (result['preview'] != null) result['preview']['items'] = previewRows(offset);
        if (result['result'] != null) result['result']['items'] = resultRows(offset);
      }
      return http.Response(jsonEncode(result), 200);
    }));
  }

  List<dynamic> previewRows(int offset) => List.generate(total, (i) => {
    'row': i + 2, 'source_ref': 'REF-$i', 'raw': {'customer': 'Alias Impor $i', 'amount': '1000000'},
    'data': {'score': 84}, 'team': 'A', 'errors': i < invalid ? ['Wilayah tidak terdaftar.'] : [],
  }).skip(offset).take(25).toList();
  List<dynamic> resultRows(int offset) => List.generate(total, (i) => {'case_id': 'TAG-$i', 'source_ref': 'REF-$i', 'customer': 'Alias Impor $i'}).skip(offset).take(25).toList();
  void makeCommitted() {
    current!['state'] = 'committed'; current!['result'] = {'total': total, 'committed_at': '2026-10-28T01:00:00Z', 'items': resultRows(0)};
  }
  Future<void> open(WidgetTester tester, {double width = 1440}) async {
    tester.view.devicePixelRatio = 1; tester.view.physicalSize = Size(width, 844);
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio); addTearDown(api.dispose);
    await api.login('supervisor', 'demo');
    await tester.pumpWidget(MaterialApp(theme: studioTheme(), home: ImportsPage(key: key, api: api, save: (bytes, name) async {
      expect(bytes, [80, 75, 3, 4]); expect(name, 'template-operasional-collection.xlsx'); downloads++;
    })));
    await tester.pumpAndSettle();
  }
  Future<void> upload(WidgetTester tester) async { await key.currentState!.upload(Uint8List.fromList([80, 75, 3, 4]), 'demo.xlsx'); await tester.pumpAndSettle(); }
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder); await tester.tap(finder);
  // Busy state intentionally remains active behind the confirmation dialog.
  await tester.pump(); await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  for (final width in [390.0, 1440.0]) {
    testWidgets('upload mapping preview cancel commit and status at $width', (tester) async {
      final f = ImportFixture(); await f.open(tester, width: width);
      await tap(tester, find.text('Unduh template operasional'));
      expect(f.downloads, 1);
      await f.upload(tester);
      expect(f.uploaded!.bodyBytes, [80, 75, 3, 4]); expect(f.uploaded!.headers['content-type'], mime);
      await tap(tester, find.text('Preview & validasi'));
      expect(find.text('2 valid'), findsOneWidget);
      await tap(tester, find.text('Impor 2 kasus')); await tap(tester, find.text('Batal'));
      expect(f.commits, isEmpty);
      await tap(tester, find.text('Impor 2 kasus')); await tap(tester, find.text('Impor sekarang'));
      expect(f.commits, [{'expected_revision': 1, 'acknowledge_ignored': false}]);
      expect(find.text('2 kasus berhasil diimpor'), findsOneWidget);
      await tap(tester, find.text('Muat ulang status'));
      expect(find.text('2 kasus berhasil diimpor'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('mapping edits invalidate preview and ignored columns need acknowledgment', (tester) async {
    final f = ImportFixture()..ignored = true; await f.open(tester); await f.upload(tester);
    await tap(tester, find.text('Preview & validasi'));
    final submit = find.widgetWithText(FilledButton, 'Impor 2 kasus');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tap(tester, find.byKey(const ValueKey('ack-ignored')));
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    final drop = find.byKey(const ValueKey('map-dpd-6'));
    await tap(tester, drop); await tap(tester, find.text('Tidak dipetakan').last);
    expect(find.text('Impor 2 kasus'), findsNothing);
    await tap(tester, find.text('Preview & validasi'));
    expect(f.previews.last['mapping'].containsKey('dpd'), isFalse);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tap(tester, find.byKey(const ValueKey('ack-ignored')));
    await tap(tester, find.text('Impor 2 kasus')); await tap(tester, find.text('Impor sekarang'));
    expect(f.commits.last, {'expected_revision': 2, 'acknowledge_ignored': true});
  });

  testWidgets('invalid row anywhere blocks commit and preview pagination retains totals', (tester) async {
    final f = ImportFixture()..total = 26..invalid = 1; await f.open(tester); await f.upload(tester);
    await tap(tester, find.text('Preview & validasi'));
    expect(find.text('1 bermasalah'), findsOneWidget);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Berikutnya').first);
    expect(find.text('Baris 27 · REF-25'), findsOneWidget);
    expect(find.text('Baris 2 · REF-0'), findsNothing);
    expect(f.gets.last, contains('offset=25'));
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Impor 26 kasus')).onPressed, isNull);
    expect(f.commits, isEmpty);
  });

  testWidgets('header validation and draft discard preserve no partial commit', (tester) async {
    final f = ImportFixture(); await f.open(tester); await f.upload(tester);
    final header = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Baris header (1–20)');
    await tester.enterText(header, '0'); await tester.pumpAndSettle();
    await tap(tester, find.text('Muat kolom'));
    expect(find.text('Baris header harus bilangan 1–20.'), findsOneWidget);
    await tap(tester, find.text('Buang draft')); await tap(tester, find.widgetWithText(FilledButton, 'Buang draft'));
    expect(find.textContaining('Draft tidak dapat diproses'), findsOneWidget);
    expect(f.commits, isEmpty);
  });

  testWidgets('ambiguous commit is checked through same batch and cannot be submitted twice', (tester) async {
    final f = ImportFixture(); await f.open(tester); await f.upload(tester);
    await tap(tester, find.text('Preview & validasi'));
    final pending = Completer<http.Response>(); var requests = 0;
    f.intercept = (r) { if (r.url.path.endsWith('/commit')) { requests++; f.makeCommitted(); return pending.future; } return null; };
    await tap(tester, find.text('Impor 2 kasus'));
    await tester.tap(find.text('Impor sekarang')); await tester.pump();
    expect(requests, 1);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Impor 2 kasus')).onPressed, isNull);
    pending.complete(http.Response('{"detail":"Respons belum pasti"}', 503)); await tester.pumpAndSettle();
    expect(find.textContaining('Hasil commit belum pasti'), findsOneWidget);
    await tap(tester, find.text('Periksa status commit'));
    expect(find.text('2 kasus berhasil diimpor'), findsOneWidget);
    expect(requests, 1);
  });

  test('XLSX bytes validate MIME and late upload cannot affect a new session', () async {
    final pending = Completer<http.Response>(); final started = Completer<void>();
    final api = Api(client: MockClient((r) async {
      if (r.url.path.endsWith('login')) return http.Response('{"access_token":"demo","user":{"role":"supervisor"}}', 200);
      if (r.url.path.endsWith('template')) return http.Response('not xlsx', 200, headers: {'content-type': 'text/html'});
      expect(r.bodyBytes, [80, 75]); expect(r.headers['content-type'], mime); started.complete(); return pending.future;
    }));
    addTearDown(api.dispose); await api.login('one', 'demo');
    await expectLater(api.exportWorkbook('/api/imports/template'), throwsA(isA<ApiException>()));
    final upload = api.uploadWorkbook(Uint8List.fromList([80, 75]), 'unicode & name.xlsx', 'collection');
    final check = expectLater(upload, throwsA(isA<ApiException>().having((e) => e.status, 'stale', 409)));
    await started.future; api.clearSession(); await api.login('two', 'demo');
    pending.complete(http.Response('{"id":"OLD"}', 201)); await check;
    expect(api.token, isNotNull);
  });
}
