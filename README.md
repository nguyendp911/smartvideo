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

## Nâng cấp dựng phim v2.3.0

- Tab **Hiệu ứng** trên thanh công cụ: chọn **Cắt thẳng** hoặc **Hòa tan (cross-dissolve)** và thời gian chuyển cảnh từ 0,2 đến 0,8 giây. Hai track video chồng hình thực sự, giảm thời lượng timeline theo tổng các lần chồng.
- **Điều chỉnh tốc độ video** tại từng clip: 0,5× / 1× / 1,5× / 2×; có tác dụng khi xuất MP4 và khi xem trước clip. Tăng/giảm tốc có thể thay đổi cao độ tiếng gốc.
- **Hiệu ứng Ken Burns cho ảnh tĩnh**: zoom in, zoom out, pan trái và pan phải; sinh frame mới bằng Core Image khi xuất.
- **Màu cho ảnh**: nguyên bản, điện ảnh, đen trắng, màu ấm và màu lạnh. Bộ màu hiện áp dụng cho ảnh tĩnh, **chưa** áp dụng cho clip video.
- **Một chạm dựng điện ảnh**: bật chuyển cảnh hòa tan 0,45 giây, phối hợp chuyển động ảnh và bộ màu điện ảnh.
- Với iPhone 12 Pro Max nên thử dự án ngắn 720p hoặc 1080p/30FPS trước; preview của ảnh tĩnh chưa mô phỏng đầy đủ chuyển động/điều màu, xuất video mới thể hiện hiệu ứng.

**Trạng thái kiểm thử**: workflow GitHub Actions biên dịch Swift; cần kiểm thử video có nhiều đoạn, nguồn xoay dọc/ngang, âm thanh, tốc độ và chuyển cảnh trên máy thật.


## ViePN Smart Video v2.4.0 – Mirror, Privacy & Smart Highlights

Tất cả kỹ thuật dưới đây xử lý cục bộ trên iPhone, không yêu cầu API hoặc máy chủ.

### Kỹ thuật mới

- **Lật video/ảnh ngang hoặc dọc**: tab **Đoạn**, chọn clip rồi chọn Lật ngang/Lật dọc. Áp dụng trong preview và video xuất.
- **Lọc metadata nguồn**: tab **Khung**, tùy chọn "Không giữ metadata của video gốc". Bật mặc định. Dùng `AVAssetExportSession.metadata = []` và `AVMetadataItemFilter.forSharing()`. Có thể loại bỏ metadata nguồn như GPS/tên camera/tác giả, **không bảo đảm MP4 hoàn toàn không còn trường metadata kỹ thuật do hệ điều hành tự tạo**.
- **Thuyết minh**: thu micro, nhập file âm thanh hoặc nhập văn bản tiếng Việt để iOS tự đọc thành file CAF dùng trong video. Chỉnh thời điểm bắt đầu/âm lượng. Nhạc nền được duck khi thuyết minh phát và fade-out khi kết thúc. Giọng TTS sử dụng voice trên thiết bị, không phải mô hình tạo giọng riêng.
- **Smart MP3 Highlights**: tab **AI**, chọn MP3/M4A rồi chọn độ dài 15/20/30 giây. Phân tích năng lượng âm thanh + biến động dải động để đề xuất tối đa 3 đoạn. Chọn "Lấy đoạn" để áp dụng ngay trên timeline nhạc; có thể cắt & chia sẻ **M4A** (AVFoundation không xuất MP3).
- **Vision Video Highlights**: chọn clip video trong timeline → tab **AI** → Phân tích video. Vision kiểm tra tối đa 32 khung hình, tìm khuôn mặt, mức chú ý của chủ thể, thay đổi hình và tương phản. Chọn từng highlight hoặc bấm "Tạo montage từ các highlight" để thay đoạn đã chọn bằng các đoạn ngắn; có nút hoàn tác một lần. Video gốc trong `Documents/Media` vẫn giữ nguyên.

### Giới hạn cần biết

- "Smart Highlights" **không phải AI hiểu ý nghĩa cảm xúc, lời bài hát hay toàn bộ câu chuyện**. Music sử dụng chấm điểm âm lượng/bùng nổ, Vision dựa trên nhận diện và mức nổi bật thị giác. Với tác phẩm dài, audio chỉ quét tối đa 240 giây đầu và video phân tích tối đa 32 khung hình. Hãy duyệt kết quả trước khi xuất.
- Các hiệu ứng được kiểm tra bằng trình biên dịch iOS trên GitHub Actions. **Chưa kiểm thử end-to-end thực tế trên iPhone 12 Pro Max**. Dự án dài hoặc codec lạ có thể gặp lỗi, cần báo lỗi từ thiết bị.
- "Lật dọc" nghĩa là phản chiếu theo trục ngang (đảo trên/dưới), không phải xoay 90 độ.
- Chọn xóa/cài lại app có thể mất file cục bộ; nên lưu MP4 và file dự án ra Tệp trước.
- GitHub Actions xuất **IPA chưa ký** để phục vụ ký với Apple certificate/provisioning hợp lệ. Không phải IPA cài thẳng từ Safari.

### Kiến trúc highlight

```text
Nhạc MP3/M4A → AVAssetReader/PCM → mức năng lượng 0,5s → xếp hạng đoạn → chọn / xuất M4A
Video       → AVAssetImageGenerator → Vision (faces + saliency) + scene change
            → gợi ý đoạn 1–7s → thay clip bằng nhiều clip ngắn → dựng MP4
TXT         → AVSpeechSynthesizer.write() → PCM CAF → track thuyết minh + duck nền
Ảnh/Video   → Transform/Flip → AVMutableVideoComposition → MP4 + lọc metadata
```



## ViePN Smart Video v2.5.0 – VFX Library

