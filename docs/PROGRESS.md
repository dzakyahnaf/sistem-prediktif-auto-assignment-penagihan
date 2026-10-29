# Progres dan urutan sesi

## Perbaikan keamanan dan persiapan deploy Render + Neon — 29 Oktober 2026

Instruksi pengguna sesudah review: perbaiki tiga temuan lalu deploy Render+Neon. Otomasi website **hanya Browser Use pada Chrome pribadi**, tanpa browser-act/kontrol desktop. Percobaan Browser Use terbaru `getTab(...,browser:'chrome')` mengembalikan **The browser access host is unavailable**. Langkah koneksi resmi sudah diberikan: aplikasi desktop Settings → Computer Use → Chrome berstatusManage/toggleaktif, ekstensi pada profil yang benar, pilih@Chrome/tab dari menu@; restart atau chat desktop baru bila kondisi sesi tidak pulih. Tidak meminta ulang allowlist/Full access tanpa bukti penolakan origin baru.

Implementasi:

- FastAPI0.162.0/Starlette1.10.0,AnyIO4.15.1,certifi2026.10.23,idna3.20. Requirements universal Python3.12 beserta35dependency dikunci denganSHA256, sumberversi `backend/requirements.in`. QueryOSV environment baru **0temuan** (`runtime/cloud-dependency-audit.json`). `.venv` lama tidak ditimpa; tes memakai `runtime/cloud-venv`, terisolasi dari server demo utama.
- Mode cloud wajib DATABASE_URL PostgreSQL denganTLS dan ADMIN_PASSWORD privat≥20karakter. Provisioning mengganti hash owner/mencabut sesinya ketika secret berubah; password seed petugas yang masih publik diacak. Role pengunjung `demo` hanya baca dashboard/antrean/detail; mutasi dan endpoint administrasi ditolak API. Benturan identitasviewer membatalkan transaksi perubahan akun. Secret tidak dibundel keFlutter/Git/log. Default demo lokal tetap tersedia.
- Flutter PUBLIC_DEMO=true memilih loginpengunjung/labelaksesbaca. Tombol aktivitas/integrasi dan kontrol supervisor disembunyikan untukviewer; penjagaan API tetap utama. Cloud memakai same-originAPI_URLkosong, CORSdefaultkosong. ResolverforwardedIP hanya mempercayaiCIDR eksplisit, menelusurikanan, menolakwildcard. Jaringaningress Render masih perlu dikonfirmasi saatdeploy.
- Docker multi-stageFlutter3.41.6+Python3.12/nonroot, bind0.0.0.0:$PORT/satuworker/asetlokal/threadnumerik1. Buildcontextallowlist mengecualikanruntime/data/secret/brief. render.yaml Free/Singapore, .env.example tanpa defaultadminsecret, gitignore .env.*. CI Linux menjalankan backend, Flutter dan build/smokeimage tanpa secretcloud. Panduan [deploy](deploy-render-neon.md).

Verifikasi aktual sebelumpush: **111tesSQLite lulus**147,927detik; **111tesPG,110lulus/1khususSQLite dilewati**328,617detik; **9tesmigrasilulus**30,978detik. Tambahan5tes konfigurasi/role/scope/rotasisesi/proxy/benturanakun dijalankan padaSQLite danPG. **95tesFlutterlulus**, analyzebersih, buildwebpublik/sameoriginberhasil46,4detik. Pythoncompilelulus. Starlette memberi peringatan deprecasi testclienthttpx, tes tetap lulus; tree-shaking memberi peringatan fontCupertino lama. Bukan hasil UAT browsercloud. Semua fingerprint bisnis utama danSQLiteoriginal tetap sama denganbaseline. Environmentuji dansecretprivat tersimpan hanya diruntime yang diabaikanGit.

Belum terverifikasi: build/smoke DockerLinux diCI, provisioningprojectNeonFree, serviceRenderFree, TLS/koneksiNeonlangsung, konfigurasiingress, UATdesktop/ponselURLpublik, persistensiredeploydanprofilRAM512MB. DockerCLI tersedia lokal tetapi daemonLinux belum berjalan; tidak mengoperasikan desktop untuk menyalakannya. Hasil CI/push berikut dicatat setelah benar-benar tersedia. **Belum ada resource cloud baru atau URL live**; fieldnama/region proyek yang sempat diisi tidak disubmit.

## Status terkini — pengerjaan berlanjut hingga Sprint 13 (29 Oktober 2026)

Sprint 9,10,12 selesai; Android/web Sprint 11 selesai dengan gate build/UAT iOS terbuka. Sprint 13 menuntaskan hardening, paket demo lokal, regresi Android/web/PostgreSQL dan panduan serah terima untuk lingkungan yang tersedia. Head schema **0006_hardening**,31 tabel. Proyek belum 100% diterima lintas platform karena iOS belum dibuild/diuji. Bagian di bawah merupakan catatan historis; angka head/tes/batas pada bagian lama bukan kondisi terkini. Rujuk catatan Sprint 13 paling akhir.

Sprint12 telah ditutup: layout390px tab Integrasi utuh ([bukti](evidence/sprint12-final-mobile-integrasi.png)); seluruhdatautama/hashbaseline danSQLiteoriginal tetap identik (`runtime/sprint12-final-check.json`). Main148kasus/5assignment/9aktivitas/26audit,5tabeloperasibaru kosong. Panduan penerimaan: [serah terima](penerimaan-dan-serah-terima.md).

## Sesi 1 — fondasi dua alur (27 Oktober 2026)

Selesai diimplementasikan:

- Pemilihan arsitektur kedua; Flutter/FastAPI; asumsi bisnis terdokumentasi.
- Backend dengan database persisten dan seed operasional 144 kasus, 12 petugas, 3 wilayah.
- Login, token kedaluwarsa/logout, role supervisor/petugas, pembatasan scope kasus.
- CRUD create/read kasus, dashboard dua domain, daftar petugas dan perubahan kapasitas/status melalui API.
- Scoring demo awal dan ulang, assignment atomik, histori siklus, audit, serta pembatasan wilayah/tim/kapasitas.
- Penagihan hingga pembayaran penuh dan pengajuan hingga pencairan simulasi/penolakan.
- Ekspor CSV API, validasi nominal, pencegahan aktivitas ganda, konflik versi.
- Sumber UI Flutter responsif untuk login, dashboard, dua antrean, formulir create, assignment, detail, aktivitas, riwayat, dan daftar petugas.

Verifikasi:

- Backend: **23 pengujian otomatis lulus** (`scripts/test-backend.ps1`), meliputi workflow, akses, kapasitas concurrent, rollback, idempotency pembayaran concurrent, batas tepat 72 jam, batas hari WIB, persistensi setelah restart, CORS, OpenAPI, dan kebocoran waktu fitur.
- Python compile check lulus untuk modul aplikasi dan pengujian.
- Server Uvicorn berhasil berjalan lokal pada port 8000; `/api/health` dan `/openapi.json` merespons melalui HTTP loopback.
- Flutter: belum analyze/build/render. SDK global ditolak akses filesystem; unduh SDK/dependensi via terminal tidak tersedia. Sumber UI masih perlu compile dan review visual sebelum dianggap siap.
- Runner Android/iOS, APK, dan iOS belum dibuat.

Tidak ada data pribadi atau file brief yang diubah. Cache dan virtual environment merupakan file lokal yang diabaikan `.gitignore`.

## Sesi 2 — jadikan antarmuka siap didemokan

**Status: selesai, 28 Oktober 2026.** Sprint ini mencakup integrasi Flutter web dengan API, workflow browser desktop/ponsel, dan verifikasi data setelah restart backend asli. Riwayat kendala di bawah dipertahankan sebagai catatan sesi; hasil penutupan terbaru ada di akhir bagian ini.

1. Pulihkan akses SDK Flutter, resolve dependency dan simpan lockfile.
2. `flutter analyze`, perbaiki hasil compile, build web, lalu verifikasi browser desktop dan ukuran ponsel.
3. Hubungkan dan uji seluruh alur UI ke API, tangani session expiry di detail dan network retry.

Perubahan dalam sprint ini:

- Sesi Flutter dipusatkan pada API notifier. Pergantian sesi mengganti navigator, sehingga halaman detail/formulir yang terbuka tidak tertinggal setelah token kedaluwarsa.
- Respons dari sesi sebelumnya ditolak berdasarkan revisi sesi; 401 lama tidak mengeluarkan pengguna yang baru masuk. 403/422/kesalahan jaringan tidak disamakan dengan kedaluwarsa sesi.
- Kesalahan JSON/validasi dan mutasi dengan hasil jaringan belum pasti dibedakan. Payload aktivitas yang mungkin sudah tersimpan tetap dikunci untuk retry idempotent.
- Respons API diberi `Cache-Control: no-store`; respons 401 konsisten menyertakan `WWW-Authenticate: Bearer`.
- Script web mendukung SDK di `.tools/flutter` atau `-FlutterSdk`, cache package lokal proyek, serta pemeriksaan berurutan yang berhenti bila gagal.
- SDK global kini dapat diakses pada lingkungan dengan izin filesystem/jaringan yang baru. Flutter 3.41.6 / Dart 3.11.4 dipakai tanpa mengunduh salinan SDK. Dependensi berhasil diunduh dan `pubspec.lock` tersedia.
- Dropdown memakai `initialValue` dan batas lebar sesuai container. Tes layar 390 piksel semula menemukan overflow 40 piksel pada dialog aktivitas; perbaikan `isExpanded` telah lulus regresi.

Verifikasi terbaru:

- **27 tes backend lulus**, termasuk penolakan token kedaluwarsa pada 13 endpoint layar/mutasi, isolasi akun setelah login ulang, logout token lama tanpa menghapus sesi baru, dan header cache.
- Python compile check dan parser PowerShell untuk seluruh script lulus.
- **13 tes Flutter lulus:** 10 tes API client dan 3 variasi widget navigasi pada 390/800/1440 piksel. `flutter analyze` tidak menemukan masalah; `flutter build web` berhasil, termasuk Wasm dry run. Terdapat peringatan build font Cupertino tidak tersedia; ikon aplikasi menggunakan Material.
- Penolakan SDK/eskalasi `sandbox_approval: false` sebelumnya sudah tidak menghalangi eksekusi biasa. Terminal sesi terbaru memakai akses penuh, tanpa permintaan eskalasi. Konfigurasi keamanan pengguna tidak diubah oleh agen.
- Backend dimulai ulang dengan kode sesi terkini; health HTTP 200 dan `Cache-Control: no-store` terverifikasi. Hasil web disajikan pada `http://127.0.0.1:5173` dan merespons HTTP 200.
- **Browser end-to-end belum dijalankan.** Pengguna telah mengizinkan situs Flutter serta kedua alamat lokal 5173/8000. Percobaan terbaru setelah izin pengguna tetap ditolak: `A saved permission or managed policy denies access`. Tidak mencoba browser/port lain untuk menghindari penolakan. Pengaturan situs perlu dibuka di Settings > Computer Use > Chrome > Manage, atau Settings > Browser > Agent permissions sesuai versi aplikasi.
- Pemeriksaan setelah pengguna me-restart aplikasi: Chrome terdeteksi kembali sebagai browser `1`, tetapi pembukaan origin yang sama tetap ditolak sebelum navigasi. Screenshot pengguna menunjukkan default Browsing/Downloads `Always allow` tanpa entri blokir localhost; dugaan daftar blokir belum terbukti. Pencarian terbatas pada konfigurasi TOML yang tersedia tidak menemukan aturan origin/approval yang menjelaskan penolakan. Penyebab belum diketahui; jangan meminta restart berulang atau mengaktifkan Full CDP sebagai solusi. Langkah diagnosis pengguna berikutnya: tambahkan exception Browsing eksplisit untuk origin lokal melalui tombol Add, lalu periksa ulang hanya setelah pengaturan berubah.
- Pembaruan 28 Oktober: kedua exception sudah ditambahkan pengguna dan diverifikasi lewat parser TOML dari file aktual. Browser tetap menolak setelah perubahan tersebut; jangan meminta pengguna menambahkan exception yang sama lagi. Referensi resmi menegaskan `access = "allow"` hanya melanjutkan pemeriksaan normal, bukan menggantikan approval/policy lain. Tidak ada bukti untuk menentukan apakah sumber penolakan adalah izin tersimpan atau managed policy. Server web/API sempat berhenti setelah restart aplikasi; keduanya telah dijalankan kembali pada port yang sama. Verifikasi browser tetap tertunda, tanpa bypass melalui browser/port/alat lain.

Jangan menandai sprint selesai atau melanjutkan ML/mobile sebelum build dan pemeriksaan workflow browser berhasil. Tidak ada API key eksternal yang diperlukan untuk mengatasi kendala ini.

Kriteria selesai: pengguna dapat melakukan dua alur dari login hingga hasil akhir lewat UI, dengan data persisten setelah restart; tidak ada overflow atau tombol mati pada cakupan ini.

### Pemeriksaan langsung 28 Oktober 2026 — sesi lanjutan

Browser biasa berhasil diakses pada sesi lanjutan. Penolakan origin pada sesi lama bukan kondisi permanen; hasil penutupan sprint dicatat di bawah.

Implementasi/perbaikan:

- Browser release menemukan dialog aktivitas kosong dengan `RangeError: max must be in range 0 < max ≤ 2^32, was 0`. Penyebabnya `Random.secure().nextInt(1 << 32)` pada target JavaScript. Batas diubah menjadi literal `4294967296`; dialog dan transaksi kemudian berhasil diverifikasi pada release hasil build baru.
- Ditambahkan `scripts/verify-ui-persistence.py`: mengambil backup SQLite melalui koneksi read-only, menjalankan dua proses Uvicorn secara berurutan pada salinan sementara, lalu membandingkan detail kasus UAT dan dashboard. Database demo asli tidak diubah oleh script.

Bukti pengujian yang sudah selesai pada sesi ini:

- API health dan web HTTP 200; tidak menjalankan instance baru pada port 8000/5173.
- Login supervisor dan `smg-col-a`, pesan password salah, logout/login ulang, dashboard scope petugas, dan menu supervisor yang tidak tampil pada akun petugas terverifikasi melalui UI Chrome.
- UI membuat `TAG-B31E1ABE68` (`UAT S2 Penagihan 2810`, SMG, Low, Rp1.000.000), assignment ke `SMG-col-A`, lalu reassign dengan alasan. Detail menampilkan siklus 1 `Dialihkan` dan siklus 2 `Berjalan`; kapasitas harian menjadi 2, beban aktif tetap 1.
- UI membuat `AJU-E64EB8D3EF` (`UAT S2 Pengajuan Cair 2810`, SMG, Low, Rp5.000.000), assignment antrean terfilter hanya memproses satu kasus dan memilih `SMG-ori-A`.
- UI membuat `AJU-1545417FC4` (`UAT S2 Pengajuan Tolak 2810`, BDG, High, Rp3.000.000), assignment memilih `BDG-ori-B`.
- Validasi formulir pengajuan kosong dan alasan reassign kurang dari 10 karakter tampil melalui UI. Dropdown wilayah/kesulitan dan navigasi desktop berfungsi.
- **27 tes backend lulus kembali** dari interpreter `.venv` sesi ini. Script restart proses lulus dengan exit 0 pada salinan yang berisi ketiga kasus UI di atas; saat pemeriksaan itu aktivitas masih 0 dan status masih assigned.
- Pengguna menjalankan `scripts/test-web.ps1 -FlutterSdk 'C:\flutter' -Offline` dari PowerShell karena akses SDK sesi agen tetap `Access is denied`. Output yang diberikan pengguna: **analyze bersih, 13 tes Flutter lulus, build web berhasil**, Wasm dry run berhasil; peringatan font Cupertino tetap ada. File build lokal juga teramati diperbarui.

