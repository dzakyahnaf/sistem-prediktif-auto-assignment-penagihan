# Laporan operasional — Sprint 4

Menu ini khusus supervisor. Dua tampilan melaporkan kondisi operasional sintetis, bukan hasil model ML atau keputusan kredit. Endpoint preview dan ekspor memakai autentikasi/otorisasi yang sama; respons API memakai `Cache-Control: no-store`.

## Portofolio kasus

Satu baris per kasus, termasuk yang belum ditugaskan. Filter tanggal memakai `cases.created_at`. Status, petugas, jumlah siklus, dan saldo adalah kondisi saat laporan diambil, bukan rekonstruksi kondisi pada akhir tanggal filter.

Realisasi penagihan adalah total pembayaran tercatat. Realisasi pengajuan adalah pencairan simulasi. Sisa nominal adalah `amount - paid`; untuk pengajuan, nominal tanpa pencairan termasuk yang ditolak dan bukan nilai kredit yang disetujui. Kasus ditolak dihitung terpisah dari lunas/dicairkan dan kasus aktif.

## Histori siklus assignment

Satu baris per record assignment. Filter petugas memakai petugas pada assignment tersebut, sehingga siklus lama tetap masuk meskipun kasus sekarang dikerjakan petugas lain. Filter tanggal memakai `assignments.assigned_at`.

Realisasi dihitung dari aktivitas `payment`/`disburse` milik assignment itu. Kasus dengan pembayaran Rp200.000 pada siklus 1 lalu Rp800.000 pada siklus 2 menghasilkan realisasi Rp1.000.000, bukan Rp2.000.000. Aktivitas setelah tanggal akhir filter tetap ikut dihitung bila milik siklus yang awalnya berada di dalam rentang: ini laporan kohort assignment, bukan laporan arus transaksi dalam periode.

- `success`, `no_success`, dan `superseded` berasal dari outcome yang tersimpan.
- `active` berarti assignment belum ditutup; `overdue` menyaring active dengan `due_at` lebih kecil daripada waktu laporan. Tepat pada batas SLA belum terlambat.
- Pelunasan penagihan setelah 72 jam tetap lunas pada status kasus, dengan outcome siklus `no_success`.
- Persentase hasil final memakai `success / (success + no_success)`. Active dan superseded dikeluarkan; penyebut nol menghasilkan `null`/Belum ada hasil. Angka mengikuti filter yang diterapkan, termasuk bila hasil tertentu saja dipilih.
- Status kasus, nama nasabah demo, nama petugas, dan tim yang ditampilkan dibaca dari data/master saat ini. Skor siklus berasal dari assignment, bukan skor kasus yang berubah saat reassign. Ini belum merupakan rekonstruksi seluruh atribut historis master.

## Filter dan API

`GET /api/reports` dan `GET /api/reports/export` menerima:

- `kind`: `collection` atau `origination`, wajib.
- `view`: `cases` (default) atau `cycles`.
- `date_from`, `date_to`: tanggal ISO `YYYY-MM-DD`, opsional. Awal inklusif pukul 00:00 WIB; akhir inklusif sampai sebelum pukul 00:00 hari berikutnya. Backend mengonversi batas ke UTC. UI menerima tahun 1900–2100. Rentang terbalik atau tanggal tidak valid ditolak.
- `region_id`, `agent_id`: wilayah/petugas yang dikenal, harus sesuai alur dan wilayah. `agent_id=unassigned` hanya tersedia untuk portofolio.
- `status`: status kasus yang sesuai alur, atau hasil siklus `active`, `overdue`, `success`, `no_success`, `superseded`. Kombinasi yang tidak sesuai ditolak.
- `q`: substring literal ID/nama, maksimal 100 karakter. Persen, underscore, dan backslash tidak berfungsi sebagai wildcard SQL.
- Preview saja: `offset` >= 0, `limit` 1–200 (default 25). Ringkasan dan `by_agent` menghitung seluruh hasil, bukan halaman aktif. Urutan stabil: tanggal menurun lalu ID. Ekspor mengabaikan pagination dan menyertakan seluruh hasil filter.

Preview membaca snapshot SQLite yang konsisten. Ekspor membuka transaksi tersendiri dan menghitung data terbaru dengan filter yang sama; karena itu isi CSV dapat berbeda dari preview bila ada aktivitas baru. UI memberitahukan hal ini sebelum unduh. Ekspor berhasil mencatat actor, seluruh filter, jumlah baris, dan waktu ke audit `export_report` dalam transaksi yang sama. Audit berarti berkas dibuat server, bukan bukti pengguna menyimpan/membukanya di disk; kegagalan jaringan setelah commit dapat meninggalkan audit tanpa unduhan berhasil.

## CSV dan unduhan web

Berkas menggunakan UTF-8 BOM, quoting CSV standar, dan penetralan formula pada teks yang berawalan `=`, `+`, `-`, `@` setelah whitespace, serta tab/CR/LF di awal. Nominal rupiah berupa integer. Timestamp dalam CSV memakai ISO UTC; `date_from_wib` dan `date_to_wib` merekam filter tanggal WIB. Baris juga memuat `generated_at` dan `date_basis`. Hasil kosong tetap menghasilkan header kolom.

Frontend mengambil byte melalui request autentikasi dengan token di header, memeriksa MIME CSV, lalu meminta browser mengunduh Blob. Object URL dilepas setelah unduhan sempat dimulai. Respons terlambat dari sesi lama ditolak; HTTP 401 membersihkan sesi dan route/dialog. HTTP 403, validasi, atau kegagalan jaringan tidak mengeluarkan pengguna secara otomatis. Perubahan filter menyembunyikan hasil lama sampai Tampilkan laporan ditekan; Reset mengembalikan seluruh filter ke default.

## Batas implementasi

SQLite dan agregasi/CSV masih memuat seluruh hasil di memori server untuk prototype. Belum ada job ekspor latar belakang, batas volume produksi, berkas snapshot yang disimpan, laporan periode berdasarkan waktu transaksi, atau ekspor Excel/PDF. Preview dibatasi pagination, tetapi ukuran data yang diolah untuk ringkasan/ekspor belum dipaginasi secara internal. Unduhan native Android/iOS belum diimplementasikan; verifikasi ponsel memakai Flutter web pada bingkai 390 × 844.
