import 'package:flutter/material.dart';
import 'api.dart';

class CaseForm extends StatefulWidget {
  final Api api;
  final String kind;
  final List<dynamic> regions;
  const CaseForm({super.key, required this.api, required this.kind, required this.regions});
  @override
  State<CaseForm> createState() => _CaseFormState();
}

class _CaseFormState extends State<CaseForm> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final amount = TextEditingController();
  final income = TextEditingController();
  final dpd = TextEditingController(text: '0');
  String region = '', difficulty = 'Medium';
  int interest = 3;
  bool documents = false, busy = false;
  String? error;
  @override
  void initState() { super.initState(); if (widget.regions.isNotEmpty) region = widget.regions.first['id'] as String; }
  @override
  void dispose() { for (final c in [name,amount,income,dpd]) { c.dispose(); } super.dispose(); }
  String? positive(String? v) => (int.tryParse(v ?? '') ?? 0) > 0 ? null : 'Masukkan bilangan bulat positif.';
  Future<void> save() async {
    if (!form.currentState!.validate() || region.isEmpty) return;
    setState(() { busy = true; error = null; });
    try {
      await widget.api.request('POST', '/api/cases', {
        'kind': widget.kind, 'customer': name.text.trim(), 'region_id': region, 'difficulty': difficulty,
        'amount': int.parse(amount.text),
        if (widget.kind == 'collection') 'dpd': int.parse(dpd.text),
        if (widget.kind == 'origination') ...{'income': int.parse(income.text), 'interest': interest, 'documents_complete': documents},
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.kind == 'collection' ? 'Kasus penagihan baru' : 'Pengajuan pinjaman baru'),
    content: SizedBox(width: 480, child: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Gunakan identitas fiktif. Data tersimpan sebagai demo.'), const SizedBox(height: 20),
      TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Nama / alias demo'), validator: (v) => v!.trim().length < 2 ? 'Minimal 2 karakter.' : null), const SizedBox(height: 16),
      DropdownButtonFormField<String>(isExpanded: true, initialValue: region, decoration: const InputDecoration(labelText: 'Wilayah'), items: widget.regions.map((r) => DropdownMenuItem(value: r['id'] as String, child: Text(r['name'] as String))).toList(), onChanged: busy ? null : (v) => setState(() => region = v!)), const SizedBox(height: 16),
      DropdownButtonFormField<String>(isExpanded: true, initialValue: difficulty, decoration: const InputDecoration(labelText: 'Kesulitan kasus'), items: ['Low','Medium','High'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: busy ? null : (v) => setState(() => difficulty = v!)), const SizedBox(height: 16),
      TextFormField(controller: amount, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: widget.kind == 'collection' ? 'Nilai tagihan penuh (Rp)' : 'Nominal pengajuan (Rp)', helperText: 'Angka tanpa titik atau koma'), validator: positive), const SizedBox(height: 16),
      if (widget.kind == 'collection') TextFormField(controller: dpd, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Hari keterlambatan'), validator: (v) => (int.tryParse(v ?? '') ?? -1) < 0 ? 'Masukkan 0 atau bilangan positif.' : null),
      if (widget.kind == 'origination') ...[
        TextFormField(controller: income, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Penghasilan bulanan (Rp)'), validator: positive), const SizedBox(height: 16),
        DropdownButtonFormField<int>(isExpanded: true, initialValue: interest, decoration: const InputDecoration(labelText: 'Minat pemohon'), items: [1,2,3,4,5].map((v) => DropdownMenuItem(value: v, child: Text('$v / 5'))).toList(), onChanged: busy ? null : (v) => setState(() => interest = v!)),
        CheckboxListTile(value: documents, title: const Text('Dokumen sudah lengkap'), contentPadding: EdgeInsets.zero, onChanged: busy ? null : (v) => setState(() => documents = v!)),
      ],
      if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
    ])))),
    actions: [TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Batal')), FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Menyimpan…' : 'Simpan'))],
  );
}
