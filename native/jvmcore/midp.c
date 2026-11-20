// MIDP 2.0 (javax.microedition.*) viết bằng C: MIDlet, Display, Canvas, GameCanvas, Graphics, Image, Font, Command, RecordStore.
// Màn hình được phát ra theo giao thức JPC1 (cùng định dạng phiên thuê) để JpcRenderer phía Dart vẽ lại; ảnh phụ (Image) vẽ bằng C.
#include "jvm.h"
#include <pthread.h>
#include <sys/stat.h>

#define NS(cls, name, desc, fn) regNative(cls, name, desc, 1, fn)
#define NI(cls, name, desc, fn) regNative(cls, name, desc, 0, fn)
#define OBJ(i) ((Obj *)a[i].a)
#define ARR(i) ((Arr *)a[i].a)

uint32_t *pngDecode(const uint8_t *d, size_t n, int *ow, int *oh);
uint8_t *loadResource(const char *name, int *len);
Obj *newBytesStream(const uint8_t *d, int n);

#define LCD "javax/microedition/lcdui/"
#define MID "javax/microedition/midlet/MIDlet"

int g_sw = 240, g_sh = 320;
void (*g_frameSink)(const uint8_t *data, int len, int key);
const char *g_rmsDir = ".";
int g_destroyed;
int g_frames;

typedef struct { int w, h; uint32_t *px; } Surf; // ARGB
static Surf *surfNew(int w, int h, uint32_t fill) {
  Surf *s = malloc(sizeof *s); s->w = w; s->h = h; s->px = malloc((size_t)(w > 0 ? w : 1) * (h > 0 ? h : 1) * 4);
  for (size_t i = 0; i < (size_t)w * h; i++) s->px[i] = fill; return s;
}

static void cstr(Obj *s, char *out, int max) {
  int n = 0; if (s) for (int i = 0; i < S_LEN(s) && n < max - 1; i++) { uint16_t c = S_CH(s)[i]; out[n++] = c < 128 ? (char)c : '_'; } out[n] = 0;
}
static void utf8(Obj *s, int from, int n, uint8_t **out, int *len) {
  uint8_t *b = malloc(n * 3 + 1); int k = 0;
  for (int i = from; i < from + n; i++) { uint16_t c = S_CH(s)[i]; if (c < 0x80) b[k++] = c; else if (c < 0x800) { b[k++] = 0xC0 | (c >> 6); b[k++] = 0x80 | (c & 63); } else { b[k++] = 0xE0 | (c >> 12); b[k++] = 0x80 | ((c >> 6) & 63); b[k++] = 0x80 | (c & 63); } }
  *out = b; *len = k;
}

// ---------------- JPC1 ----------------
static uint8_t *fb; static int fl, fcap; static int frameOpen, epoch = 1, needKey = 1, frameKey;
static uint32_t lCol; static int lcl, lct, lcr, lcb, lst;
static void pb(int v) { if (fl + 1 > fcap) { fcap = fcap * 2 + 4096; fb = realloc(fb, fcap); } fb[fl++] = (uint8_t)v; }
static void p16(int v) { pb(v >> 8); pb(v); }
static void p32(uint32_t v) { pb(v >> 24); pb(v >> 16); pb(v >> 8); pb(v); }
static int cl16(int v) { return v < -32768 ? -32768 : v > 32767 ? 32767 : v; }
static void frameBegin(void) {
  fl = 0; p32(0x4a504331); pb(3); frameKey = needKey; if (needKey) epoch++; pb(needKey ? 1 : 0); needKey = 0; p16(g_sw); p16(g_sh);
  lCol = 0; lcl = 0; lct = 0; lcr = g_sw; lcb = g_sh; lst = 0; frameOpen = 1;
}
static void frameEnd(void) {
  if (!frameOpen) return; frameOpen = 0; g_frames++;
  if (g_frameSink) g_frameSink(fb, fl, frameKey);
}

// ---------------- Font ----------------
static int fpx(Obj *f) { int sz = f ? f->f[2].i : 0; return sz == 8 ? 9 : sz == 16 ? 15 : 12; }
static int fheight(Obj *f) { return (fpx(f) * 12 + 5) / 10; }
static int fadv(Obj *f) { return (fheight(f) * 55 + 50) / 100; }
static Class *fontCls, *imgCls, *gfxCls, *cmdCls, *dispCls, *canvasCls, *rsCls;
static Obj *newFont(int face, int style, int size) { Obj *o = newObj(fontCls ? fontCls : (fontCls = loadClass(LCD "Font"))); o->f[0].i = face; o->f[1].i = style; o->f[2].i = size; return o; }
static Obj *defFont;
static void fn_getFont(Slot *a) { a[0].a = newFont(a[0].i, a[1].i, a[2].i); }
static void fn_defFont(Slot *a) { a[0].a = newFont(0, 0, 0); }
static void fn_fHeight(Slot *a) { a[0].i = fheight(OBJ(0)); }
static void fn_fBase(Slot *a) { a[0].i = fpx(OBJ(0)); }
static void fn_fStyle(Slot *a) { a[0].i = OBJ(0)->f[1].i; }
static void fn_fSize(Slot *a) { a[0].i = OBJ(0)->f[2].i; }
static void fn_fFace(Slot *a) { a[0].i = OBJ(0)->f[0].i; }
static void fn_fBold(Slot *a) { a[0].i = OBJ(0)->f[1].i & 1; }
static void fn_fItalic(Slot *a) { a[0].i = (OBJ(0)->f[1].i & 2) != 0; }
static void fn_fPlain(Slot *a) { a[0].i = OBJ(0)->f[1].i == 0; }
static void fn_fSW(Slot *a) { Obj *s = OBJ(1); if (!s) { throwNew("java/lang/NullPointerException", 0); return; } a[0].i = S_LEN(s) * fadv(OBJ(0)); }
static void fn_fCW(Slot *a) { a[0].i = fadv(OBJ(0)); }
static void fn_fSubW(Slot *a) { a[0].i = a[3].i * fadv(OBJ(0)); }
static void fn_fCharsW(Slot *a) { a[0].i = a[3].i * fadv(OBJ(0)); }

// ---------------- Image ----------------
static int g_resId = 1;
static Obj *newGraphics(Surf *target, int w, int h, Obj *img);
static Obj *newImage(Surf *s, int mutable) {
  Obj *o = newObj(imgCls ? imgCls : (imgCls = loadClass(LCD "Image")));
  o->f[0].a = s; o->f[1].i = mutable; o->f[2].i = g_resId++; o->f[3].i = -1; o->f[4].i = 1; o->f[5].i = 0; return o;
}
static Surf *sOf(Obj *img) { return img->f[0].a; }
static void fn_imgCreateWH(Slot *a) { int w = a[0].i, h = a[1].i; if (w <= 0 || h <= 0) { throwNew("java/lang/IllegalArgumentException", 0); return; } a[0].a = newImage(surfNew(w, h, 0xFFFFFFFF), 1); }
static Obj *imgFromBytes(const uint8_t *d, int n) {
  int w, h; uint32_t *px = pngDecode(d, n, &w, &h);
  if (!px) { throwNew("java/io/IOException", "ảnh không phải PNG hỗ trợ"); return 0; }
  Surf *s = malloc(sizeof *s); s->w = w; s->h = h; s->px = px; return newImage(s, 0);
}
static void fn_imgCreateB(Slot *a) { Arr *b = ARR(0); int off = a[1].i, n = a[2].i; if (!b || off < 0 || n < 0 || off + n > b->len) { throwNew("java/lang/ArrayIndexOutOfBoundsException", 0); return; } a[0].a = imgFromBytes(b->d + off, n); }
static void fn_imgCreateS(Slot *a) {
  char nm[400]; cstr(OBJ(0), nm, sizeof nm); int len; uint8_t *d = loadResource(nm, &len);
  if (!d) { throwNew("java/io/IOException", nm); return; }
  Obj *o = imgFromBytes(d, len); free(d); a[0].a = o;
}
static void fn_imgCreateIS(Slot *a) {
  Obj *in = OBJ(0); if (!in) { throwNew("java/lang/NullPointerException", 0); return; }
  if (strcmp(in->cls->name, "java/io/ByteArrayInputStream") == 0) { Arr *b = in->f[0].a; int pos = in->f[1].i, cnt = in->f[2].i; a[0].a = imgFromBytes(b->d + pos, cnt - pos); in->f[1].i = cnt; return; }
  throwNew("java/io/IOException", "InputStream chưa hỗ trợ"); }
