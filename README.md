# ViePN Smart Video – trình dựng video iOS (SwiftUI)

Mã nguồn ứng dụng **render video ngay trên iPhone 12 Pro Max**, không gửi clip lên server.

## Tính năng (bản dựng UI mới)

## ViePN Smart Video v5.5.2 – Fix chữ Sau người trong video thật

- **Sửa mốc thời gian video đã cắt:** trước đây `AVVideoComposition` có thể dùng thời gian gốc khi xuất một phần video và dùng thời gian tương đối khi xử lý đoạn MOV trung gian. Kết quả `projectSecond` bị chệch khiến lớp chữ **Sau người** không có frame nào nằm trong khoảng thời gian hiệu lực. Bản này cắt video và audio vào `AVMutableComposition` **bắt đầu từ 0 giây** trước khi chạy Vision/Core Image. Chuyển đổi thành timeline project bằng `clipStart + trimmedCompositionSecond / playbackSpeed` rõ ràng, cả với video đã cắt ở mốc 13 giây, tốc độ 0,5×/2× và nhiều clip.
- **Giữ âm thanh & chiều xoay:** track video trung gian vẫn giữ `preferredTransform`, audio được copy với offset tương đối để đồng bộ, và MOV nguồn được đưa lại vào pipeline cũ (chuyển cảnh, PIP, âm thanh, MP4).
- **Tự mở rộng chữ nằm sau người:** thêm `behindVisibilityAssist` (mặc định bật, tắt được trong tab Chữ). Người ở chính giữa có thể che toàn bộ chữ kích thước nhỏ; tính năng phóng chữ vừa đủ để nét kéo sang hai phía và vẫn được người che đúng nơi giao nhau, không đặt cả chữ lên người. Kích thước chữ chính xác khi xuất phụ thuộc độ lớn nhân vật; có thể tắt nếu muốn giữ thiết kế gốc.
- **Kiểm thử phòng ngừa:** thời gian nguồn chuẩn hóa, hiệu ứng tốc độ, khoảng thời gian giữa title và clip, và dữ liệu dự án từ các bản cũ; iOS Simulator kiểm tra ảnh chữ trong cả trạng thái người che một phần và không có người. Bộ kiểm tra MP4 H.264 cuối vẫn cần iPhone thật (trình mã hóa VideoToolbox trên Simulator trả lỗi `-12900`).
- Version **5.5.2 – Build 42**, bundle ID `com.nguyendp911.smartvideo` không thay đổi; IPA chưa ký như trước.

## ViePN Smart Video v5.5.1 – Hotfix Invisible Exported Text

- **Sửa mất chữ khi xuất MP4**: khôi phục `CATextLayer` đã hoạt động ở bản trước cho lớp chữ màu đơn và dựng sẵn bitmap RGBA chứa đúng nét chữ cho gradient/ảnh/video trong chữ. Không đưa `CALayer.mask` lồng nhau hoặc `sourceIn` transparency group chưa được rasterize vào quá trình xuất nữa.
- **Sửa trường hợp chữ sau người biến mất**: `UIGraphicsImageRenderer` trên iPhone mặc định render ở 2x/3x, khiến `CIImage` crop theo kích thước frame 1x bỏ lỡ toàn bộ chữ. Ép rasterizer sử dụng `scale = 1` khớp tọa độ frame video và mặt nạ Vision.
- **Ảnh/video chữ bị thiếu**: fallback sang màu chữ đã chọn thay vì lớp trong suốt.
- **Kiểm thử ảnh thực tế**: iOS Simulator XCTest xác minh nét chữ solid/gradient/image/video có pixel màu và alpha, kiểm tra lớp chữ trước người và CoreImage đã ghép chữ sau người. Test tạo/xuất MP4 H.264 được dành cho thiết bị thật vì trình mã hóa Simulator trả lỗi `-12900` trên môi trường CI này. Build thành công không thay thế kiểm thử render trên iPhone.
- Version **5.5.1 – Build 41**, bundle `com.nguyendp911.smartvideo` giữ nguyên; IPA phát hành từ GitHub Actions vẫn chưa ký Apple.

## ViePN Smart Video v5.5.0 – Text Layer Pro

### Chữ trước/sau người, ảnh/video nằm ngay trong nét chữ, preset điện ảnh

- **Trước chủ thể / Sau người:** đặt `depthMode` độc lập cho từng lớp chữ. Chế độ **Sau người** dùng `VNGeneratePersonSegmentationRequest` tạo matte Vision và ghép chữ **ở giữa background và người** trên từng khung video được xử lý hoặc khung ảnh được xuất; không dựa vào thao tác chỉ thay đổi z-index của một lớp chữ. Không có segmentation cho các loại chủ thể không phải người trong bản này.
- **Image In Text / Video In Text:** văn bản chính là mask alpha có vùng trong suốt ngoài nét chữ. Ảnh/video nằm bên trong từng ký tự, hỗ trợ `Fit / Fill`, zoom nội dung 0.5–4, dịch X/Y; không tạo một ô ảnh hình chữ nhật phía sau. Mỗi lớp có thể dùng màu đơn hoặc gradient.
- **Video Fill offline:** tránh phụ thuộc vào `AVPlayerLayer` không đồng bộ với AVVideoComposition khi xuất MP4; giải mã filmstrip thật từ video: tối đa 32 khung ở 8 fps trong 4 giây đầu, lặp theo chu kỳ ngắn. Chế độ xem nhanh hiển thị ảnh đại diện; xem thử **MP4 720p** để đánh giá chuyển động thật.
- **Trước/sau người trong MP4:** khi title ở sau người, video gốc được chép qua MOV trung gian để ghép chữ + Vision theo từng frame, rồi đưa vào pipeline chuyển cảnh/overlay cũ; với ảnh tĩnh Vision chỉ chạy một lần, mặt nạ được biến đổi theo pan/zoom/lật ảnh nhằm tiết kiệm năng lượng.
- **Hiệu ứng typography:** hỗ trợ viền nét chữ, bóng đổ/glow, độ dày giả 3D, hiệu ứng nhịp thở Pulse, vị trí và keyframe chuyển động cũ, nhiều lớp chữ chồng nhau.
- **8 preset**: Title Behind Person, Big Bold Intro, Image In Text, Video In Text, Product Behind Person, Cinematic Name, Laptop Sale, Travel Text. Các preset đều chỉnh được lại, không phá các source file.
- **AI gợi ý vị trí chữ** chạy bằng Vision trực tiếp trên iPhone: nhận diện khuôn mặt trong ảnh hoặc một khung video, đề xuất vùng ít che mặt. Không gửi ảnh hay video lên cloud.
- **Lưu/mở dự án cũ:** mới thêm các khóa Codable có mặc định tương thích; ảnh/video làm nội dung glyph được copy vào thư mục Media ứng dụng và đường dẫn được khôi phục đúng khi mở lại project. Không thay đổi bundle ID.
- **Giới hạn cần biết:** Vision chế độ sau chủ thể hiện nhận diện **người**, chưa hỗ trợ vật thể bất kỳ và có thể khó với tóc mờ hoặc nền phức tạp. Bộ xem nhanh dùng chữ trước người như hướng dẫn vị trí; **Xem thử 720p** và MP4 xuất cuối là kết quả phân lớp thực tế. Video trong chữ là filmstrip giới hạn 4 giây, 8fps và lặp, không phải playback 30fps của mọi video dài. Tên/chữ trên video letterbox hoặc chuyển cảnh phức tạp có thể lệch vị trí vì matte chạy trong tọa độ clip nguồn. Hiệu ứng blur nền, blend mode và 3D thực chưa có trong bản này. Cần kiểm thử trên iPhone 12 Pro Max.
- Phiên bản **5.5.0 (build 40)**, iOS 16+, bundle `com.nguyendp911.smartvideo`, build unsigned IPA bằng GitHub Actions.

