# Impor Excel operasional — Sprint 5

Supervisor membuka antrean **Penagihan** atau **Pengajuan → Impor Excel**. Impor membuat kasus baru yang memakai scoring dan workflow yang sama dengan formulir manual. Data, identitas, pembayaran, dan pencairan prototype tetap sintetis. Skor `rules-demo-v1` adalah indeks prioritas simulasi, bukan probabilitas ML.

## Alur penggunaan

1. Pilih alur, lalu **Unduh template operasional**. Workbook memiliki worksheet `Data` dengan header saja dan `Petunjuk` berisi aturan/contoh. Isi mulai baris 2. Template pengumpulan kebutuhan dalam `brief-awal/` tidak ditimpa atau dianggap langsung siap impor.
2. Pilih berkas `.xlsx`. Satu batch untuk satu alur. Pilih worksheet dan baris header 1–20; klik **Muat kolom** setelah mengubahnya. Pemetaan otomatis hanya saran; field wajib bertanda `*`, satu kolom tidak boleh dipakai dua field.
3. Klik **Preview & validasi**. Ringkasan menghitung seluruh baris, dengan rincian 25 per halaman. Preview belum membuat kasus. Satu kesalahan pada halaman mana pun memblokir seluruh batch; perbaiki berkas/pemetaan lalu preview ulang.
4. Tinjau kolom yang diabaikan dan setujui checkbox jika ada. Perubahan pemetaan membatalkan preview pada UI. Klik **Impor N kasus**, tinjau file, alur, sheet, header, nominal dan jumlah kolom yang diabaikan, lalu **Impor sekarang**. Batal mempertahankan preview.
5. Hasil menyimpan pasangan referensi sumber → ID kasus baru. **Lihat antrean** menyegarkan antrean dan menghapus filter/pilihan lama. **Buka kasus** dapat meneruskan assignment, aktivitas, pembayaran atau pencairan simulasi.

Draft, pemetaan preview, dan hasil commit disimpan di database aktif (PostgreSQL sejak Sprint7; SQLite tetap didukung). **Riwayat impor saya** menampilkan 20 batch terbaru milik akun tersebut. Draft berlaku 24 jam; maksimal 10 draft aktif per pemilik. **Buang draft** melepas workbook/preview tanpa menghapus kasus atau berkas di komputer. Batch yang sudah committed tidak kedaluwarsa dan tidak dapat dihapus melalui tindakan draft.

Jika hasil commit belum pasti karena koneksi/HTTP 5xx, UI mengunci tindakan lain dan menyediakan **Periksa status commit** pada batch yang sama. Jangan membuat batch baru untuk mencoba ulang commit. Server mengembalikan hasil yang sama untuk retry batch/revisi yang sama tanpa kasus atau audit commit tambahan.

## Kolom dan validasi

Field umum:

- `source_ref`: wajib **teks**, unik per alur tanpa membedakan huruf besar/kecil; 1–80 karakter ASCII, dimulai huruf/angka, sisanya huruf/angka atau `_ . : / -`. Simpan sebagai teks agar nol awal terjaga. ID yang sama boleh digunakan sekali pada masing-masing alur. Deduplikasi hanya berdasarkan referensi impor, bukan nama, nomor telepon, atau kemiripan kasus manual/seed.
- `customer`: alias sintetis 2–100 karakter.
- `region_id`: kode/nama wilayah terdaftar, misalnya `SMG` atau `Semarang`.
- `difficulty`: `Low`, `Medium`, `High`. Low selalu Tim A, High selalu Tim B; hanya Medium mengikuti skor dengan ambang demo 60.
- `amount`: rupiah bulat lebih dari 0 sampai 1.000.000.000. Gunakan angka Excel atau teks digit tanpa `Rp`, titik, koma atau desimal pecahan. Ini tagihan penuh/nominal pengajuan.

Penagihan: `dpd` opsional, bilangan bulat 0–3650; kosong/tidak dipetakan menjadi 0.

Pengajuan: `income` wajib rupiah bulat positif sampai satu miliar, `interest` wajib bilangan bulat 1–5, `documents_complete` opsional `Ya/Tidak`, `true/false`, atau `1/0`; kosong menjadi Tidak. Dokumen lengkap bukan persetujuan kredit; verifikasi dan pencairan tetap tindakan workflow.

Formula dan error Excel pada worksheet terpilih ditolak, termasuk kolom yang tidak dipetakan. Formula tidak dihitung atau dibaca dari cached result. Kolom hasil kontak, pembayaran, outcome, petugas, dan target historis tidak menjadi prediktor awal. Impor tidak memperbarui kasus lama, tidak mengimpor histori/aktivitas/master, tidak mencatat transaksi, dan tidak menjalankan assignment otomatis.

## Batas berkas dan transaksi

