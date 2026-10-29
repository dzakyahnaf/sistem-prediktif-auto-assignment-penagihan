import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'api.dart';
import 'report_download.dart';
import 'widgets.dart';

class ReportsPage extends StatefulWidget {
  final Api api;
  final List<dynamic> regions, agents;
  final Future<void> Function(String)? onOpenCase;
  final Future<void> Function(Uint8List, String) save;
  const ReportsPage({super.key, required this.api, required this.regions, required this.agents,
    this.onOpenCase, this.save = saveReport});
  @override
  State<ReportsPage> createState() => ReportsPageState();
}

class ReportsPageState extends State<ReportsPage> {
  final form = GlobalKey<FormState>();
  final from = TextEditingController(), to = TextEditingController(), search = TextEditingController();
  String kind = 'collection', view = 'cases', region = '', agent = '', status = '';
  Map<String, dynamic>? data;
  Map<String, String>? applied;
  String? error;
  bool loading = false, exporting = false;
  int offset = 0, revision = 0;
  static const pageSize = 25;
  @override
  void initState() { super.initState(); refresh(); }
  @override
  void dispose() { from.dispose(); to.dispose(); search.dispose(); super.dispose(); }

  List<String> get statuses => view == 'cycles' ? ['active', 'overdue', 'success', 'no_success', 'superseded']
    : ['new', 'assigned', 'in_progress', if (kind == 'collection') ...['promised', 'paid'] else ...['documents', 'qualified', 'disbursed', 'rejected']];

  void edit(VoidCallback change) {
    ++revision;
    setState(() { change(); applied = null; data = null; error = null; loading = false; offset = 0; });
  }

