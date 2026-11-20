// Màn hình lcdui cấp cao (List / Form / TextBox / Alert): C chỉ giữ dữ liệu, mô tả bằng JSON cho host (Flutter) vẽ bằng widget thật;
// host gửi thao tác (chọn, nhập chữ, bấm lệnh) về qua midpUiAction. Được #include vào cuối phần Display của midp.c.
typedef struct { Obj *str, *img; int sel; } CItem;
typedef struct { int type, n, cap; CItem *it; } Choice;
typedef struct UiI { int kind; Obj *text, *img; Choice ch; int maxSize, cons, gval, gmax, inter, ap; } UiI; // 1 chuỗi, 2 ô chữ, 3 lựa chọn, 4 thanh, 5 ảnh, 6 khoảng trống
typedef struct UiD {
  int kind, id, ncmd, ccap, nit, icap, maxSize, cons, timeout; Obj *title, *text, *selCmd, *next, *stateL, *ticker; Obj **cmd, **items; Choice ch; int64_t shown;
} UiD; // kind: 1 List, 2 Form, 3 TextBox, 4 Alert
static int uiIds, g_uiDirty = 1; static Obj *g_prevScr;
static UiD *ud(Obj *o, int kind) { UiD *u = o->f[2].a; if (!u) { u = calloc(1, sizeof *u); u->id = ++uiIds; u->timeout = 3000; o->f[2].a = u; } if (kind) u->kind = kind; return u; }
static UiI *ui_(Obj *o, int kind) { UiI *u = o->f[1].a; if (!u) { u = calloc(1, sizeof *u); o->f[1].a = u; } if (kind) u->kind = kind; return u; }
#define DIRTY() (g_uiDirty = 1)
static Obj *emptyStr(void) { static Obj *e; if (!e) e = newStr(""); return e; }

// ---- Choice ----
static int chSingle(Choice *c) { return c->type != 2; }
static void chInsert(Choice *c, int at, Obj *s, Obj *img) {
  if (at < 0 || at > c->n) at = c->n;
  if (c->n == c->cap) { c->cap = c->cap ? c->cap * 2 : 8; c->it = realloc(c->it, c->cap * sizeof(CItem)); }
  memmove(c->it + at + 1, c->it + at, (c->n - at) * sizeof(CItem)); c->it[at] = (CItem){s ? s : emptyStr(), img, 0}; c->n++;
  if (chSingle(c)) { int any = 0; for (int i = 0; i < c->n; i++) if (c->it[i].sel) any = 1; if (!any) c->it[0].sel = 1; }
}
static void chDelete(Choice *c, int i) {
  if (i < 0 || i >= c->n) return; int was = c->it[i].sel; memmove(c->it + i, c->it + i + 1, (c->n - i - 1) * sizeof(CItem)); c->n--;
  if (chSingle(c) && was && c->n) c->it[i < c->n ? i : c->n - 1].sel = 1;
}
static int chSelIdx(Choice *c) { for (int i = 0; i < c->n; i++) if (c->it[i].sel) return i; return -1; }
static void chSetSel(Choice *c, int i, int on) {
  if (i < 0 || i >= c->n) return;
  if (chSingle(c)) { for (int k = 0; k < c->n; k++) c->it[k].sel = 0; c->it[i].sel = 1; } else c->it[i].sel = on;
}
static void chSetBits(Choice *c, const char *b) { for (int i = 0; i < c->n; i++) c->it[i].sel = b[i] == '1'; if (chSingle(c)) { int f = chSelIdx(c); if (f < 0 && c->n) c->it[0].sel = 1; } }

// ---- Displayable chung ----
static void dp_setTitle(Slot *a) { ud(OBJ(0), 0)->title = a[1].a; DIRTY(); }
static void dp_getTitle(Slot *a) { a[0].a = ud(OBJ(0), 0)->title; }
static void dp_addCmd(Slot *a) {
  UiD *u = ud(OBJ(0), 0); Obj *c = OBJ(1); if (!c) { throwNew("java/lang/NullPointerException", 0); return; }
  for (int i = 0; i < u->ncmd; i++) if (u->cmd[i] == c) return;
  if (u->ncmd == u->ccap) { u->ccap = u->ccap ? u->ccap * 2 : 4; u->cmd = realloc(u->cmd, u->ccap * sizeof(Obj *)); }
  u->cmd[u->ncmd++] = c; DIRTY();
}
static void dp_rmCmd(Slot *a) { UiD *u = ud(OBJ(0), 0); for (int i = 0; i < u->ncmd; i++) if (u->cmd[i] == OBJ(1)) { memmove(u->cmd + i, u->cmd + i + 1, (u->ncmd - i - 1) * sizeof(Obj *)); u->ncmd--; DIRTY(); return; } }
static void dp_setTicker(Slot *a) { ud(OBJ(0), 0)->ticker = a[1].a; }
static void dp_getTicker(Slot *a) { a[0].a = ud(OBJ(0), 0)->ticker; }
static void dp_setListener(Slot *a) { OBJ(0)->f[D_LISTENER].a = a[1].a; }

