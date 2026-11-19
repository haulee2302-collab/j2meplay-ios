// Thư viện Java cơ bản viết bằng C: Object, Throwable, String, StringBuilder, Integer, Long, Math, System, Vector, Hashtable, Random.
#include "jvm.h"

#define NS(cls, name, desc, fn) regNative(cls, name, desc, 1, fn)
#define NI(cls, name, desc, fn) regNative(cls, name, desc, 0, fn)
#define STR(i) ((Obj *)a[i].a)

// ---- định dạng số kiểu Java ----
static void fmtDouble(double d, char *out, int isFloat) {
  if (d != d) { strcpy(out, "NaN"); return; }
  if (isinf(d)) { strcpy(out, d < 0 ? "-Infinity" : "Infinity"); return; }
  if (d == 0) { strcpy(out, signbit(d) ? "-0.0" : "0.0"); return; }
  char buf[40]; int p;
  for (p = 1; p <= 17; p++) {
    snprintf(buf, sizeof buf, "%.*e", p - 1, d);
    if (isFloat ? (float)strtod(buf, 0) == (float)d : strtod(buf, 0) == d) break;
  }
  int neg = buf[0] == '-'; char *q = buf + neg; char digs[24]; int nd = 0;
  while (*q && *q != 'e') { if (*q != '.') digs[nd++] = *q; q++; }
  int ex = atoi(q + 1);
  while (nd > 1 && digs[nd - 1] == '0') nd--;
  char *o = out; if (neg) *o++ = '-';
  double ad = fabs(d);
  if (ad >= 1e-3 && ad < 1e7) {
    if (ex >= 0) {
      for (int i = 0; i <= ex; i++) *o++ = i < nd ? digs[i] : '0';
      *o++ = '.';
      if (nd > ex + 1) for (int i = ex + 1; i < nd; i++) *o++ = digs[i]; else *o++ = '0';
    } else {
      *o++ = '0'; *o++ = '.'; for (int i = 0; i < -ex - 1; i++) *o++ = '0'; for (int i = 0; i < nd; i++) *o++ = digs[i];
    }
    *o = 0;
  } else {
    *o++ = digs[0]; *o++ = '.'; if (nd > 1) for (int i = 1; i < nd; i++) *o++ = digs[i]; else *o++ = '0';
    sprintf(o, "E%d", ex);
  }
}

static Obj *objToString(Obj *o);

// ---- StringBuilder ----
static void sbReserve(Obj *sb, int extra) {
  int len = sb->f[1].i, cap = sb->f[2].i;
  if (len + extra + 1 > cap) { cap = (len + extra + 1) * 2; sb->f[0].a = realloc(sb->f[0].a, cap * 2); sb->f[2].i = cap; }
}
static void sbApp16(Obj *sb, const uint16_t *c, int n) { sbReserve(sb, n); memcpy((uint16_t *)sb->f[0].a + sb->f[1].i, c, n * 2); sb->f[1].i += n; }
static void sbAppC(Obj *sb, const char *s) { int n = strlen(s); sbReserve(sb, n); uint16_t *d = (uint16_t *)sb->f[0].a + sb->f[1].i; for (int i = 0; i < n; i++) d[i] = (uint8_t)s[i]; sb->f[1].i += n; }
static void sbAppStr(Obj *sb, Obj *s) { if (!s) sbAppC(sb, "null"); else sbApp16(sb, S_CH(s), S_LEN(s)); }

static Obj *objToString(Obj *o) {
  if (!o) return newStr("null");
  if (o->cls == arrCls) { char b[40]; snprintf(b, sizeof b, "[array@%x", (unsigned)(((uintptr_t)o) >> 4)); return newStr(b); }
  const char *n = o->cls->name;
  if (!strcmp(n, "java/lang/String")) return o;
  if (!strcmp(n, "java/lang/Integer")) { char b[16]; snprintf(b, sizeof b, "%d", o->f[0].i); return newStr(b); }
  if (!strcmp(n, "java/lang/Long")) { char b[24]; snprintf(b, sizeof b, "%lld", (long long)o->f[0].l); return newStr(b); }
  if (!strcmp(n, "java/lang/StringBuilder") || !strcmp(n, "java/lang/StringBuffer")) return newStr16((uint16_t *)o->f[0].a, o->f[1].i);
  Method *m = findMethod(o->cls, "toString", "()Ljava/lang/String;");
  if (m && !m->native) { Slot ar[1]; ar[0].a = o; Slot r = callMethod(m, ar, 1); return g_exc ? 0 : (Obj *)r.a; }
  if (m && m->native && strcmp(m->cls->name, "java/lang/Object")) { Slot ar[1]; ar[0].a = o; m->native(ar); return (Obj *)ar[0].a; }
  char b[160]; snprintf(b, sizeof b, "%s@%x", o->cls->name, (unsigned)(((uintptr_t)o) >> 4)); for (char *p = b; *p; p++) if (*p == '/') *p = '.';
  return newStr(b);
}

// ---- Object / Throwable ----
static void o_init(Slot *a) { (void)a; }
static void o_hash(Slot *a) { a[0].i = (int32_t)(((uintptr_t)a[0].a) >> 4); }
static void o_equals(Slot *a) { a[0].i = a[0].a == a[1].a; }
static void o_getClass(Slot *a) { Obj *o = a[0].a; Obj *c = newObj(loadClass("java/lang/Class")); c->f[0].a = o->cls; a[0].a = c; }
static void cl_getName(Slot *a) { Class *k = ((Obj *)a[0].a)->f[0].a; char b[200]; snprintf(b, sizeof b, "%s", k->name); for (char *p = b; *p; p++) if (*p == '/') *p = '.'; a[0].a = newStr(b); }
static void o_toString(Slot *a) { Obj *o = a[0].a; char b[160]; snprintf(b, sizeof b, "%s@%x", o->cls->name, (unsigned)(((uintptr_t)o) >> 4)); for (char *p = b; *p; p++) if (*p == '/') *p = '.'; a[0].a = newStr(b); }
static void t_initMsg(Slot *a) { ((Obj *)a[0].a)->f[0].a = a[1].a; }
static void t_getMsg(Slot *a) { a[0].a = ((Obj *)a[0].a)->f[0].a; }
static void t_toString(Slot *a) {
  Obj *o = a[0].a; char b[200]; snprintf(b, sizeof b, "%s", o->cls->name); for (char *p = b; *p; p++) if (*p == '/') *p = '.';
  Obj *r = newStr(b); if (o->f[0].a) { Obj *sb = newObj(loadClass("java/lang/StringBuilder")); sb->f[0].a = 0; sbAppStr(sb, r); sbAppC(sb, ": "); sbAppStr(sb, o->f[0].a); r = newStr16((uint16_t *)sb->f[0].a, sb->f[1].i); }
  a[0].a = r;
}
static void t_print(Slot *a) { Obj *s = 0; Slot b[1]; b[0] = a[0]; t_toString(b); s = b[0].a; fflush(stdout); jprintStr(s, stderr); fputc('\n', stderr); }

