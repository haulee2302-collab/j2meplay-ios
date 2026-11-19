// Lõi thông dịch JVM (giai đoạn 1): đọc .class, chạy bytecode, không GC (nguyên mẫu để đo tốc độ).
// Biên dịch: gcc -O2 -o jvm jvm.c -lm     Chạy: ./jvm <thư mục chứa .class> <Lớp chính>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>

typedef union Slot { int32_t i; int64_t l; float f; double d; void *a; } Slot;

enum { CP_UTF8 = 1, CP_INT = 3, CP_FLOAT = 4, CP_LONG = 5, CP_DOUBLE = 6, CP_CLASS = 7, CP_STRING = 8,
       CP_FIELD = 9, CP_METHOD = 10, CP_IMETHOD = 11, CP_NAT = 12 };

typedef struct Class Class;
typedef struct Method Method;

typedef struct { uint16_t start, end, handler, type; } ExcEntry;

struct Method {
  Class *cls; const char *name, *desc;
  uint16_t acc; int argSlots; int retSlots; // retSlots: 0 void, 1, 2
  int maxStack, maxLocals; uint8_t *code; int codeLen;
  ExcEntry *exc; int nexc;
};

typedef struct { const char *name, *desc; uint16_t acc; int slot; int wide; Slot sval; } Field;

typedef struct { uint8_t tag; union { const char *s; int32_t i; int64_t l; double d; float f; struct { uint16_t a, b; } r; } u; void *cache; } Cp;

struct Class {
  const char *name; Class *super; int ncp; Cp *cp;
  int nfields, nmethods; Field *fields; Method *methods;
  int nInst; Slot *statics; int initState; // 0 chưa, 1 đang, 2 xong
};

typedef struct { Class *cls; Slot f[]; } Obj;
typedef struct { Class *cls; int len; int esz; uint8_t d[]; } Arr;

static const char *cpdir;
static Class *classes[512]; static int nclasses;

static void die(const char *m, const char *a) { fprintf(stderr, "LỖI: %s %s\n", m, a ? a : ""); exit(1); }

static uint16_t r16(const uint8_t *p) { return (p[0] << 8) | p[1]; }
static uint32_t r32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]; }

static int argSlotsOf(const char *d, int *ret) {
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

static Class *loadClass(const char *name);

static Class *parseClass(const uint8_t *b, size_t len) {
  (void)len;
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
  p += 2; // access
  c->name = c->cp[c->cp[r16(p)].u.r.a].u.s; p += 2;
  int sup = r16(p); p += 2;
  if (sup) c->super = loadClass(c->cp[c->cp[sup].u.r.a].u.s);
  int ni = r16(p); p += 2 + ni * 2;
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
        m->code = (uint8_t *)malloc(m->codeLen); memcpy(m->code, q + 8, m->codeLen);
        q += 8 + m->codeLen; m->nexc = r16(q); q += 2;
        m->exc = calloc(m->nexc + 1, sizeof(ExcEntry));
        for (int e = 0; e < m->nexc; e++) { m->exc[e].start = r16(q); m->exc[e].end = r16(q + 2); m->exc[e].handler = r16(q + 4); m->exc[e].type = r16(q + 6); q += 8; }
      }
      p += 6 + al;
    }
  }
  classes[nclasses++] = c;
  return c;
}

static Class *loadClass(const char *name) {
  for (int i = 0; i < nclasses; i++) if (!strcmp(classes[i]->name, name)) return classes[i];
  char path[512]; snprintf(path, sizeof path, "%s/%s.class", cpdir, name);
  FILE *f = fopen(path, "rb");
  if (!f) {
    // lớp thư viện chưa có: lớp rỗng
    Class *c = calloc(1, sizeof(Class)); c->name = strdup(name); c->initState = 2;
    c->statics = calloc(1, sizeof(Slot)); classes[nclasses++] = c; return c;
  }
  fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
  uint8_t *b = malloc(n); if (fread(b, 1, n, f) != (size_t)n) die("đọc lỗi", path); fclose(f);
  return parseClass(b, n);
}

