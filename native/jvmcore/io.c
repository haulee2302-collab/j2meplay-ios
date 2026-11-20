// java.io (luồng byte trong bộ nhớ, DataInput/OutputStream), Class.getResourceAsStream, Arrays, các hàm chuỗi bổ sung.
#include "jvm.h"

#define NS(cls, name, desc, fn) regNative(cls, name, desc, 1, fn)
#define NI(cls, name, desc, fn) regNative(cls, name, desc, 0, fn)
#define OBJ(i) ((Obj *)a[i].a)
#define ARR(i) ((Arr *)a[i].a)

// Nạp tài nguyên theo tên (đường dẫn tuyệt đối trong JAR, không có '/' đầu). Mặc định: đọc từ thư mục lớp.
uint8_t *(*g_resLoader)(const char *name, int *len);
static uint8_t *defaultRes(const char *name, int *len) {
  char path[600]; snprintf(path, sizeof path, "%s/%s", cpdir, name);
  FILE *f = fopen(path, "rb"); if (!f) return 0;
  fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
  uint8_t *b = malloc(n + 1); if (fread(b, 1, n, f) != (size_t)n) { fclose(f); free(b); return 0; } fclose(f);
  *len = (int)n; return b;
}
uint8_t *loadResource(const char *name, int *len) { return (g_resLoader ? g_resLoader : defaultRes)(name[0] == '/' ? name + 1 : name, len); }

static Class *baisCls, *baosCls, *istCls;
void ioReset(void) { baisCls = baosCls = istCls = 0; }
Class *g_sockInCls, *g_sockOutCls; int (*g_sockWait)(Obj *, int); int (*g_sockTake)(Obj *, uint8_t *, int, int); void (*g_sockPut)(Obj *, const uint8_t *, int);
static Class *cBAIS(void) { return baisCls ? baisCls : (baisCls = loadClass("java/io/ByteArrayInputStream")); }
static Class *cBAOS(void) { return baosCls ? baosCls : (baosCls = loadClass("java/io/ByteArrayOutputStream")); }

// ---- ByteArrayInputStream: f0 = mảng, f1 = pos, f2 = count, f3 = mark ----
Obj *newBytesStream(const uint8_t *d, int n) {
  Obj *o = newObj(cBAIS()); Arr *b = newArr(n, 1); memcpy(b->d, d, n);
  o->f[0].a = b; o->f[1].i = 0; o->f[2].i = n; o->f[3].i = 0; return o;
}
static void bais_init(Slot *a) { Obj *o = OBJ(0); Arr *b = ARR(1); if (!b) { throwNew("java/lang/NullPointerException", 0); return; } o->f[0].a = b; o->f[1].i = 0; o->f[2].i = b->len; o->f[3].i = 0; }
static void bais_initR(Slot *a) { Obj *o = OBJ(0); Arr *b = ARR(1); int off = a[2].i, n = a[3].i; if (!b) { throwNew("java/lang/NullPointerException", 0); return; } o->f[0].a = b; o->f[1].i = off; o->f[2].i = off + n > b->len ? b->len : off + n; o->f[3].i = off; }
static void bais_read(Slot *a) { Obj *o = OBJ(0); Arr *b = o->f[0].a; a[0].i = o->f[1].i < o->f[2].i ? b->d[o->f[1].i++] : -1; }
static int baisReadN(Obj *o, Arr *dst, int off, int n) {
  Arr *b = o->f[0].a; int pos = o->f[1].i, cnt = o->f[2].i;
  if (off < 0 || n < 0 || off + n > dst->len) { throwNew("java/lang/IndexOutOfBoundsException", 0); return -1; }
  if (n == 0) return 0; if (pos >= cnt) return -1;
  if (n > cnt - pos) n = cnt - pos;
  memcpy(dst->d + off, b->d + pos, n); o->f[1].i = pos + n; return n;
}
static void bais_readBII(Slot *a) { a[0].i = baisReadN(OBJ(0), ARR(1), a[2].i, a[3].i); }
static void bais_readB(Slot *a) { a[0].i = baisReadN(OBJ(0), ARR(1), 0, ARR(1)->len); }
static void bais_avail(Slot *a) { Obj *o = OBJ(0); a[0].i = o->f[2].i - o->f[1].i; }
static void bais_mark(Slot *a) { Obj *o = OBJ(0); o->f[3].i = o->f[1].i; }
static void bais_reset(Slot *a) { Obj *o = OBJ(0); o->f[1].i = o->f[3].i; }
static void bais_skip(Slot *a) { Obj *o = OBJ(0); int64_t n = a[1].l, r = o->f[2].i - o->f[1].i; if (n < r) r = n; if (r < 0) r = 0; o->f[1].i += (int)r; a[0].l = r; }
static void ist_nop(Slot *a) { (void)a; }
static void ist_markSup(Slot *a) { a[0].i = 1; }