Đã thêm tab **VFX** bên cạnh **Khung** trong thanh công cụ dựng phim. Đây là thư viện **9 hiệu ứng được vẽ bằng Core Animation/Core Graphics**, không yêu cầu server hay tải gói asset ngoài:

| Hiệu ứng | Xuất MP4 | Xem trước trong editor |
| --- | --- | --- |
| Hạt phim | Texture nhiễu, nhấp nháy opacity | Mô phỏng tĩnh |
| Viền tối | Radial vignette | Mô phỏng |
| Lóa ánh sáng | Gradient ấm trượt ngang | Mô phỏng tĩnh |
| Tuyết rơi | Các hạt chuyển động | Mô phỏng tĩnh |
| Mưa | Các vệt mưa rơi | Mô phỏng tĩnh |
| Tia lửa | Những hạt sáng bay lên | Mô phỏng tĩnh |
| Bụi ánh sáng | Các hạt bụi trôi nổi | Mô phỏng tĩnh |
| Nháy sáng | Flash sáng lặp | Mô phỏng tĩnh |
| Viền điện ảnh | Thanh đen trên/dưới | Mô phỏng |

Tại VFX, chọn/bỏ chọn nhiều hiệu ứng, chỉnh thanh **Cường độ VFX** (10–100%), bấm **Xóa tất cả** để tắt hoặc chọn một trong 2 phối cảnh có sẵn: **Phim điện ảnh** (hạt phim + vignette + thanh đen) và **Mộng mơ** (bụi + lóa sáng).

**Đầu ra:** `VideoRenderer` truyền lựa chọn vào `SubtitleOverlay`; `VFXOverlayLibrary` tạo các `CALayer` để đặt lên ảnh/video và phụ đề được đặt ở phía trên. Toàn bộ VFX được render vào MP4 qua cùng một `AVVideoCompositionCoreAnimationTool` (không phải giao diện trang trí).

**Tối ưu iPhone 12 Pro Max:** hoạt ảnh tạo procedurally, 1 texture grain kích thước nhỏ, khoảng 24–65 layer hạt mỗi hiệu ứng. Nên chọn không quá 3 hiệu ứng nặng cùng lúc khi xuất 1080p; với timeline dài hãy thử 720p trước. Khi hiệu ứng đã bật, bản preview chỉ **minh họa hình thái tĩnh**, không thể hiện chính xác chuyển động của phiên bản đã render. Hiện hiệu ứng áp dụng lên **toàn dự án**, chưa có VFX riêng từng clip hoặc keyframe trên timeline.

**Kiểm thử:** GitHub Actions xác nhận biên dịch và đóng gói IPA chưa ký. Chưa thể xác nhận tốc độ, tính năng animation của AVFoundation hoặc khả năng render VFX dài trên iPhone 12 Pro Max thực tế, cần thử trên thiết bị.


## ViePN Smart Video v2.6.0 – Cinematic VFX Rework

Phiên bản này được chỉnh sửa dựa trên video mẫu SmartVideo-CFC7EC97.mp4 do người dùng cung cấp: gameplay ngang nhỏ ở giữa khung dọc, các mảng đỏ/nâu hình chữ nhật của hiệu ứng light leak phủ cả vùng đen.

### Những thay đổi kỹ thuật

- **Light Leak v2**: thay dải màu tuyến tính có biên hình chữ nhật bằng gradient bán kính với alpha trong suốt ở rìa, màu cam dịu; giảm độ che nội dung.
- **Auto VFX Content Bounds**: ước lượng vùng sáng/thấy được bằng thumbnail kích thước 64×112 px; tự giới hạn VFX lên khu vực khung video (kể cả letterbox được ghi sẵn). Có lựa chọn "Toàn khung" để cố ý phủ lên toàn bộ canvas.
- **Giảm độ tối và mật độ hiệu ứng**: vignette tối đa khoảng 42% × cường độ; hạt mưa, tuyết và tia lửa giảm độ đậm để giữ nội dung nhìn rõ. Mặc định cường độ 30% thay vì 55%.
- **Điểm bắt đầu/kết thúc VFX**: trong tab VFX, chỉnh mốc thời gian áp dụng hiệu ứng bằng hai thanh. Hạn chế: cùng một khoảng thời gian cho toàn bộ VFX đã chọn, chưa phải keyframe độc lập trên từng clip.
- **4 preset mới**: Bokeh mềm, Vệt sáng ngang, Scanlines và Trầy xước phim. Tổng cộng **13 preset VFX**.
- **Preview tốt hơn**: mô phỏng lóa sáng bằng gradient mềm và có xem trước tĩnh cho bốn preset mới. Các chuyển động thực tế chỉ hiển thị đầy đủ sau khi xuất MP4.

### Quy trình kiểm tra đề xuất trên iPhone 12 Pro Max

1. Nhập một video 16:9 hoặc video dọc có gameplay 16:9 và dải đen như mẫu.
2. Chọn khung 9:16 → VFX → **Chỉ trong hình** → **Lóa ánh sáng** cường độ 20–30%.
3. Xuất một video ngắn ở 720p/30FPS và kiểm tra không còn mảng đỏ/hình chữ nhật trên vùng đen.
4. Thử Bokeh và Vệt sáng với cường độ 20–40%; đối chiếu bản MP4 với preview.
5. Khi nhiều clip có vùng nội dung khác nhau, bộ phát hiện hiện dựa trên **clip đầu tiên**; vùng VFX chưa thay đổi tự động theo từng clip. Mọi tính năng mới cần kiểm thử trên thiết bị thật.

Chạy trực tiếp bằng Core Animation/AVFoundation. Không có mô hình AI tổng hợp VFX hoặc asset VFX độc quyền bên thứ ba.