// ---- List / ChoiceGroup ----
static Choice *chOf2(Obj *o) { return subOf(o->cls, loadClass(LCD "Displayable")) ? &ud(o, 1)->ch : &ui_(o, 3)->ch; }
static void ch_init(Slot *a) { Obj *o = OBJ(0); int isD = subOf(o->cls, loadClass(LCD "Displayable")); Choice *c; if (isD) { UiD *u = ud(o, 1); u->title = a[1].a; c = &u->ch; } else { UiI *u = ui_(o, 3); o->f[0].a = a[1].a; c = &u->ch; } c->type = a[2].i; }
static void ch_initFull(Slot *a) {
  ch_init(a); Choice *c = chOf2(OBJ(0)); Arr *s = a[3].a, *im = a[4].a;
  if (s) for (int i = 0; i < s->len; i++) chInsert(c, c->n, ((Obj **)s->d)[i], im && i < im->len ? ((Obj **)im->d)[i] : 0); DIRTY();
}
static void ch_append(Slot *a) { Choice *c = chOf2(OBJ(0)); chInsert(c, c->n, a[1].a, a[2].a); a[0].i = c->n - 1; DIRTY(); }
static void ch_insert(Slot *a) { Choice *c = chOf2(OBJ(0)); if (a[1].i < 0 || a[1].i > c->n) { throwNew("java/lang/IndexOutOfBoundsException", 0); return; } chInsert(c, a[1].i, a[2].a, a[3].a); DIRTY(); }
static void ch_size(Slot *a) { a[0].i = chOf2(OBJ(0))->n; }
static int chIdx(Slot *a, Choice *c) { if (a[1].i < 0 || a[1].i >= c->n) { throwNew("java/lang/IndexOutOfBoundsException", 0); return -1; } return a[1].i; }
static void ch_getString(Slot *a) { Choice *c = chOf2(OBJ(0)); int i = chIdx(a, c); if (i >= 0) a[0].a = c->it[i].str; }
static void ch_getImage(Slot *a) { Choice *c = chOf2(OBJ(0)); int i = chIdx(a, c); if (i >= 0) a[0].a = c->it[i].img; }
static void ch_delete(Slot *a) { Choice *c = chOf2(OBJ(0)); int i = chIdx(a, c); if (i >= 0) { chDelete(c, i); DIRTY(); } }
static void ch_deleteAll(Slot *a) { chOf2(OBJ(0))->n = 0; DIRTY(); (void)a; }
static void ch_set(Slot *a) { Choice *c = chOf2(OBJ(0)); int i = chIdx(a, c); if (i >= 0) { c->it[i].str = a[2].a ? a[2].a : emptyStr(); c->it[i].img = a[3].a; DIRTY(); } }
static void ch_getSel(Slot *a) { a[0].i = chSelIdx(chOf2(OBJ(0))); }
static void ch_setSel(Slot *a) { chSetSel(chOf2(OBJ(0)), a[1].i, a[2].i); DIRTY(); }
static void ch_isSel(Slot *a) { Choice *c = chOf2(OBJ(0)); int i = chIdx(a, c); if (i >= 0) a[0].i = c->it[i].sel; }
static void ch_getFlags(Slot *a) { Choice *c = chOf2(OBJ(0)); Arr *f = a[1].a; int n = 0; if (!f) { throwNew("java/lang/NullPointerException", 0); return; } for (int i = 0; i < c->n && i < f->len; i++) { ((uint8_t *)f->d)[i] = c->it[i].sel; n += c->it[i].sel; } a[0].i = n; }
static void ch_setFlags(Slot *a) { Choice *c = chOf2(OBJ(0)); Arr *f = a[1].a; if (!f) { throwNew("java/lang/NullPointerException", 0); return; } for (int i = 0; i < c->n && i < f->len; i++) c->it[i].sel = ((uint8_t *)f->d)[i]; DIRTY(); }
static void ch_zero(Slot *a) { a[0].i = 0; }
static void ch_selCmd(Slot *a) { ud(OBJ(0), 1)->selCmd = a[1].a; DIRTY(); }

