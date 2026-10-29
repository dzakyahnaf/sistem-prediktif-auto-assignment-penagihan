# Review Data Dummy & Permintaan Data Tambahan

**Berkas yang direview:** `Use_Case.xlsx`, `Use_case_2.xlsx`
**Ukuran:** 1.200 baris × 12 fitur, tanpa nilai kosong, tanpa duplikat
**Kesimpulan singkat:** cukup untuk membangun dan mendemokan pipeline; **belum cukup** untuk memenuhi kebutuhan yang tertulis pada penjelasan awal.

---

## 1. Apresiasi — data ini jauh lebih siap dari umumnya

Kami uji dulu apakah kolom target benar-benar berhubungan dengan fitur-fiturnya, atau sekadar angka acak. Hasilnya:

| Ukuran | Hasil |
|---|---|
| Sebaran target | Success 824 (68,7%) / No success 376 (31,3%) — seimbang, tidak ekstrem |
| Nilai kosong | 0 |
| Baris duplikat | 0 |
| Performa model dasar | **AUC 0,757** (tebak acak = 0,500) |

Artinya ada logika bisnis nyata yang tertanam di dalamnya. Struktur kolomnya juga sudah masuk akal untuk domain penagihan.

---

## 2. Empat fitur bekerja, delapan tidak

Uji chi-square tiap fitur terhadap keberhasilan penagihan:

| Fitur | p-value | Rentang success rate | Status |
|---|---|---|---|
| Behavior Bayar | < 0,001 | 0,36 – 0,81 | **Kuat** |
| Kategori Kasus | < 0,001 | 0,40 – 0,83 | **Kuat** |
| Hasil Call | < 0,001 | 0,46 – 0,78 | **Kuat** (lihat bagian 3) |
| Hasil Visit | < 0,001 | 0,59 – 0,74 | **Kuat** (lihat bagian 3) |
| Kategori Case | 0,056 | 0,65 – 0,72 | Lemah |
| Pembayaran | 0,251 | 0,64 – 0,75 | Tidak ada pengaruh |
| Capacity Field Staff | 0,569 | 0,65 – 0,71 | Tidak ada pengaruh |
| Pekerjaan | 0,743 | 0,60 – 0,75 | Tidak ada pengaruh |
| Usia | 0,757 | 0,65 – 0,70 | Tidak ada pengaruh |
| Tempat Lahir | 0,812 | 0,60 – 0,75 | Tidak ada pengaruh |
| Status Rumah | 0,999 | 0,68 – 0,69 | Tidak ada pengaruh |
| Gender | 1,000 | 0,69 – 0,69 | Tidak ada pengaruh |

Nilai p = 1,000 pada Gender dan 0,999 pada Status Rumah menunjukkan kedua kolom itu diisi acak merata — wajar untuk data dummy, namun perlu dicatat bahwa pada data nyata pola ini tidak akan sama.

**Yang perlu diperhatikan:** `Kategori Case` (Low/Medium/High) tampaknya adalah tingkat kesulitan yang menjadi dasar pembagian A dan B. Tetapi dalam data ini hubungannya dengan keberhasilan sangat lemah (p = 0,056; selisih hanya 0,65 vs 0,72). Mohon dikonfirmasi apakah memang demikian di lapangan.

---

## 3. Pertanyaan penting: kapan `Hasil Call` dan `Hasil Visit` terisi?

Ini menentukan apakah model bisa dipakai atau tidak, jadi mohon dijawab lebih dulu.

Kedua kolom itu adalah **hasil dari aktivitas follow-up**. Kalau keputusan assignment dibuat *sebelum* debitur ditelepon atau dikunjungi, keduanya belum terisi pada saat model dijalankan.

Dampaknya kami ukur:

| Model | AUC |
|---|---|
| Memakai semua fitur | 0,757 |
| **Hanya fitur yang tersedia sebelum penanganan** | **0,690** |
| Tebak acak | 0,500 |

**Ada dua kemungkinan, dan keduanya sama-sama masuk akal:**

