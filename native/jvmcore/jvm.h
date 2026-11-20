#ifndef JVM_H
#define JVM_H
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <time.h>

typedef union Slot { int32_t i; int64_t l; float f; double d; void *a; } Slot;
typedef struct Class Class;
typedef struct Method Method;
typedef void (*NativeFn)(Slot *a);

typedef struct { uint16_t start, end, handler, type; } ExcEntry;
struct Method {
  Class *cls; const char *name, *desc; uint16_t acc; int argSlots, retSlots;
  int maxStack, maxLocals; uint8_t *code; int codeLen; ExcEntry *exc; int nexc; NativeFn native;
};
typedef struct { const char *name, *desc; uint16_t acc; int slot, wide; } Field;
typedef struct { uint8_t tag; union { const char *s; int32_t i; int64_t l; double d; float f; struct { uint16_t a, b; } r; } u; void *cache; void *cobj; } Cp;
struct Class {
  const char *name; Class *super; int ncp; Cp *cp; int nfields, nmethods; Field *fields; Method *methods;
  int nInst; Slot *statics; int initState; int builtin; Class **ifaces; int nifaces;
};
typedef struct { Class *cls; Slot f[]; } Obj;
typedef struct { Class *cls; int len; int esz; uint8_t d[]; } Arr;

extern Obj *g_exc;                 // ngoại lệ đang chờ xử lý
extern Class *arrCls;
Class *loadClass(const char *name);
Method *findMethod(Class *c, const char *name, const char *desc);
int subOf(Class *c, Class *t);
Obj *newObj(Class *c);
Arr *newArr(int len, int esz);
Obj *newStr16(const uint16_t *c, int n);
Obj *newStr(const char *utf8);
void throwNew(const char *cls, const char *msg);
Slot callMethod(Method *m, Slot *args, int nargs);
int jequals(Obj *a, Obj *b);
int jhash(Obj *a);
void jprintStr(Obj *s, FILE *f);
#define S_CH(o) ((uint16_t *)(o)->f[0].a)
#define S_LEN(o) ((o)->f[1].i)
void installNatives(void);
typedef struct { const char *cls, *name, *desc; int isStatic; NativeFn fn; } NativeRow;
void regNative(const char *cls, const char *name, const char *desc, int isStatic, NativeFn fn);
int argSlotsOf(const char *d, int *ret);
extern const char *cpdir;
int64_t nowMs(void);
extern void (*g_idle)(void);
void *evThreadNew(void);
int evThreadBusy(void *t);
void evThreadRun(void *t, Method *entry, Slot *args, int nargs);
void installIO(void);
void installMidp(void);
void installMisc(void);
#define ARRB(o) ((int8_t *)((Arr *)(o))->d)
#endif

int midpUiPoll(char *buf, int cap);
void midpUiAction(const char *s);
int midpNetPoll(uint8_t *buf, int cap);
void midpNetDone(int id, int status, const uint8_t *hdr, int hlen, const uint8_t *body, int blen);
