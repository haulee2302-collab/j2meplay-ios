// Socket thật: Connector.open("socket://host:port") → SocketConnection. Kết nối TCP do host (Dart) làm; lõi C giữ bộ đệm nhận/gửi.
// Đọc chờ dữ liệu bằng g_retry (các luồng Java khác vẫn chạy). Dữ liệu gửi được gom và đẩy đi sau vài mili giây hoặc khi flush/close.
typedef struct SK { int id, state; /* 0 đang nối, 1 mở, 2 đóng, 3 lỗi */ uint8_t *rb, *wb; int rl, rc, rp, wl, wc; int64_t wt, deadline; char url[300]; struct SK *pend; } SK;
typedef struct SMsg { char k; int id; uint8_t *d; int n; struct SMsg *next; } SMsg;
static pthread_mutex_t smu = PTHREAD_MUTEX_INITIALIZER; static SMsg *sqh, *sqt; static SK *sks[128]; static int nsk, sid; static SK *spend[16]; static int nspend;
static void sockPost(char k, int id, const uint8_t *d, int n) {
  SMsg *m = calloc(1, sizeof *m); m->k = k; m->id = id; m->n = n; if (n) { m->d = malloc(n); memcpy(m->d, d, n); }
  pthread_mutex_lock(&smu); if (sqt) sqt->next = m; else sqh = m; sqt = m; pthread_mutex_unlock(&smu);
}
int midpSockPoll(uint8_t *buf, int cap) {
  pthread_mutex_lock(&smu); SMsg *m = sqh; if (!m) { pthread_mutex_unlock(&smu); return 0; }
  if (5 + m->n > cap) { int r = -(5 + m->n); pthread_mutex_unlock(&smu); return r; }
  sqh = m->next; if (!sqh) sqt = 0; pthread_mutex_unlock(&smu);
  buf[0] = (uint8_t)m->k; buf[1] = m->id >> 24; buf[2] = m->id >> 16; buf[3] = m->id >> 8; buf[4] = m->id; if (m->n) memcpy(buf + 5, m->d, m->n);
  int r = 5 + m->n; free(m->d); free(m); return r;
}
static SK *skFind(int id) { for (int i = 0; i < nsk; i++) if (sks[i] && sks[i]->id == id) return sks[i]; return 0; }
// kind: 1 đã nối, 2 có dữ liệu, 3 đóng, 4 lỗi
void midpSockEvent(int id, int kind, const uint8_t *d, int n) {
  pthread_mutex_lock(&smu); SK *s = skFind(id);
  if (s) {
    if (kind == 1) s->state = 1;
    else if (kind == 2 && n > 0) { if (s->rp > 0 && s->rp == s->rl) s->rp = s->rl = 0; if (s->rl + n > s->rc) { s->rc = (s->rl + n) * 2; s->rb = realloc(s->rb, s->rc); } memcpy(s->rb + s->rl, d, n); s->rl += n; }
    else if (kind == 3) { if (s->state != 3) s->state = 2; }
    else if (kind == 4) s->state = 3;
  }
  pthread_mutex_unlock(&smu);
}
static void skFlush(SK *s) {
  pthread_mutex_lock(&smu); int n = s->wl; uint8_t *d = 0; if (n > 0) { d = s->wb; s->wb = 0; s->wl = s->wc = 0; } pthread_mutex_unlock(&smu);
  if (d) { for (int o = 0; o < n; o += 32768) sockPost('W', s->id, d + o, n - o > 32768 ? 32768 : n - o); free(d); }
}
static void sockTick(void) { int64_t t = nowMs(); for (int i = 0; i < nsk; i++) { SK *s = sks[i]; if (s && s->state == 1 && s->wl > 0 && t - s->wt >= 3) skFlush(s); } }
static void sockReset(void) { for (int i = 0; i < nsk; i++) if (sks[i] && sks[i]->state <= 1) sockPost('C', sks[i]->id, 0, 0); nspend = 0; }

