import SwiftUI
import UIKit

enum TimelinePresentation:String,CaseIterable {
    case tree="Cây thời gian",slides="Slide ký ức",gallery="Thư viện"
    var icon:String {
        switch self{case .tree:return "point.topleft.down.to.point.bottomright.curvepath";case .slides:return "rectangle.on.rectangle";case .gallery:return "square.grid.3x3"}
    }
}
enum StoryEffect:String,CaseIterable {
    case slide="Slide ngang",vertical="Slide dọc",fade="Hòa mờ",zoom="Zoom điện ảnh",card="Lật thẻ",reveal="Reveal"
    func transition(forward:Bool)->AnyTransition {
        switch self{
        case .slide:return .asymmetric(insertion:.move(edge:forward ? .trailing:.leading).combined(with:.opacity),removal:.move(edge:forward ? .leading:.trailing).combined(with:.opacity))
        case .vertical:return .asymmetric(insertion:.move(edge:forward ? .bottom:.top).combined(with:.opacity),removal:.move(edge:forward ? .top:.bottom).combined(with:.opacity))
        case .fade:return .opacity
        case .zoom:return .asymmetric(insertion:.scale(scale:1.14).combined(with:.opacity),removal:.scale(scale:0.88).combined(with:.opacity))
        case .card:return .modifier(active:StoryCardFlip(angle:forward ? 72:-72,opacity:0),identity:StoryCardFlip(angle:0,opacity:1))
        case .reveal:return .asymmetric(insertion:.offset(x:forward ? 90:-90,y:24).combined(with:.scale(scale:0.87)).combined(with:.opacity),removal:.offset(x:forward ? -90:90,y:-24).combined(with:.opacity))
        }
    }
}
private struct StoryCardFlip:ViewModifier{
    let angle:Double
    let opacity:Double
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
        }.onAppear{
            if !initialized{initialized=true;openFirst()}
        }.onChange(of:shots.first?.id){_,_ in if expanded.isEmpty || !years.contains(where:{expanded.contains($0.id)}){openFirst()}}
    }
    private func openFirst(){
        if let year=years.first{expanded.insert(year.id);if let month=year.months.first{expanded.insert(month.id)}}
    }
    private func toggle(_ id:String){
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? nil:.spring(response:0.38,dampingFraction:0.86)){
            if expanded.contains(id){expanded.remove(id)}else{expanded.insert(id)}
        }
    }
    private func treeHeader(_ proxy:ScrollViewProxy)->some View{
        VStack(alignment:.leading,spacing:12){
            HStack(alignment:.firstTextBaseline){
                VStack(alignment:.leading,spacing:4){
                    Text("HÀNH TRÌNH").font(.caption2.weight(.semibold)).tracking(3).foregroundStyle(accent)
                    Text("Cây ký ức").font(.system(size:31,design:.serif))
                }
                Spacer()
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
            TreeRail(level:0,accent:accent,large:true).frame(width:43)
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
            }.buttonStyle(.plain).padding(.vertical,5)
        }
    }
    private func monthRow(_ month:TimelineTreeMonth)->some View{
        HStack(alignment:.top,spacing:0){
            TreeRail(level:1,accent:accent,large:false).frame(width:62)
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
            }.buttonStyle(.plain).padding(.vertical,4)
        }
    }
    private func dayRow(_ day:TimelineGroup)->some View{
        HStack(alignment:.top,spacing:0){
            TreeRail(level:2,accent:accent,large:false).frame(width:79)
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
                StoryStrip(shots:day.items,vault:vault,accent:accent,open:open)
                if let note=day.cover.note,!note.isEmpty{Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(3)}
            }.padding(.vertical,12)
        }.scrollTransition(.interactive,axis:.vertical){content,phase in
            content.opacity(reduceMotion || phase.isIdentity ? 1:0.72).scaleEffect(reduceMotion || phase.isIdentity ? 1:0.96,anchor:.leading)
        }
    }
}
private struct TreeRail:View{
    let level:Int
    let accent:Color
    let large:Bool
    var body:some View{
        Canvas{ctx,size in
            let root:CGFloat=18,branch=size.width-11,y:CGFloat=level==0 ? 36:level==1 ? 35:30
            var line=Path()
            line.move(to:CGPoint(x:root,y:0));line.addLine(to:CGPoint(x:root,y:size.height))
            if level>0{
                let mid:CGFloat=level==2 ? 45:root
                if level==2{line.move(to:CGPoint(x:mid,y:0));line.addLine(to:CGPoint(x:mid,y:size.height))}
                line.move(to:CGPoint(x:root,y:y-12))
                line.addQuadCurve(to:CGPoint(x:mid+8,y:y),control:CGPoint(x:mid,y:y))
                line.addLine(to:CGPoint(x:branch,y:y))
                line.addLine(to:CGPoint(x:size.width,y:y))
            }else{line.move(to:CGPoint(x:root,y:y));line.addLine(to:CGPoint(x:size.width,y:y))}
            ctx.stroke(line,with:.color(accent.opacity(0.43)),style:StrokeStyle(lineWidth:1.2,lineCap:.round,lineJoin:.round))
            let x=level==0 ? root:branch,r:CGFloat=large ? 7:4
            ctx.fill(Path(ellipseIn:CGRect(x:x-r-4,y:y-r-4,width:(r+4)*2,height:(r+4)*2)),with:.color(accent.opacity(0.12)))
            ctx.fill(Path(ellipseIn:CGRect(x:x-r,y:y-r,width:r*2,height:r*2)),with:.color(accent))
        }.accessibilityHidden(true)
    }
}
private struct StoryStrip:View{
    let shots:[Shot]
    let vault:Vault
    let accent:Color
    let open:(Shot)->Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var current:UUID?
    var body:some View{
        VStack(alignment:.leading,spacing:6){
            ScrollView(.horizontal,showsIndicators:false){
                LazyHStack(spacing:8){
                    ForEach(shots){shot in
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
                        .containerRelativeFrame(.horizontal){length,_ in max(1,length*(shots.count>1 ? 0.87:1))}
                        .scrollTransition(.interactive,axis:.horizontal){content,phase in
                            content.scaleEffect(reduceMotion || phase.isIdentity ? 1:0.88).opacity(reduceMotion || phase.isIdentity ? 1:0.65).rotation3DEffect(.degrees(reduceMotion ? 0:phase.value*11),axis:(x:0,y:1,z:0))
                        }.id(shot.id)
                    }
                }.scrollTargetLayout()
            }.scrollTargetBehavior(.viewAligned).scrollPosition(id:$current)
            if shots.count>1{
                HStack(spacing:5){
                    ForEach(Array(shots.prefix(12).enumerated()),id:\.element.id){i,s in
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
                        ForEach([2,4,6,8],id:\.self){n in Button("\(n) giây / ảnh"){interval=n}}
                    }label:{Label(effect.rawValue,systemImage:"sparkles").font(.caption).padding(8).background(.white.opacity(0.08),in:Capsule())}
                }
                stage(shot)
                ProgressView(value:progress).tint(gold)
                HStack{
                    Button{move(-1)}label:{Image(systemName:"backward.end.fill").frame(width:44,height:44)}
                    Spacer()
                    Button{playing.toggle();progress=0}label:{
                        Image(systemName:playing ? "pause.fill":"play.fill").font(.title2).foregroundStyle(.black).frame(width:56,height:56).background(gold,in:Circle())
                    }.accessibilityLabel(playing ? "Tạm dừng":"Phát slide").disabled(shots.count<2)
                    Spacer()
                    Button{move(1)}label:{Image(systemName:"forward.end.fill").frame(width:44,height:44)}
                }.buttonStyle(.plain)
                filmstrip
            }else{ContentUnavailableView("Chưa có ảnh",systemImage:"photo.stack")}
        }.padding(14)
            .onAppear{if !initialized{index=shots.firstIndex{$0.id==initial} ?? 0;initialized=true;animateMotion()}}
            .onChange(of:shots.map(\.id)){_,_ in index=0;progress=0;animateMotion()}
            .onChange(of:scenePhase){_,p in if p != .active{playing=false}}
            .task(id:"\(playing)-\(interval)-\(index)"){
                guard playing,shots.count>1 else{return}
                let steps=max(1,interval)*20
                for tick in 1...steps{
                    do{try await Task.sleep(for:.milliseconds(50))}catch{return}
                    if Task.isCancelled{return}
                    progress=Double(tick)/Double(steps)
                }
                move(1)
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
                            .scaleEffect(effect == .zoom && motion && !reduceMotion ? 1.045:1)
                    }.clipped()
                }.id(shot.id).transition(reduceMotion ? .opacity:effect.transition(forward:forward))
            }.clipShape(RoundedRectangle(cornerRadius:18))
            VStack{
                Spacer()
                HStack(alignment:.bottom){
                    VStack(alignment:.leading,spacing:4){
                        Text(shot.session.isEmpty ? "Khoảnh khắc":shot.session).font(.system(.title2,design:.serif)).lineLimit(2)
                        if let note=shot.note,!note.isEmpty{Text(note).font(.caption).lineLimit(2)}
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
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? .easeOut(duration:0.15):.easeInOut(duration:0.48)){index=target}
        animateMotion()
    }
    private func move(_ delta:Int){
        guard shots.count>1 else{return}
        let target=(index+delta+shots.count)%shots.count
        forward=delta>0;progress=0;motion=false
        withAnimation(reduceMotion ? .easeOut(duration:0.15):.easeInOut(duration:0.48)){index=target}
        animateMotion()
    }
    private func animateMotion(){
        guard !reduceMotion else{return}
        withAnimation(.easeInOut(duration:Double(max(2,interval)))){motion=true}
    }
}
