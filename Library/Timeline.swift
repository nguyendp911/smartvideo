import SwiftUI
import PhotosUI
import Photos
import UniformTypeIdentifiers
import ImageIO

private enum Transfer { case backup,restore }
enum GalleryLayout: String, CaseIterable {
    case editorial = "Nhật ký", grid = "Lưới ảnh", cinema = "Cinema Gallery", vintage = "Vintage Diary", minimal = "Minimal Gallery", midnight = "Midnight Gold", zen = "Zen Collection"
    var hero:Bool {self == .editorial || self == .cinema || self == .vintage || self == .midnight || self == .zen}
    var background:Color {
        switch self {
        case .vintage:return Color(red:0.20,green:0.15,blue:0.12)
        case .zen:return Color(red:0.17,green:0.20,blue:0.18)
        case .midnight:return .black
        case .minimal:return Color(red:0.18,green:0.18,blue:0.18)
        default:return night
        }
    }
    var accent:Color {self == .zen ? Color(red:0.69,green:0.82,blue:0.69) : self == .minimal ? .white : gold}
    var ratio:CGFloat {self == .cinema ? 1.78 : (self == .vintage ? 0.88 : 1.46)}
    var font:Font.Design {self == .minimal || self == .grid ? .default : (self == .cinema ? .monospaced : .serif)}
}
struct Timeline: View {
    @ObservedObject var model: LibraryModel
    var initialDay:String?=nil
    @ObservedObject private var stories=StoryArchive.shared
    @ObservedObject private var life=LifeArchive.shared
    @State private var showToday=false
    @State private var pathMode:LifePathMode?
    @State private var showLifeBackup=false
    @State private var showChapters=false
    @State private var showIntelligence=false
    @State private var showLetters=false
    @State private var showVines=false
    @State private var showWorld=false
    @State private var showDiscovery=false
    @State private var showPodcast=false
    @State private var showGardenDesigner=false
    @State private var showStoryLibrary=false
    @State private var collectionStory:StoryTarget?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("timeline.presentation.v2") private var presentationValue=TimelinePresentation.tree.rawValue
    private var presentation:TimelinePresentation{TimelinePresentation(rawValue:presentationValue) ?? .tree}
    @AppStorage("timeline.layout") private var layoutValue = GalleryLayout.editorial.rawValue
    @AppStorage("timeline.spacing") private var photoSpacing=5.0
    @AppStorage("timeline.radius") private var photoRadius=8.0
    @AppStorage("timeline.columns") private var columnCount=3
    @AppStorage("timeline.heroTitle") private var heroTitle=true
    @AppStorage("timeline.dateSize") private var dateSize=21.0
    @State private var showDesigner=false
    @State private var showSignature=false
    @State private var showJump=false
    @State private var collection=""
    @State private var look:Look?
    @State private var anniversary=""
    @State private var showCalendar=false
    @State private var slideshow=false
    @State private var slideShots=[Shot]()
    @State private var search = ""
    @State private var session = ""
    @State private var period = ""
    @State private var scope = TimelineScope.all
    @State private var scale = TimelinePeriod.day
    @State private var light: Light?
    @State private var minimumRating = 0
    @State private var selection: Shot?
    @State private var imported = [PhotosPickerItem]()
    @State private var importing = false
    @State private var working = false
    @State private var importStatus = ""
    @State private var pickFolder = false
    @State private var transfer = Transfer.backup
    @State private var compare = false
    @State private var selecting = false
    @State private var chosen = Set<UUID>()
    @State private var pair = false
    @State private var newest = true
    @State private var showAlbums = false
    @State private var showFilters = false
    @State private var batchTrash = false
    @State private var batchEdit = false
    @State private var batchText = ""
    @State private var batchKind = "album"
    private var active: [Shot] { model.shots.filter { $0.deleted == nil } }
    private var filtered:[Shot]{
        let base=TimelineIndex.filter(model.shots,scope:scope,session:session,period:period,light:light,minimumRating:minimumRating,newest:newest,collection:collection,look:look,anniversary:anniversary)
        if search.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty{return base}
        let hits=Set(TimelineIndex.filter(base,scope:scope,query:search,newest:newest).map(\.id))
        return base.filter{hits.contains($0.id) || stories.matching(search,shot:$0)}
    }
    private var journalDays:Set<String>{
        guard scope == .all,session.isEmpty,collection.isEmpty,light==nil,look==nil,minimumRating==0 else{return []}
        let days=MemorySync.activeDays(shots:[],stories:stories,life:life)
        return Set(days.filter{day in
            guard period.isEmpty || day.hasPrefix(period),anniversary.isEmpty || day.hasSuffix(anniversary) else{return false}
            if search.isEmpty{return true}
            let e=stories.entry("period:"+day)
            return ([day,e?.title ?? "",e?.body ?? "",e?.mood?.rawValue ?? ""]+life.milestones(day).map{$0.title+" "+$0.note}).joined(separator:" ").localizedStandardContains(search)
        })
    }
    private var groups: [TimelineGroup] { TimelineIndex.group(filtered,period:scale,newest:newest) }
    private var selectedShots: [Shot] { model.shots.filter { chosen.contains($0.id) } }
    private var layout: GalleryLayout { GalleryLayout(rawValue:layoutValue) ?? .editorial }
    private var hasFilters: Bool { scope != .all || !session.isEmpty || !period.isEmpty || light != nil || minimumRating > 0 || !search.isEmpty || !collection.isEmpty || look != nil || !anniversary.isEmpty }
    private var columns: [GridItem] { Array(repeating:GridItem(.flexible(),spacing:CGFloat(photoSpacing)),count:max(2,min(5,columnCount))) }
    private var coverColumns: [GridItem] { Array(repeating:GridItem(.flexible(),spacing:10),count:2) }

