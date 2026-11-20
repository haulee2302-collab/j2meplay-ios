import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextStyle, TextSpan, TextPainter;

/// Giao thức khung JPC1 (v3/v4) - bản Dart của JpcStream.kt + JpcRenderer.kt (Android).
const int jpcMagic = 0x4a504331;
const int jpcLagLimitMs = 300;

int _i32(Uint8List d, int o) => (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3];
int _u16(Uint8List d, int o) => (d[o] << 8) | d[o + 1];

/// Giải nén khung theo luồng (cờ 0x04): MỘT bộ giải nén cho cả kết nối, giải MỌI khung theo đúng thứ tự nhận.
class JpcStreamInflater {
  RawZLibFilter? _f;

  Uint8List inflate(Uint8List data) {
    if (data.length < 14 || _i32(data, 0) != jpcMagic || (data[5] & 0x04) == 0) return data;
    final f = _f ??= RawZLibFilter.inflateFilter(raw: true);
    final rawLength = _i32(data, 10);
    if (rawLength < 0) throw StateError('Khung giải nén sai kích thước');
    final out = Uint8List(10 + rawLength);
    out.setRange(0, 10, data);
    out[5] = out[5] & ~0x04;
    f.process(data, 14, data.length);
    var off = 10;
    while (true) {
      final chunk = f.processed(flush: true, end: false);
      if (chunk == null || chunk.isEmpty) break;
      if (off + chunk.length > out.length) throw StateError('Khung giải nén sai kích thước');
      out.setRange(off, off + chunk.length, chunk);
      off += chunk.length;
    }
    if (off != out.length) throw StateError('Khung giải nén sai kích thước');
    return out;
  }

  void close() => _f = null;
}

bool jpcIsKeyFrame(Uint8List d) => d.length >= 10 && _i32(d, 0) == jpcMagic && (d[5] & 1) != 0;

class JpcMeta {
  final bool sync, readsScreen;
  final int dx, dy, dw, dh, cx, cy, cw, ch;
  JpcMeta(this.sync, this.readsScreen, this.dx, this.dy, this.dw, this.dh, this.cx, this.cy, this.cw, this.ch);
}

JpcMeta? jpcMeta(Uint8List d) {
  if (d.length < 26 || _i32(d, 0) != jpcMagic || d[4] != 4) return null;
  final f = d[5];
  return JpcMeta(f & 1 != 0, f & 8 != 0, _u16(d, 10), _u16(d, 12), _u16(d, 14), _u16(d, 16), _u16(d, 18), _u16(d, 20), _u16(d, 22), _u16(d, 24));
}

bool jpcCoveredLater(Uint8List d, List<Uint8List> later) {
  final m = jpcMeta(d);
  if (m == null || m.sync || m.dw == 0 || m.dh == 0) return false;
  for (final n in later) {
    final x = jpcMeta(n);
    if (x == null) return false;
    if (x.readsScreen) return false;
    if (x.sync) return true;
    if (x.cw != 0 && x.ch != 0 && x.cx <= m.dx && x.cy <= m.dy && x.cx + x.cw >= m.dx + m.dw && x.cy + x.ch >= m.dy + m.dh) return true;
  }
  return false;
}

bool jpcRedrawnLater(Uint8List d, List<Uint8List> later) {
  final m = jpcMeta(d);
  if (m == null || m.sync || m.dw == 0 || m.dh == 0) return false;
  for (final n in later) {
    final x = jpcMeta(n);
    if (x == null) return false;
    if (x.readsScreen) return false;
    if (x.sync) return true;
    if (x.dw != 0 && x.dh != 0 && x.dx <= m.dx && x.dy <= m.dy && x.dx + x.dw >= m.dx + m.dw && x.dy + x.dh >= m.dy + m.dh) return true;
  }
  return false;
}

class FrameResult {
  final int width, height;
  final bool keyFrame, skipped;
  FrameResult(this.width, this.height, this.keyFrame, this.skipped);
}

class _Res {
  final int w, h;
  Uint32List px; // RGBA byte order == little-endian 0xAABBGGRR
  _Res(this.w, this.h, this.px);
  bool? _opaque;

