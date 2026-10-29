import 'dart:math';
import 'package:flutter/material.dart';
import 'api.dart';
import 'widgets.dart';
import 'override_dialog.dart';
import 'prediction_panel.dart';
import 'operation_dialogs.dart';

class CaseDetail extends StatefulWidget {
  final Api api;
  final String caseId;
  const CaseDetail({super.key, required this.api, required this.caseId});
  @override
  State<CaseDetail> createState() => _CaseDetailState();
}

class _CaseDetailState extends State<CaseDetail> {
  Map<String, dynamic>? data;
  bool loading = true, busy = false;
  String? error;
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final result = await widget.api.request('GET', '/api/cases/${widget.caseId}');
      if (mounted) setState(() => data = Map<String, dynamic>.from(result as Map));
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> assign() async {
    setState(() => busy = true);
    try {
      final result = await widget.api.request('POST', '/api/assignments', {'case_ids': [widget.caseId]});
      if (mounted) await showMessage(context, result['results'][0]['reason'] as String);
      if (mounted) await load();
    } catch (e) { if (mounted) await showMessage(context, '$e'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> reassignCase() async {
    final text = await showDialog<String>(context: context, builder: (_) => const _ReassignReasonDialog());
    if (text == null || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.api.request('POST', '/api/cases/${widget.caseId}/reassign', {'expected_version': data!['case']['version'], 'reason': text});
      if (mounted) await load();
    } catch (e) { if (mounted) await showMessage(context, '$e'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> recordActivity() async {
    final saved = await showDialog<bool>(context: context, builder: (_) => ActivityDialog(api: widget.api, record: Map<String, dynamic>.from(data!['case'] as Map)));
    if (saved == true && mounted) await load();
  }

  Future<void> overrideCase() async {
    if (busy || loading) return;
    setState(() => busy = true);
    await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => OverrideDialog(api: widget.api, caseId: widget.caseId));
    if (mounted) { await load(); if (mounted) setState(() => busy = false); }
  }

  Future<void> simulateContact() async {
    await showDialog<void>(context:context,barrierDismissible:false,builder:(_)=>OperationDialog(api:widget.api,record:Map<String,dynamic>.from(data!['case'] as Map)));
    if(mounted)await load();
  }

  @override
  Widget build(BuildContext context) {
    final c = data?['case'];
    final closed = c != null && ['paid','disbursed','rejected'].contains(c['status']);
    return Scaffold(appBar: AppBar(title: Text(widget.caseId), actions: [IconButton(tooltip: 'Muat ulang', onPressed: loading ? null : load, icon: const Icon(Icons.refresh))]),
      body: loading && data == null ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(padding: const EdgeInsets.all(24), child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1000), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (loading) const LinearProgressIndicator(),
        if (error != null) Padding(padding: const EdgeInsets.only(bottom: 20), child: Text(error!, style: const TextStyle(color: Colors.red))),
        if (c != null) ...[
          Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [Pill(label(c['kind'] as String)), Pill(label(c['status'] as String)), const Pill('Data demo', color: muted)]), const SizedBox(height: 20),
            Text(c['customer'] as String, style: const TextStyle(color: ink, fontSize: 30, fontWeight: FontWeight.w700)), const SizedBox(height: 12),
            Text('${c['region_id']} · Kesulitan ${c['difficulty']} · Siklus ${c['cycle']}', style: const TextStyle(color: muted)),
            const SizedBox(height: 24), Wrap(spacing: 40, runSpacing: 20, children: [
              info(c['kind'] == 'collection' ? 'Tagihan penuh' : 'Pengajuan', rupiah(c['amount'] as num)),
              info(c['kind'] == 'collection' ? 'Terbayar' : 'Dicairkan', rupiah(c['paid'] as num)),
              info('Skor tersimpan', '${c['score']} / 100'), info('Kelompok tujuan', 'Tim ${data!['target_team']}'),
            ]), const SizedBox(height: 24), const Divider(), const SizedBox(height: 16),
            info('Petugas', c['agent_id'] as String? ?? 'Belum ditugaskan'), const SizedBox(height: 16),
            info('Batas tindak lanjut', dateLabel(c['due_at'] as String?)), const SizedBox(height: 20),
            if (c['kind'] == 'collection') const Text('Success: seluruh tagihan kasus dibayar maksimal 72 jam sejak penugasan. Pembayaran sebagian tetap dicatat.', style: TextStyle(color: muted, height: 1.6))
            else Text('Minat ${c['interest']}/5 · Penghasilan ${rupiah(c['income'] as num)}\nDokumen: ${c['documents_complete'] == 1 ? 'lengkap' : 'belum lengkap'}. Pencairan hanya simulasi.', style: const TextStyle(color: muted, height: 1.6)),
            const SizedBox(height: 24), Wrap(spacing: 12, runSpacing: 12, children: [
              if (widget.api.supervisor && c['agent_id'] == null && !closed) FilledButton.icon(onPressed: busy || loading ? null : assign, icon: const Icon(Icons.person_add_alt), label: const Text('Tugaskan kasus')),
              if (c['agent_id'] != null && !closed) FilledButton.icon(onPressed: busy || loading ? null : recordActivity, icon: const Icon(Icons.add_comment_outlined), label: const Text('Catat aktivitas')),
              if (c['agent_id'] != null && !closed) OutlinedButton.icon(onPressed:busy||loading?null:simulateContact,icon:const Icon(Icons.phone_outlined),label:const Text('Tindak lanjut simulasi')),
              if (widget.api.supervisor && c['agent_id'] != null && !closed) OutlinedButton.icon(onPressed: busy || loading ? null : reassignCase, icon: const Icon(Icons.sync), label: const Text('Penugasan ulang')),
              if (widget.api.supervisor && !closed) OutlinedButton.icon(onPressed: busy || loading ? null : overrideCase, icon: const Icon(Icons.person_search_outlined), label: const Text('Pilih petugas tertentu')),
            ]),
          ])), const SizedBox(height: 24),
          if (widget.api.supervisor && !closed) ...[
            const Text('Kecocokan petugas', style: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w600)), const SizedBox(height: 12),
            if ((data!['recommendations'] as List).isEmpty) const Surface(child: Text('Tidak ada petugas aktif yang cocok dengan wilayah dan tim kasus.')),
            ...(data!['recommendations'] as List).map((r) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 8), Text(r['reason'] as String, style: const TextStyle(color: muted)),
              const SizedBox(height: 8), Text('Aktif ${r['active_load']} · Hari ini ${r['daily_load']} · Kapasitas ${r['capacity']}', style: const TextStyle(color: muted, fontSize: 12)),
            ])))), const SizedBox(height: 12),
          ],
          if (data!['prediction'] is Map) ...[PredictionPanel(data: data!['prediction'] as Map, preview: c['agent_id'] == null), const SizedBox(height: 20)],
          const Text('Riwayat aktivitas', style: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w600)), const SizedBox(height: 12),
          if ((data!['activities'] as List).isEmpty) const Surface(child: EmptyState('Belum ada aktivitas', 'Hasil follow-up akan tampil di sini setelah dicatat.')),
          ...(data!['activities'] as List).map((a) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label(a['code'] as String), style: const TextStyle(color: ink, fontWeight: FontWeight.w600, fontSize: 16)), const SizedBox(height: 8),
            Text(dateLabel(a['created_at'] as String), style: const TextStyle(color: muted, fontSize: 12)),
            if ((a['amount'] as num) > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text(rupiah(a['amount'] as num))),
            if (a['promise_date'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Janji: ${dateLabel(a['promise_date'] as String)}')),
            if ((a['note'] as String).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(a['note'] as String)),
          ])))), const SizedBox(height: 24),
          const Text('Riwayat penugasan', style: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w600)), const SizedBox(height: 12),
          ...(data!['assignments'] as List).map((a) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Siklus ${a['cycle']} · ${a['agent_id']}', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (a['prediction'] is Map) Text('Skor ${a['score']} · ${a['prediction']['version']} · ${a['prediction']['source'] == 'ml_simulation' ? 'prediksi sintetis' : 'rules'}'),
            if (a['agent_name'] != null) Text('${a['agent_name']} · Tim ${a['agent_team']} · ${a['agent_channel']}'), const SizedBox(height: 8),
            Text('${dateLabel(a['assigned_at'] as String)}\n${a['reason']}', style: const TextStyle(color: muted, height: 1.6)), const SizedBox(height: 12),
            Pill(a['outcome'] == null ? 'Berjalan' : label(a['outcome'] as String)),
          ])))),
        ],
      ])))),
    );
  }

  Widget info(String title, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: muted, fontSize: 12)), const SizedBox(height: 6), Text(value, style: const TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w600))]);
}

