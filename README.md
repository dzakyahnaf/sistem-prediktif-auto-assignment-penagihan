# Assignment Studio

Prototype predictive scoring dan auto-assignment untuk penagihan dan pengajuan pinjaman. Flutter/Dart memakai API FastAPI/Pydantic, SQLAlchemy Core/Alembic dan PostgreSQL persisten. Seluruh identitas, histori dan transaksi demo bersifat sintetis.

Pengerjaan mencapai **Sprint 13: penerimaan dan serah terima**. Web dan Android emulator menjalankan workflow nyata. Runner iOS tersedia, tetapi build/UAT iOS masih membutuhkan macOS/Xcode. Status dan bukti per sprint ada di [PROGRESS](docs/PROGRESS.md); panduan akhir di [penerimaan dan serah terima](docs/penerimaan-dan-serah-terima.md).

## Fitur yang tersedia

- Dua workflow: penagihan sampai pembayaran sebagian/penuh; pengajuan sampai dokumen, verifikasi, pencairan simulasi atau penolakan.
- Login supervisor/petugas, scope per petugas, logout/kedaluwarsa, pencabutan sesi, nonaktifkan akun dan reset password oleh supervisor. Master petugas nonaktif membatasi tugas baru; kontrol akun nonaktif juga membatasi login.
- Assignment berdasarkan wilayah, domain, tim, status dan kapasitas harian/beban aktif. Low selalu Tim A, High selalu Tim B; Medium mengikuti ambang kebijakan. Reassign dan override beralasan mempertahankan saldo, progres, histori serta snapshot siklus.
- Antrean dengan pagination server, pencarian/filter dan pemilihan maksimal 100 kasus lintas halaman. Dashboard, master wilayah/petugas, audit, laporan portofolio/siklus dan CSV tersedia melalui UI.
- Impor XLSX maksimal 5 MiB/2.000 baris: worksheet/header, pemetaan, preview seluruh validasi, deduplikasi referensi dan commit atomik/idempoten. Picker dan save native memakai dialog sistem.
- Simulator histori longitudinal, snapshot sebelum keputusan, label/censoring, split waktu/identitas dan ZIP dataset. Empat model regresi logistik awal/reassign per domain dengan preprocessing train-only, kalibrasi, evaluasi, registry JSON/checksum, aktivasi/rollback dan fallback.
- Empat cohort KMeans dengan profil/evaluasi/stabilitas. Kebijakan rules, ambang Medium dan SLA tindak lanjut berversi. Snapshot assignment lama tetap; penjelasan kontribusi model bukan klaim kausal.
- Inbox assignment/pengingat SLA, antrean telephony/omnichannel tiruan, backoff, dead-letter, recovery, receipt dan audit. Worker dan scan dipicu manual dari UI; tidak ada pesan/panggilan keluar.
- Layout desktop/ponsel, session/error recovery, pembatasan percobaan login persisten, header no-store/nosniff/no-referrer/SAMEORIGIN, backup/restore terverifikasi serta paket demo lokal.

Demo utama: **148 kasus, 12 petugas, 13 akun, 3 wilayah, 5 assignment dan 9 aktivitas** pada PostgreSQL `assignment_demo`, loopback 15432. Seed awal 72 kasus per domain. Dataset historis 6.000 kasus dan kandidat model/segmen tersimpan terpisah. Main tetap rules revisi0, tanpa model/segmen aktif; kandidat tidak otomatis dipublikasikan. SQLite asli `runtime/assignment.db` dan seluruh UAT/backup lama dipertahankan.

**Rules adalah indeks simulasi, bukan probabilitas.** Probabilitas model berasal dari pelatihan pada simulator, belum validasi nasabah nyata. A=Tele/B=Lapangan dan jendela konversi pengajuan masih asumsi demo. Lunas penagihan maksimal 72 jam sejak assignment siklus adalah success; lunas terlambat tetap menutup kasus dengan outcome no_success. SLA tindak lanjut terpisah dari definisi success.

## Menjalankan workspace yang sudah tersedia

Windows PowerShell, root proyek. Gunakan interpreter `.venv` yang tersedia; jangan mengandalkan python/py global. Flutter terverifikasi `C:\flutter`, versi 3.41.6/Dart 3.11.4. Periksa proses/server sebelum memulai instance baru.

```powershell
.venv\Scripts\python.exe scripts/postgres-local.py status
# Jika klaster proyek berhenti:
.venv\Scripts\python.exe scripts/postgres-local.py start
.\scripts\start-backend.ps1
```

Di terminal kedua, jika web belum berjalan:

```powershell
.venv\Scripts\python.exe scripts/serve-web.py
```

- Web: http://127.0.0.1:5173
- API health: http://127.0.0.1:8000/api/health
- API docs: http://127.0.0.1:8000/docs

`serve-web.py` menyajikan release build dengan no-store. Development compiler alternatif: `start-web.ps1 -FlutterSdk 'C:\flutter'`. Cache paket proyek `.cache/pub`. Login ulang setelah reload diperlukan karena token hanya di memori aplikasi.

