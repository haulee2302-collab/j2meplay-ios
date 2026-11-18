import 'package:flutter/material.dart';

/// Bộ icon dùng chung với bản Android (cùng đường vẽ 24x24 của JpIcons).
class JpIconData {
  final List<String> strokes; // vẽ nét
  final List<String> fills; // tô đặc
  final double width;
  const JpIconData({this.strokes = const [], this.fills = const [], this.width = 2});
}

class JpIcons {
  static const mail = JpIconData(fills: ['M20,4H4c-1.1,0 -1.99,0.9 -1.99,2L2,18c0,1.1 0.9,2 2,2h16c1.1,0 2,-0.9 2,-2V6c0,-1.1 -0.9,-2 -2,-2zM20,8l-8,5 -8,-5V6l8,5 8,-5v2z']);
  static const lock = JpIconData(fills: ['M18,8h-1V6c0,-2.76 -2.24,-5 -5,-5S7,3.24 7,6v2H6c-1.1,0 -2,0.9 -2,2v10c0,1.1 0.9,2 2,2h12c1.1,0 2,-0.9 2,-2V10c0,-1.1 -0.9,-2 -2,-2zM12,17c-1.1,0 -2,-0.9 -2,-2s0.9,-2 2,-2 2,0.9 2,2 -0.9,2 -2,2zM15.1,8H8.9V6c0,-1.71 1.39,-3.1 3.1,-3.1 1.71,0 3.1,1.39 3.1,3.1v2z']);
  static const eye = JpIconData(fills: ['M12,4.5C7,4.5 2.73,7.61 1,12c1.73,4.39 6,7.5 11,7.5s9.27,-3.11 11,-7.5c-1.73,-4.39 -6,-7.5 -11,-7.5zM12,17c-2.76,0 -5,-2.24 -5,-5s2.24,-5 5,-5 5,2.24 5,5 -2.24,5 -5,5zM12,9c-1.66,0 -3,1.34 -3,3s1.34,3 3,3 3,-1.34 3,-3 -1.34,-3 -3,-3z']);
  static const refresh = JpIconData(fills: ['M17.65,6.35C16.2,4.9 14.21,4 12,4c-4.42,0 -7.99,3.58 -7.99,8s3.57,8 7.99,8c3.73,0 6.84,-2.55 7.73,-6h-2.08c-0.82,2.33 -3.04,4 -5.65,4 -3.31,0 -6,-2.69 -6,-6s2.69,-6 6,-6c1.66,0 3.14,0.69 4.22,1.78L13,11h7V4l-2.35,2.35z']);
  static const back = JpIconData(fills: ['M20,11H7.83l5.59,-5.59L12,4l-8,8 8,8 1.41,-1.41L7.83,13H20v-2z']);
  static const play = JpIconData(fills: ['M8,5v14l11,-7z']);
  static const add = JpIconData(fills: ['M19,13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z']);
  static const remove = JpIconData(fills: ['M19,13H5v-2h14v2z']);
  static const power = JpIconData(fills: ['M13,3h-2v10h2V3zM17.83,5.17l-1.42,1.42C17.99,7.86 19,9.81 19,12c0,3.87 -3.13,7 -7,7s-7,-3.13 -7,-7c0,-2.19 1.01,-4.14 2.58,-5.42L6.17,5.17C4.23,6.82 3,9.26 3,12c0,4.97 4.03,9 9,9s9,-4.03 9,-9c0,-2.74 -1.23,-5.18 -3.17,-6.83z']);
  static const logout = JpIconData(fills: ['M17,7l-1.41,1.41L18.17,11H8v2h10.17l-2.58,2.58L17,17l5,-5zM4,5h8V3H4c-1.1,0 -2,0.9 -2,2v14c0,1.1 0.9,2 2,2h8v-2H4V5z']);
  static const gamepad = JpIconData(fills: ['M21,6H3c-1.1,0 -2,0.9 -2,2v8c0,1.1 0.9,2 2,2h18c1.1,0 2,-0.9 2,-2V8c0,-1.1 -0.9,-2 -2,-2zM11,13H8v3H6v-3H3v-2h3V8h2v3h3v2zM15.5,15c-0.83,0 -1.5,-0.67 -1.5,-1.5s0.67,-1.5 1.5,-1.5 1.5,0.67 1.5,1.5 -0.67,1.5 -1.5,1.5zM19.5,12c-0.83,0 -1.5,-0.67 -1.5,-1.5S18.67,9 19.5,9s1.5,0.67 1.5,1.5 -0.67,1.5 -1.5,1.5z']);
  static const clock = JpIconData(fills: ['M11.99,2C6.47,2 2,6.48 2,12s4.47,10 9.99,10C17.52,22 22,17.52 22,12S17.52,2 11.99,2zM12,20c-4.42,0 -8,-3.58 -8,-8s3.58,-8 8,-8 8,3.58 8,8 -3.58,8 -8,8zM12.5,7H11v6l5.25,3.15 0.75,-1.23 -4.5,-2.67z']);
  static const wallet = JpIconData(fills: ['M21,18v1c0,1.1 -0.9,2 -2,2H5c-1.11,0 -2,-0.9 -2,-2V5c0,-1.1 0.89,-2 2,-2h14c1.1,0 2,0.9 2,2v1h-9c-1.11,0 -2,0.9 -2,2v8c0,1.1 0.89,2 2,2h9zM12,16h10V8H12v8zM16,13.5c-0.83,0 -1.5,-0.67 -1.5,-1.5s0.67,-1.5 1.5,-1.5 1.5,0.67 1.5,1.5 -0.67,1.5 -1.5,1.5z']);
  static const more = JpIconData(fills: ['M12,8c1.1,0 2,-0.9 2,-2s-0.9,-2 -2,-2 -2,0.9 -2,2 0.9,2 2,2zM12,10c-1.1,0 -2,0.9 -2,2s0.9,2 2,2 2,-0.9 2,-2 -0.9,-2 -2,-2zM12,16c-1.1,0 -2,0.9 -2,2s0.9,2 2,2 2,-0.9 2,-2 -0.9,-2 -2,-2z']);
  static const edit = JpIconData(fills: ['M3,17.25V21h3.75L17.81,9.94l-3.75,-3.75L3,17.25zM20.71,7.04c0.39,-0.39 0.39,-1.02 0,-1.41l-2.34,-2.34c-0.39,-0.39 -1.02,-0.39 -1.41,0l-1.83,1.83 3.75,3.75 1.83,-1.83z']);
  static const screen = JpIconData(fills: ['M17,1.01L7,1c-1.1,0 -2,0.9 -2,2v18c0,1.1 0.9,2 2,2h10c1.1,0 2,-0.9 2,-2V3c0,-1.1 -0.9,-1.99 -2,-1.99zM17,19H7V5h10v14z']);
  static const globe = JpIconData(fills: ['M12,2C6.48,2 2,6.48 2,12s4.48,10 10,10 10,-4.48 10,-10S17.52,2 12,2zM11,19.93c-3.95,-0.49 -7,-3.85 -7,-7.93 0,-0.62 0.08,-1.21 0.21,-1.79L9,15v1c0,1.1 0.9,2 2,2v1.93zM17.9,17.39c-0.26,-0.81 -1,-1.39 -1.9,-1.39h-1v-3c0,-0.55 -0.45,-1 -1,-1H8v-2h2c0.55,0 1,-0.45 1,-1V7h2c1.1,0 2,-0.9 2,-2v-0.41c2.93,1.19 5,4.06 5,7.41 0,2.08 -0.8,3.97 -2.1,5.39z']);
  static const tune = JpIconData(fills: ['M3,17v2h6v-2H3zM3,5v2h10V5H3zM13,21v-2h8v-2h-8v-2h-2v6h2zM7,9v2H3v2h4v2h2V9H7zM21,13v-2H11v2h10zM15,9h2V7h4V5h-4V3h-2v6z']);
  static const softKey = JpIconData(strokes: ['M6,9h12', 'M6,15h12'], width: 2.6);
  static const chevronUp = JpIconData(strokes: ['M6,15l6,-6l6,6'], width: 2.4);
  static const chevronDown = JpIconData(strokes: ['M6,9l6,6l6,-6'], width: 2.4);
  static const chevronLeft = JpIconData(strokes: ['M15,6l-6,6l6,6'], width: 2.4);
  static const chevronRight = JpIconData(strokes: ['M9,6l6,6l-6,6'], width: 2.4);
  static const swap = JpIconData(strokes: ['M7,4L3,8l4,4', 'M3,8h14', 'M17,20l4,-4l-4,-4', 'M21,16H7'], width: 2.4);
  static const undo = JpIconData(strokes: ['M9,14L4,9l5,-5', 'M4,9h10.5a5.5,5.5 0,0 1,0 11H11'], width: 2.4);
  static const erase = JpIconData(strokes: ['M10,5a2,2 0,0 0,-1.344 0.519l-6.328,5.74a1,1 0,0 0,0 1.481l6.328,5.741A2,2 0,0 0,10 19h10a2,2 0,0 0,2 -2V7a2,2 0,0 0,-2 -2z', 'M12,9l6,6', 'M18,9l-6,6'], width: 2.4);
  static const trash = JpIconData(fills: ['M6,19c0,1.1 0.9,2 2,2h8c1.1,0 2,-0.9 2,-2V7H6v12zM19,4h-3.5l-1,-1h-5l-1,1H5v2h14V4z']);
  static const syncIcon = JpIconData(fills: ['M12,4V1L8,5l4,4V6c3.31,0 6,2.69 6,6 0,1.01 -0.25,1.97 -0.7,2.8l1.46,1.46C19.54,15.03 20,13.57 20,12c0,-4.42 -3.58,-8 -8,-8zM12,18c-3.31,0 -6,-2.69 -6,-6 0,-1.01 0.25,-1.97 0.7,-2.8L5.24,7.74C4.46,8.97 4,10.43 4,12c0,4.42 3.58,8 8,8v3l4,-4 -4,-4v3z']);
  static const toolReload = JpIconData(strokes: ['M20,11a8,8 0 1,0 -2.34,5.66', 'M20,4v7h-7']);
  static const toolRestart = JpIconData(strokes: ['M12,3v8', 'M6.4,6.4a8,8 0 1,0 11.2,0']);
  static const toolJar = JpIconData(strokes: ['M14,3H7a2,2 0 0,0 -2,2v14a2,2 0 0,0 2,2h10a2,2 0 0,0 2,-2V8z', 'M14,3v5h5', 'M9,13h6', 'M9,17h4']);
  static const toolProxy = JpIconData(strokes: ['M12,3l7,3v5c0,4.6 -2.8,8 -7,10c-4.2,-2 -7,-5.4 -7,-10V6z', 'M9,12l2,2l4,-4']);
  static const toolKeyboard = JpIconData(strokes: ['M4,6h16a2,2 0 0,1 2,2v8a2,2 0 0,1 -2,2H4a2,2 0 0,1 -2,-2V8a2,2 0 0,1 2,-2z', 'M6,10h0.01', 'M10,10h0.01', 'M14,10h0.01', 'M18,10h0.01', 'M8,14h8']);
  static const toolDpad = JpIconData(strokes: ['M9,4h6v6H9z', 'M12,8V6', 'M10.5,7.5L12,6l1.5,1.5', 'M2,12h6v6H2z', 'M6,15H4', 'M5.5,13.5L4,15l1.5,1.5', 'M9,12h6v6H9z', 'M12,14v2', 'M10.5,14.5L12,16l1.5,-1.5', 'M16,12h6v6h-6z', 'M18,15h2', 'M18.5,13.5L20,15l-1.5,1.5'], width: 1.45);
  static const toolGlobe = JpIconData(strokes: ['M12,3a9,9 0 1,0 0.01,0z', 'M3,12h18', 'M12,3c2.5,2.5 3.8,5.5 3.8,9s-1.3,6.5 -3.8,9', 'M12,3c-2.5,2.5 -3.8,5.5 -3.8,9s1.3,6.5 3.8,9']);
  static const toolExpand = JpIconData(strokes: ['M9,3H3v6', 'M15,21h6v-6', 'M3,3l7,7', 'M21,21l-7,-7'], width: 2.2);
  static const zoomIn = JpIconData(strokes: ['M10.5,4a6.5,6.5 0 1,0 0,13a6.5,6.5 0 1,0 0,-13z', 'M15.2,15.2L21,21', 'M10.5,7.5v6', 'M7.5,10.5h6']);
  static const zoomOut = JpIconData(strokes: ['M10.5,4a6.5,6.5 0 1,0 0,13a6.5,6.5 0 1,0 0,-13z', 'M15.2,15.2L21,21', 'M7.5,10.5h6']);
  static const navRentals = JpIconData(strokes: ['M4,5h16a1,1 0 0,1 1,1v10a1,1 0 0,1 -1,1H4a1,1 0 0,1 -1,-1V6a1,1 0 0,1 1,-1z', 'M8,21h8', 'M12,17v4']);
  static const navUser = JpIconData(strokes: ['M12,12a4,4 0 1,0 0,-8a4,4 0 1,0 0,8z', 'M4,21c0,-4 3.6,-6.5 8,-6.5s8,2.5 8,6.5']);
  static const navContact = JpIconData(strokes: ['M21,12a8,8 0 0,1 -11.8,7l-5.2,1.5l1.5,-4.8A8,8 0 1,1 21,12z', 'M8.5,12h0.01', 'M12,12h0.01', 'M15.5,12h0.01']);
  static const navPhone = JpIconData(strokes: ['M22,16.9v3a2,2 0 0,1 -2.2,2a19.8,19.8 0 0,1 -8.6,-3.1a19.5,19.5 0 0,1 -6,-6a19.8,19.8 0 0,1 -3.1,-8.7A2,2 0 0,1 4.1,2h3a2,2 0 0,1 2,1.7c0.1,1 0.4,1.9 0.7,2.8a2,2 0 0,1 -0.5,2.1L8,9.9a16,16 0 0,0 6,6l1.3,-1.3a2,2 0 0,1 2.1,-0.4c0.9,0.3 1.8,0.6 2.8,0.7a2,2 0 0,1 1.7,2z'], width: 1.8);
  static const navUpload = JpIconData(strokes: ['M12,16V4', 'M7,9l5,-5l5,5', 'M4,20h16']);
  static const navDollar = JpIconData(strokes: ['M12,3v18', 'M16.5,7.5c-0.6,-1.5 -2.4,-2.5 -4.5,-2.5c-2.5,0 -4.5,1.5 -4.5,3.5s2,3 4.5,3.5s4.5,1.5 4.5,3.5s-2,3.5 -4.5,3.5c-2.1,0 -3.9,-1 -4.5,-2.5'], width: 2.4);
  static const copy = JpIconData(strokes: ['M9,9h10a1,1 0 0,1 1,1v10a1,1 0 0,1 -1,1H9a1,1 0 0,1 -1,-1V10a1,1 0 0,1 1,-1z', 'M5,15H4a1,1 0 0,1 -1,-1V4a1,1 0 0,1 1,-1h10a1,1 0 0,1 1,1v1']);
  static const navHome = JpIconData(strokes: ['M3,10.5l9,-7l9,7', 'M5,9v10a1,1 0 0,0 1,1h4v-6h4v6h4a1,1 0 0,0 1,-1V9']);
  static const moon = JpIconData(strokes: ['M21,12.8A9,9 0 1,1 11.2,3a7,7 0 0,0 9.8,9.8z']);
  static const sun = JpIconData(strokes: ['M12,16a4,4 0 1,0 0,-8a4,4 0 1,0 0,8z', 'M12,2v2', 'M12,20v2', 'M4.9,4.9l1.4,1.4', 'M17.7,17.7l1.4,1.4', 'M2,12h2', 'M20,12h2', 'M4.9,19.1l1.4,-1.4', 'M17.7,6.3l1.4,-1.4']);
  static const toggleOn = JpIconData(strokes: ['M8,6h8a6,6 0 0,1 0,12H8a6,6 0 0,1 0,-12z', 'M16,15a3,3 0 1,0 0,-6a3,3 0 1,0 0,6z']);
  static const toggleOff = JpIconData(strokes: ['M8,6h8a6,6 0 0,1 0,12H8a6,6 0 0,1 0,-12z', 'M8,15a3,3 0 1,0 0,-6a3,3 0 1,0 0,6z']);
  static const restart2 = JpIconData(strokes: ['M20,12a8,8 0 0,0 -14,-5.3', 'M6,3v4h4', 'M4,12a8,8 0 0,0 14,5.3', 'M18,21v-4h-4']);
  static const check = JpIconData(fills: ['M9,16.17L4.83,12l-1.42,1.41L9,19 21,7l-1.41,-1.41z']);
  // Bổ sung riêng cho iOS (cùng phong cách nét)
  static const dragHandle = JpIconData(strokes: ['M5,9h14', 'M5,15h14']);
  static const boxOff = JpIconData(strokes: ['M5,3h14a2,2 0 0,1 2,2v14a2,2 0 0,1 -2,2H5a2,2 0 0,1 -2,-2V5a2,2 0 0,1 2,-2z']);
  static const boxOn = JpIconData(fills: ['M5,3h14a2,2 0 0,1 2,2v14a2,2 0 0,1 -2,2H5a2,2 0 0,1 -2,-2V5a2,2 0 0,1 2,-2z'], strokes: ['M8,12l3,3l5,-6'], width: 2.6);
  static const radioOff = JpIconData(strokes: ['M12,3a9,9 0 1,0 0.01,0z']);
  static const radioOn = JpIconData(strokes: ['M12,3a9,9 0 1,0 0.01,0z'], fills: ['M12,7.5a4.5,4.5 0 1,0 0.01,0z']);
}