  /// Ảnh không có điểm trong suốt: chép từng hàng một lần thay vì pha từng điểm.
  bool get isOpaque {
    final c = _opaque;
    if (c != null) return c;
    var o = true;
    for (var i = 0; i < px.length; i++) {
      if (px[i] >>> 24 != 255) {
        o = false;
        break;
      }
    }
    _opaque = o;
    return o;
  }
}

class _TextSprite {
  final int w, h, baseline;
  final Uint8List alpha;
  final double advance;
  _TextSprite(this.w, this.h, this.baseline, this.alpha, this.advance);
}

/// Bộ vẽ phần mềm: khung hình là một mảng điểm ảnh RGBA (Uint32 little-endian), nên chép thẳng ra ui.Image được.
class JpcRenderer {
  int width = 0, height = 0;
  Uint32List? fb;

  final Map<int, _Res> _res = {};
  final Map<String, _TextSprite> _sprites = {};

  int _color = 0xFF000000; // packed ABGR
  int _clipL = 0, _clipT = 0, _clipR = 0, _clipB = 0;
  int _stroke = 0;

  void reset() {
    _res.clear();
  }

  void close() {
    _res.clear();
    _sprites.clear();
    fb = null;
  }

  static int _pack(int rgb) => 0xFF000000 | ((rgb & 0xff) << 16) | (rgb & 0xff00) | ((rgb >> 16) & 0xff);

  static int _blend(int dst, int src) {
    final a = src >>> 24;
    if (a == 255) return src;
    if (a == 0) return dst;
    final ia = 255 - a;
    final r = ((src & 255) * a + (dst & 255) * ia) ~/ 255;
    final g = (((src >> 8) & 255) * a + ((dst >> 8) & 255) * ia) ~/ 255;
    final b = (((src >> 16) & 255) * a + ((dst >> 16) & 255) * ia) ~/ 255;
    return 0xFF000000 | (b << 16) | (g << 8) | r;
  }

  // ---- hình cơ bản (toạ độ đã chặn theo vùng cắt) ----
  int get _cl => math.max(_clipL, 0);
  int get _ct => math.max(_clipT, 0);
  int get _cr => math.min(_clipR, width);
  int get _cb => math.min(_clipB, height);

  void _pixel(int x, int y, int c) {
    if (x < _cl || x >= _cr || y < _ct || y >= _cb) return;
    fb![y * width + x] = c;
  }

  void _fillRect(int x0, int y0, int w0, int h0) {
    var x = x0, y = y0, w = w0, h = h0;
    if (w < 0) { x += w; w = -w; }
    if (h < 0) { y += h; h = -h; }
    final l = math.max(x, _cl), t = math.max(y, _ct), r = math.min(x + w, _cr), b = math.min(y + h, _cb);
    if (r <= l || b <= t) return;
    final f = fb!;
    final c = _color;
    for (var yy = t; yy < b; yy++) {
      final base = yy * width;
      f.fillRange(base + l, base + r, c);
    }
  }

  void _line(int ax, int ay, int bx, int by) {
    final c = _color;
    if (_stroke == 0 && ay == by) {
      final l = math.max(_cl, math.min(ax, bx)), r = math.min(_cr, math.max(ax, bx) + 1);
      if (ay >= _ct && ay < _cb && r > l) fb!.fillRange(ay * width + l, ay * width + r, c);
      return;
    }
    if (_stroke == 0 && ax == bx) {
      final t = math.max(_ct, math.min(ay, by)), b = math.min(_cb, math.max(ay, by) + 1);
      if (ax >= _cl && ax < _cr) {
        for (var y = t; y < b; y++) fb![y * width + ax] = c;
      }
      return;
    }
    var x1 = ax, y1 = ay;
    final dx = (bx - x1).abs(), sx = x1 < bx ? 1 : -1;
    final dy = -(by - y1).abs(), sy = y1 < by ? 1 : -1;
    var err = dx + dy, step = 0;
    while (true) {
      if (_stroke == 0 || (step & 1) == 0) _pixel(x1, y1, c);
      if (x1 == bx && y1 == by) break;
      final e2 = err << 1;
      if (e2 >= dy) { err += dy; x1 += sx; }
      if (e2 <= dx) { err += dx; y1 += sy; }
      step++;
    }
  }