static void fn_imgCreateCopy(Slot *a) { Surf *s = sOf(OBJ(0)); Surf *c = surfNew(s->w, s->h, 0); memcpy(c->px, s->px, (size_t)s->w * s->h * 4); a[0].a = newImage(c, 0); }
static void fn_imgCreateRGB(Slot *a) {
  Arr *p = ARR(0); int w = a[1].i, h = a[2].i, alpha = a[3].i; if (!p || w <= 0 || h <= 0 || (int64_t)w * h > p->len) { throwNew("java/lang/IllegalArgumentException", 0); return; }
  Surf *s = surfNew(w, h, 0); for (int i = 0; i < w * h; i++) { uint32_t v = ((uint32_t *)p->d)[i]; s->px[i] = alpha ? v : (v | 0xFF000000); }
  a[0].a = newImage(s, 0);
}
static void fn_imgGetGraphics(Slot *a) { Obj *im = OBJ(0); if (!im->f[1].i) { throwNew("java/lang/IllegalStateException", "Image bất biến"); return; } Surf *s = sOf(im); a[0].a = newGraphics(s, s->w, s->h, im); }
static void fn_imgW(Slot *a) { a[0].i = sOf(OBJ(0))->w; }
static void fn_imgH(Slot *a) { a[0].i = sOf(OBJ(0))->h; }
static void fn_imgMut(Slot *a) { a[0].i = OBJ(0)->f[1].i; }
static void fn_imgGetRGB(Slot *a) {
  Surf *s = sOf(OBJ(0)); Arr *o = ARR(1); int off = a[2].i, sc = a[3].i, x = a[4].i, y = a[5].i, w = a[6].i, h = a[7].i;
  if (!o) { throwNew("java/lang/NullPointerException", 0); return; }
  if (x < 0 || y < 0 || x + w > s->w || y + h > s->h || w < 0 || h < 0) { throwNew("java/lang/IllegalArgumentException", 0); return; }
  for (int j = 0; j < h; j++) for (int i = 0; i < w; i++) { int di = off + j * sc + i; if (di < 0 || di >= o->len) { throwNew("java/lang/ArrayIndexOutOfBoundsException", 0); return; } ((uint32_t *)o->d)[di] = s->px[(y + j) * s->w + x + i]; }
}

// ---------------- Graphics ----------------
enum { G_T, G_COL, G_TX, G_TY, G_CX, G_CY, G_CW, G_CH, G_STROKE, G_FONT, G_IMG };
static Obj *newGraphics(Surf *target, int w, int h, Obj *img) {
  Obj *g = newObj(gfxCls ? gfxCls : (gfxCls = loadClass(LCD "Graphics")));
  g->f[G_T].a = target; g->f[G_COL].i = 0; g->f[G_TX].i = 0; g->f[G_TY].i = 0; g->f[G_CX].i = 0; g->f[G_CY].i = 0; g->f[G_CW].i = w; g->f[G_CH].i = h; g->f[G_STROKE].i = 0; g->f[G_FONT].a = 0; g->f[G_IMG].a = img; return g;
}
static void gReset(Obj *g, int w, int h) { g->f[G_COL].i = 0; g->f[G_TX].i = 0; g->f[G_TY].i = 0; g->f[G_CX].i = 0; g->f[G_CY].i = 0; g->f[G_CW].i = w; g->f[G_CH].i = h; g->f[G_STROKE].i = 0; g->f[G_FONT].a = 0; }
static Surf *gT(Obj *g) { return g->f[G_T].a; }
static void frameBegin(void);
static Obj *g_gcG;
static int gOn(Obj *g) { if (gT(g)) return 1; if (!frameOpen && g == g_gcG) frameBegin(); return frameOpen; }

static void syncState(Obj *g) {
  int cl = g->f[G_CX].i, ct = g->f[G_CY].i, cr = cl + g->f[G_CW].i, cb = ct + g->f[G_CH].i; uint32_t col = (uint32_t)g->f[G_COL].i & 0xFFFFFF; int st = g->f[G_STROKE].i;
  if (cr < cl) cr = cl; if (cb < ct) cb = ct;
  if (col == lCol && cl == lcl && ct == lct && cr == lcr && cb == lcb && st == lst) return;
  pb(1); p32(col); p16(cl16(cl)); p16(cl16(ct)); p16(cl16(cr)); p16(cl16(cb)); pb(st);
  lCol = col; lcl = cl; lct = ct; lcr = cr; lcb = cb; lst = st;
}
static void ensureRes(Obj *img) {
  Surf *s = sOf(img);
  if (img->f[3].i == epoch && img->f[5].i == img->f[4].i) return;
  pb(2); p32(img->f[2].i); p32(0); p32(0); p16(s->w); p16(s->h); p32(s->w * s->h * 4);
  for (int i = 0; i < s->w * s->h; i++) { uint32_t c = s->px[i]; pb(c >> 16); pb(c >> 8); pb(c); pb(c >> 24); }
  img->f[3].i = epoch; img->f[5].i = img->f[4].i;
}
static void touch(Obj *g) { Obj *im = g->f[G_IMG].a; if (im) im->f[4].i++; }

// ---- rasteriser cho ảnh phụ ----
static inline uint32_t blendPx(uint32_t d, uint32_t s) {
  uint32_t a = s >> 24; if (a == 255) return s; if (a == 0) return d;
  uint32_t ia = 255 - a, da = d >> 24;
  uint32_t r = (((s >> 16) & 255) * a + ((d >> 16) & 255) * ia) / 255, g = (((s >> 8) & 255) * a + ((d >> 8) & 255) * ia) / 255, b = ((s & 255) * a + (d & 255) * ia) / 255;
  uint32_t na = a + da * ia / 255; return (na << 24) | (r << 16) | (g << 8) | b;
}
static void clipOf(Obj *g, Surf *s, int *l, int *t, int *r, int *b) {
  *l = g->f[G_CX].i; *t = g->f[G_CY].i; *r = *l + g->f[G_CW].i; *b = *t + g->f[G_CH].i;
  if (*l < 0) *l = 0; if (*t < 0) *t = 0; if (*r > s->w) *r = s->w; if (*b > s->h) *b = s->h;
}
static void rFill(Obj *g, int x, int y, int w, int h) {
  Surf *s = gT(g); int l, t, r, b; clipOf(g, s, &l, &t, &r, &b); uint32_t c = 0xFF000000 | (uint32_t)g->f[G_COL].i;
  int x0 = x > l ? x : l, y0 = y > t ? y : t, x1 = x + w < r ? x + w : r, y1 = y + h < b ? y + h : b;
  for (int j = y0; j < y1; j++) for (int i = x0; i < x1; i++) s->px[j * s->w + i] = c;
}
static void rPut(Obj *g, int x, int y) {
  Surf *s = gT(g); int l, t, r, b; clipOf(g, s, &l, &t, &r, &b);
  if (x >= l && x < r && y >= t && y < b) s->px[y * s->w + x] = 0xFF000000 | (uint32_t)g->f[G_COL].i;
}
static void rLine(Obj *g, int x0, int y0, int x1, int y1) {
  int dx = abs(x1 - x0), sx = x0 < x1 ? 1 : -1, dy = -abs(y1 - y0), sy = y0 < y1 ? 1 : -1, err = dx + dy;
  for (;;) { rPut(g, x0, y0); if (x0 == x1 && y0 == y1) break; int e2 = 2 * err; if (e2 >= dy) { err += dy; x0 += sx; } if (e2 <= dx) { err += dx; y0 += sy; } }
}
static void rImage(Obj *g, Surf *src, int sx, int sy, int w, int h, int tr, int dx, int dy) {
  Surf *s = gT(g); int l, t, r, b; clipOf(g, s, &l, &t, &r, &b);
  for (int j = 0; j < h; j++) { int srow = sy + j; if (srow < 0 || srow >= src->h) continue;
    for (int i = 0; i < w; i++) { int scol = sx + i; if (scol < 0 || scol >= src->w) continue;
      int ox, oy;
      switch (tr) { case 1: ox = i; oy = h - 1 - j; break; case 2: ox = w - 1 - i; oy = j; break; case 3: ox = w - 1 - i; oy = h - 1 - j; break; case 4: ox = j; oy = i; break; case 5: ox = h - 1 - j; oy = i; break; case 6: ox = j; oy = w - 1 - i; break; case 7: ox = h - 1 - j; oy = w - 1 - i; break; default: ox = i; oy = j; }
      int x = dx + ox, y = dy + oy; if (x < l || x >= r || y < t || y >= b) continue;
      s->px[y * s->w + x] = blendPx(s->px[y * s->w + x], src->px[srow * src->w + scol]); } }
}
static void rArc(Obj *g, int x, int y, int w, int h, int sa, int aa, int fill) {
  if (w <= 0 || h <= 0) return;
  double cx = x + w / 2.0, cy = y + h / 2.0, rx = w / 2.0, ry = h / 2.0;
  for (int py = y; py < y + h; py++) for (int px = x; px < x + w; px++) {
    double dx = (px + 0.5 - cx) / rx, dy = (cy - (py + 0.5)) / ry, r2 = dx * dx + dy * dy;
    int in = fill ? r2 <= 1.0 : (r2 <= 1.0 && r2 >= 1.0 - 2.0 / (rx < ry ? rx : ry));
    if (!in) continue;
    if (aa < 360 && aa > -360) { double ang = atan2(dy, dx) * 180.0 / M_PI; if (ang < 0) ang += 360; double rel = aa >= 0 ? ang - sa : sa - ang; rel = fmod(rel, 360.0); if (rel < 0) rel += 360; if (rel > (aa >= 0 ? aa : -aa)) continue; }
    rPut(g, px, py);
  }
}
static void rTri(Obj *g, int x1, int y1, int x2, int y2, int x3, int y3) {
  int mnx = x1 < x2 ? (x1 < x3 ? x1 : x3) : (x2 < x3 ? x2 : x3), mxx = x1 > x2 ? (x1 > x3 ? x1 : x3) : (x2 > x3 ? x2 : x3);
  int mny = y1 < y2 ? (y1 < y3 ? y1 : y3) : (y2 < y3 ? y2 : y3), mxy = y1 > y2 ? (y1 > y3 ? y1 : y3) : (y2 > y3 ? y2 : y3);
  for (int y = mny; y <= mxy; y++) for (int x = mnx; x <= mxx; x++) {
    long d1 = (long)(x - x2) * (y1 - y2) - (long)(x1 - x2) * (y - y2), d2 = (long)(x - x3) * (y2 - y3) - (long)(x2 - x3) * (y - y3), d3 = (long)(x - x1) * (y3 - y1) - (long)(x3 - x1) * (y - y1);
    int neg = d1 < 0 || d2 < 0 || d3 < 0, pos = d1 > 0 || d2 > 0 || d3 > 0; if (!(neg && pos)) rPut(g, x, y);
  }
}
static int warnedText;

