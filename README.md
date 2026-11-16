# ViePN Smart Video – trình dựng video iOS (SwiftUI)

Ứng dụng **dựng và render video ngay trên iPhone**, không gửi clip lên server. Mục tiêu thiết bị: iPhone 12 Pro Max, iOS 16+.

> Lịch sử chi tiết từng phiên bản (v2.x → v6.x, kèm các "giới hạn" từng bản) nằm trong [CHANGELOG.md](CHANGELOG.md).

## Tính năng chính

| Nhóm | Có gì |
|---|---|
| **Timeline** | Cắt/tách/nhân bản/đóng băng khung hình, tốc độ 0,25×–4× và Speed Curve, chuyển cảnh (hòa tan, mờ qua đen/trắng), hoàn tác/làm lại, **ripple delete**, lưu/mở dự án offline |
| **Hình ảnh** | Preset màu, chỉnh màu thủ công, **LUT `.cube`**, VFX thủ tục, 42 mockup ánh sáng/bóng, tách người (Vision), xóa phông |
| **Lớp phủ** | Overlay ảnh, Video PIP (tối đa 4), chữ nhiều lớp (cả trước/sau người), keyframe nhiều điểm cho ảnh/PIP/chữ, chroma key ảnh, **tách nền video PIP** |
| **Âm thanh** | Nhạc nền & nhiều vùng nhạc độc lập, SFX, thuyết minh/TTS, waveform, keyframe âm lượng, mastering, **tự hạ nhạc theo tiếng nói** |
| **Phụ đề** | Nhận diện lời nói (mặc định trên thiết bị), karaoke theo từ, xuất SRT |
| **AI** | AI Auto Video Creator, AI Video Director, Gemini (qua gateway riêng), tách giọng (backend riêng) |
| **Ảnh** | Xuất ảnh JPG/PNG/HEIC 2K–8K, batch ZIP, preset ảnh, AI Photo Editor |
| **Kho video** | Nhập từ Ảnh/Files/link MP4; link TikTok/Facebook qua Video Resolver tự host |

### Mới trong nhánh `feat/editor-roadmap`

- **Auto-ducking theo giọng nói** – phân tích tệp thuyết minh (RMS 16 kHz, ngưỡng thích nghi) và chỉ hạ nhạc đúng lúc có tiếng nói: hạ trước 0,12 s, hồi lại 0,35 s, mức hạ chỉnh 5–80 %. Có thể tắt để quay về kiểu hạ cố định 25 % toàn đoạn. Áp dụng cho nhạc nền và vùng nhạc khi **xuất MP4**; nghe thử nhanh vẫn dùng mức cố định.
- **Ripple delete** – xóa một clip ở timeline chính sẽ kéo phụ đề (và mốc từng từ), chữ, overlay, PIP, mockup, FX, vùng nhạc, cửa sổ VFX và offset nhạc/giọng lùi theo độ dài vừa xóa; mục bị cắt ngang được rút ngắn hoặc bỏ. Có công tắc trong tab Đoạn; một bước hoàn tác. Âm thanh nằm vắt qua điểm cắt chỉ giữ phần đầu (chưa tách đôi).
- **Tách nền video PIP** – chroma key xanh lá/xanh dương hoặc tách người bằng Vision. Khi xuất, mỗi PIP được chuyển một lần thành bản sao HEVC có kênh alpha (cache trong `RenderTemp`, tối đa 60 s, không sửa file gốc).
- **LUT `.cube`** – nhập LUT 3D (kích thước 2–64), áp dụng theo từng clip với cường độ 0–100 % trong cùng pipeline chỉnh màu của preview và xuất.
- **Nhận link từ Shortcuts** – `smartvideo://import?link=<URL mã hóa>` mở tab Kho video và điền sẵn link (chỉ http/https, không tự tải). Cách dùng: tạo Shortcut nhận *URL* từ Share Sheet → *Encode URL* → *Open URL* `smartvideo://import?link=…`.
- **Dọn dung lượng** – tự xóa file trung gian cũ khi mở app; panel trong Kho video để dọn bộ nhớ tạm hoặc xóa bản xuất cũ hơn 7 ngày (có xác nhận).
- **Tách `EditorViewModel`** thành 12 extension theo tính năng (`EditorViewModel+*.swift`), không đổi hành vi.

## Giới hạn hiện tại (trung thực)