// ---- TextBox / TextField (cùng bố cục: tiêu đề/nhãn, nội dung, maxSize, constraints) ----
static Obj *tx(Obj *o) { return subOf(o->cls, loadClass(LCD "Displayable")) ? ud(o, 3)->text : ui_(o, 2)->text; }
static void tx_setObj(Obj *o, Obj *s) { if (subOf(o->cls, loadClass(LCD "Displayable"))) ud(o, 3)->text = s; else ui_(o, 2)->text = s; DIRTY(); }
static void tb_init(Slot *a) {
  Obj *o = OBJ(0); int isD = subOf(o->cls, loadClass(LCD "Displayable"));
  if (isD) { UiD *u = ud(o, 3); u->title = a[1].a; u->text = a[2].a ? a[2].a : emptyStr(); u->maxSize = a[3].i; u->cons = a[4].i; }
  else { UiI *u = ui_(o, 2); o->f[0].a = a[1].a; u->text = a[2].a ? a[2].a : emptyStr(); u->maxSize = a[3].i; u->cons = a[4].i; }
}
static void tb_get(Slot *a) { Obj *s = tx(OBJ(0)); a[0].a = s ? s : emptyStr(); }
static void tb_set(Slot *a) { tx_setObj(OBJ(0), a[1].a ? a[1].a : emptyStr()); }
static void tb_size(Slot *a) { Obj *s = tx(OBJ(0)); a[0].i = s ? S_LEN(s) : 0; }
static void tb_max(Slot *a) { Obj *o = OBJ(0); if (subOf(o->cls, loadClass(LCD "Displayable"))) ud(o, 3)->maxSize = a[1].i; else ui_(o, 2)->maxSize = a[1].i; DIRTY(); }
static void tb_getMax(Slot *a) { Obj *o = OBJ(0); a[0].i = subOf(o->cls, loadClass(LCD "Displayable")) ? ud(o, 3)->maxSize : ui_(o, 2)->maxSize; }
static void tb_cons(Slot *a) { Obj *o = OBJ(0); a[0].i = subOf(o->cls, loadClass(LCD "Displayable")) ? ud(o, 3)->cons : ui_(o, 2)->cons; }
static void tb_setCons(Slot *a) { Obj *o = OBJ(0); if (subOf(o->cls, loadClass(LCD "Displayable"))) ud(o, 3)->cons = a[1].i; else ui_(o, 2)->cons = a[1].i; DIRTY(); }
static void tb_insert(Slot *a) { // insert(String, int pos)
  Obj *s = tx(OBJ(0)), *t = a[1].a; int p = a[2].i; if (!t) { throwNew("java/lang/NullPointerException", 0); return; } int n = s ? S_LEN(s) : 0; if (p < 0) p = 0; if (p > n) p = n;
  uint16_t *b = malloc((n + S_LEN(t) + 1) * 2); if (n) memcpy(b, S_CH(s), p * 2); memcpy(b + p, S_CH(t), S_LEN(t) * 2); if (n) memcpy(b + p + S_LEN(t), S_CH(s) + p, (n - p) * 2);
  tx_setObj(OBJ(0), newStr16(b, n + S_LEN(t))); free(b);
}
static void tb_delete(Slot *a) { Obj *s = tx(OBJ(0)); int n = s ? S_LEN(s) : 0, o = a[1].i, l = a[2].i; if (o < 0 || l < 0 || o + l > n) { throwNew("java/lang/StringIndexOutOfBoundsException", 0); return; } uint16_t *b = malloc(n * 2 + 2); if (n) { memcpy(b, S_CH(s), o * 2); memcpy(b + o, S_CH(s) + o + l, (n - o - l) * 2); } tx_setObj(OBJ(0), newStr16(b, n - l)); free(b); }
static void tb_getChars(Slot *a) { Obj *s = tx(OBJ(0)); Arr *d = a[1].a; int n = s ? S_LEN(s) : 0; if (!d || d->len < n) { throwNew("java/lang/ArrayIndexOutOfBoundsException", 0); return; } for (int i = 0; i < n; i++) ((uint16_t *)d->d)[i] = S_CH(s)[i]; a[0].i = n; }
static void tb_setChars(Slot *a) { Arr *d = a[1].a; if (!d) { tx_setObj(OBJ(0), emptyStr()); return; } int o = a[2].i, n = a[3].i; if (o < 0 || n < 0 || o + n > d->len) { throwNew("java/lang/ArrayIndexOutOfBoundsException", 0); return; } tx_setObj(OBJ(0), newStr16((uint16_t *)d->d + o, n)); }
static void tb_caret(Slot *a) { Obj *s = tx(OBJ(0)); a[0].i = s ? S_LEN(s) : 0; }

// ---- Alert ----
static void al_init1(Slot *a) { UiD *u = ud(OBJ(0), 4); u->title = a[1].a; }
static void al_init4(Slot *a) { UiD *u = ud(OBJ(0), 4); u->title = a[1].a; u->text = a[2].a; }
static void al_setString(Slot *a) { ud(OBJ(0), 4)->text = a[1].a; DIRTY(); }
static void al_getString(Slot *a) { a[0].a = ud(OBJ(0), 4)->text; }
static void al_setTimeout(Slot *a) { ud(OBJ(0), 4)->timeout = a[1].i; }
static void al_getTimeout(Slot *a) { a[0].i = ud(OBJ(0), 4)->timeout; }
static void ui_nop(Slot *a) { (void)a; }
static void ui_zeroR(Slot *a) { a[0].l = 0; }

