import 'dart:convert';

class LocalProxy {
  final String type, host, user, pass;
  final int port;
  const LocalProxy(this.type, this.host, this.port, [this.user = '', this.pass = '']);
  String get label => '$host:$port';
  Map<String, dynamic> toJson() => {'enabled': true, 'type': type, 'host': host, 'port': port, 'user': user, 'pass': pass};
  static LocalProxy? from(dynamic o) {
    if (o is! Map || o['enabled'] == false || '${o['host'] ?? ''}'.isEmpty) return null;
    return LocalProxy('${o['type'] ?? 'http'}', '${o['host']}', (o['port'] ?? 0) as int, '${o['user'] ?? ''}', '${o['pass'] ?? ''}');
  }

  /// Đọc "ip:cổng" hoặc "ip:cổng:tài-khoản:mật-khẩu" (có thể kèm socks5:// hoặc http://).
  static LocalProxy? parse(String text, [String defaultType = 'http']) {
    var t = text.trim();
    var type = defaultType;
    final m = RegExp(r'^(socks5h?|http)://', caseSensitive: false).firstMatch(t);
    if (m != null) {
      type = m.group(0)!.toLowerCase().startsWith('socks') ? 'socks5' : 'http';
      t = t.substring(m.end);
    }
    final p = t.split(':');
    if (p.length < 2 || p[0].trim().isEmpty) return null;
    final port = int.tryParse(p[1].trim());
    if (port == null || port < 1 || port > 65535) return null;
    final user = p.length > 2 ? p[2] : '';
    final pass = p.length > 3 ? p.sublist(3).join(':') : '';
    return LocalProxy(type, p[0].trim(), port, user, pass);
  }

  static String format(LocalProxy? p) => p == null ? '' : (p.user.isEmpty && p.pass.isEmpty ? '${p.host}:${p.port}' : '${p.host}:${p.port}:${p.user}:${p.pass}');
}
