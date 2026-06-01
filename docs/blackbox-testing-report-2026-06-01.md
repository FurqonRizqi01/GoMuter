# Laporan Pengujian Black-Box GoMuter

Tanggal pengujian: 1 Juni 2026

## Resume

Pengujian API dijalankan secara otomatis menggunakan Django REST Framework API
test client, autentikasi JWT Bearer, dan basis data SQLite sementara. Basis data
Supabase produksi/UAT tidak diubah oleh proses ini.

Perintah pengujian:

```powershell
cd C:\Project\GoMuter\gomuter_backend
python manage.py test pkl.tests pkl.tests_blackbox --settings=gomuter_backend.test_settings -v 1
python manage.py check --settings=gomuter_backend.test_settings
```

Hasil:

| Pemeriksaan | Hasil |
|---|---|
| Skenario API inti | 18/18 lulus |
| Pemeriksaan keamanan akses tambahan | 2/2 lulus |
| Regression test backend keseluruhan | 28/28 lulus |
| Django system check | Tidak ditemukan masalah |
| Pengujian manual fitur aplikasi pada perangkat Android | 58/58 sesuai ekspektasi |

## Rekapitulasi dan Perhitungan

Persentase keberhasilan dihitung menggunakan rumus:

```text
Persentase keberhasilan = (Jumlah skenario sesuai / Jumlah skenario diuji) x 100%
```

| Kelompok Pengujian | Jumlah Skenario Diuji | Sesuai | Tidak Sesuai | Persentase Keberhasilan |
|---|---:|---:|---:|---:|
| API inti | 18 | 18 | 0 | 100% |
| Keamanan akses tambahan | 2 | 2 | 0 | 100% |
| Fitur aplikasi pada perangkat Android | 58 | 58 | 0 | 100% |

Contoh perhitungan pengujian fitur aplikasi:

```text
Persentase keberhasilan = (58 / 58) x 100% = 100%
```

Pengujian API otomatis dan pengujian fitur aplikasi manual disajikan secara
terpisah karena beberapa proses bisnis diuji pada kedua lapisan. Regression test
backend `28/28` digunakan sebagai bukti pendukung stabilitas implementasi dan
tidak dijumlahkan kembali sebagai skenario black-box tambahan.

Catatan pengujian:

- Skenario unggah dan verifikasi DP menguji penyimpanan URL bukti DP serta
  perubahan status pembayaran secara otomatis. Unggah file biner ke Supabase
  Storage juga telah diuji manual pada perangkat Android karena bergantung
  pada bucket, koneksi internet, tipe file, dan batas ukuran file.
- Pengujian manual pada perangkat Android mencakup perilaku UI, GPS, izin
  sistem, notifikasi perangkat, peta, dan interaksi pengguna.

## Hasil Pengujian API

