import 'dart:typed_data';
import 'dart:ui' as ui;

import '../jvm/gfx.dart';

/// Dựng sẵn bộ chữ (bitmap) từ font hệ thống để Graphics.drawString vẽ đồng bộ.
class Glyphs {
  static final Map<int, GlyphSet> _cache = {};

  static GlyphSet? get(int px, bool bold) => _cache[px * 2 + (bold ? 1 : 0)];

  static Future<void> build() async {
    for (final px in const [9, 12, 15]) {
      for (final bold in const [false, true]) {
        final k = px * 2 + (bold ? 1 : 0);
        if (_cache.containsKey(k)) continue;
        _cache[k] = await _make(px.toDouble(), bold);
      }
    }
  }

  static List<int> _chars() {
    final l = <int>[];
    for (var c = 32; c < 256; c++) {
      if (c != 127) l.add(c);
    }
    for (var c = 0x100; c < 0x180; c++) {
      l.add(c);
    }
    for (var c = 0x1A0; c <= 0x1B0; c++) {
      l.add(c);
    }
    for (var c = 0x1EA0; c <= 0x1EF9; c++) {
      l.add(c);
    }
    l.addAll(const [0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2026, 0x20AB]);
    return l;
  }

  static Future<GlyphSet> _make(double size, bool bold) async {
    final chars = _chars();
    final cell = (size * 2.2).ceil();
    const cols = 32;
    final rows = (chars.length + cols - 1) ~/ cols;
    final W = cols * cell, H = rows * cell;
    final rec = ui.PictureRecorder();
    final cv = ui.Canvas(rec);
    final advs = <int>[];
    var asc = 0.0, hgt = 0.0;
    for (var n = 0; n < chars.length; n++) {
      final pb = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: size, fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w400))
        ..pushStyle(ui.TextStyle(color: const ui.Color(0xFFFFFFFF), fontSize: size, fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w400))
        ..addText(String.fromCharCode(chars[n]));
      final p = pb.build()..layout(const ui.ParagraphConstraints(width: 400));
      asc = p.alphabeticBaseline;
      hgt = p.height;
      advs.add(p.maxIntrinsicWidth.round());
      cv.drawParagraph(p, ui.Offset((n % cols) * cell + 2.0, (n ~/ cols) * cell + 2.0));
    }
    final img = await rec.endRecording().toImage(W, H);
    final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final data = bd!.buffer.asUint8List();
    final gh = hgt.round(), ga = asc.round();
    final map = <int, GlyphData>{};
    for (var n = 0; n < chars.length; n++) {
      final cx = (n % cols) * cell, cy = (n ~/ cols) * cell;
      final gw = advs[n] + 4, ghh = gh + 4;
      final a = Uint8List(gw * ghh);
      var any = false;
      for (var j = 0; j < ghh && j < cell; j++) {
        for (var i = 0; i < gw && i < cell; i++) {
          final v = data[((cy + j) * W + cx + i) * 4 + 3];
          if (v != 0) any = true;
          a[j * gw + i] = v;
        }
      }
      map[chars[n]] = GlyphData(advs[n], any ? gw : 0, any ? ghh : 0, -2, -2, a);
    }
    return GlyphSet(gh, ga, map);
  }
}
