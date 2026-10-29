import 'package:flutter/material.dart';
import 'api.dart';
import 'widgets.dart';

class PredictionPanel extends StatelessWidget {
  final Map data;
  final bool preview;
  const PredictionPanel({super.key, required this.data, this.preview = false});
  @override
  Widget build(BuildContext context) {
    final ml = data['source'] == 'ml_simulation';
    return Surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(preview ? 'Preview keputusan berikutnya' : 'Snapshot saat penugasan', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text(ml ? 'Prediksi simulasi ML: ${((data['probability'] as num)*100).toStringAsFixed(1)}%' : 'Indeks rules: ${data['score']} / 100',
        style: const TextStyle(fontSize: 22, color: teal, fontWeight: FontWeight.w600)),
      if (ml) Text('Target ${data['model_key'].toString().startsWith('collection') ? 'lunas' : 'pencairan'} dalam ${data['horizon']} ${data['horizon_unit'] == 'hours' ? 'jam' : 'hari'}. Data training sintetis; belum divalidasi pada nasabah nyata.'),
      Text('${data['reason']}'), const SizedBox(height: 8),
      SelectableText('Versi: ${data['version']} · serving ${data['serving_revision']}'),
      Text('Keputusan: ${dateLabel(data['decision_at'] as String?)}'),
      if (preview) Text('Skor diperiksa lagi saat assignment. Low tetap Tim A, High Tim B; Medium memakai ambang ${data['policy']?['config']?['medium_threshold'] ?? 60}.'),
      if (data['policy'] is Map) Text('Kebijakan revisi ${data['policy']['revision']} · SLA tindak lanjut ${data['policy']['followup_hours']} jam. Success penagihan tetap 72 jam.'),
      if (data['segment'] is Map && data['segment']['status'] != 'inactive') ...[
        const SizedBox(height: 10), Text(data['segment']['status'] == 'ready' ? 'Segmen deskriptif: ${data['segment']['segment']}' : 'Segmen belum tersedia', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('${data['segment']['reason']}'),
        if (data['segment']['release_id'] != null) Text('Paket ${data['segment']['release_id']}'),
        if (data['segment']['profile'] is Map) ExpansionTile(title: const Text('Profil segmen pada train'), tilePadding: EdgeInsets.zero, children: [
          Align(alignment: Alignment.centerLeft, child: Text('n=${data['segment']['profile']['n']}\nRata-rata fitur: ${data['segment']['profile']['means']}')),
        ]),
      ],
      if (data['explanation'] is List) ExpansionTile(title: const Text('Faktor kontribusi model'), tilePadding: EdgeInsets.zero, children: [
        const Text('Kontribusi pada log-odds sebelum kalibrasi; bukan sebab-akibat. Tanda positif menaikkan keluaran relatif terhadap intercept.'),
        for (final x in data['explanation'] as List) ListTile(dense: true, title: Text('${x['feature']}'), trailing: Text('${x['contribution']}')),
      ]),
      if (data['features'] is Map && (data['features'] as Map).isNotEmpty) ExpansionTile(tilePadding: EdgeInsets.zero,
        title: const Text('Fitur sebelum keputusan'), children: [
          Align(alignment: Alignment.centerLeft, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Fitur tersedia: ${dateLabel(data['feature_max_at'] as String?)}'),
            for (final e in (data['features'] as Map).entries) Text('${e.key}: ${e.value}'),
          ])),
        ]),
    ]));
  }
}
