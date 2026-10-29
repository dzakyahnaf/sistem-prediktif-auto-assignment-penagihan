> Kondisi Sprint13: head **0006_hardening**,31tabel. Tambahan setelah baseline: analytics, models, decisions, operations dan login_failures. Catatan tes di bagian Sprint7 di bawah bersifat historis; hasil regresi/backup akhir ada di PROGRESS.md dan penerimaan-dan-serah-terima.md.

# PostgreSQL, SQLAlchemy Core dan Alembic — Sprint 7

Database demo aktif setelah sprint ini adalah **PostgreSQL `assignment_demo` pada 127.0.0.1:15432**. SQLite `runtime/assignment.db` tetap dipertahankan sebagai sumber sebelum cutover. Perubahan pada PostgreSQL setelah cutover tidak disalin balik otomatis ke SQLite.

Pembaruan Sprint 8: head kini **0002_analytics** setelah baseline0001_portable, dengan lima tabel analitik tambahan. Backup/restore terbaru mencakup **18 tabel**. Jumlah regresi terbaru:68 SQLite, 67 PostgreSQL (1tes khusus SQLite dilewati),9 migrasi dan60 Flutter; hasil di bawah yang menyebut Sprint 7 merupakan histori saat cutover. [Panduan analitik](analitik-historis.md) menjelaskan data sintetis yang terpisah dari antrean operasional.

Klaster khusus proyek memakai binary PostgreSQL **18.1** yang sudah terpasang di `C:\Program Files\PostgreSQL\18\bin`, data `runtime/postgres-local-data`, autentikasi SCRAM dan bind loopback. Service PostgreSQL pengguna di port 5433 tidak diubah. Port awal 55432 termasuk rentang cadangan Windows; 15432 dipilih setelah bind probe berhasil. Docker tidak diperlukan.

## Menjalankan

Dari root proyek, instal dependensi pada venv yang sudah ada bila belum tersedia:

```powershell
uv pip install --python .venv/Scripts/python.exe -r backend/requirements.txt
.venv/Scripts/python.exe scripts/postgres-local.py status
# Jika klaster proyek belum berjalan:
.venv/Scripts/python.exe scripts/postgres-local.py start
.\scripts\start-backend.ps1
# Terminal lain, jika web belum berjalan:
.venv/Scripts/python.exe scripts/serve-web.py
```

`init` hanya untuk mesin/proyek yang belum memiliki klaster/config: `.venv/Scripts/python.exe scripts/postgres-local.py init`. Perintah menolak path yang sudah ada. Password acak admin dan aplikasi disimpan hanya di `runtime/postgres-local.json`, yang diabaikan Git. Role aplikasi bukan superuser dan tidak dapat membuat role/database, tetapi memiliki database proyek untuk migrasi lokal. `provision` dapat melanjutkan pembuatan role/database setelah init terputus; tidak mengubah password role yang sudah ada. Jangan memasukkan config, dump, atau isi runtime ke repository.

`start-backend.ps1` memakai urutan: pilihan eksplisit SQLite, `DATABASE_URL` dari environment, `DATABASE_PATH` eksplisit, kemudian config lokal jika `active_backend=postgresql`, lalu SQLite default. Pilihan `-DatabaseMode PostgreSQL` memakai URL environment atau config lokal. Jangan memakai URL UAT untuk demo utama. Kredensial tidak dicetak oleh script proyek; URL environment tidak perlu ditulis langsung di command history, dapat dibaca dari config lokal.

Health check `http://127.0.0.1:8000/api/health` benar-benar memeriksa koneksi dan mengembalikan `storage: postgresql`; ketika penyimpanan tidak terhubung, mengembalikan 503. UI tetap di port 5173 dan akun demo tetap sama. Semua pembayaran/pencairan masih simulasi; skor tetap rules-demo-v1.

## Lapisan penyimpanan

