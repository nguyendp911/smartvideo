import SwiftUI
import UIKit
import CoreText
import UniformTypeIdentifiers
import AVFoundation

enum CanvasFont:String,CaseIterable,Codable{case serif="Cổ điển",rounded="Bo tròn",mono="Máy đánh chữ",hand="Viết tay",modern="Hiện đại"
    var font:Font.Design{switch self{case .serif,.hand:return .serif;case .rounded:return .rounded;case .mono:return .monospaced;case .modern:return .default}}
}
enum CanvasLayerKind:String,CaseIterable,Codable{case text="Chữ",photo="Ảnh",sticker="Sticker",quote="Trích dẫn"}
struct MemoryCanvasLayer:Codable,Identifiable,Equatable{
    var id=UUID()
    var kind:CanvasLayerKind
    var text=""
    var photo:UUID?
    var x=0.5
    var y=0.5
    var size=0.27
    var rotation=0.0
    var color="FFFFFF"
    var font:CanvasFont = .serif
}
struct MemoryCanvasDesign:Codable,Equatable{
    var background="18251F"
    var layers:[MemoryCanvasLayer]=[]
}
struct StoryCanvasStudio:View{
    let target:StoryTarget
    let vault:Vault
    @ObservedObject var archive:StoryArchive
    @Environment(\.dismiss) private var dismiss
    @State private var design=MemoryCanvasDesign()
    @State private var selected:UUID?
    @State private var output:URL?
    @State private var notice=""
    private var selection:Int?{design.layers.firstIndex{$0.id==selected}}
    var body:some View{
        NavigationStack{
            ScrollView{
                VStack(spacing:12){
                    GeometryReader{g in
                        ZStack{
                            GardenColor.decode(design.background)
                            ForEach(design.layers){layer in
                                CanvasLayerView(layer:layer,shots:target.shots,vault:vault,width:g.size.width,height:g.size.height)
                                    .overlay{if selected==layer.id{RoundedRectangle(cornerRadius:4).strokeBorder(gold,style:StrokeStyle(lineWidth:1,dash:[4,3]))}}
                                    .rotationEffect(.degrees(layer.rotation))
                                    .position(x:g.size.width*layer.x,y:g.size.height*layer.y)
                                    .onTapGesture{selected=layer.id}
                                    .gesture(DragGesture(coordinateSpace:.named("storyCanvas")).onChanged{v in
                                        selected=layer.id
                                        if let i=design.layers.firstIndex(where:{$0.id==layer.id}){design.layers[i].x=max(0.03,min(0.97,v.location.x/g.size.width));design.layers[i].y=max(0.03,min(0.97,v.location.y/g.size.height))}
                                    })
                            }
                        }.coordinateSpace(name:"storyCanvas").clipped()
                    }.aspectRatio(0.72,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:13))
                    HStack{
                        Menu("Thêm layer",systemImage:"plus.circle"){Button("Văn bản"){append(.text,"Câu chuyện của tôi")};Button("Trích dẫn"){append(.quote,"Điều đáng nhớ…")};Button("Sticker"){append(.sticker,"✿")};ForEach(target.shots.prefix(100)){s in Button("Ảnh \(s.day)"){var l=MemoryCanvasLayer(kind:.photo);l.photo=s.id;l.size=0.65;design.layers.append(l);selected=l.id}}}
                        Spacer()
                        ColorPicker("Nền",selection:Binding(get:{GardenColor.decode(design.background)},set:{design.background=GardenColor.encode($0)}),supportsOpacity:false).labelsHidden()
                    }
                    if let i=selection{
                        GroupBox("Layer đang chọn"){
                            VStack(alignment:.leading,spacing:9){
                                if design.layers[i].kind != .photo{
                                    TextField("Nội dung",text:$design.layers[i].text,axis:.vertical)
                                    Picker("Font",selection:$design.layers[i].font){ForEach(CanvasFont.allCases,id:\.self){Text($0.rawValue).tag($0)}}
                                    ColorPicker("Màu chữ",selection:Binding(get:{GardenColor.decode(design.layers[i].color)},set:{design.layers[i].color=GardenColor.encode($0)}),supportsOpacity:false)
                                }
                                Text("Kích thước");Slider(value:$design.layers[i].size,in:0.08...0.95)
                                Text("Xoay");Slider(value:$design.layers[i].rotation,in:-180...180)
                                HStack{
                                    Button("Ra trước"){let l=design.layers.remove(at:i);design.layers.append(l)}
                                    Button("Ra sau"){let l=design.layers.remove(at:i);design.layers.insert(l,at:0)}
                                    Spacer()
                                    Button("Xóa",role:.destructive){design.layers.remove(at:i);selected=nil}
                                }.font(.caption)
                            }
                        }
                    }
                    GroupBox("Xuất thiết kế"){
                        VStack{
                            Button("Xuất PNG"){export(pdf:false)}.buttonStyle(.borderedProminent)
                            Button("Xuất trang PDF"){export(pdf:true)}
                            if let output{ShareLink(item:output){Label("Lưu / Chia sẻ",systemImage:"square.and.arrow.up")}}
                            Text(notice).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.padding()
            }.navigationTitle("Story Canvas").navigationBarTitleDisplayMode(.inline).toolbar{
                ToolbarItem(placement:.cancellationAction){Button("Đóng"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button("Lưu"){save()}}
            }
        }.onAppear{
            if let existing=archive.entry(target.id)?.canvas{design=existing}
            else if let draft=archive.drafts[target.id]?.canvas{design=draft}
            else{
                if let shot=target.shots.first{var layer=MemoryCanvasLayer(kind:.photo);layer.photo=shot.id;layer.size=0.85;layer.y=0.35;design.layers.append(layer)}
                var text=MemoryCanvasLayer(kind:.text);text.text=archive.entry(target.id)?.title ?? target.label;text.y=0.78;text.size=0.82;design.layers.append(text)
            }
        }
    }
    private func append(_ kind:CanvasLayerKind,_ text:String){let l=MemoryCanvasLayer(kind:kind,text:text);design.layers.append(l);selected=l.id}
    private func save(){
        var value=archive.entry(target.id) ?? archive.draft(target)
        value.canvas=design
        do{try archive.save(value,draft:archive.entry(target.id)==nil);notice="Đã lưu thiết kế."}catch{notice=error.localizedDescription}
    }
    private func export(pdf:Bool){
        let width=1080.0,height=1500.0
        let renderer=ImageRenderer(content:CanvasRender(design:design,shots:target.shots,vault:vault,width:width,height:height))
        renderer.scale=1
        guard let image=renderer.uiImage else{notice="Không xuất được canvas.";return}
        do{
            let data:Data
            if pdf{data=UIGraphicsPDFRenderer(bounds:CGRect(x:0,y:0,width:width,height:height)).pdfData{ctx in ctx.beginPage();image.draw(in:CGRect(x:0,y:0,width:width,height:height))}}
            else{guard let png=image.pngData() else{throw CameraError.writeFailed};data=png}
            output=try CreativeEngine.exportURL(data,extension:pdf ? "pdf":"png");notice="Đã xuất thiết kế."
        }catch{notice=error.localizedDescription}
    }
}
private struct CanvasLayerView:View{
    let layer:MemoryCanvasLayer
    let shots:[Shot]
    let vault:Vault
    let width:CGFloat
    let height:CGFloat
    var body:some View{
        if layer.kind == .photo,let shot=shots.first(where:{$0.id==layer.photo}){
            if let bytes=try? Data(contentsOf:vault.thumbnail(shot.id)),let image=UIImage(data:bytes){
                Image(uiImage:image).resizable().scaledToFill().frame(width:width*layer.size,height:width*layer.size*0.8).clipped()
            }
        }else{
            let fontSize=max(10,width*layer.size*0.14)
            Text(layer.kind == .quote ? "“\(layer.text)”":layer.text)
                .font(layer.font == .hand ? .custom("Noteworthy",size:fontSize):.system(size:fontSize,design:layer.font.font))
                .foregroundStyle(GardenColor.decode(layer.color))
                .multilineTextAlignment(.center).frame(width:max(30,width*layer.size))
        }
    }
}
private struct CanvasRender:View{
    let design:MemoryCanvasDesign
    let shots:[Shot]
    let vault:Vault
    let width:CGFloat
    let height:CGFloat
    var body:some View{
        ZStack{
            GardenColor.decode(design.background)
            ForEach(design.layers){layer in
                CanvasLayerView(layer:layer,shots:shots,vault:vault,width:width,height:height).rotationEffect(.degrees(layer.rotation)).position(x:width*layer.x,y:height*layer.y)
            }
        }.frame(width:width,height:height).clipped()
    }
}
enum StoryTextEffect:String,CaseIterable,Codable{
    case normal="Tĩnh",typewriter="Máy đánh chữ",fade="Trích dẫn hiện dần"
}
struct AnimatedStoryText:View{
    let text:String
    let effect:StoryTextEffect
    let font:CanvasFont
    let color:Color
    var duration:Double=3
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var visible=0
    @State private var shown=false
    var body:some View{
        Text(effect == .typewriter && !reduced ? String(text.prefix(visible)):text)
            .font(font == .hand ? .custom("Noteworthy",size:17):.system(.body,design:font.font))
            .foregroundStyle(color).lineSpacing(5)
            .opacity(effect == .fade && !shown && !reduced ? 0:1)
            .task(id:text+effect.rawValue){
                visible=0;shown=false
                if reduced || effect == .normal{visible=text.count;shown=true;return}
                if effect == .fade{withAnimation(.easeIn(duration:0.8)){shown=true};return}
                let count=text.count,steps=min(100,max(1,count))
                for i in 1...steps{
                    do{try await Task.sleep(for:.seconds(max(0.015,duration/Double(steps))))}catch{return}
                    visible=count*i/steps
                }
            }
    }
}
enum StoryPDF{
    @MainActor static func export(_ entry:StoryEntry,shots:[Shot],vault:Vault)throws->URL{
        let bounds=CGRect(x:0,y:0,width:595,height:842)
        let pdf=UIGraphicsPDFRenderer(bounds:bounds)
        let data=pdf.pdfData{ctx in
            let title=entry.title.isEmpty ? "Miền ký ức":entry.title
            let text=[entry.body,entry.quote,entry.location,entry.people,entry.tags].filter{!$0.isEmpty}.joined(separator:"\n\n")
            let style=NSMutableParagraphStyle();style.lineSpacing=6
            let attributes:[NSAttributedString.Key:Any]=[.font:UIFont.systemFont(ofSize:14),.paragraphStyle:style,.foregroundColor:UIColor.darkGray]
            let string=NSAttributedString(string:text,attributes:attributes)
            let framesetter=CTFramesetterCreateWithAttributedString(string)
            var offset=0
            repeat{
                ctx.beginPage()
                (title as NSString).draw(in:CGRect(x:42,y:40,width:511,height:88),withAttributes:[.font:UIFont.systemFont(ofSize:28,weight:.semibold),.foregroundColor:UIColor.black])
                let rect=CGRect(x:42,y:45,width:511,height:665)
                let frame=CTFramesetterCreateFrame(framesetter,CFRange(location:offset,length:0),CGPath(rect:rect,transform:nil),nil)
                let cg=ctx.cgContext;cg.saveGState();cg.translateBy(x:0,y:bounds.height);cg.scaleBy(x:1,y:-1);CTFrameDraw(frame,cg);cg.restoreGState()
                let n=CTFrameGetVisibleStringRange(frame).length
                if n<=0{break};offset+=n
            }while offset<string.length
            for shot in shots{
                guard let data=try? Data(contentsOf:vault.picture(shot)),let cg=PhotoEngine.thumb(data,limit:1500) else{continue}
                ctx.beginPage();let image=UIImage(cgImage:cg),r=min(511/image.size.width,620/image.size.height),w=image.size.width*r,h=image.size.height*r
                image.draw(in:CGRect(x:(595-w)/2,y:55,width:w,height:h))
                let caption=entry.captions[shot.id.uuidString] ?? TimelineIndex.label(shot.day)
                (caption as NSString).draw(in:CGRect(x:42,y:700,width:511,height:95),withAttributes:attributes)
            }
        }
        return try CreativeEngine.exportURL(data,extension:"pdf")
    }
}
