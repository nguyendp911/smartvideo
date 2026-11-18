// Single source of truth for the Mockup Studio library. `generate.mjs` draws
// every file listed here and emits SmartVideo/Models/MockupStudioCatalogData.swift,
// so the app metadata can never drift from the shipped image files.

export const CATEGORIES = [
  { id: 'lightShadow', title: 'Light & Shadow', vi: 'Ánh sáng & Bóng đổ' },
  { id: 'natureShadow', title: 'Nature Shadow', vi: 'Bóng thiên nhiên' },
  { id: 'photographyEffects', title: 'Photography Effects', vi: 'Hiệu ứng nhiếp ảnh' },
  { id: 'textureSurface', title: 'Texture & Surface', vi: 'Chất liệu & Bề mặt' },
  { id: 'glassEffects', title: 'Glass Effects', vi: 'Hiệu ứng kính' },
  { id: 'weatherEffects', title: 'Weather Effects', vi: 'Thời tiết' },
  { id: 'retroEffects', title: 'Retro Effects', vi: 'Retro' },
  { id: 'background', title: 'Background', vi: 'Nền' },
  { id: 'frameMockup', title: 'Frame Mockup', vi: 'Khung ảnh' },
  { id: 'productMockup', title: 'Product Mockup', vi: 'Mockup sản phẩm' },
];

const A = (id, name, category, group, kind, blend, opacity, tags, description, size = [1280, 1280]) =>
  ({ id, name, category, group, kind, blend, opacity, tags, description, size, premium: false });

