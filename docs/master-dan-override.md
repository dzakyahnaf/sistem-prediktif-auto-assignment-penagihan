# Master operasional dan override assignment — Sprint 6

Supervisor membuka **Petugas → Kelola master operasional** untuk mengelola wilayah/petugas dan membaca audit perubahan. Tombol **Pilih petugas tertentu** tersedia pada detail kasus yang belum selesai, untuk assignment pertama maupun pengalihan ke petugas lain. Penagihan dan pengajuan memakai mekanisme yang sama, dengan validasi domain masing-masing.

Sejak Sprint7 penyimpanan demo aktif memakai PostgreSQL/SQLAlchemy Core dan Alembic0001_portable. Kontrak master/override tetap sama; [runbook PostgreSQL](postgresql.md) menjelaskan migrasi dan transaksi. Catatan schema SQLitev3 di bawah adalah hasil implementasi Sprint6 yang tetap berlaku pada fallback.

## Wilayah

- Tambah kode tetap 2–8 karakter: dimulai huruf besar, dilanjutkan huruf besar/angka/`_`/`-`. Nama 2–80 karakter; kode/nama tidak boleh bertabrakan dengan nama/kode wilayah lain tanpa membedakan kapital.
- Nama dan status aktif dapat diubah dengan alasan 10–500 karakter serta versi terbaru. Tidak ada hapus fisik; kasus/histori tetap mengacu kode yang sama. Nama wilayah di formulir/laporan mengikuti master terkini.
- Penonaktifan ditolak selama masih ada **kasus terbuka**, termasuk belum ditugaskan, atau **petugas aktif** di wilayah itu. Alihkan/selesaikan kasus dan nonaktifkan/pindahkan petugas dahulu.
- Formulir kasus, template XLSX dan validasi impor hanya menerima wilayah aktif. Laporan tetap dapat memilih wilayah nonaktif. Jika wilayah dinonaktifkan setelah preview impor, commit ditolak/rollback; preview ulang menunjukkan error wilayah.
- Prototype dibatasi 25 wilayah. Batas kode dan jumlah tersebut juga menjaga daftar validasi wilayah pada template Excel tetap di bawah batas panjang inline list Excel.

## Petugas dan akun awal

Petugas baru memerlukan kode tetap 2–40 karakter dengan pola kode wilayah, nama sintetis 2–100, wilayah, alur `collection`/`origination`, tim A/B, kanal Tele/Lapangan, pendekatan 2–100, kapasitas 1–100, status aktif, username tetap dan password awal.

Username 3–40 karakter, huruf kecil/angka/`.`/`_`/`-`, dimulai huruf kecil/angka. Password minimal 12, maksimal 128 karakter. Akun role `agent` dan profil dibuat dalam satu transaksi: konflik ID/username atau validasi membatalkan keduanya. Password di-hash PBKDF2 dan tidak masuk audit/respons profil. Batas prototype 200 petugas. Pembaruan username/password, reset akun dan administrasi supervisor belum tersedia.

Perubahan profil memerlukan alasan dan versi terbaru:

- Wilayah, alur dan tim tidak boleh berubah selama petugas masih memegang kasus nonterminal, termasuk bila status penerimaan assignment nonaktif. Selesaikan atau alihkan kasus dahulu.
- Nama, kanal, pendekatan, kapasitas dan status penerimaan dapat diperbarui. Kanal tetap metadata terpisah dari tim; A=Tele/B=Lapangan masih asumsi demo, bukan aturan yang memaksa field kanal.
- Kapasitas tidak boleh lebih kecil dari maksimum beban aktif dan jumlah assignment hari ini (hari kalender WIB). Kasus selesai tidak mengembalikan jatah harian; pindah wilayah/alur tidak menghapus beban harian petugas.
- Petugas aktif memerlukan wilayah aktif. Penonaktifan penerimaan **tidak mencabut login**, tidak melepas tugas lama dan tidak menghapus histori. Petugas tetap dapat menyelesaikan tugas yang masih menjadi miliknya.