Hasil lanjutan workflow release:

- Penagihan dilakukan sebagai `smg-col-a`: kontak, penolakan pembayaran Rp1.200.000 karena melebihi sisa tagihan, pembayaran Rp400.000 (tetap `in_progress`), lalu Rp600.000 (status `paid`, total Rp1.000.000). Detail menampilkan tiga aktivitas, siklus lama `superseded`, siklus kedua `success`, dan tombol aktivitas tidak tersedia lagi sesudah lunas. Dashboard petugas menampilkan 0 aktif, 1 selesai, pembayaran Rp1.000.000.
- Pengajuan dilakukan sebagai `smg-ori-a`: kontak, percobaan verifikasi sebelum dokumen ditolak dengan pesan prasyarat (HTTP 409, sesi tetap aktif), dokumen lengkap, verifikasi, lalu pencairan simulasi Rp5.000.000. Detail `disbursed`, empat aktivitas, outcome `success`; dashboard petugas menampilkan 1 selesai dan pencairan Rp5.000.000.
- Pengajuan penolakan dilakukan sebagai supervisor melalui bingkai ponsel: alasan kosong ditolak validasi; alasan sintetis disimpan. Kasus `rejected`, satu aktivitas, outcome `no_success`, nominal dicairkan Rp0.
- Chrome tetap memakai JavaScript lama setelah reload biasa pada origin root. Release baru disalin ke subpath sementara `/uat-s2-20261028/` pada origin 5173 yang sama, dengan base href yang sesuai. Workflow di atas diuji pada salinan ini; file JS salinan identik dengan hasil build pengguna. Tidak mengganti origin, browser, atau izin keamanan.
- Pengaturan viewport alat sempat menghasilkan screenshot berskala/crop yang tidak sesuai. Pemeriksaan visual kemudian memakai HTML sementara `responsive-check.html` berisi iframe **390 × 844** tanpa override viewport. Login, dashboard, navigasi bawah, antrean/filter, detail, kedua formulir, dropdown aktivitas pengajuan dengan seluruh enam opsi, dialog penolakan, serta formulir dengan pesan validasi diperiksa langsung. Tidak terlihat overflow pada cakupan tersebut. Formulir dibatalkan tanpa membuat data tambahan.
- Script restart proses diulang setelah hasil akhir: **PASS, exit 0**, pada backup read-only database asli. Dua proses Uvicorn mempertahankan 3 kasus, 8 aktivitas, 4 assignment, nominal pembayaran/pencairan, dan dashboard yang identik. Hasil JSON lokal disimpan di `runtime/ui-persistence-result.json` (bukan data seed baru).

Kendala sebelum penutupan:

- Restart **server demo asli** pada port 8000 belum terjadi. Snapshot detail ketiga kasus serta dashboard sudah disimpan di `runtime/ui-before-restart.json`. WMI ditolak; `netstat` kemudian mengidentifikasi listener PID 22180, tetapi `Stop-Process` juga ditolak Windows. Pengguna diminta melakukan restart manual, setelah itu data perlu dibandingkan dan layar dimuat ulang. Jangan menyamakan tes salinan dengan restart server asli.
- Browser-act gagal sebelum navigasi karena penulisan log AppData ditolak; pengujian memakai browser Chrome melalui computer-use. Diagnostik raw CDP tambahan ditolak gerbang izin; tidak dipakai lebih lanjut. Ini berbeda dari akses browser biasa yang berhasil.

### Penutupan Sprint 2 — restart backend asli

- Pada kelanjutan 28 Oktober, listener API/web lama sudah tidak berjalan. Backend asli dijalankan kembali melalui `scripts/start-backend.ps1`, PID **46852**, port **8000**, menggunakan `runtime/assignment.db` yang sama. Server lama sesi sebelumnya adalah PID 22180.
- Detail kasus `TAG-B31E1ABE68`, `AJU-E64EB8D3EF`, dan `AJU-1545417FC4` serta seluruh field dashboard dibandingkan dengan `runtime/ui-before-restart.json`: **identik / PASS**. Terjaga: 3 kasus UAT, 8 aktivitas, 4 assignment, pembayaran Rp1.000.000, pencairan Rp5.000.000, dan status paid/disbursed/rejected. Hasil sesudah restart disimpan di `runtime/ui-after-restart.json`.
- Browser-act kini dapat dijalankan dalam lingkungan akses penuh. Browser lokal terisolasi dibuka, supervisor login, dashboard menampilkan total 73 penagihan/74 pengajuan, satu kasus selesai pada masing-masing alur, realisasi Rp1.000.000/Rp5.000.000. Detail penagihan tetap Lunas, siklus 2, dengan pembayaran Rp400.000 dan Rp600.000 pada riwayat.
- Kriteria Sprint 2 terpenuhi: kedua alur sudah diuji melalui UI, perbaikan dialog JavaScript telah diuji pada release, tampilan desktop dan bingkai ponsel 390 × 844 diperiksa, serta data asli bertahan setelah server dimulai ulang.

## Sesi 3 — data, aturan, dan kontrol supervisor

### Sprint 3A — editor kapasitas dan status aktif petugas

**Status: selesai, 28 Oktober 2026.** Satu fitur dipilih dari roadmap: supervisor mengubah kapasitas 1–100 serta status aktif melalui UI daftar petugas, memakai PATCH API yang sudah ada. Pagination, impor, ML, dan migrasi database tetap sprint tersendiri.

- Dialog baru `agent_settings.dart`, tombol pada daftar petugas, informasi beban harian/aktif, validasi input, penanganan kesalahan server, dan pembaruan daftar saat dialog ditutup.
- Pengiriman ganda dan penutupan dialog selama simpan dicegah. Penonaktifan menghentikan assignment baru; tugas lama tetap tercatat.
- Tes backend baru memeriksa konflik kapasitas, role, tugas lama pada petugas nonaktif, persistensi pengaturan, dan audit. **28 tes backend lulus**.
- **16 tes Flutter lulus** (13 tes sebelumnya + 3 tes editor: validasi/konflik/status pada 390 dan 1440 piksel, serta pencegahan pengiriman ganda/penutupan saat simpan). Flutter analyze bersih, build web dan Wasm dry run berhasil. Seluruh perintah sekarang berhasil dijalankan langsung oleh agen; peringatan font Cupertino tetap ada.
- Browser desktop pada root `http://127.0.0.1:5173/`: login supervisor, buka editor `SMG-col-A`, kapasitas 0 ditolak formulir, kapasitas 1 ditolak API karena dua assignment harian, lalu 14/nonaktif berhasil disimpan dan daftar diperbarui.
- UI membuat kasus dummy `TAG-9FA46D7A6E`, alias `UAT S3 Kontrol Kapasitas`, SMG/Low/Rp200.000. Percobaan assignment saat petugas nonaktif tetap menghasilkan kasus belum ditugaskan dan pesan tidak ada petugas aktif yang sesuai.
- Backend asli dihentikan dan dimulai ulang lagi (PID **13864**). Pengaturan 14/nonaktif dan beban petugas cocok persis dengan snapshot sebelum restart. Saat API mati, UI menampilkan error koneksi, tetap menyimpan sesi; `Coba lagi` memulihkan daftar setelah restart.
- Pengaturan `SMG-col-A` dipulihkan melalui UI ke **12/aktif**. Kasus dummy yang semula tertahan kemudian berhasil ditugaskan ke petugas tersebut. Login `smg-col-a` hanya melihat dua kasus miliknya, tanpa menu Petugas/editor; petugas berhasil mencatat pembayaran Rp200.000 hingga lunas/outcome success.
- Bingkai ponsel **390 × 844** menampilkan dialog editor lengkap tanpa overflow. Kapasitas 101 ditolak; dialog ditutup tanpa menyimpan perubahan pada petugas Bandung. Bukti visual: [dialog ponsel](evidence/sprint3-agent-mobile.png), [uji nonaktif desktop](evidence/sprint3-agent-inactive-desktop.png), dan [pengaturan akhir dipulihkan](evidence/sprint3-agent-final.png).
- Pemeriksaan akhir API/audit: seluruh 12 petugas kembali **12/aktif**, dua perubahan master berhasil tercatat di audit, data/histori tiga kasus Sprint 2 tetap sama, satu kasus UAT Sprint 3 lunas. Snapshot `runtime/sprint3-final-verification.json` berstatus **PASS**. Dashboard kini 74 penagihan (2 selesai, Rp1.200.000) dan 74 pengajuan (1 dicairkan, Rp5.000.000; 1 ditolak). Tidak ada database atau hasil demo lama yang dihapus.

### Sprint 3B — pagination dan pencarian antrean di server

**Status: selesai, 28 Oktober 2026.** Antrean penagihan/pengajuan kini memuat 25 kasus per halaman melalui `offset`/`limit` API. Batas UI lama yang hanya memuat 200 kasus dihapus.

Implementasi:

- Kontrol Sebelumnya/Berikutnya di atas dan bawah daftar, rentang kasus, total hasil dari server, dan nomor halaman. Pencarian ID/nama/kode wilayah serta filter status dijalankan server; filter pengajuan mencakup Dokumen lengkap dan Ditolak.
- Pencarian dibatasi 100 karakter dan menunggu 300 ms setelah input terakhir. Request lama langsung diinvalidasi saat input berubah, sehingga respons terlambat tidak dapat mengganti hasil baru atau antrean alur lain.
- Halaman kembali ke awal ketika pencarian/filter/alur berubah; kembali dari detail mempertahankan halaman. Jika halaman terakhir menyusut setelah data berubah, UI memuat halaman terakhir yang masih valid.
- Saat fetch gagal, baris lama disembunyikan, assignment dinonaktifkan, dan retry mempertahankan parameter halaman. Dashboard hanya mengambil lima kasus antrean global untuk ringkasan.
- Tombol **Tugaskan halaman ini** dan dialog konfirmasi menyebut cakupan halaman aktif. ID yang dikirim maksimal 25 kasus belum ditugaskan pada halaman itu; halaman tersembunyi tidak diproses.
- Pencarian backend mencakup `region_id`, trim spasi, serta memperlakukan `%`, `_`, dan backslash sebagai teks literal. Scope akun tetap diterapkan sebelum pagination dan hitung total.

Verifikasi otomatis:

- **30 tes backend lulus**: dua tambahan mencakup 210 kasus, urutan stabil tanpa duplikasi antarhalaman, pencarian kasus di atas 200, kombinasi filter, pencarian wilayah/literal, dan total sesuai scope petugas.
- **25 tes Flutter lulus**: sembilan tambahan mencakup pagination hingga offset 200 pada lebar 390/1440, query/filter/reset halaman, respons lama saat debounce maupun setelah respons baru, perpindahan alur, halaman menyusut, kegagalan/retry, dan payload batch hanya dari halaman aktif.
- Flutter analyze bersih; build web dan Wasm dry run berhasil. Peringatan font Cupertino sebelumnya tetap ada. Python compile check lulus untuk perubahan backend dan helper UAT.

Verifikasi browser pada salinan database:

- `scripts/prepare-pagination-uat.py` membuat `runtime/pagination-uat.db` dari backup read-only database utama, lalu membuat data melalui API terisolasi: **285 penagihan + 287 pengajuan**. Script menolak menimpa database yang sudah ada. Data dummy massal tidak dimasukkan ke `runtime/assignment.db`.
- Browser-act lokal memverifikasi desktop: halaman 1–12 penagihan, rentang **201–225 dari 285** pada halaman 9, detail kasus urutan 285 (`TAG-237FAF6170`), lalu kembali ke halaman 12. Pencarian target dari halaman akhir menghasilkan 1 kasus dan reset ke halaman 1.
- Target pengajuan urutan **287** (`AJU-6C27005FD8`) juga ditemukan melalui pencarian. Pindah alur membersihkan filter/pencarian; filter Dokumen lengkap menghasilkan 1 kasus dan Ditolak 2 kasus pada fixture.
- Assignment halaman kedua dari 210 kasus berawalan `UAT S3B Penagihan`: 25 ID halaman direkam sebelum aksi, 9 ditugaskan sesuai sisa kapasitas, 16 tetap antre. Pemeriksaan API memastikan **0 assignment di luar halaman aktif**, dan UI tetap pada halaman 2. Filter Ditugaskan menghasilkan 9 hasil serta reset ke halaman 1.
- Bingkai ponsel **390 × 844** diuji hingga halaman 9 tanpa overflow yang terlihat. API UAT dihentikan; UI menyembunyikan kasus lama dan menampilkan error. Setelah restart API, Coba lagi mengembalikan halaman 9 dengan rentang yang sama.
- Login petugas `smg-col-a` hanya melihat **11 kasus miliknya**, tanpa kontrol assignment/master; pencarian ID target di luar scope menghasilkan 0 kasus.
- Bukti visual: [desktop di atas 200 kasus](evidence/sprint3b-pagination-desktop.png) dan [pagination ponsel](evidence/sprint3b-pagination-mobile.png). JSON fixture, hasil batch, dan pemeriksaan akhir disimpan dalam `runtime/pagination-*.json`.

Pemulihan lingkungan:

- API pada port 8000 dikembalikan ke **database utama** dengan PID 11840. Tujuh tabel bisnis dibandingkan berdasarkan seluruh isi dan SHA-256: **identik** dengan sebelum UAT (148 kasus, 5 assignment, 9 aktivitas, 21 audit). Salinan UAT tetap terpisah.
- Sesi dari salinan UAT ditolak database utama dengan HTTP 401; browser kembali ke login dan berhasil login ulang supervisor. Dashboard utama tetap 74/74 kasus, pembayaran Rp1.200.000 dan pencairan Rp5.000.000. Antrean utama berhasil membuka **26–50 dari 74 kasus**, halaman 2 dari 3 ([bukti setelah pemulihan](evidence/sprint3b-main-restored.png)). Build terbaru disajikan pada root port 5173; health API dan web HTTP 200.

### Sprint 3C — pemilihan assignment batch lintas halaman

**Status: selesai, 28 Oktober 2026.** Satu fitur: supervisor memilih kasus yang akan ditugaskan, menggunakan API assignment yang sudah ada. Tidak ada perubahan aturan bisnis atau skema database.

Implementasi:

- Checkbox per kasus yang belum ditugaskan/belum selesai, Pilih halaman ini, Kosongkan pilihan, jumlah terpilih serta jumlah dari halaman lain. Pilihan bertahan antarhalaman dengan batas 100 ID unik.
- Mengubah pencarian, filter, atau menu mengosongkan pilihan; keterangannya terlihat di atas daftar. Pilihan berada di memori workspace dan ikut hilang ketika logout, sesi berakhir, atau halaman browser dimuat ulang.
- Dialog tinjauan menampilkan seluruh pilihan dengan nama/ID/wilayah/nilai, termasuk kasus dari halaman lain. Daftar dapat digulir; Batal tidak mengirim request dan mempertahankan pilihan.
- Pengiriman ganda, navigasi menu, serta perubahan pilihan dicegah selama proses. Hasil per kasus menampilkan petugas atau alasan belum ditugaskan. Pilihan yang berhasil dihapus, yang tertahan dipertahankan. Refresh memangkas pilihan pada halaman yang kini sudah tidak memenuhi syarat; status pilihan tersembunyi tetap diperiksa server saat dikirim.
- Kegagalan jaringan mempertahankan pilihan dan memuat ulang data karena request mungkin sudah berhasil. API existing mencegah assignment ganda pada kasus yang sudah ditugaskan. UI tidak mengirim semua hasil pencarian secara otomatis.