// Đọc 1 byte từ InputStream bất kỳ (nhánh nhanh cho ByteArrayInputStream).
static int istRead1(Obj *in) {
  if (!in) { throwNew("java/lang/NullPointerException", 0); return -1; }
  if (in->cls == cBAIS()) { Arr *b = in->f[0].a; return in->f[1].i < in->f[2].i ? b->d[in->f[1].i++] : -1; }
  if (in->cls == g_sockInCls) { if (!g_sockWait(in, 1)) return -1; uint8_t b; return g_sockTake(in, &b, 1, 0) > 0 ? b : -1; }
  Method *m = findMethod(in->cls, "read", "()I"); if (!m) { throwNew("java/io/IOException", "read"); return -1; }
  Slot ar[1]; ar[0].a = in; Slot r = callMethod(m, ar, 1); return g_exc ? -1 : r.i;
}
static int istReadN(Obj *in, Arr *dst, int off, int n) {
  if (in->cls == cBAIS()) return baisReadN(in, dst, off, n);
  if (in->cls == g_sockInCls) { if (n == 0) return 0; if (!g_sockWait(in, 1)) return -1; int k = g_sockTake(in, dst->d + off, n, 0); return k > 0 ? k : -1; }
  int got = 0;
  while (got < n) { int c = istRead1(in); if (g_exc) return -1; if (c < 0) break; dst->d[off + got++] = (uint8_t)c; }
  return got == 0 && n > 0 ? -1 : got;
}
// InputStream tổng quát (lớp con do game viết sẽ ghi đè read()I)
static void ist_readB(Slot *a) { a[0].i = istReadN(OBJ(0), ARR(1), 0, ARR(1)->len); }
static void ist_readBII(Slot *a) { a[0].i = istReadN(OBJ(0), ARR(1), a[2].i, a[3].i); }
static void ist_avail(Slot *a) { a[0].i = 0; }
static void ist_init(Slot *a) { (void)a; }
static void ist_skip(Slot *a) { int64_t n = a[1].l, k = 0; Obj *o = OBJ(0); while (k < n && istRead1(o) >= 0 && !g_exc) k++; a[0].l = k; }