UI memuat ulang daftar setelah dialog ditutup, termasuk ketika hasil simpan sebelumnya belum pasti. Konflik 409 menahan dialog; **Muat versi terbaru** mengambil profil/versi terkini dan membersihkan alasan lama untuk ditinjau lagi. Kode dan username tidak diedit. API kapasitas/status lama tetap tersedia untuk kompatibilitas; UI terbaru mengirim `expected_version` bila tersedia. Klien lama tanpa versi tetap diterima pada endpoint lama saja.

## Override yang mengikuti aturan assignment

1. Buka detail kasus aktif/belum ditugaskan → **Pilih petugas tertentu**.
2. Tinjau versi kasus, skor dan tim untuk siklus yang akan dibuat. Pilih salah satu kandidat yang memenuhi syarat dan isi alasan 10–500 karakter. **Kecocokan seluruh petugas** menjelaskan penolakan wilayah/alur/tim/aktif/kapasitas atau petugas saat ini.
3. **Tinjau override** menampilkan petugas lama/baru, ID, tim, indeks aturan, alasan dan dampak siklus. Batal mempertahankan pilihan tanpa membuat assignment.
4. **Terapkan override** memeriksa ulang versi dan semua kendala di dalam transaksi database. Pilihan eksplisit memilih identitas petugas di antara kandidat yang valid; tidak melewati hard constraint atau mengubah aturan Low/Medium/High.

Low tetap Tim A, High tetap Tim B. Hanya Medium mengikuti skor/ambang demo 60. Untuk assignment pertama, skor tersimpan kasus digunakan. Untuk pengalihan, preview menghitung skor dengan histori siklus yang akan ditutup; preview sendiri belum mengubah kasus/score/siklus. Commit menutup siklus lama, menghitung ulang skor dan membuat siklus baru secara atomik. Histori siklus lama tidak ditulis ulang. Outcome lama `superseded` bila belum melewati SLA, atau `no_success` bila sudah melewati batas, sama dengan reassign otomatis.

Saldo terbayar, kelengkapan dokumen dan status qualified dibawa. Siklus baru memperoleh jendela 72 jam. Pengalihan memakai petugas berbeda; bila ingin evaluasi otomatis yang mungkin memilih petugas sama, gunakan Penugasan ulang yang sudah ada. Kasus paid/disbursed/rejected tidak dapat dioverride. Gagal kapasitas/versi/aturan membatalkan seluruh operasi sehingga siklus lama tetap aktif.

Setiap intent memiliki `request_key`. Retry dengan actor, kasus dan payload yang sama mengembalikan hasil sama tanpa siklus/audit tambahan, bahkan jika respons pertama hilang. Penggunaan key untuk payload/actor/kasus berbeda ditolak. UI mengunci payload ketika hasil jaringan/5xx ambigu dan menyediakan **Kirim ulang override**; jangan mengubah payload atau membuat key baru untuk retry intent yang sama. Tutup dan muat ulang detail bila ingin memeriksa hasil terlebih dahulu. Konflik definitif 409 membuka kontrol agar pilihan terbaru dapat dimuat; tidak ada retry otomatis.

## Histori, laporan dan audit

Assignment baru menyimpan snapshot `agent_name`, `agent_team`, `agent_channel`. Histori detail dan laporan siklus memakai snapshot tersebut; perubahan profil setelah tugas selesai tidak mengubah nama/tim pada siklus lama. Migrasi mengisi snapshot assignment lama memakai profil yang tersedia saat migrasi; tidak merekonstruksi perubahan profil yang tidak pernah dicatat sebelumnya.

Daftar petugas menyediakan `report_scopes` dari profil saat ini, kepemilikan kasus dan histori assignment. Karena itu petugas yang kemudian pindah wilayah/alur masih dapat dipilih untuk laporan historis pada konteks lama. Label pada pemilih menggunakan nama profil terkini, sedangkan baris siklus menggunakan snapshot nama. Laporan portofolio tetap memakai kondisi kasus/master terkini; realisasi siklus berasal dari aktivitas siklus tersebut.

