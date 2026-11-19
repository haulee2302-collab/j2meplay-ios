import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'extra.dart';
import 'natives.dart';
import 'vm.dart';

class JarInfo {
  final String? midletClass, midletName, vendor, version;
  final Map<String, String> attrs;
  JarInfo(this.midletClass, this.midletName, this.vendor, this.version, this.attrs);
}

/// Nạp tệp .jar vào VM: giải nén các lớp/tài nguyên và đọc MANIFEST (MIDlet-1 ...).
JarInfo loadJar(Vm vm, Uint8List bytes) {
  final z = ZipDecoder().decodeBytes(bytes);
  var manifest = '';
  for (final f in z.files) {
    if (!f.isFile) continue;
    if (f.name.endsWith('.class')) {
      vm.jarClasses.addLazy(f.name.substring(0, f.name.length - 6), f);
    } else {
      final key = f.name.startsWith('/') ? f.name.substring(1) : f.name;
      vm.jarResources.addLazy(key, f);
      if (f.name.toUpperCase() == 'META-INF/MANIFEST.MF') manifest = utf8.decode(Uint8List.fromList(f.content as List<int>), allowMalformed: true);
    }
  }
  final attrs = <String, String>{};
  final lines = manifest.replaceAll('\r\n', '\n').split('\n');
  String? last;
  for (final l in lines) {
    if (l.startsWith(' ') && last != null) {
      attrs[last] = attrs[last]! + l.substring(1);
    } else {
      final k = l.indexOf(':');
      if (k > 0) {
        last = l.substring(0, k).trim();
        attrs[last] = l.substring(k + 1).trim();
      }
    }
  }
  String? mc, mn;
  final m1 = attrs['MIDlet-1'];
  if (m1 != null) {
    final p = m1.split(',').map((e) => e.trim()).toList();
    if (p.length >= 3) {
      mn = p[0];
      mc = p[2].replaceAll('.', '/');
    }
  }
  return JarInfo(mc, mn, attrs['MIDlet-Vendor'], attrs['MIDlet-Version'], attrs);
}

/// Tạo VM mới đã cài thư viện cơ bản.
Vm createVm({void Function(String)? onLog}) {
  final vm = Vm()..onLog = onLog;
  installCore(vm);
  installExtra(vm);
  return vm;
}
