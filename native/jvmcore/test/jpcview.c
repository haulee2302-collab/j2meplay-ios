// Dựng lại ảnh từ tệp dump JPC1 (JPC_DUMP=...): ./jpcview dump.bin out.ppm   (chữ vẽ thành khối xám để biết vị trí)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
static int be16(const uint8_t *p) { return (int16_t)((p[0] << 8) | p[1]); }
static uint32_t be32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]; }
typedef struct { int w, h; uint32_t *px; } Res;
static Res res[4096]; static uint32_t id2[4096]; static int nres;
static Res *getRes(uint32_t id) { for (int i = 0; i < nres; i++) if (id2[i] == id) return &res[i]; return 0; }
static uint32_t *fb; static int W, H, col, cl, ct, cr, cb;
static uint32_t blend(uint32_t d, uint32_t s) { uint32_t a = s >> 24; if (a == 255) return s; if (!a) return d; uint32_t ia = 255 - a;
  return 0xFF000000 | ((((s >> 16) & 255) * a + ((d >> 16) & 255) * ia) / 255 << 16) | ((((s >> 8) & 255) * a + ((d >> 8) & 255) * ia) / 255 << 8) | (((s & 255) * a + (d & 255) * ia) / 255); }
static void put(int x, int y, uint32_t c) { if (x >= cl && x < cr && y >= ct && y < cb && x >= 0 && y >= 0 && x < W && y < H) fb[y * W + x] = blend(fb[y * W + x], c); }
int main(int argc, char **argv) {
  FILE *f = fopen(argv[1], "rb"); int n, frames = 0, stopAt = argc > 3 ? atoi(argv[3]) : 1 << 30; long ops = 0, imgs = 0, texts = 0, rects = 0;
  while (fread(&n, 4, 1, f) == 1 && frames < stopAt) {
    uint8_t *d = malloc(n); if (fread(d, 1, n, f) != (size_t)n) break; frames++;
    int key = d[5] & 1; int w = (d[6] << 8) | d[7], h = (d[8] << 8) | d[9];
    if (!fb || w != W || h != H) { W = w; H = h; free(fb); fb = calloc(W * H, 4); for (int i = 0; i < W * H; i++) fb[i] = 0xFF000000; }
    if (key) nres = 0;
    col = 0xFF000000; cl = 0; ct = 0; cr = W; cb = H;
    int o = 10;
    while (o < n) {
      int op = d[o++]; ops++;
      switch (op) {
        case 1: col = 0xFF000000 | (be32(d + o) & 0xFFFFFF); cl = be16(d + o + 4); ct = be16(d + o + 6); cr = be16(d + o + 8); cb = be16(d + o + 10); o += 13; break;
        case 2: { uint32_t id = be32(d + o); int rw = (d[o + 12] << 8) | d[o + 13], rh = (d[o + 14] << 8) | d[o + 15]; int len = be32(d + o + 16); o += 20;
          Res *r = getRes(id); if (!r) { id2[nres] = id; r = &res[nres++]; } else free(r->px);
          r->w = rw; r->h = rh; r->px = malloc(len); for (int i = 0; i < rw * rh; i++) r->px[i] = ((uint32_t)d[o + i * 4 + 3] << 24) | (d[o + i * 4] << 16) | (d[o + i * 4 + 1] << 8) | d[o + i * 4 + 2]; o += len; break; }
        case 10: { int x = be16(d + o), y = be16(d + o + 2), rw = be16(d + o + 4), rh = be16(d + o + 6); o += 8; rects++; for (int j = y; j < y + rh; j++) for (int i = x; i < x + rw; i++) put(i, j, col); break; }
        case 11: { int x0 = be16(d + o), y0 = be16(d + o + 2), x1 = be16(d + o + 4), y1 = be16(d + o + 6); o += 8; int dx = abs(x1 - x0), sx = x0 < x1 ? 1 : -1, dy = -abs(y1 - y0), sy = y0 < y1 ? 1 : -1, e = dx + dy; for (;;) { put(x0, y0, col); if (x0 == x1 && y0 == y1) break; int e2 = 2 * e; if (e2 >= dy) { e += dy; x0 += sx; } if (e2 <= dx) { e += dx; y0 += sy; } } break; }
        case 12: { int x = be16(d + o), y = be16(d + o + 2), rw = be16(d + o + 4), rh = be16(d + o + 6); o += 8; for (int i = x; i <= x + rw; i++) { put(i, y, col); put(i, y + rh, col); } for (int j = y; j <= y + rh; j++) { put(x, j, col); put(x + rw, j, col); } break; }
        case 13: { uint32_t id = be32(d + o); int sx = be16(d + o + 4), sy = be16(d + o + 6), iw = be16(d + o + 8), ih = be16(d + o + 10), tr = d[o + 12], dx = be16(d + o + 13), dy = be16(d + o + 15); o += 17; imgs++;
          Res *r = getRes(id); if (!r) break;
          for (int j = 0; j < ih; j++) for (int i = 0; i < iw; i++) { int ox = i, oy = j; switch (tr) { case 1: oy = ih - 1 - j; break; case 2: ox = iw - 1 - i; break; case 3: ox = iw - 1 - i; oy = ih - 1 - j; break; case 4: ox = j; oy = i; break; case 5: ox = ih - 1 - j; oy = i; break; case 6: ox = j; oy = iw - 1 - i; break; case 7: ox = ih - 1 - j; oy = iw - 1 - i; break; }
            if (sx + i < r->w && sy + j < r->h) put(dx + ox, dy + oy, r->px[(sy + j) * r->w + sx + i]); } break; }
        case 16: o += 12; break; case 17: o += 17; break; case 18: { int x = be16(d + o), y = be16(d + o + 2), rw = be16(d + o + 4), rh = be16(d + o + 6); o += 13; for (int j = y; j < y + rh; j++) for (int i = x; i < x + rw; i++) put(i, j, col); break; }
        case 19: { int x = be16(d + o), base = be16(d + o + 2), size = d[o + 6], len = be32(d + o + 7); o += 11 + len; texts++; int tw = len * size * 55 / 100; for (int j = base - size + 2; j < base; j += 2) for (int i = x; i < x + tw; i++) if ((i + j) % 3 == 0) put(i, j, col); break; }
        default: fprintf(stderr, "op lạ %d @%d\n", op, o); o = n;
      }
    }
    free(d);
  }
  fprintf(stderr, "khung=%d ops=%ld rect=%ld ảnh=%ld chữ=%ld, kích thước %dx%d\n", frames, ops, rects, imgs, texts, W, H);
  FILE *out = fopen(argv[2], "wb"); fprintf(out, "P6\n%d %d\n255\n", W, H);
  for (int i = 0; i < W * H; i++) { fputc((fb[i] >> 16) & 255, out); fputc((fb[i] >> 8) & 255, out); fputc(fb[i] & 255, out); }
  fclose(out); return 0;
}
