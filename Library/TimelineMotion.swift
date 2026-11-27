import SwiftUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers

enum TimelinePresentation:String,CaseIterable {
    case tree="Cây thời gian",slides="Slide ký ức",gallery="Thư viện"
    var icon:String {
        switch self{case .tree:return "point.topleft.down.to.point.bottomright.curvepath";case .slides:return "rectangle.on.rectangle";case .gallery:return "square.grid.3x3"}
    }
}
enum StoryEffect:String,CaseIterable {
    case slide="Slide ngang",vertical="Slide dọc",fade="Hòa mờ",zoom="Zoom điện ảnh",card="Lật thẻ",reveal="Reveal",book="Memory Book",floating="Floating Memories",film="Film Journey",petal="Petal Reveal",dust="Golden Dust",depth="Depth Motion",ink="Ink Reveal",hanging="Hanging Memories"
    func transition(forward:Bool)->AnyTransition {
        switch self{
        case .slide:return .asymmetric(insertion:.move(edge:forward ? .trailing:.leading).combined(with:.opacity),removal:.move(edge:forward ? .leading:.trailing).combined(with:.opacity))
        case .vertical:return .asymmetric(insertion:.move(edge:forward ? .bottom:.top).combined(with:.opacity),removal:.move(edge:forward ? .top:.bottom).combined(with:.opacity))
        case .fade:return .opacity
        case .zoom:return .asymmetric(insertion:.scale(scale:1.14).combined(with:.opacity),removal:.scale(scale:0.88).combined(with:.opacity))
        case .card:return .modifier(active:StoryCardFlip(angle:forward ? 72:-72,opacity:0),identity:StoryCardFlip(angle:0,opacity:1))
        case .reveal:return .asymmetric(insertion:.offset(x:forward ? 90:-90,y:24).combined(with:.scale(scale:0.87)).combined(with:.opacity),removal:.offset(x:forward ? -90:90,y:-24).combined(with:.opacity))
        case .book:return .modifier(active:PageFold(angle:forward ? -88:88,anchor:forward ? .leading:.trailing,opacity:0),identity:PageFold(angle:0,anchor:forward ? .leading:.trailing,opacity:1))
        case .floating:return .modifier(active:FloatingFrame(amount:1),identity:FloatingFrame(amount:0))
        case .film:return .asymmetric(insertion:.move(edge:forward ? .trailing:.leading),removal:.move(edge:forward ? .leading:.trailing))
        case .petal:return .modifier(active:ArtReveal(progress:0,style:.petal),identity:ArtReveal(progress:1,style:.petal))
        case .dust:return .modifier(active:ArtReveal(progress:0,style:.dust),identity:ArtReveal(progress:1,style:.dust))
        case .depth:return .asymmetric(insertion:.scale(scale:1.3).combined(with:.offset(x:forward ? 55:-55)).combined(with:.opacity),removal:.scale(scale:0.76).combined(with:.opacity))
        case .ink:return .modifier(active:ArtReveal(progress:0,style:.ink),identity:ArtReveal(progress:1,style:.ink))
        case .hanging:return .modifier(active:PageFold(angle:0,anchor:.top,opacity:0),identity:PageFold(angle:0,anchor:.top,opacity:1)).combined(with:.offset(y:-85)).combined(with:.opacity)
        }
    }
}
private struct StoryCardFlip:AnimatableModifier{
    var angle:Double
    var opacity:Double
    var animatableData:AnimatablePair<Double,Double>{get{AnimatablePair(angle,opacity)}set{angle=newValue.first;opacity=newValue.second}}
    func body(content:Content)->some View{content.rotation3DEffect(.degrees(angle),axis:(x:0,y:1,z:0),perspective:0.65).opacity(opacity)}
}
struct TimelineTreeYear:Identifiable{
    let group:TimelineGroup
    let months:[TimelineTreeMonth]
    var id:String{group.key}
}
struct TimelineTreeMonth:Identifiable{
    let group:TimelineGroup
    let days:[TimelineGroup]
    var id:String{group.key}
}
enum TimelineTreeIndex{
    static func build(_ shots:[Shot],newest:Bool)->[TimelineTreeYear]{
        TimelineIndex.group(shots,period:.year,newest:newest).map{year in
            TimelineTreeYear(group:year,months:TimelineIndex.group(year.items,period:.month,newest:newest).map{month in
                TimelineTreeMonth(group:month,days:TimelineIndex.group(month.items,period:.day,newest:newest))
            })
        }
    }
}
struct TimelineStoryTree:View{
    let shots:[Shot]
    let vault:Vault
    let newest:Bool
    let accent:Color
    let open:(Shot)->Void
    let play:([Shot])->Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var archive=StoryArchive.shared
    @AppStorage("timeline.vine.theme") private var vineValue=VineTheme.emerald.rawValue
    @AppStorage("timeline.vine.density") private var density=1.0
    @AppStorage("timeline.vine.curvature") private var curvature=1.0
    @AppStorage("timeline.vine.node") private var nodeValue=VineNode.natural.rawValue
    @State private var showVines=false
    @State private var storyTarget:StoryTarget?
    private var vine:VineTheme{VineTheme(rawValue:vineValue) ?? .emerald}
    @AppStorage("garden.seasonal") private var seasonal=false
    @AppStorage("garden.weather") private var weather=GardenAtmosphere.none.rawValue
    @AppStorage("garden.intensity") private var intensity=0.6
    @AppStorage("garden.paper") private var paper="Đêm"
    @AppStorage("garden.haptics") private var haptics=true
    @State private var expanded=Set<String>()
    @State private var initialized=false
    private var years:[TimelineTreeYear]{TimelineTreeIndex.build(shots,newest:newest)}
    var body:some View{
        ScrollViewReader{proxy in
            ScrollView{
                LazyVStack(alignment:.leading,spacing:0){
                    treeHeader(proxy)
                    ForEach(years){year in
                        yearRow(year).id(year.id)
                        if expanded.contains(year.id){
                            ForEach(year.months){month in
                                monthRow(month).id(month.id)
                                if expanded.contains(month.id){
                                    ForEach(month.days){day in
                                        dayRow(day).id(day.key)
                                    }
                                }
                            }
                        }
                    }
                    HStack(spacing:10){
                        Image(systemName:"circle.fill").font(.system(size:8)).foregroundStyle(accent)
                        Text(newest ? "Khởi đầu những ký ức":"Khoảnh khắc mới nhất").font(.caption).foregroundStyle(.secondary)
                    }.padding(.leading,18).padding(.vertical,18)
                }.padding(.horizontal,12)
            }.safeAreaPadding(.bottom,20)
        }.background(GardenBackground.color(paper))
        .overlay{GardenWeather(effect:GardenAtmosphere(rawValue:weather) ?? .none,intensity:intensity)}
        .sheet(isPresented:$showVines){VineCollectionView()}
        .sheet(item:$storyTarget){target in
            if archive.entry(target.id) != nil{StoryReader(target:target,vault:vault,archive:archive)}else{StoryComposer(target:target,vault:vault,archive:archive)}
        }.onAppear{
            if !initialized{initialized=true;openFirst()}
        }.onChange(of:shots.first?.id){_,_ in if expanded.isEmpty || !years.contains(where:{expanded.contains($0.id)}){openFirst()}}
    }
    private func openFirst(){
        if let year=years.first{expanded.insert(year.id);if let month=year.months.first{expanded.insert(month.id)}}
    }
    private func toggle(_ id:String){
        if haptics{UISelectionFeedbackGenerator().selectionChanged()}
        withAnimation(reduceMotion ? nil:.spring(response:0.38,dampingFraction:0.86)){
            if expanded.contains(id){expanded.remove(id)}else{expanded.insert(id)}
        }
    }
    private func treeHeader(_ proxy:ScrollViewProxy)->some View{
        VStack(alignment:.leading,spacing:12){
            HStack(alignment:.firstTextBaseline){
                VStack(alignment:.leading,spacing:4){
                    Text(vine.rawValue.uppercased()).font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(vine.leaf)
                    Text("Cây ký ức").font(.system(size:31,design:.serif))
                }
                Spacer()
                Button{showVines=true}label:{Image(systemName:"leaf.fill").font(.title3).foregroundStyle(vine.leaf).padding(10).background(vine.stem.opacity(0.16),in:Circle())}.accessibilityLabel("Bộ sưu tập dây leo")
                Menu{
                    Button("Mở tất cả"){withAnimation{expanded=Set(years.flatMap{[$0.id]+$0.months.map(\.id)})}}
                    Button("Thu gọn"){withAnimation{expanded=[]}}
                    ForEach(years){year in
                        Button(year.id){expanded.insert(year.id);withAnimation{proxy.scrollTo(year.id,anchor:.top)}}
                    }
                }label:{Image(systemName:"calendar.badge.clock").font(.title3).padding(10).background(.white.opacity(0.08),in:Circle())}
            }
            Text("\(years.count) năm · \(Set(shots.map(\.day)).count) ngày · \(shots.count) khoảnh khắc").font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal,8).padding(.vertical,14)
    }
    private func yearRow(_ year:TimelineTreeYear)->some View{
        HStack(alignment:.top,spacing:0){
            rail(0,key:year.id).frame(width:43)
            VStack(alignment:.leading,spacing:5){
            Button{toggle(year.id)}label:{
                HStack(spacing:12){
                    VStack(alignment:.leading,spacing:4){
                        Text(year.id).font(.system(size:37,weight:.light,design:.serif)).foregroundStyle(accent)
                        Text("\(year.months.count) tháng · \(year.group.items.count) ảnh").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength:5)
                    Image(systemName:expanded.contains(year.id) ? "chevron.up":"chevron.down").font(.caption.weight(.semibold))
                }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
                    .background(.white.opacity(0.065),in:RoundedRectangle(cornerRadius:15))
            }.buttonStyle(.plain)
            storyButton(.group(year.group))
            chapterPlay(year.group)
            }.padding(.vertical,5)
        }
    }
    private func monthRow(_ month:TimelineTreeMonth)->some View{
        HStack(alignment:.top,spacing:0){
            rail(1,key:month.id).frame(width:62)
            VStack(alignment:.leading,spacing:5){
            Button{toggle(month.id)}label:{
                HStack(spacing:10){
                    DiskImage(url:vault.thumbnail(month.group.cover.id),limit:180).scaledToFill().frame(width:56,height:56).clipped().clipShape(RoundedRectangle(cornerRadius:8))
                    VStack(alignment:.leading,spacing:4){
                        Text(TimelineIndex.label(month.id)).font(.system(.headline,design:.serif))
                        Text("\(month.days.count) ngày · \(month.group.items.count) ảnh").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength:4)
                    Image(systemName:expanded.contains(month.id) ? "minus.circle":"plus.circle").foregroundStyle(accent)
                }.padding(8).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
            }.buttonStyle(.plain)
            storyButton(.group(month.group))
            chapterPlay(month.group)
            }.padding(.vertical,4)
        }
    }
    private func chapterPlay(_ group:TimelineGroup)->some View{
        Button{play(group.items)}label:{Label("Phát chương · \(group.items.count) ảnh",systemImage:"play.circle").font(.caption2.weight(.medium)).foregroundStyle(vine.bloom).padding(.vertical,4)}
            .buttonStyle(.plain)
    }
    private func rail(_ level:Int,key:String)->some View{VineRail(level:level,theme:seasonal ? GardenBackground.season(key,fallback:vine):vine,density:density,curvature:curvature,node:VineNode(rawValue:nodeValue) ?? .natural,useCustom:!seasonal)}
    private func storyButton(_ target:StoryTarget)->some View{
        let entry=archive.entry(target.id)
        return Button{
            if haptics{UISelectionFeedbackGenerator().selectionChanged()};storyTarget=target
        }label:{
            HStack(alignment:.top,spacing:7){
                Image(systemName:entry == nil ? "pencil.line":"book.closed.fill").foregroundStyle(vine.bloom).font(.caption)
                VStack(alignment:.leading,spacing:3){
                    Text(entry == nil ? "Viết story" : (entry?.title.isEmpty == false ? entry?.title ?? "Story":"Đọc story")).font(.caption.weight(.semibold))
                    if let entry,!entry.body.isEmpty{Text(entry.body).font(.caption2).foregroundStyle(.secondary).lineLimit(2)}
                    if let mood=entry?.mood{Text(mood.rawValue).font(.caption2).foregroundStyle(vine.leaf)}
                }
                Spacer(minLength:0)
                if entry?.audio != nil{Image(systemName:"waveform").font(.caption).foregroundStyle(vine.bloom)}
            }.padding(8).frame(maxWidth:.infinity,alignment:.leading)
                .background(vine.stem.opacity(0.12),in:RoundedRectangle(cornerRadius:9))
        }.buttonStyle(.plain)
    }
    private func dayRow(_ day:TimelineGroup)->some View{
        HStack(alignment:.top,spacing:0){
            rail(2,key:day.key).frame(width:79)
            VStack(alignment:.leading,spacing:8){
                HStack{
                    VStack(alignment:.leading,spacing:3){
                        Text(TimelineIndex.label(day.key)).font(.system(.headline,design:.serif))
                        Text("\(day.items.count) khoảnh khắc").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button{play(day.items)}label:{
                        Image(systemName:"play.fill").font(.caption).foregroundStyle(.black).frame(width:34,height:34).background(accent,in:Circle())
                    }.accessibilityLabel("Trình diễn ảnh ngày này")
                }
                storyButton(.group(day))
                StoryStrip(shots:day.items,vault:vault,accent:vine.bloom,archive:archive,open:open,story:{storyTarget = .photo($0)})
                if let note=day.cover.note,!note.isEmpty{Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(3)}
            }.padding(.vertical,12)
        }.scrollTransition(.interactive,axis:.vertical){content,phase in
            content.opacity(reduceMotion || phase.isIdentity ? 1:0.72).scaleEffect(reduceMotion || phase.isIdentity ? 1:0.96,anchor:.leading)
        }
    }
}
private struct StoryStrip:View{
    let shots:[Shot]
    let vault:Vault
    let accent:Color
    @ObservedObject var archive:StoryArchive
    let open:(Shot)->Void
    let story:(Shot)->Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var current:UUID?
    var body:some View{
        VStack(alignment:.leading,spacing:6){
            ScrollView(.horizontal,showsIndicators:false){
                LazyHStack(spacing:8){
                    ForEach(shots){shot in
                        VStack(alignment:.leading,spacing:5){
                        Button{open(shot)}label:{
                            Color.clear.aspectRatio(1.38,contentMode:.fit)
                                .overlay{DiskImage(url:vault.picture(shot),limit:700).scaledToFill()}
                                .clipped()
                                .overlay(alignment:.bottomLeading){
                                    if !shot.session.isEmpty{Text(shot.session).font(.caption2.weight(.medium)).lineLimit(1).padding(7).background(.black.opacity(0.62),in:Capsule()).padding(8)}
                                }
                                .clipShape(RoundedRectangle(cornerRadius:12))
                                .overlay{RoundedRectangle(cornerRadius:12).strokeBorder(.white.opacity(0.1),lineWidth:1)}
                        }.buttonStyle(.plain)
                        Button{story(shot)}label:{
                            HStack{Image(systemName:archive.entry(StoryTarget.photo(shot).id) == nil ? "pencil.line":"book.closed.fill").foregroundStyle(accent);Text(archive.entry(StoryTarget.photo(shot).id)?.title.isEmpty == false ? archive.entry(StoryTarget.photo(shot).id)?.title ?? "Story":"Story ảnh").lineLimit(1);Spacer();if archive.entry(StoryTarget.photo(shot).id)?.audio != nil{Image(systemName:"waveform")}}.font(.caption).padding(7).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:7))
                        }.buttonStyle(.plain)
                        }
                        .containerRelativeFrame(.horizontal){length,_ in max(1,length*(shots.count>1 ? 0.87:1))}
                        .scrollTransition(.interactive,axis:.horizontal){content,phase in
                            content.scaleEffect(reduceMotion || phase.isIdentity ? 1:0.88).opacity(reduceMotion || phase.isIdentity ? 1:0.65).rotation3DEffect(.degrees(reduceMotion ? 0:phase.value*11),axis:(x:0,y:1,z:0))
                        }.id(shot.id)
                    }
                }.scrollTargetLayout()
            }.scrollTargetBehavior(.viewAligned).scrollPosition(id:$current)
            if shots.count>1{
                HStack(spacing:5){
                    ForEach(Array(shots.prefix(12))){s in
                        Capsule().fill((current ?? shots.first?.id)==s.id ? accent:Color.white.opacity(0.18)).frame(width:(current ?? shots.first?.id)==s.id ? 16:5,height:4)
                    }
                    Spacer()
                    Text("\((shots.firstIndex{$0.id==current} ?? 0)+1)/\(shots.count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }.animation(reduceMotion ? nil:.easeInOut(duration:0.2),value:current)
            }
        }
    }
}
struct TimelineSlideStage:View{
    let shots:[Shot]
    let vault:Vault
    var initial:UUID?=nil
    var autoplay=false
    var open:((Shot)->Void)?=nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("timeline.story.effect") private var effectValue=StoryEffect.zoom.rawValue
    @AppStorage("timeline.story.interval") private var interval=4
    @State private var playing=false
    @State private var index=0
    @State private var forward=true
    @State private var progress=0.0
    @State private var initialized=false
    @State private var motion=false
    @AppStorage("garden.haptics") private var haptics=true
    @ObservedObject private var archive=StoryArchive.shared
    @StateObject private var voice=StoryVoice()
    @State private var storyTarget:StoryTarget?
    @State private var narration=true
    @State private var musicPicker=false
    @State private var musicData:Data?
    @State private var musicName=""
    @State private var music:AVAudioPlayer?
    @State private var musicVolume=0.25
    @State private var soundIssue=""
    private func storyKeys(_ shot:Shot)->[String]{
        ["photo:"+shot.id.uuidString,"period:"+shot.day,"period:"+String(shot.day.prefix(7)),"period:"+String(shot.day.prefix(4))]
    }
    private func entry(_ shot:Shot)->StoryEntry?{storyKeys(shot).compactMap{archive.entry($0)}.first}
    private func target(_ shot:Shot)->StoryTarget{
        guard let e=entry(shot) else{return .photo(shot)}
        if e.id.hasPrefix("photo:"){return .photo(shot)}
        let key=String(e.id.dropFirst("period:".count))
        return .group(TimelineGroup(key:key,items:shots.filter{$0.day.hasPrefix(key)}))
    }
    private func narrationData(_ shot:Shot)->Data?{
        if let own=archive.entry(StoryTarget.photo(shot).id)?.audio{return own}
        for length in [10,7,4]{
            let key=String(shot.day.prefix(length))
            if index==0 || String(shots[index-1].day.prefix(length)) != key{
                if let audio=archive.entry("period:"+key)?.audio{return audio}
            }
        }
        return nil
    }
    private var effect:StoryEffect{StoryEffect(rawValue:effectValue) ?? .zoom}
    private var shot:Shot?{shots.indices.contains(index) ? shots[index]:nil}
    var body:some View{
        VStack(spacing:12){
            if let shot{
                HStack{
                    VStack(alignment:.leading,spacing:3){
                        Text("P H O T O   S T O R Y").font(.caption2.monospaced()).foregroundStyle(gold)
                        Text(TimelineIndex.label(shot.day)).font(.system(.title2,design:.serif))
                    }
                    Spacer()
                    Menu{
                        ForEach(StoryEffect.allCases,id:\.self){style in
                            Button{effectValue=style.rawValue}label:{if effect==style{Label(style.rawValue,systemImage:"checkmark")}else{Text(style.rawValue)}}
                        }
                        Divider()
                        Button(narration ? "Tắt lời kể":"Bật lời kể"){narration.toggle();if !narration{voice.stopPlayback()}}
                        Button("Chọn nhạc nền"){playing=false;musicPicker=true}
                        if musicData != nil{Button("Bỏ nhạc nền",role:.destructive){music?.stop();music=nil;musicData=nil;musicName=""}}
                        Divider()
                        ForEach([2,4,6,8],id:\.self){n in Button("\(n) giây / ảnh"){interval=n}}
                    }label:{Label(effect.rawValue,systemImage:"sparkles").font(.caption).padding(8).background(.white.opacity(0.08),in:Capsule())}
                }
                stage(shot)
                if let e=entry(shot),e.hasContent{
                    Button{playing=false;storyTarget=target(shot)}label:{
                        HStack{Image(systemName:"book.closed.fill").foregroundStyle(gold);Text(e.title.isEmpty ? "Đọc story":e.title).lineLimit(1);Spacer();if e.audio != nil{Image(systemName:"waveform")};Image(systemName:"chevron.right").font(.caption)}
                    }.buttonStyle(.plain).font(.caption).padding(8)
                }
                if musicData != nil{HStack{Image(systemName:"music.note");Text(musicName).lineLimit(1);Slider(value:$musicVolume,in:0...0.8)}.font(.caption)}
                if !soundIssue.isEmpty{Text(soundIssue).font(.caption2).foregroundStyle(.secondary)}
                ProgressView(value:progress).tint(gold)
                HStack{
                    Button{move(-1)}label:{Image(systemName:"backward.end.fill").frame(width:44,height:44)}
                    Spacer()
                    Button{playing.toggle();progress=0}label:{
                        Image(systemName:playing ? "pause.fill":"play.fill").font(.title2).foregroundStyle(.black).frame(width:56,height:56).background(gold,in:Circle())
                    }.accessibilityLabel(playing ? "Tạm dừng":"Phát slide").disabled(shots.isEmpty)
                    Spacer()
                    Button{move(1)}label:{Image(systemName:"forward.end.fill").frame(width:44,height:44)}
                }.buttonStyle(.plain)
                filmstrip
            }else{ContentUnavailableView("Chưa có ảnh",systemImage:"photo.stack")}
        }.padding(14)
            .onAppear{if !initialized{index=shots.firstIndex{$0.id==initial} ?? 0;initialized=true;playing=autoplay && !shots.isEmpty}}
            .onChange(of:shots.map(\.id)){_,_ in index=0;progress=0}
            .task(id:shot?.id){
                motion=false
                guard !reduceMotion else{return}
                do{try await Task.sleep(for:.milliseconds(80))}catch{return}
                if !Task.isCancelled{animateMotion()}
            }
            .onChange(of:scenePhase){_,p in if p != .active{playing=false;voice.stopPlayback();music?.pause()}}
            .onChange(of:musicVolume){_,v in music?.volume=Float(v)}
            .onChange(of:playing){_,p in if p{startMusic()}else{voice.stopPlayback();music?.pause()}}
            .onDisappear{voice.cancel();music?.stop();music=nil}
            .sheet(item:$storyTarget){target in StoryReader(target:target,vault:vault,archive:archive)}
            .fileImporter(isPresented:$musicPicker,allowedContentTypes:[.audio]){result in
                do{let url=try result.get(),access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}};let size=(try url.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0;guard size<=30_000_000 else{throw CameraError.unreadable};let data=try Data(contentsOf:url);_ = try AVAudioPlayer(data:data);music?.stop();music=nil;musicData=data;musicName=url.lastPathComponent;soundIssue=""}catch{soundIssue=error.localizedDescription}
            }
            .task(id:"\(playing)-\(interval)-\(index)-\(narration)"){
                voice.stopPlayback()
                guard playing,let shot else{return}
                startMusic()
                var duration=Double(max(1,interval))
                if narration,let data=narrationData(shot){duration=max(duration,voice.play(data))}
                let steps=max(1,Int(duration*20))
                for tick in 1...steps{
                    do{try await Task.sleep(for:.milliseconds(50))}catch{return}
                    if Task.isCancelled{return}
                    progress=Double(tick)/Double(steps)
                }
                if shots.count>1{move(1)}else{playing=false}
            }
    }
    private func stage(_ shot:Shot)->some View{
        ZStack{
            RoundedRectangle(cornerRadius:18).fill(.black)
            ZStack{
                GeometryReader{g in
                    ZStack{
                        DiskImage(url:vault.thumbnail(shot.id),limit:280).scaledToFill().frame(width:g.size.width,height:g.size.height).blur(radius:25).opacity(0.35).clipped()
                        DiskImage(url:vault.picture(shot),limit:1600).scaledToFit()
                            .frame(width:g.size.width,height:g.size.height)
                            .scaleEffect((effect == .zoom || effect == .depth) && motion && !reduceMotion ? 1.045:1)
                            .rotationEffect(.degrees(effect == .hanging && motion && !reduceMotion ? 1.7:0))
                    }.clipped()
                }.id(shot.id).transition(reduceMotion ? .opacity:effect.transition(forward:forward))
            }.clipShape(RoundedRectangle(cornerRadius:18))
            if effect == .film{FilmPerforations().allowsHitTesting(false)}
            if effect == .hanging{VStack{HStack{Spacer();Image(systemName:"paperclip").font(.title2);Spacer()}.padding(.top,8);Spacer()}.allowsHitTesting(false)}
            VStack{
                Spacer()
                HStack(alignment:.bottom){
                    VStack(alignment:.leading,spacing:4){
                        Text(entry(shot)?.title.isEmpty == false ? entry(shot)?.title ?? "Khoảnh khắc":(shot.session.isEmpty ? "Khoảnh khắc":shot.session)).font(.system(.title2,design:.serif)).lineLimit(2)
                        if let caption=entry(shot)?.captions[shot.id.uuidString],!caption.isEmpty{Text(caption).font(.caption).lineLimit(3)}
                        else if let body=entry(shot)?.body,!body.isEmpty{Text(body).font(.caption).lineLimit(3)}
                        else if let note=shot.note,!note.isEmpty{Text(note).font(.caption).lineLimit(2)}
                        else if !shot.tags.isEmpty{Text(shot.tags).font(.caption).lineLimit(2)}
                    }
                    Spacer()
                    Text(String(format:"%02d / %02d",index+1,shots.count)).font(.caption.monospacedDigit())
                }.padding(15).background(LinearGradient(colors:[.clear,.black.opacity(0.85)],startPoint:.top,endPoint:.bottom))
            }.allowsHitTesting(false)
        }.frame(minHeight:220,maxHeight:420)
        .aspectRatio(0.9,contentMode:.fit)
        .clipShape(RoundedRectangle(cornerRadius:18))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance:30).onEnded{value in
            let delta=abs(value.translation.width)>abs(value.translation.height) ? value.translation.width:value.translation.height
            if abs(delta)>35{move(delta<0 ? 1:-1)}
        })
        .onTapGesture{if let open{playing=false;open(shot)}else{playing.toggle();progress=0}}
        .accessibilityLabel("Ảnh \(index+1) trên \(shots.count), \(shot.day)")
    }
    private var filmstrip:some View{
        ScrollViewReader{proxy in
            ScrollView(.horizontal,showsIndicators:false){
                LazyHStack(spacing:6){
                    ForEach(shots.indices,id:\.self){i in
                        Button{jump(i)}label:{
                            DiskImage(url:vault.thumbnail(shots[i].id),limit:140).scaledToFill().frame(width:49,height:60).clipped().clipShape(RoundedRectangle(cornerRadius:5))
                                .overlay{RoundedRectangle(cornerRadius:5).strokeBorder(i==index ? gold:.clear,lineWidth:2)}
                                .opacity(i==index ? 1:0.62)
                        }.buttonStyle(.plain).id(i)
                    }
                }
            }.frame(height:60).onChange(of:index){_,i in withAnimation(reduceMotion ? nil:.easeInOut(duration:0.2)){proxy.scrollTo(i,anchor:.center)}}
        }
    }
    private func jump(_ target:Int){
        guard shots.indices.contains(target),target != index else{return}
        forward=target>index;progress=0;motion=false
        if haptics{UISelectionFeedbackGenerator().selectionChanged()}
        withAnimation(reduceMotion ? .easeOut(duration:0.15):.easeInOut(duration:0.48)){index=target}
    }
    private func move(_ delta:Int){
        guard shots.count>1 else{return}
        let target=(index+delta+shots.count)%shots.count
        forward=delta>0;progress=0;motion=false
        withAnimation(reduceMotion ? .easeOut(duration:0.15):.easeInOut(duration:0.48)){index=target}
    }
    private func startMusic(){
        guard let data=musicData else{return}
        do{
            let session=AVAudioSession.sharedInstance();try session.setCategory(.playback,mode:.default,options:[.mixWithOthers]);try session.setActive(true)
            if music==nil{let p=try AVAudioPlayer(data:data);p.numberOfLoops = -1;music=p}
            music?.volume=Float(musicVolume);music?.play()
        }catch{soundIssue=error.localizedDescription}
    }
    private func animateMotion(){
        guard !reduceMotion else{return}
        withAnimation(.easeInOut(duration:Double(max(2,interval)))){motion=true}
    }
}

