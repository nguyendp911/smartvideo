import SwiftUI
import UIKit
import AVFoundation

enum PersonalGardenKind:String,CaseIterable,Codable,Identifiable{
    case couple="Couple Garden",family="Family Garden",childhood="Childhood Garden",travel="Travel Garden",memorial="Memorial Garden",personal="Khu vườn riêng"
    var id:String{rawValue}
    var icon:String{switch self{case .couple:return "heart.fill";case .family:return "person.2.fill";case .childhood:return "teddybear.fill";case .travel:return "airplane";case .memorial:return "candle.fill";case .personal:return "leaf.fill"}}
}
struct PersonalGarden:Codable,Identifiable,Equatable{
    var id=UUID()
    var title:String
    var kind:PersonalGardenKind = .personal
    var theme:String=VineTheme.emerald.rawValue
    var photos:Set<UUID>=[]
    var usage:Set<String>=[]
    var created=Date()
}
struct MemoryThread:Codable,Identifiable,Equatable{
    var id=UUID()
    var title:String
    var days:Set<String>=[]
}
struct LifeCountdown:Codable,Identifiable,Equatable{
    var id=UUID()
    var title:String
    var date:Date
}
struct EcosystemData:Codable,Equatable{
    var gardens:[PersonalGarden]=[]
    var threads:[MemoryThread]=[]
    var countdowns:[LifeCountdown]=[]
}
enum MemoryCreature:String,CaseIterable,Identifiable{
    case leaf="Lá ký ức",bud="Nụ story",dew="Giọt sương",butterfly="Bướm yêu thích",bird="Chim ký ức",ladybug="Bọ rùa",lantern="Đèn kỷ niệm",key="Chìa khóa"
    var id:String{rawValue}
    var icon:String{switch self{case .leaf:return "leaf.fill";case .bud:return "camera.macro";case .dew:return "drop.fill";case .butterfly:return "butterfly";case .bird:return "bird.fill";case .ladybug:return "ladybug.fill";case .lantern:return "candle.fill";case .key:return "key.fill"}}
    var asset:String?{switch self{case .leaf:return "botanical_leaf";case .bud:return "botanical_bud";case .dew:return "ecosystem_dew";case .butterfly:return "ecosystem_butterfly";case .bird:return "ecosystem_bird";case .ladybug:return "ecosystem_ladybug";case .lantern:return "ecosystem_lantern";case .key:return "ecosystem_key"}}
}
struct MemoryDNA{
    var photos:Int;var stories:Int;var voices:Int;var favorites:Int;var milestones:Int;var chapters:Int;var letters:Int
    var creatures:[MemoryCreature]{
        var result:[MemoryCreature]=[]
        if photos>0{result.append(.leaf)}
        if stories>0{result.append(.bud)}
        if voices>0{result.append(.dew)}
        if favorites>0{result.append(.butterfly)}
        if chapters>0{result.append(.bird)}
        if photos>=10{result.append(.ladybug)}
        if milestones>0{result.append(.lantern)}
        if letters>0{result.append(.key)}
        return result
    }
    @MainActor static func day(_ key:String,shots:[Shot],archive:StoryArchive,life:LifeArchive)->MemoryDNA{
        let items=shots.filter{$0.day==key && $0.deleted==nil}
        let entries=(["period:"+key]+items.map{StoryTarget.photo($0).id}).compactMap{archive.entry($0)}
        return MemoryDNA(photos:items.count,stories:entries.filter{$0.hasContent}.count,voices:entries.filter{$0.audio != nil}.count,favorites:items.filter{$0.rating>=4}.count,milestones:life.milestones(key).count,chapters:life.data.chapters.filter{$0.end==key}.count,letters:life.data.letters.filter{LifeDate.key($0.opens)==key}.count)
    }
}
struct CreatureBadge:View{
    let creature:MemoryCreature
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var phase
    @AppStorage("garden.live") private var live=true
    var body:some View{
        TimelineView(.animation(minimumInterval:1/12,paused:reduced || !live || phase != .active)){clock in
            let t=clock.date.timeIntervalSinceReferenceDate
            let animate=live && !reduced && phase == .active
            let wing=animate && creature == .butterfly ? 0.72+0.28*abs(sin(t*3.8)):1
            Group{
                if let asset=creature.asset{Image(asset).resizable().scaledToFit()}
                else{Image(systemName:creature.icon).font(.system(size:17)).foregroundStyle(gold)}
            }.scaleEffect(x:wing,y:1)
                .rotationEffect(.degrees(animate && creature == .lantern ? sin(t*0.8)*5:0),anchor:.top)
                .offset(y:animate && (creature == .bird || creature == .butterfly) ? CGFloat(sin(t*1.2))*1.5:0)
        }.frame(width:25,height:25).accessibilityLabel(creature.rawValue)
    }
}
struct MemoryDNAChips:View{
    let day:String
    let shots:[Shot]
    let vault:Vault
    @ObservedObject var archive:StoryArchive
    @ObservedObject var life:LifeArchive
    @State private var selected:MemoryCreature?
    @State private var letters=false
    var body:some View{
        let dna=MemoryDNA.day(day,shots:shots,archive:archive,life:life)
        if !dna.creatures.isEmpty{
            HStack(spacing:8){ForEach(dna.creatures){creature in
                Button{if creature == .key{letters=true}else{selected=creature}}label:{CreatureBadge(creature:creature).padding(3).background(.white.opacity(0.045),in:Circle())}.buttonStyle(.plain)
            }}
            .sheet(item:$selected){creature in
                MemoryCreatureReader(creature:creature,day:day,shots:shots,vault:vault)
            }.sheet(isPresented:$letters){FutureLetterStudio(life:life)}
        }
    }
}
struct MemoryCreatureReader:View{
    let creature:MemoryCreature;let day:String;let shots:[Shot];let vault:Vault
    @ObservedObject private var archive=StoryArchive.shared
    @ObservedObject private var life=LifeArchive.shared
    @Environment(\.dismiss) private var dismiss
    @State private var target:StoryTarget?
    @StateObject private var voice=StoryVoice()
    @Environment(\.scenePhase) private var phase
    private var items:[Shot]{shots.filter{$0.day==day && (creature != .butterfly || $0.rating>=4)}}
    private var entries:[StoryEntry]{(["period:"+day]+items.map{StoryTarget.photo($0).id}).compactMap{archive.entry($0)}}
    var body:some View{
        NavigationStack{List{
            if creature == .lantern{ForEach(life.milestones(day)){m in VStack(alignment:.leading){Label(m.title,systemImage:m.icon);Text(m.note).font(.caption)}}}
            if creature == .bird{ForEach(life.data.chapters.filter{$0.end==day}){c in Text(c.title);Text(c.summary).font(.caption)}}
            if creature == .dew{ForEach(entries.filter{$0.audio != nil}){e in Button(e.title.isEmpty ? "Nghe lời kể":e.title,systemImage:"waveform"){if let audio=e.audio{voice.play(audio)}}}}
            Button("Story ngày này"){target=MemorySync.target(day:day,shots:shots)}
            ForEach(items){s in Button{target = .photo(s)}label:{HStack{DiskImage(url:vault.thumbnail(s.id),limit:180).scaledToFill().frame(width:64,height:64).clipped();Text(archive.entry(StoryTarget.photo(s).id)?.title ?? s.day)}}}
        }.navigationTitle(creature.rawValue).toolbar{Button("Đóng"){dismiss()}}}
        .sheet(item:$target){LifeStorySheet(target:$0,vault:vault,archive:archive)}.onChange(of:phase){_,p in if p == .background{voice.cancel()}}.onDisappear{voice.cancel()}
    }
}
struct PersonalGardensView:View{
    let shots:[Shot];let vault:Vault
    @ObservedObject private var life=LifeArchive.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editor=false
    @State private var selected:PersonalGarden?
    @State private var notice=""
    private var gardens:[PersonalGarden]{life.data.ecosystem?.gardens ?? []}
    var body:some View{
        NavigationStack{List{
            ForEach(gardens){g in Button{selected=g}label:{
                HStack{VineRail(level:0,theme:VineTheme(rawValue:g.theme) ?? .emerald,growth:VineGrowth(days:g.usage.count)).frame(width:40,height:80)
                    VStack(alignment:.leading){Label(g.title,systemImage:g.kind.icon).font(.headline);Text("\(g.photos.intersection(Set(shots.map(\.id))).count) ảnh · \(g.usage.count) ngày chăm sóc").font(.caption).foregroundStyle(.secondary)}}
            }.swipeActions{Button("Xóa",role:.destructive){do{try life.update{p in p.ecosystem?.gardens.removeAll{$0.id==g.id}}}catch{notice=error.localizedDescription}}}}
            Button("Tạo khu vườn",systemImage:"plus"){editor=true}
            Text("Chỉ lưu tham chiếu ảnh, không tạo bản sao. Mỗi khu vườn có tuổi riêng.").font(.caption)
            Text(notice).font(.caption)
        }.navigationTitle("Khu vườn của tôi").toolbar{Button("Xong"){dismiss()}}}
        .sheet(isPresented:$editor){GardenEditor(shots:shots,vault:vault,existing:nil)}
        .sheet(item:$selected){g in GardenRoom(id:g.id,shots:shots,vault:vault)}
    }
}
struct GardenEditor:View{
    let shots:[Shot];let vault:Vault;let existing:PersonalGarden?
    @ObservedObject private var life=LifeArchive.shared
    @Environment(\.dismiss) private var dismiss
    @State private var title=""
    @State private var kind=PersonalGardenKind.couple
    @State private var theme=VineTheme.emerald
    @State private var ids=Set<UUID>()
    @State private var query=""
    @State private var notice=""
    var body:some View{
        NavigationStack{List{
            Section{TextField("Tên khu vườn",text:$title);Picker("Loại",selection:$kind){ForEach(PersonalGardenKind.allCases){Text($0.rawValue).tag($0)}};Picker("Dây leo",selection:$theme){ForEach(VineTheme.allCases){Text($0.rawValue).tag($0)}}}
            Section("Chọn ảnh · \(ids.count)"){
                TextField("Tìm ngày hoặc album",text:$query)
                ForEach(shots.filter{query.isEmpty || ($0.day+" "+$0.session+" "+$0.tags).localizedStandardContains(query)}){s in Button{if ids.contains(s.id){ids.remove(s.id)}else{ids.insert(s.id)}}label:{HStack{DiskImage(url:vault.thumbnail(s.id),limit:100).scaledToFill().frame(width:44,height:44).clipped();Text(s.day);Spacer();Image(systemName:ids.contains(s.id) ? "checkmark.circle.fill":"circle")}}.buttonStyle(.plain)}
            };Text(notice).font(.caption)
        }.navigationTitle("Thiết kế khu vườn").toolbar{ToolbarItem(placement:.cancellationAction){Button("Đóng"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Lưu"){var g=existing ?? PersonalGarden(title:title);g.title=title;g.kind=kind;g.theme=theme.rawValue;g.photos=ids;g.usage.insert(LifeDate.key(Date()));do{try life.update{p in var e=p.ecosystem ?? EcosystemData();e.gardens.removeAll{$0.id==g.id};e.gardens.append(g);p.ecosystem=e};dismiss()}catch{notice=error.localizedDescription}}.disabled(title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}}}
        .onAppear{if let g=existing{title=g.title;kind=g.kind;theme=VineTheme(rawValue:g.theme) ?? .emerald;ids=g.photos}}
    }
}
struct GardenRoom:View{
    let id:UUID;let shots:[Shot];let vault:Vault
    @ObservedObject private var life=LifeArchive.shared
    @ObservedObject private var archive=StoryArchive.shared
    @Environment(\.dismiss) private var dismiss
    @State private var edit=false
    @State private var target:StoryTarget?
    @State private var calendar=false
    @State private var play=false
    @State private var notice=""
    private var garden:PersonalGarden?{life.data.ecosystem?.gardens.first{$0.id==id}}
    private var items:[Shot]{shots.filter{garden?.photos.contains($0.id)==true}}
    var body:some View{
        NavigationStack{ScrollView{
            if let g=garden{
                VStack(alignment:.leading,spacing:14){
                    HStack{VineRail(level:2,theme:VineTheme(rawValue:g.theme) ?? .emerald,growth:VineGrowth(days:g.usage.count)).frame(width:70,height:125);VStack(alignment:.leading){Text(g.title).font(.system(.largeTitle,design:.serif));Text(g.kind.rawValue).foregroundStyle(gold);Text("\(g.usage.count) ngày · \(items.count) ảnh").font(.caption)}}
                    Button("Story khu vườn",systemImage:"book.closed"){target=StoryTarget(id:"garden:"+g.id.uuidString,label:g.title,shots:items)}
                    Button("Lịch ảnh chung",systemImage:"calendar"){calendar=true}
                    Text("Nhật ký riêng của vườn nằm ở từng ngày bên dưới. Lịch ảnh đọc nhật ký ngày chung.").font(.caption2).foregroundStyle(.secondary)
                    Button("Trình chiếu",systemImage:"play"){play=true}.disabled(items.isEmpty)
                    ForEach(TimelineIndex.group(items,period:.day,newest:true)){group in
                        Button{target=StoryTarget(id:"garden:"+g.id.uuidString+":"+group.key,label:TimelineIndex.label(group.key),shots:group.items)}label:{HStack{DiskImage(url:vault.thumbnail(group.cover.id),limit:220).scaledToFill().frame(width:86,height:76).clipped().clipShape(RoundedRectangle(cornerRadius:10));VStack(alignment:.leading){Text(TimelineIndex.label(group.key));Text("\(group.items.count) ảnh").font(.caption)}}}.buttonStyle(.plain)
                    }
                    Text(notice).font(.caption)
                }.padding()
            }
        }.navigationTitle("Khu vườn").toolbar{ToolbarItem(placement:.cancellationAction){Button("Đóng"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Sửa"){edit=true}}}}
        .task{do{let day=LifeDate.key(Date());if garden?.usage.contains(day)==false{try life.update{p in if let i=p.ecosystem?.gardens.firstIndex(where:{$0.id==id}){p.ecosystem?.gardens[i].usage.insert(day)}}}}catch{notice=error.localizedDescription}}
        .sheet(isPresented:$edit){GardenEditor(shots:shots,vault:vault,existing:garden)}
        .sheet(item:$target){LifeStorySheet(target:$0,vault:vault,archive:archive)}
        .sheet(isPresented:$calendar){LifeCalendar(shots:items,vault:vault){key in calendar=false;target=MemorySync.target(day:key,shots:items)}}
        .fullScreenCover(isPresented:$play){ArchiveSlideshow(shots:items,vault:vault)}
    }
}
