import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'api.dart';
import 'report_download.dart';
import 'widgets.dart';

class ModelsPage extends StatefulWidget {
  final Api api;
  final String? initialRunId;
  final Future<void> Function(Uint8List, String) save;
  const ModelsPage({super.key, required this.api, this.initialRunId, this.save = saveDataset});
  @override
  State<ModelsPage> createState() => ModelsPageState();
}

class ModelsPageState extends State<ModelsPage> {
  final runId = TextEditingController();
  final form = GlobalKey<FormState>();
  List<dynamic> releases = [];
  Map<String, dynamic>? selected, pendingTrain, pendingSwitch;
  Map<String, dynamic> serving = {'revision': 0, 'release_id': null, 'history': []};
  bool loading = false, busy = false, exporting = false;
  String? error;
  String subset = 'test';
  int offset = 0, total = 0, revision = 0;
  bool get locked => loading || busy || exporting || pendingTrain != null || pendingSwitch != null;
  @override
  void initState() { super.initState(); runId.text = widget.initialRunId ?? ''; refresh(); }
  @override
  void dispose() { runId.dispose(); super.dispose(); }

  Future<void> refresh() async {
    if (!widget.api.supervisor || busy || exporting) return;
    final current = ++revision;
    setState(() { loading = true; error = null; });
    try {
      final values = await Future.wait([
        widget.api.request('GET', '/api/models?offset=$offset&limit=10'),
        widget.api.request('GET', '/api/models/serving'),
        if (runId.text.isEmpty) widget.api.request('GET', '/api/analytics/runs?limit=1'),
      ]);
      if (!mounted || current != revision) return;
      setState(() {
        releases = values[0]['items'] as List; total = values[0]['total'] as int;
        serving = Map<String, dynamic>.from(values[1] as Map);
        if (selected == null && releases.isNotEmpty) selected = Map<String, dynamic>.from(releases.first as Map);
        if (values.length == 3 && (values[2]['items'] as List).isNotEmpty) runId.text = values[2]['items'][0]['id'] as String;
      });
    } catch (e) { if (mounted && current == revision) { setState(() => error = '$e'); await showMessage(context, '$e'); } }
    finally { if (mounted && current == revision) setState(() => loading = false); }
  }