  String? dateError(String? value) {
    if (value == null || value.isEmpty) return null;
    final d = DateTime.tryParse(value);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) || d == null || d.toIso8601String().substring(0, 10) != value || d.year < 1900 || d.year > 2100) {
      return 'Gunakan YYYY-MM-DD (1900–2100).';
    }
    return null;
  }

  Map<String, String> query() => {
    'kind': kind, 'view': view,
    if (region.isNotEmpty) 'region_id': region,
    if (agent.isNotEmpty) 'agent_id': agent,
    if (status.isNotEmpty) 'status': status,
    if (from.text.isNotEmpty) 'date_from': from.text,
    if (to.text.isNotEmpty) 'date_to': to.text,
    if (search.text.trim().isNotEmpty) 'q': search.text.trim(),
  };

  Future<void> refresh({bool first = false}) async {
    if (!widget.api.supervisor || exporting || !(form.currentState?.validate() ?? true)) return;
    if (from.text.isNotEmpty && to.text.isNotEmpty && from.text.compareTo(to.text) > 0) {
      setState(() => error = 'Tanggal awal tidak boleh melewati tanggal akhir.'); return;
    }
    final current = ++revision;
    final params = query();
    if (first) offset = 0;
    final start = offset;
    setState(() { loading = true; error = null; data = null; applied = null; });
    try {
      final result = await widget.api.request('GET', '/api/reports?${Uri(queryParameters: {...params, 'offset': '$start', 'limit': '$pageSize'}).query}');
      if (!mounted || current != revision) return;
      final count = result['total'] as int;
      if (start > 0 && start >= count) {
        offset = count == 0 ? 0 : ((count - 1) ~/ pageSize) * pageSize;
        await refresh(); return;
      }
      setState(() { data = Map<String, dynamic>.from(result as Map); applied = params; });
    } catch (e) { if (mounted && current == revision) setState(() => error = '$e'); }
    finally { if (mounted && current == revision) setState(() => loading = false); }
  }

  Future<void> download() async {
    if (exporting || loading || data == null || applied == null) return;
    final params = Map<String, String>.of(applied!);
    final total = data!['total'];
    final session = widget.api.sessionRevision;
    setState(() => exporting = true);
    try {
      final approved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.all(16), title: const Text('Unduh laporan CSV?'),
        content: Text('${label(kind)} · ${view == 'cases' ? 'Portofolio kasus' : 'Siklus assignment'}\n'
          '$total baris pada seluruh halaman hasil filter.\n'
          'Tanggal WIB: ${params['date_from'] ?? 'awal data'} s.d. ${params['date_to'] ?? 'akhir data'}.\n\n'
          'CSV memakai filter laporan yang tampil. Data dihitung kembali saat unduh dan dapat berubah bila ada aktivitas baru. Data sintetis; bukan probabilitas ML.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Unduh'))],
      ));
      if (approved != true || !mounted) return;
      final bytes = await widget.api.exportCsv('/api/reports/export?${Uri(queryParameters: params).query}');
      if (!mounted || session != widget.api.sessionRevision) return;
      await widget.save(bytes, '${params['kind']}-${params['view']}-demo.csv');
      if (mounted) await showMessage(context, 'CSV siap; unduhan dimulai. Periksa unduhan browser atau lokasi penyimpanan pilihan.');
    } catch (e) { if (mounted) await showMessage(context, '$e'); }
    finally { if (mounted) setState(() => exporting = false); }
  }

  void reset() {
    edit(() { kind = 'collection'; view = 'cases'; region = ''; agent = ''; status = ''; from.clear(); to.clear(); search.clear(); });
    // Form.reset invokes dropdown callbacks with their OLD initialValue before
    // the keyed dropdowns rebuild, which can restore the previous filters.
    // refresh validates cleared text fields and clears their validation errors.
    refresh(first: true);
  }

  Widget dropdown(String name, String value, List<DropdownMenuItem<String>> items, ValueChanged<String> changed) =>
    DropdownButtonFormField<String>(key: ValueKey('$name-$value'), initialValue: value, isExpanded: true,
      decoration: InputDecoration(labelText: name), items: items, onChanged: exporting ? null : (v) => changed(v!));

  DropdownMenuItem<String> item(String value, String text) => DropdownMenuItem(value: value, child: Text(text, overflow: TextOverflow.ellipsis));

  Widget filters() => Surface(child: Form(key: form, child: LayoutBuilder(builder: (context, box) {
    final width = box.maxWidth >= 700 ? (box.maxWidth - 32) / 3 : box.maxWidth >= 450 ? (box.maxWidth - 16) / 2 : box.maxWidth;
    final choices = widget.agents.where((a) => ((a['report_scopes'] ?? [a]) as List).any((s) => s['kind'] == kind && (region.isEmpty || s['region_id'] == region)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Filter laporan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)), const SizedBox(height: 18),
      Wrap(spacing: 16, runSpacing: 16, children: [
        SizedBox(width: width, child: dropdown('Alur', kind, [item('collection', 'Penagihan'), item('origination', 'Pengajuan')], (v) => edit(() { kind = v; status = ''; agent = ''; }))),
        SizedBox(width: width, child: dropdown('Jenis laporan', view, [item('cases', 'Portofolio kasus'), item('cycles', 'Siklus assignment')], (v) => edit(() { view = v; status = ''; agent = ''; }))),
        SizedBox(width: width, child: dropdown('Wilayah', region, [item('', 'Semua wilayah'), ...widget.regions.map((r) => item(r['id'] as String, r['name'] as String))], (v) => edit(() { region = v; agent = ''; }))),
        SizedBox(width: width, child: dropdown('Petugas', agent, [item('', 'Semua petugas'), if (view == 'cases') item('unassigned', 'Belum ditugaskan'), ...choices.map((a) => item(a['id'] as String, a['name'] as String))], (v) => edit(() => agent = v))),
        SizedBox(width: width, child: dropdown(view == 'cases' ? 'Status kasus' : 'Hasil siklus', status, [item('', 'Semua'), ...statuses.map((s) => item(s, reportLabel(s)))], (v) => edit(() => status = v))),
        for (final entry in [(from, 'Tanggal awal'), (to, 'Tanggal akhir')]) SizedBox(width: width, child: TextFormField(
          controller: entry.$1, enabled: !exporting, validator: dateError, onChanged: (_) => edit(() {}),
          decoration: InputDecoration(labelText: '${entry.$2} (WIB)', hintText: 'YYYY-MM-DD'), keyboardType: TextInputType.datetime,
        )),
        SizedBox(width: width, child: TextFormField(controller: search, maxLength: 100, enabled: !exporting,
          decoration: const InputDecoration(labelText: 'Cari ID atau nama'), onChanged: (_) => edit(() {}))),
      ]),
      const SizedBox(height: 12),
      Text(view == 'cases' ? 'Tanggal memilih kasus berdasarkan waktu dibuat. Status, saldo, dan petugas adalah kondisi terkini.'
        : 'Tanggal memilih siklus berdasarkan awal assignment. Nominal adalah transaksi sepanjang siklus, termasuk setelah rentang tanggal; status kasus adalah kondisi terkini.', style: const TextStyle(color: muted, height: 1.5)),
      const SizedBox(height: 16), Wrap(spacing: 12, runSpacing: 12, children: [
        FilledButton(onPressed: exporting || loading ? null : () => refresh(first: true), child: const Text('Tampilkan laporan')),
        TextButton(onPressed: exporting ? null : reset, child: const Text('Reset filter')),
      ]),
    ]);
  })));

  Widget metric(String title, String value, double width) => SizedBox(width: width, child: Surface(padding: const EdgeInsets.all(18), child:
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: muted)), const SizedBox(height: 8), Text(value, style: const TextStyle(fontSize: 22, color: ink, fontWeight: FontWeight.w700))])));

  Widget summary() {
    final s = data!['summary'] as Map;
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth >= 900 ? (box.maxWidth - 48) / 4 : box.maxWidth >= 500 ? (box.maxWidth - 16) / 2 : box.maxWidth;
      final values = view == 'cases' ? [
        ('Kasus sesuai filter', '${s['total']}'), ('Nominal kasus', rupiah(s['amount'] as num)),
        (kind == 'collection' ? 'Pembayaran tercatat' : 'Pencairan simulasi', rupiah(s['realized'] as num)),
        (kind == 'collection' ? 'Sisa tagihan' : 'Nominal tanpa pencairan', rupiah(s['outstanding'] as num)),
        ('Belum ditugaskan', '${s['unassigned']}'), ('Kasus aktif', '${s['active']}'), ('Lunas / dicairkan', '${s['completed']}'), ('Ditolak', '${s['rejected']}'),
      ] : [
        ('Siklus sesuai filter', '${s['total']}'), ('Berhasil', '${s['success']}'), ('Tidak berhasil', '${s['no_success']}'), ('Dialihkan', '${s['superseded']}'),
        ('Siklus aktif', '${s['active']}'), ('Aktif melewati SLA', '${s['overdue']}'), ('Realisasi per siklus', rupiah(s['realized'] as num)),
        ('Keberhasilan hasil final', s['success_rate'] == null ? 'Belum ada hasil' : '${s['success_rate']}%'),
      ];
      return Wrap(spacing: 16, runSpacing: 16, children: values.map((v) => metric(v.$1, v.$2, width)).toList());
    });
  }

  Widget pager() {
    final total = data!['total'] as int;
    return Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      OutlinedButton(onPressed: offset > 0 && !exporting ? () { offset -= pageSize; refresh(); } : null, child: const Text('Sebelumnya')),
      Text('Halaman ${offset ~/ pageSize + 1} dari ${total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize}'),
      OutlinedButton(onPressed: offset + pageSize < total && !exporting ? () { offset += pageSize; refresh(); } : null, child: const Text('Berikutnya')),
    ]);
  }

  Widget row(dynamic r) => Padding(padding: const EdgeInsets.only(top: 12), child: Surface(padding: const EdgeInsets.all(20), child:
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${view == 'cases' ? r['id'] : '${r['case_id']} · Siklus ${r['cycle']}'} · ${r['region_name']}', style: const TextStyle(color: muted, fontSize: 12)),
      const SizedBox(height: 8), Text('${r['customer']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10), Wrap(spacing: 8, runSpacing: 8, children: [
        Pill('${r['agent_name'] ?? 'Belum ditugaskan'}'), Pill(view == 'cases' ? label(r['status'] as String) : reportLabel(r['outcome'] as String)),
        if (r['overdue'] == true) const Pill('Melewati SLA', color: Colors.deepOrange),
      ]), const SizedBox(height: 12),
      if (view == 'cases') Text('Nominal ${rupiah(r['amount'] as num)} · Realisasi ${rupiah(r['paid'] as num)}\nDibuat ${dateLabel(r['created_at'] as String?)}', style: const TextStyle(color: muted, height: 1.5))
      else Text('Awal ${dateLabel(r['assigned_at'] as String?)}\nSelesai ${dateLabel(r['ended_at'] as String?)}\nRealisasi siklus ${rupiah(r['realized'] as num)} · ${r['activity_count']} aktivitas\nStatus kasus kini: ${label(r['case_status'] as String)}', style: const TextStyle(color: muted, height: 1.5)),
      if (widget.onOpenCase != null) TextButton(onPressed: exporting ? null : () async {
        await widget.onOpenCase!((view == 'cases' ? r['id'] : r['case_id']) as String);
        if (mounted) await refresh();
      }, child: const Text('Buka detail kasus')),
    ])));

  @override
  Widget build(BuildContext context) {
    if (!widget.api.supervisor) return const EmptyState('Akses supervisor', 'Laporan tidak tersedia untuk akun ini.');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Laporan operasional · data sintetis', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8), const Text('Portofolio dan histori penugasan untuk penagihan serta pengajuan. Sumber dan versi skor atau prediksi dijelaskan pada detail kasus.', style: TextStyle(color: muted)),
      const SizedBox(height: 20), filters(), const SizedBox(height: 24),
      if (loading) const LinearProgressIndicator(),
      if (error != null) Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(error!, style: const TextStyle(color: Colors.red)), TextButton(onPressed: () => refresh(), child: const Text('Coba lagi laporan')),
      ])),
      if (!loading && data == null && error == null) const Text('Filter berubah. Tekan Tampilkan laporan untuk memuat hasil dan mengaktifkan ekspor.'),
      if (data != null && !loading) ...[
        Text('Dihitung ${dateLabel(data!['generated_at'] as String?)} · Ringkasan seluruh hasil filter, bukan hanya halaman ini.', style: const TextStyle(color: muted)),
        const SizedBox(height: 16), summary(), const SizedBox(height: 16),
        Text(view == 'cycles' ? 'Keberhasilan = berhasil ÷ (berhasil + tidak berhasil); siklus aktif dan dialihkan dikeluarkan. Penagihan lunas terlambat tetap tidak berhasil SLA. Pencairan simulasi memakai outcome pengajuan yang tersimpan.'
          : 'Realisasi merupakan total tercatat sampai saat laporan. Nominal tanpa pencairan termasuk pengajuan yang ditolak; bukan nilai persetujuan kredit.', style: const TextStyle(color: muted, fontSize: 12, height: 1.5)),
        const SizedBox(height: 16),
        ExpansionTile(title: const Text('Ringkasan per petugas'), children: [
          for (final a in data!['by_agent'] as List) ListTile(title: Text('${a['agent_name']}'), subtitle: Text('${a['total']} ${view == 'cases' ? 'kasus' : 'siklus'} · realisasi ${rupiah(a['realized'] as num)}${view == 'cycles' ? ' · ${a['success']} berhasil / ${a['no_success']} tidak berhasil / ${a['superseded']} dialihkan' : ''}')),
        ]), const SizedBox(height: 20),
        FilledButton.icon(onPressed: exporting ? null : download, icon: const Icon(Icons.download), label: Text(exporting ? 'Menyiapkan CSV…' : 'Unduh CSV (${data!['total']} baris)')),
        const SizedBox(height: 20), Text('${data!['total']} baris ditemukan · 25 baris per halaman'), const SizedBox(height: 12), pager(),
        if ((data!['items'] as List).isEmpty) const EmptyState('Tidak ada hasil laporan', 'Ubah filter. CSV kosong tetap memuat header kolom.'),
        ...(data!['items'] as List).map(row),
        const SizedBox(height: 16), pager(),
      ],
    ]);
  }
}

String reportLabel(String value) => const {'active': 'Aktif', 'overdue': 'Aktif melewati SLA'}[value] ?? label(value);