static void anchorXY(int *x, int *y, int w, int h, int an) {
  if (an & 1) *x -= w / 2; else if (an & 8) *x -= w; if (an & 2) *y -= h / 2; else if (an & 32) *y -= h;
}

// ---- natives Graphics ----
static void g_setColor1(Slot *a) { Obj *g = OBJ(0); g->f[G_COL].i = a[1].i & 0xFFFFFF; }
static void g_setColor3(Slot *a) { Obj *g = OBJ(0); g->f[G_COL].i = ((a[1].i & 255) << 16) | ((a[2].i & 255) << 8) | (a[3].i & 255); }
static void g_getColor(Slot *a) { a[0].i = OBJ(0)->f[G_COL].i; }
static void g_setGray(Slot *a) { int v = a[1].i & 255; OBJ(0)->f[G_COL].i = (v << 16) | (v << 8) | v; }
static void g_translate(Slot *a) { Obj *g = OBJ(0); g->f[G_TX].i += a[1].i; g->f[G_TY].i += a[2].i; }
static void g_getTX(Slot *a) { a[0].i = OBJ(0)->f[G_TX].i; }
static void g_getTY(Slot *a) { a[0].i = OBJ(0)->f[G_TY].i; }
static void g_setClip(Slot *a) { Obj *g = OBJ(0); g->f[G_CX].i = a[1].i + g->f[G_TX].i; g->f[G_CY].i = a[2].i + g->f[G_TY].i; g->f[G_CW].i = a[3].i < 0 ? 0 : a[3].i; g->f[G_CH].i = a[4].i < 0 ? 0 : a[4].i; }
static void g_clipRect(Slot *a) {
  Obj *g = OBJ(0); int x0 = g->f[G_CX].i > a[1].i + g->f[G_TX].i ? g->f[G_CX].i : a[1].i + g->f[G_TX].i, y0 = g->f[G_CY].i > a[2].i + g->f[G_TY].i ? g->f[G_CY].i : a[2].i + g->f[G_TY].i;
  int ax = a[1].i + g->f[G_TX].i + a[3].i, ay = a[2].i + g->f[G_TY].i + a[4].i, bx = g->f[G_CX].i + g->f[G_CW].i, by = g->f[G_CY].i + g->f[G_CH].i;
  int x1 = ax < bx ? ax : bx, y1 = ay < by ? ay : by; g->f[G_CX].i = x0; g->f[G_CY].i = y0; g->f[G_CW].i = x1 > x0 ? x1 - x0 : 0; g->f[G_CH].i = y1 > y0 ? y1 - y0 : 0;
}
static void g_getCX(Slot *a) { Obj *g = OBJ(0); a[0].i = g->f[G_CX].i - g->f[G_TX].i; }
static void g_getCY(Slot *a) { Obj *g = OBJ(0); a[0].i = g->f[G_CY].i - g->f[G_TY].i; }
static void g_getCW(Slot *a) { a[0].i = OBJ(0)->f[G_CW].i; }
static void g_getCH(Slot *a) { a[0].i = OBJ(0)->f[G_CH].i; }
static void g_setStroke(Slot *a) { OBJ(0)->f[G_STROKE].i = a[1].i; }
static void g_getStroke(Slot *a) { a[0].i = OBJ(0)->f[G_STROKE].i; }
static void g_setFont(Slot *a) { OBJ(0)->f[G_FONT].a = a[1].a; }
static void g_getFont(Slot *a) { Obj *f = OBJ(0)->f[G_FONT].a; a[0].a = f ? f : (defFont ? defFont : (defFont = newFont(0, 0, 0))); }

static void g_fillRect(Slot *a) {
  Obj *g = OBJ(0); if (!gOn(g)) return; int x = a[1].i + g->f[G_TX].i, y = a[2].i + g->f[G_TY].i, w = a[3].i, h = a[4].i; if (w <= 0 || h <= 0) return;
  if (gT(g)) { rFill(g, x, y, w, h); touch(g); return; }
  syncState(g); pb(10); p16(cl16(x)); p16(cl16(y)); p16(cl16(w)); p16(cl16(h));
}
static void g_drawRect(Slot *a) {
  Obj *g = OBJ(0); if (!gOn(g)) return; int x = a[1].i + g->f[G_TX].i, y = a[2].i + g->f[G_TY].i, w = a[3].i, h = a[4].i; if (w < 0 || h < 0) return;
  if (gT(g)) { rLine(g, x, y, x + w, y); rLine(g, x, y + h, x + w, y + h); rLine(g, x, y, x, y + h); rLine(g, x + w, y, x + w, y + h); touch(g); return; }
  syncState(g); pb(12); p16(cl16(x)); p16(cl16(y)); p16(cl16(w)); p16(cl16(h));
}
static void g_drawLine(Slot *a) {
  Obj *g = OBJ(0); if (!gOn(g)) return; int tx = g->f[G_TX].i, ty = g->f[G_TY].i;
  if (gT(g)) { rLine(g, a[1].i + tx, a[2].i + ty, a[3].i + tx, a[4].i + ty); touch(g); return; }
  syncState(g); pb(11); p16(cl16(a[1].i + tx)); p16(cl16(a[2].i + ty)); p16(cl16(a[3].i + tx)); p16(cl16(a[4].i + ty));
}
static void g_tri(Slot *a) {
  Obj *g = OBJ(0); if (!gOn(g)) return; int tx = g->f[G_TX].i, ty = g->f[G_TY].i;
  if (gT(g)) { rTri(g, a[1].i + tx, a[2].i + ty, a[3].i + tx, a[4].i + ty, a[5].i + tx, a[6].i + ty); touch(g); return; }
  syncState(g); pb(16); for (int i = 0; i < 3; i++) { p16(cl16(a[1 + i * 2].i + tx)); p16(cl16(a[2 + i * 2].i + ty)); }
}
static void arcCommon(Slot *a, int fill) {
  Obj *g = OBJ(0); if (!gOn(g)) return; int x = a[1].i + g->f[G_TX].i, y = a[2].i + g->f[G_TY].i, w = a[3].i, h = a[4].i;
  if (gT(g)) { rArc(g, x, y, w, h, a[5].i, a[6].i, fill); touch(g); return; }
  syncState(g); pb(17); p16(cl16(x)); p16(cl16(y)); p16(cl16(w)); p16(cl16(h)); p32(a[5].i); p32(a[6].i); pb(fill);
}
static void g_drawArc(Slot *a) { arcCommon(a, 0); }
static void g_fillArc(Slot *a) { arcCommon(a, 1); }
static void rrCommon(Slot *a, int fill) {
  Obj *g = OBJ(0); if (!gOn(g)) return; int x = a[1].i + g->f[G_TX].i, y = a[2].i + g->f[G_TY].i, w = a[3].i, h = a[4].i;
  if (gT(g)) { if (fill) rFill(g, x, y, w, h); else { rLine(g, x, y, x + w, y); rLine(g, x, y + h, x + w, y + h); rLine(g, x, y, x, y + h); rLine(g, x + w, y, x + w, y + h); } touch(g); return; }
  syncState(g); pb(18); p16(cl16(x)); p16(cl16(y)); p16(cl16(w)); p16(cl16(h)); p16(cl16(a[5].i)); p16(cl16(a[6].i)); pb(fill);
}
static void g_drawRR(Slot *a) { rrCommon(a, 0); }
static void g_fillRR(Slot *a) { rrCommon(a, 1); }

