# Demo publik di Render + Neon

Status 29 Oktober 2026: **demo Live di https://assignment-studio-demo.onrender.com**, Render Free/Docker/Singapore dan Neon Free/PostgreSQL18/Singapore. Commit kode **a89a495**, [CI Linux seluruhnya lulus](https://github.com/dzakyahnaf/sistem-prediktif-auto-assignment-penagihan/actions/runs/40844358486). Browser Use in-app pada Codex desktop berhasil terhubung. Login pengunjung/pemilik, layout desktop/390px, penagihan dengan reassign/pembayaran sebagian/penuh serta pengajuan dokumen/verifikasi/pencairan simulasi dan penolakan sudah diuji melalui UI. Hasil persistensi redeploy terbaru dicatat di PROGRESS. Cloud terpisah dari database lokal asli.

Resource demo: organisasi Neon `assignment-demo-free` (`org-ancient-paper-94877234`), project `assignment-studio-demo` (`empty-tooth-07554638`), branch `production`; service Render `srv-dbhgdjnb9u1s73eq1q8g`. Organisasi Neon Launch dan project aplikasi pengguna lain tidak diubah. Credential owner/database aktual hanya pada environment Render dan file ignored `runtime/cloud-deployment-secrets.json`; tidak ditulis pada dokumentasi.

Redeploy aktual `dep-dbhglu9srm7s73fq95rg` selesai52,5detik; **27 fingerprint tabel bisnis identik**, 147kasus/4assignment/7aktivitas tetap tersimpan. Sesi supervisor UI ditutup setelah UAT. Bukti: [Render Live](evidence/cloud-render-live.png), [dashboard sesudah redeploy](evidence/cloud-dashboard-after-redeploy.png), [dialog pembayaran ponsel](evidence/cloud-payment-dialog-mobile.png). Masih belum diuji di cloud: loginpetugasprivat, imporXLSX/inboxworker/training/segmentasi dan profilingRAM/beban; ingress masih perlu konfirmasi. Cloud memakai rules, kandidat historis/model lokal tidak dipindahkan otomatis.

Deploy pertama menemukan batas UID/GID pada builder Render ketika mengekstrak arsip Gradle Flutter. Build stage memakai `TAR_OPTIONS=--no-same-owner` agar pemilik artefak mengikuti builder; runtime tetap nonroot. Build ulang Render dan CI lulus. Koneksi Neon direct dibuktikan client libpq memakai TLS; `pg_stat_ssl` internal server bukan indikator koneksi TLS client ke endpoint Neon.

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

## Panduan manual UI, berurutan

Nama menu mengikuti dokumentasi resmi Neon/Render dan pengamatan Chrome pada 29 Oktober 2026. Beberapa akun dapat memperoleh susunan menu berbeda. Jangan melanjutkan pilihan berbayar jika label Free tidak tersedia. Jalur berikut menggunakan formulir Web Service manual, bukan Blueprint.

### 1. Siapkan repository dan password pemilik

1. Buka repository GitHub `dzakyahnaf/sistem-prediktif-auto-assignment-penagihan`, pilih branch `main`.
2. Pastikan root repository berisi `Dockerfile`, `.dockerignore`, `render.yaml`, folder `deploy`, `backend`, dan `apps`. Commit kode deployment yang sudah lulus CI adalah `5b61cc7`; commit dokumentasi dapat lebih baru. Tidak perlu menyalin hasil build dari komputer lokal.
3. Siapkan password supervisor privat acak minimal 20 karakter, disarankan 32 karakter atau lebih, dan simpan di password manager. Jangan gunakan password demo publik. Password ini menjadi nilai `ADMIN_PASSWORD` di Render; bukan password akun Render/Neon/GitHub.
4. Secret privat yang sebelumnya disiapkan ada di file lokal ignored `runtime/cloud-deployment-secrets.json`, field `admin_password`. Boleh menggunakan nilai itu secara privat atau membuat password baru. Jangan kirim isinya ke chat, Git, screenshot atau log.

### 2. Pastikan organisasi Neon Free

