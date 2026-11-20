// Bộ giải nén PNG nhỏ (inflate + bỏ lọc), đủ cho ảnh J2ME. Trả về ARGB (0xAARRGGBB).
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct { const uint8_t *s; size_t n, pos; uint32_t bit; int nb; uint8_t *o; size_t on, cap; int err; } Inf;
typedef struct { uint16_t cnt[16], sym[320]; } Huff;

static int getbits(Inf *z, int n) {
  while (z->nb < n) { if (z->pos >= z->n) { z->err = 1; return 0; } z->bit |= (uint32_t)z->s[z->pos++] << z->nb; z->nb += 8; }
  int v = z->bit & ((1u << n) - 1); z->bit >>= n; z->nb -= n; return v;
}
static void putb(Inf *z, uint8_t b) {
  if (z->on >= z->cap) { z->cap = z->cap * 2 + 1024; z->o = realloc(z->o, z->cap); }
  z->o[z->on++] = b;
}
static void hbuild(Huff *h, const uint8_t *len, int n) {
  uint16_t offs[16]; memset(h->cnt, 0, sizeof h->cnt);
  for (int i = 0; i < n; i++) h->cnt[len[i]]++;
  h->cnt[0] = 0; offs[1] = 0;
  for (int i = 1; i < 15; i++) offs[i + 1] = offs[i] + h->cnt[i];
  for (int i = 0; i < n; i++) if (len[i]) h->sym[offs[len[i]]++] = i;
}
static int hdec(Inf *z, Huff *h) {
  int code = 0, first = 0, index = 0;
  for (int l = 1; l <= 15; l++) {
    code |= getbits(z, 1); int c = h->cnt[l];
    if (code - c < first) return h->sym[index + (code - first)];
    index += c; first += c; first <<= 1; code <<= 1;
    if (z->err) return -1;
  }
  z->err = 1; return -1;
}
static const uint16_t lbase[] = {3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258};
static const uint8_t lext[] = {0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0};
static const uint16_t dbase[] = {1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577};
static const uint8_t dext[] = {0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13};

static int codes(Inf *z, Huff *lh, Huff *dh) {
  for (;;) {
    int s = hdec(z, lh); if (s < 0 || z->err) return -1;
    if (s < 256) putb(z, s);
    else if (s == 256) return 0;
    else {
      s -= 257; if (s >= 29) return -1;
      int len = lbase[s] + getbits(z, lext[s]);
      int ds = hdec(z, dh); if (ds < 0 || ds >= 30) return -1;
      size_t d = dbase[ds] + getbits(z, dext[ds]); if (d > z->on) return -1;
      for (int i = 0; i < len; i++) putb(z, z->o[z->on - d]);
    }
  }
}
// Giải nén zlib (bỏ 2 byte đầu). Trả về bộ đệm malloc hoặc NULL.
static uint8_t *inflateZ(const uint8_t *src, size_t n, size_t *outn) {
  Inf z = {0}; z.s = src; z.n = n; z.pos = 2;
  int last;
  do {
    last = getbits(&z, 1); int type = getbits(&z, 2);
    if (z.err) break;
    if (type == 0) {
      z.bit = 0; z.nb = 0; if (z.pos + 4 > z.n) { z.err = 1; break; }
      int len = z.s[z.pos] | (z.s[z.pos + 1] << 8); z.pos += 4;
      if (z.pos + len > z.n) { z.err = 1; break; }
      for (int i = 0; i < len; i++) putb(&z, z.s[z.pos++]);
    } else if (type == 1) {
      static Huff lh, dh; static int init; static uint8_t l[320];
      if (!init) { int i = 0; for (; i < 144; i++) l[i] = 8; for (; i < 256; i++) l[i] = 9; for (; i < 280; i++) l[i] = 7; for (; i < 288; i++) l[i] = 8; hbuild(&lh, l, 288); uint8_t d[30]; for (i = 0; i < 30; i++) d[i] = 5; hbuild(&dh, d, 30); init = 1; }
      if (codes(&z, &lh, &dh)) { z.err = 1; break; }
    } else if (type == 2) {
      static const uint8_t ord[19] = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15};
      int nl = getbits(&z, 5) + 257, nd = getbits(&z, 5) + 1, nc = getbits(&z, 4) + 4;
      uint8_t lens[320] = {0}; Huff ch, lh, dh;
      for (int i = 0; i < nc; i++) lens[ord[i]] = getbits(&z, 3);
      hbuild(&ch, lens, 19);
      uint8_t ll[320] = {0}; int i = 0;
      while (i < nl + nd && !z.err) {
        int s = hdec(&z, &ch); if (s < 0) { z.err = 1; break; }
        if (s < 16) ll[i++] = s;
        else { int rep, v = 0; if (s == 16) { if (!i) { z.err = 1; break; } v = ll[i - 1]; rep = 3 + getbits(&z, 2); } else if (s == 17) rep = 3 + getbits(&z, 3); else rep = 11 + getbits(&z, 7);
          if (i + rep > nl + nd) { z.err = 1; break; } while (rep--) ll[i++] = v; }
      }
      if (z.err) break;
      hbuild(&lh, ll, nl); hbuild(&dh, ll + nl, nd);
      if (codes(&z, &lh, &dh)) { z.err = 1; break; }
    } else { z.err = 1; break; }
  } while (!last);
  if (z.err) { free(z.o); return 0; }
  *outn = z.on; return z.o;
}

