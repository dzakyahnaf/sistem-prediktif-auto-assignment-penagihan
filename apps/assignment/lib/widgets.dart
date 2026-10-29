import 'package:flutter/material.dart';

const ink = Color(0xFF102A36);
const teal = Color(0xFF087E8B);
const muted = Color(0xFF647785);

ThemeData studioTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: teal, brightness: Brightness.light),
  scaffoldBackgroundColor: const Color(0xFFF4F7F9),
  appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF4F7F9), foregroundColor: ink, elevation: 0),
  inputDecorationTheme: InputDecorationTheme(
    filled: true, fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFDCE5EA))),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  ),
  filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
    backgroundColor: teal, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
);

class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Surface({super.key, required this.child, this.padding = const EdgeInsets.all(24)});
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE1E9EE))),
    child: child,
  );
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, {super.key, this.color = teal});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: color.withAlpha(22), borderRadius: BorderRadius.circular(8)),
    child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
  );
}

class EmptyState extends StatelessWidget {
  final String title, subtitle;
  const EmptyState(this.title, this.subtitle, {super.key});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(40), child: Column(children: [
    const Icon(Icons.inbox_outlined, size: 42, color: muted), const SizedBox(height: 16),
    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
    const SizedBox(height: 8), Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: muted)),
  ]));
}

Future<void> showMessage(BuildContext context, String message) async {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
