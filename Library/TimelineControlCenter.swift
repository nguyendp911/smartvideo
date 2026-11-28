import SwiftUI

enum TimelineToolGroup:String,CaseIterable,Identifiable{
    case photo="Nhiếp ảnh & sáng tạo",time="Dòng thời gian",memory="Thế giới ký ức",life="Nhật ký cuộc đời",design="Thiết kế & cá nhân hóa",data="Dữ liệu & bảo mật"
    var id:String{rawValue}
}
enum TimelineTool:String,CaseIterable,Codable,Identifiable{
    case photoLab,signature,compare,slideshow,story,importPhotos,calendar,jump,anniversary,tree,slides,focus,gardens,portal,threads,world,discovery,search,box,journey,river,today,chapters,intelligence,letters,podcast,secret,memorySignature,gardenDesigner,vines,designer,lifeBackup,backup,restore
    var id:String{rawValue}
    var group:TimelineToolGroup{
        switch self{
        case .photoLab,.signature,.compare,.slideshow,.story,.importPhotos:return .photo
        case .calendar,.jump,.anniversary,.tree,.slides,.focus:return .time
        case .gardens,.portal,.threads,.world,.discovery,.search,.box,.journey,.river:return .memory
        case .today,.chapters,.intelligence,.letters,.podcast:return .life
        case .memorySignature,.gardenDesigner,.vines,.designer:return .design
        case .secret,.lifeBackup,.backup,.restore:return .data
        }
    }
    var title:String{
        switch self{
        case .photoLab:return "Photo Lab"
        case .signature:return "Signature Studio"
        case .compare:return "So sánh hai ảnh"
        case .slideshow:return "Trình chiếu"
        case .story:return "Story Studio"
        case .importPhotos:return "Nhập ảnh"
        case .calendar:return "Lịch ảnh"
        case .jump:return "Đi đến tháng/năm"
        case .anniversary:return "Ngày này qua các năm"
        case .tree:return "Cây thời gian"
        case .slides:return "Slide ký ức"
        case .focus:return "Timeline Focus"
        case .gardens:return "Khu vườn riêng"
        case .portal:return "Memory Portal"
        case .threads:return "Memory Threads"
        case .world:return "Memory World"
        case .discovery:return "Khám phá ký ức"
        case .search:return "Memory Search"
        case .box:return "Memory Box & Echo"
        case .journey:return "Life Journey"
        case .river:return "Memory River"
        case .today:return "Hôm nay của tôi"
        case .chapters:return "Life Chapters"
        case .intelligence:return "Memory Intelligence"
        case .letters:return "Thư tương lai"
        case .podcast:return "Memory Podcast"
        case .secret:return "Secret Letter"
        case .memorySignature:return "Memory Signature & hình nền"
        case .gardenDesigner:return "Vine Designer"
        case .vines:return "Bộ sưu tập dây leo"
        case .designer:return "Thiết kế Timeline"
        case .lifeBackup:return "Sao lưu nhật ký & cuộc đời"
        case .backup:return "Sao lưu vào Tệp"
        case .restore:return "Phục hồi từ thư mục"
        }
    }
    var icon:String{
        switch self{
        case .photoLab:return "slider.horizontal.3"
        case .signature:return "sparkles"
        case .compare:return "rectangle.split.2x1"
        case .slideshow:return "play.rectangle"
        case .story:return "book.closed"
        case .importPhotos:return "photo.badge.plus"
        case .calendar:return "calendar"
        case .jump:return "calendar.badge.clock"
        case .anniversary,.discovery:return "clock.arrow.circlepath"
        case .tree,.journey:return "point.topleft.down.to.point.bottomright.curvepath"
        case .slides:return "rectangle.on.rectangle"
        case .focus:return "arrow.up.left.and.arrow.down.right"
        case .gardens:return "heart.fill"
        case .portal:return "door.left.hand.open"
        case .threads:return "link"
        case .world:return "sparkles.rectangle.stack"
        case .search:return "magnifyingglass"
        case .box:return "shippingbox"
        case .river:return "water.waves"
        case .today:return "sun.max"
        case .chapters:return "book.pages"
        case .intelligence:return "sparkles"
        case .letters:return "envelope"
        case .podcast:return "waveform"
        case .secret:return "lock.envelope"
        case .memorySignature:return "signature"
        case .gardenDesigner:return "paintpalette"
        case .vines:return "leaf.fill"
        case .designer:return "paintbrush.pointed"
        case .lifeBackup:return "externaldrive"
        case .backup:return "square.and.arrow.up"
        case .restore:return "arrow.counterclockwise"
        }
    }
    var keywords:String{
        switch self{
        case .photoLab:return "hậu kỳ chỉnh ảnh màu preset AI masking mockup crop Lightroom"
        case .signature:return "studio collage cinema video sáng tạo"
        case .calendar:return "lịch âm ngày tháng ký ức"
        case .gardens,.gardenDesigner,.vines:return "vườn cây hoa dây leo botanical"
        case .backup,.lifeBackup,.restore:return "backup restore dữ liệu khôi phục"
        case .search:return "tìm ảnh câu chuyện"
        case .compare:return "đối chiếu trước sau"
        default:return title
        }
    }
    func matches(_ query:String)->Bool{
        let needle=query.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !needle.isEmpty else{return true}
        let options:String.CompareOptions=[.caseInsensitive,.diacriticInsensitive]
        func fold(_ text:String)->String{text.folding(options:options,locale:Locale(identifier:"vi_VN")).replacingOccurrences(of:"đ",with:"d").replacingOccurrences(of:"Đ",with:"D")}
        let hay=fold(title+" "+group.rawValue+" "+keywords)
        return fold(needle).split(whereSeparator:{$0.isWhitespace}).allSatisfy{hay.contains($0)}
    }
}
struct TimelineToolPreferences:Codable,Equatable{
    var pinned:[TimelineTool]=[.photoLab,.calendar,.importPhotos,.today]
    var recent:[TimelineTool]=[]
    mutating func toggle(_ tool:TimelineTool){
        if pinned.contains(tool){pinned.removeAll{$0==tool}}
        else if pinned.count<4{pinned.append(tool)}
    }
    mutating func used(_ tool:TimelineTool){
        recent.removeAll{$0==tool};recent.insert(tool,at:0);recent=Array(recent.prefix(6))
    }
    static func decode(_ data:Data)->Self{
        guard var p=try? JSONDecoder().decode(Self.self,from:data) else{return Self()}
        var seen=Set<TimelineTool>()
        p.pinned=Array(p.pinned.filter{seen.insert($0).inserted}.prefix(4))
        seen.removeAll()
        p.recent=Array(p.recent.filter{seen.insert($0).inserted}.prefix(6))
        return p
    }
}
struct TimelineControlCenter:View{
    @Binding var preferences:TimelineToolPreferences
    let available:(TimelineTool)->Bool
    let open:(TimelineTool)->Void
    let selectedCount:Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var query=""
    @State private var editing=false
    @FocusState private var searching:Bool
    private var columns:[GridItem]{Array(repeating:GridItem(.flexible(),spacing:9),count:typeSize.isAccessibilitySize ? 2:3)}
    var body:some View{
        VStack(spacing:0){
            header
            searchField
            ScrollView{
                LazyVStack(alignment:.leading,spacing:22){
                    if query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty{
                        sectionHeader("Truy cập nhanh",detail:"\(preferences.pinned.count)/4")
                        if preferences.pinned.isEmpty{Text("Ghim tối đa bốn công cụ bằng biểu tượng ngôi sao.").font(.caption).foregroundStyle(.secondary)}
                        else{grid(preferences.pinned)}
                        if !preferences.recent.isEmpty{sectionHeader("Vừa sử dụng",detail:nil);grid(preferences.recent)}
                    }
                    ForEach(TimelineToolGroup.allCases){group in
                        let tools=TimelineTool.allCases.filter{$0.group==group && $0.matches(query)}
                        if !tools.isEmpty{sectionHeader(group.rawValue,detail:nil);grid(tools)}
                    }
                    if !TimelineTool.allCases.contains(where:{$0.matches(query)}){
                        ContentUnavailableView("Không tìm thấy công cụ",systemImage:"magnifyingglass",description:Text("Thử tên khác, ví dụ hậu kỳ hoặc lịch ảnh."))
                    }
                }.padding(.horizontal,18).padding(.vertical,20)
            }.scrollDismissesKeyboard(.interactively)
        }.background(night).preferredColorScheme(.dark)
        .sheet(isPresented:$editing){pinEditor}
    }
    private var header:some View{
        HStack(alignment:.center){
            VStack(alignment:.leading,spacing:5){
                Text("V I E L E N S   /   T O O L S").font(.caption2.monospaced()).foregroundStyle(gold)
                Text("Control Center").font(.system(.largeTitle,design:.serif))
                Text(selectedCount>0 ? "\(selectedCount) ảnh đã chọn":"Mọi công cụ trong tầm tay").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button{editing=true}label:{Image(systemName:"slider.horizontal.3").frame(width:44,height:44).background(.white.opacity(0.08),in:Circle())}.accessibilityLabel("Sắp xếp lối tắt")
            Button{dismiss()}label:{Image(systemName:"xmark").frame(width:44,height:44).background(.white.opacity(0.08),in:Circle())}.accessibilityLabel("Đóng trung tâm công cụ")
        }.padding(.horizontal,18).padding(.vertical,12)
    }
    private var searchField:some View{
        HStack{
            Image(systemName:"magnifyingglass").foregroundStyle(.secondary)
            TextField("Tìm công cụ",text:$query).focused($searching).autocorrectionDisabled()
            if !query.isEmpty{Button{query=""}label:{Image(systemName:"xmark.circle.fill")}.accessibilityLabel("Xóa tìm kiếm")}
        }.padding(12).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:12)).padding(.horizontal,18)
    }
    private func sectionHeader(_ title:String,detail:String?)->some View{
        HStack{Text(title).font(.system(.headline,design:.serif)).foregroundStyle(gold);Spacer();if let detail{Text(detail).font(.caption).foregroundStyle(.secondary)}}
    }
    private func grid(_ tools:[TimelineTool])->some View{
        LazyVGrid(columns:columns,spacing:9){ForEach(tools){tool in tile(tool)}}
    }
    private func tile(_ tool:TimelineTool)->some View{
        let enabled=available(tool),pinned=preferences.pinned.contains(tool)
        return VStack(spacing:0){
            Button{searching=false;open(tool)}label:{
                VStack(spacing:9){
                    Image(systemName:tool.icon).font(.system(size:23,weight:.medium)).foregroundStyle(gold).frame(height:34)
                    Text(tool.title).font(.caption.weight(.medium)).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                }.frame(maxWidth:.infinity,minHeight:80).padding(.horizontal,5).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1:0.40)
            Button{preferences.toggle(tool)}label:{
                Image(systemName:pinned ? "star.fill":"star").font(.system(size:13)).foregroundStyle(pinned ? gold:Color.secondary).frame(maxWidth:.infinity,minHeight:32)
            }.buttonStyle(.plain).disabled(!pinned && preferences.pinned.count>=4).accessibilityLabel(pinned ? "Bỏ ghim \(tool.title)":"Ghim \(tool.title)")
        }.background(.white.opacity(0.055),in:RoundedRectangle(cornerRadius:14))
    }
    private var pinEditor:some View{
        NavigationStack{
            List{
                Section("Kéo để đổi thứ tự"){
                    ForEach(preferences.pinned){tool in Label(tool.title,systemImage:tool.icon)}
                        .onMove{from,to in preferences.pinned.move(fromOffsets:from,toOffset:to)}
                        .onDelete{preferences.pinned.remove(atOffsets:$0)}
                }
                Section("Công cụ chưa ghim"){
                    ForEach(TimelineTool.allCases.filter{!preferences.pinned.contains($0)}){tool in
                        Button{preferences.toggle(tool)}label:{Label(tool.title,systemImage:"plus.circle")}.disabled(preferences.pinned.count>=4)
                    }
                }
            }.environment(\.editMode,.constant(.active)).navigationTitle("Lối tắt").navigationBarTitleDisplayMode(.inline)
                .toolbar{Button("Xong"){editing=false}}
        }.presentationDetents([.large])
    }
}