| No. | Skenario | Method/Endpoint | Input | Ekspektasi | Hasil Aktual | Kesimpulan |
|---|---|---|---|---|---|---|
| 1 | Registrasi berhasil | `POST /api/accounts/register/` | Data registrasi pembeli valid | Status `201`, akun baru terbentuk | Status `201`, akun baru terbentuk | Sesuai |
| 2 | Login berhasil | `POST /api/auth/token/` | Username dan password valid | Status `200`, body berisi access token, refresh token, peran, dan identitas pengguna | Status `200`, seluruh field tersedia | Sesuai |
| 3 | Login gagal | `POST /api/auth/token/` | Username valid dan password salah | Status `401` | Status `401` | Sesuai |
| 4 | Ambil profil akun sendiri | `GET /api/accounts/me/` | Bearer token pembeli | Status `200`, data profil tampil | Status `200`, username sesuai akun | Sesuai |
| 5 | Buat dan perbarui profil PKL | `POST /api/pkl/profile/`, `PUT /api/pkl/profile/` | Bearer token PKL dan data profil usaha | Status `201` dan `200`; status verifikasi dan catatan verifikasi read-only | Profil dibuat dan diperbarui; percobaan self-verification tetap menghasilkan status `PENDING` | Sesuai |
| 6 | Perbarui lokasi PKL terverifikasi | `POST /api/pkl/update-location/` | Bearer token PKL terverifikasi dan koordinat | Status `201`, lokasi tersimpan | Status `201`, jumlah riwayat lokasi bertambah | Sesuai |
| 7 | Perbarui lokasi PKL belum terverifikasi | `POST /api/pkl/update-location/` | Bearer token PKL pending dan koordinat | Status `403`, lokasi tidak tersimpan | Status `403`, lokasi tidak terbentuk | Sesuai |
| 8 | Simpan lokasi pembeli | `POST /api/pkl/buyer/location/` | Bearer token pembeli, koordinat, radius `300` | Status `200` atau `201`, lokasi tersimpan | Status `201`, radius tersimpan | Sesuai |
| 9 | Ambil daftar PKL aktif | `GET /api/pkl/active/?jenis=Makanan&q=siomay` | Filter kategori dan pencarian | Status `200`, hanya PKL aktif dan terverifikasi yang relevan tampil | Status `200`, PKL relevan tampil dan PKL pending tidak tampil | Sesuai |
| 10 | Ambil detail PKL | `GET /api/pkl/{id}/` | ID PKL | Status `200`, detail PKL dan produk tampil | Status `200`, produk `Siomay Komplit` tampil | Sesuai |
| 11 | Kelola favorit PKL | `POST /api/pkl/buyer/favorites/`, `DELETE /api/pkl/buyer/favorites/{id}/` | Bearer token pembeli dan `pkl_id` | Status `201` saat tambah dan `204` saat hapus | Status `201` dan `204` | Sesuai |
| 12 | Buat pre-order | `POST /api/pkl/preorder/create/` | Bearer token pembeli, produk seharga Rp15.000 sebanyak 2 | Status `201`, total harga dan DP dihitung | Status `201`, total Rp30.000 dan DP Rp6.000 | Sesuai |
| 13 | Ambil daftar pre-order | `GET /api/pkl/preorder/my/`, `GET /api/pkl/preorder/pkl/` | Bearer token sesuai peran | Status `200`, pesanan tampil pada kedua sisi | Status `200`, pesanan ditemukan pada kedua daftar | Sesuai |
| 14 | Perbarui status pre-order oleh PKL | `POST /api/pkl/preorder/{id}/status/` | Bearer token PKL dan status `DITERIMA` | Status `200`, status berubah | Status `200`, status menjadi `DITERIMA` | Sesuai |
| 15 | Simpan URL bukti dan verifikasi DP | `POST /api/pkl/preorder/{id}/upload-dp/`, `POST /api/pkl/preorder/{id}/dp-verification/` | Bearer token, URL bukti DP, dan aksi `TERIMA` | Status `200`, DP berubah menjadi menunggu konfirmasi lalu terkonfirmasi | Status DP berubah menjadi `MENUNGGU_KONFIRMASI`, lalu `TERKONFIRMASI`; pesanan menjadi `DITERIMA` | Sesuai |
| 16 | Mulai chat dan kirim pesan | `POST /api/pkl/chat/start/`, `POST /api/pkl/chat/{id}/messages/` | Bearer token pembeli dan isi pesan | Status `200` atau `201`, ruang chat dan pesan terbentuk | Status `200` dan `201`, isi pesan sesuai | Sesuai |
| 17 | Ambil dan tandai notifikasi dibaca | `GET /api/pkl/buyer/notifications/`, `POST /api/pkl/buyer/notifications/{id}/read/` | Bearer token pembeli | Status `200`, notifikasi tampil dan dibaca | Status `200`, `is_read` berubah menjadi `true` | Sesuai |
| 18 | Akses dashboard admin | `GET /api/pkl/admin/dashboard/` | Bearer token admin | Status `200`, ringkasan dashboard tampil | Status `200`, field `summary` dan `trend` tersedia | Sesuai |