// ---- PrintStream ----
static void pr(Slot *a, Obj *s, int nl) { jprintStr(s, stdout); if (nl) fputc('\n', stdout); (void)a; }
static void ps_println_s(Slot *a) { pr(a, STR(1), 1); }
static void ps_print_s(Slot *a) { pr(a, STR(1), 0); }
static void ps_println_i(Slot *a) { printf("%d\n", a[1].i); }
static void ps_print_i(Slot *a) { printf("%d", a[1].i); }
static void ps_println_j(Slot *a) { printf("%lld\n", (long long)a[1].l); }
static void ps_print_j(Slot *a) { printf("%lld", (long long)a[1].l); }
static void ps_println_c(Slot *a) { uint16_t c = a[1].i; Obj *s = newStr16(&c, 1); pr(a, s, 1); }
static void ps_print_c(Slot *a) { uint16_t c = a[1].i; Obj *s = newStr16(&c, 1); pr(a, s, 0); }
static void ps_println_z(Slot *a) { puts(a[1].i ? "true" : "false"); }
static void ps_print_z(Slot *a) { fputs(a[1].i ? "true" : "false", stdout); }
static void ps_println_d(Slot *a) { char b[40]; fmtDouble(a[1].d, b, 0); puts(b); }
static void ps_print_d(Slot *a) { char b[40]; fmtDouble(a[1].d, b, 0); fputs(b, stdout); }
static void ps_println_f(Slot *a) { char b[40]; fmtDouble(a[1].f, b, 1); puts(b); }
static void ps_print_f(Slot *a) { char b[40]; fmtDouble(a[1].f, b, 1); fputs(b, stdout); }
static void ps_println_o(Slot *a) { Obj *s = objToString(STR(1)); if (!g_exc) pr(a, s, 1); }
static void ps_print_o(Slot *a) { Obj *s = objToString(STR(1)); if (!g_exc) pr(a, s, 0); }
static void ps_println_0(Slot *a) { (void)a; fputc('\n', stdout); }

// ---- String ----
static void st_init0(Slot *a) { Obj *o = a[0].a; o->f[0].a = calloc(1, 2); o->f[1].i = 0; }
static void st_initS(Slot *a) { Obj *o = a[0].a, *s = a[1].a; if (!s) { throwNew("java/lang/NullPointerException", 0); return; } Obj *n = newStr16(S_CH(s), S_LEN(s)); o->f[0].a = n->f[0].a; o->f[1].i = n->f[1].i; }
static void st_initC(Slot *a) { Obj *o = a[0].a; Arr *c = a[1].a; Obj *n = newStr16((uint16_t *)c->d, c->len); o->f[0].a = n->f[0].a; o->f[1].i = n->f[1].i; }
static void st_initCII(Slot *a) { Obj *o = a[0].a; Arr *c = a[1].a; int off = a[2].i, n = a[3].i; if (off < 0 || n < 0 || off + n > c->len) { throwNew("java/lang/StringIndexOutOfBoundsException", 0); return; } Obj *s = newStr16((uint16_t *)c->d + off, n); o->f[0].a = s->f[0].a; o->f[1].i = n; }
static void st_initB(Slot *a) { Obj *o = a[0].a; Arr *b = a[1].a; char *t = malloc(b->len + 1); memcpy(t, b->d, b->len); t[b->len] = 0; Obj *s = newStr(t); free(t); o->f[0].a = s->f[0].a; o->f[1].i = s->f[1].i; }
static void st_length(Slot *a) { a[0].i = S_LEN(STR(0)); }
static void st_charAt(Slot *a) { Obj *s = STR(0); int i = a[1].i; if ((unsigned)i >= (unsigned)S_LEN(s)) { char b[40]; snprintf(b, sizeof b, "String index out of range: %d", i); throwNew("java/lang/StringIndexOutOfBoundsException", b); return; } a[0].i = S_CH(s)[i]; }
static void st_equals(Slot *a) { Obj *o = a[1].a; a[0].i = o && o->cls == ((Obj *)a[0].a)->cls && jequals(a[0].a, o); }
static void st_hash(Slot *a) { a[0].i = jhash(a[0].a); }
static void st_toString(Slot *a) { (void)a; }
static void st_substr1(Slot *a) { Obj *s = STR(0); int b = a[1].i; if (b < 0 || b > S_LEN(s)) { throwNew("java/lang/StringIndexOutOfBoundsException", 0); return; } a[0].a = newStr16(S_CH(s) + b, S_LEN(s) - b); }
static void st_substr2(Slot *a) { Obj *s = STR(0); int b = a[1].i, e = a[2].i; if (b < 0 || e > S_LEN(s) || b > e) { throwNew("java/lang/StringIndexOutOfBoundsException", 0); return; } a[0].a = newStr16(S_CH(s) + b, e - b); }
static void st_indexOfC(Slot *a) { Obj *s = STR(0); int c = a[1].i; a[0].i = -1; for (int i = 0; i < S_LEN(s); i++) if (S_CH(s)[i] == c) { a[0].i = i; return; } }
static void st_indexOfCI(Slot *a) { Obj *s = STR(0); int c = a[1].i, f = a[2].i; if (f < 0) f = 0; a[0].i = -1; for (int i = f; i < S_LEN(s); i++) if (S_CH(s)[i] == c) { a[0].i = i; return; } }
static void st_lastIndexOfC(Slot *a) { Obj *s = STR(0); int c = a[1].i; a[0].i = -1; for (int i = S_LEN(s) - 1; i >= 0; i--) if (S_CH(s)[i] == c) { a[0].i = i; return; } }
static int idxOfStr(Obj *s, Obj *t, int from) {
  int n = S_LEN(s), m = S_LEN(t); if (from < 0) from = 0;
  for (int i = from; i + m <= n; i++) if (!memcmp(S_CH(s) + i, S_CH(t), m * 2)) return i;
  return -1;
}
static void st_indexOfS(Slot *a) { a[0].i = idxOfStr(STR(0), STR(1), 0); }
static void st_indexOfSI(Slot *a) { a[0].i = idxOfStr(STR(0), STR(1), a[2].i); }
static void st_startsWith(Slot *a) { Obj *s = STR(0), *t = STR(1); a[0].i = S_LEN(t) <= S_LEN(s) && !memcmp(S_CH(s), S_CH(t), S_LEN(t) * 2); }
static void st_endsWith(Slot *a) { Obj *s = STR(0), *t = STR(1); a[0].i = S_LEN(t) <= S_LEN(s) && !memcmp(S_CH(s) + S_LEN(s) - S_LEN(t), S_CH(t), S_LEN(t) * 2); }
static void st_concat(Slot *a) { Obj *s = STR(0), *t = STR(1); uint16_t *b = malloc((S_LEN(s) + S_LEN(t) + 1) * 2); memcpy(b, S_CH(s), S_LEN(s) * 2); memcpy(b + S_LEN(s), S_CH(t), S_LEN(t) * 2); a[0].a = newStr16(b, S_LEN(s) + S_LEN(t)); free(b); }
static void st_trim(Slot *a) { Obj *s = STR(0); int b = 0, e = S_LEN(s); while (b < e && S_CH(s)[b] <= ' ') b++; while (e > b && S_CH(s)[e - 1] <= ' ') e--; a[0].a = newStr16(S_CH(s) + b, e - b); }
static void st_lower(Slot *a) { Obj *s = STR(0); Obj *r = newStr16(S_CH(s), S_LEN(s)); for (int i = 0; i < S_LEN(r); i++) { uint16_t c = S_CH(r)[i]; if (c >= 'A' && c <= 'Z') S_CH(r)[i] = c + 32; } a[0].a = r; }
static void st_upper(Slot *a) { Obj *s = STR(0); Obj *r = newStr16(S_CH(s), S_LEN(s)); for (int i = 0; i < S_LEN(r); i++) { uint16_t c = S_CH(r)[i]; if (c >= 'a' && c <= 'z') S_CH(r)[i] = c - 32; } a[0].a = r; }
static void st_replace(Slot *a) { Obj *s = STR(0); Obj *r = newStr16(S_CH(s), S_LEN(s)); for (int i = 0; i < S_LEN(r); i++) if (S_CH(r)[i] == a[1].i) S_CH(r)[i] = a[2].i; a[0].a = r; }
static void st_compareTo(Slot *a) { Obj *s = STR(0), *t = STR(1); int n = S_LEN(s) < S_LEN(t) ? S_LEN(s) : S_LEN(t); for (int i = 0; i < n; i++) if (S_CH(s)[i] != S_CH(t)[i]) { a[0].i = S_CH(s)[i] - S_CH(t)[i]; return; } a[0].i = S_LEN(s) - S_LEN(t); }
static void st_toCharArray(Slot *a) { Obj *s = STR(0); Arr *r = newArr(S_LEN(s), 2); memcpy(r->d, S_CH(s), S_LEN(s) * 2); a[0].a = r; }
static void st_getBytes(Slot *a) { Obj *s = STR(0); Arr *r = newArr(S_LEN(s), 1); for (int i = 0; i < S_LEN(s); i++) r->d[i] = (uint8_t)S_CH(s)[i]; a[0].a = r; }
static void st_isEmpty(Slot *a) { a[0].i = S_LEN(STR(0)) == 0; }
static void st_equalsIC(Slot *a) { Obj *s = STR(0), *t = STR(1); if (!t || S_LEN(s) != S_LEN(t)) { a[0].i = 0; return; } for (int i = 0; i < S_LEN(s); i++) { uint16_t x = S_CH(s)[i], y = S_CH(t)[i]; if (x >= 'A' && x <= 'Z') x += 32; if (y >= 'A' && y <= 'Z') y += 32; if (x != y) { a[0].i = 0; return; } } a[0].i = 1; }
static void st_vI(Slot *a) { char b[16]; snprintf(b, sizeof b, "%d", a[0].i); a[0].a = newStr(b); }
static void st_vJ(Slot *a) { char b[24]; snprintf(b, sizeof b, "%lld", (long long)a[0].l); a[0].a = newStr(b); }
static void st_vC(Slot *a) { uint16_t c = a[0].i; a[0].a = newStr16(&c, 1); }
static void st_vZ(Slot *a) { a[0].a = newStr(a[0].i ? "true" : "false"); }
static void st_vD(Slot *a) { char b[40]; fmtDouble(a[0].d, b, 0); a[0].a = newStr(b); }
static void st_vF(Slot *a) { char b[40]; fmtDouble(a[0].f, b, 1); a[0].a = newStr(b); }
static void st_vO(Slot *a) { Obj *s = objToString(a[0].a); if (!g_exc) a[0].a = s; }
static void st_vCA(Slot *a) { Arr *c = a[0].a; a[0].a = newStr16((uint16_t *)c->d, c->len); }

