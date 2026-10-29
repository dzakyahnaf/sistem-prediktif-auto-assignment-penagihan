import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:assignment_studio/analytics_page.dart';
import 'package:assignment_studio/api.dart';
import 'package:assignment_studio/widgets.dart';

class Fixture {
  late final Api api;
  final posts = <Map<String, dynamic>>[], queries = <Map<String, String>>[];
  Future<http.Response>? Function(http.Request)? intercept;
  int exports = 0;
  Uint8List? saved;
  Map<String, dynamic> get run => {
    'id': 'HIST-TEST', 'created_at': '2026-10-28T00:00:00+00:00',
    'config': {'cases_per_kind': 3000, 'seed': 281026, 'start_date': '2024-10-01', 'train_until': '2026-02-01', 'validation_until': '2026-06-01', 'as_of': '2026-10-01'},
    'manifest': {'simulator_version': 'history-simulator-v1', 'feature_version': 'point-in-time-v1',
      'labels': {'origination_days': 30}, 'counts': {'cases': 6000, 'samples': 7000}, 'data_sha256': 'verified-dataset-hash',
      'datasets': [{'kind': 'collection', 'stage': 'initial', 'total': 3000,
        'splits': {'train': {'total': 1000, 'positive': 400, 'negative': 600}}, 'excluded': {'censored': 10}, 'demo_training_ready': true}],
      'warnings': ['Seluruh data simulasi.']},
  };
  Fixture({String role = 'supervisor'}) {
    api = Api(client: MockClient((r) async {
      if (r.url.path.endsWith('login')) return http.Response(jsonEncode({'access_token': 'demo', 'user': {'role': role}}), 200);
      if (r.method == 'POST') posts.add(Map<String, dynamic>.from(jsonDecode(r.body) as Map));
      final override = intercept?.call(r); if (override != null) return override;
      if (r.method == 'POST') return http.Response(jsonEncode(run), 201);
      if (r.url.path.endsWith('export')) { exports++; return http.Response.bytes([80, 75, 3, 4], 200, headers: {'content-type': 'application/zip'}); }
      if (r.url.path.endsWith('samples')) {
        final q = r.url.queryParameters; queries.add(q);
        final start = int.parse(q['offset'] ?? '0');
        return http.Response(jsonEncode({'total': 52, 'items': List.generate(25, (i) => {
          'id': 'Sample-${start+i}', 'case_id': 'C-${start+i}', 'entity_id': 'E-$i', 'split': q['split'] == 'excluded' ? 'excluded' : 'train',
          'label': 0, 'exclusion': q['split'] == 'excluded' ? 'censored' : null, 'decision_at': '2025-01-01T01:00:00+00:00',
          'feature_max_at': '2025-01-01T00:00:00+00:00', 'label_ready_at': '2025-01-04T01:00:00+00:00',
          'features': {'amount': 100000, if (q['stage'] == 'reassignment') 'closed_cycles': 1}, 'team': 'A', 'assignment_propensity': 1.0,
        })}), 200);
      }
      if (r.url.path.endsWith('HIST-TEST')) return http.Response(jsonEncode(run), 200);
      return http.Response(jsonEncode({'items': [run], 'total': 1}), 200);
    }));
  }
  Future<void> open(WidgetTester t, {double width = 390}) async {
    t.view.physicalSize = Size(width, 844); t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio); addTearDown(api.dispose);
    await api.login('demo', 'demo');
    await t.pumpWidget(MaterialApp(theme: studioTheme(), home: AnalyticsPage(api: api, save: (b, n) async { saved = b; })));
    await t.pumpAndSettle();
  }
}

Future<void> tap(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) await t.scrollUntilVisible(f, 450, scrollable: find.byType(Scrollable).first, maxScrolls: 30);
  await t.ensureVisible(f); await t.pumpAndSettle(); await t.tap(f); await t.pumpAndSettle();
}

Future<void> choose(WidgetTester t, String label, String value) async {
  final f = find.byWidgetPredicate((w) => w is DropdownButtonFormField<String> && w.decoration.labelText == label);
  await tap(t, f); await t.tap(find.text(value).last); await t.pumpAndSettle();
}

