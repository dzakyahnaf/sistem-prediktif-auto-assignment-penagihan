import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'case_detail.dart';
import 'case_form.dart';
import 'agent_settings.dart';
import 'reports_page.dart';
import 'imports_page.dart';
import 'master_page.dart';
import 'analytics_page.dart';
import 'models_page.dart';
import 'decisions_page.dart';
import 'operations_page.dart';
import 'widgets.dart';

class Workspace extends StatefulWidget {
  final Api api;
  final VoidCallback onLogout;
  const Workspace({super.key, required this.api, required this.onLogout});
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  Map<String, dynamic>? dashboard;
  List<dynamic> recent = [], rows = [], agents = [], regions = [], reportRegions = [];
  static const pageSize = 25;
  int offset = 0, total = 0, queueRevision = 0, summaryRevision = 0;
  int page = 0;
  bool loading = true, working = false, queueLoading = false;
  String search = '', filter = 'all';
  String? error, queueError;
  final searchController = TextEditingController();
  final contentScroll = ScrollController();
  final reportsKey = GlobalKey<ReportsPageState>();
  Timer? searchTimer;
  final selectedCases = <String, Map<String, dynamic>>{};
  bool eligible(dynamic c) => c['agent_id'] == null && !['paid', 'disbursed', 'rejected'].contains(c['status']);
  @override
  void initState() { super.initState(); load(); }
  @override
  void dispose() { searchTimer?.cancel(); searchController.dispose(); contentScroll.dispose(); super.dispose(); }