// ---- StringBuilder / StringBuffer ----
static void sb_init(Slot *a) { Obj *o = a[0].a; o->f[2].i = 16; o->f[1].i = 0; o->f[0].a = malloc(32); }
static void sb_initI(Slot *a) { Obj *o = a[0].a; int c = a[1].i < 16 ? 16 : a[1].i; o->f[2].i = c; o->f[1].i = 0; o->f[0].a = malloc(c * 2 + 2); }
static void sb_initS(Slot *a) { Obj *o = a[0].a; o->f[2].i = 16; o->f[1].i = 0; o->f[0].a = malloc(32); if (!a[1].a) { throwNew("java/lang/NullPointerException", 0); return; } sbAppStr(o, a[1].a); }
static void sb_appS(Slot *a) { sbAppStr(a[0].a, a[1].a); }
static void sb_appI(Slot *a) { char b[16]; snprintf(b, sizeof b, "%d", a[1].i); sbAppC(a[0].a, b); }
static void sb_appJ(Slot *a) { char b[24]; snprintf(b, sizeof b, "%lld", (long long)a[1].l); sbAppC(a[0].a, b); }
static void sb_appC(Slot *a) { uint16_t c = a[1].i; sbApp16(a[0].a, &c, 1); }
static void sb_appZ(Slot *a) { sbAppC(a[0].a, a[1].i ? "true" : "false"); }
static void sb_appD(Slot *a) { char b[40]; fmtDouble(a[1].d, b, 0); sbAppC(a[0].a, b); }
static void sb_appF(Slot *a) { char b[40]; fmtDouble(a[1].f, b, 1); sbAppC(a[0].a, b); }
static void sb_appO(Slot *a) { Obj *s = objToString(a[1].a); if (!g_exc) { sbAppStr(a[0].a, s); } }
static void sb_appCA(Slot *a) { Arr *c = a[1].a; sbApp16(a[0].a, (uint16_t *)c->d, c->len); }
static void sb_toString(Slot *a) { Obj *o = a[0].a; a[0].a = newStr16((uint16_t *)o->f[0].a, o->f[1].i); }
static void sb_length(Slot *a) { a[0].i = ((Obj *)a[0].a)->f[1].i; }
static void sb_charAt(Slot *a) { Obj *o = a[0].a; int i = a[1].i; if ((unsigned)i >= (unsigned)o->f[1].i) { throwNew("java/lang/StringIndexOutOfBoundsException", 0); return; } a[0].i = ((uint16_t *)o->f[0].a)[i]; }
static void sb_setLength(Slot *a) { Obj *o = a[0].a; int n = a[1].i; if (n > o->f[1].i) { sbReserve(o, n - o->f[1].i); memset((uint16_t *)o->f[0].a + o->f[1].i, 0, (n - o->f[1].i) * 2); } o->f[1].i = n; }
static void sb_reverse(Slot *a) { Obj *o = a[0].a; uint16_t *c = o->f[0].a; for (int i = 0, j = o->f[1].i - 1; i < j; i++, j--) { uint16_t t = c[i]; c[i] = c[j]; c[j] = t; } }
static void sb_deleteCharAt(Slot *a) { Obj *o = a[0].a; int i = a[1].i; uint16_t *c = o->f[0].a; if ((unsigned)i >= (unsigned)o->f[1].i) { throwNew("java/lang/StringIndexOutOfBoundsException", 0); return; } memmove(c + i, c + i + 1, (o->f[1].i - i - 1) * 2); o->f[1].i--; }
static void sb_insertS(Slot *a) { Obj *o = a[0].a; int i = a[1].i; Obj *s = a[2].a; if (!s) s = newStr("null"); if (i < 0 || i > o->f[1].i) { throwNew("java/lang/StringIndexOutOfBoundsException", 0); return; } sbReserve(o, S_LEN(s)); uint16_t *c = o->f[0].a; memmove(c + i + S_LEN(s), c + i, (o->f[1].i - i) * 2); memcpy(c + i, S_CH(s), S_LEN(s) * 2); o->f[1].i += S_LEN(s); }