static uint32_t be32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]; }
static int paeth(int a, int b, int c) { int p = a + b - c, pa = abs(p - a), pb = abs(p - b), pc = abs(p - c); return pa <= pb && pa <= pc ? a : (pb <= pc ? b : c); }

// Trả về mảng ARGB (malloc) và kích thước; NULL nếu không phải PNG hỗ trợ.
static uint32_t *jpgDecode(const uint8_t *d, size_t n, int *ow, int *oh);
uint32_t *pngDecode(const uint8_t *d, size_t n, int *ow, int *oh) {
  if (n > 4 && d[0] == 0xFF && d[1] == 0xD8) return jpgDecode(d, n, ow, oh);
  if (n < 33 || memcmp(d, "\x89PNG\r\n\x1a\n", 8)) return 0;
  size_t p = 8; int w = 0, h = 0, depth = 0, ct = 0, il = 0;
  uint8_t pal[256 * 3]; int npal = 0; uint8_t trns[256]; int ntrns = 0; int tkey = -1;
  uint8_t *idat = 0; size_t idn = 0;
  while (p + 8 <= n) {
    uint32_t len = be32(d + p); const uint8_t *t = d + p + 4; const uint8_t *c = d + p + 8; if (p + 12 + len > n) break;
    if (!memcmp(t, "IHDR", 4)) { w = be32(c); h = be32(c + 4); depth = c[8]; ct = c[9]; il = c[12]; }
    else if (!memcmp(t, "PLTE", 4)) { npal = len / 3; if (npal > 256) npal = 256; memcpy(pal, c, npal * 3); }
    else if (!memcmp(t, "tRNS", 4)) { if (ct == 3) { ntrns = len > 256 ? 256 : len; memcpy(trns, c, ntrns); } else if (ct == 0 && len >= 2) tkey = (c[0] << 8) | c[1]; else if (ct == 2 && len >= 6) tkey = (c[1] << 16) | (c[3] << 8) | c[5]; }
    else if (!memcmp(t, "IDAT", 4)) { idat = realloc(idat, idn + len); memcpy(idat + idn, c, len); idn += len; }
    else if (!memcmp(t, "IEND", 4)) break;
    p += 12 + len;
  }
  if (!w || !h || w > 4096 || h > 4096 || il || !idat) { free(idat); return 0; }
  size_t rawn; uint8_t *raw = inflateZ(idat, idn, &rawn); free(idat); if (!raw) return 0;
  int ch = ct == 0 ? 1 : ct == 2 ? 3 : ct == 3 ? 1 : ct == 4 ? 2 : 4;
  int bpp = (ch * depth + 7) / 8, stride = (w * ch * depth + 7) / 8;
  if (rawn < (size_t)(stride + 1) * h) { free(raw); return 0; }
  uint8_t *cur = calloc(stride, 1), *prev = calloc(stride, 1);
  uint32_t *out = malloc((size_t)w * h * 4);
  for (int y = 0; y < h; y++) {
    const uint8_t *row = raw + (size_t)y * (stride + 1); int f = row[0]; memcpy(cur, row + 1, stride);
    for (int i = 0; i < stride; i++) {
      int a = i >= bpp ? cur[i - bpp] : 0, b = prev[i], c = i >= bpp ? prev[i - bpp] : 0;
      switch (f) { case 1: cur[i] += a; break; case 2: cur[i] += b; break; case 3: cur[i] += (a + b) >> 1; break; case 4: cur[i] += paeth(a, b, c); break; }
    }
    for (int x = 0; x < w; x++) {
      uint32_t r, g, bl, al = 255;
      if (depth == 8) {
        const uint8_t *q = cur + x * ch;
        if (ct == 0) { r = g = bl = q[0]; if (tkey >= 0 && q[0] == tkey) al = 0; }
        else if (ct == 2) { r = q[0]; g = q[1]; bl = q[2]; if (tkey >= 0 && (int)((r << 16) | (g << 8) | bl) == tkey) al = 0; }
        else if (ct == 3) { int i = q[0]; if (i >= npal) i = 0; r = pal[i * 3]; g = pal[i * 3 + 1]; bl = pal[i * 3 + 2]; al = i < ntrns ? trns[i] : 255; }
        else if (ct == 4) { r = g = bl = q[0]; al = q[1]; }
        else { r = q[0]; g = q[1]; bl = q[2]; al = q[3]; }
      } else if (depth == 16) {
        const uint8_t *q = cur + x * ch * 2;
        if (ct == 0) { r = g = bl = q[0]; } else if (ct == 2) { r = q[0]; g = q[2]; bl = q[4]; } else if (ct == 4) { r = g = bl = q[0]; al = q[2]; } else { r = q[0]; g = q[2]; bl = q[4]; al = q[6]; }
      } else { // 1,2,4 bit (xám hoặc bảng màu)
        int per = 8 / depth, bi = x / per, sh = 8 - depth * (x % per + 1); int v = (cur[bi] >> sh) & ((1 << depth) - 1);
        if (ct == 3) { int i = v < npal ? v : 0; r = pal[i * 3]; g = pal[i * 3 + 1]; bl = pal[i * 3 + 2]; al = i < ntrns ? trns[i] : 255; }
        else { r = g = bl = v * 255 / ((1 << depth) - 1); if (tkey >= 0 && v == tkey) al = 0; }
      }
      out[(size_t)y * w + x] = (al << 24) | (r << 16) | (g << 8) | bl;
    }
    uint8_t *t = prev; prev = cur; cur = t;
  }
  free(cur); free(prev); free(raw); *ow = w; *oh = h; return out;
}