## ViePN Smart Video v5.4.0 – Multi-Music Regions

### Nhiều đoạn nhạc độc lập trên timeline

- **Multi-Music Studio** trong tab **Âm thanh**: chuyển rõ giữa **Một nhạc nền** (hành vi 5.3) và **Nhiều đoạn nhạc**; dữ liệu cả hai chế độ vẫn được lưu, chỉ một chế độ phát trong bản phối để không bị phát đúp.
- Tối đa **12 đoạn nhạc độc lập** (ngoài 12 FX): nhập MP3/M4A/WAV riêng từ ứng dụng Tệp, hoặc **Từ nhạc nền** đang chọn. Chuyển đổi nhạc nền một bài thành vùng nhạc không làm thay đổi file gốc, giữ cắt nguồn và keyframe nhưng **không** tái tạo chế độ lặp nhạc tự động trong các vùng.
- **Tách nhạc tại con trỏ**, **Sao chép → Dán**, **Nhân bản**, **Xóa**; mỗi vùng có `start`, `sourceStart`, `duration`, `volume`, `fadeIn/fadeOut`, `muted` và tối đa **16 keyframe âm lượng** riêng. Split chia keyframe để giữ nguyên mức âm ngay tại điểm tách, không tự tạo fade ngoài ý muốn.
- Mỗi vùng nhạc hiện **waveform màu xanh lá trong timeline mở rộng**, kéo trực tiếp để dời mốc phát; di chuyển keyframe trên track (thời điểm và độ lớn). Bộ waveform cắt nguồn trong bảng chỉnh cũng hỗ trợ tua/zoom; vùng nhạc gốc không bị ghi đè.
- **Xuất MP4**, **Xem thử 720p**, **Nghe bản phối** và **xem nhanh** đều dùng các vùng âm thanh này khi ở chế độ nhiều đoạn. Các vùng có thể chồng lên nhau, trộn độc lập; nhạc tự hạ âm lượng khi thuyết minh có tiếng, qua các ramp AVAudioMix.
- **Undo/Redo** cho chuyển chế độ và các thao tác vùng nhạc; save/load thêm `musicRegions` và `musicRegionMode` với mặc định tương thích dự án cũ. Không tự phát lại bài nhạc nền cũ khi người dùng xóa vùng cuối và vẫn đang ở chế độ nhiều đoạn.
- **Giới hạn**: chưa có chế độ ripple dịch chuyển video/phụ đề sau khi tách nhạc. Các vùng nhạc không tự lặp theo từng vùng; bật **Một nhạc nền** để giữ loop nhạc toàn dự án. Tổng 12 nhạc + 12 FX có thể ngốn tài nguyên ở iPhone cũ; thực tế cần kiểm tra render và âm thanh trên thiết bị trước khi phát hành rộng.
- Phiên bản **5.4.0 (build 39)**, bundle ID `com.nguyendp911.smartvideo` không thay đổi, IPA cần ký riêng.

## ViePN Smart Video v5.3.0 – Music & Voice Automation Pro

- **Kéo nhạc nền và thuyết minh trên timeline**: các track âm nhạc / giọng đọc kéo ngang trực tiếp, có hút vào nhịp nếu bật nam châm. Đã tách riêng **mốc cắt bên trong MP3** (`musicStartSeconds`) và **mốc nhạc phát trên video** (`musicTimelineOffset`), để dời track không làm đổi đoạn nguồn.
- **Keyframe âm lượng cho cả nhạc nền và giọng đọc**: trong tab Âm thanh, thêm tối đa 16 mốc/track tại vị trí con trỏ, chọn chấm màu cam, chỉnh mức 0–100% bằng slider hoặc kéo điểm trực tiếp trên timeline. Có xóa từng mốc hoặc xóa toàn bộ; Undo/Redo cho di chuyển và thay đổi mốc.
- **Bản MP4 thật, Preview 720p, bản nghe phối âm và Live Preview** dùng chung `ProjectAudioTrackMath` cho mốc phát nhạc, đoạn nguồn, loop, fade, ducking và keyframe. Các ramp được chia thành đoạn không chồng lấn, tránh fade hoặc duck ghi đè lên keyframe.
- **Nhạc xuất hiện muộn**: trước mốc nhạc không có âm thanh; sau đó nhạc phát từ phần nguồn đã cắt và lặp nếu bật tùy chọn. Giọng đọc theo mốc riêng; vùng nhạc trùng với thuyết minh giảm âm lượng có ramp 150ms/200ms.
- **Dự án cũ tương thích**: JSON không có `musicTimelineOffset` mặc định bắt đầu nhạc tại 0 giây; mảng keyframe nhạc/giọng vắng mặt mặc định rỗng = âm lượng giữ nguyên. Giữ nguồn và bundle ID hiện tại.
- **Giới hạn**: một track nhạc nền toàn dự án và một track thuyết minh (chưa hỗ trợ nhiều đoạn nhạc độc lập trên timeline). Mỗi FX vẫn là vùng độc lập như bản 5.2. Kéo/điểm keyframe cần thử trên thiết bị thật; bộ nghe nhanh có thể có độ trễ nhỏ ở điểm lặp MP3. Không thay đổi app ký bằng chứng chỉ.
- v**5.3.0 (build 38)**, iOS 16+, bundle ID `com.nguyendp911.smartvideo`.

## ViePN Smart Video v5.2.0 – Unified Multi-Track Timeline