// ---- Integer / Long / Character ----
static Obj *boxI(int32_t v) { Obj *o = newObj(loadClass("java/lang/Integer")); o->f[0].l = v; return o; }
static Obj *boxJ(int64_t v) { Obj *o = newObj(loadClass("java/lang/Long")); o->f[0].l = v; return o; }
static int parseNum(Obj *s, int radix, int64_t lo, int64_t hi, int64_t *out) {
  if (!s) return 0; int n = S_LEN(s), i = 0, neg = 0; if (!n) return 0;
  if (S_CH(s)[0] == '-') { neg = 1; i = 1; } else if (S_CH(s)[0] == '+') i = 1;
  if (i >= n) return 0; __int128 v = 0;
  for (; i < n; i++) { int c = S_CH(s)[i], d; if (c >= '0' && c <= '9') d = c - '0'; else if (c >= 'a' && c <= 'z') d = c - 'a' + 10; else if (c >= 'A' && c <= 'Z') d = c - 'A' + 10; else return 0; if (d >= radix) return 0; v = v * radix + d; if (v > ((__int128)1 << 64)) return 0; }
  if (neg) v = -v; if (v < lo || v > hi) return 0; *out = (int64_t)v; return 1;
}
static void numErr(Obj *s) { Obj *sb = newObj(loadClass("java/lang/StringBuilder")); sb->f[0].a = malloc(32); sb->f[2].i = 16; sbAppC(sb, "For input string: \""); sbAppStr(sb, s ? s : newStr("null")); sbAppC(sb, "\""); Obj *e = newObj(loadClass("java/lang/NumberFormatException")); e->f[0].a = newStr16((uint16_t *)sb->f[0].a, sb->f[1].i); g_exc = e; }
static void in_parse(Slot *a) { int64_t v; if (!parseNum(STR(0), 10, INT32_MIN, INT32_MAX, &v)) { numErr(STR(0)); return; } a[0].i = (int32_t)v; }
static void in_parseR(Slot *a) { int64_t v; if (!parseNum(STR(0), a[1].i, INT32_MIN, INT32_MAX, &v)) { numErr(STR(0)); return; } a[0].i = (int32_t)v; }
static void in_valueOfS(Slot *a) { int64_t v; if (!parseNum(STR(0), 10, INT32_MIN, INT32_MAX, &v)) { numErr(STR(0)); return; } a[0].a = boxI((int32_t)v); }
static void in_valueOfI(Slot *a) { a[0].a = boxI(a[0].i); }
static void in_initI(Slot *a) { ((Obj *)a[0].a)->f[0].l = a[1].i; }
static void in_intValue(Slot *a) { a[0].i = ((Obj *)a[0].a)->f[0].i; }
static void in_longValue(Slot *a) { a[0].l = ((Obj *)a[0].a)->f[0].l; }
static void in_toStringS(Slot *a) { st_vI(a); }
static void in_toString(Slot *a) { char b[16]; snprintf(b, sizeof b, "%d", ((Obj *)a[0].a)->f[0].i); a[0].a = newStr(b); }
static void in_equals(Slot *a) { a[0].i = jequals(a[0].a, a[1].a); }
static void in_hash(Slot *a) { a[0].i = jhash(a[0].a); }
static void in_toHex(Slot *a) { char b[16]; snprintf(b, sizeof b, "%x", (unsigned)a[0].i); a[0].a = newStr(b); }
static void lg_parse(Slot *a) { int64_t v; if (!parseNum(STR(0), 10, INT64_MIN, INT64_MAX, &v)) { numErr(STR(0)); return; } a[0].l = v; }
static void lg_valueOfJ(Slot *a) { a[0].a = boxJ(a[0].l); }
static void lg_initJ(Slot *a) { ((Obj *)a[0].a)->f[0].l = a[1].l; }
static void lg_toString(Slot *a) { char b[24]; snprintf(b, sizeof b, "%lld", (long long)((Obj *)a[0].a)->f[0].l); a[0].a = newStr(b); }
static void lg_toStringJ(Slot *a) { st_vJ(a); }
static void ch_isDigit(Slot *a) { int c = a[0].i; a[0].i = c >= '0' && c <= '9'; }
static void ch_isLetter(Slot *a) { int c = a[0].i; a[0].i = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c > 0xBF; }
static void ch_toUpper(Slot *a) { int c = a[0].i; a[0].i = (c >= 'a' && c <= 'z') ? c - 32 : c; }
static void ch_toLower(Slot *a) { int c = a[0].i; a[0].i = (c >= 'A' && c <= 'Z') ? c + 32 : c; }

