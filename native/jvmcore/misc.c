// Phần bổ sung: System.getProperty, Class.forName, Runtime, Math, Character.digit, và các màn hình lcdui (List/Alert/Form/TextBox)
// ở dạng khung rỗng (giao diện thật sẽ do host Dart dựng).
#include "jvm.h"

#define NS(cls, name, desc, fn) regNative(cls, name, desc, 1, fn)
#define NI(cls, name, desc, fn) regNative(cls, name, desc, 0, fn)
#define OBJ(i) ((Obj *)a[i].a)

static const char *props[][2] = {
  {"microedition.platform", "Nokia6300/5.0"}, {"microedition.encoding", "ISO-8859-1"}, {"microedition.configuration", "CLDC-1.1"},
  {"microedition.profiles", "MIDP-2.0"}, {"microedition.locale", "en-US"}, {"microedition.hostname", "localhost"}, {"microedition.commports", ""},
  {"microedition.media.version", "1.0"}, {"microedition.m3g.version", "1.1"}, {"file.separator", "/"}, {"line.separator", "\n"},
};
static void sy_getProp(Slot *a) {
  Obj *k = OBJ(0); if (!k) { throwNew("java/lang/NullPointerException", 0); return; }
  char b[100]; int n = 0; for (int i = 0; i < S_LEN(k) && n < 99; i++) b[n++] = (char)S_CH(k)[i]; b[n] = 0;
  for (size_t i = 0; i < sizeof props / sizeof *props; i++) if (!strcmp(props[i][0], b)) { a[0].a = newStr(props[i][1]); return; }
  a[0].a = 0;
}
static void cl_loader(Slot *a) { a[0].a = 0; }
static void cl_forName(Slot *a) {
  Obj *k = OBJ(0); char b[300]; int n = 0; if (k) for (int i = 0; i < S_LEN(k) && n < 299; i++) { char c = (char)S_CH(k)[i]; b[n++] = c == '.' ? '/' : c; } b[n] = 0;
  char path[700]; snprintf(path, sizeof path, "%s/%s.class", cpdir, b); FILE *f = fopen(path, "rb");
  if (!f && strncmp(b, "java/", 5) && strncmp(b, "javax/", 6)) { throwNew("java/lang/ClassNotFoundException", b); return; }
  if (f) fclose(f);
  Obj *c = newObj(loadClass("java/lang/Class")); c->f[0].a = loadClass(b); a[0].a = c;
}
static void cl_forName3(Slot *a) { Slot b[1]; b[0] = a[0]; cl_forName(b); a[0] = b[0]; }
static void cl_newInstance(Slot *a) { Class *k = ((Obj *)a[0].a)->f[0].a; Obj *o = newObj(k); Method *m = findMethod(k, "<init>", "()V"); if (m) { Slot ar[1]; ar[0].a = o; callMethod(m, ar, 1); } a[0].a = o; }
static void rt_get(Slot *a) { a[0].a = newObj(loadClass("java/lang/Runtime")); }
static void rt_free(Slot *a) { a[0].l = 64 * 1024 * 1024; }
static void rt_total(Slot *a) { a[0].l = 128 * 1024 * 1024; }
static void nop(Slot *a) { (void)a; }
static void zero(Slot *a) { a[0].l = 0; }
static void m_toRad(Slot *a) { a[0].d = a[0].d / 180.0 * M_PI; }
static void m_toDeg(Slot *a) { a[0].d = a[0].d * 180.0 / M_PI; }
static void m_asin(Slot *a) { a[0].d = asin(a[0].d); }
static void m_acos(Slot *a) { a[0].d = acos(a[0].d); }
static void m_atan2(Slot *a) { a[0].d = atan2(a[0].d, a[2].d); }
static void ch_digit(Slot *a) { int c = a[0].i, r = a[1].i, v = -1; if (c >= '0' && c <= '9') v = c - '0'; else if (c >= 'a' && c <= 'z') v = c - 'a' + 10; else if (c >= 'A' && c <= 'Z') v = c - 'A' + 10; a[0].i = v >= 0 && v < r ? v : -1; }
static void ch_forDigit(Slot *a) { int d = a[0].i, r = a[1].i; a[0].i = d < 0 || d >= r ? 0 : (d < 10 ? '0' + d : 'a' + d - 10); }

