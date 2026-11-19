# jvmcore — lõi thông dịch JVM bằng C (giai đoạn 1, nguyên mẫu)

Mục đích: đo xem bộ thông dịch C nhanh hơn bao nhiêu so với bản Dart (`lib/jvm/vm.dart`).

    gcc -O2 -o jvm jvm.c -lm
    cd test && javac --release 8 -d . Bench.java && cd ..
    ./jvm test Bench

Hiện có: đọc .class, ~190 opcode (số nguyên/long/float/double, mảng, trường, gọi hàm tĩnh/ảo/giao diện,
khởi tạo lớp <clinit>, switch). Chưa có: GC, ngoại lệ (athrow/try-catch), luồng, chuỗi/StringBuilder,
thư viện Java, nối với MIDP/Dart (FFI).

Kết quả Bench (5 bài: fib, sàng, gọi ảo, mandelbrot, mảng) — kết quả in ra khớp `java -Xint`:
- jvmcore: ~3,4 s (~2,07 tỷ bytecode → ~600 triệu bytecode/s)
- HotSpot `java -Xint` (thông dịch thuần): ~2,3 s