// ---- Math / System ----
static void m_absI(Slot *a) { a[0].i = a[0].i < 0 ? (int32_t)(0u - (uint32_t)a[0].i) : a[0].i; }
static void m_absJ(Slot *a) { a[0].l = a[0].l < 0 ? (int64_t)(0ull - (uint64_t)a[0].l) : a[0].l; }
static void m_absD(Slot *a) { a[0].d = fabs(a[0].d); }
static void m_absF(Slot *a) { a[0].f = fabsf(a[0].f); }
static void m_maxI(Slot *a) { a[0].i = a[0].i > a[1].i ? a[0].i : a[1].i; }
static void m_minI(Slot *a) { a[0].i = a[0].i < a[1].i ? a[0].i : a[1].i; }
static void m_maxJ(Slot *a) { a[0].l = a[0].l > a[2].l ? a[0].l : a[2].l; }
static void m_minJ(Slot *a) { a[0].l = a[0].l < a[2].l ? a[0].l : a[2].l; }
static void m_maxD(Slot *a) { a[0].d = a[0].d > a[2].d ? a[0].d : a[2].d; }
static void m_minD(Slot *a) { a[0].d = a[0].d < a[2].d ? a[0].d : a[2].d; }
static void m_maxF(Slot *a) { a[0].f = a[0].f > a[1].f ? a[0].f : a[1].f; }
static void m_minF(Slot *a) { a[0].f = a[0].f < a[1].f ? a[0].f : a[1].f; }
#define M1(fn, e) static void fn(Slot *a) { double x = a[0].d; a[0].d = e; }
M1(m_sqrt, sqrt(x)) M1(m_sin, sin(x)) M1(m_cos, cos(x)) M1(m_tan, tan(x)) M1(m_floor, floor(x)) M1(m_ceil, ceil(x)) M1(m_exp, exp(x)) M1(m_log, log(x)) M1(m_atan, atan(x))
static void m_pow(Slot *a) { a[0].d = pow(a[0].d, a[2].d); }
static void m_atan2(Slot *a) { a[0].d = atan2(a[0].d, a[2].d); }
static void m_random(Slot *a) { a[0].d = (double)rand() / ((double)RAND_MAX + 1); }
static void m_roundD(Slot *a) { a[0].l = (int64_t)floor(a[0].d + 0.5); }
static void m_roundF(Slot *a) { a[0].i = (int32_t)floorf(a[0].f + 0.5f); }
static void sy_ctm(Slot *a) { struct timespec t; clock_gettime(CLOCK_REALTIME, &t); a[0].l = (int64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000; }
static void sy_nano(Slot *a) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); a[0].l = (int64_t)t.tv_sec * 1000000000LL + t.tv_nsec; }
static void sy_arraycopy(Slot *a) {
  Arr *s = a[0].a, *d = a[2].a; int sp = a[1].i, dp = a[3].i, n = a[4].i;
  if (!s || !d) { throwNew("java/lang/NullPointerException", 0); return; }
  if (sp < 0 || dp < 0 || n < 0 || sp + n > s->len || dp + n > d->len) { throwNew("java/lang/ArrayIndexOutOfBoundsException", "arraycopy"); return; }
  memmove(d->d + (size_t)dp * d->esz, s->d + (size_t)sp * s->esz, (size_t)n * s->esz);
}
static void sy_exit(Slot *a) { fflush(stdout); exit(a[0].i); }
static void sy_null(Slot *a) { a[0].a = 0; }
static void ob_nn(Slot *a) { if (!a[0].a) throwNew("java/lang/NullPointerException", 0); }
static void sy_nop(Slot *a) { (void)a; }
static void sy_idhash(Slot *a) { a[0].i = (int32_t)(((uintptr_t)a[0].a) >> 4); }

// ---- Vector / ArrayList / Stack ----
#define VD(o) ((void **)(o)->f[0].a)
static void v_init(Slot *a) { Obj *o = a[0].a; o->f[2].i = 10; o->f[1].i = 0; o->f[0].a = calloc(10, sizeof(void *)); }
static void v_initI(Slot *a) { Obj *o = a[0].a; int c = a[1].i > 0 ? a[1].i : 10; o->f[2].i = c; o->f[1].i = 0; o->f[0].a = calloc(c, sizeof(void *)); }
static void vAdd(Obj *o, void *x) { if (o->f[1].i == o->f[2].i) { o->f[2].i *= 2; o->f[0].a = realloc(o->f[0].a, o->f[2].i * sizeof(void *)); } VD(o)[o->f[1].i++] = x; }
static void v_add(Slot *a) { vAdd(a[0].a, a[1].a); }
static void v_addZ(Slot *a) { vAdd(a[0].a, a[1].a); a[0].i = 1; }
static void v_size(Slot *a) { a[0].i = ((Obj *)a[0].a)->f[1].i; }
static void v_isEmpty(Slot *a) { a[0].i = ((Obj *)a[0].a)->f[1].i == 0; }
static void vIdxErr(int i, int n) { char b[64]; snprintf(b, sizeof b, "Index: %d, Size: %d", i, n); throwNew("java/lang/ArrayIndexOutOfBoundsException", b); }
static void v_get(Slot *a) { Obj *o = a[0].a; int i = a[1].i; if ((unsigned)i >= (unsigned)o->f[1].i) { vIdxErr(i, o->f[1].i); return; } a[0].a = VD(o)[i]; }
static void v_set(Slot *a) { Obj *o = a[0].a; int i = a[1].i; if ((unsigned)i >= (unsigned)o->f[1].i) { vIdxErr(i, o->f[1].i); return; } void *old = VD(o)[i]; VD(o)[i] = a[2].a; a[0].a = old; }
static void v_setEl(Slot *a) { Obj *o = a[0].a; int i = a[2].i; if ((unsigned)i >= (unsigned)o->f[1].i) { vIdxErr(i, o->f[1].i); return; } VD(o)[i] = a[1].a; }
static void v_removeAt(Slot *a) { Obj *o = a[0].a; int i = a[1].i; if ((unsigned)i >= (unsigned)o->f[1].i) { vIdxErr(i, o->f[1].i); return; } void *old = VD(o)[i]; memmove(VD(o) + i, VD(o) + i + 1, (o->f[1].i - i - 1) * sizeof(void *)); o->f[1].i--; a[0].a = old; }
static void v_removeAtV(Slot *a) { v_removeAt(a); }
static void v_clear(Slot *a) { ((Obj *)a[0].a)->f[1].i = 0; }
static void v_insertAt(Slot *a) { Obj *o = a[0].a; int i = a[2].i; if (i < 0 || i > o->f[1].i) { vIdxErr(i, o->f[1].i); return; } vAdd(o, 0); memmove(VD(o) + i + 1, VD(o) + i, (o->f[1].i - i - 1) * sizeof(void *)); VD(o)[i] = a[1].a; }
static int vIndexOf(Obj *o, Obj *x) { for (int i = 0; i < o->f[1].i; i++) { if (jequals(x, VD(o)[i])) return i; if (g_exc) return -1; } return -1; }
static void v_indexOf(Slot *a) { a[0].i = vIndexOf(a[0].a, a[1].a); }
static void v_contains(Slot *a) { a[0].i = vIndexOf(a[0].a, a[1].a) >= 0; }
static void v_removeObj(Slot *a) { Obj *o = a[0].a; int i = vIndexOf(o, a[1].a); if (i < 0) { a[0].i = 0; return; } memmove(VD(o) + i, VD(o) + i + 1, (o->f[1].i - i - 1) * sizeof(void *)); o->f[1].i--; a[0].i = 1; }
static void v_first(Slot *a) { Obj *o = a[0].a; if (!o->f[1].i) { throwNew("java/util/NoSuchElementException", 0); return; } a[0].a = VD(o)[0]; }
static void v_last(Slot *a) { Obj *o = a[0].a; if (!o->f[1].i) { throwNew("java/util/NoSuchElementException", 0); return; } a[0].a = VD(o)[o->f[1].i - 1]; }
static void v_copyInto(Slot *a) { Obj *o = a[0].a; Arr *d = a[1].a; memcpy(d->d, VD(o), o->f[1].i * sizeof(void *)); }
static void stk_push(Slot *a) { vAdd(a[0].a, a[1].a); a[0].a = a[1].a; }
static void stk_pop(Slot *a) { Obj *o = a[0].a; if (!o->f[1].i) { throwNew("java/util/EmptyStackException", 0); return; } a[0].a = VD(o)[--o->f[1].i]; }
static void stk_peek(Slot *a) { Obj *o = a[0].a; if (!o->f[1].i) { throwNew("java/util/EmptyStackException", 0); return; } a[0].a = VD(o)[o->f[1].i - 1]; }

