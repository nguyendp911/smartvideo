import SwiftUI
import UIKit
import AVFoundation

struct MemoryDeskView:View{
    let target:StoryTarget;let vault:Vault
    @ObservedObject var archive:StoryArchive
    @Environment(\.dismiss) private var dismiss
    @State private var active:StoryTarget?
    @State private var showLetter=false
    @State private var play=false
    @State private var positions:[String:CGSize]=[:]
    var body:some View{
        NavigationStack{ScrollView{
            VStack(spacing:18){
                Text("Bàn ký ức").font(.system(size:32,design:.serif))
                ZStack{
                    LinearGradient(colors:[Color(red:0.28,green:0.16,blue:0.10),Color(red:0.10,green:0.065,blue:0.05)],startPoint:.topLeading,endPoint:.bottomTrailing)
                    Image("botanical_bloom").resizable().scaledToFit().frame(width:65,height:180).rotationEffect(.degrees(-35)).offset(x:-120,y:-120)
                    ForEach(Array(target.shots.prefix(6).enumerated()),id:\.offset){i,s in
                        let pos=positions[s.id.uuidString] ?? .zero
                        Button{active = .photo(s)}label:{
                            VStack(spacing:4){DiskImage(url:vault.thumbnail(s.id),limit:350).scaledToFill().frame(width:86,height:92).clipped();Text(s.day).font(.system(size:8)).foregroundStyle(.black)}
                                .padding(7).background(.white).shadow(radius:6).rotationEffect(.degrees(Double(i%3-1)*8))
                        }.buttonStyle(.plain).offset(x:CGFloat(i%3-1)*101+pos.width,y:CGFloat(i/3)*135-57+pos.height)
                            .simultaneousGesture(DragGesture().onEnded{v in positions[s.id.uuidString]=CGSize(width:pos.width+v.translation.width,height:pos.height+v.translation.height)})
                    }
                }.frame(height:330).clipShape(RoundedRectangle(cornerRadius:18))
                Button("Mở lá thư",systemImage:"envelope.fill"){showLetter=true}
                if showLetter,let entry=archive.entry(target.id){
                    VStack(alignment:.leading,spacing:10){Text(entry.title).font(.system(.title,design:.serif));Text(entry.body).font(.custom("Noteworthy",size:18))}
                        .foregroundStyle(.black).padding(20).frame(maxWidth:.infinity,alignment:.leading).background(Color(red:0.93,green:0.86,blue:0.72),in:RoundedRectangle(cornerRadius:8))
                }
                Button("Phát ký ức",systemImage:"play.rectangle"){play=true}.disabled(target.shots.isEmpty)
                Button("Sắp lại bàn"){positions=[:]}
            }.padding()
        }.navigationTitle("Memory Desk").toolbar{Button("Đóng"){dismiss()}}}.sheet(item:$active){LifeStorySheet(target:$0,vault:vault,archive:archive)}
        .fullScreenCover(isPresented:$play){ArchiveSlideshow(shots:target.shots,vault:vault)}
    }
}
struct MemorySearchView:View{
    let shots:[Shot];let vault:Vault
    @ObservedObject private var archive=StoryArchive.shared
    @ObservedObject private var life=LifeArchive.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query=""
    @State private var target:StoryTarget?
    static func normalized(_ s:String)->String{s.folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"vi_VN")).lowercased().replacingOccurrences(of:"đ",with:"d")}
    static func tokens(_ s:String)->[String]{
        let stop=Set(["tim","anh","nhung","cac","ky","uc","ve","cua","toi","cho","minh","vao","ngay","thang","nam","co","mot","o","tai"])
        return normalized(s).split(whereSeparator:{!$0.isLetter && !$0.isNumber}).map(String.init).filter{!stop.contains($0)}
    }
    private var matches:[StoryEntry]{
        let words=Self.tokens(query)
        guard !words.isEmpty else{return []}
        return archive.entries.values.filter{e in
            let hay=Self.normalized([e.id,e.title,e.body,e.location,e.people,e.quote,e.tags,e.mood?.rawValue ?? "",(e.chapters ?? []).joined(separator:" ")].joined(separator:" "))
            return words.allSatisfy{hay.contains($0)}
        }.sorted{$0.updatedAt>$1.updatedAt}
    }
    private var photos:[Shot]{
        let words=Self.tokens(query);guard !words.isEmpty else{return []}
        return shots.filter{s in
            let hay=Self.normalized([s.day,s.tags,s.session,s.note ?? ""].joined(separator:" "))
            return words.allSatisfy{hay.contains($0)} || archive.matching(words.joined(separator:" "),shot:s)
        }
    }
    var body:some View{
        NavigationStack{List{
            TextField("Ví dụ: ký ức Đà Lạt 2025",text:$query).textFieldStyle(.roundedBorder)
            Text("Tìm từ khóa tiếng Việt không dấu, story và metadata nội bộ; không gửi ảnh lên mạng.").font(.caption).foregroundStyle(.secondary)
            Section("Câu chuyện · \(matches.count)"){ForEach(matches){e in Button{if e.id.hasPrefix("period:"){target=MemorySync.target(period:String(e.id.dropFirst(7)),shots:shots)}else{target=StoryTarget(id:e.id,label:e.title,shots:shots.filter{e.photoIDs.contains($0.id)||e.id=="photo:"+$0.id.uuidString})}}label:{VStack(alignment:.leading){Text(e.title.isEmpty ? e.id:e.title);Text(e.body).font(.caption).lineLimit(2)}}}}
            Section("Ảnh · \(photos.count)"){ForEach(photos){s in Button{target = .photo(s)}label:{HStack{DiskImage(url:vault.thumbnail(s.id),limit:140).scaledToFill().frame(width:60,height:60).clipped();Text(s.day)}}}}
        }.navigationTitle("Memory Search").toolbar{Button("Đóng"){dismiss()}}}.sheet(item:$target){LifeStorySheet(target:$0,vault:vault,archive:archive)}
    }
}
enum GardenEvolutionFilm{
    static func export(days:Int,theme:VineTheme,name:String)async throws->URL{
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mp4")
        let width=720,height=1280,fps=24
        let writer=try AVAssetWriter(outputURL:url,fileType:.mp4)
        let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:width,AVVideoHeightKey:height])
        let attrs:[String:Any]=[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:width,kCVPixelBufferHeightKey as String:height,kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true]
        let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:attrs)
        guard writer.canAdd(input) else{throw CameraError.writeFailed}
        input.expectsMediaDataInRealTime=false;writer.add(input)
        guard writer.startWriting() else{throw writer.error ?? CameraError.writeFailed}
        writer.startSession(atSourceTime:.zero)
        let stages=VineGrowthStage.allCases.filter{$0.threshold<=days}
        let ageValues=Array(Set(stages.map(\.threshold)+[max(0,days)])).sorted()
        let imageSize=CGSize(width:width,height:height)
        var frame:Int64=0
        do{
            for day in ageValues{
                let age=VineGrowth(days:day)
                guard let vine=UIImage(named:BotanicalAssets.rail(theme:theme,age:age)) else{throw CameraError.unreadable}
                let fmt=UIGraphicsImageRendererFormat();fmt.scale=1
                let rendered=UIGraphicsImageRenderer(size:imageSize,format:fmt).image{c in
                    UIColor(red:0.045,green:0.09,blue:0.065,alpha:1).setFill();c.fill(CGRect(origin:.zero,size:imageSize))
                    let w=CGFloat(70+age.maturity*140),h=min(CGFloat(760),w*vine.size.height/max(1,vine.size.width))
                    for i in 0..<(age.hasBranches ? 3:1){
                        let x=CGFloat(width)/2-w/2+CGFloat(i==0 ? 0:i==1 ? -150:150)
                        vine.draw(in:CGRect(x:x,y:280+CGFloat(i)*40,width:w,height:h))
                    }
                    let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center
                    let head:[NSAttributedString.Key:Any]=[.font:UIFont(name:"Georgia",size:42) ?? UIFont.systemFont(ofSize:42),.foregroundColor:UIColor(red:0.92,green:0.81,blue:0.58,alpha:1),.paragraphStyle:paragraph]
                    ((name.isEmpty ? "Miền ký ức":name) as NSString).draw(in:CGRect(x:25,y:100,width:670,height:90),withAttributes:head)
                    (age.stage.title as NSString).draw(in:CGRect(x:25,y:1025,width:670,height:70),withAttributes:head)
                    let meta:[NSAttributedString.Key:Any]=[.font:UIFont.systemFont(ofSize:25),.foregroundColor:UIColor.white,.paragraphStyle:paragraph]
                    ("\(day) ngày sử dụng" as NSString).draw(in:CGRect(x:25,y:1115,width:670,height:70),withAttributes:meta)
                }
                guard let image=rendered.cgImage else{throw CameraError.writeFailed}
                for i in 0..<48{
                    try Task.checkCancellation()
                    let deadline=Date().addingTimeInterval(30)
                    while !input.isReadyForMoreMediaData{guard writer.status == .writing,Date()<deadline else{throw writer.error ?? CameraError.writeFailed};try await Task.sleep(for:.milliseconds(15))}
                    let pixel:CVPixelBuffer=try autoreleasepool{
                        var buffer:CVPixelBuffer?
                        guard CVPixelBufferCreate(nil,width,height,kCVPixelFormatType_32BGRA,attrs as CFDictionary,&buffer)==kCVReturnSuccess,let buffer else{throw CameraError.writeFailed}
                        CVPixelBufferLockBaseAddress(buffer,[]);defer{CVPixelBufferUnlockBaseAddress(buffer,[])}
                        guard let ctx=CGContext(data:CVPixelBufferGetBaseAddress(buffer),width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(buffer),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else{throw CameraError.writeFailed}
                        ctx.setFillColor(UIColor.black.cgColor);ctx.fill(CGRect(origin:.zero,size:imageSize))
                        ctx.setAlpha(min(1,CGFloat(i+1)/8,CGFloat(48-i)/8))
                        let zoom=1+CGFloat(i)/48*0.025
                        ctx.draw(image,in:CGRect(x:(1-zoom)*CGFloat(width)/2,y:(1-zoom)*CGFloat(height)/2,width:CGFloat(width)*zoom,height:CGFloat(height)*zoom))
                        return buffer
                    }
                    guard adaptor.append(pixel,withPresentationTime:CMTime(value:frame,timescale:Int32(fps))) else{throw writer.error ?? CameraError.writeFailed}
                    frame+=1
                }
            }
            writer.endSession(atSourceTime:CMTime(value:frame,timescale:Int32(fps)));input.markAsFinished();await writer.finishWriting()
            guard writer.status == .completed else{throw writer.error ?? CameraError.writeFailed};return url
        }catch{writer.cancelWriting();try? FileManager.default.removeItem(at:url);throw error}
    }
}
