import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:assignment_studio/api.dart';
import 'package:assignment_studio/models_page.dart';
import 'package:assignment_studio/prediction_panel.dart';
import 'package:assignment_studio/widgets.dart';
import 'package:assignment_studio/case_detail.dart';

class Fixture {
  late final Api api;
  final trainPosts = <Map<String, dynamic>>[], switchPosts = <Map<String, dynamic>>[];
  Future<http.Response>? Function(http.Request)? intercept;
  Uint8List? saved;
  String? active;
  int servingRevision = 0, exports = 0;
  bool trained = false;
  final replayed = <String>{};
  Map<String, dynamic> metric(int n) => {'n': n, 'positive': n~/3, 'auc': .62, 'average_precision': .5, 'brier': .2, 'log_loss': .6, 'ece': .03,
    'confusion': [[10, 2], [3, 5]], 'reliability': [{'bin': 1, 'count': n, 'predicted': .3, 'observed': .32}]};
  Map<String, dynamic> get package => {'id': 'MOD-TEST', 'run_id': 'HIST-TEST', 'created_at': '2026-10-28T00:00:00+00:00', 'artifact_sha256': 'artifact-checksum',
    'report': {'engine': 'logit-json-v1', 'activation_eligible': true, 'warnings': ['Hasil simulator, bukan validasi nasabah nyata.'], 'models': [
      for (final kind in ['collection', 'origination']) for (final stage in ['initial', 'reassignment'])
        {'key': '${kind}_$stage', 'kind': kind, 'stage': stage, 'horizon': kind == 'collection' ? 72 : 30, 'horizon_unit': kind == 'collection' ? 'hours' : 'days',
          'calibration': 'none', 'calibration_entity_purged': 1, 'validation_beats_constant': false,
          'counts': {'train': {'n': 1000, 'classes': {'0': 600, '1': 400}}},
          'evaluation': {for (final subset in ['train', 'validation_selection', 'validation_calibration', 'test']) subset:
            {'model': metric(subset == 'test' ? 392 : 100), 'constant': metric(100), 'rules_ranking': {'auc': .58, 'average_precision': .4}, 'serving_coverage': 1.0}},
        },
    ]}};
  Fixture({String role = 'supervisor'}) {
    api = Api(client: MockClient((r) async {
      if (r.url.path.endsWith('login')) return http.Response(jsonEncode({'access_token': 'demo', 'user': {'role': role}}), 200);
      if (r.method == 'POST' && r.url.path.endsWith('train')) trainPosts.add(Map<String, dynamic>.from(jsonDecode(r.body) as Map));
      if (r.method == 'POST' && r.url.path.endsWith('serving')) switchPosts.add(Map<String, dynamic>.from(jsonDecode(r.body) as Map));
      final override = intercept?.call(r); if (override != null) return override;
      if (r.url.path.endsWith('train')) { trained = true; return http.Response(jsonEncode(package), 201); }
      if (r.url.path.endsWith('serving')) {
        if (r.method == 'POST') {
          final p = jsonDecode(r.body) as Map;
          if (!replayed.contains(p['request_key'])) { active = p['release_id'] as String?; servingRevision++; replayed.add(p['request_key'] as String); }
        }
        return http.Response(jsonEncode({'release_id': active, 'revision': servingRevision, 'status': 'ready', 'history': []}), 200);
      }
      if (r.url.path.endsWith('runs')) return http.Response('{"items":[{"id":"HIST-TEST"}],"total":1}', 200);
      if (r.url.path.endsWith('export')) { exports++; return http.Response.bytes([80, 75, 3, 4], 200, headers: {'content-type': 'application/zip'}); }
      if (r.url.path.endsWith('MOD-TEST')) return http.Response(jsonEncode(package), 200);
      return http.Response(jsonEncode({'items': trained ? [package] : [], 'total': trained ? 1 : 0}), 200);
    }));
  }
  Future<void> open(WidgetTester t, {double width = 390}) async {
    t.view.physicalSize = Size(width, 844); t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio); addTearDown(api.dispose);
    await api.login('demo', 'demo'); await t.pumpWidget(MaterialApp(theme: studioTheme(), home: ModelsPage(api: api,
      save: (b, n) async { saved = b; })));
    await t.pumpAndSettle();
  }
}

