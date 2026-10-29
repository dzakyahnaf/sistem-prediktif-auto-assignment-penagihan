# Kebutuhan Data & Informasi
## Prototype: Predictive Lead Assignment & Collection System

**Status dokumen:** Draft untuk konfirmasi client
**Tahap:** Prototype
**Tujuan dokumen:** Mengunci ruang lingkup dan memastikan ketersediaan data sebelum pengembangan dimulai.

---

## 0. Cara pakai dokumen ini

Bagian **A** adalah data yang menentukan apakah pendekatan machine learning bisa dijalankan sesuai arsitektur yang Bapak/Ibu kirimkan. Bagian **B–F** bisa menyusul.

Mohon jawaban Bagian **1** dan penyerahan Bagian **A** didahulukan.

---

## 1. Konfirmasi Ruang Lingkup

Mohon dikonfirmasi/dikoreksi poin-poin berikut:

### 1.1 Dua alur bisnis
Pemahaman kami, sistem ini menangani **dua proses berbeda** yang berbagi mesin assignment yang sama:

| | Alur A — Pengajuan Pinjaman | Alur B — Penagihan |
|---|---|---|
| Objek | Lead / calon debitur | Debitur existing yang menunggak |
| Yang diprediksi | Peluang lead menjadi pencairan | Peluang debitur membayar |
| Petugas | Tele-marketing + sales lapangan | Telecollection + collector lapangan |
| Hasil akhir | Pencairan | Pelunasan / recovery |

**Pertanyaan:** Benar keduanya dalam satu sistem? Atau salah satu didahulukan di prototype?

### 1.2 Dua gambar arsitektur
Kami menerima dua diagram. Setelah kami bandingkan, keduanya adalah **kerangka yang sama dengan dua varian berbeda**:

| Bagian | Gambar dengan "Segment Engine" | Gambar dengan "External Scoring Engine" |
|---|---|---|
| Zone 2 | Missing Value Imputation, Label Encoding/Scaling | Diganti 4 scoring engine untuk pihak eksternal (collection service, institusi, kuasa hukum, umum) |
| Zone 4 | Segment Engine (K-Means + PCA) | Tidak ada |
| Zone 5 | Assignment Rule Engine | Inference Engine |

**Pertanyaan:**
- Apakah ada rencana melempar kasus ke **pihak ketiga** (agency penagihan / kuasa hukum / institusi mitra)? Kalau tidak ada, varian "External Scoring Engine" kami anggap tidak berlaku untuk prototype.
- Kalau ada — pihak ketiga itu masuk di tahap mana? Setelah internal gagal, atau langsung dari awal berdasarkan skor?

### 1.3 Catatan koreksi pada diagram
Tiga hal yang perlu kami luruskan sebelum dijadikan acuan teknis:

1. Pada varian "External Scoring Engine", kotak berlabel **Zone 4: Unsupervised Learning** berisi *Model Registry* dan *Debtor Prediction Model*. Keduanya adalah keluaran *supervised learning* (Zone 3), bukan unsupervised.
2. Pada varian yang sama, Zone 5 masih menerima input **"Segment"**, padahal Segment Engine-nya tidak ada di diagram tersebut. Sumber segment perlu diperjelas.
3. Di **kedua** diagram, terdapat dua kotak yang sama-sama bernama **"Debtor Segmentation Model"** — satu menghasilkan *Probability*, satu menghasilkan *Segment*. Yang menghasilkan Probability semestinya bernama **Debtor Prediction Model**.

### 1.4 Definisi skor dan kode A / B
Kami menerima informasi *"skor tingkat low ke A, high ke B"*.

**Pertanyaan:**
- **A** dan **B** merujuk pada apa? Kanal (tele vs lapangan), grade petugas, tim, atau kategori kasus?
- **Low/high** ini skor apa? Tingkat kesulitan, potensi bayar, atau nilai nominal? (Arahnya bisa terbalik tergantung jawabannya.)
- Berapa ambang batas angkanya, dan apakah ada tingkat menengah?

### 1.5 Definisi operasional
Pada penjelasan awal disebut lead dibagi berdasarkan **potensi, tingkat kesulitan, interest, dan prospek**. Keempatnya saat ini diukur bagaimana? Dinilai manual oleh supervisor, atau ada rumus/kolom di Excel?

