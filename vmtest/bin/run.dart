// Chạy thử từng JAR trong VM (không cần iPhone): dart run bin/run.dart <thư mục jar> <thư mục kết quả>
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as im;

import '../../lib/emu/net.dart';
import '../../lib/jvm/jar.dart';
import '../../lib/jvm/midp.dart';
import '../../lib/jvm/vm.dart';

Future<void> main(List<String> args) async {
  // dart run bin/run.dart <thư mục kết quả> <thư mục jar> [+thư mục jar đọc cả thư mục con] ...
  final out = Directory(args[0])..createSync(recursive: true);
  final jars = <File>[];
  for (final a in args.skip(1)) {
    final rec = a.startsWith('+');
    final d = Directory(rec ? a.substring(1) : a);
    if (!d.existsSync()) continue;
    jars.addAll(d.listSync(recursive: rec).whereType<File>().where((f) => f.path.toLowerCase().endsWith('.jar')));
  }
  jars.removeWhere((f) => RegExp(r'(cfr|asm|apktool|gradle-wrapper)', caseSensitive: false).hasMatch(f.path.split(Platform.pathSeparator).last) || f.path.contains('tools'));
  jars.sort((a, b) => a.path.compareTo(b.path));
  final summary = StringBuffer();
  var idx = 0;
  for (final f in jars) {
    idx++;
    final name = f.path.split(Platform.pathSeparator).last;
    final log = <String>[];
    final vm = createVm(onLog: (s) { if (log.length < 400) log.add(s); });
    String status = 'OK';
    Midp? m;
    var paints = 0;
    try {
      vm.mainThread = vm.uiThread;
      final info = loadJar(vm, Uint8List.fromList(f.readAsBytesSync()));
      if (info.midletClass == null) {
        status = 'KHÔNG CÓ MIDlet-1';
      } else {
        m = Midp(vm, 240, 320, info.attrs);
        m.install();
        installNet(m, null);
        m.onFrame = () => paints++;
        final mid = vm.newInstance(info.midletClass!);
        unawaited(vm.runScheduler());
        m.start(mid);
        final end = DateTime.now().add(const Duration(seconds: 8));
        while (DateTime.now().isBefore(end)) {
          await Future.delayed(const Duration(milliseconds: 40));
          m.tick();
        }
      }
    } on JavaThrow catch (e) {
      status = 'LỖI KHỞI ĐỘNG: ${vm.jtoString(e.obj)}';
    } catch (e, st) {
      status = 'LỖI DART: $e\n${st.toString().split('\n').take(6).join('\n')}';
    }
    vm.stop();
    final errs = log.where((l) => l.startsWith('Lỗi') || l.startsWith('Ngoại lệ')).toList();
    if (status == 'OK' && errs.isNotEmpty) status = 'CÓ LỖI LÚC CHẠY';
    summary.writeln('[$idx] $name  => $status  (khung hình: $paints, form: ${m?.form?.cls.name ?? '-'})');
    for (final l in errs.take(6)) {
      summary.writeln('      $l');
    }
    final tail = log.where((l) => !errs.contains(l)).take(8).toList();
    for (final l in tail) {
      summary.writeln('      · $l');
    }
    if (m != null && paints > 0) {
      final img = im.Image(width: m.width, height: m.height);
      for (var y = 0; y < m.height; y++) {
        for (var x = 0; x < m.width; x++) {
          final c = m.screen.px[y * m.width + x];
          img.setPixelRgba(x, y, (c >> 16) & 255, (c >> 8) & 255, c & 255, 255);
        }
      }
      File('${out.path}/${idx.toString().padLeft(2, '0')}_${name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}.png').writeAsBytesSync(im.encodePng(img));
    }
    stdout.writeln(summary.toString().split('\n').where((l) => l.startsWith('[$idx]')).join('\n'));
  }
  File('${out.path}/summary.txt').writeAsStringSync(summary.toString());
  exit(0);
}
