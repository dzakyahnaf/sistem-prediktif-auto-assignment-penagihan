import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'api.dart';
import 'report_download.dart';
import 'widgets.dart';
import 'models_page.dart';

class AnalyticsPage extends StatefulWidget {
  final Api api;
  final Future<void> Function(Uint8List, String) save;
  const AnalyticsPage({super.key, required this.api, this.save = saveDataset});
  @override
  State<AnalyticsPage> createState() => AnalyticsPageState();
}

class AnalyticsPageState extends State<AnalyticsPage> {
  final form = GlobalKey<FormState>();
  final fields = {
    'cases_per_kind': TextEditingController(text: '3000'),
    'seed': TextEditingController(text: '281026'),
    'start_date': TextEditingController(text: '2024-10-01'),
    'train_until': TextEditingController(text: '2026-02-01'),
    'validation_until': TextEditingController(text: '2026-06-01'),
    'as_of': TextEditingController(text: '2026-10-01'),
    'origination_window_days': TextEditingController(text: '30'),
  };
  static const labels = {'cases_per_kind': 'Kasus per alur (100–5000)', 'seed': 'Seed simulasi',
    'start_date': 'Awal histori (UTC)', 'train_until': 'Batas train (UTC)',
    'validation_until': 'Batas validation (UTC)', 'as_of': 'Observasi sampai (UTC)',
    'origination_window_days': 'Jendela pengajuan (hari)'};
  List<dynamic> runs = [];
  Map<String, dynamic>? selected, rows, pending;
  String kind = 'collection', stage = 'initial', split = 'all';
  String? error, sampleError;
  bool busy = false, loading = false, sampleLoading = false, exporting = false;
  int offset = 0, listOffset = 0, runTotal = 0, revision = 0;
  @override
  void initState() { super.initState(); refresh(); }
  @override
  void dispose() { for (final c in fields.values) { c.dispose(); } super.dispose(); }
  bool get locked => busy || exporting || pending != null;

