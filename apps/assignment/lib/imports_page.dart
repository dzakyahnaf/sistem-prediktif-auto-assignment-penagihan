import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'api.dart';
import 'case_detail.dart';
import 'report_download.dart';
import 'widgets.dart';
import 'workbook_picker.dart';

class ImportsPage extends StatefulWidget {
  final Api api;
  final String initialKind;
  final Future<void> Function(Uint8List, String) save;
  const ImportsPage({super.key, required this.api, this.initialKind = 'collection', this.save = saveWorkbook});
  @override
  State<ImportsPage> createState() => ImportsPageState();
}

class ImportsPageState extends State<ImportsPage> {
  late String kind;
  String sheet = '';
  final header = TextEditingController(text: '1');
  Map<String, dynamic>? batch, layout;
  Map<String, int> mapping = {};
  List<dynamic> history = [];
  String? error, historyError;
  bool busy = false, historyLoading = false, acknowledge = false, uncertainCommit = false;
  int offset = 0;
  static const pageSize = 25;
  Map<String, dynamic>? get preview => batch?['preview'] == null ? null : Map<String, dynamic>.from(batch!['preview'] as Map);
  bool get editable => batch != null && ['uploaded', 'previewed'].contains(batch!['state']) && !uncertainCommit;
  @override
  void initState() { super.initState(); kind = widget.initialKind; loadHistory(); }
  @override
  void dispose() { header.dispose(); super.dispose(); }

  Future<void> loadHistory() async {
    if (!widget.api.supervisor) return;
    setState(() { historyLoading = true; historyError = null; });
    try {
      final result = await widget.api.request('GET', '/api/imports');
      if (mounted) setState(() => history = result as List);
    } catch (e) { if (mounted) setState(() => historyError = '$e'); }
    finally { if (mounted) setState(() => historyLoading = false); }
  }

