# J2ME Play cho iPhone (Flutter)

Giao diện và bố cục theo bản Android (`../app`): đăng nhập, Phiên thuê (thuê, khởi động lại, tắt), Kho JAR, Tài khoản, màn game.

## Chưa có trong bản này
- Luồng hình ảnh game (websocket JPC1 + bộ vẽ lệnh) — khung game hiện "Xin chờ".
- Phím ảo chưa gửi vào game; trang "Xem tất cả"; đăng nhập Google; nạp tiền trong app (mở website).
- Giả lập chạy JAR trên máy: iOS không hỗ trợ.

## Build IPA từ Windows (không cần Mac)
1. Đẩy thư mục `appios` này lên một repo GitHub riêng (thư mục này là gốc repo, đã có sẵn `.github/workflows/ios.yml`).
2. Vào tab Actions → "Build iOS IPA (chưa ký)" → Run workflow.
3. Tải artifact `J2MEPlay-unsigned-ipa`, cài bằng Sideloadly/AltStore với Apple ID (hết hạn sau 7 ngày với tài khoản miễn phí).