---

## 2. Bagian A — Data Historis *(penentu kelayakan machine learning)*

Ini bagian paling kritis. Model prediktif belajar dari keputusan masa lalu **beserta hasilnya**. Tanpa data ini, Zone 3 pada diagram tidak dapat dijalankan.

### A1. Histori lead pengajuan pinjaman + hasil akhirnya
Satu baris = satu lead. Wajib memuat hasil akhir (cair / tidak cair / ditolak).

Kolom yang diharapkan:
- ID lead, tanggal masuk, sumber lead
- Profil calon debitur pada saat lead masuk (usia, pekerjaan, penghasilan, lokasi, dst.)
- Nominal & jenis pinjaman yang diajukan
- Petugas yang menangani
- **Hasil akhir + tanggalnya**

### A2. Histori debitur & penagihan + status pembayaran
Satu baris = satu akun/kasus penagihan.

- ID debitur, produk, tanggal jatuh tempo
- Outstanding, tunggakan, DPD (days past due)
- Riwayat pembayaran
- Petugas/kanal yang menangani
- **Status pembayaran akhir + tanggalnya**

### A3. Histori aktivitas follow-up
Satu baris = satu kali kontak. Ini yang membentuk loop pada poin 3–4 penjelasan awal.

- ID lead/debitur, tanggal & jam, petugas, kanal (telepon/WA/kunjungan)
- Kode hasil (lihat B4)
- Catatan, janji bayar (nominal + tanggal), realisasi

### A4. Histori penugasan
Siapa ditugaskan ke siapa, kapan, oleh siapa/aturan apa, dan apakah pernah dialihkan.

### Spesifikasi minimum

| Kondisi data per alur | Konsekuensi |
|---|---|
| ≥ 24 bulan, ≥ 10.000 baris | Ideal — full ML sesuai diagram |
| ≥ 12 bulan, ≥ 3.000 baris, kelas minoritas ≥ 300 | Cukup — model dapat dipertanggungjawabkan |
| 1.000–3.000 baris | Terbatas — model sederhana saja (regresi logistik), tanpa XGBoost |
| < 1.000 baris | **Tidak layak** — supervised learning dihentikan, lihat Bagian 7 |

**Catatan penting:** kolom yang baru terisi *setelah* hasil diketahui (misalnya jumlah yang akhirnya dibayar) tidak boleh dipakai sebagai variabel prediktor. Ini menyebabkan *data leakage* — model tampak sangat akurat saat diuji, tetapi gagal total di lapangan. Karena itu kami perlu tahu **kapan tiap kolom terisi**, bukan hanya isinya.

---

## 3. Bagian B — Master Data

**B1. Daftar petugas** — nama/ID, peran (tele / lapangan / supervisor), grade atau level jika ada, tanggal bergabung.

**B2. Wilayah kerja** — pemetaan petugas ke wilayah (provinsi/kota/kecamatan/kode pos). Ini kebutuhan yang disebut pada poin 4 penjelasan awal dan **belum tergambar di kedua diagram**. Mohon juga diinfokan: apakah satu wilayah boleh dipegang lebih dari satu petugas, dan apakah petugas boleh lintas wilayah.

**B3. Kapasitas & SLA** — maksimal lead/kasus per petugas per hari, target waktu kontak pertama, aturan lead yang tidak ditindaklanjuti.

**B4. Kode hasil follow-up** — daftar resmi beserta artinya. Contoh yang biasa dipakai: PTP (janji bayar), broken promise, menolak bayar, tidak terhubung, nomor tidak aktif, sengketa, permohonan restrukturisasi, tidak berminat, minta dihubungi ulang, dokumen belum lengkap.

**B5. Aturan penugasan yang berlaku sekarang** — pada percakapan sebelumnya disampaikan aturannya *sudah ada*. Mohon dikirimkan dalam bentuk apa pun: dokumen, file Excel berisi rumus, atau tangkapan layar. Ini akan menjadi *baseline* pembanding performa model.

---

## 4. Bagian C — Data & Dokumen Operasional

**C1.** Contoh file Excel lead yang dipakai sehari-hari — file asli, bukan diketik ulang, agar format aslinya terbaca.
**C2.** Contoh laporan yang berjalan saat ini + siapa penerimanya.
**C3.** Daftar indikator (KPI) yang ingin muncul di dashboard, dipisah per peran: manajemen, supervisor, petugas.
**C4.** Tangkapan layar sistem yang dipakai sekarang, jika ada.