// ---- DataInputStream: f0 = luồng bên dưới ----
static void dis_init(Slot *a) { Obj *o = OBJ(0); if (!a[1].a) { throwNew("java/lang/NullPointerException", 0); return; } o->f[0].a = a[1].a; }
static Obj *under(Slot *a) { return OBJ(0)->f[0].a; }
static int dRead(Slot *a) { return istRead1(under(a)); }
#define EOFX { throwNew("java/io/EOFException", 0); return; }
static int readBytes(Slot *a, uint8_t *out, int n) {
  Obj *u = under(a);
  if (u->cls == cBAIS()) { Arr *b = u->f[0].a; if (u->f[2].i - u->f[1].i < n) { u->f[1].i = u->f[2].i; throwNew("java/io/EOFException", 0); return 0; } memcpy(out, b->d + u->f[1].i, n); u->f[1].i += n; return 1; }
  if (u->cls == g_sockInCls) { if (!g_sockWait(u, n)) return 0; if (g_sockTake(u, out, n, 0) < n) { throwNew("java/io/EOFException", 0); return 0; } return 1; }
  for (int i = 0; i < n; i++) { int c = istRead1(u); if (g_exc) return 0; if (c < 0) { throwNew("java/io/EOFException", 0); return 0; } out[i] = (uint8_t)c; }
  return 1;
}
static void dis_read(Slot *a) { a[0].i = dRead(a); }
static void dis_readB(Slot *a) { a[0].i = istReadN(under(a), ARR(1), 0, ARR(1)->len); }
static void dis_readBII(Slot *a) { a[0].i = istReadN(under(a), ARR(1), a[2].i, a[3].i); }
static void dis_avail(Slot *a) { Obj *u = under(a); if (u->cls == cBAIS()) { a[0].i = u->f[2].i - u->f[1].i; return; } Method *m = findMethod(u->cls, "available", "()I"); if (!m) { a[0].i = 0; return; } Slot ar[1]; ar[0].a = u; a[0] = callMethod(m, ar, 1); }
static void dis_close(Slot *a) { Obj *u = under(a); Method *m = findMethod(u->cls, "close", "()V"); if (m && !m->native) { Slot ar[1]; ar[0].a = u; callMethod(m, ar, 1); } }
static void dis_mark(Slot *a) { Obj *u = under(a); if (u->cls == cBAIS()) u->f[3].i = u->f[1].i; }
static void dis_reset(Slot *a) { Obj *u = under(a); if (u->cls == cBAIS()) u->f[1].i = u->f[3].i; }
static void dis_skip(Slot *a) { Slot b[2]; b[0].a = under(a); b[1] = a[1]; if (b[0].a && ((Obj *)b[0].a)->cls == cBAIS()) { bais_skip(b); a[0] = b[0]; } else { ist_skip(b); a[0] = b[0]; } }
static void dis_skipBytes(Slot *a) { Slot b[2]; b[0].a = under(a); b[1].l = a[1].i; Obj *u = b[0].a; if (u->cls == cBAIS()) bais_skip(b); else ist_skip(b); a[0].i = (int)b[0].l; }
static void dis_readFullyB(Slot *a) { Arr *b = ARR(1); if (!b) { throwNew("java/lang/NullPointerException", 0); return; } readBytes(a, b->d, b->len); }
static void dis_readFullyBII(Slot *a) { Arr *b = ARR(1); int off = a[2].i, n = a[3].i; if (!b || off < 0 || n < 0 || off + n > b->len) { throwNew("java/lang/IndexOutOfBoundsException", 0); return; } readBytes(a, b->d + off, n); }
static void dis_readUB(Slot *a) { uint8_t b[1]; if (!readBytes(a, b, 1)) return; a[0].i = b[0]; }
static void dis_readB1(Slot *a) { uint8_t b[1]; if (!readBytes(a, b, 1)) return; a[0].i = (int8_t)b[0]; }
static void dis_readZ(Slot *a) { uint8_t b[1]; if (!readBytes(a, b, 1)) return; a[0].i = b[0] != 0; }
static void dis_readS(Slot *a) { uint8_t b[2]; if (!readBytes(a, b, 2)) return; a[0].i = (int16_t)((b[0] << 8) | b[1]); }
static void dis_readUS(Slot *a) { uint8_t b[2]; if (!readBytes(a, b, 2)) return; a[0].i = (b[0] << 8) | b[1]; }
static void dis_readI(Slot *a) { uint8_t b[4]; if (!readBytes(a, b, 4)) return; a[0].i = (int32_t)(((uint32_t)b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]); }
static void dis_readJ(Slot *a) { uint8_t b[8]; if (!readBytes(a, b, 8)) return; uint64_t v = 0; for (int i = 0; i < 8; i++) v = (v << 8) | b[i]; a[0].l = (int64_t)v; }
static void dis_readF(Slot *a) { uint8_t b[4]; if (!readBytes(a, b, 4)) return; uint32_t v = ((uint32_t)b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]; memcpy(&a[0].f, &v, 4); }
static void dis_readD(Slot *a) { uint8_t b[8]; if (!readBytes(a, b, 8)) return; uint64_t v = 0; for (int i = 0; i < 8; i++) v = (v << 8) | b[i]; memcpy(&a[0].d, &v, 8); }
static void dis_readUTF(Slot *a) {
  { Obj *u = under(a); if (u->cls == g_sockInCls) { uint8_t pk[2]; if (!g_sockWait(u, 2)) return; if (g_sockTake(u, pk, 2, 1) == 2 && !g_sockWait(u, 2 + ((pk[0] << 8) | pk[1]))) return; } }
  uint8_t h[2]; if (!readBytes(a, h, 2)) return; int n = (h[0] << 8) | h[1];
  uint8_t *b = malloc(n + 1); if (!readBytes(a, b, n)) { free(b); return; }
  uint16_t *c = malloc((n + 1) * 2); int k = 0;
  for (int i = 0; i < n;) {
    uint8_t x = b[i];
    if (x < 0x80) { c[k++] = x; i++; }
    else if ((x & 0xE0) == 0xC0 && i + 1 < n) { c[k++] = ((x & 31) << 6) | (b[i + 1] & 63); i += 2; }
    else if ((x & 0xF0) == 0xE0 && i + 2 < n) { c[k++] = ((x & 15) << 12) | ((b[i + 1] & 63) << 6) | (b[i + 2] & 63); i += 3; }
    else { free(b); free(c); throwNew("java/io/UTFDataFormatException", 0); return; }
  }
  Obj *s = newStr16(c, k); free(b); free(c); a[0].a = s;
}

