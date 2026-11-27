# VieLens
Máy ảnh iPhone với xử lý ảnh trên thiết bị và Timeline ngoại tuyến. Bundle ID của SmartVideo là `com.nguyendp911.smartvideo`. Tên ứng dụng mới là VieLens. Yêu cầu iOS 17 trở lên.

Mở máy ảnh và chụp. App đo phân bố sáng, tìm vùng mặt bằng Vision, điều chỉnh đường cong tông màu và lưu JPEG sRGB cùng bản gốc. Chạm khung ngắm để lấy nét, đổi ống kính hoặc đổi màu trong Tùy chọn. Camera đo chuyển động giữa các khung để cân bằng tốc độ và chất lượng. Hình trong khung ngắm là tín hiệu camera trực tiếp. Xử lý màu cuối diễn ra sau khi chụp.

Timeline lưu theo ngày, tháng và năm. Dùng trình đơn để nhập ảnh, so hai ảnh, sao lưu vào Tệp hoặc phục hồi. Bộ lọc tìm theo phiên, nhãn, ánh sáng hoặc ngày dạng YYYY-MM-DD. Mỗi ảnh có xếp hạng, file gốc, ảnh hoàn thiện, lưu sang Ảnh Apple và chia sẻ. Các ảnh đã xóa ở trong thùng rác tối đa 30 ngày. Để giữ dữ liệu trước khi gỡ app, chọn sao lưu vào một thư mục bên ngoài. Khi phục hồi, chọn thư mục VieLens chứa VieLens.json.

## Build
Trên Mac có Xcode và XcodeGen, chạy `xcodegen generate` rồi mở `VieLens.xcodeproj`. GitHub Actions trên main tạo IPA arm64 chưa ký và chạy các bài kiểm thử trên iOS Simulator. Artifact VieLens-iPhone-Unsigned chứa IPA và SHA-256. Ký lại bằng tài khoản của bạn trước khi cài lên iPhone.
