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

## Signature Evolution 11
Memory Cinema thêm chuyển cảnh mờ/hòa ảnh, chuyển động zoom/lướt, ngang/dọc, nhạc từ Tệp với lặp và fade-out. Creative Studio lưu công thức chỉnh sửa đặt tên và ID ảnh qua các lần mở. Chỉnh sửa câu chuyện, ảnh bìa, thành viên. Sao lưu Signature JSON riêng, hợp nhất theo ID; phục hồi ảnh bằng backup Vault riêng. Duplicate Cleaner chỉ chọn bản trùng byte SHA-256, luôn giữ một ảnh mỗi nhóm và xóa mềm có xác nhận. Visual Collections nhóm chủ đề Vision và RAW gallery cho ảnh RAW đã nhập. Chưa tự động nhận diện danh tính người; không suy đoán cảm xúc thực tế; Private Vault vẫn là bản sao mã hóa.

## Motion Timeline 12
Cây thời gian mặc định năm–tháng–ngày có nhánh, mở/thu gọn, nhảy năm, carousel có scroll transition; Slide ký ức với sáu hiệu ứng, cử chỉ, phát/tạm dừng, thanh tiến độ, filmstrip, hỗ trợ Reduce Motion. Thư viện lưới cũ vẫn có. Cải thiện cấp phát và backpressure encoder video, giữ kiểm thử xuất phim.

## Story Vine 13
Sáu chủ đề dây leo vector, tùy chỉnh mật độ, độ cong và node. Story ảnh/ngày/tháng/năm/bộ sưu tập, draft, mood, chú thích, ảnh bìa, ghi âm AAC tối đa 120 giây, tìm kiếm theo nội dung, Story Studio và sao lưu JSON riêng. Slide đọc story và giọng kể (ưu tiên từng ảnh, lời kể ngày phát đầu nhóm), nhạc Tệp lặp trong phiên. Không xuất lời kể vào MP4; sao lưu ảnh, Signature, Story là các tệp riêng.

## Living Memory World 14
15 bộ dây leo vector, lá chuyển động, hạt sáng, theo mùa quy ước, màu tùy chỉnh, nền và môi trường, lưu preset. 14 hiệu ứng slideshow trong app. Story Canvas kéo thả layer chữ/ảnh/sticker, font, màu, thứ tự, xuất PNG/PDF; Story PDF nhiều trang, chapter và hiệu ứng chữ. Memory World có bản đồ cây/vũ trụ/vườn 2D, museum carousel, wall kéo thả; Discovery nhóm kỷ niệm, cảm xúc, thẻ, tổng kết, GPS; Podcast lời kể. Chưa có WidgetKit, AR/3D thực, AI sinh văn bản, phân đoạn chủ thể, đồng bộ từng chữ với âm thanh hoặc xuất MP4 story đầy đủ.

Build 60/61: Story Writer Apple Foundation Models khi khả dụng trên iOS 26, mẫu offline riêng; Vision foreground mask cho lớp ảnh PNG trong suốt; soundscape tổng hợp offline, phim story 1080p có caption, lời kể không lặp và ambient loop. Đồng bộ chữ theo tổng thời lượng lời kể, không phải nhận dạng từng từ. Chưa có WidgetKit (cần app extension/provisioning riêng), AR/3D thật, xuất toàn bộ layer Canvas động hoặc toàn bộ hiệu ứng UI vào MP4. Bộ phối lưu cả mật độ/độ cong/nút/rung.