// ---- Form ----
static void fm_add(UiD *u, int at, Obj *it) {
  if (u->nit == u->icap) { u->icap = u->icap ? u->icap * 2 : 8; u->items = realloc(u->items, u->icap * sizeof(Obj *)); }
  if (at < 0 || at > u->nit) at = u->nit; memmove(u->items + at + 1, u->items + at, (u->nit - at) * sizeof(Obj *)); u->items[at] = it; u->nit++; DIRTY();
}
static void fm_init(Slot *a) { UiD *u = ud(OBJ(0), 2); u->title = a[1].a; }
static void fm_initItems(Slot *a) { fm_init(a); UiD *u = ud(OBJ(0), 2); Arr *s = a[2].a; if (s) for (int i = 0; i < s->len; i++) if (((Obj **)s->d)[i]) fm_add(u, u->nit, ((Obj **)s->d)[i]); }
static Obj *mkStringItem(Obj *label, Obj *text) { Obj *o = newObj(loadClass(LCD "StringItem")); o->f[0].a = label; ui_(o, 1)->text = text; return o; }
static void fm_appendItem(Slot *a) { UiD *u = ud(OBJ(0), 2); if (!OBJ(1)) { throwNew("java/lang/NullPointerException", 0); return; } fm_add(u, u->nit, OBJ(1)); a[0].i = u->nit - 1; }
static void fm_appendStr(Slot *a) { UiD *u = ud(OBJ(0), 2); fm_add(u, u->nit, mkStringItem(0, a[1].a)); a[0].i = u->nit - 1; }
static void fm_appendImg(Slot *a) { UiD *u = ud(OBJ(0), 2); Obj *o = newObj(loadClass(LCD "ImageItem")); ui_(o, 5)->img = a[1].a; fm_add(u, u->nit, o); a[0].i = u->nit - 1; }
static void fm_insert(Slot *a) { UiD *u = ud(OBJ(0), 2); if (a[1].i < 0 || a[1].i > u->nit) { throwNew("java/lang/IndexOutOfBoundsException", 0); return; } fm_add(u, a[1].i, OBJ(2)); }
static void fm_set(Slot *a) { UiD *u = ud(OBJ(0), 2); if (a[1].i < 0 || a[1].i >= u->nit) { throwNew("java/lang/IndexOutOfBoundsException", 0); return; } u->items[a[1].i] = OBJ(2); DIRTY(); }
static void fm_delete(Slot *a) { UiD *u = ud(OBJ(0), 2); int i = a[1].i; if (i < 0 || i >= u->nit) { throwNew("java/lang/IndexOutOfBoundsException", 0); return; } memmove(u->items + i, u->items + i + 1, (u->nit - i - 1) * sizeof(Obj *)); u->nit--; DIRTY(); }
static void fm_deleteAll(Slot *a) { ud(OBJ(0), 2)->nit = 0; DIRTY(); (void)a; }
static void fm_get(Slot *a) { UiD *u = ud(OBJ(0), 2); if (a[1].i < 0 || a[1].i >= u->nit) { throwNew("java/lang/IndexOutOfBoundsException", 0); return; } a[0].a = u->items[a[1].i]; }
static void fm_size(Slot *a) { a[0].i = ud(OBJ(0), 2)->nit; }
static void fm_setISL(Slot *a) { ud(OBJ(0), 2)->stateL = a[1].a; }

// ---- Item ----
static void it_getLabel(Slot *a) { a[0].a = OBJ(0)->f[0].a; }
static void it_setLabel(Slot *a) { OBJ(0)->f[0].a = a[1].a; DIRTY(); }
static void si_init(Slot *a) { Obj *o = OBJ(0); o->f[0].a = a[1].a; ui_(o, 1)->text = a[2].a; }
static void si_init3(Slot *a) { si_init(a); }
static void si_getText(Slot *a) { a[0].a = ui_(OBJ(0), 1)->text; }
static void si_setText(Slot *a) { ui_(OBJ(0), 1)->text = a[1].a; DIRTY(); }
static void ga_init(Slot *a) { Obj *o = OBJ(0); UiI *u = ui_(o, 4); o->f[0].a = a[1].a; u->inter = a[2].i; u->gmax = a[3].i; u->gval = a[4].i; }
static void ga_getV(Slot *a) { a[0].i = ui_(OBJ(0), 4)->gval; }
static void ga_setV(Slot *a) { ui_(OBJ(0), 4)->gval = a[1].i; DIRTY(); }
static void ga_getM(Slot *a) { a[0].i = ui_(OBJ(0), 4)->gmax; }
static void ga_setM(Slot *a) { ui_(OBJ(0), 4)->gmax = a[1].i; DIRTY(); }
static void ga_inter(Slot *a) { a[0].i = ui_(OBJ(0), 4)->inter; }
static void ii_init(Slot *a) { Obj *o = OBJ(0); o->f[0].a = a[1].a; ui_(o, 5)->img = a[2].a; }
static void sp_init(Slot *a) { Obj *o = OBJ(0); ui_(o, 6)->ap = a[1].i; ui_(o, 6)->maxSize = a[2].i; }
static void tk_init(Slot *a) { OBJ(0)->f[0].a = a[1].a; }

