// Thử API thư viện (giống cách Dart gọi): ./libtest <dir> <Midlet> [dir2 Midlet2]
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
int jvmcore_start(const char *, const char *, const char *, int, int); int jvmcore_poll(uint8_t *, int); void jvmcore_key(int, int);
void jvmcore_refresh(void); int jvmcore_status(void); const char *jvmcore_error(void); void jvmcore_stop(void);
static void run(const char *dir, const char *mid) {
  int rc = jvmcore_start(dir, mid, "/tmp/libtest_rms", 240, 320); printf("start=%d\n", rc);
  uint8_t *buf = malloc(1 << 20); int cap = 1 << 20, frames = 0; long bytes = 0;
  for (int t = 0; t < 300; t++) { // ~3 giây
    for (;;) { int n = jvmcore_poll(buf, cap); if (n == 0) break; if (n < 0) { cap = -n; buf = realloc(buf, cap); continue; } frames++; bytes += n; }
    if (t == 100) { jvmcore_key(0, -5); jvmcore_key(1, -5); }
    usleep(10000);
  }
  printf("khung=%d byte=%ld status=%d err='%s'\n", frames, bytes, jvmcore_status(), jvmcore_error());
  jvmcore_stop(); printf("đã dừng status=%d\n", jvmcore_status());
}
int main(int c, char **v) { run(v[1], v[2]); if (c > 4) run(v[3], v[4]); return 0; }