  Future<void> train() async {
    if (busy || exporting || pendingSwitch != null) return;
    if (pendingTrain == null) {
      if (!(form.currentState?.validate() ?? false)) return;
      final source = runId.text.trim();
      final approved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.all(16), title: const Text('Latih empat model demo?'),
        content: Text('$source\nModel awal dan penugasan ulang untuk penagihan/pengajuan. '
          'Preprocessing hanya pada train, pemilihan kalibrasi pada validation; test dilaporkan sesudah parameter dibekukan. '
          'Training menyimpan kandidat, lalu supervisor meninjau hasil sebelum aktivasi.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Latih model'))],
      ));
      if (approved != true || !mounted) return;
      pendingTrain = {'run_id': source, 'request_key': 'train-${DateTime.now().microsecondsSinceEpoch}'};
    }
    setState(() { busy = true; error = null; });
    bool success = false;
    try {
      final result = await widget.api.request('POST', '/api/models/train', pendingTrain);
      if (!mounted) return;
      setState(() { pendingTrain = null; selected = Map<String, dynamic>.from(result as Map); offset = 0; });
      success = true;
    } catch (e) { handleError(e, training: true); }
    finally { if (mounted) setState(() => busy = false); }
    if (success && mounted) await refresh();
  }

  void handleError(Object e, {required bool training}) {
    if (!mounted) return;
    setState(() {
      error = '$e';
      if (e is ApiException && !e.mayHaveSucceeded && e.status != null && e.status! < 500) {
        if (training) { pendingTrain = null; } else { pendingSwitch = null; }
      }
    });
    showMessage(context, '$e');
  }

  Future<void> changeServing(String? target) async {
    if (busy || exporting || pendingTrain != null) return;
    if (pendingSwitch == null) {
      final choice = await showDialog<String>(context: context, barrierDismissible: false, builder: (_) => _ServingDialog(
        target: target, previous: serving['release_id'] as String?, revision: serving['revision'] as int));
      if (choice == null || !mounted) return;
      pendingSwitch = {'release_id': target, 'expected_revision': serving['revision'], 'reason': choice,
        'request_key': 'serving-${DateTime.now().microsecondsSinceEpoch}', 'demo_ack': target != null};
    }
    setState(() { busy = true; error = null; });
    bool success = false;
    try {
      await widget.api.request('POST', '/api/models/serving', pendingSwitch);
      if (!mounted) return;
      setState(() => pendingSwitch = null); success = true;
    } catch (e) { handleError(e, training: false); }
    finally { if (mounted) setState(() => busy = false); }
    if (success && mounted) await refresh();
  }

  Future<void> open(String id) async {
    if (locked) return;
    final current = ++revision;
    setState(() { loading = true; error = null; });
    try {
      final result = await widget.api.request('GET', '/api/models/$id');
      if (mounted && current == revision) setState(() => selected = Map<String, dynamic>.from(result as Map));
    } catch (e) { if (mounted && current == revision) { setState(() => error = '$e'); await showMessage(context, '$e'); } }
    finally { if (mounted && current == revision) setState(() => loading = false); }
  }

  Future<void> download() async {
    if (locked || selected == null) return;
    final id = selected!['id']; final session = widget.api.sessionRevision;
    setState(() => exporting = true);
    try {
      final approved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Unduh paket model?'), content: const Text('ZIP berisi model JSON, preprocessing, parameter kalibrasi, provenance dan laporan evaluasi. Seluruh hasil dari simulator.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Unduh paket'))],
      ));
      if (approved != true || !mounted) return;
      final bytes = await widget.api.exportDataset('/api/models/$id/export');
      if (!mounted || session != widget.api.sessionRevision) return;
      await widget.save(bytes, '$id-model-demo.zip');
      if (mounted) await showMessage(context, 'Paket model siap; periksa unduhan browser atau lokasi penyimpanan pilihan.');
    } catch (e) { if (mounted) await showMessage(context, '$e'); }
    finally { if (mounted) setState(() => exporting = false); }
  }

  String number(dynamic v) => v is num ? v.toStringAsFixed(4) : '—';
  Widget modelCard(Map m) {
    final evaluation = m['evaluation'][subset] as Map;
    final metric = evaluation['model'] as Map?;
    final baseline = evaluation['constant'] as Map?;
    return Padding(padding: const EdgeInsets.only(top: 14), child: Surface(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${label(m['kind'] as String)} · ${m['stage'] == 'initial' ? 'Awal' : 'Penugasan ulang'}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      Text('Target: ${m['horizon']} ${m['horizon_unit'] == 'hours' ? 'jam' : 'hari'} · kalibrasi ${m['calibration']}'),
      Text('$subset · n=${metric?['n'] ?? 0} · positif=${metric?['positive'] ?? 0}'),
      Text('AUC ${number(metric?['auc'])} · AP ${number(metric?['average_precision'])}'),
      Text('Brier ${number(metric?['brier'])} · Log loss ${number(metric?['log_loss'])} · ECE ${number(metric?['ece'])}'),
      Text('Baseline konstan: Brier ${number(baseline?['brier'])} · Log loss ${number(baseline?['log_loss'])}'),
      Text('Rules (ranking): AUC ${number(evaluation['rules_ranking']['auc'])} · AP ${number(evaluation['rules_ranking']['average_precision'])}'),
      Text('Cakupan domain serving: ${((evaluation['serving_coverage'] as num)*100).toStringAsFixed(1)}%'),
      if (m['validation_beats_constant'] != true) const Text('Belum mengungguli baseline konstan pada validation-selection.', style: TextStyle(color: Colors.deepOrange)),
      ExpansionTile(tilePadding: EdgeInsets.zero, title: const Text('Distribusi dan kalibrasi'), children: [Align(alignment: Alignment.centerLeft, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final e in (m['counts'] as Map).entries) Text('${e.key}: ${e.value['n']} · kelas ${e.value['classes']}'),
        Text('Identitas validation lintas calibration/selection yang dipurge: ${m['calibration_entity_purged']}'),
        Text('Confusion pada ambang evaluasi 0,5 (baris aktual 0/1): ${metric?['confusion']}'),
        const SizedBox(height: 8), const Text('Reliability: prediksi vs fraksi positif teramati'),
        for (final bin in metric?['reliability'] as List? ?? []) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Bin ${bin['bin']} · n=${bin['count']} · pred ${number(bin['predicted'])} / aktual ${number(bin['observed'])}'),
          LinearProgressIndicator(value: (bin['predicted'] as num).toDouble(), color: teal), const SizedBox(height: 4),
          LinearProgressIndicator(value: (bin['observed'] as num).toDouble(), color: Colors.deepOrange),
        ])),
      ]))]),
    ])));
  }

  Widget report() {
    final r = selected!['report'] as Map;
    return Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SelectableText('${selected!['id']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
      Text('Dataset: ${selected!['run_id']} · ${r['engine']}'),
      SelectableText('SHA-256 artefak: ${selected!['artifact_sha256']}'),
      const SizedBox(height: 12), const Text('Brier/Log loss/ECE lebih rendah lebih baik; AUC/AP lebih tinggi lebih baik. '
        'Test tidak dipakai memilih model/kalibrasi. Angka ini hanya evaluasi simulator.'),
      const SizedBox(height: 12), DropdownButtonFormField<String>(initialValue: subset, isExpanded: true, decoration: const InputDecoration(labelText: 'Subset evaluasi'),
        items: const [DropdownMenuItem(value: 'test', child: Text('Test (holdout)')), DropdownMenuItem(value: 'validation_selection', child: Text('Validation selection')),
          DropdownMenuItem(value: 'validation_calibration', child: Text('Validation calibration')), DropdownMenuItem(value: 'train', child: Text('Train'))],
        onChanged: locked ? null : (v) => setState(() => subset = v!)),
      for (final m in r['models'] as List) modelCard(m as Map),
      const SizedBox(height: 16), for (final w in r['warnings'] as List) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('$w', style: const TextStyle(color: muted))),
      Wrap(spacing: 12, runSpacing: 12, children: [
        FilledButton(onPressed: locked || r['activation_eligible'] != true || serving['release_id'] == selected!['id'] ? null : () => changeServing(selected!['id'] as String), child: const Text('Aktifkan paket demo')),
        OutlinedButton.icon(onPressed: locked ? null : download, icon: const Icon(Icons.download_outlined), label: const Text('Unduh model & laporan')),
      ]),
    ]));
  }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Model & evaluasi'), actions: [
    IconButton(tooltip: 'Muat model dan serving', onPressed: busy || exporting ? null : refresh, icon: const Icon(Icons.refresh)),
  ]), body: !widget.api.supervisor ? const Center(child: Text('Model memerlukan supervisor.')) : Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: ListView(padding: const EdgeInsets.all(20), children: [
    const Text('Model predictive · simulasi', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: ink)),
    const SizedBox(height: 8), const Text('Empat model awal/ulang per domain. Aktivasi atomik untuk keputusan baru; kasus lama tanpa snapshot atau fitur di luar domain latih memakai fallback rules.'),
    const SizedBox(height: 20), Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Serving: ${serving['release_id'] ?? 'Rules'}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      Text('Revisi ${serving['revision']} · ${serving['status'] ?? 'belum dimuat'}'),
      const SizedBox(height: 12), OutlinedButton(onPressed: locked || serving['release_id'] == null ? null : () => changeServing(null), child: const Text('Kembali ke rules')),
      if (pendingSwitch != null && !busy) ...[const Text('Hasil perubahan belum pasti; ulangi payload yang sama.'), FilledButton(onPressed: () => changeServing(null), child: const Text('Periksa / ulangi perubahan'))],
    ])),
    const SizedBox(height: 20), Surface(child: Form(key: form, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Training kandidat', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12), TextFormField(controller: runId, enabled: !locked, decoration: const InputDecoration(labelText: 'ID dataset historis'),
        validator: (v) => (v?.trim().length ?? 0)<5 ? 'Isi ID dataset tersimpan.' : null),
      const SizedBox(height: 12), FilledButton.icon(onPressed: busy || exporting || pendingSwitch != null ? null : train,
        icon: const Icon(Icons.science_outlined), label: Text(busy ? 'Memproses…' : pendingTrain != null ? 'Periksa / ulangi training' : 'Tinjau training')),
      if (pendingTrain != null && !busy) const Text('Hasil belum pasti. Sumber dan kunci dikunci untuk mencegah paket ganda.'),
    ]))),
    if (loading || busy || exporting) const LinearProgressIndicator(),
    if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(error!, style: const TextStyle(color: Colors.deepOrange)), TextButton(onPressed: busy ? null : refresh, child: const Text('Muat versi serving terbaru')),
    ])),
    const SizedBox(height: 20), Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Registry paket', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      for (final item in releases) ListTile(contentPadding: EdgeInsets.zero, title: Text('${item['id']}', overflow: TextOverflow.ellipsis),
        subtitle: Text('${item['run_id']} · ${serving['release_id'] == item['id'] ? 'Aktif' : 'Tersimpan'}'), onTap: locked ? null : () => open(item['id'] as String)),
      Text('$total paket tersimpan'), Wrap(spacing: 12, children: [
        TextButton(onPressed: locked || offset == 0 ? null : () { offset -= 10; refresh(); }, child: const Text('Paket sebelumnya')),
        TextButton(onPressed: locked || offset+10 >= total ? null : () { offset += 10; refresh(); }, child: const Text('Paket berikutnya')),
      ]),
    ])),
    if (selected != null) ...[const SizedBox(height: 20), report()],
    const SizedBox(height: 20), Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Histori serving', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      for (final h in serving['history'] as List? ?? []) Padding(padding: const EdgeInsets.only(top: 12), child: Text(
        'Revisi ${h['revision']}: ${h['previous_release_id'] ?? 'Rules'} → ${h['release_id'] ?? 'Rules'}\n${h['reason']} · ${dateLabel(h['created_at'] as String?)}')),
    ])), const SizedBox(height: 24),
  ]))));
}

