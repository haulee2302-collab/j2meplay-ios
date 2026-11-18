import 'dart:math' as math;
import 'dart:typed_data';

/// Bộ vẽ phần mềm cho MIDP Graphics: ảnh ARGB 32-bit, cắt vùng (clip), trộn alpha.
class Surface {
  final int w, h;
  final Uint32List px;
  bool hasAlpha;
  Surface(this.w, this.h, {int fill = 0xFFFFFFFF, this.hasAlpha = false}) : px = Uint32List(w * h) {
    if (fill != 0) px.fillRange(0, px.length, fill);
  }
  Surface.from(this.w, this.h, this.px, {this.hasAlpha = true});

  Surface copy() => Surface.from(w, h, Uint32List.fromList(px), hasAlpha: hasAlpha);
}

class GlyphData {
  final int adv, w, h, ox, oy;
  final Uint8List alpha; // w*h
  const GlyphData(this.adv, this.w, this.h, this.ox, this.oy, this.alpha);
}

/// Bộ chữ đã dựng sẵn cho một cỡ.
class GlyphSet {
  final int height, ascent;
  final Map<int, GlyphData> glyphs;
  GlyphSet(this.height, this.ascent, this.glyphs);
  int adv(int c) => glyphs[c]?.adv ?? (height * 0.55).round();
}

class Gfx {
  final Surface s;
  int color = 0xFF000000;
  int tx = 0, ty = 0;
  int cx = 0, cy = 0, cw = 0, ch = 0; // clip (toạ độ thiết bị)
  Gfx(this.s) {
    cw = s.w;
    ch = s.h;
  }

  void setClip(int x, int y, int w, int h) {
    cx = x + tx;
    cy = y + ty;
    cw = w < 0 ? 0 : w;
    ch = h < 0 ? 0 : h;
  }

  void clipRect(int x, int y, int w, int h) {
    final x0 = math.max(cx, x + tx), y0 = math.max(cy, y + ty);
    final x1 = math.min(cx + cw, x + tx + w), y1 = math.min(cy + ch, y + ty + h);
    cx = x0;
    cy = y0;
    cw = math.max(0, x1 - x0);
    ch = math.max(0, y1 - y0);
  }

  // ---- điểm ảnh ----
  void _put(int x, int y, int c) {
    if (x < cx || y < cy || x >= cx + cw || y >= cy + ch || x < 0 || y < 0 || x >= s.w || y >= s.h) return;
    final a = c >>> 24;
    if (a == 255) {
      s.px[y * s.w + x] = c;
    } else if (a != 0) {
      s.px[y * s.w + x] = blend(s.px[y * s.w + x], c);
    }
  }

  static int blend(int dst, int src) {
    final a = src >>> 24;
    if (a == 255) return src;
    if (a == 0) return dst;
    final ia = 255 - a;
    final da = dst >>> 24;
    final r = (((src >> 16) & 255) * a + ((dst >> 16) & 255) * ia) ~/ 255;
    final g = (((src >> 8) & 255) * a + ((dst >> 8) & 255) * ia) ~/ 255;
    final b = ((src & 255) * a + (dst & 255) * ia) ~/ 255;
    final na = a + da * ia ~/ 255;
    return (na << 24) | (r << 16) | (g << 8) | b;
  }

  void fillRect(int x, int y, int w, int h) {
    x += tx;
    y += ty;
    var x0 = math.max(math.max(x, cx), 0), y0 = math.max(math.max(y, cy), 0);
    var x1 = math.min(math.min(x + w, cx + cw), s.w), y1 = math.min(math.min(y + h, cy + ch), s.h);
    if (x0 >= x1 || y0 >= y1) return;
    final a = color >>> 24;
    for (var j = y0; j < y1; j++) {
      final row = j * s.w;
      if (a == 255) {
        s.px.fillRange(row + x0, row + x1, color);
      } else if (a != 0) {
        for (var i = x0; i < x1; i++) {
          s.px[row + i] = blend(s.px[row + i], color);
        }
      }
    }
  }

  void drawRect(int x, int y, int w, int h) {
    if (w < 0 || h < 0) return;
    fillRect(x, y, w + 1, 1);
    fillRect(x, y + h, w + 1, 1);
    fillRect(x, y + 1, 1, h - 1);
    fillRect(x + w, y + 1, 1, h - 1);
  }

