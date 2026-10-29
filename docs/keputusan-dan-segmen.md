# Kebijakan dan segmentasi — Sprint 10

Ringkasan → Keputusan & segmen, khusus supervisor. Editor mengatur ambang Medium, dua SLA tindak lanjut, basis/pengurang DPD dan tiga bobot rules pengajuan. Review/Batal, alasan, expected revision dan request key melindungi penerbitan. Retry ambigu mempertahankan payload. Riwayat menyimpan seluruh konfigurasi; rollback dilakukan dengan menerbitkan nilai sebelumnya sebagai revisi baru.

Low selalu A, High selalu B; scope, wilayah, status aktif dan kapasitas tidak dapat dilewati. **Success penagihan tetap seluruh tagihan lunas dalam72jam sejak assignment**, terpisah dari due_at tindak lanjut yang kini dapat1–168jam. Pembayaran pada48jam dengan follow-up24jam tetap success, sedangkan pembayaran73jam dengan follow-up168jam tetap no_success. Aktivitas dan pengalihan memakai deadline keberhasilan tersebut. Model penagihan tetap memprediksi horizon72jam, pengajuan mengikuti horizon dataset; mengubah SLA operasional tidak melatih ulang model.

Kebijakan hanya memengaruhi kasus/keputusan baru; assignment/prediksi lama tidak ditulis ulang. Antrean menampilkan skor tersimpan, batch assignment menghitung prioritas keputusan terbaru. Override menyertakan revision kebijakan dan serving, lalu memeriksa ulang saat commit. Impor preview memakai rules kebijakan saat itu; perubahan kebijakan memblokir commit sampai preview ulang. Riwayat impor committed tetap dapat di-retry tanpa duplikasi.

## Segmentasi

Latih segmen dari ID model sumber yang valid. Empat cohort per domain/tahap memakai preprocessing train-only yang sudah dibekukan dari sumber tersebut. KMeans memilih k2–4 melalui silhouette train, minimum5anggota tiap cluster. Tiga resampling80% train melaporkan adjusted Rand index; validation/test hanya evaluasi, tidak memilih k. Label outcome tidak digunakan untuk clustering atau profil. Kalender dan wilayah dikeluarkan dari vektor jarak agar ciri operasional menentukan cluster. Artefak JSON memuat pusat cluster, indeks fitur dan profil train; checksum diverifikasi sebelum dipilih/serving.

Paket calon tidak langsung aktif. Pilih paket dalam editor kebijakan lalu terbitkan; kosongkan pilihan untuk menonaktifkan pada keputusan baru. Segmen S1/S2/dst adalah ID kelompok kemiripan, **bukan urutan risiko atau petugas terbaik**. Profil memuat rata-rata fitur/kategori train. Silhouette kecil, collapse satu cluster dan stabilitas resampling rendah diberi pesan review. Data sintetis belum membuktikan stabilitas bisnis di data nyata.

Detail assignment menyimpan segmen, profil dan revision secara atomik dengan prediksi. Data asal tidak tersedia/di luar domain/checksum gagal menghasilkan status segmen tidak tersedia, tanpa memaksakan kelompok atau menghalangi rules. Prediksi ML menampilkan empat kontribusi fitur terbesar pada log-odds sebelum kalibrasi; tanda kontribusi relatif terhadap intercept, bukan hubungan sebab-akibat.

## API/storage

- GET /api/decisions: kebijakan sekarang,20riwayat,20paket terakhir plus paket aktif bila lebih lama,100ID model terbaru.
- POST /api/decisions/policy: config,expected_revision,reason,request_key.
- POST /api/decisions/segments: model_id,request_key.
- GET /api/decisions/segments/{id}: laporan paket immutable.

Semua khusus supervisor/no-store. Alembic0004_decisions menambah policy_revisions dan segment_releases; default revisi0 tetap sama dengan aturan semula, tanpa seed/aktivasi kebijakan baru. Tidak memerlukan layanan/API key baru.

Referensi primer: [KMeans](https://scikit-learn.org/stable/modules/generated/sklearn.cluster.KMeans.html), [silhouette](https://scikit-learn.org/stable/auto_examples/cluster/plot_kmeans_silhouette_analysis.html), [evaluasi inisialisasi](https://scikit-learn.org/stable/auto_examples/cluster/plot_kmeans_stability_low_dim_dense.html).
