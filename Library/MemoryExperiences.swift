import SwiftUI
import UIKit
import AVFoundation
import LocalAuthentication
import CryptoKit
import Security

enum MemoryPortalIndex{
    static func prompt(_ day:String)->String{
        let options=["Điều gì làm bạn mỉm cười hôm nay?","Bạn muốn cảm ơn ai?","Khoảnh khắc nào bạn muốn nhớ mãi?","Hôm nay bạn đã học được gì?","Nếu gửi một lời nhắn cho mình tương lai, bạn sẽ viết gì?","Điều nhỏ bé nào khiến hôm nay khác biệt?","Bạn muốn giữ lại cảm xúc nào?"]
        return options[Int(UInt(bitPattern:NaturalSample.seed(day)) % UInt(options.count))]
    }
    static func sameDay(_ day:String,shots:[Shot])->[Shot]{shots.filter{$0.day.suffix(5)==day.suffix(5)}}
}
struct MemoryPortalView:View{
    let shots:[Shot];let vault:Vault
    @ObservedObject private var archive=StoryArchive.shared
    @ObservedObject private var life=LifeArchive.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var date=Date()
    @State private var opened=false
    @State private var target:StoryTarget?
    @State private var playing=false
    private var day:String{LifeDate.key(date)}
    private var items:[Shot]{shots.filter{$0.day==day}}
    var body:some View{
        NavigationStack{ScrollView{
            VStack(spacing:18){
                DatePicker("Trở về ngày",selection:$date,displayedComponents:.date).onChange(of:date){_,_ in opened=false}
                ZStack{
                    Circle().strokeBorder(gold.opacity(0.4),lineWidth:2).frame(width:228,height:228)
                    if let cover=MemorySync.cover(items,entry:archive.entry("period:"+day)),opened{
                        DiskImage(url:vault.picture(cover),limit:900).scaledToFill().frame(width:220,height:220).clipShape(Circle()).transition(.scale(scale:0.2).combined(with:.opacity))
                    }else{
                        Circle().fill(RadialGradient(colors:[gold.opacity(0.35),night],center:.center,startRadius:5,endRadius:110)).frame(width:220,height:220)
                        Image(systemName:"door.left.hand.closed").font(.system(size:55,weight:.thin)).foregroundStyle(gold)
                    }
                    Image("botanical_bloom").resizable().scaledToFit().frame(width:65,height:230).offset(x:-108).allowsHitTesting(false)
                    Image("botanical_bloom").resizable().scaledToFit().frame(width:65,height:230).scaleEffect(x:-1,y:1).offset(x:108).allowsHitTesting(false)
                }.frame(height:248)
                Button(opened ? "Đóng cánh cổng":"Mở cánh cổng"){withAnimation(reduced ? nil:.easeInOut(duration:0.8)){opened.toggle()}}.buttonStyle(.borderedProminent)
                if opened{
                    Text(TimelineIndex.label(day)).font(.system(.title,design:.serif))
                    Text(archive.entry("period:"+day)?.body ?? "Chưa có nhật ký ngày này.").font(.body)
                    Button("Đọc / viết story"){target=MemorySync.target(day:day,shots:shots)}
                    Button("Phát hành trình ngày"){playing=true}.disabled(items.isEmpty)
                    MemoryDNAChips(day:day,shots:items,vault:vault,archive:archive,life:life)
                    ForEach(items){s in Button{target = .photo(s)}label:{DiskImage(url:vault.picture(s),limit:900).scaledToFit().clipShape(RoundedRectangle(cornerRadius:12))}.buttonStyle(.plain)}
                }
            }.padding()
        }.background(night).navigationTitle("Memory Portal").toolbar{Button("Đóng"){dismiss()}}}
        .sheet(item:$target){LifeStorySheet(target:$0,vault:vault,archive:archive)}
        .fullScreenCover(isPresented:$playing){ArchiveSlideshow(shots:items,vault:vault)}
    }
}
struct MemoryThreadsView:View{
    let shots:[Shot];let vault:Vault
    @ObservedObject private var life=LifeArchive.shared
    @ObservedObject private var archive=StoryArchive.shared
    @Environment(\.dismiss) private var dismiss
    @State private var title=""
    @State private var selected=Set<String>()
    @State private var active:MemoryThread?
    @State private var notice=""
    private var days:[String]{MemorySync.activeDays(shots:shots,stories:archive,life:life).sorted(by:>)}
    var body:some View{
        NavigationStack{List{
            Section("Kết nối ký ức"){
                TextField("Tên sợi dây",text:$title)
                ForEach(days,id:\.self){d in Button{if selected.contains(d){selected.remove(d)}else{selected.insert(d)}}label:{HStack{Text(TimelineIndex.label(d));Spacer();Image(systemName:selected.contains(d) ? "checkmark.circle.fill":"circle")}}.buttonStyle(.plain)}
                Button("Tạo liên kết"){do{try life.update{p in var e=p.ecosystem ?? EcosystemData();e.threads.append(MemoryThread(title:title,days:selected));p.ecosystem=e};title="";selected=[]}catch{notice=error.localizedDescription}}.disabled(title.isEmpty || selected.count<2)
            }
            Section("Sợi dây đã lưu"){
                ForEach(life.data.ecosystem?.threads ?? []){t in Button{active=t}label:{Label(t.title+" · \(t.days.count) ngày",systemImage:"link")}.swipeActions{Button("Xóa",role:.destructive){do{try life.update{$0.ecosystem?.threads.removeAll{$0.id==t.id}}}catch{notice=error.localizedDescription}}}}
            }
            Text(notice).font(.caption)
        }.navigationTitle("Memory Threads").toolbar{Button("Xong"){dismiss()}}}
        .sheet(item:$active){t in ThreadDetail(thread:t,shots:shots,vault:vault)}
    }
}
private struct ThreadDetail:View{
    let thread:MemoryThread;let shots:[Shot];let vault:Vault
    @ObservedObject private var archive=StoryArchive.shared
    @Environment(\.dismiss) private var dismiss
    @State private var target:StoryTarget?
    var body:some View{
        NavigationStack{ScrollView{VStack(alignment:.leading,spacing:12){
            ForEach(thread.days.sorted(),id:\.self){d in HStack{
                VineRail(level:0,theme:.emerald,growth:VineGrowth(days:90)).frame(width:35,height:90)
                Button{target=MemorySync.target(day:d,shots:shots)}label:{VStack(alignment:.leading){Text(TimelineIndex.label(d)).font(.headline);Text(archive.entry("period:"+d)?.title ?? "Ký ức").font(.caption)}}.buttonStyle(.plain)
            }}
        }.padding()}.navigationTitle(thread.title).toolbar{Button("Đóng"){dismiss()}}}.sheet(item:$target){LifeStorySheet(target:$0,vault:vault,archive:archive)}
    }
}
struct CalendarExtras:View{
    let day:String;let shots:[Shot];let vault:Vault
    @ObservedObject private var archive=StoryArchive.shared
    @ObservedObject private var life=LifeArchive.shared
    @State private var gratitude=""
    @State private var title=""
    @State private var due=Date().addingTimeInterval(86400)
    @State private var notice=""
    @State private var target:StoryTarget?
    @State private var compare=false
    @State private var year=false
    @State private var poster:URL?
    var body:some View{
        GroupBox("Ký ức mỗi ngày"){
            VStack(alignment:.leading,spacing:12){
                Text(MemoryPortalIndex.prompt(day)).font(.system(.headline,design:.serif))
                Button("Viết câu trả lời"){target=MemorySync.target(day:day,shots:shots)}
                TextField("Điều tôi biết ơn",text:$gratitude,axis:.vertical)
                Button("Lưu biết ơn"){saveGratitude()}.disabled(gratitude.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                ForEach((life.data.ecosystem?.threads ?? []).filter{$0.days.contains(day)}){thread in NavigationLink{ThreadDetail(thread:thread,shots:shots,vault:vault)}label:{Label(thread.title+" · \(thread.days.count) ngày",systemImage:"link")}}
                Button("Cùng ngày qua nhiều năm"){compare=true}
                Button("365 ngày ký ức"){year=true}
                Button("Tạo poster tháng"){makePoster()}
                if let poster{ShareLink(item:poster){Label("Lưu poster",systemImage:"square.and.arrow.up")}}
                Divider()
                TextField("Sự kiện sắp đến",text:$title)
                DatePicker("Ngày sự kiện",selection:$due,in:Date()...)
                Button("Thêm đếm ngược"){do{try life.update{p in var e=p.ecosystem ?? EcosystemData();e.countdowns.append(LifeCountdown(title:title,date:due));p.ecosystem=e};title=""}catch{notice=error.localizedDescription}}.disabled(title.isEmpty)
                ForEach((life.data.ecosystem?.countdowns ?? []).sorted{$0.date<$1.date}){c in HStack{
                    VStack(alignment:.leading){Text(c.title);Text(c.date,style:.relative).font(.caption).foregroundStyle(gold)}
                    Spacer();Button(role:.destructive){do{try life.update{$0.ecosystem?.countdowns.removeAll{$0.id==c.id}}}catch{notice=error.localizedDescription}}label:{Image(systemName:"trash")}
                }}
                Text(notice).font(.caption)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }.sheet(item:$target){LifeStorySheet(target:$0,vault:vault,archive:archive)}
        .sheet(isPresented:$compare){NavigationStack{ScrollView{LazyVStack{ForEach(MemoryPortalIndex.sameDay(day,shots:shots)){s in Text(s.day).font(.headline);DiskImage(url:vault.picture(s),limit:900).scaledToFit()}}.padding()}.navigationTitle("Cùng ngày qua các năm").toolbar{Button("Đóng"){compare=false}}}}
        .sheet(isPresented:$year){LifeReflection(range:.rolling(LifeDate.date(day) ?? Date()),shots:shots,vault:vault)}
    }
    private func saveGratitude(){
        let id="period:"+day
        var e=archive.entry(id) ?? StoryEntry(id:id)
        let draft=archive.drafts[id]
        e.body += (e.body.isEmpty ? "":"\n\n")+"Biết ơn: "+gratitude
        do{try archive.save(e,draft:false);if var draft{draft.body += (draft.body.isEmpty ? "":"\n\n")+"Biết ơn: "+gratitude;try archive.save(draft,draft:true)};gratitude="";notice="Đã lưu vào nhật ký."}catch{notice=error.localizedDescription}
    }
    private func makePoster(){
        let items=Array(shots.filter{$0.day.hasPrefix(String(day.prefix(7)))}.prefix(12))
        let renderer=ImageRenderer(content:VStack(alignment:.leading,spacing:12){
            Text("V I E L E N S").font(.caption.monospaced()).foregroundStyle(gold)
            Text(TimelineIndex.label(String(day.prefix(7)))).font(.system(size:30,design:.serif))
            LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:3),spacing:4){ForEach(items){s in
                if let im=UIImage(contentsOfFile:vault.thumbnail(s.id).path){Image(uiImage:im).resizable().scaledToFill().frame(height:100).clipped()}
            }}
            Text("\(items.count) khoảnh khắc · Miền ký ức").font(.caption)
        }.padding(20).frame(width:360).background(night).foregroundStyle(.white))
        renderer.scale=3
        do{guard let png=renderer.uiImage?.pngData() else{throw CameraError.writeFailed};poster=try CreativeEngine.exportURL(png,extension:"png")}catch{notice=error.localizedDescription}
    }
}
struct MemorySignatureView:View{
    let shots:[Shot];let vault:Vault
    @ObservedObject private var life=LifeArchive.shared
    @Environment(\.dismiss) private var dismiss
    @State private var output:URL?
    @State private var notice=""
    @State private var theme=VineTheme.emerald
    @State private var name=""
    @State private var movie:URL?
    @State private var exporting=false
    private var art:some View{
        ZStack{
            LinearGradient(colors:[night,Color(red:0.10,green:0.22,blue:0.14)],startPoint:.top,endPoint:.bottom)
            Image(BotanicalAssets.rail(theme:theme,age:VineGrowth(days:life.gardenDays))).resizable().scaledToFit().frame(width:120,height:320).rotationEffect(.degrees(-13)).offset(x:-80,y:-40)
            Image(BotanicalAssets.rail(theme:theme,age:VineGrowth(days:life.gardenDays))).resizable().scaledToFit().frame(width:120,height:320).scaleEffect(x:-1,y:1).rotationEffect(.degrees(13)).offset(x:80,y:-40)
            VStack(spacing:10){Text("M I Ề N  K Ý  Ứ C").font(.caption2.monospaced()).foregroundStyle(gold);Text(name.isEmpty ? "VieLens":name).font(.system(size:38,design:.serif));Text("\(life.gardenDays) ngày · \(shots.count) ảnh").font(.caption);Spacer();Text("Mỗi ngày, một ký ức").font(.system(.caption,design:.serif))}
                .padding(.vertical,80)
        }.frame(width:320,height:570).foregroundStyle(.white).clipped()
    }
    var body:some View{
        NavigationStack{ScrollView{VStack(spacing:16){art.clipShape(RoundedRectangle(cornerRadius:20))
            TextField("Tên trên hình nền",text:$name).textFieldStyle(.roundedBorder)
            Picker("Dây leo",selection:$theme){ForEach(VineTheme.allCases){Text($0.rawValue).tag($0)}}
            Button("Xuất hình nền PNG"){let r=ImageRenderer(content:art);r.scale=3;do{guard let data=r.uiImage?.pngData() else{throw CameraError.writeFailed};output=try CreativeEngine.exportURL(data,extension:"png")}catch{notice=error.localizedDescription}}
            if let output{ShareLink(item:output){Label("Lưu hình nền",systemImage:"square.and.arrow.up")}}
            Button("Xuất phim cây trưởng thành",systemImage:"film"){exporting=true;let days=life.gardenDays,t=theme,n=name;Task{do{movie=try await Task.detached(priority:.userInitiated){try await GardenEvolutionFilm.export(days:days,theme:t,name:n)}.value;notice="Đã xuất phim."}catch{notice=error.localizedDescription};exporting=false}}.disabled(exporting)
            if exporting{ProgressView()}
            if let movie{ShareLink(item:movie){Label("Lưu phim khu vườn",systemImage:"square.and.arrow.up")}}
            Text(notice).font(.caption)
        }.padding()}.navigationTitle("Memory Signature").toolbar{Button("Xong"){dismiss()}}}
    }
}
