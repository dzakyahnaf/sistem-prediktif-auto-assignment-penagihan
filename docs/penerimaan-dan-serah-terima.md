# Penerimaan prototype dan serah terima — Sprint 13

Scope hingga Sprint 13 adalah aplikasi yang berfungsi dengan data sintetis, web dan Android emulator, penyimpanan persisten, model/segmen simulasi serta integrasi tiruan. Build dan UAT iOS masih memerlukan macOS/Xcode. Penerimaan bisnis final, publikasi store dan layanan produksi belum termasuk hasil yang terverifikasi.

## Peta kebutuhan dan bukti

- Dua workflow sampai pelunasan, dokumen/verifikasi/pencairan dan penolakan: UAT Chrome Sprint 2/7/9/13 dan Android Sprint 11/13; tes `test_workflows.py`. Semua transaksi simulasi.
- Assignment awal/ulang, wilayah/tim/kapasitas/status, Low→A/High→B/Medium mengikuti ambang, override beralasan, histori dan audit: Sprint 6/7/9/10; tes master/decisions/models. Override tetap mengikuti batas mutlak.
- Dataset historis, snapshot sebelum keputusan, label/censoring dan split waktu/identitas: Sprint 8; tes analytics. Simulator longitudinal terpisah dari 144 seed operasional. Ingest histori nyata belum tersedia.
- Empat model awal/reassign per domain, preprocessing train-only, kalibrasi/evaluasi, registry JSON/checksum, aktivasi/rollback/fallback dan kontribusi: Sprint 9. Segmen KMeans, profil/stabilitas dan kebijakan: Sprint 10. Kandidat tidak otomatis aktif; hasil sintetis bukan bukti efektivitas pada nasabah nyata.
- Master, pagination/pemilihan lintas halaman, laporan/scope historis, CSV dan impor XLSX preview/validasi/commit: Sprint 3–6. Chrome diperiksa per modul; picker/save OS Android diperiksa Sprint 11. Impor tidak mengubah histori/transaksi lama.
- PostgreSQL/SQLAlchemy Core/Alembic, migrasi read-only SQLite, hash/sequence/receipt dan backup/restore: Sprint 7 serta regresi setiap penambahan schema. SQLite asli dipertahankan, tanpa sinkronisasi balik setelah cutover.
- Inbox, pengingat SLA, mock telephony/omnichannel, retry/dead-letter/recovery/receipt dan akun nonaktif/reset/revocation: Sprint 12. UAT Chrome desktop/390px, tes operasi dan restart seluruh tabel. Job tidak mengirim komunikasi keluar atau membuat aktivitas bisnis otomatis.
- Android: runner/flavor/jaringan, workflow native, IME, picker/save OS di Sprint 11; regresi dengan inbox di Sprint 13. iOS baru runner/config. Perangkat Android fisik dan store belum diverifikasi.
- Hardening login, headers, paket demo, acceptance dan panduan: Sprint 13. Angka pengujian, artefak dan catatan akhir tercantum di [PROGRESS](PROGRESS.md).

## Menjalankan demo utama

Gunakan root workspace, interpreter `.venv\Scripts\python.exe` dan Flutter SDK `C:\flutter`. Periksa server sebelum menjalankan instance baru. Startup default memakai config privat PostgreSQL `runtime/postgres-local.json`. Jangan init ulang klaster yang berisi demo. Klaster proyek port 15432 terpisah dari service pengguna 5433.

```powershell
.venv\Scripts\python.exe scripts/postgres-local.py status
.\scripts\start-backend.ps1
# Terminal kedua, jika port 5173 belum dipakai:
.venv\Scripts\python.exe scripts/serve-web.py
```

Web 5173, API 8000. Server web menyajikan release build; setelah perubahan frontend jalankan `test-web.ps1 -FlutterSdk 'C:\flutter' -Offline`. Logout sebelum berganti role. Login ulang sesudah reload diperlukan karena sesi Flutter hanya di memori.

Paket alternatif dibangun dengan `build-demo.ps1 -FlutterSdk 'C:\flutter' -Offline`. ZIP di `runtime/artifacts` memuat compiled web, backend, panduan dan manifest, tanpa runtime/config privat/database workspace. Ekstrak ke folder baru lalu ikuti START-DEMO.ps1/README paket. Python 3.12 dan dependensi diperlukan; Flutter SDK tidak diperlukan untuk menjalankan ZIP. Startup membuat SQLite sendiri dengan 144 kasus, tanpa dataset/model workspace.