1. Buka https://console.neon.tech/ dan login dengan akun sendiri.
2. Buka pemilih organisasi/profil. Pada tampilan yang diverifikasi, klik menu `rakken account menu button`, kemudian item `rakken` untuk membuka submenu organisasi; submenu berisi `Create organization`. Dokumentasi Neon juga menyebut menu profil kanan atas; susunan dapat berbeda.
3. Jika sudah ada organisasi pribadi Free, pilih organisasi tersebut. Jika belum, pilih `Create organization` dari menu profil/pengelolaan organisasi.
4. Beri nama organisasi baru, misalnya `assignment-demo-free`, lalu pilih paket `Free` dan konfirmasikan pembuatan organisasi. Jangan mengubah atau menurunkan paket organisasi aplikasi lain.
5. Buka `Billing` pada organisasi baru. Pastikan paket aktif bertuliskan `Free`, bukan `Launch` atau `Scale`, sebelum membuat project.
6. Jika tidak menemukan pilihan organisasi Free, berhenti di sini. Organisasi `rakken` yang diperiksa memakai Launch berbayar; membuat project baru di dalamnya tidak membuat project tersebut otomatis gratis.

Referensi UI: https://neon.com/docs/manage/orgs-manage

### 3. Buat project PostgreSQL baru

1. Pada organisasi Free, klik `Projects`, kemudian `New Project`.
2. Isi `Project name` dengan `assignment-studio-demo`.
3. Pilih region `AWS Singapore` (`ap-southeast-1`). Jika provider dan region merupakan kolom terpisah, pilih `AWS`, lalu `Singapore`.
4. Di bagian `Services`, aktifkan `Postgres database`; biarkan versi PostgreSQL default. Tidak perlu mengaktifkan Neon Auth, object storage, functions atau AI gateway untuk aplikasi ini.
5. Periksa nama organisasi dan region, kemudian klik `Create project`.
6. Tunggu halaman Overview project baru. Gunakan database dan role bawaan, umumnya `neondb` serta `neondb_owner`; jangan menggunakan database project lain.

Referensi UI: https://neon.com/docs/manage/projects

### 4. Salin koneksi direct Neon

1. Dari project baru, klik `Connect`.
2. Pada dialog `Connect to your branch`, pilih branch utama/default (`production` atau `main`, sesuai yang ditampilkan), primary/read-write compute, database `neondb`, dan role `neondb_owner` jika nama bawaan itu tersedia.
3. Matikan toggle `Connection pooling`. Aplikasi ini menggunakan koneksi direct untuk migrasi dan operasi sesi PostgreSQL.
4. Jika ada pilihan format, pilih `Connection string`; jangan memilih potongan kode Prisma, JavaScript atau command psql.
5. Klik tombol copy pada URI. Nilainya harus diawali `postgresql://`, hostname direct tidak mengandung `-pooler`, dan query memuat `sslmode=require` atau mode verifikasi TLS lebih ketat. Pertahankan parameter lain seperti `channel_binding=require` jika disediakan Neon.
6. Simpan URI secara privat sementara. Di Render, tempel hanya URI, tanpa awalan `psql`, tanpa `DATABASE_URL=`, tanpa tanda kutip, tanpa backtick dan tanpa baris baru.

Referensi UI: https://neon.com/docs/connect/connect-from-any-app

### 5. Hubungkan repository pada Render

1. Buka https://dashboard.render.com/ dan login.
2. Klik `+ New` / `New +`, kemudian `Web Service`.
3. Pada daftar repository/Git Provider, cari `sistem-prediktif-auto-assignment-penagihan` milik `dzakyahnaf`, lalu klik `Connect`.
4. Jika repository belum muncul, gunakan tombol koneksi `GitHub`, login/otorisasi melalui GitHub, dan bila tersedia pilih `Only select repositories` serta repository ini saja. Kembali ke Render, refresh daftar, lalu klik `Connect` pada repository.
5. Alternatif tanpa menghubungkan GitHub: pilih `Public Git Repository`, tempel `https://github.com/dzakyahnaf/sistem-prediktif-auto-assignment-penagihan`, lalu `Connect`. Pada jalur URL publik, jangan mengasumsikan auto deploy tersedia; gunakan `Manual Deploy` sesudah push berikutnya.

### 6. Isi konfigurasi service

Pada formulir service baru, isi:

- `Name`: `assignment-studio-demo` (boleh tambahkan suffix jika sudah dipakai).
- `Project`: opsional; biarkan tanpa project/default jika tidak memerlukan pengelompokan.
- `Language` / `Runtime`: `Docker`, walaupun Render mendeteksi Python.
- `Branch`: `main`.
- `Region`: `Singapore`.
- `Root Directory`: kosong, karena build memerlukan folder backend dan apps dari root repository.
- `Dockerfile Path`: `./Dockerfile` jika kolom ditampilkan.
- `Docker Build Context Directory`: `.` / root repository jika kolom ditampilkan.
- `Instance Type` / `Compute`: klik kartu `Free`, pastikan harga `$0`. Jangan pilih Starter atau plan berbayar.

Jangan memasukkan perintah PowerShell, `flutter run`, `pip install`, atau `uvicorn` ke command Render. Dockerfile sudah membangun Flutter dan memasang dependency, lalu CMD menjalankan launcher yang benar. `Docker Command` dibiarkan kosong agar CMD image dipakai.

Referensi UI: https://render.com/docs/docker dan https://render.com/docs/your-first-deploy

### 7. Isi environment

Pada `Environment Variables`, klik `Add Environment Variable` untuk setiap pasangan berikut. Kolom kiri adalah key, kolom kanan adalah value:

```text
APP_ENV=cloud
DATABASE_URL=<URI direct dari Neon>
ADMIN_PASSWORD=<password pemilik privat minimal 20 karakter>
OMP_NUM_THREADS=1
OPENBLAS_NUM_THREADS=1
MKL_NUM_THREADS=1
```

Teks dalam kurung sudut adalah petunjuk, bukan nilai yang ditempel. Di formulir, `APP_ENV` dan `cloud` dimasukkan ke dua kolom terpisah. Jangan menambahkan tanda kutip ke value. Password owner berbeda dari password role database yang sudah berada di URI Neon.

`WEB_BUILD_PATH=/app/web` dan pengaturan thread sudah memiliki default pada image; pengulangan thread di atas membuat konfigurasi eksplisit. Render menyediakan PORT, launcher membacanya. Tidak perlu mengisi `DATABASE_PATH`, `API_URL`, `CORS_ORIGINS`, Flutter SDK path atau localhost.

Untuk deployment awal, jangan tambahkan `TRUSTED_PROXY_CIDRS` jika ingress belum dikonfirmasi. Ini mengabaikan forwarding header dan dapat membuat beberapa pengunjung berbagi anggaran percobaan login; verifikasi ingress tetap menjadi pekerjaan sebelum UAT banyak pengguna. Jangan isi wildcard atau menebak jaringan proxy.

### 8. Health check dan deploy

1. Buka `Advanced` jika tersedia.
2. Isi `Health Check Path` dengan `/api/health`.
3. Biarkan `Docker Command`, `Pre-Deploy Command`, dan `Registry Credential` kosong. Tidak perlu disk, database Render, background worker, cron atau layanan tambahan. Startup aplikasi sudah menjalankan migrasi dan seed database baru.
4. Periksa kembali Free, Singapore, Docker, main, root kosong, dan tiga environment wajib.
5. Klik `Deploy Web Service` / `Deploy` sesuai tombol formulir.
6. Buka `Events` untuk melihat build/deploy, dan `Logs` untuk startup. Build pertama mengunduh Flutter/dependency sehingga dapat memerlukan beberapa menit. Jangan submit pembuatan service berulang saat masih Building.
7. Jika Health Check Path belum tersedia saat create, setelah service muncul buka `Settings`, cari `Health Checks` / `Health Check Path`, klik `Edit`, isi `/api/health`, lalu `Save`.
8. Tunggu deployment sukses/status `Live`. Ambil alamat `https://<nama-service>.onrender.com` dari halaman service; nama akhir dapat memiliki suffix. Jangan mengasumsikan nama URL sebelum Render menampilkannya.

### 9. Periksa API, login, dan persistensi