### Video, nhạc nền, giọng đọc và FX chung một trục thời gian
- **Mở rộng timeline** ngay dưới video cố định: chung một vùng cuộn ngang và chung tỷ lệ thời gian cho video, MP3, thuyết minh, và **từng** track FX (tối đa 12). Có thước thời gian và đường playhead chạy đồng bộ; chạm thước để tua.
- **Waveform thực** cho track âm thanh, lấy mẫu từ PCM theo phần đầu nguồn, giới hạn 90 giây/track để tránh giải mã tệp dài quá tốn tài nguyên. Với âm thanh dài, phần chưa lấy mẫu **không** bị tô bằng sóng âm giả.
- **Kéo ngang vùng waveform FX** để dời vị trí phát trên dự án (không cắt lại nguồn). Nút **nam châm** trên thước thời gian cho phép bật/tắt hút vào mốc nhịp từ Beat Sync. Kéo track bị chặn ở đầu/cuối tổng thời lượng.
- **Kéo điểm keyframe trực tiếp trên dòng FX**: ngang đổi mốc thời gian, dọc tăng/giảm gain. Có thể mở bảng Âm FX để tinh chỉnh số chính xác như trước. Các ramp này xuất ra MP4 và nghe trong Quick Preview đã có từ v5.1.
- Video, nhạc, giọng và FX cuộn ngang cùng nhau; danh sách âm thanh cuộn dọc riêng khi nhiều track để video preview **không bị đẩy khỏi màn hình**. Thu gọn timeline trở về giao diện gọn v4.7.
- **Hoàn tác/Làm lại có cả SoundFX**, gồm kéo track, kéo keyframe, thay đổi các slider FX, tắt tiếng, nhập/nhân bản/xóa FX, chia FX và cắt bằng waveform. Một cử chỉ kéo được ghi nhận thành một bước Undo; không khôi phục dữ liệu giữa hai dự án khác nhau.
- **Giới hạn:** phiên bản 5.2 mới cho **FX** kéo trực tiếp (nhạc nền vẫn ở mốc 0, giọng đọc vẫn điều chỉnh offset từ tab Âm thanh). Waveform track dài chỉ vẽ phần nguồn đã phân tích, không tự quét toàn bộ tệp dài. Phần nhạc lặp được vẽ dưới dạng vùng phát và mẫu waveform, chưa vẽ chính xác từng chu kỳ. Việc căn hàng thời gian chính xác khi kéo cần kiểm thử cảm ứng trên iPhone thật.
- v**5.2.0 (build 37)**, iOS 16+; bundle ID `com.nguyendp911.smartvideo` không đổi.

## ViePN Smart Video v5.1.0 – Waveform Editor & SFX Audio Keyframes

### Chỉnh âm thanh chính xác hơn mà không cần xuất thử
- **Waveform tương tác** trong tab **Âm thanh** (nhạc nền) và **Âm FX** (track đang chọn): hiển thị đỉnh tín hiệu thật từ file PCM đã giải mã, có 2 vạch chỉnh cắt **đầu nguồn** (xanh) và **cuối nguồn** (cam), chạm/kéo để chỉnh thời gian vào/ra. Thao tác không sửa file gốc.
- Các phím điều khiển **zoom**, **dịch trái/phải** và **Tới đoạn cắt** cho phép xem từng cửa sổ của tệp dài. Mỗi lần chỉ phân tích tối đa 90 giây với 112 cột; **không** giả định waveform của 90 giây đầu đại diện cho mọi phần nhạc.
- Nhạc nền cập nhật **musicStartSeconds / musicHighlightDuration**, kết hợp với tự lặp, giới hạn highlight, fade và tính năng render sẵn có. SFX cập nhật **sourceStart + duration** ngay khi kéo điểm cắt.
- **Tách FX tại con trỏ**: hai đoạn phát liên tục từ cùng file, không biến đổi âm gốc; các keyframe được chia lại và giữ nguyên giá trị đúng tại mốc tách, tránh nhảy âm lượng.
- **16 keyframe âm lượng trên mỗi track FX**: đặt tại con trỏ timeline, xem đường âm lượng trên biểu đồ, chọn điểm màu cam và kéo slider 0–100%, xóa từng điểm hoặc xóa toàn bộ. Từ điểm này tới điểm tiếp theo nội suy tuyến tính.
- **Nghe thử và xuất MP4 đều có hiệu lực**: LiveAudioPreview và SoundEffectsMixer đọc các keyframe cùng fade-in/fade-out, mute và master volume. AVAudioMix được dựng thành các đoạn ramp không chồng nhau; chỉ lấy mẫu 50ms ở vùng fade, giữ mức tài nguyên ổn định với clip dài.
- Dự án cũ không có `volumeKeyframes` vẫn mở bình thường (mặc định không automation). Tối đa 12 track FX như trước, không thay đổi bundle ID.
- **Giới hạn**: waveform là cửa sổ **nguồn** có thể kéo/chỉnh cắt trong panel, không phải DAW đa track toàn màn hình; việc kéo điểm cắt SFX không tự ripple các lớp khác. Keyframe hiện áp dụng cho **FX**, không phải âm lượng nhạc nền hoặc tiếng gốc video. Preview nhanh vẫn chưa tái hiện chính xác các chuyển cảnh hình và âm thanh nhiều clip; dùng **Xem thử 720p** để kiểm tra bản kết xuất hoàn chỉnh.
- Phiên bản **5.1.0 (build 36)**, iOS 16+ và bundle ID `com.nguyendp911.smartvideo`.

## ViePN Smart Video v5.0.0 – Clip Audio Studio

### Âm thanh độc lập cho từng đoạn video
- Chọn một clip **video** trên timeline, mở tab **Đoạn → Âm thanh gốc của đoạn**: điều chỉnh volume 0–100%, các mức nhanh 0/25/50/100%, bật/tắt tiếng riêng, **fade-in** và **fade-out** riêng 0–3 giây, **Đặt lại**. Clip ảnh không cần audio source.
- Điều khiển áp dụng **thực sự khi xuất MP4**: AVAudioMix dùng 2 audio track xen kẽ, kết hợp âm lượng, fade từng clip và crossfade ở đầu/cuối clip khi có chuyển cảnh. Các ramp được gộp thành các đoạn thời gian không chồng lấn, tránh một ramp ghi đè ramp khác.
- **Preview tức thời**: AVPlayer.volume cập nhật theo tiến độ clip gốc, cả clip video cắt/tăng tốc và Speed Curve. Nút giữ tiếng gốc toàn dự án vẫn có ưu tiên cao hơn.
- Mỗi thao tác đặt nhanh/mute/reset có undo; kéo slider tạo một checkpoint ở đầu thao tác. Split, duplicate, Speed Curve và project save tiếp tục giữ thuộc tính âm thanh theo từng clip.
- Mở project cũ vẫn phát âm lượng **100%, không tắt tiếng, không fade** do các trường mới có giá trị Codable mặc định; không sửa file nguồn.
- Envelope có toán học độc lập, kiểm thử Swift trước khi build. Chỉ lấy mẫu trong vùng fade (mỗi 50ms) thay vì tạo hàng nghìn nút trên clip nhiều giờ.
- **Giới hạn:** MP4 xuất sử dụng envelope gần đúng tuyến tính 50ms tại vùng 2 fade chồng lấn; preview nhanh là cut-style, không tái tạo chính xác crossfade audio giữa 2 clip. Dùng **Xem thử 720p** để đối chiếu audio mix cuối. Hiệu ứng tiếng gốc, nhạc nền, FX và giọng thuyết minh vẫn cần QA trên thiết bị thực.
- Phiên bản **5.0.0 (build 35)**, iOS 16+, bundle ID không đổi `com.nguyendp911.smartvideo`.

## ViePN Smart Video v4.9.0 – Live Audio Monitor

