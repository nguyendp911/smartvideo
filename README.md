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


## ViePN Smart Video v2.7.0 – Voice Studio, Silence Removal and Metadata

### Thư viện giọng & sắc thái thuyết minh
- Tab **Giọng** → chọn giọng có sẵn trong hệ thống iOS. Ưu tiên liệt kê tiếng Việt trước, sau đó tiếng Anh. Số lượng giọng phụ thuộc giọng đã cài trên iPhone (không tự hứa có đủ giọng nam/nữ). Có **Nghe thử** trực tiếp.
- 6 sắc thái điều chỉnh tốc độ, cao độ, khoảng nghỉ: **Tự nhiên, Ấm áp, Sôi nổi, Kể chuyện, Chậm rãi, Bản tin**. Đây là preset điều khiển TTS Apple, **không phải mô hình AI tạo cảm xúc thật**.
- Thanh tinh chỉnh tốc độ 75%–130%, cao độ 75%–125%; tạo file CAF giọng đọc và dùng làm track thuyết minh. Có thể **Tạo phụ đề từ lời thuyết minh**, với thời gian chia đều sơ bộ (chưa tự đồng bộ lời nói).
- Thu micro hoặc nhập tệp âm thanh sẵn có vẫn hoạt động; thuyết minh có thời điểm bắt đầu và âm lượng riêng.

### Xóa khoảng lặng
- Trong tab **Giọng**, khi đã có tệp thuyết minh, bấm **Xóa khoảng lặng**. Phần mềm đọc PCM, đo RMS trong khung 80ms, phát hiện lời nói theo ngưỡng dBFS, gộp các cụm gần nhau và chừa 120ms đệm ở đầu/cuối. Cắt những khoảng lặng lớn hơn mức cấu hình; xuất file **M4A mới**, không ghi đè bản gốc.
- Điều chỉnh **ngưỡng phát hiện lời nói** (-55 tới -24 dBFS) và **khoảng lặng tối thiểu** (0,25 tới 1,2 giây). Nên nghe lại bản cắt để phát hiện mất âm đầu hoặc dấu câu.
- Thao tác xóa khoảng lặng làm thay đổi độ dài bản thuyết minh; **không tự căn lại subtitle**, có thể cần chỉnh sửa mốc thời gian phụ đề.

### Metadata do người dùng nhập
- Tab **Metadata** → bật "Gắn metadata do tôi nhập" → điền tiêu đề, tác giả, mô tả, bản quyền, từ khóa, thể loại, ghi chú, năm. Khi xuất MP4, app tạo metadata common-key thông qua AVFoundation.
- Tùy chọn **lọc metadata nguồn** hoạt động độc lập với metadata mới. Các ứng dụng và codec khác nhau có thể chỉ nhận một phần trường metadata tùy chuẩn container. Thông tin kỹ thuật như codec, bitrate, kích thước và thời lượng vẫn được hệ điều hành ghi lại.

### Kỹ thuật dựng thêm
- Chỉnh riêng thời lượng **fade-in nhạc 0–3 giây** và **fade-out 0–5 giây**.
- Giảm nhạc nền tự động trong khoảng thời gian có giọng đọc.
- Sửa **Giữ tiếng gốc của các clip**: tắt thì timeline thực sự bỏ track tiếng gốc khi kết xuất.
- Thanh công cụ gồm menu **Công cụ** trên cùng để vào trực tiếp mỗi chức năng; không cần vuốt qua toàn bộ các tab.

### Trạng thái kiểm thử
GitHub Actions kiểm tra compile Swift và tạo IPA iPhone unsigned. Chưa thực hiện kiểm thử âm thanh/metadata/thời gian TTS end-to-end trên iPhone 12 Pro Max. Nếu MP4 không hiển thị trường metadata trong ứng dụng ngoài, hãy kiểm tra metadata bằng công cụ phân tích container; đây không đồng nghĩa với trường đã được giữ trong mọi định dạng chia sẻ.


## ViePN Smart Video v2.8.0 – CapCut-style editing foundations

Phiên bản này nâng cấp **workflow dựng phim**, không sao chép giao diện/biểu tượng/tài sản có bản quyền của CapCut.

### Timeline có thể chỉnh chính xác

- Thanh tua 0,04 giây trong timeline; chọn clip tự chuyển phần xem trước tới đoạn đó.
- Video có khung hình thumbnail thực tế (lấy bằng AVAssetImageGenerator, cache NSCache); ảnh hiển thị preview ảnh. Tự sinh thumbnail khi cuộn tới đoạn.
- Zoom timeline từ 0,5× đến 3,0×: tăng/giảm bề ngang clip để dễ nhìn vùng cần cắt.
- **Tách clip tại con trỏ**: đối với video chia duration nguồn đúng theo playbackSpeed, đối với ảnh chia thời lượng hiển thị, giữ media gốc; không tạo file video mới.
- **Nhân bản clip**, **kéo thả đổi thứ tự**, di chuyển trái/phải/xóa. Thao tác thay đổi cấu trúc timeline có **Undo/Redo tối đa 40 lần**.
- Thanh hiển thị thời gian phút:giây.phần trăm giây.

