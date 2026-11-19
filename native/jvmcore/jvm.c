// Lõi thông dịch JVM bằng C (giai đoạn 2): ngoại lệ, chuỗi, thư viện java.lang/java.util cơ bản, gọi lồng nhau.
// Biên dịch: gcc -O2 -o jvm jvm.c natives.c -lm     Chạy: ./jvm <thư mục lớp> <Lớp chính>
#include "jvm.h"

enum { CP_UTF8 = 1, CP_INT = 3, CP_FLOAT = 4, CP_LONG = 5, CP_DOUBLE = 6, CP_CLASS = 7, CP_STRING = 8,
       CP_FIELD = 9, CP_METHOD = 10, CP_IMETHOD = 11, CP_NAT = 12 };

Obj *g_exc = 0;
Class *arrCls;
static const char *cpdir;
static Class *classes[2048]; static int nclasses;

static void die(const char *m, const char *a) { fflush(stdout); fprintf(stderr, "LỖI: %s %s\n", m, a ? a : ""); exit(1); }
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
  if (nrows == caprows) { caprows = caprows ? caprows * 2 : 512; rows = realloc(rows, caprows * sizeof(NativeRow)); }
  rows[nrows++] = (NativeRow){cls, name, desc, isStatic, fn};
}

// ---------------- lớp có sẵn ----------------
typedef struct { const char *name, *super; int nInst; } BDef;
static const BDef bdefs[] = {
  {"java/lang/Object", 0, 0}, {"java/lang/Class", "java/lang/Object", 1}, {"java/lang/Throwable", "java/lang/Object", 2}, {"java/lang/Exception", "java/lang/Throwable", 0},
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
  {"java/lang/Integer", "java/lang/Object", 1}, {"java/lang/Long", "java/lang/Object", 1}, {"java/lang/Boolean", "java/lang/Object", 1},
  {"java/lang/Character", "java/lang/Object", 1}, {"java/io/PrintStream", "java/lang/Object", 0}, {"java/util/Random", "java/lang/Object", 1},
  {"java/util/Vector", "java/lang/Object", 3}, {"java/util/Stack", "java/util/Vector", 0}, {"java/util/ArrayList", "java/lang/Object", 3},
  {"java/util/Hashtable", "java/lang/Object", 3}, {"java/util/HashMap", "java/lang/Object", 3},
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
void throwNew(const char *cls, const char *msg) {
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

typedef struct Frame { Method *m; Slot *loc; Slot *sp; uint8_t *pc; } Frame;
#define MAXF 4096
static Frame frames[MAXF]; static int nf;
static Slot *arena, *gTop;

static int ensureInit(Class *c, Slot *sp) {
  if (c->initState == 2 || c->initState == 1) return 0;
  if (c->super && c->super->initState == 0) return ensureInit(c->super, sp);
  c->initState = 1;
  Method *m = 0;
  for (int i = 0; i < c->nmethods; i++) if (!strcmp(c->methods[i].name, "<clinit>")) m = &c->methods[i];
  if (!m) { c->initState = 2; return 0; }
  if (nf >= MAXF) die("tràn ngăn xếp", 0);
  Frame *nfp = &frames[nf++];
  nfp->m = m; nfp->loc = sp; nfp->sp = sp + m->maxLocals; nfp->pc = m->code;
  return 1;
}


static __attribute__((noinline, cold)) void thr(const char *cls, const char *msg) { throwNew(cls, msg); }
static __attribute__((noinline, cold)) void thrIdx(int i, int n) { char b[96]; snprintf(b, sizeof b, "Index %d out of bounds for length %d", i, n); throwNew("java/lang/ArrayIndexOutOfBoundsException", b); }

static __attribute__((noinline)) int doUnwind(int base) {
  Obj *ex = g_exc; int first = 1;
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
    nf--;
    if (nf == base) return 0; // g_exc vẫn đặt: người gọi xử lý
  }
}

// interp: chạy cho đến khi số khung giảm về [base]. Trả về khi hết khung hoặc có ngoại lệ chưa bắt (g_exc != 0).
static void interp(int base) {
  static void *disp[256]; static int inited = 0;
  Frame *fr = 0; Method *m = 0; Slot *loc = 0, *sp = 0; uint8_t *pc = 0, *code = 0; Class *cc = 0;
#define PUSHI(v) (sp++->i = (v))
#define POPI() ((--sp)->i)
#define NEXT goto *disp[*pc]
#define SAVE() (fr->sp = sp, fr->pc = pc)
#define LOADF() (fr = &frames[nf - 1], m = fr->m, loc = fr->loc, sp = fr->sp, pc = fr->pc, code = m->code, cc = m->cls)
#define THROW(cls, msg) do { SAVE(); thr(cls, msg); UNWIND(); } while (0)
#define UNWIND() do { if (doUnwind(base)) { LOADF(); NEXT; } return; } while (0)
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
    OP(192, L_checkcast); OP(193, L_instanceof); OP(194, L_nop); OP(195, L_nop); OP(196, L_wide); OP(197, L_multianewarray);
    OP(198, L_ifnull); OP(199, L_ifnonnull); OP(200, L_goto_w);
    return;
  }
  LOADF();
  NEXT;
  L_bad: fflush(stdout); fprintf(stderr, "opcode %d chưa hỗ trợ tại %s.%s\n", *pc, m->cls->name, m->name); exit(2);
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
  L_goto: pc += (int16_t)r16(pc + 1); NEXT;
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
    nf--;
    if (nf == base) { if (rs) b0->l = rv.l; return; }
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
  L_athrow: { Obj *o = sp[-1].a; SAVE(); if (!o) { throwNew("java/lang/NullPointerException", 0); } else g_exc = o; UNWIND(); }
  L_invoke: {
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
        if (!oc->builtin) { fflush(stdout); fprintf(stderr, "không thấy phương thức %s.%s%s\n", oc->name, name, desc); }
      }
      st->tm = tm; e->cache = st;
    }
    Method *tm = st->tm; int ilen = op == 185 ? 5 : 3;
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
        fprintf(stderr, "[chưa cài] %s.%s%s\n", tm->cls->name, tm->name, tm->desc);
        sp -= tm->argSlots; if (tm->retSlots) { sp->l = 0; sp += tm->retSlots; } pc += ilen; NEXT;
      }
      Slot *a = sp - tm->argSlots; gTop = sp; SAVE();
      tm->native(a);
      if (g_exc) { sp = a; UNWIND(); }
      sp = a + tm->retSlots; pc += ilen; NEXT;
    }
    if (nf >= MAXF) { THROW("java/lang/StackOverflowError", 0); }
    fr->sp = sp - tm->argSlots; fr->pc = pc + ilen;
    fr = &frames[nf++]; fr->m = tm; fr->loc = sp - tm->argSlots; fr->sp = fr->loc + tm->maxLocals; fr->pc = tm->code;
    m = tm; loc = fr->loc; sp = fr->sp; pc = fr->pc; code = m->code; cc = m->cls; NEXT; }

}

