# Flutter native — Sprint 11

Runner Android dan iOS berbagi sumber Dart yang sama dengan web. Android mempunyai flavor demo/production; app demo memakai ID `id.assignmentstudio.assignment_studio.demo`. `file_picker`13.3.0 menyediakan dialog sistem, XLSX dibaca sebagai stream maksimal5MiB dan diperiksa lagi oleh API. Berkas CSV/XLSX/ZIP disimpan melalui Save As; membatalkan tidak dilaporkan sebagai unduhan berhasil. Callback terlambat sesudah route ditutup diabaikan. Token tetap di memori: menutup proses aplikasi meminta login lagi, data server tetap persisten. Tidak ada mode offline/sinkronisasi tersembunyi.

## Menjalankan Android

Gunakan Flutter3.41.6, SDK Android36 danNDK28.2.13676358, JDK17. Lingkungan ini sudah menyediakan SDK melalui junction `C:\Android\Sdk`, Java dan emulator Pixel_5 Android14. Tidak perlu mengubah konfigurasi SDK global atau service PostgreSQL pengguna. Periksa perangkat sebelum memulai emulator baru.

```powershell
.\scripts\build-android.ps1 -FlutterSdk 'C:\flutter' -Offline
# APK baru dan SHA256 disimpan pada runtime/artifacts, tanpa menimpa artefak lama.
C:\Android\Sdk\platform-tools\adb.exe devices -l
C:\Android\Sdk\platform-tools\adb.exe -s emulator-5554 install -r '<path APK demo>'
```

API_URL default script adalah `http://10.0.2.2:8000` untuk Android Emulator standar. Backend tetap bind loopback Windows. Untuk perangkat USB, gunakan API_URL127.0.0.1 dan `adb -s <device> reverse tcp:8000 tcp:8000`; host LAN HTTP lain sengaja tidak diizinkan. Server di luar host perlu HTTPS dan origin sesuai. Flavor demo hanya mengizinkan HTTP10.0.2.2/127.0.0.1/localhost; base network config dan flavor production menolak cleartext. INTERNET tersedia pada manifest utama. Tidak meminta akses penyimpanan menyeluruh; picker memakai Storage Access Framework. Signing distribusi/store harus dikonfigurasi pemilik deployment; APK debug bukan rilis produksi.

## Pengujian native

Siapkan schema UAT baru dengan `prepare-sprint-uat.py --sprint11` **sekali saja**; script menolak config yang sudah ada dan menjaga semua demo lama. Mulai backend memakai DATABASE_URL dari config privat tersebut, jangan mencetak password URL. Pastikan backend8000 memang menunjuk UAT yang sama sebelum tes berikut:

```powershell
.\scripts\test-android.ps1 -FlutterSdk 'C:\flutter' -UatConfig runtime/sprint11-uat-config.json
# Probe Save/Open OS memerlukan operator mengonfirmasi dialog emulator:
.\scripts\test-android.ps1 -FlutterSdk 'C:\flutter' -UatConfig runtime/sprint11-uat-config.json -NativeFiles
```

Tes workflow mengoperasikan widget pada Android asli/emulator dan backend nyata; hanya membaca API untuk memeriksa saldo/status/ID, tidak menggantikan aksi UI dengan mutasi API. Pengetikan tes memakai test input Flutter agar deterministik, terpisah dari pemeriksaan IME perangkat. Tes unit adapter memeriksa bytes/MIME/cancel/ukuran/berkas berubah/navigation disposal; itu tidak menggantikan probe dialog OS. Hasil pengujian aktual dan batas platform dicatat di PROGRESS.

## iOS

Runner Swift, Podfile minimal iOS14, konfigurasi CocoaPods, dan Info-Demo.plist untuk Debug tersedia. Hanya Debug mengizinkan HTTP lokal; Profile/Release memakai Info.plist normal tanpa ATS exception. Xcode signing team harus diisi pemilik perangkat. Windows tidak dapat menjalankan build/UAT iOS. Di Mac dengan Xcode/CocoaPods dan Flutter versi yang sesuai:

```sh
cd apps/assignment
flutter pub get
flutter build ios --debug --no-codesign --dart-define=API_URL=http://127.0.0.1:8000
flutter devices
flutter run -d <ios-simulator> --dart-define=API_URL=http://127.0.0.1:8000
```

Alamat127.0.0.1 tersebut memerlukan backend di Mac yang sama atau tunnel lokal yang disiapkan pemilik. Untuk perangkat/server lain pakai HTTPS. Build, signing, picker, keyboard dan workflow iOS belum dapat dianggap terverifikasi hanya karena Dart analyze/web/Android lulus.

Referensi: [platform Flutter](https://docs.flutter.dev/platform-integration), [setup iOS](https://docs.flutter.dev/platform-integration/ios/setup), [file_picker13.3.0](https://pub.dev/packages/file_picker/versions/13.3.0), [API file picker](https://pub.dev/documentation/file_picker/13.3.0/file_picker/FilePicker-class.html).
