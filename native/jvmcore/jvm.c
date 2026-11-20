// Lõi thông dịch JVM bằng C (giai đoạn 2): ngoại lệ, chuỗi, thư viện java.lang/java.util cơ bản, gọi lồng nhau.
// Biên dịch: gcc -O2 -o jvm jvm.c natives.c -lm     Chạy: ./jvm <thư mục lớp> <Lớp chính>
#include "jvm.h"

enum { CP_UTF8 = 1, CP_INT = 3, CP_FLOAT = 4, CP_LONG = 5, CP_DOUBLE = 6, CP_CLASS = 7, CP_STRING = 8,
       CP_FIELD = 9, CP_METHOD = 10, CP_IMETHOD = 11, CP_NAT = 12 };

Obj *g_exc = 0;
Class *arrCls;
const char *cpdir;
static Class *classes[2048]; static int nclasses;

#include <stdarg.h>
char g_log[8192]; static int g_loglen;
void jlogf(const char *fmt, ...) {
  char b[700]; va_list ap; va_start(ap, fmt); vsnprintf(b, sizeof b, fmt, ap); va_end(ap);
  fputs(b, stderr); int n = (int)strlen(b); if (g_loglen + n < (int)sizeof g_log - 1) { memcpy(g_log + g_loglen, b, n); g_loglen += n; g_log[g_loglen] = 0; }
}
static void jlogStr(Obj *s) { char b[300]; int n = 0; for (int i = 0; i < S_LEN(s) && n < 280; i++) { uint16_t c = S_CH(s)[i]; b[n++] = c < 128 ? (char)c : '?'; } b[n] = 0; jlogf("%s", b); }
#ifdef JVM_LIB
#include <pthread.h>
char g_err[512];
static void die(const char *m, const char *a) { snprintf(g_err, sizeof g_err, "%s %s", m, a ? a : ""); jlogf("LỖI: %s\n", g_err); pthread_exit(0); }
#else
static void die(const char *m, const char *a) { fflush(stdout); fprintf(stderr, "LỖI: %s %s\n", m, a ? a : ""); exit(1); }
#endif
static uint16_t r16(const uint8_t *p) { return (p[0] << 8) | p[1]; }
static uint32_t r32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]; }

int argSlotsOf(const char *d, int *ret) {
  int n = 0; d++;
  while (*d != ')') {
    if (*d == 'J' || *d == 'D') { n += 2; d++; }
    else if (*d == 'L') { n++; while (*d != ';') d++; d++; }
    else if (*d == '[') { while (*d == '[') d++; if (*d == 'L') { while (*d != ';') d++; } d++; n++; }
    else { n++; d++; }
  }
  d++;
  *ret = *d == 'V' ? 0 : (*d == 'J' || *d == 'D') ? 2 : 1;
  return n;
}

// ---------------- đăng ký native ----------------
static NativeRow *rows; static int nrows, caprows;
void regNative(const char *cls, const char *name, const char *desc, int isStatic, NativeFn fn) {
  for (int i = 0; i < nrows; i++) if (!strcmp(rows[i].cls, cls) && !strcmp(rows[i].name, name) && !strcmp(rows[i].desc, desc)) { rows[i].fn = fn; rows[i].isStatic = isStatic; return; } // đăng ký sau ghi đè đăng ký trước
  if (nrows == caprows) { caprows = caprows ? caprows * 2 : 512; rows = realloc(rows, caprows * sizeof(NativeRow)); }
  rows[nrows++] = (NativeRow){cls, name, desc, isStatic, fn};
}

// ---------------- lớp có sẵn ----------------
typedef struct { const char *name, *super; int nInst; } BDef;
static const BDef bdefs[] = {
  {"java/util/Timer", "java/lang/Object", 1}, {"javax/microedition/io/StreamConnection", "java/lang/Object", 1}, {"javax/microedition/io/SocketConnection", "javax/microedition/io/StreamConnection", 1}, {"javax/microedition/io/SockIn", "java/io/InputStream", 1}, {"javax/microedition/io/SockOut", "java/io/OutputStream", 1}, {"java/util/TimerTask", "java/lang/Object", 1}, {"javax/microedition/media/MediaException", "java/io/IOException", 0}, {"javax/microedition/media/Control", "java/lang/Object", 0}, {"javax/microedition/media/control/VolumeControl", "javax/microedition/media/Control", 0}, {"javax/microedition/media/Player", "java/lang/Object", 1}, {"javax/microedition/media/Manager", "java/lang/Object", 0}, {"javax/microedition/media/PlayerListener", "java/lang/Object", 0},
  {"java/lang/Object", 0, 0}, {"java/lang/Class", "java/lang/Object", 1}, {"java/lang/Thread", "java/lang/Object", 3},
  {"java/lang/IllegalMonitorStateException", "java/lang/RuntimeException", 0}, {"java/lang/IllegalThreadStateException", "java/lang/IllegalArgumentException", 0}, {"java/lang/Throwable", "java/lang/Object", 2}, {"java/lang/Exception", "java/lang/Throwable", 0},
  {"java/lang/Error", "java/lang/Throwable", 0}, {"java/lang/RuntimeException", "java/lang/Exception", 0},
  {"java/lang/IllegalArgumentException", "java/lang/RuntimeException", 0}, {"java/lang/IllegalStateException", "java/lang/RuntimeException", 0},
  {"java/lang/NullPointerException", "java/lang/RuntimeException", 0}, {"java/lang/ArithmeticException", "java/lang/RuntimeException", 0},
  {"java/lang/IndexOutOfBoundsException", "java/lang/RuntimeException", 0}, {"java/lang/ArrayIndexOutOfBoundsException", "java/lang/IndexOutOfBoundsException", 0},
  {"java/lang/StringIndexOutOfBoundsException", "java/lang/IndexOutOfBoundsException", 0}, {"java/lang/ClassCastException", "java/lang/RuntimeException", 0},
  {"java/lang/NegativeArraySizeException", "java/lang/RuntimeException", 0}, {"java/lang/NumberFormatException", "java/lang/IllegalArgumentException", 0},
  {"java/lang/ArrayStoreException", "java/lang/RuntimeException", 0}, {"java/lang/InterruptedException", "java/lang/Exception", 0},
  {"java/io/IOException", "java/lang/Exception", 0}, {"java/lang/OutOfMemoryError", "java/lang/Error", 0},
  {"java/util/NoSuchElementException", "java/lang/RuntimeException", 0}, {"java/util/EmptyStackException", "java/lang/RuntimeException", 0},
  {"java/lang/String", "java/lang/Object", 3}, {"java/lang/StringBuffer", "java/lang/Object", 3}, {"java/lang/StringBuilder", "java/lang/Object", 3},
  {"java/lang/Integer", "java/lang/Object", 1}, {"java/lang/Byte", "java/lang/Object", 1}, {"java/lang/Long", "java/lang/Object", 1}, {"java/lang/Boolean", "java/lang/Object", 1},
  {"java/lang/Character", "java/lang/Object", 1}, {"java/io/PrintStream", "java/lang/Object", 0}, {"java/util/Random", "java/lang/Object", 1},
  {"java/util/Vector", "java/lang/Object", 3}, {"java/util/Stack", "java/util/Vector", 0}, {"java/util/ArrayList", "java/lang/Object", 3},
  {"java/util/Hashtable", "java/lang/Object", 3}, {"javax/microedition/lcdui/ImageItem", "javax/microedition/lcdui/Item", 2}, {"javax/microedition/lcdui/Spacer", "javax/microedition/lcdui/Item", 2}, {"javax/microedition/lcdui/DateField", "javax/microedition/lcdui/Item", 2}, {"javax/microedition/lcdui/Ticker", "java/lang/Object", 2}, {"java/util/Date", "java/lang/Object", 1}, {"java/util/Calendar", "java/lang/Object", 1}, {"java/util/EnumImpl", "java/lang/Object", 3}, {"javax/microedition/io/ConnectionNotFoundException", "java/io/IOException", 0}, {"javax/microedition/io/Connector", "java/lang/Object", 0}, {"javax/microedition/io/HttpConnection", "java/lang/Object", 1}, {"java/util/HashMap", "java/lang/Object", 3},
  {"java/io/EOFException", "java/io/IOException", 0}, {"java/io/UTFDataFormatException", "java/io/IOException", 0}, {"java/util/Arrays", "java/lang/Object", 0},
  {"java/io/InputStream", "java/lang/Object", 4}, {"java/io/ByteArrayInputStream", "java/io/InputStream", 4}, {"java/io/DataInputStream", "java/io/InputStream", 4},
  {"java/io/OutputStream", "java/lang/Object", 3}, {"java/io/ByteArrayOutputStream", "java/io/OutputStream", 3}, {"java/io/DataOutputStream", "java/io/OutputStream", 3},
  {"javax/microedition/midlet/MIDlet", "java/lang/Object", 2}, {"javax/microedition/lcdui/Displayable", "java/lang/Object", 4}, {"javax/microedition/lcdui/Canvas", "javax/microedition/lcdui/Displayable", 4},
  {"javax/microedition/lcdui/game/GameCanvas", "javax/microedition/lcdui/Canvas", 4}, {"javax/microedition/lcdui/Graphics", "java/lang/Object", 12}, {"javax/microedition/lcdui/Image", "java/lang/Object", 6},
  {"javax/microedition/lcdui/Font", "java/lang/Object", 3}, {"javax/microedition/lcdui/Command", "java/lang/Object", 3}, {"javax/microedition/lcdui/Display", "java/lang/Object", 2},
  {"javax/microedition/rms/RecordStore", "java/lang/Object", 3}, {"javax/microedition/rms/RecordEnumeration", "java/lang/Object", 3},
  {"javax/microedition/rms/RecordStoreException", "java/lang/Exception", 0}, {"javax/microedition/rms/RecordStoreNotFoundException", "javax/microedition/rms/RecordStoreException", 0},
  {"javax/microedition/rms/RecordStoreNotOpenException", "javax/microedition/rms/RecordStoreException", 0}, {"javax/microedition/rms/InvalidRecordIDException", "javax/microedition/rms/RecordStoreException", 0},
  {"javax/microedition/rms/RecordStoreFullException", "javax/microedition/rms/RecordStoreException", 0},
  {"java/lang/Runtime", "java/lang/Object", 0}, {"java/lang/ClassNotFoundException", "java/lang/Exception", 0},
  {"javax/microedition/lcdui/List", "javax/microedition/lcdui/Displayable", 5}, {"javax/microedition/lcdui/Alert", "javax/microedition/lcdui/Displayable", 4},
  {"javax/microedition/lcdui/Form", "javax/microedition/lcdui/Displayable", 4}, {"javax/microedition/lcdui/TextBox", "javax/microedition/lcdui/Displayable", 4},
  {"javax/microedition/lcdui/Item", "java/lang/Object", 2}, {"javax/microedition/lcdui/ChoiceGroup", "javax/microedition/lcdui/Item", 5}, {"javax/microedition/lcdui/TextField", "javax/microedition/lcdui/Item", 4},
  {"javax/microedition/lcdui/StringItem", "javax/microedition/lcdui/Item", 2}, {"javax/microedition/lcdui/Gauge", "javax/microedition/lcdui/Item", 2}, {"javax/microedition/lcdui/AlertType", "java/lang/Object", 0},
  {"com/nokia/mid/ui/DeviceControl", "java/lang/Object", 0},
};