Future<void> tap(WidgetTester t, Finder finder) async {
  if (finder.evaluate().isEmpty) await t.scrollUntilVisible(finder, 500, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
  await t.ensureVisible(finder); await t.pumpAndSettle(); await t.tap(finder); await t.pumpAndSettle();
}
Future<void> train(WidgetTester t) async { await tap(t, find.text('Tinjau training')); await tap(t, find.text('Latih model')); }
Future<void> approve(WidgetTester t, {bool ack = true}) async {
  final reason = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Alasan perubahan model');
  await t.enterText(reason, 'Pengujian lifecycle model sintetis');
  if (ack) await tap(t, find.byType(CheckboxListTile));
  await tap(t, find.text('Terapkan perubahan'));
}

void main() {
  testWidgets('refresh failure is visible while deep inside the report and keeps the session', (t) async {
    final f = Fixture()..trained = true; await f.open(t);
    await t.drag(find.byType(ListView).first, const Offset(0, -1800)); await t.pumpAndSettle();
    f.intercept = (r) => Future.value(http.Response('{"detail":"Koneksi model gagal"}', 503));
    await tap(t, find.byTooltip('Muat model dan serving'));
    expect(find.descendant(of: find.byType(SnackBar), matching: find.text('Koneksi model gagal')), findsOneWidget);
    expect(f.api.token, isNotNull); expect(t.takeException(), isNull);
  });
  testWidgets('reassignment dialog owns its controller until route disposal', (t) async {
    int writes = 0;
    final api = Api(client: MockClient((r) async {
      if (r.url.path.endsWith('login')) return http.Response('{"access_token":"demo","user":{"role":"supervisor"}}', 200);
      if (r.method == 'POST') { writes++; return http.Response('{"assigned":true}', 200); }
      return http.Response(jsonEncode({'case': {'id': 'CASE-1', 'customer': 'Demo S9', 'kind': 'collection', 'status': 'assigned',
        'region_id': 'SMG', 'difficulty': 'Low', 'amount': 5000000, 'paid': 0, 'score': 60.0, 'cycle': writes+1, 'version': writes+1, 'agent_id': 'SMG-col-A'},
        'assignments': [], 'activities': [], 'recommendations': [], 'target_team': 'A'}), 200);
    }));
    addTearDown(api.dispose); await api.login('demo', 'demo');
    await t.pumpWidget(MaterialApp(theme: studioTheme(), home: CaseDetail(api: api, caseId: 'CASE-1'))); await t.pumpAndSettle();
    await tap(t, find.text('Penugasan ulang'));
    await t.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Alasan penugasan ulang'), 'UAT dialog penugasan ulang model');
    await tap(t, find.text('Lanjutkan')); expect(writes, 1); expect(t.takeException(), isNull);
  });
  for (final width in [390.0, 1440.0]) {
    testWidgets('train review metrics activation rollback and model ZIP at $width', (t) async {
      final f = Fixture(); await f.open(t, width: width);
      await tap(t, find.text('Tinjau training')); await tap(t, find.text('Batal')); expect(f.trainPosts, isEmpty);
      await train(t); expect(f.trainPosts.single['run_id'], 'HIST-TEST');
      await tap(t, find.text('Distribusi dan kalibrasi').first);
      expect(find.textContaining('Reliability:'), findsOneWidget);
      await tap(t, find.text('Aktifkan paket demo'));
      expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Terapkan perubahan')).onPressed, isNull);
      await tap(t, find.text('Batal')); expect(f.switchPosts, isEmpty);
      await tap(t, find.text('Aktifkan paket demo')); await approve(t); expect(f.active, 'MOD-TEST');
      final state = t.state<ModelsPageState>(find.byType(ModelsPage)); expect(state.serving['revision'], 1);
      // Rollback control is near the top; allow its lazy ListView child to rebuild.
      await t.drag(find.byType(ListView).first, const Offset(0, 6000)); await t.pumpAndSettle();
      await tap(t, find.text('Kembali ke rules')); await approve(t, ack: false); expect(f.active, isNull); expect(f.servingRevision, 2);
      await tap(t, find.text('Unduh model & laporan')); await tap(t, find.text('Batal')); expect(f.exports, 0);
      await tap(t, find.text('Unduh model & laporan')); await tap(t, find.text('Unduh paket'));
      expect(f.saved, [80, 75, 3, 4]); expect(f.exports, 1); expect(t.takeException(), isNull);
    });
  }
  testWidgets('ambiguous training retains source and idempotency key', (t) async {
    final f = Fixture(); bool fail = true;
    f.intercept = (r) => r.url.path.endsWith('train') && fail ? Future.value(http.Response('{"detail":"Training belum pasti"}', 503)) : null;
    await f.open(t); await train(t); expect(t.state<ModelsPageState>(find.byType(ModelsPage)).error, 'Training belum pasti');
    final original = Map.of(f.trainPosts.single); fail = false;
    await tap(t, find.text('Periksa / ulangi training')); expect(f.trainPosts, [original, original]);
  });
  testWidgets('known training validation error remains visible and unlocks form', (t) async {
    final f = Fixture(); f.intercept = (r) => r.url.path.endsWith('train') ? Future.value(http.Response('{"detail":"Label belum cukup"}', 422)) : null;
    await f.open(t); await train(t); expect(t.state<ModelsPageState>(find.byType(ModelsPage)).error, 'Label belum cukup');
    expect(t.state<ModelsPageState>(find.byType(ModelsPage)).pendingTrain, isNull);
  });
  testWidgets('serving conflict refreshes current revision without replaying stale switch', (t) async {
    final f = Fixture()..trained = true;
    f.intercept = (r) => r.method == 'POST' && r.url.path.endsWith('serving') ? Future.value(http.Response('{"detail":"Model aktif berubah"}', 409)) : null;
    await f.open(t); await tap(t, find.text('Aktifkan paket demo')); await approve(t);
    expect(t.state<ModelsPageState>(find.byType(ModelsPage)).error, 'Model aktif berubah'); expect(t.state<ModelsPageState>(find.byType(ModelsPage)).pendingSwitch, isNull);
    await t.drag(find.byType(ListView).first, const Offset(0, 6000)); await t.pumpAndSettle();
    f.servingRevision = 2; await tap(t, find.text('Muat versi serving terbaru'));
    expect(t.state<ModelsPageState>(find.byType(ModelsPage)).serving['revision'], 2); expect(f.switchPosts.length, 1);
  });
  testWidgets('ambiguous serving switch retries identical payload', (t) async {
    final f = Fixture()..trained = true; bool fail = true;
    f.intercept = (r) => r.method == 'POST' && r.url.path.endsWith('serving') && fail ? Future.value(http.Response('{"detail":"Hasil switch belum pasti"}', 503)) : null;
    await f.open(t); await tap(t, find.text('Aktifkan paket demo')); await approve(t);
    final original = Map.of(f.switchPosts.single); fail = false;
    await t.drag(find.byType(ListView).first, const Offset(0, 6000)); await t.pumpAndSettle();
    await tap(t, find.text('Periksa / ulangi perubahan')); expect(f.switchPosts, [original, original]); expect(f.servingRevision, 1);
  });
  testWidgets('unauthorized model download clears session without saving bytes', (t) async {
    final f = Fixture()..trained = true;
    f.intercept = (r) => r.url.path.endsWith('export') ? Future.value(http.Response('expired', 401)) : null;
    await f.open(t); await tap(t, find.text('Unduh model & laporan')); await tap(t, find.text('Unduh paket'));
    expect(f.api.token, isNull); expect(f.saved, isNull);
  });
  testWidgets('agent cannot fetch model registry', (t) async {
    final f = Fixture(role: 'agent'); await f.open(t); expect(find.text('Model memerlukan supervisor.'), findsOneWidget);
    expect(f.trainPosts, isEmpty); expect(f.switchPosts, isEmpty);
  });
  testWidgets('prediction snapshot explains simulation and exposes predecision features', (t) async {
    t.view.physicalSize = const Size(390, 844); t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(theme: studioTheme(), home: Scaffold(body: SingleChildScrollView(child: PredictionPanel(data: const {
      'source': 'ml_simulation', 'probability': .32, 'score': 32, 'version': 'MOD-TEST:collection_initial', 'serving_revision': 1,
      'horizon': 72, 'horizon_unit': 'hours', 'model_key': 'collection_initial', 'reason': 'Prediksi sintetis',
      'decision_at': '2026-10-28T02:00:00+00:00', 'feature_max_at': '2026-10-28T01:00:00+00:00', 'features': {'dpd': 15},
    })))));
    await t.pumpAndSettle(); expect(find.text('Prediksi simulasi ML: 32.0%'), findsOneWidget);
    await tap(t, find.text('Fitur sebelum keputusan')); expect(find.text('dpd: 15'), findsOneWidget); expect(t.takeException(), isNull);
  });
}
