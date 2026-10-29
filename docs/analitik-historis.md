# Data historis dan pipeline analitik — Sprint 8

Supervisor membuka **Ringkasan → Analitik historis**. Modul ini membuat histori longitudinal sintetis dan dataset berversi untuk eksperimen predictive berikutnya. Tidak melatih model, mengganti skor rules-demo-v1, menambahkan kasus ke antrean, atau mengirim transaksi nyata. Tidak memerlukan API key/layanan eksternal.

## Membuat dan meninjau dataset

1. Tentukan jumlah kasus **per alur** (100–5.000), seed, rentang histori, batas train/validation, tanggal observasi dan jendela konversi pengajuan. Default: 3.000 penagihan + 3.000 pengajuan, seed 281026, 1 Oktober2024 sampai1 Oktober2026 UTC, batas train1 Februari2026 dan validation1 Juni2026.
2. Tanggal berurutan, batas eksklusif pada00:00UTC. Rentang180–1.826 hari; tiap partisi lebih panjang dari jendela pengajuan+7 hari. Tanggal observasi tidak boleh di masa depan. Tinjau konfigurasi, lalu **Buat dataset** atau **Batal**.
3. Riwayat menyimpan konfigurasi, versi simulator/fitur, hash, jumlah raw record, distribusi kelas dan alasan eksklusi. Jumlah minimum kelas untuk **demo** adalah20 positif dan20 negatif pada setiap partisi dalam setiap kombinasi domain/tahap. Status ini tidak menyatakan kelayakan ML pada data nyata.
4. Pilih alur, tahap keputusan dan partisi. Preview25 sampel/halaman mencakup waktu keputusan, ketersediaan fitur, kematangan label, identitas, aksi tim/propensity dan fitur prediktor yang diizinkan. Label kosong berarti belum dapat dievaluasi; bukan label0.
5. **Unduh dataset ZIP** memuat seluruh dataset, termasuk sampel excluded, tanpa mengikuti filter/pagination preview. Unduhan memeriksa ulang hash dan dicatat dalam audit.

Jika respons pembuatan hilang/5xx, UI mempertahankan payload dan request_key, mengunci edit dan menyediakan **Cek / ulangi pembuatan**. Retry yang sama mengembalikan run yang sudah ada; key berbeda boleh membuat eksperimen baru. Bila halaman ditutup saat hasil belum pasti, periksa riwayat/seed/konfigurasi sebelum membuat ulang. Tidak ada penghapusan otomatis dataset dalam sprint ini.

## Kontrak dataset

Versi saat ini: `history-simulator-v1`, `point-in-time-v1`. Seed dan konfigurasi yang sama menghasilkan raw history, sampel dan SHA-256 yang sama. ID run dan waktu pembuatan berbeda untuk eksperimen baru. Jangan mengubah semantik simulator/fitur versi ini diam-diam; naikkan versi dan pertahankan kamus lama saat menambah kontrak baru.

Paket ZIP memakai UTF-8 dan berisi:

- `cases.jsonl`: identitas sintetis, domain/wilayah, waktu masuk dan profil pada saat masuk. Dua kasus per identitas dipakai untuk menguji isolasi entitas. Tidak ada nama, NIK, nomor telepon atau data pribadi nyata.
- `decisions.jsonl`: satu record per keputusan/siklus, waktu assignment/penutupan, petugas sintetis, tim, propensity dan versi kebijakan. ID petugas berawalan H tidak merujuk akun/master operasional.
- `events.jsonl`: follow-up, janji, pembayaran, dokumen/verifikasi, pencairan/penolakan simulasi. Event setelah tanggal observasi tidak diekspor. `closed_at=null` berarti penutupan belum teramati saat observasi.
- `samples.jsonl`: metadata keputusan/identitas/waktu, `features`, label0/1/null, split dan alasan eksklusi. **Trainer hanya boleh membaca fitur dari objek `features`, dan hanya sampel split train/validation/test.** Raw outcome, label, ID, tim/propensity atau nominal realisasi sesudah keputusan bukan prediktor.
- `manifest.json`: ID/config run dan manifest versi, hash, hitungan, distribusi kelas, pemeriksaan kualitas serta batas interpretasi.
- `dictionary.json`: allowlist fitur per domain/tahap, kebijakan waktu/identitas dan arti alasan eksklusi.