// ---- Hashtable / HashMap ----
typedef struct Ent { void *k, *v; int h; struct Ent *next; } Ent;
#define HT(o) ((Ent **)(o)->f[0].a)
static void h_init(Slot *a) { Obj *o = a[0].a; o->f[1].i = 16; o->f[2].i = 0; o->f[0].a = calloc(16, sizeof(Ent *)); }
static void h_initI(Slot *a) { Obj *o = a[0].a; int c = 16; while (c < a[1].i) c *= 2; o->f[1].i = c; o->f[2].i = 0; o->f[0].a = calloc(c, sizeof(Ent *)); }
static Ent *hFind(Obj *o, Obj *k, int h) { for (Ent *e = HT(o)[(unsigned)h % o->f[1].i]; e; e = e->next) { if (e->h == h && jequals(k, e->k)) return e; if (g_exc) return 0; } return 0; }
static void h_put(Slot *a) {
  Obj *o = a[0].a; Obj *k = a[1].a; if (!k || !a[2].a) { if (!k || o->cls->name[10] == 'H' && 0) { throwNew("java/lang/NullPointerException", 0); return; } }
  int h = jhash(k); if (g_exc) return; Ent *e = hFind(o, k, h); if (g_exc) return;
  if (e) { void *old = e->v; e->v = a[2].a; a[0].a = old; return; }
  if (o->f[2].i >= o->f[1].i * 3 / 4) { int nc = o->f[1].i * 2; Ent **nt = calloc(nc, sizeof(Ent *)); for (int i = 0; i < o->f[1].i; i++) for (Ent *x = HT(o)[i], *nx; x; x = nx) { nx = x->next; unsigned b = (unsigned)x->h % nc; x->next = nt[b]; nt[b] = x; } free(o->f[0].a); o->f[0].a = nt; o->f[1].i = nc; }
  e = calloc(1, sizeof(Ent)); e->k = k; e->v = a[2].a; e->h = h; unsigned b = (unsigned)h % o->f[1].i; e->next = HT(o)[b]; HT(o)[b] = e; o->f[2].i++; a[0].a = 0;
}
static void h_get(Slot *a) { Obj *o = a[0].a; Obj *k = a[1].a; if (!k) { throwNew("java/lang/NullPointerException", 0); return; } int h = jhash(k); if (g_exc) return; Ent *e = hFind(o, k, h); if (g_exc) return; a[0].a = e ? e->v : 0; }
static void h_containsKey(Slot *a) { Obj *o = a[0].a; Obj *k = a[1].a; if (!k) { throwNew("java/lang/NullPointerException", 0); return; } int h = jhash(k); if (g_exc) return; Ent *e = hFind(o, k, h); if (g_exc) return; a[0].i = e != 0; }
static void h_remove(Slot *a) {
  Obj *o = a[0].a; Obj *k = a[1].a; if (!k) { throwNew("java/lang/NullPointerException", 0); return; } int h = jhash(k); if (g_exc) return;
  Ent **pp = &HT(o)[(unsigned)h % o->f[1].i];
  for (; *pp; pp = &(*pp)->next) { Ent *e = *pp; if (e->h == h && jequals(k, e->k)) { *pp = e->next; a[0].a = e->v; o->f[2].i--; return; } if (g_exc) return; }
  a[0].a = 0;
}
static void h_size(Slot *a) { a[0].i = ((Obj *)a[0].a)->f[2].i; }
static void h_isEmpty(Slot *a) { a[0].i = ((Obj *)a[0].a)->f[2].i == 0; }
static void h_clear(Slot *a) { Obj *o = a[0].a; for (int i = 0; i < o->f[1].i; i++) HT(o)[i] = 0; o->f[2].i = 0; }

// ---- Random (đúng thuật toán java.util.Random) ----
static void rnd_seed(Obj *o, int64_t s) { o->f[0].l = (s ^ 0x5DEECE66DLL) & ((1LL << 48) - 1); }
static int rnd_next(Obj *o, int bits) { o->f[0].l = (int64_t)(((uint64_t)o->f[0].l * 0x5DEECE66DULL + 0xBULL) & ((1ULL << 48) - 1)); return (int)(o->f[0].l >> (48 - bits)); }
static void rn_init(Slot *a) { struct timespec t; clock_gettime(CLOCK_REALTIME, &t); rnd_seed(a[0].a, t.tv_nsec ^ t.tv_sec); }
static void rn_initJ(Slot *a) { rnd_seed(a[0].a, a[1].l); }
static void rn_setSeed(Slot *a) { rnd_seed(a[0].a, a[1].l); }
static void rn_nextInt(Slot *a) { a[0].i = rnd_next(a[0].a, 32); }
static void rn_nextIntN(Slot *a) {
  Obj *o = a[0].a; int n = a[1].i; if (n <= 0) { throwNew("java/lang/IllegalArgumentException", "n must be positive"); return; }
  if ((n & -n) == n) { a[0].i = (int)(((int64_t)n * (int64_t)rnd_next(o, 31)) >> 31); return; }
  int bits, val; do { bits = rnd_next(o, 31); val = bits % n; } while (bits - val + (n - 1) < 0); a[0].i = val;
}
static void rn_nextLong(Slot *a) { Obj *o = a[0].a; int64_t hi = (int64_t)((uint64_t)(int64_t)rnd_next(o, 32) << 32); a[0].l = (int64_t)((uint64_t)hi + (uint64_t)(int64_t)rnd_next(o, 32)); }
static void rn_nextBoolean(Slot *a) { a[0].i = rnd_next(a[0].a, 1) != 0; }

static void both(const char *c1, const char *c2, const char *name, const char *desc, NativeFn fn) { NI(c1, name, desc, fn); NI(c2, name, desc, fn); }