// ---- ByteArrayOutputStream: f0 = bộ đệm, f1 = len, f2 = cap ----
static void baos_reserve(Obj *o, int extra) {
  int len = o->f[1].i, cap = o->f[2].i;
  if (len + extra > cap) { cap = (len + extra) * 2 + 16; o->f[0].a = realloc(o->f[0].a, cap); o->f[2].i = cap; }
}
static void baos_init(Slot *a) { Obj *o = OBJ(0); o->f[0].a = 0; o->f[1].i = 0; o->f[2].i = 0; baos_reserve(o, 32); }
static void baos_initI(Slot *a) { Obj *o = OBJ(0); o->f[0].a = 0; o->f[1].i = 0; o->f[2].i = 0; baos_reserve(o, a[1].i > 0 ? a[1].i : 32); }
static void baosPut(Obj *o, const uint8_t *d, int n) { baos_reserve(o, n); memcpy((uint8_t *)o->f[0].a + o->f[1].i, d, n); o->f[1].i += n; }
static void baos_write(Slot *a) { uint8_t b = (uint8_t)a[1].i; baosPut(OBJ(0), &b, 1); }
static void baos_writeBII(Slot *a) { Arr *b = ARR(1); int off = a[2].i, n = a[3].i; if (!b || off < 0 || n < 0 || off + n > b->len) { throwNew("java/lang/IndexOutOfBoundsException", 0); return; } baosPut(OBJ(0), b->d + off, n); }
static void baos_writeB(Slot *a) { Arr *b = ARR(1); baosPut(OBJ(0), b->d, b->len); }
static void baos_size(Slot *a) { a[0].i = OBJ(0)->f[1].i; }
static void baos_reset(Slot *a) { OBJ(0)->f[1].i = 0; }
static void baos_toBytes(Slot *a) { Obj *o = OBJ(0); Arr *r = newArr(o->f[1].i, 1); if (o->f[1].i) memcpy(r->d, o->f[0].a, o->f[1].i); a[0].a = r; }
static void baos_toStr(Slot *a) { Obj *o = OBJ(0); char *t = malloc(o->f[1].i + 1); memcpy(t, o->f[0].a, o->f[1].i); t[o->f[1].i] = 0; a[0].a = newStr(t); free(t); }

