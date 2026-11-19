# jvmcore — lõi thông dịch JVM bằng C (nguyên mẫu)

Mục đích: thay bộ thông dịch Dart (`lib/jvm/vm.dart`) bằng lõi C nhanh hơn nhiều cho iOS (chỉ thông dịch, không JIT).

    ./run_tests.sh              # build (clang/gcc) + so kết quả với JDK thật
    ./jvm test Bench            # đo tốc độ

Giai đoạn 1: đọc .class, ~190 opcode, <clinit>, switch, gọi tĩnh/ảo/giao diện, inline cache.
Giai đoạn 3: luồng xanh (Thread/Runnable/sleep/join/yield/interrupt), synchronized (phương thức + khối), wait/notify,
bộ điều phối chia lát theo số lệnh, nạp class từ thư mục để thử JAR thật: `./jvm -midlet <thư mục lớp> <MidletClass> [giây]`.
`test/T2.java` (luồng, khoá, producer/consumer, sleep, ngoại lệ trong luồng) cũng giống hệt JDK.
Thử JAR thật (HSO, LHT, KPAH, Ninja): constructor + startApp chạy tới khi gặp API MIDP/IO còn thiếu
(Image.createImage, Class.getResourceAsStream, DataInputStream, RecordStore, Canvas.getWidth...) — đây là danh sách việc của giai đoạn 4.

Giai đoạn 2: ngoại lệ (athrow, try/catch/finally, ngoại lệ thời gian chạy), chuỗi UTF-16 thật,
String/StringBuilder/StringBuffer, Integer/Long/Character, Math, System, Vector/ArrayList/Stack,
Hashtable/HashMap, Random (đúng thuật toán JDK), PrintStream, Class.getName, checkcast/instanceof có giao diện,
multianewarray, gọi lồng nhau từ native (callMethod → equals/hashCode/toString của lớp game).
`test/T1.java` chạy ~35 tình huống; kết quả **giống hệt JDK**.

Chưa có: GC, java.util.Timer, MIDP (đồ họa/RMS/mạng), nối Dart qua FFI,
phần lớn thư viện (Enumeration, StringTokenizer, Calendar...).

Tốc độ Bench (5 bài, ~2,07 tỷ bytecode): clang -O2 ~2,7 s (≈750 triệu bytecode/s);
gcc -O2 ~4,2 s; HotSpot `java -Xint` ~2,3 s (máy chủ x86, không phải iPhone). Trình biên dịch của iOS là clang.