// ---------------- gọi lồng nhau từ native ----------------
Slot callMethod(Method *m, Slot *args, int nargs) {
  Slot r; r.l = 0;
  if (m->native) { Slot tmp[16]; memcpy(tmp, args, nargs * sizeof(Slot)); m->native(tmp); return tmp[0]; }
  Slot *top = gTop;
  if (nf >= MAXF) { throwNew("java/lang/StackOverflowError", 0); return r; }
  Frame *f = &frames[nf++]; f->m = m; f->loc = top; f->sp = top + m->maxLocals; f->pc = m->code;
  memcpy(top, args, nargs * sizeof(Slot));
  Slot *savedTop = gTop;
  interp(nf - 1);
  gTop = savedTop;
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

int main(int argc, char **argv) {
  if (argc < 3) { fprintf(stderr, "dùng: %s <thư mục lớp> <Lớp chính>\n", argv[0]); return 1; }
  cpdir = argv[1];
  installNatives();
  arrCls = calloc(1, sizeof(Class)); arrCls->name = "[array"; arrCls->initState = 2; arrCls->builtin = 1;
  arena = calloc(2 << 20, sizeof(Slot)); gTop = arena;
  interp(0); // khởi tạo bảng nhảy (inited)
  Class *c = loadClass(argv[2]);
  Method *mm = findMethod(c, "main", "([Ljava/lang/String;)V");
  if (!mm) die("không có main", 0);
  if (c->initState == 0) { Slot *sp = arena; if (ensureInit(c, sp)) { interp(0); if (g_exc) goto uncaught; } }
  frames[nf].m = mm; frames[nf].loc = arena; frames[nf].sp = arena + mm->maxLocals; frames[nf].pc = mm->code; nf++;
  arena[0].a = newArr(0, 8);
  interp(0);
  if (g_exc) {
uncaught:
    fflush(stdout); fprintf(stderr, "Exception in thread \"main\" %s", g_exc->cls->name);
    if (g_exc->f[0].a) { fprintf(stderr, ": "); jprintStr(g_exc->f[0].a, stderr); }
    fprintf(stderr, "\n"); return 1;
  }
  fflush(stdout);
  return 0;
}