Hash dihitung dari canonical JSON empat array `cases/decisions/events/samples`, dengan urutan ID deterministik, key terurut dan representasi ASCII JSON. Manifest/ID run/waktu pembuatan tidak masuk hash sehingga reproduksibilitas tidak tergantung waktu request. Jangan menghitung hash langsung dari byte ZIP sebagai pengganti hash data tersebut.

## Snapshot fitur dan label

Snapshot awal hanya memakai profil yang sudah diketahui saat kasus masuk, tanpa hasil call/visit/pembayaran siklus berjalan. Snapshot ulang memakai profil awal, umur kasus/DPD saat keputusan, serta aktivitas **siklus sebelumnya yang sudah ditutup sebelum keputusan**. Pembayaran sebelumnya mengurangi saldo yang masih harus dibayar pada siklus baru. `feature_max_at` mencatat waktu ketersediaan terakhir dari input itu; seluruhnya paling lambat pada waktu keputusan.

Allowlist fitur:

- Bersama: wilayah domisili `region_id`, kesulitan, nominal awal integer rupiah, umur kasus dalam hari, bulan dan hari keputusan UTC. Tidak menggunakan tempat lahir atau karakter sensitif.
- Penagihan: DPD saat keputusan. Tahap ulang menambah jumlah siklus tertutup, kontak/tidak terhubung/janji sebelumnya, pembayaran sebelumnya dan saldo tersisa saat keputusan.
- Pengajuan: penghasilan, minat1–5 dan kelengkapan dokumen **saat masuk**. Tahap ulang menambah agregat histori tertutup di atas, serta jumlah event dokumen/verifikasi sebelumnya. Kelengkapan dokumen yang baru muncul di siklus berjalan tidak masuk snapshot.

Definisi label dibekukan pada konfigurasi run:

- **Penagihan**: label1 bila seluruh tagihan kasus (termasuk pembayaran siklus terdahulu) lunas paling lambat72 jam sejak keputusan tersebut. Pembayaran sebagian dan pelunasan setelah72 jam adalah label0 jika observasi cukup. Batas tepat72 jam termasuk sukses.
- **Pengajuan**: label1 bila pencairan simulasi terjadi paling lambat jendela konversi sejak keputusan; default30 hari, dapat dipilih7–90 hari. Ditolak/tidak cair dalam jendela adalah label0 bila observasi cukup. Ini **asumsi label eksperimen**, terpisah dari SLA tindak lanjut operasional72 jam dan belum keputusan bisnis final.
- `label_ready_at` selalu akhir jendela penuh, termasuk ketika hasil positif/penolakan terjadi lebih awal. Ini menghindari memasukkan positif muda tetapi membuang negatif muda pada cutoff observasi.
- Siklus nonterminal yang ditutup/dialihkan lebih awal dari jendela tidak dianggap gagal. Kode raw `outcome` mencatat akhir trajektori, bukan label ML: lunas/pencairan terlambat tetap dapat memiliki label0.

## Pemisahan dan pemeriksaan kualitas

Pembagian berdasarkan **waktu keputusan**, bukan random split. Label train harus matang paling lambat batas train; label validation paling lambat batas validation; label test paling lambat tanggal observasi. Tidak ada pemindahan baris masa depan ke train untuk menyeimbangkan kelas.

Urutan eksklusi:

1. `censored`: jendela label belum selesai pada observasi, labelnull.
2. `early_reassignment`: siklus dialihkan sebelum jendela lengkap, labelnull.
3. `label_cross_boundary`: label melewati batas partisi; tidak boleh dipakai pada partisi sebelumnya.
4. `entity_cross_split`: setelah eksklusi di atas, identitas yang masih muncul pada beberapa partisi dipurge dari seluruh partisi tersebut. Sampel yang sudah excluded mempertahankan alasan awalnya. Identitas eligible train/validation/test akhirnya saling terpisah.