static void attachNatives(Class *c) {
  int n = 0; for (int i = 0; i < nrows; i++) if (!strcmp(rows[i].cls, c->name)) n++;
  c->methods = calloc(n + 1, sizeof(Method)); c->nmethods = 0;
  for (int i = 0; i < nrows; i++) if (!strcmp(rows[i].cls, c->name)) {
    Method *m = &c->methods[c->nmethods++];
    m->cls = c; m->name = rows[i].name; m->desc = rows[i].desc; m->acc = 0x100 | (rows[i].isStatic ? 8 : 0);
    m->argSlots = argSlotsOf(m->desc, &m->retSlots) + (rows[i].isStatic ? 0 : 1); m->native = rows[i].fn;
  }
}

static Class *makeBuiltin(const char *name) {
  Class *c = calloc(1, sizeof(Class)); c->name = strdup(name); c->initState = 2; c->builtin = 1;
  const char *sup = "java/lang/Object"; int ni = 0;
  for (size_t i = 0; i < sizeof bdefs / sizeof *bdefs; i++) if (!strcmp(bdefs[i].name, name)) { sup = bdefs[i].super; ni = bdefs[i].nInst; }
  classes[nclasses++] = c;
  if (strcmp(name, "java/lang/Object")) c->super = loadClass(sup ? sup : "java/lang/Object");
  c->nInst = ni > (c->super ? c->super->nInst : 0) ? ni : (c->super ? c->super->nInst : 0);
  c->statics = calloc(4, sizeof(Slot));
  attachNatives(c);
  return c;
}

static Class *parseClass(const uint8_t *b) {
  if (r32(b) != 0xCAFEBABE) die("không phải .class", 0);
  Class *c = calloc(1, sizeof(Class));
  const uint8_t *p = b + 8;
  int n = r16(p); p += 2;
  c->ncp = n; c->cp = calloc(n, sizeof(Cp));
  for (int i = 1; i < n; i++) {
    uint8_t t = *p++; c->cp[i].tag = t;
    switch (t) {
      case CP_UTF8: { int l = r16(p); p += 2; char *s = malloc(l + 1); memcpy(s, p, l); s[l] = 0; c->cp[i].u.s = s; p += l; break; }
      case CP_INT: c->cp[i].u.i = (int32_t)r32(p); p += 4; break;
      case CP_FLOAT: { uint32_t v = r32(p); memcpy(&c->cp[i].u.f, &v, 4); p += 4; break; }
      case CP_LONG: { uint64_t v = ((uint64_t)r32(p) << 32) | r32(p + 4); c->cp[i].u.l = (int64_t)v; p += 8; i++; break; }
      case CP_DOUBLE: { uint64_t v = ((uint64_t)r32(p) << 32) | r32(p + 4); memcpy(&c->cp[i].u.d, &v, 8); p += 8; i++; break; }
      case CP_CLASS: case CP_STRING: c->cp[i].u.r.a = r16(p); p += 2; break;
      case CP_FIELD: case CP_METHOD: case CP_IMETHOD: case CP_NAT: c->cp[i].u.r.a = r16(p); c->cp[i].u.r.b = r16(p + 2); p += 4; break;
      case 15: p += 3; break; case 16: p += 2; break; case 18: p += 4; break;
      default: die("hằng số không hỗ trợ", 0);
    }
  }
  p += 2;
  c->name = c->cp[c->cp[r16(p)].u.r.a].u.s; p += 2;
  classes[nclasses++] = c;
  int sup = r16(p); p += 2;
  if (sup) c->super = loadClass(c->cp[c->cp[sup].u.r.a].u.s);
  int ni = r16(p); p += 2;
  c->ifaces = calloc(ni + 1, sizeof(Class *)); c->nifaces = ni;
  for (int i = 0; i < ni; i++) { c->ifaces[i] = loadClass(c->cp[c->cp[r16(p)].u.r.a].u.s); p += 2; }
  c->nfields = r16(p); p += 2;
  c->fields = calloc(c->nfields + 1, sizeof(Field));
  c->nInst = c->super ? c->super->nInst : 0;
  int ns = 0;
  for (int i = 0; i < c->nfields; i++) {
    Field *f = &c->fields[i];
    f->acc = r16(p); f->name = c->cp[r16(p + 2)].u.s; f->desc = c->cp[r16(p + 4)].u.s;
    f->wide = f->desc[0] == 'J' || f->desc[0] == 'D';
    int na = r16(p + 6); p += 8;
    for (int a = 0; a < na; a++) p += 6 + r32(p + 2);
    if (f->acc & 8) f->slot = ns++; else f->slot = c->nInst++;
  }
  c->statics = calloc(ns + 1, sizeof(Slot));
  c->nmethods = r16(p); p += 2;
  c->methods = calloc(c->nmethods + 1, sizeof(Method));
  for (int i = 0; i < c->nmethods; i++) {
    Method *m = &c->methods[i];
    m->cls = c; m->acc = r16(p); m->name = c->cp[r16(p + 2)].u.s; m->desc = c->cp[r16(p + 4)].u.s;
    m->argSlots = argSlotsOf(m->desc, &m->retSlots);
    if (!(m->acc & 8)) m->argSlots++;
    int na = r16(p + 6); p += 8;
    for (int a = 0; a < na; a++) {
      const char *an = c->cp[r16(p)].u.s; uint32_t al = r32(p + 2);
      if (!strcmp(an, "Code")) {
        const uint8_t *q = p + 6;
        m->maxStack = r16(q); m->maxLocals = r16(q + 2); m->codeLen = r32(q + 4);
        m->code = malloc(m->codeLen); memcpy(m->code, q + 8, m->codeLen);
        q += 8 + m->codeLen; m->nexc = r16(q); q += 2;
        m->exc = calloc(m->nexc + 1, sizeof(ExcEntry));
        for (int e = 0; e < m->nexc; e++) { m->exc[e].start = r16(q); m->exc[e].end = r16(q + 2); m->exc[e].handler = r16(q + 4); m->exc[e].type = r16(q + 6); q += 8; }
      }
      p += 6 + al;
    }
  }
  return c;
}

Class *loadClass(const char *name) {
  for (int i = 0; i < nclasses; i++) if (!strcmp(classes[i]->name, name)) return classes[i];
  char path[512]; snprintf(path, sizeof path, "%s/%s.class", cpdir, name);
  FILE *f = fopen(path, "rb");
  if (!f) return makeBuiltin(name);
  fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
  uint8_t *b = malloc(n); if (fread(b, 1, n, f) != (size_t)n) die("đọc lỗi", path); fclose(f);
  return parseClass(b);
}

Method *findMethod(Class *c, const char *name, const char *desc) {
  for (; c; c = c->super)
    for (int i = 0; i < c->nmethods; i++)
      if (!strcmp(c->methods[i].name, name) && !strcmp(c->methods[i].desc, desc)) return &c->methods[i];
  return 0;
}
int subOf(Class *c, Class *t) {
  for (; c; c = c->super) { if (c == t) return 1; for (int i = 0; i < c->nifaces; i++) if (subOf(c->ifaces[i], t)) return 1; }
  return 0;
}

// ---------------- đối tượng / chuỗi ----------------
Obj *newObj(Class *c) { Obj *o = calloc(1, sizeof(Obj) + c->nInst * sizeof(Slot)); o->cls = c; return o; }
Arr *newArr(int len, int esz) { Arr *a = calloc(1, sizeof(Arr) + (size_t)len * esz + 8); a->cls = arrCls; a->len = len; a->esz = esz; return a; }
static Class *strCls;
Obj *newStr16(const uint16_t *c, int n) {
  if (!strCls) strCls = loadClass("java/lang/String");
  Obj *o = newObj(strCls); uint16_t *d = malloc((n + 1) * 2); if (n) memcpy(d, c, n * 2); d[n] = 0;
  o->f[0].a = d; o->f[1].i = n; return o;
}
Obj *newStr(const char *s) {
  size_t L = strlen(s); uint16_t *t = malloc((L + 1) * 2); int n = 0;
  for (size_t i = 0; i < L;) {
    uint8_t ch = s[i];
    if (ch < 0x80) { t[n++] = ch; i++; }
    else if ((ch & 0xE0) == 0xC0 && i + 1 < L) { t[n++] = ((ch & 31) << 6) | (s[i + 1] & 63); i += 2; }
    else if (i + 2 < L) { t[n++] = ((ch & 15) << 12) | ((s[i + 1] & 63) << 6) | (s[i + 2] & 63); i += 3; }
    else i++;
  }
  Obj *o = newStr16(t, n); free(t); return o;
}
void jprintStr(Obj *s, FILE *f) {
  if (!s) { fputs("null", f); return; }
  for (int i = 0; i < S_LEN(s); i++) {
    uint16_t c = S_CH(s)[i];
    if (c < 0x80) fputc(c, f); else if (c < 0x800) { fputc(0xC0 | (c >> 6), f); fputc(0x80 | (c & 63), f); }
    else { fputc(0xE0 | (c >> 12), f); fputc(0x80 | ((c >> 6) & 63), f); fputc(0x80 | (c & 63), f); }
  }
}
static void traceHere(const char *what, const char *msg);
void throwNew(const char *cls, const char *msg) {
  traceHere(cls, msg);
  Obj *e = newObj(loadClass(cls)); if (msg) e->f[0].a = newStr(msg); g_exc = e;
}

// ---------------- phân giải ----------------
typedef struct { Field *f; Class *owner; } FieldRef;
typedef struct { Method *tm; Class *icCls; Method *icTgt; } Site;

static void resolveField(Class *cur, int idx, FieldRef *out) {
  Cp *e = &cur->cp[idx];
  Class *oc = loadClass(cur->cp[cur->cp[e->u.r.a].u.r.a].u.s);
  Cp *nt = &cur->cp[e->u.r.b];
  const char *name = cur->cp[nt->u.r.a].u.s, *desc = cur->cp[nt->u.r.b].u.s;
  for (Class *c = oc; c; c = c->super)
    for (int i = 0; i < c->nfields; i++)
      if (!strcmp(c->fields[i].name, name) && !strcmp(c->fields[i].desc, desc)) { out->f = &c->fields[i]; out->owner = c; return; }
  if (oc->builtin) { Field *f = calloc(1, sizeof(Field)); f->name = name; f->desc = desc; f->slot = 0; out->f = f; out->owner = oc; return; }
  die("không thấy trường", name);
}