- `app/tables.py`: SQLAlchemy Core metadata, foreign key, unique/check constraints dan indeks. Tidak menggunakan ORM; layanan yang sudah ada memakai SQL berparameter melalui adapter `db_sa.py`. Placeholder di luar literal dikonversi menjadi named binds, tanpa interpolasi nilai pengguna. `LIKE` menjadi `ILIKE` pada PostgreSQL untuk pencarian yang tidak peka kapital. Boolean domain disimpan sebagai integer 0/1 sesuai kontrak lama.
- `app/db.py`: persistence API publik; engine/pool SQLAlchemy untuk kedua backend. SQLite memakai NullPool dan foreign keys, sehingga file tes dapat ditutup tanpa handle tertahan. `sqlite_legacy.py` hanya mengadopsi skema file lama sampai v3 sebelum baseline Alembic; operasi layanan selanjutnya melalui SQLAlchemy.
- Timestamp UTC tetap berupa ISO string dengan format API lama; uang tetap integer rupiah. JSON audit/preview tetap text dan workbook BLOB menjadi BYTEA. Ini pilihan kompatibilitas yang diuji, bukan konversi seluruh field menjadi tipe native PostgreSQL.
- `migrations/versions/0001_portable.py` dan snapshot metadata beku `migrations/schema_0001.py`: baseline schema dengan revision **0001_portable**. File SQLite lama diadopsi tanpa menghapus data. `alembic_version` menjadi sumber versi lintas database; PRAGMA user_version=3 tetap metadata legacy SQLite. Jangan mengubah snapshot baseline untuk fitur berikutnya: tambahkan revision baru.
- Alembic dijalankan saat startup melalui connection yang sama dengan transaksi migrasi. Guard proses dan advisory lock database mencegah startup upgrade bersamaan. CLI juga tersedia: dari `backend`, setelah `DATABASE_URL` diset, `.venv` interpreter absolut → `-m alembic upgrade head`. `alembic.ini` tidak menyimpan URL/password.
- Downgrade baseline yang menghapus seluruh data sengaja ditolak. Pemulihan menggunakan backup ke target terpisah, bukan drop tabel demo.

Mutasi memakai **transaction-level advisory lock** yang sama untuk semua penulis aplikasi dan isolasi READ COMMITTED. Setelah lock diperoleh, query berikutnya melihat penulis sebelumnya. Ini mempertahankan semantik single-writer prototype: pemeriksaan kapasitas, pembayaran/idempotency, perubahan master, import dan assignment/reassign tetap atomik. Lock timeout 15 detik, statement timeout 60 detik; ini bukan klaim throughput produksi. Penulis langsung melalui SQL di luar aplikasi harus mengikuti kontrak lock yang sama. Pembacaan memakai transaksi REPEATABLE READ/READ ONLY agar total, daftar, agregat dan laporan berada pada snapshot konsisten. Pool memakai pre-ping untuk reconnect setelah restart.