static void drawStr(Obj *g, Obj *s, int from, int n, int x, int y, int an) {
  if (!gOn(g)) return; if (!s) { throwNew("java/lang/NullPointerException", 0); return; }
  if (from < 0 || n < 0 || from + n > S_LEN(s)) { throwNew("java/lang/StringIndexOutOfBoundsException", 0); return; }
  Obj *f = g->f[G_FONT].a; int h = fheight(f), asc = fpx(f), w = n * fadv(f);
  x += g->f[G_TX].i; y += g->f[G_TY].i;
  if (an & 1) x -= w / 2; else if (an & 8) x -= w;
  int base; if (an & 64) base = y; else if (an & 32) base = y - (h - asc); else base = y + asc;
  if (gT(g)) { if (!warnedText) { warnedText = 1; fprintf(stderr, "[midp] chữ vẽ lên Image chưa hỗ trợ\n"); } return; }
  if (n == 0) return;
  uint8_t *u; int ul; utf8(s, from, n, &u, &ul);
  syncState(g); pb(19); p16(cl16(x)); p16(cl16(base)); pb(f ? f->f[0].i : 0); pb(f ? f->f[1].i : 0); pb(fpx(f)); p32(ul); for (int i = 0; i < ul; i++) pb(u[i]); free(u);
}
static void g_drawString(Slot *a) { Obj *s = OBJ(1); drawStr(OBJ(0), s, 0, s ? S_LEN(s) : 0, a[2].i, a[3].i, a[4].i); }
static void g_drawSubstring(Slot *a) { drawStr(OBJ(0), OBJ(1), a[2].i, a[3].i, a[4].i, a[5].i, a[6].i); }
static void g_drawChar(Slot *a) { uint16_t c = (uint16_t)a[1].i; Obj *s = newStr16(&c, 1); drawStr(OBJ(0), s, 0, 1, a[2].i, a[3].i, a[4].i); }
static void g_drawChars(Slot *a) { Arr *ca = ARR(1); if (!ca) { throwNew("java/lang/NullPointerException", 0); return; } Obj *s = newStr16((uint16_t *)ca->d + a[2].i, a[3].i); drawStr(OBJ(0), s, 0, a[3].i, a[4].i, a[5].i, a[6].i); }

static void drawImg(Obj *g, Obj *img, int sx, int sy, int w, int h, int tr, int x, int y, int an) {
  if (!gOn(g)) return; if (!img) { throwNew("java/lang/NullPointerException", 0); return; }
  Surf *s = sOf(img); if (w <= 0 || h <= 0) return;
  int dw = tr >= 4 ? h : w, dh = tr >= 4 ? w : h; x += g->f[G_TX].i; y += g->f[G_TY].i; anchorXY(&x, &y, dw, dh, an);
  if (gT(g)) { rImage(g, s, sx, sy, w, h, tr, x, y); touch(g); return; }
  syncState(g); ensureRes(img); pb(13); p32(img->f[2].i); p16(sx); p16(sy); p16(w); p16(h); pb(tr); p16(cl16(x)); p16(cl16(y));
}
static void g_drawImage(Slot *a) { Obj *im = OBJ(1); if (!im) { throwNew("java/lang/NullPointerException", 0); return; } Surf *s = sOf(im); drawImg(OBJ(0), im, 0, 0, s->w, s->h, 0, a[2].i, a[3].i, a[4].i); }
static void g_drawRegion(Slot *a) {
  Obj *im = OBJ(1); if (!im) { throwNew("java/lang/NullPointerException", 0); return; } Surf *s = sOf(im);
  int sx = a[2].i, sy = a[3].i, w = a[4].i, h = a[5].i, tr = a[6].i;
  if (sx < 0 || sy < 0 || w < 0 || h < 0 || sx + w > s->w || sy + h > s->h || tr < 0 || tr > 7) { throwNew("java/lang/IllegalArgumentException", 0); return; }
  drawImg(OBJ(0), im, sx, sy, w, h, tr, a[7].i, a[8].i, a[9].i);
}
static void g_drawRGB(Slot *a) {
  Obj *g = OBJ(0); Arr *p = ARR(1); int off = a[2].i, sc = a[3].i, x = a[4].i, y = a[5].i, w = a[6].i, h = a[7].i, al = a[8].i;
  if (!p) { throwNew("java/lang/NullPointerException", 0); return; } if (w <= 0 || h <= 0) return;
  Surf *s = surfNew(w, h, 0);
  for (int j = 0; j < h; j++) for (int i = 0; i < w; i++) { int si = off + j * sc + i; if (si < 0 || si >= p->len) { free(s->px); free(s); throwNew("java/lang/ArrayIndexOutOfBoundsException", 0); return; } uint32_t v = ((uint32_t *)p->d)[si]; s->px[j * w + i] = al ? v : (v | 0xFF000000); }
  Obj *tmp = newImage(s, 0); drawImg(g, tmp, 0, 0, w, h, 0, x, y, 0);
}
static void g_copyArea(Slot *a) { (void)a; }

// ---------------- Display / Displayable / Canvas ----------------
static Obj *g_cur, *g_display, *g_screenG, *g_midlet;
static int g_repaint, g_inPaint, g_keyBits;
static int64_t lastPaint;
static Obj *gcCanvas;
#define D_LISTENER 1
static Class *cvCls() { return canvasCls ? canvasCls : (canvasCls = loadClass(LCD "Canvas")); }
static int isCanvas(Obj *o) { return o && subOf(o->cls, cvCls()); }

typedef struct { int kind, a, b; Obj *o; } Ev;
enum { EK_KEYD, EK_KEYU, EK_KEYR, EK_PD, EK_PU, EK_PM, EK_SERIAL, EK_CMD, EK_SHOW, EK_ITEM };
static Ev evq[512]; static int evh, evt;
static pthread_mutex_t evmu = PTHREAD_MUTEX_INITIALIZER;
static void evPush(int kind, int a, int b, Obj *o) { pthread_mutex_lock(&evmu); int n = (evt + 1) % 512; if (n != evh) { evq[evt] = (Ev){kind, a, b, o}; evt = n; } pthread_mutex_unlock(&evmu); }
static void *evT; static int evBusy, evPaint;

