// Bộ giải nén PNG nhỏ (inflate + bỏ lọc), đủ cho ảnh J2ME. Trả về ARGB (0xAARRGGBB).
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
uint32_t *pngDecode(const uint8_t *d, size_t n, int *ow, int *oh) {
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