---

## 5. Bagian D — Integrasi & Teknis

Merujuk pada Zone 5 diagram:

- **Telephony System (Queue)** — vendor/dialer apa? Sudah ada API?
- **Omnichannel (API)** — kanal apa saja? WhatsApp Business API, SMS, email?
- **Field Force App** — aplikasi mobile baru, atau ada aplikasi lapangan eksisting?
- **Core Banking / Data Lake** — apakah tersedia akses API/database, atau untuk prototype cukup Excel?
- Jumlah pengguna aktif yang diperkirakan, dan estimasi volume lead/kasus per bulan.
- Rencana penempatan: cloud atau on-premise?

---

## 6. Bagian E — Kepatuhan & Keamanan Data

- **Jenis entitas** — bank, multifinance, fintech P2P, koperasi, atau lainnya? Ini menentukan aturan pengawasan yang berlaku atas praktik penagihan.
- **Data pribadi** — pengelolaan data debitur tunduk pada UU No. 27 Tahun 2022 tentang Pelindungan Data Pribadi. Untuk tahap prototype, kami **menyarankan data diserahkan dalam kondisi ter-anonimisasi**: nama, NIK, dan nomor telepon diganti kode, alamat cukup sampai tingkat kecamatan/kode pos. Kualitas model tidak terpengaruh.
- Apakah ada perjanjian kerahasiaan (NDA) yang perlu ditandatangani lebih dulu?
- Apakah ada persetujuan internal (legal/compliance) yang dibutuhkan sebelum data keluar?

---

## 7. Skenario Jika Data Historis Tidak Tersedia

Kami sampaikan di awal agar tidak ada kejutan di tengah jalan.

| Ketersediaan Bagian A | Yang bisa dibangun |
|---|---|
| **Tersedia** | Full ML sesuai diagram: Zone 3 (XGBoost/RF/LogReg) + Zone 4 (K-Means/PCA) + Zone 5 |
| **Sebagian** | Zone 4 (segmentasi) + Zone 5 penuh; Zone 3 dibangun dengan model sederhana dan diberi label eksplisit sebagai indikatif |
| **Tidak tersedia** | Zone 4 + Zone 5 dengan skor berbasis aturan. Arsitektur tetap disiapkan agar Zone 3 bisa dipasang kemudian tanpa membongkar sistem. Selama prototype berjalan, sistem sekaligus **mengumpulkan data berlabel** untuk pelatihan model di fase berikutnya. |

Perlu kami tegaskan: menampilkan angka probabilitas dari model yang dilatih dengan data sangat terbatas justru berisiko, karena hasilnya terlihat meyakinkan padahal tidak dapat diandalkan untuk pengambilan keputusan.

---

## 8. Format Penyerahan

- Format: `.xlsx` atau `.csv` — file asli, bukan tangkapan layar atau salinan ketik ulang
- Satu file per jenis data (A1, A2, A3, A4 terpisah)
- Sertakan **seluruh kolom** meski sebagian kosong — kolom kosong pun merupakan informasi
- Jika ada istilah/singkatan internal, mohon disertakan penjelasannya

---

## 9. Ringkasan Pertanyaan Terbuka

Untuk memudahkan, berikut daftar pertanyaan yang menunggu jawaban:

1. Prototype mencakup pengajuan pinjaman, penagihan, atau keduanya?
2. Ada rencana pelibatan pihak ketiga (agency/kuasa hukum)?
3. **A** dan **B** merujuk pada apa, dan **low/high** itu skor apa?
4. Berapa ambang batas skornya? Ada tingkat menengah?
5. Potensi, kesulitan, interest, prospek — sekarang dinilai bagaimana?
6. Apakah data historis pada Bagian A tersedia? Berapa lama periodenya?
7. Satu wilayah dipegang berapa petugas? Boleh lintas wilayah?
8. Berapa kapasitas maksimal per petugas per hari?
9. Vendor telephony dan kanal omnichannel apa yang dipakai?
10. Ada NDA atau persetujuan internal yang perlu diselesaikan lebih dulu?

---

*Dokumen ini akan diperbarui setelah menerima tanggapan.*