### Dự án offline

- Menu folder **Dự án** ở thanh trên; tạo mới, đặt tên, lưu, mở hoặc xóa dự án JSON trong Documents/Projects.
- Lưu bố cục clip, tốc độ, thời gian cắt, subtitle, tỷ lệ và độ phân giải, chuyển cảnh, nhạc và giọng đọc, VFX, metadata xuất, các giá trị chỉnh sửa chính.
- Tệp JSON chỉ lưu edit decision list, tham chiếu tên media đã được nhập vào Documents/Media; **không bao gồm file media**. Không xóa app trước khi sao lưu dữ liệu gốc.
- Dự án được lưu **thủ công**, không có autosave hay đồng bộ đám mây.
- Phân tách timeline hỗ trợ chồng hình từ cross-dissolve; ở vùng transition con trỏ ưu tiên clip mới vào, không phát preview hoàn chỉnh của cả hai clip cùng lúc.

### Giới hạn so với CapCut

Đây **chưa phải bản tương đương CapCut**: chưa có layer overlay video độc lập, xử lý toàn bộ multi-track, track text độc lập có keyframe riêng, stabilisation, motion-tracking hay thư viện tài nguyên online. Preview chỉ phát clip đang chọn, không render trực tiếp toàn bộ transition/VFX/âm thanh trộn; cần xuất MP4 để xem kết quả đầy đủ. Hãy kiểm tra kết quả trên iPhone 12 Pro Max thực tế trước khi dựng dự án dài.

### Cách kiểm tra nhanh

1. Thêm 3 video, chọn tab Đoạn, kéo thanh tua tới giữa clip thứ nhất.
2. Chọn **Tách**; timeline sẽ có 4 clip. **Undo** và **Redo** để kiểm tra có phục hồi chính xác.
3. Nhấn vào clip đã tách → biểu tượng **Nhân bản**; kéo thả một clip sang vị trí khác.
4. Bấm biểu tượng folder → nhập tên dự án → **Lưu dự án hiện tại** → **Tạo dự án mới** → mở lại dự án đã lưu.
5. Xuất MP4 ngắn, kiểm tra timeline sau khi chỉnh. Với video codec đặc biệt, bản nguồn vẫn được giữ để thử lại.



## ViePN Smart Video v2.9.0 – Overlay & Picture-in-Picture

