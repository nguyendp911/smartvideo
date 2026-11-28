import SwiftUI
import UIKit
import CoreImage
import AVFoundation

enum LifeReflectionRange:Identifiable{
    case day(Date),week(Date),month(Date),year(Date),rolling(Date)
    var anchor:Date{switch self{case .day(let d),.week(let d),.month(let d),.year(let d),.rolling(let d):return d}}
    var component:Calendar.Component{switch self{case .day:return .day;case .week:return .weekOfYear;case .month:return .month;case .year,.rolling:return .year}}
    var interval:DateInterval{if case .rolling(let date)=self{let end=LifeDate.calendar.date(byAdding:.day,value:1,to:LifeDate.calendar.startOfDay(for:date)) ?? date;let start=LifeDate.calendar.date(byAdding:.day,value:-365,to:end) ?? end.addingTimeInterval(-365*86400);return DateInterval(start:start,end:end)};return LifeDate.calendar.dateInterval(of:component,for:anchor) ?? DateInterval(start:anchor,duration:86400)}
    var start:String{LifeDate.key(interval.start)}
    var end:String{LifeDate.key(interval.end)}
    var id:String{storyID}
    var title:String{switch self{case .day:return "Nhật ký ngày";case .week:return "Nhìn lại một tuần";case .month:return "Tạp chí tháng";case .year:return "Yearbook";case .rolling:return "365 Memories"}}
    var storyID:String{switch self{case .week:return "week:"+start;case .day:return "period:"+start;case .month:return "period:"+String(start.prefix(7));case .year:return "period:"+String(start.prefix(4));case .rolling:return "rolling:"+start}}
    func contains(_ day:String)->Bool{day>=start && day<end}
}
struct LifeReflection:View{
    let range:LifeReflectionRange
    let shots:[Shot]
    let vault:Vault
    @ObservedObject private var stories=StoryArchive.shared
    @ObservedObject private var life=LifeArchive.shared
    @Environment(\.dismiss) private var dismiss
    @State private var target:StoryTarget?
    @State private var export:URL?
    @State private var notice=""
    @State private var play=false
    private var items:[Shot]{shots.filter{range.contains($0.day) && $0.deleted==nil}}
    private var days:[StoryEntry]{stories.entries.values.filter{$0.id.hasPrefix("period:") && $0.id.count==17 && range.contains(String($0.id.dropFirst(7)))}.sorted{$0.id<$1.id}}
    private var milestones:[LifeMilestone]{life.data.milestones.filter{$0.gardenID==nil && range.contains($0.date)}.sorted{$0.date<$1.date}}
    private var group:StoryTarget{StoryTarget(id:range.storyID,label:range.title,shots:items)}
    private var recap:StoryEntry{
        if let e=stories.entry(range.storyID){return e}
        var e=StoryEntry(id:range.storyID);e.title=range.title;e.body="\(items.count) ảnh · \(Set(items.map(\.day)).count) ngày có ảnh · \(days.count) nhật ký · \(milestones.count) cột mốc."
        e.chapters=days.map{TimelineIndex.label(String($0.id.dropFirst(7)))+"\n"+$0.title+"\n"+$0.body}+milestones.map{$0.title+" · "+TimelineIndex.label($0.date)+"\n"+$0.note}
        e.photoIDs=items.map(\.id);e.cover=MemorySync.cover(items,entry:nil)?.id
        return e
    }
    var body:some View{
        NavigationStack{
            ScrollView{
                VStack(alignment:.leading,spacing:18){
                    Text("V I E L E N S  /  R E F L E C T I O N").font(.caption2.monospaced()).foregroundStyle(gold)
                    Text(range.title).font(.system(size:34,design:.serif))
                    Text(TimelineIndex.label(range.start)).font(.caption).foregroundStyle(.secondary)
                    if let cover=MemorySync.cover(items,entry:stories.entry(range.storyID)){
                        DiskImage(url:vault.picture(cover),limit:1300).scaledToFill().frame(height:220).clipped().clipShape(RoundedRectangle(cornerRadius:12))
                    }
                    HStack{metric("\(items.count)","Ảnh");metric("\(days.count)","Nhật ký");metric("\(milestones.count)","Cột mốc")}
                    if !days.isEmpty{MoodSummary(entries:days)}
                    ForEach(TimelineIndex.group(items,period:range.component == .year ? .month:.day,newest:false)){g in
                        VStack(alignment:.leading,spacing:8){
                            Text(TimelineIndex.label(g.key)).font(.system(.headline,design:.serif))
                            HStack(spacing:4){ForEach(g.items.prefix(3)){shot in DiskImage(url:vault.thumbnail(shot.id),limit:300).scaledToFill().frame(maxWidth:.infinity).frame(height:100).clipped().clipShape(RoundedRectangle(cornerRadius:5))}}
                            if let e=stories.entry("period:"+g.key){Text(e.title).font(.headline);Text(e.body).font(.caption).lineLimit(5)}
                        }
                    }
                    ForEach(days){e in
                        if !items.contains(where:{$0.day==String(e.id.dropFirst(7))}){
                            VStack(alignment:.leading){Text(TimelineIndex.label(String(e.id.dropFirst(7)))).font(.caption).foregroundStyle(gold);Text(e.title).font(.headline);Text(e.body).font(.caption)}
                        }
                    }
                    ForEach(milestones){m in Label(m.title,systemImage:m.icon).foregroundStyle(gold)}
                    Button("Viết lời tổng kết",systemImage:"pencil.line"){target=group}.buttonStyle(.borderedProminent)
                    Button("Phát hành trình",systemImage:"play.rectangle"){play=true}.disabled(items.isEmpty)
                    Button("Xuất sách PDF",systemImage:"book.closed"){do{export=try StoryPDF.export(recap,shots:items,vault:vault);notice="Đã tạo sách."}catch{notice=error.localizedDescription}}
                    if let export{ShareLink(item:export){Label("Lưu / chia sẻ sách",systemImage:"square.and.arrow.up")}}
                    Text(notice).font(.caption)
                }.padding(18)
            }.navigationTitle(range.title).navigationBarTitleDisplayMode(.inline).toolbar{Button("Đóng"){dismiss()}}
        }.sheet(item:$target){LifeStorySheet(target:$0,vault:vault,archive:stories)}
        .fullScreenCover(isPresented:$play){ArchiveSlideshow(shots:items,vault:vault)}
    }
    private func metric(_ count:String,_ label:String)->some View{
        VStack{Text(count).font(.system(.title,design:.serif)).foregroundStyle(gold);Text(label).font(.caption2)}.frame(maxWidth:.infinity).padding(10).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:10))
    }
}
struct MoodSummary:View{
    let entries:[StoryEntry]
    private var total:Int{max(1,entries.filter{$0.mood != nil}.count)}
    var body:some View{
        VStack(alignment:.leading,spacing:9){
            Text("Hành trình cảm xúc").font(.system(.headline,design:.serif))
            ForEach(StoryMood.allCases,id:\.self){mood in
                let count=entries.filter{$0.mood==mood}.count
                if count>0{
                    HStack{
                        Text(mood.rawValue).font(.caption).frame(width:82,alignment:.leading)
                        GeometryReader{g in Capsule().fill(mood.calendarColor.opacity(0.8)).frame(width:g.size.width*CGFloat(count)/CGFloat(total))}
                            .frame(height:7)
                        Text("\(count)").font(.caption.monospacedDigit())
                    }
                }
            }
            Text("Dựa trên cảm xúc bạn tự ghi lại, không suy đoán từ khuôn mặt.").font(.caption2).foregroundStyle(.secondary)
        }.padding(12).background(.white.opacity(0.055),in:RoundedRectangle(cornerRadius:12))
    }
}
struct LifeChapterStudio:View{
    let shots:[Shot]
    let vault:Vault
    @ObservedObject private var life=LifeArchive.shared
    @ObservedObject private var stories=StoryArchive.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editing=false
    @State private var existing:LifeChapter?
    @State private var target:StoryTarget?
    @State private var playback:[Shot]=[]
    @State private var playing=false
    @State private var notice=""
    var body:some View{
        NavigationStack{
            List{
                Section("Các chương cuộc đời"){
                    ForEach(life.data.chapters.sorted{$0.start<$1.start}){chapter in
                        let items=shots.filter{chapter.contains($0.day)}
                        VStack(alignment:.leading,spacing:8){
                            if let cover=MemorySync.cover(items,entry:stories.entry("chapter:"+chapter.id.uuidString)){
                                DiskImage(url:vault.thumbnail(cover.id),limit:600).scaledToFill().frame(height:120).clipped().clipShape(RoundedRectangle(cornerRadius:9))
                            }
                            Text(chapter.title).font(.system(.title2,design:.serif))
                            Text("\(chapter.start) – \(chapter.end) · \(items.count) ảnh").font(.caption).foregroundStyle(.secondary)
                            Text(chapter.summary).font(.caption)
                            HStack{
                                Button("Story"){target=StoryTarget(id:"chapter:"+chapter.id.uuidString,label:chapter.title,shots:items)}
                                Spacer();Button("Sửa"){existing=chapter;editing=true};Button("Phát"){playback=items;playing=true}.disabled(items.isEmpty)
                            }.buttonStyle(.borderless)
                        }.padding(.vertical,5)
                    }.onDelete{indices in
                        let sorted=life.data.chapters.sorted{$0.start<$1.start},ids=Set(indices.map{sorted[$0].id})
                        do{try life.update{$0.chapters.removeAll{ids.contains($0.id)}}}catch{notice=error.localizedDescription}
                    }
                    Button("Tạo chương mới",systemImage:"plus"){existing=nil;editing=true}
                }
                Section("Gợi ý chương theo năm"){
                    ForEach(TimelineIndex.group(shots,period:.year,newest:true)){g in
                        Button{existing=LifeChapter(title:"Hành trình "+g.key,start:g.key+"-01-01",end:g.key+"-12-31");editing=true}label:{HStack{Text(g.key);Spacer();Text("\(g.items.count) ảnh").font(.caption)}}
                    }
                }
                Text(notice).font(.caption)
            }.navigationTitle("Life Chapters").toolbar{Button("Xong"){dismiss()}}
        }.sheet(isPresented:$editing){LifeChapterEditor(existing:existing,life:life)}
        .sheet(item:$target){LifeStorySheet(target:$0,vault:vault,archive:stories)}
        .fullScreenCover(isPresented:$playing){ArchiveSlideshow(shots:playback,vault:vault)}
    }
}
private struct LifeChapterEditor:View{
    let existing:LifeChapter?
    @ObservedObject var life:LifeArchive
    @Environment(\.dismiss) private var dismiss
    @State private var title=""
    @State private var summary=""
    @State private var start=Date()
    @State private var end=Date()
    @State private var notice=""
    var body:some View{
        NavigationStack{
            Form{
                TextField("Tên chương",text:$title)
                DatePicker("Bắt đầu",selection:$start,displayedComponents:.date)
                DatePicker("Kết thúc",selection:$end,displayedComponents:.date)
                TextField("Lời giới thiệu",text:$summary,axis:.vertical)
                Text(notice).font(.caption)
            }.navigationTitle("Chương cuộc đời").toolbar{
                ToolbarItem(placement:.cancellationAction){Button("Đóng"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button("Lưu"){
                    var item=existing ?? LifeChapter(title:title,start:LifeDate.key(start),end:LifeDate.key(end));item.title=title;item.start=LifeDate.key(start);item.end=LifeDate.key(end);item.summary=summary
                    do{try life.update{$0.chapters.removeAll{$0.id==item.id};$0.chapters.append(item)};dismiss()}catch{notice=error.localizedDescription}
                }.disabled(title.isEmpty || LifeDate.key(end)<LifeDate.key(start))}
            }
        }.onAppear{if let existing{title=existing.title;summary=existing.summary;start=LifeDate.date(existing.start) ?? Date();end=LifeDate.date(existing.end) ?? Date()}}
    }
}
struct LifeIntelligence:View{
    let shots:[Shot]
    let vault:Vault
    @ObservedObject private var stories=StoryArchive.shared
    @ObservedObject private var life=LifeArchive.shared
    @Environment(\.dismiss) private var dismiss
    @State private var range:LifeReflectionRange?
    @State private var notice=""
    @State private var reminder=false
    @State private var anniversaryDate=Date()
    @State private var hour=Date()
    @State private var connections=false
    @State private var smartCover:Shot?
    @State private var scanning=false
    private var dayEntries:[StoryEntry]{stories.entries.values.filter{$0.id.hasPrefix("period:") && $0.id.count==17}}
    var body:some View{
        NavigationStack{
            List{
                Section("Thống kê cuộc đời"){
                    LabeledContent("Ảnh",value:String(shots.count))
                    LabeledContent("Ngày có ký ức",value:String(MemorySync.activeDays(shots:shots,stories:stories,life:life).count))
                    LabeledContent("Story",value:String(stories.entries.count))
                    LabeledContent("Cột mốc",value:String(life.data.milestones.count))
                    LabeledContent("Chương",value:String(life.data.chapters.count))
                    LabeledContent("Địa điểm đã ghi",value:String(Set(stories.entries.values.map(\.location).filter{!$0.isEmpty}).count))
                    MoodSummary(entries:dayEntries)
                }
                Section("Nhìn lại"){
                    Button("Daily Recap"){range = .day(Date())}
                    Button("Weekly Reflection"){range = .week(Date())}
                    Button("Monthly Reflection"){range = .month(Date())}
                    Button("Annual Reflection"){range = .year(Date())}
                    Button("Ký ức liên quan"){connections=true}
                }
                Section("Gợi ý ảnh bìa"){
                    Button("Đánh giá ảnh gần đây"){scan()}.disabled(scanning || shots.isEmpty)
                    if scanning{ProgressView()}
                    if let shot=smartCover{DiskImage(url:vault.thumbnail(shot.id),limit:600).scaledToFit().frame(maxHeight:160);Text("Ưu tiên ảnh rõ, sáng phù hợp và được đánh giá cao.")}
                }
                Section("Âm thanh gợi ý"){
                    let mood=stories.entry("period:"+LifeDate.key(Date()))?.mood
                    Text(mood == .peaceful || mood == .nostalgic ? "Mưa nhẹ hoặc gió rừng":mood == .adventure ? "Sóng biển":"Âm thanh nhẹ, không lời")
                    Text("Đây là gợi ý theo cảm xúc bạn chọn. Có thể đổi soundscape trong Story.").font(.caption)
                }
                Section("Nhắc viết nhật ký"){
                    DatePicker("Giờ nhắc",selection:$hour,displayedComponents:.hourAndMinute)
                    Button("Bật nhắc hằng ngày"){Task{do{try await MemoryReminder.schedule(id:"daily-journal",title:"Dành một phút lưu lại hôm nay.",date:LifeDate.calendar.dateComponents([.hour,.minute],from:hour),repeats:true);notice="Đã bật nhắc hằng ngày."}catch{notice=error.localizedDescription}}}
                    Button("Tắt nhắc"){MemoryReminder.cancel("daily-journal");notice="Đã tắt nhắc."}
                    DatePicker("Ngày kỷ niệm hằng năm",selection:$anniversaryDate,displayedComponents:[.date,.hourAndMinute])
                    Button("Bật nhắc kỷ niệm"){Task{do{try await MemoryReminder.schedule(id:"annual-memory",title:"Hôm nay là ngày nhìn lại một kỷ niệm.",date:LifeDate.calendar.dateComponents([.month,.day,.hour,.minute],from:anniversaryDate),repeats:true);notice="Đã bật nhắc hằng năm."}catch{notice=error.localizedDescription}}}
                    Button("Tắt nhắc kỷ niệm"){MemoryReminder.cancel("annual-memory");notice="Đã tắt nhắc kỷ niệm."}
                    Text(notice).font(.caption)
                }
            }.navigationTitle("Memory Intelligence").toolbar{Button("Đóng"){dismiss()}}
        }.sheet(item:$range){LifeReflection(range:$0,shots:shots,vault:vault)}
        .sheet(isPresented:$connections){MemoryDiscover(shots:shots,vault:vault)}
    }
    private func scan(){
        scanning=true
        let candidates=Array(shots.prefix(60)),v=vault
        Task{
            let result=await Task.detached(priority:.utility){()->Shot? in
                var best:Shot?,score = -Double.infinity
                for shot in candidates{
                    guard let data=try? Data(contentsOf:v.thumbnail(shot.id)),let cg=PhotoEngine.thumb(data,limit:120) else{continue}
                    let width=32,height=32;var pixels=[UInt8](repeating:0,count:width*height)
                    let valid=pixels.withUnsafeMutableBytes{ptr->Bool in
                        guard let ctx=CGContext(data:ptr.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else{return false}
                        ctx.draw(cg,in:CGRect(x:0,y:0,width:width,height:height));return true
                    }
                    if !valid{continue}
                    var edge=0.0
                    for y in 1..<height{for x in 1..<width{let i=y*width+x;edge+=abs(Double(pixels[i])-Double(pixels[i-1]))+abs(Double(pixels[i])-Double(pixels[i-width]))}}
                    let light=pixels.reduce(0.0){$0+Double($1)}/Double(pixels.count)
                    let rank=edge/Double(pixels.count)+Double(shot.rating)*8-abs(light-128)*0.2
                    if rank>score{score=rank;best=shot}
                }
                return best
            }.value
            smartCover=result;scanning=false
        }
    }
}
