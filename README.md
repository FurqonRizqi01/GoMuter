# GoMuter

GoMuter adalah aplikasi lokator Pedagang Kaki Lima (PKL) berbasis mobile yang membantu pembeli menemukan PKL terdekat, melihat detail dagangan, melakukan pre-order, berkomunikasi melalui chat, serta menerima notifikasi terkait PKL dan pesanan.

Proyek ini terdiri dari aplikasi mobile Flutter dan backend Django REST Framework yang dideploy ke Google Cloud Run. Database produksi menggunakan PostgreSQL Supabase, sedangkan media seperti foto profil, foto produk, QRIS, dan bukti pembayaran disimpan di Supabase Storage.

## Fitur Utama

- Autentikasi pengguna berbasis JWT untuk pembeli, PKL, dan admin.
- Pencarian PKL aktif berdasarkan lokasi, radius, kategori, dan kata kunci.
- Detail PKL berisi profil usaha, menu unggulan, lokasi, ulasan, dan informasi pembayaran.
- Manajemen profil, status toko, lokasi manual/otomatis, produk, dan pembayaran untuk PKL.
- Pre-order dengan total harga, DP, upload bukti pembayaran, dan verifikasi oleh PKL.
- Chat antara pembeli dan PKL.
- Notifikasi perangkat menggunakan Firebase Cloud Messaging.
- Dashboard admin dan Django Admin untuk monitoring serta pengelolaan data.
- Verifikasi profil PKL oleh admin sebelum PKL dapat mengaktifkan toko dan memperbarui lokasi.

## Tech Stack

- Mobile: Flutter, Dart
- Backend: Django, Django REST Framework
- Authentication: JWT, Simple JWT
- Database: PostgreSQL Supabase
- Object storage: Supabase Storage
- Deployment: Google Cloud Run
- Notification: Firebase Cloud Messaging
- Map: Flutter Map, OpenStreetMap
- Geocoding: Nominatim / device geocoding

## Struktur Folder

```text
GoMuter/
├── gomuter_app/        # Aplikasi mobile Flutter
├── gomuter_backend/    # Backend Django REST Framework
├── docs/               # Dokumentasi, laporan pengujian, dan catatan proyek
├── README.md
└── .gitignore
```

## Backend

Masuk ke folder backend:

```powershell
cd gomuter_backend
```

Aktifkan virtual environment:

```powershell
.\.venv\Scripts\Activate.ps1
```

Jalankan migrasi:

```powershell
python manage.py migrate
```

Jalankan server lokal:

```powershell
python manage.py runserver
```

Jalankan pengujian black-box API:

```powershell
python manage.py test pkl.tests_blackbox --settings=gomuter_backend.test_settings -v 2
```

Jalankan seluruh pengujian backend terkait:

```powershell
python manage.py test pkl.tests pkl.tests_blackbox --settings=gomuter_backend.test_settings -v 2
```

## Flutter App

Masuk ke folder aplikasi:

```powershell
cd gomuter_app
```

Ambil dependency:

```powershell
flutter pub get
```

Jalankan aplikasi:

```powershell
flutter run
```

Build APK release:

```powershell
flutter build apk --release --target lib/main.dart
```

Output APK:

```text
gomuter_app/build/app/outputs/flutter-apk/app-release.apk
```

## Konfigurasi Produksi

Konfigurasi sensitif tidak disimpan di repository. Backend membaca konfigurasi dari environment variable atau Google Cloud Secret Manager.

Contoh konfigurasi penting:

- `DATABASE_URL`
- `SECRET_KEY`
- `FIREBASE_SERVICE_ACCOUNT_B64`
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_STORAGE_BUCKET`
- `GOMUTER_EMAIL_HOST_USER`
- `GOMUTER_EMAIL_HOST_PASSWORD`
- `GOMUTER_DEFAULT_FROM_EMAIL`

File lokal seperti `gomuter_app/lib/config.dart`, `.env`, service account, file build, media upload, dan arsip deployment diabaikan oleh `.gitignore`.

## Deployment

Backend produksi berjalan di Google Cloud Run dengan service:

```text
gomuter-backend
```

Region:

```text
asia-southeast2
```

Database dan storage produksi menggunakan Supabase:

- PostgreSQL untuk data akun, PKL, lokasi, produk, chat, pre-order, rating, dan notifikasi.
- Supabase Storage bucket `gomuter-media` untuk file media publik.

## Dokumentasi Pengujian

Laporan pengujian black-box tersedia di:

```text
docs/blackbox-testing-report-2026-06-01.md
```

Ringkasan konteks proyek tersedia di:

```text
docs/context-handoff-2026-06-03.md
```

## Catatan Keamanan

- Jangan commit password, token, service role key, atau service account JSON.
- Gunakan Google Cloud Secret Manager untuk credential produksi.
- Gunakan Supabase Storage untuk media agar file tetap persisten setelah redeploy Cloud Run.
- Jalankan test dengan `gomuter_backend.test_settings` agar tidak mengubah database produksi.