- **Kemungkinan A** — kolom itu berisi hasil pada siklus penagihan **yang sedang berjalan**. Kalau begini, kolom tersebut tidak boleh dipakai untuk assignment awal, karena datanya belum ada saat keputusan diambil.
- **Kemungkinan B** — kolom itu berisi hasil pada siklus **sebelumnya**. Kalau begini justru aman dan sangat berguna, dan cocok dengan poin 4 penjelasan awal *("sistem melakukan generate kembali untuk melakukan assignment")*.

**Jika jawabannya B**, kami usulkan dibangun dua model terpisah:
1. **Model assignment awal** — untuk lead/kasus yang baru masuk, tanpa riwayat kontak
2. **Model re-assignment** — untuk siklus berikutnya, memanfaatkan hasil call & visit sebelumnya

Ini justru sesuai dengan alur yang Bapak/Ibu gambarkan.

---

## 4. Temuan yang paling perlu didiskusikan

Inti dari auto-assignment adalah: **kasus tertentu bila ditangani petugas dengan karakter tertentu, hasilnya lebih baik.** Kami uji hal ini secara langsung.

Success rate per kombinasi `Kategori Case` × `Capacity Field Staff`:

| Kategori Case | High Negosiasi | High Penegasan | Low Negosiasi | Low Penegasan | Rajin | Tidak Rajin |
|---|---|---|---|---|---|---|
| **High** | 0,767 | 0,750 | 0,526 | 0,615 | 0,729 | 0,548 |
| **Medium** | 0,611 | 0,607 | 0,704 | 0,667 | 0,653 | 0,667 |
| **Low** | 0,740 | 0,633 | 0,758 | 0,767 | 0,732 | 0,680 |

Uji chi-square kombinasi tersebut terhadap keberhasilan: **p = 0,113 — belum signifikan secara statistik.**

Perlu kami sampaikan secara berimbang: jumlah sampel per sel hanya 38–104, jadi hasil ini **belum terbukti, bukan terbukti tidak ada**. Rentang 0,53–0,77 juga cukup lebar dan polanya sebagian masuk akal (kasus High lebih berhasil di tangan petugas High Negosiasi, 0,767 vs 0,526 untuk Low Negosiasi).

**Mohon dikonfirmasi:** apakah di lapangan pencocokan karakter petugas memang berpengaruh pada keberhasilan? Kalau ya, kami perlu data nyata yang memuat pola tersebut, karena data dummy saat ini belum menunjukkannya secara meyakinkan.

---

## 5. Kolom `Capacity Field Staff` perlu diperjelas

Kolom ini berisi dua jenis informasi yang berbeda dalam satu kolom:

- **Tingkat pendekatan:** High Negosiasi, Low Negosiasi, High Penegasan, Low Penegasan
- **Etos kerja:** Rajin, Tidak Rajin

Selain itu maknanya masih bisa ditafsirkan dua arah:

- **Tafsir A** — karakter petugas yang **menangani** kasus ini. Kalau begini, kolom ini adalah *keputusan assignment*, sehingga seharusnya menjadi **keluaran** model, bukan masukan.
- **Tafsir B** — karakter petugas yang **dibutuhkan** kasus ini. Kalau begini, kolom ini adalah *label* yang harus diprediksi.

Usul kami: dipecah menjadi dua kolom terpisah, dan diperjelas apakah menggambarkan petugas yang menangani atau petugas yang dibutuhkan.

---

## 6. Kolom yang belum ada dan sangat dibutuhkan

Diurutkan berdasarkan tingkat kepentingan.

### Prioritas 1 — tanpa ini, kebutuhan pada penjelasan awal tidak bisa dipenuhi

| Kolom | Alasan |
|---|---|
| **Wilayah / domisili debitur** | Poin 4 penjelasan awal menyebut *"assignment sesuai wilayah kerja sales"*. Saat ini yang ada hanya **Tempat Lahir**, yang tidak menunjukkan lokasi debitur sekarang. Mohon diganti alamat domisili (cukup sampai tingkat kota/kecamatan/kode pos). Catatan tambahan: tempat lahir sebaiknya tidak dipakai sebagai variabel model karena berpotensi menjadi proksi suku/daerah asal, yang dapat menimbulkan bias dalam pengambilan keputusan. |
| **ID petugas + wilayah kerjanya** | Tanpa identitas petugas, sistem tidak bisa membagi beban kerja, tidak bisa mengukur performa per petugas, dan tidak bisa menjalankan siklus re-assignment. |
| **Kanal penanganan** (tele / lapangan / eksternal) | Inti sistem adalah membagi ke tele dan sales lapangan. Saat ini tidak ada kolom yang menyatakan kasus ditangani lewat kanal mana. |
| **Tanggal** — lead masuk, penugasan, kontak, jatuh tempo, hasil | Tidak ada satu pun kolom tanggal. Akibatnya: tidak bisa memisahkan data latih dan uji berdasarkan waktu (standar wajib agar hasil pengujian tidak terlalu optimistis), tidak bisa menghitung SLA, dan tidak bisa memantau penurunan performa model dari waktu ke waktu. |