void installNatives(void) {
  const char *O = "java/lang/Object", *T = "java/lang/Throwable", *P = "java/io/PrintStream", *S = "java/lang/String";
  const char *SB = "java/lang/StringBuilder", *SF = "java/lang/StringBuffer";
  NI(O, "<init>", "()V", o_init); NI(O, "hashCode", "()I", o_hash); NI(O, "equals", "(Ljava/lang/Object;)Z", o_equals); NI(O, "toString", "()Ljava/lang/String;", o_toString); NI(O, "getClass", "()Ljava/lang/Class;", o_getClass); NI("java/lang/Class", "getName", "()Ljava/lang/String;", cl_getName);
  NI(T, "<init>", "()V", o_init); NI(T, "<init>", "(Ljava/lang/String;)V", t_initMsg); NI(T, "getMessage", "()Ljava/lang/String;", t_getMsg);
  NI(T, "toString", "()Ljava/lang/String;", t_toString); NI(T, "printStackTrace", "()V", t_print);
  NI(P, "println", "(Ljava/lang/String;)V", ps_println_s); NI(P, "print", "(Ljava/lang/String;)V", ps_print_s);
  NI(P, "println", "(I)V", ps_println_i); NI(P, "print", "(I)V", ps_print_i); NI(P, "println", "(J)V", ps_println_j); NI(P, "print", "(J)V", ps_print_j);
  NI(P, "println", "(C)V", ps_println_c); NI(P, "print", "(C)V", ps_print_c); NI(P, "println", "(Z)V", ps_println_z); NI(P, "print", "(Z)V", ps_print_z);
  NI(P, "println", "(D)V", ps_println_d); NI(P, "print", "(D)V", ps_print_d); NI(P, "println", "(F)V", ps_println_f); NI(P, "print", "(F)V", ps_print_f);
  NI(P, "println", "(Ljava/lang/Object;)V", ps_println_o); NI(P, "print", "(Ljava/lang/Object;)V", ps_print_o); NI(P, "println", "()V", ps_println_0);
  NI(S, "<init>", "()V", st_init0); NI(S, "<init>", "(Ljava/lang/String;)V", st_initS); NI(S, "<init>", "([C)V", st_initC); NI(S, "<init>", "([CII)V", st_initCII); NI(S, "<init>", "([B)V", st_initB);
  NI(S, "length", "()I", st_length); NI(S, "charAt", "(I)C", st_charAt); NI(S, "equals", "(Ljava/lang/Object;)Z", st_equals); NI(S, "hashCode", "()I", st_hash);
  NI(S, "toString", "()Ljava/lang/String;", st_toString); NI(S, "substring", "(I)Ljava/lang/String;", st_substr1); NI(S, "substring", "(II)Ljava/lang/String;", st_substr2);
  NI(S, "indexOf", "(I)I", st_indexOfC); NI(S, "indexOf", "(II)I", st_indexOfCI); NI(S, "lastIndexOf", "(I)I", st_lastIndexOfC);
  NI(S, "indexOf", "(Ljava/lang/String;)I", st_indexOfS); NI(S, "indexOf", "(Ljava/lang/String;I)I", st_indexOfSI);
  NI(S, "startsWith", "(Ljava/lang/String;)Z", st_startsWith); NI(S, "endsWith", "(Ljava/lang/String;)Z", st_endsWith); NI(S, "concat", "(Ljava/lang/String;)Ljava/lang/String;", st_concat);
  NI(S, "trim", "()Ljava/lang/String;", st_trim); NI(S, "toLowerCase", "()Ljava/lang/String;", st_lower); NI(S, "toUpperCase", "()Ljava/lang/String;", st_upper);
  NI(S, "replace", "(CC)Ljava/lang/String;", st_replace); NI(S, "compareTo", "(Ljava/lang/String;)I", st_compareTo); NI(S, "toCharArray", "()[C", st_toCharArray);
  NI(S, "getBytes", "()[B", st_getBytes); NI(S, "isEmpty", "()Z", st_isEmpty); NI(S, "equalsIgnoreCase", "(Ljava/lang/String;)Z", st_equalsIC);
  NS(S, "valueOf", "(I)Ljava/lang/String;", st_vI); NS(S, "valueOf", "(J)Ljava/lang/String;", st_vJ); NS(S, "valueOf", "(C)Ljava/lang/String;", st_vC); NS(S, "valueOf", "(Z)Ljava/lang/String;", st_vZ);
  NS(S, "valueOf", "(D)Ljava/lang/String;", st_vD); NS(S, "valueOf", "(F)Ljava/lang/String;", st_vF); NS(S, "valueOf", "(Ljava/lang/Object;)Ljava/lang/String;", st_vO); NS(S, "valueOf", "([C)Ljava/lang/String;", st_vCA);
  const char *B[2] = {SB, SF};
  for (int i = 0; i < 2; i++) {
    const char *c = B[i]; char rd[64]; snprintf(rd, sizeof rd, "L%s;", c);
    char d[10][96];
#define SIG(k, arg) snprintf(d[k], sizeof d[k], "(%s)%s", arg, rd)
    NI(c, "<init>", "()V", sb_init); NI(c, "<init>", "(I)V", sb_initI); NI(c, "<init>", "(Ljava/lang/String;)V", sb_initS);
    SIG(0, "Ljava/lang/String;"); NI(c, "append", strdup(d[0]), sb_appS); SIG(1, "I"); NI(c, "append", strdup(d[1]), sb_appI); SIG(2, "J"); NI(c, "append", strdup(d[2]), sb_appJ);
    SIG(3, "C"); NI(c, "append", strdup(d[3]), sb_appC); SIG(4, "Z"); NI(c, "append", strdup(d[4]), sb_appZ); SIG(5, "D"); NI(c, "append", strdup(d[5]), sb_appD);
    SIG(6, "F"); NI(c, "append", strdup(d[6]), sb_appF); SIG(7, "Ljava/lang/Object;"); NI(c, "append", strdup(d[7]), sb_appO); SIG(8, "[C"); NI(c, "append", strdup(d[8]), sb_appCA);
    NI(c, "toString", "()Ljava/lang/String;", sb_toString); NI(c, "length", "()I", sb_length); NI(c, "charAt", "(I)C", sb_charAt); NI(c, "setLength", "(I)V", sb_setLength);
    snprintf(d[9], sizeof d[9], "()%s", rd); NI(c, "reverse", strdup(d[9]), sb_reverse);
    snprintf(d[9], sizeof d[9], "(I)%s", rd); NI(c, "deleteCharAt", strdup(d[9]), sb_deleteCharAt);
    snprintf(d[9], sizeof d[9], "(ILjava/lang/String;)%s", rd); NI(c, "insert", strdup(d[9]), sb_insertS);
  }
  const char *I = "java/lang/Integer", *L = "java/lang/Long", *C = "java/lang/Character";
  NS(I, "parseInt", "(Ljava/lang/String;)I", in_parse); NS(I, "parseInt", "(Ljava/lang/String;I)I", in_parseR); NS(I, "valueOf", "(Ljava/lang/String;)Ljava/lang/Integer;", in_valueOfS);
  NS(I, "valueOf", "(I)Ljava/lang/Integer;", in_valueOfI); NI(I, "<init>", "(I)V", in_initI); NI(I, "intValue", "()I", in_intValue); NI(I, "longValue", "()J", in_longValue);
  NS(I, "toString", "(I)Ljava/lang/String;", in_toStringS); NI(I, "toString", "()Ljava/lang/String;", in_toString); NI(I, "equals", "(Ljava/lang/Object;)Z", in_equals); NI(I, "hashCode", "()I", in_hash);
  NS(I, "toHexString", "(I)Ljava/lang/String;", in_toHex);
  NS(L, "parseLong", "(Ljava/lang/String;)J", lg_parse); NS(L, "valueOf", "(J)Ljava/lang/Long;", lg_valueOfJ); NI(L, "<init>", "(J)V", lg_initJ); NI(L, "longValue", "()J", in_longValue);
  NI(L, "toString", "()Ljava/lang/String;", lg_toString); NS(L, "toString", "(J)Ljava/lang/String;", lg_toStringJ); NI(L, "equals", "(Ljava/lang/Object;)Z", in_equals); NI(L, "hashCode", "()I", in_hash);
  NS(C, "isDigit", "(C)Z", ch_isDigit); NS(C, "isLetter", "(C)Z", ch_isLetter); NS(C, "toUpperCase", "(C)C", ch_toUpper); NS(C, "toLowerCase", "(C)C", ch_toLower);
  const char *M = "java/lang/Math";
  NS(M, "abs", "(I)I", m_absI); NS(M, "abs", "(J)J", m_absJ); NS(M, "abs", "(D)D", m_absD); NS(M, "abs", "(F)F", m_absF);
  NS(M, "max", "(II)I", m_maxI); NS(M, "min", "(II)I", m_minI); NS(M, "max", "(JJ)J", m_maxJ); NS(M, "min", "(JJ)J", m_minJ); NS(M, "max", "(DD)D", m_maxD); NS(M, "min", "(DD)D", m_minD);
  NS(M, "max", "(FF)F", m_maxF); NS(M, "min", "(FF)F", m_minF);
  NS(M, "sqrt", "(D)D", m_sqrt); NS(M, "sin", "(D)D", m_sin); NS(M, "cos", "(D)D", m_cos); NS(M, "tan", "(D)D", m_tan); NS(M, "floor", "(D)D", m_floor); NS(M, "ceil", "(D)D", m_ceil);
  NS(M, "exp", "(D)D", m_exp); NS(M, "log", "(D)D", m_log); NS(M, "atan", "(D)D", m_atan); NS(M, "pow", "(DD)D", m_pow); NS(M, "atan2", "(DD)D", m_atan2); NS(M, "random", "()D", m_random);
  NS(M, "round", "(D)J", m_roundD); NS(M, "round", "(F)I", m_roundF);
  NS("java/util/Objects", "requireNonNull", "(Ljava/lang/Object;)Ljava/lang/Object;", ob_nn);
  const char *Y = "java/lang/System";
  NS(Y, "currentTimeMillis", "()J", sy_ctm); NS(Y, "nanoTime", "()J", sy_nano); NS(Y, "arraycopy", "(Ljava/lang/Object;ILjava/lang/Object;II)V", sy_arraycopy);
  NS(Y, "exit", "(I)V", sy_exit); NS(Y, "getProperty", "(Ljava/lang/String;)Ljava/lang/String;", sy_null); NS(Y, "gc", "()V", sy_nop); NS(Y, "identityHashCode", "(Ljava/lang/Object;)I", sy_idhash);
  const char *LS[3] = {"java/util/Vector", "java/util/ArrayList", 0};
  for (int i = 0; i < 2; i++) {
    const char *c = LS[i];
    NI(c, "<init>", "()V", v_init); NI(c, "<init>", "(I)V", v_initI); NI(c, "size", "()I", v_size); NI(c, "isEmpty", "()Z", v_isEmpty);
    NI(c, "addElement", "(Ljava/lang/Object;)V", v_add); NI(c, "add", "(Ljava/lang/Object;)Z", v_addZ); NI(c, "elementAt", "(I)Ljava/lang/Object;", v_get); NI(c, "get", "(I)Ljava/lang/Object;", v_get);
    NI(c, "set", "(ILjava/lang/Object;)Ljava/lang/Object;", v_set); NI(c, "setElementAt", "(Ljava/lang/Object;I)V", v_setEl); NI(c, "removeElementAt", "(I)V", v_removeAtV);
    NI(c, "remove", "(I)Ljava/lang/Object;", v_removeAt); NI(c, "removeAllElements", "()V", v_clear); NI(c, "clear", "()V", v_clear);
    NI(c, "insertElementAt", "(Ljava/lang/Object;I)V", v_insertAt); NI(c, "indexOf", "(Ljava/lang/Object;)I", v_indexOf); NI(c, "contains", "(Ljava/lang/Object;)Z", v_contains);
    NI(c, "removeElement", "(Ljava/lang/Object;)Z", v_removeObj); NI(c, "remove", "(Ljava/lang/Object;)Z", v_removeObj); NI(c, "firstElement", "()Ljava/lang/Object;", v_first); NI(c, "lastElement", "()Ljava/lang/Object;", v_last);
    NI(c, "copyInto", "([Ljava/lang/Object;)V", v_copyInto);
  }
  const char *K = "java/util/Stack";
  NI(K, "push", "(Ljava/lang/Object;)Ljava/lang/Object;", stk_push); NI(K, "pop", "()Ljava/lang/Object;", stk_pop); NI(K, "peek", "()Ljava/lang/Object;", stk_peek); NI(K, "empty", "()Z", v_isEmpty);
  const char *HS[2] = {"java/util/Hashtable", "java/util/HashMap"};
  for (int i = 0; i < 2; i++) {
    const char *c = HS[i];
    NI(c, "<init>", "()V", h_init); NI(c, "<init>", "(I)V", h_initI); NI(c, "put", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;", h_put); NI(c, "get", "(Ljava/lang/Object;)Ljava/lang/Object;", h_get);
    NI(c, "containsKey", "(Ljava/lang/Object;)Z", h_containsKey); NI(c, "remove", "(Ljava/lang/Object;)Ljava/lang/Object;", h_remove); NI(c, "size", "()I", h_size); NI(c, "isEmpty", "()Z", h_isEmpty); NI(c, "clear", "()V", h_clear);
  }
  const char *R = "java/util/Random";
  NI(R, "<init>", "()V", rn_init); NI(R, "<init>", "(J)V", rn_initJ); NI(R, "setSeed", "(J)V", rn_setSeed); NI(R, "nextInt", "()I", rn_nextInt); NI(R, "nextInt", "(I)I", rn_nextIntN);
  NI(R, "nextLong", "()J", rn_nextLong); NI(R, "nextBoolean", "()Z", rn_nextBoolean);
  (void)both;
}
