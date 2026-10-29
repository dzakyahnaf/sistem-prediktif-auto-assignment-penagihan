import 'package:flutter/material.dart';
import 'api.dart';
import 'widgets.dart';

class DecisionsPage extends StatefulWidget {
  final Api api;
  const DecisionsPage({super.key, required this.api});
  @override
  State<DecisionsPage> createState() => DecisionsPageState();
}

class DecisionsPageState extends State<DecisionsPage> {
  final form = GlobalKey<FormState>();
  final model = TextEditingController(), reason = TextEditingController();
  final fields = <String, TextEditingController>{};
  static const specs = <String, (String, double, double)>{
    'medium_threshold': ('Ambang Medium ke Tim A', 1, 99),
    'collection_followup_hours': ('SLA tindak lanjut penagihan (jam)', 1, 168),
    'origination_followup_hours': ('SLA tindak lanjut pengajuan (jam)', 1, 168),
    'collection_base': ('Basis rules penagihan', 50, 95),
    'dpd_penalty': ('Pengurang per hari DPD', 0, 1),
    'interest_weight': ('Bobot minat pengajuan', 0, 15),
    'document_bonus': ('Bonus dokumen lengkap', 0, 25),
    'income_bonus': ('Bonus rasio pendapatan', 0, 20),
  };
  Map<String, dynamic>? data, selected, pending;
  String? segment, error;
  bool loading = true, busy = false, pendingTrain = false;
  int generation = 0;
  bool get locked => loading || busy || pending != null;
  @override
  void initState() { super.initState(); for (final k in specs.keys) { fields[k] = TextEditingController(); } load(); }
  @override
  void dispose() { model.dispose(); reason.dispose(); for (final f in fields.values) { f.dispose(); } super.dispose(); }

  Future<void> load() async {
    if (!widget.api.supervisor || busy) { if (mounted) setState(() => loading = false); return; }
    final g = ++generation; setState(() { loading = true; error = null; });
    try {
      final r = Map<String, dynamic>.from(await widget.api.request('GET', '/api/decisions') as Map);
      if (!mounted || g != generation) return;
      setState(() {
        data = r;
        if (pending == null) {
          final config = r['policy']['config'] as Map;
          for (final k in fields.keys) { fields[k]!.text = '${config[k]}'; }
          segment = config['segment_release_id'] as String?; reason.clear();
        }
        if (model.text.isEmpty && (r['model_ids'] as List).isNotEmpty) model.text = r['model_ids'][0] as String;
        if (selected == null && (r['segments'] as List).isNotEmpty) selected = Map<String, dynamic>.from(r['segments'][0] as Map);
      });
    } catch (e) { if (mounted && g == generation) { setState(() => error = '$e'); await showMessage(context, '$e'); } }
    finally { if (mounted && g == generation) setState(() => loading = false); }
  }

