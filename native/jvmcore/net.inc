extern volatile int g_stop;
// javax.microedition.io: Connector.open("http(s)://...") → HttpConnection. Việc gửi nhận do host (Dart) làm: lõi C đặt yêu cầu vào
// hàng đợi rồi chờ kết quả (cả máy ảo tạm dừng trong lúc chờ, tối đa 30 giây). Các giao thức khác (socket, sms, file...) báo ConnectionNotFoundException.
typedef struct HC { char url[1024], method[16]; Obj *ks[24], *vs[24]; int nh; Obj *out; int done, posted, id, status, rlen; int64_t deadline; uint8_t *resp; char *rh; } HC;
static pthread_mutex_t nmu = PTHREAD_MUTEX_INITIALIZER; static pthread_cond_t ncv = PTHREAD_COND_INITIALIZER;
static char *nreq; static int nreqLen, nid, nwait, nflag, nstatus, nbLen; static uint8_t *nbody; static char *nhdr;

int midpNetPoll(uint8_t *buf, int cap) {
  int r = 0; pthread_mutex_lock(&nmu);
  if (nreq) { if (nreqLen > cap) r = -nreqLen; else { memcpy(buf, nreq, nreqLen); r = nreqLen; free(nreq); nreq = 0; } }
  pthread_mutex_unlock(&nmu); return r;
}
void midpNetDone(int id, int status, const uint8_t *hdr, int hlen, const uint8_t *body, int blen) {
  pthread_mutex_lock(&nmu);
  if (id == nwait) {
    free(nbody); free(nhdr); nbody = malloc(blen + 1); memcpy(nbody, body, blen); nbLen = blen; nhdr = malloc(hlen + 1); memcpy(nhdr, hdr, hlen); nhdr[hlen] = 0; nstatus = status; nflag = 1;
    pthread_cond_broadcast(&ncv);
  }
  pthread_mutex_unlock(&nmu);
}
static HC *hcOf(Obj *o) { return o->f[0].a; }
// Trả 1 khi đã có kết quả (h->status); 0 khi phải thoát native ngay (đã xin chạy lại, hoặc đã ném ngoại lệ).
static int hcExec(HC *h, int canRetry) {
  if (h->done) return 1;
  if (!h->posted) {
    pthread_mutex_lock(&nmu); int busy = nwait != 0 || nreq; pthread_mutex_unlock(&nmu);
    if (busy) { if (canRetry && vmRetry(4)) return 0; nanosleep(&(struct timespec){0, 4000000}, 0); return hcExec(h, canRetry); }
    int bl = 0; const uint8_t *bd = 0; if (h->out) { bl = h->out->f[1].i; bd = h->out->f[0].a; }
    int cap = 2048 + bl + h->nh * 620; char *r = malloc(cap); int n = 0;
    pthread_mutex_lock(&nmu); h->id = ++nid; pthread_mutex_unlock(&nmu);
    n += snprintf(r + n, cap - n, "%d\n%s\n%s\n", h->id, h->method, h->url);
    for (int i = 0; i < h->nh; i++) { char k[200], v[400]; cstr(h->ks[i], k, sizeof k); cstr(h->vs[i], v, sizeof v); n += snprintf(r + n, cap - n, "%s: %s\n", k, v); }
    n += snprintf(r + n, cap - n, "\n"); if (bl) { memcpy(r + n, bd, bl); n += bl; }
    pthread_mutex_lock(&nmu); free(nreq); nreq = r; nreqLen = n; nwait = h->id; nflag = 0; pthread_mutex_unlock(&nmu);
    h->posted = 1; h->deadline = nowMs() + 30000;
  }
  for (;;) {
    pthread_mutex_lock(&nmu);
    if (nflag && nwait == h->id) { h->status = nstatus; h->resp = nbody; h->rlen = nbLen; h->rh = nhdr; nbody = 0; nhdr = 0; nwait = 0; nflag = 0; pthread_mutex_unlock(&nmu); break; }
    if (nowMs() > h->deadline || g_stop) { h->status = 0; free(nreq); nreq = 0; nwait = 0; pthread_mutex_unlock(&nmu); break; }
    pthread_mutex_unlock(&nmu);
    if (canRetry && vmRetry(4)) return 0;
    nanosleep(&(struct timespec){0, 2000000}, 0);
  }
  h->done = 1;
  if (h->status <= 0) { throwNew("java/io/IOException", "không kết nối được"); return 0; }
  return 1;
}
static Obj *hcNew(Obj *urlS, int withBody) {
  char u[1024]; cstr(urlS, u, sizeof u); Obj *o = newObj(loadClass("javax/microedition/io/HttpConnection")); HC *h = calloc(1, sizeof *h);
  snprintf(h->url, sizeof h->url, "%s", u); snprintf(h->method, sizeof h->method, "GET"); o->f[0].a = h; (void)withBody; return o;
}
static int isHttp(Obj *s) { char u[16]; cstr(s, u, sizeof u); return !strncmp(u, "http://", 7) || !strncmp(u, "https://", 8); }
static int isSock(Obj *s);
static void sock_open(Slot *a);
static void con_open(Slot *a) {
  Obj *u = OBJ(0); if (!u) { throwNew("java/lang/IllegalArgumentException", "url null"); return; }
  if (isSock(u)) { sock_open(a); return; }
  if (!isHttp(u)) { char b[120]; cstr(u, b, sizeof b); throwNew("javax/microedition/io/ConnectionNotFoundException", b); return; }
  a[0].a = hcNew(u, 0);
}
static Obj *wrapDIS(Obj *in) { Obj *d = newObj(loadClass("java/io/DataInputStream")); d->f[0].a = in; return d; }
static Obj *hcIn(HC *h, int canRetry) { if (!hcExec(h, canRetry)) return 0; return newBytesStream(h->resp ? h->resp : (const uint8_t *)"", h->rlen); }
static void con_openIn(Slot *a) { Obj *u = OBJ(0); if (!u || !isHttp(u)) { con_open(a); return; } Obj *c = hcNew(u, 0); Obj *s = hcIn(hcOf(c), 0); if (!g_exc) a[0].a = s; }
static void con_openDIn(Slot *a) { Obj *u = OBJ(0); if (!u || !isHttp(u)) { con_open(a); return; } Obj *c = hcNew(u, 0); Obj *s = hcIn(hcOf(c), 0); if (!g_exc) a[0].a = wrapDIS(s); }
static void hc_setMethod(Slot *a) { HC *h = hcOf(OBJ(0)); char m[16]; cstr(OBJ(1), m, sizeof m); snprintf(h->method, sizeof h->method, "%s", m); }
static void hc_setProp(Slot *a) { HC *h = hcOf(OBJ(0)); if (!OBJ(1) || h->nh >= 24) return; for (int i = 0; i < h->nh; i++) if (h->ks[i] && jequals(h->ks[i], OBJ(1))) { h->vs[i] = OBJ(2); return; } h->ks[h->nh] = OBJ(1); h->vs[h->nh++] = OBJ(2); }
static void hc_getProp(Slot *a) { HC *h = hcOf(OBJ(0)); for (int i = 0; i < h->nh; i++) if (jequals(h->ks[i], OBJ(1))) { a[0].a = h->vs[i]; return; } a[0].a = 0; }
static void hc_code(Slot *a) { HC *h = hcOf(OBJ(0)); if (!hcExec(h, 1)) return; a[0].i = h->status; }
static void hc_msg(Slot *a) { HC *h = hcOf(OBJ(0)); if (!hcExec(h, 1)) return; a[0].a = newStr(h->status == 200 ? "OK" : ""); }
static const char *hdrFind(HC *h, const char *key, int *vl) {
  if (!h->rh) return 0; size_t kl = strlen(key);
  for (char *p = h->rh; *p;) { char *e = strchr(p, '\n'); size_t ll = e ? (size_t)(e - p) : strlen(p);
    if (ll > kl && p[kl] == ':' && !strncasecmp(p, key, kl)) { const char *v = p + kl + 1; while (*v == ' ') v++; *vl = (int)(ll - (size_t)(v - p)); return v; }
    p = e ? e + 1 : p + ll; }
  return 0;
}
static Obj *mkStrN(const char *s, int n) { char *t = malloc(n + 1); memcpy(t, s, n); t[n] = 0; Obj *o = utf8Str(t); free(t); return o; }
static void hc_hdr(Slot *a) { HC *h = hcOf(OBJ(0)); if (!hcExec(h, 1)) return; char k[120]; cstr(OBJ(1), k, sizeof k); int vl; const char *v = hdrFind(h, k, &vl); a[0].a = v ? mkStrN(v, vl) : 0; }
static void hc_hdrN(Slot *a) { HC *h = hcOf(OBJ(0)); if (!hcExec(h, 1)) return; int n = a[1].i; a[0].a = 0; if (!h->rh) return; for (char *p = h->rh; *p && n >= 0; n--) { char *e = strchr(p, '\n'); size_t ll = e ? (size_t)(e - p) : strlen(p); if (n == 0) { char *c = memchr(p, ':', ll); if (c) { const char *v = c + 1; while (*v == ' ') v++; a[0].a = mkStrN(v, (int)(ll - (size_t)(v - p))); } return; } p = e ? e + 1 : p + ll; } }
static void hc_hdrK(Slot *a) { HC *h = hcOf(OBJ(0)); if (!hcExec(h, 1)) return; int n = a[1].i; a[0].a = 0; if (!h->rh) return; for (char *p = h->rh; *p && n >= 0; n--) { char *e = strchr(p, '\n'); size_t ll = e ? (size_t)(e - p) : strlen(p); if (n == 0) { char *c = memchr(p, ':', ll); if (c) a[0].a = mkStrN(p, (int)(c - p)); return; } p = e ? e + 1 : p + ll; } }
static void hc_len(Slot *a) { HC *h = hcOf(OBJ(0)); if (!hcExec(h, 1)) return; int vl; const char *v = hdrFind(h, "Content-Length", &vl); a[0].l = v ? atoll(v) : h->rlen; }
static void hc_type(Slot *a) { HC *h = hcOf(OBJ(0)); if (!hcExec(h, 1)) return; int vl; const char *v = hdrFind(h, "Content-Type", &vl); a[0].a = v ? mkStrN(v, vl) : 0; }
static void hc_enc(Slot *a) { a[0].a = 0; }
static void hc_url(Slot *a) { a[0].a = newStr(hcOf(OBJ(0))->url); }
static void hc_zeroL(Slot *a) { a[0].l = 0; }
static void hc_open(Slot *a) { Obj *c = OBJ(0); Obj *s = hcIn(hcOf(c), 1); if (g_retry || g_exc) return; a[0].a = s; }
static void hc_openD(Slot *a) { Obj *c = OBJ(0); Obj *s = hcIn(hcOf(c), 1); if (g_retry || g_exc) return; a[0].a = wrapDIS(s); }
static Obj *hcOut(Obj *c) { HC *h = hcOf(c); if (!h->out) { h->out = newObj(loadClass("java/io/ByteArrayOutputStream")); h->out->f[0].a = calloc(64, 1); h->out->f[1].i = 0; h->out->f[2].i = 64; if (!strcmp(h->method, "GET")) snprintf(h->method, sizeof h->method, "POST"); } return h->out; }
static void hc_openOut(Slot *a) { a[0].a = hcOut(OBJ(0)); }
static void hc_openDOut(Slot *a) { Obj *o = newObj(loadClass("java/io/DataOutputStream")); o->f[0].a = hcOut(OBJ(0)); a[0].a = o; }
static void hc_close(Slot *a) { (void)a; }
static void hc_host(Slot *a) { HC *h = hcOf(OBJ(0)); const char *p = strstr(h->url, "://"); p = p ? p + 3 : h->url; const char *e = p; while (*e && *e != '/' && *e != ':') e++; a[0].a = mkStrN(p, (int)(e - p)); }
static void hc_port(Slot *a) { HC *h = hcOf(OBJ(0)); const char *p = strstr(h->url, "://"); p = p ? p + 3 : h->url; while (*p && *p != '/' && *p != ':') p++; a[0].i = *p == ':' ? atoi(p + 1) : (!strncmp(h->url, "https", 5) ? 443 : 80); }
static void netInstall(void) {
  const char *H = "javax/microedition/io/HttpConnection", *C = "javax/microedition/io/Connector";
  NS(C, "open", "(Ljava/lang/String;)Ljavax/microedition/io/Connection;", con_open); NS(C, "open", "(Ljava/lang/String;I)Ljavax/microedition/io/Connection;", con_open); NS(C, "open", "(Ljava/lang/String;IZ)Ljavax/microedition/io/Connection;", con_open);
  NS(C, "openInputStream", "(Ljava/lang/String;)Ljava/io/InputStream;", con_openIn); NS(C, "openDataInputStream", "(Ljava/lang/String;)Ljava/io/DataInputStream;", con_openDIn);
  NI(H, "setRequestMethod", "(Ljava/lang/String;)V", hc_setMethod); NI(H, "setRequestProperty", "(Ljava/lang/String;Ljava/lang/String;)V", hc_setProp); NI(H, "getRequestProperty", "(Ljava/lang/String;)Ljava/lang/String;", hc_getProp);
  NI(H, "getRequestMethod", "()Ljava/lang/String;", hc_enc);
  NI(H, "getResponseCode", "()I", hc_code); NI(H, "getResponseMessage", "()Ljava/lang/String;", hc_msg); NI(H, "getHeaderField", "(Ljava/lang/String;)Ljava/lang/String;", hc_hdr);
  NI(H, "getHeaderField", "(I)Ljava/lang/String;", hc_hdrN); NI(H, "getHeaderFieldKey", "(I)Ljava/lang/String;", hc_hdrK);
  NI(H, "getLength", "()J", hc_len); NI(H, "getType", "()Ljava/lang/String;", hc_type); NI(H, "getEncoding", "()Ljava/lang/String;", hc_enc); NI(H, "getURL", "()Ljava/lang/String;", hc_url);
  NI(H, "getDate", "()J", hc_zeroL); NI(H, "getExpiration", "()J", hc_zeroL); NI(H, "getLastModified", "()J", hc_zeroL); NI(H, "getHost", "()Ljava/lang/String;", hc_host); NI(H, "getPort", "()I", hc_port);
  NI(H, "openInputStream", "()Ljava/io/InputStream;", hc_open); NI(H, "openDataInputStream", "()Ljava/io/DataInputStream;", hc_openD);
  NI(H, "openOutputStream", "()Ljava/io/OutputStream;", hc_openOut); NI(H, "openDataOutputStream", "()Ljava/io/DataOutputStream;", hc_openDOut); NI(H, "close", "()V", hc_close);
}
