# GoMuter Context Handoff - 2026-06-03

Dokumen ini berisi ringkasan konteks proyek GoMuter agar pekerjaan bisa dilanjutkan tanpa harus membaca ulang seluruh percakapan.

## Struktur Proyek

- `gomuter_app/`: aplikasi mobile Flutter.
- `gomuter_backend/`: backend Django + Django REST Framework.
- `docs/`: catatan dan laporan pengujian.

## Backend dan Deployment

- Backend dideploy ke Google Cloud Run.
- Service Cloud Run: `gomuter-backend`.
- Region: `asia-southeast2`.
- Database produksi menggunakan PostgreSQL di Supabase.
- Media/gambar sudah diarahkan ke Supabase Storage dengan bucket `gomuter-media`.
- Untuk deployment backend, kode terbaru perlu di-upload/zip dulu ke Cloud Shell. Perubahan lokal di laptop tidak otomatis masuk ke Google Cloud.

## Konfigurasi Penting

- `DATABASE_URL`, `SECRET_KEY`, dan credential Firebase disimpan lewat Google Cloud Secret Manager.
- Supabase Storage memakai env:
  - `SUPABASE_URL`
  - `SUPABASE_SERVICE_ROLE_KEY`
  - `SUPABASE_STORAGE_BUCKET`
- Reset password memakai SMTP Gmail dengan App Password lewat Secret Manager.
- Jangan menyimpan password, service role key, atau secret lain di source code.

## Autentikasi

- Backend memakai JWT.
- Access token default: 240 menit.
- Refresh token default: 90 hari.
- Flutter memakai `TokenManager` untuk mengambil access token valid dan melakukan refresh otomatis jika access token sudah expired.
- Setelah perubahan aturan token, pengguna lama perlu login ulang sekali agar mendapat refresh token dengan aturan baru.

## Reset Password

- Fitur lupa password tidak memakai OTP angka.
- Backend mengirim `UID` dan `TOKEN` ke email pengguna.
- Endpoint:
  - `POST /api/auth/password-reset/request/`
  - `POST /api/auth/password-reset/confirm/`
- Jika SMTP belum benar, backend tetap mengembalikan pesan generik demi keamanan, tetapi email tidak sampai.
- SMTP produksi perlu `GOMUTER_EMAIL_HOST_USER`, `GOMUTER_EMAIL_HOST_PASSWORD`, dan `GOMUTER_DEFAULT_FROM_EMAIL`.

## Perubahan Backend Penting

- Verifikasi PKL dikunci dari sisi admin.
- `status_verifikasi` dan `catatan_verifikasi` bersifat read-only untuk PKL.
- Update lokasi PKL hanya boleh dilakukan jika profil PKL sudah `DITERIMA`.
- Pre-order dan start chat dibatasi untuk pembeli.
- Upload gambar produk, foto profil PKL, QRIS, dan bukti DP diarahkan ke Supabase Storage.
- Upload gambar pernah diperbaiki untuk menangani masalah MIME type dan error `cannot pickle 'BufferedRandom' instances`.

## Perubahan Flutter Penting

- Default radius pencarian pembeli dibuat tanpa radius, bukan otomatis `300 m`.
- Detail PKL menampilkan menu unggulan dan opsi pembayaran.
- Pre-order pembeli memakai lokasi penjemputan default dari lokasi pembeli, tetap bisa diganti lewat map.
- Halaman PKL menampilkan menu unggulan dengan gambar.
- Mode lokasi otomatis PKL dibuat lebih jelas agar tombol manual tidak membingungkan.
- Tombol telepon/detail kontak diarahkan ke nomor WhatsApp PKL jika tersedia.

## Testing

File pengujian:

- `gomuter_backend/pkl/tests_blackbox.py`
- `gomuter_backend/gomuter_backend/test_settings.py`
- `docs/blackbox-testing-report-2026-06-01.md`

Jalankan black-box API test dari PowerShell:

```powershell
cd C:\Project\GoMuter\gomuter_backend
.\.venv\Scripts\Activate.ps1
python manage.py test pkl.tests_blackbox --settings=gomuter_backend.test_settings -v 2
```

Jalankan semua test backend terkait:

```powershell
python manage.py test pkl.tests pkl.tests_blackbox --settings=gomuter_backend.test_settings -v 2
```

Catatan:

- `test_settings.py` memakai konfigurasi test yang aman.
- Test tidak menyentuh database produksi Supabase.
- Jangan menjalankan `tests_blackbox.py` langsung dengan `python pkl/tests_blackbox.py`.

## Black-Box Report

- Laporan pengujian ada di `docs/blackbox-testing-report-2026-06-01.md`.
- Pengujian API utama sudah disusun dalam tabel skenario, input, ekspektasi, dan kesimpulan.
- Fitur lupa password boleh dimasukkan sebagai pengujian tambahan, tetapi tidak wajib jika bukan ruang lingkup utama.

## Build APK

Command build release APK:

```powershell
cd C:\Project\GoMuter\gomuter_app
flutter build apk --release --target lib/main.dart
```

Output APK:

```text
gomuter_app/build/app/outputs/flutter-apk/app-release.apk
```

Catatan:

- Warning `tree-shaken icons` normal dan bukan error.
- Jika hanya backend berubah, tidak selalu perlu build APK ulang.
- Jika Flutter berubah, pengguna perlu install APK baru agar mendapat perubahan UI/client.

## Git dan File Sementara

- File `.zip` sudah diabaikan oleh `.gitignore`.
- `gomuter_app/lib/config.dart` juga diabaikan agar URL/config lokal tidak ikut commit.
- File test black-box aman untuk di-push karena tidak berisi secret produksi.
- Folder staging/upload sementara yang lama boleh dihapus jika sudah tidak dipakai.

## Catatan Dokumentasi Skripsi

Perubahan yang paling mungkin memengaruhi dokumen:

- Diagram arsitektur jika media dipindah dari Django Media Storage ke Supabase Storage.
- Screenshot konfigurasi JWT.
- Screenshot `TokenManager`.
- Screenshot validasi verifikasi PKL untuk update lokasi.
- Screenshot endpoint pre-order/chat jika membahas pembatasan role.
- Screenshot UI PKL untuk kondisi pending dan diterima.
- Screenshot atau tabel pengujian jika skenario baru ditambahkan.

## Hal yang Perlu Diingat

- Supabase adalah PostgreSQL terkelola, jadi penulisan "PostgreSQL" dalam skripsi tetap tepat.
- Cloud Run filesystem tidak persisten untuk media, sehingga Supabase Storage lebih stabil untuk gambar.
- Untuk UAT, data dummy PKL bisa diatur koordinatnya langsung dari database agar dekat dengan lokasi responden.
- Jika akun lama tidak menerima reset password, cek dulu kolom `email` di tabel `accounts_user`.