typedef struct Frame { Method *m; Slot *loc; Slot *sp; uint8_t *pc; void *lock; } Frame;
#define MAXF 3000
enum { TS_RUN, TS_SLEEP, TS_WAIT, TS_REACQ, TS_BLOCK, TS_JOIN, TS_DONE };
typedef struct Thread {
  Frame *fs; int nfs; Slot *arena, *top; Obj *jobj; int state; int64_t wakeAt; void *waitObj; int savedCount;
  struct Thread *joinTarget; int daemon, interrupted, pend, id;
} Thread;
static Thread *curT; static Thread *threads[256]; static int nthreads;
static int g_trace = -1;
// JVM_TRACE=1: in chuỗi phương thức đang chạy mỗi khi ném ngoại lệ từ native (để dò lỗi)
static void traceHere(const char *what, const char *msg) {
  if (g_trace < 0) g_trace = getenv("JVM_TRACE") != 0;
  if (!g_trace || !curT) return;
  fprintf(stderr, "[throw %s: %s]", what, msg ? msg : "");
  if (curT->nfs > 0) { Frame *f = &curT->fs[curT->nfs - 1]; fprintf(stderr, "@%ld", (long)(f->pc - f->m->code)); }
  for (int i = curT->nfs - 1, k = 0; i >= 0 && k < 6; i--, k++) { Method *m = curT->fs[i].m; fprintf(stderr, " <- %s.%s%s", m->cls->name, m->name, m->desc); }
  fprintf(stderr, "\n");
}


#define frames (curT->fs)
#define nf (curT->nfs)
#define gTop (curT->top)
static int monEnter(void *o, int force);
static int g_yield, g_budget, nestDepth;
int g_retry; // native yêu cầu chạy lại lệnh gọi sau ms mili giây (chờ không chặn các luồng khác)
int vmRetry(int ms);
#define BUDGET 4000

static int ensureInit(Class *c, Slot *sp) {
  if (c->initState == 2 || c->initState == 1) return 0;
  if (c->super && c->super->initState == 0 && ensureInit(c->super, sp)) return 1; // siêu lớp có <clinit>: chạy trước, lệnh sẽ được thực thi lại
  c->initState = 1;
  Method *m = 0;
  for (int i = 0; i < c->nmethods; i++) if (!strcmp(c->methods[i].name, "<clinit>")) m = &c->methods[i];
  if (!m) { c->initState = 2; return 0; }
  if (nf >= MAXF) die("tràn ngăn xếp", 0);
  Frame *nfp = &frames[nf++];
  nfp->m = m; nfp->loc = sp; nfp->sp = sp + m->maxLocals; nfp->pc = m->code; nfp->lock = 0;
  return 1;
}


static __attribute__((noinline, cold)) void thr(const char *cls, const char *msg) { throwNew(cls, msg); }
static __attribute__((noinline, cold)) void thrIdx(int i, int n) { char b[96]; snprintf(b, sizeof b, "Index %d out of bounds for length %d", i, n); throwNew("java/lang/ArrayIndexOutOfBoundsException", b); }

static void monExit(void *o);
static __attribute__((noinline)) int doUnwind(int base, int firstFlag) {
  Obj *ex = g_exc; int first = firstFlag;
  for (;;) {
    Frame *f = &frames[nf - 1]; Method *fm = f->m;
    int off = first ? (int)(f->pc - fm->code) : (int)(f->pc - fm->code) - 1; first = 0;
    for (int i = 0; i < fm->nexc; i++) {
      ExcEntry *h = &fm->exc[i];
      if (off < h->start || off >= h->end) continue;
      if (h->type) { Class *k = loadClass(fm->cls->cp[fm->cls->cp[h->type].u.r.a].u.s); if (!subOf(ex->cls, k)) continue; }
      g_exc = 0;
      f->sp = f->loc + fm->maxLocals; f->sp++->a = ex; f->pc = fm->code + h->handler;
      return 1;
    }
    if (fm->cls->initState == 1 && !strcmp(fm->name, "<clinit>")) fm->cls->initState = 2;
    if (f->lock) monExit(f->lock);
    nf--;
    if (nf == base) return 0; // g_exc vẫn đặt: người gọi xử lý
  }
}