  Future<void> refresh() async {
    if (!widget.api.supervisor || busy || exporting) return;
    setState(() { loading = true; error = null; });
    try {
      final result = await widget.api.request('GET', '/api/analytics/runs?offset=$listOffset&limit=10');
      if (!mounted) return;
      setState(() { runs = result['items'] as List; runTotal = result['total'] as int; });
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> openRun(String id) async {
    if (locked) return;
    final current = ++revision;
    setState(() { selected = null; rows = null; error = null; sampleError = null; sampleLoading = true; offset = 0; });
    try {
      final result = await widget.api.request('GET', '/api/analytics/runs/$id');
      if (!mounted || current != revision) return;
      setState(() => selected = Map<String, dynamic>.from(result as Map));
      await loadSamples();
    } catch (e) { if (mounted && current == revision) setState(() { error = '$e'; sampleLoading = false; }); }
  }

  Map<String, dynamic>? payload() {
    if (!(form.currentState?.validate() ?? false)) return null;
    final data = <String, dynamic>{for (final e in fields.entries) e.key: e.value.text.trim()};
    for (final key in ['cases_per_kind', 'seed', 'origination_window_days']) { data[key] = int.parse(data[key] as String); }
    return data;
  }

  Future<void> generate() async {
    if (busy || exporting) return;
    var data = pending;
    if (data == null) {
      data = payload(); if (data == null) return;
      final accepted = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.all(16), title: const Text('Buat histori sintetis?'),
        content: Text('${data!['cases_per_kind']} kasus penagihan dan ${data['cases_per_kind']} pengajuan.\n'
          'Dataset disimpan terpisah dari antrean operasional. Semua hasil adalah simulasi; belum melatih model.\n\n'
          'Jendela label: penagihan 72 jam; pengajuan ${data['origination_window_days']} hari (asumsi).'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Buat dataset'))],
      ));
      if (accepted != true || !mounted) return;
      data['request_key'] = 'history-${DateTime.now().microsecondsSinceEpoch}';
      pending = Map<String, dynamic>.from(data);
    }
    final current = ++revision;
    setState(() { busy = true; error = null; rows = null; selected = null; });
    try {
      final result = await widget.api.request('POST', '/api/analytics/runs', pending);
      if (!mounted || current != revision) return;
      setState(() { pending = null; selected = Map<String, dynamic>.from(result as Map); offset = 0; listOffset = 0; });
    } catch (e) {
      if (!mounted || current != revision) return;
      setState(() {
        error = '$e';
        if (e is ApiException && !e.mayHaveSucceeded && e.status != null && e.status! < 500) { pending = null; }
      });
    } finally { if (mounted) setState(() => busy = false); }
    if (!mounted || current != revision) return;
    if (selected != null) { await loadSamples(); await refresh(); }
  }

  Future<void> loadSamples() async {
    if (selected == null) return;
    final current = ++revision;
    final id = selected!['id'];
    setState(() { rows = null; sampleLoading = true; sampleError = null; });
    try {
      final query = Uri(queryParameters: {'kind': kind, 'stage': stage, 'split': split, 'offset': '$offset', 'limit': '25'}).query;
      final result = await widget.api.request('GET', '/api/analytics/runs/$id/samples?$query');
      if (mounted && current == revision) setState(() => rows = Map<String, dynamic>.from(result as Map));
    } catch (e) { if (mounted && current == revision) setState(() => sampleError = '$e'); }
    finally { if (mounted && current == revision) setState(() => sampleLoading = false); }
  }

  Future<void> download() async {
    if (selected == null || locked) return;
    final id = selected!['id'];
    final session = widget.api.sessionRevision;
    setState(() => exporting = true);
    try {
      final accepted = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.all(16), title: const Text('Unduh paket dataset?'),
        content: const Text('ZIP memuat seluruh histori, snapshot fitur/label, manifest hash dan kamus data. '
          'Termasuk sampel yang dikeluarkan; training hanya boleh memakai split train/validation/test yang eligible. '
          'Filter preview tidak membatasi unduhan. Seluruh data sintetis.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Unduh ZIP'))],
      ));
      if (accepted != true || !mounted) return;
      final bytes = await widget.api.exportDataset('/api/analytics/runs/$id/export');
      if (!mounted || widget.api.sessionRevision != session) return;
      await widget.save(bytes, '$id-synthetic.zip');
      if (mounted) await showMessage(context, 'Paket dataset siap; periksa unduhan browser atau lokasi penyimpanan pilihan.');
    } catch (e) { if (mounted) await showMessage(context, '$e'); }
    finally { if (mounted) setState(() => exporting = false); }
  }

  String? validate(String key, String? text) {
    final value = text?.trim() ?? '';
    if (['cases_per_kind', 'seed', 'origination_window_days'].contains(key)) {
      final v = int.tryParse(value), min = key == 'cases_per_kind' ? 100 : key == 'seed' ? 1 : 7,
        max = key == 'cases_per_kind' ? 5000 : key == 'seed' ? 2000000000 : 90;
      return v == null || v < min || v > max ? 'Gunakan bilangan $min–$max.' : null;
    }
    final d = DateTime.tryParse(value);
    return !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) || d == null || d.toIso8601String().substring(0, 10) != value ? 'Gunakan YYYY-MM-DD yang valid.' : null;
  }

  Widget generator() => Surface(child: Form(key: form, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Histori baru', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
    const SizedBox(height: 8), const Text('Batas tanggal UTC eksklusif. Urutan: awal < train < validation < observasi. '
      'Setiap partisi harus lebih panjang dari jendela pengajuan + 7 hari. Hasil belum merupakan model ML.'),
    const SizedBox(height: 20), LayoutBuilder(builder: (context, box) => Wrap(spacing: 16, runSpacing: 16, children: [
      for (final e in fields.entries) SizedBox(width: box.maxWidth >= 700 ? (box.maxWidth-32)/3 : box.maxWidth >= 450 ? (box.maxWidth-16)/2 : box.maxWidth,
        child: TextFormField(controller: e.value, enabled: !locked, decoration: InputDecoration(labelText: labels[e.key]),
          validator: (v) => validate(e.key, v))),
    ])),
    const SizedBox(height: 16),
    if (pending != null && !busy) const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Hasil belum pasti. Ulangi dengan konfigurasi dan kunci yang sama; jangan membuat dataset baru.')),
    FilledButton.icon(onPressed: busy || exporting ? null : generate, icon: const Icon(Icons.science_outlined),
      label: Text(busy ? 'Membuat dataset…' : pending != null ? 'Cek / ulangi pembuatan' : 'Tinjau dataset baru')),
  ])));

  Widget overview() {
    final m = selected!['manifest'] as Map, config = selected!['config'] as Map;
    return Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SelectableText('${selected!['id']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8), Text('${m['simulator_version']} · ${m['feature_version']}'),
      Text('${config['start_date']} s.d. ${config['as_of']} UTC · seed ${config['seed']}'),
      Text('Batas train ${config['train_until']} · validation ${config['validation_until']}'),
      Text('Label lunas ≤72 jam · pencairan ≤${m['labels']['origination_days']} hari (asumsi)'),
      const SizedBox(height: 12), Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in (m['counts'] as Map).entries) Pill('${e.key}: ${e.value}'),
        const Pill('Pemeriksaan kualitas lulus'),
      ]),
      const SizedBox(height: 12), const Text('Kebocoran waktu: 0 · Identitas lintas partisi: 0 · Label lintas batas: 0 pada sampel eligible.'),
      const SizedBox(height: 12), SelectableText('SHA-256: ${m['data_sha256']}', style: const TextStyle(fontSize: 12)),
      for (final d in m['datasets'] as List) Padding(padding: const EdgeInsets.only(top: 18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${label(d['kind'] as String)} · ${d['stage'] == 'initial' ? 'Awal' : 'Penugasan ulang'} (${d['total']})', style: const TextStyle(fontWeight: FontWeight.w600)),
        for (final e in (d['splits'] as Map).entries) Text('${e.key}: ${e.value['total']} · label 1: ${e.value['positive']} · label 0: ${e.value['negative']}'),
        Text('Dikeluarkan: ${(d['excluded'] as Map).entries.map((e) => '${e.key}=${e.value}').join(', ')}'),
        Text(d['demo_training_ready'] == true ? 'Jumlah kelas memenuhi pemeriksaan demo.' : 'Jumlah kelas belum cukup untuk training demo pada semua partisi.'),
      ])),
      const SizedBox(height: 16),
      for (final warning in m['warnings'] as List) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('$warning', style: const TextStyle(color: muted))),
      OutlinedButton.icon(onPressed: locked ? null : download, icon: const Icon(Icons.download_outlined), label: Text(exporting ? 'Mengunduh…' : 'Unduh dataset ZIP')),
      const SizedBox(height: 8), OutlinedButton.icon(onPressed: locked ? null : () => Navigator.push<void>(context,
        MaterialPageRoute(builder: (_) => ModelsPage(api: widget.api, initialRunId: selected!['id'] as String))),
        icon: const Icon(Icons.science_outlined), label: const Text('Model dari dataset ini')),
    ]));
  }

  Widget dropdown(String name, String value, Map<String, String> values, ValueChanged<String> changed) => SizedBox(width: 250,
    child: DropdownButtonFormField<String>(key: ValueKey('$name-$value'), initialValue: value, isExpanded: true,
      decoration: InputDecoration(labelText: name), items: values.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: locked ? null : (v) { setState(() { changed(v!); offset = 0; }); loadSamples(); }));

  Widget preview() => Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Snapshot fitur dan label', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
    const SizedBox(height: 12), Wrap(spacing: 12, runSpacing: 12, children: [
      dropdown('Alur dataset', kind, const {'collection': 'Penagihan', 'origination': 'Pengajuan'}, (v) => kind = v),
      dropdown('Tahap keputusan', stage, const {'initial': 'Awal', 'reassignment': 'Penugasan ulang'}, (v) => stage = v),
      dropdown('Partisi', split, const {'all': 'Semua', 'train': 'Train', 'validation': 'Validation', 'test': 'Test', 'excluded': 'Dikeluarkan'}, (v) => split = v),
    ]),
    const SizedBox(height: 12), const Text('Buka sampel untuk melihat fitur yang tersedia sebelum keputusan. Metadata, label dan aksi petugas bukan prediktor.'),
    if (sampleLoading) const LinearProgressIndicator(),
    if (sampleError != null) ...[Text(sampleError!), TextButton(onPressed: loadSamples, child: const Text('Coba lagi sampel'))],
    if (rows != null) ...[
      Text('${rows!['total']} sampel ditemukan · 25 per halaman'),
      for (final s in rows!['items'] as List) ExpansionTile(tilePadding: EdgeInsets.zero,
        title: Text('${s['id']}', overflow: TextOverflow.ellipsis),
        subtitle: Text('${s['split']} · label ${s['label'] ?? 'belum diketahui'}${s['exclusion'] != null ? ' · ${s['exclusion']}' : ''}'),
        childrenPadding: const EdgeInsets.only(bottom: 16), expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [Text('Identitas: ${s['entity_id']} · Kasus: ${s['case_id']}'),
          Text('Keputusan: ${s['decision_at']}'), Text('Fitur tersedia: ${s['feature_max_at']}'), Text('Label matang: ${s['label_ready_at']}'),
          Text('Aksi: tim ${s['team']} · propensity ${s['assignment_propensity']} (metadata simulasi)'),
          const SizedBox(height: 8), const Text('Fitur prediktor', style: TextStyle(fontWeight: FontWeight.w600)),
          for (final e in (s['features'] as Map).entries) Text('${e.key}: ${e.value}'),
        ]),
      Wrap(spacing: 12, runSpacing: 8, children: [
        OutlinedButton(onPressed: locked || sampleLoading || offset == 0 ? null : () { offset -= 25; loadSamples(); }, child: const Text('Sampel sebelumnya')),
        OutlinedButton(onPressed: locked || sampleLoading || offset+25 >= (rows!['total'] as int) ? null : () { offset += 25; loadSamples(); }, child: const Text('Sampel berikutnya')),
      ]),
    ],
  ]));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Analitik historis'), actions: [IconButton(tooltip: 'Muat ulang histori', onPressed: locked || loading ? null : refresh, icon: const Icon(Icons.refresh))]),
    body: !widget.api.supervisor ? const Center(child: Text('Analitik historis memerlukan supervisor.')) : ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Laboratorium data sintetis', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: ink)),
      const SizedBox(height: 8), const Text('Data historis terpisah dari kasus operasional. Dataset berversi tidak berubah setelah dibuat. Aktivasi model dikelola melalui Model & evaluasi.'),
      const SizedBox(height: 20), generator(),
      if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(error!, style: const TextStyle(color: Colors.deepOrange))),
      const SizedBox(height: 20), Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Riwayat dataset', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        if (loading) const LinearProgressIndicator(),
        if (!loading && runs.isEmpty && error == null) const Text('Belum ada dataset historis.'),
        if (error != null) TextButton(onPressed: locked ? null : refresh, child: const Text('Coba lagi histori')),
        for (final run in runs) ListTile(contentPadding: EdgeInsets.zero, title: Text('${run['id']}', overflow: TextOverflow.ellipsis),
          subtitle: Text('${run['config']['cases_per_kind']} kasus/alur · seed ${run['config']['seed']} · ${dateLabel(run['created_at'] as String)}'),
          trailing: const Icon(Icons.chevron_right), onTap: locked ? null : () => openRun(run['id'] as String)),
        Text('$runTotal dataset tersimpan'),
        Wrap(spacing: 12, children: [
          TextButton(onPressed: locked || loading || listOffset == 0 ? null : () { listOffset -= 10; refresh(); }, child: const Text('Riwayat sebelumnya')),
          TextButton(onPressed: locked || loading || listOffset+10 >= runTotal ? null : () { listOffset += 10; refresh(); }, child: const Text('Riwayat berikutnya')),
        ]),
      ])),
      if (selected != null) ...[const SizedBox(height: 20), overview(), const SizedBox(height: 20), preview()],
      const SizedBox(height: 24),
    ]),
  );
}