Verifikasi otomatis:

- **31 tes Flutter lulus**: enam tambahan mencakup pilihan eksplisit dari dua halaman pada lebar 390/1440, Batal, payload hanya ID terpilih, hasil parsial, batas 100 tanpa duplikasi, pengosongan pada perubahan konteks, kasus assigned/terminal, kegagalan request ambigu/pengiriman tunggal, serta tidak adanya kontrol batch pada role petugas. Tes batch lama diperbarui untuk langkah pemilihan eksplisit.
- **30 tes backend lulus** sebagai regresi, termasuk scope role, validasi batch, transaksi atomik, kapasitas concurrent, dan assignment idempoten. Tidak ada tes backend baru karena kontrak API tidak berubah.
- Flutter analyze bersih dan build web berhasil. Peringatan font Cupertino sebelumnya tetap ada. Semua pemeriksaan dijalankan langsung menggunakan SDK/virtual environment proyek.

Verifikasi browser:

- Login supervisor pada Chrome pribadi berhasil sebelum pengujian fitur. Kontrol native kemudian dihentikan alat karena URL tidak dapat dipastikan untuk pemeriksaan kebijakan; ini bukan bukti bahwa konfigurasi izin pengguna salah. Pengguna selanjutnya menginstruksikan browser-act.
- UAT fitur dituntaskan dengan browser-act pada Chrome terpisah yang sudah dikonfigurasi, memakai `runtime/selection-uat.db`. Salinan dibuat helper pagination yang sama, sehingga fixture tetap bernama UAT S3B: **285 penagihan + 287 pengajuan**. Database utama tidak digunakan untuk mutasi UAT.
- Desktop: pilih `TAG-0005FA9AF3` pada halaman 1 dan `TAG-1DB2C29885` pada halaman 2. Dialog menampilkan dua kasus dan satu pilihan dari halaman lain. Batal mempertahankan keduanya; konfirmasi berikutnya menghasilkan **2 ditugaskan**, tetap di halaman 2, checkbox kasus assigned dinonaktifkan ([hasil](evidence/sprint3c-cross-page-result.png)).
- Pilih empat halaman berturut-turut: 25 → 50 → 75 → **100**. Pada halaman 5, 100 pilihan tetap tersimpan dan checkbox kasus tambahan dinonaktifkan. Dialog tinjauan memuat 100 pilihan dari halaman lain dan daftar berhasil digulir; dibatalkan tanpa assignment ([batas](evidence/sprint3c-limit-desktop.png), [tinjauan](evidence/sprint3c-review-desktop.png)).
- Pencarian baru menghapus 100 pilihan dan reset halaman. Memilih 25 penagihan kemudian menghasilkan **7 ditugaskan + 18 tertahan karena kapasitas**. Hasil memuat alasan per kasus; 18 pilihan tetap tersimpan. Pembandingan ID database memastikan **0 assignment di luar 25 pilihan** (`runtime/selection-batch-result.json`, [hasil parsial](evidence/sprint3c-partial-result.png)). Perpindahan alur dan filter Dokumen lengkap juga membersihkan pilihan.
- Bingkai ponsel **390 × 844**: dialog tinjauan 24 kasus tampil utuh, daftar bergulir dan tombol Batal/Tugaskan terlihat tanpa overflow ([tinjauan ponsel](evidence/sprint3c-mobile-review.png)). Pencarian sembilan pengajuan lalu Pilih halaman ini → tinjauan → konfirmasi menghasilkan **9 ditugaskan + 0 tertahan**, tepat sembilan ID sesuai pilihan (`runtime/selection-phone-result.json`, [hasil ponsel](evidence/sprint3c-mobile-result.png)). Ini pengujian Flutter web dalam bingkai, bukan build Android/iOS atau keyboard perangkat fisik.
- Logout supervisor dan login `smg-col-a` pada ponsel: hanya **11 kasus miliknya**, tanpa checkbox/batch/master petugas. Pencarian `TAG-7BA31221E0` di luar scope menghasilkan 0 kasus ([role petugas](evidence/sprint3c-mobile-agent.png)).
- Dengan 17 kasus terpilih di desktop, API UAT dihentikan. UI menyembunyikan daftar lama, menampilkan error koneksi, mempertahankan 17 pilihan dan tidak membuka dialog assignment saat tombol ditekan. Setelah restart UAT (PID 27188), Muat ulang memulihkan daftar/17 pilihan. Seluruh isi dan SHA-256 tujuh tabel UAT identik sebelum/sesudah restart, termasuk **25 assignment** (`runtime/selection-before-restart.json`, `selection-final-check.json`).

Pemulihan lingkungan:

- API port 8000 dikembalikan ke **runtime/assignment.db**, PID **10880**. Sesi UAT menerima HTTP 401 dan seluruh pilihan lama hilang saat kembali ke login; login ulang supervisor berhasil. Dashboard utama tetap 74/74 kasus, pembayaran Rp1.200.000 dan pencairan Rp5.000.000.
- Tujuh tabel bisnis utama dibandingkan dengan fingerprint sebelum UAT: **identik**, dengan **148 kasus, 5 assignment, 9 aktivitas, 21 audit**, seluruh 12 petugas tetap kapasitas 12/aktif. UAT menyimpan 18 assignment tambahan hanya pada salinan (2 lintas halaman + 7 parsial + 9 pengajuan); dua assignment fixture sudah ada sebelum pengujian batch. Bukti pemeriksaan akhir ada di `runtime/selection-final-check.json`.

## Sprint 4 — laporan operasional dan ekspor CSV terpadu

**Status: selesai, 28 Oktober 2026.** Sesuai instruksi terbaru, mulai sprint ini tidak memakai sub-sprint huruf. Cakupan satu sprint diperluas menjadi satu integrasi utuh: laporan portofolio dan siklus, filter/KPI, UI, unduhan, audit, keamanan sesi, regresi, serta UAT browser. Nama sprint lama tetap dipertahankan sebagai histori.

Implementasi:

- Modul `backend/app/reports.py`: filter alur, jenis laporan, tanggal WIB inklusif, wilayah, petugas, status/hasil, serta pencarian literal ID/nama. Validasi menolak kombinasi wilayah/petugas/jenis status yang tidak sesuai.
- `GET /api/reports` menyediakan pagination, ringkasan seluruh hasil dan per petugas dalam snapshot baca SQLite. `GET /api/reports/export` memakai filter yang sama, mengekspor seluruh hasil tanpa batas 200 baris, dan mencatat actor/filter/jumlah baris ke audit `export_report` dalam satu transaksi. Endpoint lama dengan `kind` saja tetap menghasilkan portofolio.
- Portofolio memakai tanggal pembuatan kasus dan kondisi terkini. Siklus memakai tanggal awal assignment serta petugas historis pada assignment, dengan realisasi dari aktivitas siklus itu. Pembayaran tidak dihitung ulang sebagai total kasus pada setiap siklus. Keberhasilan hanya `success / (success + no_success)`; active dan superseded dikeluarkan. Outcome lunas terlambat tetap `no_success`.
- Menu Laporan khusus supervisor pada sidebar/navigasi bawah: formulir responsif, Tampilkan laporan/Reset, ringkasan dan rincian petugas, pagination 25, detail kasus, tinjauan ekspor, serta unduhan web. Sidebar dapat digulir pada layar desktop pendek setelah penambahan menu kelima.
- Filter yang diubah langsung menyembunyikan hasil lama; ekspor menunggu preview terbaru. Request/unduhan terlambat dari sesi sebelumnya ditolak. Unduhan tidak menaruh token di URL, memeriksa MIME CSV, mempertahankan BOM/Unicode, memakai Blob, dan melepas object URL. Target native memakai fallback yang menjelaskan unduhan web; runner Android/iOS belum dibuat.
- CSV memakai quoting standar, pelolosan formula termasuk yang didahului whitespace, metadata tanggal/waktu, serta header pada hasil kosong. Ekspor dihitung ulang saat diminta, bukan snapshot permanen dari preview. Definisi dan batas lengkap ada di [laporan operasional](laporan-operasional.md).

Verifikasi otomatis:

- **38 tes backend lulus** (30 sebelumnya + 8 laporan): batas hari WIB awal/akhir, kesamaan preview/CSV, 211 baris/pagination/ekspor lengkap, filter literal/hasil kosong, realisasi parsial antar-siklus, petugas historis, tanggal assignment berbeda dari tanggal kasus, lunas terlambat/aktif lewat SLA, pencairan/penolakan, validasi/role, audit, formula/kutipan/Unicode.
- **38 tes Flutter lulus** (31 sebelumnya + 7 laporan): lebar 390/1440, pagination, ekspor seluruh hasil dan Batal, query filter yang benar, tanggal tidak valid/rentang terbalik, pembersihan pilihan petugas/status saat konteks berubah, respons preview lama, error/retry, hasil kosong, kirim tunggal, sesi berubah saat unduh, MIME/403/401, dan regresi Reset.
- Flutter analyze bersih; build web/Wasm dry run berhasil. Peringatan font Cupertino lama tetap ada. `web` 1.1.1 yang sudah tersedia pada cache/lock kini menjadi dependensi langsung untuk unduhan; tidak membutuhkan layanan atau API key eksternal.

Verifikasi browser-act, Chrome terpisah lokal:

- Helper `scripts/prepare-reports-uat.py` membuat backup baru `runtime/reports-uat.db` dan skenario lewat API terisolasi. Total **364 kasus (288 penagihan + 76 pengajuan), 11 assignment, 17 aktivitas**. Fixture memuat 210 kasus portofolio, pembayaran parsial lalu pindah tim, lunas setelah 73 jam, aktif lewat SLA, pencairan, penolakan, dan teks formula/Unicode. Database lama tidak ditimpa.
- Desktop: filter UAT S4 Portofolio dan tanggal **28 Oktober WIB** menghasilkan **210 kasus / Rp210.000.000**, paging ke halaman 2 dari 9. Batal ekspor tidak membuat Blob/request ekspor. Konfirmasi berikutnya benar-benar menyimpan `collection-cases-demo.csv` di Downloads: **210 baris**, 44.108 byte, BOM UTF-8, seluruh ID cocok fixture; tidak terpotong halaman/200 baris ([preview dan ekspor](evidence/sprint4-report-export-desktop.png)).
- Filter siklus bertanggal **25 Oktober WIB** menghasilkan **4 siklus: 1 berhasil, 1 tidak berhasil, 1 dialihkan, 1 aktif lewat SLA**, realisasi **Rp2.000.000**, hasil final **50%**. Pembayaran terlambat tanggal 28 tetap masuk karena tanggal memilih awal siklus, sesuai keterangan UI. Rincian petugas: tim A tiga siklus/Rp1.200.000, tim B satu siklus/Rp800.000 ([ringkasan siklus](evidence/sprint4-report-cycles.png)).
- CSV siklus unduhan nyata memuat pembayaran **Rp200.000 pada siklus 1** dan **Rp800.000 pada siklus 2** untuk kasus reassign `TAG-938D15EA5E`. Filter Tele Semarang COL tetap menampilkan siklus lama walaupun kasus sekarang pada tim B. Dari laporan, Buka detail kasus → Back mempertahankan filter dan memuat ulang laporan.
- Pengajuan: dua siklus UAT terdiri dari satu dicairkan dan satu ditolak, hasil final 50%, realisasi **Rp1.000.000**. CSV siklus serta portofolio masing-masing dua baris dan nominal sesuai; tidak bercampur dengan penagihan.
- Bingkai ponsel **390 × 844**: menu kelima Laporan dapat dibuka, dropdown alur/wilayah/petugas sesuai scope dan tidak overflow, tanggal `2026-02-30` ditolak. Filter Pengajuan/Semarang/Tele ORI/tanggal 25 Oktober/UAT S4 menghasilkan dua kasus; dialog unduh tampil utuh dan CSV dua baris benar-benar tersimpan ([dropdown](evidence/sprint4-report-mobile-dropdown.png), [konfirmasi](evidence/sprint4-report-mobile-confirm.png)). Ini pengujian web dalam bingkai, bukan perangkat/keyboard native.
- Logout lalu login `smg-col-a` pada ponsel: hanya tiga menu, tanpa Petugas/Laporan; dashboard menunjukkan empat kasus penagihan miliknya ([role petugas](evidence/sprint4-report-mobile-agent.png)). API laporan dan ekspor menolak role petugas (403) pada tes backend; tanpa/kehabisan sesi ditolak dan respons binary 401 membersihkan sesi.
- Browser menemukan bug **Reset filter**: `Form.reset()` memanggil callback dropdown dengan nilai lama sebelum widget dibangun ulang. Perbaikan menghapus reset form yang memulihkan nilai lama; validasi pada refresh membersihkan error. Tes regresi ditambahkan dan build diulang. Browser pada build terbaru membuktikan Pengajuan/Siklus → Reset kembali ke Penagihan/Portofolio, menghapus tanggal/petugas/pencarian/status, serta memuat 288 kasus UAT.
- Unduhan kasus dengan teks formula di awal setelah whitespace, koma, kutip, dan Unicode mempertahankan seluruh teks serta prefix apostrof. Unduhan kosong hanya memuat header. Berkas asli hasil klik UI disalin ke `runtime/sprint4-*.csv`; pemeriksaan JSON berada di `runtime/reports-download-verification.json`.
- API UAT dihentikan: konfirmasi unduh menghasilkan error koneksi tanpa berkas baru; sesi tetap ada. Muat ulang menyembunyikan hasil/ekspor lama dan menampilkan Coba lagi laporan. Setelah restart (PID 29744), retry memulihkan hasil kosong dengan filter yang sama. Seluruh isi/SHA-256 tujuh tabel UAT identik sebelum/sesudah restart, termasuk **259 audit**. Tujuh audit ekspor memiliki jumlah baris `[210,4,2,2,0,1,0]`; satu ekspor kosong dilakukan saat menelusuri bug Reset sebelum perbaikan. Error koneksi tidak menambah audit ([error unduh](evidence/sprint4-report-export-error.png)).

Pemulihan lingkungan:

- Backend port 8000 kembali ke **runtime/assignment.db**, PID **38948**. Sesi salinan ditolak 401, laporan lama hilang, login ulang supervisor berhasil. Menu Laporan pada database asli menampilkan **74 penagihan, nominal Rp273.200.000, realisasi Rp1.200.000, sisa Rp272.000.000**, 72 belum ditugaskan/2 lunas ([bukti pemulihan](evidence/sprint4-main-restored.png)). Ekspor tidak dijalankan pada database asli agar audit/data demo tidak berubah selama UAT.
- Tujuh tabel utama identik dengan fingerprint sebelum UAT: **148 kasus, 5 assignment, 9 aktivitas, 21 audit**; 12 petugas tetap kapasitas 12/aktif. Snapshot, hasil unduhan, dan pembandingan restart disimpan dalam `runtime/reports-*.json`. Web terbaru dan API tetap pada port 5173/8000.

Keputusan pada penutupan Sprint 4: sprint berikutnya memakai nomor utuh dan satu integrasi yang lebih besar, tanpa 4A/4B atau 5A/5B. Kandidat saat itu **Sprint 5: impor Excel lengkap**; implementasi dan hasil penutupannya kini tercatat di bagian Sprint 5 di bawah.

