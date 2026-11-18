import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class User {
  final int id;
  final String email, name, role;
  final int balance;
  User(this.id, this.email, this.name, this.balance, this.role);
  factory User.from(Map<String, dynamic> u) => User(
      (u['id'] ?? 0) as int, '${u['email'] ?? ''}', '${u['name'] ?? ''}', ((u['balance'] ?? 0) as num).toInt(), '${u['role'] ?? ''}');
}

class Product {
  final String id, name;
  final int durationDays, price, originalPrice;
  Product(this.id, this.name, this.durationDays, this.price, this.originalPrice);
}

class Rental {
  final String id, deviceName, status;
  final int endsAt, screenWidth, screenHeight;
  final String? machineStatus, productName, connectionStatus;
  Rental(this.id, this.deviceName, this.status, this.endsAt, this.machineStatus, this.productName, this.connectionStatus, this.screenWidth, this.screenHeight);
  factory Rental.from(Map<String, dynamic> o) {
    final screen = o['screen'] as Map<String, dynamic>?;
    int n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return Rental(
      '${o['id'] ?? ''}',
      '${o['deviceName'] ?? o['device_name'] ?? 'Máy J2ME'}',
      '${o['status'] ?? ''}',
      n(o['endsAt'] ?? o['ends_at']),
      '${o['machineStatus'] ?? o['machine_status'] ?? ''}',
      '${o['productName'] ?? o['product_name'] ?? ''}',
      '${o['connectionStatus'] ?? ''}',
      n(screen?['width']),
      n(screen?['height']),
    );
  }
}

class UserJar {
  final String id, name;
  final int size, createdAt;
  UserJar(this.id, this.name, this.size, this.createdAt);
}

class ApiError implements Exception {
  final String message;
  final int code;
  ApiError(this.message, [this.code = 0]);
  @override
  String toString() => message;
}

/// Máy khách API (cùng giao thức với bản Android): Bearer token lưu cục bộ, gốc mặc định https://j2meplay.com
class Api {
  static const defaultBase = 'https://j2meplay.com';
  static final Api instance = Api._();
  Api._();