class _ReassignReasonDialog extends StatefulWidget {
  const _ReassignReasonDialog();
  @override
  State<_ReassignReasonDialog> createState() => _ReassignReasonDialogState();
}

class _ReassignReasonDialogState extends State<_ReassignReasonDialog> {
  final reason = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() { reason.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.all(16), title: const Text('Mulai siklus penugasan baru'),
    content: SizedBox(width: 440, child: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Siklus lama akan ditutup dan skor dihitung kembali memakai histori siklus tertutup. Petugas dapat tetap sama jika paling sesuai. Riwayat tetap disimpan.'),
      const SizedBox(height: 20), TextFormField(controller: reason, maxLines: 3, decoration: const InputDecoration(labelText: 'Alasan penugasan ulang'),
        validator: (v) => v!.trim().length < 10 ? 'Tulis alasan minimal 10 karakter.' : null),
    ])))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
      FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(context, reason.text.trim()); }, child: const Text('Lanjutkan'))],
  );
}

class ActivityDialog extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> record;
  const ActivityDialog({super.key, required this.api, required this.record});
  @override
  State<ActivityDialog> createState() => _ActivityDialogState();
}

class _ActivityDialogState extends State<ActivityDialog> {
  final form = GlobalKey<FormState>();
  final note = TextEditingController(), amount = TextEditingController();
  // A 32-bit shift wraps to zero on Dart's JavaScript target.
  final requestKey = '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(4294967296)}';
  String code = 'contacted';
  bool busy = false;
  String? error;
  Map<String, dynamic>? submitted;
  DateTime promise = DateTime.now().add(const Duration(days: 1));
  @override
  void dispose() { note.dispose(); amount.dispose(); super.dispose(); }
  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final payload = {'code': code, 'note': note.text.trim(), 'amount': ['payment','disburse'].contains(code) ? int.parse(amount.text) : 0,
      'expected_version': widget.record['version'], 'request_key': requestKey,
      if (code == 'promise') 'promise_date': promise.toUtc().toIso8601String()};
    // Keep the same payload and key for an ambiguous network retry.
    submitted ??= payload;
    setState(() { busy = true; error = null; });
    try {
      await widget.api.request('POST', '/api/cases/${widget.record['id']}/activities', submitted);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() {
        error = '$e';
        if (e is ApiException && !e.mayHaveSucceeded) submitted = null;
      });
    } finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) {
    final collection = widget.record['kind'] == 'collection';
    final locked = busy || submitted != null;
    final codes = collection ? ['contacted','unreachable','promise','payment'] : ['contacted','unreachable','documents','qualified','disburse','reject'];
    return AlertDialog(title: const Text('Catat hasil follow-up'), content: SizedBox(width: 480, child: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
      DropdownButtonFormField<String>(isExpanded: true, initialValue: code, decoration: const InputDecoration(labelText: 'Hasil aktivitas'), items: codes.map((v) => DropdownMenuItem(value: v, child: Text(label(v)))).toList(), onChanged: locked ? null : (v) => setState(() { code = v!; if (code == 'disburse') amount.text = '${widget.record['amount']}'; })), const SizedBox(height: 16),
      if (['payment','disburse'].contains(code)) ...[
        TextFormField(controller: amount, enabled: !locked, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Nominal (Rp)', helperText: collection ? 'Sisa tagihan: ${rupiah((widget.record['amount'] as num)-(widget.record['paid'] as num))}' : 'Nominal pencairan simulasi'), validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? 'Masukkan nominal positif tanpa pemisah.' : null), const SizedBox(height: 16),
      ],
      if (code == 'promise') ...[
        OutlinedButton.icon(onPressed: locked ? null : () async {
          final selected = await showDatePicker(context: context, initialDate: promise, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 90)));
          if (selected != null && mounted) setState(() => promise = DateTime(selected.year, selected.month, selected.day, 17));
        }, icon: const Icon(Icons.calendar_month_outlined), label: Text(dateLabel(promise.toUtc().toIso8601String()))), const SizedBox(height: 16),
      ],
      TextFormField(controller: note, enabled: !locked, maxLines: 3, decoration: const InputDecoration(labelText: 'Catatan'), validator: (v) => code == 'reject' && v!.trim().length < 5 ? 'Isi alasan penolakan.' : null),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(error!, style: const TextStyle(color: Colors.red))),
      if (submitted != null && !busy) const Padding(padding: EdgeInsets.only(top: 12), child: Text('Respons belum diterima. Coba kirim ulang aktivitas yang sama, atau tutup lalu muat ulang kasus untuk memeriksa hasilnya.')),
    ])))), actions: [TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Tutup')), FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Menyimpan…' : 'Simpan aktivitas'))]);
  }
}