static Method *findMethod(Class *c, const char *name, const char *desc) {
  for (; c; c = c->super)
    for (int i = 0; i < c->nmethods; i++)
      if (!strcmp(c->methods[i].name, name) && !strcmp(c->methods[i].desc, desc)) return &c->methods[i];
  return 0;
}

static int subOf(Class *c, Class *t) { for (; c; c = c->super) if (c == t) return 1; return 0; }

// ---- đối tượng ----
static Obj *newObj(Class *c) { Obj *o = calloc(1, sizeof(Obj) + c->nInst * sizeof(Slot)); o->cls = c; return o; }
static Class *arrCls;
static Arr *newArr(int len, int esz) { Arr *a = calloc(1, sizeof(Arr) + (size_t)len * esz + 8); a->cls = arrCls; a->len = len; a->esz = esz; return a; }

// ---- tài nguyên phân giải ----
typedef struct { Field *f; Class *owner; } FieldRef;
typedef struct { Method *m; } MethRef;

static Cp *CPOOL; // tạm

static void resolveField(Class *cur, int idx, FieldRef *out) {
  Cp *e = &cur->cp[idx];
  Class *oc = loadClass(cur->cp[cur->cp[e->u.r.a].u.r.a].u.s);
  Cp *nt = &cur->cp[e->u.r.b];
  const char *name = cur->cp[nt->u.r.a].u.s, *desc = cur->cp[nt->u.r.b].u.s;
  for (Class *c = oc; c; c = c->super)
    for (int i = 0; i < c->nfields; i++)
      if (!strcmp(c->fields[i].name, name) && !strcmp(c->fields[i].desc, desc)) { out->f = &c->fields[i]; out->owner = c; return; }
  if (oc->ncp == 0) { Field *f = calloc(1, sizeof(Field)); f->name = name; f->desc = desc; f->slot = 0; out->f = f; out->owner = oc; return; }
  die("không thấy trường", name);
}

typedef struct Frame { Method *m; Slot *loc; Slot *sp; uint8_t *pc; } Frame;
#define MAXF 8192
static Frame frames[MAXF]; static int nf;
static Slot *arena; // vùng slot

static void out_s(Obj *o) { (void)o; }

static int ensureInit(Class *c, Slot **spp, Frame *fr) {
  // trả 1 nếu đã đẩy khung <clinit> (cần chạy lại lệnh)
  if (c->initState == 2) return 0;
  if (c->super && c->super->initState != 2 && c->initState == 0) return ensureInit(c->super, spp, fr);
  if (c->initState == 1) return 0;
  c->initState = 1;
  Method *m = 0;
  for (int i = 0; i < c->nmethods; i++) if (!strcmp(c->methods[i].name, "<clinit>")) m = &c->methods[i];
  if (!m) { c->initState = 2; return 0; }
  fr->sp = *spp;
  Frame *nfp = &frames[nf++];
  nfp->m = m; nfp->loc = *spp; nfp->sp = *spp + m->maxLocals; nfp->pc = m->code;
  return 1;
}
// khi <clinit> kết thúc ta đặt initState=2 ở lệnh return (kiểm tra tên)

static long long icount = 0;