  void drawLine(int x0, int y0, int x1, int y1) {
    x0 += tx; y0 += ty; x1 += tx; y1 += ty;
    final dx = (x1 - x0).abs(), dy = -(y1 - y0).abs();
    final sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
    var err = dx + dy;
    while (true) {
      _put(x0, y0, color);
      if (x0 == x1 && y0 == y1) break;
      final e2 = 2 * err;
      if (e2 >= dy) { err += dy; x0 += sx; }
      if (e2 <= dx) { err += dx; y0 += sy; }
    }
  }

  /// Tô đa giác (toạ độ thiết bị, quy tắc chẵn-lẻ).
  void _fillPoly(List<double> xs, List<double> ys) {
    final n = xs.length;
    if (n < 3) return;
    var minY = ys[0], maxY = ys[0];
    for (final y in ys) {
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    final y0 = math.max(minY.floor(), math.max(cy, 0)), y1 = math.min(maxY.ceil(), math.min(cy + ch, s.h) - 1);
    for (var y = y0; y <= y1; y++) {
      final fy = y + 0.5;
      final cross = <double>[];
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        final ya = ys[i], yb = ys[j];
        if ((ya <= fy && yb > fy) || (yb <= fy && ya > fy)) {
          cross.add(xs[i] + (fy - ya) / (yb - ya) * (xs[j] - xs[i]));
        }
      }
      cross.sort();
      for (var k = 0; k + 1 < cross.length; k += 2) {
        final xa = cross[k].round(), xb = cross[k + 1].round();
        for (var x = xa; x < xb; x++) {
          _put(x, y, color);
        }
      }
    }
  }

  void fillTriangle(int x1, int y1, int x2, int y2, int x3, int y3) {
    _fillPoly([x1 + tx + 0.0, x2 + tx + 0.0, x3 + tx + 0.0], [y1 + ty + 0.0, y2 + ty + 0.0, y3 + ty + 0.0]);
  }

  List<List<double>> _arcPts(int x, int y, int w, int h, int start, int arc, {bool sector = false}) {
    final xs = <double>[], ys = <double>[];
    final cxx = x + tx + w / 2.0, cyy = y + ty + h / 2.0;
    final steps = math.max(12, ((w + h) / 2).round());
    final a0 = start * math.pi / 180.0;
    final a = arc.clamp(-360, 360) * math.pi / 180.0;
    if (sector) {
      xs.add(cxx);
      ys.add(cyy);
    }
    for (var i = 0; i <= steps; i++) {
      final t = a0 + a * i / steps;
      xs.add(cxx + math.cos(t) * w / 2.0);
      ys.add(cyy - math.sin(t) * h / 2.0);
    }
    return [xs, ys];
  }

  void fillArc(int x, int y, int w, int h, int start, int arc) {
    if (w <= 0 || h <= 0) return;
    final p = _arcPts(x, y, w, h, start, arc, sector: arc.abs() < 360);
    _fillPoly(p[0], p[1]);
  }

  void drawArc(int x, int y, int w, int h, int start, int arc) {
    if (w < 0 || h < 0) return;
    final p = _arcPts(x, y, w, h, start, arc);
    for (var i = 0; i + 1 < p[0].length; i++) {
      drawLine((p[0][i] - tx).round(), (p[1][i] - ty).round(), (p[0][i + 1] - tx).round(), (p[1][i + 1] - ty).round());
    }
  }

  List<List<double>> _roundPts(int x, int y, int w, int h, int aw, int ah) {
    final xs = <double>[], ys = <double>[];
    final rx = math.min(aw / 2.0, w / 2.0), ry = math.min(ah / 2.0, h / 2.0);
    final l = x + tx + 0.0, t = y + ty + 0.0, r = l + w, b = t + h;
    void corner(double cx0, double cy0, double a0) {
      for (var i = 0; i <= 8; i++) {
        final a = a0 + (math.pi / 2) * i / 8;
        xs.add(cx0 + math.cos(a) * rx);
        ys.add(cy0 - math.sin(a) * ry);
      }
    }
    corner(r - rx, t + ry, 0);
    corner(l + rx, t + ry, math.pi / 2);
    corner(l + rx, b - ry, math.pi);
    corner(r - rx, b - ry, 3 * math.pi / 2);
    return [xs, ys];
  }