  Future<void> run(Future<void> Function() action, {bool committing = false}) async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try { await action(); }
    catch (e) {
      if (mounted) setState(() {
        if (committing && e is ApiException) uncertainCommit = e.mayHaveSucceeded;
        error = '$e${uncertainCommit ? ' Hasil commit belum pasti. Periksa status batch sebelum tindakan lain.' : ''}';
      });
    } finally { if (mounted) setState(() => busy = false); }
  }

  void invalidate(VoidCallback change) {
    setState(() { change(); batch?.remove('preview'); acknowledge = false; offset = 0; error = null; });
  }

  Future<void> fetchLayout({bool preserve = false}) async {
    final row = int.tryParse(header.text);
    if (row == null || row < 1 || row > 20) throw ApiException('Baris header harus bilangan 1–20.');
    final oldMapping = preserve && preview != null ? (preview!['mapping'] as Map) : null;
    if (!preserve) invalidate(() { layout = null; mapping = {}; });
    final params = Uri(queryParameters: {'sheet': sheet, 'header_row': '$row'}).query;
    final result = await widget.api.request('GET', '/api/imports/${batch!['id']}/layout?$params');
    if (!mounted) return;
    setState(() {
      layout = Map<String, dynamic>.from(result as Map);
      mapping = Map<String, int>.from(oldMapping ?? result['mapping'] as Map);
    });
  }

  Future<void> upload(Uint8List bytes, String filename) => run(() async {
    if (uncertainCommit) throw ApiException('Periksa status commit batch sebelumnya terlebih dahulu.');
    if (!filename.toLowerCase().endsWith('.xlsx') || bytes.isEmpty || bytes.length > 5 * 1024 * 1024) throw ApiException('Pilih berkas .xlsx berisi data, maksimal 5 MB.');
    setState(() { batch = null; layout = null; mapping = {}; offset = 0; acknowledge = false; });
    final result = await widget.api.uploadWorkbook(bytes, filename, kind);
    if (!mounted) return;
    setState(() {
      batch = Map<String, dynamic>.from(result as Map);
      sheet = batch!['metadata']['suggested_sheet'] as String;
      header.text = '${batch!['metadata']['suggested_header_row']}';
    });
    await fetchLayout();
    if (mounted) await loadHistory();
  });

  Future<void> resume(String id) => run(() async {
    final result = await widget.api.request('GET', '/api/imports/$id');
    if (!mounted) return;
    setState(() {
      batch = Map<String, dynamic>.from(result as Map); kind = batch!['kind'] as String;
      sheet = (batch!['preview']?['sheet'] ?? batch!['metadata']['suggested_sheet']) as String;
      header.text = '${batch!['preview']?['header_row'] ?? batch!['metadata']['suggested_header_row']}';
      offset = 0; layout = null; mapping = {}; acknowledge = false; uncertainCommit = false;
    });
    if (editable) await fetchLayout(preserve: true);
    if (mounted) await loadHistory();
  });

  Future<void> refresh() async {
    if (busy) return;
    if (batch == null) { await loadHistory(); }
    else { await resume(batch!['id'] as String); }
  }

  Future<void> validate() => run(() async {
    if (!editable || layout == null) return;
    final row = int.tryParse(header.text);
    if (row != layout!['header_row'] || sheet != layout!['sheet']) throw ApiException('Muat kolom setelah mengubah worksheet/baris header.');
    setState(() { batch!.remove('preview'); acknowledge = false; offset = 0; });
    final result = await widget.api.request('POST', '/api/imports/${batch!['id']}/preview', {'sheet': sheet, 'header_row': row, 'mapping': mapping});
    if (mounted) { setState(() => batch = Map<String, dynamic>.from(result as Map)); await loadHistory(); }
  });

  Future<void> commit() => run(() async {
    final p = preview;
    if (!editable || p == null || p['can_commit'] != true || ((p['ignored_columns'] as List).isNotEmpty && !acknowledge)) return;
    final bid = batch!['id']; final revision = batch!['revision'];
    final approved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      insetPadding: const EdgeInsets.all(16), title: Text('Impor ${p['total']} kasus baru?'),
      content: SingleChildScrollView(child: Text('${label(kind)}\n${batch!['filename']}\nWorksheet $sheet · header baris ${p['header_row']}\n'
        'Total nominal ${rupiah(p['amount'] as num)}\n${(p['ignored_columns'] as List).length} kolom tidak dipetakan.\n\n'
        'Seluruh baris disimpan bersama atau dibatalkan bersama. Kasus baru belum ditugaskan. Kasus lama, pembayaran, dan histori tidak diperbarui.')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Impor sekarang'))],
    ));
    if (approved != true || !mounted) return;
    final result = await widget.api.request('POST', '/api/imports/$bid/commit', {'expected_revision': revision, 'acknowledge_ignored': acknowledge});
    if (!mounted) return;
    setState(() { batch = Map<String, dynamic>.from(result as Map); uncertainCommit = false; offset = 0; });
    await loadHistory();
  }, committing: true);

  Future<void> downloadTemplate() => run(() async {
    final session = widget.api.sessionRevision;
    final bytes = await widget.api.exportWorkbook('/api/imports/template?kind=$kind');
    if (!mounted || session != widget.api.sessionRevision) return;
    await widget.save(bytes, 'template-operasional-$kind.xlsx');
    if (mounted) await showMessage(context, 'Template operasional siap; periksa unduhan browser atau lokasi penyimpanan pilihan.');
  });

  Future<void> discard() => run(() async {
    final approved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Buang draft impor?'), content: const Text('Salinan workbook dan preview draft akan dilepas. Berkas di komputer dan kasus yang sudah ada tetap tersimpan.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Buang draft'))],
    ));
    if (approved == true && mounted) {
      final result = await widget.api.request('POST', '/api/imports/${batch!['id']}/discard');
      if (mounted) { setState(() { batch = Map<String, dynamic>.from(result as Map); layout = null; }); await loadHistory(); }
    }
  });

  Future<void> changeOffset(int value) => run(() async {
    final result = await widget.api.request('GET', '/api/imports/${batch!['id']}?offset=$value&limit=$pageSize');
    if (mounted) setState(() { batch = Map<String, dynamic>.from(result as Map); offset = value; });
  });

  Widget pager(int total) => Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
    OutlinedButton(onPressed: busy || offset == 0 ? null : () => changeOffset(offset - pageSize), child: const Text('Sebelumnya')),
    Text('Halaman ${offset ~/ pageSize + 1} dari ${total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize}'),
    OutlinedButton(onPressed: busy || offset + pageSize >= total ? null : () => changeOffset(offset + pageSize), child: const Text('Berikutnya')),
  ]);

  Widget mappingForm() => Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('2. Worksheet dan pemetaan', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)), const SizedBox(height: 16),
    DropdownButtonFormField<String>(key: ValueKey('sheet-$sheet'), initialValue: sheet, isExpanded: true, decoration: const InputDecoration(labelText: 'Worksheet'),
      items: (batch!['metadata']['sheets'] as List).map((s) => DropdownMenuItem(value: s['name'] as String, child: Text('${s['name']}${s['hidden'] == true ? ' (tersembunyi)' : ''}', overflow: TextOverflow.ellipsis))).toList(),
      onChanged: busy || uncertainCommit ? null : (v) => invalidate(() { sheet = v!; layout = null; mapping = {}; })),
    const SizedBox(height: 12), TextField(controller: header, enabled: !busy && !uncertainCommit, keyboardType: TextInputType.number,
      decoration: const InputDecoration(labelText: 'Baris header (1–20)'), onChanged: (_) => invalidate(() { layout = null; mapping = {}; })),
    const SizedBox(height: 12), OutlinedButton(onPressed: busy || uncertainCommit ? null : () => run(() => fetchLayout()), child: const Text('Muat kolom')),
    if (layout != null) ...[
      const SizedBox(height: 16), const Text('Petakan field wajib (*). Satu kolom hanya boleh dipakai untuk satu field. Kolom lain tidak akan diimpor.', style: TextStyle(color: muted)),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, box) => Wrap(spacing: 16, runSpacing: 16, children: [
        for (final f in layout!['fields'] as List) SizedBox(width: box.maxWidth >= 650 ? (box.maxWidth - 16) / 2 : box.maxWidth, child:
          DropdownButtonFormField<int>(key: ValueKey('map-${f['name']}-${mapping[f['name']]}'), initialValue: mapping[f['name']] ?? 0, isExpanded: true,
            decoration: InputDecoration(labelText: '${f['label']}${f['required'] == true ? ' *' : ''}', helperText: '${f['help']}', helperMaxLines: 3),
            items: [const DropdownMenuItem(value: 0, child: Text('Tidak dipetakan')), ...(layout!['columns'] as List).map((c) => DropdownMenuItem(value: c['index'] as int, child: Text('${c['letter']} · ${c['header']}', overflow: TextOverflow.ellipsis)))],
            onChanged: busy || uncertainCommit ? null : (v) => invalidate(() { if (v == 0) { mapping.remove(f['name']); } else { mapping[f['name'] as String] = v!; } }),
          )),
      ])), const SizedBox(height: 20),
      FilledButton(onPressed: busy || uncertainCommit ? null : validate, child: const Text('Preview & validasi')),
    ],
  ]));

  Widget previewView() {
    final p = preview!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('3. Tinjau hasil validasi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)), const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [Pill('${p['total']} baris'), Pill('${p['valid']} valid'), Pill('${p['invalid']} bermasalah', color: p['invalid'] == 0 ? teal : Colors.deepOrange)]),
        const SizedBox(height: 12), Text('Nominal baris valid: ${rupiah(p['amount'] as num)} · revisi ${batch!['revision']}'),
        const SizedBox(height: 8), const Text('Preview belum membuat kasus. Skor adalah indeks aturan demo, bukan probabilitas ML.', style: TextStyle(color: muted)),
        if ((p['ignored_columns'] as List).isNotEmpty) ...[
          const SizedBox(height: 14), Text('Kolom diabaikan: ${(p['ignored_columns'] as List).map((c) => '${c['letter']} · ${c['header']}').join(', ')}'),
          CheckboxListTile(key: const ValueKey('ack-ignored'), contentPadding: EdgeInsets.zero, value: acknowledge,
            title: const Text('Saya menyetujui kolom yang tidak dipetakan akan diabaikan.'),
            onChanged: busy || uncertainCommit ? null : (v) => setState(() => acknowledge = v == true)),
        ], const SizedBox(height: 16),
        FilledButton(onPressed: busy || uncertainCommit || p['can_commit'] != true || ((p['ignored_columns'] as List).isNotEmpty && !acknowledge) ? null : commit,
          child: Text('Impor ${p['total']} kasus')),
        if (p['total'] == 0) const Padding(padding: EdgeInsets.only(top: 12), child: Text('Tidak ada baris data. Isi worksheet mulai baris setelah header.')),
        if (p['invalid'] != 0) const Padding(padding: EdgeInsets.only(top: 12), child: Text('Perbaiki workbook atau pemetaan, lalu preview ulang. Tidak ada baris yang akan disimpan sebagian.')),
      ])), const SizedBox(height: 16), pager(p['total'] as int),
      for (final r in p['items'] as List) Padding(padding: const EdgeInsets.only(top: 12), child: SizedBox(width: double.infinity, child: Surface(padding: const EdgeInsets.all(18), child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Baris ${r['row']} · ${r['source_ref']}', style: const TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 8),
          for (final e in (r['raw'] as Map).entries) Text('${fieldLabel(e.key as String)}: ${e.value}', style: const TextStyle(color: muted, height: 1.5)),
          if (r['data'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Skor ${r['data']['score']} · Tim ${r['team']}')),
          for (final message in r['errors'] as List) Padding(padding: const EdgeInsets.only(top: 6), child: Text('$message', style: const TextStyle(color: Colors.deepOrange))),
        ])))) ,
      const SizedBox(height: 16), pager(p['total'] as int),
    ]);
  }

  Widget resultView() {
    final result = batch!['result'];
    return Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${result['total']} kasus berhasil diimpor', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10), Text('Disimpan ${dateLabel(result['committed_at'] as String?)}'),
      const SizedBox(height: 8), const Text('Saat impor, kasus baru masuk antrean tanpa assignment. Pengulangan commit batch ini tidak menambah kasus lagi.'),
      const SizedBox(height: 16), Wrap(spacing: 12, runSpacing: 8, children: [
        FilledButton(onPressed: busy ? null : () => Navigator.pop(context, true), child: const Text('Lihat antrean')),
        OutlinedButton(onPressed: busy ? null : refresh, child: const Text('Muat ulang status')),
      ]), const SizedBox(height: 16), pager(result['total'] as int),
      for (final r in result['items'] as List) ListTile(contentPadding: EdgeInsets.zero, title: Text('${r['source_ref']} · ${r['customer']}'),
        subtitle: Text('${r['case_id']}'), trailing: IconButton(tooltip: 'Buka kasus', icon: const Icon(Icons.chevron_right), onPressed: busy ? null : () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => CaseDetail(api: widget.api, caseId: r['case_id'] as String))))),
    ]));
  }

  @override
  Widget build(BuildContext context) => PopScope(canPop: !busy, child: Scaffold(
    appBar: AppBar(title: const Text('Impor Excel'), leading: BackButton(onPressed: busy ? null : () => Navigator.pop(context, batch?['state'] == 'committed')),
      actions: [IconButton(tooltip: 'Muat ulang impor', onPressed: busy ? null : refresh, icon: const Icon(Icons.refresh))]),
    body: !widget.api.supervisor ? const EmptyState('Akses supervisor', 'Impor tidak tersedia untuk akun ini.') : SingleChildScrollView(padding: const EdgeInsets.all(20), child:
      Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Kasus baru dari workbook operasional', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10), const Text('XLSX maksimal 5 MB, 2.000 baris, 64 kolom. Satu batch untuk satu alur. Draft berlaku 24 jam. Histori, pembayaran, petugas, dan target lama tidak diimpor.', style: TextStyle(color: muted, height: 1.5)),
        const SizedBox(height: 20),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
        if (uncertainCommit) Padding(padding: const EdgeInsets.only(bottom: 16), child: FilledButton(onPressed: busy ? null : refresh, child: const Text('Periksa status commit'))),
        Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('1. Pilih alur dan workbook', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)), const SizedBox(height: 16),
          DropdownButtonFormField<String>(key: ValueKey('kind-$kind'), initialValue: kind, isExpanded: true, decoration: const InputDecoration(labelText: 'Alur impor'),
            items: const [DropdownMenuItem(value: 'collection', child: Text('Penagihan')), DropdownMenuItem(value: 'origination', child: Text('Pengajuan'))],
            onChanged: busy || uncertainCommit ? null : (v) => setState(() { kind = v!; batch = null; layout = null; mapping = {}; acknowledge = false; error = null; })),
          const SizedBox(height: 16), Wrap(spacing: 12, runSpacing: 12, children: [
            OutlinedButton.icon(onPressed: busy || uncertainCommit ? null : downloadTemplate, icon: const Icon(Icons.download), label: const Text('Unduh template operasional')),
            WorkbookPicker(disabled: busy || uncertainCommit, onFile: upload, onError: (e) => setState(() => error = e)),
          ]), const SizedBox(height: 12), const Text('Template pengumpulan data awal tetap terpisah. Template operasional tidak berisi baris contoh yang langsung terimpor.', style: TextStyle(color: muted)),
        ])),
        if (batch != null) ...[
          const SizedBox(height: 20), Text('${batch!['id']} · ${batch!['filename']} · ${importState(batch!['state'] as String)}', style: const TextStyle(fontWeight: FontWeight.w600)),
          if (['uploaded', 'previewed', 'expired'].contains(batch!['state'])) ...[
            const SizedBox(height: 6), Text('Draft sampai ${dateLabel(batch!['expires_at'] as String?)}', style: const TextStyle(color: muted)),
          ],
          for (final warning in batch!['metadata']['warnings'] as List) Padding(padding: const EdgeInsets.only(top: 10), child: Text('$warning', style: const TextStyle(color: Colors.deepOrange))),
          const SizedBox(height: 16),
          if (editable) ...[mappingForm(), const SizedBox(height: 20)],
          if (batch!['state'] == 'committed') resultView()
          else if (preview != null) previewView()
          else if (['expired', 'discarded'].contains(batch!['state'])) const Text('Draft tidak dapat diproses. Pilih workbook untuk membuat draft baru.'),
          if (editable) Padding(padding: const EdgeInsets.only(top: 12), child: TextButton(onPressed: busy ? null : discard, child: const Text('Buang draft'))),
        ],
        const SizedBox(height: 24), ExpansionTile(title: const Text('Riwayat impor saya (20 terbaru)'), children: [
          if (historyLoading) const LinearProgressIndicator(),
          if (historyError != null) Text(historyError!, style: const TextStyle(color: Colors.red)),
          TextButton(onPressed: busy || historyLoading ? null : loadHistory, child: const Text('Muat riwayat')),
          if (history.isEmpty && !historyLoading) const Text('Belum ada batch impor.'),
          for (final h in history) ListTile(contentPadding: EdgeInsets.zero, title: Text('${h['filename']} · ${label(h['kind'] as String)}'),
            subtitle: Text('${h['id']}\n${importState(h['state'] as String)} · ${h['total']} kasus · ${dateLabel(h['created_at'] as String?)}'),
            trailing: IconButton(tooltip: 'Buka batch', icon: const Icon(Icons.chevron_right), onPressed: busy || uncertainCommit ? null : () => resume(h['id'] as String))),
        ]),
      ]))),
    ),
  ));
}

String importState(String value) => const {'uploaded': 'Menunggu pemetaan', 'previewed': 'Sudah dipreview', 'committed': 'Berhasil diimpor', 'expired': 'Kedaluwarsa', 'discarded': 'Draft dibuang'}[value] ?? value;
String fieldLabel(String value) => const {'source_ref': 'Referensi', 'customer': 'Alias', 'region_id': 'Wilayah', 'difficulty': 'Kesulitan', 'amount': 'Nominal', 'dpd': 'Hari terlambat', 'income': 'Penghasilan', 'interest': 'Minat', 'documents_complete': 'Dokumen lengkap'}[value] ?? value;