- **Nghe thử nhạc nền, thuyết minh và âm thanh FX** khi bấm Play trong khu vực preview cố định; không cần xuất toàn bộ MP4 chỉ để nghe thời điểm vào tiếng.
- Hỗ trợ phát nhạc từ mốc đã chọn, giới hạn highlight, tùy chọn lặp, fade đầu/cuối, giảm nhạc còn khoảng 25% trong lúc có thuyết minh và chỉnh âm lượng trong lúc phát. Theo dõi tối đa **12 hiệu ứng âm thanh**, giữ mỗi vị trí start/sourceStart/duration, fade và mute riêng.
- Có nút **biểu tượng loa** trên cả timeline thu gọn và đầy đủ để bật/tắt phần monitor nhạc, thuyết minh và FX. Nút này không ảnh hưởng tới nội dung MP4 cuối.
- Khi tua, tạm dừng, đổi công cụ, chuyển dự án hoặc nhấn xuất video, bộ monitor dừng đúng lúc. Trong giai đoạn tải Speed Curve, âm thanh chờ clip thực sự bắt đầu chạy thay vì phát trước.
- Tùy chọn **Giữ tiếng gốc của các clip** cũng áp dụng khi xem nhanh video.
- Các bản nhạc/audio dùng AVAudioPlayer xử lý trực tiếp trên thiết bị. Có kiểm thử Swift cho loop, mốc audio, fade và ducking trong GitHub Actions.
- **Giới hạn:** Đây là monitor tương đối cho dựng nhanh, không phải engine trộn âm chính xác đến từng sample. Đoạn nhạc có giới hạn highlight/lặp có thể có một nhịp nhỏ tại điểm nối; chưa có auto-ducking dựa trên nội dung giọng nói, và không preview đầy đủ crossfade audio giữa các clip. Để kiểm tra bản mix cuối, dùng **Xem thử 720p**.
- Phiên bản **4.9.0 (build 34)**, iOS 16+, giữ bundle ID `com.nguyendp911.smartvideo`.

## ViePN Smart Video v4.8.0 – Xem nhanh toàn timeline

### Phát preview liên tục không cần xuất file
- Trong Studio, **phần video cố định phía trên** nay có nút **Phát/Tạm dừng toàn dự án** cho **cả video lẫn ảnh tĩnh**, không còn chỉ chạy đoạn video đang chọn rồi tự dừng.
- Hết clip hoặc đến mốc bắt đầu clip tiếp theo (kể cả timeline có chuyển cảnh chồng lấn), preview tự chọn clip tiếp theo. Thời gian và phụ đề hiển thị đồng bộ theo thời gian tổng.
- Ảnh tĩnh chạy đúng thời lượng; khi đặt Ken Burns **Zoom in/out, Pan trái/phải**, khung preview phản ánh chuyển động cơ bản thay vì đứng im.
- Preview video tuân thủ cắt, tốc độ cố định và các nút **Speed Curve** hiện có. Khi chuyển sang clip cần lập AVComposition, preview đợi tạo item rồi phát tiếp. Không tải video lên server.
- Sau khi dừng ở cuối dự án, bấm Play để phát lại từ đầu. Tua, chuyển clip và nhấn Pause tắt chế độ phát tự động để người dùng giữ nguyên vị trí chỉnh.
- Timeline thu gọn có **Clip trước / Clip tiếp** bên cạnh slider. Chọn lại cùng một clip sẽ thực sự tua về đầu, không giữ khung hình cũ.
- Bộ timing độc lập có Swift regression test và được chạy trên GitHub Actions trước khi build app.

**Giới hạn quan trọng:** Đây là **preview nhanh theo thứ tự các clip**: xem liên tục clip/ảnh, màu, phụ đề và overlay đang có, **không** tái tạo toàn bộ dissolve/dip giữa clip, trộn nhiều track nhạc/voice/SFX hay VFX chuyển động như MP4 cuối cùng. Chức năng **Xem thử 720p** vẫn là cách xem bản dựng đồng bộ đầy đủ. Trên một số video Speed Curve nặng, chuyển clip có thể chậm một chút. Kiểm thử trực tiếp trên iPhone vẫn cần thiết.

Phiên bản **4.8.0 (build 33)**, bundle ID vẫn `com.nguyendp911.smartvideo`, iOS 16+.

## ViePN Smart Video v4.7.0 – Studio có preview cố định

### Khắc phục giao diện phải cuộn lên/xuống để xem video
- **Video Preview cố định ở phía trên**: vùng xem trước không nằm trong ScrollView của các công cụ; khi cuộn các bộ lọc, chỉnh màu, âm thanh, phụ đề hoặc overlay, hình/video luôn hiện ở đầu màn hình.
- **Timeline gọn mặc định**: dùng một thanh tua, các nút clip và thao tác Tách, Hoàn tác, Làm lại ngay dưới video. Bấm nút mũi tên để **mở timeline đầy đủ** khi cần kéo/sắp xếp clip, xem track FX/beat/keyframe. Bấm mũi tên hướng lên để thu lại. Trạng thái mở rộng được nhớ giữa các lần dùng.
- **Kích thước preview điều chỉnh nhanh**: nút phóng to/thu nhỏ ở góc trên bên phải màn hình video. Tùy chọn được lưu để lần mở tiếp theo giữ bố cục quen thuộc.
- **Thanh công cụ cuộn ngang tự định vị** mục đang chọn; bảng tham số cuộn dọc riêng, tự về đầu khi chuyển nhóm chức năng. Kéo bên dưới sẽ không đẩy preview lên khỏi màn hình.
- **Thanh tác vụ ghim dưới cùng** chỉ còn một hàng nút *Xem thử 720p / Xuất MP4*, giữ các trạng thái đang render và nút Lưu/Chia sẻ video khi có kết quả. Mở rộng không gian chỉnh sửa trên iPhone.
- Bố cục đo chiều cao từ màn hình thật và dành một khoảng cho bộ điều khiển bên dưới, hạn chế nút không chạm được trên iPhone cỡ nhỏ.
- Phiên bản **4.7.0 (build 32)**; iOS 16+, bundle ID `com.nguyendp911.smartvideo` không đổi.

> Bản build từ GitHub Actions là IPA chưa ký; chưa thể xem đó là kết quả kiểm thử thao tác thực tế trên iPhone 12 Pro Max. Tính năng xử lý video trên v4.6 được giữ nguyên.

## ViePN Smart Video v4.6.0 – AI Person Cutout & Face Follow

### Vision Person Cutout (cục bộ trên iPhone)
- Trong **Hiệu ứng**, chọn clip ảnh/video rồi chọn **AI tách nền người**: giữ nguyên, xóa phông, nền đen, trắng hoặc xanh.
- Video xử lý **từng frame bằng VNGeneratePersonSegmentationRequest** với mask và Core Image `CIBlendWithMask`. Bản xuất MP4 thật dùng cùng đoạn xử lý với preview. Bản ảnh tĩnh dùng Vision một lần rồi mã hóa các frame.
- Hoạt động đồng thời với Speed Curve, grade màu, overlay và transitions nhờ pipeline MOV trung gian. Các dự án cũ vẫn mở được. Không tải file lên cloud.
- Đây là **tách nền người** (không phải vật thể tùy ý). MP4 H.264 không lưu alpha nên ứng dụng chọn một nền màu hoặc nền làm mờ, không xuất nền trong suốt. Chất lượng tóc/viền có thể hạn chế tùy ánh sáng và máy; có thể render chậm.

