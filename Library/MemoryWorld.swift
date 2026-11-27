import SwiftUI
import AVFoundation
import MapKit
import UIKit

enum MemoryWorldMode:String,CaseIterable{
    case tree="Tree of Life",universe="Memory Universe",museum="Memory Museum",wall="Memory Wall",garden="Memory Garden"
}
struct MemoryWorld:View{
    let shots:[Shot]
    let vault:Vault
    @ObservedObject private var archive=StoryArchive.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var mode=MemoryWorldMode.tree
    @State private var zoom=1.0
    @State private var selection:TimelineGroup?
    @State private var story:StoryTarget?
    @State private var offset=CGSize.zero
    @State private var origin=CGSize.zero
    @AppStorage("world.wall.positions") private var wallData=Data()
    @State private var positions=[String:WallPosition]()
    private var years:[TimelineGroup]{TimelineIndex.group(shots,period:.year,newest:false)}
    private var collections:[TimelineGroup]{TimelineIndex.collections(shots)}
    private var items:[TimelineGroup]{mode == .garden || mode == .universe ? (collections.isEmpty ? years:collections):years}
    var body:some View{
        NavigationStack{
            VStack(spacing:10){
                ScrollView(.horizontal,showsIndicators:false){
                    HStack{ForEach(MemoryWorldMode.allCases,id:\.self){m in Button{mode=m;zoom=1;offset = .zero;origin = .zero}label:{Text(m.rawValue).font(.caption.weight(.medium)).padding(10).background(m==mode ? gold.opacity(0.25):.white.opacity(0.06),in:Capsule())}.buttonStyle(.plain)}}
                }.padding(.horizontal)
                if shots.isEmpty{ContentUnavailableView("Chưa có ký ức",systemImage:"photo.stack")}
                else if mode == .museum{museum}
                else if mode == .wall{wall}
                else{mapCanvas}
                if mode != .museum && mode != .wall{
                    HStack{Image(systemName:"minus.magnifyingglass");Slider(value:$zoom,in:0.7...2.5);Image(systemName:"plus.magnifyingglass");Button("Đặt lại"){zoom=1;offset = .zero;origin = .zero}.font(.caption)}.padding(.horizontal)
                    Text("Kéo để di chuyển · Chạm vào nhánh để khám phá").font(.caption2).foregroundStyle(.secondary)
                }
            }.background(night).navigationTitle("Memory World").navigationBarTitleDisplayMode(.inline).toolbar{Button("Xong"){dismiss()}}
        }.sheet(item:$selection){group in
            NavigationStack{
                ScrollView{
                    VStack(spacing:12){
                        Text(group.key).font(.system(.largeTitle,design:.serif))
                        ForEach(group.items){shot in
                            Button{story = .photo(shot)}label:{
                                VStack(alignment:.leading){DiskImage(url:vault.picture(shot),limit:900).scaledToFit().clipShape(RoundedRectangle(cornerRadius:13));Text(archive.entry(StoryTarget.photo(shot).id)?.title ?? shot.day).font(.caption)}
                            }.buttonStyle(.plain)
                        }
                    }.padding()
                }.navigationTitle("Ký ức").toolbar{Button("Đóng"){selection=nil}}
                .sheet(item:$story){target in StoryReader(target:target,vault:vault,archive:archive)}
            }
        }.onAppear{positions=(try? JSONDecoder().decode([String:WallPosition].self,from:wallData)) ?? [:]}
    }
    private func point(_ index:Int,count:Int,size:CGSize)->CGPoint{
        let n=max(1,count),angle=Double(index)*2*Double.pi/Double(n)-Double.pi/2
        if mode == .tree{
            let y=size.height*(0.14+0.70*CGFloat(index)/CGFloat(max(1,n-1)))
            return CGPoint(x:size.width*(index%2==0 ? 0.25:0.75),y:y)
        }
        let r=min(size.width,size.height)*0.34
        return CGPoint(x:size.width/2+CGFloat(cos(angle))*r,y:size.height/2+CGFloat(sin(angle))*r)
    }
    private var mapCanvas:some View{
        GeometryReader{g in
            let visible=Array(items.prefix(24)),size=g.size
            ZStack{
                LinearGradient(colors:[Color(red:0.05,green:0.12,blue:0.12),.black],startPoint:.top,endPoint:.bottom)
                ZStack{
                    Canvas{ctx,s in
                        let center=CGPoint(x:s.width/2,y:mode == .tree ? s.height*0.91:s.height/2)
                        if mode == .universe{
                            for i in 0..<110{
                                let x=CGFloat((i*79)%997)/997*s.width,y=CGFloat((i*53)%991)/991*s.height
                                ctx.fill(Path(ellipseIn:CGRect(x:x,y:y,width:i%5==0 ? 2:1,height:i%5==0 ? 2:1)),with:.color(.white.opacity(0.24)))
                            }
                        }
                        if mode == .tree{
                            var trunk=Path();trunk.move(to:center);trunk.addQuadCurve(to:CGPoint(x:s.width/2,y:s.height*0.06),control:CGPoint(x:s.width*0.44,y:s.height*0.43))
                            ctx.stroke(trunk,with:.color(.green.opacity(0.5)),style:StrokeStyle(lineWidth:9,lineCap:.round))
                        }
                        for i in visible.indices{
                            let p=point(i,count:visible.count,size:s)
                            let start=mode == .tree ? CGPoint(x:s.width/2,y:p.y+25):center
                            var line=Path();line.move(to:start);line.addQuadCurve(to:p,control:CGPoint(x:(start.x+p.x)/2,y:p.y+35))
                            ctx.stroke(line,with:.color(gold.opacity(0.45)),style:StrokeStyle(lineWidth:mode == .tree ? 2:1,lineCap:.round))
                        }
                    }
                    ForEach(visible.indices,id:\.self){i in
                        let group=visible[i]
                        Button{selection=group}label:{
                            VStack(spacing:4){
                                DiskImage(url:vault.thumbnail(group.cover.id),limit:220).scaledToFill().frame(width:68,height:68).clipped().clipShape(Circle()).overlay{Circle().strokeBorder(gold.opacity(0.8),lineWidth:1.4)}
                                Text(group.key).font(.caption2.weight(.semibold)).lineLimit(1)
                                Text("\(group.items.count) ảnh").font(.system(size:9)).foregroundStyle(.secondary)
                            }.frame(width:100)
                        }.buttonStyle(.plain).position(point(i,count:visible.count,size:size))
                    }
                    if mode != .tree{Image(systemName:mode == .garden ? "leaf.fill":"sparkles").font(.system(size:38)).foregroundStyle(gold)}
                }.scaleEffect(zoom).offset(offset)
                if items.count>24{VStack{Spacer();Text("Hiển thị 24/\(items.count) nhánh. Duyệt đầy đủ ở Timeline.").font(.caption2).padding(7).background(.black.opacity(0.6),in:Capsule())}}
            }.clipped().gesture(DragGesture().onChanged{v in offset=CGSize(width:origin.width+v.translation.width,height:origin.height+v.translation.height)}.onEnded{_ in origin=offset})
        }
    }
    private var museum:some View{
        ScrollView(.horizontal,showsIndicators:false){
            LazyHStack(spacing:18){
                ForEach(shots){shot in
                    Button{selection=TimelineGroup(key:shot.day,items:[shot])}label:{
                        VStack(spacing:12){
                            DiskImage(url:vault.picture(shot),limit:1300).scaledToFit().frame(height:290).padding(12)
                                .background(Color(red:0.25,green:0.18,blue:0.10))
                                .overlay{Rectangle().strokeBorder(gold,lineWidth:3)}
                            Text(archive.entry(StoryTarget.photo(shot).id)?.title ?? TimelineIndex.label(shot.day)).font(.system(.headline,design:.serif))
                            Text(shot.note ?? shot.session).font(.caption).lineLimit(2).foregroundStyle(.secondary)
                        }.containerRelativeFrame(.horizontal){l,_ in l*0.84}
                    }.buttonStyle(.plain).scrollTransition(.interactive,axis:.horizontal){view,phase in view.scaleEffect(reduced || phase.isIdentity ? 1:0.88).rotation3DEffect(.degrees(reduced ? 0:phase.value*18),axis:(x:0,y:1,z:0))}
                }
            }.scrollTargetLayout().padding(.horizontal,10)
        }.scrollTargetBehavior(.viewAligned)
    }
    private struct WallPosition:Codable{var x:Double;var y:Double}
    private var wall:some View{
        GeometryReader{g in
            ZStack{
                Color(red:0.18,green:0.13,blue:0.10)
                ForEach(Array(shots.prefix(18).enumerated()),id:\.element.id){i,shot in
                    let key=shot.id.uuidString,p=positions[key] ?? WallPosition(x:Double(i%3+1)/4,y:Double(i/3+1)/7)
                    DiskImage(url:vault.thumbnail(shot.id),limit:300).scaledToFill().frame(width:82,height:94).clipped().padding(5).padding(.bottom,12).background(.white)
                        .rotationEffect(.degrees(Double(i%3-1)*5)).shadow(radius:5)
                        .position(x:CGFloat(p.x)*g.size.width,y:CGFloat(p.y)*g.size.height)
                        .gesture(DragGesture(coordinateSpace:.named("wall")).onChanged{v in
                            positions[key]=WallPosition(x:max(0.1,min(0.9,Double(v.location.x/g.size.width))),y:max(0.08,min(0.92,Double(v.location.y/g.size.height))))
                        }.onEnded{_ in if let data=try? JSONEncoder().encode(positions){wallData=data}})
                        .onTapGesture{selection=TimelineGroup(key:shot.day,items:[shot])}
                }
            }.coordinateSpace(name:"wall").clipped()
        }.overlay(alignment:.bottom){Button("Đặt lại vị trí"){positions=[:];wallData=Data()}.font(.caption).padding(8).background(.black.opacity(0.6),in:Capsule()).padding()}
    }
}
struct MemoryDiscover:View{
    let shots:[Shot]
    let vault:Vault
    @ObservedObject private var archive=StoryArchive.shared
    @Environment(\.dismiss) private var dismiss
    @State private var mode="Kỷ niệm"
    @State private var selected:TimelineGroup?
    @State private var storyTarget:StoryTarget?
    @AppStorage("world.lastViewed") private var viewedData=Data()
    @State private var viewed=[String:Date]()
    @State private var year=Calendar.current.component(.year,from:Date())
    private var groups:[TimelineGroup]{
        switch mode{
        case "Kỷ niệm":return TimelineIndex.group(shots.filter{String($0.day.suffix(5))==TimelineIndex.todaySuffix() && !$0.day.hasPrefix(String(Calendar.current.component(.year,from:Date())))},period:.year,newest:true)
        case "Lâu chưa xem":
            let old=shots.filter{Date().timeIntervalSince($0.date)>30*86400 && Date().timeIntervalSince(viewed[$0.id.uuidString] ?? .distantPast)>30*86400}
            return TimelineIndex.group(Array(old.prefix(100)),period:.month,newest:false)
        case "Cảm xúc":
            return StoryMood.allCases.compactMap{mood in
                let found=shots.filter{s in ["photo:"+s.id.uuidString,"period:"+s.day].contains{archive.entry($0)?.mood==mood}}
                return found.isEmpty ? nil:TimelineGroup(key:mood.rawValue,items:found)
            }
        case "Liên kết":
            var buckets=[String:[Shot]]()
            for s in shots{
                let story=archive.entry(StoryTarget.photo(s).id)
                let tags=(s.tags+" "+(story?.people ?? "")+" "+(story?.tags ?? "")).split(whereSeparator:{$0.isWhitespace || $0==","}).map{String($0).lowercased()}
                for tag in Set(tags) where tag.count>1{buckets[tag,default:[]].append(s)}
            }
            return buckets.filter{Set($0.value.map(\.day)).count>1}.map{TimelineGroup(key:$0.key,items:$0.value)}.sorted{$0.items.count>$1.items.count}
        case "Tổng kết":return TimelineIndex.group(shots.filter{$0.day.hasPrefix(String(year))},period:.month,newest:false)
        default:return TimelineIndex.group(shots,period:.day,newest:false)
        }
    }
    var body:some View{
        NavigationStack{
            List{
                Picker("Khám phá",selection:$mode){ForEach(["Kỷ niệm","Lâu chưa xem","Cảm xúc","Liên kết","Tổng kết","Hành trình"],id:\.self){Text($0).tag($0)}}
                if mode=="Tổng kết"{Picker("Năm",selection:$year){ForEach(Array(Set(shots.compactMap{Int($0.day.prefix(4))})).sorted(by:>),id:\.self){Text(String($0)).tag($0)}}}
                if mode=="Lâu chưa xem"{Text("Dựa trên ngày chụp và lượt mở trong mục Khám phá; không theo dõi toàn bộ lượt xem.").font(.caption)}
                if mode=="Tổng kết"{let items=groups.flatMap(\.items);Text("\(items.count) ảnh · \(Set(items.map(\.day)).count) ngày · \(groups.count) tháng có ảnh").font(.headline)}
                if mode=="Hành trình"{NavigationLink("Bản đồ hành trình"){SignatureAtlas(shots:shots,vault:vault)}}
                if groups.isEmpty{Text("Chưa có dữ liệu phù hợp.").foregroundStyle(.secondary)}
                ForEach(groups){g in Button{selected=g;for s in g.items{viewed[s.id.uuidString]=Date()};if let data=try? JSONEncoder().encode(viewed){viewedData=data}}label:{
                    HStack{DiskImage(url:vault.thumbnail(g.cover.id),limit:180).scaledToFill().frame(width:66,height:66).clipped().clipShape(RoundedRectangle(cornerRadius:8));VStack(alignment:.leading){Text(g.key);Text("\(g.items.count) ký ức").font(.caption).foregroundStyle(.secondary)}}
                }.buttonStyle(.plain)}
            }.navigationTitle("Memory Discovery").toolbar{Button("Xong"){dismiss()}}
        }.onAppear{viewed=(try? JSONDecoder().decode([String:Date].self,from:viewedData)) ?? [:]}
        .sheet(item:$selected){g in ArchiveSlideshow(shots:g.items,vault:vault)}
    }
}
struct MemoryPodcast:View{
    @ObservedObject private var archive=StoryArchive.shared
    @StateObject private var voice=StoryVoice()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scene
    @State private var index=0
    @State private var playing=false
    @State private var duration=0.0
    private var tracks:[StoryEntry]{archive.entries.values.filter{$0.audio != nil}.sorted{$0.createdAt<$1.createdAt}}
    var body:some View{
        NavigationStack{
            List{
                if tracks.isEmpty{ContentUnavailableView("Chưa có lời kể",systemImage:"waveform")}
                else if tracks.indices.contains(index){
                    Section{
                        Image(systemName:"waveform.circle").font(.system(size:80)).foregroundStyle(gold).frame(maxWidth:.infinity)
                        Text(tracks[index].title.isEmpty ? "Lời kể \(index+1)":tracks[index].title).font(.title2)
                        HStack{Button{if index>0{index-=1}}label:{Image(systemName:"backward.end.fill")};Spacer();Button{playing.toggle()}label:{Image(systemName:playing ? "pause.circle.fill":"play.circle.fill").font(.largeTitle)};Spacer();Button{if index+1<tracks.count{index+=1}}label:{Image(systemName:"forward.end.fill")}}.buttonStyle(.plain)
                    }
                    Section("Danh sách lời kể"){ForEach(tracks.indices,id:\.self){i in Button{index=i;playing=true}label:{Label(tracks[i].title.isEmpty ? "Lời kể \(i+1)":tracks[i].title,systemImage:i==index ? "waveform":"mic")}}}
                }
            }.navigationTitle("Memory Podcast").toolbar{Button("Xong"){dismiss()}}
        }.task(id:"\(index)-\(playing)"){
            voice.stopPlayback();guard playing,tracks.indices.contains(index),let audio=tracks[index].audio else{return}
            duration=voice.play(audio)
            guard duration>0 else{playing=false;return}
            do{try await Task.sleep(for:.seconds(duration+0.15))}catch{return}
            if !Task.isCancelled{if index+1<tracks.count{index+=1}else{playing=false}}
        }.onChange(of:scene){_,p in if p != .active{playing=false;voice.stopPlayback()}}.onDisappear{voice.cancel()}
    }
}