// Ghi vào OutputStream bất kỳ
static void ostWrite(Obj *out, const uint8_t *d, int n) {
  if (!out) { throwNew("java/lang/NullPointerException", 0); return; }
  if (out->cls == cBAOS()) { baosPut(out, d, n); return; }
  if (out->cls == g_sockOutCls) { g_sockPut(out, d, n); return; }
  Method *m = findMethod(out->cls, "write", "(I)V"); if (!m) { throwNew("java/io/IOException", "write"); return; }
  for (int i = 0; i < n; i++) { Slot ar[2]; ar[0].a = out; ar[1].i = d[i]; callMethod(m, ar, 2); if (g_exc) return; }
}
// ---- DataOutputStream: f0 = luồng bên dưới ----
static void dos_init(Slot *a) { OBJ(0)->f[0].a = a[1].a; }
static Obj *uo(Slot *a) { return OBJ(0)->f[0].a; }
static void dos_write(Slot *a) { uint8_t b = (uint8_t)a[1].i; ostWrite(uo(a), &b, 1); }
static void dos_writeB(Slot *a) { ostWrite(uo(a), ARR(1)->d, ARR(1)->len); }
static void dos_writeBII(Slot *a) { Arr *b = ARR(1); int off = a[2].i, n = a[3].i; if (!b || off < 0 || n < 0 || off + n > b->len) { throwNew("java/lang/IndexOutOfBoundsException", 0); return; } ostWrite(uo(a), b->d + off, n); }
static void dos_writeS(Slot *a) { uint8_t b[2] = {(uint8_t)(a[1].i >> 8), (uint8_t)a[1].i}; ostWrite(uo(a), b, 2); }
static void dos_writeI(Slot *a) { uint32_t v = (uint32_t)a[1].i; uint8_t b[4] = {v >> 24, v >> 16, v >> 8, v}; ostWrite(uo(a), b, 4); }
static void dos_writeJ(Slot *a) { uint64_t v = (uint64_t)a[1].l; uint8_t b[8]; for (int i = 0; i < 8; i++) b[i] = (uint8_t)(v >> (56 - 8 * i)); ostWrite(uo(a), b, 8); }
static void dos_writeF(Slot *a) { uint32_t v; memcpy(&v, &a[1].f, 4); uint8_t b[4] = {v >> 24, v >> 16, v >> 8, v}; ostWrite(uo(a), b, 4); }
static void dos_writeD(Slot *a) { uint64_t v; memcpy(&v, &a[1].d, 8); uint8_t b[8]; for (int i = 0; i < 8; i++) b[i] = (uint8_t)(v >> (56 - 8 * i)); ostWrite(uo(a), b, 8); }
static void dos_writeZ(Slot *a) { uint8_t b = a[1].i != 0; ostWrite(uo(a), &b, 1); }
static void dos_writeUTF(Slot *a) {
  Obj *s = OBJ(1); if (!s) { throwNew("java/lang/NullPointerException", 0); return; }
  int n = S_LEN(s); uint8_t *b = malloc(n * 3 + 2); int k = 0;
  for (int i = 0; i < n; i++) { uint16_t c = S_CH(s)[i]; if (c >= 1 && c < 0x80) b[k++] = c; else if (c < 0x800) { b[k++] = 0xC0 | (c >> 6); b[k++] = 0x80 | (c & 63); } else { b[k++] = 0xE0 | (c >> 12); b[k++] = 0x80 | ((c >> 6) & 63); b[k++] = 0x80 | (c & 63); } }
  if (k > 65535) { free(b); throwNew("java/io/UTFDataFormatException", 0); return; }
  uint8_t h[2] = {(uint8_t)(k >> 8), (uint8_t)k}; ostWrite(uo(a), h, 2); if (!g_exc) ostWrite(uo(a), b, k); free(b);
}
static void dos_flush(Slot *a) { (void)a; }

// ---- Class.getResourceAsStream ----
static void cl_getRes(Slot *a) {
  Class *k = ((Obj *)a[0].a)->f[0].a; Obj *n = OBJ(1); if (!n) { throwNew("java/lang/NullPointerException", 0); return; }
  char nm[400]; int L = 0; for (int i = 0; i < S_LEN(n) && L < 390; i++) nm[L++] = (char)S_CH(n)[i]; nm[L] = 0;
  char full[800];
  if (nm[0] == '/') snprintf(full, sizeof full, "%s", nm + 1);
  else { char pk[400]; snprintf(pk, sizeof pk, "%s", k->name); char *sl = strrchr(pk, '/'); if (sl) { *sl = 0; snprintf(full, sizeof full, "%s/%s", pk, nm); } else snprintf(full, sizeof full, "%s", nm); }
  int len; uint8_t *d = loadResource(full, &len); if (!d) { a[0].a = 0; return; }
  a[0].a = newBytesStream(d, len); free(d);
}

