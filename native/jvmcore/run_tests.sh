#!/bin/bash
# So kết quả lõi C với JDK thật: ./run_tests.sh   (cần gcc, javac, java)
set -e
cd "$(dirname "$0")"
CC=${CC:-$(command -v clang || command -v gcc)}
$CC -O2 -w -o jvm jvm.c natives.c -lm
cd test
for t in T1; do
  javac --release 8 -d . $t.java 2>/dev/null
  java -cp . $t > /tmp/$t.java.txt 2>/dev/null || true
  ../jvm . $t > /tmp/$t.c.txt 2>/dev/null || true
  if diff -q /tmp/$t.java.txt /tmp/$t.c.txt >/dev/null; then echo "$t: GIỐNG JDK"; else echo "$t: KHÁC"; diff /tmp/$t.java.txt /tmp/$t.c.txt | head; fi
done
