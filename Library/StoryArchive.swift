import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

enum StoryMood:String,CaseIterable,Codable {
    case peaceful="Bình yên",happy="Hạnh phúc",romantic="Yêu thương",nostalgic="Hoài niệm",sad="Trầm lắng",grateful="Biết ơn",adventure="Khám phá"
}
enum StoryFormat:String,CaseIterable,Codable{
    case quick="Ghi nhanh",rich="Câu chuyện",chapter="Chương ký ức",letter="Lá thư",voice="Lời kể"
}
struct StoryEntry:Codable,Equatable,Identifiable{
    var id:String
    var title=""
    var body=""
    var mood:StoryMood?
    var location=""
    var people=""
    var quote=""
    var tags=""
    var format:StoryFormat = .rich
    var cover:UUID?
    var photoIDs:[UUID]=[]
    var captions:[String:String]=[:]
    var audio:Data?
    var canvas:MemoryCanvasDesign?=nil
    var textEffect:StoryTextEffect?=nil
    var textFont:CanvasFont?=nil
    var textColor:String?=nil
    var chapters:[String]?=nil
    var soundscape:StorySoundscape?=nil
    var createdAt=Date()
    var updatedAt=Date()
    var hasContent:Bool{![title,body,location,people,quote,tags].allSatisfy{$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty} || mood != nil || audio != nil || !captions.isEmpty || canvas != nil || !(chapters ?? []).isEmpty}
}
struct StoryTarget:Identifiable{
    let id:String
    let label:String
    let shots:[Shot]
    static func photo(_ shot:Shot)->Self{Self(id:"photo:"+shot.id.uuidString,label:"Story ảnh · "+TimelineIndex.label(shot.day),shots:[shot])}
    static func group(_ group:TimelineGroup)->Self{Self(id:"period:"+group.key,label:TimelineIndex.label(group.key),shots:group.items)}
    static func collection(_ name:String,shots:[Shot])->Self{Self(id:"collection:"+name,label:name,shots:shots)}
}
struct StoryArchivePackage:Codable{
    let version:Int
    let entries:[StoryEntry]
    let drafts:[StoryEntry]
}
@MainActor final class StoryArchive:ObservableObject{
    static let shared=StoryArchive()
    @Published private(set) var entries:[String:StoryEntry]=[:]
    @Published private(set) var drafts:[String:StoryEntry]=[:]
    @Published private(set) var issue:String?
    let root:URL
    init(root:URL=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("VieLensStories",isDirectory:true)){
        self.root=root
        do{
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            let url=root.appendingPathComponent("stories.json")
            if FileManager.default.fileExists(atPath:url.path){
                let package=try JSONDecoder().decode(StoryArchivePackage.self,from:Data(contentsOf:url))
                guard package.version==1 else{throw CameraError.unreadable}
                for entry in package.entries{entries[entry.id]=entry}
                for draft in package.drafts{drafts[draft.id]=draft}
            }
        }catch{issue=error.localizedDescription}
    }
    func entry(_ id:String)->StoryEntry?{entries[id]}
    func draft(_ target:StoryTarget)->StoryEntry{
        if let d=drafts[target.id]{return d}
        if let e=entries[target.id]{return e}
        var entry=StoryEntry(id:target.id)
        entry.photoIDs=target.shots.map(\.id)
        entry.cover=target.shots.first?.id
        if target.id.hasPrefix("photo:"),let note=target.shots.first?.note{entry.body=note}
        return entry
    }
    private func persist(_ e:[String:StoryEntry],_ d:[String:StoryEntry])throws{
        // Never overwrite a damaged archive silently.
        if issue != nil{throw CameraError.writeFailed}
        let data=try JSONEncoder().encode(StoryArchivePackage(version:1,entries:Array(e.values),drafts:Array(d.values)))
        try data.write(to:root.appendingPathComponent("stories.json"),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        entries=e;drafts=d
    }
    func save(_ value:StoryEntry,draft:Bool)throws{
        guard (value.audio?.count ?? 0)<=4_000_000 else{throw CameraError.writeFailed}
        var e=entries,d=drafts,item=value;item.updatedAt=Date()
        if draft{d[item.id]=item}else{e[item.id]=item;d.removeValue(forKey:item.id)}
        try persist(e,d)
    }
    func remove(_ id:String)throws{
        var e=entries,d=drafts;e.removeValue(forKey:id);d.removeValue(forKey:id);try persist(e,d)
    }
    func discardDraft(_ id:String)throws{var d=drafts;d.removeValue(forKey:id);try persist(entries,d)}
    func export()throws->URL{
        guard issue==nil else{throw CameraError.unreadable}
        return try CreativeEngine.exportURL(JSONEncoder().encode(StoryArchivePackage(version:1,entries:Array(entries.values),drafts:Array(drafts.values))),extension:"json")
    }
    func merge(_ data:Data)throws{
        guard data.count<=100_000_000 else{throw CameraError.unreadable}
        let package=try JSONDecoder().decode(StoryArchivePackage.self,from:data)
        guard package.version==1,(package.entries+package.drafts).allSatisfy({($0.audio?.count ?? 0)<=4_000_000}) else{throw CameraError.unreadable}
        var e=entries,d=drafts
        for item in package.entries where e[item.id]==nil{e[item.id]=item}
        for item in package.drafts where d[item.id]==nil{d[item.id]=item}
        try persist(e,d)
    }
    func matching(_ query:String,shot:Shot)->Bool{
        let words=query.folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"vi_VN")).lowercased().replacingOccurrences(of:"đ",with:"d").split(whereSeparator:\.isWhitespace)
        guard !words.isEmpty else{return false}
        let ids=["photo:"+shot.id.uuidString,"period:"+shot.day,"period:"+String(shot.day.prefix(7)),"period:"+String(shot.day.prefix(4))]+(shot.collections ?? []).map{"collection:"+$0}
        let text=ids.compactMap{entries[$0]}.map{[$0.title,$0.body,$0.location,$0.people,$0.quote,$0.tags,$0.mood?.rawValue ?? "",$0.captions[shot.id.uuidString] ?? ""].joined(separator:" ")}.joined(separator:" ").folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"vi_VN")).lowercased().replacingOccurrences(of:"đ",with:"d")
        return words.allSatisfy{text.contains($0)}
    }
}
@MainActor final class StoryVoice:ObservableObject{
    @Published private(set) var recording=false
    @Published private(set) var playing=false
    @Published private(set) var issue:String?
    private var recorder:AVAudioRecorder?
    private var player:AVAudioPlayer?
    private var temp:URL?
    private var timer:Task<Void,Never>?
    private var playbackTask:Task<Void,Never>?
    private var generation=UUID()
    func begin(onFinished:@escaping(Data?)->Void)async{
        let token=UUID();generation=token
        let allowed=await withCheckedContinuation{(c:CheckedContinuation<Bool,Never>) in AVAudioSession.sharedInstance().requestRecordPermission{c.resume(returning:$0)}}
        guard token==generation else{return}
        guard allowed else{issue="Hãy cấp quyền microphone trong Cài đặt.";return}
        stopPlayback()
        do{
            let audio=AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord,mode:.default,options:[.defaultToSpeaker])
            try audio.setActive(true)
            let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".m4a")
            temp=url
            let r=try AVAudioRecorder(url:url,settings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:22050,AVNumberOfChannelsKey:1,AVEncoderBitRateKey:48000])
            recorder=r
            guard r.record(forDuration:120) else{throw CameraError.writeFailed}
            recording=true
            timer=Task{[weak self] in
                do{try await Task.sleep(for:.seconds(120))}catch{return}
                if let self{onFinished(self.finish())}
            }
        }catch{issue=error.localizedDescription;_ = finish()}
    }
    func finish()->Data?{
        generation=UUID();timer?.cancel();timer=nil
        recorder?.stop();recorder=nil;recording=false
        guard let url=temp else{return nil};temp=nil
        defer{try? FileManager.default.removeItem(at:url);try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)}
        guard let data=try? Data(contentsOf:url),data.count>0,data.count<=4_000_000 else{return nil}
        return data
    }
    @discardableResult func play(_ data:Data,volume:Float=1)->Double{
        stopPlayback()
        do{
            let session=AVAudioSession.sharedInstance();try session.setCategory(.playback,mode:.default,options:[.mixWithOthers]);try session.setActive(true)
            let p=try AVAudioPlayer(data:data);p.volume=volume
            guard p.play() else{throw CameraError.unreadable}
            player=p;playing=true
            playbackTask=Task{[weak self] in
                do{try await Task.sleep(for:.seconds(p.duration+0.1))}catch{return}
                self?.stopPlayback()
            }
            return p.duration
        }catch{issue=error.localizedDescription;return 0}
    }
    func stopPlayback(){playbackTask?.cancel();playbackTask=nil;player?.stop();player=nil;playing=false}
    func cancel(){_ = finish();stopPlayback()}
}
struct StoryComposer:View{
    let target:StoryTarget
    let vault:Vault
    @ObservedObject var archive:StoryArchive
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @StateObject private var voice=StoryVoice()
    @State private var value:StoryEntry
    @State private var baseline:StoryEntry
    @State private var notice=""
    @State private var deleting=false
    @State private var confirmClose=false
    @State private var chapterText=""
    @State private var showWriter=false
    init(target:StoryTarget,vault:Vault,archive:StoryArchive){
        self.target=target;self.vault=vault;self.archive=archive
        let initial=archive.draft(target)
        _value=State(initialValue:initial);_baseline=State(initialValue:initial)
    }
    var body:some View{
        NavigationStack{
            Form{
                Section{
                    Picker("Kiểu story",selection:$value.format){ForEach(StoryFormat.allCases,id:\.self){Text($0.rawValue).tag($0)}}
                    Menu("Mẫu gợi ý"){
                        Button("Một ngày bình yên"){insert("Một ngày bình yên","Hôm ấy, điều mình muốn nhớ nhất là…",.peaceful)}
                        Button("Lá thư gửi tương lai"){insert("Gửi mình của ngày mai","Mình mong rằng khi đọc lại những dòng này…",.nostalgic)}
                        Button("Chương mới"){insert("Một chương mới","Mọi thứ bắt đầu từ…",.adventure)}
                        Button("Gia đình"){insert("Nhà là nơi trở về","Điều mình trân trọng ở gia đình là…",.grateful)}
                        Button("Tình yêu"){insert("Có nhau","Khoảnh khắc mình muốn kể về hai đứa là…",.romantic)}
                        Button("Chuyến đi"){insert("Những bước chân","Nơi mình đã đến, điều mình học được…",.adventure)}
                    }.disabled(!value.title.isEmpty || !value.body.isEmpty)
                    Button("Story Writer · hỗ trợ viết",systemImage:"sparkles"){showWriter=true}
                    TextField("Tiêu đề",text:$value.title)
                    TextEditor(text:$value.body).frame(minHeight:145).accessibilityLabel("Nội dung story")
                    Picker("Hiệu ứng chữ",selection:Binding(get:{value.textEffect ?? .normal},set:{value.textEffect=$0})){ForEach(StoryTextEffect.allCases,id:\.self){Text($0.rawValue).tag($0)}}
                    Picker("Phong cách chữ",selection:Binding(get:{value.textFont ?? .serif},set:{value.textFont=$0})){ForEach(CanvasFont.allCases,id:\.self){Text($0.rawValue).tag($0)}}
                    ColorPicker("Màu chữ",selection:Binding(get:{GardenColor.decode(value.textColor ?? "FFFFFF")},set:{value.textColor=GardenColor.encode($0)}),supportsOpacity:false)
                    if value.format != .quick{
                        Picker("Cảm xúc",selection:$value.mood){Text("Chưa chọn").tag(nil as StoryMood?);ForEach(StoryMood.allCases,id:\.self){Text($0.rawValue).tag(Optional($0))}}
                        TextField("Địa điểm / bối cảnh",text:$value.location)
                        TextField("Những người liên quan",text:$value.people)
                        TextField("Trích dẫn",text:$value.quote,axis:.vertical)
                        TextField("Hashtag cá nhân",text:$value.tags)
                    }
                }
                Section("Chương truyện"){
                    ForEach(Array((value.chapters ?? []).indices),id:\.self){i in TextField("Chương \(i+1)",text:Binding(get:{(value.chapters ?? [])[i]},set:{value.chapters?[i]=$0}),axis:.vertical)}.onDelete{value.chapters?.remove(atOffsets:$0)}
                    TextField("Nội dung chương mới",text:$chapterText,axis:.vertical)
                    Button("Thêm chương"){value.chapters=(value.chapters ?? [])+[chapterText];chapterText=""}.disabled(chapterText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                }
                if target.shots.count>1{
                    Section("Ảnh bìa & chú thích"){
                        ScrollView(.horizontal){HStack{ForEach(target.shots){shot in
                            Button{value.cover=shot.id}label:{DiskImage(url:vault.thumbnail(shot.id),limit:180).scaledToFill().frame(width:74,height:74).clipped().overlay{if value.cover==shot.id{Rectangle().strokeBorder(gold,lineWidth:3)}}}.buttonStyle(.plain)
                        }}}
                        ForEach(target.shots){shot in
                            HStack{
                                DiskImage(url:vault.thumbnail(shot.id),limit:100).scaledToFill().frame(width:45,height:45).clipped()
                                TextField("Chú thích ảnh",text:Binding(get:{value.captions[shot.id.uuidString] ?? ""},set:{text in if text.isEmpty{value.captions.removeValue(forKey:shot.id.uuidString)}else{value.captions[shot.id.uuidString]=text}}))
                            }
                        }
                    }
                }
                Section("Âm thanh môi trường"){
                    Picker("Soundscape",selection:Binding(get:{value.soundscape ?? .none},set:{value.soundscape=$0})){ForEach(StorySoundscape.allCases,id:\.self){Text($0.rawValue).tag($0)}}
                    Button("Nghe thử"){if let data=(value.soundscape ?? .none).generate(){voice.play(data,volume:0.5)}}.disabled(voice.recording || (value.soundscape ?? .none) == .none)
                }
                Section("Giọng kể · tối đa 2 phút"){
                    Button(voice.recording ? "Dừng thu âm":"Thu âm lời kể",systemImage:voice.recording ? "stop.circle.fill":"mic.fill"){
                        if voice.recording{if let data=voice.finish(){value.audio=data}}
                        else{Task{await voice.begin{data in if let data{value.audio=data}}}}
                    }
                    if let audio=value.audio{
                        Button(voice.playing ? "Dừng nghe":"Nghe thử",systemImage:voice.playing ? "stop.fill":"play.fill"){if voice.playing{voice.stopPlayback()}else{voice.play(audio)}}.disabled(voice.recording)
                        Button("Bỏ bản thu",role:.destructive){voice.stopPlayback();value.audio=nil}.disabled(voice.recording)
                    }
                    if let error=voice.issue{Text(error).font(.caption).foregroundStyle(.secondary)}
                }
                Section{
                    Button("Lưu bản nháp"){save(draft:true)}.disabled(voice.recording)
                    if archive.entry(target.id) != nil || archive.drafts[target.id] != nil{Button("Xóa story và bản nháp",role:.destructive){deleting=true}.disabled(voice.recording)}
                    if !notice.isEmpty{Text(notice).font(.caption)}
                }
            }.navigationTitle(target.label).navigationBarTitleDisplayMode(.inline)
                .toolbar{
                    ToolbarItem(placement:.cancellationAction){Button("Đóng"){if value != baseline{confirmClose=true}else{dismiss()}}.disabled(voice.recording)}
                    ToolbarItem(placement:.confirmationAction){Button("Lưu"){save(draft:false)}.disabled(!value.hasContent || voice.recording)}
                }
                .confirmationDialog("Đóng story chưa lưu?",isPresented:$confirmClose){Button("Lưu bản nháp"){save(draft:true)};Button("Bỏ thay đổi",role:.destructive){dismiss()}}
                .confirmationDialog("Xóa story?",isPresented:$deleting){Button("Xóa",role:.destructive){do{try archive.remove(target.id);dismiss()}catch{notice=error.localizedDescription}}}
        }.sheet(isPresented:$showWriter){StoryWriterSheet(mood:value.mood?.rawValue ?? ""){draft in value.body=draft}}
        .interactiveDismissDisabled()
        .onChange(of:phase){_,p in if p == .background{if voice.recording,let data=voice.finish(){value.audio=data};voice.stopPlayback();if value.hasContent && value != baseline{try? archive.save(value,draft:true)}}}
        .onDisappear{voice.cancel()}
    }
    private func insert(_ title:String,_ body:String,_ mood:StoryMood){value.title=title;value.body=body;value.mood=mood}
    private func save(draft:Bool){
        // Preserve references outside the current filtered view.
        var seen=Set(value.photoIDs);value.photoIDs += target.shots.map(\.id).filter{seen.insert($0).inserted}
        if let cover=value.cover,!value.photoIDs.contains(cover){value.cover=value.photoIDs.first}
        if value.cover==nil{value.cover=value.photoIDs.first}
        do{try archive.save(value,draft:draft);dismiss()}catch{notice=error.localizedDescription}
    }
}
struct StoryReader:View{
    let target:StoryTarget
    let vault:Vault
    @ObservedObject var archive:StoryArchive
    @Environment(\.dismiss) private var dismiss
    @State private var editing=false
    @State private var canvasEditor=false
    @State private var pdfURL:URL?
    @State private var exportError=""
    @State private var showVideo=false
    @State private var textReplay=0
    @AppStorage("timeline.vine.theme") private var vineValue=VineTheme.emerald.rawValue
    @StateObject private var voice=StoryVoice()
    @Environment(\.scenePhase) private var phase
    var body:some View{
        NavigationStack{
            ScrollView{
                if let story=archive.entry(target.id){
                    VStack(alignment:.leading,spacing:15){
                        if let cover=target.shots.first(where:{$0.id==story.cover}) ?? target.shots.first{
                            DiskImage(url:vault.picture(cover),limit:1300).scaledToFill().frame(height:230).clipped().clipShape(RoundedRectangle(cornerRadius:17))
                        }
                        Text(story.format.rawValue.uppercased()).font(.caption2.monospaced()).foregroundStyle(gold)
                        Text(story.title.isEmpty ? target.label:story.title).font(.system(size:33,design:.serif))
                        if let mood=story.mood{Label(mood.rawValue,systemImage:"leaf").font(.caption).foregroundStyle(gold)}
                        if !story.location.isEmpty{Label(story.location,systemImage:"mappin").font(.caption)}
                        if !story.people.isEmpty{Label(story.people,systemImage:"person.2").font(.caption)}
                        if !story.quote.isEmpty{Text("“"+story.quote+"”").font(.system(.title3,design:.serif)).italic().foregroundStyle(gold)}
                        AnimatedStoryText(text:story.body,effect:story.textEffect ?? .normal,font:story.textFont ?? .serif,color:GardenColor.decode(story.textColor ?? "FFFFFF"),duration:story.audio.flatMap{try? AVAudioPlayer(data:$0).duration} ?? 3,trigger:textReplay)
                        ForEach(Array((story.chapters ?? []).enumerated()),id:\.offset){i,chapter in VStack(alignment:.leading,spacing:7){Text("CHƯƠNG \(i+1)").font(.caption2.monospaced()).foregroundStyle(gold);Text(chapter).font(.body).lineSpacing(5)}}
                        Button("Story Canvas",systemImage:"paintpalette"){canvasEditor=true}.buttonStyle(.bordered)
                        Button("Xuất sách ký ức PDF",systemImage:"book.closed"){do{pdfURL=try StoryPDF.export(story,shots:target.shots,vault:vault)}catch{exportError=error.localizedDescription}}
                        if let pdfURL{ShareLink(item:pdfURL){Label("Lưu sách PDF",systemImage:"square.and.arrow.up")}}
                        Button("Tạo video ký ức",systemImage:"film"){showVideo=true}.disabled(target.shots.isEmpty)
                        if !exportError.isEmpty{Text(exportError).font(.caption)}
                        if !story.tags.isEmpty{Text(story.tags).font(.caption).foregroundStyle(.secondary)}
                        if let data=story.audio{Button(voice.playing ? "Dừng lời kể":"Nghe lời kể",systemImage:voice.playing ? "stop.fill":"waveform"){if voice.playing{voice.stopPlayback()}else{textReplay+=1;voice.play(data)}}.buttonStyle(.borderedProminent)}
                        if target.shots.count>1{
                            HStack{Image(systemName:"leaf.fill");Text("NHỮNG KHOẢNH KHẮC").tracking(2);Spacer()}.font(.caption2).foregroundStyle(gold)
                            ForEach(target.shots.filter{$0.id != story.cover || story.captions[$0.id.uuidString] != nil}){shot in
                                VStack(alignment:.leading,spacing:7){
                                    DiskImage(url:vault.picture(shot),limit:1200).scaledToFit().clipShape(RoundedRectangle(cornerRadius:11))
                                    Text(story.captions[shot.id.uuidString] ?? TimelineIndex.label(shot.day)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }.padding(18)
                    .overlay(alignment:.topLeading){VineRail(level:0,theme:VineTheme(rawValue:vineValue) ?? .emerald,density:0.65,curvature:0.8).frame(width:22,height:120).opacity(0.8).allowsHitTesting(false)}
                }else{ContentUnavailableView("Chưa có story",systemImage:"book.closed",description:Text("Viết câu chuyện cho khoảnh khắc này."))}
            }.navigationTitle("Story").navigationBarTitleDisplayMode(.inline).toolbar{
                ToolbarItem(placement:.cancellationAction){Button("Đóng"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Menu{Button("Viết / sửa"){voice.stopPlayback();editing=true};Button("Story Canvas"){voice.stopPlayback();canvasEditor=true}}label:{Image(systemName:"ellipsis.circle")}}
            }
        }.sheet(isPresented:$editing){StoryComposer(target:target,vault:vault,archive:archive)}
        .sheet(isPresented:$canvasEditor){StoryCanvasStudio(target:target,vault:vault,archive:archive)}
        .sheet(isPresented:$showVideo){if let story=archive.entry(target.id){StoryFilmView(story:story,shots:target.shots,vault:vault)}}
        .onChange(of:phase){_,p in if p != .active{voice.stopPlayback()}}.onDisappear{voice.cancel()}
    }
}
struct StoryLibrary:View{
    let shots:[Shot]
    let vault:Vault
    @ObservedObject var archive:StoryArchive
    @Environment(\.dismiss) private var dismiss
    @State private var target:StoryTarget?
    @State private var importing=false
    @State private var backup:URL?
    @State private var notice=""
    @State private var query=""
    private var rows:[StoryEntry]{archive.entries.values.filter{query.isEmpty || [$0.title,$0.body,$0.tags,$0.people,$0.location,$0.quote,$0.mood?.rawValue ?? ""].joined(separator:" ").localizedStandardContains(query)}.sorted{$0.updatedAt>$1.updatedAt}}
    private func makeTarget(_ entry:StoryEntry)->StoryTarget{StoryTarget(id:entry.id,label:entry.title.isEmpty ? entry.id:entry.title,shots:shots.filter{entry.photoIDs.contains($0.id)})}
    var body:some View{
        NavigationStack{
            List{
                if let error=archive.issue{Text(error).foregroundStyle(.secondary)}
                Section("Story đã lưu"){
                    ForEach(rows){entry in Button{target=makeTarget(entry)}label:{HStack{Image(systemName:"book.closed").foregroundStyle(gold);VStack(alignment:.leading){Text(entry.title.isEmpty ? entry.format.rawValue:entry.title);Text(entry.body).font(.caption).lineLimit(2).foregroundStyle(.secondary)}}}}
                }
                Section("Bản nháp"){
                    ForEach(Array(archive.drafts.values).sorted{$0.updatedAt>$1.updatedAt}){entry in Button{target=makeTarget(entry)}label:{Label(entry.title.isEmpty ? "Bản nháp":entry.title,systemImage:"pencil.line")}}
                }
                Section("Sao lưu Story"){
                    Button("Tạo tệp sao lưu JSON"){do{backup=try archive.export();notice="Tệp chứa cả nội dung và giọng kể. Cất ở nơi riêng tư."}catch{notice=error.localizedDescription}}
                    if let backup{ShareLink(item:backup){Label("Lưu tệp",systemImage:"square.and.arrow.up")}}
                    Button("Khôi phục / hợp nhất"){importing=true}
                    Text("Sao lưu story riêng với ảnh Timeline; không ghi đè story đã có.").font(.caption).foregroundStyle(.secondary)
                    if !notice.isEmpty{Text(notice).font(.caption)}
                }
            }.searchable(text:$query).navigationTitle("Story Studio").toolbar{Button("Xong"){dismiss()}}
        }.sheet(item:$target){t in if archive.drafts[t.id] != nil{StoryComposer(target:t,vault:vault,archive:archive)}else{StoryReader(target:t,vault:vault,archive:archive)}}
        .fileImporter(isPresented:$importing,allowedContentTypes:[.json]){result in
            do{let url=try result.get(),access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}};try archive.merge(Data(contentsOf:url));notice="Đã hợp nhất story."}catch{notice=error.localizedDescription}
        }
    }
}