### Face Follow (theo dõi khuôn mặt dành cho overlay ảnh)
- Trong **Overlay**, thêm một sticker/logo PNG, đặt thời gian của nó nằm trọn trên một video có người, chọn **AI bám khuôn mặt**.
- Vision lấy mẫu khung hình và dò vị trí khuôn mặt, tối đa 14 khung được chuyển thành keyframe X/Y của overlay. Keyframe vẫn chỉnh tay được và được dùng trong cả preview/render theo pipeline cũ.
- Khi có nhiều mặt, chọn mặt gần vị trí sticker trước đó. Nếu không phát hiện đủ khuôn mặt, thông báo lỗi, không tạo keyframe giả.
- Ngoài bám mặt, phiên bản này còn có **AI bám vật thể** bằng `VNTrackObjectRequest`: đặt sticker trên vật thể tại đầu đoạn và chọn **AI bám vật thể đã chọn**. Vision theo dõi vùng ảnh qua nhiều mốc và ghi keyframe cho overlay.
- Không hỗ trợ theo dõi khi vật thể bị che khuất lâu, di chuyển quá nhanh, hoặc qua nhiều clip; với clip dài, số mẫu được giới hạn. Không phải tracking 30 FPS hoặc tracking nhiều đối tượng đồng thời. Nên chỉnh lại keyframe khi cần.

### Thư viện preset cục bộ v4.6
- Mở **Preset Pro** để chọn giữa **30 công thức dựng** (trước đây có 24). Sáu công thức thêm mới: **Laptop Review, Sale Flash, Lesson Explainer, Travel Recap, Daily Story, Portrait Hero**.
- Các mẫu này thực sự áp màu, chuyển cảnh, VFX, chuyển động và title theo engine hiện tại; không chỉ là nút trang trí.
- Không phải kho template online tải từ CapCut. Dự án vẫn chưa có dịch vụ đồng bộ/tải asset bản quyền trên Internet.

Build 31 (v4.6.0). GitHub Actions kiểm tra biên dịch Simulator và IPA unsigned, nhưng không thể thay thế QA render trên iPhone 12 Pro Max.

> Các mục mô tả phiên bản cũ bên dưới được giữ làm lịch sử phát triển; đọc phần **v4.6** để biết tính năng hiện có.

## ViePN Smart Video v4.5.0 – Speed Curve

- **Speed Curve có hiệu lực thực khi xuất MP4**: trong **Hiệu ứng → Speed Curve**, chọn **Montage**, **Hero**, **Flash** hoặc **Tùy chỉnh**. Có 5 nút điều khiển tốc độ theo vị trí nguồn video từ 0% đến 100%, trong khoảng **0,25×–4×**.
- Dữ liệu curve được lưu vào project, mở project cũ vẫn hoạt động với tốc độ cố định cũ. Thời lượng và vị trí clip được tính theo cùng các lát tốc độ khi dựng video. Tách clip/Freeze Frame dùng phép ánh xạ từ thời gian timeline về đúng khung hình nguồn.
- Xem trước sử dụng AVMutableComposition được retime từ video nguồn; các chỉnh sửa slider tạo preview mới sau khoảng debounce ngắn, loại bỏ tác vụ cũ khi chọn clip khác.
- Export tạo MOV trung gian từ khoảng video đã cắt, thay đổi tốc độ theo từng lát (đồng bộ audio nguồn nếu có), sau đó áp màu Core Image, chuyển cảnh, overlay và xuất MP4 trong pipeline hiện tại. File nguồn không bị sửa.
- **Giới hạn:** Speed Curve sử dụng chia khoảng AVFoundation, không thực hiện optical flow hoặc bù khung hình AI. Audio có thể đổi cao độ; clip dài hoặc chất lượng cao cần thời gian và dung lượng trung gian nhiều hơn.
- Phiên bản ứng dụng: **4.5.0 (build 30)**. Cần kiểm tra thực tế trên iPhone 12 Pro Max; GitHub Actions chỉ kiểm tra biên dịch và đóng gói.

## ViePN Smart Video v4.4.0 – Freeze Frame & Transitions

- **Freeze Frame:** Trong **Đoạn**, chọn video, đưa con trỏ đến thời điểm cần giữ và chạm **Đóng băng 1,5s**. Ứng dụng trích khung hình gốc bằng AVFoundation, tách video tại vị trí hợp lệ và chèn một clip ảnh tĩnh có thể tăng/giảm thời lượng.
- Khung hình đóng băng giữ các thiết lập lật và màu của clip gốc; bản gốc không bị chỉnh sửa. Có thể **Hoàn tác/Làm lại**, lưu/mở project và xuất MP4 như các clip ảnh khác.
- **Chuyển cảnh mới:** **Mờ qua đen** và **Mờ qua trắng**, bên cạnh cắt thẳng/hòa tan. Hiệu ứng được tính trên timeline và được render với hai nửa chuyển cảnh độc lập, không chỉ là hiệu ứng giao diện.
- **Tốc độ thường:** bổ sung nút nhanh 0,25× / 0,5× / 1× / 2× / 4× và thanh kéo từng bước 0,05×. *Chưa phải Speed Curve tùy chỉnh hoặc optical-flow slow motion.*
- Cập nhật số phiên bản lên 4.4.0 (build 29). Build bằng GitHub Actions (Simulator và IPA unsigned); vẫn cần kiểm thử trên iPhone trước khi phát hành.

## ViePN Smart Video v4.3.0 – Manual Color Controls

- Thêm chỉnh màu **theo từng clip**: phơi sáng −2 đến +2 EV, tương phản 0,5–1,5, bão hòa 0–2 và cân bằng ấm/lạnh.
- Áp dụng lên ảnh và video trong preview lẫn MP4 xuất bằng cùng pipeline Core Image. Các giá trị được lưu trong project; dự án cũ tự nhận mức trung tính.
- Có nút **Đặt lại** cho clip và so sánh trước/sau. File nguồn không bị ghi đè.

### Đối chiếu nhóm tính năng với CapCut

ViePN Smart Video đã có dựng clip, tỷ lệ canvas, cắt/nối, chuyển cảnh hòa tan và mờ qua đen/trắng, freeze frame, tốc độ clip 0,25×–4×, preset/VFX, chỉnh màu preset, phụ đề tự nhận diện, thuyết minh/TTS, keyframe nhiều điểm cho overlay/chữ/PIP, kho media và xuất MP4. Bản 4.3 bổ sung chỉnh màu thủ công từng clip.