void main() {
  for (final width in [390.0, 1440.0]) {
    testWidgets('historical creation review, paging, features and ZIP at $width', (t) async {
      final f = Fixture(); await f.open(t, width: width);
      await tap(t, find.text('Tinjau dataset baru')); await tap(t, find.text('Batal')); expect(f.posts, isEmpty);
      await tap(t, find.text('Tinjau dataset baru')); await tap(t, find.text('Buat dataset'));
      expect(f.posts.single['cases_per_kind'], 3000); expect(f.posts.single['request_key'], startsWith('history-'));
      await tap(t, find.text('Sampel berikutnya')); expect(f.queries.last['offset'], '25');
      await tap(t, find.text('Sample-25')); expect(find.text('amount: 100000'), findsOneWidget);
      await choose(t, 'Tahap keputusan', 'Penugasan ulang'); expect(f.queries.last['stage'], 'reassignment'); expect(f.queries.last['offset'], '0');
      await choose(t, 'Partisi', 'Dikeluarkan'); expect(f.queries.last['split'], 'excluded');
      // The download control is above the sample section; scroll back before locating it.
      await t.drag(find.byType(ListView).first, const Offset(0, 1800)); await t.pumpAndSettle();
      await tap(t, find.text('Unduh dataset ZIP')); await tap(t, find.text('Batal')); expect(f.exports, 0);
      await tap(t, find.text('Unduh dataset ZIP')); await tap(t, find.text('Unduh ZIP'));
      expect(f.saved, [80, 75, 3, 4]); expect(f.exports, 1); expect(t.takeException(), isNull);
    });
  }

  testWidgets('ambiguous generation keeps payload/key and locks edits until retry', (t) async {
    final f = Fixture(); bool fail = true;
    f.intercept = (r) => r.method == 'POST' && fail ? Future.value(http.Response('{"detail":"Layanan sementara gagal"}', 503)) : null;
    await f.open(t);
    await tap(t, find.text('Tinjau dataset baru')); await tap(t, find.text('Buat dataset'));
    expect(find.text('Layanan sementara gagal'), findsOneWidget);
    expect(find.text('Cek / ulangi pembuatan'), findsOneWidget);
    final state = t.state<AnalyticsPageState>(find.byType(AnalyticsPage));
    expect(state.pending, isNotNull); final original = Map.of(state.pending!);
    fail = false; await tap(t, find.text('Cek / ulangi pembuatan'));
    expect(f.posts, [original, original]); expect(state.pending, isNull); expect(t.takeException(), isNull);
  });

  testWidgets('known validation failure remains visible and allows edits', (t) async {
    final f = Fixture(); f.intercept = (r) => r.method == 'POST' ? Future.value(http.Response('{"detail":"Urutan tanggal salah"}', 422)) : null;
    await f.open(t); await tap(t, find.text('Tinjau dataset baru')); await tap(t, find.text('Buat dataset'));
    expect(find.text('Urutan tanggal salah'), findsOneWidget);
    expect(t.state<AnalyticsPageState>(find.byType(AnalyticsPage)).pending, isNull);
    expect(find.text('Tinjau dataset baru'), findsOneWidget);
  });

  testWidgets('history network failure offers retry without expiring session', (t) async {
    final f = Fixture(); bool fail = true;
    f.intercept = (r) => r.method == 'GET' && fail ? Future.error(http.ClientException('offline')) : null;
    await f.open(t); expect(f.api.token, isNotNull);
    await tap(t, find.text('Coba lagi histori')); fail = false;
    await tap(t, find.text('Coba lagi histori')); expect(find.text('HIST-TEST'), findsOneWidget);
  });

  testWidgets('late sample result cannot replace newer filter results', (t) async {
    final f = Fixture(); await f.open(t); await tap(t, find.text('HIST-TEST'));
    final state = t.state<AnalyticsPageState>(find.byType(AnalyticsPage));
    final late = Completer<http.Response>();
    f.intercept = (r) => r.url.path.endsWith('samples') && r.url.queryParameters['split'] == 'train' ? late.future : null;
    state.split = 'train'; final waiting = state.loadSamples(); await t.pump();
    state.split = 'test'; await state.loadSamples(); await t.pumpAndSettle();
    late.complete(http.Response('{"total":0,"items":[]}', 200)); await waiting; await t.pumpAndSettle();
    expect(state.rows!['total'], 52); expect(state.split, 'test');
  });

  testWidgets('agent cannot load analytics from the page', (t) async {
    final f = Fixture(role: 'agent'); await f.open(t);
    expect(find.text('Analitik historis memerlukan supervisor.'), findsOneWidget); expect(f.queries, isEmpty); expect(f.posts, isEmpty);
  });
}