- Laporan operasional dan ekspor CSV UI selesai sebagai Sprint 4; pemilihan batch/pagination/editor petugas pada sprint sebelumnya tetap tercatat sebagai histori.
- Impor Excel preview/validasi/commit atomik dengan template operasional terpisah kemudian selesai pada Sprint 5 di bawah.
- Master petugas/wilayah lengkap, pengaturan kelompok/ambang/SLA, override petugas dengan alasan dan audit.
- Laporan periode transaksi (berbeda dari kohort assignment), ekspor latar belakang, dan skala data produksi bila diperlukan. Laporan siklus/filter tanggal/skenario demo sudah selesai pada Sprint 4.
- PostgreSQL, SQLAlchemy, Alembic, migrasi data, dan pengujian transaksi concurrent pada database tujuan.

## Sprint 5 — impor Excel operasional

**Status: selesai, 28 Oktober 2026.** Satu integrasi utuh, tanpa sub-sprint huruf: template terpisah per alur, unggah XLSX, pemilihan worksheet/header, pemetaan, preview per baris, deduplikasi referensi, commit atomik/idempoten, riwayat draft, audit, integrasi antrean dan UAT browser. Panduan penggunaan, batas, API dan recovery ada di [impor operasional](impor-operasional.md).

Implementasi:

- `backend/app/imports.py`: template `Data` kosong + `Petunjuk`; upload raw XLSX maksimal 5 MiB; ZIP/XML preflight, openpyxl read-only/defusedxml, tanpa evaluasi formula. Maksimal 2.000 baris/64 kolom/20 worksheet; baris berlebih tidak dipotong. Berkas rusak, makro, external links, embedded object, formula/error Excel, ID numerik dan nominal teks berformat ribuan ditolak.
- Pilih worksheet/header baris 1–20, saran pemetaan alias kolom, pemetaan manual unik, validasi melalui kontrak kasus yang sama. Preview global menghitung seluruh baris dengan rincian 25 per halaman, nomor baris asli, error, skor aturan demo dan tim. Satu error memblokir seluruh commit; kolom diabaikan memerlukan persetujuan eksplisit.
- SQLite schema version 2 menambah `import_batches` dan `import_case_refs` secara aditif. Referensi sumber unik tanpa membedakan kapital per alur. Kasus baru `excel-operational` tanpa assignment/pembayaran; tidak mengimpor histori, aktivitas, master atau memperbarui kasus lama. Template awal klien tidak ditimpa.
- Commit memakai revisi preview tersimpan dan satu `BEGIN IMMEDIATE`; duplikasi/wilayah/validasi diperiksa lagi. Kasus, referensi dan audit tersimpan bersama atau rollback bersama. Retry batch/revisi yang sama mengembalikan hasil sama tanpa menambah kasus/audit commit.
- Draft milik actor bertahan 24 jam, maksimal 10 aktif; riwayat 20 terbaru dapat dilanjutkan. Discard melepas workbook/preview tanpa menghapus kasus. Binary dilepas setelah commit; hasil committed tidak kedaluwarsa. Audit mencakup upload/preview/discard/tiap kasus/commit.
- Wizard Flutter responsif melalui tombol Impor Excel pada dua antrean supervisor. Picker/unduhan XLSX web nyata, detail hasil, kembali ke antrean dengan filter/pilihan bersih, error/retry dan penguncian tindakan ketika hasil commit belum pasti. Respons lintas sesi ditolak, 401 membersihkan navigator/dialog; petugas tidak mendapat kontrol impor. Tidak menambah menu keenam pada navigasi utama.
- Runtime baru openpyxl 3.1.5 dan defusedxml 0.7.1 tercantum pada requirements, terpasang melalui uv karena venv saat ini tidak memiliki pip. Tidak membutuhkan API key/layanan eksternal. Runner/picker native Android/iOS, impor histori/master/update kasus, ML dan PostgreSQL belum diimplementasikan.

Verifikasi otomatis:

- **47 tes backend lulus** (38 regresi + 9 impor): template kedua alur, formula/numerik/duplikasi, header/pemetaan/kolom diabaikan, rollback konflik batch lain, concurrent commit/replay, revisi, role/pemilik, kedaluwarsa/discard, persistensi/migrasi, berkas/ukuran/makro/mapping invalid, preview berpaginasi/commit seluruh 2.000 baris dan penolakan 2.001 baris.
- **45 tes Flutter lulus** (38 regresi + 7 impor): lebar 390/1440, unggah/unduh, preview/Batal/commit, pemetaan membatalkan preview, persetujuan kolom diabaikan, error halaman kedua memblokir commit, header invalid/discard, hasil commit ambigu/cek status batch yang sama, MIME upload dan respons lintas sesi.
- Analyze bersih dan build web/Wasm dry run berhasil. Pemeriksaan web lengkap diulang setelah koreksi teks hasil UAT, tetap 45 lulus. Peringatan Cupertino lama tetap muncul; aplikasi memakai ikon Material. Build native/perangkat fisik belum diuji.

Verifikasi browser-act pada Chrome lokal terpisah:

- `scripts/prepare-imports-uat.py` membuat backup baru `runtime/imports-uat.db` dan workbook sintetis pada `runtime/import-fixtures/`, menolak path yang sudah ada. Salinan awal 148 kasus, 5 assignment, 9 aktivitas dan 21 audit. Browser bertipe `chrome`, bukan Chrome pribadi/chrome-direct. Seluruh mutasi UAT hanya pada salinan.
- Desktop: unduhan nyata `template-operasional-collection.xlsx` tersimpan di Downloads. Pemeriksaan openpyxl memastikan `Data` hanya satu baris header, `Petunjuk` tersedia dan freeze A2. Unggah penagihan memetakan enam kolom dan menampilkan kolom hasil kontak diabaikan. Preview **3 valid/Rp600.000** belum menambah kasus. Tombol impor sebelum persetujuan kolom tidak membuka dialog; Batal berikutnya mempertahankan preview. Konfirmasi membuat tepat **3 kasus**, tanpa assignment/transaksi ([konfirmasi](evidence/sprint5-import-confirm-desktop.png), [hasil](evidence/sprint5-import-result-desktop.png)).
- Workbook 31 baris: **30 valid/1 bermasalah** memblokir impor sejak halaman 1. Halaman 2 menunjukkan baris Excel 32 dengan wilayah UNKNOWN; tidak ada baris disimpan ([halaman kedua](evidence/sprint5-invalid-page2.png)). Workbook lain menolak ID ganda case-insensitive, ID numerik, nominal `1.000.000` dan formula `=SUM(1,2)` ([validasi](evidence/sprint5-invalid-formula.png)).
- Workbook berjudul pada baris 1 otomatis memakai header baris 2. `Saldo_Custom` harus dipetakan manual ke amount; preview **2 valid/Rp900.000** ([pemetaan](evidence/sprint5-custom-mapping.png)). API dihentikan: Muat ulang menampilkan error koneksi dan mempertahankan sesi/draft ([error](evidence/sprint5-import-network-error.png)). Setelah restart UAT PID 18648, **isi dan SHA-256 sembilan tabel identik**, termasuk 151 kasus/4 batch/3 referensi. Muat ulang memulihkan pemetaan manual/preview; commit menambah tepat dua kasus.
- Unggah ulang penagihan menandai semua referensi sudah diimpor dan memblokir commit. Konfirmasi Buang draft melepas binary/preview; kasus hasil impor tetap ada. Riwayat dapat membuka batch committed ([riwayat](evidence/sprint5-history.png)). `.xlsx` berisi data rusak ditolak tanpa menambah batch atau menghapus sesi ([error berkas](evidence/sprint5-malformed-workbook.png)).
- Bingkai web **390 × 844**: delapan field pengajuan, dropdown panjang, scrolling, preview dua kasus/Rp3.000.000 dan dialog tampil tanpa overflow ([dropdown](evidence/sprint5-mobile-mapping-dropdown.png), [konfirmasi](evidence/sprint5-mobile-confirm.png)). Konfirmasi membuat tepat **2 pengajuan** ([hasil](evidence/sprint5-mobile-result.png)). CLI sempat menggulir parent iframe; pengguliran elemen semantik dalam frame berhasil tanpa mengganti aksi workflow melalui API. Ini pengujian web, bukan perangkat native.
- Dari hasil impor, Buka kasus pengajuan → Tugaskan → Lolos verifikasi → Pencairan simulasi **Rp1.000.000** berhasil, status disbursed/siklus success ([ponsel](evidence/sprint5-import-disbursed-mobile.png)). Penagihan **TAG-D21D63184E** → Tugaskan → bayar **Rp40.000** tetap ditindaklanjuti → bayar **Rp60.000** menjadi lunas/paid Rp100.000/siklus success ([parsial](evidence/sprint5-import-partial-payment.png), [lunas](evidence/sprint5-import-paid-desktop.png)). Kembali ke antrean dan pencarian memuat tiga nama hasil impor. Reassign/penolakan lengkap tetap bukti sprint sebelumnya dan regresi backend; tidak diklaim diulang seluruhnya di sprint ini.
- Logout supervisor/login `smg-col-a` pada ponsel berhasil, hanya tiga kasus miliknya dan tanpa Impor Excel/master/batch ([role](evidence/sprint5-agent-no-import.png)). Penolakan API bagi petugas/supervisor lain, kedaluwarsa dan replay concurrent dibuktikan tes otomatis, bukan seluruhnya diulang lewat UI.
- UAT akhir: **155 kasus, 7 assignment, 13 aktivitas, 50 audit, 6 batch, 7 referensi impor**. Tiga commit menghasilkan 3+2+2 kasus; dua batch invalid hanya preview, satu batch duplikat dibuang. Dua assignment/empat aktivitas tambahan berasal dari workflow di atas. Bukti: `runtime/imports-browser-results.json`; fingerprint restart: `imports-before-restart.json` dan `imports-after-restart.json`.
- Koreksi teks UI: batch selesai/dibuang tidak lagi menampilkan batas waktu draft; keterangan hasil menjelaskan keadaan saat impor agar tetap benar setelah assignment. Tes dan build diulang. Flow utama diuji pada build sebelum perubahan teks tersebut; build final diperiksa kembali dengan smoke browser.

Pemulihan lingkungan:

- API port 8000 kembali ke **runtime/assignment.db**, PID **31636**; web 5173 melayani build terbaru. Sesi salinan mendapat 401 dan navigator impor dihapus. Reload build final → login supervisor → Penagihan → Impor Excel menunjukkan riwayat kosong ([pemulihan](evidence/sprint5-main-restored.png)).
- SHA-256 isi tujuh tabel bisnis utama **identik** sebelum/sesudah UAT: **148 kasus, 5 assignment, 9 aktivitas, 21 audit**, 12 petugas aktif/kapasitas 12. Migrasi aditif schema v2 diterapkan; dua tabel impor utama kosong. Web/API HTTP 200; bukti `runtime/imports-final-check.json`. Database/workbook UAT dipertahankan; hasil demo lama tidak dihapus.

Sprint berikutnya yang dipilih: **Sprint 6 — master operasional dan override assignment terpadu**. Implementasi dan pemeriksaan aktualnya dicatat di bawah.

## Sprint 6 — master operasional dan override assignment terpadu

**Status: selesai, 28 Oktober 2026.** Satu integrasi master wilayah/petugas/akun awal, validasi dampak perubahan, override assignment dengan alasan dan audit, histori profil, UI responsif, regresi, serta UAT browser. Aturan wilayah/alur/tim/aktif/kapasitas tetap berlaku. Panduan lengkap dan kontrak API: [master dan override](master-dan-override.md).

Implementasi:

- `backend/app/master.py`: tambah/ubah wilayah dan profil petugas, akun awal role agent atomik bersama profil, versi perubahan, audit sebelum/sesudah, serta API opsi/commit override. Kode/username tetap; tidak ada hapus fisik atau reset password. Prototype dibatasi 25 wilayah/200 petugas. Username/ID unik, password minimal 12 karakter di-hash dan tidak dicatat dalam audit.
- Wilayah tidak dapat dinonaktifkan selama ada kasus nonterminal (termasuk antrean) atau petugas aktif. Wilayah nonaktif dikeluarkan dari formulir kasus, template dan validasi impor, tetapi tetap tersedia untuk laporan. Perubahan sesudah preview impor diperiksa lagi saat commit.
- Wilayah/alur/tim petugas tidak dapat diubah selama ada tugas aktif; perubahan nama/kanal/pendekatan/kapasitas/status tetap diperbolehkan. Kapasitas tidak boleh di bawah beban aktif/harian. Nonaktif penerimaan assignment tidak mencabut login atau tugas lama. UI mengirim versi; konflik ditinjau melalui Muat versi terbaru. Endpoint kapasitas lama tetap kompatibel dengan klien tanpa versi.
- Override pertama maupun pengalihan memilih ID petugas eksplisit yang memenuhi syarat. Preview pengalihan menghitung skor dari histori siklus yang akan ditutup tanpa mengubah kasus; commit mempertahankan skor/snapshot siklus lama, saldo dan progres qualified, menutup siklus lama dan membuat siklus baru 72 jam secara atomik. Low=A, High=B, Medium ambang demo 60 tetap berlaku; petugas saat ini tidak dapat dipilih ulang secara manual.
- Semua mutasi master dan assignment memakai `BEGIN IMMEDIATE`. Override memakai expected_version dan request_key: retry actor/kasus/payload sama tidak menambah siklus/audit, payload berbeda ditolak. UI mengunci payload jika hasil ambigu dan menyediakan kirim ulang yang sama; konflik definitif mengizinkan refresh pilihan.
- Migrasi aditif schema v3: `regions.active/version`, `agents.version`, snapshot `agent_name/agent_team/agent_channel` pada assignments dan tabel `assignment_overrides`. Assignment lama diisi dari profil yang tersedia saat migrasi; bukan rekonstruksi histori profil yang belum pernah tersimpan. Laporan memakai snapshot dan report_scopes agar histori tetap dapat dipilih setelah profil pindah alur/wilayah. Kolom bisnis lama dipertahankan.
- Flutter `master_page.dart` diakses melalui Petugas → Kelola master operasional, berisi formulir responsif, pencarian/status, tab Wilayah/Petugas/Audit perubahan. `override_dialog.dart` menampilkan skor/tim, kandidat layak dan alasan penolakan seluruh kandidat, review/Batal, error/retry. Detail siklus menunjukkan snapshot profil. Menu utama tetap lima supervisor/tiga petugas.
- Tidak membutuhkan dependensi atau API key baru. Editor aturan skor/ambang/SLA, admin akun lengkap, PostgreSQL/ML, notifikasi, dan runner native belum menjadi hasil sprint ini.

Verifikasi otomatis:

- **57 tes backend lulus** (47 regresi + 10 master/override): master aktif/nonaktif/unik/versi, akun atomik/hash/tanpa password audit, penolakan perubahan routing saat tugas aktif, kapasitas, histori laporan setelah profil dipindah, aturan override/scope/terminal, retry identik/payload bentrok, concurrent kapasitas, pembayaran/proyeksi skor/pemindahan akses, qualified/pencairan dan outcome lewat SLA, role/audit, migrasi v2→v3/restart berulang, perubahan wilayah setelah preview impor, dan race penonaktifan wilayah versus aktivasi petugas.
- **53 tes Flutter lulus** (45 regresi + 8): pembuatan profil/akun dan scrolling pada lebar 390/1440, validasi pilihan/alasan, review/Batal, kirim tunggal/penguncian saat pending, retry ambigu dengan key/payload identik, konflik versi master/refresh/isi ulang alasan, pencarian/audit/error tanpa data lama, dan refresh opsi setelah409. Regresi laporan/CSV/impor/sesi/pagination/batch tetap lulus.
- Analyze bersih, build web/Wasm dry run dan Python compile check berhasil. Suite web lengkap diulang setelah mempersempit lebar dialog konfirmasi desktop, tetap 53 lulus. Peringatan Cupertino lama tetap ada; ikon aplikasi memakai Material. Tidak mengklaim pengujian native atau keyboard perangkat fisik.

