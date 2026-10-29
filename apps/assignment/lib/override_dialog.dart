import 'dart:math';
import 'package:flutter/material.dart';
import 'api.dart';
import 'widgets.dart';

class OverrideDialog extends StatefulWidget {
  final Api api;
  final String caseId;
  const OverrideDialog({super.key, required this.api, required this.caseId});
  @override
  State<OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends State<OverrideDialog> {
  final form = GlobalKey<FormState>();
  final reason = TextEditingController();
  Map<String, dynamic>? data, submitted;
  String? selected, error;
  bool loading = true, busy = false;
  String requestKey = '';
  List<dynamic> get options => data?['options'] as List? ?? [];
  @override
  void initState() { super.initState(); load(); }
  @override
  void dispose() { reason.dispose(); super.dispose(); }
  Future<void> load() async {
    if (busy || submitted != null) return;
    setState(() { loading = true; error = null; data = null; selected = null; });
    try {
      final result = await widget.api.request('GET', '/api/cases/${widget.caseId}/assignment-options');
      if (mounted) setState(() { data = Map<String, dynamic>.from(result as Map); requestKey = '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(4294967296)}'; });
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => loading = false); }
  }
  Future<void> save() async {
    if (busy || loading || data == null || !form.currentState!.validate()) return;
    setState(() { busy = true; error = null; });
    try {
      if (submitted == null) {
        final target = options.firstWhere((a) => a['agent_id'] == selected);
        final approved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
          insetPadding: const EdgeInsets.all(16), title: const Text('Konfirmasi override assignment'),
          content: SizedBox(width: 560, child: SingleChildScrollView(child: Text('${widget.caseId}\n${data!['previous_agent'] ?? 'Belum ditugaskan'} → ${target['name']} (${target['agent_id']})\n'
            'Tim ${data!['target_team']} · skor keputusan ${data!['score']}\n${data!['prediction']?['reason'] ?? ''}\n\n${reason.text.trim()}\n\n'
            '${data!['previous_agent'] == null ? 'Mulai siklus pertama.' : 'Siklus lama ditutup; hasil dan aktivitas tetap tersimpan. Skor memakai histori siklus yang ditutup.'} '
            'SLA tindak lanjut ${data!['prediction']?['policy']?['followup_hours'] ?? 72} jam. Success penagihan tetap 72 jam. Saldo terbayar dan progres pengajuan dibawa; kapasitas dan aturan diperiksa lagi saat simpan.'))),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Terapkan override'))],
        ));
        if (approved != true || !mounted) return;
        submitted = {'agent_id': selected, 'expected_version': data!['expected_version'], 'reason': reason.text.trim(), 'request_key': requestKey};
        if (data!['expected_scoring_revision'] != null) submitted!['expected_scoring_revision'] = data!['expected_scoring_revision'];
        if (data!['expected_policy_revision'] != null) submitted!['expected_policy_revision'] = data!['expected_policy_revision'];
      }
      await widget.api.request('POST', '/api/cases/${widget.caseId}/override-assignment', submitted);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { error = '$e'; if (e is ApiException && !e.mayHaveSucceeded) submitted = null; });
    } finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) {
    final locked = loading || busy || submitted != null;
    final eligible = options.where((a) => a['eligible'] == true).toList();
    return PopScope(canPop: !busy, child: AlertDialog(insetPadding: const EdgeInsets.all(16), title: const Text('Pilih petugas tertentu'),
      content: SizedBox(width: 600, child: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (loading) const LinearProgressIndicator(),
        const Text('Override tetap mengikuti wilayah, alur, tim, status aktif dan kapasitas. Petugas saat ini tidak dapat dipilih ulang.'), const SizedBox(height: 16),
        if (data != null) ...[
          Text('Versi kasus ${data!['expected_version']} · Tim ${data!['target_team']} · Skor ${data!['score']}'), const SizedBox(height: 8),
          Text(data!['previous_agent'] == null ? 'Assignment pertama tanpa memakai aktivitas siklus berjalan.' : 'Preview untuk siklus baru setelah siklus saat ini ditutup. Skor awal siklus lama tetap tersimpan.'), const SizedBox(height: 16),
          if (eligible.isEmpty) const Text('Tidak ada petugas lain yang memenuhi syarat. Periksa master/kapasitas atau gunakan penugasan ulang otomatis.'),
          if (eligible.isNotEmpty) DropdownButtonFormField<String>(key: ValueKey('override-$selected'), initialValue: selected, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Petugas tujuan'), items: eligible.map((a) => DropdownMenuItem(value: a['agent_id'] as String, child: Text('${a['name']} · ${a['agent_id']} · sisa ${a['remaining']}', overflow: TextOverflow.ellipsis))).toList(),
            onChanged: locked ? null : (v) => setState(() => selected = v), validator: (v) => v == null ? 'Pilih petugas tujuan.' : null),
          const SizedBox(height: 16), TextFormField(controller: reason, enabled: !locked, maxLines: 3, maxLength: 500, decoration: const InputDecoration(labelText: 'Alasan override'),
            validator: (v) => v!.trim().length < 10 ? 'Tulis alasan minimal 10 karakter.' : null),
          ExpansionTile(title: Text('Kecocokan seluruh petugas (${options.length})'), children: [for (final a in options) ListTile(contentPadding: EdgeInsets.zero,
            title: Text('${a['name']} · ${a['agent_id']}'), subtitle: Text('${a['reason']}\nAktif ${a['active_load']} · Hari ini ${a['daily_load']} · Kapasitas ${a['capacity']}'),
            leading: Icon(a['eligible'] == true ? Icons.check_circle_outline : Icons.block, color: a['eligible'] == true ? teal : muted))]),
        ],
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
        if (submitted != null && !busy) const Padding(padding: EdgeInsets.only(top: 12), child: Text('Hasil belum pasti. Kirim ulang payload yang sama dengan aman, atau tutup lalu muat ulang detail untuk memeriksa siklus. Pilihan dikunci agar retry tidak berubah.')),
      ])))),
      actions: [TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Tutup')),
        OutlinedButton(onPressed: locked ? null : load, child: const Text('Muat pilihan terbaru')),
        FilledButton(onPressed: busy || loading || eligible.isEmpty ? null : save, child: Text(busy ? 'Memproses…' : submitted != null ? 'Kirim ulang override' : 'Tinjau override'))],
    ));
  }
}