// ---- Display.setCurrent ----
static int uiIsScreen(Obj *o) { return o && !isCanvas(o); }
static void uiSwitch(Obj *d, Obj *nextAfterAlert) {
  if (g_cur && !isCanvas(g_cur) && ud(g_cur, 0)->kind != 4) g_prevScr = g_cur; else if (g_cur && isCanvas(g_cur)) g_prevScr = g_cur;
  g_cur = d; g_repaint = 1; DIRTY();
  if (d && ud(d, 0)->kind == 4) { UiD *u = ud(d, 4); u->shown = nowMs(); u->next = nextAfterAlert ? nextAfterAlert : g_prevScr; }
  if (isCanvas(d)) { needKey = 1; evPush(EK_SHOW, 0, 0, d); }
}
static void dispSetUi(Slot *a) { Obj *d = OBJ(1); if (!d) return; uiSwitch(d, 0); }
static void dispSetAlertUi(Slot *a) { Obj *al = OBJ(1); if (!al) return; uiSwitch(al, OBJ(2)); }

// ---- JSON mô tả màn hình cho host ----
typedef struct { char *b; int n, cap; } JB;
static void jc(JB *j, int c) { if (j->n + 8 > j->cap) { j->cap = j->cap * 2 + 1024; j->b = realloc(j->b, j->cap); } j->b[j->n++] = (char)c; }
static void js(JB *j, const char *s) { while (*s) jc(j, *s++); }
static void ji(JB *j, int v) { char t[24]; snprintf(t, sizeof t, "%d", v); js(j, t); }
static void jstr(JB *j, Obj *s) {
  jc(j, '"'); int n = s ? S_LEN(s) : 0;
  for (int i = 0; i < n; i++) {
    uint32_t c = S_CH(s)[i];
    if (c >= 0xD800 && c < 0xDC00 && i + 1 < n && S_CH(s)[i + 1] >= 0xDC00 && S_CH(s)[i + 1] < 0xE000) { c = 0x10000 + ((c - 0xD800) << 10) + (S_CH(s)[i + 1] - 0xDC00); i++; }
    if (c == '"' || c == '\\') { jc(j, '\\'); jc(j, c); } else if (c == '\n') js(j, "\\n"); else if (c == '\r') js(j, "\\r"); else if (c == '\t') js(j, "\\t");
    else if (c < 0x20) { char t[8]; snprintf(t, sizeof t, "\\u%04x", c); js(j, t); }
    else if (c < 0x80) jc(j, c); else if (c < 0x800) { jc(j, 0xC0 | (c >> 6)); jc(j, 0x80 | (c & 63)); }
    else if (c < 0x10000) { jc(j, 0xE0 | (c >> 12)); jc(j, 0x80 | ((c >> 6) & 63)); jc(j, 0x80 | (c & 63)); }
    else { jc(j, 0xF0 | (c >> 18)); jc(j, 0x80 | ((c >> 12) & 63)); jc(j, 0x80 | ((c >> 6) & 63)); jc(j, 0x80 | (c & 63)); }
  }
  jc(j, '"');
}
static void jCmds(JB *j, UiD *u) {
  js(j, ",\"commands\":[");
  for (int i = 0; i < u->ncmd; i++) { Obj *c = u->cmd[i]; if (i) jc(j, ','); js(j, "{\"index\":"); ji(j, i); js(j, ",\"label\":"); jstr(j, c->f[0].a); js(j, ",\"type\":"); ji(j, c->f[1].i); js(j, ",\"priority\":"); ji(j, c->f[2].i); jc(j, '}'); }
  jc(j, ']');
}
static void jChoice(JB *j, Choice *c, int withIdx) {
  js(j, "\"options\":[");
  for (int i = 0; i < c->n; i++) { if (i) jc(j, ','); js(j, "{\"index\":"); ji(j, i); js(j, ",\"label\":"); jstr(j, c->it[i].str); js(j, ",\"selected\":"); js(j, c->it[i].sel ? "true" : "false"); jc(j, '}'); }
  jc(j, ']'); (void)withIdx;
}
static char *uiJson(int *len) {
  JB j = {0}; Obj *d = g_cur; UiD *u = d && !isCanvas(d) ? ud(d, 0) : 0;
  if (d && isCanvas(d)) { UiD *cu = ud(d, 0); if (cu->ncmd > 0) { js(&j, "{\"kind\":\"softkeys\",\"id\":"); ji(&j, cu->id); jCmds(&j, cu); jc(&j, '}'); *len = j.n; jc(&j, 0); return j.b; } }
  if (!u || !u->kind) { js(&j, "{\"kind\":\"none\"}"); *len = j.n; jc(&j, 0); return j.b; }
  js(&j, "{\"id\":"); ji(&j, u->id); js(&j, ",\"title\":"); jstr(&j, u->title);
  if (u->kind == 1) { js(&j, ",\"kind\":\"list\",\"choiceType\":"); ji(&j, u->ch.type); js(&j, ",\"selectedIndex\":"); ji(&j, chSelIdx(&u->ch)); jc(&j, ','); jChoice(&j, &u->ch, 1); jCmds(&j, u); }
  else if (u->kind == 2) {
    js(&j, ",\"kind\":\"form\",\"items\":[");
    for (int i = 0; i < u->nit; i++) {
      Obj *it = u->items[i]; UiI *x = ui_(it, 0); if (i) jc(&j, ',');
      js(&j, "{\"index\":"); ji(&j, i); js(&j, ",\"label\":"); jstr(&j, it->f[0].a);
      switch (x->kind) {
        case 2: js(&j, ",\"type\":\"text\",\"value\":"); jstr(&j, x->text); js(&j, ",\"maxSize\":"); ji(&j, x->maxSize); js(&j, ",\"constraints\":"); ji(&j, x->cons); break;
        case 3: js(&j, ",\"type\":\"choice\",\"choiceType\":"); ji(&j, x->ch.type); jc(&j, ','); jChoice(&j, &x->ch, 0); break;
        case 4: js(&j, ",\"type\":\"gauge\",\"interactive\":"); js(&j, x->inter ? "true" : "false"); js(&j, ",\"maxValue\":"); ji(&j, x->gmax); js(&j, ",\"value\":"); ji(&j, x->gval); break;
        case 5: js(&j, ",\"type\":\"image\",\"className\":\"\""); break;
        case 6: js(&j, ",\"type\":\"spacer\""); break;
        default: js(&j, ",\"type\":\"string\",\"value\":"); jstr(&j, x->text);
      }
      jc(&j, '}');
    }
    jc(&j, ']'); jCmds(&j, u);
  } else if (u->kind == 3) { js(&j, ",\"kind\":\"editor\",\"value\":"); jstr(&j, u->text); js(&j, ",\"maxSize\":"); ji(&j, u->maxSize); js(&j, ",\"constraints\":"); ji(&j, u->cons); jCmds(&j, u); }
  else { js(&j, ",\"kind\":\"alert\",\"text\":"); jstr(&j, u->text); js(&j, ",\"timeout\":"); ji(&j, u->timeout); jCmds(&j, u); }
  jc(&j, '}'); *len = j.n; jc(&j, 0); return j.b;
}