  void fillRoundRect(int x, int y, int w, int h, int aw, int ah) {
    final p = _roundPts(x, y, w, h, aw, ah);
    _fillPoly(p[0], p[1]);
  }

  void drawRoundRect(int x, int y, int w, int h, int aw, int ah) {
    final p = _roundPts(x, y, w, h, aw, ah);
    final n = p[0].length;
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      drawLine((p[0][i] - tx).round(), (p[1][i] - ty).round(), (p[0][j] - tx).round(), (p[1][j] - ty).round());
    }
  }

  // ---- ảnh ----
  /// Vẽ vùng [sx,sy,sw,sh] của [src] tại (dx,dy) với phép biến đổi MIDP (0..7).
  void blit(Surface src, int sx, int sy, int sw, int sh, int trans, int dx, int dy) {
    if (sx < 0 || sy < 0 || sw <= 0 || sh <= 0 || sx + sw > src.w || sy + sh > src.h) return;
    final swap = trans >= 4;
    final dw = swap ? sh : sw, dh = swap ? sw : sh;
    dx += tx;
    dy += ty;
    final x0 = math.max(math.max(dx, cx), 0), y0 = math.max(math.max(dy, cy), 0);
    final x1 = math.min(math.min(dx + dw, cx + cw), s.w), y1 = math.min(math.min(dy + dh, cy + ch), s.h);
    if (x0 >= x1 || y0 >= y1) return;
    final sp = src.px, dp = s.px;
    for (var y = y0; y < y1; y++) {
      final j = y - dy;
      for (var x = x0; x < x1; x++) {
        final i = x - dx;
        int u, v;
        switch (trans) {
          case 0: u = i; v = j; break;
          case 1: u = i; v = sh - 1 - j; break;
          case 2: u = sw - 1 - i; v = j; break;
          case 3: u = sw - 1 - i; v = sh - 1 - j; break;
          case 4: u = j; v = i; break;
          case 5: u = j; v = sh - 1 - i; break;
          case 6: u = sw - 1 - j; v = i; break;
          default: u = sw - 1 - j; v = sh - 1 - i; break;
        }
        final c = sp[(sy + v) * src.w + sx + u];
        final a = c >>> 24;
        if (a == 255) {
          dp[y * s.w + x] = c;
        } else if (a != 0) {
          dp[y * s.w + x] = blend(dp[y * s.w + x], c);
        }
      }
    }
  }

  static (int, int) anchorXY(int x, int y, int w, int h, int anchor) {
    var ax = x, ay = y;
    if ((anchor & 1) != 0) ax = x - w ~/ 2;
    else if ((anchor & 8) != 0) ax = x - w;
    if ((anchor & 2) != 0) ay = y - h ~/ 2;
    else if ((anchor & 32) != 0) ay = y - h;
    return (ax, ay);
  }

  // ---- chữ ----
  void drawText(GlyphSet gs, String text, int x, int y, int anchor) {
    var w = 0;
    for (final c in text.codeUnits) {
      w += gs.adv(c);
    }
    var ax = x, ay = y;
    if ((anchor & 1) != 0) ax = x - w ~/ 2;
    else if ((anchor & 8) != 0) ax = x - w;
    if ((anchor & 64) != 0) {
      ay = y - gs.ascent;
    } else if ((anchor & 32) != 0) {
      ay = y - gs.height;
    }
    ax += tx;
    ay += ty;
    final base = color & 0x00FFFFFF, ca = color >>> 24;
    for (final c in text.codeUnits) {
      final g = gs.glyphs[c];
      if (g != null) {
        for (var j = 0; j < g.h; j++) {
          for (var i = 0; i < g.w; i++) {
            final a = g.alpha[j * g.w + i];
            if (a != 0) {
              _put(ax + g.ox + i, ay + g.oy + j, (((a * ca) ~/ 255) << 24) | base);
            }
          }
        }
        ax += g.adv;
      } else {
        ax += gs.adv(c);
      }
    }
  }
}