static int gameBit(int code) {
  switch (code) { case -1: case 50: return 1 << 1; case -2: case 56: return 1 << 6; case -3: case 52: return 1 << 2; case -4: case 54: return 1 << 5; case -5: case 53: return 1 << 8; case 49: return 1 << 9; case 51: return 1 << 10; case 55: return 1 << 11; case 57: return 1 << 12; }
  return 0;
}
// Host đẩy phím / chạm vào hàng đợi
static int heldK[16];
void midpKey(int type, int code) { if (type == 0) { int rep = 0, fr = -1; for (int i = 0; i < 16; i++) { if (heldK[i] == code) rep = 1; if (!heldK[i] && fr < 0) fr = i; } if (!rep && fr >= 0) heldK[fr] = code; g_keyBits |= gameBit(code); evPush(rep ? EK_KEYR : EK_KEYD, code, 0, 0); } else if (type == 1) { for (int i = 0; i < 16; i++) if (heldK[i] == code) heldK[i] = 0; g_keyBits &= ~gameBit(code); evPush(EK_KEYU, code, 0, 0); } else evPush(EK_KEYR, code, 0, 0); }
void midpPointer(int type, int x, int y) { evPush(type == 0 ? EK_PD : type == 1 ? EK_PU : EK_PM, x, y, 0); }

static void fn_dispGet(Slot *a) { (void)a; if (!g_display) g_display = newObj(dispCls ? dispCls : (dispCls = loadClass(LCD "Display"))); a[0].a = g_display; }
static void fn_dispSet(Slot *a) {
  Obj *d = OBJ(1); g_cur = d; g_repaint = 1; evPush(EK_SHOW, 0, 0, d);
}
static void fn_dispSetAlert(Slot *a) { g_cur = OBJ(2); g_repaint = 1; evPush(EK_SHOW, 0, 0, g_cur); }
static void fn_dispCur(Slot *a) { a[0].a = g_cur; }
static void fn_dispSerial(Slot *a) { evPush(EK_SERIAL, 0, 0, OBJ(1)); }
static void fn_true(Slot *a) { a[0].i = 1; }
static void fn_false(Slot *a) { a[0].i = 0; }
static void fn_zero(Slot *a) { a[0].i = 0; }
static void fn_nop(Slot *a) { (void)a; }
static void fn_numColors(Slot *a) { a[0].i = 16777216; }
static void fn_numAlpha(Slot *a) { a[0].i = 256; }
static void fn_best32(Slot *a) { a[0].i = 32; }
static void fn_dispColor(Slot *a) { int c = a[1].i; a[0].i = (c == 1 || c == 3) ? 0 : 0xFFFFFF; }
static void fn_dW(Slot *a) { a[0].i = g_sw; }
static void fn_dH(Slot *a) { a[0].i = g_sh; }
static void fn_setListener(Slot *a) { OBJ(0)->f[D_LISTENER].a = a[1].a; }
static void fn_repaint(Slot *a) { (void)a; g_repaint = 1; }
static void fn_keyName(Slot *a) { char b[16]; snprintf(b, sizeof b, "%d", a[1].i); a[0].a = newStr(b); }
static void fn_getGameAction(Slot *a) { int c = a[1].i; int r = 0; switch (c) { case -1: case 50: r = 1; break; case -2: case 56: r = 6; break; case -3: case 52: r = 2; break; case -4: case 54: r = 5; break; case -5: case 53: r = 8; break; case 49: r = 9; break; case 51: r = 10; break; case 55: r = 11; break; case 57: r = 12; break; } a[0].i = r; }
static void fn_getKeyCode(Slot *a) { switch (a[1].i) { case 1: a[0].i = -1; break; case 6: a[0].i = -2; break; case 2: a[0].i = -3; break; case 5: a[0].i = -4; break; case 8: a[0].i = -5; break; case 9: a[0].i = 49; break; case 10: a[0].i = 51; break; case 11: a[0].i = 55; break; case 12: a[0].i = 57; break; default: a[0].i = 0; } }

static void paintNow(Obj *cv) {
  Method *m = findMethod(cv->cls, "paint", "(Ljavax/microedition/lcdui/Graphics;)V"); if (!m || m->native) return;
  if (!frameOpen) frameBegin();
  gReset(g_screenG, g_sw, g_sh); Slot ar[2]; ar[0].a = cv; ar[1].a = g_screenG; g_inPaint = 1; callMethod(m, ar, 2); g_inPaint = 0;
  frameEnd(); lastPaint = nowMs();
}
static void fn_serviceRepaints(Slot *a) {
  (void)a; if (g_inPaint || !g_repaint || !isCanvas(g_cur) || g_cur == gcCanvas) return;
  g_repaint = 0; paintNow(g_cur);
}

// GameCanvas
static void fn_gcInit(Slot *a) { gcCanvas = OBJ(0); }
static void fn_gcGetG(Slot *a) { (void)a; if (!g_gcG) g_gcG = newGraphics(0, g_sw, g_sh, 0); if (!frameOpen) { frameBegin(); gReset(g_gcG, g_sw, g_sh); } a[0].a = g_gcG; }
static void fn_gcFlush(Slot *a) { (void)a; if (frameOpen) frameEnd(); g_repaint = 0; }
static void fn_gcKeys(Slot *a) { a[0].i = g_keyBits; }

#include "ui.inc"
#include "net.inc"

// ---- phát sự kiện: gọi trên luồng sự kiện ----
static int startEvent(Ev *e) {
  if (getenv("JVM_CALLS")) fprintf(stderr, "EV kind=%d a=%d\n", e->kind, e->a);
  Obj *cv = g_cur; Method *m = 0; Slot ar[4]; int n = 0;
  switch (e->kind) {
    case EK_KEYD: if (!isCanvas(cv)) return 0; m = findMethod(cv->cls, "keyPressed", "(I)V"); ar[0].a = cv; ar[1].i = e->a; n = 2; break;
    case EK_KEYU: if (!isCanvas(cv)) return 0; m = findMethod(cv->cls, "keyReleased", "(I)V"); ar[0].a = cv; ar[1].i = e->a; n = 2; break;
    case EK_KEYR: if (!isCanvas(cv)) return 0; m = findMethod(cv->cls, "keyRepeated", "(I)V"); ar[0].a = cv; ar[1].i = e->a; n = 2; break;
    case EK_PD: if (!isCanvas(cv)) return 0; m = findMethod(cv->cls, "pointerPressed", "(II)V"); ar[0].a = cv; ar[1].i = e->a; ar[2].i = e->b; n = 3; break;
    case EK_PU: if (!isCanvas(cv)) return 0; m = findMethod(cv->cls, "pointerReleased", "(II)V"); ar[0].a = cv; ar[1].i = e->a; ar[2].i = e->b; n = 3; break;
    case EK_PM: if (!isCanvas(cv)) return 0; m = findMethod(cv->cls, "pointerDragged", "(II)V"); ar[0].a = cv; ar[1].i = e->a; ar[2].i = e->b; n = 3; break;
    case EK_SERIAL: m = findMethod(e->o->cls, "run", "()V"); ar[0].a = e->o; n = 1; break;
    case EK_SHOW: if (!isCanvas(e->o)) return 0; m = findMethod(e->o->cls, "showNotify", "()V"); ar[0].a = e->o; n = 1; break;
    case EK_CMD: { if (!e->o || isCanvas(e->o)) return 0; UiD *u = ud(e->o, 0); Obj *cmd = e->a < 0 ? (u->selCmd ? u->selCmd : (Obj *)loadClass(LCD "List")->statics[0].a) : (e->a < u->ncmd ? u->cmd[e->a] : 0); Obj *l = e->o->f[D_LISTENER].a; if (!l || !cmd) return 0;
      m = findMethod(l->cls, "commandAction", "(Ljavax/microedition/lcdui/Command;Ljavax/microedition/lcdui/Displayable;)V"); ar[0].a = l; ar[1].a = cmd; ar[2].a = e->o; n = 3; break; }
    case EK_ITEM: { if (!e->o) return 0; UiD *u = ud(e->o, 0); Obj *l = u->stateL; if (!l || e->a >= u->nit) return 0; m = findMethod(l->cls, "itemStateChanged", "(Ljavax/microedition/lcdui/Item;)V"); ar[0].a = l; ar[1].a = u->items[e->a]; n = 2; break; }
    default: return 0;
  }
  if (!m || m->native) return 0;
  evThreadRun(evT, m, ar, n); evBusy = 1; evPaint = 0; return 1;
}
static void midpIdle(void) {
  if (!evT) evT = evThreadNew();
  uiTick();
  if (evBusy && !evThreadBusy(evT)) { evBusy = 0; if (evPaint) { evPaint = 0; frameEnd(); lastPaint = nowMs(); } }
  if (evBusy) return;
  for (;;) { pthread_mutex_lock(&evmu); if (evh == evt) { pthread_mutex_unlock(&evmu); break; } Ev e = evq[evh]; evh = (evh + 1) % 512; pthread_mutex_unlock(&evmu); if (startEvent(&e)) return; }
  if (g_repaint && isCanvas(g_cur) && g_cur != gcCanvas && nowMs() - lastPaint >= 16) {
    Method *m = findMethod(g_cur->cls, "paint", "(Ljavax/microedition/lcdui/Graphics;)V");
    if (m && !m->native) {
      g_repaint = 0; if (!frameOpen) frameBegin(); gReset(g_screenG, g_sw, g_sh);
      Slot ar[2]; ar[0].a = g_cur; ar[1].a = g_screenG; evThreadRun(evT, m, ar, 2); evBusy = 1; evPaint = 1;
    }
  }
}

