import SwiftUI
import LocalAuthentication
import CryptoKit
import Security

enum MemoryKind:String,CaseIterable,Codable {
    case magazine="Memory Magazine",life="Life Timeline",couple="Couple Timeline",family="Family Heritage",daily="Daily Moments",capsule="Time Capsule",people="People Stories",mood="Mood Collection"
    var icon:String{
        switch self{case .magazine:return "book.closed";case .life:return "flag";case .couple:return "heart";case .family:return "person.3";case .daily:return "sun.max";case .capsule:return "clock";case .people:return "person.crop.circle";case .mood:return "sparkles"}
    }
}
struct MemoryRecord:Codable,Identifiable {
    var id=UUID()
    var kind:MemoryKind
    var title:String
    var note:String
    var date:Date
    var unlock:Date?
    var photos:[UUID]
    var cover:UUID?
    var locked:Bool{unlock.map{$0>Date()} ?? false}
}
struct SignatureHub:View {
    @ObservedObject var model:LibraryModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("signature.memories.v1") private var stored=Data()
    @State private var records=[MemoryRecord]()
    @State private var chosen=Set<UUID>()
    @State private var selectPhotos=false
    @State private var createKind:MemoryKind?
    @State private var selectedRecord:MemoryRecord?
    @State private var showDelete=false
    @State private var removeID:UUID?
    private var active:[Shot]{model.shots.filter{$0.deleted==nil}}
    private var selected:[Shot]{active.filter{chosen.contains($0.id)}}
    private var input:[Shot]{chosen.isEmpty ? Array(active.prefix(60)):selected}
    var body:some View{
        NavigationStack{
            ScrollView{
                VStack(alignment:.leading,spacing:20){
                    header
                    Button{selectPhotos=true}label:{
                        HStack{Image(systemName:"checkmark.circle");Text(chosen.isEmpty ? "Chọn ảnh cho Studio":"\(chosen.count) ảnh đã chọn");Spacer();Image(systemName:"chevron.right")}
                            .padding(14).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:12))
                    }.buttonStyle(.plain)
                    Text(chosen.isEmpty ? "Nếu chưa chọn, công cụ sáng tạo dùng tối đa 60 ảnh mới nhất. Công cụ phân tích và bản đồ dùng thư viện hiện tại.":"Các công cụ sáng tạo dùng ảnh đã chọn.").font(.caption).foregroundStyle(.secondary)
                    section("Miền ký ức")
                    memoryGrid
                    section("Khám phá thông minh")
                    discovery
                    section("Xưởng sáng tạo")
                    creative
                    section("Riêng tư")
                    NavigationLink{EncryptedMemoryVault(shots:input,vault:model.vault)}label:{module("Private Vault","Bản sao mã hóa, khóa xác thực thiết bị","lock.shield")}.buttonStyle(.plain)
                    section("Những câu chuyện đã lưu")
                    if records.isEmpty{Text("Tạo câu chuyện đầu tiên từ những ảnh đã chọn.").font(.caption).foregroundStyle(.secondary)}
                    ForEach(records.sorted{$0.date>$1.date}){record in
                        Button{selectedRecord=record}label:{recordRow(record)}.buttonStyle(.plain)
                            .contextMenu{Button("Xóa câu chuyện",role:.destructive){removeID=record.id;showDelete=true}}
                    }
                }.padding(16)
            }.background(night).navigationTitle("Signature Studio").navigationBarTitleDisplayMode(.inline)
                .toolbar{Button("Xong"){dismiss()}}
        }
        .onAppear{records=(try? JSONDecoder().decode([MemoryRecord].self,from:stored)) ?? []}
        .sheet(isPresented:$selectPhotos){PhotoChoice(shots:active,vault:model.vault,selected:$chosen)}
        .sheet(isPresented:Binding(get:{createKind != nil},set:{if !$0{createKind=nil}})){
            if let kind=createKind{
                MemoryComposer(kind:kind,shots:input,vault:model.vault){record in records.append(record);persist();createKind=nil}
            }
        }
        .sheet(item:$selectedRecord){record in
            NavigationStack{
                MemoryReader(record:record,shots:active,vault:model.vault)
                    .toolbar{Button("Đóng"){selectedRecord=nil}}
            }
        }
        .confirmationDialog("Xóa câu chuyện? Ảnh gốc không bị xóa.",isPresented:$showDelete){
            Button("Xóa",role:.destructive){if let removeID{records.removeAll{$0.id==removeID};persist()}}
        }
    }
    private func persist(){if let data=try? JSONEncoder().encode(records){stored=data}}
    private var header:some View{
        VStack(alignment:.leading,spacing:6){
            Text("V I E L E N S   /   S I G N A T U R E").font(.caption2.monospaced()).foregroundStyle(gold)
            Text("Miền ký ức").font(.system(size:38,design:.serif))
            Text("Mỗi khoảnh khắc, một câu chuyện.").font(.subheadline).foregroundStyle(.secondary)
            if let shot=active.first{
                DiskImage(url:model.vault.picture(shot),limit:1100).scaledToFill().frame(height:190).clipped().clipShape(RoundedRectangle(cornerRadius:16))
            }
        }
    }
    private func section(_ title:String)->some View{Text(title).font(.system(.title2,design:.serif))}
    private func module(_ title:String,_ subtitle:String,_ icon:String)->some View{
        HStack(alignment:.center,spacing:12){
            Image(systemName:icon).font(.title2).foregroundStyle(gold).frame(width:42,height:42)
            VStack(alignment:.leading,spacing:3){Text(title).font(.headline);Text(subtitle).font(.caption).foregroundStyle(.secondary)}
            Spacer(minLength:0);Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.055),in:RoundedRectangle(cornerRadius:13))
    }
    private var memoryGrid:some View{
        VStack(spacing:7){
            ForEach(MemoryKind.allCases,id:\.self){kind in
                Button{createKind=kind}label:{module(kind.rawValue,description(kind),kind.icon)}.buttonStyle(.plain).disabled(input.isEmpty)
            }
        }
    }
    private func description(_ kind:MemoryKind)->String{
        switch kind{
        case .magazine:return "Tạp chí ảnh có tiêu đề và ảnh bìa"
        case .life:return "Cột mốc cuộc đời"
        case .couple:return "Câu chuyện dành cho hai người"
        case .family:return "Lưu giữ chuyện gia đình"
        case .daily:return "Nhật ký và cảm xúc trong ngày"
        case .capsule:return "Đặt ngày mở ký ức"
        case .people:return "Nhóm ảnh theo người do bạn đặt tên"
        case .mood:return "Bộ sưu tập cảm xúc do bạn chọn"
        }
    }
    private var discovery:some View{
        VStack(spacing:7){
            NavigationLink{SignatureIntelligence(shots:active,vault:model.vault)}label:{module("Photo Intelligence","Tìm nội dung, chất lượng, ảnh gần giống, dung lượng","viewfinder")}.buttonStyle(.plain)
            NavigationLink{SignatureAtlas(shots:active,vault:model.vault)}label:{module("Memory Atlas","Bản đồ GPS từ ảnh gốc","map")}.buttonStyle(.plain)
            NavigationLink{SmartEventsView(shots:active,vault:model.vault)}label:{module("Smart Event","Nhóm ảnh theo thời điểm chụp","calendar.badge.clock")}.buttonStyle(.plain)
            NavigationLink{ThenNowView(shots:input,vault:model.vault)}label:{module("Then & Now","So sánh hai ảnh bằng thanh trượt","rectangle.split.2x1")}.buttonStyle(.plain).disabled(input.count<2)
        }
    }
    private var creative:some View{
        VStack(spacing:7){
            NavigationLink{CreativeStudio(shots:input,vault:model.vault)}label:{module("Photo Editor / Color Studio","Chỉnh màu, preset, xuất hàng loạt","slider.horizontal.3")}.buttonStyle(.plain).disabled(input.isEmpty)
            NavigationLink{CollageStudio(shots:input,vault:model.vault)}label:{module("Photo Collage","Ghép ảnh và xuất JPEG","square.grid.2x2")}.buttonStyle(.plain).disabled(input.isEmpty)
            NavigationLink{MemoryCinema(shots:input,vault:model.vault)}label:{module("Memory Cinema","Xuất phim ảnh 1080p / 4K","film")}.buttonStyle(.plain).disabled(input.isEmpty)
            NavigationLink{ArchiveSlideshow(shots:input,vault:model.vault)}label:{module("Immersive Slideshow","Trình chiếu toàn màn hình","play.rectangle")}.buttonStyle(.plain).disabled(input.isEmpty)
        }
    }
    private func recordRow(_ record:MemoryRecord)->some View{
        HStack{
            if !record.locked,let cover=record.cover ?? record.photos.first,let shot=active.first(where:{$0.id==cover}){
                DiskImage(url:model.vault.thumbnail(shot.id),limit:180).scaledToFill().frame(width:64,height:64).clipped().clipShape(RoundedRectangle(cornerRadius:8))
            }else{Image(systemName:record.locked ? "lock":record.kind.icon).font(.title2).frame(width:64,height:64)}
            VStack(alignment:.leading){Text(record.title).font(.headline);Text("\(record.kind.rawValue) · \(record.photos.count) ảnh").font(.caption).foregroundStyle(.secondary)}
            Spacer();Image(systemName:"chevron.right").font(.caption)
        }.padding(9).background(.white.opacity(0.055),in:RoundedRectangle(cornerRadius:12))
    }
}
private struct PhotoChoice:View{
    let shots:[Shot];let vault:Vault
    @Binding var selected:Set<UUID>
    @Environment(\.dismiss) private var dismiss
    var body:some View{
        NavigationStack{
            ScrollView{
                LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:5),count:3),spacing:5){
                    ForEach(shots){s in
                        Button{if selected.contains(s.id){selected.remove(s.id)}else{selected.insert(s.id)}}label:{
                            Color.clear.aspectRatio(1,contentMode:.fit).overlay{DiskImage(url:vault.thumbnail(s.id),limit:300).scaledToFill()}.clipped().overlay(alignment:.topTrailing){
                                Image(systemName:selected.contains(s.id) ? "checkmark.circle.fill":"circle").foregroundStyle(selected.contains(s.id) ? gold:.white).padding(6)
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding(8)
            }.navigationTitle("\(selected.count) ảnh").toolbar{
                ToolbarItem(placement:.cancellationAction){Button("Bỏ chọn"){selected=[]}}
                ToolbarItem(placement:.confirmationAction){Button("Xong"){dismiss()}}
            }
        }
    }
}
private struct MemoryComposer:View{
    let kind:MemoryKind
    let shots:[Shot]
    let vault:Vault
    let save:(MemoryRecord)->Void
    @Environment(\.dismiss) private var dismiss
    @State private var title=""
    @State private var note=""
    @State private var date=Date()
    @State private var unlock=Date().addingTimeInterval(86400*30)
    @State private var cover:UUID?
    var body:some View{
        NavigationStack{
            Form{
                Section("Câu chuyện"){
                    TextField("Tiêu đề",text:$title)
                    TextField("Lời nhắn / nội dung",text:$note,axis:.vertical).lineLimit(3...8)
                    DatePicker("Ngày kỷ niệm",selection:$date,displayedComponents:.date)
                    if kind == .capsule{
                        DatePicker("Ngày mở",selection:$unlock,in:Date()...,displayedComponents:.date)
                        Text("Chỉ khóa giao diện câu chuyện tới ngày đã chọn; ảnh vẫn tồn tại trong thư viện, không phải kho bảo mật.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Ảnh bìa"){
                    ScrollView(.horizontal){
                        HStack{ForEach(shots){s in Button{cover=s.id}label:{
                            DiskImage(url:vault.thumbnail(s.id),limit:160).scaledToFill().frame(width:75,height:75).clipped().overlay{if cover==s.id{Rectangle().strokeBorder(gold,lineWidth:3)}}
                        }.buttonStyle(.plain)}}
                    }
                }
            }.navigationTitle(kind.rawValue).toolbar{
                ToolbarItem(placement:.cancellationAction){Button("Hủy"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button("Lưu"){
                    save(MemoryRecord(kind:kind,title:title.trimmingCharacters(in:.whitespacesAndNewlines),note:note,date:date,unlock:kind == .capsule ? unlock:nil,photos:shots.map(\.id),cover:cover ?? shots.first?.id))
                }.disabled(title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || shots.isEmpty)}
            }
        }
    }
}
struct MemoryReader:View{
    let record:MemoryRecord
    let shots:[Shot]
    let vault:Vault
    private var items:[Shot]{record.photos.compactMap{id in shots.first{$0.id==id}}}
    var body:some View{
        ScrollView{
            VStack(alignment:.leading,spacing:14){
                if record.locked{
                    ContentUnavailableView("Ký ức đang đóng",systemImage:"lock",description:Text("Mở vào \(record.unlock?.formatted(date:.long,time:.omitted) ?? "")"))
                }else{
                    if let cover=items.first(where:{$0.id==record.cover}) ?? items.first{
                        DiskImage(url:vault.picture(cover),limit:1400).scaledToFill().frame(height:280).clipped().clipShape(RoundedRectangle(cornerRadius:16))
                    }
                    Text(record.title).font(.system(size:36,design:.serif))
                    Text(record.date.formatted(date:.long,time:.omitted)).font(.caption).foregroundStyle(gold)
                    Text(record.note).font(.body)
                    ForEach(items){shot in
                        VStack(alignment:.leading,spacing:5){
                            DiskImage(url:vault.picture(shot),limit:1100).scaledToFit().frame(maxWidth:.infinity).clipShape(RoundedRectangle(cornerRadius:10))
                            Text(shot.note ?? TimelineIndex.label(shot.day)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }.padding(16)
        }.navigationTitle(record.kind.rawValue).navigationBarTitleDisplayMode(.inline)
    }
}
private struct SmartEventsView:View{
    let shots:[Shot];let vault:Vault
    var body:some View{
        List(SignatureIndex.events(shots)){event in
            NavigationLink{
                ScrollView{LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:5),count:2)){ForEach(event.shots){s in DiskImage(url:vault.thumbnail(s.id),limit:400).scaledToFill().frame(height:150).clipped()}}.padding()}.navigationTitle(event.title)
            }label:{
                HStack{
                    if let first=event.shots.first{DiskImage(url:vault.thumbnail(first.id),limit:160).scaledToFill().frame(width:72,height:72).clipped()}
                    VStack(alignment:.leading){Text(event.title);Text("\(event.shots.count) ảnh · cách nhau tối đa 2 giờ").font(.caption).foregroundStyle(.secondary)}
                }
            }
        }.navigationTitle("Smart Event")
    }
}
private struct ThenNowView:View{
    let shots:[Shot];let vault:Vault
    @State private var first=0
    @State private var second=1
    @State private var fraction=0.5
    var body:some View{
        VStack{
            if shots.count>1{
                Picker("Trước",selection:$first){ForEach(shots.indices,id:\.self){i in Text("\(i+1) · \(shots[i].day)").tag(i)}}
                Picker("Sau",selection:$second){ForEach(shots.indices,id:\.self){i in Text("\(i+1) · \(shots[i].day)").tag(i)}}
                GeometryReader{g in
                    ZStack(alignment:.leading){
                        DiskImage(url:vault.picture(shots[second]),limit:1500).scaledToFit().frame(width:g.size.width,height:g.size.height)
                        DiskImage(url:vault.picture(shots[first]),limit:1500).scaledToFit().frame(width:g.size.width,height:g.size.height)
                            .mask(alignment:.leading){Rectangle().frame(width:g.size.width*fraction)}
                        Rectangle().fill(gold).frame(width:2).offset(x:g.size.width*fraction)
                    }.clipped()
                }
                Slider(value:$fraction,in:0...1).padding()
            }
        }.navigationTitle("Then & Now")
    }
}