## Pengujian Keamanan Akses Tambahan

| No. | Skenario | Method/Endpoint | Input | Ekspektasi | Hasil Aktual | Kesimpulan |
|---|---|---|---|---|---|---|
| K.1 | Akses fitur privat tanpa login | `GET /api/accounts/me/` | Tanpa token | Status `401` | Status `401` | Sesuai |
| K.2 | Akses dashboard admin oleh pembeli | `GET /api/pkl/admin/dashboard/` | Bearer token pembeli | Status `403` | Status `403` | Sesuai |

## Checklist Pengujian Fitur Aplikasi

Pengujian manual telah dilakukan pada perangkat Android. Seluruh skenario
berjalan sesuai dengan hasil yang diharapkan.

| No. | Skenario | Prosedur Uji | Ekspektasi | Hasil Aktual | Kesimpulan |
|---|---|---|---|---|---|
| T.1 | Splash screen pertama kali | Jalankan aplikasi setelah instalasi awal | Splash tampil lalu onboarding terbuka | Berfungsi sesuai ekspektasi | Sesuai |
| T.2 | Splash screen setelah onboarding | Jalankan ulang aplikasi setelah onboarding | Splash dilanjutkan pengecekan sesi atau halaman utama | Berfungsi sesuai ekspektasi | Sesuai |
| T.3 | Onboarding berjalan | Gunakan tombol Next, Skip, dan Finish | Navigasi berjalan dan status onboarding tersimpan | Berfungsi sesuai ekspektasi | Sesuai |
| T.4 | Izin lokasi dan notifikasi diterima | Setujui kedua izin perangkat | Aplikasi berlanjut dan fitur terkait dapat digunakan | Berfungsi sesuai ekspektasi | Sesuai |
| T.5 | Izin lokasi ditolak | Tolak izin lokasi | Aplikasi tetap terbuka; fitur berbasis GPS tidak berjalan | Berfungsi sesuai ekspektasi | Sesuai |
| T.6 | Izin notifikasi ditolak | Tolak izin notifikasi | Aplikasi tetap dapat digunakan tanpa push notification | Berfungsi sesuai ekspektasi | Sesuai |
| T.7 | Seluruh izin ditolak | Tolak izin lokasi dan notifikasi | Fitur umum tetap dapat dipakai; GPS dan push notification tidak berjalan | Berfungsi sesuai ekspektasi | Sesuai |
| T.8 | Registrasi berhasil | Isi akun baru dengan email valid dan pilih peran | Akun berhasil dibuat | Berfungsi sesuai ekspektasi | Sesuai |
| T.9 | Username duplikat | Daftar menggunakan username yang sudah ada | Registrasi ditolak | Berfungsi sesuai ekspektasi | Sesuai |
| T.10 | Email tidak valid | Daftar menggunakan email `useremail.com` | Registrasi ditolak | Berfungsi sesuai ekspektasi | Sesuai |
| T.11 | Password tidak valid | Gunakan password kosong atau terlalu pendek | Registrasi ditolak | Berfungsi sesuai ekspektasi | Sesuai |
| T.12 | Registrasi PKL tanpa identitas formal | Daftar sebagai PKL dengan data akun dasar | Akun PKL terbentuk dan profil usaha menunggu verifikasi admin | Berfungsi sesuai ekspektasi | Sesuai |
| T.13 | Login berhasil | Masukkan kredensial benar | Masuk ke halaman utama sesuai peran | Berfungsi sesuai ekspektasi | Sesuai |
| T.14 | Login gagal | Masukkan kredensial salah | Pesan login gagal tampil | Berfungsi sesuai ekspektasi | Sesuai |
| T.15 | Refresh token berhasil | Gunakan aplikasi setelah access token kedaluwarsa | Sesi diperbarui otomatis selama refresh token valid | Berfungsi sesuai ekspektasi | Sesuai |
| T.16 | Refresh token gagal | Gunakan refresh token tidak valid | Pengguna diarahkan login ulang | Berfungsi sesuai ekspektasi | Sesuai |
| T.17 | Daftar PKL aktif tampil | Buka halaman utama pembeli | Marker dan daftar PKL aktif terverifikasi tampil | Berfungsi sesuai ekspektasi | Sesuai |
| T.18 | Lokasi pembeli tersimpan | Berikan izin lokasi dan buka halaman utama | Lokasi pembeli tersimpan | Berfungsi sesuai ekspektasi | Sesuai |
| T.19 | Pencarian kata kunci sesuai | Cari `siomay` | PKL relevan tampil | Berfungsi sesuai ekspektasi | Sesuai |
| T.20 | Pencarian kata kunci salah ketik | Cari `somay` | Hasil relevan tampil sesuai fuzzy search | Berfungsi sesuai ekspektasi | Sesuai |
| T.21 | Pencarian tidak tersedia | Cari `sate padang` | Hasil relevan atau kondisi tidak ditemukan tampil | Berfungsi sesuai ekspektasi | Sesuai |
| T.22 | Filter jenis dagangan | Pilih kategori `Makanan` | Daftar PKL menyesuaikan kategori | Berfungsi sesuai ekspektasi | Sesuai |
| T.23 | Filter radius valid | Pilih radius 300, 500, atau 1000 meter | PKL dalam radius tampil | Berfungsi sesuai ekspektasi | Sesuai |
| T.24 | Filter radius tidak valid | Kirim radius di luar opsi melalui API | Nilai ditolak atau digunakan ketentuan bawaan | Berfungsi sesuai ekspektasi | Sesuai |
| T.25 | Detail PKL tampil | Pilih salah satu PKL | Detail profil dan produk tampil | Berfungsi sesuai ekspektasi | Sesuai |
| T.26 | Rute menuju PKL tampil | Pilih marker atau tombol rute | Garis rute menuju PKL tampil | Berfungsi sesuai ekspektasi | Sesuai |
| T.27 | Kelola favorit PKL | Tambahkan lalu hapus favorit | Daftar favorit menyesuaikan aksi | Berfungsi sesuai ekspektasi | Sesuai |
| T.28 | Lihat notifikasi | Buka halaman notifikasi | Daftar notifikasi tampil | Berfungsi sesuai ekspektasi | Sesuai |
| T.29 | Tandai notifikasi dibaca | Pilih salah satu notifikasi | Status notifikasi menjadi telah dibaca | Berfungsi sesuai ekspektasi | Sesuai |
| T.30 | Notifikasi PKL terdekat atau favorit aktif | Berada dalam radius PKL atau aktifkan PKL favorit | Notifikasi relevan diterima | Berfungsi sesuai ekspektasi | Sesuai |
| T.31 | Profil usaha tampil | Masuk sebagai PKL dan buka profil | Profil usaha tampil | Berfungsi sesuai ekspektasi | Sesuai |
| T.32 | Profil usaha dibuat atau diperbarui | Isi profil usaha dan foto | Data tersimpan dan gambar tampil kembali | Berfungsi sesuai ekspektasi | Sesuai |
| T.33 | Pembaruan lokasi manual | Tekan perbarui lokasi sebagai PKL terverifikasi | Lokasi terbaru tersimpan | Berfungsi sesuai ekspektasi | Sesuai |
| T.34 | Pembaruan lokasi otomatis | Aktifkan mode otomatis | Lokasi diperbarui berkala selama izin tersedia | Berfungsi sesuai ekspektasi | Sesuai |
| T.35 | Pembaruan lokasi tanpa izin | Cabut izin lokasi lalu perbarui posisi PKL | Pesan izin lokasi diperlukan tampil | Berfungsi sesuai ekspektasi | Sesuai |
| T.36 | PKL belum terverifikasi mengaktifkan toko | Aktifkan status toko pada profil pending | Aksi ditolak atau fitur terkunci | Berfungsi sesuai ekspektasi | Sesuai |
| T.37 | PKL belum terverifikasi memperbarui lokasi | Perbarui lokasi pada profil pending | Lokasi tidak tersimpan | Berfungsi sesuai ekspektasi | Sesuai |
| T.38 | Status jualan diperbarui | Ubah status toko sebagai PKL terverifikasi | Status berubah sesuai pilihan | Berfungsi sesuai ekspektasi | Sesuai |
| T.39 | Kelola produk PKL | Tambah, ubah, dan hapus produk beserta gambar | Perubahan data produk tersimpan | Berfungsi sesuai ekspektasi | Sesuai |
| T.40 | Harga produk tidak valid | Isi harga kosong atau nol | Penyimpanan ditolak | Berfungsi sesuai ekspektasi | Sesuai |
| T.41 | Pengaturan pembayaran | Isi rekening, e-wallet, tautan pembayaran, dan QRIS | Informasi pembayaran tersimpan | Berfungsi sesuai ekspektasi | Sesuai |
| T.42 | Daftar pre-order PKL | Buka halaman daftar pesanan PKL | Daftar pesanan masuk tampil | Berfungsi sesuai ekspektasi | Sesuai |
| T.43 | Pre-order berhasil dibuat | Pilih item, lokasi pengambilan, lalu pesan | Pre-order terbentuk dengan status pending | Berfungsi sesuai ekspektasi | Sesuai |
| T.44 | Pre-order tanpa item | Kirim pesanan tanpa memilih item | Pesanan ditolak | Berfungsi sesuai ekspektasi | Sesuai |
| T.45 | Riwayat pre-order pembeli | Buka tab riwayat | Riwayat pesanan tampil | Berfungsi sesuai ekspektasi | Sesuai |
| T.46 | Bukti DP berhasil diunggah | Unggah file bukti DP valid di bawah batas bucket | Bukti tampil dan status menunggu konfirmasi | Berfungsi sesuai ekspektasi | Sesuai |
| T.47 | Verifikasi DP oleh PKL | Terima atau tolak bukti DP | Status pembayaran dan pesanan berubah sesuai aksi | Berfungsi sesuai ekspektasi | Sesuai |
| T.48 | Perubahan status pre-order | Ubah status menjadi diterima, ditolak, atau selesai | Status pesanan berubah | Berfungsi sesuai ekspektasi | Sesuai |
| T.49 | Mulai chat | Tekan chat dari detail PKL | Ruang chat terbuka | Berfungsi sesuai ekspektasi | Sesuai |
| T.50 | Kirim pesan chat | Kirim pesan valid | Pesan tampil di ruang chat | Berfungsi sesuai ekspektasi | Sesuai |
| T.51 | Kirim pesan kosong | Tekan kirim saat pesan kosong | Pesan tidak terkirim | Berfungsi sesuai ekspektasi | Sesuai |
| T.52 | Login admin | Masuk dengan akun admin valid | Dashboard admin terbuka | Berfungsi sesuai ekspektasi | Sesuai |
| T.53 | Dashboard admin tampil | Buka dashboard admin | Ringkasan data tampil | Berfungsi sesuai ekspektasi | Sesuai |
| T.54 | Verifikasi PKL oleh admin | Terima atau tolak profil PKL | Status verifikasi berubah | Berfungsi sesuai ekspektasi | Sesuai |
| T.55 | Hapus data PKL | Hapus salah satu data PKL dummy | Data PKL terhapus | Berfungsi sesuai ekspektasi | Sesuai |
| T.56 | Monitoring PKL | Buka halaman monitoring admin | PKL aktif dan lokasi tampil | Berfungsi sesuai ekspektasi | Sesuai |
| T.57 | Akses privat tanpa login | Buka fitur privat tanpa sesi | Pengguna diminta login | Berfungsi sesuai ekspektasi | Sesuai |
| T.58 | Akses admin dengan akun non-admin | Coba membuka dashboard admin sebagai pembeli atau PKL | Akses ditolak | Berfungsi sesuai ekspektasi | Sesuai |
