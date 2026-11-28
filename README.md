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

## Life Memory System 15
Shared period IDs for Calendar/Timeline/Story. Calendar modes photo/mood/heat, empty-day journal, selected cover, milestones, photo story and slideshow, month/year reflections. Timeline includes journal-only and milestone-only dates. Life Today from camera and timeline, life chapters, future letters with optional local notifications, stats and daily reminder. Story data stays in original archive, Life metadata separately protected. No new bundle ID or extension.

Build 63: Life Journey/Memory River alternating cards, six Story Presentation modes (magazine, envelope, cinema, scrapbook, book, podcast), combined Story/Life JSON backup, annual local reminder. No notification auto-restoration; photo and Signature backups remain separate. Future letters are date-gated in UI, not cryptographically time-locked. Smart chapter suggests year periods, not inferred life events.

## Living Vine Evolution (15.1)
Growth is based on unique local foreground usage dates, saved in Life archive and merged in Life backup. Existing libraries start counting from this update; importing historical photos does not advance age. Stages at 0/7/30/90/180/365 active days. Theme changes, inactive periods and deleting photos do not reset growth. Growth controls stem thickness, density, leaf size, side shoots, buds and flowers; milestone/story nodes bloom at maturity. No streak pressure. Calendar dates follow device time, not a server clock.

## Natural Garden renderer 15.2
Replaces flat vine and weather primitives with stable per-branch organic curvature, shaded stems, asymmetric gradient leaves with veins, layered petals, glass-like dew, radial glow, six-arm snow crystals with depth/blur, angled rain and tumbling botanical particles. Growth stages remain intact. Procedural 2D illustration, not photographic assets or a physical simulation. Weather pauses outside active scene and honors Reduce Motion.

## Botanical Image Edition 15.3
Replaces procedural vine/weather drawing with 17 actual transparent PNG image assets derived from the generated botanical imagery. Asset catalog contains young and blooming green vines, autumn vine, corner, sprig, leaf, bud, flower, dew and drop, firefly, glow, bokeh, three snow textures and petal. Motion uses independently composited sprites, not a moving sheet. All 15 themes are color variants of the three source vines, not 15 individual species. Photos are generated art, not camera photographs. Growth uses the young texture through day 179, buds at 90, flowering at 180, additional density and branch detail by 365. Minimal retains the sparse texture. Assets are resized and palette-optimized for the small display area. Accessibility Reduce Motion and scene-phase pause remain. Tests require all 17 assets to resolve in the app bundle.

## Botanical Continuity 15.4
Continuous trunk image tiles share timeline content coordinates, with mirrored joins and stem anchor profiles sampled from the PNG silhouette. Extra independently placed leaf, bud and bloom sprites grow with age. Weather has real point-per-second fall speed, edge fades, wind and speed controls, foreground/background placement (default behind content), optional time-of-day lighting, and automatic Low Power Mode quality. All 17 existing PNGs remain bundled. Colors still share the original three source vine textures; no claim of separate botanical species or real physics. The prior procedural renderer remains in source for compatibility but not used by the primary timeline.

## Living Memory Ecosystem 16
DNA day badges based on actual photos, stories, recordings, ratings, milestones, chapters and letter dates; existing botanical textures and SF Symbols for new creatures. Separate garden references, per-garden theme and usage days, date threads, portal, focus, daily prompt, gratitude, countdown, year recap, month poster, same-day comparison, PNG signature wallpaper, AES-GCM secret letters, Story Director export controls (opening/ending caption, typeface, zoom keyframes, transition, independent voice/music/ambience mix). Ecosystem metadata is included in Life backup; secret letters are device-bound and separate. Not all proposed features are implemented: no new creature photoreal assets, no per-word audio alignment or depth-separated parallax export, no growth film or animated wallpaper; garden day story shares existing archive. No claims of actual iPhone visual test.

Build 71: interactive Memory Desk with draggable Polaroids and letter, local Vietnamese accent-insensitive search, static signature wallpaper, 720x1280 MP4 of reached growth milestones, separate per-garden day story IDs. Garden calendar still reads shared journal. Garden video reconstructs stages from current age and textures, not a recording of historical frames. Music file suffix preserved for AVFoundation.

Build 72: six alpha PNG creature/ornament sprites (320px, generated art), animated memory badges, Memory Box/Echo, Living Magazine, 365-day rolling reflection, optional on-device speech recognition with timestamped transcript highlighting, Vision two-layer draggable parallax preview, persistent director settings. Speech requires supported on-device language and user permission. Story text is not forcibly aligned to speech. Parallax preview is not exported as layered video. No true Live Photo/animated wallpaper. Secret letter deletion confirms.

## Photo Signature 16.1
Expanded non-destructive recipe with highlights, shadows, tint, vibrance, noise reduction, luminance sharpen, vignette, film looks, rotate and mirror, additional crop ratios, HEIC export and original-size default. Photo Inspector reads real file dimensions and luminance histogram/edge metric. Zoom requests higher resolution after zoom. Edited exports are SDR sRGB and not AI super-resolution. Originals unchanged. Old recipes decode with optional fields.