Verifikasi browser-act, Chrome terpisah:

- Helper `scripts/prepare-master-uat.py` membuat backup baru **runtime/master-uat.db** dan prasyarat sintetis melalui API salinan: **151 kasus, 7 assignment, 13 aktivitas, 30 audit** sebelum browser. Tiga fixture: Medium `TAG-DB240E856F` dengan Rp20.000/tidak terhubung, pengajuan `AJU-1896E8B5EB` lolos verifikasi, High `TAG-613A9C34C4` belum ditugaskan. Ini setup UAT, bukan klaim pembuatan fixture lewat UI. Database utama hanya dibaca untuk backup/fingerprint.
- Desktop: Tambah wilayah YOG / Yogyakarta → ubah nama Yogyakarta Demo dan nonaktif → aktifkan kembali berhasil. Master menampilkan revisi 1→2→3 ([nonaktif](evidence/sprint6-region-inactive.png)). Wilayah baru tersedia pada formulir kasus, yang berhasil membuat **UAT S6 Kasus Wilayah Baru** di YOG. Penonaktifan sesudah itu ditolak dengan pesan kasus terbuka, wilayah tetap aktif ([penolakan](evidence/sprint6-region-open-case-block.png)).
- Tambah petugas **SMG-S6-B**, penagihan / SMG / Tim B / Lapangan, kapasitas 1, username **uat-s6-b** melalui form desktop berhasil ([form](evidence/sprint6-agent-create-desktop.png)). Login akun baru pada bingkai web 390×844 berhasil; sebelum override dashboard 0 kasus.
- Kasus Medium: preview override menunjukkan versi 4, **Tim B/skor55,5**, sedangkan kasus/siklus lama tetap 67,5. Alasan pendek ditolak; pilih SMG-S6-B → review → Batal mempertahankan input tanpa mutasi. Konfirmasi berikutnya mengalihkan **SMG-col-A → SMG-S6-B**, siklus 2, paid tetap Rp20.000 ([hasil](evidence/sprint6-reassign-result.png)). Akun baru kemudian melihat tepat kasus tersebut tanpa kontrol supervisor.
- Ubah Tim B→A saat memegang tugas aktif ditolak ([guard](evidence/sprint6-active-routing-block.png)). Muat versi terbaru memulihkan Tim B; nonaktifkan penerimaan assignment berhasil tanpa mencabut tugas/login. Petugas baru tetap dapat mencatat **Rp80.000** melalui browser ponsel, menjadi lunas/siklus success ([pembayaran](evidence/sprint6-new-agent-payment-mobile.png)).
- Kasus High: daftar kecocokan dapat digulir dan dropdown hanya menyediakan petugas layak; petugas baru yang nonaktif/telah memakai kuota tidak tersedia. Override awal eksplisit ke **SMG-col-B** berhasil, siklus 1. High tetap Tim B meskipun skor 61. Ini assignment pertama, berbeda dari dua pengalihan.
- Setelah tugas petugas baru selesai, perubahan profil **SMG-S6-B → nama Pengajuan Bandung Sintetis S6, BDG/pengajuan/Tim A/Tele** berhasil; akun/ID tetap dan revisi 3 ([profil](evidence/sprint6-profile-after-completion.png)). Laporan penagihan/siklus masih dapat memilih petugas tersebut walaupun sekarang berprofil pengajuan. Hasil lama tetap **Lapangan Sintetis S6**, satu siklus berhasil, realisasi **Rp80.000** ([ringkasan](evidence/sprint6-historical-report.png), [rincian](evidence/sprint6-historical-cycle-details.png)); snapshot database mengonfirmasi Tim B.
- Ponsel 390×844: Tambah **SMG-S6-ORI**, SMG / pengajuan / Tim A / Tele, kapasitas 2, username **uat-s6-ori** berhasil. Form bergulir, dropdown dan footer simpan tampil utuh ([form](evidence/sprint6-master-mobile-form.png)). Override pengajuan terverifikasi memilih petugas baru; konfirmasi tampil tanpa overflow ([konfirmasi](evidence/sprint6-override-confirm-mobile.png)). Status qualified/dokumen lengkap tetap terbawa, skor siklus baru 95 (siklus lama 81), kemudian pencairan simulasi **Rp1.000.000** berhasil ([pencairan](evidence/sprint6-origination-disbursed-mobile.png)). Logout/login akun uat-s6-ori berhasil dan antrean menampilkan tepat satu pengajuan dicairkan tanpa fitur supervisor.
- Audit perubahan pada UI memuat actor, alasan, objek dan **SMG-ori-A → SMG-S6-ORI/siklus 2**, juga perubahan profil dan pembuatan akun ([audit](evidence/sprint6-master-audit.png)). Total **10 event master/override**, tiga record idempotency; invalid/Batal tidak menambah event.
- Backend UAT dihentikan: Muat ulang master menyembunyikan hasil lama, menampilkan error/Coba lagi, sesi tidak dihapus ([error](evidence/sprint6-master-network-error.png)). Restart UAT PID 22180 → **seluruh isi/SHA-256 10 tabel identik**, termasuk master/profil/snapshot/key override. Retry memulihkan audit. Bukti `runtime/master-before-restart.json` dan `master-after-restart.json`.
- UAT akhir **152 kasus, 14 petugas, 15 user, 4 wilayah, 10 assignment, 15 aktivitas, 48 audit, 3 override**. Dibanding setup browser: +1 kasus / +2 petugas / +2 akun / +1 wilayah / +3 assignment / +2 aktivitas / +18 audit. Bukti detail/snapshot `runtime/master-browser-results.json`. Password tidak berada pada audit; ini juga diperiksa tes backend.
- Temuan lingkungan: Chrome pada origin127.0.0.1 masih memuat JS sprint sebelumnya meskipun file build/server baru benar. Origin localhost membuktikan tombol baru tersedia. Diganti server release lokal menjadi **scripts/serve-web.py**, bind loopback/no-store dan GET mengabaikan validator tanggal lama. Origin127.0.0.1 kemudian memuat UI baru; GET aset dengan If-Modified-Since masa depan tetap 200/no-store. Tidak mengubah pengaturan izin browser pengguna.
- Review visual menemukan konfirmasi override desktop terlalu lebar. Lebar konten dibatasi 560, suite/build diulang, lalu reload final → review kasus TAG-0001 → Batal/Tutup terbukti tidak menambah assignment/audit dan dialog tampil proporsional ([build final](evidence/sprint6-final-confirm-layout.png)). Sebagian scrolling iframe dilakukan pada elemen semantik karena CLI menggulir parent; appbar dipastikan terlihat sebelum Back/logout. Seluruh aksi bisnis UAT tetap melalui UI; API hanya untuk fixture dan tes otomatis.

Pemulihan lingkungan:

- Backend kembali ke **runtime/assignment.db**, PID **9808**. Server web baru port 5173 PID **18544**, release final. Sesi salinan ditolak 401 dan navigator detail dibersihkan. Login ulang supervisor → Master → pencarian S6 menunjukkan **0 dari 12 petugas**, tanpa akun/profil UAT ([pemulihan](evidence/sprint6-main-restored.png)).
- Fingerprint seluruh **kolom lama** pada sembilan tabel sumber identik sebelum/sesudah UAT: **148 kasus, 5 assignment, 9 aktivitas, 21 audit, 12 petugas, 13 user, 3 wilayah**, import_batches/import_case_refs kosong. Perubahan yang diharapkan hanya migrasi aditif schema 3: aktif/versi default master, snapshot lima assignment lama, tabel override kosong. Tidak mengklaim byte seluruh file SQLite identik setelah migrasi. Bukti **runtime/master-final-check.json**; API/web HTTP 200. Database/workbook UAT dan seluruh hasil demo sebelumnya dipertahankan.

Sprint berikutnya yang disarankan: **Sprint 7 — PostgreSQL, SQLAlchemy/Alembic dan migrasi data terpadu**, termasuk backup/migrasi tanpa hilang histori, konfigurasi lokal, transaksi concurrent pada database tujuan, regresi dan UAT browser. Periksa ketersediaan PostgreSQL sebelum mulai; SQLite tetap aktual sampai migrasi itu teruji. Sprint 7 belum dikerjakan. Gunakan satu nomor utuh, tanpa sub-sprint huruf.

## Sprint 7 — PostgreSQL, SQLAlchemy/Alembic dan migrasi terpadu

**Status: selesai, 28 Oktober 2026.** Database demo utama sudah beralih ke **PostgreSQL assignment_demo, 127.0.0.1:15432**, bukan sekadar dependency/adapter. Klaster proyek memakai binary PostgreSQL18.1 terpasang, bind loopback dan autentikasi SCRAM. Service PostgreSQL18 pengguna di5433 tetap berjalan dan tidak diubah. Config/password acak hanya di `runtime/postgres-local.json`, diabaikan Git. Tidak membutuhkan API key eksternal.

Implementasi:

- SQLAlchemy Core2.0.55, Alembic1.20.1 dan psycopg3.3.6 terpasang/pinned. `db_sa.py` menyediakan engine/pool dan adapter parameter bagi layanan lama; SQLite tetap didukung untuk tes/fallback. Tidak mengklaim migrasi ke ORM. Uang integer rupiah, waktu UTC ISO text, JSON text dan workbook BYTEA mempertahankan kontrak API sebelumnya.
- Schema lintas database dikelola Alembic **0001_portable**, dengan snapshot baseline beku dan guard startup concurrent. Metadata/FK/constraint/index diuji tanpa drift. File SQLite lama diadopsi lewat migrasi legacyv3 tanpa menghapus histori. Urutan impor memakai `upload_order`, menggantikan rowid khusus SQLite.
- Mutasi PostgreSQL mengambil advisory transaction lock bersama dan READ COMMITTED agar pemeriksaan kapasitas, aktivitas/idempotency, master, impor dan assignment atomik. Pembacaan memakai snapshot REPEATABLE READ/READ ONLY. Ini mempertahankan semantik single-writer prototype; optimasi throughput paralel belum dilakukan.
- `app/migrate.py` dan `scripts/migrate-postgres.py` membaca sumber SQLite read-only, membuat backup baru, meng-upgrade hanya backup, memeriksa FK, menyalin sepuluh tabel bisnis dalam satu transaksi, membandingkan jumlah/SHA-256, serta memulihkan sequence di atas ID/counter lama. Sesi login sengaja tidak disalin; hash password/akun tetap. Target berisi data ditolak; receipt snapshot membuat retry idempoten tanpa menimpa perubahan sesudah migrasi.
- `postgres-local.py` mengelola hanya klaster proyek. Startup default memilih config aktif PostgreSQL; mode SQLite eksplisit tersedia. `--activate` pada migrator memilih demo lokal setelah verifikasi/report; target UAT/URL lain ditolak. Health memeriksa koneksi nyata dan mengembalikan503 saat penyimpanan terputus. `backup-postgres.py` membuat pg_dump memakai exported snapshot dan memverifikasi restore ke database baru. [Runbook](postgresql.md) memuat startup, cutover, backup, fallback dan batasnya.
- Perbedaan driver yang ditemukan sudah diperbaiki: akses `lastrowid` hanya pada INSERT identity/RETURNING, boolean domain dibind sebagai integer, dan konversi placeholder/LIKE tidak mengubah literal SQL. Kedua backend telah diuji ulang sesudah perbaikan.

Pengujian otomatis aktual:

- **57 tes backend SQLite lulus** (`test-backend.ps1`). **56 skenario backend PostgreSQL lulus**, satu tes khusus PRAGMA/drop-column tetap diuji pada SQLite (runner PostgreSQL:57 run/1skip). Runner memakai schema UUID terisolasi; pemeriksaan akhir menunjukkan nol schema tes tertinggal.
- **8 tes migrasi PostgreSQL lulus**: kesamaan data/BLOB/hash/ID, sesi tidak disalin, rollback fault injection/retry, target nonempty, replay setelah aktivitas target, sequence SQLite tinggi9000, head/schema/FK/restart, snapshot baca, sumber FK rusak serta parameter/literal/pencarian. Beberapa pemeriksaan digabung dalam satu test case.
- **53 tes Flutter lulus**, analyze bersih, release build web berhasil menggunakan Flutter3.41.6/Dart3.11.4. Python compile check dan parser startup PowerShell lulus. Tidak ada fitur UI besar baru dalam sprint ini.
- Pengujian CLI tambahan: `--activate --target uat` ditolak sebelum copy; replay demo dengan `--activate` berhasil tanpa menggandakan baris. Bukti `runtime/postgres-main-activation.json`; receipt tetap satu.

Verifikasi browser-act, Chrome lokal terpisah:

- Migrasi awal UAT dari `runtime/master-uat.db` ke `assignment_uat_s7` cocok seluruh tabel bisnis: **152kasus,14petugas,15user,4wilayah,10assignment,15aktivitas,48audit,3override**. Seluruh file SQLite lama dipertahankan.
- Supervisor membuat penagihan **TAG-6CCD8F522D**, nominalRp100.000, Medium/SMG, auto-assignment TimA/skor67,5. Aktivitas tidak terhubung dan pembayaranRp25.000 tercatat. Override ke SMG-col-B memakai alasan/review, skor ulang55,5; siklus1 menjadi superseded, siklus2 membawa saldoRp25.000 ([override](evidence/sprint7-postgres-override.png)).
- Bingkai web **390×844**, login `smg-col-b`: hanya menu petugas/scope sendiri, mencari dan membuka kasus itu, mencatat sisaRp75.000. Kasus menjadi paid/Rp100.000, outcome siklus2 success; histori menampilkan pembayaran pada siklus terkait. Tampilan/scroll/form dapat dipakai tanpa overflow terlihat ([pelunasan ponsel](evidence/sprint7-postgres-mobile-paid.png)). Ini bukan pengujian native/perangkat fisik.
- Supervisor membuat pengajuan **AJU-1EA82312B5** Rp1.000.000, auto-assignment SMG-ori-A, melengkapi dokumen, verifikasi lalu pencairan simulasi. Status disbursed, paidRp1.000.000/outcome success ([pencairan](evidence/sprint7-postgres-disbursed.png)). Penolakan/aturan pengajuan lain tercakup regresi PostgreSQL; penolakan tidak diulang melalui UI pada sprint ini.
- Upload XLSX nyata, preview dan commit **dua kasus/Rp130.000**; `import_batches` committed dan dua referensi unik tersimpan. ID **TAG-27BAF306E6** dan **TAG-3173D2286A** ([impor](evidence/sprint7-postgres-import.png)). Master SMG-S6-ORI diperbarui kapasitas2→3 dengan alasan, versi/audit tersimpan ([master](evidence/sprint7-postgres-master.png)).
- Laporan portofolio penagihan filter UAT S7 menghasilkan **3baris**. Klik unduh benar-benar menyimpan CSV tiga baris, isi/nama pelanggan cocok dengan PostgreSQL; `runtime/postgres-csv-verification.json` menyimpan pemeriksaan ([laporan](evidence/sprint7-postgres-report.png)).
- Klaster PostgreSQL proyek dihentikan sementara, API tetap berjalan. Health503; reload laporan menyembunyikan hasil lama, menampilkan error/Coba lagi dan mempertahankan sesi ([gangguan](evidence/sprint7-postgres-outage.png)). Sesudah klaster dimulai ulang, jumlah/SHA seluruh **11tabel non-sesi termasuk receipt** identik; retry memulihkan tiga baris dengan filter sama tanpa login ulang ([pulih](evidence/sprint7-postgres-recovered.png)). Snapshot `runtime/postgres-before-restart.json`/`postgres-after-restart.json`.
- Akhir UAT **156kasus,13assignment,21aktivitas,68audit,4override,1batch/2referensiimpor**; master14petugas/15user/4wilayah. Bukti query final `runtime/postgres-browser-results.json`. UAT tidak bercampur dengan demo utama.

