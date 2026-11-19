# jvmcore — lõi thông dịch JVM bằng C (nguyên mẫu)

Mục đích: thay bộ thông dịch Dart (`lib/jvm/vm.dart`) bằng lõi C nhanh hơn nhiều cho iOS (chỉ thông dịch, không JIT).

    ./run_tests.sh              # build (clang/gcc) + so kết quả với JDK thật
    ./jvm test Bench            # đo tốc độ

Giai đoạn 1: đọc .class, ~190 opcode, <clinit>, switch, gọi tĩnh/ảo/giao diện, inline cache.
Giai đoạn 3: luồng xanh (Thread/Runnable/sleep/join/yield/interrupt), synchronized (phương thức + khối), wait/notify,
bộ điều phối chia lát theo số lệnh, nạp class từ thư mục để thử JAR thật: `./jvm -midlet <thư mục lớp> <MidletClass> [giây]`.
`test/T2.java` (luồng, khoá, producer/consumer, sleep, ngoại lệ trong luồng) cũng giống hệt JDK.
Giai đoạn 4 (MIDP + IO): `io.c` (ByteArray/Data Input/OutputStream, Class.getResourceAsStream, Arrays.fill, String từ byte[]),
`midp.c` (MIDlet, Display, Canvas, GameCanvas, Graphics, Image, Font, Command, RecordStore lưu tệp, hàng đợi sự kiện paint/phím/chạm),
`png.c` (giải PNG), `misc.c` (System.getProperty, Class.forName, Math, màn hình List/Alert/Form/TextBox dạng khung rỗng).
**Đồ họa dùng giao thức JPC1 của phiên thuê**: Graphics trên màn hình phát lệnh JPC1 (fillRect, drawImage, drawString...), phía Dart dùng lại
`JpcRenderer`; ảnh phụ (Image.getGraphics) vẽ bằng C. Kiểm thử: `JPC_DUMP=out.bin ./jvm -midlet <thư mục JAR đã giải nén> <MidletClass> 8`
rồi `test/jpcview out.bin out.ppm` để dựng lại khung. `JVM_TRACE=1` in chuỗi phương thức mỗi khi native ném ngoại lệ; `KEYS="ms:mã,..."` phát phím.
Kết quả: KPAH (bản đồ) và Ninja/NSOCAN (màn hình chào) **vẽ ra khung hình thật** (≈30 khung/s); LHT, HSO, PBE dừng vì thiếu tài nguyên
trong JAR (`/MrQuyet/MrQuyet.png`...) hoặc API chưa có.

Giai đoạn 2: ngoại lệ (athrow, try/catch/finally, ngoại lệ thời gian chạy), chuỗi UTF-16 thật,
String/StringBuilder/StringBuffer, Integer/Long/Character, Math, System, Vector/ArrayList/Stack,
Hashtable/HashMap, Random (đúng thuật toán JDK), PrintStream, Class.getName, checkcast/instanceof có giao diện,
multianewarray, gọi lồng nhau từ native (callMethod → equals/hashCode/toString của lớp game).
`test/T1.java` chạy ~35 tình huống; kết quả **giống hệt JDK**.

Chưa có: GC, java.util.Timer, mạng (Connector/socket), âm thanh, chữ vẽ lên Image (cần bộ glyph từ host), màn hình List/Form thật,
nối Dart qua FFI + bước CI, phần lớn thư viện (Enumeration, StringTokenizer, Calendar, Byte.parseByte, Hashtable.keys...).

Tốc độ Bench (5 bài, ~2,07 tỷ bytecode): clang -O2 ~2,7 s (≈750 triệu bytecode/s);
gcc -O2 ~4,2 s; HotSpot `java -Xint` ~2,3 s (máy chủ x86, không phải iPhone). Trình biên dịch của iOS là clang.