// Màn hình lcdui dạng khung: lưu danh sách chuỗi để size()/getString() hoạt động.
// List/ChoiceGroup: f0 = tiêu đề, f1 = listener (Displayable), f2 = số mục, f3 = mảng chuỗi, f4 = chỉ số chọn
static void lst_init(Slot *a) { Obj *o = OBJ(0); o->f[0].a = a[1].a; o->f[2].i = 0; o->f[3].a = newArr(8, 8); }
static void lst_initFull(Slot *a) {
  Obj *o = OBJ(0); o->f[0].a = a[1].a; Arr *src = a[3].a; int n = src ? src->len : 0; Arr *t = newArr(n > 8 ? n : 8, 8);
  for (int i = 0; i < n; i++) ((void **)t->d)[i] = ((void **)src->d)[i]; o->f[2].i = n; o->f[3].a = t;
}
static void lst_append(Slot *a) {
  Obj *o = OBJ(0); Arr *t = o->f[3].a; int n = o->f[2].i;
  if (!t) { t = newArr(8, 8); o->f[3].a = t; }
  if (n >= t->len) { Arr *t2 = newArr(t->len * 2, 8); memcpy(t2->d, t->d, (size_t)t->len * 8); o->f[3].a = t2; t = t2; }
  ((void **)t->d)[n] = a[1].a; o->f[2].i = n + 1; a[0].i = n;
}
static void lst_size(Slot *a) { a[0].i = OBJ(0)->f[2].i; }
static void lst_getString(Slot *a) { Obj *o = OBJ(0); int i = a[1].i; if (i < 0 || i >= o->f[2].i) { throwNew("java/lang/IndexOutOfBoundsException", 0); return; } a[0].a = ((void **)((Arr *)o->f[3].a)->d)[i]; }
static void lst_delete(Slot *a) { Obj *o = OBJ(0); int i = a[1].i, n = o->f[2].i; if (i < 0 || i >= n) { throwNew("java/lang/IndexOutOfBoundsException", 0); return; } void **d = ((Arr *)o->f[3].a)->d; for (int k = i; k < n - 1; k++) d[k] = d[k + 1]; o->f[2].i = n - 1; }
static void lst_deleteAll(Slot *a) { OBJ(0)->f[2].i = 0; }
static void lst_set(Slot *a) { Obj *o = OBJ(0); int i = a[1].i; if (i < 0 || i >= o->f[2].i) { throwNew("java/lang/IndexOutOfBoundsException", 0); return; } ((void **)((Arr *)o->f[3].a)->d)[i] = a[2].a; }
static void lst_getSel(Slot *a) { a[0].i = OBJ(0)->f[4].i; }
static void lst_setSel(Slot *a) { OBJ(0)->f[4].i = a[1].i; }
static void lst_isSel(Slot *a) { a[0].i = OBJ(0)->f[4].i == a[1].i; }
static void lst_getTitle(Slot *a) { a[0].a = OBJ(0)->f[0].a; }
static void lst_setTitle(Slot *a) { OBJ(0)->f[0].a = a[1].a; }
// TextBox / TextField: f0 = tiêu đề, f2 = nội dung
static void tb_init(Slot *a) { Obj *o = OBJ(0); o->f[0].a = a[1].a; o->f[2].a = a[2].a; }
static void tb_get(Slot *a) { Obj *o = OBJ(0); a[0].a = o->f[2].a ? o->f[2].a : newStr(""); }
static void tb_set(Slot *a) { OBJ(0)->f[2].a = a[1].a; }
static void tb_max(Slot *a) { a[0].i = a[1].i; }

