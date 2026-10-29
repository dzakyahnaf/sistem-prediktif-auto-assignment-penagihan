# Assignment Studio 0.13.0 — paket demo lokal

Ekstrak ZIP ke folder baru. Paket berisi web terkompilasi dan backend, tanpa database workspace, kredensial PostgreSQL, sesi atau hasil UAT. Startup pertama membuat 144 kasus sintetis/12 petugas/13 akun pada `runtime/demo.db` milik folder ini. Startup berikutnya mempertahankan data. Jangan menimpa folder demo lama ketika memperbarui paket; backup data dahulu.

Pada mesin baru, sediakan Python 3.12 dan instal dependensi. Perintah `py` berikut hanya untuk mesin baru yang memiliki Python launcher:

```powershell
py -3.12 -m venv .venv
.venv\Scripts\python.exe -m pip install -r backend/requirements.txt
.\START-DEMO.ps1 -PythonExe "$PWD\.venv\Scripts\python.exe"
```

Di workspace pengembang, parameter PythonExe dapat menunjuk interpreter `.venv\Scripts\python.exe` yang sudah tersedia dengan path absolut. Tidak perlu Flutter SDK untuk menjalankan paket. Python dan paket dependensinya tidak dibundel; instalasi awal memerlukan internet atau wheel cache.

Buka **http://127.0.0.1:8080**. API `/api/health` dan UI memakai origin yang sama. Login `supervisor` atau `smg-col-a` / `smg-ori-a`; password `DemoAssignment!2026`. Hentikan dengan Ctrl+C. Port dapat diubah melalui `-Port`; semua akses tetap loopback. Lima login gagal untuk kombinasi asal/username atau 30 kegagalan per asal dalam15menit memicu429 hingga jendela berakhir. Restart tidak menghapus batas ini. Tidak memakai header proxy sebagai identitas asal.

Mulai dari Ringkasan→Penagihan/Pengajuan→Kasus baru→Tugaskan→Catat aktivitas. Pembayaran sebagian belum sukses; penuh maksimal72jam sejak assignment sukses. Pengajuan memerlukan dokumen→verifikasi→pencairan simulasi. Coba Penugasan ulang untuk melihat histori siklus. Supervisor mengelola master, impor XLSX, laporan, model/segmen, kebijakan serta Operasi & notifikasi. Petugas melihat scope sendiri. Job telephony/omnichannel sepenuhnya tiruan; jalankan Proses job siap dan Pindai SLA secara manual.

Model/dataset analitik workspace tidak dibawa; buat simulator dari menu Analitik historis bila diperlukan. Semua angka sintetis, bukan validasi kredit nyata. Publikasi model tetap memerlukan review manual. Panduan lengkap modul ada pada folder `docs` paket.

Backup SQLite: hentikan demo dahulu, salin `runtime/demo.db` ke lokasi aman dengan nama baru, kemudian mulai kembali. Restore dengan demo berhenti ke folder paket baru yang kompatibel, salin sebagai `runtime/demo.db` sebelum startup. Jangan menggunakan file SQLite workspace lama sebagai pengganti database PostgreSQL aktif.

`run-demo.py --check` memverifikasi manifest SHA256 sebelum startup. Manifest merupakan pemeriksaan integritas, bukan tanda tangan rilis. Paket ini demo lokal, belum deployment publik, belum signing store/operasi produksi. Android APK terpisah ditujukan emulator host10.0.2.2:8000; iOS belum dibuild/diuji karena membutuhkan macOS/Xcode.