- **Chưa có kết quả build/test trên máy thật cho nhánh này.** CI chỉ chứng minh biên dịch + test logic; cần QA render, âm thanh và hiệu năng trên iPhone 12 Pro Max.
- Preview nhanh trong editor không tái tạo đủ chuyển cảnh, crossfade audio, auto-ducking và PIP đã tách nền; dùng **Xem thử 720p** để kiểm tra bản kết xuất thật.
- Tách nền PIP cần máy mã hóa được HEVC có alpha (iPhone đời gần đây); tách người chỉ nhận diện **người**, không nhận mọi vật thể. Chưa có preview trực tiếp của alpha trong khung xem nhanh.
- LUT: chỉ LUT 3D `.cube` với DOMAIN 0–1; chưa hỗ trợ LUT 1D, `.3dl` hay HDR/Log tự nhận dạng không gian màu.
- Link TikTok/Facebook cần **Video Resolver** do bạn tự host (xem `backend/video_resolver`); chưa có server công khai. Chưa có Share Extension gốc (cần App Group + provisioning) – dùng Shortcut ở trên.
- Gemini gateway là bản chủ sở hữu duy nhất: chưa có xác thực theo người dùng, rate limit hay quota.
- Chưa có: stabilization, optical-flow slow-mo, tracking nhiều đối tượng, mockup nhập từ ảnh ngoài hoặc bóng 3D theo phối cảnh, dịch phụ đề đa ngôn ngữ, đa ngôn ngữ giao diện (chuỗi UI hiện viết trực tiếp bằng tiếng Việt).

## Công nghệ

- iOS 16+, Swift 5, SwiftUI, PhotosUI
- AVFoundation (`AVMutableComposition`, `AVAssetWriter`, `AVAssetExportSession`), Core Image, Vision, Speech, Photos
- XcodeGen sinh `.xcodeproj` từ `project.yml`

## Chạy bằng Xcode trên macOS

1. Cài **Xcode** và **XcodeGen**: `brew install xcodegen`.
2. Clone repo, chạy `xcodegen generate` tại thư mục gốc.
3. Mở `SmartVideo.xcodeproj`, chọn Team ở **Signing & Capabilities**, đổi Bundle Identifier nếu cần (mặc định `com.nguyendp911.smartvideo`).
4. Chọn thiết bị đã bật Developer Mode rồi Run.
5. Trên macOS, chạy `bash scripts/make-icon.sh` trước `xcodegen generate` để chuẩn bị icon 1024×1024 (CI tự tạo).

### Kiểm thử

- `scripts/*-tests.swift`: test logic thuần Swift, biên dịch độc lập bằng `swiftc` (xem từng bước trong `.github/workflows/ios.yml`), ví dụ `voice-ducking-tests`, `ripple-edit-tests`, `cube-lut-tests`, `incoming-link-tests`, `storage-policy-tests`.
- `SmartVideoTests/`: XCTest chạy trên iOS Simulator trong CI.

### GitHub Actions

Workflow **iOS Build** chạy khi push `main` và với mọi pull request: kiểm tra Python resolver, các test `swiftc`, XCTest trên Simulator, rồi build bản Simulator *không ký*. `SmartVideo-Simulator.zip` **không** cài được trên iPhone thật; muốn có IPA cần chứng chỉ và provisioning profile của bạn (không đưa private key lên repo).

## Kiến trúc

```text
PhotosPicker / Files / Kho video
    ↓
MediaStorage (Documents/Media, Exports, RenderTemp, LUTs)
    ↓
EditorViewModel (+ extension theo tính năng) / TimelineClip
    ↓
VideoRenderer
  ├─ Ảnh → AVAssetWriter;  clip → AVMutableComposition
  ├─ AlphaVideoProcessor: PIP tách nền → HEVC alpha (cache)
  ├─ TimelineComposer: PIP, chuyển cảnh, keyframe
  ├─ StudioColorGrader (+ LUTLibrary) cho từng frame
  └─ AVMutableAudioMix: tiếng gốc, nhạc (ducking theo VoiceActivityAnalyzer), giọng, FX
    ↓
AVAssetExportSession → Documents/Exports/*.mp4 → Photos / ShareLink
```

Thư mục chính: `SmartVideo/Models` (dữ liệu và toán thuần), `SmartVideo/Services` (xử lý media), `SmartVideo/ViewModels`, `SmartVideo/Views`, `backend/` (dịch vụ tùy chọn: `video_resolver`, `audio_separator`, `gemini_gateway`).

## Quyền riêng tư

Mặc định mọi xử lý nằm trên thiết bị. PhotosPicker không đòi quyền xem cả thư viện; quyền **add-only** chỉ xin khi lưu video. Nhận diện giọng nói chạy offline, chỉ dùng dịch vụ Apple khi bạn bật riêng. Tính năng Gemini chỉ gửi **văn bản** qua gateway của bạn hoặc trực tiếp bằng khóa của bạn (BYOK); khóa API và token gateway được lưu trong Keychain, gửi bằng header HTTPS và không được ghi log. Xóa app sẽ mất dự án cục bộ — hãy sao lưu trước.

## Lưu ý cho iPhone 12 Pro Max

Bắt đầu với 1080p/30 FPS và dự án ngắn; 4K đầu vào được hạ về kích thước xuất. Render dài hoặc nhiều lớp (PIP tách nền, mockup, VFX) có thể nóng máy — giữ app ở foreground khi render.
