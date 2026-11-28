import SwiftUI

enum LifeCalendarMode:String,CaseIterable{case photo="Ảnh",mood="Cảm xúc",heat="Mật độ"}
struct LifeCalendar:View{
    let shots:[Shot]
    let vault:Vault
    var gardenID:UUID?=nil
    let select:(String)->Void
    @ObservedObject private var stories=StoryArchive.shared
    @ObservedObject private var life=LifeArchive.shared
    @Environment(\.dismiss) private var dismiss
    @State private var month=Date()
    @State private var day=LifeDate.key(Date())
    @State private var mode=LifeCalendarMode.photo
    @State private var target:StoryTarget?
    @State private var milestone=false
    @State private var editMilestone:LifeMilestone?
    @State private var showLetters=false
    @State private var reflection:LifeReflectionRange?
    @State private var showSlide=false
    @State private var notice=""
    @State private var jump=false
    private var grouped:[String:[Shot]]{Dictionary(grouping:shots.filter{$0.deleted==nil},by:\.day)}
    private var items:[Shot]{grouped[day] ?? []}
    private func storyID(_ key:String)->String{gardenID.map{"garden:"+$0.uuidString+":"+key} ?? "period:"+key}
    private var selectedTarget:StoryTarget{StoryTarget(id:storyID(day),label:TimelineIndex.label(day),shots:items)}
    private var activeDays:Set<String>{
        guard let gardenID else{return MemorySync.activeDays(shots:shots,stories:stories,life:life)}
        let prefix="garden:"+gardenID.uuidString+":"
        return Set(grouped.keys).union(stories.entries.keys.filter{$0.hasPrefix(prefix) && $0.count==prefix.count+10}.map{String($0.dropFirst(prefix.count))}).union(life.data.milestones.filter{$0.gardenID==gardenID}.map(\.date))
    }
    private var current:StoryEntry?{stories.entry(selectedTarget.id)}
    var body:some View{
        NavigationStack{
            ScrollView{
                VStack(alignment:.leading,spacing:16){
                    header
                    Picker("Lịch",selection:$mode){ForEach(LifeCalendarMode.allCases,id:\.self){Text($0.rawValue).tag($0)}}.pickerStyle(.segmented)
                    calendarGrid
                    HStack{
                        let prefix=String(LifeDate.key(month).prefix(7))
                        let days=activeDays.filter{$0.hasPrefix(prefix)}
                        Text("\(days.count) ngày có ký ức").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Hôm nay"){month=Date();day=LifeDate.key(Date())}.font(.caption)
                    }
                    dayPanel
                    if gardenID==nil{
                    CalendarExtras(day:day,shots:shots,vault:vault)
                    GroupBox("Nhìn lại"){
                        VStack(alignment:.leading,spacing:12){
                            Button("Tạp chí tháng",systemImage:"book.closed"){reflection = .month(month)}
                            Button("Yearbook",systemImage:"book.pages"){reflection = .year(month)}
                            Button("Thư tương lai",systemImage:"envelope"){showLetters=true}
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                    }
                }.padding(14)
            }.navigationTitle(gardenID==nil ? "Lịch ký ức":"Lịch riêng khu vườn").navigationBarTitleDisplayMode(.inline).toolbar{Button("Xong"){dismiss()}}
        }.sheet(item:$target){LifeStorySheet(target:$0,vault:vault,archive:stories)}
        .sheet(isPresented:$milestone){LifeMilestoneEditor(day:day,life:life,gardenID:gardenID)}
        .sheet(item:$editMilestone){LifeMilestoneEditor(day:day,life:life,existing:$0,gardenID:gardenID)}
        .sheet(isPresented:$showLetters){FutureLetterStudio(life:life)}
        .sheet(item:$reflection){LifeReflection(range:$0,shots:shots,vault:vault)}
        .fullScreenCover(isPresented:$showSlide){ArchiveSlideshow(shots:items,vault:vault)}
        .sheet(isPresented:$jump){NavigationStack{Form{DatePicker("Chọn ngày",selection:Binding(get:{LifeDate.date(day) ?? month},set:{day=LifeDate.key($0);month=$0}),displayedComponents:.date).datePickerStyle(.graphical)}.toolbar{Button("Xong"){jump=false}}}}
    }
    private var header:some View{
        HStack{
            Button{shift(-1)}label:{Image(systemName:"chevron.left").frame(width:40,height:44)}
            Spacer()
            Button{jump=true}label:{
                VStack(spacing:3){
                    Text("M E M O R Y  C A L E N D A R").font(.system(size:9,design:.monospaced)).foregroundStyle(gold)
                    Text(TimelineIndex.label(String(LifeDate.key(month).prefix(7)))).font(.system(.title2,design:.serif))
                }
            }.buttonStyle(.plain)
            Spacer()
            Button{shift(1)}label:{Image(systemName:"chevron.right").frame(width:40,height:44)}
        }
    }
    private func shift(_ amount:Int){
        if let date=LifeDate.calendar.date(byAdding:.month,value:amount,to:LifeDate.start(month)){month=date;day=LifeDate.key(date)}
    }
    private var calendarGrid:some View{
        let cells=LifeDate.monthCells(month),groups=grouped
        let count=max(1,groups.filter{$0.key.hasPrefix(String(LifeDate.key(month).prefix(7)))}.values.map(\.count).max() ?? 1)
        return LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:3),count:7),spacing:4){
            ForEach(["T2","T3","T4","T5","T6","T7","CN"],id:\.self){Text($0).font(.caption2).foregroundStyle(.secondary)}
            ForEach(cells.indices,id:\.self){index in
                if let date=cells[index]{
                    let key=LifeDate.key(date),items=groups[key] ?? [],entry=stories.entry(storyID(key))
                    Button{withAnimation(.easeInOut(duration:0.18)){day=key}}label:{
                        calendarCell(date:date,key:key,items:items,entry:entry,peak:count)
                    }.buttonStyle(.plain).accessibilityLabel("\(TimelineIndex.label(key)), \(items.count) ảnh, \(entry?.mood?.rawValue ?? "")")
                }else{Color.clear.frame(height:55)}
            }
        }
    }
    private func calendarCell(date:Date,key:String,items:[Shot],entry:StoryEntry?,peak:Int)->some View{
        let milestones=life.milestones(key,gardenID:gardenID)
        return ZStack{
            RoundedRectangle(cornerRadius:8).fill(.white.opacity(0.045))
            if mode == .photo,let cover=MemorySync.cover(items,entry:entry){
                DiskImage(url:vault.thumbnail(cover.id),limit:150).scaledToFill().frame(height:55).clipped().overlay(.black.opacity(0.38))
            }
            if mode == .heat{RoundedRectangle(cornerRadius:8).fill(gold.opacity(items.isEmpty ? 0.02:0.13+0.64*Double(items.count)/Double(peak)))}
            if mode == .mood,let mood=entry?.mood{RoundedRectangle(cornerRadius:8).fill(mood.calendarColor.opacity(0.4))}
            VStack(spacing:2){
                Text(String(LifeDate.calendar.component(.day,from:date))).font(.system(size:13,weight:key==day ? .bold:.medium))
                HStack(spacing:2){
                    if !milestones.isEmpty{Image(systemName:"star.fill").font(.system(size:8)).foregroundStyle(gold)}
                    if entry != nil{Image("botanical_flower").resizable().scaledToFit().frame(width:12,height:12)}
                    if !items.isEmpty{Text("\(items.count)").font(.system(size:9,weight:.medium))}
                }
            }.foregroundStyle(.white)
        }.frame(height:55).clipShape(RoundedRectangle(cornerRadius:8))
            .overlay{RoundedRectangle(cornerRadius:8).strokeBorder(key==day ? gold:key==LifeDate.key(Date()) ? .white.opacity(0.4):.clear,lineWidth:key==day ? 2:1)}
    }
    private var dayPanel:some View{
        VStack(alignment:.leading,spacing:12){
            HStack{
                VStack(alignment:.leading,spacing:4){
                    Text(TimelineIndex.label(day)).font(.system(.title2,design:.serif))
                    Text("\(items.count) ảnh · \(life.milestones(day,gardenID:gardenID).count) cột mốc").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button{milestone=true}label:{Image(systemName:"star.circle").font(.title2)}.accessibilityLabel("Thêm cột mốc")
            }
            if let cover=MemorySync.cover(items,entry:current){
                DiskImage(url:vault.picture(cover),limit:1000).scaledToFill().frame(height:190).clipped().clipShape(RoundedRectangle(cornerRadius:14))
                    .overlay(alignment:.bottomLeading){Text("Ảnh nổi bật").font(.caption).padding(8).background(.black.opacity(0.6),in:Capsule()).padding(8)}
            }
            if !items.isEmpty{
                ScrollView(.horizontal,showsIndicators:false){LazyHStack(spacing:6){ForEach(items){shot in
                    Button{if let gardenID{target=StoryTarget(id:"garden:"+gardenID.uuidString+":photo:"+shot.id.uuidString,label:TimelineIndex.label(shot.day),shots:[shot])}else{target = .photo(shot)}}label:{DiskImage(url:vault.thumbnail(shot.id),limit:240).scaledToFill().frame(width:72,height:72).clipped().clipShape(RoundedRectangle(cornerRadius:8))}.buttonStyle(.plain)
                        .contextMenu{Button("Đặt ảnh nổi bật"){do{try MemorySync.setCover(shot,target:selectedTarget,archive:stories)}catch{notice=error.localizedDescription}}}
                }}}
                Button("Phát slide",systemImage:"play.circle"){showSlide=true}.font(.caption)
            }
            if !items.isEmpty || current != nil || !life.milestones(day,gardenID:gardenID).isEmpty{Button("Mở Timeline ngày này",systemImage:"leaf"){select(day)}.font(.caption)}
            Button{target=selectedTarget}label:{
                VStack(alignment:.leading,spacing:6){
                    Label(current?.title.isEmpty == false ? current?.title ?? "Nhật ký":"Nhật ký trong ngày",systemImage:"book.closed").font(.headline)
                    Text(current?.body.isEmpty == false ? current?.body ?? "":"Viết điều bạn muốn ghi nhớ, kể cả ngày không có ảnh.").font(.caption).foregroundStyle(.secondary).lineLimit(4)
                }.frame(maxWidth:.infinity,alignment:.leading).padding(12).background(.white.opacity(0.065),in:RoundedRectangle(cornerRadius:12))
            }.buttonStyle(.plain)
            Text("Cảm xúc hôm nay").font(.caption.weight(.semibold))
            ScrollView(.horizontal,showsIndicators:false){HStack{ForEach(StoryMood.allCases,id:\.self){mood in
                Button{do{try MemorySync.setMood(mood,target:selectedTarget,archive:stories)}catch{notice=error.localizedDescription}}label:{
                    Text(mood.rawValue).font(.caption).padding(8).background(current?.mood==mood ? mood.calendarColor.opacity(0.4):.white.opacity(0.07),in:Capsule())
                }.buttonStyle(.plain)
            }}}
            ForEach(life.milestones(day,gardenID:gardenID)){item in
                Button{editMilestone=item}label:{HStack{Image(systemName:item.icon).foregroundStyle(gold);VStack(alignment:.leading){Text(item.title);Text(item.note).font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:"chevron.right").font(.caption)}}.buttonStyle(.plain)
            }
            if !notice.isEmpty{Text(notice).font(.caption).foregroundStyle(.secondary)}
        }.padding(12).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:16))
    }
}
struct LifeToday:View{
    @ObservedObject var model:LibraryModel
    @ObservedObject private var stories=StoryArchive.shared
    @ObservedObject private var life=LifeArchive.shared
    @Environment(\.dismiss) private var dismiss
    let camera:()->Void
    let timeline:(String?)->Void
    @State private var target:StoryTarget?
    @State private var calendar=false
    @State private var letters=false
    @State private var milestone=false
    @State private var chapters=false
    @State private var intelligence=false
    @State private var reflection:LifeReflectionRange?
    @State private var playback:[Shot]=[]
    @State private var showPlayback=false
    @State private var notice=""
    private var shots:[Shot]{model.shots.filter{$0.deleted==nil}}
    private var day:String{LifeDate.key(Date())}
    private var today:[Shot]{shots.filter{$0.day==day}}
    private var story:StoryEntry?{stories.entry("period:"+day)}
    private var previous:[Shot]{shots.filter{String($0.day.suffix(5))==String(day.suffix(5)) && $0.day != day}}
    var body:some View{
        NavigationStack{
            ScrollView{
                VStack(alignment:.leading,spacing:18){
                    VStack(alignment:.leading,spacing:5){
                        Text("T O D A Y  I N  M Y  L I F E").font(.caption2.monospaced()).foregroundStyle(gold)
                        Text("Hôm nay của tôi").font(.system(size:34,design:.serif))
                        Text(TimelineIndex.label(day)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    hero
                    VineGrowthCard(life:life)
                    HStack(spacing:7){
                        quick("Chụp ảnh","camera",camera)
                        quick("Viết Story","pencil.line"){target=MemorySync.target(day:day,shots:shots)}
                        quick("Lịch ảnh","calendar"){calendar=true}
                    }
                    GroupBox("Cảm xúc hôm nay"){
                        ScrollView(.horizontal,showsIndicators:false){HStack{ForEach(StoryMood.allCases,id:\.self){mood in Button{do{try MemorySync.setMood(mood,day:day,shots:shots,archive:stories)}catch{notice=error.localizedDescription}}label:{Text(mood.rawValue).font(.caption).padding(9).background(story?.mood==mood ? mood.calendarColor.opacity(0.4):.white.opacity(0.07),in:Capsule())}.buttonStyle(.plain)}}}
                    }
                    if !previous.isEmpty{
                        Text("Ngày này năm xưa").font(.system(.title2,design:.serif))
                        ScrollView(.horizontal){LazyHStack{ForEach(previous){shot in Button{playback=previous;showPlayback=true}label:{
                            VStack(alignment:.leading){DiskImage(url:model.vault.thumbnail(shot.id),limit:240).scaledToFill().frame(width:132,height:100).clipped().clipShape(RoundedRectangle(cornerRadius:10));Text(TimelineIndex.label(shot.day)).font(.caption2)}
                        }.buttonStyle(.plain)}}}
                    }
                    GroupBox("Hành trình của tôi"){
                        VStack(spacing:13){
                            action("Mở cây thời gian","leaf"){timeline(nil)}
                            action("Life Chapters","book.pages"){chapters=true}
                            action("Cột mốc mới","star"){milestone=true}
                            action("Thư tương lai","envelope"){letters=true}
                            action("Tổng kết tuần","calendar.badge.clock"){reflection = .week(Date())}
                            action("Memory Intelligence","sparkles"){intelligence=true}
                        }
                    }
                    if !notice.isEmpty{Text(notice).font(.caption)}
                }.padding(18)
            }.background(night).navigationBarTitleDisplayMode(.inline).toolbar{Button("Xong"){dismiss()}}
        }.task{await model.reload()}
        .sheet(item:$target){LifeStorySheet(target:$0,vault:model.vault,archive:stories)}
        .sheet(isPresented:$calendar){LifeCalendar(shots:shots,vault:model.vault){key in calendar=false;timeline(key)}}
        .sheet(isPresented:$letters){FutureLetterStudio(life:life)}
        .sheet(isPresented:$milestone){LifeMilestoneEditor(day:day,life:life)}
        .sheet(isPresented:$chapters){LifeChapterStudio(shots:shots,vault:model.vault)}
        .sheet(isPresented:$intelligence){LifeIntelligence(shots:shots,vault:model.vault)}
        .sheet(item:$reflection){LifeReflection(range:$0,shots:shots,vault:model.vault)}
        .fullScreenCover(isPresented:$showPlayback){ArchiveSlideshow(shots:playback,vault:model.vault)}
    }
    private var hero:some View{
        ZStack(alignment:.bottomLeading){
            RoundedRectangle(cornerRadius:18).fill(LinearGradient(colors:[Color(red:0.19,green:0.35,blue:0.24),night],startPoint:.topLeading,endPoint:.bottomTrailing))
            if let cover=MemorySync.cover(today,entry:story){DiskImage(url:model.vault.picture(cover),limit:1100).scaledToFill().frame(height:210).clipped()}
            else{VineRail(level:2,theme:.emerald,density:1.1,curvature:1.4,growth:VineGrowth(days:life.gardenDays)).frame(width:90,height:200).frame(maxWidth:.infinity,alignment:.trailing).padding(.trailing,25)}
            VStack(alignment:.leading,spacing:5){
                Text(story?.title.isEmpty == false ? story?.title ?? "":"Một ngày mới").font(.system(.title,design:.serif))
                Text(story?.body.isEmpty == false ? story?.body ?? "":"Mỗi ngày đều có một câu chuyện đáng giữ lại.").font(.caption).lineLimit(3)
                Text("\(today.count) khoảnh khắc").font(.caption2).foregroundStyle(gold)
            }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(LinearGradient(colors:[.clear,.black.opacity(0.85)],startPoint:.top,endPoint:.bottom))
        }.frame(height:210).clipShape(RoundedRectangle(cornerRadius:18))
    }
    private func quick(_ title:String,_ icon:String,_ run:@escaping()->Void)->some View{
        Button(action:run){VStack(spacing:8){Image(systemName:icon).font(.title2).foregroundStyle(gold);Text(title).font(.caption2.weight(.medium))}.frame(maxWidth:.infinity).frame(height:68).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:12))}.buttonStyle(.plain)
    }
    private func action(_ title:String,_ icon:String,_ run:@escaping()->Void)->some View{
        Button(action:run){HStack{Label(title,systemImage:icon);Spacer();Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)}}.buttonStyle(.plain)
    }
}
