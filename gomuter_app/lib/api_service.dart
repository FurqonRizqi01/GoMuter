import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:gomuter_app/config.dart';

class ApiService {
  // Base URL backend yang dipakai seluruh request dari aplikasi mobile.
  static const String baseUrl = AppConfig.baseUrl;

  static Map<String, String> _jsonHeaders({String? token}) {
    // Header standar JSON untuk komunikasi dengan REST API backend.
    final headers = {'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      // Access token JWT dikirim pada endpoint yang membutuhkan autentikasi.
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // Endpoint login: mengirim username/password dan menerima access+refresh token.
  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final url = Uri.parse('$baseUrl/api/auth/token/');

    final response = await http.post(
      url,
      headers: _jsonHeaders(),
      body: jsonEncode({"username": username, "password": password}),
    ).timeout(const Duration(seconds: 12));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Login gagal: ${response.body}");
    }
  }

  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String role,
  }) async {
    // Endpoint registrasi akun baru (pembeli/PKL) dari aplikasi mobile.
    final url = Uri.parse('$baseUrl/api/auth/register/');

    final response = await http.post(
      url,
      headers: _jsonHeaders(),
      body: jsonEncode({
        "username": username,
        "email": email,
        "password": password,
        "role": role,
      }),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Registrasi gagal: ${response.body}");
    }
  }

  // Endpoint refresh token: memperbarui access token saat token lama kedaluwarsa.
  static Future<Map<String, dynamic>> refreshAccessToken({
    required String refreshToken,
  }) async {
    final url = Uri.parse('$baseUrl/api/auth/token/refresh/');
    final response = await http
        .post(
          url,
          headers: _jsonHeaders(),
          body: jsonEncode({'refresh': refreshToken}),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Gagal menyegarkan token: ${response.body}');
  }

  static Future<void> requestPasswordReset({required String identifier}) async {
    // Mengirim permintaan reset password berbasis email/username.
    final url = Uri.parse('$baseUrl/api/auth/password-reset/request/');
    final response = await http.post(
      url,
      headers: _jsonHeaders(),
      body: jsonEncode({'identifier': identifier}),
    );

    if (response.statusCode == 200) {
      return;
    }
    throw Exception('Gagal meminta reset password: ${response.body}');
  }

  static Future<void> confirmPasswordReset({
    required String uid,
    required String token,
    required String newPassword,
  }) async {
    // Konfirmasi reset password menggunakan uid + token dari backend.
    final url = Uri.parse('$baseUrl/api/auth/password-reset/confirm/');
    final response = await http.post(
      url,
      headers: _jsonHeaders(),
      body: jsonEncode({
        'uid': uid,
        'token': token,
        'new_password': newPassword,
      }),
    );

    if (response.statusCode == 200) {
      return;
    }
    throw Exception('Gagal reset password: ${response.body}');
  }

  // === Endpoint PKL (role PKL) ===

  static Future<Map<String, dynamic>?> getPKLProfile(String token) async {
    // Mengambil profil PKL milik user yang sedang login.
    final url = Uri.parse('$baseUrl/api/pkl/profile/');
    final response = await http.get(url, headers: _jsonHeaders(token: token));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    if (response.statusCode == 404) {
      return null;
    }
    throw Exception('Gagal mengambil profil PKL: ${response.body}');
  }

  static Future<Map<String, dynamic>> savePKLProfile({
    required String token,
    required Map<String, dynamic> data,
    required bool isNew,
  }) async {
    // Menyimpan profil PKL: POST untuk create, PUT untuk update.
    final url = Uri.parse('$baseUrl/api/pkl/profile/');
    final body = jsonEncode(data);
    late http.Response response;

    if (isNew) {
      response = await http.post(
        url,
        headers: _jsonHeaders(token: token),
        body: body,
      );
    } else {
      response = await http.put(
        url,
        headers: _jsonHeaders(token: token),
        body: body,
      );
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Gagal menyimpan profil PKL: ${response.body}');
  }

  // === PKL products ===

  static Future<List<Map<String, dynamic>>> getPKLProducts(String token) async {
    final url = Uri.parse('$baseUrl/api/pkl/products/');
    final response = await http.get(url, headers: _jsonHeaders(token: token));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data.map((item) => Map<String, dynamic>.from(item)).toList();
    }
    if (response.statusCode == 404) {
      return <Map<String, dynamic>>[];
    }
    throw Exception('Gagal mengambil produk PKL: ${response.body}');
  }

  static Future<Map<String, dynamic>> createPKLProduct({
    required String token,
    required String name,
    required int price,
    String? description,
    bool isFeatured = false,
    bool isAvailable = true,
    List<int>? imageBytes,
    String? imageFileName,
  }) async {
    final url = Uri.parse('$baseUrl/api/pkl/products/');
    final request = http.MultipartRequest('POST', url)
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['name'] = name
      ..fields['price'] = price.toString()
      ..fields['is_featured'] = isFeatured.toString()
      ..fields['is_available'] = isAvailable.toString();

    if (description != null && description.isNotEmpty) {
      request.fields['description'] = description;
    }

    if (imageBytes != null && imageFileName != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: imageFileName,
        ),
      );
    }

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Gagal membuat produk PKL: ${response.body}');
  }

  static Future<Map<String, dynamic>> updatePKLProduct({
    required String token,
    required int productId,
    required String name,
    required int price,
    String? description,
    required bool isFeatured,
    required bool isAvailable,
    List<int>? imageBytes,
    String? imageFileName,
    bool removeImage = false,
  }) async {
    final url = Uri.parse('$baseUrl/api/pkl/products/$productId/');
    final request = http.MultipartRequest('PATCH', url)
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['name'] = name
      ..fields['price'] = price.toString()
      ..fields['is_featured'] = isFeatured.toString()
      ..fields['is_available'] = isAvailable.toString();

    if (description != null) {
      request.fields['description'] = description;
    }

    if (removeImage) {
      request.fields['remove_image'] = 'true';
    }

    if (imageBytes != null && imageFileName != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: imageFileName,
        ),
      );
    }

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Gagal memperbarui produk PKL: ${response.body}');
  }

  static Future<void> deletePKLProduct({
    required String token,
    required int productId,
  }) async {
    final url = Uri.parse('$baseUrl/api/pkl/products/$productId/');
    final response = await http.delete(
      url,
      headers: _jsonHeaders(token: token),
    );

    if (response.statusCode == 204) {
      return;
    }
    throw Exception('Gagal menghapus produk PKL: ${response.body}');
  }

  static Future<Map<String, dynamic>> updatePKLLocation({
    required String token,
    required double latitude,
    required double longitude,
  }) async {
    // Mengirim koordinat lokasi PKL ke backend (manual/otomatis).
    final url = Uri.parse('$baseUrl/api/pkl/update-location/');
    final response = await http
        .post(
          url,
          headers: _jsonHeaders(token: token),
          body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
        )
        .timeout(const Duration(seconds: 12));

    // Backend may return either 200 (OK) or 201 (Created) depending on implementation.
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    if (response.statusCode == 401) {
      throw Exception('Unauthorized (401): ${response.body}');
    }

    throw Exception(
      'Gagal mengupdate lokasi PKL (${response.statusCode}): ${response.body}',
    );
  }

  static Future<Map<String, dynamic>> getPKLDailyStats({
    required String token,
  }) async {
    final url = Uri.parse('$baseUrl/api/pkl/stats/today/');
    final response = await http.get(url, headers: _jsonHeaders(token: token));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Gagal mengambil statistik harian PKL: ${response.body}');
  }

  // === Endpoint daftar/detil PKL untuk pembeli/public ===

  static Future<List<dynamic>> getActivePKL({
    required String accessToken,
    String? jenis,
    String? query,
  }) async {
    // Mengambil daftar PKL aktif dengan opsi filter jenis dagangan dan keyword.
    final params = <String, String>{};
    if (jenis != null && jenis.isNotEmpty) {
      params['jenis'] = jenis;
    }
    if (query != null && query.isNotEmpty) {
      params['q'] = query;
    }

    final baseUri = Uri.parse('$baseUrl/api/pkl/active/');
    final url = params.isEmpty
        ? baseUri
        : baseUri.replace(queryParameters: params);

    final response = await http.get(
      url,
      headers: _jsonHeaders(token: accessToken),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Gagal mengambil daftar PKL aktif: ${response.body}');
  }

  static Future<Map<String, dynamic>> getPKLDetail(int id) async {
    // Mengambil detail satu PKL berdasarkan id untuk halaman detail usaha.
    final url = Uri.parse('$baseUrl/api/pkl/$id/');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Gagal mengambil detail PKL: ${response.body}');
  }

  static Future<Map<String, dynamic>> getPKLRatingSummary({
    required int pklId,
    String? accessToken,
  }) async {
    final url = Uri.parse('$baseUrl/api/pkl/$pklId/rating/');
    final response = await http.get(
      url,
      headers: _jsonHeaders(token: accessToken),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Gagal mengambil rating PKL: ${response.body}');
  }

  static Future<Map<String, dynamic>> submitPKLRating({
    required String token,
    required int pklId,
    required double score,
    String? comment,
  }) async {
    final url = Uri.parse('$baseUrl/api/pkl/$pklId/rating/');
    final payload = {
      'score': double.parse(score.toStringAsFixed(1)),
      if (comment != null && comment.trim().isNotEmpty)
        'comment': comment.trim(),
    };

    final response = await http.post(
      url,
      headers: _jsonHeaders(token: token),
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Gagal menyimpan rating: ${response.body}');
  }

  static Future<void> deletePKLRating({
    required String token,
    required int pklId,
  }) async {
    final url = Uri.parse('$baseUrl/api/pkl/$pklId/rating/');
    final response = await http.delete(
      url,
      headers: _jsonHeaders(token: token),
    );

    if (response.statusCode == 204) {
      return;
    }
    throw Exception('Gagal menghapus rating: ${response.body}');
  }

  // === Endpoint admin ===

  static Future<Map<String, dynamic>> getAdminDashboard({
    required String token,
  }) async {
    // Mengambil ringkasan statistik operasional untuk dashboard admin.
    final url = Uri.parse('$baseUrl/api/pkl/admin/dashboard/');
    final response = await http.get(url, headers: _jsonHeaders(token: token));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Gagal mengambil ringkasan dashboard: ${response.body}');
  }

  static Future<List<dynamic>> getAdminPKLs({
    required String token,
    String? statusVerifikasi,
    bool? statusAktif,
    String? search,
  }) async {
    final query = <String, String>{};
    if (statusVerifikasi != null && statusVerifikasi.isNotEmpty) {
      query['status_verifikasi'] = statusVerifikasi;
    }
    if (statusAktif != null) {
      query['status_aktif'] = statusAktif.toString();
    }
    if (search != null && search.trim().isNotEmpty) {
      query['search'] = search.trim();
    }

    final uri = Uri.parse(
      '$baseUrl/api/pkl/admin/pkls/',
    ).replace(queryParameters: query.isEmpty ? null : query);

    final response = await http.get(uri, headers: _jsonHeaders(token: token));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Gagal mengambil data PKL: ${response.body}');
  }

  static Future<List<dynamic>> getPendingPKL({required String token}) async {
    final url = Uri.parse('$baseUrl/api/pkl/admin/pending/');
    final response = await http.get(url, headers: _jsonHeaders(token: token));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Gagal mengambil PKL pending: ${response.body}');
  }

  static Future<Map<String, dynamic>> verifyPKL({
    required String token,
    required int id,
    required Map<String, dynamic> data,
  }) async {
    // Endpoint verifikasi PKL oleh admin (diterima/ditolak + catatan).
    final url = Uri.parse('$baseUrl/api/pkl/admin/$id/verify/');
    final response = await http.patch(
      url,
      headers: _jsonHeaders(token: token),
      body: jsonEncode(data),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Gagal memverifikasi PKL: ${response.body}');
  }

  static Future<List<dynamic>> monitorActivePKL({required String token}) async {
    final url = Uri.parse('$baseUrl/api/pkl/admin/monitor/');
    final response = await http.get(url, headers: _jsonHeaders(token: token));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Gagal mengambil data monitoring PKL: ${response.body}');
  }

  static Future<void> deleteAdminPKL({
    required String token,
    required int pklId,
  }) async {
    final url = Uri.parse('$baseUrl/api/pkl/admin/pkls/$pklId/');
    final response = await http.delete(url, headers: _jsonHeaders(token: token));

    if (response.statusCode == 204) {
      return;
    }
    throw Exception('Gagal menghapus PKL: ${response.body}');
  }

  static Future<Map<String, dynamic>> getCurrentUser(String accessToken) async {
    final url = Uri.parse('$baseUrl/api/accounts/me/');

    final response = await http.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).timeout(const Duration(seconds: 12));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Gagal mengambil data user: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> updateCurrentUsername({
    required String accessToken,
    required String username,
  }) async {
    final url = Uri.parse('$baseUrl/api/accounts/me/');

    final response = await http.patch(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'username': username}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Gagal memperbarui username: ${response.body}');
  }

  // === Chat endpoints ===

  static Future<Map<String, dynamic>> startChat({
    required String token,
    required int pklId,
  }) async {
    // Membuat/membuka room chat antara pembeli dan PKL.
    final url = Uri.parse('$baseUrl/api/pkl/chat/start/');
    final response = await http.post(
      url,
      headers: _jsonHeaders(token: token),
      body: jsonEncode({'pkl_id': pklId}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Gagal memulai chat: ${response.body}');
  }

  static Future<List<dynamic>> getChatMessages({
    required String token,
    required int chatId,
  }) async {
    // Mengambil riwayat pesan pada room chat tertentu.
    final url = Uri.parse('$baseUrl/api/pkl/chat/$chatId/messages/');
    final response = await http.get(url, headers: _jsonHeaders(token: token));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Gagal mengambil pesan: ${response.body}');
  }

  static Future<Map<String, dynamic>> sendChatMessage({
    required String token,
    required int chatId,
    required String content,
  }) async {
    // Mengirim pesan baru dari user aktif ke room chat.
    final url = Uri.parse('$baseUrl/api/pkl/chat/$chatId/messages/');
    final response = await http.post(
      url,
      headers: _jsonHeaders(token: token),
      body: jsonEncode({'content': content}),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Gagal mengirim pesan: ${response.body}');
  }

  static Future<List<dynamic>> getChats({required String token}) async {
    final url = Uri.parse('$baseUrl/api/pkl/chat/');
    final response = await http.get(url, headers: _jsonHeaders(token: token));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Gagal mengambil daftar chat: ${response.body}');
  }

  // === Pre-order endpoints ===

  static Future<Map<String, dynamic>> createPreOrder({
    required String token,
    required int pklId,
    String? deskripsiPesanan,
    String? catatan,
    String? pickupAddress,
    double? pickupLatitude,
    double? pickupLongitude,
    int? dpAmount,
    double? perkiraanTotal,
    List<Map<String, dynamic>>? items,
  }) async {
    // Membuat transaksi pre-order dari pembeli ke PKL.
    final url = Uri.parse('$baseUrl/api/pkl/preorder/create/');
    final payload = <String, dynamic>{
      'pkl_id': pklId,
      if (deskripsiPesanan != null && deskripsiPesanan.isNotEmpty)
        'deskripsi_pesanan': deskripsiPesanan,
      if (catatan != null && catatan.isNotEmpty) 'catatan': catatan,
      if (pickupAddress != null && pickupAddress.isNotEmpty)
        'pickup_address': pickupAddress,
      if (pickupLatitude != null) 'pickup_latitude': pickupLatitude,
      if (pickupLongitude != null) 'pickup_longitude': pickupLongitude,
      if (dpAmount != null) 'dp_amount': dpAmount,
      if (perkiraanTotal != null) 'perkiraan_total': perkiraanTotal,
      if (items != null && items.isNotEmpty) 'items': items,
    };

    final response = await http.post(
      url,
      headers: _jsonHeaders(token: token),
      body: jsonEncode(payload),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Gagal membuat pre-order: ${response.body}');
  }

  static Future<List<dynamic>> getMyPreOrders({required String token}) async {
    final url = Uri.parse('$baseUrl/api/pkl/preorder/my/');
    final response = await http.get(url, headers: _jsonHeaders(token: token));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Gagal mengambil daftar pre-order: ${response.body}');
  }

  static Future<List<dynamic>> getPKLPreOrders({required String token}) async {
    final url = Uri.parse('$baseUrl/api/pkl/preorder/pkl/');
    final response = await http.get(url, headers: _jsonHeaders(token: token));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Gagal mengambil pre-order PKL: ${response.body}');
  }

  static Future<Map<String, dynamic>> updatePreOrderStatus({
    required String token,
    required int preorderId,
    required String status,
  }) async {
    // Update status pre-order oleh PKL (diterima/ditolak/selesai).
    final url = Uri.parse('$baseUrl/api/pkl/preorder/$preorderId/status/');
    final response = await http.post(
      url,
      headers: _jsonHeaders(token: token),
      body: jsonEncode({'status': status}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Gagal memperbarui status pre-order: ${response.body}');
  }

  static Future<Map<String, dynamic>> uploadDPProof({
    required String token,
    required int preorderId,
    required String buktiUrl,
  }) async {
    final url = Uri.parse('$baseUrl/api/pkl/preorder/$preorderId/upload-dp/');
    final response = await http.post(
      url,
      headers: _jsonHeaders(token: token),
      body: jsonEncode({'bukti_dp_url': buktiUrl}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Gagal mengunggah bukti DP: ${response.body}');
  }

  static Future<Map<String, dynamic>> verifyDPStatus({
    required String token,
    required int preorderId,
    required bool approve,
  }) async {
    // Verifikasi pembayaran DP oleh PKL (TERIMA/TOLAK).
    final url = Uri.parse(
      '$baseUrl/api/pkl/preorder/$preorderId/dp-verification/',
    );
    final response = await http.post(
      url,
      headers: _jsonHeaders(token: token),
      body: jsonEncode({'action': approve ? 'TERIMA' : 'TOLAK'}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Gagal memperbarui status DP: ${response.body}');
  }

  static Future<Map<String, dynamic>> uploadPKLProfilePhoto({
    required String token,
    required List<int> bytes,
    required String filename,
  }) async {
    final url = Uri.parse('$baseUrl/api/pkl/upload/profile-photo/');
    final request = http.MultipartRequest('POST', url)
      ..headers.addAll(_jsonHeaders(token: token))
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Gagal upload foto profil: ${response.body}');
  }

  static Future<String> uploadDPFile({
    required String token,
    required String fileName,
    required List<int> fileBytes,
  }) async {
    final url = Uri.parse('$baseUrl/api/pkl/upload/dp-proof/');
    final request = http.MultipartRequest('POST', url)
      ..headers.addAll(_jsonHeaders(token: token))
      ..files.add(
        http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
      );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final urlValue = data['url'];
      if (urlValue is String) {
        return urlValue;
      }
    }
    throw Exception('Gagal mengunggah file DP: ${response.body}');
  }

  // === Buyer location, favorites, notifications ===

  static Future<Map<String, dynamic>> updateBuyerLocation({
    required String token,
    required double latitude,
    required double longitude,
    int? radiusM,
  }) async {
    // Sinkronisasi lokasi pembeli untuk fitur nearby/favorit dan notifikasi.
    final url = Uri.parse('$baseUrl/api/pkl/buyer/location/');
    final payload = {
      'latitude': latitude,
      'longitude': longitude,
      if (radiusM != null) 'radius_m': radiusM,
    };

    final response = await http.post(
      url,
      headers: _jsonHeaders(token: token),
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Gagal menyimpan lokasi pembeli: ${response.body}');
  }

  static Future<Map<String, dynamic>?> getBuyerLocation({
    required String token,
  }) async {
    final url = Uri.parse('$baseUrl/api/pkl/buyer/location/');
    final response = await http.get(url, headers: _jsonHeaders(token: token));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    if (response.statusCode == 404) {
      return null;
    }
    throw Exception('Gagal mengambil lokasi pembeli: ${response.body}');
  }

  static Future<List<dynamic>> getFavoritePKL({required String token}) async {
    final url = Uri.parse('$baseUrl/api/pkl/buyer/favorites/');
    final response = await http.get(url, headers: _jsonHeaders(token: token));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Gagal mengambil PKL favorit: ${response.body}');
  }

  static Future<Map<String, dynamic>> addFavoritePKL({
    required String token,
    required int pklId,
  }) async {
    final url = Uri.parse('$baseUrl/api/pkl/buyer/favorites/');
    final response = await http.post(
      url,
      headers: _jsonHeaders(token: token),
      body: jsonEncode({'pkl_id': pklId}),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Gagal menambahkan PKL favorit: ${response.body}');
  }

  static Future<void> removeFavoritePKL({
    required String token,
    required int pklId,
  }) async {
    final url = Uri.parse('$baseUrl/api/pkl/buyer/favorites/$pklId/');
    final response = await http.delete(
      url,
      headers: _jsonHeaders(token: token),
    );

    if (response.statusCode == 204) {
      return;
    }
    throw Exception('Gagal menghapus PKL favorit: ${response.body}');
  }

  static Future<List<dynamic>> getNotifications({
    required String token,
    bool unreadOnly = false,
    int limit = 20,
  }) async {
    // Mengambil daftar notifikasi pembeli dari backend.
    final params = {
      'limit': limit.toString(),
      if (unreadOnly) 'unread': 'true',
    };
    final url = Uri.parse(
      '$baseUrl/api/pkl/buyer/notifications/',
    ).replace(queryParameters: params);

    final response = await http.get(url, headers: _jsonHeaders(token: token));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Gagal mengambil notifikasi: ${response.body}');
  }

  static Future<Map<String, dynamic>> markNotificationRead({
    required String token,
    required int notificationId,
  }) async {
    // Menandai notifikasi tertentu sebagai sudah dibaca.
    final url = Uri.parse(
      '$baseUrl/api/pkl/buyer/notifications/$notificationId/read/',
    );
    final response = await http.post(url, headers: _jsonHeaders(token: token));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Gagal memperbarui notifikasi: ${response.body}');
  }
}