### Prioritas 2 — pendorong utama akurasi pada data penagihan nyata

| Kolom | Alasan |
|---|---|
| **Outstanding / sisa pokok / nilai angsuran** | Pada data penagihan nyata, nominal termasuk prediktor terkuat sekaligus penentu apakah kunjungan lapangan layak secara biaya. |
| **DPD dalam angka** | `Behavior Bayar` sudah dikelompokkan menjadi teks. Angka mentah memuat informasi lebih banyak. |
| **Tenor, sisa tenor, jenis produk** | Konteks kredit. |
| **Jumlah percobaan kontak** | Membedakan yang baru dihubungi sekali dengan yang sudah delapan kali. |
| **Riwayat menunggak sebelumnya** | Perilaku masa lalu adalah prediktor terbaik perilaku masa depan. |

### Prioritas 3 — definisi

- **Apa arti "Success"?** Lunas seluruhnya, janji bayar ditepati, atau bayar sebagian? Dalam rentang waktu berapa hari?
- **`Kategori Case` Low/Medium/High** — apakah ini yang menjadi dasar pembagian A dan B? Jika ya, **Medium** masuk ke mana?
- **Ambang batas skor** untuk A dan B.

---

## 7. Belum ada sama sekali: sisi pengajuan pinjaman

Kedua berkas seluruhnya berisi data **penagihan**. Tidak ada satu pun baris mengenai lead pengajuan pinjaman.

Bila prototype juga mencakup alur pengajuan, kami membutuhkan berkas terpisah berisi minimal:

- ID lead, tanggal masuk, sumber lead
- Profil calon debitur **pada saat lead masuk**
- Nominal dan jenis pinjaman yang diajukan
- Petugas yang menangani + wilayah
- **Hasil akhir**: cair / ditolak / batal, beserta tanggalnya

Bila belum tersedia, mohon diinfokan agar prototype difokuskan pada penagihan terlebih dahulu.

---

## 8. Catatan teknis: kategori dengan sampel sedikit

Tiga kategori pada `Kategori Kasus` memiliki jumlah baris di bawah 50:

| Kategori | Jumlah | Success rate |
|---|---|---|
| Raib | 27 | 0,407 |
| Data tidak valid | 34 | 0,647 |
| Backup Pihak 3 | 47 | 0,830 |

Pada pembagian 80/20, kategori sebanyak ini bisa nyaris hilang dari data uji sehingga hasilnya tidak stabil. Bila memungkinkan, mohon jumlahnya ditambah — atau kami gabungkan menjadi kategori "Lainnya", mohon konfirmasinya.

---

## 9. Ringkasan pertanyaan

1. `Hasil Call` dan `Hasil Visit` — hasil siklus berjalan atau siklus sebelumnya?
2. `Capacity Field Staff` — karakter petugas yang menangani, atau yang dibutuhkan?
3. Apakah pencocokan karakter petugas memang berpengaruh pada keberhasilan di lapangan?
4. Apa definisi "Success", dan dalam rentang waktu berapa hari?
5. `Kategori Case` Low/Medium/High — ini dasar pembagian A dan B? Medium masuk ke mana?
6. Bisakah ditambahkan kolom Prioritas 1 (wilayah, ID petugas, kanal, tanggal)?
7. Apakah data pengajuan pinjaman tersedia, atau prototype difokuskan ke penagihan dulu?
8. Untuk tiga kategori bersampel sedikit — ditambah, atau digabung?

---

*Dokumen ini menyertai permintaan data sebelumnya dan menggantikan bagian yang telah terjawab oleh kedua berkas di atas.*
