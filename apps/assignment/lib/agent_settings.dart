import 'package:flutter/material.dart';
import 'api.dart';

class AgentSettingsDialog extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> agent;
  const AgentSettingsDialog({super.key, required this.api, required this.agent});

  @override
  State<AgentSettingsDialog> createState() => _AgentSettingsDialogState();
}

class _AgentSettingsDialogState extends State<AgentSettingsDialog> {
  final form = GlobalKey<FormState>();
  late final TextEditingController capacity;
  late bool active;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    capacity = TextEditingController(text: '${widget.agent['capacity']}');
    active = widget.agent['active'] == 1;
  }

  @override
  void dispose() {
    capacity.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() { busy = true; error = null; });
    try {
      await widget.api.request('PATCH', '/api/agents/${widget.agent['id']}', {
        'capacity': int.parse(capacity.text.trim()), 'active': active,
        if (widget.agent['version'] != null) 'expected_version': widget.agent['version'],
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Pengaturan petugas'),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Form(
        key: form,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.agent['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('${widget.agent['active_load']} kasus aktif · ${widget.agent['daily_load']} assignment hari ini'),
          const SizedBox(height: 20),
          TextFormField(
            controller: capacity, enabled: !busy, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Kapasitas petugas', helperText: '1–100 kasus; berlaku untuk beban aktif dan penugasan harian.', helperMaxLines: 3),
            validator: (value) {
              final number = int.tryParse(value?.trim() ?? '');
              return number == null || number < 1 || number > 100 ? 'Masukkan bilangan bulat 1–100.' : null;
            },
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Aktif menerima assignment'), value: active,
            onChanged: busy ? null : (value) => setState(() => active = value),
          ),
          const SizedBox(height: 8),
          const Text('Petugas nonaktif tidak menerima assignment baru. Kasus yang sudah ditugaskan tetap tercatat pada petugas tersebut.'),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(error!, style: const TextStyle(color: Colors.red))),
        ]),
      ))),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context, false), child: const Text('Tutup')),
        FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Menyimpan…' : 'Simpan pengaturan')),
      ],
    ),
  );
}
