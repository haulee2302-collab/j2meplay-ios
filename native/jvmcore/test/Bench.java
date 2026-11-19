public class Bench {
  static int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
  static int sieve(int n) {
    boolean[] c = new boolean[n + 1]; int cnt = 0;
    for (int i = 2; i <= n; i++) {
      if (!c[i]) { cnt++; for (int j = i * 2; j <= n; j += i) c[j] = true; }
    }
    return cnt;
  }
  static class Vec { int x, y; Vec(int x, int y) { this.x = x; this.y = y; } int dot(Vec o) { return x * o.x + y * o.y; } void add(Vec o) { x += o.x; y += o.y; } }
  static long vecs(int n) {
    Vec a = new Vec(1, 2), b = new Vec(3, 4); long s = 0;
    for (int i = 0; i < n; i++) { s += a.dot(b); a.add(b); if ((i & 1023) == 0) { a.x = 1; a.y = 2; } }
    return s;
  }
  static double mandel(int w, int h, int it) {
    double tot = 0;
    for (int py = 0; py < h; py++) for (int px = 0; px < w; px++) {
      double x0 = px * 3.5 / w - 2.5, y0 = py * 2.0 / h - 1.0, x = 0, y = 0; int i = 0;
      while (x * x + y * y < 4 && i < it) { double t = x * x - y * y + x0; y = 2 * x * y + y0; x = t; i++; }
      tot += i;
    }
    return tot;
  }
  static int mixed(int n) {
    int[] a = new int[1024]; int h = 0;
    for (int i = 0; i < n; i++) { int k = i & 1023; a[k] = a[k] * 31 + i; h ^= a[k] >>> 3; }
    return h;
  }
  public static void main(String[] args) {
    System.out.println((long) fib(32));
    System.out.println((long) sieve(5000000));
    System.out.println(vecs(20000000));
    System.out.println(mandel(200, 150, 200));
    System.out.println((long) mixed(30000000));
  }
}