static int sockWaitFn(Obj *in, int need) {
  SK *s = in->f[0].a;
  for (;;) {
    pthread_mutex_lock(&smu); int av = s->rl - s->rp, st = s->state; pthread_mutex_unlock(&smu);
    if (av >= need || st >= 2 || g_stop) return 1;
    if (vmRetry(4)) return 0;
    nanosleep(&(struct timespec){0, 2000000}, 0);
  }
}
static int sockTakeFn(Obj *in, uint8_t *out, int n, int peek) {
  SK *s = in->f[0].a; pthread_mutex_lock(&smu); int av = s->rl - s->rp; if (n > av) n = av; if (n > 0) { memcpy(out, s->rb + s->rp, n); if (!peek) s->rp += n; } pthread_mutex_unlock(&smu); return n;
}
static void sockPutFn(Obj *out, const uint8_t *d, int n) {
  SK *s = out->f[0].a; pthread_mutex_lock(&smu);
  if (s->state >= 2) { pthread_mutex_unlock(&smu); throwNew("java/io/IOException", "socket đã đóng"); return; }
  if (s->wl + n > s->wc) { s->wc = (s->wl + n) * 2 + 64; s->wb = realloc(s->wb, s->wc); } memcpy(s->wb + s->wl, d, n); if (!s->wl) s->wt = nowMs(); s->wl += n; pthread_mutex_unlock(&smu);
}
// SocketConnection
static int isSock(Obj *s) { char u[16]; cstr(s, u, sizeof u); return !strncmp(u, "socket://", 9); }
static void sock_open(Slot *a) {
  Obj *us = OBJ(0); char url[300]; cstr(us, url, sizeof url); SK *s = 0; int pi = -1;
  for (int i = 0; i < nspend; i++) if (!strcmp(spend[i]->url, url)) { s = spend[i]; pi = i; break; }
  if (!s) {
    const char *p = url + 9; char hp[260]; int n = 0; while (*p && *p != ';' && n < 255) hp[n++] = *p++; hp[n] = 0;
    if (!strchr(hp, ':') || hp[0] == ':') { throwNew("java/lang/IllegalArgumentException", url); return; }
    s = calloc(1, sizeof *s); snprintf(s->url, sizeof s->url, "%s", url); s->deadline = nowMs() + 20000;
    pthread_mutex_lock(&smu); s->id = ++sid; if (nsk < 128) sks[nsk++] = s; pthread_mutex_unlock(&smu);
    if (nspend < 16) { spend[nspend++] = s; pi = nspend - 1; }
    sockPost('O', s->id, (const uint8_t *)hp, (int)strlen(hp));
  }
  for (;;) {
    pthread_mutex_lock(&smu); int st = s->state; pthread_mutex_unlock(&smu);
    if (st != 0 || nowMs() > s->deadline || g_stop) {
      if (pi >= 0) { spend[pi] = spend[--nspend]; }
      if (st == 1) { Obj *o = newObj(loadClass("javax/microedition/io/SocketConnection")); o->f[0].a = s; a[0].a = o; return; }
      s->state = 3; sockPost('C', s->id, 0, 0); throwNew("javax/microedition/io/ConnectionNotFoundException", url); return;
    }
    if (vmRetry(4)) return;
    nanosleep(&(struct timespec){0, 2000000}, 0);
  }
}
static SK *skOf(Obj *o) { return o->f[0].a; }
static Obj *skIn(Obj *c) { Obj *o = newObj(loadClass("javax/microedition/io/SockIn")); o->f[0].a = skOf(c); return o; }
static Obj *skOut(Obj *c) { Obj *o = newObj(loadClass("javax/microedition/io/SockOut")); o->f[0].a = skOf(c); return o; }
static void sc_in(Slot *a) { a[0].a = skIn(OBJ(0)); }
static void sc_din(Slot *a) { Obj *d = newObj(loadClass("java/io/DataInputStream")); d->f[0].a = skIn(OBJ(0)); a[0].a = d; }
static void sc_out(Slot *a) { a[0].a = skOut(OBJ(0)); }
static void sc_dout(Slot *a) { Obj *d = newObj(loadClass("java/io/DataOutputStream")); d->f[0].a = skOut(OBJ(0)); a[0].a = d; }
static void sc_close(Slot *a) { SK *s = skOf(OBJ(0)); if (s->state == 1) { skFlush(s); sockPost('C', s->id, 0, 0); } if (s->state <= 1) s->state = 2; }
static void sc_nop(Slot *a) { (void)a; }
static void sc_zero(Slot *a) { a[0].i = 0; }
static void sc_addr(Slot *a) { SK *s = skOf(OBJ(0)); const char *p = s->url + 9; const char *e = p; while (*e && *e != ':' && *e != ';') e++; a[0].a = mkStrN(p, (int)(e - p)); }
static void sc_port(Slot *a) { SK *s = skOf(OBJ(0)); const char *p = strchr(s->url + 9, ':'); a[0].i = p ? atoi(p + 1) : 0; }
// SockIn / SockOut
static void si_read(Slot *a) { Obj *o = OBJ(0); if (!sockWaitFn(o, 1)) return; uint8_t b; a[0].i = sockTakeFn(o, &b, 1, 0) > 0 ? b : -1; }
static void si_readBII(Slot *a) { Obj *o = OBJ(0); Arr *b = ARR(1); int off = a[2].i, n = a[3].i; if (!b || off < 0 || n < 0 || off + n > b->len) { throwNew("java/lang/IndexOutOfBoundsException", 0); return; } if (n == 0) { a[0].i = 0; return; } if (!sockWaitFn(o, 1)) return; int k = sockTakeFn(o, b->d + off, n, 0); a[0].i = k > 0 ? k : -1; }
static void si_readB(Slot *a) { Arr *b = ARR(1); if (!b) { throwNew("java/lang/NullPointerException", 0); return; } Slot t[4]; t[0] = a[0]; t[1] = a[1]; t[2].i = 0; t[3].i = b->len; si_readBII(t); a[0] = t[0]; }
static void si_avail(Slot *a) { SK *s = skOf(OBJ(0)); pthread_mutex_lock(&smu); a[0].i = s->rl - s->rp; pthread_mutex_unlock(&smu); }
static void so_write(Slot *a) { uint8_t b = (uint8_t)a[1].i; sockPutFn(OBJ(0), &b, 1); }
static void so_writeB(Slot *a) { Arr *b = ARR(1); if (!b) { throwNew("java/lang/NullPointerException", 0); return; } sockPutFn(OBJ(0), b->d, b->len); }
static void so_writeBII(Slot *a) { Arr *b = ARR(1); int off = a[2].i, n = a[3].i; if (!b || off < 0 || n < 0 || off + n > b->len) { throwNew("java/lang/IndexOutOfBoundsException", 0); return; } sockPutFn(OBJ(0), b->d + off, n); }
static void so_flush(Slot *a) { skFlush(skOf(OBJ(0))); }
static void sockInstall(void) {
  g_sockInCls = loadClass("javax/microedition/io/SockIn"); g_sockOutCls = loadClass("javax/microedition/io/SockOut");
  g_sockWait = sockWaitFn; g_sockTake = sockTakeFn; g_sockPut = sockPutFn;
  const char *C = "javax/microedition/io/SocketConnection", *I = "javax/microedition/io/SockIn", *O = "javax/microedition/io/SockOut";
  NI(C, "openInputStream", "()Ljava/io/InputStream;", sc_in); NI(C, "openDataInputStream", "()Ljava/io/DataInputStream;", sc_din);
  NI(C, "openOutputStream", "()Ljava/io/OutputStream;", sc_out); NI(C, "openDataOutputStream", "()Ljava/io/DataOutputStream;", sc_dout);
  NI(C, "close", "()V", sc_close); NI(C, "setSocketOption", "(BI)V", sc_nop); NI(C, "getSocketOption", "(B)I", sc_zero);
  NI(C, "getAddress", "()Ljava/lang/String;", sc_addr); NI(C, "getLocalAddress", "()Ljava/lang/String;", sc_addr); NI(C, "getPort", "()I", sc_port); NI(C, "getLocalPort", "()I", sc_zero);
  NI(I, "read", "()I", si_read); NI(I, "read", "([B)I", si_readB); NI(I, "read", "([BII)I", si_readBII); NI(I, "available", "()I", si_avail); NI(I, "close", "()V", sc_nop);
  NI(O, "write", "(I)V", so_write); NI(O, "write", "([B)V", so_writeB); NI(O, "write", "([BII)V", so_writeBII); NI(O, "flush", "()V", so_flush); NI(O, "close", "()V", so_flush);
}