void installMisc(void) {
  const char *Y = "java/lang/System", *C = "java/lang/Class", *M = "java/lang/Math", *R = "java/lang/Runtime", *CH = "java/lang/Character";
  NS(Y, "getProperty", "(Ljava/lang/String;)Ljava/lang/String;", sy_getProp);
  NI(C, "getClassLoader", "()Ljava/lang/ClassLoader;", cl_loader); NS(C, "forName", "(Ljava/lang/String;)Ljava/lang/Class;", cl_forName);
  NS(C, "forName", "(Ljava/lang/String;ZLjava/lang/ClassLoader;)Ljava/lang/Class;", cl_forName3); NI(C, "newInstance", "()Ljava/lang/Object;", cl_newInstance);
  NS(R, "getRuntime", "()Ljava/lang/Runtime;", rt_get); NI(R, "freeMemory", "()J", rt_free); NI(R, "totalMemory", "()J", rt_total); NI(R, "gc", "()V", nop);
  NS(M, "toRadians", "(D)D", m_toRad); NS(M, "toDegrees", "(D)D", m_toDeg); NS(M, "asin", "(D)D", m_asin); NS(M, "acos", "(D)D", m_acos); NS(M, "atan2", "(DD)D", m_atan2);
  NS(CH, "digit", "(CI)I", ch_digit); NS(CH, "forDigit", "(II)C", ch_forDigit);
  const char *L = "javax/microedition/lcdui/List", *A = "javax/microedition/lcdui/Alert", *F = "javax/microedition/lcdui/Form", *T = "javax/microedition/lcdui/TextBox";
  const char *CG = "javax/microedition/lcdui/ChoiceGroup", *TF = "javax/microedition/lcdui/TextField", *SI = "javax/microedition/lcdui/StringItem", *GA = "javax/microedition/lcdui/Gauge";
  NI(L, "<init>", "(Ljava/lang/String;I)V", lst_init); NI(L, "<init>", "(Ljava/lang/String;I[Ljava/lang/String;[Ljavax/microedition/lcdui/Image;)V", lst_initFull);
  NI(CG, "<init>", "(Ljava/lang/String;I)V", lst_init); NI(CG, "<init>", "(Ljava/lang/String;I[Ljava/lang/String;[Ljavax/microedition/lcdui/Image;)V", lst_initFull);
  const char *LC[2] = {L, CG};
  for (int i = 0; i < 2; i++) {
    NI(LC[i], "append", "(Ljava/lang/String;Ljavax/microedition/lcdui/Image;)I", lst_append); NI(LC[i], "size", "()I", lst_size); NI(LC[i], "getString", "(I)Ljava/lang/String;", lst_getString);
    NI(LC[i], "delete", "(I)V", lst_delete); NI(LC[i], "deleteAll", "()V", lst_deleteAll); NI(LC[i], "set", "(ILjava/lang/String;Ljavax/microedition/lcdui/Image;)V", lst_set);
    NI(LC[i], "getSelectedIndex", "()I", lst_getSel); NI(LC[i], "setSelectedIndex", "(IZ)V", lst_setSel); NI(LC[i], "isSelected", "(I)Z", lst_isSel);
    NI(LC[i], "setFitPolicy", "(I)V", nop); NI(LC[i], "setSelectCommand", "(Ljavax/microedition/lcdui/Command;)V", nop);
  }
  NI(L, "getTitle", "()Ljava/lang/String;", lst_getTitle); NI(L, "setTitle", "(Ljava/lang/String;)V", lst_setTitle);
  NI(A, "<init>", "(Ljava/lang/String;)V", nop); NI(A, "<init>", "(Ljava/lang/String;Ljava/lang/String;Ljavax/microedition/lcdui/Image;Ljavax/microedition/lcdui/AlertType;)V", nop);
  NI(A, "setString", "(Ljava/lang/String;)V", nop); NI(A, "setTimeout", "(I)V", nop); NI(A, "setType", "(Ljavax/microedition/lcdui/AlertType;)V", nop); NI(A, "setImage", "(Ljavax/microedition/lcdui/Image;)V", nop);
  NS("javax/microedition/lcdui/AlertType", "playSound", "(Ljavax/microedition/lcdui/Display;)Z", zero);
  NI(F, "<init>", "(Ljava/lang/String;)V", nop); NI(F, "<init>", "(Ljava/lang/String;[Ljavax/microedition/lcdui/Item;)V", nop);
  NI(F, "append", "(Ljava/lang/String;)I", zero); NI(F, "append", "(Ljavax/microedition/lcdui/Item;)I", zero); NI(F, "deleteAll", "()V", nop); NI(F, "get", "(I)Ljavax/microedition/lcdui/Item;", zero);
  NI(F, "insert", "(ILjavax/microedition/lcdui/Item;)V", nop); NI(F, "setItemStateListener", "(Ljavax/microedition/lcdui/ItemStateListener;)V", nop);
  NI(T, "<init>", "(Ljava/lang/String;Ljava/lang/String;II)V", tb_init); NI(TF, "<init>", "(Ljava/lang/String;Ljava/lang/String;II)V", tb_init);
  const char *TT[2] = {T, TF}; for (int i = 0; i < 2; i++) { NI(TT[i], "getString", "()Ljava/lang/String;", tb_get); NI(TT[i], "setString", "(Ljava/lang/String;)V", tb_set); NI(TT[i], "setMaxSize", "(I)I", tb_max); NI(TT[i], "setConstraints", "(I)V", nop); }
  NI(SI, "<init>", "(Ljava/lang/String;Ljava/lang/String;)V", nop);
  NI(GA, "<init>", "(Ljava/lang/String;ZII)V", nop); NI(GA, "getMaxValue", "()I", zero); NI(GA, "getValue", "()I", zero); NI(GA, "setValue", "(I)V", nop);
  NS("com/nokia/mid/ui/DeviceControl", "setLights", "(II)V", nop);
}