  Future<void> load() async {
    final revision = ++summaryRevision;
    searchTimer?.cancel();
    final queueRefresh = page == 1 || page == 2 ? loadQueue() : Future<void>.value();
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final values = await Future.wait([
        widget.api.request('GET', '/api/dashboard'), widget.api.request('GET', '/api/config'),
        widget.api.request('GET', '/api/cases?status=new&limit=5'),
        if (widget.api.supervisor) widget.api.request('GET', '/api/agents'),
      ]);
      if (!mounted || revision != summaryRevision) return;
      setState(() {
        dashboard = Map<String, dynamic>.from(values[0] as Map);
        regions = values[1]['regions'] as List;
        reportRegions = (values[1]['report_regions'] ?? values[1]['regions']) as List;
        recent = values[2]['items'] as List;
        agents = widget.api.supervisor ? values[3] as List : [];
      });
    } catch (e) {
      if (!mounted || revision != summaryRevision) return;
      if (e is ApiException && e.status == 401) return;
      setState(() => error = '$e');
    } finally { if (mounted && revision == summaryRevision) setState(() => loading = false); }
    await queueRefresh;
  }

  void scrollToTop() { if (contentScroll.hasClients) contentScroll.jumpTo(0); }

  Future<void> loadQueue() async {
    if (!mounted || (page != 1 && page != 2)) return;
    final revision = ++queueRevision;
    final requestedOffset = offset;
    final query = Uri(queryParameters: {
      'kind': page == 1 ? 'collection' : 'origination',
      'offset': '$requestedOffset', 'limit': '$pageSize',
      if (search.trim().isNotEmpty) 'q': search.trim(),
      if (filter != 'all') 'status': filter,
    }).query;
    setState(() { queueLoading = true; queueError = null; });
    try {
      final result = await widget.api.request('GET', '/api/cases?$query');
      if (!mounted || revision != queueRevision) return;
      final count = result['total'] as int;
      final lastOffset = count == 0 ? 0 : ((count - 1) ~/ pageSize) * pageSize;
      // A case may leave the current filter after an activity or assignment.
      if (requestedOffset > lastOffset) {
        offset = lastOffset;
        await loadQueue();
        return;
      }
      setState(() {
        rows = result['items'] as List; total = count;
        for (final c in rows) {
          if (!eligible(c)) { selectedCases.remove(c['id']); }
          else if (selectedCases.containsKey(c['id'])) { selectedCases[c['id'] as String] = Map<String, dynamic>.from(c as Map); }
        }
      });
    } catch (e) {
      if (mounted && revision == queueRevision) setState(() => queueError = '$e');
    } finally {
      if (mounted && revision == queueRevision) setState(() => queueLoading = false);
    }
  }

  void changeSearch(String value) {
    searchTimer?.cancel();
    ++queueRevision; // Invalidate immediately, before the debounce fires.
    setState(() { search = value; offset = 0; queueLoading = true; queueError = null; selectedCases.clear(); });
    scrollToTop();
    searchTimer = Timer(const Duration(milliseconds: 300), loadQueue);
  }

  void changeFilter(String value) {
    searchTimer?.cancel();
    setState(() { filter = value; offset = 0; selectedCases.clear(); });
    scrollToTop();
    loadQueue();
  }

  void changeOffset(int value) {
    setState(() => offset = value);
    scrollToTop();
    loadQueue();
  }

  void selectCase(dynamic c, bool checked) {
    if (!eligible(c) || working) return;
    setState(() {
      if (!checked) { selectedCases.remove(c['id']); }
      else if (selectedCases.length < 100) { selectedCases[c['id'] as String] = Map<String, dynamic>.from(c as Map); }
    });
  }

  void selectVisible() {
    setState(() {
      for (final c in rows.where(eligible)) {
        if (selectedCases.length >= 100) break;
        selectedCases[c['id'] as String] = Map<String, dynamic>.from(c as Map);
      }
    });
  }

  Future<void> assignSelected() async {
    if (working || !widget.api.supervisor || selectedCases.isEmpty) return;
    final snapshot = selectedCases.values.toList();
    final ids = snapshot.map((c) => c['id'] as String).toList();
    final visibleIds = rows.map((c) => c['id']).toSet();
    final hidden = ids.where((id) => !visibleIds.contains(id)).length;
    setState(() => working = true);
    try {
      final approved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.all(16),
        title: Text('Tugaskan ${ids.length} kasus terpilih?'),
        content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$hidden pilihan dari halaman lain. Periksa daftar sebelum melanjutkan. Tim, wilayah, status, dan kapasitas diperiksa kembali oleh server.'),
          const SizedBox(height: 12),
          Flexible(child: SizedBox(height: 300, child: ListView(children: snapshot.map((c) => ListTile(
            contentPadding: EdgeInsets.zero, title: Text(c['customer'] as String),
            subtitle: Text('${c['id']} · ${regionName(c['region_id'] as String)} · ${rupiah(c['amount'] as num)}'),
          )).toList()))),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tugaskan'))],
      ));
      if (approved != true || !mounted) return;
      final result = await widget.api.request('POST', '/api/assignments', {'case_ids': ids});
      final results = result['results'] as List;
      final assigned = results.where((r) => r['assigned'] == true).length;
      if (!mounted) return;
      setState(() {
        for (final r in results.where((r) => r['assigned'] == true)) { selectedCases.remove(r['case_id']); }
      });
      await load();
      if (mounted) await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.all(16), title: const Text('Hasil assignment'),
        content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$assigned ditugaskan · ${results.length-assigned} belum ditugaskan.'),
          const SizedBox(height: 12),
          Flexible(child: SizedBox(height: 300, child: ListView(children: results.map((r) => ListTile(
            contentPadding: EdgeInsets.zero, title: Text('${r['case_id']}'),
            subtitle: Text(r['assigned'] == true ? 'Ditugaskan: ${r['agent_id']}' : '${r['reason']}'),
          )).toList()))),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup'))],
      ));
    } catch (e) {
      if (mounted) await showMessage(context, '$e Pilihan disimpan; muat ulang sebelum mencoba kembali.');
      if (mounted) await load();
    }
    finally { if (mounted) setState(() => working = false); }
  }

  Future<void> openCase(String id) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CaseDetail(api: widget.api, caseId: id)));
    if (mounted) await load();
  }

  Future<void> createCase(String kind) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => CaseForm(api: widget.api, kind: kind, regions: regions));
    if (saved == true && mounted) { offset = 0; scrollToTop(); await load(); }
  }

  Future<void> importCases(String kind) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ImportsPage(api: widget.api, initialKind: kind)));
    if (!mounted) return;
    if (saved == true) {
      searchTimer?.cancel(); ++queueRevision;
      setState(() { offset = 0; search = ''; filter = 'all'; searchController.clear(); selectedCases.clear(); });
      scrollToTop();
    }
    await load();
  }

  Future<void> editAgent(Map<String, dynamic> agent) async {
    if (!widget.api.supervisor) return;
    final saved = await showDialog<bool>(
      context: context, barrierDismissible: false,
      builder: (_) => AgentSettingsDialog(api: widget.api, agent: agent),
    );
    // Refresh after closing too: a network error may hide a committed update.
    if (mounted) await load();
    if (saved == true && mounted) await showMessage(context, 'Pengaturan petugas disimpan.');
  }

  Future<void> master() async {
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => MasterPage(api: widget.api)));
    if (mounted) await load();
  }

  Future<void> openAnalytics() async {
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => AnalyticsPage(api: widget.api)));
    if (mounted) await load();
  }

  Future<void> openModels() async {
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => ModelsPage(api: widget.api)));
    if (mounted) await load();
  }

  Future<void> openDecisions() async {
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => DecisionsPage(api: widget.api)));
    if (mounted) await load();
  }

  Future<void> openOperations() async {
    await Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>OperationsPage(api:widget.api)));
    if(mounted)await load();
  }

  void selectPage(int index) {
    searchTimer?.cancel();
    ++queueRevision;
    if (working) return;
    setState(() { page = index; search = ''; filter = 'all'; searchController.clear(); offset = 0; total = 0; rows = []; queueError = null; selectedCases.clear(); });
    scrollToTop();
    if (index == 1 || index == 2) loadQueue();
  }
  String regionName(String id) {
    for (final region in regions) {
      if (region['id'] == id) return region['name'] as String;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Ringkasan operasional', 'Penagihan', 'Pengajuan pinjaman', 'Petugas & kapasitas', 'Laporan operasional'];
    final icons = [Icons.space_dashboard_outlined, Icons.account_balance_wallet_outlined, Icons.note_add_outlined, Icons.groups_outlined, Icons.summarize_outlined];
    final names = ['Ringkasan', 'Penagihan', 'Pengajuan', 'Petugas', 'Laporan'];
    final count = widget.api.supervisor ? 5 : 3;
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      appBar: wide ? null : AppBar(title: const Text('Assignment Studio'), actions: [IconButton(tooltip: 'Keluar', onPressed: logout, icon: const Icon(Icons.logout))]),
      bottomNavigationBar: wide ? null : NavigationBar(selectedIndex: page, onDestinationSelected: selectPage,
        destinations: List.generate(count, (i) => NavigationDestination(icon: Icon(icons[i]), label: names[i]))),
      body: Row(children: [
        if (wide) Container(width: 240, color: ink, child: SafeArea(child: Padding(padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 20), const Icon(Icons.hub_outlined, color: Color(0xFF83E0D1), size: 36), const SizedBox(height: 18),
          const Text('Assignment\nStudio', style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w700, height: 1.2)),
          const SizedBox(height: 12), const Text('RUANG KERJA TIM', style: TextStyle(color: Color(0xFF94ABB5), fontSize: 10, letterSpacing: 2)),
          const SizedBox(height: 48),
          Expanded(child: ListView(padding: EdgeInsets.zero, children: List.generate(count, (i) => Padding(padding: const EdgeInsets.only(bottom: 8), child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            tileColor: page == i ? const Color(0xFF234551) : null,
            leading: Icon(icons[i], color: page == i ? const Color(0xFF83E0D1) : Colors.white70, size: 22),
            title: Text(names[i], style: const TextStyle(color: Colors.white, fontSize: 14)), onTap: () => selectPage(i),
          ))))),
          const Divider(color: Colors.white24), const SizedBox(height: 12),
          Text(widget.api.user?['username'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6), Text(widget.api.supervisor ? 'Supervisor' : widget.api.readOnly ? 'Pengunjung · akses baca' : 'Petugas', style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 12), TextButton.icon(onPressed: logout, icon: const Icon(Icons.logout, size: 16), label: const Text('Keluar'), style: TextButton.styleFrom(foregroundColor: Colors.white70)),
        ])))),
        Expanded(child: SafeArea(child: Column(children: [
          Padding(padding: EdgeInsets.fromLTRB(wide ? 36 : 20, 24, wide ? 36 : 20, 16), child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('WORKSPACE / OPERASIONAL', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.5)),
              const SizedBox(height: 8), Text(titles[page], style: TextStyle(fontSize: wide ? 28 : 22, fontWeight: FontWeight.w700, color: ink)),
            ])),
            if (wide) const Pill('Data sintetis'), const SizedBox(width: 12),
            IconButton(tooltip: 'Muat ulang', onPressed: loading ? null : page == 4 ? () => reportsKey.currentState?.refresh() : load, icon: const Icon(Icons.refresh)),
          ])),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          if (error != null) MaterialBanner(content: Text(error!), actions: [TextButton(onPressed: load, child: const Text('Coba lagi'))]),
          Expanded(child: dashboard == null
            ? (loading ? const Center(child: CircularProgressIndicator()) : const EmptyState('Data belum tersedia', 'Muat ulang setelah koneksi API pulih.'))
            : SingleChildScrollView(controller: contentScroll, padding: EdgeInsets.all(wide ? 36 : 20), child: page == 0 ? overview() : page == 3 ? agentView() : page == 4
              ? ReportsPage(key: reportsKey, api: widget.api, regions: reportRegions, agents: agents, onOpenCase: openCase)
              : caseQueue(page == 1 ? 'collection' : 'origination'))),
        ]))),
      ]),
    );
  }

  Future<void> logout() async {
    final revision = widget.api.sessionRevision;
    try { await widget.api.request('POST', '/api/auth/logout'); }
    on ApiException { /* Always clear the local session when offline. */ }
    finally { if (mounted && widget.api.sessionRevision == revision) widget.onLogout(); }
  }

  Widget overview() {
    final streams = dashboard!['streams'] as Map;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: double.infinity, padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Setiap kasus, tindak lanjut yang tepat.', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12), const Text('Pantau dua alur bisnis dan jaga pembagian tugas tetap sesuai kapasitas tim.', style: TextStyle(color: Color(0xFFBCD0D8), height: 1.6)),
        const SizedBox(height: 22), Wrap(spacing: 12, runSpacing: 12, children: [
          FilledButton.icon(onPressed: () => selectPage(1), icon: const Icon(Icons.arrow_forward, size: 18), label: const Text('Buka penagihan')),
          OutlinedButton(onPressed: () => selectPage(2), style: OutlinedButton.styleFrom(foregroundColor: Colors.white), child: const Text('Buka pengajuan')),
          if (widget.api.supervisor) OutlinedButton.icon(
            onPressed: openAnalytics,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white), icon: const Icon(Icons.analytics_outlined), label: const Text('Analitik historis')),
          if (widget.api.supervisor) OutlinedButton.icon(
            onPressed: openModels,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white), icon: const Icon(Icons.science_outlined), label: const Text('Model & evaluasi')),
          if (widget.api.supervisor) OutlinedButton.icon(onPressed: openDecisions,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white), icon: const Icon(Icons.tune), label: const Text('Keputusan & segmen')),
          if (!widget.api.readOnly) OutlinedButton.icon(onPressed:openOperations,style:OutlinedButton.styleFrom(foregroundColor:Colors.white),icon:const Icon(Icons.notifications_outlined),label:const Text('Operasi & notifikasi')),
        ]),
      ])),
      const SizedBox(height: 24),
      LayoutBuilder(builder: (context, constraints) => Wrap(spacing: 16, runSpacing: 16, children: [
        for (final kind in ['collection', 'origination']) SizedBox(width: constraints.maxWidth >= 700 ? (constraints.maxWidth-16)/2 : constraints.maxWidth,
          child: Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label(kind), style: const TextStyle(color: muted, fontWeight: FontWeight.w600)), const SizedBox(height: 16),
            Text('${streams[kind]['total']}', style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w700, color: ink)),
            const SizedBox(height: 12), Wrap(spacing: 8, runSpacing: 8, children: [Pill('${streams[kind]['unassigned']} antrean', color: const Color(0xFFB47116)), Pill('${streams[kind]['active']} aktif'), Pill('${streams[kind]['completed']} selesai')]),
            const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider()),
            Text(kind == 'collection' ? 'Pembayaran tercatat' : 'Pencairan simulasi', style: const TextStyle(color: muted, fontSize: 12)),
            const SizedBox(height: 6), Text(rupiah(streams[kind]['realized'] as num), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: ink)),
            if ((streams[kind]['overdue'] as int) > 0) Padding(padding: const EdgeInsets.only(top: 12), child: Pill('${streams[kind]['overdue']} melewati SLA', color: Colors.deepOrange)),
          ]))),
      ])),
      const SizedBox(height: 28), const Text('Menunggu penugasan', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: ink)),
      const SizedBox(height: 6), const Text('Indeks prioritas demo menggunakan aturan yang dapat dijelaskan.', style: TextStyle(color: muted)), const SizedBox(height: 16),
      if (recent.isEmpty) const Surface(child: EmptyState('Antrean sudah tertangani', 'Periksa aktivitas pada kasus yang sedang berjalan.')),
      ...recent.map(caseCard),
      const SizedBox(height: 12), Text(dashboard!['score_mode'] == 'mixed-ml-simulation'
        ? 'Model simulasi aktif untuk keputusan baru; kasus tanpa snapshot/domain sesuai memakai fallback rules. Antrean menampilkan skor tersimpan.'
        : 'Rules aktif. Skor simulasi 0–100 adalah indeks aturan; model demo dapat dipilih supervisor.', style: const TextStyle(color: muted, fontSize: 12)),
    ]);
  }

  Widget caseQueue(String kind) {
    final ready = !loading && !queueLoading && queueError == null && !working;
    final assignable = rows.any((c) => eligible(c) && !selectedCases.containsKey(c['id']));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (widget.api.supervisor) FilledButton.icon(onPressed: ready && selectedCases.isNotEmpty ? assignSelected : null, icon: const Icon(Icons.auto_awesome_outlined, size: 18), label: Text(working ? 'Memproses…' : 'Tinjau & tugaskan (${selectedCases.length})')),
        if (widget.api.supervisor) OutlinedButton.icon(onPressed: working || loading ? null : () => createCase(kind), icon: const Icon(Icons.add, size: 18), label: Text(kind == 'collection' ? 'Kasus baru' : 'Pengajuan baru')),
        if (widget.api.supervisor) OutlinedButton.icon(onPressed: working || loading ? null : () => importCases(kind), icon: const Icon(Icons.upload_file, size: 18), label: const Text('Impor Excel')),
      ]),
      if (widget.api.supervisor) ...[
        const SizedBox(height: 12),
        Text('${selectedCases.length}/100 kasus terpilih · ${selectedCases.keys.where((id) => !rows.any((c) => c['id'] == id)).length} dari halaman lain'),
        const SizedBox(height: 8),
        const Text('Pilihan bertahan antarhalaman. Pencarian, filter, atau menu baru mengosongkan pilihan.', style: TextStyle(color: muted, fontSize: 12)),
        Wrap(spacing: 12, runSpacing: 8, children: [
          TextButton(onPressed: ready && assignable && selectedCases.length < 100 ? selectVisible : null, child: const Text('Pilih halaman ini')),
          TextButton(onPressed: !working && selectedCases.isNotEmpty ? () => setState(selectedCases.clear) : null, child: const Text('Kosongkan pilihan')),
        ]),
      ],
      const SizedBox(height: 20), TextField(controller: searchController, enabled: !working, maxLength: 100, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cari ID, nama demo, atau kode wilayah…'), onChanged: changeSearch),
      const SizedBox(height: 16), Wrap(spacing: 8, runSpacing: 8, children: [
        for (final status in ['all', 'new', 'assigned', 'in_progress', if (kind == 'collection') 'promised', if (kind == 'origination') ...['documents', 'qualified'], kind == 'collection' ? 'paid' : 'disbursed', if (kind == 'origination') 'rejected'])
          ChoiceChip(label: Text(status == 'all' ? 'Semua' : label(status)), selected: filter == status, onSelected: working ? null : (_) => changeFilter(status)),
      ]),
      const SizedBox(height: 20),
      if (queueLoading) const Padding(padding: EdgeInsets.all(16), child: Text('Memuat kasus…')),
      if (queueError != null) Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(queueError!, style: const TextStyle(color: Colors.red)), const SizedBox(height: 12), TextButton(onPressed: loadQueue, child: const Text('Coba lagi antrean'))])),
      if (!queueLoading && queueError == null) ...[
        Text(total == 0 ? '0 kasus ditemukan' : '${offset + 1}–${offset + rows.length} dari $total kasus', style: const TextStyle(color: muted)),
        const SizedBox(height: 12), pagination(ready), const SizedBox(height: 16),
        if (rows.isEmpty) const Surface(child: EmptyState('Tidak ada kasus', 'Ubah pencarian atau filter untuk melihat kasus lainnya.')),
        ...rows.map((c) => caseCard(c, selectable: widget.api.supervisor)),
        if (rows.isNotEmpty) pagination(ready),
      ],
      const SizedBox(height: 16), const Text('25 kasus per halaman. Hanya kasus belum ditugaskan dan belum selesai yang dapat dipilih.', style: TextStyle(color: muted, fontSize: 12)),
    ]);
  }

  Widget pagination(bool ready) => Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
    OutlinedButton.icon(onPressed: ready && offset > 0 ? () => changeOffset(offset - pageSize) : null, icon: const Icon(Icons.chevron_left), label: const Text('Sebelumnya')),
    Text('Halaman ${total == 0 ? 1 : offset ~/ pageSize + 1} dari ${total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize}'),
    OutlinedButton.icon(onPressed: ready && offset + pageSize < total ? () => changeOffset(offset + pageSize) : null, icon: const Icon(Icons.chevron_right), label: const Text('Berikutnya')),
  ]);

  Widget caseCard(dynamic c, {bool selectable = false}) => Padding(padding: const EdgeInsets.only(bottom: 12), child: InkWell(
    borderRadius: BorderRadius.circular(18), onTap: working ? null : () => openCase(c['id'] as String),
    child: Surface(padding: const EdgeInsets.all(20), child: LayoutBuilder(builder: (context, constraints) {
      final summary = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (selectable) CheckboxListTile(
          key: ValueKey('select-${c['id']}'), contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
          title: Text(eligible(c) ? 'Pilih kasus' : 'Tidak dapat dipilih'),
          value: selectedCases.containsKey(c['id']),
          onChanged: !working && eligible(c) && (selectedCases.containsKey(c['id']) || selectedCases.length < 100) ? (value) => selectCase(c, value == true) : null,
        ),
        Text('${c['id']}  ·  ${regionName(c['region_id'] as String)}', style: const TextStyle(color: muted, fontSize: 11)),
        const SizedBox(height: 8), Text(c['customer'] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: ink)),
        const SizedBox(height: 8), Text(rupiah(c['amount'] as num), style: const TextStyle(color: muted)),
      ]);
      final tags = Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Pill(c['difficulty'] as String, color: c['difficulty'] == 'High' ? Colors.deepOrange : muted),
        Pill(label(c['status'] as String)), Pill('Skor ${c['score']}', color: ink), const Icon(Icons.chevron_right, color: muted),
      ]);
      return constraints.maxWidth > 650 ? Row(children: [Expanded(child: summary), tags]) : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [summary, const SizedBox(height: 16), tags]);
    })),
  ));

  Widget agentView() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    if (widget.api.supervisor) ...[FilledButton.icon(onPressed: loading ? null : master, icon: const Icon(Icons.settings_outlined), label: const Text('Kelola master operasional')), const SizedBox(height: 20)],
    const Text('Kapasitas berlaku untuk assignment hari ini dan jumlah kasus aktif. Penugasan tetap disaring berdasarkan wilayah, alur bisnis, dan tim.', style: TextStyle(color: muted, height: 1.6)),
    const SizedBox(height: 20),
    ...agents.map((a) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(a['name'] as String, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: ink))), Pill(a['active'] == 1 ? 'Aktif' : 'Nonaktif', color: a['active'] == 1 ? teal : muted)]),
      const SizedBox(height: 8), Text('${label(a['kind'] as String)} · ${regionName(a['region_id'] as String)} · Tim ${a['team']}', style: const TextStyle(color: muted)),
      const SizedBox(height: 18), LinearProgressIndicator(value: ((a['active_load'] as num)/(a['capacity'] as num)).clamp(0,1).toDouble(), minHeight: 6, borderRadius: BorderRadius.circular(6)),
      const SizedBox(height: 10), Text('${a['active_load']} kasus aktif / ${a['capacity']} kapasitas · ${a['daily_load']} assignment hari ini', style: const TextStyle(color: muted, fontSize: 12)),
      if (widget.api.supervisor) ...[
        const SizedBox(height: 16),
        OutlinedButton.icon(onPressed: loading ? null : () => editAgent(Map<String, dynamic>.from(a as Map)), icon: const Icon(Icons.tune, size: 18), label: const Text('Atur kapasitas & status')),
      ],
    ])))),
  ]);
}