// interp: chạy cho đến khi số khung giảm về [base]. Trả về khi hết khung hoặc có ngoại lệ chưa bắt (g_exc != 0).
static int interp(int base) {
  static void *disp[256]; static int inited = 0;
  Frame *fr = 0; Method *m = 0; Slot *loc = 0, *sp = 0; uint8_t *pc = 0, *code = 0; Class *cc = 0;
#define PUSHI(v) (sp++->i = (v))
#define POPI() ((--sp)->i)
#define NEXT goto *disp[*pc]
#define SAVE() (fr->sp = sp, fr->pc = pc)
#define LOADF() (fr = &frames[nf - 1], m = fr->m, loc = fr->loc, sp = fr->sp, pc = fr->pc, code = m->code, cc = m->cls)
#define THROW(cls, msg) do { SAVE(); thr(cls, msg); UNWIND(); } while (0)
#define UNWIND() do { if (doUnwind(base, 1)) { LOADF(); NEXT; } return 0; } while (0)
#define YIELD() do { SAVE(); return 1; } while (0)
#define THROWI(i, n) do { SAVE(); thrIdx(i, n); UNWIND(); } while (0)
  if (!inited) {
    inited = 1;
    for (int i = 0; i < 256; i++) disp[i] = &&L_bad;
#define OP(n, l) disp[n] = &&l
    OP(0, L_nop); OP(1, L_aconst_null);
    for (int i = 2; i <= 8; i++) disp[i] = &&L_iconst;
    OP(9, L_lconst); OP(10, L_lconst); OP(11, L_fconst); OP(12, L_fconst); OP(13, L_fconst); OP(14, L_dconst); OP(15, L_dconst);
    OP(16, L_bipush); OP(17, L_sipush); OP(18, L_ldc); OP(19, L_ldc_w); OP(20, L_ldc2_w);
    OP(21, L_iload); OP(22, L_lload); OP(23, L_iload); OP(24, L_lload); OP(25, L_iload);
    for (int i = 26; i <= 29; i++) disp[i] = &&L_iload_n;
    for (int i = 30; i <= 33; i++) disp[i] = &&L_lload_n;
    for (int i = 34; i <= 37; i++) disp[i] = &&L_iload_n;
    for (int i = 38; i <= 41; i++) disp[i] = &&L_lload_n;
    for (int i = 42; i <= 45; i++) disp[i] = &&L_iload_n;
    OP(46, L_iaload); OP(47, L_laload); OP(48, L_faload); OP(49, L_daload); OP(50, L_aaload); OP(51, L_baload); OP(52, L_caload); OP(53, L_saload);
    OP(54, L_istore); OP(55, L_lstore); OP(56, L_istore); OP(57, L_lstore); OP(58, L_istore);
    for (int i = 59; i <= 62; i++) disp[i] = &&L_istore_n;
    for (int i = 63; i <= 66; i++) disp[i] = &&L_lstore_n;
    for (int i = 67; i <= 70; i++) disp[i] = &&L_istore_n;
    for (int i = 71; i <= 74; i++) disp[i] = &&L_lstore_n;
    for (int i = 75; i <= 78; i++) disp[i] = &&L_istore_n;
    OP(79, L_iastore); OP(80, L_lastore); OP(81, L_fastore); OP(82, L_dastore); OP(83, L_aastore); OP(84, L_bastore); OP(85, L_castore); OP(86, L_sastore);
    OP(87, L_pop); OP(88, L_pop2); OP(89, L_dup); OP(90, L_dup_x1); OP(91, L_dup_x2); OP(92, L_dup2); OP(93, L_dup2_x1); OP(94, L_dup2_x2); OP(95, L_swap);
    OP(96, L_iadd); OP(97, L_ladd); OP(98, L_fadd); OP(99, L_dadd); OP(100, L_isub); OP(101, L_lsub); OP(102, L_fsub); OP(103, L_dsub);
    OP(104, L_imul); OP(105, L_lmul); OP(106, L_fmul); OP(107, L_dmul); OP(108, L_idiv); OP(109, L_ldiv); OP(110, L_fdiv); OP(111, L_ddiv);
    OP(112, L_irem); OP(113, L_lrem); OP(114, L_frem); OP(115, L_drem); OP(116, L_ineg); OP(117, L_lneg); OP(118, L_fneg); OP(119, L_dneg);
    OP(120, L_ishl); OP(121, L_lshl); OP(122, L_ishr); OP(123, L_lshr); OP(124, L_iushr); OP(125, L_lushr);
    OP(126, L_iand); OP(127, L_land); OP(128, L_ior); OP(129, L_lor); OP(130, L_ixor); OP(131, L_lxor); OP(132, L_iinc);
    OP(133, L_i2l); OP(134, L_i2f); OP(135, L_i2d); OP(136, L_l2i); OP(137, L_l2f); OP(138, L_l2d); OP(139, L_f2i); OP(140, L_f2l); OP(141, L_f2d);
    OP(142, L_d2i); OP(143, L_d2l); OP(144, L_d2f); OP(145, L_i2b); OP(146, L_i2c); OP(147, L_i2s);
    OP(148, L_lcmp); OP(149, L_fcmpl); OP(150, L_fcmpg); OP(151, L_dcmpl); OP(152, L_dcmpg);
    for (int i = 153; i <= 158; i++) disp[i] = &&L_if0;
    for (int i = 159; i <= 164; i++) disp[i] = &&L_ificmp;
    OP(165, L_ifacmpeq); OP(166, L_ifacmpne); OP(167, L_goto); OP(170, L_tableswitch); OP(171, L_lookupswitch);
    OP(172, L_ret1); OP(173, L_ret2); OP(174, L_ret1); OP(175, L_ret2); OP(176, L_ret1); OP(177, L_ret0);
    OP(178, L_getstatic); OP(179, L_putstatic); OP(180, L_getfield); OP(181, L_putfield);
    OP(182, L_invoke); OP(183, L_invoke); OP(184, L_invoke); OP(185, L_invoke);
    OP(187, L_new); OP(188, L_newarray); OP(189, L_anewarray); OP(190, L_arraylength); OP(191, L_athrow);
    OP(192, L_checkcast); OP(193, L_instanceof); OP(194, L_monenter); OP(195, L_monexit); OP(196, L_wide); OP(197, L_multianewarray);
    OP(198, L_ifnull); OP(199, L_ifnonnull); OP(200, L_goto_w);
    return 0;
  }
  LOADF();
  if (curT->pend) { curT->pend = 0; throwNew("java/lang/InterruptedException", 0); if (doUnwind(base, 0)) { LOADF(); } else return 0; }
  NEXT;
  L_bad: { char ob[200]; snprintf(ob, sizeof ob, "opcode %d tại %s.%s", *pc, m->cls->name, m->name); die("opcode chưa hỗ trợ", ob); }
  L_nop: pc++; NEXT;
  L_aconst_null: sp++->a = 0; pc++; NEXT;
  L_iconst: PUSHI(*pc - 3); pc++; NEXT;
  L_lconst: sp->l = *pc - 9; sp += 2; pc++; NEXT;
  L_fconst: sp++->f = (float)(*pc - 11); pc++; NEXT;
  L_dconst: sp->d = (double)(*pc - 14); sp += 2; pc++; NEXT;
  L_bipush: PUSHI((int8_t)pc[1]); pc += 2; NEXT;
  L_sipush: PUSHI((int16_t)r16(pc + 1)); pc += 3; NEXT;
  L_ldc: L_ldc_w: {
    int w = *pc == 18; int idx = w ? pc[1] : r16(pc + 1); Cp *e = &cc->cp[idx];
    if (e->tag == CP_INT) PUSHI(e->u.i); else if (e->tag == CP_FLOAT) sp++->f = e->u.f;
    else if (e->tag == CP_STRING) { if (!e->cache) e->cache = newStr(cc->cp[e->u.r.a].u.s); sp++->a = e->cache; }
    else if (e->tag == CP_CLASS) { if (!e->cobj) { Obj *co = newObj(loadClass("java/lang/Class")); co->f[0].a = loadClass(cc->cp[e->u.r.a].u.s); e->cobj = co; } sp++->a = e->cobj; }
    else sp++->a = 0;
    pc += w ? 2 : 3; NEXT; }
  L_ldc2_w: { Cp *e = &cc->cp[r16(pc + 1)]; if (e->tag == CP_LONG) sp->l = e->u.l; else sp->d = e->u.d; sp += 2; pc += 3; NEXT; }
  L_iload: sp++->l = loc[pc[1]].l; pc += 2; NEXT;
  L_lload: sp->l = loc[pc[1]].l; sp += 2; pc += 2; NEXT;
  L_iload_n: { int n = (*pc - 26) & 3; sp++->l = loc[n].l; pc++; NEXT; }
  L_lload_n: { int n = (*pc - 30) & 3; sp->l = loc[n].l; sp += 2; pc++; NEXT; }
  L_istore: loc[pc[1]].l = (--sp)->l; pc += 2; NEXT;
  L_lstore: sp -= 2; loc[pc[1]].l = sp->l; pc += 2; NEXT;
  L_istore_n: { int n = (*pc - 59) & 3; loc[n].l = (--sp)->l; pc++; NEXT; }
  L_lstore_n: { int n = (*pc - 63) & 3; sp -= 2; loc[n].l = sp->l; pc++; NEXT; }
#define ARRCHK(a, i) if (__builtin_expect(!(a), 0)) THROW("java/lang/NullPointerException", 0); \
  if (__builtin_expect((uint32_t)(i) >= (uint32_t)(a)->len, 0)) THROWI(i, (a)->len);
#define ALOAD(label, T, push) label: { int i = POPI(); Arr *a = (--sp)->a; ARRCHK(a, i); push(((T *)a->d)[i]); pc++; NEXT; }
#define PI(v) PUSHI(v)
#define PA(v) (sp++->a = (void *)(v))
#define PF(v) (sp++->f = (v))
#define PL(v) (sp->l = (v), sp += 2)
#define PD(v) (sp->d = (v), sp += 2)
  ALOAD(L_iaload, int32_t, PI) ALOAD(L_baload, int8_t, PI) ALOAD(L_caload, uint16_t, PI) ALOAD(L_saload, int16_t, PI)
  ALOAD(L_faload, float, PF) ALOAD(L_aaload, void *, PA) ALOAD(L_laload, int64_t, PL) ALOAD(L_daload, double, PD)
  L_iastore: L_fastore: { int32_t v = sp[-1].i; int i = sp[-2].i; Arr *a = sp[-3].a; sp -= 3; ARRCHK(a, i); ((int32_t *)a->d)[i] = v; pc++; NEXT; }
  L_aastore: { void *v = sp[-1].a; int i = sp[-2].i; Arr *a = sp[-3].a; sp -= 3; ARRCHK(a, i); ((void **)a->d)[i] = v; pc++; NEXT; }
  L_bastore: { int32_t v = sp[-1].i; int i = sp[-2].i; Arr *a = sp[-3].a; sp -= 3; ARRCHK(a, i); ((int8_t *)a->d)[i] = (int8_t)v; pc++; NEXT; }
  L_castore: L_sastore: { int32_t v = sp[-1].i; int i = sp[-2].i; Arr *a = sp[-3].a; sp -= 3; ARRCHK(a, i); ((int16_t *)a->d)[i] = (int16_t)v; pc++; NEXT; }
  L_lastore: L_dastore: { int64_t v = sp[-2].l; int i = sp[-3].i; Arr *a = sp[-4].a; sp -= 4; ARRCHK(a, i); ((int64_t *)a->d)[i] = v; pc++; NEXT; }
  L_pop: sp--; pc++; NEXT;
  L_pop2: sp -= 2; pc++; NEXT;
  L_dup: sp[0] = sp[-1]; sp++; pc++; NEXT;
  L_dup_x1: { Slot a = sp[-1], b = sp[-2]; sp[-2] = a; sp[-1] = b; sp[0] = a; sp++; pc++; NEXT; }
  L_dup_x2: { Slot a = sp[-1], b = sp[-2], c = sp[-3]; sp[-3] = a; sp[-2] = c; sp[-1] = b; sp[0] = a; sp++; pc++; NEXT; }
  L_dup2: sp[0] = sp[-2]; sp[1] = sp[-1]; sp += 2; pc++; NEXT;
  L_dup2_x1: { Slot a = sp[-1], b = sp[-2], c = sp[-3]; sp[-3] = b; sp[-2] = a; sp[-1] = c; sp[0] = b; sp[1] = a; sp += 2; pc++; NEXT; }
  L_dup2_x2: { Slot a = sp[-1], b = sp[-2], c = sp[-3], d = sp[-4]; sp[-4] = b; sp[-3] = a; sp[-2] = d; sp[-1] = c; sp[0] = b; sp[1] = a; sp += 2; pc++; NEXT; }
  L_swap: { Slot t = sp[-1]; sp[-1] = sp[-2]; sp[-2] = t; pc++; NEXT; }
#define BINI(label, expr) label: { int32_t b = sp[-1].i, a = sp[-2].i; sp--; sp[-1].i = (expr); pc++; NEXT; }
#define BINL(label, expr) label: { int64_t b = sp[-2].l, a = sp[-4].l; sp -= 2; sp[-2].l = (expr); pc++; NEXT; }
#define BINF(label, expr) label: { float b = sp[-1].f, a = sp[-2].f; sp--; sp[-1].f = (expr); pc++; NEXT; }
#define BIND(label, expr) label: { double b = sp[-2].d, a = sp[-4].d; sp -= 2; sp[-2].d = (expr); pc++; NEXT; }
  BINI(L_iadd, (int32_t)((uint32_t)a + (uint32_t)b)) BINI(L_isub, (int32_t)((uint32_t)a - (uint32_t)b)) BINI(L_imul, (int32_t)((uint32_t)a * (uint32_t)b))
  BINI(L_iand, a & b) BINI(L_ior, a | b) BINI(L_ixor, a ^ b)
  BINI(L_ishl, (int32_t)((uint32_t)a << (b & 31))) BINI(L_ishr, a >> (b & 31)) BINI(L_iushr, (int32_t)((uint32_t)a >> (b & 31)))
  L_idiv: { int32_t b = sp[-1].i, a = sp[-2].i; if (!b) THROW("java/lang/ArithmeticException", "/ by zero"); sp--; sp[-1].i = (b == -1) ? (int32_t)(0u - (uint32_t)a) : a / b; pc++; NEXT; }
  L_irem: { int32_t b = sp[-1].i, a = sp[-2].i; if (!b) THROW("java/lang/ArithmeticException", "/ by zero"); sp--; sp[-1].i = (b == -1) ? 0 : a % b; pc++; NEXT; }
  BINL(L_ladd, (int64_t)((uint64_t)a + (uint64_t)b)) BINL(L_lsub, (int64_t)((uint64_t)a - (uint64_t)b)) BINL(L_lmul, (int64_t)((uint64_t)a * (uint64_t)b))
  BINL(L_land, a & b) BINL(L_lor, a | b) BINL(L_lxor, a ^ b)
  L_ldiv: { int64_t b = sp[-2].l, a = sp[-4].l; if (!b) THROW("java/lang/ArithmeticException", "/ by zero"); sp -= 2; sp[-2].l = (b == -1) ? (int64_t)(0ull - (uint64_t)a) : a / b; pc++; NEXT; }
  L_lrem: { int64_t b = sp[-2].l, a = sp[-4].l; if (!b) THROW("java/lang/ArithmeticException", "/ by zero"); sp -= 2; sp[-2].l = (b == -1) ? 0 : a % b; pc++; NEXT; }
  L_lshl: { int sh = sp[-1].i & 63; sp--; sp[-2].l = (int64_t)((uint64_t)sp[-2].l << sh); pc++; NEXT; }
  L_lshr: { int sh = sp[-1].i & 63; sp--; sp[-2].l = sp[-2].l >> sh; pc++; NEXT; }
  L_lushr: { int sh = sp[-1].i & 63; sp--; sp[-2].l = (int64_t)((uint64_t)sp[-2].l >> sh); pc++; NEXT; }
  BINF(L_fadd, a + b) BINF(L_fsub, a - b) BINF(L_fmul, a * b) BINF(L_fdiv, a / b) BINF(L_frem, fmodf(a, b))
  BIND(L_dadd, a + b) BIND(L_dsub, a - b) BIND(L_dmul, a * b) BIND(L_ddiv, a / b) BIND(L_drem, fmod(a, b))
  L_ineg: sp[-1].i = (int32_t)(0u - (uint32_t)sp[-1].i); pc++; NEXT;
  L_lneg: sp[-2].l = (int64_t)(0ull - (uint64_t)sp[-2].l); pc++; NEXT;
  L_fneg: sp[-1].f = -sp[-1].f; pc++; NEXT;
  L_dneg: sp[-2].d = -sp[-2].d; pc++; NEXT;
  L_iinc: loc[pc[1]].i += (int8_t)pc[2]; pc += 3; NEXT;
  L_i2l: sp[-1].l = (int64_t)sp[-1].i; sp++; pc++; NEXT;
  L_i2f: sp[-1].f = (float)sp[-1].i; pc++; NEXT;
  L_i2d: sp[-1].d = (double)sp[-1].i; sp++; pc++; NEXT;
  L_l2i: sp--; sp[-1].i = (int32_t)sp[-1].l; pc++; NEXT;
  L_l2f: { float f = (float)sp[-2].l; sp--; sp[-1].f = f; pc++; NEXT; }
  L_l2d: sp[-2].d = (double)sp[-2].l; pc++; NEXT;
  L_f2i: { float f = sp[-1].f; sp[-1].i = f != f ? 0 : f >= 2147483648.0f ? INT32_MAX : f <= -2147483648.0f ? INT32_MIN : (int32_t)f; pc++; NEXT; }
  L_f2l: { float f = sp[-1].f; sp[-1].l = f != f ? 0 : f >= 9.223372e18f ? INT64_MAX : f <= -9.223372e18f ? INT64_MIN : (int64_t)f; sp++; pc++; NEXT; }
  L_f2d: sp[-1].d = (double)sp[-1].f; sp++; pc++; NEXT;
  L_d2i: { double d = sp[-2].d; sp--; sp[-1].i = d != d ? 0 : d >= 2147483647.0 ? INT32_MAX : d <= -2147483648.0 ? INT32_MIN : (int32_t)d; pc++; NEXT; }
  L_d2l: { double d = sp[-2].d; sp[-2].l = d != d ? 0 : d >= 9.223372036854775807e18 ? INT64_MAX : d <= -9.223372036854775808e18 ? INT64_MIN : (int64_t)d; pc++; NEXT; }
  L_d2f: { float f = (float)sp[-2].d; sp--; sp[-1].f = f; pc++; NEXT; }
  L_i2b: sp[-1].i = (int8_t)sp[-1].i; pc++; NEXT;
  L_i2c: sp[-1].i = (uint16_t)sp[-1].i; pc++; NEXT;
  L_i2s: sp[-1].i = (int16_t)sp[-1].i; pc++; NEXT;
  L_lcmp: { int64_t b = sp[-2].l, a = sp[-4].l; sp -= 3; sp[-1].i = a < b ? -1 : a > b ? 1 : 0; pc++; NEXT; }
  L_fcmpl: L_fcmpg: { float b = sp[-1].f, a = sp[-2].f; sp--; sp[-1].i = (a != a || b != b) ? (*pc == 150 ? 1 : -1) : a < b ? -1 : a > b ? 1 : 0; pc++; NEXT; }
  L_dcmpl: L_dcmpg: { double b = sp[-2].d, a = sp[-4].d; sp -= 3; sp[-1].i = (a != a || b != b) ? (*pc == 152 ? 1 : -1) : a < b ? -1 : a > b ? 1 : 0; pc++; NEXT; }
  L_if0: { int v = POPI(); int op = *pc - 153; int t = op == 0 ? v == 0 : op == 1 ? v != 0 : op == 2 ? v < 0 : op == 3 ? v >= 0 : op == 4 ? v > 0 : v <= 0; pc += t ? (int16_t)r16(pc + 1) : 3; NEXT; }
  L_ificmp: { int b = sp[-1].i, a = sp[-2].i; sp -= 2; int op = *pc - 159; int t = op == 0 ? a == b : op == 1 ? a != b : op == 2 ? a < b : op == 3 ? a >= b : op == 4 ? a > b : a <= b; pc += t ? (int16_t)r16(pc + 1) : 3; NEXT; }
  L_ifacmpeq: { void *b = sp[-1].a, *a = sp[-2].a; sp -= 2; pc += a == b ? (int16_t)r16(pc + 1) : 3; NEXT; }
  L_ifacmpne: { void *b = sp[-1].a, *a = sp[-2].a; sp -= 2; pc += a != b ? (int16_t)r16(pc + 1) : 3; NEXT; }
  L_ifnull: { void *a = (--sp)->a; pc += a == 0 ? (int16_t)r16(pc + 1) : 3; NEXT; }
  L_ifnonnull: { void *a = (--sp)->a; pc += a != 0 ? (int16_t)r16(pc + 1) : 3; NEXT; }
  L_goto: { int16_t off = (int16_t)r16(pc + 1); pc += off; if (off < 0 && base == 0 && --g_budget <= 0) { g_budget = BUDGET; YIELD(); } NEXT; }
  L_goto_w: pc += (int32_t)r32(pc + 1); NEXT;
  L_tableswitch: { uint8_t *b0 = pc; uint8_t *q = pc + 1; q += (4 - ((q - code) & 3)) & 3; int32_t def = (int32_t)r32(q), lo = (int32_t)r32(q + 4), hi = (int32_t)r32(q + 8); int v = POPI(); pc = b0 + (v < lo || v > hi ? def : (int32_t)r32(q + 12 + 4 * (v - lo))); NEXT; }
  L_lookupswitch: { uint8_t *b0 = pc; uint8_t *q = pc + 1; q += (4 - ((q - code) & 3)) & 3; int32_t def = (int32_t)r32(q), n = (int32_t)r32(q + 4); int v = POPI(); int32_t off = def; for (int i = 0; i < n; i++) if ((int32_t)r32(q + 8 + 8 * i) == v) { off = (int32_t)r32(q + 12 + 8 * i); break; } pc = b0 + off; NEXT; }
  L_wide: { int op = pc[1]; int idx = r16(pc + 2);
    if (op == 132) { loc[idx].i += (int16_t)r16(pc + 4); pc += 6; NEXT; }
    if (op >= 21 && op <= 25) { if (op == 22 || op == 24) { sp->l = loc[idx].l; sp += 2; } else sp++->l = loc[idx].l; pc += 4; NEXT; }
    if (op >= 54 && op <= 58) { if (op == 55 || op == 57) { sp -= 2; loc[idx].l = sp->l; } else loc[idx].l = (--sp)->l; pc += 4; NEXT; }
    goto L_bad; }
  L_ret0: L_ret1: L_ret2: {
    int rs = *pc == 177 ? 0 : (*pc == 173 || *pc == 175) ? 2 : 1;
    Slot rv = rs ? sp[-rs] : (Slot){0};
    if (m->cls->initState == 1 && !strcmp(m->name, "<clinit>")) m->cls->initState = 2;
    Slot *b0 = loc;
    if (fr->lock) monExit(fr->lock);
    nf--;
    if (nf == base) { if (rs) b0->l = rv.l; return 0; }
    LOADF(); sp = b0; if (rs) { sp->l = rv.l; sp += rs; }
    NEXT; }
  L_getstatic: L_putstatic: {
    FieldRef *r = (FieldRef *)cc->cp[r16(pc + 1)].cache;
    if (!r) { r = malloc(sizeof *r); resolveField(cc, r16(pc + 1), r); cc->cp[r16(pc + 1)].cache = r; }
    if (r->owner->initState != 2) { SAVE(); if (ensureInit(r->owner, sp)) { LOADF(); NEXT; } }
    Slot *sv = &r->owner->statics[r->f->slot];
    if (*pc == 178) { if (r->owner->builtin && !strcmp(r->f->name, "out")) { sv->a = sv->a ? sv->a : newObj(loadClass("java/io/PrintStream")); } if (r->f->wide) { sp->l = sv->l; sp += 2; } else sp++->l = sv->l; }
    else { if (r->f->wide) { sp -= 2; sv->l = sp->l; } else sv->l = (--sp)->l; }
    pc += 3; NEXT; }
  L_getfield: { FieldRef *r = (FieldRef *)cc->cp[r16(pc + 1)].cache;
    if (!r) { r = malloc(sizeof *r); resolveField(cc, r16(pc + 1), r); cc->cp[r16(pc + 1)].cache = r; }
    Obj *o = sp[-1].a; if (!o) THROW("java/lang/NullPointerException", r->f->name);
    sp[-1].l = o->f[r->f->slot].l; if (r->f->wide) sp++; pc += 3; NEXT; }
  L_putfield: { FieldRef *r = (FieldRef *)cc->cp[r16(pc + 1)].cache;
    if (!r) { r = malloc(sizeof *r); resolveField(cc, r16(pc + 1), r); cc->cp[r16(pc + 1)].cache = r; }
    int w = r->f->wide; Obj *o = sp[-1 - (w ? 2 : 1)].a; if (!o) THROW("java/lang/NullPointerException", r->f->name);
    o->f[r->f->slot].l = sp[-(w ? 2 : 1)].l; sp -= w ? 3 : 2; pc += 3; NEXT; }
  L_new: { Cp *e = &cc->cp[r16(pc + 1)]; Class *k = (Class *)e->cache; if (!k) { k = loadClass(cc->cp[e->u.r.a].u.s); e->cache = k; }
    if (k->initState != 2) { SAVE(); if (ensureInit(k, sp)) { LOADF(); NEXT; } }
    sp++->a = newObj(k); pc += 3; NEXT; }
  L_newarray: { int t = pc[1]; int len = POPI(); if (len < 0) THROW("java/lang/NegativeArraySizeException", 0); int esz = (t == 4 || t == 8) ? 1 : (t == 5 || t == 9) ? 2 : (t == 7 || t == 11) ? 8 : 4; sp++->a = newArr(len, esz); pc += 2; NEXT; }
  L_anewarray: { int len = POPI(); if (len < 0) THROW("java/lang/NegativeArraySizeException", 0); sp++->a = newArr(len, sizeof(void *)); pc += 3; NEXT; }
  L_multianewarray: { int dims = pc[3]; const char *d = cc->cp[cc->cp[r16(pc + 1)].u.r.a].u.s; int sz[8]; for (int i = dims - 1; i >= 0; i--) sz[i] = POPI();
    // d như "[[I": phần tử cuối cùng quyết định kích thước
    int depth = 0; while (d[depth] == '[') depth++; char leaf = d[depth];
    int lesz = (leaf == 'B' || leaf == 'Z') ? 1 : (leaf == 'C' || leaf == 'S') ? 2 : (leaf == 'J' || leaf == 'D') ? 8 : (leaf == 'I' || leaf == 'F') ? 4 : 8;
    // dựng đệ quy bằng ngăn xếp cục bộ
    Arr *root = newArr(sz[0], depth == 1 ? lesz : 8);
    if (dims > 1) { Arr **lv = (Arr **)&root; (void)lv;
      // lặp theo từng chiều
      Arr **cur = malloc(sizeof(Arr *)); cur[0] = root; long ncur = 1;
      for (int dm = 1; dm < dims; dm++) {
        long tot = 0; for (long i = 0; i < ncur; i++) tot += cur[i]->len;
        Arr **nx = malloc((tot ? tot : 1) * sizeof(Arr *)); long k = 0;
        for (long i = 0; i < ncur; i++) for (int j = 0; j < cur[i]->len; j++) { Arr *c = newArr(sz[dm], dm == depth - 1 ? lesz : 8); ((void **)cur[i]->d)[j] = c; nx[k++] = c; }
        free(cur); cur = nx; ncur = tot;
      }
      free(cur);
    }
    sp++->a = root; pc += 4; NEXT; }
  L_arraylength: { Arr *a = sp[-1].a; if (!a) THROW("java/lang/NullPointerException", 0); sp[-1].i = a->len; pc++; NEXT; }
  L_checkcast: { Obj *o = sp[-1].a; if (o && o->cls != arrCls) { Cp *e = &cc->cp[r16(pc + 1)]; Class *k = (Class *)e->cache;
      if (!k) { const char *nm = cc->cp[e->u.r.a].u.s; if (nm[0] == '[') { pc += 3; NEXT; } k = loadClass(nm); e->cache = k; }
      if (!subOf(o->cls, k) && ((!o->cls->builtin && !k->builtin) || (o->cls->builtin && k->builtin && o->cls->nmethods && k->nmethods))) { THROW("java/lang/ClassCastException", o->cls->name); } }
    pc += 3; NEXT; }
  L_instanceof: { Obj *o = sp[-1].a; Cp *e = &cc->cp[r16(pc + 1)]; Class *k = (Class *)e->cache; if (!k) { const char *nm = cc->cp[e->u.r.a].u.s; if (nm[0] == '[') { sp[-1].i = o && o->cls == arrCls; pc += 3; NEXT; } k = loadClass(nm); e->cache = k; } sp[-1].i = o && o->cls != arrCls && subOf(o->cls, k); pc += 3; NEXT; }
  L_monenter: { void *o = sp[-1].a; if (!o) THROW("java/lang/NullPointerException", 0);
    if (!monEnter(o, base != 0)) { curT->state = TS_BLOCK; curT->waitObj = o; YIELD(); }
    sp--; pc++; NEXT; }
  L_monexit: { void *o = sp[-1].a; if (o) monExit(o); sp--; pc++; NEXT; }
  L_athrow: { Obj *o = sp[-1].a; SAVE(); if (!o) { throwNew("java/lang/NullPointerException", 0); } else g_exc = o; UNWIND(); }
  L_invoke: {
    if (base == 0 && --g_budget <= 0) { g_budget = BUDGET; YIELD(); }
    int op = *pc; Cp *e = &cc->cp[r16(pc + 1)];
    Site *st = (Site *)e->cache;
    if (!st) {
      st = calloc(1, sizeof *st);
      Class *oc = loadClass(cc->cp[cc->cp[e->u.r.a].u.r.a].u.s);
      Cp *nt = &cc->cp[e->u.r.b];
      const char *name = cc->cp[nt->u.r.a].u.s, *desc = cc->cp[nt->u.r.b].u.s;
      Method *tm = findMethod(oc, name, desc);
      if (!tm) { // phương thức thư viện chưa cài
        tm = calloc(1, sizeof(Method)); tm->cls = oc; tm->name = name; tm->desc = desc; tm->acc = 0x100 | (op == 184 ? 8 : 0);
        tm->argSlots = argSlotsOf(desc, &tm->retSlots) + (op == 184 ? 0 : 1);
        if (!oc->builtin) { fflush(stdout); jlogf("không thấy phương thức %s.%s%s\n", oc->name, name, desc); }
      }
      st->tm = tm; e->cache = st;
    }
    Method *tm = st->tm; int ilen = op == 185 ? 5 : 3;
    { static int dbg = -1; if (dbg < 0) dbg = getenv("JVM_CALLS") != 0; if (dbg && !tm->cls->builtin) fprintf(stderr, "CALL %s.%s%s\n", tm->cls->name, tm->name, tm->desc); else if (dbg) fprintf(stderr, "NAT %s.%s\n", tm->cls->name, tm->name); }
    if (op == 184 && tm->cls->initState != 2) { SAVE(); if (ensureInit(tm->cls, sp)) { LOADF(); NEXT; } }
    if (op != 184) {
      Obj *recv = sp[-tm->argSlots].a;
      if (!recv) THROW("java/lang/NullPointerException", tm->name);
      if (op != 183 && recv->cls != tm->cls && recv->cls != arrCls) {
        if (st->icCls == recv->cls) tm = st->icTgt;
        else { Method *v = findMethod(recv->cls, tm->name, tm->desc); if (v) tm = v; st->icCls = recv->cls; st->icTgt = tm; }
      }
    }
    if (tm->native || (tm->acc & 0x100)) {
      if (!tm->native) { // chưa cài: bỏ qua, trả 0/null
        static char seen[4096]; (void)seen; fflush(stdout);
        { static Method *seenM[128]; static int ns; int dup = 0; for (int q = 0; q < ns; q++) if (seenM[q] == tm) dup = 1; if (!dup) { if (ns < 128) seenM[ns++] = tm; jlogf("[chưa cài] %s.%s%s\n", tm->cls->name, tm->name, tm->desc); } }
        sp -= tm->argSlots; if (tm->retSlots) { sp->l = 0; sp += tm->retSlots; } pc += ilen; NEXT;
      }
      Slot *a = sp - tm->argSlots; gTop = sp; SAVE();
      Slot a0 = a[0]; tm->native(a);
      if (g_retry) { g_retry = 0; a[0] = a0; sp = a + tm->argSlots; SAVE(); return 1; }
      if (g_exc) { sp = a; UNWIND(); }
      sp = a + tm->retSlots; pc += ilen;
      if (g_yield) { g_yield = 0; SAVE(); return 1; }
      NEXT;
    }
    void *lk = 0;
    if (tm->acc & 0x20) { lk = (tm->acc & 8) ? (void *)tm->cls : sp[-tm->argSlots].a; if (!monEnter(lk, base != 0)) { curT->state = TS_BLOCK; curT->waitObj = lk; YIELD(); } }
    if (nf >= MAXF) { THROW("java/lang/StackOverflowError", 0); }
    fr->sp = sp - tm->argSlots; fr->pc = pc + ilen;
    fr = &frames[nf++]; fr->m = tm; fr->loc = sp - tm->argSlots; fr->sp = fr->loc + tm->maxLocals; fr->pc = tm->code; fr->lock = lk;
    m = tm; loc = fr->loc; sp = fr->sp; pc = fr->pc; code = m->code; cc = m->cls; NEXT; }

}