Các hạng mục lớn còn thiếu so với CapCut gồm optical-flow slow motion, tracking nhiều đối tượng/đi xuyên clip, đường cong tốc độ Bézier và thư viện template/asset trực tuyến. Bản 4.6 đã có Vision tách nền **người**, bám **khuôn mặt/vật thể trong một clip**, và 30 preset cục bộ; chưa tương đương các tính năng AI thương mại đầy đủ.


## ViePN Smart Video v4.2.0 – Media Inspector

- Thêm công cụ **Media Inspector** cho clip đang chọn: đọc codec, kích thước, thời lượng, FPS metadata, bitrate ước tính, thông tin audio, dung lượng và dấu hiệu HDR.
- Hiển thị cảnh báo với các trường hợp thường cần chú ý khi dựng như HDR, độ phân giải cao, FPS trên 60, nhiều track, thiếu âm thanh hoặc dung lượng lớn.
- Tạo báo cáo kỹ thuật dạng văn bản để chia sẻ khi cần chẩn đoán lỗi. Toàn bộ việc đọc metadata chạy cục bộ bằng AVFoundation; không tải media lên server.
- FPS, bitrate và HDR chỉ được báo khi metadata của tệp cung cấp đủ thông tin. Cảnh báo là gợi ý tương thích, không đảm bảo dự đoán mọi lỗi codec hoặc render.



- **Giao diện không cuộn cả màn hình:** preview phía trên luôn cố định, timeline cuộn ngang, thanh công cụ 4 thẻ Đoạn / Khung / Phụ đề / Âm thanh, nút xuất MP4 cố định bên dưới.
- **Tỷ lệ trực tiếp:** chọn video 9:16 hoặc 16:9 để thấy ngay canvas thay đổi trên preview; chế độ Vừa khung/Phủ đầy được áp dụng cả lúc render.
- **Timeline:** nhập nhiều video/ảnh bằng PhotosPicker, chỉnh điểm bắt đầu và thời lượng, đổi chỗ 1 bước qua nút trái/phải, xóa clip, preview clip đang chọn.
- **Phụ đề:** nhập TXT UTF-8 hoặc UTF-16 để tự chia từng dòng theo thời lượng video; nhập SRT để giữ timing; sửa từng câu, nắn thời gian ±0.5s; xuất SRT và chèn phụ đề trực tiếp vào video khi render.
- **Thuyết minh:** ghi âm bằng micro hoặc nhập tệp giọng đọc có sẵn, trộn giọng và tiếng gốc.
- **Cắt MP3 theo video:** chọn vị trí bắt đầu, dò phần im lặng đầu bài để đề xuất điểm vào, tự lặp khi nhạc ngắn, tự dừng ở cuối video và giảm âm lượng khi có giọng đọc, fade 1.2 giây ở cuối.
- Xuất **MP4 H.264**, 720p / 1080p, 30 FPS; lưu vào Photos hoặc chia sẻ qua ứng dụng khác.

### Giới hạn chức năng

Chưa có import LUT 3D .cube, xóa nền video bằng AI, motion tracking hoặc optical-flow slow motion. Nhận diện highlight nhạc/video dùng heuristic âm thanh và Vision, không hiểu nội dung như người dựng phim. Các clip nguồn và track phủ có những khả năng chỉnh sửa riêng; editor chưa cung cấp một timeline đa track kéo thả hoàn chỉnh như NLE desktop.

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


## ViePN Smart Video v3.8.0 – Multi-Keyframe Video PIP, Text & Curved Motion

### Lớp phủ video và chữ có keyframe nhiều điểm
- Bổ sung tối đa **16 keyframe** cho mỗi track **Video PIP** và **Chữ/Title**, điều khiển vị trí X/Y, tỷ lệ phóng to, góc xoay (tối đa ±360°) và độ mờ theo thời gian.
- **Dự án cũ** tiếp tục dùng vị trí đầu/cuối của phiên bản 3.7 và trước đó: mảng keyframes vắng mặt sẽ mặc định rỗng. Nút **Về hai điểm** cho phép trở lại điều khiển kiểu cũ.
- Bộ điều khiển **Multi-Keyframe Pro** trong tab **Video PIP** hoặc **Chữ** cho thêm mốc tại con trỏ, chọn/xóa/chỉnh mốc giữa, đổi tốc độ nội suy, và áp dụng 5 preset: Zoom điện ảnh, Trượt từ dưới, Nhịp phóng, Xoay 360°, Xuất hiện/Tan biến.
- Có hai loại đường đi: **Đường thẳng** và **Đường cong**. Đường cong dùng Catmull-Rom qua các mốc đã đặt; có thể cần kiểm tra không vượt mép canvas khi góc xoay hoặc scale lớn.
- Timeline hiển thị dải hình thoi cho Video PIP / Chữ và cho phép chạm để tua đến mốc. Preview nội suy theo đúng các mốc và khoảng thời gian; kéo lớp phủ sẽ dịch toàn bộ đường đi mà giữ tương quan các keyframe.
- **Kết xuất MP4**: Video PIP dùng AVFoundation transform/opacity ramps được chia thành nhiều đoạn ngắn để gần với đường cong và easing của preview; lớp chữ dùng Core Animation keyframe cho vị trí, scale, rotation và opacity. Đây là chuyển động thật trong file xuất, không chỉ mô phỏng trên UI.
- Mở rộng **Đường cong** cho cả **Overlay ảnh**: ảnh vẫn được xuất qua Core Animation và nội suy Catmull-Rom với các mẫu phụ nhỏ, nhằm giữ cảm giác chuyển động tương đương preview.
- Video PIP vẫn hiển thị **thumbnail tĩnh khi chỉnh sửa** để giữ thao tác nhẹ; khi bấm **Xem thử toàn bộ · 720p**, ứng dụng dựng và phát video thật có hiệu ứng của track PIP. Tiếng của video PIP hiện chưa được trộn theo track riêng.

### Cách kiểm thử nhanh
1. Thêm video nền; vào **Video PIP**, thêm video phụ.
2. Chọn **Zoom điện ảnh** hoặc **Trượt từ dưới**, thêm mốc mới tại con trỏ, chỉnh X/Y, phóng to, xoay và opacity.
3. Chuyển đường đi sang **Đường cong** và kéo timeline qua các mốc. Dải hình thoi cho phép chọn thời điểm chính xác.
4. Vào **Chữ**, thêm một tiêu đề, chọn **Xoay 360°**, giảm opacity đầu/cuối và điều chỉnh đường cong.
5. Thêm logo PNG trong **Overlay ảnh** và thử Đường cong. Bấm **Xem thử toàn bộ · 720p** để xác nhận, sau đó xuất MP4 1080p.
6. Lưu dự án rồi mở lại để kiểm tra các keyframe vẫn có đủ và dự án cũ không bị ảnh hưởng.