Startup backend default membaca config privat `runtime/postgres-local.json`. Jangan init ulang klaster yang sudah terisi. Service PostgreSQL pengguna 5433 tidak diubah. `DATABASE_URL` atau `DATABASE_PATH` eksplisit memilih target lain; gunakan hanya target yang dimaksud. Head Alembic **0006_hardening** setelah portable, analytics, models, decisions dan operations. SQLite tetap didukung untuk tes/paket; tidak otomatis memuat perubahan PostgreSQL setelah cutover.

## Akun demo

Supervisor `supervisor`. Petugas `smg-col-a`, `smg-col-b`, `smg-ori-a`, `smg-ori-b`; pola sama untuk `sby` dan `bdg`. Semua password awal **DemoAssignment!2026**. Reset UAT Sprint12 dipulihkan ke password demo; akun utama tidak diubah oleh latihan tersebut.

Lima login gagal per kombinasi asal/username atau 30 per asal dalam 15 menit menghasilkan 429 sampai jendela berakhir. Restart tidak menghapus batas ini. Startup lokal tidak mempercayai forwarded proxy headers.

## Paket demo dan Android

```powershell
.\scripts\build-demo.ps1 -FlutterSdk 'C:\flutter' -Offline
.\scripts\build-android.ps1 -FlutterSdk 'C:\flutter' -Offline
```

ZIP demo berada di `runtime/artifacts`, berisi compiled web, backend, panduan dan manifest SHA256. Ekstrak ke folder baru dan ikuti README/START-DEMO.ps1 di dalamnya. FastAPI melayani UI/API satu origin loopback 8080 dengan SQLite baru milik paket. Tidak membawa data/kredensial/config workspace. Python 3.12/dependensi tetap diperlukan; Flutter SDK tidak diperlukan untuk menjalankan ZIP. Ini paket demo lokal, belum deployment publik.

APK demo debug di `runtime/artifacts`, memakai `lib/main.dart` dan API host emulator 10.0.2.2:8000. Native integration test memakai backend UAT terpisah dan target test tersendiri. HTTP demo hanya untuk loopback/emulator; production menolak cleartext. iOS memerlukan Mac/Xcode; jangan generate ulang runner yang sudah ada. Lihat [mobile native](docs/mobile-native.md).

## Verifikasi

```powershell
.\scripts\test-backend.ps1
.venv\Scripts\python.exe scripts/test-postgres.py
.\scripts\test-migration.ps1
.\scripts\test-web.ps1 -FlutterSdk 'C:\flutter' -Offline
```

Regresi Sprint13: **106 tes SQLite lulus, 93 tes Flutter lulus, analyze bersih dan build web berhasil, 9 tes migrasi lulus**. Regresi PostgreSQL: 105 lulus/1 khusus SQLite dilewati dari 106 tes; UAT Android lintas role/inbox/kedua workflow lulus. UAT paket dan bukti akhir ada di PROGRESS. Satu tes khusus SQLite dilewati pada PostgreSQL. Tes memakai file/schema UUID terisolasi. Native workflow, picker/save/IME dan Chrome desktop/390px memiliki bukti terpisah; build tidak dianggap pengganti UAT.

Backup dengan nama baru:

```powershell
.venv\Scripts\python.exe scripts/backup-postgres.py --output runtime/backups/demo-baru.dump --report runtime/backup-baru.json --verify-restore
```

Tool mengekspor snapshot dan memverifikasi restore pada database baru; tidak menimpa demo. Dump mengandung hash akun/sesi, simpan lokal dengan aman. Jangan menghapus database atau hasil demo/UAT lama. Untuk UAT baru gunakan schema salinan sesuai panduan atau ZIP baru yang terisolasi.

## Panduan modul dan batas

[Arsitektur](docs/arsitektur.md), [PostgreSQL](docs/postgresql.md), [master/override](docs/master-dan-override.md), [impor](docs/impor-operasional.md), [laporan](docs/laporan-operasional.md), [histori analitik](docs/analitik-historis.md), [model](docs/model-predictive.md), [keputusan/segmen](docs/keputusan-dan-segmen.md), [operasi/notifikasi](docs/operasi-dan-notifikasi.md), [penerimaan](docs/penerimaan-dan-serah-terima.md).

Belum diterima: build/UAT iOS, Android fisik, signing/store, validasi bisnis/model pada data nyata, ingest histori nyata, integrasi vendor live, deployment publik/TLS/HA/monitoring/load test produksi. Impor operasional tidak mengimpor aktivitas/master atau memperbarui kasus lama. Tidak membutuhkan API key untuk demo lokal; vendor live memerlukan akses/kunci terpisah.

## Mesin baru

Hanya untuk mesin baru dengan Python launcher terpasang:

```powershell
py -3.12 -m venv .venv
.venv\Scripts\python.exe -m pip install -r backend/requirements.txt
```

Pada workspace ini venv/dependensi sudah ada. Migrasi SQLite ke PostgreSQL target kosong mengikuti runbook; jangan seed dahulu jika akan membawa data lama. Jangan menyalin config privat atau URL berkredensial ke paket publik.