// ---------------- gọi lồng nhau từ native ----------------
Slot callMethod(Method *m, Slot *args, int nargs) {
  Slot r; r.l = 0;
  if (m->native) { Slot tmp[16]; memcpy(tmp, args, nargs * sizeof(Slot)); m->native(tmp); return tmp[0]; }
  Slot *top = gTop;
  if (nf >= MAXF) { throwNew("java/lang/StackOverflowError", 0); return r; }
  Frame *f = &frames[nf++]; f->m = m; f->loc = top; f->sp = top + m->maxLocals; f->pc = m->code; f->lock = 0;
  memcpy(top, args, nargs * sizeof(Slot));
  Slot *savedTop = gTop; Thread *me = curT;
  nestDepth++;
  interp(nf - 1);
  nestDepth--;
  curT = me; gTop = savedTop;
  if (!g_exc) r = top[0];
  return r;
}

int jhash(Obj *a) {
  if (!a) return 0;
  if (a->cls->name[10] == 'S' && !strcmp(a->cls->name, "java/lang/String")) {
    if (a->f[2].i) return a->f[2].i; uint32_t h = 0; for (int i = 0; i < S_LEN(a); i++) h = 31 * h + S_CH(a)[i]; a->f[2].i = (int32_t)h; return (int32_t)h; }
  if (!strcmp(a->cls->name, "java/lang/Integer")) return a->f[0].i;
  if (!strcmp(a->cls->name, "java/lang/Long")) return (int32_t)(a->f[0].l ^ ((uint64_t)a->f[0].l >> 32));
  Method *m = findMethod(a->cls, "hashCode", "()I");
  if (m && !m->native) { Slot ar[1]; ar[0].a = a; Slot r = callMethod(m, ar, 1); return r.i; }
  return (int32_t)(((uintptr_t)a) >> 4);
}
int jequals(Obj *a, Obj *b) {
  if (a == b) return 1; if (!a || !b) return 0;
  if (!strcmp(a->cls->name, "java/lang/String")) {
    if (a->cls != b->cls || S_LEN(a) != S_LEN(b)) return 0; return !memcmp(S_CH(a), S_CH(b), S_LEN(a) * 2); }
  if (!strcmp(a->cls->name, "java/lang/Integer") || !strcmp(a->cls->name, "java/lang/Long")) return a->cls == b->cls && a->f[0].l == b->f[0].l;
  Method *m = findMethod(a->cls, "equals", "(Ljava/lang/Object;)Z");
  if (m && !m->native) { Slot ar[2]; ar[0].a = a; ar[1].a = b; Slot r = callMethod(m, ar, 2); return r.i; }
  return 0;
}