### Giới hạn và lưu ý
- Cả preview và bản xuất sử dụng cùng thuật toán lấy mẫu, nhưng **AVFoundation vẫn nội suy các ma trận biến đổi tuyến tính giữa từng mẫu** nên xoay góc lớn có thể khác nhẹ với preview, nhất là khi nhiều lớp PIP hoạt động đồng thời.
- Chưa có điều khiển đường cong bằng tay nắm Bézier, motion tracking tự động, xử lý alpha/chroma theo từng frame cho video hoặc bộ trộn âm riêng của video PIP.
- Mã iPhone/Simulator được kiểm tra bằng GitHub Actions; **chưa kiểm thử hiệu suất hoặc độ chính xác render trên iPhone 12 Pro Max thật**. IPA do CI tạo là file chưa ký.


## ViePN Smart Video v3.9.0 – Preset Studio PRO (24 original presets)

### Sáu bộ sưu tập / 24 công thức dựng thật
- **Cinematic**: Neo Cinema, Noir Luxe, Golden Film, Midnight Thriller.
- **Social / Reels**: Viral Pop, Neon Pulse, Flash Cut, Digital Edge.
- **Lifestyle**: Soft Morning, Sunset Diary, Clean Vlog, Rose Bloom.
- **Editorial**: Mono Editorial, Minimal Vision, Gallery White, Quiet Luxury.
- **Retro**: Analog 35, VHS Tape, Y2K Lights, Memory Film.
- **Product / Brand**: Product Hero, Luxury Reveal, Tech Launch, Food Glow.

Mỗi preset là một **công thức chỉnh sửa được** chứ không phải ảnh màu gắn nhãn: có bộ lọc Core Image dành cho ảnh tĩnh, chuyển động Ken Burns, tổ hợp VFX trên composition MP4, cường độ hiệu ứng, lựa chọn cut/dissolve, kiểu phụ đề, và preset chuyển động title. Không dùng nhạc/ảnh/logo/asset của CapCut hay từ bên thứ ba.

### Tính năng của Preset Studio
- Mở **Công cụ → Preset Pro**, tìm theo tên hoặc cảm xúc, lọc theo sáu danh mục, lưu preset yêu thích qua AppStorage trên thiết bị.
- Chạm vào một thẻ để xem công thức và bảng màu **minh họa**, bấm **Áp dụng toàn dự án** để đổi thật bộ màu **của các clip ảnh**, chuyển động ảnh, VFX, thời gian chuyển cảnh, và kiểu phụ đề. Media nguồn không bị ghi đè.
- **14 màu Core Image mới** bổ sung cho năm kiểu có sẵn: Teal & Orange, Noir Luxe, Golden Hour, Soft Pastel, Moody, Clean Studio, Forest, Analog 35, Rose Film, Desert, Midnight, Neon Pop, Editorial, Creamy. Tổng cộng 19 kiểu màu trong danh sách clip ảnh. Các bộ lọc mới chạy khi xuất MP4 và còn hiển thị trên preview ảnh (downsample để tránh chiếm RAM lớn).
- **Thêm tiêu đề** là hành động tùy chọn riêng: tạo một text overlay với keyframe chuyển động, màu chữ tương ứng preset, nội dung ban đầu “NHẬP TIÊU ĐỀ” có thể chỉnh sửa trong tab Chữ. Không tự thêm chữ/nhãn watermark vào video khi chỉ bấm Áp dụng.
- **Hoàn tác preset** trở về thiết lập ngay trước lần áp dụng gần nhất (bao gồm clips, VFX, transition, subtitle appearance). Vì nút Thêm tiêu đề là thao tác riêng, xóa tiêu đề ở tab Chữ nếu không dùng.
- Chỉnh cường độ VFX của preset đang áp dụng, bấm **Xem thử MP4 · 720p** để render thử cùng pipeline xuất cuối. Preset ID được lưu vào file JSON dự án và đọc tùy chọn để tương thích dự án cũ.
- Khi áp dụng một preset mới, màu/hiệu ứng/transition cũ trong cùng nhóm được **thay thế có chủ đích**, không tự xếp chồng vô hạn. Các track âm thanh, phụ đề đã gõ, video PIP, clip chữ có sẵn và file nguồn được giữ nguyên.

### Giới hạn quan trọng
- Bộ màu Core Image 19 look **chỉ áp dụng cho clip ảnh tĩnh**. Các clip video đang được dựng bằng AVFoundation, nên hiện preset chỉ phối VFX, chuyển cảnh và title trên **video**; đây chưa phải LUT/3D LUT color grade áp trực tiếp lên từng khung video.
- Thẻ preset hiển thị gradient bảng màu **minh họa**, không phải thumbnail chính xác của footage. Với ảnh, preview chỉnh sửa dùng bộ lọc thực; với video, xem bản MP4 720p để kiểm tra VFX.
- **Không phải bộ preset thương mại sao chép CapCut**. Đây là 24 công thức gốc được viết bằng Swift/Core Image/AVFoundation/Core Animation, không yêu cầu máy chủ hoặc mua thêm gói hiệu ứng.
- Build iPhone/Simulator qua GitHub Actions kiểm tra tương thích mã và tạo IPA chưa ký; chất lượng của từng preset trên nhiều video HDR/codec khác nhau cần thử thực tế trên iPhone.

### Kiểm tra nhanh
1. Thêm 2–3 clip ảnh + video ngắn, mở **Preset Pro**.
2. Chọn **Neo Cinema → Áp dụng toàn dự án**. Xem preview ảnh đã đổi màu; video sẽ mang VFX và chuyển cảnh theo công thức.
3. Thử **Thêm tiêu đề**, chuyển sang tab Chữ và gõ tên dự án.
4. Bấm **Xem thử MP4 · 720p**, so sánh với bản xuất. Đổi preset sang **Clean Vlog** và dùng **Hoàn tác** nếu cần.
5. Lưu dự án, mở lại và kiểm tra dữ liệu preset, màu ảnh, VFX và text overlay vẫn còn.


## ViePN Smart Video v4.0.0 — Real Video Grading & A/B Compare

### Tính năng mới
- 24 preset Preset Pro nay có thể áp bộ màu Core Image lên **cả ảnh tĩnh lẫn khung hình video**, bên cạnh VFX, chuyển cảnh và title. Không chỉ tô màu thumbnail.
- Bộ màu gồm 19 kiểu gốc. Có slider cường độ 0–100% cho từng clip trong Hiệu ứng; có slider áp đồng loạt toàn dự án trong Preset Pro.
- Chế độ **So sánh trước / sau** cho xem footage gốc hoặc sau khi áp màu. Toggle chỉ ảnh hưởng preview, không thay đổi lựa chọn màu đã lưu hoặc xuất MP4.
- Ảnh tĩnh preview bằng Core Image downsample. Video preview qua AVPlayerItem.videoComposition với cùng công thức màu trong bộ xuất.
- JSON dự án lưu lookIntensity riêng mỗi clip; dự án cũ thiếu trường này sẽ mặc định 1.0 và tiếp tục mở được.

