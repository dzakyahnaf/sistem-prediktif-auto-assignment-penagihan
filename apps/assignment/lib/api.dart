import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int? status;
  final bool mayHaveSucceeded;
  ApiException(this.message, [this.status, this.mayHaveSucceeded = false]);
  @override
  String toString() => message;
}

class Api extends ChangeNotifier {
  final http.Client client;
  final String baseUrl;
  final Duration timeout;
  String? _token;
  Map<String, dynamic>? _user;
  int _sessionRevision = 0;
  bool _disposed = false;
  String? sessionMessage;
  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  int get sessionRevision => _sessionRevision;
  Api({http.Client? client, this.baseUrl = const String.fromEnvironment('API_URL', defaultValue: 'http://127.0.0.1:8000'), this.timeout = const Duration(seconds: 15)})
      : client = client ?? http.Client();
  bool get supervisor => user?['role'] == 'supervisor';
  bool get readOnly => user?['role'] == 'viewer';

  Future<dynamic> request(String method, String path, [Object? data]) async {
    return _request(method, path, data);
  }

  Future<Uint8List> exportCsv(String path) async => await _request('GET', path, null, binaryMime: 'text/csv') as Uint8List;
  Future<Uint8List> exportDataset(String path) async => await _request('GET', path, null, binaryMime: 'application/zip') as Uint8List;
  Future<Uint8List> exportWorkbook(String path) async => await _request('GET', path, null,
    binaryMime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') as Uint8List;
  Future<dynamic> uploadWorkbook(Uint8List bytes, String filename, String kind) =>
    _request('POST', '/api/imports/upload?${Uri(queryParameters: {'kind': kind, 'filename': filename}).query}', bytes, upload: true);

  Future<dynamic> _request(String method, String path, Object? data, {String? binaryMime, bool upload = false}) async {
    final publicRequest = path == '/api/auth/login' || path == '/api/health';
    final issuedRevision = _sessionRevision;
    final issuedToken = _token;
    final mutation = method != 'GET';
    if (_disposed || (!publicRequest && issuedToken == null)) {
      throw ApiException('Silakan masuk kembali.', 401);
    }
    final req = http.Request(method, endpoint(baseUrl, path));
    req.headers['Content-Type'] = upload ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' : 'application/json';
    if (!publicRequest && issuedToken != null) req.headers['Authorization'] = 'Bearer $issuedToken';
    if (upload) { req.bodyBytes = data as Uint8List; }
    else if (data != null) { req.body = jsonEncode(data); }
    try {
      final response = await (() async {
        final streamed = await client.send(req);
        return http.Response.fromStream(streamed);
      })().timeout(timeout);
      // A late response from a previous user must never populate the next user's UI.
      if (_disposed || issuedRevision != _sessionRevision) {
        throw ApiException('Sesi telah berubah. Muat ulang data.', 409);
      }
      // Expire the session even if a proxy returned a non-JSON 401 response.
      if (response.statusCode == 401 && !publicRequest) {
        clearSession(message: 'Sesi Anda berakhir. Silakan masuk kembali.');
        throw ApiException('Sesi Anda berakhir. Silakan masuk kembali.', 401);
      }
      if (binaryMime != null && response.statusCode >= 200 && response.statusCode < 300) {
        if ((response.headers['content-type'] ?? '').split(';').first.trim().toLowerCase() != binaryMime) {
          throw ApiException('Berkas unduhan tidak valid. Muat ulang dan coba kembali.', response.statusCode);
        }
        return response.bodyBytes;
      }
      dynamic body;
      try {
        body = response.body.isEmpty ? null : jsonDecode(response.body);
      } on FormatException {
        throw ApiException('Respons layanan tidak valid. Muat ulang sebelum mencoba kembali.', response.statusCode, mutation);
      }
      if (response.statusCode >= 400) {
        final detail = body is Map ? body['detail'] : null;
        final message = detail is String ? detail : validationMessage(detail);
        throw ApiException(message, response.statusCode, mutation && response.statusCode >= 500);
      }
      return body;
    } on TimeoutException {
      throw ApiException('Respons terlalu lama. Muat ulang data sebelum mencoba kembali.', null, mutation);
    } on http.ClientException {
      throw ApiException('Layanan belum terhubung. Periksa koneksi dan coba lagi.', null, mutation);
    }
  }

  static Uri endpoint(String baseUrl, String path, {Uri? origin}) {
    final uri = baseUrl.isEmpty ? (origin ?? Uri.base).resolve(path) : Uri.parse('$baseUrl$path');
    if (!uri.hasAuthority || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ApiException('Alamat layanan belum dikonfigurasi.');
    }
    return uri;
  }

  Future<void> login(String username, String password) async {
    final result = await request('POST', '/api/auth/login', {'username': username, 'password': password});
    if (result is! Map || result['access_token'] is! String || result['user'] is! Map) {
      throw ApiException('Respons login tidak valid. Silakan coba kembali.');
    }
    _token = result['access_token'] as String;
    _user = Map<String, dynamic>.from(result['user'] as Map);
    sessionMessage = null;
    _sessionRevision++;
    notifyListeners();
  }

  void clearSession({String? message}) {
    if (_disposed || (_token == null && _user == null)) return;
    _token = null;
    _user = null;
    sessionMessage = message;
    _sessionRevision++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    client.close();
    super.dispose();
  }
}

String validationMessage(dynamic detail) {
  const fields = {'amount': 'nominal', 'income': 'penghasilan', 'dpd': 'hari keterlambatan', 'customer': 'nama demo', 'region_id': 'wilayah', 'note': 'catatan', 'promise_date': 'tanggal janji'};
  if (detail is List) {
    final invalid = <String>{};
    for (final item in detail) {
      if (item is Map && item['loc'] is List && (item['loc'] as List).length > 1) {
        final field = (item['loc'] as List).last.toString();
        invalid.add(fields[field] ?? 'isian formulir');
      }
    }
    if (invalid.isNotEmpty) return 'Periksa ${invalid.take(3).join(', ')}. Nilai belum sesuai ketentuan.';
  }
  return 'Permintaan belum dapat diproses. Periksa isian dan coba kembali.';
}

String rupiah(num value) {
  final raw = value.round().toString();
  return 'Rp ${raw.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
}

String label(String value) => const {
  'collection': 'Penagihan', 'origination': 'Pengajuan', 'new': 'Belum ditugaskan',
  'assigned': 'Ditugaskan', 'in_progress': 'Ditindaklanjuti', 'promised': 'Janji bayar',
  'documents': 'Dokumen lengkap', 'qualified': 'Lolos verifikasi', 'paid': 'Lunas',
  'disbursed': 'Dicairkan', 'rejected': 'Ditolak', 'contacted': 'Terhubung',
  'unreachable': 'Tidak terhubung', 'promise': 'Janji bayar', 'payment': 'Pembayaran',
  'disburse': 'Pencairan simulasi', 'reject': 'Penolakan', 'success': 'Berhasil',
  'no_success': 'Tidak berhasil', 'superseded': 'Dialihkan',
}[value] ?? value;

String dateLabel(String? value) {
  if (value == null) return '—';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  final time = parsed.toUtc().add(const Duration(hours: 7));
  return '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}/${time.year} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} WIB';
}
