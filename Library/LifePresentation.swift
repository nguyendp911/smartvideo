import SwiftUI

enum LifePathMode:String,CaseIterable,Identifiable{
    var id:String{rawValue}
    case journey="Life Journey",river="Memory River"
}
struct LifePathView:View{
    let shots:[Shot]
    let vault:Vault
    let mode:LifePathMode
    @ObservedObject private var archive=StoryArchive.shared
    @ObservedObject private var life=LifeArchive.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var target:StoryTarget?
    @State private var newest=false
    private var groups:[TimelineGroup]{
        let days=MemorySync.activeDays(shots:shots,stories:archive,life:life)
        let byDay=Dictionary(grouping:shots,by:\.day)
        return days.sorted{newest ? $0>$1:$0<$1}.map{TimelineGroup(key:$0,items:byDay[$0] ?? [])}
    }
    var body:some View{
        NavigationStack{
            ScrollView{
                LazyVStack(spacing:0){
                    VStack(alignment:.leading,spacing:5){Text("V I E L E N S  /  J O U R N E Y").font(.caption2.monospaced()).foregroundStyle(gold);Text(mode.rawValue).font(.system(size:35,design:.serif));Text("\(groups.count) ngày đáng nhớ").font(.caption).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading).padding()
                    ForEach(Array(groups.enumerated()),id:\.offset){i,g in
                        GeometryReader{geo in
                            let width=geo.size.width,center=width/2
                            ZStack{
                                Canvas{ctx,size in
                                    var path=Path();path.move(to:CGPoint(x:center,y:0))
                                    path.addCurve(to:CGPoint(x:center,y:size.height),control1:CGPoint(x:center+(i%2==0 ? 28:-28),y:size.height*0.35),control2:CGPoint(x:center+(i%2==0 ? -28:28),y:size.height*0.7))
                                    ctx.stroke(path,with:.color(mode == .river ? .cyan.opacity(0.10):gold.opacity(0.12)),style:StrokeStyle(lineWidth:mode == .river ? 28:10,lineCap:.round))
                                    ctx.stroke(path,with:.color(mode == .river ? .mint.opacity(0.6):gold.opacity(0.7)),style:StrokeStyle(lineWidth:mode == .river ? 2:1.5,lineCap:.round,dash:mode == .river ? []:[5,4]))
                                }
                                Circle().fill(gold).frame(width:9,height:9).shadow(color:gold,radius:6).position(x:center,y:geo.size.height/2)
                                Button{target=MemorySync.target(day:g.key,shots:shots)}label:{
                                    VStack(alignment:.leading,spacing:5){
                                        if let cover=MemorySync.cover(g.items,entry:archive.entry("period:"+g.key)){DiskImage(url:vault.thumbnail(cover.id),limit:320).scaledToFill().frame(height:90).clipped().clipShape(RoundedRectangle(cornerRadius:8))}
                                        Text(TimelineIndex.label(g.key)).font(.caption.weight(.semibold))
                                        if let e=archive.entry("period:"+g.key){Text(e.title.isEmpty ? e.body:e.title).font(.caption2).lineLimit(2)}
                                        ForEach(life.milestones(g.key).prefix(2)){m in Label(m.title,systemImage:m.icon).font(.caption2).foregroundStyle(gold)}
                                        Text("\(g.items.count) ảnh").font(.caption2).foregroundStyle(.secondary)
                                    }.frame(width:max(80,width/2-28),alignment:.leading).padding(8).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:12))
                                }.buttonStyle(.plain).position(x:i%2==0 ? width/4:width*3/4,y:geo.size.height/2)
                            }
                        }.frame(height:185)
                            .scrollTransition(.interactive,axis:.vertical){content,phase in content.opacity(reduced || phase.isIdentity ? 1:0.65).scaleEffect(reduced || phase.isIdentity ? 1:0.94)}
                    }
                }.padding(.horizontal,12)
            }.background(mode == .river ? Color(red:0.035,green:0.11,blue:0.16):night)
                .overlay{if mode == .river{GardenWeather(effect:.firefly,intensity:0.25)}}
                .navigationTitle(mode.rawValue).navigationBarTitleDisplayMode(.inline).toolbar{
                    ToolbarItem(placement:.cancellationAction){Button("Đóng"){dismiss()}}
                    ToolbarItem(placement:.confirmationAction){Button(newest ? "Mới nhất":"Cũ nhất"){newest.toggle()}}
                }
        }.sheet(item:$target){LifeStorySheet(target:$0,vault:vault,archive:archive)}
    }
}
enum StoryPresentation:String,CaseIterable,Codable{
    case magazine="Magazine",letter="Memory Letter",cinema="Story Cinema",scrapbook="Scrapbook",book="Story Book",podcast="Podcast"
}
struct StoryPresentationStudio:View{
    let story:StoryEntry
    let target:StoryTarget
    let vault:Vault
    @ObservedObject var archive:StoryArchive
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduced
    @StateObject private var voice=StoryVoice()
    @State private var style=StoryPresentation.magazine
    @State private var opened=false
    @State private var page=0
    @State private var notice=""
    private var cover:Shot?{MemorySync.cover(target.shots,entry:story)}
    var body:some View{
        NavigationStack{
            VStack(spacing:10){
                ScrollView(.horizontal,showsIndicators:false){HStack{ForEach(StoryPresentation.allCases,id:\.self){p in Button{voice.stopPlayback();style=p;opened=false;page=0}label:{Text(p.rawValue).font(.caption.weight(.semibold)).padding(9).background(style==p ? gold.opacity(0.25):.white.opacity(0.07),in:Capsule())}.buttonStyle(.plain)}}.padding(.horizontal)}
                ScrollView{
                    switch style{
                    case .magazine:magazine
                    case .letter:letter
                    case .cinema:TimelineSlideStage(shots:target.shots,vault:vault,autoplay:true)
                    case .scrapbook:scrapbook
                    case .book:book
                    case .podcast:podcast
                    }
                }
                if !notice.isEmpty{Text(notice).font(.caption)}
            }.navigationTitle("Story Presentation").navigationBarTitleDisplayMode(.inline).toolbar{
                ToolbarItem(placement:.cancellationAction){Button("Đóng"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button("Lưu kiểu"){
                    var value=archive.entry(target.id) ?? story;value.presentation=style
                    let draft=archive.drafts[target.id]
                    do{try archive.save(value,draft:false);if var draft{draft.presentation=style;try archive.save(draft,draft:true)};notice="Đã lưu phong cách."}catch{notice=error.localizedDescription}
                }}
            }
        }.onAppear{style=story.presentation ?? .magazine}.onDisappear{voice.cancel()}
    }
    private var magazine:some View{
        VStack(alignment:.leading,spacing:16){
            Text("V I E L E N S  /  M E M O R I E S").font(.caption2.monospaced()).tracking(3).foregroundStyle(gold)
            if let cover{DiskImage(url:vault.picture(cover),limit:1400).scaledToFit().clipShape(RoundedRectangle(cornerRadius:3))}
            Text(story.title.isEmpty ? target.label:story.title).font(.system(size:38,design:.serif))
            Rectangle().fill(gold).frame(height:1)
            Text(story.body).font(.system(.body,design:.serif)).lineSpacing(7)
            ForEach(Array((story.chapters ?? []).enumerated()),id:\.offset){i,c in Text("CHƯƠNG \(i+1)").font(.caption2.monospaced()).foregroundStyle(gold);Text(c).font(.system(.body,design:.serif))}
            if !story.quote.isEmpty{Text("“\(story.quote)”").font(.system(.title2,design:.serif)).italic().foregroundStyle(gold)}
        }.padding(22)
    }
    private var letter:some View{
        VStack(spacing:20){
            if opened{
                VStack(alignment:.leading,spacing:14){
                    Text(story.title.isEmpty ? "Gửi người đọc":story.title).font(.system(.title,design:.serif))
                    Text(story.body).font(.custom("Noteworthy",size:18)).lineSpacing(8)
                    Text(story.quote).italic()
                }.foregroundStyle(Color(red:0.23,green:0.15,blue:0.08)).padding(24).frame(maxWidth:.infinity,alignment:.leading)
                    .background(Color(red:0.91,green:0.83,blue:0.67),in:RoundedRectangle(cornerRadius:8)).transition(.scale(scale:0.85,anchor:.bottom).combined(with:.opacity))
            }
            Button{withAnimation(reduced ? nil:.spring(response:0.65,dampingFraction:0.82)){opened.toggle()}}label:{
                VStack(spacing:10){Image(systemName:opened ? "envelope.open.fill":"envelope.fill").font(.system(size:85)).foregroundStyle(gold);Text(opened ? "Gấp thư":"Mở phong bì").font(.system(.headline,design:.serif))}
                    .frame(maxWidth:.infinity).padding(24).background(.white.opacity(0.055),in:RoundedRectangle(cornerRadius:16))
            }.buttonStyle(.plain)
        }.padding(20)
    }
    private var scrapbook:some View{
        VStack(spacing:16){
            Text(story.title.isEmpty ? target.label:story.title).font(.system(.largeTitle,design:.serif))
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:18){
                ForEach(Array(target.shots.enumerated()),id:\.offset){i,shot in
                    VStack(spacing:4){
                        DiskImage(url:vault.thumbnail(shot.id),limit:600).scaledToFill().frame(height:130).clipped()
                        Text(story.captions[shot.id.uuidString] ?? shot.day).font(.caption2).foregroundStyle(.black).lineLimit(2)
                    }.padding(7).padding(.bottom,8).background(.white).rotationEffect(.degrees(i%2==0 ? -4:4)).overlay(alignment:.topTrailing){Image(systemName:"leaf.fill").foregroundStyle(.green).offset(x:7,y:-7)}
                }
            }
            Text(story.body).font(.custom("Noteworthy",size:17))
        }.padding(22)
    }
    private var pages:[String]{[story.body]+(story.chapters ?? [])}
    private var book:some View{
        VStack(spacing:18){
            Text("Trang \(page+1) / \(pages.count)").font(.caption.monospacedDigit()).foregroundStyle(gold)
            ZStack{
                VStack(alignment:.leading,spacing:14){
                    Text(page==0 ? story.title:"Chương \(page)").font(.system(.title,design:.serif))
                    Text(pages[page]).font(.system(.body,design:.serif)).lineSpacing(8)
                }.padding(24).frame(maxWidth:.infinity,minHeight:320,alignment:.topLeading).foregroundStyle(.black)
                    .background(Color(red:0.93,green:0.88,blue:0.78),in:RoundedRectangle(cornerRadius:7)).id(page)
                    .transition(.asymmetric(insertion:.move(edge:.trailing).combined(with:.opacity),removal:.move(edge:.leading).combined(with:.opacity)))
            }.clipped()
            HStack{Button("Trang trước"){turn(-1)}.disabled(page==0);Spacer();Button("Trang sau"){turn(1)}.disabled(page+1>=pages.count)}
        }.padding(20)
    }
    private func turn(_ n:Int){withAnimation(reduced ? nil:.easeInOut(duration:0.35)){page=max(0,min(pages.count-1,page+n))}}
    private var podcast:some View{
        VStack(spacing:18){
            Image(systemName:"waveform.circle").font(.system(size:110)).foregroundStyle(gold)
            Text(story.title).font(.system(.title,design:.serif))
            if let audio=story.audio{Button(voice.playing ? "Dừng lời kể":"Phát lời kể",systemImage:voice.playing ? "stop.fill":"play.fill"){if voice.playing{voice.stopPlayback()}else{voice.play(audio)}}.buttonStyle(.borderedProminent)}
            else{Text("Story chưa có lời kể.").foregroundStyle(.secondary)}
            Text(story.body).font(.caption).lineSpacing(5)
        }.padding(20)
    }
}