class _ServingDialog extends StatefulWidget {
  final String? target, previous;
  final int revision;
  const _ServingDialog({required this.target, required this.previous, required this.revision});
  @override
  State<_ServingDialog> createState() => _ServingDialogState();
}

class _ServingDialogState extends State<_ServingDialog> {
  final form = GlobalKey<FormState>();
  final reason = TextEditingController();
  bool acknowledged = false;
  @override
  void dispose() { reason.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.all(16), title: Text(widget.target == null ? 'Kembali ke rules?' : 'Aktifkan model demo?'),
    content: SizedBox(width: 560, child: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${widget.previous ?? 'Rules'} → ${widget.target ?? 'Rules'}\nRevisi serving ${widget.revision}'),
      const SizedBox(height: 12), const Text('Perubahan berlaku pada keputusan assignment berikutnya. Histori tidak ditulis ulang. Low/High, wilayah, tim dan kapasitas tetap diperiksa. Medium memakai ambang kebijakan yang berlaku.'),
      if (widget.target != null) CheckboxListTile(contentPadding: EdgeInsets.zero, value: acknowledged, onChanged: (v) => setState(() => acknowledged = v!),
        title: const Text('Saya memahami model ini dilatih pada data sintetis dan belum divalidasi pada nasabah nyata.')),
      const SizedBox(height: 12), TextFormField(controller: reason, maxLines: 3, maxLength: 500, decoration: const InputDecoration(labelText: 'Alasan perubahan model'),
        validator: (v) => (v?.trim().length ?? 0) < 10 ? 'Tulis alasan minimal 10 karakter.' : null),
    ])))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
      FilledButton(onPressed: widget.target != null && !acknowledged ? null : () { if (form.currentState!.validate()) Navigator.pop(context, reason.text.trim()); }, child: const Text('Terapkan perubahan'))],
  );
}