Rujukan implementasi: [SQLAlchemy 2.0 connections](https://docs.sqlalchemy.org/en/20/core/connections.html), [Alembic connection sharing](https://alembic.sqlalchemy.org/en/latest/cookbook.html#connection-sharing), dan [PostgreSQL transaction/advisory locks](https://www.postgresql.org/docs/18/explicit-locking.html).

## Migrasi data

Target harus kosong; migrasi tidak melakukan merge atau menimpa database yang sudah berisi data. `assignment_demo` untuk salinan utama, `assignment_uat_s7` untuk UAT. Kredensial diambil dari config lokal atau `DATABASE_URL` eksplisit.

```powershell
.venv/Scripts/python.exe scripts/migrate-postgres.py --activate --report runtime/migrasi-baru.json
# Untuk salinan UAT baru pada target kosong:
.venv/Scripts/python.exe scripts/migrate-postgres.py --source runtime/salinan.db --target uat --report runtime/migrasi-uat-baru.json
```

Script membuka sumber SQLite read-only, membuat backup SQLite konsisten dengan nama baru di `runtime/backups`, mengadopsi schema hanya pada backup, dan memeriksa foreign keys. Seluruh tabel bisnis (termasuk hash password, ID, versi, histori siklus/aktivitas, audit, binary draft impor dan kunci override) disalin dalam satu transaksi PostgreSQL. Jumlah dan SHA-256 isi ternormalisasi dibandingkan sebelum commit. Sequence assignment/aktivitas/audit disetel di atas ID maksimum atau counter SQLite sebelumnya, mana yang lebih besar.

`--activate` menyetel `active_backend=postgresql` pada config lokal hanya setelah copy/receipt terverifikasi dan report tersimpan. Opsi ini menolak target UAT atau URL selain demo lokal; tidak mengubah backend yang sudah berjalan. Hentikan backend lama, hilangkan override `DATABASE_URL`/`DATABASE_PATH` dari environment, lalu mulai startup default. Tanpa `--activate`, script hanya menyalin/verifikasi. Jika penyimpanan report/config gagal sesudah commit, data copy tetap ada; gunakan report/receipt dan path report baru untuk retry, jangan mengosongkan target.

**Sesi login tidak disalin**: pengguna masuk ulang setelah cutover. Ini bukan kehilangan data bisnis. `upload_order` menggantikan penggunaan rowid SQLite untuk urutan riwayat impor. Receipt migrasi mencatat snapshot sumber; pengulangan snapshot yang sama mengembalikan receipt tanpa menyalin data lagi, termasuk bila target sudah menerima aktivitas setelah import pertama. Receipt adalah bukti saat impor, bukan klaim bahwa kondisi target selamanya sama.

Sejak Sprint 8, receipt versi sebelumnya juga dicocokkan melalui hash isi snapshot sumber asli jika perubahan schema aditif mengubah struktur copy ternormalisasi. Replay sumber Sprint 7 sesudah pembuatan dataset analitik telah diuji: data baru dipertahankan, receipt tetap satu, laporan replay tetap menunjukkan snapshot lama saat cutover. Sumber yang berbeda tetap ditolak pada target yang berisi data.

Kegagalan/konflik/hasil hash berbeda me-rollback semua baris target. Schema Alembic yang sudah dibuat dapat tetap ada dalam keadaan kosong; source/backup tidak dihapus. Tes fault injection membuktikan rollback di tengah copy dan retry berikutnya. Jangan menjalankan cutover saat ada penulisan di aplikasi lama; gunakan jeda pemeliharaan, verifikasi snapshot, baru pindahkan backend.

## Backup dan pemulihan

```powershell
.venv/Scripts/python.exe scripts/backup-postgres.py --output runtime/backups/demo-baru.dump --report runtime/backup-baru.json --verify-restore
```

`pg_dump` memakai exported snapshot yang sama dengan pembandingan tabel. Opsi verify membuat database baru bernama `assignment_restore_s7_<acak>`, menjalankan pg_restore dalam satu transaksi, lalu membandingkan seluruh tabel, termasuk sesi, receipt dan revision. Database lama tidak ditimpa dan hasil restore dipertahankan. Dump mengandung hash password/token; perlakukan sebagai data lokal proyek. Tidak ada enkripsi/rotasi backup produksi pada sprint ini.

Perintah menghentikan/memulai klaster proyek: `scripts/postgres-local.py stop` / `start`. Semua database proyek pada klaster itu ikut berhenti; service PostgreSQL pengguna tetap berjalan. Jangan mematikan klaster saat tes sedang berlangsung.

Fallback SQLite dapat dijalankan melalui `start-backend.ps1 -DatabaseMode SQLite`; `DATABASE_PATH` dapat menunjuk backup/copy yang dipilih. **Fallback bukan sinkronisasi mundur**: perubahan PostgreSQL sesudah cutover tidak ada dalam SQLite lama. Buat dump PostgreSQL dahulu dan tentukan titik pemulihan yang diinginkan. Sesi ini membuktikan fallback API pada backup tanpa menulis ulang SQLite asli, lalu membiarkan demo utama pada PostgreSQL.

## Verifikasi dan batas

```powershell
.\scripts\test-backend.ps1
.venv/Scripts/python.exe scripts/test-postgres.py
.\scripts\test-migration.ps1
.\scripts\test-web.ps1 -FlutterSdk 'C:\flutter' -Offline
```

- SQLite: 57 tes lulus. PostgreSQL: 56 skenario backend lulus; satu tes khusus PRAGMA/drop-column SQLite tetap di suite SQLite. Runner menciptakan schema UUID terisolasi pada UAT dan membersihkan hanya schema yang dibuatnya.
- Delapan tes migrasi lulus: kesamaan data/BLOB/hash/ID, sesi dikosongkan, rollback/ulang, target nonempty ditolak, replay, sequence, head Alembic/no metadata drift/FK, snapshot baca, sumber rusak dan bind/pencarian.
- 53 tes Flutter lulus, analyze bersih dan build web berhasil; tidak ada fitur UI besar baru pada sprint ini. Chrome browser-act desktop dan bingkai web390×844 benar-benar menguji backend PostgreSQL: kasus/assignment, partial→override→pelunasan oleh petugas, pengajuan→dokumen/verifikasi/pencairan, impor XLSX, master, CSV, gangguan/restart dan pemulihan koneksi.
- Demo utama: **148 kasus, 12 petugas, 13 user, 3 wilayah, 5 assignment, 9 aktivitas, 21 audit** cocok sumber. UAT baru tersimpan terpisah; bukti lengkap pada [PROGRESS.md](PROGRESS.md). SQLite asli tetap utuh.
- Migrasi data legacy, SQLAlchemy Core dan transaksi PostgreSQL telah diuji. Belum mencakup high availability, TLS remote, role deployment terpisah untuk migrasi/runtime, row-lock parallel throughput, pengujian beban produksi, monitoring/rotasi backup atau deployment produksi. Tidak memerlukan API key eksternal.
