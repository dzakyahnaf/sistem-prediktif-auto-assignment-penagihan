import 'package:flutter/material.dart';
import 'api.dart';
import 'shell.dart';
import 'widgets.dart';

void main() => runApp(const AssignmentApp());

class AssignmentApp extends StatefulWidget {
  final Api? api;
  const AssignmentApp({super.key, this.api});
  @override
  State<AssignmentApp> createState() => _AssignmentAppState();
}

class _AssignmentAppState extends State<AssignmentApp> {
  late final Api api;
  @override
  void initState() {
    super.initState();
    api = widget.api ?? Api();
    api.addListener(sessionChanged);
  }
  void sessionChanged() { if (mounted) setState(() {}); }
  @override
  void dispose() {
    api.removeListener(sessionChanged);
    if (widget.api == null) api.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => MaterialApp(
    // Rebuild the Navigator too, so expired detail pages and dialogs are removed.
    key: ValueKey(api.sessionRevision),
    title: 'Assignment Studio', debugShowCheckedModeBanner: false, theme: studioTheme(),
    home: api.token == null
      ? LoginPage(api: api)
      : Workspace(api: api, onLogout: api.clearSession),
  );
}

class LoginPage extends StatefulWidget {
  final Api api;
  const LoginPage({super.key, required this.api});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final username = TextEditingController(text: 'supervisor');
  final password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false;
  String? error;
  @override
  void dispose() { username.dispose(); password.dispose(); super.dispose(); }
  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() { busy = true; error = null; });
    try {
      await widget.api.login(username.text.trim(), password.text);
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: SingleChildScrollView(
    padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: Surface(
      padding: const EdgeInsets.all(32), child: Form(key: form, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.hub_outlined, color: teal, size: 40), const SizedBox(height: 24),
        const Pill('PROTOTYPE · DATA SINTETIS'), const SizedBox(height: 20),
        const Text('Assignment\nStudio', style: TextStyle(fontSize: 38, color: ink, fontWeight: FontWeight.w700, height: 1.1)),
        const SizedBox(height: 16), const Text('Satu ruang kerja untuk penagihan, pengajuan, dan tindak lanjut tim.', style: TextStyle(color: muted, height: 1.6)),
        const SizedBox(height: 28),
        if (widget.api.sessionMessage != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(widget.api.sessionMessage!, style: const TextStyle(color: muted))),
        TextFormField(controller: username, decoration: const InputDecoration(labelText: 'Username'), validator: (v) => v!.trim().isEmpty ? 'Isi username.' : null),
        const SizedBox(height: 16),
        TextFormField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password'), validator: (v) => v!.isEmpty ? 'Isi password.' : null, onFieldSubmitted: (_) { if (!busy) submit(); }),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(error!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 24), SizedBox(width: double.infinity, child: FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Memeriksa…' : 'Masuk ke ruang kerja'))),
        const SizedBox(height: 20), const Text('Akun demo: supervisor\nPassword: DemoAssignment!2026', style: TextStyle(color: muted, fontSize: 12, height: 1.7)),
      ])),
    )),
  )));
}