- Thêm tab **Overlay** (mở nhanh từ menu Công cụ): chọn ảnh/logo/sticker từ Ảnh iOS. Trình nhập overlay lưu thành PNG giữ kênh alpha, **không chuyển JPEG làm mất nền trong suốt**.
- Mỗi ảnh là một **track overlay độc lập** với thời điểm bắt đầu, thời lượng, kích thước theo khung, độ mờ, xoay và vị trí. Kéo ảnh trên preview để đặt vị trí.
- Hỗ trợ hai **keyframe vị trí**: điểm đầu (X/Y) và điểm cuối (X/Y). AVFoundation/Core Animation nội suy vị trí khi xuất MP4. Preview tính nội suy theo con trỏ timeline; kéo ảnh dịch cả đường chuyển động.
- Có thể thêm nhiều overlay và chỉnh riêng từng lớp, không xóa hay sửa ảnh/video nguồn. Overlay được ghi **trên lớp VFX và dưới phụ đề** trong cùng \`AVVideoCompositionCoreAnimationTool\`.
- Dự án v2.9 lưu và mở lại các overlay. Trình đọc dự án vẫn hỗ trợ dự án JSON v2.8 không có trường overlay; cần giữ các tệp PNG cùng với dữ liệu ứng dụng.
- **Giới hạn**: chưa hỗ trợ overlay video có alpha, mask/chroma key nâng cao, easing đa điểm, hoặc xuất từng track riêng. Các hiệu ứng/phụ đề đều được render cuối khi xuất MP4; preview không phải full realtime timeline compositor.
- Cần kiểm thử kết xuất với PNG trong suốt, nhiều lớp, video 720p/1080p trên iPhone 12 Pro Max. GitHub Actions xác nhận *biên dịch*, không xác nhận mọi hiệu ứng xuất đúng trên thiết bị thật.


## v3.0.0 – Nền tảng dựng nhiều lớp (Video PIP / Text / Chroma Key)

- **Video PIP**: tab **Video PIP** → Thêm video từ Photos. Tạo nhiều track video độc lập (giới hạn 4 track PIP đồng thời); điều chỉnh thời gian xuất hiện, độ dài, kích thước, opacity, vị trí điểm đầu/cuối. Video gốc nằm ở timeline chính; track PIP được chèn vào `AVMutableComposition` và transform bằng `AVMutableVideoCompositionLayerInstruction`. Tiếng từ video PIP đang **tắt mặc định**, chưa có mixer riêng.
- **Text Overlay**: tab **Chữ** → tạo nhiều lớp chữ độc lập với phụ đề. Chỉnh nội dung, thời gian, độ mờ, cỡ chữ, màu HEX, nền tối, tọa độ chuyển động và lựa chọn gia tốc. Được render trực tiếp vào MP4 bằng Core Animation.
- **Chroma Key ảnh**: tab **Overlay** → chọn ảnh xanh lá/xanh dương → bật **Chroma Key**. Thay đổi ngưỡng tách màu và độ mềm viền. Xử lý bằng Core Image CIColorCube để xuất ảnh alpha, KHÔNG sửa tệp PNG/JPG nguồn.
- **Chroma Key video**: chưa được hỗ trợ. Video PIP có hình chuyển động nhưng chưa xử lý khử nền xanh theo từng frame; cần custom pixel-buffer compositor để làm đúng.
- **Editor preview**: hiển thị ảnh đã khử nền, xem trước chữ và vị trí keyframe theo con trỏ; **video PIP chỉ hiện một frame đại diện**, bản MP4 xuất mới phát video phủ đầy đủ.
- **Lưu/mở dự án**: lưu cả ảnh phủ, video PIP, lớp chữ và tùy chọn chroma. File dự án JSON cũ (v2.8/v2.9) vẫn được đọc: field thiếu mặc định là mảng rỗng, thuộc tính chroma mới mặc định tắt. Không xóa file media trong thư mục ứng dụng nếu cần mở lại.
- **Giới hạn**: đây mới là nền tảng multi-layer. Chưa có mask/chroma key video, clip speed riêng cho PIP, time-stretch audio PIP, chuyển cảnh giữa các PIP, timeline preview tổng hợp toàn bộ video, hoặc realtime GPU compositor.
- **Kiểm thử**: GitHub Actions chỉ xác nhận biên dịch iPhone/Simulator và đóng gói unsigned IPA. Cần kiểm tra trên iPhone 12 Pro Max với dự án ngắn, một lớp video PIP và một ảnh xanh trước khi xuất dự án nhiều lớp 1080p.


## ViePN Smart Video v3.1.0 – Multi-track Sound Effects

Ứng dụng tiếp tục phát triển trên iOS 16+ với một **studio hiệu ứng âm thanh đa track**. Không dùng hay sao chép âm thanh/giao diện có bản quyền của CapCut.

- **Tab Âm FX**: thêm âm thanh từ Files (MP3, M4A, WAV và các định dạng AVFoundation hỗ trợ) hoặc tạo sáu âm thanh tổng hợp gốc ngay trên máy: **Whoosh, Pop, Impact, Click, Riser, Glitch**.
- **Tối đa 12 đoạn SFX** trong một dự án, đặt đồng thời ở các mốc khác nhau; mỗi đoạn có file nguồn, thời điểm bắt đầu trên timeline, thời điểm cắt vào nguồn, thời lượng phát, mức âm lượng 0–100%, mute, fade-in, fade-out.
- **Hiển thị waveform**: phân tích đỉnh âm thanh của tối đa 90 giây đầu thành 64 cột. Với tệp dài hơn, waveform chỉ biểu diễn đầu nguồn.
- **Trên timeline**: hiển thị hàng FX riêng, chạm vào một hiệu ứng để chọn đoạn và mở tab Âm FX. Các nút **Đặt tại con trỏ**, **Nhân bản**, **Xóa**, **Nghe thử** giúp giảm thao tác vuốt.
- **Render thật**: mỗi hiệu ứng có track audio riêng trong AVMutableComposition, chèn vào thời gian đã chọn, dùng AVMutableAudioMixInputParameters để điều chỉnh gain và fade. Track SFX có thể phát chồng lên nhạc nền, tiếng video và thuyết minh.
- **Lưu / mở lại dự án**: âm thanh và thông số SFX được ghi vào JSON trong Documents/Projects. Dự án 3.0 hoặc cũ hơn không có trường soundEffects vẫn có thể mở, mặc định là danh sách SFX rỗng.
- **Không phá hủy nguồn**: tệp nhạc gốc không bị cắt/ghi đè. Nếu xóa ứng dụng hoặc mất thư mục Media, bản JSON một mình không chứa audio để dựng lại.

**Giới hạn hiện tại**: SoundFX chỉ nghe thử độc lập trong editor, chưa có phát trực tiếp bản phối tổng hợp theo con trỏ (cần preview mixer riêng). Không có waveform toàn bài cho nhạc dài trên 90 giây, không tạo tiếng bằng mô hình AI, chưa có bộ lọc EQ/compressor đa băng hoặc pitch shifting. Các hiệu ứng tự tổng hợp là tín hiệu ngắn cơ bản, không thay thế thư viện âm thanh chuyên nghiệp.

Kiểm thử bằng GitHub Actions xác nhận biên dịch iOS/Simulator và tạo IPA chưa ký; cần thử xuất MP4 với nhiều track SFX chồng lên nhau trên iPhone 12 Pro Max để xác nhận chất lượng/đồng bộ thực tế.


## ViePN Smart Video v3.2.0 – Beat Sync & Audio Mix Audition

Bản này nối tiếp v3.1.0, tập trung vào các thao tác phối âm nhanh phục vụ chỉnh sửa video nhiều lớp:

- **Phân tích nhịp MP3/M4A cục bộ**: Tab **Âm FX → Phân tích nhịp MP3** đọc PCM tối đa 90 giây từ mốc cắt nhạc đã chọn; phát hiện biến động RMS và đề xuất BPM trong khoảng khoảng 70–180 BPM. Đây là **ước lượng từ onset/âm lượng**, không phải nhận diện âm nhạc bằng AI hoặc bảo đảm nhịp chính xác 100%.
- **Lưới nhịp**: Hiển thị mốc nhịp nhỏ dưới thanh tua timeline và trong tab Âm FX. Nếu bật lặp nhạc, lưới lặp theo độ dài phần nhạc đã chọn; vùng nhạc chưa phân tích không có mốc.
- **Căn nhịp cho âm thanh**: Chọn một đoạn SFX → **Căn nhịp** để đổi vị trí bắt đầu sang nhịp gần nhất. Hoặc chọn **Căn tất cả FX**. Có thể chỉnh lại vị trí phát bằng slider sau khi căn.
- **Nghe bản phối nhiều track ngay trong editor**: bấm **Nghe bản phối** để phát MP3, thuyết minh và các SFX (tối đa 12 lớp), bắt đầu từ con trỏ timeline. Dùng một `AVMutableComposition` và `AVMutableAudioMix` trong bộ nhớ; **không xuất file tạm**.
- **Phạm vi bản phối được nghe thử**: **không gồm tiếng gốc video, PIP, hoặc ducking nhạc nền theo giọng nói**. Nếu cần xác nhận âm lượng đầy đủ và đồng bộ cuối cùng, hãy xuất một MP4 ngắn rồi nghe lại.
- **Giữ nguyên dự án cũ**: mảng beat/bpm mới trong file dự án JSON được đọc bằng giá trị tùy chọn; dự án bản trước không có trường này vẫn mở bình thường. Mốc thời gian SFX sau khi snap được lưu cùng dự án.

### Cách thử nhanh
1. Thêm video khoảng 20–30 giây, vào **Âm thanh** và chọn MP3 có nhịp trống rõ.
2. Mở **Âm FX**, thêm hiệu ứng Pop, Whoosh hay Impact. Bấm **Phân tích nhịp MP3**.
3. Quan sát BPM và lưới nhịp. Chọn SFX → **Căn nhịp**, hoặc **Căn tất cả FX**.
4. Đưa con trỏ về đầu hoặc đoạn muốn kiểm tra → **Nghe bản phối**. Nếu đúng ý, xuất MP4.
5. Mở **Dự án** → Lưu → Mở lại và kiểm tra các đoạn SFX vẫn nằm ở mốc đã căn.

**Giới hạn**: Nhịp ước lượng có thể sai nửa/nhân đôi BPM ở nhạc phức tạp. Bộ nghe thử âm thanh mới không thay thế phần preview video tổng hợp đầy đủ, và chưa có EQ/compressor hay thay đổi pitch cho mỗi SFX. Việc build thành công chỉ chứng minh mã nguồn tương thích ở bước biên dịch; cần chạy thực tế trên iPhone 12 Pro Max.


## ViePN Smart Video v3.3.0 – Voice Mastering Pro

Bản v3.3.0 bổ sung xử lý giọng thuyết minh offline, tương tự nhóm công cụ audio mastering của trình dựng chuyên nghiệp. Toàn bộ tính năng mới chạy trong app, **không sử dụng AI sinh giọng hay dịch vụ đám mây**.

- Tab **Giọng → Voice Mastering Pro** với 5 preset: **Nguyên bản, Podcast, Ấm áp, Trong sáng, Radio**.
- **EQ 3 dải** có slider ±12 dB: low shelf 155 Hz, mid peak 1450 Hz, high shelf xấp xỉ 4900 Hz (tự giới hạn với file sample rate thấp).
- **Compressor**: chỉnh ngưỡng từ -36 tới -8 dBFS và tỷ lệ 1:1 đến 6:1. Áp dụng attack 12ms / release 170ms; giảm mức động học thay vì chỉ tăng giảm âm lượng chung.
- **Noise gate**: tùy chọn cổng giảm tiếng nền rất nhỏ, ngưỡng -60 đến -30 dBFS, lên/xuống gain có smoothing để hạn chế cắt âm đột ngột. Không tương đương khử tiếng ồn bằng AI hoặc voice isolation.
- **Output gain**: -6 tới +8 dB; giới hạn peak ~-0.35 dBFS để tránh clipping số, tuy nhiên không phải chuẩn hóa LUFS theo chuẩn phát hành.
- **Xử lý thực sự vào bản xuất**: bấm **Áp dụng vào giọng đọc** để tạo một file CAF PCM mới trong `Documents/Media`. File này thay cho `voiceoverURL` và được pipeline xuất MP4 trộn vào dự án. File gốc được giữ, có nút **Khôi phục**.
- **A/B Audition**: **Nghe bản gốc** / **Nghe bản xử lý**, không phải chỉ nghe preset trong giao diện. Thay preset hoặc thay slider cần bấm **Áp dụng vào giọng đọc** lại để thay đổi đầu ra.
- **Lưu dự án**: lưu tham số mastering và filename bản thu gốc để tiếp tục mở lại, nghe so sánh và khôi phục. Dự án cũ trước v3.3 thiếu các trường này vẫn mở bình thường với giá trị mặc định.
- **Giới hạn định dạng**: tập trung giọng mono/stereo, iOS AVAudioFile PCM 8–192kHz, tệp dài tối đa 15 phút để tránh xuất file PCM quá lớn. Một số định dạng audio codec lạ có thể không giải mã được.
- **Lưu ý hệ thống**: file CAF chưa nén có thể chiếm nhiều bộ nhớ lưu trữ. App giữ các phiên bản đã xử lý trong Media để không làm hỏng dự án đã lưu; trước khi xóa app hãy sao lưu toàn bộ media, không chỉ JSON.
- **Kiểm thử**: GitHub Actions xác nhận biên dịch iPhone/Simulator và đóng gói IPA chưa ký. Chưa kiểm thử tốc độ, crash hoặc chất lượng audio end-to-end trên iPhone 12 Pro Max thật. Nên xuất thử một MP4 10–20 giây, so sánh âm thanh và mới áp dụng trên clip dài.


## ViePN Smart Video v3.4.0 – Music Mastering, RMS Normalize, Synchronized Draft Preview

### 1. Music Mastering
- Tab **Âm thanh → Music Mastering**: sáu preset EQ gốc **Nguyên bản, Âm ấm, Sáng rõ, Bass Boost, Điện ảnh, Lo-fi**. Có các slider bass/mid/treble ±12 dB, tỷ lệ compressor 1:1–5:1 và ngưỡng nén -34 đến -8 dBFS.
- **Áp dụng EQ**: chạy bộ xử lý PCM offline, tạo CAF nhạc đã qua EQ/compressor; file gốc được giữ lại. **Khôi phục nhạc gốc** để trở về file chưa xử lý. Chỉ thay đổi âm thanh khi bấm áp dụng, slider riêng không tự thay đổi video cuối.
- Từng dự án JSON lưu tham số music mastering, nhạc gốc và nhạc đã xử lý. Tương thích dự án trước v3.4 (trường mới là tùy chọn).

### 2. Chuẩn hóa RMS và bảo vệ đỉnh
- **Chuẩn hóa RMS** cho nhạc tới mục tiêu **-18 dBFS**; cho thuyết minh tới **-20 dBFS**, bằng công cụ quét PCM hai lượt và xuất CAF mới.
- Gain điều chỉnh trong khoảng **-15 dB đến +12 dB** và giới hạn đỉnh sample **-1 dBFS**. Nếu nguồn có nhiều transient đỉnh cao, mức đích RMS sẽ **không đạt**, vì ưu tiên không méo tiếng.
- Đây là **RMS thông thường, không phải LUFS EBU R128, loudness-gating hoặc true-peak oversampling**. Không quảng cáo là chuẩn hóa LUFS chuẩn phát hành. Các bộ xử lý tạo file PCM trung gian lớn, mỗi file tối đa 15 phút.
- Có thể **Nghe bản gốc / Nghe bản xử lý** trong Studio thuyết minh và **Nghe nhạc** trong Music Mastering.

### 3. Xem thử toàn bộ hình + tiếng đồng bộ
- Nút **Xem thử toàn bộ · 720p** bên dưới editor sẽ dựng **một MP4 720p đầy đủ** thông qua cùng bộ AVFoundation/VideoRenderer đang dùng cho xuất 1080p.
- Màn hình **Xem thử bản dựng** sử dụng AVKit `VideoPlayer` để phát MP4 với chuyển cảnh, VFX, ảnh và video PIP, text overlay, tiếng gốc, nhạc, giọng đọc và SFX được ghép **trong cùng file**. Nhấn Đóng để quay về chỉnh sửa.
- Đây **không phải preview realtime tức thì**: phải đợi render MP4, và dự án dài vẫn tốn nhiều thời gian/bộ nhớ. Preview được dựng cho *toàn bộ timeline* (không chỉ 10–20 giây gần con trỏ). Chỉnh sửa xong phải bấm lại để tạo bản nháp mới.
- Video preview được lưu ở Exports của app; khuyến nghị dọn các file render nháp cũ khi không dùng (các bản hiện tại chưa có chức năng tự dọn hết lịch sử render nháp).

### Kiểm thử đề xuất
1. Nhập video 10–20 giây, nhạc MP3 và một track thuyết minh.
2. Tab **Âm thanh**: chọn **Bass Boost** → **Áp dụng EQ** → **Nghe nhạc**. Thử **Chuẩn hóa RMS**, rồi **Khôi phục nhạc gốc**.
3. Tab **Giọng**: **Chuẩn hóa giọng · RMS -20 dBFS**, nghe trước và sau.
4. Thêm âm FX, phụ đề và chuyển cảnh; bấm **Xem thử toàn bộ · 720p** để kiểm tra hình/tiếng khớp.
5. Chỉnh sửa lại, xuất 1080p và đối chiếu với preview. Lưu dự án → mở lại và kiểm tra file âm thanh gốc, file đã xử lý, preset và thông số.

**Trạng thái**: GitHub Actions xác minh khả năng biên dịch iOS và tạo unsigned IPA. Hiệu ứng âm thanh chưa được thử nghiệm end-to-end trên iPhone 12 Pro Max; cần nghe và kiểm tra nhiều định dạng audio cụ thể trên thiết bị thật.


## ViePN Smart Video v3.5.0 – Auto Captions & Subtitle Designer

### Speech-to-subtitles with real time codes
- Mở **Công cụ → Phụ đề → Auto Captions**, chọn nguồn **Thuyết minh** hoặc **Clip video đang chọn**, ngôn ngữ **Tiếng Việt**, English, 中文, 日本語 hoặc 한국어. Cấp quyền nhận diện giọng nói khi iOS yêu cầu.
- App dùng **Apple Speech / SFSpeechURLRecognitionRequest** với các khoảng thời gian `SFTranscriptionSegment.timestamp` và `duration` thực từ đoạn âm thanh; không tự gán thời gian giả đều theo độ dài video.
- Với **Clip video**, tách phần audio của clip trong một file M4A tạm, rồi chuyển mốc thời gian về timeline chính theo điểm bắt đầu, thời gian cắt và tốc độ `playbackSpeed`. File tạm được xóa khi xong.
- Với **Thuyết minh**, nhận diện từ tệp giọng đang dùng, đưa các câu vào vị trí `voiceoverOffset`.
- Hiện giới hạn **58 giây đầu mỗi nguồn trong một lần nhận diện** để tránh vượt giới hạn nhận diện file dài. Nếu lời dài hơn, chia clip/thuyết minh thành đoạn ngắn trước. Kết quả được chia thành các câu ngắn khoảng 8 từ / 44 ký tự / 3,2 giây, dựa vào dấu câu và khoảng ngắt; người dùng vẫn có thể sửa từng câu, dời mốc và **xuất SRT**.
- Mặc định **chỉ chạy nhận diện trên thiết bị** (khi recognizer cho ngôn ngữ đó hỗ trợ `supportsOnDeviceRecognition`). Nếu không hỗ trợ, ứng dụng thông báo chứ không tự gửi âm thanh. Bật **Cho phép dịch vụ Speech của Apple** là hành động đồng ý riêng biệt; khi bật, iOS có thể sử dụng mạng/dịch vụ Apple để nhận diện audio.
- **Thay toàn bộ phụ đề hiện có** là tùy chọn; mặc định app thêm các câu mới vào dự án và giữ câu có sẵn. Hãy xem và chỉnh lại độ chính xác trước khi xuất.

### Subtitle styling
- 4 preset **Cổ điển**, **Tối giản**, **Vàng nổi bật**, **Tương phản**.
- Kích cỡ chữ 65–160%, độ mờ nền 0–95%, màu chữ HEX, bóng chữ bật/tắt. Giao diện preview và Core Animation export nhận cùng thông số.
- Phụ đề vẫn kéo được vào các vị trí trên/dưới/trái/phải bằng tọa độ X/Y trong tab Phụ đề.
- Các thông số phụ đề được lưu trong project JSON, tương thích với dự án 2.8–3.4 bằng giá trị mặc định khi không có `subtitleAppearance`.

### Cách kiểm tra
1. Thêm video 10–30 giây có giọng nói rõ hoặc thu một bản thuyết minh.
2. Chọn đúng clip video rồi vào **Phụ đề**, chọn nguồn và ngôn ngữ, bấm **Nhận diện và tạo phụ đề**.
3. Nếu máy không hỗ trợ nhận diện offline cho ngôn ngữ đó, cân nhắc chủ động bật quyền dịch vụ Apple và thử lại khi kết nối mạng.
4. Đọc lại từng câu, sửa từ sai hoặc chỉnh mốc. Chọn preset và căn phụ đề theo khung.
5. Bấm **Tạo SRT** để xuất tệp hoặc **Xem thử toàn bộ · 720p** để kiểm tra trên MP4, rồi xuất 1080p.

### Giới hạn
- Kết quả Apple Speech có thể nhận sai từ riêng, giọng địa phương, lời trong bài hát và nhiều người nói chồng nhau. Không tự xác nhận chính xác 100%.
- Bản v3.5 là Auto Captions theo cụm từ, **chưa có karaoke animation theo từng từ**, dịch phụ đề đa ngôn ngữ hay khử giọng trước khi nhận diện.
- Build bằng GitHub Actions chỉ xác nhận biên dịch; chưa được thử trên iPhone 12 Pro Max thực tế. File IPA chưa được Apple ký.


## ViePN Smart Video v3.6.0 – Long-form Auto Captions + Karaoke per Word

### Nhận diện lời nói dài hơn
- Tab **Phụ đề → Auto Captions** có tùy chọn **Nhận diện toàn bộ (tối đa 10 phút)** (bật mặc định). Nếu tắt, chỉ quét 52 giây đầu.
- Nhạc/thuyết minh hoặc video nguồn được chia thành các file M4A **52 giây** rồi nhận diện lần lượt với Apple Speech. Từng M4A tạm được xóa sau khi nhận diện; không ghi đè media gốc.
- Hỗ trợ **Clip video đang chọn** và **Thuyết minh**. Với video, giữ mốc thời gian theo điểm trim, speed và vị trí trên timeline. Với thuyết minh, dựa vào voiceoverOffset. Mọi câu và từ đều được chuyển sang **thời gian tuyệt đối trên timeline**.
- Nguyên tắc quyền riêng tư không thay đổi: **mặc định xử lý offline**; nếu thiết bị không hỗ trợ offline, app báo lỗi, không tự động gửi audio ra mạng. Muốn dùng dịch vụ Apple cần tự bật lựa chọn cho phép (âm thanh có thể được gửi lên máy chủ Apple). Giới hạn 10 phút là **tổng lượng audio nguồn tối đa trong một lượt**, không phải bảo đảm dịch vụ Apple sẽ nhận diện thành công mọi đoạn.
- Phân tích nhiều đoạn có thể mất thời gian. Các đoạn cắt ở ranh giới 52 giây đôi khi làm mất/nhận sai một từ; người dùng cần sửa và nghe lại.

### Karaoke word timing trong preview & MP4
- Mỗi SubtitleCue có thể chứa words: [SubtitleWord], mỗi từ có start, end, text riêng. Dự án cũ không có words vẫn mở như bình thường; trường này là tùy chọn khi decode.
- Tab **Phụ đề → Kiểu phụ đề** bật **Karaoke · sáng từng từ theo giọng nói**. Chọn **Sáng chữ**, **Nảy chữ** hoặc **Phát sáng**, màu chữ active dạng HEX.
- Preview thay đổi màu theo con trỏ và từ đang được đọc. Khi xuất MP4, Core Animation hiển thị chữ gốc và một lớp màu vàng/được tùy chỉnh đúng mốc từng từ; chuyển động **Pop** nảy nhẹ từ đang đọc. Nếu câu quá dài hoặc không đủ thông tin word timing, fallback về phụ đề thông thường.
- Bên dưới mỗi câu có **Chỉnh karaoke từng từ** để sửa chữ và dời mốc từng từ ±0,05 giây. Dời cả câu 0,5 giây cũng dời các mốc từ theo, tránh sai đồng bộ.
- Nếu người dùng sửa trực tiếp cả câu nhưng không cập nhật dữ liệu từng từ, app **tạm tắt karaoke của câu đó** để không hiển thị sai lời. Có thể đồng bộ lại khi số từ không thay đổi, hoặc sửa trong bảng từ.
- Xuất SRT vẫn chứa các mốc **cấp câu**, không nhúng thời gian từng từ. Các mốc từ chỉ được lưu trong dự án JSON và được burn vào MP4 khi bật Karaoke.

### Thử nghiệm đề xuất
1. Thêm clip 70–120 giây có giọng nói rõ hoặc thu giọng thuyết minh dài, chọn đúng nguồn trong Auto Captions.
2. Bật nhận diện toàn bộ, chọn tiếng Việt (offline nếu máy hỗ trợ), nhấn Nhận diện và quan sát tiến độ đoạn 1/3, 2/3...
3. Trong Kiểu phụ đề bật Karaoke → Nảy chữ → chọn HEX màu active.
4. Rà lời từng câu, mở bảng từng từ nếu cần. Xem thử timeline ở 720p rồi xuất MP4 ngắn để kiểm tra nhịp highlight.
5. Lưu, đóng và mở lại dự án, kiểm tra words được giữ và các phụ đề cũ không bị mất.

**Giới hạn**: Apple Speech không bảo đảm độ chính xác tuyệt đối, đặc biệt với giọng vùng miền, nền nhạc lớn và nhiều người nói. Cách highlight dùng Core Animation trên MP4, không phải mô hình karaoke optical flow. Build thành công là kiểm tra biên dịch; cần test trên iPhone 12 Pro Max trước khi làm dự án dài.


## ViePN Smart Video v3.7.0 – Multi-Point Keyframe Animator

Thêm **bộ keyframe nhiều điểm dành cho lớp ảnh/logo/sticker Overlay**. So với kiểu v2.9–v3.6 chỉ có vị trí đầu/cuối, v3.7 cho phép tạo tối đa **16 mốc** trên mỗi lớp ảnh và điều khiển độc lập **X, Y, scale, rotation, opacity**.

### Các tính năng
- Trong **Công cụ → Overlay**, chọn ảnh rồi bấm **Thêm tại con trỏ** để tạo mốc ngay tại vị trí đang tua. Mỗi mốc dùng tỷ lệ 0–100% của thời lượng overlay, nên khi kéo dài/rút ngắn overlay, nhịp chuyển động tự co giãn.
- Chạm vào mốc để nhảy đến thời điểm, rồi chỉnh **Vị trí ngang/dọc**, **Kích thước**, **Độ mờ**, **Góc xoay**. Các mốc giữa có thể di chuyển trên thời gian hoặc xóa; mốc đầu và cuối luôn được giữ.
- **5 hiệu ứng gốc**: Zoom điện ảnh, Trượt từ dưới, Nhịp phóng, Xoay 360°, Xuất hiện/Tan. Các preset tạo ra mốc thật, có thể chỉnh thủ công sau đó.
- **Gia tốc giữa mốc**: Tuyến tính, Tăng tốc, Giảm tốc hoặc Mượt hai đầu. Chọn trên Overlay Studio.
- Hiển thị **hình thoi màu cam** trên timeline khi chọn lớp ảnh Overlay; chạm một hình thoi để tua chính xác đến mốc đó.
- Kéo ảnh trực tiếp trên preview để **dịch toàn bộ đường chuyển động**, không xóa keyframe; preview tính nội suy X/Y/zoom/alpha/góc xoay theo con trỏ.
- Khi xuất MP4, hệ thống sử dụng **CAKeyframeAnimation** với từng mốc và cùng Core Animation composition đang dùng cho VFX và phụ đề; không làm thay đổi file ảnh nguồn. PNG alpha và Chroma Key ảnh tiếp tục hoạt động.
- Dữ liệu mới lưu trong **imageOverlays[].keyframes** của JSON dự án. Các dự án v2.8–v3.6 không có mảng này vẫn mở theo đường chuyển động hai điểm cũ. Bấm **Về 2 điểm** để quay về cách dựng cũ.

### Cách thử trên iPhone
1. Nhập video 10–20 giây rồi vào **Overlay → Thêm ảnh** (logo PNG trong suốt).
2. Bấm **Zoom điện ảnh**, chọn các mốc dưới phần Keyframe Pro để tùy chỉnh zoom/alpha và xoay.
3. Kéo slider timeline để kiểm tra hoạt ảnh, hoặc tạo thêm mốc theo con trỏ. Chạm các hình thoi cam để tua đến từng mốc.
4. Bấm **Xem thử toàn bộ · 720p** và xuất MP4; so sánh chuyển động thực tế với preview.
5. Lưu dự án, mở lại, kiểm tra các mốc vẫn có thể sửa và preset không làm hỏng file gốc.

**Giới hạn:** Bộ keyframe nhiều điểm trong v3.7 **chỉ áp dụng cho Overlay ảnh**; Video PIP và chữ độc lập vẫn dùng chuyển động hai điểm. Nội suy preview có thể khác nhẹ với Core Animation của file xuất. GitHub Actions chỉ xác nhận mã biên dịch và tạo IPA; chưa đo hiệu suất render nhiều lớp trên iPhone 12 Pro Max.
