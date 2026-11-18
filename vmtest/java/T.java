public class T {
    static StringBuffer out = new StringBuffer();
    static void p(String s) { System.out.println(s); }
    static void p(String k, long v) { System.out.println(k + "=" + v); }
    static void p(String k, String v) { System.out.println(k + "=" + v); }
    static int sfield = 5;
    static long lstat = 1L << 40;
    int ifield = 7;
    long lf = 3;
    static String[] SA;
    static char[] CA;
    static { SA = new String[] { "a", "b", "c" }; CA = "hello".toCharArray(); p("clinit T"); }

    interface Shape { int area(); }
    static abstract class Base implements Shape {
        int w = 2;
        Base() { p("Base ctor w=" + w); init(); }
        void init() { p("Base.init"); }
        public String toString() { return "Base" + area(); }
    }
    static class Rect extends Base {
        int h = 3;
        Rect() { super(); p("Rect ctor h=" + h); }
        void init() { p("Rect.init h=" + h); }
        public int area() { return w * h; }
    }
    static class MyEx extends Exception { int code; MyEx(String m, int c) { super(m); code = c; } }
    static class Lazy { static int v; static { v = 42; p("Lazy clinit"); } static int get() { return v; } }

    static int thrower(int i) throws MyEx {
        if (i == 0) throw new MyEx("zero", 10);
        if (i == 1) throw new IllegalStateException("one");
        return i;
    }
    static String dec(String s, int k) {
        if (s == null || s.length() == 0 || k == 0) return "";
        try {
            int n = s.length();
            byte[] b = new byte[n];
            int key = (6523 ^ 22395) + (k & (48 - 22 ^ 21)) << (54 ^ 62);
            for (int i = (58 - 16 ^ 42); i < n; i++) {
                int c = (s.charAt(i) - key) & (1540 ^ 1787);
                int x = (k ^ (i * (78 ^ 107) + (3288 ^ 3202))) & (317 - 62);
                b[i] = (byte) (c ^ x);
            }
            return new String(b, "UTF-8");
        } catch (Exception e) { return s; }
    }
    static long lmul(long a, long b) { return a * b; }
    static double dmix(double a, int b, long c, float f) { return a * b + c - f; }

    public static void main(String[] args) throws Exception {
        int a = 0x7fffffff, b = -17, c = 5;
        try {
        p("add", a + 1); p("mul", a * 3); p("sub", Integer.MIN_VALUE - 1);
        p("div", b / c); p("rem", b % c); p("div2", -b / 4); p("rem2", 17 % -5);
        p("shl", b << 3); p("shr", b >> 2); p("ushr", b >>> 28); p("shl33", 1 << 33); p("ushr33", b >>> 33);
        p("and", b & 0xff); p("or", b | 0x100); p("xor", b ^ 0x55); p("neg", -a); p("not", ~c);
        p("i2b", (byte) 200); p("i2c", (int) (char) -1); p("i2s", (short) 70000); p("b2i", (int) (byte) -3);
        int cnt = 0; for (int i = 0; i < 1000; i++) { cnt += i * i; cnt ^= i; } p("loop", cnt);
        } catch (Throwable e) { p("SECTION 1 threw " + e); }
        try {
        long x = 0x123456789abcdefL, y = -987654321L;
        p("ladd", x + y); p("lmul", lmul(x, y)); p("lmul2", lmul(Long.MAX_VALUE, 3)); p("ldiv", x / y); p("lrem", x % y);
        p("lshl", x << 5); p("lshr", y >> 3); p("lushr", y >>> 40); p("lshl65", 1L << 65);
        p("land", x & 0xffffffffL); p("lor", x | 1); p("lxor", x ^ y); p("lneg", -y);
        p("l2i", (int) x); p("i2l", (long) -5); p("lcmp", x > y ? 1 : (x < y ? -1 : 0));
        p("lstat", lstat); lstat += 7; lstat++; p("lstat2", lstat);
        T t = new T(); t.lf += 100; t.lf++; p("lf", t.lf); t.ifield *= 3; t.ifield++; p("if", t.ifield);
        long[] la = new long[3]; la[1] = x; la[1]++; la[2] += la[1] * 2; p("la", la[2]);
        } catch (Throwable e) { p("SECTION 2 threw " + e); }
        try {
        double d = 10.0 / 3; float f = 1.1f * 3;
        p("dmix", (long) (dmix(d, 3, 100L, f) * 1000));
        p("d2i", (int) 1e20); p("d2i2", (int) -1e20); p("d2i3", (int) 3.99); p("d2i4", (int) -3.99);
        p("f2l", (long) 1e19f); p("drem", (long) (7.5 % 2)); p("dcmp", Double.isNaN(0.0 / 0.0) ? 1 : 0);
        p("sqrt", (long) (Math.sqrt(2) * 1e6)); p("abs", Math.abs(-5)); p("max", Math.max(3, 9)); p("min", Math.min(3L, 9L));
        } catch (Throwable e) { p("SECTION 3 threw " + e); }
        try {
        byte[] ba = new byte[4]; ba[0] = (byte) 255; ba[1] = (byte) 128; ba[2] += 130; p("ba", ba[0] + ba[1] * 100 + ba[2] * 10000);
        char[] ca = new char[3]; ca[0] = 'x'; ca[1] = (char) (ca[0] + 1); ca[2]++; p("ca", ca[0] + ca[1] + ca[2]);
        short[] sa = new short[2]; sa[0] = (short) 40000; sa[1] = (short) (sa[0] * 2); p("sa", sa[0] * 100000L + sa[1]);
        int[][] m = new int[3][4]; m[1][2] = 5; m[2][3] = m[1][2] * 2; p("m", m[2][3] + m.length * 100 + m[0].length * 1000);
        int[] ia = { 5, 6, 7 }; int[] ib = (int[]) ia.clone(); ib[0] = 99; p("clone", ia[0] * 1000 + ib[0]);
        int ix = 0; int[] arr = new int[5]; arr[ix++] = 10; arr[ix++] = 20; arr[ix] = arr[ix - 1] + 5; arr[ix]++; p("ix", arr[0] + arr[1] + arr[2] + ix * 1000);
        int[] sz = new int[2]; System.arraycopy(ia, 0, sz, 0, 2); p("acopy", sz[0] + sz[1]);
        String[][] sm = new String[2][2]; sm[1][1] = "z"; p("sm", sm[1][1] + sm[0][0]);
        } catch (Throwable e) { p("SECTION 4 threw " + e); }
        try {
        String s = "Xin chào Việt Nam";
        p("len", s.length()); p("charAt", s.charAt(5)); p("idx", s.indexOf("Việt")); p("sub", s.substring(4, 8)); p("up", s.toUpperCase());
        p("tca", new String(s.toCharArray(), 0, 3)); p("eq", "ab".equals("a" + "b") ? "y" : "n"); p("cmp", "apple".compareTo("banana"));
        p("hash", "hello".hashCode()); p("val", String.valueOf(3.5)); p("trim", "  q ".trim() + "|");
        StringBuffer sb = new StringBuffer(); sb.append(1).append('c').append(2L).append("s").append(true).append(1.5).append(new char[] { 'a', 'b' }); p("sb", sb.toString());
        sb.insert(0, "[").reverse(); sb.setLength(5); sb.deleteCharAt(0); p("sb2", sb.toString());
        StringBuilder sbb = new StringBuilder("abc"); sbb.append(sbb.length()).append((Object) "o").append((String) null); p("sbb", sbb.toString());
        p("enc", new String("Việt".getBytes("UTF-8"), "UTF-8")); p("bytes", "Việt".getBytes("UTF-8").length);
        p("dec", dec("abc", 7)); p("dec0", dec("abc", 0));
        char ch = 'a'; ch += 2; ch++; p("ch", ch); p("chn", Character.isDigit('5') ? 1 : 0); p("cup", Character.toUpperCase('q'));
        p("itos", Integer.toString(-255, 16)); p("parse", Integer.parseInt("-123") + Integer.parseInt("77")); p("ltos", Long.toString(1L << 50));
        p("concat", "a" + 1 + 2L + 'c' + 1.5f + null + true);
        switch (a & 3) { case 0: p("sw", "zero"); break; case 3: p("sw", "three"); break; default: p("sw", "def"); }
        switch (b) { case -17: p("sw2", "m17"); break; case 1000: p("sw2", "k"); break; default: p("sw2", "no"); }
        } catch (Throwable e) { p("SECTION 5 threw " + e); }
        try {
        for (int i = 0; i < 3; i++) {
            try { p("thr", thrower(i)); } catch (MyEx e) { p("caught " + e.getMessage() + e.code); } catch (RuntimeException e) { p("rt " + e.getMessage()); } finally { p("fin" + i); }
        }
        try { int[] z = new int[2]; z[2] = 1; } catch (ArrayIndexOutOfBoundsException e) { p("aioobe"); }
        try { Object o = null; o.toString(); } catch (NullPointerException e) { p("npe"); }
        try { p("div0", 5 / (a - a)); } catch (ArithmeticException e) { p("arith"); }
        try { Object o = "s"; Integer ii = (Integer) o; } catch (ClassCastException e) { p("cce"); }
        try { try { throw new RuntimeException("inner"); } finally { p("f1"); } } catch (Exception e) { p("outer " + e.getMessage()); }
        try { Integer.parseInt("zz"); } catch (NumberFormatException e) { p("nfe"); }
        try { new int[-1].toString(); } catch (NegativeArraySizeException e) { p("nase"); }
        } catch (Throwable e) { p("SECTION 6 threw " + e); }
        try {
        Base r = new Rect(); p("area", r.area()); p("ts", r.toString()); Shape sh = r; p("ish", sh.area());
        p("inst", (r instanceof Rect ? 1 : 0) + (r instanceof Shape ? 10 : 0) + (sh instanceof Base ? 100 : 0));
        p("lazy0", "before"); p("lazy", Lazy.get());
        Runnable rn = new Runnable() { public void run() { p("anon run " + sfield); } }; rn.run();
        Object[] objs = { new Integer(3), "str", new int[1], null }; int q = 0; for (int i = 0; i < objs.length; i++) { if (objs[i] instanceof Integer) q += 1; if (objs[i] instanceof String) q += 10; if (objs[i] instanceof int[]) q += 100; } p("objs", q);
        } catch (Throwable e) { p("SECTION 7 threw " + e); }
        try {
        java.util.Vector v = new java.util.Vector(); v.addElement("a"); v.addElement(new Integer(2)); v.insertElementAt("z", 0); p("vec", v.size() + "" + v.elementAt(0) + v.elementAt(2));
        java.util.Hashtable h = new java.util.Hashtable(); h.put("k", new Integer(9)); h.put("j", "v"); p("ht", h.size() + "" + h.get("k") + h.get("j") + h.containsKey("q"));
        java.util.Random rnd = new java.util.Random(12345); p("rnd", rnd.nextInt() + ":" + rnd.nextInt(100) + ":" + rnd.nextLong());
        java.util.Enumeration en = v.elements(); int ec = 0; while (en.hasMoreElements()) { en.nextElement(); ec++; } p("enum", ec);
        } catch (Throwable e) { p("SECTION 8 threw " + e); }
        try {
        final int[] shared = new int[1]; final Object lock = new Object();
        Thread[] th = new Thread[3];
        for (int i = 0; i < 3; i++) { th[i] = new Thread(new Runnable() { public void run() { for (int j = 0; j < 100; j++) { synchronized (lock) { shared[0]++; } Thread.yield(); } } }); th[i].start(); }
        for (int i = 0; i < 3; i++) th[i].join(); p("threads", shared[0]);
        } catch (Throwable e) { p("SECTION 9 threw " + e); }
        try {
        p("sfield", sfield++ + ++sfield); p("tern", a > 0 ? "pos" : "neg"); p("cmpchain", (1 < 2 && 3 > 2 || 5 == 6) ? 1 : 0);
        int w = 3; w <<= 2; w ^= 5; w >>>= 1; w %= 4; p("w", w);
        long ll = 5; ll <<= 33; ll |= 3; ll >>= 1; ll *= -3; p("ll", ll);
        p("done", "ok");
        } catch (Throwable e) { p("SECTION 10 threw " + e); }
    }
}

