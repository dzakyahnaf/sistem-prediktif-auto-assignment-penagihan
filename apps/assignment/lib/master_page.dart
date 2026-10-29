import 'package:flutter/material.dart';
import 'api.dart';
import 'widgets.dart';

class MasterPage extends StatefulWidget {
  final Api api;
  const MasterPage({super.key, required this.api});
  @override
  State<MasterPage> createState() => _MasterPageState();
}

class _MasterPageState extends State<MasterPage> {
  List<dynamic> regions = [], agents = [], audit = [];
  bool loading = true;
  String? error;
  String section = 'agents', search = '', status = '';
  final query = TextEditingController();
  @override
  void initState() { super.initState(); load(); }
  @override
  void dispose() { query.dispose(); super.dispose(); }
  Future<void> load() async {
    if (!widget.api.supervisor) { setState(() => loading = false); return; }
    setState(() { loading = true; error = null; });
    try {
      final result = await Future.wait([widget.api.request('GET', '/api/master/regions'), widget.api.request('GET', '/api/agents'), widget.api.request('GET', '/api/master/audit')]);
      if (mounted) setState(() { regions = result[0] as List; agents = result[1] as List; audit = result[2] as List; });
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => loading = false); }
  }
  Future<void> edit(bool agent, [Map<String, dynamic>? row]) async {
    await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => MasterDialog(api: widget.api, agent: agent, regions: regions, record: row));
    if (mounted) await load();
  }
  String regionName(dynamic id) => regions.where((r) => r['id'] == id).map((r) => r['name'] as String).firstOrNull ?? '$id';
  List<dynamic> get filtered => (section == 'agents' ? agents : regions).where((r) =>
    (status.isEmpty || (r['active'] == 1 ? 'active' : 'inactive') == status) &&
    [r['id'], r['name'], r['username'], r['kind'] == null ? '' : label(r['kind'] as String), r['region_id'], r['team']].join(' ').toLowerCase().contains(search.toLowerCase())).toList();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Master operasional'), actions: [IconButton(tooltip: 'Muat ulang master', onPressed: loading ? null : load, icon: const Icon(Icons.refresh))]),
    body: !widget.api.supervisor ? const EmptyState('Akses supervisor', 'Master tidak tersedia untuk akun ini.') : SingleChildScrollView(padding: const EdgeInsets.all(20), child:
      Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Wilayah, petugas, dan jejak keputusan', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)), const SizedBox(height: 12),
        const Text('Kode dan username tetap. Nonaktif menghentikan assignment baru; tugas dan login petugas lama tetap tersedia. Wilayah hanya dapat dinonaktifkan setelah tidak ada kasus terbuka atau petugas aktif.'),
        const SizedBox(height: 16), Wrap(spacing: 10, runSpacing: 8, children: [
          for (final s in [('agents', 'Petugas'), ('regions', 'Wilayah'), ('audit', 'Audit perubahan')]) ChoiceChip(label: Text(s.$2), selected: section == s.$1,
            onSelected: (_) => setState(() { section = s.$1; search = ''; query.clear(); status = ''; })),
        ]), const SizedBox(height: 16),
        if (loading) const LinearProgressIndicator(),
        if (error != null) ...[Text(error!, style: const TextStyle(color: Colors.red)), TextButton(onPressed: loading ? null : load, child: const Text('Coba lagi master'))],
        if (!loading && error == null && section != 'audit') ...[
          Wrap(spacing: 12, runSpacing: 12, children: [
            FilledButton.icon(onPressed: () => edit(section == 'agents'), icon: const Icon(Icons.add), label: Text(section == 'agents' ? 'Tambah petugas' : 'Tambah wilayah')),
            SizedBox(width: 240, child: DropdownButtonFormField<String>(key: ValueKey('status-$section-$status'), initialValue: status, isExpanded: true, decoration: const InputDecoration(labelText: 'Status master'),
              items: const [DropdownMenuItem(value: '', child: Text('Semua status')), DropdownMenuItem(value: 'active', child: Text('Aktif')), DropdownMenuItem(value: 'inactive', child: Text('Nonaktif'))], onChanged: (v) => setState(() => status = v!))),
          ]), const SizedBox(height: 16),
          TextField(controller: query, decoration: const InputDecoration(labelText: 'Cari kode, nama, wilayah atau username', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => search = v)),
          const SizedBox(height: 16), Text('${filtered.length} dari ${section == 'agents' ? agents.length : regions.length} ${section == 'agents' ? 'petugas' : 'wilayah'}'), const SizedBox(height: 12),
          if (filtered.isEmpty) const EmptyState('Tidak ada hasil', 'Ubah pencarian/status atau tambahkan master baru.'),
          for (final r in filtered) Padding(padding: const EdgeInsets.only(bottom: 12), child: Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 10, runSpacing: 8, children: [Text('${r['name']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)), Pill(r['active'] == 1 ? 'Aktif' : 'Nonaktif')]),
            const SizedBox(height: 10), Text('${r['id']} · revisi ${r['version']}'), const SizedBox(height: 8),
            if (section == 'agents') ...[
              Text('${regionName(r['region_id'])} · ${label(r['kind'] as String)} · Tim ${r['team']} · ${r['channel']}'),
              Text('${r['approach']} · Login ${r['username'] ?? 'belum tersedia'}'), const SizedBox(height: 8),
              Text('Aktif ${r['active_load']} · Hari ini ${r['daily_load']} · Kapasitas ${r['capacity']}'),
            ] else Text('${r['active_cases']} kasus terbuka · ${r['active_agents']} petugas aktif · ${r['case_count']} seluruh kasus'),
            const SizedBox(height: 12), OutlinedButton(onPressed: () => edit(section == 'agents', Map<String, dynamic>.from(r as Map)), child: Text(section == 'agents' ? 'Ubah petugas' : 'Ubah wilayah')),
          ]))),
        ],
        if (!loading && error == null && section == 'audit') ...[
          const Text('100 perubahan master/override terbaru. Seluruh audit tetap tersimpan pada backend.'), const SizedBox(height: 12),
          if (audit.isEmpty) const EmptyState('Belum ada perubahan', 'Perubahan master dan override akan tercatat di sini.'),
          for (final a in audit) Padding(padding: const EdgeInsets.only(bottom: 12), child: Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(masterAction(a['action'] as String), style: const TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 8),
            Text('${a['username']} · ${dateLabel(a['created_at'] as String)}'),
            Text('${a['case_id'] ?? a['detail']['agent_id'] ?? a['detail']['region_id'] ?? a['detail']['id'] ?? ''}'),
            if (a['detail']['reason'] != null || a['detail']['after']?['reason'] != null) Text('${a['detail']['reason'] ?? a['detail']['after']['reason']}'),
            if (a['action'] == 'override_assignment') Text('${a['detail']['previous_agent'] ?? 'Antrean'} → ${a['detail']['agent_id']} · siklus ${a['detail']['cycle']}'),
          ]))),
        ],
      ]))),
    ),
  );
}