**Audit perubahan** menampilkan 100 kejadian master/override terbaru, actor, waktu, alasan, objek dan perpindahan petugas/siklus. Seluruh audit tersimpan di database. Detail sebelum/sesudah, tim, skor dan alasan tersedia melalui API; password tidak dicatat. Event utama: `create_region`, `update_region`, `create_agent`, `update_agent_profile`, `update_agent`, `override_assignment`; assignment/reassign juga mempertahankan audit lamanya. Tidak ada layanan eksternal/API key yang diperlukan.

## Kontrak API

Semua route di bawah khusus supervisor, memakai Bearer token dan `Cache-Control: no-store`.

- `GET /api/master/regions`: semua wilayah, status/versi, jumlah kasus terbuka/seluruh kasus dan petugas aktif.
- `POST /api/master/regions`: `{ "id": "YOG", "name": "Yogyakarta Demo", "active": true }`.
- `PATCH /api/master/regions/{id}`: `{ "name": "Yogyakarta Demo", "active": false, "expected_version": 1, "reason": "Penutupan wilayah demo" }`.
- `GET /api/agents`: profil, username (tanpa password), versi, beban dan `report_scopes`.
- `POST /api/master/agents`: field profil di atas ditambah `id`, `username`, `password` untuk akun awal.
- `PATCH /api/master/agents/{id}`: profil lengkap tanpa ID/username/password, ditambah `expected_version`, `reason`.
- `PATCH /api/agents/{id}`: endpoint lama kapasitas/status, versi opsional.
- `GET /api/cases/{id}/assignment-options`: versi kasus, petugas lama, skor proyeksi, tim tujuan dan kandidat beserta alasan kelayakan.
- `POST /api/cases/{id}/override-assignment`: `{ "agent_id": "SMG-col-B", "expected_version": 4, "request_key": "kunci-unik-minimal-16-karakter", "reason": "Pengalihan untuk tindak lanjut lapangan" }`.
- `GET /api/master/audit`: 100 audit master/override terbaru, dengan detail JSON yang sudah diparse.
- `GET /api/config`: `regions` aktif untuk input kasus/impor, `report_regions` seluruh wilayah untuk histori/laporan.

## Penyimpanan dan verifikasi

Migrasi aditif SQLite schema v3 pada Sprint6 menambahkan `regions.active/version`, `agents.version`, tiga snapshot assignment, dan tabel `assignment_overrides`. Restart mengisi kolom legacy yang belum tersedia tanpa menghapus tabel/kasus/histori lama. Sejak Sprint7 baseline Alembic mengelola schema lintas backend. Semua perubahan master/override dan assignment otomatis mengambil lock transaksi yang sama: advisory lock pada PostgreSQL, `BEGIN IMMEDIATE` pada SQLite, sehingga perubahan kapasitas/aktif dan assignment concurrent terserialisasi.

**57 tes backend dan 53 tes Flutter lulus**, analyze bersih dan build web berhasil. Detail Chrome desktop/bingkai web 390 × 844, bukti transaksi, restart dan pemulihan database utama ada pada [PROGRESS.md](PROGRESS.md). Pengujian ponsel ini bukan build Android/iOS atau keyboard perangkat fisik.

Helper UAT: `.venv\Scripts\python.exe scripts/prepare-master-uat.py --database runtime/master-uat-baru.db`. Script membuat backup baru dan prasyarat workflow sintetis, menolak database yang sudah ada. Gunakan `DATABASE_PATH` ke salinan selama UAT dan kembalikan ke `runtime/assignment.db` setelah selesai.

Untuk release lokal gunakan `.venv\Scripts\python.exe scripts/serve-web.py`. Server hanya bind loopback dan memakai `no-store` serta mengirim ulang aset meskipun klien membawa validator tanggal lama. Ini menghindari Chrome memakai build sprint sebelumnya setelah file build diganti; bukan konfigurasi deployment produksi.

Belum diimplementasikan: editor aturan skor/ambang/SLA, bulk import master, reset password/admin akun lengkap, model ML, notifikasi atau build native. PostgreSQL/SQLAlchemy Core/Alembic sudah dituntaskan pada Sprint7; master dan override juga diperiksa ulang melalui browser pada storage tersebut.