Cutover, backup dan kondisi akhir:

- Migrasi sumber utama `runtime/assignment.db` ke PostgreSQL **assignment_demo** terverifikasi: **148kasus (74+74),12petugas,13user,3wilayah,5assignment,9aktivitas,21audit**; imports/override kosong seperti sumber. SQLite asli tidak dihapus/ditulis ulang. Hash sepuluh tabel target sama dengan manifest; snapshot sumber asli tetap identik. Receipt/replay tidak menggandakan data (`runtime/postgres-main-migration.json`, `postgres-main-replay.json`, `postgres-final-check.json`).
- Backend dimulai ulang pada target utama PostgreSQL. Sesi UAT lama ditolak401 dan route lama dibersihkan; login supervisor baru berhasil. Dashboard browser menampilkan 74+74kasus, pembayaranRp1.200.000 dan pencairanRp5.000.000 ([demo utama PostgreSQL](evidence/sprint7-main-postgres.png)). Health storagepostgresql/API200 dan web200. API PID18380; server release no-store PID18544 pada saat penutupan, periksa ulang sebelum menjalankan instance.
- `pg_dump` custom **34.005byte**, restore dalam satu transaksi ke database baru `assignment_restore_s7_09992b807118`, seluruh **13tabel termasuk sesi/receipt/revision** cocok. Dump `runtime/backups/assignment-s7.dump`, bukti `runtime/postgres-backup-restore.json`; hasil restore dipertahankan. Fallback SQLite diuji login/dashboard148kasus pada **backup**, tidak menulis sumber asli (`runtime/postgres-sqlite-fallback.json`). Fallback bukan sinkronisasi balik perubahan PostgreSQL.
- Belum diverifikasi/diimplementasikan: HA/TLS remote, beban/throughput produksi, role migrasi/runtime terpisah, enkripsi/rotasi backup, deployment produksi. ML/segmentasi serta runner native belum dikerjakan; skor aktual masih rules-demo-v1. Panduan sprint lama menyebut SQLite sebagai kondisi historis, bukan storage utama saat ini.

## Sprint 8 — data historis dan pipeline analitik terpadu

**Status: selesai, 28 Oktober 2026.** Simulator longitudinal, snapshot fitur/label, quality gate, pemisahan waktu/identitas, persistence/API, Flutter supervisor, ekspor dan UAT browser dituntaskan sebagai satu sprint. Model ML belum dilatih dan skor operasional tetap rules-demo-v1. Panduan: [analitik historis](analitik-historis.md).

Implementasi:

- `historical.py` membangkitkan dua alur secara deterministik, versi `history-simulator-v1`/`point-in-time-v1`, dengan seed/config eksplisit dan raw event hanya sampai cutoff observasi. Dua kasus per identitas memungkinkan pengujian isolasi kelompok. Low selalu A, High B; Medium diacak dalam histori sintetis dengan propensity tim 0,5. Kebijakan ini terpisah dari assignment operasional dan tidak menjadi bukti kausal kecocokan petugas.
- Empat dataset: awal/penugasan ulang untuk penagihan/pengajuan. Allowlist fitur awal tanpa hasil siklus berjalan; fitur ulang hanya memakai histori siklus terdahulu yang sudah ditutup. Metadata identitas, aksi tim/propensity, label dan outcome terpisah dari objek prediktor `features`. `feature_max_at`/`label_ready_at` membuat cutoff dapat diperiksa.
- Label penagihan: seluruh tagihan lunas paling lambat 72 jam, membawa pembayaran terdahulu; parsial dan lunas terlambat bukan sukses. Label pengajuan: pencairan dalam **asumsi default 30 hari**, dapat dipilih 7–90 hari per run, terpisah dari SLA operasional 72 jam. Semua label menunggu jendela observasi penuh, termasuk hasil positif dini.
- Train/validation/test berdasarkan waktu keputusan dan kematangan label. `censored`, `early_reassignment`, `label_cross_boundary` dan `entity_cross_split` dikeluarkan dengan alasan; yang belum teramati tidak dipaksa menjadi label 0. Identitas eligible tidak muncul pada beberapa partisi. Quality gate memeriksa relasi/ID, waktu, urutan siklus, nominal, tim/propensity, kontrak serta derivasi snapshot/label sebelum penyimpanan.
- Alembic **0002_analytics** menambah lima tabel analytics_* tanpa mengubah kasus operasional. JSON raw/snapshot disimpan utuh, indeks kind/stage/split mendukung preview server. Generasi/quality gate dilakukan sebelum write lock; seluruh data run dan audit disimpan atomik. Request key diperiksa ulang di bawah lock agar retry/concurrent request tidak membuat run ganda. Run tidak mempunyai API edit/delete.
- API khusus supervisor menyediakan riwayat berpaginasi, detail/manifest/kamus, preview 25 sampel dan ZIP seluruh data. Ekspor memeriksa hash canonical data sebelum memberikan berkas dan menambah audit. Flutter dibuka dari **Ringkasan → Analitik historis**, dengan formulir/review/Batal, empat kelompok/distribusi kelas, fitur yang dapat dibuka, filter/paging dan unduhan. Payload/key pembuatan ambigu dipertahankan untuk retry.
- Perbaikan kompatibilitas: migrator dapat mengenali receipt Sprint 7 melalui fingerprint **snapshot sumber asli** ketika tabel baru mengubah hash struktur copy ternormalisasi. Retry tidak menyalin ulang data target yang sudah menerima histori analitik/audit baru. Tes dan CLI pada sumber utama membuktikan replay; bukti `runtime/sprint8-legacy-replay.json`.

Hasil pengujian otomatis aktual:

- **68 tes backend SQLite lulus**, termasuk 11 tes analitik baru. **67 skenario PostgreSQL lulus**, satu tes PRAGMA khusus SQLite tetap dijalankan pada SQLite (68 run/1 skip).
- **9 tes migrasi PostgreSQL lulus**, termasuk baseline→head tanpa metadata drift dan replay receipt sebelum penambahan schema analitik. Nol schema tes UUID tertinggal pada akhir pemeriksaan.
- **60 tes Flutter lulus** (7 tes analitik baru), analyze bersih, release build web berhasil. Tes baru mencakup review/Batal, paging/filter/fitur, ZIP pada lebar 390/1440, payload retry ambigu, error 422 yang tetap terlihat, pemulihan jaringan, respons filter terlambat serta role petugas. Python compile check lulus. Peringatan font Cupertino lama tetap ada; ikon UI memakai Material.
- Tes backend memeriksa reproduksibilitas default/seed berbeda, fitur awal bebas outcome berjalan, pembayaran 72 vs 73 jam/parsial, label pencairan 30 hari, histori pembayaran sebelum reassign, censoring/transfer dini, purge identitas/waktu, sumber rusak, RBAC/validasi, concurrent idempotency, rollback seluruh run, restart serta blokir ekspor saat hash rusak. Perbaikan UI yang ditemukan selama penulisan tes: refresh daftar setelah kegagalan generate sempat menghapus pesan error; refresh kini hanya dilakukan setelah pembuatan berhasil.

UAT browser-act, Chrome lokal terpisah:

- Supervisor login dan membuka analitik dari Ringkasan. Review dibatalkan lalu dijalankan; hanya **satu run HIST-DA17B9491C00** tersimpan pada PostgreSQL utama. Config default 3.000 kasus/alur, seed 281026, histori 2024-10-01 sampai 2026-10-01 UTC, batas train 2026-02-01 dan validation 2026-06-01.
- Hasil **6.000 kasus historis, 7.670 keputusan/sampel, 22.082 event**. **5.403 sampel eligible, 2.267 excluded**. Keempat kombinasi memiliki kedua kelas pada train/validation/test dan memenuhi pemeriksaan jumlah kelas demo (≥20 tiap kelas/partisi), bukan klaim kelayakan model produksi ([manifest desktop](evidence/sprint8-dataset-desktop.png)). Hash data `6d83caee3535776ae3377d8faffdd7ed300c313fa91e1c9928bc64cacaa4901a`.
- Desktop membuka fitur awal penagihan serta histori tertutup pada fitur ulang, mengganti ke pengajuan/ulang/Test, berpindah halaman dan melihat sampel berikutnya. Pengajuan awal/Validation diperiksa pada ponsel, sehingga keempat kombinasi benar-benar dibuka melalui UI ([awal](evidence/sprint8-initial-snapshot.png), [ulang](evidence/sprint8-reassignment-snapshot.png), [paging](evidence/sprint8-paging-test.png)).
- Unduh ZIP dibatalkan lalu dikonfirmasi. Berkas nyata di Downloads **854.885 byte**, enam file JSON/JSONL, tidak terpotong filter/pagination. Data hasil unduhan dibaca ulang, quality gate dijalankan ulang dan hash cocok. Salinan `runtime/sprint8-dataset.zip`; bukti `runtime/sprint8-download-verification.json`. Audit hanya satu generate dan satu export; Batal tidak menambahnya.
- Bingkai web **390×844**: formulir/scroll, input tanggal invalid `2026-02-30` ditolak, review/Batal, membuka run tersimpan, dropdown alur/partisi, pengajuan awal Validation (264 sampel), ekspansi fitur, dan alasan excluded dapat digunakan tanpa overflow terlihat. Tidak menguji keyboard/perangkat native ([form](evidence/sprint8-mobile-form.png), [validasi](evidence/sprint8-mobile-date-validation.png), [review](evidence/sprint8-mobile-confirm.png), [dropdown](evidence/sprint8-mobile-dropdown.png), [fitur pengajuan](evidence/sprint8-mobile-origination-snapshot.png), [excluded](evidence/sprint8-mobile-exclusions.png)).
- Logout/login `smg-col-a` pada bingkai: hanya tiga menu dan tanpa Analitik historis. Pembatasan seluruh endpoint analitik 403 untuk petugas/401 tanpa sesi telah diuji otomatis pada kedua database ([role](evidence/sprint8-mobile-agent.png)).
- Backend dihentikan sementara: Muat ulang histori menampilkan koneksi gagal/Coba lagi dengan sesi tetap ada. Dataset immutable yang sudah terbuka tetap merupakan snapshot lama; tidak ditampilkan sebagai hasil refresh baru. Setelah startup default, **18 tabel termasuk sesi/receipt/revision identik jumlah dan SHA-256**, UI retry pulih tanpa login ulang, dan run dibuka kembali dari server ([gangguan](evidence/sprint8-backend-outage.png), [pulih](evidence/sprint8-backend-recovered.png)). Bukti `runtime/sprint8-before-restart.json`/`sprint8-after-restart.json`.

Kondisi akhir dan batas:

- Demo utama tetap PostgreSQL **assignment_demo:15432**, head **0002_analytics**. Backend PID **30732** pada 8000, web no-store PID **18544** pada 5173 saat penutupan; periksa ulang kondisi proses. API/web 200. Service pengguna 5433 tidak diubah.
- Seluruh kolom pada sepuluh tabel operasional sebelum sprint, termasuk prefix 21 audit lama, tetap identik: **148 kasus, 12 petugas, 13 user, 3 wilayah, 5 assignment, 9 aktivitas**, imports/override kosong. Audit kini **23**, tambahan generate/export analitik saja. SQLite asli tidak ditulis ulang. Bukti `runtime/sprint8-operational-before.json` dan `sprint8-final-check.json`.
- Backup sebelum sprint **34.005 byte** dan sesudah sprint **1.048.492 byte** berhasil direstore ke database baru terpisah dan dibandingkan seluruh tabel. Bukti `runtime/postgres-before-s8-backup.json`, `runtime/sprint8-backup-restore.json`; dump/hasil restore dan semua UAT lama dipertahankan. Pengujian baru dilakukan pada schema UUID terisolasi atau modul analitik yang terpisah dari antrean operasional.
- Belum diimplementasikan: ingest histori nyata/Excel historis, snapshot historis dari aktivitas operasional yang belum direkam saat keputusan, model/preprocessing train-only, kalibrasi/registry, segmentasi, notifikasi, native dan produksi. Simulator bukan bukti akurasi pada nasabah nyata. Berikutnya **Sprint 9 — model predictive awal/reassign, evaluasi dan lifecycle terpadu**; gunakan fitur allowlist serta hanya sampel eligible, jangan memakai raw outcome/metadata sebagai prediktor.

## Estimasi penyelesaian keseluruhan prototype — enam sprint besar setelah Sprint7

Brief/SOW v2.1 dan kebutuhan data ditelusuri kembali. Target prototype mencakup web dan mobile, prediksi awal/ulang, segmentasi, override, integrasi tiruan serta UAT/serah terima. Pengajuan dengan data sintetis tetap mengikuti instruksi terbaru. Patokan pengerjaan **Sprint8–13**, satu kesatuan fitur/integrasi per nomor:

1. **Sprint8 — data historis dan pipeline analitik**: simulator longitudinal dua domain, snapshot fitur sebelum keputusan, definisi label/jendela, kualitas data dan pemisahan waktu/identitas. Data operasional sekarang belum menjadi dataset training.
2. **Sprint9 — model predictive dan lifecycle terpadu**: model awal/reassign per domain, baseline pembanding, evaluasi/kalibrasi, registry/version, serving dan fallback. Hasil sintetis dilabeli sebagai validasi simulator; tidak mengklaim efektivitas pada nasabah nyata atau dampak kausal petugas.
3. **Sprint10 — segmentasi dan decision support**: segmentasi yang dapat ditafsirkan, penjelasan/rekomendasi UI, aturan skor/ambang/SLA yang dapat dikonfigurasi dan audit/validasinya.
4. **Sprint11 — aplikasi native Android/iOS**: runner, konfigurasi jaringan/izin, alur petugas/berkas/unduhan, build serta UAT perangkat. Android dapat dikerjakan lokal; build/uji iOS memerlukan macOS/Xcode dan perangkat/simulator yang sesuai.
5. **Sprint12 — notifikasi dan integrasi operasional simulasi**: inbox in-app, adapter telephony/omnichannel tiruan, event/retry/idempotency dan pelengkapan administrasi operasional yang dibutuhkan acceptance.
6. **Sprint13 — penerimaan dan serah terima**: pengujian lintas role/platform, perbaikan hasil UAT, hardening untuk lingkungan demo, paket deployment uji, panduan/training dan checklist kebutuhan brief.

Ini estimasi pada penutupan Sprint7 untuk **prototype sesuai scope**, bukan janji nol bug/produksi siap dalam enam sesi. Sprint8 kini selesai; tersisa **lima sprint besar, Sprint9–13**. Bisa bertambah bila kebutuhan baru, definisi outcome belum disepakati, data nyata harus divalidasi atau lingkungan iOS belum tersedia. Integrasi live perbankan/WA/telephony, publikasi store, operasi produksi dan validasi model pada data nyata memerlukan cakupan/akses tersendiri; jangan menyamakan simulasi dengan integrasi nyata.

## Roadmap lanjutan — predictive analytics dan segmentasi

- Simulator historis longitudinal terpisah untuk penagihan dan pengajuan.
- Dataset snapshot sebelum keputusan, label terdefinisi, temporal holdout dan pemisahan identitas.
- Model awal/ulang per domain, baseline rules sebagai pembanding, evaluasi kalibrasi dan stabilitas.
- Segmentasi untuk insight, alasan rekomendasi, registry model/version, dan fallback bila data tidak cukup.
- Angka prediksi sintetis diberi label jelas; tidak membuat klaim produksi atau uplift kausal yang belum terbukti.