// ---- hàng đợi: JSON ra host, thao tác từ host ----
static pthread_mutex_t uimu = PTHREAD_MUTEX_INITIALIZER;
static char *uiOut; static int uiOutLen, uiOutNew;
static char *uiActs[64]; static int uiAh, uiAt;
int midpUiPoll(char *buf, int cap) {
  int r = 0; pthread_mutex_lock(&uimu);
  if (uiOutNew && uiOut) { if (uiOutLen + 1 > cap) r = -(uiOutLen + 1); else { memcpy(buf, uiOut, uiOutLen + 1); r = uiOutLen; uiOutNew = 0; } }
  pthread_mutex_unlock(&uimu); return r;
}
void midpUiAction(const char *s) { pthread_mutex_lock(&uimu); int n = (uiAt + 1) % 64; if (n != uiAh) { uiActs[uiAt] = strdup(s); uiAt = n; } pthread_mutex_unlock(&uimu); }

static Obj *utf8Str(const char *s) {
  size_t n = strlen(s); uint16_t *b = malloc((n + 1) * 2); int k = 0;
  for (size_t i = 0; i < n;) { uint8_t c = s[i]; uint32_t cp; int l;
    if (c < 0x80) { cp = c; l = 1; } else if ((c >> 5) == 6 && i + 1 < n) { cp = ((c & 31) << 6) | (s[i + 1] & 63); l = 2; } else if ((c >> 4) == 14 && i + 2 < n) { cp = ((c & 15) << 12) | ((s[i + 1] & 63) << 6) | (s[i + 2] & 63); l = 3; }
    else if ((c >> 3) == 30 && i + 3 < n) { cp = ((c & 7) << 18) | ((s[i + 1] & 63) << 12) | ((s[i + 2] & 63) << 6) | (s[i + 3] & 63); l = 4; } else { cp = '?'; l = 1; }
    i += l; if (cp >= 0x10000) { cp -= 0x10000; b[k++] = 0xD800 + (cp >> 10); b[k++] = 0xDC00 + (cp & 1023); } else b[k++] = cp; }
  Obj *r = newStr16(b, k); free(b); return r;
}
static void uiFire(Obj *scr, Obj *cmd, int idx) { evPush(EK_CMD, idx, 0, scr); (void)cmd; }
static void uiApply(const char *s) {
  Obj *d = g_cur; if (!d) return;
  if (isCanvas(d)) { if (s[0] == 'K') { UiD *cu = ud(d, 0); int i = atoi(s + 1); if (i >= 0 && i < cu->ncmd) uiFire(d, cu->cmd[i], i); } return; }
  UiD *u = ud(d, 0); if (!u->kind) return;
  switch (s[0]) {
    case 'K': { int i = atoi(s + 1); if (i >= 0 && i < u->ncmd) uiFire(d, u->cmd[i], i); if (u->kind == 4 && (u->ncmd == 0 || 1) && i >= 0) { /* lệnh của Alert: giữ nguyên */ } break; }
    case 'D': if (u->kind == 4 && u->next) { uiSwitch(u->next, 0); } break;
    case 'L': { int i = atoi(s + 1); if (u->kind == 1 && i >= 0 && i < u->ch.n) { chSetSel(&u->ch, i, 1); uiFire(d, 0, -1); } break; }
    case 'M': if (u->kind == 1) chSetBits(&u->ch, s + 1); break;
    case 'E': if (u->kind == 3) u->text = utf8Str(s + 1); break;
    case 'T': case 'S': case 'G': {
      int i = atoi(s + 1); const char *c = strchr(s, ':'); if (u->kind != 2 || !c || i < 0 || i >= u->nit) break; Obj *it = u->items[i]; UiI *x = ui_(it, 0);
      if (s[0] == 'T' && x->kind == 2) { x->text = utf8Str(c + 1); }
      else if (s[0] == 'S' && x->kind == 3) { chSetBits(&x->ch, c + 1); evPush(EK_ITEM, i, 0, d); }
      else if (s[0] == 'G' && x->kind == 4) { x->gval = atoi(c + 1); evPush(EK_ITEM, i, 0, d); }
      break; }
  }
}
// gọi trên luồng lập lịch (midpIdle): xử lý thao tác và cập nhật JSON khi có thay đổi
static void uiTick(void) {
  for (;;) { char *s = 0; pthread_mutex_lock(&uimu); if (uiAh != uiAt) { s = uiActs[uiAh]; uiAh = (uiAh + 1) % 64; } pthread_mutex_unlock(&uimu); if (!s) break; uiApply(s); free(s); }
  if (g_cur && !isCanvas(g_cur)) { UiD *u = ud(g_cur, 0); if (u->kind == 4 && u->timeout > 0 && u->next && nowMs() - u->shown >= u->timeout) uiSwitch(u->next, 0); }
  if (g_uiDirty) {
    g_uiDirty = 0; int n; char *j = uiJson(&n);
    pthread_mutex_lock(&uimu); free(uiOut); uiOut = j; uiOutLen = n; uiOutNew = 1; pthread_mutex_unlock(&uimu);
  }
}

