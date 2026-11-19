import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import '../jvm/jar.dart';
import 'proxy.dart';
export 'proxy.dart';
import '../jvm/vm.dart';



class LocalInstance {
  final String id, name, jarName, jarId;
  final int width, height, fps; // fps 0 = không giới hạn
  final bool sound, joystick;
  final int createdAt, lastPlayed;
  final LocalProxy? proxy;
  const LocalInstance(this.id, this.name, this.jarName, this.width, this.height, this.fps, this.sound, this.joystick, this.createdAt,
      {this.lastPlayed = 0, this.jarId = '', this.proxy});

  LocalInstance copy({LocalProxy? proxy, bool clearProxy = false, int? lastPlayed}) => LocalInstance(id, name, jarName, width, height, fps, sound, joystick, createdAt,
      lastPlayed: lastPlayed ?? this.lastPlayed, jarId: jarId, proxy: clearProxy ? null : (proxy ?? this.proxy));

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'jarName': jarName, 'width': width, 'height': height, 'fps': fps, 'sound': sound, 'joystick': joystick,
        'createdAt': createdAt, 'lastPlayed': lastPlayed, 'jarId': jarId, if (proxy != null) 'proxy': proxy!.toJson(),
      };

  static LocalInstance from(Map o) => LocalInstance('${o['id'] ?? ''}', '${o['name'] ?? ''}', '${o['jarName'] ?? ''}', (o['width'] ?? 350) as int,
      (o['height'] ?? 400) as int, (o['fps'] ?? 30) as int, o['sound'] != false, o['joystick'] != false, (o['createdAt'] ?? 0) as int,
      lastPlayed: (o['lastPlayed'] ?? 0) as int, jarId: '${o['jarId'] ?? ''}', proxy: LocalProxy.from(o['proxy']));
}

class DeviceJar {
  final String id, name, error, title;
  final int size, createdAt;
  final bool compiled;
  const DeviceJar(this.id, this.name, this.size, this.createdAt, {this.compiled = false, this.error = '', this.title = ''});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'size': size, 'createdAt': createdAt, 'compiled': compiled, 'error': error, 'title': title};
  static DeviceJar from(Map o) => DeviceJar('${o['id']}', '${o['name']}', (o['size'] ?? 0) as int, (o['createdAt'] ?? 0) as int,
      compiled: o['compiled'] == true, error: '${o['error'] ?? ''}', title: '${o['title'] ?? ''}');
}

String newId() {
  final r = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  return (r + DateTime.now().millisecond.toRadixString(36)).padLeft(12, '0').substring(0, 12);
}

/// Lưu trữ giả lập và kho JAR thiết bị (thư mục dữ liệu của app).
class EmuStore {
  static Directory? _root;
  static Future<Directory> root() async {
    final d = _root ??= Directory('${(await getApplicationDocumentsDirectory()).path}/emu');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static Future<File> _file(String name) async => File('${(await root()).path}/$name');

  // ---- giả lập ----
  static Future<List<LocalInstance>> listInstances() async {
    try {
      final f = await _file('instances.json');
      if (!f.existsSync()) return [];
      return [for (final o in jsonDecode(await f.readAsString()) as List) LocalInstance.from(o as Map)];
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveInstances(List<LocalInstance> l) async => (await _file('instances.json')).writeAsString(jsonEncode([for (final i in l) i.toJson()]));

  static Future<Directory> instanceDir(String id) async {
    final d = Directory('${(await root()).path}/inst/$id');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static Future<File> shot(String id) async => File('${(await instanceDir(id)).path}/jp_shot.png');

  static Future<void> deleteInstance(String id) async {
    final d = Directory('${(await root()).path}/inst/$id');
    if (d.existsSync()) d.deleteSync(recursive: true);
  }

  // ---- kho JAR thiết bị ----
  static Future<List<DeviceJar>> listJars() async {
    try {
      final f = await _file('jars.json');
      if (!f.existsSync()) return [];
      return [for (final o in jsonDecode(await f.readAsString()) as List) DeviceJar.from(o as Map)];
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveJars(List<DeviceJar> l) async => (await _file('jars.json')).writeAsString(jsonEncode([for (final j in l) j.toJson()]));

  static Future<Directory> jarDir(String id) async {
    final d = Directory('${(await root()).path}/jars/$id');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static Future<File> jarFile(String id) async => File('${(await jarDir(id)).path}/app.jar');
  static Future<File> iconFile(String id) async => File('${(await jarDir(id)).path}/icon.png');

  /// Thêm JAR vào kho và kiểm tra/"biên dịch" (đọc lớp + MANIFEST). Trả về mục đã cập nhật.
  static Future<DeviceJar> importJar(String name, Uint8List bytes) async {
    final id = newId();
    await (await jarFile(id)).writeAsBytes(bytes);
    var item = DeviceJar(id, name, bytes.length, DateTime.now().millisecondsSinceEpoch);
    try {
      final vm = Vm();
      final info = loadJar(vm, bytes);
      final hasMain = info.midletClass != null && vm.jarClasses.containsKey(info.midletClass);
      if (vm.jarClasses.isEmpty) throw StateError('JAR không có lớp Java');
      // icon: MIDlet-Icon hoặc trường thứ 2 của MIDlet-1
      final m1 = info.attrs['MIDlet-1']?.split(',').map((e) => e.trim()).toList();
      final iconPath = (info.attrs['MIDlet-Icon'] ?? (m1 != null && m1.length > 1 ? m1[1] : '')).replaceFirst(RegExp(r'^/'), '');
      final iconBytes = iconPath.isEmpty ? null : vm.jarResources[iconPath];
      if (iconBytes != null) await (await iconFile(id)).writeAsBytes(iconBytes);
      item = DeviceJar(id, name, bytes.length, item.createdAt,
          compiled: hasMain, title: info.midletName ?? '', error: hasMain ? '' : 'Không tìm thấy MIDlet chính trong MANIFEST');
    } catch (e) {
      item = DeviceJar(id, name, bytes.length, item.createdAt, error: 'Không đọc được JAR: $e');
    }
    await saveJars([...await listJars(), item]);
    return item;
  }

  static Future<void> deleteJar(String id) async {
    final d = Directory('${(await root()).path}/jars/$id');
    if (d.existsSync()) d.deleteSync(recursive: true);
    await saveJars((await listJars()).where((j) => j.id != id).toList());
  }

  /// Giải nén sẵn một tệp ZIP (dùng cho kiểm thử).
  static bool isZip(Uint8List b) => b.length > 3 && b[0] == 0x50 && b[1] == 0x4B;
  static Archive? tryZip(Uint8List b) {
    try {
      return ZipDecoder().decodeBytes(b);
    } catch (_) {
      return null;
    }
  }
}