## Roadmap lanjutan — mobile, integrasi simulasi, dan UAT

Build mobile dan integrasi eksternal dikerjakan dalam sprint terpisah.

- Generate runner Android/iOS, konfigurasi jaringan development, build APK dan uji emulator Android; iOS pada macOS.
- UX petugas, notifikasi in-app, adapter telephony/omnichannel simulasi, kebijakan sync/offline jika dibutuhkan.
- Pengujian lintas role/platform, error recovery, acceptance scenario, paket demo dan panduan serah terima.
- Deployment demo setelah environment target ditentukan; integrasi live/store publication bukan hasil sesi pertama.

## Instruksi melanjutkan

### Sprint 9 — model predictive, evaluasi dan lifecycle terpadu

Implementasi sudah tersedia: empat regresi logistik awal/ulang per domain, preprocessing train-only, kalibrasi validation terpisah, evaluasi terhadap prior konstan/ranking rules, registry JSON checksum, aktivasi/rollback beralasan dan berversi, snapshot asal serta prediksi assignment, fallback eksplisit dan UI supervisor. Panduan: [model predictive](model-predictive.md). Head `0003_models`, 23 tabel total. Kasus legacy tidak diberi snapshot asal palsu. Low/High, kapasitas dan scope tetap berlaku.

Verifikasi otomatis: **82 tes SQLite lulus; 82 tes PostgreSQL dijalankan, 81 lulus/1 khusus SQLite dilewati; 9 tes migrasi PostgreSQL lulus**. Mencakup leakage, parity JSON, snapshot awal/ulang, domain fallback, transaksi/idempotency/race/revision, override preview, korupsi artefak, retry, ekspor dan restart. **71 tes Flutter lulus**, analyze bersih dan build web berhasil. Koreksi pesan refresh diuji pada laporan yang digulir dalam: snackbar terlihat di ponsel saat backend berhenti. PowerShell menganggap stderr peringatan Wasm sebagai error ketika seluruh stream diarahkan ke berkas; build tanpa pengalihan stream diulang dan berhasil, bukan kegagalan kompilasi.

UAT Chrome browser-act pada schema salinan `uat_s9_df39a8179ca4`, bukan database utama: aktivasi revision1; kasus baru TAG-9B3E32DD47 mendapat ML44,92% dan AJU-E48898B2EE ML42,31%; pengalihan TAG-FC6FE80D9F ke siklus2 ML25,09% membawa pembayaran sebelumnya Rp1,5 juta; AJU-6B198D6AAC siklus2 ML50,46% membawa dokumen/verifikasi. Petugas smg-col-b melunasi sisa Rp3,5 juta melalui UI, pengajuan dicairkan Rp5 juta; prediksi tersimpan tidak berubah. Model rollback revision2 lalu aktif kembali revision3 melalui dialog ponsel. Legacy TAG-0009 menampilkan fallback asal tidak tersedia. Review/Batal, laporan empat model, dropdown subset, fitur sebelum keputusan dan role petugas telah diperiksa pada desktop/bingkai390×844. Ini web, bukan native.

UAT akhir: **152 kasus, 11 assignment, 15 aktivitas, 47 audit, 4 asal kasus, 6 snapshot prediksi, 3 transisi model**. Seluruh isi/hash **23 tabel identik setelah backend benar-benar dihentikan dan dimulai kembali** (`runtime/sprint9-uat-before-restart.json`, `sprint9-uat-after-restart.json`). Hash 6 prediksi juga identik sebelum/sesudah rollback dan reaktivasi. Bukti kasus/lifecycle `runtime/sprint9-browser-results.json`, screenshot `docs/evidence/sprint9-*`.

Database utama hanya mendapat kandidat **MOD-2F47EACC9298** dan audit training/ekspor. ZIP unduhan browser 7.162 byte diverifikasi berisi empat model dengan hash **1accc24e5fc154841226a010bb321cbe07d5957c02e34db001bee1af0dc71cf0**. Test AUC0,54–0,64; dua model pengajuan belum mengungguli prior konstan pada validation-selection. Kandidat tidak otomatis diaktifkan pada demo utama; hasil simulator bukan validasi nyata/kausal. Demo utama dipulihkan (backend PID37368), semua data operasional/analitik lama serta SQLite asli identik; head0003_models, serving rules revision0. Sesi UAT mendapat401 sesudah pemulihan, navigator lama dihapus. Backup akhir1.063.263byte berhasil direstore dan seluruh23tabel dibandingkan (`sprint9-backup-restore.json`). Bukti utama `runtime/sprint9-final-check.json`.

Pengguna memperluas otorisasi pada 29 Oktober 2026: lanjut **Sprint10–13** berurutan dalam sesi kerja yang sama. Sprint11 tetap memerlukan bukti build/perangkat; macOS/Xcode tidak dapat dianggap tersedia di Windows. Jangan menandai seluruh proyek selesai bila ada penerimaan platform yang belum terverifikasi.

### Sprint 10 — segmentasi dan decision support terpadu

**Status: selesai,29Oktober2026.** Kebijakan rules/ambang/SLA berversi, audit, preview/konflik override/impor, prioritas batch terbaru, empat cohort KMeans train-only, evaluasi/stabilitas, lifecycle paket segmen melalui kebijakan, snapshot deskriptif serta kontribusi prediksi dalam detail. Panduan [keputusan dan segmen](keputusan-dan-segmen.md). Success penagihan72jam tetap; follow-up SLA terpisah. Head0004_decisions/25tabel.

Tes:90tes SQLite full lulus, ditambah tes prioritas batch terbaru dalam8tes keputusan lulus padaSQLite danPostgreSQL (total91terkoleksi);89tes PG full sebelumnya88lulus/1SQLite-onlyskip, lalu10tes impor dan8keputusan pada kode akhir lulus.9tes migrasi lulus.77tes Flutter/analyze/build lulus; build diulang setelah memperjelas teks ambang model. Regresi lengkap akhir lintas sprint dijalankan lagi saat penerimaanSprint13.

UAT browser-act Chrome pada schema baru `uat_s10_d4d07904ff56`: training/Batal lalu konfirmasi, publikasi review/Batal/konfirmasi revisi1; evaluasi menemukan clustering kalender melemah pada test, sehingga vektor cluster dibatasi ke ciri operasional. Kandidat lamaUAT dipertahankan; training ulang **SEG-23AB6D1B37AF** dipilih melalui revisi2. Profil, empat cohort dan metrik ditinjau ([profil](evidence/sprint10-profile.png)). Silhouette test paket akhir sekitar0,24–0,27; bukan validasi bisnis nyata.

Kasus UI **TAG-A92675800D**,Medium/SMG/skor67,5 ditugaskan keTimB/SMG-col-B karena ambang70; SLA tindak lanjut24jam dan segmenS2 terekam ([snapshot](evidence/sprint10-decision-snapshot.png)). Publikasi ponsel390×844 mengubah ambang60 pada revisi3; snapshot kasus tetaprevisi2. Form/dropdown/dialog/scrolling diperiksa ([review](evidence/sprint10-mobile-review.png)). Login smg-col-b hanya melihat satu kasus miliknya, tanpa kontrol keputusan. Aktivasi ML melalui review, lalu UI membuat/menugaskan **AJU-C09D77BCD9**:ML42,31%,segmenS2,revisi3,SLA48jam; panel kontribusi berfungsi ([faktor](evidence/sprint10-model-explanation.png)). Alur pembayaran/pencairan penuh telah diujiSprint9; tidak diklaim diulang diSprint10.

UAT akhir150kasus/7assignment/9aktivitas/35audit,2snapshot/2asal,2paket segmen/3revisi kebijakan/1transisiML. Seluruh25tabel identik setelah restart aktual (`sprint10-before-restart.json`,`sprint10-after-restart.json`); detail hasil `sprint10-browser-results.json`. Restore utama dan login ulang berhasil; training UI utama menyimpan kandidat **SEG-D83C7A70315B**, kebijakan tetaprevisi0/tanpa segmen aktif,MLtetaprules. Seluruh data operasional/analitik/model lama danSQLite asli identik (`sprint10-final-check.json`), hanya satu audit segmen baru. Backup1.071.203byte berhasilrestore/verifikasi25tabel. Tidak ada UAT yang dihapus.

Sprint11 dimulai berikutnya: runner Android/iOS, jaringan demo terbatas, picker/unduhan native, build dan UAT Android. SDK Android/Java/emulator tersedia; belum ada perangkat berjalan. Windows tidak menyediakan toolchain build iOS.

### Sprint 11 — native Android/iOS dan berkas

**Android/web selesai; build dan UAT iOS masih terbuka.** Runner Android/iOS digenerasi ke scaffold terpisah lalu hanya folder platform disalin, kode aplikasi lama tidak dibuat ulang. Android demo/production, INTERNET, HTTP demo dibatasi loopback/emulator dan production menolak cleartext. iOS14/Swift/Podfile dan ATS exception hanyaDebug disiapkan. Signing store belum tersedia. Panduan [mobile native](mobile-native.md).

file_picker13.3.0 dipin; picker XLSX memakai stream terbatas5MiB, penyimpanan CSV/XLSX/ZIP lewat dialog sistem, cancel dan callback sesudah disposal ditangani. **83tes Flutter lulus**, analyze bersih/build web berhasil.6tes adapter baru mencakup bytes/MIME/cancel/ukuran/berkas berubah/disposal. Pemeriksaan XML/plist memastikan policy jaringan; itu bukan build iOS.

APK ordinary entrypoint `lib/main.dart` berhasil: **runtime/artifacts/assignment-s11-demo-debug.apk**,152.054.613byte,SHA256 **cd2a4247bde4162eac735c6216f793541e12bad3d0ba88c467b3c8a15c63dd0e**. Dipasang pada emulatorPixel_5 Android14/API34. Native integration test **lulus1skenario**,2menit17detik: supervisor membuat kasus melaluiUI, assignment/reassign, logout/login smg-col-a, bayarRp400.000 laluRp600.000 menjadi lunasRp1juta/siklus2success; supervisor membuat pengajuan, dokumen→verifikasi→cairRp1juta serta pengajuan lain→penolakan. Read API hanya memeriksa hasil, seluruh mutasi workflow lewat widget UI Android. Hasil **TAG-CC95EC97B5 paid**,**AJU-1F975A88C8 disbursed**,**AJU-7DFE8E7BCE rejected**. Bukti `runtime/sprint11-native-results.json`, [aktivitas native](evidence/sprint11-stage.png).

Probe adapter pada Android nyata/emulator juga **lulus1skenario**,1menit2detik: konfirmasi Save/Open melalui dialog OS menghasilkan XLSX6.779byte, dibaca ulang identik byte-per-byte dan dibuka olehopenpyxl. [Save](evidence/sprint11-native-save-dialog.png), [Open](evidence/sprint11-native-open-dialog.png). Probe ini harness adapter, bukan klaim commit impor bisnis native lengkap. Pengujian workflow memakai test input Flutter deterministik; uji tambahan pengetikan IME melalui adb pada APK biasa berhasil login smg-col-a, menampilkan tiga navigasi tanpa kontrol supervisor ([IME/role](evidence/sprint11-native-agent-real-ime.png)).

Temuan harness: build pertama terganggu regenerasi plugin ketika dependency berubah bersamaan denganGradle; build berurutan berhasil. Pengetikan otomatis yang mencampur test input dengan IME nyata mereset isian username; harness dipisahkan, lalu input IME nyata diverifikasi tersendiri. Empat percobaan gagal sudah membuat kasus/siklus sebagian padaUAT; semuanya dipertahankan dan dibedakan dari3kasus skenario lulus, tidak dihapus untuk merapikan hasil. Tidak ada bukti bug workflow aplikasi dari kegagalan harness tersebut.

Regresi Chrome browser-act: unduh XLSX nyata valid, unggah penagihan-valid.xlsx→preview3valid/Rp600.000→persetujuan kolom→commit3kasus, dan unduhCSV laporan. [Preview](evidence/sprint11-web-import-preview.png),[hasil](evidence/sprint11-web-import-result.png). Alur ini pada schemaUAT yang sama, bukanutama. UAT akhir **158kasus/14assignment/15aktivitas/57audit,10asal/9snapshot,1batch/3referensiimpor**. Seluruh25tabel identik setelah restart backend aktual (`sprint11-final-before-restart.json`,`sprint11-after-restart.json`). SQLite asli dan data utama tetap dipertahankan; startup default dipulihkan setelah UAT.

Belum terverifikasi: build/signing/workflow/picker/keyboard iOS, perangkat Android fisik, distribusi store. Pertanyaan aksesMac sudah diajukan secara asinkron; pekerjaanSprint12/13 tidak menunggu jawaban. Jangan menyebut project100%diterima selama gateiOS masih terbuka.

### Sprint 12 — notifikasi dan integrasi operasional simulasi

**Status: selesai.** Inbox assignment, pengingat SLA deduplikasi, telephony/omnichannel tiruan, antrean persisten/backoff/dead-letter/recovery/receipt, kontrol akun/login/reset/revocation, scope, audit dan retry idempotent. Layout akhir dan pemulihan utama telah diperiksa (`sprint12-final-check.json`). Panduan [operasi dan notifikasi](operasi-dan-notifikasi.md). Tidak ada komunikasi/API vendor nyata. Head0005_operations menambah5tabel;30tabel total, tanpa menulis ulang user lama.

**101tes SQLite lulus;101tes PG dijalankan,100lulus/1khususSQLite dilewati;9tes migrasi lulus.** Tambahan10tes mencakup inbox/scope/pengalihan, job concurrent/replay, backoff/dead-letter/recovery, pembatalan terminal/siklus/akun, rollback audit, reset/revocation/hash/tanpa password audit, role dan restart. **91tes Flutter/analyze/build lulus**,8tes baru untuk390/1440, review/Batal, password review, read/paging, scope/error, retryambigu dan tab terkunci. Build/tes akhir diulang setelah menyingkat tab Integrasi yang terpotong pada ponsel.

UAT Chrome browser-act pada schema `uat_s12_e85d8248a43e`: supervisor membuat **TAG-2CDAFA9647**,Medium/SMG/Rp100.000 dan menugaskan keSMG-col-A. Inbox petugas menerima satu notifikasi, tandai dibaca dan Buka kasus berfungsi. Petugas membuat jobTelephony melalui ponsel, tanpa kontrol skenario gangguan. Supervisor membuat Omnichannel gagal sekali setelah review/Batal/konfirmasi. Proses UI menghasilkan **JOB-9EF3CFE8BA864E96 delivered1kali**, **JOB-D6B214E25032431E retry→delivered2kali**, receipt unik dan histori tampil ([histori](evidence/sprint12-omnichannel-history.png)). Petugas melihat job dalam scope;smg-ori-a melihat0job penagihan.

Kontrol smg-col-a melaluiUI: nonaktif+reset mencabut sesi petugas yang sedang terbuka ([401](evidence/sprint12-revoked-session.png)); login dengan password baru ditolak selama nonaktif. Aktivasi ulang memungkinkan login password hasilreset. Supervisor di ponsel memulihkan password demo dalam revisi3; tugas tetap1aktif dan master tidak berubah ([review](evidence/sprint12-mobile-account-review.png)). Audit/payload tidak berisi password; helper verifikasi memastikan passworddemo kembali berlaku padaUAT saja.

Job ketiga **JOB-B078F4124AAA45B1** menjalani3kegagalan pada jadwalbackoff hingga dead ([dead](evidence/sprint12-dead-letter.png)). Pemulihan melalui dialogponsel mempertahankan histori, lalu percobaan4delivered/limit6 ([empatpercobaan](evidence/sprint12-recovered-four-attempts.png)). Job tidak menambah aktivitas/transaksi: digest seluruh9aktivitas identik denganbaseline.