static void uiInstall(void) {
  const char *DP = LCD "Displayable", *L = LCD "List", *CG = LCD "ChoiceGroup", *F = LCD "Form", *T = LCD "TextBox", *TF = LCD "TextField", *A = LCD "Alert", *SI = LCD "StringItem", *GA = LCD "Gauge", *II = LCD "ImageItem", *SP = LCD "Spacer", *IT = LCD "Item", *TK = LCD "Ticker";
  NI(DP, "setTitle", "(Ljava/lang/String;)V", dp_setTitle); NI(DP, "getTitle", "()Ljava/lang/String;", dp_getTitle);
  NI(DP, "addCommand", "(Ljavax/microedition/lcdui/Command;)V", dp_addCmd); NI(DP, "removeCommand", "(Ljavax/microedition/lcdui/Command;)V", dp_rmCmd);
  NI(DP, "setTicker", "(Ljavax/microedition/lcdui/Ticker;)V", dp_setTicker); NI(DP, "getTicker", "()Ljavax/microedition/lcdui/Ticker;", dp_getTicker);
  NI(DP, "setCommandListener", "(Ljavax/microedition/lcdui/CommandListener;)V", dp_setListener);
  const char *CS[2] = {L, CG};
  for (int i = 0; i < 2; i++) {
    const char *c = CS[i];
    NI(c, "<init>", "(Ljava/lang/String;I)V", ch_init); NI(c, "<init>", "(Ljava/lang/String;I[Ljava/lang/String;[Ljavax/microedition/lcdui/Image;)V", ch_initFull);
    NI(c, "append", "(Ljava/lang/String;Ljavax/microedition/lcdui/Image;)I", ch_append); NI(c, "insert", "(ILjava/lang/String;Ljavax/microedition/lcdui/Image;)V", ch_insert);
    NI(c, "size", "()I", ch_size); NI(c, "getString", "(I)Ljava/lang/String;", ch_getString); NI(c, "getImage", "(I)Ljavax/microedition/lcdui/Image;", ch_getImage);
    NI(c, "delete", "(I)V", ch_delete); NI(c, "deleteAll", "()V", ch_deleteAll); NI(c, "set", "(ILjava/lang/String;Ljavax/microedition/lcdui/Image;)V", ch_set);
    NI(c, "getSelectedIndex", "()I", ch_getSel); NI(c, "setSelectedIndex", "(IZ)V", ch_setSel); NI(c, "isSelected", "(I)Z", ch_isSel);
    NI(c, "getSelectedFlags", "([Z)I", ch_getFlags); NI(c, "setSelectedFlags", "([Z)V", ch_setFlags);
    NI(c, "setFitPolicy", "(I)V", ui_nop); NI(c, "getFitPolicy", "()I", ch_zero); NI(c, "setFont", "(ILjavax/microedition/lcdui/Font;)V", ui_nop); NI(c, "getFont", "(I)Ljavax/microedition/lcdui/Font;", ui_zeroR);
  }
  NI(L, "setSelectCommand", "(Ljavax/microedition/lcdui/Command;)V", ch_selCmd);
  NI(T, "<init>", "(Ljava/lang/String;Ljava/lang/String;II)V", tb_init); NI(TF, "<init>", "(Ljava/lang/String;Ljava/lang/String;II)V", tb_init);
  const char *TT[2] = {T, TF};
  for (int i = 0; i < 2; i++) { const char *c = TT[i];
    NI(c, "getString", "()Ljava/lang/String;", tb_get); NI(c, "setString", "(Ljava/lang/String;)V", tb_set); NI(c, "size", "()I", tb_size); NI(c, "setMaxSize", "(I)I", tb_max); NI(c, "getMaxSize", "()I", tb_getMax);
    NI(c, "getConstraints", "()I", tb_cons); NI(c, "setConstraints", "(I)V", tb_setCons); NI(c, "insert", "(Ljava/lang/String;I)V", tb_insert); NI(c, "delete", "(II)V", tb_delete);
    NI(c, "getChars", "([C)I", tb_getChars); NI(c, "setChars", "([CII)V", tb_setChars); NI(c, "getCaretPosition", "()I", tb_caret); NI(c, "setInitialInputMode", "(Ljava/lang/String;)V", ui_nop); }
  NI(A, "<init>", "(Ljava/lang/String;)V", al_init1); NI(A, "<init>", "(Ljava/lang/String;Ljava/lang/String;Ljavax/microedition/lcdui/Image;Ljavax/microedition/lcdui/AlertType;)V", al_init4);
  NI(A, "setString", "(Ljava/lang/String;)V", al_setString); NI(A, "getString", "()Ljava/lang/String;", al_getString); NI(A, "setTimeout", "(I)V", al_setTimeout); NI(A, "getTimeout", "()I", al_getTimeout);
  NI(A, "setType", "(Ljavax/microedition/lcdui/AlertType;)V", ui_nop); NI(A, "setImage", "(Ljavax/microedition/lcdui/Image;)V", ui_nop); NI(A, "setIndicator", "(Ljavax/microedition/lcdui/Gauge;)V", ui_nop);
  NS(LCD "AlertType", "playSound", "(Ljavax/microedition/lcdui/Display;)Z", ui_zeroR);
  NI(F, "<init>", "(Ljava/lang/String;)V", fm_init); NI(F, "<init>", "(Ljava/lang/String;[Ljavax/microedition/lcdui/Item;)V", fm_initItems);
  NI(F, "append", "(Ljavax/microedition/lcdui/Item;)I", fm_appendItem); NI(F, "append", "(Ljava/lang/String;)I", fm_appendStr); NI(F, "append", "(Ljavax/microedition/lcdui/Image;)I", fm_appendImg);
  NI(F, "insert", "(ILjavax/microedition/lcdui/Item;)V", fm_insert); NI(F, "set", "(ILjavax/microedition/lcdui/Item;)V", fm_set); NI(F, "delete", "(I)V", fm_delete); NI(F, "deleteAll", "()V", fm_deleteAll);
  NI(F, "get", "(I)Ljavax/microedition/lcdui/Item;", fm_get); NI(F, "size", "()I", fm_size); NI(F, "setItemStateListener", "(Ljavax/microedition/lcdui/ItemStateListener;)V", fm_setISL);
  NI(IT, "getLabel", "()Ljava/lang/String;", it_getLabel); NI(IT, "setLabel", "(Ljava/lang/String;)V", it_setLabel);
  NI(SI, "<init>", "(Ljava/lang/String;Ljava/lang/String;)V", si_init); NI(SI, "<init>", "(Ljava/lang/String;Ljava/lang/String;I)V", si_init3); NI(SI, "getText", "()Ljava/lang/String;", si_getText); NI(SI, "setText", "(Ljava/lang/String;)V", si_setText);
  NI(GA, "<init>", "(Ljava/lang/String;ZII)V", ga_init); NI(GA, "getValue", "()I", ga_getV); NI(GA, "setValue", "(I)V", ga_setV); NI(GA, "getMaxValue", "()I", ga_getM); NI(GA, "setMaxValue", "(I)V", ga_setM); NI(GA, "isInteractive", "()Z", ga_inter);
  NI(II, "<init>", "(Ljava/lang/String;Ljavax/microedition/lcdui/Image;ILjava/lang/String;)V", ii_init); NI(II, "<init>", "(Ljava/lang/String;Ljavax/microedition/lcdui/Image;ILjava/lang/String;I)V", ii_init);
  NI(SP, "<init>", "(II)V", sp_init); NI(TK, "<init>", "(Ljava/lang/String;)V", tk_init);
  NI(LCD "Display", "setCurrent", "(Ljavax/microedition/lcdui/Displayable;)V", dispSetUi); NI(LCD "Display", "setCurrent", "(Ljavax/microedition/lcdui/Alert;Ljavax/microedition/lcdui/Displayable;)V", dispSetAlertUi);
  Class *lc = loadClass(L); Obj *sc = newObj(loadClass(LCD "Command")); sc->f[0].a = newStr("Select"); sc->f[1].i = 1; sc->f[2].i = 0; lc->statics[0].a = sc;
}
