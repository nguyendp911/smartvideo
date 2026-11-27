# VieLens
Máy ảnh iPhone với xử lý ảnh trên thiết bị và Timeline ngoại tuyến. Bundle ID của SmartVideo là `com.nguyendp911.smartvideo`. Tên ứng dụng mới là VieLens. Yêu cầu iOS 17 trở lên.

Mở máy ảnh và chụp. App đo phân bố sáng, tìm vùng mặt bằng Vision, điều chỉnh đường cong tông màu và lưu JPEG sRGB cùng bản gốc. Chạm khung ngắm để lấy nét, đổi ống kính hoặc đổi màu trong Tùy chọn. Camera đo chuyển động giữa các khung để cân bằng tốc độ và chất lượng. Hình trong khung ngắm là tín hiệu camera trực tiếp. Xử lý màu cuối diễn ra sau khi chụp.

Timeline lưu theo ngày, tháng và năm. Dùng trình đơn để nhập ảnh, so hai ảnh, sao lưu vào Tệp hoặc phục hồi. Bộ lọc tìm theo phiên, nhãn, ánh sáng hoặc ngày dạng YYYY-MM-DD. Mỗi ảnh có xếp hạng, file gốc, ảnh hoàn thiện, lưu sang Ảnh Apple và chia sẻ. Các ảnh đã xóa ở trong thùng rác tối đa 30 ngày. Để giữ dữ liệu trước khi gỡ app, chọn sao lưu vào một thư mục bên ngoài. Khi phục hồi, chọn thư mục VieLens chứa VieLens.json.

## Build
Trên Mac có Xcode và XcodeGen, chạy `xcodegen generate` rồi mở `VieLens.xcodeproj`. GitHub Actions trên main tạo IPA arm64 chưa ký và chạy các bài kiểm thử trên iOS Simulator. Artifact VieLens-iPhone-Unsigned chứa IPA và SHA-256. Ký lại bằng tài khoản của bạn trước khi cài lên iPhone.

## Timeline Pro
Dòng thời gian dạng nhật ký có ảnh lớn và lưới ảnh, thẻ tháng/năm mở sâu vào thời gian, album trực quan từ phiên chụp, tìm kiếm kết hợp và bộ lọc ánh sáng/xếp hạng. Chọn nhiều ảnh để đưa vào album, gắn nhãn, đánh sao, chia sẻ hoặc phục hồi/xóa mềm. Trình xem toàn màn hình có vuốt, filmstrip, phóng to và thông tin EXIF từ bản gốc. Giữ định dạng Vault, ảnh gốc và Bundle ID hiện có. Album là phiên chụp, mỗi ảnh thuộc tối đa một phiên.

## Camera Pro / Timeline Studio 9
Zoom pinch và slider, EV, AE/AF lock, ISO/shutter nếu thiết bị hỗ trợ, histogram luma, flash, hẹn giờ, chuỗi chụp tuần tự và 9 chất màu hậu kỳ. Timeline có lịch ảnh, kỷ niệm cùng ngày, trình chiếu, nhật ký và bộ sưu tập đa thành viên lưu trong metadata từng ảnh, tương thích bản sao lưu cũ. Không phải RAW, HDR bracket hay burst tốc độ cao.

## Signature 10
Timeline Designer (7 layout gồm grid, tùy chỉnh), pinch số cột, nhảy tháng; Signature Studio có hồ sơ câu chuyện, cột mốc, capsule theo ngày, nhóm người/cảm xúc thủ công, ảnh bìa, GPS MapKit, sự kiện theo thời gian, Vision tìm nhãn và số khuôn mặt, điểm kỹ thuật, hash gần giống, so sánh trượt, chỉnh màu/crop và xuất JPEG/PNG theo lô, collage, MP4 ảnh tĩnh 1080p/4K. Kho riêng tạo bản sao AES-GCM, Keychain userPresence trên thiết bị; không ẩn/xóa ảnh gốc. Câu chuyện/preset lưu cục bộ ngoài backup Vault; video chưa nhạc/chuyển cảnh; chưa nhóm danh tính mặt, RAW capture, lịch sử chỉnh sửa bền vững hay Spatial Gallery.