// ---- Arrays / chuỗi bổ sung ----
static void ar_fillI(Slot *a) { Arr *b = ARR(0); int v = a[1].i; for (int i = 0; i < b->len; i++) ((int32_t *)b->d)[i] = v; }
static void ar_fillB(Slot *a) { Arr *b = ARR(0); memset(b->d, a[1].i, b->len); }
static void ar_fillC(Slot *a) { Arr *b = ARR(0); for (int i = 0; i < b->len; i++) ((uint16_t *)b->d)[i] = (uint16_t)a[1].i; }
static void ar_fillS(Slot *a) { Arr *b = ARR(0); for (int i = 0; i < b->len; i++) ((int16_t *)b->d)[i] = (int16_t)a[1].i; }
static void ar_fillZ(Slot *a) { ar_fillB(a); }
static void ar_fillJ(Slot *a) { Arr *b = ARR(0); for (int i = 0; i < b->len; i++) ((int64_t *)b->d)[i] = a[1].l; }
static void ar_fillRI(Slot *a) { Arr *b = ARR(0); int f = a[1].i, t = a[2].i; if (f < 0 || t > b->len || f > t) { throwNew("java/lang/ArrayIndexOutOfBoundsException", 0); return; } for (int i = f; i < t; i++) ((int32_t *)b->d)[i] = a[3].i; }
static void ar_fillRB(Slot *a) { Arr *b = ARR(0); int f = a[1].i, t = a[2].i; if (f < 0 || t > b->len || f > t) { throwNew("java/lang/ArrayIndexOutOfBoundsException", 0); return; } memset(b->d + f, a[3].i, t - f); }
static void ar_fillO(Slot *a) { Arr *b = ARR(0); for (int i = 0; i < b->len; i++) ((void **)b->d)[i] = a[1].a; }

// new String(byte[],int,int[,String]) và getBytes(String): dùng UTF-8 / ISO-8859-1
static void setStr(Obj *o, Obj *s) { o->f[0].a = s->f[0].a; o->f[1].i = s->f[1].i; }
static void st_initBII(Slot *a) { Arr *b = ARR(1); int off = a[2].i, n = a[3].i; if (!b || off < 0 || n < 0 || off + n > b->len) { throwNew("java/lang/StringIndexOutOfBoundsException", 0); return; } char *t = malloc(n + 1); memcpy(t, b->d + off, n); t[n] = 0; Obj *s = newStr(t); free(t); setStr(OBJ(0), s); }
static void st_initBIIS(Slot *a) { st_initBII(a); }
static void st_initBS(Slot *a) { Slot b[4]; b[0] = a[0]; b[1] = a[1]; b[2].i = 0; b[3].i = ARR(1) ? ARR(1)->len : 0; st_initBII(b); }
static void st_getBytesS(Slot *a) {
  Obj *s = OBJ(0); int n = S_LEN(s); uint8_t *t = malloc(n * 3 + 1); int k = 0;
  for (int i = 0; i < n; i++) { uint16_t c = S_CH(s)[i]; if (c < 0x80) t[k++] = c; else if (c < 0x800) { t[k++] = 0xC0 | (c >> 6); t[k++] = 0x80 | (c & 63); } else { t[k++] = 0xE0 | (c >> 12); t[k++] = 0x80 | ((c >> 6) & 63); t[k++] = 0x80 | (c & 63); } }
  Arr *r = newArr(k, 1); memcpy(r->d, t, k); free(t); a[0].a = r;
}