Fixture API `prepare-operations-sla-uat.py` membuat **AJU-4250150BD6**100jam sebelumjamUAT pada schema salinan, bukanpembuatanbrowser/backfill. PindaiSLA melaluiUI menghasilkan1pengingat; ulangi dengankeybaru menghasilkan0. Login smg-ori-a menampilkan tepat assignment+pengingatSLA ([inbox](evidence/sprint12-mobile-sla-notification.png)); scan tidak memfinalkan outcome.

UAT akhir **150kasus,7assignment,9aktivitas,46audit,16notifikasi,3job/7percobaan/3receipt,15request operasi,1kontrolakun(revisi3aktif)**. Datahasil `runtime/sprint12-browser-results.json`. Setelah backend dihentikan, refresh menyembunyikan job lama/menampilkanerror tanpa menghapus sesi; restart→seluruh30tabel identik→refreshpulih tanpa loginulang (`sprint12-before-restart.json`,`sprint12-after-restart.json`). Backup utama sebelum modul1.081.468byte berhasilrestore/verifikasi30tabel. Pengguna tidak diminta mengulang konfigurasi izin browser.

### Sprint 13 — penerimaan, hardening dan serah terima

**Selesai untuk web, Android emulator dan demo lokal; gate iOS tetap terbuka.** Versi aplikasi/API **0.13.0**, Android versionCode13. Pembatasan login gagal persisten memakai bucket hash pasangan peer/username (5 kegagalan) dan peer (30 kegagalan), fixed window15menit,429/Retry-After. Penolakan401 disimpan setelah transaksi commit; sukses membersihkan pasangan, restart tidak mereset budget. Identitas tidak memakai forwarded headers pada startup lokal. Tabel baru `login_failures` melalui revision0006_hardening;31tabel total, tanpa menulis ulang data lama. Password/username/IP mentah tidak disimpan dalam bucket.

Header no-store, nosniff, no-referrer dan SAMEORIGIN berlaku pada API dan static bundle. Static web opsional dipasang sesudah route API; API Flutter dapat memakai origin halaman. Paket demo allowlist memuat compiled web, aset renderer lokal, backend/migrasi, requirements, panduan dan manifest SHA256. Tidak membawa runtime workspace, database, config/URL PostgreSQL berkredensial atau sesi. Startup loopback8080 membuat SQLite sendiri144kasus. ZIP dapat dijalankan dengan Python/dependensi tanpa Flutter SDK. **Ini deployment demo lokal terverifikasi, bukan deployment publik/produksi.** Panduan [penerimaan dan serah terima](penerimaan-dan-serah-terima.md), README utama, arsitektur dan runbook PostgreSQL diperbarui.

Regresi akhir: **106 tes SQLite lulus** (190,437detik); **106 tes PostgreSQL,105lulus/1khususSQLite dilewati** (547,363detik); **9 tes migrasi lulus** (53,012detik). Lima tes hardening baru menguji persistensi/konkurensi/batas waktu/spray/proxy palsu/privasi/static traversal serta headers. **93 tes Flutter lulus**, analyze bersih, build web normal dan bundle same-origin berhasil. Dua tes endpoint baru memeriksa origin/port/query serta konfigurasi native kosong. Python compile check dan parser seluruh script PowerShell lulus. Peringatan font Cupertino masih muncul ketika tree-shaking; ikon Material yang dipakai tampil dalam UAT.

Android native integration test akhir **lulus1skenario,2menit57detik** pada schema `uat_s13_7b7893bcf2d8`, backend terpisah port8001. Mutasi melalui UI: create/assign/reassign, petugas membuka inbox/tandai dibaca/Buka kasus, bayar400ribu+600ribu, pengajuan dokumen/verifikasi/pencairan1juta serta penolakan pengajuan lain. Kasus **TAG-F6ED0BDF90 paid/siklus2**,**AJU-3F8C06DC5A disbursed**,**AJU-0FB6AF6991 rejected**. Scope/kontrol supervisor diperiksa. UAT akhir151kasus/9assignment/15aktivitas/40audit/4notifikasi. Seluruh31tabel identik sesudah restart backend aktual (`sprint13-native-before/after-restart.json`). Hasil `sprint13-native-results.json`.

APK biasa `lib/main.dart` berhasil dibuild/dipasang/dibuka ke login: **runtime/artifacts/assignment-demo-debug-20261028-235617.apk**,176.769.995byte,SHA256 **c946a200e60d01efc300106387ea2b981b975ddcfe3505b64d812edc9558d972**. API APK10.0.2.2:8000, versionName0.13.0-demo. Emulator sempat menampilkan ANR System UI saat startup/tes paralel, kemudian tes tetap selesai lulus. Pemeriksaan IME APK biasa tambahan padaSprint13 berhenti ketika AVD terkunci PIN yang sudah ada; PIN tidak ditebak/diubah. Bukti IME nyata yang lulus tetapSprint11. Screenshot hitam saat perangkat tidur bukan bukti UI berhasil dan tidak dipakai sebagai hasil penerimaan. Emulator tidak diwajibkan berjalan setelah tes; data AVD dipertahankan.

Paket kandidat ZIP12.565.800byte diekstrak ke `runtime/demo-acceptance-s13`, manifest diverifikasi lalu benar-benar dijalankan pada8080 dengan SQLite baru. **UAT Chrome browser-act**: supervisor membuat **TAG-0B5DBE8F66**,assignSMG-col-A,kontak→bayar400ribu(statusaktif)→600ribu(lunas1juta); membuat **AJU-8E0B824ACF**,assignSMG-ori-A,dokumen→verifikasi→cair1juta. Petugas smg-col-a login, hanya inbox/scope sendiri, tandai dibaca dan Buka kasus berfungsi. [Parsial](evidence/sprint13-bundle-partial.png),[lunas](evidence/sprint13-bundle-paid.png),[cair](evidence/sprint13-bundle-disbursed.png). Main web390px sesudah restart/login petugas menampilkan tiga navigasi tanpa kontrol supervisor ([role](evidence/sprint13-main-mobile-agent.png)).

Enam percobaan login akun fiktif melalui UI menghasilkan lima401 lalu429 dengan pesan ramah ([throttle](evidence/sprint13-bundle-login-throttle.png)). Backend paket dihentikan, SQLite dibackup saat berhenti, lalu dimulai lagi: **seluruh31tabel identik**, kedua budget tetap5, UI tetap menolak sampaiwindowberakhir. Paket UAT akhir146kasus/2assignment/6aktivitas/10audit/2notifikasi(1dibaca), bukti `sprint13-bundle-results.json` dan `sprint13-bundle-before/after-restart.json`. Penolakan/pengalihan native diuji pada schemaPG terpisah, tidak diklaim diulang melalui paket.

Demo utama dipertahankan: **148kasus,12petugas,13user,3wilayah,5assignment,9aktivitas,26audit**, seluruhhashbisnis sama denganbaselineSprint13; SQLite asli sama denganbaselineSprint9. Kandidat model/segmen tetap, serving rules/policyrevisi0. Seluruh31tabel identik saat main benar-benar direstart (`sprint13-main-before/after-restart.json`); API versi0.13.0/PG200. Bukti `sprint13-final-check.json`. Backup **runtime/backups/assignment-after-s13.dump**,1.082.477byte berhasilrestore dan cocok31tabel (`sprint13-backup-restore.json`). Service pengguna5433 tidak diubah. Semua UAT/backup lama dipertahankan.

Paket serah terima final **runtime/artifacts/assignment-studio-0.13.0-demo.zip**,12.568.287byte,SHA256 **32070b949afd84c60961e6d440b783fcdaa6974d68031472a08e6aaa10a7714d**,91berkas. Backend/web dan launcher sama byte-per-byte dengan kandidat yang menjalani UAT; panduan diperbarui. Ekstraksi baru `runtime/demo-release-s13`, checkmanifest/start8081/API0.13.0/SQLite serta login supervisor/dashboard melaluiChrome berhasil;144kasus/0aktivitas membuktikan ZIP bersih. [Dashboard bersih](evidence/sprint13-release-clean-dashboard.png). Scan tidak menemukan database/config/password PostgreSQL privat padaarsip. Packaging sempat memangkas suffix nama semver; diperbaiki dengan append `.zip`, artefak sebelumnya dipertahankan. Bukti `runtime/sprint13-release.json`. Database UAT yang telah dipakai tidak dibundel.

### Instruksi sesudah Sprint 13

### Review GitHub dan kesiapan hosting publik — 29 Oktober 2026

Permintaan pengguna: periksa push GitHub dan rekomendasikan hosting demo gratis. Repository publik `dzakyahnaf/sistem-prediktif-auto-assignment-penagihan`, HEAD lokal/remote **84a6719c90e9936c23c1e13690d6dd275e2e9b72**, satu commit,379file/22.396.770byte tracked; working tree bersih saat review dimulai. Halaman repo diperiksa melalui browser-act Chrome. Tidak ada perubahan kode/push/deployment cloud pada review ini; tambahan ini hanya catatan lokal.

Scan pola credential/private key dan pencocokan password PostgreSQL privat lokal terhadap seluruh blob commit, termasuk XML di DOCX/XLSX: **tidak ditemukan kecocokan**. Tidak ada runtime, .env, database/dump/keystore privat yang tracked. Ini pemeriksaan terbatas, bukan sertifikasi keamanan. Folder brief-awal/SOW dan transkrip Claude ikut publik; perlu penilaian pemilik apakah memang boleh dibagikan. `.env.production` belum dicakup `.gitignore`, walau saat ini tidak ada yang tracked. Bukti tanpa nilai secret: `runtime/github-review-scan.json`.

Temuan sebelum live:

- **Akun supervisor publik**: seed dan teks login/README memakai password demo yang sama. Perlu secret supervisor terkonfigurasi serta akses pengunjung terbatas; jangan mengekspos seluruh kontrol training/master/transaksi dengan credential demo publik.
- **Dependency advisory**: query OSV atas34paket venv menemukan advisori pada Starlette0.50.0,AnyIO4.12.0,certifi2025.11.12,idna3.11. Ada advisori severity HIGH/CRITICAL dengan kondisi eksploitasi masing-masing; tidak otomatis semua jalur aplikasi terdampak. FastAPI0.128.0 membatasi Starlette<0.51, sehingga pembaruan harus memilih pasangan FastAPI/Starlette yang kompatibel, memperbarui dependency transitif dan menjalankan ulang regresi. Versi perbaikan menurut advisory: Starlette hingga1.3.1,AnyIO4.14.2,idna3.15,certifi disarankan2026.10.19+. Tidak menaikkan versi tanpa pengujian. Bukti `github-review-dependencies.json`,`github-review-advisories.json`. Contoh sumber: [Starlette](https://github.com/Kludex/starlette/security/advisories/GHSA-wqp7-x3pw-xc5r),[certifi](https://github.com/certifi/python-certifi/security/advisories/GHSA-6q48-6c7w-9gw2).
- **Konfigurasi masih lokal**: API_URL default127.0.0.1, CORS hanya5173, startup PowerShell bind loopback/tanpa PORT dinamis; belum ada Dockerfile/render.yaml/vercel.json atau CI GitHub. Perlu build Flutter Linux/same-origin, entrypoint0.0.0.0:$PORT, WEB_BUILD_PATH dan DATABASE_URL rahasia melalui hosting. Limiter peer-IP perlu disesuaikan dengan proxy tepercaya hosting. Semua12dependency langsung tersedia diPyPI dengan wheel yang sesuai Linux/Python3.12; belum dibuild/di-UAT di cloud. Bukti `github-review-pypi.json`.

Rekomendasi: **Render Free satu service untuk compiledFlutter+FastAPI (Docker/same-origin) dan Neon Free PostgreSQL eksternal**. Ini paling dekat monolit yang sudah diverifikasi, tanpa keharusan menjalankan server lokal bagi pengunjung. Jangan memakai SQLite di filesystem ephemeral Render; data hilang saat restart/redeploy/sleep. RenderFree tidur sesudah15menit idle, cold start sekitar1menit,750jam/workspace/bulan,512MBRAM. Training model/histori perlu profiling pada kapasitas ini sebelum menjanjikan seluruh fitur lancar. RenderPostgresFree kedaluwarsa30hari, sehingga kurang sesuai untuk demo jangka panjang. Sumber [Render free](https://render.com/docs/free),[pricing](https://render.com/pricing).

NeonFree saat dicek:1GBstorage/project,100CU-hours/project/bulan,5GBpublictransfer/project/bulan,scale-to-zero setelah5menit idle. Kuota dapat menghentikan compute/operasi; bukan jaminan gratis tanpa batas atau always-on. Gunakan koneksi TLS; initial deployment/migrasi dan opsi sesi database aplikasi perlu diuji dengan direct/unpooled connection. [Plan Neon](https://neon.com/docs/introduction/plans),[pooling](https://neon.com/docs/connect/connection-pooling).

Vercel **mendukung FastAPI**, termasuk lifespan, tetapi menjadi serverless function; Python bundle standar500MB dan batas resource/durasi berlaku. Bisa dipilih untuk frontend statis ditambah backendRender/DBNeon, atau diadaptasi seluruhnya dengan database eksternal. Untuk project ini Render monolit lebih sederhana. **Vercel Hobby hanya personal/noncommercial**, perlu diperhatikan bila demo untuk klien/usaha. [FastAPI Vercel](https://vercel.com/docs/frameworks/backend/fastapi),[Hobby](https://vercel.com/docs/plans/hobby). Belum ada URL demo publik yang dideploy/diuji; estimasi biaya0hanya selama memenuhi kuota/kebijakan free dan memakai subdomain bawaan.

Penutupan: proses UAT8001 dan paket8080/8081 dihentikan, seluruhdatanya dipertahankan. Main API8000 PID43116/web5173 PID18544 tetap200, hashbisnis danSQLiteoriginal diperiksa lagi sesudah semua pengujian. Kedua sesiChrome milik agent ditutup; Chrome/profil pengguna tidak dihapus. Verifikasi ulang proses saat melanjutkan karena PID bukan kontrak startup.

Baca README, arsitektur, PROGRESS dan panduan penerimaan. Periksa proses aktual sebelum startup; PID hanya catatan eksekusi. Main PostgreSQL assignment_demo:15432, schema0006_hardening; web5173/API8000. BackendUAT8001 dan paket8080/8081 hanya proses penerimaan, tidak menggantikan startup utama. Config privat tetap di runtime. Dataset **HIST-DA17B9491C00**,kandidat **MOD-2F47EACC9298** dan **SEG-D83C7A70315B** dipertahankan; jangan train/generate ulang atau aktivasi otomatis tanpa tujuan baru. Fitur allowlist/train-only dan snapshot asal legacy tetap berlaku. User meminta browser-act/Chrome pada tiap workflow dan satu integrasi utuh per sprint.

Gate terbuka: iOS memerlukan Mac/Xcode yang belum tersedia; Android fisik/store/signing; konfirmasi aturan bisnis; histori nyata dan validasi model/segmen; vendor live/APIkey; deployment publik/TLS/HA/monitoring/load test produksi. Prototype lokal memenuhi cakupan yang bisa diverifikasi pada lingkungan ini, **bukan seluruh project100%diterima untuk produksi/lintasplatform**. Tidak meminta ulang konfigurasi izin browser/Flutter yang sudah bekerja. Sprint berikutnya dipilih berdasarkan gate dan akses yang tersedia, bukan membuat ulang aplikasi.