    var body: some View {
        NavigationStack {
            VStack(spacing:0) {
                top
                controls
                if working { ProgressView(importStatus.isEmpty ? "Đang xử lý…" : importStatus).padding(8).frame(maxWidth:.infinity) }
                if selecting || compare { selectionBar }
                if showAlbums { albumPage }
                else if filtered.isEmpty && (presentation != .tree || journalDays.isEmpty || selecting || compare) { emptyPage }
                else if selecting || compare || scope == .trash || presentation == .gallery {gallery}
                else if presentation == .tree{
                    TimelineStoryTree(shots:filtered,vault:model.vault,newest:newest,accent:layout.accent,open:{selection=$0},play:{slideShots=$0;slideshow=true},extraDays:journalDays)
                }else{
                    ScrollView {TimelineSlideStage(shots:filtered,vault:model.vault,open:{selection=$0})}.scrollIndicators(.hidden)
                }
            }
            .background(layout.background)
            .tint(layout.accent)
            .disabled(working)
            .toolbar(.hidden,for:.navigationBar)
        }
        .task { await model.reload();if let initialDay{resetFilters();period=initialDay;presentationValue=TimelinePresentation.tree.rawValue} }
        .onChange(of:search) { _,_ in chosen.removeAll() }
        .fullScreenCover(item:$selection) { shot in
            ShotDetail(model:model,shot:shot,shots:filtered)
        }
        .fullScreenCover(isPresented:$pair,onDismiss:{ clearSelection() }) {
            CompareView(shots:selectedShots,vault:model.vault)
        }
        .sheet(isPresented:$showFilters) { filterSheet }
        .sheet(isPresented:$showVines){VineCollectionView()}
        .sheet(item:$pathMode){LifePathView(shots:active,vault:model.vault,mode:$0)}
        .sheet(isPresented:$showLifeBackup){LifeBackupView()}
        .sheet(isPresented:$showToday){LifeToday(model:model,camera:{showToday=false;dismiss()},timeline:{day in showToday=false;resetFilters();period=day ?? "";showAlbums=false;presentationValue=TimelinePresentation.tree.rawValue})}
        .sheet(isPresented:$showChapters){LifeChapterStudio(shots:active,vault:model.vault)}
        .sheet(isPresented:$showIntelligence){LifeIntelligence(shots:active,vault:model.vault)}
        .sheet(isPresented:$showLetters){FutureLetterStudio(life:life)}
        .fullScreenCover(isPresented:$showWorld){MemoryWorld(shots:active,vault:model.vault)}
        .sheet(isPresented:$showDiscovery){MemoryDiscover(shots:active,vault:model.vault)}
        .sheet(isPresented:$showPodcast){MemoryPodcast()}
        .sheet(isPresented:$showGardenDesigner){GardenDesigner()}
        .sheet(isPresented:$showStoryLibrary){StoryLibrary(shots:active,vault:model.vault,archive:stories)}
        .sheet(item:$collectionStory){target in if stories.entry(target.id) != nil{StoryReader(target:target,vault:model.vault,archive:stories)}else{StoryComposer(target:target,vault:model.vault,archive:stories)}}
        .sheet(isPresented:$showDesigner){TimelineDesigner(layout:$layoutValue,spacing:$photoSpacing,radius:$photoRadius,columns:$columnCount,caption:$heroTitle,dateSize:$dateSize)}
        .fullScreenCover(isPresented:$showSignature){SignatureHub(model:model)}
        .sheet(isPresented:$showJump){
            NavigationStack {
                List(TimelineIndex.group(active,period:.month,newest:true)){group in
                    Button {resetFilters();period=group.key;scale = .day;showAlbums=false;showJump=false} label:{
                        HStack{Text(TimelineIndex.label(group.key));Spacer();Text("\(group.items.count) ảnh").foregroundStyle(.secondary)}
                    }
                }.navigationTitle("Đi đến thời gian").toolbar{Button("Đóng"){showJump=false}}
            }
        }
        .sheet(isPresented:$showCalendar){
            LifeCalendar(shots:active,vault:model.vault){key in
                resetFilters();period=key;scale = .day;showAlbums=false;presentationValue=TimelinePresentation.tree.rawValue;showCalendar=false
            }
        }
        .fullScreenCover(isPresented:$slideshow){ArchiveSlideshow(shots:slideShots,vault:model.vault)}
        .sheet(isPresented:$batchEdit) { batchSheet }
        .photosPicker(isPresented:$importing,selection:$imported,maxSelectionCount:20,matching:.images)
        .onChange(of:imported) { _,items in
            guard !items.isEmpty else { return }
            Task {
                working=true
                defer { working=false;importStatus="";imported=[] }
                var failures=0
                for (i,item) in items.enumerated() {
                    importStatus="Nhập ảnh \(i+1)/\(items.count)"
                    do {
                        guard let bytes=try await item.loadTransferable(type:Data.self) else { throw CameraError.unreadable }
                        _=try await model.vault.add(bytes,look:.neutral,session:session,time:Date(),lens:"Ảnh nhập")
                    } catch { failures+=1 }
                }
                await model.reload()
                if failures>0 { model.message="Có \(failures) ảnh không nhập được." }
            }
        }
        .fileImporter(isPresented:$pickFolder,allowedContentTypes:[.folder]) { result in
            guard case .success(let url)=result else { return }
            let action=transfer
            Task {
                let access=url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                working=true; defer { working=false }
                do {
                    switch action {
                    case .backup: let n=try await model.vault.backup(to:url);model.message="Đã sao lưu \(n) ảnh."
                    case .restore: let (n,s)=try await model.vault.restore(from:url);model.message="Đã phục hồi \(n) ảnh, bỏ qua \(s) mục đã có."
                    }
                } catch { model.message=error.localizedDescription }
                await model.reload()
            }
        }
        .confirmationDialog("Chuyển \(chosen.count) ảnh vào thùng rác?",isPresented:$batchTrash) {
            Button("Chuyển vào thùng rác",role:.destructive) { runBatch(trash:true) }
        }
        .alert("VieLens",isPresented:Binding(get:{model.message != nil && selection == nil},set:{if !$0 {model.message=nil}})) {
            Button("Đóng") { model.message=nil }
        } message: { Text(model.message ?? "") }
    }
    private var top: some View {
        HStack(alignment:.center,spacing:12) {
            VStack(alignment:.leading,spacing:3) {
                Text("V I E L E N S   /   S I G N A T U R E").font(.system(size:9,weight:.semibold,design:.monospaced)).foregroundStyle(gold)
                Text(showAlbums ? "Bộ sưu tập" : "Miền ký ức").font(.system(size:34,weight:.regular,design:.serif)).lineLimit(1).minimumScaleFactor(0.7)
                Text("\(active.count) ảnh  ·  \(Set(active.map(\.day)).count) ngày lưu giữ").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength:4)
            Menu {
                Button("Hôm nay của tôi",systemImage:"sun.max"){showToday=true}
                Button("Life Journey",systemImage:"point.topleft.down.to.point.bottomright.curvepath"){pathMode = .journey}
                Button("Memory River",systemImage:"water.waves"){pathMode = .river}
                Button("Sao lưu nhật ký & cuộc đời",systemImage:"externaldrive"){showLifeBackup=true}
                Button("Life Chapters",systemImage:"book.pages"){showChapters=true}
                Button("Memory Intelligence",systemImage:"sparkles"){showIntelligence=true}
                Button("Thư tương lai",systemImage:"envelope"){showLetters=true}
                Button("Memory World",systemImage:"sparkles.rectangle.stack"){showWorld=true}
                Button("Khám phá ký ức",systemImage:"clock.arrow.circlepath"){showDiscovery=true}
                Button("Memory Podcast",systemImage:"waveform"){showPodcast=true}
                Button("Vine Designer",systemImage:"paintpalette"){showGardenDesigner=true}
                Button("Story Studio",systemImage:"book.closed"){showStoryLibrary=true}
                Button("Bộ sưu tập dây leo",systemImage:"leaf.fill"){showVines=true}
                Button("Signature Studio",systemImage:"sparkles"){showSignature=true}
                Button("Thiết kế Timeline",systemImage:"paintbrush.pointed"){showDesigner=true}
                Button("Đi đến tháng/năm",systemImage:"calendar.badge.clock"){showJump=true}
                Button("Nhập ảnh",systemImage:"photo.badge.plus") { importing=true }
                Button("Lịch ảnh",systemImage:"calendar") {showCalendar=true}
                Button("Ngày này qua các năm",systemImage:"clock.arrow.circlepath"){resetFilters();anniversary=TimelineIndex.todaySuffix();scale = .day;showAlbums=false}
                Button("Cây thời gian",systemImage:"point.topleft.down.to.point.bottomright.curvepath"){clearSelection();showAlbums=false;presentationValue=TimelinePresentation.tree.rawValue}
                Button("Slide ký ức",systemImage:"rectangle.on.rectangle"){clearSelection();showAlbums=false;presentationValue=TimelinePresentation.slides.rawValue}
                Button("Trình chiếu",systemImage:"play.rectangle"){slideShots=filtered;slideshow=true}.disabled(filtered.isEmpty || scope == .trash)
                Button("So sánh hai ảnh",systemImage:"rectangle.split.2x1") { showAlbums=false;clearSelection();compare=true }
                Button("Sao lưu vào Tệp",systemImage:"square.and.arrow.up") { transfer = .backup;pickFolder=true }
                Button("Phục hồi từ thư mục",systemImage:"arrow.counterclockwise") { transfer = .restore;pickFolder=true }
            } label: { circleIcon("ellipsis") }.disabled(working)
            Button { dismiss() } label: { circleIcon("camera") }.accessibilityLabel("Về máy ảnh")
        }.padding(.horizontal,18).padding(.vertical,12)
    }
    private func circleIcon(_ icon: String) -> some View {
        Image(systemName:icon).font(.system(size:17,weight:.medium)).frame(width:42,height:42)
            .background(.white.opacity(0.07),in:Circle())
    }
    private var controls: some View {
        VStack(spacing:10) {
            HStack(spacing:8) {
                tab("Dòng thời gian",icon:"calendar",selected: !showAlbums) { showAlbums=false }
                tab("Album",icon:"rectangle.stack",selected:showAlbums) { clearSelection();showAlbums=true }
                Spacer(minLength:0)
                Button{showCalendar=true}label:{circleIcon("calendar")}.accessibilityLabel("Lịch ký ức")
                Button { showFilters=true } label: { circleIcon(hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease") }.accessibilityLabel("Bộ lọc")
                Button { if selecting || compare {clearSelection()} else {showAlbums=false;selecting=true} } label: { circleIcon(selecting || compare ? "xmark" : "checkmark.circle") }.accessibilityLabel("Chọn ảnh")
            }
            if showAlbums || presentation == .gallery {
            Button {showSignature=true} label:{
                HStack{
                    Image(systemName:"sparkles").foregroundStyle(layout.accent)
                    Text("Signature Studio").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("Ký ức · Sáng tạo").font(.caption).foregroundStyle(.secondary)
                    Image(systemName:"chevron.right").font(.caption)
                }.padding(10).background(.white.opacity(0.065),in:RoundedRectangle(cornerRadius:11))
            }.buttonStyle(.plain)
            }
            if !showAlbums {
                if !selecting && !compare && scope != .trash{
                    HStack(spacing:5){
                        ForEach(TimelinePresentation.allCases,id:\.self){mode in
                            Button{
                                UISelectionFeedbackGenerator().selectionChanged()
                                withAnimation(.easeInOut(duration:0.25)){presentationValue=mode.rawValue}
                            }label:{
                                VStack(spacing:4){
                                    Image(systemName:mode.icon).font(.system(size:15,weight:.medium))
                                    Text(mode.rawValue).font(.system(size:10,weight:.semibold)).lineLimit(1)
                                }.frame(maxWidth:.infinity).frame(height:43)
                                    .foregroundStyle(presentation==mode ? Color.black:Color.white.opacity(0.8))
                                    .background(presentation==mode ? layout.accent:Color.white.opacity(0.06),in:RoundedRectangle(cornerRadius:10))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if presentation == .gallery || selecting || compare || scope == .trash{
                HStack(spacing:8) {
                    Picker("Khoảng thời gian",selection:Binding(get:{scale},set:{scale=$0;period="";clearSelection()})) {
                        ForEach(TimelinePeriod.allCases,id:\.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    Button {showDesigner=true} label:{Image(systemName:"paintbrush.pointed").frame(width:40,height:36)}.accessibilityLabel("Thiết kế Timeline")
                }
                }
                HStack {
                    Image(systemName:"magnifyingglass")
                    TextField("Tìm khoảnh khắc, ngày, nhãn…",text:$search).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !search.isEmpty { Button { search="" } label:{Image(systemName:"xmark.circle.fill")} }
                }.font(.subheadline).foregroundStyle(.secondary).padding(11).background(.white.opacity(0.065),in:RoundedRectangle(cornerRadius:12))
                if hasFilters {
                    HStack {
                        Text([scope != .all ? scope.rawValue : "",session,collection,look?.rawValue ?? "",anniversary.isEmpty ? "" : "Ngày này",period.isEmpty ? "" : TimelineIndex.label(period),light?.rawValue ?? "",minimumRating > 0 ? "\(minimumRating)+ sao" : ""].filter{ !$0.isEmpty }.joined(separator:" · ")).lineLimit(1)
                        Spacer()
                        Text("\(filtered.count) ảnh")
                        Button("Xóa lọc") { resetFilters() }
                    }.font(.caption).foregroundStyle(gold)
                }
            }
        }.padding(.horizontal,16).padding(.bottom,10)
    }
    private func tab(_ title: String,icon: String,selected: Bool,action: @escaping ()->Void) -> some View {
        Button(action:action) {
            Label(title,systemImage:icon).font(.caption.weight(.semibold)).lineLimit(1)
                .padding(.horizontal,12).frame(height:38)
                .foregroundStyle(selected ? Color.black : Color.white)
                .background(selected ? gold : Color.white.opacity(0.07),in:Capsule())
        }.buttonStyle(.plain)
    }
    private var emptyPage: some View {
        VStack {
            Spacer()
            ContentUnavailableView {
                Label(scope == .trash ? "Thùng rác trống" : "Chưa có khoảnh khắc",systemImage:"photo.stack")
            } description: { Text(hasFilters ? "Thử thay đổi bộ lọc hoặc từ khóa." : "Chụp ảnh hoặc nhập ảnh để bắt đầu lưu giữ.") } actions: {
                if hasFilters { Button("Xóa bộ lọc") { resetFilters() }.buttonStyle(.bordered) }
                else { Button("Nhập ảnh") { importing=true }.buttonStyle(.borderedProminent) }
            }
            Spacer()
        }
    }
    private var gallery: some View {
        ScrollView {
            if scale == .day || selecting || compare {
                LazyVStack(alignment:.leading,spacing:14,pinnedViews:[.sectionHeaders]) {
                    ForEach(groups) { group in
                        Section {
                            if scale == .day && layout.hero && !selecting && !compare, let cover=group.items.first {
                                tile(cover,hero:true)
                                let rest=group.items.filter { $0.id != cover.id }
                                LazyVGrid(columns:columns,spacing:CGFloat(photoSpacing)) { ForEach(rest) { tile($0) } }
                            } else {
                                LazyVGrid(columns:columns,spacing:5) { ForEach(group.items) { tile($0) } }
                            }
                        } header: { dayHeader(group) }
                    }
                }.padding(.horizontal,12)
            } else {
                LazyVGrid(columns:coverColumns,spacing:12) {
                    ForEach(groups) { group in
                        Button {
                            period=group.key
                            scale = scale == .year ? .month : .day
                        } label: { collectionCard(group,title:TimelineIndex.label(group.key),icon:"calendar") }.buttonStyle(.plain)
                    }
                }.padding(.horizontal,14)
            }
        }.safeAreaPadding(.bottom,24)
        .simultaneousGesture(MagnifyGesture().onEnded{v in if !selecting && !compare {if v.magnification>1.22{columnCount=max(2,columnCount-1)}else if v.magnification<0.8{columnCount=min(5,columnCount+1)}}})
    }
    private func dayHeader(_ group: TimelineGroup) -> some View {
        HStack(alignment:.center) {
            Circle().fill(gold).frame(width:7,height:7)
            VStack(alignment:.leading,spacing:2) {
                Text(TimelineIndex.label(group.key)).font(.system(size:dateSize,weight:.medium,design:layout.font))
                let names=Set(group.items.map(\.session).filter{ !$0.isEmpty })
                if names.count == 1, let name=names.first { Text(name).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text("\(group.items.count) ảnh").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if selecting {
                Button("Chọn nhóm") { chosen.formUnion(group.items.map(\.id)) }.font(.caption)
            }
        }.padding(.vertical,10).padding(.horizontal,6).background(layout.background)
    }
    private func tile(_ shot: Shot,hero: Bool = false) -> some View {
        Button {
            if selecting || compare {
                if chosen.contains(shot.id) { chosen.remove(shot.id) }
                else if !compare || chosen.count < 2 { chosen.insert(shot.id) }
                if compare && chosen.count == 2 { pair=true }
            } else { UISelectionFeedbackGenerator().selectionChanged();selection=shot }
        } label: {
            Color.white.opacity(0.045).aspectRatio(hero ? layout.ratio : 1,contentMode:.fit)
                .overlay { DiskImage(url:hero ? model.vault.picture(shot) : model.vault.thumbnail(shot.id),limit:hero ? 1000 : 400).scaledToFill() }
                .clipped()
                .overlay(alignment:.bottomLeading) {
                    if hero && heroTitle {
                        VStack(alignment:.leading,spacing:4) {
                            Text(shot.session.isEmpty ? "Khoảnh khắc" : shot.session).font(.system(.headline,design:.serif))
                            Text(shot.tags.isEmpty ? shot.light.rawValue : shot.tags).font(.caption).lineLimit(1)
                        }.padding(13).frame(maxWidth:.infinity,alignment:.leading)
                            .background(LinearGradient(colors:[.clear,.black.opacity(0.75)],startPoint:.top,endPoint:.bottom))
                    }
                }
                .overlay(alignment:.topTrailing) {
                    if selecting || compare {
                        Image(systemName:chosen.contains(shot.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title2).foregroundStyle(chosen.contains(shot.id) ? gold : .white).shadow(radius:3).padding(7)
                    } else if shot.rating >= 4 { Image(systemName:"star.fill").font(.caption).foregroundStyle(gold).padding(8).shadow(radius:3) }
                }
                .clipShape(RoundedRectangle(cornerRadius:CGFloat(photoRadius)+(hero ? 6 : 0)))
                .overlay { if chosen.contains(shot.id) { RoundedRectangle(cornerRadius:5).strokeBorder(gold,lineWidth:2) } }
        }.buttonStyle(.plain).accessibilityLabel("Ảnh \(shot.day), \(shot.session), \(shot.rating) sao").accessibilityAddTraits(chosen.contains(shot.id) ? .isSelected : [])
    }
    private func collectionCard(_ group: TimelineGroup,title: String,icon: String) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Color.white.opacity(0.06).aspectRatio(0.95,contentMode:.fit)
                .overlay { DiskImage(url:model.vault.picture(group.cover),limit:700).scaledToFill() }.clipped()
                .overlay(alignment:.bottomLeading) {
                    VStack(alignment:.leading,spacing:4) {
                        Image(systemName:icon).font(.caption).foregroundStyle(gold)
                        Text(title).font(.system(size:21,weight:.medium,design:.serif)).lineLimit(2)
                        Text("\(group.items.count) ảnh").font(.caption).foregroundStyle(.white.opacity(0.85))
                    }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
                        .background(LinearGradient(colors:[.clear,.black.opacity(0.88)],startPoint:.top,endPoint:.bottom))
                }
                .clipShape(RoundedRectangle(cornerRadius:14))
        }
    }
    private var albumPage: some View {
        ScrollView {
            let albums=TimelineIndex.albums(active)
            VStack(alignment:.leading,spacing:12) {
                Text("Bộ sưu tập cá nhân").font(.system(.title2,design:.serif)).padding(.horizontal,16)
                let collections=TimelineIndex.collections(active)
                if collections.isEmpty {
                    Text("Chọn nhiều ảnh → Thao tác → Thêm vào bộ sưu tập. Một ảnh có thể nằm trong nhiều bộ sưu tập.").font(.caption).foregroundStyle(.secondary).padding(.horizontal,16)
                } else {
                    LazyVGrid(columns:coverColumns,spacing:12){
                        ForEach(collections){group in
                            VStack(alignment:.leading,spacing:5){
                            Button {resetFilters();collection=group.key;scale = .day;showAlbums=false} label:{collectionCard(group,title:group.key,icon:"heart.text.square")}.buttonStyle(.plain)
                            Button{collectionStory = .collection(group.key,shots:group.items)}label:{Label(stories.entry("collection:"+group.key) == nil ? "Viết chapter":"Đọc chapter",systemImage:"book.closed").font(.caption).foregroundStyle(gold)}.buttonStyle(.plain)
                            }
                        }
                    }.padding(.horizontal,14)
                }
                Text("Khám phá").font(.system(.title2,design:.serif)).padding(.horizontal,16)
                HStack {
                    Button {showCalendar=true} label:{Label("Lịch ảnh",systemImage:"calendar").frame(maxWidth:.infinity)}
                    Button {resetFilters();anniversary=TimelineIndex.todaySuffix();scale = .day;showAlbums=false} label:{Label("Ngày này",systemImage:"clock.arrow.circlepath").frame(maxWidth:.infinity)}
                }.buttonStyle(.bordered).padding(.horizontal,14)
                ForEach([TimelineScope.unorganized,.portraits,.imported],id:\.self){kind in
                    Button {resetFilters();scope=kind;scale = .day;showAlbums=false} label:{
                        HStack {Label(kind.rawValue,systemImage:"photo.on.rectangle");Spacer();Text("\(TimelineIndex.filter(active,scope:kind).count)");Image(systemName:"chevron.right")}.padding(12)
                    }.background(.white.opacity(0.065),in:RoundedRectangle(cornerRadius:12)).padding(.horizontal,14)
                }
                Text("Theo phiên chụp").font(.system(.title2,design:.serif)).padding(.horizontal,16)
                Text("Gom ảnh vào album bằng cách chọn nhiều ảnh và đặt tên phiên. Ảnh gốc vẫn được giữ nguyên.").font(.caption).foregroundStyle(.secondary).padding(.horizontal,16)
                if albums.isEmpty { ContentUnavailableView("Chưa có album",systemImage:"rectangle.stack.badge.plus",description:Text("Chọn ảnh trong dòng thời gian để tạo album.")) }
                else {
                    LazyVGrid(columns:coverColumns,spacing:12) {
                        ForEach(albums) { group in
                            Button {
                                resetFilters();session=group.key;scale = .day;showAlbums=false
                            } label: { collectionCard(group,title:group.key,icon:"rectangle.stack") }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal,14)
                }
                Button { resetFilters();scope = .picks;scale = .day;showAlbums=false } label: {
                    HStack { Label("Ảnh đã chọn (4–5 sao)",systemImage:"star.fill");Spacer();Text("\(active.filter{$0.rating>=4}.count)");Image(systemName:"chevron.right") }.padding(16)
                }.background(.white.opacity(0.065),in:RoundedRectangle(cornerRadius:14)).padding(.horizontal,14)
                Button { resetFilters();scope = .trash;scale = .day;showAlbums=false } label: {
                    HStack { Label("Thùng rác",systemImage:"trash");Spacer();Text("\(model.shots.filter{$0.deleted != nil}.count)");Image(systemName:"chevron.right") }.padding(16)
                }.background(.white.opacity(0.065),in:RoundedRectangle(cornerRadius:14)).padding(.horizontal,14)
            }.padding(.vertical,10)
        }
    }
    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Phạm vi") {
                    Picker("Loại ảnh",selection:$scope) { ForEach(TimelineScope.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
                    Picker("Phiên chụp",selection:$session) {
                        Text("Mọi phiên").tag("")
                        ForEach(Array(Set(model.shots.map(\.session).filter{ !$0.isEmpty })).sorted(),id:\.self) { Text($0).tag($0) }
                    }
                }
                Section("Thông tin ảnh") {
                    Picker("Chất màu",selection:$look){
                        Text("Tất cả").tag(nil as Look?)
                        ForEach(Look.allCases){Text($0.rawValue).tag(Optional($0))}
                    }
                    Picker("Ánh sáng",selection:$light) {
                        Text("Tất cả").tag(nil as Light?)
                        ForEach(Light.allCases,id:\.self) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    Picker("Xếp hạng tối thiểu",selection:$minimumRating) {
                        Text("Tất cả").tag(0)
                        ForEach(1...5,id:\.self) { Text("\($0) sao").tag($0) }
                    }
                    Toggle("Mới nhất trước",isOn:$newest)
                }
                Button("Đặt lại bộ lọc") { resetFilters() }
            }.navigationTitle("Bộ lọc ảnh").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Xong") { clearSelection();showAlbums=false;showFilters=false } }
        }.presentationDetents([.large])
    }
    private var selectionBar: some View {
        HStack(spacing:12) {
            Text(compare ? "\(chosen.count)/2 ảnh" : "\(chosen.count) đã chọn").font(.caption.weight(.semibold)).foregroundStyle(gold)
            Spacer(minLength:2)
            if !compare {
                Button("Tất cả") { chosen.formUnion(filtered.map(\.id)) }.font(.caption)
                Menu {
                    if scope != .trash {
                        Button("Thêm vào bộ sưu tập",systemImage:"heart.text.square"){batchKind="collection";batchText="";batchEdit=true}
                        if !collection.isEmpty {
                            Button("Đặt làm ảnh bìa",systemImage:"photo.artframe"){
                                if let id=selectedShots.first?.id{
                                    let name=collection
                                    Task{do{try await model.vault.setCollectionCover(name,id:id);await model.reload();clearSelection()}catch{model.message=error.localizedDescription}}
                                }
                            }.disabled(chosen.count != 1)
                            Button("Bỏ khỏi bộ sưu tập",systemImage:"minus.circle"){runBatch(removeCollection:collection)}
                        }
                        Button("Trình chiếu ảnh đã chọn",systemImage:"play.rectangle"){slideShots=selectedShots;slideshow=true}
                        Button("Đưa vào album",systemImage:"rectangle.stack.badge.plus") { batchKind="album";batchText="";batchEdit=true }
                        Button("Gắn nhãn",systemImage:"tag") { batchKind="tags";batchText="";batchEdit=true }
                        Button("Đánh dấu 5 sao",systemImage:"star") { runBatch(rating:5) }
                        Button("So sánh",systemImage:"rectangle.split.2x1") { pair=true }.disabled(chosen.count != 2)
                        ShareLink(items:selectedShots.map{model.vault.picture($0)}) { Label("Chia sẻ ảnh",systemImage:"square.and.arrow.up") }
                        Button("Chuyển vào thùng rác",systemImage:"trash",role:.destructive) { batchTrash=true }
                    } else {
                        Button("Phục hồi ảnh",systemImage:"arrow.uturn.backward") { runBatch(trash:false) }
                    }
                } label: { Label("Thao tác",systemImage:"ellipsis.circle").font(.caption.weight(.semibold)) }.disabled(chosen.isEmpty || working)
            }
            Button("Hủy") { clearSelection() }.font(.caption)
        }.padding(12).background(.white.opacity(0.055))
    }
    private var batchSheet: some View {
        NavigationStack {
            Form {
                TextField(batchKind == "tags" ? "Nhãn ảnh" : "Tên bộ sưu tập",text:$batchText)
                Text(batchKind == "collection" ? "Thêm vào \(chosen.count) ảnh, không thay thế bộ sưu tập cũ." : "Áp dụng cho \(chosen.count) ảnh. Giá trị cũ sẽ được thay thế.").font(.caption).foregroundStyle(.secondary)
            }.navigationTitle(batchKind == "tags" ? "Gắn nhãn" : "Bộ sưu tập")
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Hủy") { batchEdit=false } }
                    ToolbarItem(placement:.confirmationAction) {
                        Button("Lưu") {
                            let value=batchText.trimmingCharacters(in:.whitespacesAndNewlines)
                            batchEdit=false
                            if batchKind == "collection" {runBatch(addCollection:value)} else if batchKind == "album" { runBatch(session:value) } else { runBatch(tags:value) }
                        }.disabled(batchText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    }
                }
        }.presentationDetents([.medium])
    }
    private func runBatch(rating: Int?=nil,tags: String?=nil,session: String?=nil,trash: Bool?=nil,addCollection:String?=nil,removeCollection:String?=nil) {
        let ids=Array(chosen)
        working=true
        Task {
            defer { working=false;clearSelection() }
            var failures=0
            for id in ids {
                do { try await model.vault.edit(id,rating:rating,tags:tags,session:session,trash:trash,addCollection:addCollection,removeCollection:removeCollection) } catch { failures+=1 }
            }
            await model.reload()
            if failures>0 { model.message="Đã xử lý \(ids.count-failures)/\(ids.count) ảnh." }
        }
    }
    private func clearSelection() { selecting=false;compare=false;chosen=[] }
    private func resetFilters() { scope = .all;session="";period="";search="";light=nil;minimumRating=0;collection="";look=nil;anniversary="";clearSelection() }
}

private struct CompareView: View {
    let shots: [Shot]
    let vault: Vault
    @State private var zoom = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing:12) {
                Text("Đối chiếu từng chi tiết").font(.system(.title,design:.serif))
                GeometryReader { g in
                    HStack(spacing:3) {
                        ForEach(shots) { s in
                            DiskImage(url:vault.picture(s),limit:1800).scaledToFit()
                                .scaleEffect(zoom ? 2 : 1)
                                .frame(width:max(1,(g.size.width-3)/2),height:g.size.height)
                                .clipped()
                        }
                    }
                }
                HStack {
                    ForEach(shots) { s in
                        VStack { Text(TimelineIndex.label(s.day));Text("\(s.rating) sao · \(s.light.rawValue)").foregroundStyle(.secondary) }.font(.caption).frame(maxWidth:.infinity)
                    }
                }
                Button(zoom ? "Xem toàn ảnh" : "Phóng đại đồng thời 2×") { zoom.toggle() }.buttonStyle(.bordered).padding()
            }.background(night).navigationTitle("So sánh").navigationBarTitleDisplayMode(.inline).toolbar { Button("Xong") { dismiss() } }
        }
    }
}
private struct ShotDetail:View {
    @ObservedObject var model:LibraryModel
    let shots:[Shot]
    @State private var selectedID:UUID
    @ObservedObject private var storyArchive=StoryArchive.shared
    @State private var showPhotoStory=false
    @State private var showMetadata=false
    @State private var immersive=false
    @State private var showEditor=false
    init(model:LibraryModel,shot:Shot,shots:[Shot]) {
        self.model=model
        self.shots=shots.isEmpty ? [shot] : shots
        _selectedID=State(initialValue:shot.id)
    }
    var shot:Shot { shots.first{$0.id==selectedID} ?? shots[0] }
    @Environment(\.dismiss) private var dismiss
    @State private var original=false
    @State private var tags=""
    @State private var note=""
    @State private var session=""
    @State private var editing=false
    @State private var confirm=false
    @State private var notice:String?
    var current:Shot {model.shots.first{$0.id==shot.id} ?? shot}
    var body:some View {
        NavigationStack {
            VStack(spacing:12) {
                if !immersive && current.enhanced {Picker("Phiên bản",selection:$original){Text("Ảnh hoàn thiện").tag(false);Text("Bản gốc").tag(true)}.pickerStyle(.segmented).padding(.horizontal)}
                TabView(selection:$selectedID) {
                    ForEach(shots) { item in
                        ZoomPhoto(url:model.vault.picture(model.shots.first{$0.id==item.id} ?? item,original:original)).tag(item.id)
                    }
                }.tabViewStyle(.page(indexDisplayMode:.never))
                .frame(maxHeight:.infinity)
                .onAppear{MemoryVisitLog.mark(selectedID)}
                .onChange(of:selectedID){_,id in original=false;MemoryVisitLog.mark(id)}
                if !immersive {
                Text("\((shots.firstIndex{$0.id==selectedID} ?? 0)+1) / \(shots.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal,showsIndicators:false) {
                        LazyHStack(spacing:5) {
                            ForEach(shots){ item in
                                Button { selectedID=item.id } label: {
                                    DiskImage(url:model.vault.thumbnail(item.id),limit:120).scaledToFill().frame(width:46,height:46).clipped()
                                        .overlay { if item.id==selectedID { Rectangle().strokeBorder(gold,lineWidth:2) } }
                                }.buttonStyle(.plain).id(item.id)
                            }
                        }
                    }.frame(height:48)
                    .onAppear { proxy.scrollTo(selectedID,anchor:.center) }
                    .onChange(of:selectedID) { _,id in withAnimation(.easeOut(duration:0.2)){ proxy.scrollTo(id,anchor:.center) } }
                }.padding(.horizontal)

                VStack(spacing:6){
                    Text([current.light.rawValue,current.look.rawValue,current.lens].filter{!$0.isEmpty}.joined(separator:" · ")).font(.subheadline)
                    if !current.session.isEmpty || !current.tags.isEmpty {Text([current.session,current.tags].filter{!$0.isEmpty}.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)}
                    if let note=current.note,!note.isEmpty {Text(note).font(.caption).lineLimit(2)}
                    Button{showPhotoStory=true}label:{Label(storyArchive.entry(StoryTarget.photo(current).id) == nil ? "Viết story ảnh":"Đọc / sửa story ảnh",systemImage:"book.closed").font(.caption.weight(.semibold)).foregroundStyle(gold)}.disabled(current.deleted != nil)
                    HStack(spacing:2){ForEach(1...5,id:\.self){n in Button {Task{await model.edit(shot.id,rating:current.rating==n ? 0 : n)}} label:{Image(systemName:n<=current.rating ? "star.fill":"star").foregroundStyle(gold).frame(width:35,height:40)}.accessibilityLabel("\(n) sao")}}
                }
                HStack(spacing:18) {
                    Button {showEditor=true} label:{Image(systemName:"slider.horizontal.3")}.accessibilityLabel("Chỉnh màu ảnh").disabled(current.deleted != nil)
                    Button {showMetadata=true} label:{Image(systemName:"info.circle")}.accessibilityLabel("Thông tin EXIF")
                    ShareLink(item:model.vault.picture(current,original:original)){Image(systemName:"square.and.arrow.up")}.accessibilityLabel("Chia sẻ ảnh")
                    Button {saveToPhotos()} label:{Image(systemName:"square.and.arrow.down")}.accessibilityLabel("Lưu vào Ảnh Apple")
                    Button {tags=current.tags;session=current.session;note=current.note ?? "";editing=true} label:{Image(systemName:"tag")}.accessibilityLabel("Đổi nhãn và phiên")
                    Button {if current.deleted != nil {Task{await model.edit(shot.id,trash:false);dismiss()}} else {confirm=true}} label:{Image(systemName:current.deleted==nil ? "trash":"arrow.uturn.backward")}.accessibilityLabel(current.deleted==nil ? "Chuyển vào thùng rác":"Phục hồi")
                }.font(.title3).padding(.bottom,18)
                }
            }.navigationTitle(shot.day).navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.topBarLeading){Button{withAnimation(.easeInOut(duration:0.22)){immersive.toggle()}}label:{Image(systemName:immersive ? "rectangle.compress.vertical":"rectangle.expand.vertical")}.accessibilityLabel("Chế độ thưởng thức ảnh")};ToolbarItem(placement:.confirmationAction){Button("Xong"){dismiss()}}}
        }.sheet(isPresented:$showPhotoStory){let target=StoryTarget.photo(current);if storyArchive.entry(target.id) != nil{StoryReader(target:target,vault:model.vault,archive:storyArchive)}else{StoryComposer(target:target,vault:model.vault,archive:storyArchive)}}
        .sheet(isPresented:$showEditor){NavigationStack{CreativeStudio(shots:[current],vault:model.vault).toolbar{Button("Xong"){showEditor=false}}}}
        .sheet(isPresented:$showMetadata){PhotoMetadataView(shot:current,url:model.vault.picture(current,original:true))}
        .sheet(isPresented:$editing){NavigationStack{Form{TextField("Phiên chụp",text:$session);TextField("Nhãn ảnh",text:$tags);TextField("Nhật ký khoảnh khắc",text:$note,axis:.vertical)}.navigationTitle("Thông tin ảnh").toolbar{Button("Lưu"){Task{do{try await model.vault.edit(shot.id,tags:tags,session:session,note:note);await model.reload();editing=false}catch{notice=error.localizedDescription}}}}}.presentationDetents([.medium])}
        .confirmationDialog("Chuyển ảnh vào thùng rác trong 30 ngày?",isPresented:$confirm){Button("Chuyển vào thùng rác",role:.destructive){Task{await model.edit(shot.id,trash:true);dismiss()}}}
        .alert("VieLens",isPresented:Binding(get:{notice != nil || model.message != nil},set:{if !$0{notice=nil;model.message=nil}})){Button("Đóng"){notice=nil;model.message=nil}} message:{Text(notice ?? model.message ?? "")}
    }
    private func saveToPhotos() {
        let url=model.vault.picture(current,original:original),date=shot.date
        Task{
            let auth=await PHPhotoLibrary.requestAuthorization(for:.addOnly)
            guard auth == .authorized || auth == .limited else {notice="Hãy bật quyền thêm ảnh trong Cài đặt.";return}
            do {try await PHPhotoLibrary.shared().performChanges {
                let request=PHAssetCreationRequest.forAsset();request.creationDate=date
                request.addResource(with:.photo,fileURL:url,options:nil)
            };notice="Đã lưu vào Ảnh Apple."} catch {notice=error.localizedDescription}
        }
    }
}

private struct ZoomPhoto: View {
    let url:URL
    @State private var scale:CGFloat=1
    @State private var base:CGFloat=1
    @State private var offset:CGSize = .zero
    @State private var origin:CGSize = .zero
    var body:some View {
        GeometryReader { g in
            DiskImage(url:url,limit:3000).scaledToFit().frame(width:g.size.width,height:g.size.height)
                .scaleEffect(scale).offset(offset)
                .gesture(MagnifyGesture().onChanged { v in scale=min(4,max(1,base*v.magnification)) }
                    .onEnded { _ in base=scale;if scale==1 {offset = .zero;origin = .zero} })
                .simultaneousGesture(DragGesture().onChanged{ v in
                    if scale>1 { offset=CGSize(width:origin.width+v.translation.width,height:origin.height+v.translation.height) }
                }.onEnded{_ in
                    let x=g.size.width*(scale-1)/2,y=g.size.height*(scale-1)/2
                    offset=CGSize(width:min(x,max(-x,offset.width)),height:min(y,max(-y,offset.height)));origin=offset
                },including:scale>1 ? .all : .none)
                .onTapGesture(count:2){ withAnimation(.easeInOut(duration:0.2)){scale=scale>1 ? 1:2;base=scale;offset = .zero;origin = .zero} }
                .clipped()
        }.onChange(of:url){_,_ in scale=1;base=1;offset = .zero;origin = .zero}
    }
}
private struct PhotoMetadataView:View {
    let shot:Shot
    let url:URL
    @Environment(\.dismiss) private var dismiss
    @State private var entries:[Entry]=[]
    private struct Entry:Identifiable {
        let id:String
        let value:String
    }
    var body:some View {
        NavigationStack {
            List {
                Section("Lưu trữ") {
                    LabeledContent("Ngày gốc",value:shot.day)
                    LabeledContent("Thời điểm",value:shot.date.formatted(date:.abbreviated,time:.standard))
                    LabeledContent("Tệp",value:shot.sourceFile)
                    LabeledContent("Phiên",value:shot.session.isEmpty ? "Chưa phân loại" : shot.session)
                    LabeledContent("Màu",value:shot.look.rawValue)
                }
                Section("EXIF bản gốc") {
                    if entries.isEmpty {Text("Không có metadata đọc được ngoài thông tin lưu trữ.").foregroundStyle(.secondary)}
                    ForEach(entries){ row in LabeledContent(row.id,value:row.value) }
                }
            }.navigationTitle("Thông tin ảnh").navigationBarTitleDisplayMode(.inline).toolbar{Button("Xong"){dismiss()}}
        }.task {
            guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),
                  let props=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any] else{return}
            let exif=props[kCGImagePropertyExifDictionary as String] as? [String:Any] ?? [:]
            let tiff=props[kCGImagePropertyTIFFDictionary as String] as? [String:Any] ?? [:]
            var result=[Entry]()
            func append(_ label:String,_ value:Any?) { if let value {result.append(Entry(id:label,value:String(describing:value)))} }
            if let w=props[kCGImagePropertyPixelWidth as String],let h=props[kCGImagePropertyPixelHeight as String] {append("Độ phân giải","\(w) × \(h) px")}
            append("Thiết bị",tiff["Model"]);append("Ống kính",exif["LensModel"])
            append("Ngày EXIF",exif["DateTimeOriginal"]);append("Múi giờ",exif["OffsetTimeOriginal"])
            append("ISO",exif["ISOSpeedRatings"]);append("Khẩu độ",exif["FNumber"]);append("Phơi sáng (s)",exif["ExposureTime"])
            append("Tiêu cự (mm)",exif["FocalLength"])
            if let size=try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize {append("Dung lượng",ByteCountFormatter.string(fromByteCount:Int64(size),countStyle:.file))}
            entries=result
        }
    }
}