- Format `.xlsx` saja: maksimal 5 MiB, 20 worksheet, 64 kolom, dan 2.000 baris data setelah header. Pembatas pemeriksaan berkas menolak cell di luar baris 2.020, 200.000 cell terisi, ZIP lebih dari 2.000 entri atau 30 MiB setelah dekompresi. Tidak ada pemotongan baris diam-diam.
- Berkas rusak, terenkripsi, makro, embedded objects, dan external links ditolak. XML menggunakan defusedxml; ZIP tidak diekstrak ke filesystem. Parser openpyxl berjalan read-only; CPU parsing unggahan dijalankan di threadpool.
- Seluruh kasus, referensi dan audit commit disimpan dalam satu `BEGIN IMMEDIATE`. Konflik deduplikasi/wilayah/validasi saat commit membatalkan seluruh batch, termasuk baris awal yang sempat diproses dalam transaksi. Jalankan preview ulang setelah konflik.
- Commit memakai revisi preview tersimpan; payload klien tidak memasok ulang data kasus. Referensi dicek lagi saat commit. Aturan/model versi preview harus masih sesuai. SHA-256 workbook disimpan untuk audit, bukan dijadikan kunci deduplikasi file.
- Setelah commit, binary workbook dilepas; metadata, preview dan hasil tetap tersimpan. Binary draft kedaluwarsa dibersihkan saat unggahan berikutnya. Tidak ada scheduler retensi atau pengarsipan produksi pada sprint ini.

## API dan penyimpanan

Semua endpoint membutuhkan token supervisor. Batch juga dibatasi pemiliknya; petugas ditolak 403 dan supervisor lain tidak dapat membaca batch tersebut. Respons tetap `Cache-Control: no-store`. HTTP 401 menghapus sesi/rute/dialog Flutter; 403/422/error jaringan mempertahankan sesi. Unduhan tidak memasukkan token ke URL.

- `GET /api/imports/template?kind=collection|origination`: workbook operasional.
- `POST /api/imports/upload?kind=...&filename=...`: body binary XLSX, bukan JSON/multipart; mengembalikan 201 dan ID batch.
- `GET /api/imports`: riwayat pemilik; `GET /api/imports/{id}?offset=0&limit=25`: preview/hasil berpaginasi (maks. 200/request).
- `GET /api/imports/{id}/layout?sheet=Data&header_row=1`: kolom, spesifikasi field dan saran pemetaan.
- `POST /api/imports/{id}/preview`: `{ "sheet": "Data", "header_row": 1, "mapping": { "source_ref": 1, "customer": 2, "region_id": 3, "difficulty": 4, "amount": 5, "dpd": 6 } }`. Indeks kolom dimulai dari 1.
- `POST /api/imports/{id}/commit`: `{ "expected_revision": 1, "acknowledge_ignored": false }`.
- `POST /api/imports/{id}/discard`: membuang draft, bukan kasus hasil impor.

Migrasi impor Sprint5 menaikkan SQLite `user_version` menjadi2 dan menambahkan `import_batches`, `import_case_refs`, serta indeks; Sprint6 menjadi legacyv3. Sejak Sprint7 schema lintas backend dikelola Alembic0001_portable; `upload_order` mempertahankan urutan batch tanpa rowid khusus SQLite. Kontrak impor tetap berlaku. Wilayah nonaktif tidak diterima pada preview/commit atau template, dan status diperiksa lagi saat commit. Kasus impor ditandai `source=excel-operational`; mapping referensi mempunyai unique key `(kind, source_key)`. Audit mencatat upload, preview, discard, tiap kasus dan commit batch beserta actor, ID batch, jumlah baris atau referensi file sesuai jenis tindakannya. Definisi audit persis dapat diperiksa pada `backend/app/imports.py`.

Runtime baru memerlukan `openpyxl==3.1.5` dan `defusedxml==0.7.1` dari `backend/requirements.txt`. Tidak membutuhkan API key atau layanan eksternal. Picker/unduhan baru diuji pada Flutter web. Runner serta picker native Android/iOS belum diimplementasikan.

## Bukti pengujian

Pada Sprint5: **47 tes backend dan45 tes Flutter lulus**, analyze bersih dan build web berhasil. Tes mencakup commit2.000baris, rollback konflik batch lain, concurrent retry, revisi, pembatasan role/pemilik, kedaluwarsa, discard, restart, pemetaan/header, formula/numerik, pagination, respons lintas sesi serta hasil commit ambigu. Suite impor telah dijalankan ulang pada PostgreSQL dalam regresi Sprint7, disertai upload/preview/commit browser dua kasus. Hasil terbaru seluruh suite dan UAT Chrome desktop/bingkai web390×844 berada pada [PROGRESS.md](PROGRESS.md).

Helper `.venv\Scripts\python.exe scripts/prepare-imports-uat.py --database runtime/imports-uat-baru.db --fixtures runtime/import-fixtures-baru` membuat backup SQLite dan fixture sintetis, menolak path yang sudah ada. Helper ini membaca snapshot sebelum cutover, bukan perubahan PostgreSQL terbaru. Untuk UAT SQLite, arahkan `DATABASE_PATH` ke salinan itu dan gunakan startup modeSQLite eksplisit. Setelah selesai hapus override environment dan mulai startup default untuk kembali ke demo PostgreSQL. Jangan menghapus database lama untuk menyiapkan UAT. UAT PostgreSQL mengikuti [runbook](postgresql.md).