// ---- JPEG baseline (tuần tự, Huffman, có restart, lấy mẫu con) ----
typedef struct { uint8_t bits[17]; uint8_t val[256]; int mincode[17], maxcode[18], valptr[17]; int ok; } JHuff;
typedef struct { const uint8_t *d; size_t n, p; uint32_t buf; int cnt; int eof; } JBits;
static const uint8_t jzz[64] = {0,1,8,16,9,2,3,10,17,24,32,25,18,11,4,5,12,19,26,33,40,48,41,34,27,20,13,6,7,14,21,28,35,42,49,56,57,50,43,36,29,22,15,23,30,37,44,51,58,59,52,45,38,31,39,46,53,60,61,54,47,55,62,63};
static void jbuild(JHuff *h) {
  int code = 0, k = 0;
  for (int l = 1; l <= 16; l++) { h->valptr[l] = k; h->mincode[l] = code; code += h->bits[l]; k += h->bits[l]; h->maxcode[l] = h->bits[l] ? code - 1 : -1; code <<= 1; }
  h->maxcode[17] = 0x7fffffff; h->ok = 1;
}
static int jbit(JBits *b) {
  if (!b->cnt) {
    int c = 0;
    if (b->p < b->n) { c = b->d[b->p++]; if (c == 0xFF) { int c2 = b->p < b->n ? b->d[b->p] : 0; if (c2 == 0) b->p++; else { b->p--; c = 0; b->eof = 1; } } } else b->eof = 1;
    b->buf = c; b->cnt = 8;
  }
  b->cnt--; return (b->buf >> b->cnt) & 1;
}
static int jrecv(JBits *b, int n) { int v = 0; while (n--) v = (v << 1) | jbit(b); return v; }
static int jext(int v, int n) { return n && v < (1 << (n - 1)) ? v - (1 << n) + 1 : v; }
static int jdec(JBits *b, JHuff *h) {
  int code = 0;
  for (int l = 1; l <= 16; l++) { code = (code << 1) | jbit(b); if (h->maxcode[l] >= 0 && code <= h->maxcode[l] && code >= h->mincode[l]) return h->val[h->valptr[l] + code - h->mincode[l]]; }
  return -1;
}
static void jidct(const int *in, uint8_t *out, int stride) {
  float tmp[64];
  static float c[8][8]; static int init;
  if (!init) { for (int u = 0; u < 8; u++) for (int x = 0; x < 8; x++) c[u][x] = (u ? 1.0f : 0.70710678f) * cosf((2 * x + 1) * u * 3.14159265f / 16) * 0.5f; init = 1; }
  for (int y = 0; y < 8; y++) for (int x = 0; x < 8; x++) { float s = 0; for (int u = 0; u < 8; u++) s += c[u][x] * in[y * 8 + u]; tmp[y * 8 + x] = s; }
  for (int x = 0; x < 8; x++) for (int y = 0; y < 8; y++) { float s = 0; for (int v = 0; v < 8; v++) s += c[v][y] * tmp[v * 8 + x]; int r = (int)(s + 128.5f); out[y * stride + x] = r < 0 ? 0 : r > 255 ? 255 : r; }
}
static uint32_t *jpgDecode(const uint8_t *d, size_t n, int *ow, int *oh) {
  JHuff hdc[4], hac[4]; memset(hdc, 0, sizeof hdc); memset(hac, 0, sizeof hac);
  int qt[4][64]; memset(qt, 0, sizeof qt);
  int w = 0, h = 0, nc = 0, ri = 0; int cid[4] = {0}, chs[4] = {0}, cvs[4] = {0}, cq[4] = {0}, td[4] = {0}, ta[4] = {0};
  size_t p = 2;
  while (p + 4 <= n) {
    if (d[p] != 0xFF) { p++; continue; }
    int m = d[p + 1]; if (m == 0xFF) { p++; continue; }
    if (m == 0xD8 || (m >= 0xD0 && m <= 0xD7) || m == 0x01) { p += 2; continue; }
    int len = (d[p + 2] << 8) | d[p + 3]; const uint8_t *s = d + p + 4; size_t end = p + 2 + len; if (end > n) return 0;
    if (m == 0xDB) { const uint8_t *q = s; while (q < d + end) { int pq = q[0] >> 4, t = q[0] & 15; q++; if (t > 3) return 0; for (int i = 0; i < 64; i++) { qt[t][jzz[i]] = pq ? (q[0] << 8) | q[1] : q[0]; q += pq ? 2 : 1; } } }
    else if (m == 0xC4) { const uint8_t *q = s; while (q + 17 <= d + end) { int tc = q[0] >> 4, t = q[0] & 15; q++; if (t > 3) return 0; JHuff *H = tc ? &hac[t] : &hdc[t]; int tot = 0; H->bits[0] = 0; for (int i = 1; i <= 16; i++) { H->bits[i] = q[i - 1]; tot += q[i - 1]; } q += 16; if (tot > 256) return 0; memcpy(H->val, q, tot); q += tot; jbuild(H); } }
    else if (m == 0xC0 || m == 0xC1) { if (s[0] != 8) return 0; h = (s[1] << 8) | s[2]; w = (s[3] << 8) | s[4]; nc = s[5]; if (nc != 1 && nc != 3) return 0; for (int i = 0; i < nc; i++) { cid[i] = s[6 + i * 3]; chs[i] = s[7 + i * 3] >> 4; cvs[i] = s[7 + i * 3] & 15; cq[i] = s[8 + i * 3] & 3; if (!chs[i] || !cvs[i] || chs[i] > 4 || cvs[i] > 4) return 0; } }
    else if (m == 0xC2 || (m >= 0xC3 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC)) return 0; // progressive/lossless/arith: chưa hỗ trợ
    else if (m == 0xDD) ri = (s[0] << 8) | s[1];
    else if (m == 0xDA) {
      if (!w || !h || w > 4096 || h > 4096 || !nc) return 0;
      int ns = s[0]; if (ns != nc) return 0;
      for (int i = 0; i < ns; i++) { int id = s[1 + i * 2], t = s[2 + i * 2]; int k; for (k = 0; k < nc; k++) if (cid[k] == id) break; if (k == nc) return 0; td[k] = (t >> 4) & 3; ta[k] = t & 3; }
      int hmax = 1, vmax = 1; for (int i = 0; i < nc; i++) { if (chs[i] > hmax) hmax = chs[i]; if (cvs[i] > vmax) vmax = cvs[i]; }
      int mw = 8 * hmax, mh = 8 * vmax, mx = (w + mw - 1) / mw, my = (h + mh - 1) / mh;
      uint8_t *pl[4] = {0}; int pw[4], ph[4];
      for (int i = 0; i < nc; i++) { pw[i] = mx * chs[i] * 8; ph[i] = my * cvs[i] * 8; pl[i] = malloc((size_t)pw[i] * ph[i]); if (!pl[i]) return 0; }
      JBits b = {d, n, end, 0, 0, 0}; int pred[4] = {0}, rst = 0, bad = 0;
      for (int by = 0; by < my && !bad; by++) for (int bx = 0; bx < mx && !bad; bx++) {
        if (ri && rst == ri) { b.cnt = 0; b.eof = 0; while (b.p + 1 < n && !(d[b.p] == 0xFF && d[b.p + 1] >= 0xD0 && d[b.p + 1] <= 0xD7)) b.p++; b.p += 2; memset(pred, 0, sizeof pred); rst = 0; }
        rst++;
        for (int c = 0; c < nc; c++) for (int v = 0; v < cvs[c]; v++) for (int u = 0; u < chs[c]; u++) {
          int blk[64]; memset(blk, 0, sizeof blk);
          int t = jdec(&b, &hdc[td[c]]); if (t < 0 || t > 15) { bad = 1; break; }
          pred[c] += jext(jrecv(&b, t), t); blk[0] = pred[c] * qt[cq[c]][0];
          for (int k = 1; k < 64;) { int rs = jdec(&b, &hac[ta[c]]); if (rs < 0) { bad = 1; break; } int r = rs >> 4, sz = rs & 15; if (!sz) { if (r == 15) { k += 16; continue; } break; } k += r; if (k > 63) break; blk[jzz[k]] = jext(jrecv(&b, sz), sz) * qt[cq[c]][jzz[k]]; k++; }
          if (bad) break;
          jidct(blk, pl[c] + (size_t)((by * cvs[c] + v) * 8) * pw[c] + (bx * chs[c] + u) * 8, pw[c]);
        }
      }
      uint32_t *out = bad && 0 ? 0 : malloc((size_t)w * h * 4);
      if (out) for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
        int v[3];
        for (int c = 0; c < nc; c++) v[c] = pl[c][(size_t)(y * cvs[c] / vmax) * pw[c] + x * chs[c] / hmax];
        int r, g, bl;
        if (nc == 1) r = g = bl = v[0];
        else { float Y = v[0], cb = v[1] - 128, cr = v[2] - 128; r = (int)(Y + 1.402f * cr + 0.5f); g = (int)(Y - 0.344136f * cb - 0.714136f * cr + 0.5f); bl = (int)(Y + 1.772f * cb + 0.5f); }
        r = r < 0 ? 0 : r > 255 ? 255 : r; g = g < 0 ? 0 : g > 255 ? 255 : g; bl = bl < 0 ? 0 : bl > 255 ? 255 : bl;
        out[(size_t)y * w + x] = 0xFF000000u | (r << 16) | (g << 8) | bl;
      }
      for (int i = 0; i < nc; i++) free(pl[i]);
      *ow = w; *oh = h; return out;
    }
    p = end;
  }
  return 0;
}
