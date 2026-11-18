# Music Photo Video Studio – phân tích và kế hoạch kỹ thuật

Tính năng mới của ViePN Smart Video: biến ảnh thành video nhạc có lời karaoke, đĩa than quay, visualizer và chuyển cảnh. Viết hoàn toàn bằng Swift/SwiftUI và framework của Apple, **không** React Native, Flutter hay WebView.

Trạng thái: **giai đoạn 1 đã làm** (editor UI + xem trước). Các giai đoạn 2–9 chưa làm; mục "Kế hoạch" bên dưới là thiết kế, không phải tính năng đã có.

## 1. Phân tích dự án hiện có

| Hạng mục | Hiện trạng |
|---|---|
| Nền tảng | iOS 16.0, Swift 5, SwiftUI, XcodeGen (`project.yml`), CI GitHub Actions trên macOS |
| Thư viện ngoài | Không có (không SPM/CocoaPods). Chỉ framework Apple |
| Kiến trúc | `Models/` (dữ liệu, toán thuần), `Services/` (AVFoundation, Core Image, Vision), `ViewModels/` (`EditorViewModel`, tách thành extension theo tính năng), `Views/` |
| Giao diện | Dark, màu nhấn cyan, panel theo tab công cụ trong `EditorView` |
| Thời gian | Timeline chính theo giây `Double`; một `Timer` 80 ms trong `EditorView` cho xem nhanh |
| Âm thanh | `AVAudioPlayer` (`LiveAudioPreview`), `AVMutableComposition`/`AVAudioMix` khi xuất. **Chưa có `AVAudioEngine`**, `Accelerate` hay Metal |
| Có thể tái dùng | `AudioWaveformSampler` (đọc PCM), `MusicBeatAnalyzer`, `AutoCaptionSpeech` (Speech, có mốc từng từ), `KaraokeSubtitleRenderer` (CALayer), `SubtitleCue`/`SubtitleWord`, `AudioDocumentPicker`, `PhotoExporter`/`MediaStorage` |
| Xung đột tên | `TimelineClip` đã có ở `Models/TimelineClipBlock.swift`; `TimelineView` trùng SwiftUI |

### Cách tránh xung đột

Toàn bộ module nằm trong namespace `enum MusicVideoStudio` (`SmartVideo/MusicVideoStudio/`). Tên như `TimelineClip`, `PhotoLayer`, `TextLayer` là kiểu lồng nhau nên không đụng code cũ. View timeline đặt tên `TimelineTracksView` (file `TimelineView.swift`) để không trùng `SwiftUI.TimelineView`. Module chỉ chạm app cũ ở **một điểm**: thêm tab "Music Video" trong `EditorTool` để mở màn hình.

## 2. Kiến trúc module

```text
SmartVideo/MusicVideoStudio/
├─ Core/        MusicVideoStudio, ProjectTime, VideoProject, TimelineEngine, TimelineScale,
│               UndoHistory, TransportState, PlaybackEngine, ProjectManager, MusicVideoEditorModel
├─ Models/      Layer (TrackKind, LayerTransform, LayerCore), PhotoLayer, TextLayer,
│               TimelineClipBlock (kiểu `MusicVideoStudio.TimelineClip`; file đổi tên vì Xcode không cho
│               hai file cùng tên trong một target)
├─ Views/       MusicVideoEditorView, VideoPreviewView, PlaybackControlsView, TimelineRulerView,
│               TimelineView (TimelineTracksView), LayerToolbarView, PropertiesInspectorView
└─ Photo/       PhotoImageCache, PhotoTrackView (ClipBlockView, PhotoThumbnailView)
```

Các thư mục `Audio/`, `Lyrics/`, `Vinyl/`, `Visualizer/`, `Export/` và các file `AudioLayer`, `LyricsLayer`, `VinylLayer`, `VisualizerLayer`, `EffectLayer`, `AudioEngine`, `ExportEngine` **chưa được tạo**: mỗi cái sẽ được thêm ở giai đoạn của nó, để không có file rỗng hay nút giả.

### Quyết định thiết kế chính

- **Một mô hình thời gian** `ProjectTime`: số nguyên tick 1/60000 s, quy đổi chính xác sang `CMTime`. Một khung hình ở 24, 25, 30, 60 fps đều là số tick nguyên nên không bao giờ lệch dần.
- **Một đồng hồ chủ** `PlaybackEngine`: một `CADisplayLink` duy nhất đẩy `TransportState` (hàm thuần, test được). Không có `Timer` riêng cho từng track. Ảnh, chữ và về sau âm thanh, đĩa than, lời, visualizer đều suy ra hình từ `frameTime` của đồng hồ này.
- **Xem trước = xuất**: `TimelineEngine.renderItems(in:at:)` là hàm thuần dùng chung. Cả xem trước và bộ xuất (giai đoạn 9) gọi cùng hàm, cùng quy tắc làm tròn về khung hình, cùng thứ tự z.
- **Project là value type** (`VideoProject`, Codable, chịu được file thiếu trường) nên hoàn tác là hoán đổi snapshot và lưu là encode JSON.
- **Ảnh gốc được giữ nguyên byte** trong `Documents/MusicVideoProjects/<id>/media/`; xem trước dùng ImageIO giải mã **thu nhỏ**, ngoài luồng chính, có cache giới hạn bộ nhớ.
- **Giảm cập nhật SwiftUI**: `MusicVideoEditorModel` (cấu trúc) và `PlaybackEngine` (thời gian) tách riêng. Chỉ preview, playhead và đồng hồ quan sát engine; inspector, toolbar và các clip không vẽ lại mỗi khung hình.

## 3. Giai đoạn 1 – đã làm

Có thật và dùng được:

- Giao diện editor tối: thanh trên, canvas xem trước, thanh phát, thước thời gian, timeline nhiều lane, toolbar dưới, inspector. Dọc và ngang, vùng an toàn, iPad/ngang đặt inspector bên cạnh.
- **Xem trước có đồng hồ chủ**: phát/tạm dừng, tua, lùi/tiến từng khung hình, về đầu/cuối, lặp, tua bằng kéo thước hoặc thanh trượt, mã thời gian theo khung hình.
- **Ảnh**: nhập nhiều ảnh từ thư viện (tối đa 100 một lần), xếp nối tiếp 3 giây mỗi ảnh, lấp đầy hoặc vừa khung, giữ đúng kích thước sau xoay EXIF, prefetch ảnh sắp xuất hiện.
- **Chữ**: lớp chữ có nội dung, cỡ, độ đậm, căn lề, màu, đổ bóng.
- **Mỗi lớp** có: id, bắt đầu, kết thúc/thời lượng, vị trí, tỉ lệ, góc xoay, độ mờ đục, hiển thị, khóa, z-index. Chỉnh bằng inspector, áp dụng cho nhiều lớp đã chọn; lớp bị khóa không bị sửa.
- **Timeline**: thước thích ứng mức zoom, zoom bằng thanh trượt hoặc chụm, nút "Vừa", playhead tự cuộn theo khi phát, chọn clip, chọn nhiều, menu ngữ cảnh (nhân bản, khóa, ẩn, đặt lại, xóa).
- Tỉ lệ khung 9:16, 16:9, 1:1, 4:5, 3:4; 24/25/30/60 fps.
- Hoàn tác/làm lại, tự lưu sau 0,7 giây, lưu tay, nhiều dự án (mới, mở lại).

### Có chủ đích **chưa** có ở giai đoạn 1

Kéo/cắt/tách clip trên timeline và snap (giai đoạn 2), nhạc và waveform (3), đĩa than (4), lời karaoke (5), visualizer (6), thao tác trực tiếp trên canvas bằng kéo/chụm/xoay và đường gióng (7), hiệu ứng và chuyển cảnh (8), **xuất video** (9). Phần mở rộng vì thế không có nút trong giao diện.

## 4. Kế hoạch các giai đoạn tiếp theo

| GĐ | Nội dung | Thiết kế chính |
|---|---|---|
| 2 | Quản lý ảnh + timeline | Kéo/trim/tách/nhân bản/đổi thời lượng clip, snap vào playhead/nhịp, sắp xếp lại, Ken Burns, chuyển cảnh ảnh |
| 3 | Âm thanh + waveform | `AVAudioEngine` + `AVAudioPlayerNode` phát từ **thời điểm của đồng hồ chủ**; đồng hồ chuyển sang bám `sampleTime` của engine khi có nhạc. Waveform đọc PCM thật bằng `AVAssetReader`, rút gọn bằng `Accelerate` (`vDSP`), cache theo (tệp, độ phân giải). Fade, lặp, offset, cắt, âm lượng. Xử lý `AVAudioSession` interruption/route change |
| 4 | Đĩa than | Góc quay = hàm của thời gian (`angle = f(frameTime)`), không animation lặp, nên tua/tạm dừng không lệch. Bìa ở giữa, bóng, glow, phản chiếu |
| 5 | Lời karaoke | Mô hình `Lyrics → Line → Word(start,end)`; `LRCParser`, `SRTParser`; bộ đồng bộ độc lập nhà cung cấp phiên âm (giao diện `LyricsAligner`). Highlight theo từ, fill, glow, scale, fade, typewriter đều là hàm của thời gian. Trình chỉnh mốc dòng/từ, dịch toàn bộ, tính lại sau khi cắt nhạc. Nhận dạng giọng hát cần dịch vụ phiên âm + forced alignment: **Speech của Apple không đủ chính xác cho giọng hát** |
| 6 | Visualizer | Phân tích âm thanh **offline** thành bảng phổ theo khung hình (FFT bằng `vDSP`), lưu cùng dự án. Xem trước và xuất đọc cùng bảng, nên xuất không phụ thuộc đầu vào âm thanh trực tiếp. Vẽ bằng Metal khi cần |
| 7 | Chỉnh biến đổi trên canvas | Kéo, chụm, xoay trực tiếp; đường gióng giữa/vùng an toàn; khóa vị trí |
| 8 | Hiệu ứng + chuyển cảnh | Core Image/Metal, tham số hóa theo thời gian |
| 9 | Xuất | `AVAssetWriter` + bộ vẽ khung hình dùng chung `TimelineEngine`; 720p–4K, 24/30/60 fps, H.264/HEVC, AAC, MP4/MOV, 5 tỉ lệ; tiến độ, hủy, lưu vào Ảnh |

Mỗi giai đoạn chỉ được coi là xong khi: build CI qua, test của giai đoạn qua, và có QA trên iPhone thật cho đồng bộ phát, bộ nhớ và nhiệt.

## 5. Rủi ro và điểm chưa kiểm chứng

- Giai đoạn 1 **chưa chạy trên iPhone thật**. CI xác nhận biên dịch, test logic thuần (`scripts/music-video-core-tests.swift`) và XCTest trên Simulator (`MusicVideoStudioTests`: file thật, display link thật, render SwiftUI thật của preview). Chưa đo hiệu năng và bộ nhớ trên máy.
- Thước thời gian vẽ bằng một `Canvas` rộng bằng cả dự án: ổn với dự án vài phút; dự án rất dài ở mức zoom cao nên chuyển sang vẽ theo vùng nhìn thấy.
- Đồng hồ chủ hiện theo thời gian thực của display link. Khi có âm thanh (giai đoạn 3) nó phải bám đồng hồ của audio engine để không trôi so với tiếng.
