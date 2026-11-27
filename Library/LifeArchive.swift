import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import AVFoundation

enum LifeDate{
    static var calendar:Calendar{var c=Calendar(identifier:.gregorian);c.firstWeekday=2;return c}
    static func key(_ date:Date)->String{
        let f=DateFormatter();f.calendar=calendar;f.locale=Locale(identifier:"en_US_POSIX");f.dateFormat="yyyy-MM-dd";return f.string(from:date)
    }
    static func date(_ key:String)->Date?{
        let f=DateFormatter();f.calendar=calendar;f.locale=Locale(identifier:"en_US_POSIX");f.dateFormat="yyyy-MM-dd";f.isLenient=false;return f.date(from:key)
    }
    static func start(_ date:Date)->Date{calendar.date(from:calendar.dateComponents([.year,.month],from:date)) ?? date}
    static func monthCells(_ month:Date)->[Date?]{
        let start=start(month),count=calendar.range(of:.day,in:.month,for:start)?.count ?? 0
        let leading=(calendar.component(.weekday,from:start)+5)%7
        return Array(repeating:nil,count:leading)+(0..<count).map{calendar.date(byAdding:.day,value:$0,to:start)}
    }
}
extension StoryMood{
    var calendarColor:Color{
        switch self{case .peaceful:return .mint;case .happy:return .yellow;case .romantic:return .pink;case .nostalgic:return .orange;case .sad:return .blue;case .grateful:return .purple;case .adventure:return .green}
    }
}
struct LifeMilestone:Codable,Identifiable,Equatable{
    var id=UUID()
    var title:String
    var date:String
    var note:String=""
    var icon:String="star.fill"
}
struct FutureMemoryLetter:Codable,Identifiable,Equatable{
    var id=UUID()
    var title:String
    var content:String
    var opens:Date
    var created=Date()
    func isOpen(at date:Date=Date())->Bool{date>=opens}
}
struct LifeChapter:Codable,Identifiable,Equatable{
    var id=UUID()
    var title:String
    var start:String
    var end:String
    var summary=""
    func contains(_ day:String)->Bool{day>=start && day<=end}
}
struct LifePackage:Codable{
    var version=1
    var milestones:[LifeMilestone]=[]
    var letters:[FutureMemoryLetter]=[]
    var chapters:[LifeChapter]=[]
    var gardenUsageDays:Set<String>?=nil
}
@MainActor final class LifeArchive:ObservableObject{
    static let shared=LifeArchive()
    @Published private(set) var data=LifePackage()
    @Published private(set) var issue:String?
    let root:URL
    init(root:URL=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("VieLensLife",isDirectory:true)){
        self.root=root
        do{
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            let url=root.appendingPathComponent("life.json")
            if FileManager.default.fileExists(atPath:url.path){
                data=try JSONDecoder().decode(LifePackage.self,from:Data(contentsOf:url))
                guard data.version==1 else{throw CameraError.unreadable}
            }
        }catch{issue=error.localizedDescription}
    }
    func update(_ change:(inout LifePackage)->Void)throws{
        guard issue==nil else{throw CameraError.writeFailed}
        var next=data;change(&next)
        let bytes=try JSONEncoder().encode(next)
        try bytes.write(to:root.appendingPathComponent("life.json"),options:[.atomic,.completeFileProtection])
        data=next
    }
    var gardenDays:Int{data.gardenUsageDays?.count ?? 0}
    func recordGardenUse(_ date:Date=Date())throws{
        let key=LifeDate.key(date)
        guard !(data.gardenUsageDays ?? []).contains(key) else{return}
        try update{$0.gardenUsageDays=($0.gardenUsageDays ?? []).union([key])}
    }
    func milestones(_ day:String)->[LifeMilestone]{data.milestones.filter{$0.date==day}}
    func exportData()throws->Data{guard issue==nil else{throw CameraError.unreadable};return try JSONEncoder().encode(data)}
    func merge(_ bytes:Data)throws{
        let incoming=try JSONDecoder().decode(LifePackage.self,from:bytes)
        guard incoming.version==1 else{throw CameraError.unreadable}
        try update{p in
            var m=Set(p.milestones.map(\.id)),l=Set(p.letters.map(\.id)),c=Set(p.chapters.map(\.id))
            p.milestones += incoming.milestones.filter{m.insert($0.id).inserted}
            p.letters += incoming.letters.filter{l.insert($0.id).inserted}
            p.chapters += incoming.chapters.filter{c.insert($0.id).inserted}
            p.gardenUsageDays=(p.gardenUsageDays ?? []).union(incoming.gardenUsageDays ?? [])
        }
    }
}
@MainActor enum MemorySync{
    static func target(day:String,shots:[Shot])->StoryTarget{
        StoryTarget(id:"period:"+day,label:TimelineIndex.label(day),shots:shots.filter{$0.deleted==nil && $0.day==day})
    }
    static func target(period:String,shots:[Shot])->StoryTarget{
        StoryTarget(id:"period:"+period,label:TimelineIndex.label(period),shots:shots.filter{$0.deleted==nil && $0.day.hasPrefix(period)})
    }
    static func storyDays(_ archive:StoryArchive)->Set<String>{
        Set(archive.entries.keys.filter{$0.hasPrefix("period:") && $0.count==17}.map{String($0.dropFirst(7))})
    }
    static func activeDays(shots:[Shot],stories:StoryArchive,life:LifeArchive)->Set<String>{
        Set(shots.filter{$0.deleted==nil}.map(\.day)).union(storyDays(stories)).union(life.data.milestones.map(\.date))
    }
    static func cover(_ shots:[Shot],entry:StoryEntry?)->Shot?{
        if let id=entry?.cover,let shot=shots.first(where:{$0.id==id}){return shot}
        return shots.max{a,b in a.rating==b.rating ? a.date<b.date:a.rating<b.rating}
    }
    static func setMood(_ mood:StoryMood,day:String,shots:[Shot],archive:StoryArchive)throws{
        let target=target(day:day,shots:shots)
        var value=archive.entry(target.id) ?? StoryEntry(id:target.id)
        value.mood=mood
        var known=Set(value.photoIDs)
        value.photoIDs+=target.shots.map(\.id).filter{known.insert($0).inserted}
        if value.cover==nil{value.cover=cover(target.shots,entry:nil)?.id}
        // Keep an existing draft instead of replacing unpublished writing.
        let draft=archive.drafts[target.id]
        try archive.save(value,draft:false)
        if var draft{draft.mood=mood;try archive.save(draft,draft:true)}
    }
    static func setCover(_ shot:Shot,target:StoryTarget,archive:StoryArchive)throws{
        var entry=archive.entry(target.id) ?? StoryEntry(id:target.id)
        let draft=archive.drafts[target.id]
        entry.cover=shot.id
        var known=Set(entry.photoIDs);entry.photoIDs+=target.shots.map(\.id).filter{known.insert($0).inserted}
        try archive.save(entry,draft:false)
        if var draft{draft.cover=shot.id;try archive.save(draft,draft:true)}
    }
}
struct LifeStorySheet:View{
    let target:StoryTarget
    let vault:Vault
    @ObservedObject var archive:StoryArchive
    var body:some View{
        if archive.entry(target.id) != nil{StoryReader(target:target,vault:vault,archive:archive)}
        else{StoryComposer(target:target,vault:vault,archive:archive)}
    }
}
enum MemoryReminder{
    static func schedule(id:String,title:String,date:DateComponents,repeats:Bool)async throws{
        let center=UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options:[.alert,.sound]) else{
            throw NSError(domain:"VieLens.Reminder",code:1,userInfo:[NSLocalizedDescriptionKey:"Bạn chưa cho phép thông báo."])
        }
        let content=UNMutableNotificationContent();content.title="VieLens · Ký ức";content.body=title;content.sound = .default
        let trigger=UNCalendarNotificationTrigger(dateMatching:date,repeats:repeats)
        guard trigger.nextTriggerDate() != nil else{throw CameraError.unreadable}
        try await center.add(UNNotificationRequest(identifier:id,content:content,trigger:trigger))
    }
    static func cancel(_ id:String){UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers:[id])}
}
struct LifeMilestoneEditor:View{
    let day:String
    @ObservedObject var life:LifeArchive
    var existing:LifeMilestone?=nil
    @Environment(\.dismiss) private var dismiss
    @State private var title=""
    @State private var note=""
    @State private var icon="star.fill"
    @State private var date=Date()
    @State private var notice=""
    var body:some View{
        NavigationStack{
            Form{
                TextField("Tên cột mốc",text:$title)
                DatePicker("Ngày",selection:$date,displayedComponents:.date)
                Picker("Biểu tượng",selection:$icon){ForEach(["star.fill","heart.fill","graduationcap.fill","house.fill","airplane","birthday.cake.fill","leaf.fill"],id:\.self){Image(systemName:$0).tag($0)}}
                TextField("Câu chuyện",text:$note,axis:.vertical)
                if !notice.isEmpty{Text(notice).font(.caption)}
                if let existing{Button("Xóa cột mốc",role:.destructive){do{try life.update{$0.milestones.removeAll{$0.id==existing.id}};MemoryReminder.cancel("milestone:"+existing.id.uuidString);dismiss()}catch{notice=error.localizedDescription}}}
            }.navigationTitle("Cột mốc cuộc đời").toolbar{
                ToolbarItem(placement:.cancellationAction){Button("Đóng"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button("Lưu"){
                    var item=existing ?? LifeMilestone(title:title,date:day)
                    item.title=title;item.date=LifeDate.key(date);item.note=note;item.icon=icon
                    do{try life.update{p in p.milestones.removeAll{$0.id==item.id};p.milestones.append(item)};dismiss()}catch{notice=error.localizedDescription}
                }.disabled(title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
            }
        }.onAppear{title=existing?.title ?? "";note=existing?.note ?? "";icon=existing?.icon ?? "star.fill";date=LifeDate.date(existing?.date ?? day) ?? Date()}
    }
}
struct FutureLetterStudio:View{
    @ObservedObject var life:LifeArchive
    @Environment(\.dismiss) private var dismiss
    @State private var title=""
    @State private var content=""
    @State private var opens=Date().addingTimeInterval(86400)
    @State private var reminder=true
    @State private var notice=""
    @State private var selected:FutureMemoryLetter?
    @State private var deleting:FutureMemoryLetter?
    var body:some View{
        NavigationStack{
            List{
                Section("Gửi mình của tương lai"){
                    TextField("Tiêu đề",text:$title)
                    TextEditor(text:$content).frame(minHeight:110)
                    DatePicker("Ngày mở thư",selection:$opens,in:Date()...)
                    Toggle("Nhắc vào ngày mở",isOn:$reminder)
                    Button("Niêm phong thư",systemImage:"envelope.fill"){save()}.disabled(title.isEmpty || content.isEmpty)
                    Text("Thư được ẩn trong giao diện đến ngày mở. Không phải khóa mã hóa hay chống chỉnh giờ thiết bị.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Những lá thư"){
                    ForEach(life.data.letters.sorted{$0.opens<$1.opens}){letter in
                        Button{if letter.isOpen(){selected=letter}else{notice="Thư chưa đến ngày mở."}}label:{
                            HStack{Image(systemName:letter.isOpen() ? "envelope.open":"envelope.fill").foregroundStyle(gold);VStack(alignment:.leading){Text(letter.title);Text(letter.opens.formatted(date:.abbreviated,time:.shortened)).font(.caption)};Spacer();if !letter.isOpen(){Image(systemName:"lock")}}
                        }.swipeActions{Button("Xóa",role:.destructive){deleting=letter}}
                    }
                }
                Text(notice).font(.caption)
            }.navigationTitle("Future Letter").toolbar{Button("Xong"){dismiss()}}
        }.sheet(item:$selected){letter in NavigationStack{ScrollView{VStack(alignment:.leading,spacing:20){Image(systemName:"envelope.open.fill").font(.largeTitle).foregroundStyle(gold);Text(letter.title).font(.system(.largeTitle,design:.serif));Text(letter.content).font(.system(.body,design:.serif)).lineSpacing(7)}.padding()}.toolbar{Button("Đóng"){selected=nil}}}}
        .confirmationDialog("Xóa lá thư?",isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}})){Button("Xóa",role:.destructive){if let item=deleting{do{try life.update{$0.letters.removeAll{$0.id==item.id}};MemoryReminder.cancel("letter:"+item.id.uuidString)}catch{notice=error.localizedDescription};deleting=nil}}}
    }
    private func save(){
        let letter=FutureMemoryLetter(title:title,content:content,opens:opens)
        do{
            try life.update{$0.letters.append(letter)}
            title="";content="";notice="Đã niêm phong thư."
            if reminder{Task{do{try await MemoryReminder.schedule(id:"letter:"+letter.id.uuidString,title:"Một lá thư tương lai đã đến ngày mở.",date:LifeDate.calendar.dateComponents([.year,.month,.day,.hour,.minute],from:letter.opens),repeats:false)}catch{notice="Đã lưu thư; "+error.localizedDescription}}}
        }catch{notice=error.localizedDescription}
    }
}

struct LifeBackupView:View{
    @ObservedObject private var archive=StoryArchive.shared
    @ObservedObject private var life=LifeArchive.shared
    @Environment(\.dismiss) private var dismiss
    @State private var output:URL?
    @State private var importing=false
    @State private var notice=""
    struct Package:Codable{let version:Int;let story:Data;let life:Data}
    var body:some View{
        NavigationStack{
            Form{
                Section("Nhật ký và cuộc đời"){
                    Text("Gộp story, bản nháp, giọng kể, canvas, cột mốc, chương cuộc đời và thư tương lai vào một tệp. Ảnh gốc và Signature vẫn sao lưu riêng. Tệp chứa dữ liệu cá nhân, hãy lưu nơi an toàn.").font(.caption)
                    Button("Tạo bản sao lưu"){
                        do{
                            let url=try archive.export()
                            defer{try? FileManager.default.removeItem(at:url)}
                            let package=Package(version:1,story:try Data(contentsOf:url),life:try life.exportData())
                            output=try CreativeEngine.exportURL(JSONEncoder().encode(package),extension:"json");notice="Đã tạo bản sao lưu."
                        }catch{notice=error.localizedDescription}
                    }
                    if let output{ShareLink(item:output){Label("Lưu bản sao lưu",systemImage:"square.and.arrow.up")}}
                    Button("Khôi phục / hợp nhất"){importing=true}
                    Text(notice).font(.caption)
                }
            }.navigationTitle("Life Backup").toolbar{Button("Xong"){dismiss()}}
        }.fileImporter(isPresented:$importing,allowedContentTypes:[.json]){result in
            do{
                let url=try result.get(),access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
                let bytes=try Data(contentsOf:url)
                guard bytes.count<=150_000_000 else{throw CameraError.unreadable}
                let package=try JSONDecoder().decode(Package.self,from:bytes)
                guard package.version==1,try JSONDecoder().decode(LifePackage.self,from:package.life).version==1,try JSONDecoder().decode(StoryArchivePackage.self,from:package.story).version==1 else{throw CameraError.unreadable}
                try archive.merge(package.story)
                do{try life.merge(package.life);notice="Đã hợp nhất Story và Life. Các thông báo cần bật lại thủ công."}catch{notice="Story đã hợp nhất, Life chưa khôi phục: "+error.localizedDescription}
            }catch{notice=error.localizedDescription}
        }
    }
}