void installIO(void) {
  const char *IS = "java/io/InputStream", *BI = "java/io/ByteArrayInputStream", *DI = "java/io/DataInputStream";
  const char *OS = "java/io/OutputStream", *BO = "java/io/ByteArrayOutputStream", *DO = "java/io/DataOutputStream";
  NI(IS, "<init>", "()V", ist_init); NI(IS, "read", "([B)I", ist_readB); NI(IS, "read", "([BII)I", ist_readBII); NI(IS, "available", "()I", ist_avail);
  NI(IS, "close", "()V", ist_nop); NI(IS, "mark", "(I)V", ist_nop); NI(IS, "reset", "()V", ist_nop); NI(IS, "skip", "(J)J", ist_skip); NI(IS, "markSupported", "()Z", ist_markSup);
  NI(BI, "<init>", "([B)V", bais_init); NI(BI, "<init>", "([BII)V", bais_initR); NI(BI, "read", "()I", bais_read); NI(BI, "read", "([BII)I", bais_readBII); NI(BI, "read", "([B)I", bais_readB);
  NI(BI, "available", "()I", bais_avail); NI(BI, "mark", "(I)V", bais_mark); NI(BI, "reset", "()V", bais_reset); NI(BI, "skip", "(J)J", bais_skip);
  NI(DI, "<init>", "(Ljava/io/InputStream;)V", dis_init); NI(DI, "read", "()I", dis_read); NI(DI, "read", "([B)I", dis_readB); NI(DI, "read", "([BII)I", dis_readBII);
  NI(DI, "available", "()I", dis_avail); NI(DI, "close", "()V", dis_close); NI(DI, "mark", "(I)V", dis_mark); NI(DI, "reset", "()V", dis_reset); NI(DI, "skip", "(J)J", dis_skip); NI(DI, "skipBytes", "(I)I", dis_skipBytes);
  NI(DI, "readFully", "([B)V", dis_readFullyB); NI(DI, "readFully", "([BII)V", dis_readFullyBII);
  NI(DI, "readUnsignedByte", "()I", dis_readUB); NI(DI, "readByte", "()B", dis_readB1); NI(DI, "readBoolean", "()Z", dis_readZ);
  NI(DI, "readShort", "()S", dis_readS); NI(DI, "readUnsignedShort", "()I", dis_readUS); NI(DI, "readChar", "()C", dis_readUS);
  NI(DI, "readInt", "()I", dis_readI); NI(DI, "readLong", "()J", dis_readJ); NI(DI, "readFloat", "()F", dis_readF); NI(DI, "readDouble", "()D", dis_readD); NI(DI, "readUTF", "()Ljava/lang/String;", dis_readUTF);
  NI(OS, "<init>", "()V", ist_init); NI(OS, "write", "([B)V", baos_writeB); NI(OS, "flush", "()V", dos_flush); NI(OS, "close", "()V", dos_flush);
  NI(BO, "<init>", "()V", baos_init); NI(BO, "<init>", "(I)V", baos_initI); NI(BO, "write", "(I)V", baos_write); NI(BO, "write", "([BII)V", baos_writeBII); NI(BO, "write", "([B)V", baos_writeB);
  NI(BO, "size", "()I", baos_size); NI(BO, "reset", "()V", baos_reset); NI(BO, "toByteArray", "()[B", baos_toBytes); NI(BO, "toString", "()Ljava/lang/String;", baos_toStr);
  NI(BO, "toString", "(Ljava/lang/String;)Ljava/lang/String;", baos_toStr); NI(BO, "flush", "()V", dos_flush); NI(BO, "close", "()V", dos_flush);
  NI(DO, "<init>", "(Ljava/io/OutputStream;)V", dos_init); NI(DO, "write", "(I)V", dos_write); NI(DO, "write", "([B)V", dos_writeB); NI(DO, "write", "([BII)V", dos_writeBII);
  NI(DO, "writeByte", "(I)V", dos_write); NI(DO, "writeBoolean", "(Z)V", dos_writeZ); NI(DO, "writeShort", "(I)V", dos_writeS); NI(DO, "writeChar", "(I)V", dos_writeS);
  NI(DO, "writeInt", "(I)V", dos_writeI); NI(DO, "writeLong", "(J)V", dos_writeJ); NI(DO, "writeFloat", "(F)V", dos_writeF); NI(DO, "writeDouble", "(D)V", dos_writeD); NI(DO, "writeUTF", "(Ljava/lang/String;)V", dos_writeUTF);
  NI(DO, "flush", "()V", dos_flush); NI(DO, "close", "()V", dos_flush);
  NI("java/lang/Class", "getResourceAsStream", "(Ljava/lang/String;)Ljava/io/InputStream;", cl_getRes);
  const char *AR = "java/util/Arrays";
  NS(AR, "fill", "([II)V", ar_fillI); NS(AR, "fill", "([BB)V", ar_fillB); NS(AR, "fill", "([CC)V", ar_fillC); NS(AR, "fill", "([SS)V", ar_fillS);
  NS(AR, "fill", "([ZZ)V", ar_fillZ); NS(AR, "fill", "([JJ)V", ar_fillJ); NS(AR, "fill", "([Ljava/lang/Object;Ljava/lang/Object;)V", ar_fillO);
  NS(AR, "fill", "([IIII)V", ar_fillRI); NS(AR, "fill", "([BIIB)V", ar_fillRB);
  const char *S = "java/lang/String";
  NI(S, "<init>", "([BII)V", st_initBII); NI(S, "<init>", "([BIILjava/lang/String;)V", st_initBIIS); NI(S, "<init>", "([BLjava/lang/String;)V", st_initBS);
  NI(S, "getBytes", "(Ljava/lang/String;)[B", st_getBytesS);
  (void)istCls;
}