private struct PageFold:AnimatableModifier{
    var angle:Double
    let anchor:UnitPoint
    var opacity:Double
    var animatableData:AnimatablePair<Double,Double>{get{.init(angle,opacity)}set{angle=newValue.first;opacity=newValue.second}}
    func body(content:Content)->some View{content.rotation3DEffect(.degrees(angle),axis:(x:0,y:1,z:0),anchor:anchor,perspective:0.7).opacity(opacity)}
}
private struct FloatingFrame:AnimatableModifier{
    var amount:Double
    var animatableData:Double{get{amount}set{amount=newValue}}
    func body(content:Content)->some View{content.scaleEffect(1-0.32*amount).offset(x:70*amount,y:-85*amount).rotationEffect(.degrees(12*amount)).opacity(1-amount)}
}
private struct ArtReveal:AnimatableModifier{
    var progress:Double
    let style:StoryEffect
    var animatableData:Double{get{progress}set{progress=newValue}}
    func body(content:Content)->some View{
        content.mask{
            Canvas{ctx,size in
                let p=max(0,min(1,progress))
                if p>=0.995{ctx.fill(Path(CGRect(origin:.zero,size:size)),with:.color(.white));return}
                if style == .dust{
                    let cols=14,rows=18,w=size.width/CGFloat(cols),h=size.height/CGFloat(rows)
                    for y in 0..<rows{for x in 0..<cols{
                        let order=Double((x*73+y*31)%97)/97
                        if p>order{ctx.fill(Path(CGRect(x:CGFloat(x)*w,y:CGFloat(y)*h,width:w+0.5,height:h+0.5)),with:.color(.white))}
                    }}
                }else{
                    let count=style == .petal ? 7:12
                    let reach=hypot(size.width,size.height)*CGFloat(p)
                    for i in 0..<count{
                        let a=Double(i)*2*Double.pi/Double(count)
                        let offset=style == .petal ? reach*0.24:reach*0.17
                        let x=size.width/2+CGFloat(cos(a))*offset,y=size.height/2+CGFloat(sin(a))*offset
                        let r=reach*(style == .petal ? 0.48:0.38)
                        ctx.fill(Path(ellipseIn:CGRect(x:x-r,y:y-r,width:r*2,height:r*2)),with:.color(.white))
                    }
                }
            }
        }.overlay{
            if progress<0.98 && progress>0.01{
                GardenWeather(effect:style == .petal ? .petals:style == .dust ? .gold:.none,intensity:0.7*(1-progress))
            }
        }
    }
}
private struct FilmPerforations:View{
    var body:some View{
        VStack{strip;Spacer();strip}.padding(.vertical,4)
    }
    private var strip:some View{
        HStack(spacing:6){ForEach(0..<14,id:\.self){_ in RoundedRectangle(cornerRadius:2).fill(.white.opacity(0.6)).frame(width:10,height:6)}}.frame(maxWidth:.infinity).padding(5).background(.black.opacity(0.8))
    }
}
