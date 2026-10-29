# Demo publik di Render + Neon

Status: konfigurasi dan tes lokal serta CI Linux backend/frontend/build dan startup Docker lulus pada commit **5b61cc7**. Pembuatan resource dan UAT URL publik belum selesai karena Browser Use belum terhubung pada sesi CLI. Gunakan hasil aktual pada PROGRESS.md untuk mengetahui commit yang sudah diuji/deploy. Deployment ini terpisah dari database demo PostgreSQL lokal dan SQLite asli.

## Bentuk deployment

Satu service Docker Render Free melayani Flutter web terkompilasi dan FastAPI pada origin HTTPS yang sama. Neon menyimpan PostgreSQL secara persisten. `Dockerfile` membangun Flutter 3.41.6 dan menyertakan aset renderer lokal, lalu menjalankan Python 3.12 sebagai user nonroot. Tidak memerlukan Flutter SDK atau server lokal di komputer pengunjung.

`.dockerignore` memakai daftar file yang diizinkan: hanya source frontend, backend/migrasi, requirements dan launcher. Runtime/database, secret, hasil UAT, screenshot serta brief tidak masuk build context. `.gitignore` juga mengecualikan `.env.*` selain contoh `.env.example`.

## Akses publik dan pemilik

- Pengunjung: username `demo`, password publik `DemoAssignment!2026`, role `viewer`. Dapat membaca dashboard, antrean dan detail data sintetis. API menolak perubahan dan akses administrasi, bukan hanya menyembunyikan tombol.
- Supervisor: username `supervisor`, password privat dari environment `ADMIN_PASSWORD` minimal 20 karakter. Password tidak dimasukkan ke build Flutter, Git atau log. Password demo lokal tidak berlaku sebagai supervisor cloud.
- Password seed petugas yang masih menggunakan password demo umum diganti ke nilai acak privat pada provisioning cloud. Tugas dan profil tetap tersedia. Pemilik dapat menetapkan password petugas privat melalui Operasi & notifikasi → Akun petugas.
- Restart tidak membuat ulang data. Perubahan `ADMIN_PASSWORD` memutakhirkan hash supervisor dan mencabut sesinya; sesi pengunjung tetap. Benturan identitas akun `demo` menghentikan provisioning dan membatalkan transaksi perubahan akun.

Mode lokal tetap mendukung akun demo lama untuk latihan pada komputer pengembang. `APP_ENV=cloud` otomatis digunakan pada Render (`RENDER=true`) jika APP_ENV tidak diberikan. Mode cloud menolak DATABASE_URL yang bukan PostgreSQL/TLS atau secret supervisor yang kosong/lemah/diketahui.

## Neon

1. Buat project terpisah bernama `assignment-studio-demo` pada paket Free, region AWS Singapore. Jangan memakai project/database aplikasi lain milik pengguna.
2. Gunakan database/role bawaan project baru. Pilih koneksi **direct/unpooled** untuk migrasi awal dan opsi sesi PostgreSQL yang dipakai aplikasi; wajib `sslmode=require` atau verifikasi TLS yang lebih ketat.
3. Simpan URL hanya pada environment rahasia Render sebagai `DATABASE_URL`. Jangan memasukkannya ke `--dart-define`, file tracked, screenshot bukti atau log CI.
4. Aplikasi menjalankan Alembic sampai head dan seed 144 kasus ketika users masih kosong, lalu menyiapkan owner privat dan pengunjung. Jika ingin membawa data/model lokal yang sudah ada, lakukan migrasi/restore sebagai tugas terpisah; deployment bersih tidak otomatis membawa kandidat lokal.

## Render

`render.yaml` menyediakan Blueprint, atau impor repository GitHub sebagai Web Service ber-runtime Docker:

- Plan **Free**, region **Singapore**, branch `main`, Dockerfile `./Dockerfile`.
- `APP_ENV=cloud`.
- `DATABASE_URL`: koneksi Neon baru yang membutuhkan TLS.
- `ADMIN_PASSWORD`: secret acak privat, minimal 20 karakter. Contoh `.env.example` bukan credential yang boleh dipakai.
- `WEB_BUILD_PATH=/app/web` sudah disetel image. Launcher bind `0.0.0.0:$PORT`, default10000, satu worker.
- `OMP_NUM_THREADS=1`, `OPENBLAS_NUM_THREADS=1`, `MKL_NUM_THREADS=1` membatasi thread kerja numerik pada instance kecil.
- Health check `/api/health` memeriksa penyimpanan. UI dan API sama origin, sehingga CORS cloud default kosong.

`TRUSTED_PROXY_CIDRS` hanya boleh berisi jaringan ingress yang benar-benar dikonfirmasi untuk service tersebut. Kosong berarti semua forwarding header diabaikan. Resolver menelusuri X-Forwarded-For dari kanan dan berhenti pada hop tidak dipercaya; alamat palsu yang ditambahkan di kiri tidak dipakai. Wildcard IPv4/IPv6 ditolak. Jangan mengaktifkan trust `*` pada Uvicorn. Verifikasi perilaku IP/limiter pada deployment sebelum membuka URL ke banyak pengunjung; konfigurasi kosong di belakang proxy dapat menggabungkan anggaran percobaan login beberapa pengunjung.

Free service dapat tidur setelah15menit idle dan memerlukan sekitar1menit untuk bangun. SQLite/file lokal Render tidak persisten. Jangan menambah disk/database berbayar atau monitor keepalive untuk mengakali batas free. Training model dan generator histori tetap perlu diuji terhadap RAM512MB dan kuota Neon; keberhasilan lokal bukan bukti performa cloud.

## Dependency dan CI

`backend/requirements.in` mencatat versi yang dipilih. `requirements.txt` dihasilkan dengan resolver universal Python3.12, semua dependency terkunci dengan SHA256 untuk instalasi `--require-hashes`. Regenerasi dengan:

```powershell
uv pip compile backend/requirements.in --universal --python-version 3.12 --generate-hashes --output-file backend/requirements.txt
```

GitHub Actions menjalankan tes backend SQLite, analyze/tes/build Flutter publik, kemudian build dan smoke image Linux. Workflow tidak menerima secret cloud. Pengujian PostgreSQL/migrasi lokal terisolasi tetap dijalankan pada environment uji pengembang.

## Penerimaan setelah deploy

Periksa login pengunjung, dashboard/detail pada desktop dan ponsel; coba request perubahan dengan token pengunjung dan pastikan403. Pemilik memeriksa login privat serta satu alur penagihan dan pengajuan sintetis, histori, inbox/job simulasi, lalu restart/redeploy dan bandingkan hasil database. Pastikan origin HTTPS/API benar, password demo supervisor ditolak, rate limit memahami ingress, dan tidak ada secret pada aset/log. Catat commit, URL, hasil CI, keterbatasan free dan bukti UAT aktual.

Referensi: [Render Free](https://render.com/docs/free), [Neon plans](https://neon.com/docs/introduction/plans), [Neon pooling](https://neon.com/docs/connect/connection-pooling).

## Koneksi Browser Use

Jika alat memberi `The browser access host is unavailable`, browser belum tersambung ke sesi alat meskipun Chrome terbuka. Di aplikasi desktop ChatGPT/Codex, periksa Settings → Computer Use → Google Chrome: status Manage dan toggle aktif. Buka ekstensi ChatGPT pada profil Chrome yang benar, lalu pilih @Chrome atau tab Neon/Render dari menu @ di percakapan. Bila tetap gagal, restart browser/aplikasi desktop; chat desktop baru dapat membersihkan kondisi koneksi khusus percakapan. Website permissions yang sudah diberikan tidak perlu diubah tanpa bukti penolakan origin baru. [Panduan ekstensi resmi](https://learn.chatgpt.com/docs/chrome-extension).

Instruksi pengguna untuk task ini membatasi otomasi pada Browser Use Chrome. Jangan beralih ke browser-act atau kontrol desktop. Perbaikan kode, tes, build dan CI dapat berjalan melalui tool pengembangan selama koneksi browser belum tersedia.
