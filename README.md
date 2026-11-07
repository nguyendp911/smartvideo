# ViePN Smart Video – trình dựng video iOS (SwiftUI)

Mã nguồn ứng dụng **render video ngay trên iPhone 12 Pro Max**, không gửi clip lên server.

## Tính năng (bản dựng UI mới)

- **Giao diện không cuộn cả màn hình:** preview phía trên luôn cố định, timeline cuộn ngang, thanh công cụ 4 thẻ Đoạn / Khung / Phụ đề / Âm thanh, nút xuất MP4 cố định bên dưới.
- **Tỷ lệ trực tiếp:** chọn video 9:16 hoặc 16:9 để thấy ngay canvas thay đổi trên preview; chế độ Vừa khung/Phủ đầy được áp dụng cả lúc render.
- **Timeline:** nhập nhiều video/ảnh bằng PhotosPicker, chỉnh điểm bắt đầu và thời lượng, đổi chỗ 1 bước qua nút trái/phải, xóa clip, preview clip đang chọn.
- **Phụ đề:** nhập TXT UTF-8 hoặc UTF-16 để tự chia từng dòng theo thời lượng video; nhập SRT để giữ timing; sửa từng câu, nắn thời gian ±0.5s; xuất SRT và chèn phụ đề trực tiếp vào video khi render.
- **Thuyết minh:** ghi âm bằng micro hoặc nhập tệp giọng đọc có sẵn, trộn giọng và tiếng gốc.
- **Cắt MP3 theo video:** chọn vị trí bắt đầu, dò phần im lặng đầu bài để đề xuất điểm vào, tự lặp khi nhạc ngắn, tự dừng ở cuối video và giảm âm lượng khi có giọng đọc, fade 1.2 giây ở cuối.
- Xuất **MP4 H.264**, 720p / 1080p, 30 FPS; lưu vào Photos hoặc chia sẻ qua ứng dụng khác.

### Phạm vi chức năng chưa có

Hiệu ứng crossfade, filter LUT, nhận diện nhịp beat chuyên sâu, tự phát sinh lời phụ đề bằng AI/STT, tổng hợp giọng nói TTS từ văn bản, timeline đa track kéo thả, undo, lưu project, và render nền khi khóa màn hình **chưa được thực hiện**. Tính năng chọn nhạc tự động chỉ phân tích âm lượng để bỏ đoạn im lặng, **không phải AI chọn đoạn nhạc hay**.

### Giới hạn thực tế

Các API AVFoundation trên GitHub Actions biên dịch được nhưng **vẫn cần kiểm thử render thực tế trên iPhone 12 Pro Max**. Dự án có âm thanh/codec không được hỗ trợ có thể xuất thất bại. Phụ đề sử dụng font iOS tiêu chuẩn, chưa tùy chỉnh style. Khi dùng ảnh tĩnh số lượng lớn, thời gian render và dung lượng sẽ tăng. Với clip dài nên chọn 720p hoặc 1080p/30 FPS.

## Công nghệ

- iOS 16+, Swift 5, SwiftUI, PhotosUI
- AVFoundation, AVMutableComposition, AVAssetWriter, AVAssetExportSession
- Core Image, VideoToolbox (qua bộ mã hóa AVFoundation), Photos
- XcodeGen để sinh .xcodeproj từ project.yml

Bộ render chạy **offline** trên thiết bị. Các API AVFoundation được sử dụng tương thích với deployment target iOS 16; Apple đã đưa ra các API mới hơn ở các SDK gần đây.

## Chạy bằng Xcode trên macOS

1. Cài **Xcode** và **XcodeGen**: brew install xcodegen.
2. Clone repository, mở Terminal tại thư mục và chạy: xcodegen generate
3. Mở SmartVideo.xcodeproj, chọn **Signing & Capabilities** và Team của bạn.
4. Đổi Bundle Identifier nếu cần (giá trị mặc định: com.nguyendp911.smartvideo).
5. Chọn iPhone 12 Pro Max đã bật Developer Mode, bấm Run.
6. Cho phép thêm video vào thư viện khi ứng dụng yêu cầu.

### GitHub Actions

Push lên nhánh main sẽ khởi chạy workflow **iOS Build**. Workflow biên dịch bản iOS Simulator *không ký*, tải xuống được tại Actions → lần chạy → Artifacts.

**SmartVideo-Simulator.zip KHÔNG phải IPA cài được trên iPhone thật.** Để xuất IPA cài trên iPhone, cần Mac runner, tài khoản Apple Developer, certificate (.p12), provisioning profile hợp lệ và ký ứng dụng. Có thể mở bằng Xcode rồi Product → Archive → Distribute App. Không tải chứng chỉ hay private key lên repository.

## Kiến trúc

```text
PhotosPicker / Files
    ↓
MediaStorage (Documents/Media)
    ↓
EditorViewModel / TimelineClip
    ↓
VideoRenderer
  ├─ Ảnh → AVAssetWriter (H.264 segment)
  ├─ Clip → AVMutableComposition (cắt / nối)
  ├─ AVMutableVideoComposition (xoay / fit 9:16, 16:9)
  └─ AVMutableAudioMix (tiếng gốc + nhạc nền lặp)
    ↓
AVAssetExportSession → Documents/Exports/*.mp4
    ↓
Photos / ShareLink
```

## Lưu ý riêng cho iPhone 12 Pro Max

Nên khởi đầu với 1080p/30 FPS và dự án ngắn. Video 4K đầu vào được hạ về kích thước xuất đã chọn. Render ảnh dài và nhiều clip liên tục có thể nóng máy. Giữ ứng dụng ở foreground khi đang render; iOS có thể tạm dừng app chạy nền.

## Quyền riêng tư

PhotosPicker không yêu cầu quyền xem toàn bộ thư viện. App chỉ xin quyền **add-only** lúc bạn chọn “Lưu vào thư viện Ảnh”. Tất cả tệp nhập và xuất nằm trong vùng lưu trữ của SmartVideo.

## Bố cục iPhone 12 Pro Max / ViePN Smart Video

- LaunchScreen storyboard cho khung màn hình đầy đủ (khắc phục chế độ letterbox).
- Preview co giãn theo chiều cao thiết bị; timeline, tab chỉnh sửa và nút xuất video nằm trong safe area.
- Tên hiển thị: **ViePN Smart Video**, icon đóng gói với Asset Catalog.
- Trên macOS, chạy `bash scripts/make-icon.sh` trước khi `xcodegen generate` để chuẩn bị ảnh app icon 1024 x 1024.
- Build IPA mới qua GitHub Actions sẽ tự tạo icon. Cân nhắc sao lưu dữ liệu trước khi xóa app cũ; xóa ứng dụng sẽ mất tệp dự án cục bộ.

## Sửa lỗi nhập âm thanh (v2.2.1)

- Dùng một trình nhập tệp hệ thống SwiftUI cho cả MP3, thuyết minh và SRT/TXT. Bỏ lồng UIDocumentPicker vào sheet, tránh việc iOS và SwiftUI cùng đóng sheet khi chọn tệp.
- Sao chép file đã chọn vào vùng riêng của ứng dụng trong lúc file URL còn quyền truy cập.
- Chỉ hiển thị nút cắt nhạc khi đã xác minh track âm thanh và thời lượng hữu hạn, hợp lệ; tệp lỗi trả thông báo thay vì đưa NaN vào SwiftUI Slider.
- Biên dịch GitHub Actions chỉ xác nhận build; chưa thay thế kiểm thử thao tác chọn file trên máy thật.