static void run(Method *entry) {
  Frame *fr = 0; Method *m = 0; Slot *loc = 0, *sp = 0; uint8_t *pc = 0, *code = 0; Class *cc = 0;
#define PUSHI(v) (sp++->i = (v))
#define POPI() ((--sp)->i)
#define NEXT goto *disp[*pc]
#define SAVE() (fr->sp = sp, fr->pc = pc)
  static void *disp[256];
  static int init = 0;
  if (!init) {
    init = 1;
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
    OP(112, L_irem); OP(113, L_lrem); OP(116, L_ineg); OP(117, L_lneg); OP(118, L_fneg); OP(119, L_dneg);
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
    OP(187, L_new); OP(188, L_newarray); OP(189, L_anewarray); OP(190, L_arraylength);
    OP(192, L_checkcast); OP(193, L_instanceof); OP(194, L_nop); OP(195, L_nop); OP(198, L_ifnull); OP(199, L_ifnonnull);
    return;
  }
  fr = &frames[nf++];
  fr->m = entry; fr->loc = arena; fr->sp = arena + entry->maxLocals; fr->pc = entry->code;
  m = entry; loc = fr->loc; sp = fr->sp; pc = fr->pc; code = m->code; cc = m->cls;
  NEXT;
  L_bad: fprintf(stderr, "opcode %d chưa hỗ trợ tại %s.%s\n", *pc, m->cls->name, m->name); exit(2);
  L_nop: pc++; NEXT;
  L_aconst_null: sp++->a = 0; pc++; NEXT;
  L_iconst: PUSHI(*pc - 3); pc++; NEXT;
  L_lconst: sp->l = *pc - 9; sp += 2; pc++; NEXT;
  L_fconst: sp++->f = (float)(*pc - 11); pc++; NEXT;
  L_dconst: sp->d = (double)(*pc - 14); sp += 2; pc++; NEXT;
  L_bipush: PUSHI((int8_t)pc[1]); pc += 2; NEXT;
  L_sipush: PUSHI((int16_t)r16(pc + 1)); pc += 3; NEXT;
  L_ldc: L_ldc_w: {
    int idx = *pc == 18 ? pc[1] : r16(pc + 1); Cp *e = &cc->cp[idx];
    if (e->tag == CP_INT) PUSHI(e->u.i); else if (e->tag == CP_FLOAT) sp++->f = e->u.f;
    else if (e->tag == CP_STRING) { if (!e->cache) e->cache = newObj(loadClass("java/lang/String")); sp++->a = e->cache; }
    else sp++->a = 0;
    pc += *pc == 18 ? 2 : 3; NEXT; }
  L_ldc2_w: { Cp *e = &cc->cp[r16(pc + 1)]; if (e->tag == CP_LONG) sp->l = e->u.l; else sp->d = e->u.d; sp += 2; pc += 3; NEXT; }
  L_iload: sp++->i = loc[pc[1]].i; pc += 2; NEXT;  // iload/fload/aload (a: dùng l để không cắt con trỏ)
  L_lload: sp->l = loc[pc[1]].l; sp += 2; pc += 2; NEXT;
  L_iload_n: { int n = (*pc - 26) & 3; sp++->l = loc[n].l; pc++; NEXT; }
  L_lload_n: { int n = (*pc - 30) & 3; sp->l = loc[n].l; sp += 2; pc++; NEXT; }
  L_istore: loc[pc[1]].l = (--sp)->l; pc += 2; NEXT;
  L_lstore: sp -= 2; loc[pc[1]].l = sp->l; pc += 2; NEXT;
  L_istore_n: { int n = (*pc - 59) & 3; loc[n].l = (--sp)->l; pc++; NEXT; }
  L_lstore_n: { int n = (*pc - 63) & 3; sp -= 2; loc[n].l = sp->l; pc++; NEXT; }
#define ARRCHK(a, i) if (!(a)) { SAVE(); die("NullPointerException", 0); } if ((uint32_t)(i) >= (uint32_t)(a)->len) { SAVE(); fprintf(stderr, "ArrayIndexOutOfBounds %d tại %s.%s\n", i, m->cls->name, m->name); exit(3); }
#define ALOAD(label, T, push) label: { int i = POPI(); Arr *a = (--sp)->a; ARRCHK(a, i); push(((T *)a->d)[i]); pc++; NEXT; }
#define PI(v) PUSHI(v)
#define PA(v) (sp++->a = (void *)(v))
#define PF(v) (sp++->f = (v))
#define PL(v) (sp->l = (v), sp += 2)
#define PD(v) (sp->d = (v), sp += 2)
  ALOAD(L_iaload, int32_t, PI) ALOAD(L_baload, int8_t, PI) ALOAD(L_caload, uint16_t, PI) ALOAD(L_saload, int16_t, PI)
  ALOAD(L_faload, float, PF) ALOAD(L_aaload, void *, PA) ALOAD(L_laload, int64_t, PL) ALOAD(L_daload, double, PD)
#define ASTORE2(label, T) label: { sp -= 2; int i = sp[-1 + 0].i; (void)i; }
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
  L_idiv: { int32_t b = sp[-1].i, a = sp[-2].i; if (!b) { SAVE(); die("ArithmeticException / by zero", 0); } sp--; sp[-1].i = (b == -1) ? (int32_t)(0u - (uint32_t)a) : a / b; pc++; NEXT; }
  L_irem: { int32_t b = sp[-1].i, a = sp[-2].i; if (!b) { SAVE(); die("ArithmeticException / by zero", 0); } sp--; sp[-1].i = (b == -1) ? 0 : a % b; pc++; NEXT; }
  BINL(L_ladd, (int64_t)((uint64_t)a + (uint64_t)b)) BINL(L_lsub, (int64_t)((uint64_t)a - (uint64_t)b)) BINL(L_lmul, (int64_t)((uint64_t)a * (uint64_t)b))
  BINL(L_land, a & b) BINL(L_lor, a | b) BINL(L_lxor, a ^ b)
  L_ldiv: { int64_t b = sp[-2].l, a = sp[-4].l; if (!b) { SAVE(); die("ArithmeticException / by zero", 0); } sp -= 2; sp[-2].l = (b == -1) ? (int64_t)(0ull - (uint64_t)a) : a / b; pc++; NEXT; }
  L_lrem: { int64_t b = sp[-2].l, a = sp[-4].l; if (!b) { SAVE(); die("ArithmeticException / by zero", 0); } sp -= 2; sp[-2].l = (b == -1) ? 0 : a % b; pc++; NEXT; }
  L_lshl: { int sh = sp[-1].i & 63; sp--; sp[-2].l = (int64_t)((uint64_t)sp[-2].l << sh); pc++; NEXT; }
  L_lshr: { int sh = sp[-1].i & 63; sp--; sp[-2].l = sp[-2].l >> sh; pc++; NEXT; }
  L_lushr: { int sh = sp[-1].i & 63; sp--; sp[-2].l = (int64_t)((uint64_t)sp[-2].l >> sh); pc++; NEXT; }
  BINF(L_fadd, a + b) BINF(L_fsub, a - b) BINF(L_fmul, a * b) BINF(L_fdiv, a / b)
  BIND(L_dadd, a + b) BIND(L_dsub, a - b) BIND(L_dmul, a * b) BIND(L_ddiv, a / b)
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
  L_tableswitch: { uint8_t *base = pc; uint8_t *q = pc + 1; q += (4 - ((q - code) & 3)) & 3; int32_t def = (int32_t)r32(q), lo = (int32_t)r32(q + 4), hi = (int32_t)r32(q + 8); int v = POPI(); pc = base + (v < lo || v > hi ? def : (int32_t)r32(q + 12 + 4 * (v - lo))); NEXT; }
  L_lookupswitch: { uint8_t *base = pc; uint8_t *q = pc + 1; q += (4 - ((q - code) & 3)) & 3; int32_t def = (int32_t)r32(q), n = (int32_t)r32(q + 4); int v = POPI(); int32_t off = def; for (int i = 0; i < n; i++) if ((int32_t)r32(q + 8 + 8 * i) == v) { off = (int32_t)r32(q + 12 + 8 * i); break; } pc = base + off; NEXT; }
  L_ret0: L_ret1: L_ret2: {
    int rs = *pc == 177 ? 0 : (*pc == 173 || *pc == 175) ? 2 : 1;
    Slot rv = rs ? sp[-rs] : (Slot){0};
    if (!strcmp(m->name, "<clinit>")) m->cls->initState = 2;
    nf--;
    if (nf == 0) return;
    Slot *base = loc; fr = &frames[nf - 1];
    m = fr->m; loc = fr->loc; code = m->code; cc = m->cls; pc = fr->pc;
    sp = base; if (rs) { sp->l = rv.l; sp += rs; }
    if (*pc == 0) {} 
    NEXT; }
  L_getstatic: L_putstatic: { // pc trỏ vào lệnh; nếu cần khởi tạo lớp thì đẩy <clinit> rồi chạy lại
    FieldRef *fr2 = (FieldRef *)cc->cp[r16(pc + 1)].cache;
    if (!fr2) { fr2 = malloc(sizeof *fr2); resolveField(cc, r16(pc + 1), fr2); cc->cp[r16(pc + 1)].cache = fr2; }
    if (fr2->owner->initState != 2) { SAVE(); fr->pc = pc; if (ensureInit(fr2->owner, &sp, fr)) { fr->sp = sp; fr = &frames[nf - 1]; m = fr->m; loc = fr->loc; sp = fr->sp; pc = fr->pc; code = m->code; cc = m->cls; NEXT; } }
    Slot *sv = &fr2->owner->statics[fr2->f->slot];
    if (*pc == 178) { if (fr2->f->wide) { sp->l = sv->l; sp += 2; } else sp++->l = sv->l; }
    else { if (fr2->f->wide) { sp -= 2; sv->l = sp->l; } else sv->l = (--sp)->l; }
    pc += 3; NEXT; }
  L_getfield: { FieldRef *fr2 = (FieldRef *)cc->cp[r16(pc + 1)].cache;
    if (!fr2) { fr2 = malloc(sizeof *fr2); resolveField(cc, r16(pc + 1), fr2); cc->cp[r16(pc + 1)].cache = fr2; }
    Obj *o = sp[-1].a; if (!o) { SAVE(); die("NullPointerException getfield", fr2->f->name); }
    sp[-1].l = o->f[fr2->f->slot].l; if (fr2->f->wide) sp++; pc += 3; NEXT; }
  L_putfield: { FieldRef *fr2 = (FieldRef *)cc->cp[r16(pc + 1)].cache;
    if (!fr2) { fr2 = malloc(sizeof *fr2); resolveField(cc, r16(pc + 1), fr2); cc->cp[r16(pc + 1)].cache = fr2; }
    int w = fr2->f->wide; Obj *o = sp[-1 - (w ? 2 : 1)].a; if (!o) { SAVE(); die("NullPointerException putfield", fr2->f->name); }
    o->f[fr2->f->slot].l = sp[-(w ? 2 : 1)].l; sp -= w ? 3 : 2; pc += 3; NEXT; }
  L_new: { Cp *e = &cc->cp[r16(pc + 1)]; Class *k = (Class *)e->cache; if (!k) { k = loadClass(cc->cp[e->u.r.a].u.s); e->cache = k; }
    if (k->initState != 2) { SAVE(); fr->pc = pc; if (ensureInit(k, &sp, fr)) { fr->sp = sp; fr = &frames[nf - 1]; m = fr->m; loc = fr->loc; sp = fr->sp; pc = fr->pc; code = m->code; cc = m->cls; NEXT; } }
    sp++->a = newObj(k); pc += 3; NEXT; }
  L_newarray: { int t = pc[1]; int len = POPI(); int esz = (t == 4 || t == 8) ? 1 : (t == 5 || t == 9) ? 2 : (t == 7 || t == 11) ? 8 : 4; sp++->a = newArr(len, esz); pc += 2; NEXT; }
  L_anewarray: { int len = POPI(); sp++->a = newArr(len, sizeof(void *)); pc += 3; NEXT; }
  L_arraylength: { Arr *a = sp[-1].a; if (!a) { SAVE(); die("NullPointerException length", 0); } sp[-1].i = a->len; pc++; NEXT; }
  L_checkcast: pc += 3; NEXT;
  L_instanceof: { Obj *o = sp[-1].a; Cp *e = &cc->cp[r16(pc + 1)]; Class *k = (Class *)e->cache; if (!k) { k = loadClass(cc->cp[e->u.r.a].u.s); e->cache = k; } sp[-1].i = o && o->cls != arrCls && subOf(o->cls, k); pc += 3; NEXT; }
  L_invoke: {
    int op = *pc; int idx = r16(pc + 1);
    Cp *e = &cc->cp[idx];
    Method *tm = (Method *)e->cache;
    if (!tm) {
      Class *oc = loadClass(cc->cp[cc->cp[e->u.r.a].u.r.a].u.s);
      Cp *nt = &cc->cp[e->u.r.b];
      const char *name = cc->cp[nt->u.r.a].u.s, *desc = cc->cp[nt->u.r.b].u.s;
      tm = findMethod(oc, name, desc);
      if (!tm) {
        // phương thức thư viện (vd System.out.println): tạo giả
        tm = calloc(1, sizeof(Method)); tm->cls = oc; tm->name = name; tm->desc = desc; tm->acc = 0x100; tm->argSlots = argSlotsOf(desc, &tm->retSlots) + (op == 184 ? 0 : 1);
      }
      e->cache = tm;
    }
    if (tm->acc & 0x100) { // native/giả: println
      if (!strcmp(tm->name, "println")) {
        if (tm->desc[1] == 'J') printf("%lld\n", (long long)sp[-2].l); else if (tm->desc[1] == 'I') printf("%d\n", sp[-1].i);
        else if (tm->desc[1] == 'D') printf("%.6f\n", sp[-2].d); else printf("[obj]\n");
      }
      sp -= tm->argSlots; pc += op == 185 ? 5 : 3; NEXT;
    }
    if (op == 184 && tm->cls->initState != 2) { SAVE(); fr->pc = pc; if (ensureInit(tm->cls, &sp, fr)) { fr->sp = sp; fr = &frames[nf - 1]; m = fr->m; loc = fr->loc; sp = fr->sp; pc = fr->pc; code = m->code; cc = m->cls; NEXT; } }
    if (op == 182 || op == 185) {
      Obj *recv = sp[-tm->argSlots].a;
      if (!recv) { SAVE(); die("NullPointerException invoke", tm->name); }
      if (recv->cls != tm->cls) { Method *vm = findMethod(recv->cls, tm->name, tm->desc); if (vm) tm = vm; }
    }
    // đẩy khung mới
    fr->sp = sp - tm->argSlots; fr->pc = pc + (op == 185 ? 5 : 3);
    fr = &frames[nf++]; fr->m = tm; fr->loc = sp - tm->argSlots; fr->sp = fr->loc + tm->maxLocals; fr->pc = tm->code;
    m = tm; loc = fr->loc; sp = fr->sp; pc = fr->pc; code = m->code; cc = m->cls; NEXT; }
}

int main(int argc, char **argv) {
  if (argc < 3) { fprintf(stderr, "dùng: %s <thư mục lớp> <Lớp chính>\n", argv[0]); return 1; }
  cpdir = argv[1];
  arrCls = calloc(1, sizeof(Class)); arrCls->name = "[array"; arrCls->initState = 2;
  arena = calloc(4 << 20, sizeof(Slot));
  Class *c = loadClass(argv[2]);
  Method *mm = findMethod(c, "main", "([Ljava/lang/String;)V");
  if (!mm) die("không có main", 0);
  arena[0].a = 0;
  for (int i = 0; i < c->nmethods; i++) if (!strcmp(c->methods[i].name, "<clinit>")) { c->initState = 1; }
  c->initState = 0;
  run(0);
  run(mm);
  return 0;
}