String masterAction(String action) => const {'create_agent': 'Petugas dibuat', 'update_agent_profile': 'Profil petugas diubah', 'update_agent': 'Kapasitas/status diubah',
  'create_region': 'Wilayah dibuat', 'update_region': 'Wilayah diubah', 'override_assignment': 'Override assignment'}[action] ?? action;

class MasterDialog extends StatefulWidget {
  final Api api;
  final bool agent;
  final List<dynamic> regions;
  final Map<String, dynamic>? record;
  const MasterDialog({super.key, required this.api, required this.agent, required this.regions, this.record});
  @override
  State<MasterDialog> createState() => _MasterDialogState();
}

class _MasterDialogState extends State<MasterDialog> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  late Map<String, dynamic> record;
  String region = '', kind = 'collection', team = 'A', channel = 'Tele';
  bool active = true, busy = false;
  String? error;
  bool get creating => widget.record == null;
  @override
  void initState() {
    super.initState();
    for (final k in ['id', 'name', 'approach', 'capacity', 'username', 'password', 'reason']) { fields[k] = TextEditingController(); }
    populate(widget.record ?? {});
  }
  void populate(Map<String, dynamic> row) {
    record = row;
    for (final k in fields.keys) { fields[k]!.text = '${row[k] ?? (k == 'capacity' ? 12 : '')}'; }
    region = '${row['region_id'] ?? (widget.regions.isEmpty ? '' : widget.regions.first['id'])}';
    kind = '${row['kind'] ?? 'collection'}'; team = '${row['team'] ?? 'A'}'; channel = '${row['channel'] ?? 'Tele'}'; active = row['active'] == null || row['active'] == 1;
  }
  @override
  void dispose() { for (final c in fields.values) { c.dispose(); } super.dispose(); }
  Future<void> reload() async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      final rows = await widget.api.request('GET', widget.agent ? '/api/agents' : '/api/master/regions') as List;
      final row = rows.where((r) => r['id'] == record['id']).firstOrNull;
      if (row == null) throw ApiException('Master tidak ditemukan. Tutup dan muat ulang daftar.');
      if (mounted) setState(() { populate(Map<String, dynamic>.from(row as Map)); error = 'Versi terbaru dimuat. Tinjau dan isi alasan kembali sebelum menyimpan.'; });
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() { busy = true; error = null; });
    try {
      final payload = <String, dynamic>{'name': fields['name']!.text.trim(), 'active': active,
        if (creating) 'id': fields['id']!.text.trim(),
        if (!creating) ...{'expected_version': record['version'], 'reason': fields['reason']!.text.trim()},
        if (widget.agent) ...{'region_id': region, 'kind': kind, 'team': team, 'channel': channel, 'approach': fields['approach']!.text.trim(), 'capacity': int.parse(fields['capacity']!.text.trim()),
          if (creating) ...{'username': fields['username']!.text.trim(), 'password': fields['password']!.text}},
      };
      final path = '/api/master/${widget.agent ? 'agents' : 'regions'}${creating ? '' : '/${record['id']}'}';
      await widget.api.request(creating ? 'POST' : 'PATCH', path, payload);
      if (mounted) Navigator.pop(context, true);
    } catch (e) { if (mounted) setState(() => error = '$e${e is ApiException && e.mayHaveSucceeded ? ' Respons belum pasti. Periksa daftar atau muat versi terbaru sebelum mencoba ulang.' : ''}'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Widget text(String key, String title, {int min = 2, int max = 100, String? pattern, String? help, bool password = false}) => TextFormField(
    key: ValueKey('master-$key'), controller: fields[key], enabled: !busy, obscureText: password, maxLength: max,
    keyboardType: key == 'capacity' ? TextInputType.number : TextInputType.text,
    decoration: InputDecoration(labelText: title, helperText: help, helperMaxLines: 3),
    validator: (v) {
      final value = v?.trim() ?? '';
      if (value.length < min) return 'Isi minimal $min karakter.';
      if (pattern != null && !RegExp(pattern).hasMatch(value)) return 'Format tidak sesuai petunjuk.';
      if (key == 'capacity' && ((int.tryParse(value) ?? 0) < 1 || (int.tryParse(value) ?? 101) > 100)) return 'Kapasitas harus 1–100.';
      return null;
    });
  Widget select(String title, String value, List<DropdownMenuItem<String>> items, void Function(String) change) => DropdownButtonFormField<String>(
    key: ValueKey('$title-$value'), initialValue: value, isExpanded: true, decoration: InputDecoration(labelText: title), items: items,
    onChanged: busy ? null : (v) => setState(() => change(v!)), validator: (v) => v == null || v.isEmpty ? 'Pilih nilai.' : null);
  DropdownMenuItem<String> item(String v, String title) => DropdownMenuItem(value: v, child: Text(title, overflow: TextOverflow.ellipsis));
  @override
  Widget build(BuildContext context) => PopScope(canPop: !busy, child: Dialog(insetPadding: const EdgeInsets.all(16), child: ConstrainedBox(
    constraints: BoxConstraints(maxWidth: 760, maxHeight: MediaQuery.sizeOf(context).height - 48), child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${creating ? 'Tambah' : 'Ubah'} ${widget.agent ? 'petugas' : 'wilayah'}', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700)), const SizedBox(height: 12),
      Flexible(child: SingleChildScrollView(child: Form(key: form, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!creating) Text('${record['id']} · revisi ${record['version']}${widget.agent ? '\n${record['active_load']} kasus aktif · ${record['daily_load']} assignment hari ini' : ''}'), const SizedBox(height: 16),
        LayoutBuilder(builder: (context, box) {
          final children = <Widget>[
            if (creating) text('id', widget.agent ? 'Kode petugas' : 'Kode wilayah', max: widget.agent ? 40 : 8, pattern: widget.agent ? r'^[A-Z][A-Z0-9_-]{1,39}$' : r'^[A-Z][A-Z0-9_-]{1,7}$', help: 'Huruf besar, angka, _ atau -. Kode tidak dapat diubah.'),
            text('name', widget.agent ? 'Nama petugas sintetis' : 'Nama wilayah', max: widget.agent ? 100 : 80),
            if (widget.agent) ...[
              select('Wilayah petugas', region, widget.regions.map((r) => item(r['id'] as String, '${r['name']}${r['active'] == 0 ? ' (nonaktif)' : ''}')).toList(), (v) => region = v),
              select('Alur petugas', kind, [item('collection', 'Penagihan'), item('origination', 'Pengajuan')], (v) => kind = v),
              select('Tim petugas', team, [item('A', 'Tim A'), item('B', 'Tim B')], (v) => team = v),
              select('Kanal petugas', channel, [item('Tele', 'Tele'), item('Lapangan', 'Lapangan')], (v) => channel = v),
              text('approach', 'Pendekatan'), text('capacity', 'Kapasitas', min: 1, max: 3, help: '1–100; beban aktif dan harian diperiksa saat simpan.'),
              if (creating) ...[text('username', 'Username baru', min: 3, max: 40, pattern: r'^[a-z0-9][a-z0-9._-]{2,39}$', help: 'Huruf kecil, angka, titik, _ atau -. Username tetap.'), text('password', 'Password awal', min: 12, max: 128, password: true, help: 'Minimal 12 karakter. Tidak dicatat dalam audit.')],
            ],
          ];
          return Wrap(spacing: 16, runSpacing: 16, children: [for (final child in children) SizedBox(width: box.maxWidth >= 600 ? (box.maxWidth - 16) / 2 : box.maxWidth, child: child)]);
        }), const SizedBox(height: 16),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(widget.agent ? 'Aktif menerima assignment' : 'Wilayah aktif'), value: active, onChanged: busy ? null : (v) => setState(() => active = v)),
        if (!creating) ...[const SizedBox(height: 12), text('reason', 'Alasan perubahan master', min: 10, max: 500)],
        if (widget.agent) const Text('Wilayah/alur/tim tidak dapat diubah selama masih ada tugas aktif. Penonaktifan tidak mencabut login untuk menyelesaikan tugas lama.'),
        if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
      ])))), const SizedBox(height: 16),
      Wrap(spacing: 10, runSpacing: 8, children: [TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Tutup')),
        if (!creating) OutlinedButton(onPressed: busy ? null : reload, child: const Text('Muat versi terbaru')),
        FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Menyimpan…' : 'Simpan master'))]),
    ])),
  )));
}