class JpIcon extends StatelessWidget {
  final JpIconData data;
  final double size;
  final Color? color;
  const JpIcon(this.data, {super.key, this.size = 24, this.color});
  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.black;
    return UnconstrainedBox(child: SizedBox(width: size, height: size, child: CustomPaint(painter: _IconPainter(data, c))));
  }
}

class _IconPainter extends CustomPainter {
  final JpIconData d;
  final Color color;
  _IconPainter(this.d, this.color);
  @override
  void paint(Canvas canvas, Size s) {
    canvas.scale(s.width / 24, s.height / 24);
    for (final p in d.fills) {
      canvas.drawPath(parseSvgPath(p)..fillType = PathFillType.evenOdd, Paint()..color = color..style = PaintingStyle.fill..isAntiAlias = true);
    }
    final sp = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = d.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    for (final p in d.strokes) {
      canvas.drawPath(parseSvgPath(p), sp);
    }
  }

  @override
  bool shouldRepaint(_IconPainter o) => o.d != d || o.color != color;
}

final _pathCache = <String, Path>{};

/// Bộ phân tích path SVG: M L H V C S A Z (hoa/thường).
Path parseSvgPath(String d) {
  final cached = _pathCache[d];
  if (cached != null) return Path.from(cached);
  final path = Path();
  final t = RegExp(r'[a-zA-Z]|-?(?:\d+\.?\d*|\.\d+)').allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0;
  double x = 0, y = 0, sx = 0, sy = 0, lcx = 0, lcy = 0;
  var cmd = 'M';
  var lastC = false;
  double n() => double.parse(t[i++]);
  bool isCmd(String s) => RegExp(r'^[a-zA-Z]$').hasMatch(s);
  while (i < t.length) {
    if (isCmd(t[i])) cmd = t[i++];
    final rel = cmd == cmd.toLowerCase();
    final c = cmd.toLowerCase();
    var wasC = false;
    switch (c) {
      case 'm': { final a = n(), b = n(); x = rel ? x + a : a; y = rel ? y + b : b; sx = x; sy = y; path.moveTo(x, y); cmd = rel ? 'l' : 'L'; break; }
      case 'l': { final a = n(), b = n(); x = rel ? x + a : a; y = rel ? y + b : b; path.lineTo(x, y); break; }
      case 'h': { final a = n(); x = rel ? x + a : a; path.lineTo(x, y); break; }
      case 'v': { final a = n(); y = rel ? y + a : a; path.lineTo(x, y); break; }
      case 'c': {
        final v = List.generate(6, (_) => n());
        final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
        path.cubicTo(ox + v[0], oy + v[1], ox + v[2], oy + v[3], ox + v[4], oy + v[5]);
        lcx = ox + v[2]; lcy = oy + v[3]; x = ox + v[4]; y = oy + v[5]; wasC = true;
        break;
      }
      case 's': {
        final v = List.generate(4, (_) => n());
        final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
        final c1x = lastC ? 2 * x - lcx : x, c1y = lastC ? 2 * y - lcy : y;
        path.cubicTo(c1x, c1y, ox + v[0], oy + v[1], ox + v[2], oy + v[3]);
        lcx = ox + v[0]; lcy = oy + v[1]; x = ox + v[2]; y = oy + v[3]; wasC = true;
        break;
      }
      case 'a': {
        final rx = n(), ry = n(); n();
        final large = n() != 0, sweep = n() != 0;
        final a = n(), b = n();
        final nx = rel ? x + a : a, ny = rel ? y + b : b;
        path.arcToPoint(Offset(nx, ny), radius: Radius.elliptical(rx, ry), largeArc: large, clockwise: sweep);
        x = nx; y = ny;
        break;
      }
      case 'z': path.close(); x = sx; y = sy; break;
      default: i++;
    }
    lastC = wasC;
  }
  _pathCache[d] = Path.from(path);
  return path;
}