export const ASSETS = [
  // LIGHT & SHADOW -------------------------------------------------------
  A('window-shadow', 'Window Shadow', 'lightShadow', 'light', 'overlay', 'multiply', 0.75, ['cửa sổ', 'window', 'bóng', 'nắng'], 'Bóng cửa sổ chia ô, nắng chiếu xiên lên tường.'),
  A('window-frame-shadow', 'Window Frame Shadow', 'lightShadow', 'light', 'overlay', 'multiply', 0.7, ['khung cửa', 'frame', 'bóng'], 'Bóng khung và thanh chia của cửa sổ.'),
  A('sunlight-rays', 'Sunlight Rays', 'lightShadow', 'light', 'overlay', 'screen', 0.7, ['tia nắng', 'rays', 'ánh sáng', 'god rays'], 'Chùm tia nắng tỏa từ góc trên trái.'),
  A('natural-light', 'Natural Light', 'lightShadow', 'light', 'overlay', 'softLight', 0.9, ['ánh sáng tự nhiên', 'warm', 'ấm'], 'Ánh sáng ngày dịu, ấm ở góc, lạnh nhẹ ở đối diện.'),
  A('blind-shadows', 'Blind Shadows', 'lightShadow', 'light', 'overlay', 'multiply', 0.7, ['rèm', 'blinds', 'sọc', 'venetian'], 'Bóng rèm lá sách chéo.'),
  A('hard-light', 'Hard Light', 'lightShadow', 'light', 'overlay', 'screen', 0.8, ['ánh sáng gắt', 'hard', 'mảng sáng'], 'Các mảng sáng viền sắc nét như nắng gắt.'),
  A('soft-light', 'Soft Light', 'lightShadow', 'light', 'overlay', 'softLight', 0.9, ['ánh sáng mềm', 'soft', 'glow'], 'Ánh sáng khuếch tán mềm, tối nhẹ phần dưới.'),
  A('long-shadow', 'Long Shadow', 'lightShadow', 'light', 'overlay', 'multiply', 0.7, ['bóng dài', 'long', 'hoàng hôn'], 'Các dải bóng dài khi nắng thấp.'),
  A('floating-shadow', 'Floating Shadow', 'lightShadow', 'light', 'overlay', 'multiply', 0.8, ['bóng nổi', 'floating', 'sản phẩm'], 'Bóng mềm cho vật thể như đang lơ lửng.'),
  A('product-shadow', 'Product Shadow', 'lightShadow', 'light', 'overlay', 'multiply', 0.85, ['bóng sản phẩm', 'contact', 'studio'], 'Bóng tiếp xúc cộng bóng đổ nhẹ dưới sản phẩm.'),

  // NATURE SHADOW --------------------------------------------------------
  A('palm-leaf-shadow', 'Palm Leaf Shadow', 'natureShadow', 'nature', 'overlay', 'multiply', 0.72, ['cọ', 'palm', 'lá', 'nhiệt đới'], 'Bóng các tàu lá cọ lông chim.'),
  A('plant-shadow', 'Plant Shadow', 'natureShadow', 'nature', 'overlay', 'multiply', 0.72, ['cây', 'plant', 'lá'], 'Bóng bụi cây nhiều thân lá.'),
  A('tree-branch-shadow', 'Tree Branch Shadow', 'natureShadow', 'nature', 'overlay', 'multiply', 0.74, ['cành cây', 'branch', 'tree'], 'Bóng cành cây có lá nhỏ.'),
  A('flower-shadow', 'Flower Shadow', 'natureShadow', 'nature', 'overlay', 'multiply', 0.7, ['hoa', 'flower', 'cánh hoa'], 'Bóng những bông hoa nhiều cánh trên cuống.'),
  A('tropical-leaf-shadow', 'Tropical Leaf Shadow', 'natureShadow', 'nature', 'overlay', 'multiply', 0.72, ['monstera', 'chuối', 'tropical', 'lá lớn'], 'Bóng lá monstera xẻ thùy và lá chuối.'),

  // PHOTOGRAPHY EFFECTS --------------------------------------------------
  A('film-grain', 'Film Grain', 'photographyEffects', 'photo', 'overlay', 'overlay', 0.5, ['hạt phim', 'grain', 'film', 'noise'], 'Nhiễu hạt phim trung tính, dùng với Overlay hoặc Soft Light.'),
  A('light-leak', 'Light Leak', 'photographyEffects', 'photo', 'overlay', 'screen', 0.7, ['rò sáng', 'leak', 'cam', 'film'], 'Vệt sáng cam–hồng loang ở mép như máy film rò sáng.'),
  A('lens-flare', 'Lens Flare', 'photographyEffects', 'photo', 'overlay', 'screen', 0.8, ['flare', 'ống kính', 'lóa', 'anamorphic'], 'Lóa ống kính với vệt ngang và vòng phản xạ.'),
  A('haze', 'Haze', 'photographyEffects', 'photo', 'overlay', 'screen', 0.6, ['sương mù nhẹ', 'haze', 'mờ ảo'], 'Lớp mù mờ dâng dần từ dưới lên.'),
  A('glow', 'Glow', 'photographyEffects', 'photo', 'overlay', 'screen', 0.7, ['phát sáng', 'glow', 'bloom'], 'Quầng sáng bloom quanh vùng sáng.'),
  A('vignette', 'Vignette', 'photographyEffects', 'photo', 'overlay', 'multiply', 0.6, ['tối góc', 'vignette', 'viền tối'], 'Tối dần ra bốn góc.'),
  A('dust', 'Dust', 'photographyEffects', 'photo', 'overlay', 'screen', 0.7, ['bụi', 'dust', 'hạt bụi'], 'Hạt bụi và sợi xơ bám trên ống kính.'),
  A('scratches', 'Scratches', 'photographyEffects', 'photo', 'overlay', 'screen', 0.6, ['xước', 'scratches', 'film cũ'], 'Vết xước dọc của cuộn phim cũ.'),
  A('bokeh', 'Bokeh', 'photographyEffects', 'photo', 'overlay', 'screen', 0.8, ['bokeh', 'đốm sáng', 'xóa phông'], 'Các đốm bokeh tròn có viền sáng.'),
  A('chromatic-aberration', 'Chromatic Aberration', 'photographyEffects', 'photo', 'overlay', 'screen', 0.6, ['sắc sai', 'chromatic', 'rgb', 'viền màu'], 'Viền màu đỏ/lục lam ở mép khung (mô phỏng sắc sai ống kính).'),

  // TEXTURE & SURFACE ----------------------------------------------------
  A('paper-texture', 'Paper Texture', 'textureSurface', 'texture', 'overlay', 'multiply', 0.6, ['giấy', 'paper', 'texture'], 'Bề mặt giấy có sợi, nên dùng với Multiply.'),
  A('torn-paper', 'Torn Paper', 'textureSurface', 'texture', 'overlay', 'normal', 1, ['giấy rách', 'torn', 'mép rách'], 'Tờ giấy rách mép phủ nửa dưới ảnh.'),
  A('folded-paper', 'Folded Paper', 'textureSurface', 'texture', 'overlay', 'multiply', 0.65, ['giấy gấp', 'folded', 'nếp gấp'], 'Giấy có nếp gấp như bức thư.'),
  A('crumpled-paper', 'Crumpled Paper', 'textureSurface', 'texture', 'overlay', 'multiply', 0.55, ['giấy nhàu', 'crumpled', 'nhăn'], 'Giấy vo nhàu, nổi khối mạnh.'),
  A('concrete-texture', 'Concrete Texture', 'textureSurface', 'texture', 'overlay', 'multiply', 0.55, ['bê tông', 'concrete', 'xi măng'], 'Bề mặt bê tông có lỗ rỗ.'),
  A('plaster-wall', 'Plaster Wall', 'textureSurface', 'texture', 'overlay', 'multiply', 0.5, ['tường vữa', 'plaster', 'tường'], 'Tường trát vữa gợn nhẹ.'),
  A('linen-texture', 'Linen Texture', 'textureSurface', 'texture', 'overlay', 'multiply', 0.5, ['vải lanh', 'linen', 'dệt'], 'Vải lanh dệt thoi có xơ.'),
  A('canvas-texture', 'Canvas Texture', 'textureSurface', 'texture', 'overlay', 'multiply', 0.5, ['canvas', 'vải bố', 'tranh sơn dầu'], 'Vải canvas dệt mịn như toan vẽ.'),
  A('vintage-texture', 'Vintage Texture', 'textureSurface', 'texture', 'overlay', 'multiply', 0.7, ['cổ điển', 'vintage', 'ố vàng'], 'Giấy cũ ố vàng, cháy viền.'),

  // GLASS EFFECTS --------------------------------------------------------
  A('frosted-glass', 'Frosted Glass', 'glassEffects', 'glass', 'overlay', 'normal', 0.9, ['kính mờ', 'frosted', 'mờ'], 'Kính nhám trắng đục.'),
  A('glass-reflection', 'Glass Reflection', 'glassEffects', 'glass', 'overlay', 'screen', 0.8, ['phản chiếu', 'reflection', 'kính'], 'Các dải phản chiếu chéo trên mặt kính.'),
  A('glass-blur', 'Glass Blur', 'glassEffects', 'glass', 'overlay', 'normal', 0.9, ['kính mờ nhòe', 'blur', 'sương kính'], 'Lớp sương kính loang mờ (mô phỏng, không làm nhòe ảnh bên dưới).'),
  A('glass-distortion', 'Glass Distortion', 'glassEffects', 'glass', 'overlay', 'overlay', 0.8, ['kính gân', 'fluted', 'reeded', 'méo'], 'Kính gân dọc tạo vệt sáng–tối như thấu kính nhỏ.'),
  A('water-droplets', 'Water Droplets', 'glassEffects', 'glass', 'overlay', 'normal', 0.9, ['giọt nước', 'droplets', 'mưa', 'kính ướt'], 'Giọt nước đọng trên kính có điểm sáng và bóng.'),

  // WEATHER --------------------------------------------------------------
  A('rain', 'Rain', 'weatherEffects', 'weather', 'overlay', 'screen', 0.85, ['mưa', 'rain'], 'Hạt mưa rơi xiên.'),
  A('snow', 'Snow', 'weatherEffects', 'weather', 'overlay', 'screen', 0.9, ['tuyết', 'snow'], 'Tuyết rơi nhiều lớp xa gần.'),
  A('fog', 'Fog', 'weatherEffects', 'weather', 'overlay', 'screen', 0.8, ['sương mù', 'fog'], 'Sương mù dày nhất ở phía dưới.'),
  A('mist', 'Mist', 'weatherEffects', 'weather', 'overlay', 'screen', 0.8, ['màn sương', 'mist', 'bồng bềnh'], 'Các dải sương mỏng bồng bềnh.'),
  A('sun-flare', 'Sun Flare', 'weatherEffects', 'weather', 'overlay', 'screen', 0.85, ['nắng', 'sun', 'flare', 'mặt trời'], 'Mặt trời chói ở góc phải với tia và vòng sáng.'),
  A('water-reflection', 'Water Reflection', 'weatherEffects', 'weather', 'overlay', 'overlay', 0.7, ['nước', 'reflection', 'mặt hồ', 'gợn sóng'], 'Mặt nước gợn sóng phản chiếu ở nửa dưới.'),

  // RETRO ----------------------------------------------------------------
  A('vhs', 'VHS', 'retroEffects', 'retro', 'overlay', 'overlay', 0.8, ['vhs', 'băng từ', 'scanline'], 'Đường quét, nhiễu băng và lệch màu băng VHS.'),
  A('halftone', 'Halftone', 'retroEffects', 'retro', 'overlay', 'multiply', 0.7, ['chấm bán sắc', 'halftone', 'in ấn'], 'Lưới chấm in offset lớn dần theo đường chéo.'),
  A('duotone', 'Duotone', 'retroEffects', 'retro', 'overlay', 'overlay', 0.7, ['hai tông', 'duotone', 'gradient'], 'Dải màu tím–cam cho tông hai màu (Overlay).'),
  A('film-burn', 'Film Burn', 'retroEffects', 'retro', 'overlay', 'screen', 0.9, ['cháy phim', 'burn', 'film'], 'Vệt cháy phim cam–vàng loang ở góc.'),
  A('vintage-film', 'Vintage Film', 'retroEffects', 'retro', 'overlay', 'multiply', 0.85, ['phim cũ', 'vintage', 'viền phim'], 'Viền khung phim cũ, ám vàng và bụi.'),
  A('analog-noise', 'Analog Noise', 'retroEffects', 'retro', 'overlay', 'overlay', 0.5, ['nhiễu analog', 'noise', 'tín hiệu'], 'Nhiễu màu analog kèm vệt ngang.'),

  // BACKGROUND -----------------------------------------------------------
  A('minimal-background', 'Minimal Background', 'background', 'background', 'background', 'normal', 1, ['tối giản', 'minimal', 'trắng ngà'], 'Nền trắng ngà gradient nhẹ.'),
  A('studio-background', 'Studio Background', 'background', 'background', 'background', 'normal', 1, ['studio', 'phông', 'xám'], 'Phông studio cong có đèn rọi giữa.'),
  A('gradient-background', 'Gradient Background', 'background', 'background', 'background', 'normal', 1, ['gradient', 'pastel', 'chuyển màu'], 'Nền pastel đào–tím–xanh.'),
  A('abstract-background', 'Abstract Background', 'background', 'background', 'background', 'normal', 1, ['trừu tượng', 'abstract', 'hữu cơ'], 'Các mảng màu hữu cơ nhòe với đường vòng mảnh.'),
  A('beige-background', 'Beige Background', 'background', 'background', 'background', 'normal', 1, ['be', 'beige', 'ấm'], 'Nền be ấm có hạt mịn.'),
  A('paper-background', 'Paper Background', 'background', 'background', 'background', 'normal', 1, ['nền giấy', 'paper', 'giấy'], 'Nền giấy trắng ngà có sợi.'),

  // FRAME MOCKUP ---------------------------------------------------------
  A('polaroid-frame', 'Polaroid Frame', 'frameMockup', 'frames', 'scene', 'normal', 1, ['polaroid', 'ảnh lấy liền', 'khung'], 'Ảnh lấy liền Polaroid dán băng keo.', [1200, 1500]),
  A('film-frame', 'Film Frame', 'frameMockup', 'frames', 'scene', 'normal', 1, ['phim 35mm', 'film', 'khung phim'], 'Cuộn phim 35mm trên bàn đèn.', [1500, 1200]),
  A('vintage-frame', 'Vintage Frame', 'frameMockup', 'frames', 'scene', 'normal', 1, ['khung cổ', 'vintage', 'vàng'], 'Khung gỗ mạ vàng cổ điển treo tường.', [1200, 1500]),
  A('photo-frame', 'Photo Frame', 'frameMockup', 'frames', 'scene', 'normal', 1, ['khung ảnh', 'photo', 'treo tường'], 'Khung ảnh đen viền trắng treo tường.', [1200, 1500]),
  A('magazine-frame', 'Magazine Frame', 'frameMockup', 'frames', 'scene', 'normal', 1, ['trang tạp chí', 'magazine', 'bài báo'], 'Trang bên trong tạp chí có ảnh lớn.', [1200, 1500]),

  // PRODUCT MOCKUP -------------------------------------------------------
  A('cosmetic-packaging', 'Cosmetic Packaging', 'productMockup', 'products', 'scene', 'normal', 1, ['mỹ phẩm', 'hộp', 'cosmetic', 'packaging'], 'Hộp mỹ phẩm kem kèm hũ nắp vàng.', [1200, 1500]),
  A('perfume-bottle', 'Perfume Bottle', 'productMockup', 'products', 'scene', 'normal', 1, ['nước hoa', 'perfume', 'chai'], 'Chai nước hoa thủy tinh nắp vàng.', [1200, 1500]),
  A('skincare-bottle', 'Skincare Bottle', 'productMockup', 'products', 'scene', 'normal', 1, ['chăm sóc da', 'skincare', 'chai pump'], 'Chai skincare có vòi pump trên bục.', [1200, 1500]),
  A('product-box', 'Product Box', 'productMockup', 'products', 'scene', 'normal', 1, ['hộp', 'box', 'carton'], 'Hộp carton nhìn 3 mặt.', [1200, 1500]),
  A('shopping-bag', 'Shopping Bag', 'productMockup', 'products', 'scene', 'normal', 1, ['túi giấy', 'shopping', 'bag', 'kraft'], 'Túi giấy kraft quai dây.', [1200, 1500]),
  A('poster', 'Poster', 'productMockup', 'products', 'scene', 'normal', 1, ['poster', 'áp phích', 'tranh treo'], 'Poster khung đen treo tường phòng khách.', [1200, 1500]),
  A('business-card', 'Business Card', 'productMockup', 'products', 'scene', 'normal', 1, ['danh thiếp', 'business card', 'namecard'], 'Danh thiếp trên bàn gỗ.', [1500, 1100]),
  A('magazine-cover', 'Magazine Cover', 'productMockup', 'products', 'scene', 'normal', 1, ['bìa tạp chí', 'magazine', 'cover'], 'Bìa tạp chí có tên báo và mã vạch.', [1200, 1500]),
  A('book-cover', 'Book Cover', 'productMockup', 'products', 'scene', 'normal', 1, ['bìa sách', 'book', 'cover'], 'Cuốn sách đứng có gáy và mép giấy.', [1200, 1500]),
];