// MIDlet
static void fn_midInit(Slot *a) { g_midlet = OBJ(0); }
static void fn_notifyDestroyed(Slot *a) { (void)a; g_destroyed = 1; }
static void fn_platformReq(Slot *a) { a[0].i = 0; }
static Obj *utf8Str(const char *s);
// MIDlet.getAppProperty: đọc META-INF/MANIFEST.MF (và .jad cạnh đó nếu có) trong thư mục lớp
static char *g_mf; static int g_mfLen;
static void mfLoad(void) {
  if (g_mf) return; int n = 0; uint8_t *d = loadResource("META-INF/MANIFEST.MF", &n);
  if (!d) { g_mf = strdup(""); g_mfLen = 0; return; }
  char *t = malloc(n + 2); int k = 0;
  for (int i = 0; i < n; i++) { if (d[i] == '\r') continue; if (d[i] == '\n' && i + 1 < n && d[i + 1] == ' ') { i++; continue; } t[k++] = d[i]; } t[k] = 0; g_mf = t; g_mfLen = k;
}
static void fn_getProp(Slot *a) {
  Obj *k = OBJ(1); if (!k) { throwNew("java/lang/NullPointerException", 0); return; } mfLoad();
  char key[200]; cstr(k, key, sizeof key); size_t kl = strlen(key);
  for (char *p = g_mf; p && *p;) {
    char *e = strchr(p, '\n'); size_t ll = e ? (size_t)(e - p) : strlen(p);
    if (ll > kl && !strncmp(p, key, kl) && p[kl] == ':') { const char *v = p + kl + 1; while (*v == ' ') v++; size_t vl = ll - (size_t)(v - p); char *tmp = malloc(vl + 1); memcpy(tmp, v, vl); tmp[vl] = 0; a[0].a = utf8Str(tmp); free(tmp); return; }
    p = e ? e + 1 : 0;
  }
  a[0].a = 0;
}
static void fn_perm(Slot *a) { a[0].i = 1; }

// Command
static void fn_cmdInit(Slot *a) { Obj *o = OBJ(0); o->f[0].a = a[1].a; o->f[1].i = a[2].i; o->f[2].i = a[3].i; }
static void fn_cmdInit2(Slot *a) { Obj *o = OBJ(0); o->f[0].a = a[1].a; o->f[1].i = a[3].i; o->f[2].i = a[4].i; }
static void fn_cmdLabel(Slot *a) { a[0].a = OBJ(0)->f[0].a; }
static void fn_cmdType(Slot *a) { a[0].i = OBJ(0)->f[1].i; }
static void fn_cmdPrio(Slot *a) { a[0].i = OBJ(0)->f[2].i; }

// ---------------- RecordStore ----------------
typedef struct RS { char name[80]; int nextId, n, cap; int *ids, *len; uint8_t **dat; int open; struct RS *next; } RS;
static RS *rsList;
static void rsPath(const char *name, char *out, int n) { snprintf(out, n, "%s/rms_%s.bin", g_rmsDir, name); }
static void rsSave(RS *r) {
  char p[600]; rsPath(r->name, p, sizeof p); FILE *f = fopen(p, "wb"); if (!f) return;
  fwrite(&r->nextId, 4, 1, f); fwrite(&r->n, 4, 1, f);
  for (int i = 0; i < r->n; i++) { fwrite(&r->ids[i], 4, 1, f); fwrite(&r->len[i], 4, 1, f); fwrite(r->dat[i], 1, r->len[i], f); }
  fclose(f);
}
static RS *rsFind(const char *name) { for (RS *r = rsList; r; r = r->next) if (!strcmp(r->name, name)) return r; return 0; }
static RS *rsOpen(const char *name, int create) {
  RS *r = rsFind(name); if (r) return r;
  char p[600]; rsPath(name, p, sizeof p); FILE *f = fopen(p, "rb");
  if (!f && !create) return 0;
  r = calloc(1, sizeof *r); snprintf(r->name, sizeof r->name, "%s", name); r->nextId = 1;
  if (f) { int nid, n; if (fread(&nid, 4, 1, f) == 1 && fread(&n, 4, 1, f) == 1 && n >= 0 && n < 100000) { r->nextId = nid; r->cap = n + 4; r->ids = malloc(r->cap * 4); r->len = malloc(r->cap * 4); r->dat = malloc(r->cap * sizeof(void *));
      for (int i = 0; i < n; i++) { int id, L; if (fread(&id, 4, 1, f) != 1 || fread(&L, 4, 1, f) != 1 || L < 0) break; uint8_t *d = malloc(L + 1); if (fread(d, 1, L, f) != (size_t)L) { free(d); break; } r->ids[r->n] = id; r->len[r->n] = L; r->dat[r->n++] = d; } }
    fclose(f); }
  r->next = rsList; rsList = r; return r;
}
static int rsIdx(RS *r, int id) { for (int i = 0; i < r->n; i++) if (r->ids[i] == id) return i; return -1; }
static Obj *rsObj(RS *r) { Obj *o = newObj(rsCls ? rsCls : (rsCls = loadClass("javax/microedition/rms/RecordStore"))); o->f[0].a = r; o->f[1].i = 1; return o; }
static RS *rsOf(Slot *a) { Obj *o = OBJ(0); if (!o->f[1].i) { throwNew("javax/microedition/rms/RecordStoreNotOpenException", 0); return 0; } return o->f[0].a; }
static void rs_open(Slot *a) {
  char nm[100]; cstr(OBJ(0), nm, sizeof nm); RS *r = rsOpen(nm, a[1].i); if (!r) { throwNew("javax/microedition/rms/RecordStoreNotFoundException", nm); return; } a[0].a = rsObj(r);
}
static void rs_close(Slot *a) { Obj *o = OBJ(0); o->f[1].i = 0; }
static void rs_delete(Slot *a) {
  char nm[100]; cstr(OBJ(0), nm, sizeof nm); RS *r = rsFind(nm); char p[600]; rsPath(nm, p, sizeof p);
  FILE *f = fopen(p, "rb"); if (!r && !f) { throwNew("javax/microedition/rms/RecordStoreNotFoundException", nm); return; } if (f) fclose(f);
  remove(p); if (r) { r->n = 0; r->nextId = 1; }
}
static void rs_add(Slot *a) {
  RS *r = rsOf(a); if (!r) return; Arr *b = ARR(1); int off = a[2].i, n = a[3].i;
  if (!b && n > 0) { throwNew("java/lang/NullPointerException", 0); return; } if (b && (off < 0 || n < 0 || off + n > b->len)) { throwNew("java/lang/ArrayIndexOutOfBoundsException", 0); return; }
  if (r->n >= r->cap) { r->cap = r->cap * 2 + 8; r->ids = realloc(r->ids, r->cap * 4); r->len = realloc(r->len, r->cap * 4); r->dat = realloc(r->dat, r->cap * sizeof(void *)); }
  uint8_t *d = malloc(n + 1); if (n) memcpy(d, b->d + off, n); r->ids[r->n] = r->nextId; r->len[r->n] = n; r->dat[r->n++] = d; a[0].i = r->nextId++; rsSave(r);
}
static void rs_get(Slot *a) {
  RS *r = rsOf(a); if (!r) return; int i = rsIdx(r, a[1].i); if (i < 0) { throwNew("javax/microedition/rms/InvalidRecordIDException", 0); return; }
  Arr *o = newArr(r->len[i], 1); if (r->len[i]) memcpy(o->d, r->dat[i], r->len[i]); a[0].a = o;
}
static void rs_getInto(Slot *a) {
  RS *r = rsOf(a); if (!r) return; int i = rsIdx(r, a[1].i); if (i < 0) { throwNew("javax/microedition/rms/InvalidRecordIDException", 0); return; }
  Arr *b = ARR(2); int off = a[3].i; if (r->len[i] > b->len - off) { throwNew("javax/microedition/rms/RecordStoreException", "buffer nhỏ"); return; } memcpy(b->d + off, r->dat[i], r->len[i]); a[0].i = r->len[i];
}
static void rs_set(Slot *a) {
  RS *r = rsOf(a); if (!r) return; int i = rsIdx(r, a[1].i); if (i < 0) { throwNew("javax/microedition/rms/InvalidRecordIDException", 0); return; }
  Arr *b = ARR(2); int off = a[3].i, n = a[4].i; if (!b && n > 0) { throwNew("java/lang/NullPointerException", 0); return; } free(r->dat[i]); r->dat[i] = malloc(n + 1); if (n) memcpy(r->dat[i], b->d + off, n); r->len[i] = n; rsSave(r);
}
static void rs_del(Slot *a) {
  RS *r = rsOf(a); if (!r) return; int i = rsIdx(r, a[1].i); if (i < 0) { throwNew("javax/microedition/rms/InvalidRecordIDException", 0); return; }
  free(r->dat[i]); for (int k = i; k < r->n - 1; k++) { r->ids[k] = r->ids[k + 1]; r->len[k] = r->len[k + 1]; r->dat[k] = r->dat[k + 1]; } r->n--; rsSave(r);
}
static void rs_num(Slot *a) { RS *r = rsOf(a); if (r) a[0].i = r->n; }
static void rs_next(Slot *a) { RS *r = rsOf(a); if (r) a[0].i = r->nextId; }
static void rs_size(Slot *a) { RS *r = rsOf(a); if (!r) return; int s = 0; for (int i = 0; i < r->n; i++) s += r->len[i]; a[0].i = s; }
static void rs_avail(Slot *a) { a[0].i = 1 << 22; }
static void rs_name(Slot *a) { RS *r = rsOf(a); if (r) a[0].a = newStr(r->name); }
static void rs_ver(Slot *a) { a[0].i = 1; }
static void rs_list(Slot *a) {
  int n = 0; for (RS *r = rsList; r; r = r->next) n++; if (!n) { a[0].a = 0; return; }
  Arr *o = newArr(n, 8); int i = 0; for (RS *r = rsList; r; r = r->next) ((void **)o->d)[i++] = newStr(r->name); a[0].a = o;
}
// RecordEnumeration: f0 = RS, f1 = mảng id (Arr int), f2 = vị trí
static void rs_enum(Slot *a) {
  RS *r = rsOf(a); if (!r) return; Obj *e = newObj(loadClass("javax/microedition/rms/RecordEnumeration")); Arr *ids = newArr(r->n, 4);
  for (int i = 0; i < r->n; i++) ((int *)ids->d)[i] = r->ids[i]; e->f[0].a = r; e->f[1].a = ids; e->f[2].i = 0; a[0].a = e;
}
static void re_has(Slot *a) { Obj *e = OBJ(0); a[0].i = e->f[2].i < ((Arr *)e->f[1].a)->len; }
static void re_nextId(Slot *a) { Obj *e = OBJ(0); Arr *ids = e->f[1].a; if (e->f[2].i >= ids->len) { throwNew("javax/microedition/rms/InvalidRecordIDException", 0); return; } a[0].i = ((int *)ids->d)[e->f[2].i++]; }
static void re_next(Slot *a) { Obj *e = OBJ(0); RS *r = e->f[0].a; re_nextId(a); if (g_exc) return; int i = rsIdx(r, a[0].i); if (i < 0) { throwNew("javax/microedition/rms/InvalidRecordIDException", 0); return; } Arr *o = newArr(r->len[i], 1); if (r->len[i]) memcpy(o->d, r->dat[i], r->len[i]); a[0].a = o; }
static void re_num(Slot *a) { a[0].i = ((Arr *)OBJ(0)->f[1].a)->len; }
static void re_reset(Slot *a) { OBJ(0)->f[2].i = 0; }
static void re_nop(Slot *a) { (void)a; }

