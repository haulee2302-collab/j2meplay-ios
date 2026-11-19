import java.util.*;
public class T2 {
  static int shared = 0;
  static final Object lock = new Object();
  static synchronized void incStatic() { shared++; }
  int inst = 0;
  synchronized void incInst() { inst++; }
  static class Q { Vector v = new Vector(); synchronized void put(Object o) { v.addElement(o); notifyAll(); } synchronized Object take() throws InterruptedException { while (v.size() == 0) wait(); Object o = v.elementAt(0); v.removeElementAt(0); return o; } }
  static class Worker extends Thread { int id; static int done = 0; Worker(int id) { this.id = id; } public void run() { for (int i = 0; i < 20000; i++) incStatic(); synchronized (lock) { done++; } } }
  public static void main(String[] args) throws Exception {
    static_init();
    Thread[] ts = new Thread[4]; for (int i = 0; i < 4; i++) { ts[i] = new Worker(i); ts[i].start(); } for (int i = 0; i < 4; i++) ts[i].join();
    System.out.println("shared=" + shared + " done=" + Worker.done);
    final T2 t = new T2(); Thread a = new Thread(new Runnable() { public void run() { for (int i = 0; i < 50000; i++) t.incInst(); } }); Thread b = new Thread(new Runnable() { public void run() { for (int i = 0; i < 50000; i++) t.incInst(); } });
    a.start(); b.start(); a.join(); b.join(); System.out.println("inst=" + t.inst);
    final Q q = new Q(); final int[] sum = new int[1];
    Thread cons = new Thread(new Runnable() { public void run() { try { for (int i = 0; i < 100; i++) { Integer x = (Integer) q.take(); sum[0] += x.intValue(); } } catch (InterruptedException e) { } } });
    cons.start(); for (int i = 1; i <= 100; i++) { q.put(new Integer(i)); if (i % 17 == 0) Thread.sleep(2); } cons.join(); System.out.println("sum=" + sum[0]);
    Thread s1 = new Thread(new Runnable() { public void run() { try { Thread.sleep(80); } catch (InterruptedException e) { } System.out.println("late"); } });
    s1.start(); Thread.sleep(20); System.out.println("early"); s1.join(); System.out.println("joined " + s1.isAlive());
    Thread bad = new Thread(new Runnable() { public void run() { throw new RuntimeException("boom in thread"); } }); bad.start(); bad.join(); System.out.println("main continues");
    synchronized (lock) { synchronized (lock) { System.out.println("reentrant ok"); } }
    try { lock.wait(); } catch (IllegalMonitorStateException e) { System.out.println("IMSE"); }
    long t0 = System.currentTimeMillis(); Thread.sleep(50); long dt = System.currentTimeMillis() - t0; System.out.println(dt >= 49 && dt < 200);
  }
  static void static_init() { System.out.println("start"); }
}