1. Buka `<URL-Render>/api/health`. Hasil yang diharapkan memuat `status: ok`, `mode: synthetic-demo`, dan `storage: postgresql` (versi aplikasi saat ini `0.13.0`). Ini baru hasil yang diharapkan, belum hasil cloud yang telah diuji.
2. Buka URL root service. Pastikan halaman login Flutter muncul.
3. Login sebagai `demo` dengan password publik `DemoAssignment!2026`. Dashboard, antrean dan detail bisa dibaca; kontrol perubahan/administrasi tidak tersedia. Akun ini untuk pengunjung.
4. Logout. Login `supervisor` dengan password privat `ADMIN_PASSWORD` yang disimpan pada Render. Password demo publik tidak berlaku untuk supervisor cloud.
5. Dengan akun supervisor buat satu kasus sintetis dengan nama mudah dicari, misalnya `UAT Cloud Persistensi 01`, lalu simpan. Catat ID kasus dan satu aktivitas yang dimasukkan.
6. Pada Render buka service, klik `Manual Deploy`, lalu `Deploy latest commit`; tunggu Live kembali. Ini menguji pergantian container tanpa mengganti database Neon.
7. Buka kembali aplikasi, login, lalu cari ID kasus tadi. Kasus dan aktivitas harus masih ada. Jika hilang, periksa DATABASE_URL/branch/database dan log sebelum menyatakan persistensi lulus.
8. Lanjutkan UAT penagihan (assignment, pembayaran sebagian/penuh), pengajuan (dokumen, verifikasi, pencairan simulasi/penolakan), reassign/histori, role dan tampilan ponsel. HTTP health/build sukses belum membuktikan alur tersebut.

Deployment baru menyiapkan 144 kasus, 12 petugas, dan 3 wilayah sintetis jika database masih kosong. Data/model lokal tidak otomatis dipindahkan ke Neon. Aplikasi dan database lokal tetap utuh.

### 10. Jika gagal

- Pesan `Cloud requires a private ADMIN_PASSWORD...`: Render service → `Environment` → `Edit`, masukkan secret privat minimal 20 karakter, lalu `Save, rebuild, and deploy` / `Save and deploy` sesuai pilihan yang tampil.
- Pesan `Cloud requires an explicit PostgreSQL DATABASE_URL` atau TLS: ambil ulang URI direct dari dialog Connect Neon; perbaiki value DATABASE_URL di Environment. Jangan menyalin command `psql` atau tanda kutip.
- `password authentication failed`: periksa branch/database/role dan URI terbaru di project Neon yang benar. Jangan reset password project aplikasi lain.
- `ModuleNotFoundError: app`: pastikan Render branch main memakai commit `5b61cc7` atau sesudahnya, lalu Manual Deploy latest commit. Fix launcher sudah ada pada commit tersebut.
- `404` root tetapi health hidup: pastikan Runtime Docker, Dockerfile root proyek, Root Directory kosong, dan tidak ada Docker Command override. Build publik memerlukan frontend dan backend sekaligus.
- Halaman lama setelah deploy sukses: gunakan Ctrl+Shift+R, lalu cek Events untuk commit yang benar.
- Status 429 setelah percobaan login berulang: tunggu batas limiter pulih; periksa konfigurasi ingress sebelum mengulang banyak percobaan.
- Startup berhenti/kehabisan memori: kirim cuplikan error log yang sudah disamarkan. Batas RAM Free perlu pengukuran; jangan langsung upgrade atau menyimpulkan training berat pasti muat.

### 11. Batas gratis

Render Free tidur setelah sekitar 15 menit tanpa trafik; kunjungan berikutnya biasanya memerlukan sekitar satu menit untuk bangun. Filesystem container bersifat sementara. Data database berada di Neon, namun file lokal yang dibuat saat runtime tidak otomatis persisten. Render memberikan 750 jam Free per workspace per bulan dan mempunyai kuota bandwidth/build. Jika workspace memiliki metode pembayaran, pemakaian tambahan tertentu dapat ditagih; periksa Billing/Monthly Included Usage dan spend limit pipeline. Untuk demo tanpa biaya tambahan, gunakan paket Free dan jangan menambah resource berbayar. Neon Free tetap memiliki kuota sendiri.

Referensi: https://render.com/docs/free

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

Browser Use pada sesi CLI sebelumnya memberi `The browser access host is unavailable`. Setelah pengguna membuka percakapan di Codex desktop dengan tab in-app Render dan Neon, inventaris dan pembacaan tab berhasil melalui `cua_repl`; deployment dan UAT cloud diteruskan di browser tersebut. Jangan mengulang permintaan allowlist/Full access atau menyimpulkan akses tetap gagal berdasarkan hasil sesi lama. Panduan manual di atas tetap tersedia sebagai alternatif.