  void _rectOutline(int x, int y, int w, int h) {
    _line(x, y, x + w, y);
    _line(x + w, y, x + w, y + h);
    _line(x + w, y + h, x, y + h);
    _line(x, y + h, x, y);
  }

  int _edge(int ax, int ay, int bx, int by, int px, int py) => (px - ax) * (by - ay) - (py - ay) * (bx - ax);

  void _triangle(int x1, int y1, int x2, int y2, int x3, int y3) {
    final minX = math.max(_cl, math.min(x1, math.min(x2, x3)));
    final maxX = math.min(_cr - 1, math.max(x1, math.max(x2, x3)));
    final minY = math.max(_ct, math.min(y1, math.min(y2, y3)));
    final maxY = math.min(_cb - 1, math.max(y1, math.max(y2, y3)));
    if (_edge(x1, y1, x2, y2, x3, y3) == 0) {
      _line(x1, y1, x2, y2);
      _line(x2, y2, x3, y3);
      return;
    }
    final c = _color;
    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        final a = _edge(x1, y1, x2, y2, x, y), b = _edge(x2, y2, x3, y3, x, y), d = _edge(x3, y3, x1, y1, x, y);
        if ((a >= 0 && b >= 0 && d >= 0) || (a <= 0 && b <= 0 && d <= 0)) fb![y * width + x] = c;
      }
    }
  }

  int _jsRound(double v) => (v + 0.5).floor();

  void _arcDirect(int x, int y, int w, int h, int startAngle, int arcAngle, bool filled) {
    if (filled) { _fillArcRows(x, y, w, h, startAngle, arcAngle); return; }
    final steps = math.max(12, (arcAngle.abs() * math.max(w, h) / 90).floor());
    final start = -startAngle * math.pi / 180;
    final delta = (-arcAngle * math.pi / 180) / steps;
    final cx = x + w ~/ 2, cy = y + h ~/ 2;
    var px = cx + _jsRound(math.cos(start) * w / 2), py = cy + _jsRound(math.sin(start) * h / 2);
    for (var i = 1; i <= steps; i++) {
      final a = start + delta * i;
      final nx = cx + _jsRound(math.cos(a) * w / 2), ny = cy + _jsRound(math.sin(a) * h / 2);
      _line(px, py, nx, ny);
      px = nx;
      py = ny;
    }
  }

  void _fillArcRows(int x, int y, int w, int h, int startAngle, int arcAngle) {
    final rx = w / 2.0, ry = h / 2.0;
    if (rx <= 0 || ry <= 0) return;
    final cx = x + rx, cy = y + ry;
    final full = arcAngle.abs() >= 360;
    var a0 = (arcAngle < 0 ? startAngle + arcAngle : startAngle).toDouble();
    final span = math.min(360, arcAngle.abs()).toDouble();
    a0 = ((a0 % 360) + 360) % 360;
    bool inSector(double px, double py) {
      var deg = math.atan2(cy - py, px - cx) * 180 / math.pi;
      if (deg < 0) deg += 360;
      var rel = deg - a0;
      if (rel < 0) rel += 360;
      return rel <= span;
    }

    final top = math.max(_ct, y), bottom = math.min(_cb, (y + h.toDouble()).ceil());
    final c = _color;
    for (var row = top; row < bottom; row++) {
      final dy = (row + 0.5 - cy) / ry;
      if (dy <= -1 || dy >= 1) continue;
      final half = rx * math.sqrt(1 - dy * dy);
      final left = math.max(_cl, (cx - half - 0.5).ceil());
      final right = math.min(_cr - 1, (cx + half - 0.5).floor());
      if (right < left) continue;
      for (var col = left; col <= right; col++) {
        if (full || inSector(col + 0.5, row + 0.5)) fb![row * width + col] = c;
      }
    }
  }

  void _arc(int x, int y, int w, int h, int start, int arc, bool filled) {
    if (w < 0 || h < 0 || arc == 0) return;
    if (_clipR <= _clipL || _clipB <= _clipT) return;
    if (x + w + 2 <= _clipL || y + h + 2 <= _clipT || x - 1 >= _clipR || y - 1 >= _clipB) return;
    _arcDirect(x, y, w, h, start, arc, filled);
  }

  void _roundRect(int x, int y, int w, int h, int arcW, int arcH, bool filled) {
    final aw = math.max(0, math.min(w, arcW)), ah = math.max(0, math.min(h, arcH));
    if (filled) {
      _fillRect(x + aw ~/ 2, y, w - aw, h + 1);
      _fillRect(x, y + ah ~/ 2, w + 1, h - ah);
      _arc(x, y, aw, ah, 90, 90, true);
      _arc(x + w - aw, y, aw, ah, 0, 90, true);
      _arc(x, y + h - ah, aw, ah, 180, 90, true);
      _arc(x + w - aw, y + h - ah, aw, ah, 270, 90, true);
      return;
    }
    _line(x + aw ~/ 2, y, x + w - aw ~/ 2, y);
    _line(x + aw ~/ 2, y + h, x + w - aw ~/ 2, y + h);
    _line(x, y + ah ~/ 2, x, y + h - ah ~/ 2);
    _line(x + w, y + ah ~/ 2, x + w, y + h - ah ~/ 2);
    _arc(x, y, aw, ah, 90, 90, false);
    _arc(x + w - aw, y, aw, ah, 0, 90, false);
    _arc(x, y + h - ah, aw, ah, 180, 90, false);
    _arc(x + w - aw, y + h - ah, aw, ah, 270, 90, false);
  }

  // ---- ảnh ----
  void _drawImage(_Res res, int sx, int sy, int w, int h, int tr, int dx, int dy) {
    if (_clipR <= _clipL || _clipB <= _clipT || w <= 0 || h <= 0) return;
    final f = fb!;
    final cl = _cl, ct = _ct, cr = _cr, cb = _cb;
    if (tr == 0) {
      final i0 = math.max(math.max(0, cl - dx), -sx), i1 = math.min(math.min(w, cr - dx), res.w - sx);
      if (i1 <= i0) return;
      final n = i1 - i0, opaque = res.isOpaque, px = res.px;
      for (var j = 0; j < h; j++) {
        final y = dy + j;
        final srow = sy + j;
        if (y < ct || y >= cb || srow < 0 || srow >= res.h) continue;
        final sb = srow * res.w + sx + i0, db = y * width + dx + i0;
        if (opaque) {
          f.setRange(db, db + n, px, sb);
        } else {
          for (var q = 0; q < n; q++) {
            final sp = px[sb + q];
            final a = sp >>> 24;
            if (a == 255) {
              f[db + q] = sp;
            } else if (a != 0) {
              f[db + q] = _blend(f[db + q], sp);
            }
          }
        }
      }
      return;
    }
    for (var j = 0; j < h; j++) {
      final srow = sy + j;
      if (srow < 0 || srow >= res.h) continue;
      for (var i = 0; i < w; i++) {
        final scol = sx + i;
        if (scol < 0 || scol >= res.w) continue;
        // (i, j) theo toạ độ vùng nguồn; vị trí đích theo từng phép biến đổi MIDP.
        int ox, oy;
        switch (tr) {
          case 1: ox = i; oy = h - 1 - j; break;
          case 2: ox = w - 1 - i; oy = j; break;
          case 3: ox = w - 1 - i; oy = h - 1 - j; break;
          case 4: ox = j; oy = i; break;
          case 5: ox = h - 1 - j; oy = i; break;
          case 6: ox = j; oy = w - 1 - i; break;
          case 7: ox = h - 1 - j; oy = w - 1 - i; break;
          default: throw StateError('JPC1 bad image transform');
        }
        final x = dx + ox, y = dy + oy;
        if (x < cl || x >= cr || y < ct || y >= cb) continue;
        final idx = y * width + x;
        f[idx] = _blend(f[idx], res.px[srow * res.w + scol]);
      }
    }
  }

  void _drawRgb(Uint8List src, int off, int len, int x, int y, int w, int h) {
    if (w <= 0 || h <= 0 || len != w * h * 4) throw StateError('JPC1 RGB size mismatch');
    if (_clipR <= _clipL || _clipB <= _clipT) return;
    final f = fb!;
    final bd = ByteData.sublistView(src, off, off + len);
    for (var j = 0; j < h; j++) {
      final yy = y + j;
      if (yy < _ct || yy >= _cb) continue;
      for (var i = 0; i < w; i++) {
        final xx = x + i;
        if (xx < _cl || xx >= _cr) continue;
        final p = bd.getUint32((j * w + i) * 4, Endian.little);
        final idx = yy * width + xx;
        f[idx] = _blend(f[idx], p);
      }
    }
  }

  void _copyArea(int sx, int sy, int w, int h, int dx, int dy) {
    if (w <= 0 || h <= 0) return;
    final f = fb!;
    final tmp = Uint32List(w * h);
    for (var j = 0; j < h; j++) {
      final y = sy + j;
      if (y < 0 || y >= height) continue;
      for (var i = 0; i < w; i++) {
        final x = sx + i;
        if (x < 0 || x >= width) continue;
        tmp[j * w + i] = f[y * width + x];
      }
    }
    if (_clipR <= _clipL || _clipB <= _clipT) return;
    for (var j = 0; j < h; j++) {
      final y = dy + j;
      if (y < _ct || y >= _cb) continue;
      for (var i = 0; i < w; i++) {
        final x = dx + i;
        if (x < _cl || x >= _cr) continue;
        final p = tmp[j * w + i];
        if (p >>> 24 == 0) continue;
        f[y * width + x] = p;
      }
    }
  }

  // ---- chữ: dựng mặt nạ từng ký tự bằng dart:ui (lưu lại để dùng mãi), ghép lại khi vẽ ----
  Future<_TextSprite> _sprite(String text, int face, int style, int size) async {
    final key = '$face|$style|$size|$text';
    final cached = _sprites[key];
    if (cached != null) return cached;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const ui.Color(0xFFFFFFFF),
          fontSize: size.toDouble(),
          height: 1.0,
          fontFamily: face == 32 ? 'Courier' : null,
          fontWeight: (style & 1) != 0 ? ui.FontWeight.bold : ui.FontWeight.normal,
          fontStyle: (style & 2) != 0 ? ui.FontStyle.italic : ui.FontStyle.normal,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final pad = 2;
    final w = math.max(1, tp.width.ceil() + pad * 2), h = math.max(1, tp.height.ceil() + pad * 2);
    final baseline = pad + tp.computeDistanceToActualBaseline(ui.TextBaseline.alphabetic).round();
    final rec = ui.PictureRecorder();
    final cv = ui.Canvas(rec);
    tp.paint(cv, ui.Offset(pad.toDouble(), pad.toDouble()));
    final img = await rec.endRecording().toImage(w, h);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    final alpha = Uint8List(w * h);
    if (bytes != null) {
      for (var i = 0; i < w * h; i++) alpha[i] = bytes.getUint8(i * 4 + 3);
    }
    if (_sprites.length > 3000) _sprites.clear();
    return _sprites[key] = _TextSprite(w, h, baseline, alpha, tp.width);
  }

  void _blitSprite(_TextSprite sp, int ox, int oy, int r, int g, int b) {
    final f = fb!;
    final j0 = math.max(0, _ct - oy), j1 = math.min(sp.h, _cb - oy);
    final i0 = math.max(0, _cl - ox), i1 = math.min(sp.w, _cr - ox);
    if (j1 <= j0 || i1 <= i0) return;
    final rgb = (b << 16) | (g << 8) | r, al = sp.alpha;
    for (var j = j0; j < j1; j++) {
      final row = (oy + j) * width + ox, srow = j * sp.w;
      for (var i = i0; i < i1; i++) {
        final a = al[srow + i];
        if (a == 0) continue;
        f[row + i] = a == 255 ? (0xFF000000 | rgb) : _blend(f[row + i], (a << 24) | rgb);
      }
    }
  }

  Future<void> _drawText(String value, int x, int baseline, int face, int style, int size) async {
    if (_clipR <= _clipL || _clipB <= _clipT || value.isEmpty) return;
    final sz = math.max(1, size);
    final r = _color & 255, g = (_color >> 8) & 255, b = (_color >> 16) & 255;
    var pen = x.toDouble();
    for (final rune in value.runes) {
      final ch = String.fromCharCode(rune);
      final key = '$face|$style|$sz|$ch';
      final sp = _sprites[key] ?? await _sprite(ch, face, style, sz);
      if (rune != 32 && rune != 9) _blitSprite(sp, pen.round() - 2, baseline - sp.baseline, r, g, b);
      pen += sp.advance;
    }
    if (style & 4 != 0) {
      _fillRect(x, baseline + 1, (pen - x).round(), 1);
    }
  }

  // ---- áp một khung ----
  Future<FrameResult> renderFrame(Uint8List data, bool skipDraw) async {
    if (data.length < 10) throw StateError('JPC1 truncated');
    final v = ByteData.sublistView(data);
    final version = data[4];
    final headerBytes = version == 3 ? 10 : (version == 4 ? 26 : 0);
    if (v.getUint32(0) != jpcMagic || headerBytes == 0) throw StateError('JPC1 v3/v4 required');
    _need(data, 0, headerBytes);
    final flags = data[5];
    if (flags & 0x06 != 0) throw StateError('JPC1 frame still compressed');
    final key = flags & 1 != 0;
    final draw = !(skipDraw && !key);
    final w = v.getUint16(6), h = v.getUint16(8);
    if (w == 0 || h == 0) throw StateError('JPC1 screen size invalid');
    if (fb == null || w != width || h != height) {
      width = w;
      height = h;
      fb = Uint32List(w * h)..fillRange(0, w * h, 0xFF000000);
    }
    _color = 0xFF000000;
    _clipL = 0; _clipT = 0; _clipR = w; _clipB = h;
    _stroke = 0;
    if (key) reset();

    var o = headerBytes;
    final end = data.length;
    while (o < end) {
      final op = data[o];
      o += 1;
      switch (op) {
        case 1:
          _need(data, o, 13);
          _color = _pack(v.getUint32(o) & 0xffffff);
          _clipL = v.getInt16(o + 4); _clipT = v.getInt16(o + 6);
          _clipR = v.getInt16(o + 8); _clipB = v.getInt16(o + 10);
          _stroke = data[o + 12];
          o += 13;
          break;
        case 2: {
          _need(data, o, 20);
          final id = v.getInt32(o);
          final rw = v.getUint16(o + 12), rh = v.getUint16(o + 14);
          final len = v.getInt32(o + 16);
          o += 20;
          _need(data, o, len);
          if (len != rw * rh * 4) throw StateError('JPC1 resource size mismatch');
          final px = Uint32List(rw * rh);
          final bd = ByteData.sublistView(data, o, o + len);
          for (var i = 0; i < px.length; i++) px[i] = bd.getUint32(i * 4, Endian.little);
          _res[id] = _Res(rw, rh, px);
          o += len;
          break;
        }
        case 3:
          _need(data, o, 4);
          _res.remove(v.getInt32(o));
          o += 4;
          break;
        case 4: {
          _need(data, o, 24);
          final id = v.getInt32(o);
          final px = v.getUint16(o + 12), py = v.getUint16(o + 14), pw = v.getUint16(o + 16), ph = v.getUint16(o + 18);
          final len = v.getInt32(o + 20);
          o += 24;
          _need(data, o, len);
          if (pw == 0 || ph == 0 || len != pw * ph * 4) throw StateError('JPC1 resource patch size mismatch');
          final res = _res[id];
          if (res == null) throw StateError('JPC1 missing image resource');
          if (px + pw > res.w || py + ph > res.h) throw StateError('JPC1 resource patch bounds invalid');
          final bd = ByteData.sublistView(data, o, o + len);
          for (var j = 0; j < ph; j++) {
            for (var i = 0; i < pw; i++) {
              res.px[(py + j) * res.w + px + i] = bd.getUint32((j * pw + i) * 4, Endian.little);
            }
          }
          o += len;
          break;
        }
        case 10: case 11: case 12: {
          _need(data, o, 8);
          final a = v.getInt16(o), b = v.getInt16(o + 2), c = v.getInt16(o + 4), d = v.getInt16(o + 6);
          o += 8;
          if (!draw) break;
          if (op == 10) _fillRect(a, b, c, d);
          else if (op == 11) _line(a, b, c, d);
          else _rectOutline(a, b, c, d);
          break;
        }
        case 13: {
          _need(data, o, 17);
          final id = v.getInt32(o);
          final sx = v.getInt16(o + 4), sy = v.getInt16(o + 6), iw = v.getInt16(o + 8), ih = v.getInt16(o + 10);
          final tr = data[o + 12];
          final dx = v.getInt16(o + 13), dy = v.getInt16(o + 15);
          o += 17;
          if (!draw) break;
          final res = _res[id];
          if (res == null) throw StateError('JPC1 missing image resource');
          _drawImage(res, sx, sy, iw, ih, tr, dx, dy);
          break;
        }
        case 14: {
          _need(data, o, 12);
          final x = v.getInt16(o), y = v.getInt16(o + 2), rw = v.getInt16(o + 4), rh = v.getInt16(o + 6);
          final len = v.getInt32(o + 8);
          o += 12;
          _need(data, o, len);
          if (draw) _drawRgb(data, o, len, x, y, rw, rh);
          o += len;
          break;
        }
        case 15: {
          _need(data, o, 12);
          final sx = v.getInt16(o), sy = v.getInt16(o + 2), cw = v.getInt16(o + 4), ch = v.getInt16(o + 6), dx = v.getInt16(o + 8), dy = v.getInt16(o + 10);
          o += 12;
          if (draw) _copyArea(sx, sy, cw, ch, dx, dy);
          break;
        }
        case 16: {
          _need(data, o, 12);
          final p = List<int>.generate(6, (i) => v.getInt16(o + i * 2));
          o += 12;
          if (draw) _triangle(p[0], p[1], p[2], p[3], p[4], p[5]);
          break;
        }
        case 17: {
          _need(data, o, 17);
          final x = v.getInt16(o), y = v.getInt16(o + 2), aw = v.getInt16(o + 4), ah = v.getInt16(o + 6);
          final sa = v.getInt32(o + 8), aa = v.getInt32(o + 12);
          final fill = data[o + 16] != 0;
          o += 17;
          if (draw) _arc(x, y, aw, ah, sa, aa, fill);
          break;
        }
        case 18: {
          _need(data, o, 13);
          final x = v.getInt16(o), y = v.getInt16(o + 2), rw = v.getInt16(o + 4), rh = v.getInt16(o + 6);
          final aw = v.getInt16(o + 8), ah = v.getInt16(o + 10);
          final fill = data[o + 12] != 0;
          o += 13;
          if (draw) _roundRect(x, y, rw, rh, aw, ah, fill);
          break;
        }
        case 19: {
          _need(data, o, 11);
          final x = v.getInt16(o), baseline = v.getInt16(o + 2);
          final face = data[o + 4], style = data[o + 5], size = data[o + 6];
          final len = v.getInt32(o + 7);
          o += 11;
          _need(data, o, len);
          if (draw) {
            final s = utf8.decode(Uint8List.sublistView(data, o, o + len), allowMalformed: true);
            await _drawText(s, x, baseline, face, style, size);
          }
          o += len;
          break;
        }
        default:
          throw StateError('JPC1 opcode $op unsupported');
      }
    }
    return FrameResult(w, h, key, !draw);
  }

  void _need(Uint8List d, int offset, int bytes) {
    if (bytes < 0 || offset + bytes > d.length) throw StateError('JPC1 truncated');
  }

  /// Sao chép khung hình hiện tại ra ui.Image để hiển thị.
  Future<ui.Image?> snapshot() {
    final f = fb;
    if (f == null) return Future.value(null);
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(Uint8List.fromList(f.buffer.asUint8List()), width, height, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }
}
