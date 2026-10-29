# Model predictive dan lifecycle — Sprint 9

Empat regresi logistik melayani penagihan/pengajuan, masing-masing keputusan awal dan penugasan ulang. Semua data pelatihan berasal dari simulator Sprint 8. Ini validasi teknis prototype; tidak membuktikan ketepatan pada nasabah nyata atau efektivitas kausal pemilihan petugas.

## Training dan evaluasi

Supervisor membuka Ringkasan → Model & evaluasi, memilih run historis, meninjau lalu mengonfirmasi training. Training menghasilkan kandidat immutable, bukan aktivasi otomatis. Preprocessing median/standardisasi/one-hot hanya di-fit pada train. Validation dibagi berurutan untuk kalibrasi dan pemilihan, dengan purge identitas yang melintasi kedua bagian. Sigmoid regularized dipilih hanya jika log loss selection membaik; test tidak dipakai memilih parameter. Empat subset dilaporkan terpisah.

Laporan memuat AUC, average precision, Brier, log loss, ECE, reliability dan confusion pada 0,5. Baseline konstan memakai prior train; rules hanya dibandingkan sebagai ranking karena indeks rules bukan probabilitas. AUC/AP makin besar makin baik, Brier/log loss/ECE makin kecil makin baik; Brier bukan ukuran kalibrasi murni. Sampel kecil membatasi kesimpulan.

Kandidat demo `MOD-2F47EACC9298`, sumber `HIST-DA17B9491C00`, test AUC sekitar 0,54–0,64. Dua model pengajuan belum mengungguli baseline konstan pada validation selection; model penagihan ulang juga tidak mengungguli seluruh baseline pada test. Default database utama tetap rules. `activation_eligible` berarti lolos pemeriksaan teknis demo, bukan lolos standar performa produksi.

## Serving dan histori

Aktivasi/rollback memerlukan alasan, expected revision dan request key; aktivasi meminta pengakuan data sintetis. Satu transaksi mengganti paket empat model, menyimpan histori dan audit. Retry identik tidak menggandakan perubahan. Konflik 409 meminta review ulang. Rollback menuju rules tidak mengubah keputusan lama.

Artefak JSON `logit-json-v1` memuat preprocessing, koefisien, kalibrasi, domain train dan provenance. Checksum diverifikasi; tidak memuat pickle/kode yang dieksekusi. Unduhan ZIP memuat model.json dan report.json, khusus supervisor dan dicatat dalam audit. Inferensi JSON diverifikasi terhadap scikit-learn saat training.

Snapshot asal kasus hanya diambil ketika kasus benar-benar dibuat, termasuk impor commit. Kasus legacy tidak diisi ulang dari keadaan sekarang. Fitur keputusan memakai asal tersebut dan histori siklus yang sudah ditutup; aktivitas siklus berjalan tidak mengubah prediksi tersimpan. Snapshot fitur, waktu, model, horizon, probabilitas dan revision disimpan atomik dengan assignment. Preview pengalihan memperlakukan siklus berjalan akan ditutup tanpa menulis data; commit menghitung ulang dalam transaksi. Waktu tersimpan sampai detik, sehingga urutan tindakan pada detik yang sama mengikuti urutan transaksi.

Fallback rules eksplisit berlaku tanpa model aktif, asal legacy tidak tersedia, checksum/fitur rusak atau nilai/kategori di luar domain train. Misalnya wilayah baru atau usia antrean yang tidak tercakup train. Laporan evaluasi seluruh holdout tetap dipisahkan dari cakupan domain serving. Antrean menyimpan skor keputusan terakhir; tidak melakukan rescore massal. Hard Low=A/High=B, wilayah, aktif dan kapasitas tetap berlaku; Medium memakai ambang demo 60 terhadap skor keputusan. Ambang itu belum dioptimalkan sebagai kebijakan bisnis.

## Kontrak API

- `GET /api/models?offset=0&limit=10`: registry (maksimal 100/halaman).
- `POST /api/models/train`: run_id dan request_key; source hash/quality gate diperiksa, training di luar write lock, penyimpanan/audit atomik.
- `GET /api/models/serving`: mode/revision/histori terbaru.
- `POST /api/models/serving`: release_id atau null, expected_revision, reason, request_key, demo_ack untuk aktivasi.
- `GET /api/models/{id}` dan `GET /api/models/{id}/export`: laporan/ZIP.

Semua endpoint khusus supervisor, no-store. Snapshot keputusan pada detail kasus tetap mengikuti scope petugas. UI mempertahankan payload/key ketika hasil mutasi ambigu; GET gagal memberi pesan tanpa menghapus sesi.

## Storage dan operasi

Alembic `0003_models` menambah ml_releases, ml_serving, ml_transitions, case_origins, ml_predictions. Tidak menulis ulang histori operasional lama. Dependensi training lokal scikit-learn 1.9.1, NumPy 2.5.4, SciPy 1.18.1 dipin di requirements. Tidak memerlukan API key. Training sinkron masih sesuai ukuran demo; job queue, tuning/cross-validation, data nyata, monitoring drift dan validasi bisnis belum tersedia.

Referensi primer: [LogisticRegression](https://scikit-learn.org/stable/modules/generated/sklearn.linear_model.LogisticRegression.html), [kalibrasi probabilitas dan pemisahan data](https://scikit-learn.org/stable/modules/calibration.html).