### Pipeline video chuẩn bị trước khi dựng
- Nếu clip video có màu khác Nguyên bản và intensity > 0, bộ xuất trích đúng vùng video đã cắt rồi tạo một MOV trung gian qua AVVideoComposition áp Core Image filter frame-by-frame.
- MOV trung gian bảo toàn đường xử lý tiếng nguồn khi định dạng hỗ trợ; TimelineComposer tiếp tục trộn nhạc nền, giọng đọc, SFX, PIP, chuyển cảnh và phụ đề bằng pipeline cũ.
- Đầu ra MP4 720p xem thử và 1080p chính thức đều dùng bước video grading này. Media nguồn không bị thay đổi. File trung gian được xóa sau khi xuất xong hoặc lỗi.

### Hạn chế
- Các kiểu màu dùng Core Image, **không phải LUT 3D .cube nhập ngoài** hay bộ chỉnh màu chuyên dụng Dolby Vision HDR.
- Video có màu cần transcode thêm một lượt, sẽ tăng thời gian xuất, sử dụng dung lượng tạm và mức tiêu thụ pin. Một số codec, HDR và máy thiếu dung lượng có thể không hỗ trợ.
- Cần thử nghiệm end-to-end trên iPhone 12 Pro Max thật; GitHub Actions chỉ xác nhận biên dịch và khả năng tạo unsigned IPA.

### Thử nghiệm
1. Nhập video ngắn 10–20 giây có tiếng và ảnh tĩnh, chọn clip video trong tab Hiệu ứng.
2. Chọn Neo Cinema, Golden Hour hoặc Midnight; thử chỉnh 25%, 65%, 100%. Bật/tắt So sánh trước / sau.
3. Mở Preset Pro → Áp dụng toàn dự án, chỉnh cường độ màu chung, xem MP4 preview 720p và so với bản 1080p.
4. Kiểm tra video gốc còn tiếng, PIP và subtitles vẫn chạy, rồi lưu/khôi phục dự án để kiểm tra các cường độ còn nguyên.


## ViePN Smart Video v4.1.0 – Social Video Downloader & Local Vault

### Tải video và kho độc lập
- Tab **Kho video** (có trong Công cụ) nhận link TikTok, Facebook Reels hoặc URL HTTPS của một tệp MP4/MOV trực tiếp. Có nút **Dán** lấy link từ Clipboard.
- Với **MP4/MOV HTTPS trực tiếp**, app dùng URLSession tải file, kiểm tra HTTP, kích thước ≤ 300 MB, AVAsset có track video và duration hợp lệ. Không thể chỉ đổi đuôi một trang HTML thành MP4.
- Với **link bài đăng TikTok/Facebook**, app gọi máy chủ **Video Resolver** riêng qua HTTPS + X-API-Key để lấy MP4. Phần backend FastAPI/yt-dlp/ffmpeg và Dockerfile trong backend/video_resolver. Bạn cần chạy server và nhập domain/token; app không tự chạy Python/yt-dlp trên iPhone và **chưa có server công khai được triển khai**.
- Dịch vụ tham chiếu chỉ xử lý video công khai mà người tải sở hữu/được phép, không dùng cookie, không đăng nhập vào tài khoản riêng tư, không vượt DRM, không gỡ watermark. Giới hạn server 15 phút và 250 MB; video không hợp lệ, giới hạn truy cập hoặc mạng bị chặn sẽ báo lỗi.
- Thư viện video lưu tại Documents/DownloadLibrary kèm JSON chỉ mục: ngày tải, URL nguồn, thời lượng, tên và dung lượng; video không lưu trên server lâu dài. Token máy chủ lưu trong **iOS Keychain**; không lưu trong project, UserDefaults hay GitHub.
- Kho có bộ lọc theo nguồn, thumbnail, xem bằng AVPlayer, đổi tên, lưu vào Photos, Share Sheet và xác nhận xóa.
- Bấm **Chỉnh sửa** trên một mục tải để **sao chép** vào Documents/Media và thêm clip video lên timeline, rồi áp preset, phụ đề hoặc VFX. Xóa video khỏi Kho không xóa file đã đưa vào dự án.

### Triển khai Video Resolver
1. Thuê/chuẩn bị VPS hoặc Cloud Run có Docker và ffmpeg; xem backend/video_resolver/README.md.
2. Đặt VIEPN_DOWNLOAD_TOKEN dài ≥ 20 ký tự, không công khai. Chạy container, cấu hình proxy HTTPS và rate-limit.
3. Trong ứng dụng mở **Kho video → Thiết lập máy chủ**, nhập https://domain-cua-ban, token, bấm **Lưu khóa bảo mật**.
4. Dán link video công khai bạn được phép tải, đánh dấu xác nhận quyền sử dụng, bấm **Tải về Kho video**.
5. Sau khi xuất hiện trong Kho, bấm **Chỉnh sửa** hoặc **Lưu Ảnh**. Với video có tính năng Save video chính thức của nền tảng, có thể lưu bằng nền tảng rồi nhập từ Photos mà không cần server.

### Kiểm tra
- Dùng 1 URL MP4 HTTPS hợp lệ, kiểm tra tải trực tiếp không cần server, thumbnail, AVPlayer, chia sẻ, đổi tên, xóa.
- Chạy Video Resolver có HTTPS và token riêng: kiểm tra link TikTok/Facebook được phép, link lỗi, token sai, server tắt, response HTML/JSON, video quá 300 MB.
- Đưa video từ Kho vào timeline, lưu dự án, xóa bản Kho, mở lại dự án và xác minh clip vẫn có video.
- Chưa thử nghiệm downloader end-to-end trên iPhone thật hay VPS thực. CI GitHub kiểm tra biên dịch Swift, cú pháp backend Python và tạo IPA chưa ký.

### Giới hạn minh bạch
- Không bảo đảm mọi link TikTok/Facebook hoạt động: nền tảng có thể thay đổi, video riêng tư/bị hạn chế không được hỗ trợ. Điều kiện quyền nội dung và tải của tác giả phải được tôn trọng.
- Backend là thành phần riêng, **không được host tự động bởi GitHub Actions**. Nếu chưa có VPS/server HTTPS, tính năng dán link TikTok/Facebook sẽ báo cần cấu hình chứ không tải giả.
- Hiện chưa có Share Extension nhận link trực tiếp từ nút Chia sẻ TikTok/Facebook; hãy dùng **Sao chép liên kết → Dán** trong Kho.

### Không cần VPS: nhập video đã lưu từ nền tảng
- Trong TikTok/Facebook, nếu chủ nội dung cho phép, dùng **Save video** chính thức để tải về Ảnh trên iPhone.
- Vào **ViePN Smart Video → Kho video → Nhập video đã lưu từ Ảnh**. Chọn video trong PhotosPicker; app kiểm tra thời lượng/track rồi chuyển nó vào **DownloadLibrary**, nơi vẫn có xem, đổi tên, đưa vào timeline, chia sẻ và xóa.
- Cách này hoàn toàn chạy trên iPhone và **không cần máy chủ**. Nút **Tải về Kho video** khi dán link bài đăng TikTok/Facebook vẫn cần Video Resolver HTTPS; hai cách nhập là độc lập.
