// So sánh kết quả VM với Java thật: dart run bin/conf.dart <thư mục .class> <lớp main>
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../lib/jvm/jar.dart';
import '../../lib/jvm/vm.dart';

Future<void> main(List<String> args) async {
  final dir = Directory(args[0]);
  final main = args[1];
  final out = <String>[];
  final vm = createVm(onLog: (s) => out.add(s));
  vm.mainThread = vm.uiThread;
  for (final f in dir.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.class')) continue;
    var n = f.path.substring(dir.path.length + 1).replaceAll('\\', '/');
    n = n.substring(0, n.length - 6);
    vm.jarClasses[n] = Uint8List.fromList(f.readAsBytesSync());
  }
  unawaited(vm.runScheduler());
  final cls = vm.loadClass(main);
  vm.ensureInit(cls);
  final m = vm.findMethod(cls, 'main([Ljava/lang/String;)V')!;
  final done = Completer<void>();
  final th = vm.newThread(m, [JArray('[Ljava/lang/String;', [])]);
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (!th.done && DateTime.now().isBefore(end)) {
    await Future.delayed(const Duration(milliseconds: 20));
  }
  vm.stop();
  if (!th.done) out.add('TIMEOUT');
  File(args[2]).writeAsStringSync('${out.join('\n')}\n');
  if (!done.isCompleted) done.complete();
  exit(0);
}
