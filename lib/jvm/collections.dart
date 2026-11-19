import "dart:collection";
import 'vm.dart';

class _Iter {
  final List<dynamic> items;
  int i = 0;
  _Iter(this.items);
}

/// java.util: List/ArrayList/LinkedList, Map/HashMap, Set/HashSet, Iterator, Collections, Arrays.
void installCollections(Vm vm) {
  const obj = 'java/lang/Object';
  int i(List a, int k) => a[k] as int;
  NullPointer() => vm.ex('java/lang/NullPointerException');

  const LI = 'java/util/Iterator';
  vm.defClass(LI, null, isInterface: true);
  vm.defClass('java/util/\$Iter', obj, ifaces: [LI]);
  vm.reg('java/util/\$Iter', 'hasNext', '()Z', (v, t, a) { final e = (a[0] as JObject).native as _Iter; return e.i < e.items.length ? 1 : 0; });
  vm.reg('java/util/\$Iter', 'next', '()Ljava/lang/Object;', (v, t, a) {
    final e = (a[0] as JObject).native as _Iter;
    if (e.i >= e.items.length) throw v.ex('java/util/NoSuchElementException');
    return e.items[e.i++];
  });
  vm.reg('java/util/\$Iter', 'remove', '()V', (v, t, a) => null);
  JObject iter(List<dynamic> l) => vm.box('java/util/\$Iter', _Iter(l));

  vm.defClass('java/util/Collection', null, isInterface: true);
  vm.defClass('java/util/List', null, isInterface: true, ifaces: ['java/util/Collection']);
  vm.defClass('java/util/Set', null, isInterface: true, ifaces: ['java/util/Collection']);
  vm.defClass('java/util/Map', null, isInterface: true);
  vm.defClass('java/util/Comparator', null, isInterface: true);
  vm.defClass('java/util/ArrayList', obj, ifaces: ['java/util/List']);
  vm.defClass('java/util/LinkedList', obj, ifaces: ['java/util/List']);
  vm.defClass('java/util/HashSet', obj, ifaces: ['java/util/Set']);
  vm.defClass('java/util/HashMap', obj, ifaces: ['java/util/Map']);
  vm.defClass('java/util/LinkedHashMap', 'java/util/HashMap');
  vm.defClass('java/util/Collections', obj);
  vm.defClass('java/util/Arrays', obj);

  List<dynamic> lst(dynamic o) {
    if (o == null) throw NullPointer();
    final j = o as JObject;
    final n = j.native;
    if (n is List<dynamic>) return n;
    return j.native = <dynamic>[];
  }

  void forLists(String name, {bool vecLike = false}) {
    vm.reg(name, '<init>', '()V', (v, t, a) { lst(a[0]); return null; });
    vm.reg(name, '<init>', '(I)V', (v, t, a) { lst(a[0]); return null; });
    vm.reg(name, '<init>', '(Ljava/util/Collection;)V', (v, t, a) { lst(a[0]).addAll(_items(v, a[1])); return null; });
    vm.reg(name, 'add', '(Ljava/lang/Object;)Z', (v, t, a) { lst(a[0]).add(a[1]); return 1; });
    vm.reg(name, 'add', '(ILjava/lang/Object;)V', (v, t, a) {
      final l = lst(a[0]);
      if (i(a, 1) < 0 || i(a, 1) > l.length) throw v.ex('java/lang/IndexOutOfBoundsException', '${i(a, 1)}');
      l.insert(i(a, 1), a[2]);
      return null;
    });
    vm.reg(name, 'addAll', '(Ljava/util/Collection;)Z', (v, t, a) { lst(a[0]).addAll(_items(v, a[1])); return 1; });
    vm.reg(name, 'get', '(I)Ljava/lang/Object;', (v, t, a) {
      final l = lst(a[0]);
      if (i(a, 1) < 0 || i(a, 1) >= l.length) throw v.ex('java/lang/IndexOutOfBoundsException', '${i(a, 1)}');
      return l[i(a, 1)];
    });
    vm.reg(name, 'set', '(ILjava/lang/Object;)Ljava/lang/Object;', (v, t, a) {
      final l = lst(a[0]);
      if (i(a, 1) < 0 || i(a, 1) >= l.length) throw v.ex('java/lang/IndexOutOfBoundsException', '${i(a, 1)}');
      final o = l[i(a, 1)];
      l[i(a, 1)] = a[2];
      return o;
    });
    vm.reg(name, 'remove', '(I)Ljava/lang/Object;', (v, t, a) {
      final l = lst(a[0]);
      if (i(a, 1) < 0 || i(a, 1) >= l.length) throw v.ex('java/lang/IndexOutOfBoundsException', '${i(a, 1)}');
      return l.removeAt(i(a, 1));
    });
    vm.reg(name, 'remove', '(Ljava/lang/Object;)Z', (v, t, a) {
      final l = lst(a[0]);
      final k = l.indexWhere((e) => v.jequals(e, a[1]));
      if (k < 0) return 0;
      l.removeAt(k);
      return 1;
    });
    vm.reg(name, 'size', '()I', (v, t, a) => lst(a[0]).length);
    vm.reg(name, 'isEmpty', '()Z', (v, t, a) => lst(a[0]).isEmpty ? 1 : 0);
    vm.reg(name, 'clear', '()V', (v, t, a) { lst(a[0]).clear(); return null; });
    vm.reg(name, 'contains', '(Ljava/lang/Object;)Z', (v, t, a) => lst(a[0]).any((e) => v.jequals(e, a[1])) ? 1 : 0);
    vm.reg(name, 'indexOf', '(Ljava/lang/Object;)I', (v, t, a) => lst(a[0]).indexWhere((e) => v.jequals(e, a[1])));
    vm.reg(name, 'iterator', '()Ljava/util/Iterator;', (v, t, a) => iter(List<dynamic>.of(lst(a[0]))));
    vm.reg(name, 'toArray', '()[Ljava/lang/Object;', (v, t, a) => JArray('[Ljava/lang/Object;', List<dynamic>.of(lst(a[0]))));
    vm.reg(name, 'toArray', '([Ljava/lang/Object;)[Ljava/lang/Object;', (v, t, a) => JArray((a[1] as JArray).type, List<dynamic>.of(lst(a[0]))));
    vm.reg(name, 'addFirst', '(Ljava/lang/Object;)V', (v, t, a) { lst(a[0]).insert(0, a[1]); return null; });
    vm.reg(name, 'addLast', '(Ljava/lang/Object;)V', (v, t, a) { lst(a[0]).add(a[1]); return null; });
    vm.reg(name, 'getFirst', '()Ljava/lang/Object;', (v, t, a) {
      final l = lst(a[0]);
      if (l.isEmpty) throw v.ex('java/util/NoSuchElementException');
      return l.first;
    });
    vm.reg(name, 'getLast', '()Ljava/lang/Object;', (v, t, a) {
      final l = lst(a[0]);
      if (l.isEmpty) throw v.ex('java/util/NoSuchElementException');
      return l.last;
    });
    vm.reg(name, 'removeFirst', '()Ljava/lang/Object;', (v, t, a) {
      final l = lst(a[0]);
      if (l.isEmpty) throw v.ex('java/util/NoSuchElementException');
      return l.removeAt(0);
    });
    vm.reg(name, 'removeLast', '()Ljava/lang/Object;', (v, t, a) {
      final l = lst(a[0]);
      if (l.isEmpty) throw v.ex('java/util/NoSuchElementException');
      return l.removeLast();
    });
    vm.reg(name, 'poll', '()Ljava/lang/Object;', (v, t, a) { final l = lst(a[0]); return l.isEmpty ? null : l.removeAt(0); });
    vm.reg(name, 'peek', '()Ljava/lang/Object;', (v, t, a) { final l = lst(a[0]); return l.isEmpty ? null : l.first; });
    vm.reg(name, 'offer', '(Ljava/lang/Object;)Z', (v, t, a) { lst(a[0]).add(a[1]); return 1; });
  }

  forLists('java/util/ArrayList');
  forLists('java/util/LinkedList');

  // HashSet
  const HS = 'java/util/HashSet';
  Map<dynamic, dynamic> mp(dynamic o) {
    if (o == null) throw NullPointer();
    final j = o as JObject;
    final n = j.native;
    if (n is Map<dynamic, dynamic>) return n;
    return j.native = _newMap(vm);
  }

  vm.reg(HS, '<init>', '()V', (v, t, a) { mp(a[0]); return null; });
  vm.reg(HS, '<init>', '(I)V', (v, t, a) { mp(a[0]); return null; });
  vm.reg(HS, '<init>', '(Ljava/util/Collection;)V', (v, t, a) { final m = mp(a[0]); for (final e in _items(v, a[1])) { m[e] = true; } return null; });
  vm.reg(HS, 'add', '(Ljava/lang/Object;)Z', (v, t, a) { final m = mp(a[0]); if (m.containsKey(a[1])) return 0; m[a[1]] = true; return 1; });
  vm.reg(HS, 'remove', '(Ljava/lang/Object;)Z', (v, t, a) => mp(a[0]).remove(a[1]) != null ? 1 : 0);
  vm.reg(HS, 'contains', '(Ljava/lang/Object;)Z', (v, t, a) => mp(a[0]).containsKey(a[1]) ? 1 : 0);
  vm.reg(HS, 'size', '()I', (v, t, a) => mp(a[0]).length);
  vm.reg(HS, 'isEmpty', '()Z', (v, t, a) => mp(a[0]).isEmpty ? 1 : 0);
  vm.reg(HS, 'clear', '()V', (v, t, a) { mp(a[0]).clear(); return null; });
  vm.reg(HS, 'iterator', '()Ljava/util/Iterator;', (v, t, a) => iter(mp(a[0]).keys.toList()));

  // HashMap
  for (final HM in ['java/util/HashMap']) {
    vm.reg(HM, '<init>', '()V', (v, t, a) { mp(a[0]); return null; });
    vm.reg(HM, '<init>', '(I)V', (v, t, a) { mp(a[0]); return null; });
    vm.reg(HM, '<init>', '(IF)V', (v, t, a) { mp(a[0]); return null; });
    vm.reg(HM, 'put', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;', (v, t, a) {
      final m = mp(a[0]);
      final old = m[a[1]];
      m[a[1]] = a[2] ?? _nullVal;
      return old == _nullVal ? null : old;
    });
    vm.reg(HM, 'get', '(Ljava/lang/Object;)Ljava/lang/Object;', (v, t, a) { final r = mp(a[0])[a[1]]; return r == _nullVal ? null : r; });
    vm.reg(HM, 'remove', '(Ljava/lang/Object;)Ljava/lang/Object;', (v, t, a) { final r = mp(a[0]).remove(a[1]); return r == _nullVal ? null : r; });
    vm.reg(HM, 'containsKey', '(Ljava/lang/Object;)Z', (v, t, a) => mp(a[0]).containsKey(a[1]) ? 1 : 0);
    vm.reg(HM, 'containsValue', '(Ljava/lang/Object;)Z', (v, t, a) => mp(a[0]).values.any((e) => v.jequals(e == _nullVal ? null : e, a[1])) ? 1 : 0);
    vm.reg(HM, 'size', '()I', (v, t, a) => mp(a[0]).length);
    vm.reg(HM, 'isEmpty', '()Z', (v, t, a) => mp(a[0]).isEmpty ? 1 : 0);
    vm.reg(HM, 'clear', '()V', (v, t, a) { mp(a[0]).clear(); return null; });
    vm.reg(HM, 'keySet', '()Ljava/util/Set;', (v, t, a) {
      final s = JObject(v.loadClass(HS));
      final m = mp(s);
      for (final k in mp(a[0]).keys) { m[k] = true; }
      return s;
    });
    vm.reg(HM, 'values', '()Ljava/util/Collection;', (v, t, a) {
      final s = JObject(v.loadClass('java/util/ArrayList'));
      s.native = [for (final e in mp(a[0]).values) e == _nullVal ? null : e];
      return s;
    });
  }

  // Collections / Arrays
  const CO = 'java/util/Collections';
  vm.reg(CO, 'reverse', '(Ljava/util/List;)V', (v, t, a) { final l = lst(a[0]); final r = l.reversed.toList(); l..clear()..addAll(r); return null; }, isStatic: true);
  vm.reg(CO, 'shuffle', '(Ljava/util/List;)V', (v, t, a) { lst(a[0]).shuffle(); return null; }, isStatic: true);
  vm.reg(CO, 'sort', '(Ljava/util/List;)V', (v, t, a) { _sortNat(lst(a[0])); return null; }, isStatic: true);

  const AR = 'java/util/Arrays';
  vm.reg(AR, 'fill', '([II)V', (v, t, a) { final x = a[0] as JArray; for (var k = 0; k < x.length; k++) { x.data[k] = a[1]; } return null; }, isStatic: true);
  vm.reg(AR, 'fill', '([BB)V', (v, t, a) { final x = a[0] as JArray; for (var k = 0; k < x.length; k++) { x.data[k] = a[1]; } return null; }, isStatic: true);
  vm.reg(AR, 'fill', '([ZZ)V', (v, t, a) { final x = a[0] as JArray; for (var k = 0; k < x.length; k++) { x.data[k] = a[1]; } return null; }, isStatic: true);
  vm.reg(AR, 'fill', '([SS)V', (v, t, a) { final x = a[0] as JArray; for (var k = 0; k < x.length; k++) { x.data[k] = a[1]; } return null; }, isStatic: true);
  vm.reg(AR, 'fill', '([CC)V', (v, t, a) { final x = a[0] as JArray; for (var k = 0; k < x.length; k++) { x.data[k] = a[1]; } return null; }, isStatic: true);
  vm.reg(AR, 'fill', '([Ljava/lang/Object;Ljava/lang/Object;)V', (v, t, a) { final x = a[0] as JArray; for (var k = 0; k < x.length; k++) { x.data[k] = a[1]; } return null; }, isStatic: true);
  vm.reg(AR, 'sort', '([I)V', (v, t, a) { (a[0] as JArray).data.sort((x, y) => (x as int).compareTo(y as int)); return null; }, isStatic: true);
  vm.reg(AR, 'sort', '([Ljava/lang/Object;)V', (v, t, a) { _sortNat((a[0] as JArray).data); return null; }, isStatic: true);
  JArray copyOf(JArray x, int n) {
    final r = vm.newArray(x.type, n);
    for (var k = 0; k < n && k < x.length; k++) { r.data[k] = x.data[k]; }
    return r;
  }
  for (final d in ['[I', '[B', '[C', '[S', '[Z', '[J', '[Ljava/lang/Object;']) {
    vm.reg(AR, 'copyOf', '(${d}I)$d', (v, t, a) => copyOf(a[0] as JArray, i(a, 1)), isStatic: true);
  }
  vm.reg(AR, 'copyOf', '([Ljava/lang/String;I)[Ljava/lang/String;', (v, t, a) => copyOf(a[0] as JArray, i(a, 1)), isStatic: true);
  vm.reg(AR, 'copyOfRange', '([III)[I', (v, t, a) {
    final x = a[0] as JArray;
    final r = vm.newArray('[I', i(a, 2) - i(a, 1));
    for (var k = i(a, 1); k < i(a, 2) && k < x.length; k++) { r.data[k - i(a, 1)] = x.data[k]; }
    return r;
  }, isStatic: true);
  vm.reg(AR, 'copyOfRange', '([BII)[B', (v, t, a) {
    final x = a[0] as JArray;
    final r = vm.newArray('[B', i(a, 2) - i(a, 1));
    for (var k = i(a, 1); k < i(a, 2) && k < x.length; k++) { r.data[k - i(a, 1)] = x.data[k]; }
    return r;
  }, isStatic: true);
  vm.reg(AR, 'asList', '([Ljava/lang/Object;)Ljava/util/List;', (v, t, a) {
    final s = JObject(v.loadClass('java/util/ArrayList'));
    s.native = List<dynamic>.of((a[0] as JArray).data);
    return s;
  }, isStatic: true);
}

final Object _nullVal = Object();

Map<dynamic, dynamic> _newMap(Vm v) => _mk(v);
Map<dynamic, dynamic> _mk(Vm v) => _LinkedMap.create(v);

class _LinkedMap {
  static Map<dynamic, dynamic> create(Vm v) =>
      LinkedHashMap<dynamic, dynamic>(equals: v.jequals, hashCode: v.jhash);
}

List<dynamic> _items(Vm v, dynamic o) {
  if (o == null) throw v.ex('java/lang/NullPointerException');
  final n = (o as JObject).native;
  if (n is List<dynamic>) return n;
  if (n is Map<dynamic, dynamic>) return n.keys.toList();
  return const [];
}

void _sortNat(List<dynamic> l) {
  l.sort((x, y) {
    final a = x is JObject ? x.native : x;
    final b = y is JObject ? y.native : y;
    if (a is num && b is num) return a.compareTo(b);
    if (a is String && b is String) return a.compareTo(b);
    return 0;
  });
}