// ---------------- monitor ----------------
typedef struct Mon { void *obj; Thread *owner; int count; struct Mon *next; } Mon;
static Mon *montab[1024];
static Mon *monFind(void *o, int create) {
  unsigned h = (unsigned)(((uintptr_t)o) >> 4) % 1024; Mon *m;
  for (m = montab[h]; m; m = m->next) if (m->obj == o) return m;
  if (!create) return 0;
  m = calloc(1, sizeof *m); m->obj = o; m->next = montab[h]; montab[h] = m; return m;
}
static int monEnter(void *o, int force) {
  Mon *m = monFind(o, 1);
  if (!m->owner || m->owner == curT || force) { if (m->owner != curT) { m->owner = curT; m->count = 0; } m->count++; return 1; }
  return 0;
}
static void monExit(void *o) { Mon *m = monFind(o, 0); if (m && m->owner == curT && --m->count <= 0) { m->owner = 0; m->count = 0; } }

// ---------------- luồng ----------------
int64_t nowMs(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (int64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000; }
#define STACKSLOTS (256 * 1024)
static Thread *newThread(Method *entry, Slot *args, int nargs, Obj *jobj) {
  Thread *t = calloc(1, sizeof *t);
  t->fs = calloc(MAXF + 1, sizeof(Frame)); t->arena = calloc(STACKSLOTS, sizeof(Slot)); t->top = t->arena;
  Frame *f = &t->fs[0]; f->m = entry; f->loc = t->arena; f->sp = t->arena + entry->maxLocals; f->pc = entry->code; f->lock = 0;
  memcpy(t->arena, args, nargs * sizeof(Slot)); t->nfs = 1; t->state = TS_RUN; t->jobj = jobj; t->id = nthreads;
  if (nthreads >= 256) die("quá nhiều luồng", 0);
  threads[nthreads++] = t; return t;
}
static Class *threadCls;
static Obj *threadObj(Thread *t) { if (!t->jobj) { t->jobj = newObj(threadCls ? threadCls : (threadCls = loadClass("java/lang/Thread"))); t->jobj->f[1].a = t; } return t->jobj; }

static void printUncaught(Thread *t) {
  fflush(stdout); jlogf("Exception in thread \"Thread-%d\" %s", t->id, g_exc->cls->name);
  if (g_exc->f[0].a && g_exc->cls->nInst) { jlogf(": "); jlogStr(g_exc->f[0].a); }
  jlogf("\n"); g_exc = 0;
}

// Chạy bộ điều phối cho đến khi [until] xong (nếu có) hoặc hết luồng không-daemon hoặc quá hạn.
void (*g_idle)(void);
volatile int g_stop; int g_keepAlive;
extern int g_destroyed;
static void schedule(Thread *until, int64_t deadline) {
  int last = -1;
  for (;;) {
    if (g_stop || (g_destroyed && !until)) return;
    if (g_idle) g_idle();
    if (until && until->state == TS_DONE) return;
    int64_t now = nowMs(); if (deadline && now >= deadline) return;
    int alive = 0; Thread *pick = 0; int64_t earliest = 0;
    for (int k = 1; k <= nthreads; k++) {
      int i = (last + k) % nthreads; Thread *t = threads[i];
      if (t->state == TS_DONE) continue;
      if (!t->daemon) alive++;
      switch (t->state) {
        case TS_SLEEP: if (now >= t->wakeAt) t->state = TS_RUN; else if (!earliest || t->wakeAt < earliest) earliest = t->wakeAt; break;
        case TS_WAIT: if (t->wakeAt) { if (now >= t->wakeAt) t->state = TS_REACQ; else if (!earliest || t->wakeAt < earliest) earliest = t->wakeAt; } break;
        case TS_JOIN: if (t->joinTarget->state == TS_DONE) t->state = TS_RUN; break;
        default: break;
      }
      if (t->state == TS_REACQ || t->state == TS_BLOCK) {
        Mon *m = monFind(t->waitObj, 1);
        if (!m->owner) { if (t->state == TS_REACQ) { m->owner = t; m->count = t->savedCount; } t->state = TS_RUN; }
      }
      if (t->state == TS_RUN && !pick) { pick = t; last = i; }
    }
    if (!alive && !until && !g_keepAlive) return; // MIDlet (g_keepAlive) sống tới khi notifyDestroyed / dừng
    if (!pick) {
      if (earliest) { int64_t d = earliest - nowMs(); if (deadline && earliest > deadline) d = deadline - nowMs(); if (d > 0) { struct timespec ts = {d / 1000, (d % 1000) * 1000000}; nanosleep(&ts, 0); } continue; }
      if (until) return; // kẹt (deadlock)
      if (g_keepAlive) { struct timespec ts = {0, 2000000}; nanosleep(&ts, 0); continue; } // MIDlet: chờ sự kiện
      fflush(stdout); jlogf("[deadlock: mọi luồng đều chờ]\n"); return;
    }
    curT = pick; g_budget = BUDGET;
    int r = interp(0);
    if (r == 0 || pick->nfs == 0) { if (g_exc) printUncaught(pick); pick->state = TS_DONE; }
  }
}

// Luồng sự kiện dùng lại được (paint, phím, ...): khởi chạy một phương thức trên luồng [t] đã xong.
void *evThreadNew(void) { Method dummy; (void)dummy; Thread *t = calloc(1, sizeof *t); t->fs = calloc(MAXF + 1, sizeof(Frame)); t->arena = calloc(STACKSLOTS, sizeof(Slot)); t->top = t->arena; t->state = TS_DONE; t->daemon = 1; t->id = nthreads; if (nthreads >= 256) die("quá nhiều luồng", 0); threads[nthreads++] = t; return t; }
int evThreadBusy(void *p) { return ((Thread *)p)->state != TS_DONE; }
void evThreadRun(void *p, Method *entry, Slot *args, int nargs) {
  Thread *t = p; Frame *f = &t->fs[0]; f->m = entry; f->loc = t->arena; f->sp = t->arena + entry->maxLocals; f->pc = entry->code; f->lock = 0;
  memcpy(t->arena, args, nargs * sizeof(Slot)); t->nfs = 1; t->top = t->arena; t->state = TS_RUN; t->interrupted = 0; t->pend = 0;
}

// ---- native cho Thread / Object.wait,notify ----
static void th_init(Slot *a) { Obj *o = a[0].a; o->f[0].a = 0; }
static void th_initR(Slot *a) { Obj *o = a[0].a; o->f[0].a = a[1].a; }
static void th_run(Slot *a) { (void)a; }
static void th_start(Slot *a) {
  Obj *to = a[0].a;
  if (to->f[1].a) { throwNew("java/lang/IllegalThreadStateException", 0); return; }
  Method *rm = findMethod(to->cls, "run", "()V"); Slot arg; arg.a = to;
  if (rm && rm->native) { Obj *tg = to->f[0].a; if (!tg) { Thread *t = calloc(1, sizeof *t); t->state = TS_DONE; to->f[1].a = t; return; } rm = findMethod(tg->cls, "run", "()V"); arg.a = tg; }
  if (!rm || rm->native) { throwNew("java/lang/RuntimeException", "Thread.run"); return; }
  Thread *t = newThread(rm, &arg, 1, to); to->f[1].a = t;
}
int vmRetry(int ms) { if (nestDepth || !curT) return 0; g_retry = 1; curT->state = TS_SLEEP; curT->wakeAt = nowMs() + ms; return 1; }
static void th_join(Slot *a) { Thread *t = ((Obj *)a[0].a)->f[1].a; if (!t || t->state == TS_DONE || nestDepth) return; curT->state = TS_JOIN; curT->joinTarget = t; g_yield = 1; }
static void th_joinJ(Slot *a) { th_join(a); }
static void th_sleep(Slot *a) {
  int64_t ms = a[0].l; if (ms < 0) ms = 0;
  if (nestDepth) { struct timespec ts = {ms / 1000, (ms % 1000) * 1000000}; nanosleep(&ts, 0); return; }
  curT->state = TS_SLEEP; curT->wakeAt = nowMs() + ms; g_yield = 1;
}
static void th_yield(Slot *a) { (void)a; if (!nestDepth) g_yield = 1; }
static void th_current(Slot *a) { a[0].a = threadObj(curT); }
static void th_nop(Slot *a) { (void)a; }
static void th_prio(Slot *a) { a[0].i = 5; }
static void th_setDaemon(Slot *a) { Thread *t = ((Obj *)a[0].a)->f[1].a; if (t) t->daemon = a[1].i; }
static void th_isAlive(Slot *a) { Thread *t = ((Obj *)a[0].a)->f[1].a; a[0].i = t && t->state != TS_DONE; }
static void th_interrupt(Slot *a) { Thread *t = ((Obj *)a[0].a)->f[1].a; if (!t) return; t->interrupted = 1; if (t->state == TS_SLEEP || t->state == TS_WAIT || t->state == TS_JOIN) { t->pend = 1; if (t->state == TS_WAIT) t->state = TS_REACQ; else t->state = TS_RUN; } }
static void ob_wait0(Slot *a);
static void ob_waitJ(Slot *a) {
  Obj *o = a[0].a; int64_t ms = a[1].l; Mon *m = monFind(o, 0);
  if (!m || m->owner != curT) { throwNew("java/lang/IllegalMonitorStateException", "current thread not owner"); return; }
  if (nestDepth) return;
  curT->savedCount = m->count; m->owner = 0; m->count = 0; curT->state = TS_WAIT; curT->waitObj = o; curT->wakeAt = ms > 0 ? nowMs() + ms : 0; g_yield = 1;
}
static void ob_wait0(Slot *a) { Slot b[2]; b[0] = a[0]; b[1].l = 0; ob_waitJ(b); }
static void ob_notify(Slot *a) {
  Obj *o = a[0].a; Mon *m = monFind(o, 0);
  if (!m || m->owner != curT) { throwNew("java/lang/IllegalMonitorStateException", "current thread not owner"); return; }
  for (int i = 0; i < nthreads; i++) if (threads[i]->state == TS_WAIT && threads[i]->waitObj == o) { threads[i]->state = TS_REACQ; return; }
}
static void ob_notifyAll(Slot *a) {
  Obj *o = a[0].a; Mon *m = monFind(o, 0);
  if (!m || m->owner != curT) { throwNew("java/lang/IllegalMonitorStateException", "current thread not owner"); return; }
  for (int i = 0; i < nthreads; i++) if (threads[i]->state == TS_WAIT && threads[i]->waitObj == o) threads[i]->state = TS_REACQ;
}
static void installThreadNatives(void) {
  const char *T = "java/lang/Thread", *O = "java/lang/Object";
  regNative(T, "<init>", "()V", 0, th_init); regNative(T, "<init>", "(Ljava/lang/Runnable;)V", 0, th_initR); regNative(T, "<init>", "(Ljava/lang/String;)V", 0, th_init);
  regNative(T, "start", "()V", 0, th_start); regNative(T, "run", "()V", 0, th_run); regNative(T, "join", "()V", 0, th_join); regNative(T, "join", "(J)V", 0, th_joinJ);
  regNative(T, "sleep", "(J)V", 1, th_sleep); regNative(T, "yield", "()V", 1, th_yield); regNative(T, "currentThread", "()Ljava/lang/Thread;", 1, th_current);
  regNative(T, "setPriority", "(I)V", 0, th_nop); regNative(T, "getPriority", "()I", 0, th_prio); regNative(T, "setDaemon", "(Z)V", 0, th_setDaemon);
  regNative(T, "isAlive", "()Z", 0, th_isAlive); regNative(T, "interrupt", "()V", 0, th_interrupt);
  regNative(O, "wait", "()V", 0, ob_wait0); regNative(O, "wait", "(J)V", 0, ob_waitJ); regNative(O, "notify", "()V", 0, ob_notify); regNative(O, "notifyAll", "()V", 0, ob_notifyAll);
}

// ---------------- chạy ----------------
void ioReset(void); void midpReset(void);
static void jvmResetAll(void) {
  memset(classes, 0, sizeof classes); nclasses = 0; arrCls = 0; strCls = 0; threadCls = 0; curT = 0; memset(threads, 0, sizeof threads); nthreads = 0;
  memset(montab, 0, sizeof montab); g_exc = 0; g_yield = 0; g_budget = 0; nestDepth = 0; nrows = 0; g_stop = 0; g_destroyed = 0; g_keepAlive = 1;
  ioReset(); midpReset();
}
static void initRuntime(void) {
  installNatives(); installThreadNatives(); installIO(); installMidp(); installMisc();
  arrCls = calloc(1, sizeof(Class)); arrCls->name = "[array"; arrCls->initState = 2; arrCls->builtin = 1;
  { static int once; if (!once) { once = 1; interp(0); } } // khởi tạo bảng nhảy (một lần)
}
// chạy một phương thức trong luồng mới cho đến khi xong
static int runToEnd(Method *m, Slot *args, int n, int64_t deadline) {
  Thread *t = newThread(m, args, n, 0);
  curT = t;
  // khởi tạo lớp chứa phương thức (nếu cần)
  schedule(t, deadline);
  return t->state == TS_DONE;
}

static void initClassNow(Class *k, int64_t deadline) {
  if (!k || k->initState != 0) return;
  if (k->super) initClassNow(k->super, deadline);
  Method *m = 0; for (int i = 0; i < k->nmethods; i++) if (!strcmp(k->methods[i].name, "<clinit>")) m = &k->methods[i];
  k->initState = 1;
  if (m) { Slot none[1]; none[0].l = 0; runToEnd(m, none, 0, deadline); }
  k->initState = 2;
}

#ifndef JVM_LIB
extern void (*g_frameSink)(const uint8_t *, int, int);
extern int g_frames; extern void midpKey(int, int); extern const char *g_rmsDir;
#include <sys/stat.h>
static FILE *dumpF;
static void dumpSink(const uint8_t *d, int n, int key) { (void)key; if (dumpF) { fwrite(&n, 4, 1, dumpF); fwrite(d, 1, n, dumpF); } }
static int64_t keyT0; static char *keySpec; static void (*realIdle)(void);
static void keyPump(void) { // KEYS="tms:code,..." phát phím theo thời gian (kiểm thử)
  static int idx; if (!keySpec) return; char *p = keySpec; for (int i = 0; i < idx && p; i++) { p = strchr(p, ','); if (p) p++; } if (!p || !*p) return;
  int ms, code; if (sscanf(p, "%d:%d", &ms, &code) == 2 && nowMs() - keyT0 >= ms) { midpKey(0, code); midpKey(1, code); idx++; }
}
static void idleWrap(void) { keyPump(); if (realIdle) realIdle(); }
int main(int argc, char **argv) {
  const char *mode = "main"; int ai = 1; int secs = 5;
  if (argc > 1 && !strcmp(argv[1], "-midlet")) { mode = "midlet"; ai = 2; }
  if (argc < ai + 2) { fprintf(stderr, "dùng: %s [-midlet] <thư mục lớp> <Lớp chính> [giây]\n", argv[0]); return 1; }
  cpdir = argv[ai]; if (argc > ai + 2) secs = atoi(argv[ai + 2]);
  { const char *e = getenv("RMS_DIR"); g_rmsDir = e ? e : "/tmp/jvmcore_rms"; mkdir(g_rmsDir, 0755); }
  initRuntime();
  Class *c = loadClass(argv[ai + 1]);
  threadCls = loadClass("java/lang/Thread");
  int64_t deadline = nowMs() + (int64_t)secs * 1000;
  if (!strcmp(mode, "main")) {
    Method *mm = findMethod(c, "main", "([Ljava/lang/String;)V");
    if (!mm) die("không có main", 0);
    Slot arg; arg.a = newArr(0, 8);
    initClassNow(c, 0);
    Thread *t = newThread(mm, &arg, 1, 0); curT = t;
    schedule(0, 0);
    fflush(stdout);
    return 0;
  } else {
    g_keepAlive = 1;
    const char *df = getenv("JPC_DUMP"); if (df) { dumpF = fopen(df, "wb"); g_frameSink = dumpSink; }
    keySpec = getenv("KEYS"); keyT0 = nowMs(); if (keySpec) { realIdle = g_idle; g_idle = idleWrap; }
    initClassNow(c, deadline);
    Obj *mid = newObj(c);
    Method *ctor = findMethod(c, "<init>", "()V"); Slot a1; a1.a = mid;
    if (ctor) { Thread *t = newThread(ctor, &a1, 1, 0); curT = t; schedule(t, deadline); }
    Method *sa = findMethod(c, "startApp", "()V");
    if (sa) { Thread *t = newThread(sa, &a1, 1, 0); curT = t; schedule(t, deadline); }
    schedule(0, deadline); // để các luồng game chạy tới hạn
    fflush(stdout); fprintf(stderr, "[midlet] số khung đã phát: %d\n", g_frames); if (dumpF) fclose(dumpF); return 0;
  }
}
#else
#include <sys/stat.h>
#include <unistd.h>
#define EXPORT __attribute__((visibility("default"))) __attribute__((used))
extern void (*g_frameSink)(const uint8_t *, int, int);
extern const char *g_rmsDir; extern int g_sw, g_sh;
void midpKey(int, int); void midpPointer(int, int, int); void midpSetScreen(int, int); void midpForceKey(void);

// Hàng đợi khung hình giữa luồng VM và luồng giao diện (Dart)
typedef struct { uint8_t *d; int n; } QF;
#define QCAP 96
static QF fq[QCAP]; static int fqh, fqt, fqn; static pthread_mutex_t fqmu = PTHREAD_MUTEX_INITIALIZER;
static void libSink(const uint8_t *d, int n, int key) {
  (void)key; pthread_mutex_lock(&fqmu);
  if (fqn >= QCAP) { // giao diện không kịp lấy: bỏ hết, buộc khung kế tiếp là khung chính (vẽ lại đủ)
    while (fqn) { free(fq[fqh].d); fqh = (fqh + 1) % QCAP; fqn--; } midpForceKey();
  }
  uint8_t *c = malloc(n); memcpy(c, d, n); fq[fqt].d = c; fq[fqt].n = n; fqt = (fqt + 1) % QCAP; fqn++;
  pthread_mutex_unlock(&fqmu);
}
typedef struct { char dir[600], midlet[200], rms[600]; } StartArgs;
static StartArgs g_sa; static pthread_t g_th; static volatile int g_status; // 0 chưa chạy, 1 đang chạy, 2 đã thoát, -1 lỗi
static int g_thValid;
static void *vmMain(void *p) {
  (void)p; g_err[0] = 0; g_status = 1; g_log[0] = 0; g_loglen = 0;
  jvmResetAll(); cpdir = g_sa.dir; g_rmsDir = g_sa.rms; g_frameSink = libSink;
  initRuntime();
  Class *c = loadClass(g_sa.midlet); threadCls = loadClass("java/lang/Thread");
  initClassNow(c, 0);
  Obj *mid = newObj(c); Method *ctor = findMethod(c, "<init>", "()V"); Slot a1; a1.a = mid;
  if (ctor) { Thread *t = newThread(ctor, &a1, 1, 0); curT = t; schedule(t, 0); }
  Method *sa = findMethod(c, "startApp", "()V");
  if (sa) { Thread *t = newThread(sa, &a1, 1, 0); curT = t; schedule(t, 0); }
  schedule(0, 0);
  g_status = 2; return 0;
}
static void *vmEntry(void *p) { vmMain(p); if (g_err[0]) g_status = -1; else if (g_status == 1) g_status = 2; return 0; }

// ---- API cho Dart ----
EXPORT int jvmcore_start(const char *dir, const char *midlet, const char *rms, int w, int h) {
  if (g_thValid && g_status == 1) return -1; // đang có một giả lập chạy
  if (g_thValid) { g_stop = 1; pthread_join(g_th, 0); g_thValid = 0; }
  pthread_mutex_lock(&fqmu); while (fqn) { free(fq[fqh].d); fqh = (fqh + 1) % QCAP; fqn--; } pthread_mutex_unlock(&fqmu);
  snprintf(g_sa.dir, sizeof g_sa.dir, "%s", dir); snprintf(g_sa.midlet, sizeof g_sa.midlet, "%s", midlet); snprintf(g_sa.rms, sizeof g_sa.rms, "%s", rms);
  mkdir(rms, 0755); midpSetScreen(w, h); g_status = 1; g_stop = 0;
  pthread_attr_t at; pthread_attr_init(&at); pthread_attr_setstacksize(&at, 16 * 1024 * 1024);
  if (pthread_create(&g_th, &at, vmEntry, 0)) { g_status = -1; snprintf(g_err, sizeof g_err, "không tạo được luồng VM"); return -2; }
  g_thValid = 1; return 0;
}
// Lấy một khung: 0 = chưa có, >0 = số byte đã chép, <0 = bộ đệm nhỏ (cần -n byte)
EXPORT int jvmcore_poll(uint8_t *buf, int cap) {
  int r = 0; pthread_mutex_lock(&fqmu);
  if (fqn) { QF *f = &fq[fqh]; if (f->n > cap) r = -f->n; else { memcpy(buf, f->d, f->n); r = f->n; free(f->d); fqh = (fqh + 1) % QCAP; fqn--; } }
  pthread_mutex_unlock(&fqmu); return r;
}
EXPORT int jvmcore_net_poll(uint8_t *buf, int cap) { return midpNetPoll(buf, cap); }
EXPORT void jvmcore_net_done(int id, int status, const uint8_t *h, int hl, const uint8_t *b, int bl) { midpNetDone(id, status, h, hl, b, bl); }
EXPORT int jvmcore_ui_poll(char *buf, int cap) { return midpUiPoll(buf, cap); }
EXPORT void jvmcore_ui_action(const char *s) { midpUiAction(s); }
void midpSetDraw(int on);
EXPORT void jvmcore_set_draw(int on) { midpSetDraw(on); }
EXPORT int jvmcore_sock_poll(uint8_t *b, int cap) { return midpSockPoll(b, cap); }
EXPORT void jvmcore_sock_event(int id, int kind, const uint8_t *d, int n) { midpSockEvent(id, kind, d, n); }
EXPORT void jvmcore_refresh(void) { midpForceKey(); }
EXPORT void jvmcore_key(int type, int code) { midpKey(type, code); }
EXPORT void jvmcore_pointer(int type, int x, int y) { midpPointer(type, x, y); }
EXPORT int jvmcore_status(void) { return g_status; }
EXPORT const char *jvmcore_log(void) { return g_log; }
EXPORT const char *jvmcore_error(void) { return g_err; }
EXPORT void jvmcore_stop(void) { if (g_thValid) { g_stop = 1; pthread_join(g_th, 0); g_thValid = 0; } g_status = 0; }
#endif