  Future<void> submit(bool training) async {
    if (busy || loading || !widget.api.supervisor || (pending != null && pendingTrain != training)) return;
    if (pending == null) {
      Map<String, dynamic> body;
      if (training) {
        if (model.text.trim().isEmpty) { await showMessage(context, 'Isi ID model sumber.'); return; }
        body = {'model_id': model.text.trim()};
      } else {
        if (!(form.currentState?.validate() ?? false)) return;
        final config = <String, dynamic>{for (final e in fields.entries) e.key:
          e.key.endsWith('_hours') ? int.parse(e.value.text) : double.parse(e.value.text)};
        config['segment_release_id'] = segment;
        body = {'config': config, 'expected_revision': data!['policy']['revision'], 'reason': reason.text.trim()};
      }
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.all(16), title: Text(training ? 'Latih segmen deskriptif?' : 'Terbitkan kebijakan?'),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: Text(training
          ? 'Sumber ${body['model_id']}. K dipilih dari train saja; validation/test hanya evaluasi. Segmen tidak otomatis dipakai sampai dipilih pada kebijakan.'
          : 'Revisi ${body['expected_revision']} → ${(body['expected_revision'] as int)+1}\n${body['config']}\nAlasan: ${body['reason']}\nHanya keputusan baru. Low=A, High=B dan success penagihan72jam tetap. Histori tidak ditulis ulang.'))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(training ? 'Latih segmen' : 'Terbitkan'))],
      ));
      if (ok != true || !mounted) return;
      pendingTrain = training; pending = {...body, 'request_key': 'decision-${DateTime.now().microsecondsSinceEpoch}'};
    }
    setState(() { busy = true; error = null; }); bool success = false;
    try {
      final result = await widget.api.request('POST', training ? '/api/decisions/segments' : '/api/decisions/policy', pending);
      if (!mounted) return;
      setState(() { if (training) selected = Map<String, dynamic>.from(result as Map); pending = null; }); success = true;
    } catch (e) {
      if (mounted) {
        setState(() { error = '$e'; if (e is ApiException && !e.mayHaveSucceeded && e.status != null && e.status! < 500) pending = null; });
        await showMessage(context, '$e');
      }
    } finally { if (mounted) setState(() => busy = false); }
    if (success && mounted) await load();
  }

  String metric(dynamic value) => value is num ? value.toStringAsFixed(3) : 'Belum tersedia';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Keputusan & segmen'), actions: [IconButton(tooltip: 'Muat kebijakan terbaru', onPressed: busy || loading ? null : load, icon: const Icon(Icons.refresh))]),
    body: !widget.api.supervisor ? const Center(child: Text('Keputusan memerlukan supervisor.')) : ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Kebijakan operasional dan segmen deskriptif', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
      const Text('Asumsi demo dapat ditinjau. Low selalu A, High selalu B; success penagihan tetap seluruh tagihan lunas dalam72jam. SLA tindak lanjut berbeda dari jendela outcome model.'),
      if (loading) const LinearProgressIndicator(),
      if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(error!, style: const TextStyle(color: Colors.deepOrange))),
      if (pending != null) ...[const Text('Hasil perubahan belum pasti. Payload dikunci untuk retry yang sama.'),
        FilledButton(onPressed: busy || loading ? null : () => submit(pendingTrain), child: const Text('Periksa / ulangi keputusan'))],
      if (data != null) ...[
        const SizedBox(height: 16), Surface(child: Form(key: form, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Kebijakan revisi ${data!['policy']['revision']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16), LayoutBuilder(builder: (_, box) => Wrap(spacing: 16, runSpacing: 16, children: [
            for (final e in specs.entries) SizedBox(width: box.maxWidth >= 700 ? (box.maxWidth-16)/2 : box.maxWidth,
              child: TextFormField(controller: fields[e.key], enabled: !locked, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: e.value.$1),
                validator: (v) { final n = num.tryParse(v ?? ''); if (n == null || !n.isFinite || n < e.value.$2 || n > e.value.$3 || (e.key.endsWith('_hours') && int.tryParse(v ?? '') == null)) return 'Isi ${e.value.$2}–${e.value.$3}${e.key.endsWith('_hours') ? ' bulat' : ''}'; return null; })),
          ])), const SizedBox(height: 16),
          DropdownButtonFormField<String>(key: ValueKey('${data!['policy']['revision']}-$segment'), initialValue: segment, isExpanded: true, decoration: const InputDecoration(labelText: 'Paket segmen untuk keputusan baru'),
            items: [const DropdownMenuItem(value: null, child: Text('Tanpa segmentasi')), for (final s in data!['segments'] as List) DropdownMenuItem(value: s['id'] as String, child: Text('${s['id']}', overflow: TextOverflow.ellipsis))],
            onChanged: locked ? null : (v) => setState(() => segment = v)), const SizedBox(height: 16),
          TextFormField(controller: reason, enabled: !locked, minLines: 2, maxLines: 4, maxLength: 500, decoration: const InputDecoration(labelText: 'Alasan kebijakan'), validator: (v) => (v?.trim().length ?? 0) >= 10 ? null : 'Minimal10karakter'),
          FilledButton(onPressed: locked ? null : () => submit(false), child: const Text('Tinjau kebijakan')),
        ]))),
        const SizedBox(height: 16), Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Training segmen', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const Text('Preprocessing train-only dari model sumber; KMeans k2–4 dipilih dengan silhouette train. Kalender dan wilayah tidak menentukan cluster. ID segmen bukan urutan risiko.'), const SizedBox(height: 16),
          TextField(controller: model, enabled: !locked, decoration: const InputDecoration(labelText: 'ID model sumber segmen')), const SizedBox(height: 12),
          OutlinedButton(onPressed: locked ? null : () => submit(true), child: const Text('Tinjau training segmen')),
          for (final s in data!['segments'] as List) ListTile(contentPadding: EdgeInsets.zero, title: Text('${s['id']}'), subtitle: Text('Model ${s['model_id']}'),
            onTap: locked ? null : () => setState(() => selected = Map<String, dynamic>.from(s as Map))),
        ])),
        if (selected != null) ...[
          const SizedBox(height: 16), SelectableText('Paket ${selected!['id']} · SHA256 ${selected!['artifact_sha256']}'),
          Text('${selected!['report']['warning']}'),
          for (final m in selected!['report']['models'] as List) Padding(padding: const EdgeInsets.only(top: 16), child: Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${m['key']} · ${m['k']} segmen', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            Text('Stabilitas ARI resampling: ${(m['stability_ari'] as List).map(metric).join(' / ')}'),
            if (m['features'] != null) Text('Fitur segmen: ${(m['features'] as List).join(', ')}'),
            for (final w in m['warnings'] as List? ?? []) Text('$w', style: const TextStyle(color: Colors.deepOrange)),
            for (final e in (m['subsets'] as Map).entries) Text('${e.key}: n=${e.value['n']} · silhouette ${metric(e.value['silhouette'])} · ${e.value['counts']}'),
            ExpansionTile(tilePadding: EdgeInsets.zero, title: Text('Profil segmen ${m['key']}'), children: [
              for (final p in m['profiles'] as List) ListTile(contentPadding: EdgeInsets.zero, title: Text('${p['segment']} · n=${p['n']} train'), subtitle: Text('Rata-rata: ${p['means']}\nKategori: ${p['categories']}')),
              Text('Kandidat K (train): ${m['train_candidates']}'),
            ]),
          ]))),
        ],
        const SizedBox(height: 20), const Text('Riwayat penerbitan kebijakan', style: TextStyle(fontSize: 20)),
        for (final h in data!['history'] as List) ListTile(contentPadding: EdgeInsets.zero, title: Text('Revisi ${h['revision']} · ${h['reason']}'), subtitle: Text(dateLabel(h['created_at'] as String?))),
      ],
    ]),
  );
}
