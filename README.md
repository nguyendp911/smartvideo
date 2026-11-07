# SmartVideo – trình dựng video iOS (SwiftUI)

Mã nguồn ứng dụng **render video ngay trên iPhone 12 Pro Max**, không gửi clip lên server.

## Tính năng MVP

- Nhập nhiều **ảnh** và **video** từ PhotosPicker; sao chép vào bộ nhớ riêng của ứng dụng.
- Timeline có thể sắp xếp lại, xóa, chọn từng clip, chỉnh độ dài ảnh/video, đặt điểm bắt đầu cho video.
- Xem trước một clip đã chọn.
- Thêm nhạc nền từ ứng dụng Tệp, điều chỉnh âm lượng; tùy chọn giữ tiếng gốc của các video.
- Xuất **MP4 H.264**, tỉ lệ **9:16** hoặc **16:9**, **720p** hoặc **1080p**, **30 FPS**.
- Ghép ảnh thành các đoạn video ngắn rồi nối các clip, giữ nguyên tỉ lệ bằng viền đen khi cần.
- Lưu video xuất ra Photos hoặc chia sẻ qua Share Sheet.

### Chưa hỗ trợ

Crossfade, filter LUT, text overlay, phụ đề, tiến độ render chính xác, render nền khi khóa màn hình, hoàn tác timeline, lưu dự án nhiều phiên và AI sinh video. Tệp xuất có thể lớn, quá trình render cần đủ dung lượng và pin.

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
