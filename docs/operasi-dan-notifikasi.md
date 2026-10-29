# Operasi, inbox dan akun — Sprint 12

Ringkasan → Operasi & notifikasi tersedia untuk semua akun. Petugas mendapat Inbox dan Integrasi dalam scope kasus saat ini; supervisor juga mengakses Akun petugas dan kontrol proses batch. Inbox hanya milik akun yang masuk, dengan filter belum dibaca, pagination25 dan aksi tandai dibaca idempoten. Notifikasi assignment dibuat atomik dengan assignment. Notifikasi lama tetap ada setelah pengalihan, tetapi tautan kasus dinonaktifkan bila scope berubah; isi generik tidak memuat alias/nilai tagihan.

Supervisor menekan Pindai SLA untuk membuat satu pengingat per kasus/siklus yang aktif melewati due_at tindak lanjut. Memindai kembali tidak menggandakan pengingat atau mengakhiri siklus. Ini proses eksplisit, bukan scheduler push/background. Tidak membuat notifikasi historis palsu untuk assignment sebelum modul tersedia.

## Integrasi simulasi

Pada detail kasus aktif, Tindak lanjut simulasi membuat job telephony/omnichannel lokal setelah review. Petugas hanya dapat memakai skenario berhasil; supervisor dapat memilih gagal sekali atau selalu gagal. Tidak menerima nomor telepon, alamat pesan, atau token vendor. Tidak ada request eksternal dan tidak otomatis menambah aktivitas kontak, transaksi, pembayaran atau pencairan.

Proses job siap memproses maksimal20 (API50) job yang available_at-nya sudah tiba. Transaksi menyimpan hasil percobaan, notification, audit, receipt dan request key bersama. Skenario gagal memakai backoff15/30/60/dst, maksimal300detik; setelah3percobaan menjadi dead. Supervisor dapat meninjau pemulihan, memilih skenario dan alasan, lalu menjadwalkan ulang job yang sama dengan tambahan3kesempatan. Nomor/histori percobaan tidak direset. Receipt `MOCK-JOB-...` unik dan hanya bukti adapter lokal. Ini tidak menjamin exactly-once pada vendor nyata yang belum diintegrasikan.

Sebelum adapter, worker memeriksa kasus belum terminal, siklus masih sama dan akun terkait aktif. Job lama dibatalkan jika scope/siklus/akun sudah berubah. Retry tidak dapat mengirim ulang job delivered/canceled. Enqueue, proses batch dan recovery memakai request key; replay payload sama tidak menggandakan efek, payload berbeda ditolak. UI mengunci payload bila hasil ambigu. Semua job persisten; tidak ada layanan worker eksternal atau API key yang diperlukan.

## Akun petugas

Supervisor dapat menonaktifkan/mengaktifkan login dan mereset password petugas (minimal12karakter), dengan reason, expected version, review dan request key. Reset/nonaktif mencabut sesi; login nonaktif juga diperiksa server pada setiap request. Akun nonaktif tidak memenuhi kandidat assignment/override. Tugas lama dan status master profil tidak diubah; supervisor masih dapat mengalihkan/menangani tugas. Status master nonaktif sendiri tetap hanya menghentikan penerimaan assignment, sesuai keputusanSprint6.

Password tidak ditampilkan dalam review/audit atau JSON idempotency payload. Penyimpanan hash password memakai helper keamanan yang sama; replay reset diverifikasi terhadap hash privat yang disimpan, termasuk bila password pernah berubah lagi. UI hanya menyimpan payload ambigu dalam memori dialog. Akun supervisor tidak diedit lewat endpoint ini; pembuatan akun petugas tetap atomik dengan master. Administrasi identitas produksi/SSO dan distribusi password bukan hasil modul ini.

## API dan schema

- GET /api/notifications?unread=false&offset=0&limit=25; PATCH /api/notifications/{id}/read, milik akun sendiri.
- POST /api/notifications/scan, supervisor, request_key.
- POST /api/cases/{id}/integrations, scope kasus, expected_version/channel/scenario/request_key.
- GET /api/integrations, pagination dan scope kasus saat ini.
- POST /api/integrations/process, supervisor, limit/request_key.
- POST /api/integrations/{id}/retry, supervisor, expected_version/scenario/reason/request_key.
- GET /api/accounts dan PATCH /api/accounts/{id}, supervisor, active/new_password opsional/expected_version/reason/request_key.

Alembic0005_operations menambah notifications, integration_jobs, integration_attempts, operation_requests dan user_controls. User/kasus lama tidak ditulis ulang; kontrol akun default aktif/revisi0 bila belum ada record. Semua endpoint no-store. Pengujian mencakup scope, revocation, idempotency/concurrency, backoff/dead-letter, pembatalan siklus dan rollback jika audit gagal.