  String base = defaultBase;
  String? token;
  User? user;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    token = p.getString('auth_token');
    final b = p.getString('server_base_url');
    if (b != null && b.isNotEmpty) base = b.trim().replaceAll(RegExp(r'/+$'), '');
  }

  bool get loggedIn => token != null && token!.isNotEmpty;

  Future<void> _saveToken(String? t) async {
    token = t;
    final p = await SharedPreferences.getInstance();
    if (t == null) {
      await p.remove('auth_token');
    } else {
      await p.setString('auth_token', t);
    }
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
        'X-Jarplay-App': 'ios',
        if (loggedIn) 'Authorization': 'Bearer $token',
        if (loggedIn) 'Cookie': 'jarplay_auth=$token',
      };

  Future<(int, Map<String, dynamic>?, http.Response?)> _send(String method, String path, [Map<String, dynamic>? body]) async {
    try {
      final uri = Uri.parse('$base${path.startsWith('/') ? path : '/$path'}');
      final req = http.Request(method, uri)..headers.addAll(_headers);
      if (body != null) req.body = jsonEncode(body);
      final res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 20)));
      if (res.statusCode == 401 && !path.endsWith('/login')) await _saveToken(null);
      Map<String, dynamic>? json;
      try {
        final d = jsonDecode(utf8.decode(res.bodyBytes));
        if (d is Map<String, dynamic>) json = d;
      } catch (_) {}
      return (res.statusCode, json, res);
    } catch (e) {
      return (0, <String, dynamic>{'error': 'Lỗi kết nối máy chủ'}, null);
    }
  }

  Future<Map<String, dynamic>> _ok(String method, String path, [Map<String, dynamic>? body, String fallback = 'Thao tác thất bại']) async {
    final (code, json, _) = await _send(method, path, body);
    if (code >= 200 && code < 300) return json ?? <String, dynamic>{};
    final msg = json?['error'];
    throw ApiError(msg is String && msg.isNotEmpty ? msg : '$fallback (mã $code)', code);
  }

  Future<User> login(String email, String pass) async {
    final (code, json, res) = await _send('POST', '/api/site/login',
        {'email': email, 'password': pass, 'rememberLogin': true, 'turnstileToken': ''});
    if (code >= 200 && code < 300 && json != null) {
      var t = '${json['token'] ?? ''}';
      if (t.isEmpty) {
        final c = res?.headers['set-cookie'] ?? '';
        final m = RegExp(r'jarplay_auth=([^;]+)').firstMatch(c);
        if (m != null) t = m.group(1)!;
      }
      if (t.isEmpty) throw ApiError('Máy chủ không trả về phiên đăng nhập. Vui lòng thử lại.');
      await _saveToken(t);
      user = User.from(json['user'] as Map<String, dynamic>);
      return user!;
    }
    if (code == 428 && json?['captchaRequired'] == true) {
      throw ApiError('Máy chủ yêu cầu xác minh captcha. Hãy đăng nhập một lần trên j2meplay.com rồi thử lại.');
    }
    final msg = json?['error'];
    throw ApiError(msg is String && msg.isNotEmpty ? msg : 'Đăng nhập thất bại (mã $code)', code);
  }

  Future<User> me() async {
    final j = await _ok('GET', '/api/site/me', null, 'Không thể lấy thông tin người dùng');
    user = User.from(j['user'] as Map<String, dynamic>);
    return user!;
  }

  Future<void> logout() async {
    try { await _send('POST', '/api/site/logout', {}); } catch (_) {}
    await _saveToken(null);
    user = null;
  }

  Future<List<Rental>> rentals() async {
    final j = await _ok('GET', '/api/site/rentals', null, 'Không tải được danh sách phiên');
    return ((j['rentals'] as List?) ?? []).map((e) => Rental.from(e as Map<String, dynamic>)).toList();
  }

  Future<List<Product>> products() async {
    final j = await _ok('GET', '/api/site/products', null, 'Không lấy được bảng giá thuê');
    int n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return ((j['products'] as List?) ?? []).map((e) {
      final o = e as Map<String, dynamic>;
      return Product('${o['id']}', '${o['name']}', n(o['durationDays'] ?? o['duration_days'] ?? 1), n(o['price']), n(o['originalPrice'] ?? o['price']));
    }).toList();
  }

  Future<Map<String, dynamic>> previewRental(String productId, int quantity) =>
      _ok('POST', '/api/site/rentals/preview', {'productId': productId, 'quantity': quantity}, 'Không tính được giá thuê');

  Future<void> createRental(String productId, int quantity) =>
      _ok('POST', '/api/site/rentals', {'productId': productId, 'quantity': quantity}, 'Thuê phiên thất bại');

  Future<void> control(String rentalId, String action) =>
      _ok('POST', '/api/site/rentals/${Uri.encodeComponent(rentalId)}/$action', {}, 'Thực hiện thao tác thất bại');

  Future<Map<String, dynamic>> jars() => _ok('GET', '/api/site/jars', null, 'Không tải được kho JAR');

  Future<void> deleteJar(String id) => _ok('POST', '/api/site/jars/$id/delete', {}, 'Xóa JAR thất bại');

  Future<void> renameJar(String id, String name) => _ok('POST', '/api/site/jars/$id/rename', {'name': name}, 'Đổi tên thất bại');

  Future<Map<String, dynamic>> uploadJar(String filename, List<int> bytes) async {
    final uri = Uri.parse('$base/api/site/jars/upload?filename=${Uri.encodeQueryComponent(filename)}');
    final req = http.Request('POST', uri)..headers.addAll(_headers)..bodyBytes = bytes;
    req.headers['Content-Type'] = 'application/octet-stream';
    final res = await http.Response.fromStream(await req.send().timeout(const Duration(minutes: 3)));
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 200 && res.statusCode < 300) return j as Map<String, dynamic>;
    throw ApiError('${(j as Map)['error'] ?? 'Tải JAR lên thất bại'}', res.statusCode);
  }

  /// POST thô cho các thao tác phụ (đổi mật khẩu...). Trả (mã, json, phản hồi).
  Future<(int, Map<String, dynamic>?, dynamic)> rawGet(String path) => _send('GET', path);

  Future<(int, Map<String, dynamic>?, dynamic)> rawPost(String path, Map<String, dynamic> body) => _send('POST', path, body);
}