void installMidp(void) {
  const char *FT = LCD "Font", *IM = LCD "Image", *GR = LCD "Graphics", *DS = LCD "Display", *DP = LCD "Displayable", *CV = LCD "Canvas", *GC = LCD "game/GameCanvas", *CM = LCD "Command";
  const char *MI = MID, *RS_ = "javax/microedition/rms/RecordStore", *RE = "javax/microedition/rms/RecordEnumeration";
  NS(FT, "getFont", "(III)Ljavax/microedition/lcdui/Font;", fn_getFont); NS(FT, "getDefaultFont", "()Ljavax/microedition/lcdui/Font;", fn_defFont);
  NI(FT, "getHeight", "()I", fn_fHeight); NI(FT, "getBaselinePosition", "()I", fn_fBase); NI(FT, "getStyle", "()I", fn_fStyle); NI(FT, "getSize", "()I", fn_fSize); NI(FT, "getFace", "()I", fn_fFace);
  NI(FT, "isBold", "()Z", fn_fBold); NI(FT, "isItalic", "()Z", fn_fItalic); NI(FT, "isPlain", "()Z", fn_fPlain);
  NI(FT, "stringWidth", "(Ljava/lang/String;)I", fn_fSW); NI(FT, "charWidth", "(C)I", fn_fCW); NI(FT, "substringWidth", "(Ljava/lang/String;II)I", fn_fSubW); NI(FT, "charsWidth", "([CII)I", fn_fCharsW);
  NS(IM, "createImage", "(II)Ljavax/microedition/lcdui/Image;", fn_imgCreateWH); NS(IM, "createImage", "([BII)Ljavax/microedition/lcdui/Image;", fn_imgCreateB);
  NS(IM, "createImage", "(Ljava/lang/String;)Ljavax/microedition/lcdui/Image;", fn_imgCreateS); NS(IM, "createImage", "(Ljava/io/InputStream;)Ljavax/microedition/lcdui/Image;", fn_imgCreateIS);
  NS(IM, "createImage", "(Ljavax/microedition/lcdui/Image;)Ljavax/microedition/lcdui/Image;", fn_imgCreateCopy); NS(IM, "createRGBImage", "([IIIZ)Ljavax/microedition/lcdui/Image;", fn_imgCreateRGB);
  NI(IM, "getWidth", "()I", fn_imgW); NI(IM, "getHeight", "()I", fn_imgH); NI(IM, "isMutable", "()Z", fn_imgMut); NI(IM, "getRGB", "([IIIIIII)V", fn_imgGetRGB);
  NI(IM, "getGraphics", "()Ljavax/microedition/lcdui/Graphics;", fn_imgGetGraphics);
  NI(GR, "setColor", "(I)V", g_setColor1); NI(GR, "setColor", "(III)V", g_setColor3); NI(GR, "getColor", "()I", g_getColor); NI(GR, "setGrayScale", "(I)V", g_setGray);
  NI(GR, "translate", "(II)V", g_translate); NI(GR, "getTranslateX", "()I", g_getTX); NI(GR, "getTranslateY", "()I", g_getTY);
  NI(GR, "setClip", "(IIII)V", g_setClip); NI(GR, "clipRect", "(IIII)V", g_clipRect); NI(GR, "getClipX", "()I", g_getCX); NI(GR, "getClipY", "()I", g_getCY); NI(GR, "getClipWidth", "()I", g_getCW); NI(GR, "getClipHeight", "()I", g_getCH);
  NI(GR, "setStrokeStyle", "(I)V", g_setStroke); NI(GR, "getStrokeStyle", "()I", g_getStroke); NI(GR, "setFont", "(Ljavax/microedition/lcdui/Font;)V", g_setFont); NI(GR, "getFont", "()Ljavax/microedition/lcdui/Font;", g_getFont);
  NI(GR, "fillRect", "(IIII)V", g_fillRect); NI(GR, "drawRect", "(IIII)V", g_drawRect); NI(GR, "drawLine", "(IIII)V", g_drawLine); NI(GR, "fillTriangle", "(IIIIII)V", g_tri);
  NI(GR, "drawArc", "(IIIIII)V", g_drawArc); NI(GR, "fillArc", "(IIIIII)V", g_fillArc); NI(GR, "drawRoundRect", "(IIIIII)V", g_drawRR); NI(GR, "fillRoundRect", "(IIIIII)V", g_fillRR);
  NI(GR, "drawString", "(Ljava/lang/String;III)V", g_drawString); NI(GR, "drawSubstring", "(Ljava/lang/String;IIIII)V", g_drawSubstring); NI(GR, "drawChar", "(CIII)V", g_drawChar); NI(GR, "drawChars", "([CIIIII)V", g_drawChars);
  NI(GR, "drawImage", "(Ljavax/microedition/lcdui/Image;III)V", g_drawImage); NI(GR, "drawRegion", "(Ljavax/microedition/lcdui/Image;IIIIIIII)V", g_drawRegion);
  NI(GR, "drawRGB", "([IIIIIIIZ)V", g_drawRGB); NI(GR, "copyArea", "(IIIIIII)V", g_copyArea);
  NI(DP, "<init>", "()V", fn_nop); NI(DP, "getWidth", "()I", fn_dW); NI(DP, "getHeight", "()I", fn_dH); NI(DP, "setCommandListener", "(Ljavax/microedition/lcdui/CommandListener;)V", fn_setListener);
  NI(DP, "addCommand", "(Ljavax/microedition/lcdui/Command;)V", fn_nop); NI(DP, "removeCommand", "(Ljavax/microedition/lcdui/Command;)V", fn_nop); NI(DP, "isShown", "()Z", fn_true);
  NI(CV, "<init>", "()V", fn_nop); NI(CV, "repaint", "()V", fn_repaint); NI(CV, "repaint", "(IIII)V", fn_repaint); NI(CV, "serviceRepaints", "()V", fn_serviceRepaints);
  NI(CV, "showNotify", "()V", fn_nop); NI(CV, "hideNotify", "()V", fn_nop); NI(CV, "keyPressed", "(I)V", fn_nop); NI(CV, "keyReleased", "(I)V", fn_nop); NI(CV, "keyRepeated", "(I)V", fn_nop);
  NI(CV, "pointerPressed", "(II)V", fn_nop); NI(CV, "pointerReleased", "(II)V", fn_nop); NI(CV, "pointerDragged", "(II)V", fn_nop); NI(CV, "sizeChanged", "(II)V", fn_nop);
  NI(CV, "setFullScreenMode", "(Z)V", fn_nop); NI(CV, "hasPointerEvents", "()Z", fn_true); NI(CV, "hasPointerMotionEvents", "()Z", fn_true); NI(CV, "hasRepeatEvents", "()Z", fn_true); NI(CV, "isDoubleBuffered", "()Z", fn_true);
  NI(CV, "getGameAction", "(I)I", fn_getGameAction); NI(CV, "getKeyCode", "(I)I", fn_getKeyCode); NI(CV, "getKeyName", "(I)Ljava/lang/String;", fn_keyName);
  NI(GC, "<init>", "(Z)V", fn_gcInit); NI(GC, "getGraphics", "()Ljavax/microedition/lcdui/Graphics;", fn_gcGetG); NI(GC, "flushGraphics", "()V", fn_gcFlush); NI(GC, "flushGraphics", "(IIII)V", fn_gcFlush); NI(GC, "getKeyStates", "()I", fn_gcKeys);
  NS(DS, "getDisplay", "(Ljavax/microedition/midlet/MIDlet;)Ljavax/microedition/lcdui/Display;", fn_dispGet);
  NI(DS, "setCurrent", "(Ljavax/microedition/lcdui/Displayable;)V", fn_dispSet); NI(DS, "setCurrent", "(Ljavax/microedition/lcdui/Alert;Ljavax/microedition/lcdui/Displayable;)V", fn_dispSetAlert);
  NI(DS, "getCurrent", "()Ljavax/microedition/lcdui/Displayable;", fn_dispCur); NI(DS, "callSerially", "(Ljava/lang/Runnable;)V", fn_dispSerial);
  NI(DS, "isColor", "()Z", fn_true); NI(DS, "numColors", "()I", fn_numColors); NI(DS, "numAlphaLevels", "()I", fn_numAlpha); NI(DS, "vibrate", "(I)Z", fn_true); NI(DS, "flashBacklight", "(I)Z", fn_true);
  NI(DS, "getBestImageWidth", "(I)I", fn_best32); NI(DS, "getBestImageHeight", "(I)I", fn_best32); NI(DS, "getColor", "(I)I", fn_dispColor); NI(DS, "setCurrentItem", "(Ljavax/microedition/lcdui/Item;)V", fn_nop);
  NI(MI, "<init>", "()V", fn_midInit); NI(MI, "notifyDestroyed", "()V", fn_notifyDestroyed); NI(MI, "notifyPaused", "()V", fn_nop); NI(MI, "resumeRequest", "()V", fn_nop);
  NI(MI, "platformRequest", "(Ljava/lang/String;)Z", fn_platformReq); NI(MI, "getAppProperty", "(Ljava/lang/String;)Ljava/lang/String;", fn_getProp); NI(MI, "checkPermission", "(Ljava/lang/String;)I", fn_perm);
  NI(CM, "<init>", "(Ljava/lang/String;II)V", fn_cmdInit); NI(CM, "<init>", "(Ljava/lang/String;Ljava/lang/String;II)V", fn_cmdInit2);
  NI(CM, "getLabel", "()Ljava/lang/String;", fn_cmdLabel); NI(CM, "getCommandType", "()I", fn_cmdType); NI(CM, "getPriority", "()I", fn_cmdPrio);
  NS(RS_, "openRecordStore", "(Ljava/lang/String;Z)Ljavax/microedition/rms/RecordStore;", rs_open); NS(RS_, "deleteRecordStore", "(Ljava/lang/String;)V", rs_delete); NS(RS_, "listRecordStores", "()[Ljava/lang/String;", rs_list);
  NI(RS_, "closeRecordStore", "()V", rs_close); NI(RS_, "addRecord", "([BII)I", rs_add); NI(RS_, "getRecord", "(I)[B", rs_get); NI(RS_, "getRecord", "(I[BI)I", rs_getInto); NI(RS_, "setRecord", "(I[BII)V", rs_set);
  NI(RS_, "deleteRecord", "(I)V", rs_del); NI(RS_, "getNumRecords", "()I", rs_num); NI(RS_, "getNextRecordID", "()I", rs_next); NI(RS_, "getSize", "()I", rs_size); NI(RS_, "getSizeAvailable", "()I", rs_avail);
  NI(RS_, "getName", "()Ljava/lang/String;", rs_name); NI(RS_, "getVersion", "()I", rs_ver);
  NI(RS_, "enumerateRecords", "(Ljavax/microedition/rms/RecordFilter;Ljavax/microedition/rms/RecordComparator;Z)Ljavax/microedition/rms/RecordEnumeration;", rs_enum);
  NI(RE, "hasNextElement", "()Z", re_has); NI(RE, "nextRecordId", "()I", re_nextId); NI(RE, "nextRecord", "()[B", re_next); NI(RE, "numRecords", "()I", re_num); NI(RE, "reset", "()V", re_reset); NI(RE, "destroy", "()V", re_nop);
  (void)re_next; (void)fn_zero; (void)fn_false;
  g_idle = midpIdle;
  uiInstall();
  netInstall();
  g_screenG = newGraphics(0, g_sw, g_sh, 0);
}

// ---------------- API cho host ----------------
void midpSetScreen(int w, int h) { if (w != g_sw || h != g_sh) { g_sw = w; g_sh = h; needKey = 1; if (g_screenG) gReset(g_screenG, w, h); } g_repaint = 1; }
void midpRequestRepaint(void) { g_repaint = 1; }

void midpForceKey(void) { needKey = 1; g_repaint = 1; frameOpen = 0; }
void midpReset(void) {
  fontCls = imgCls = gfxCls = cmdCls = dispCls = canvasCls = rsCls = 0; defFont = 0; g_resId = 1; g_gcG = 0; g_cur = g_display = g_screenG = g_midlet = 0; gcCanvas = 0;
  g_repaint = 0; g_inPaint = 0; g_keyBits = 0; lastPaint = 0; evh = evt = 0; evT = 0; evBusy = evPaint = 0; rsList = 0; warnedText = 0; frameOpen = 0; needKey = 1; epoch = 1; g_frames = 0; g_destroyed = 0;
  memset(heldK, 0, sizeof heldK); g_prevScr = 0; free(g_mf); g_mf = 0; g_uiDirty = 1; uiAh = uiAt = 0; uiOutNew = 0;
}