Quality gate memeriksa duplikasi ID/siklus, relasi kasus/keputusan/event, waktu masuk/assignment/penutupan/event, kontinuitas siklus, nominal, aturan Low→A/High→B, propensity, kontrak fitur, snapshot/label hasil derivasi, kematangan label serta isolasi waktu dan identitas. Kegagalan menghentikan penyimpanan. Korupsi hash saat ekspor memblokir berkas dan tidak menambah audit ekspor berhasil.

Kebijakan historis adalah **synthetic-exploration-v1**: Low selaluA, High selaluB, Medium mengacak A/B dengan peluang masing-masing0,5. Propensity yang disimpan adalah peluang **tim** terpilih, bukan probabilitas outcome/model atau estimasi kecocokan petugas. Low/High tidak memiliki overlap antaraksi. Simulator menyederhanakan operasi dan tidak memutar ulang kapasitas harian/master aktif; tidak boleh digunakan untuk mengklaim uplift kausal atau petugas terbaik. Kebijakan assignment aplikasi operasional tetap memakai rules-demo-v1/ambang Medium60.

## Penyimpanan dan API

Alembic **0002_analytics** menambah lima tabel: `analytics_runs`, `analytics_cases`, `analytics_decisions`, `analytics_events`, `analytics_samples`. Seluruh record terikat run dengan FK; relasi internal raw record diperiksa oleh quality gate. Payload JSON disimpan utuh untuk mempertahankan snapshot, sedangkan kolom kind/stage/split dan indeks memungkinkan pagination dari server. Tidak ada update/delete run pada API.

Pembuatan raw history/quality gate dilakukan sebelum mengambil write lock. Penyimpanan seluruh run, raw data, sampel dan audit berlangsung atomik; retry concurrent diperiksa ulang di bawah lock. Kegagalan tengah transaksi me-rollback seluruh run. SQLite tetap mendukung kontrak yang sama untuk tes/fallback.

Seluruh endpoint berikut khusus supervisor, no-store:

- `GET /api/analytics/runs?offset=0&limit=20`: daftar run berpaginasi, total.
- `POST /api/analytics/runs`: konfigurasi di atas dan `request_key` unik12–80 karakter alfanumerik/underscore/hyphen. Semua parameter mempunyai default kecuali key; lihat OpenAPI. Key sama/config atau akun berbeda menghasilkan409.
- `GET /api/analytics/runs/{id}`: konfigurasi, manifest dan kamus.
- `GET /api/analytics/runs/{id}/samples?kind=collection&stage=initial&split=train&offset=0&limit=25`: preview; stage initial/reassignment, split all/train/validation/test/excluded, limit maksimal200.
- `GET /api/analytics/runs/{id}/export`: ZIP seluruh data; verifikasi hash lalu audit.

Pengujian: `scripts/test-backend.ps1`, `scripts/test-postgres.py`, `scripts/test-migration.ps1`, dan `scripts/test-web.ps1 -FlutterSdk 'C:\flutter' -Offline`. Bukti UI serta persistensi aktual ada di [PROGRESS.md](PROGRESS.md). Script backup PostgreSQL sekarang mencakup18 tabel termasuk analitik, sesi, receipt dan revision.

## Hasil dan batas Sprint 8

Run demo `HIST-DA17B9491C00` dibuat melalui UI pada PostgreSQL utama: **6.000 kasus historis, 7.670 keputusan/sampel, 22.082 event**, dengan5.403 sampel eligible dan2.267excluded. Keempat kombinasi domain/tahap memiliki kelas0/1 pada ketiga partisi dan memenuhi pemeriksaan jumlah kelas demo. Seluruh148 kasus operasional tetap sama; data historis tidak dimasukkan ke dashboard operasional. Audit bertambah dua event generate/export.

Belum mencakup ingest histori nyata/Excel historis, rekonstruksi fitur sebelum keputusan dari snapshot operasional lama yang tidak direkam, model terlatih, preprocessing/imputation/scaling yang di-fit pada train, kalibrasi, segmentasi atau registry model. Pekerjaan model masuk Sprint 9; preprocessing yang belajar dari data harus di-fit hanya pada train dan dipakai ulang pada validation/test. Hasil pada simulator tidak membuktikan akurasi pada data nasabah nyata.