FastAPI melayani UI dan API pada satu origin loopback 8080. `StaticFiles(html=True)` menyediakan index direktori; route yang tidak ada tetap 404. Referensi: [FastAPI](https://fastapi.tiangolo.com/tutorial/static-files/) dan [Starlette](https://www.starlette.io/staticfiles/). Aset renderer web lokal disertakan dalam paket.

APK demo memakai host emulator `10.0.2.2:8000` dan applicationId `.demo`, entrypoint `lib/main.dart`. Ini APK debug untuk demonstrasi, belum signing distribusi. Native integration test memakai backend UAT dan target test tersendiri. iOS memerlukan Mac/Xcode. Lihat [mobile](mobile-native.md).

## Latihan operator

1. Supervisor membuat penagihan Low/SMG/Rp1 juta lalu menugaskan. Periksa Tim A, SLA, skor/sumber dan snapshot. Petugas smg-col-a membuka inbox/kasus, mencatat follow-up serta pembayaran Rp400 ribu lalu Rp600 ribu. Parsial masih aktif; penuh menutup kasus. Outcome success hanya jika lunas maksimal 72 jam sejak assignment siklus.
2. Buat pengajuan Low/SMG/Rp1 juta, penghasilan Rp5 juta. Catat dokumen lengkap→lolos verifikasi→pencairan simulasi Rp1 juta. Buat pengajuan lain lalu tolak dengan alasan. Periksa dashboard dan histori per domain.
3. Reassign sebelum terminal dengan alasan. Periksa siklus lama ditutup, saldo/progres terbawa dan snapshot baru hanya memakai siklus tertutup. Ubah kebijakan lalu pastikan snapshot assignment lama tetap.
4. Uji scope: petugas tidak memiliki kontrol master/model/kebijakan atau akses kasus pihak lain. Pada UAT, nonaktifkan akun melalui Operasi: sesi dicabut/login ditolak, tugas lama tetap. Pulihkan akun/password sesudah latihan. Status master dan status login mempunyai fungsi berbeda.
5. Buat mock job, review/Batal lalu konfirmasi. Proses job siap menghasilkan receipt. Gagal sekali menunggu 15 detik; tiga gagal menjadi dead. Jadwalkan ulang dengan alasan, histori dipertahankan. Aktivitas/pembayaran tidak ditambah otomatis.
6. Hentikan backend UAT, refresh: error dan data usang disembunyikan. Mulai kembali lalu refresh: pulih. Bandingkan fingerprint sebelum/sesudah restart. Build saja tidak dianggap UAT.

Gunakan schema salinan UUID melalui helper proyek atau paket SQLite baru untuk latihan yang bermutasi. Jangan menumpuk pengujian di antrean utama. Semua hasil UAT lama dipertahankan.

## Hardening dan pemulihan

Revision `0006_hardening` menambah hashed failed-login buckets. Lima kegagalan per kombinasi peer/username atau 30 per peer dalam 15 menit menahan login dengan 429/Retry-After hingga window berakhir. Sukses membersihkan bucket kombinasi; anggaran peer tetap. Tabel tidak menyimpan password, username atau IP mentah. Kegagalan disimpan meskipun respons 401 dan bertahan restart. Startup lokal mengabaikan proxy headers. Deployment dengan reverse proxy memerlukan konfigurasi trust/limiter tersendiri.

API dan bundle static memakai no-store, nosniff, no-referrer dan SAMEORIGIN. Hash token/PBKDF2, role/scope, optimistic version, idempotency dan audit transaksi tetap berlaku. Hardening ini bukan klaim pentest lengkap atau kesiapan produksi.

Backup PostgreSQL menggunakan nama baru:

```powershell
.venv\Scripts\python.exe scripts/backup-postgres.py --output runtime/backups/nama-baru.dump --report runtime/nama-baru.json --verify-restore
```

Tool membandingkan snapshot dump dengan restore di database UUID baru. Dump berisi hash akun/sesi; simpan lokal dengan aman. Untuk SQLite paket: hentikan demo, salin `runtime/demo.db` ke lokasi aman bernama baru, lalu mulai kembali. Restore ke folder paket kompatibel dengan demo berhenti. Jangan menulis SQLite asli workspace sebagai pengganti PostgreSQL aktif. Prosedur migrasi/rollback ada di [PostgreSQL](postgresql.md).

## Gate yang masih terbuka

Build/UAT/signing iOS, Android fisik, keputusan bisnis A/Tele/B/Lapangan dan nilai tagihan target, jendela konversi pengajuan, validasi model/segmen pada histori nyata, integrasi vendor live, TLS/HA/monitoring/load test produksi dan store. Demo lokal saat ini tidak membutuhkan API key. Jangan menyebut seluruh project 100% diterima sebelum gate platform dan bisnis yang disepakati terpenuhi.
