import java.util.*;
public class T1 {
  interface Shape { double area(); String name(); }
  static abstract class Base implements Shape { static int count = 0; Base() { count++; } public String name() { return getClass().getName().length() > 0 ? "shape" : "?"; } }
  static class Circle extends Base { double r; Circle(double r) { this.r = r; } public double area() { return 3.0 * r * r; } public String name() { return "circle"; } }
  static class Rect extends Base { int w, h; Rect(int w, int h) { this.w = w; this.h = h; } public double area() { return w * h; } }
  static class MyEx extends Exception { int code; MyEx(String m, int c) { super(m); code = c; } }
  static int depth(int n) throws MyEx { if (n == 0) throw new MyEx("bottom", 42); return depth(n - 1) + 1; }
  static int fin() { int x = 1; try { x = 2; return x; } finally { x = 3; System.out.println("finally " + x); } }
  static String sw(String s) { switch (s) { case "a": return "A"; case "bb": return "BB"; default: return "?" + s; } }
  static int sw2(int k) { switch (k) { case 1: return 10; case 2: return 20; case 3: return 30; case 100: return 1000; default: return -1; } }
  static class Counter { int n; void inc() { n++; } }
  class Inner { int v = 7; int outerVal() { return base + v; } }
  int base = 100;
  public static void main(String[] args) throws Exception {
    Shape[] sh = { new Circle(2), new Rect(3, 4), new Circle(1.5) };
    double tot = 0; for (Shape s : sh) { tot += s.area(); System.out.println(s.name() + " " + s.area()); }
    System.out.println("total " + tot + " count " + Base.count);
    System.out.println(sh[0] instanceof Shape);
    System.out.println(sh[1] instanceof Circle);
    try { depth(5); } catch (MyEx e) { System.out.println("caught " + e.getMessage() + " " + e.code); }
    System.out.println(fin());
    try { int[] a = new int[3]; a[5] = 1; } catch (ArrayIndexOutOfBoundsException e) { System.out.println("AIOOBE " + e.getMessage()); }
    try { int z = 0; System.out.println(5 / z); } catch (ArithmeticException e) { System.out.println("AE " + e.getMessage()); }
    try { String s = null; s.length(); } catch (NullPointerException e) { System.out.println("NPE"); }
    try { Object o = "str"; Integer i = (Integer) o; } catch (ClassCastException e) { System.out.println("CCE"); }
    try { Integer.parseInt("12x"); } catch (NumberFormatException e) { System.out.println(e.getMessage()); }
    try { throw new IllegalStateException("ise"); } catch (RuntimeException e) { System.out.println("RTE " + e); } finally { System.out.println("fin2"); }
    StringBuilder sb = new StringBuilder(); for (int i = 0; i < 5; i++) sb.append(i).append(',').append("x").append(1.5).append(true).append(10000000000L);
    System.out.println(sb.toString() + " " + sb.length());
    String s = "Hello, World"; System.out.println(s.substring(7) + s.indexOf("World") + s.charAt(4) + s.toUpperCase() + s.replace('l', 'L') + s.length() + s.hashCode());
    System.out.println(sw("a") + sw("bb") + sw("zz") + sw2(2) + sw2(100) + sw2(7));
    Vector v = new Vector(); for (int i = 0; i < 25; i++) v.addElement(new Integer(i * i)); System.out.println(v.size() + " " + v.elementAt(24) + " " + v.indexOf(new Integer(49)));
    Hashtable h = new Hashtable(); for (int i = 0; i < 100; i++) h.put("k" + i, new Integer(i)); System.out.println(h.size() + " " + h.get("k77") + " " + h.get("nope") + " " + h.containsKey("k5"));
    int[][] g = new int[4][5]; for (int i = 0; i < 4; i++) for (int j = 0; j < 5; j++) g[i][j] = i * j; System.out.println(g[3][4] + " " + g.length + " " + g[0].length);
    long L = 1L << 40; L += 12345; double d = L / 7.0; float f = (float) d; System.out.println(L + " " + d + " " + f + " " + (int) d + " " + (L % 1000) + " " + (L >>> 3));
    char c = 'a'; c += 2; System.out.println(c + " " + (int) c + " " + (char) (c + 1));
    Random r = new Random(12345); System.out.println(r.nextInt() + " " + r.nextInt(100) + " " + r.nextInt(64) + " " + r.nextLong());
    Counter cn = new Counter(); for (int i = 0; i < 1000; i++) cn.inc(); System.out.println(cn.n);
    T1 t = new T1(); T1.Inner in = t.new Inner(); System.out.println(in.outerVal());
    outer: for (int i = 0; i < 5; i++) { for (int j = 0; j < 5; j++) { if (i * j == 6) { System.out.println("found " + i + j); break outer; } } }
    System.out.println(Math.abs(-5) + " " + Math.max(3, 9) + " " + Math.sqrt(2) + " " + Math.pow(2, 10) + " " + Math.floor(-1.5) + " " + (1.0 / 3) + " " + 100.0 + " " + 1e10 + " " + 0.0001);
    Object[] objs = { "a", new Integer(5), new Long(9L) }; for (Object o : objs) System.out.println(o);
    Stack st = new Stack(); st.push("x"); st.push("y"); System.out.println(st.pop() + "" + st.peek() + st.empty());
    throw new MyEx("final uncaught", 1);
  }
}
