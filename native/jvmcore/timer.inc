// java.util.Timer / TimerTask và stub javax.microedition.media (Manager/Player/VolumeControl).
// Timer chạy trên một luồng riêng (tmT), thực hiện tuần tự từng TimerTask khi đến hạn.
typedef struct TmE { Obj *task, *timer; int64_t next, period; int fixed, dead; } TmE;
static TmE *tmL; static int tmN, tmCap; static void *tmT; static int tmBusy = -1;
static void tmAdd(Obj *timer, Obj *task, int64_t delay, int64_t period, int fixed) {
  if (!task) { throwNew("java/lang/NullPointerException", 0); return; }
  if (delay < 0 || (period < 0)) { throwNew("java/lang/IllegalArgumentException", 0); return; }
  if (task->f[0].i) { throwNew("java/lang/IllegalStateException", "Task already scheduled or cancelled"); return; }
  if (timer->f[0].i) { throwNew("java/lang/IllegalStateException", "Timer already cancelled"); return; }
  task->f[0].i = 1;
  if (tmN == tmCap) { tmCap = tmCap ? tmCap * 2 : 16; tmL = realloc(tmL, tmCap * sizeof *tmL); }
  TmE e = {task, timer, nowMs() + delay, period, fixed, 0}; tmL[tmN++] = e;
}
static void tm_init(Slot *a) { (void)a; }
static void tm_sch1(Slot *a) { tmAdd(OBJ(0), OBJ(1), a[2].l, 0, 0); }
static void tm_sch2(Slot *a) { tmAdd(OBJ(0), OBJ(1), a[2].l, a[4].l <= 0 ? -1 : a[4].l, 0); }
static void tm_fix(Slot *a) { tmAdd(OBJ(0), OBJ(1), a[2].l, a[4].l <= 0 ? -1 : a[4].l, 1); }
static void tm_cancel(Slot *a) { Obj *t = OBJ(0); t->f[0].i = 1; for (int i = 0; i < tmN; i++) if (tmL[i].timer == t) tmL[i].dead = 1; }
static void tt_cancel(Slot *a) { Obj *t = OBJ(0); int was = 0; for (int i = 0; i < tmN; i++) if (tmL[i].task == t && !tmL[i].dead) { tmL[i].dead = 1; was = 1; } t->f[0].i = 1; a[0].i = was; }
static void tmTick(void) {
  if (!tmT) tmT = evThreadNew();
  if (tmBusy >= 0) {
    if (evThreadBusy(tmT)) return;
    TmE *e = &tmL[tmBusy]; tmBusy = -1;
    if (e->period > 0 && !e->dead) { if (e->fixed) e->next += e->period; else e->next = nowMs() + e->period; } else e->dead = 1;
  }
  int k = 0; for (int i = 0; i < tmN; i++) if (!tmL[i].dead) tmL[k++] = tmL[i]; tmN = k;
  int64_t now = nowMs(); int pick = -1;
  for (int i = 0; i < tmN; i++) if (tmL[i].next <= now && (pick < 0 || tmL[i].next < tmL[pick].next)) pick = i;
  if (pick < 0) return;
  Method *m = findMethod(tmL[pick].task->cls, "run", "()V"); Slot ar[1]; ar[0].a = tmL[pick].task;
  if (!m || m->native) { tmL[pick].dead = 1; return; }
  tmBusy = pick; evThreadRun(tmT, m, ar, 1);
}
static void tmReset(void) { tmN = 0; tmBusy = -1; tmT = 0; }

// ---- javax.microedition.media (không phát âm thanh thật, chỉ để game không lỗi) ----
static void md_player(Slot *a) { a[0].a = newObj(loadClass("javax/microedition/media/Player")); }
static void md_pnop(Slot *a) { (void)a; }
static void md_pi0(Slot *a) { a[0].i = 0; }
static void md_pl0(Slot *a) { a[0].l = 0; }
static void md_state(Slot *a) { a[0].i = 100; } // REALIZED
static void md_ctl(Slot *a) { a[0].a = newObj(loadClass("javax/microedition/media/control/VolumeControl")); }
static void md_lvl(Slot *a) { a[0].i = 50; }
static void mediaInstall(void) {
  const char *P = "javax/microedition/media/Player", *M = "javax/microedition/media/Manager", *V = "javax/microedition/media/control/VolumeControl";
  NS(M, "createPlayer", "(Ljava/io/InputStream;Ljava/lang/String;)Ljavax/microedition/media/Player;", md_player);
  NS(M, "createPlayer", "(Ljava/lang/String;)Ljavax/microedition/media/Player;", md_player);
  NS(M, "playTone", "(III)V", md_pnop);
  const char *pv[] = {"start", "stop", "close", "realize", "prefetch", "deallocate"};
  for (int i = 0; i < 6; i++) NI(P, pv[i], "()V", md_pnop);
  NI(P, "setLoopCount", "(I)V", md_pnop); NI(P, "setMediaTime", "(J)J", md_pl0); NI(P, "getMediaTime", "()J", md_pl0); NI(P, "getDuration", "()J", md_pl0);
  NI(P, "getState", "()I", md_state); NI(P, "getControl", "(Ljava/lang/String;)Ljavax/microedition/media/Control;", md_ctl);
  NI(P, "addPlayerListener", "(Ljavax/microedition/media/PlayerListener;)V", md_pnop); NI(P, "removePlayerListener", "(Ljavax/microedition/media/PlayerListener;)V", md_pnop);
  NI(V, "setLevel", "(I)I", md_lvl); NI(V, "getLevel", "()I", md_lvl); NI(V, "setMute", "(Z)V", md_pnop); NI(V, "isMuted", "()Z", md_pi0);
  const char *T = "java/util/Timer", *TT = "java/util/TimerTask";
  NI(T, "<init>", "()V", tm_init); NI(T, "schedule", "(Ljava/util/TimerTask;J)V", tm_sch1); NI(T, "schedule", "(Ljava/util/TimerTask;JJ)V", tm_sch2);
  NI(T, "scheduleAtFixedRate", "(Ljava/util/TimerTask;JJ)V", tm_fix); NI(T, "cancel", "()V", tm_cancel);
  NI(TT, "<init>", "()V", tm_init); NI(TT, "cancel", "()Z", tt_cancel);
}
