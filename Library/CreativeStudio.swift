import SwiftUI
import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

struct CreativeVersion:Codable,Identifiable {
    var id=UUID()
    let name:String
    let date:Date
    let recipe:CreativeRecipe
    let photoIDs:[UUID]
    var original:Bool?=nil
}
struct CreativeRecipe:Codable,Equatable {
    var exposure=0.0
    var contrast=1.0
    var saturation=1.0
    var warmth=0.0
    var crop="Gốc"
    var compositionAnchor:CompositionAnchor?=nil
    var highlights:Double?=nil
    var shadows:Double?=nil
    var vibrance:Double?=nil
    var sharpness:Double?=nil
    var noise:Double?=nil
    var vignette:Double?=nil
    var tint:Double?=nil
    var rotation:Int?=nil
    var mirror:Bool?=nil
    var film:String?=nil
    var premiumID:String?=nil
    var premiumStrength:Double?=nil
    var lighting:LightMockupRecipe?=nil
    var masking:[PhotoMaskDocument]?=nil
}
enum CreativeEngine {
    private static let context=CIContext(options:[.cacheIntermediates:false])
    static func fileExtension(_ format:String)->String{format=="PNG" ? "png":format=="HEIC" ? "heic":"jpg"}
    static func render(_ url:URL,recipe:CreativeRecipe,maxSize:Int,format:String,quality:Double,metadata:Bool,thumbnailOnly:Bool=false)->Data?{
        guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),
              let full=CIImage(contentsOf:url,options:[.applyOrientationProperty:true]),maxSize>0 else{return nil}
        let image:CIImage
        if thumbnailOnly,recipe.masking==nil,recipe.lighting==nil,recipe.crop=="Gốc",let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:max(1,maxSize*2)] as CFDictionary){image=CIImage(cgImage:cg)}else{image=full}
        let initial=PremiumColorEngine.apply(image,id:recipe.premiumID,strength:recipe.premiumStrength ?? 0.8)
        var result=initial.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:recipe.exposure])
            .applyingFilter("CIColorControls",parameters:[kCIInputContrastKey:recipe.contrast,kCIInputSaturationKey:recipe.saturation])
        if recipe.warmth != 0 {result=result.applyingFilter("CITemperatureAndTint",parameters:["inputNeutral":CIVector(x:6500,y:0),"inputTargetNeutral":CIVector(x:6500+recipe.warmth*2000,y:0)])}
        let highlight=recipe.highlights ?? 0,shadow=recipe.shadows ?? 0
        if highlight != 0 || shadow != 0{result=result.applyingFilter("CIHighlightShadowAdjust",parameters:["inputHighlightAmount":1+highlight,"inputShadowAmount":shadow])}
        if let tint=recipe.tint,tint != 0{result=result.applyingFilter("CITemperatureAndTint",parameters:["inputNeutral":CIVector(x:6500,y:0),"inputTargetNeutral":CIVector(x:6500,y:tint*100)])}
        if let vibrance=recipe.vibrance,vibrance != 0{result=result.applyingFilter("CIVibrance",parameters:["inputAmount":vibrance])}
        if let noise=recipe.noise,noise>0{result=MasterImageQuality.noise(result,amount:noise)}
        if let sharpness=recipe.sharpness,sharpness>0{result=MasterImageQuality.sharpen(result,amount:sharpness)}
        if let vignette=recipe.vignette,vignette>0{result=result.applyingFilter("CIVignette",parameters:["inputIntensity":vignette,"inputRadius":1.5])}
        switch recipe.film{
        case "Film 35mm":result=result.applyingFilter("CIPhotoEffectInstant")
        case "Noir":result=result.applyingFilter("CIPhotoEffectNoir")
        case "Chrome":result=result.applyingFilter("CIPhotoEffectChrome")
        case "Fade":result=result.applyingFilter("CIPhotoEffectFade")
        default:break
        }
        let maskKey=SemanticMaskEngine.sourceKey(url)
        if let document=recipe.masking?.first(where:{$0.source==maskKey}){
            do{result=try SemanticMaskEngine.apply(result,original:image,document:document,key:maskKey)}catch{return nil}
        }
        if recipe.lighting != nil{
            let stamp=(try? url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970) ?? 0
            guard let lit=LightMockupEngine.apply(result,original:image,recipe:recipe.lighting,key:url.path+"#"+String(stamp),document:recipe.masking?.first(where:{$0.source==maskKey}),sourceKey:maskKey) else{return nil}
            result=lit
        }
        switch recipe.rotation ?? 0{case 90:result=result.oriented(.left);case 180:result=result.oriented(.down);case 270:result=result.oriented(.right);default:break}
        if recipe.mirror == true{result=result.transformed(by:CGAffineTransform(scaleX:-1,y:1))}
        let rect=result.extent.integral
        guard rect.width>0,rect.height>0,rect.width*rect.height<=70_000_000 else{return nil}
        if recipe.crop != "Gốc" {
            let ratio:CGFloat=recipe.crop=="1:1" ? 1 : recipe.crop=="4:5" ? 0.8:recipe.crop=="9:16" ? 9/16:recipe.crop=="3:2" ? 3/2:16/9
            result=result.cropped(to:(recipe.compositionAnchor ?? CompositionAnchor()).rect(in:rect,ratio:ratio))
        }
        result=MasterImageQuality.downsample(result,maxSize:maxSize)
        guard let cg=context.createCGImage(result,from:result.extent.integral,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!) else{return nil}
        let data=NSMutableData(),type=format=="PNG" ? UTType.png:format=="HEIC" ? UTType.heic:UTType.jpeg
        guard let dest=CGImageDestinationCreateWithData(data,type.identifier as CFString,1,nil) else{return nil}
        var tags:[String:Any]=[kCGImagePropertyOrientation as String:1,kCGImageDestinationLossyCompressionQuality as String:quality]
        if metadata,format != "PNG",let props=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any]{
            if var exif=props[kCGImagePropertyExifDictionary as String] as? [String:Any]{
                exif.removeValue(forKey:kCGImagePropertyExifMakerNote as String)
                exif[kCGImagePropertyExifPixelXDimension as String]=cg.width
                exif[kCGImagePropertyExifPixelYDimension as String]=cg.height
                tags[kCGImagePropertyExifDictionary as String]=exif
            }
        }
        CGImageDestinationAddImage(dest,cg,tags as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data:nil
    }
    static func exportURL(_ data:Data,extension ext:String)throws->URL{
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("VieLens-"+UUID().uuidString).appendingPathExtension(ext)
        try data.write(to:url,options:[.atomic,.completeFileProtection])
        return url
    }
}
struct CreativeStudio:View {
    let shots:[Shot]
    let vault:Vault
    @State private var recipe=CreativeRecipe()
    @State private var preview:UIImage?
    @State private var selected=0
    @State private var format="JPEG"
    @State private var maxSize=100000
    @State private var quality=0.94
    @State private var metadata=false
    @State private var outputs=[URL]()
    @State private var working=false
    @State private var notice=""
    @AppStorage("signature.versions.v1") private var versionData=Data()
    @State private var history=[CreativeVersion]()
    @State private var versionName=""
    @State private var showVersionName=false
    @State private var useOriginal=false
    @State private var originalPreview=false
    @State private var showPremium=true
    @State private var showTaste=true
    @State private var showWorkflow=true
    @State private var tasteScene=TasteScene.auto
    @ObservedObject private var taste=PhotoTasteStore.shared
    @State private var showLighting=false
    @State private var showMaskStudio=false
    @State private var showManual=false
    @State private var previewError=false
    @State private var renderedKey:PreviewKey?
    @State private var previewSource:URL?
    private var activeKey:PreviewKey{PreviewKey(recipe:recipe,index:selected,original:useOriginal)}
    private var previewReady:Bool{renderedKey==activeKey && preview != nil && !previewError}
    @AppStorage("signature.colorPreset") private var savedPreset=Data()
    private var current:Shot?{shots.indices.contains(selected) ? shots[selected]:nil}
    var body:some View{
        ScrollView{
            VStack(spacing:14){
                if originalPreview,let current{DiskImage(url:vault.picture(current,original:useOriginal),limit:1400).scaledToFit().frame(maxHeight:410)}
                else if let preview,let current,previewSource==vault.picture(current,original:useOriginal){Image(uiImage:preview).resizable().scaledToFit().frame(maxHeight:330)}
                else if let current{DiskImage(url:vault.picture(current,original:useOriginal),limit:1000).scaledToFit().frame(height:250)}
                Toggle("Chỉnh từ ảnh gốc",isOn:$useOriginal)
                Toggle("Xem ảnh trước chỉnh sửa",isOn:$originalPreview)
                if shots.count>1{Picker("Ảnh xem trước",selection:$selected){ForEach(shots.indices,id:\.self){i in Text("\(i+1) · \(shots[i].day)").tag(i)}}}
                if !previewReady && !previewError && !originalPreview{ProgressView("Đang cập nhật ảnh…").font(.caption)}
                if previewError{Text("Không thể kết xuất ảnh hiện tại. Kiểm tra mặt nạ hoặc mockup đang dùng. Nếu không tìm thấy chủ thể, hãy chỉnh mặt nạ hoặc bỏ phông nền.").font(.caption).foregroundStyle(.orange)}
                if let current{
                    DisclosureGroup("Adaptive AI · Quy trình hậu kỳ",isExpanded:$showWorkflow){AdaptiveWorkflowPanel(url:vault.picture(current,original:useOriginal),recipe:$recipe,scene:tasteScene,taste:taste).padding(.top,8)}.padding(12).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
                }
                if let current{
                    DisclosureGroup("Personal Style AI · Gu màu của tôi",isExpanded:$showTaste){
                        PhotoTastePanel(url:vault.picture(current,original:useOriginal),recipe:$recipe,scene:$tasteScene,store:taste).padding(.top,8)
                    }.padding(12).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
                }
                DisclosureGroup("Bộ preset Premium · 32 màu",isExpanded:$showPremium){PremiumPresetPanel(url:current.map{vault.picture($0,original:useOriginal)},recipe:$recipe).padding(.top,8)}.padding(12).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
                if let current{
                    let source=vault.picture(current,original:useOriginal),key=SemanticMaskEngine.sourceKey(source)
                    let layers=recipe.masking?.first(where:{$0.source==key})?.layers.count ?? 0
                    Button{showMaskStudio=true}label:{
                        HStack(spacing:12){
                            Image(systemName:"circle.dotted.circle.fill").font(.title2).foregroundStyle(gold)
                            VStack(alignment:.leading,spacing:4){Text("Masking Studio").font(.headline);Text(layers==0 ? "Bầu trời, người, mắt, môi, nền · chỉnh riêng vùng":"\(layers) mặt nạ trên ảnh này").font(.caption).foregroundStyle(.secondary)}
                            Spacer();Image(systemName:"chevron.right").font(.caption)
                        }.padding(12).background(.white.opacity(0.065),in:RoundedRectangle(cornerRadius:12))
                    }.buttonStyle(.plain)
                }
                DisclosureGroup("Lighting & Mockup Studio · 24 asset",isExpanded:$showLighting){LightMockupPanel(recipe:$recipe,onRefine:{showMaskStudio=true}).padding(.top,8)}.padding(12).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
                DisclosureGroup("Hậu kỳ chuyên sâu · Color Studio",isExpanded:$showManual){
                    VStack(alignment:.leading){
                        control("Phơi sáng",value:$recipe.exposure,range:-2...2)
                        control("Tương phản",value:$recipe.contrast,range:0.6...1.5)
                        control("Bão hòa",value:$recipe.saturation,range:0...2)
                        control("Nhiệt độ màu",value:$recipe.warmth,range:-1...1)
                        control("Vùng sáng",value:optional(\.highlights),range:-1...0)
                        control("Vùng tối",value:optional(\.shadows),range:-0.5...1)
                        control("Sắc thái xanh / hồng",value:optional(\.tint),range:-1...1)
                        control("Màu thông minh",value:optional(\.vibrance),range:-1...1)
                        control("Độ nét",value:optional(\.sharpness),range:0...1)
                        control("Khử nhiễu",value:optional(\.noise),range:0...1)
                        control("Tối viền",value:optional(\.vignette),range:0...2)
                        Picker("Chất phim",selection:Binding(get:{recipe.film ?? "Gốc"},set:{recipe.film=$0})){ForEach(["Gốc","Film 35mm","Noir","Chrome","Fade"],id:\.self){Text($0).tag($0)}}
                        Picker("Tỷ lệ cắt ảnh",selection:$recipe.crop){ForEach(["Gốc","1:1","4:5","9:16","3:2","16:9"],id:\.self){Text($0).tag($0)}}
                        if recipe.crop != "Gốc"{
                            if let current{
                                Button("AI căn bố cục",systemImage:"viewfinder"){let u=vault.picture(current,original:useOriginal),crop=recipe.crop;Task{let result=await Task.detached(priority:.userInitiated){CompositionEngine.proposal(url:u,crop:crop)}.value;if let result,recipe.crop==crop,self.current?.id==current.id{recipe.compositionAnchor=result}}}.disabled((recipe.rotation ?? 0) != 0 || recipe.mirror == true)
                            }
                            control("Căn ngang",value:Binding(get:{recipe.compositionAnchor?.x ?? 0.5},set:{var a=recipe.compositionAnchor ?? CompositionAnchor();a.x=$0;recipe.compositionAnchor=a}),range:0...1)
                            control("Căn dọc",value:Binding(get:{recipe.compositionAnchor?.y ?? 0.5},set:{var a=recipe.compositionAnchor ?? CompositionAnchor();a.y=$0;recipe.compositionAnchor=a}),range:0...1)
                            Button("Căn giữa"){recipe.compositionAnchor=nil}.font(.caption)
                        }
                        HStack{Button("Xoay 90°",systemImage:"rotate.right"){recipe.rotation=((recipe.rotation ?? 0)+90)%360};Spacer();Button("Lật ngang",systemImage:"arrow.left.and.right.righttriangle.left.righttriangle.right"){recipe.mirror = !(recipe.mirror ?? false)}}.font(.caption)
                        HStack{
                            Button("Lưu preset"){versionName="";showVersionName=true}.disabled(!previewReady || working)
                            Spacer()
                            Button("Dùng preset"){if let r=try? JSONDecoder().decode(CreativeRecipe.self,from:savedPreset){var next=r;next.masking=recipe.masking;recipe=next}}
                            Button("Đặt lại"){recipe=CreativeRecipe()}
                        }.font(.caption)
                        if !history.isEmpty{
                            Menu("Lịch sử chỉnh sửa · \(history.count)"){
                                ForEach(history.reversed()){v in
                                    Button("\(v.name) · \(v.date.formatted(date:.abbreviated,time:.shortened))"){recipe=v.recipe;useOriginal=v.original ?? false}
                                }
                                Button("Xóa lịch sử preset",role:.destructive){history=[];persistVersions()}
                            }
                        }
                    }
                }
                GroupBox("Export Studio"){
                    VStack{
                        Picker("Định dạng",selection:$format){Text("JPEG").tag("JPEG");Text("HEIC").tag("HEIC");Text("PNG").tag("PNG")}.pickerStyle(.segmented)
                        Picker("Cạnh dài tối đa",selection:$maxSize){Text("1080 px").tag(1080);Text("2048 px").tag(2048);Text("4096 px").tag(4096);Text("Gốc").tag(100000)}
                        if format != "PNG"{control("Chất lượng nén",value:$quality,range:0.5...1);Toggle("Giữ thông số EXIF (không GPS)",isOn:$metadata)}
                        Button("Xuất \(shots.count) ảnh đã chọn"){Task{await export()}}.buttonStyle(.borderedProminent).disabled(working || shots.isEmpty || !previewReady)
                        if working{ProgressView()}
                        if !outputs.isEmpty{ShareLink(items:outputs){Label("Chia sẻ / Lưu tệp",systemImage:"square.and.arrow.up")}}
                        Text(notice).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Ảnh xuất là bản sao; không ghi đè ảnh gốc. Các phiên bản đã đặt tên lưu công thức chỉnh sửa và ID ảnh trên thiết bị.").font(.caption).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("Premium Photo Lab")
        .sheet(isPresented:$showMaskStudio){if let current{PhotoMaskStudio(url:vault.picture(current,original:useOriginal),recipe:$recipe)}}
        .onChange(of:selected){_,_ in tasteScene = .auto}
        .onAppear{history=(try? JSONDecoder().decode([CreativeVersion].self,from:versionData)) ?? []}
        .alert("Lưu phiên bản",isPresented:$showVersionName){TextField("Tên phiên bản",text:$versionName);Button("Lưu"){guard previewReady,!working else{notice="Ảnh chưa kết xuất xong.";return};var reusable=recipe;reusable.masking=nil;guard let data=try? JSONEncoder().encode(reusable) else{notice="Không lưu được công thức.";return};let name=versionName.trimmingCharacters(in:.whitespacesAndNewlines);history.append(CreativeVersion(name:name.isEmpty ? "Phiên bản \(history.count+1)":name,date:Date(),recipe:recipe,photoIDs:shots.map(\.id),original:useOriginal));persistVersions();savedPreset=data;if let shot=current{let r=recipe,u=vault.picture(shot,original:useOriginal),s=tasteScene,token=taste.generation;Task{await learnTaste(photo:shot.id,url:u,recipe:r,scene:s,token:token)}}};Button("Hủy",role:.cancel){}}
        .task(id:activeKey){
            guard let current else{return}
            let key=activeKey,r=recipe,url=vault.picture(current,original:useOriginal)
            if previewSource != url{preview=nil;previewSource=url};previewError=false;renderedKey=nil
            do{try await Task.sleep(for:.milliseconds(180))}catch{return}
            let data=await PhotoPreviewWorker.shared.photo(url,recipe:r,maxSize:1600,thumbnail:false)
            if !Task.isCancelled,activeKey==key{preview=data.flatMap{UIImage(data:$0)};previewError=preview==nil;renderedKey=key}
        }
    }
    private struct PreviewKey:Equatable {let recipe:CreativeRecipe;let index:Int;let original:Bool}
    private func optional(_ key:WritableKeyPath<CreativeRecipe,Double?>)->Binding<Double>{Binding(get:{recipe[keyPath:key] ?? 0},set:{recipe[keyPath:key]=$0})}
    private func persistVersions(){if let data=try? JSONEncoder().encode(history){versionData=data}}
    private func control(_ title:String,value:Binding<Double>,range:ClosedRange<Double>)->some View{
        VStack(alignment:.leading){Text("\(title) · \(String(format:"%.2f",value.wrappedValue))").font(.caption);Slider(value:value,in:range)}
    }
    @MainActor private func learnTaste(photo:UUID,url:URL,recipe:CreativeRecipe,scene:TasteScene,token:UUID)async{
        guard taste.enabled,token==taste.generation else{return}
        let key=SemanticMaskEngine.sourceKey(url)
        guard let context=await Task.detached(priority:.utility,operation:{TasteContext.analyze(url,override:scene)}).value else{return}
        let feedback=await Task.detached(priority:.utility){CompositionEngine.feedback(url:url,recipe:recipe)}.value
        var sample=TasteSample(photo:photo,context:context,recipe:recipe,source:key);sample.compositionFeedback=feedback
        taste.record(sample,token:token)
    }
    @MainActor private func export()async{
        guard previewReady,!working else{return}
        working=true;outputs=[];notice=""
        defer{working=false}
        let r=recipe,size=maxSize,f=format,q=quality,m=metadata,v=vault,original=useOriginal
        let chosen=current?.id,scene=tasteScene,token=taste.generation
        var learned:Shot?
        for shot in shots{
            if let url=await Task.detached(priority:.utility,operation:{()->URL? in
                guard let d=CreativeEngine.render(v.picture(shot,original:original),recipe:r,maxSize:size,format:f,quality:q,metadata:m) else{return nil}
                return try? CreativeEngine.exportURL(d,extension:CreativeEngine.fileExtension(f))
            }).value{outputs.append(url);if learned==nil || shot.id==chosen{learned=shot}}
        }
        notice="Đã xuất \(outputs.count)/\(shots.count) ảnh."
        if let shot=learned,shot.id==chosen{await learnTaste(photo:shot.id,url:v.picture(shot,original:original),recipe:r,scene:scene,token:token)}
    }
}
struct CollageStudio:View {
    let shots:[Shot]
    let vault:Vault
    @State private var columns=2
    @State private var gap=12.0
    @State private var output:URL?
    @State private var working=false
    var body:some View{
        VStack{
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:gap/3),count:columns),spacing:gap/3){
                ForEach(Array(shots.prefix(12))){s in DiskImage(url:vault.thumbnail(s.id),limit:400).scaledToFill().frame(height:100).clipped()}
            }.padding()
            Stepper("Số cột: \(columns)",value:$columns,in:1...4).padding(.horizontal)
            Slider(value:$gap,in:0...40).padding(.horizontal)
            Button("Xuất collage JPEG"){working=true;Task{
                let items=Array(shots.prefix(12)),v=vault,c=columns,g=gap
                output=await Task.detached(priority:.utility){()->URL? in
                    let tile=600.0,rows=Int(ceil(Double(items.count)/Double(c)))
                    guard rows>0 else{return nil}
                    let size=CGSize(width:Double(c)*tile+Double(c+1)*g,height:Double(rows)*tile+Double(rows+1)*g)
                    let fmt=UIGraphicsImageRendererFormat();fmt.scale=1
                    let image=UIGraphicsImageRenderer(size:size,format:fmt).image{ctx in
                        UIColor.black.setFill();ctx.fill(CGRect(origin:.zero,size:size))
                        for (i,s) in items.enumerated(){
                            guard let data=try? Data(contentsOf:v.picture(s)),let cg=PhotoEngine.thumb(data,limit:1200) else{continue}
                            let box=CGRect(x:g+Double(i%c)*(tile+g),y:g+Double(i/c)*(tile+g),width:tile,height:tile)
                            let im=UIImage(cgImage:cg),scale=max(tile/im.size.width,tile/im.size.height)
                            let w=im.size.width*scale,h=im.size.height*scale
                            ctx.cgContext.saveGState();ctx.cgContext.clip(to:box)
                            im.draw(in:CGRect(x:box.midX-w/2,y:box.midY-h/2,width:w,height:h));ctx.cgContext.restoreGState()
                        }
                    }
                    guard let d=image.jpegData(compressionQuality:0.94) else{return nil}
                    return try? CreativeEngine.exportURL(d,extension:"jpg")
                }.value
                working=false
            }}.buttonStyle(.borderedProminent).disabled(working || shots.isEmpty)
            if working{ProgressView()}
            if let output{ShareLink(item:output){Label("Chia sẻ collage",systemImage:"square.and.arrow.up")}}
            Text("Tối đa 12 ảnh, xuất bản sao JPEG.").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.navigationTitle("Photo Collage")
    }
}
enum MovieMotion:String,CaseIterable {
    case still="Tĩnh",zoom="Zoom chậm",pan="Lướt ngang"
}
enum MovieTransition:String,CaseIterable {
    case cut="Cắt thẳng",fade="Mờ dần",dissolve="Hòa ảnh"
}
enum MemoryMovie {
    static func make(_ shots:[Shot],vault:Vault,width:Int,height:Int,seconds:Int,title:String,motion:MovieMotion = .still,transition:MovieTransition = .cut,captions:[UUID:String]=[:],direction:StoryDirection?=nil) async throws->URL{
        guard !shots.isEmpty else{throw CameraError.unreadable}
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("VieLens-"+UUID().uuidString+".mp4")
        let writer=try AVAssetWriter(outputURL:url,fileType:.mp4)
        let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:width,AVVideoHeightKey:height])
        let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:width,kCVPixelBufferHeightKey as String:height,kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true])
        guard writer.canAdd(input) else{throw CameraError.writeFailed};input.expectsMediaDataInRealTime=false;writer.add(input)
        guard writer.startWriting() else{throw writer.error ?? CameraError.writeFailed}
        writer.startSession(atSourceTime:.zero)
        do{
            var frame:Int64=0
            var previous:CGImage?
            for (i,shot) in shots.enumerated(){
                try Task.checkCancellation()
                guard let data=try? Data(contentsOf:vault.picture(shot)),let image=PhotoEngine.thumb(data,limit:max(width,height)) else{throw CameraError.unreadable}
                let fmt=UIGraphicsImageRendererFormat();fmt.scale=1
                let size=CGSize(width:width,height:height)
                let still=UIGraphicsImageRenderer(size:size,format:fmt).image{c in
                    UIColor.black.setFill();c.fill(CGRect(origin:.zero,size:size))
                    let im=UIImage(cgImage:image),factor=min(size.width/im.size.width,size.height/im.size.height)
                    let w=im.size.width*factor,h=im.size.height*factor
                    im.draw(in:CGRect(x:(size.width-w)/2,y:(size.height-h)/2,width:w,height:h))
                    let caption=captions[shot.id] ?? TimelineIndex.label(shot.day)
                    let line=i==0 && !title.isEmpty ? (captions.isEmpty ? title:title+"\n"+caption):caption
                    let point=CGFloat(width)*0.033
                    let font: UIFont = direction?.typography=="Cổ điển" ? (UIFont(name:"Georgia",size:point) ?? .systemFont(ofSize:point)) : direction?.typography=="Máy đánh chữ" ? .monospacedSystemFont(ofSize:point,weight:.medium):.systemFont(ofSize:point,weight:.semibold)
                    let attrs:[NSAttributedString.Key:Any]=[.font:font,.foregroundColor:UIColor.white,.backgroundColor:UIColor.black.withAlphaComponent(0.6)]
                    (line as NSString).draw(in:CGRect(x:CGFloat(width)*0.04,y:CGFloat(height)*0.87,width:CGFloat(width)*0.92,height:CGFloat(height)*0.13),withAttributes:attrs)
                }
                guard let cg=still.cgImage else{throw CameraError.writeFailed}
                let frames=max(1,seconds*24)
                for j in 0..<frames{
                    try Task.checkCancellation()
                    let deadline=Date().addingTimeInterval(60)
                    while !input.isReadyForMoreMediaData {
                        guard writer.status == .writing,Date()<deadline else{throw writer.error ?? NSError(domain:"VieLens.Movie",code:1,userInfo:[NSLocalizedDescriptionKey:"Encoder không sẵn sàng ở frame \(frame)."])}
                        try await Task.sleep(for:.milliseconds(15))
                    }
                    let p=Double(j)/Double(max(1,frames-1))
                    let fadeFrames=min(12,max(1,frames/3))
                    let pixel:CVPixelBuffer=try autoreleasepool{
                        var buffer:CVPixelBuffer?
                        var status:CVReturn = kCVReturnError
                        if let pool=adaptor.pixelBufferPool{status=CVPixelBufferPoolCreatePixelBuffer(nil,pool,&buffer)}
                        if status != kCVReturnSuccess || buffer == nil{
                            let attrs=[kCVPixelBufferCGImageCompatibilityKey:true,kCVPixelBufferCGBitmapContextCompatibilityKey:true] as CFDictionary
                            status=CVPixelBufferCreate(nil,width,height,kCVPixelFormatType_32BGRA,attrs,&buffer)
                        }
                        guard status==kCVReturnSuccess,let pixel=buffer else{throw NSError(domain:"VieLens.Movie",code:Int(status),userInfo:[NSLocalizedDescriptionKey:"Không cấp phát được frame video."])} 
                        CVPixelBufferLockBaseAddress(pixel,[])
                        defer{CVPixelBufferUnlockBaseAddress(pixel,[])}
                        guard let ctx=CGContext(data:CVPixelBufferGetBaseAddress(pixel),width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(pixel),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else{throw CameraError.writeFailed}
                        let w=CGFloat(width),h=CGFloat(height),full=CGRect(x:0,y:0,width:w,height:h)
                        ctx.setFillColor(UIColor.black.cgColor);ctx.fill(full)
                        let scale:CGFloat=motion == .zoom ? CGFloat((direction?.startScale ?? 1)+((direction?.endScale ?? 1.075)-(direction?.startScale ?? 1))*p) : (motion == .pan ? 1.08:1)
                        let shift:CGFloat=motion == .pan ? (CGFloat(p)-0.5)*w*0.07:0
                        let rect=CGRect(x:(w-w*scale)/2+shift,y:(h-h*scale)/2,width:w*scale,height:h*scale)
                        if transition == .dissolve,let previous,j<fadeFrames{
                            ctx.draw(previous,in:full)
                            ctx.setAlpha(CGFloat(j+1)/CGFloat(fadeFrames))
                        }else if transition == .fade{
                            let incoming=CGFloat(j+1)/CGFloat(fadeFrames),outgoing=CGFloat(frames-j)/CGFloat(fadeFrames)
                            ctx.setAlpha(min(1,min(incoming,outgoing)))
                        }
                        ctx.draw(cg,in:rect)
                        return pixel
                    }
                    guard adaptor.append(pixel,withPresentationTime:CMTime(value:frame,timescale:24)) else{throw writer.error ?? CameraError.writeFailed}
                    frame+=1
                }
                previous=cg
            }
            writer.endSession(atSourceTime:CMTime(value:frame,timescale:24))
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else{throw writer.error ?? CameraError.writeFailed}
            return url
        }catch{writer.cancelWriting();try? FileManager.default.removeItem(at:url);throw error}
    }
}
enum MovieSoundtrack {
    static func add(video:URL,audio:URL,volume:Float)async throws->URL{
        let movie=AVURLAsset(url:video),music=AVURLAsset(url:audio)
        let duration=try await movie.load(.duration),audioDuration=try await music.load(.duration)
        guard CMTimeGetSeconds(duration)>0,CMTimeGetSeconds(audioDuration)>0,
              let v=try await movie.loadTracks(withMediaType:.video).first,
              let a=try await music.loadTracks(withMediaType:.audio).first else{throw CameraError.unreadable}
        let comp=AVMutableComposition()
        guard let videoTrack=comp.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid),
              let audioTrack=comp.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid) else{throw CameraError.writeFailed}
        try videoTrack.insertTimeRange(CMTimeRange(start:.zero,duration:duration),of:v,at:.zero)
        videoTrack.preferredTransform=try await v.load(.preferredTransform)
        var position=CMTime.zero
        while CMTimeCompare(position,duration)<0 {
            let left=CMTimeSubtract(duration,position)
            let length=CMTimeMinimum(left,audioDuration)
            guard CMTimeGetSeconds(length)>0 else{break}
            try audioTrack.insertTimeRange(CMTimeRange(start:.zero,duration:length),of:a,at:position)
            position=CMTimeAdd(position,length)
        }
        let params=AVMutableAudioMixInputParameters(track:audioTrack)
        params.setVolume(volume,at:.zero)
        let fade=CMTimeMinimum(CMTime(seconds:1,preferredTimescale:600),duration)
        params.setVolumeRamp(fromStartVolume:volume,toEndVolume:0,timeRange:CMTimeRange(start:CMTimeSubtract(duration,fade),duration:fade))
        let mix=AVMutableAudioMix();mix.inputParameters=[params]
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("VieLens-Music-"+UUID().uuidString+".mp4")
        guard let exporter=AVAssetExportSession(asset:comp,presetName:AVAssetExportPresetHighestQuality) else{throw CameraError.writeFailed}
        exporter.outputURL=url;exporter.outputFileType = .mp4;exporter.audioMix=mix
        await exporter.export()
        guard exporter.status == .completed else{try? FileManager.default.removeItem(at:url);throw exporter.error ?? CameraError.writeFailed}
        return url
    }
}
struct MemoryCinema:View {
    let shots:[Shot]
    let vault:Vault
    @State private var title=""
    @State private var resolution=1080
    @State private var motion=MovieMotion.zoom
    @State private var transition=MovieTransition.dissolve
    @State private var audio:URL?
    @State private var chooseAudio=false
    @State private var volume=0.65
    @State private var vertical=false
    @State private var seconds=3
    @State private var working=false
    @State private var output:URL?
    @State private var notice=""
    var body:some View{
        Form{
            Section("Video ký ức"){
                TextField("Tiêu đề",text:$title)
                Picker("Độ phân giải",selection:$resolution){Text("1080p").tag(1080);Text("4K").tag(2160)}
                Picker("Thời gian mỗi ảnh",selection:$seconds){ForEach([2,3,5],id:\.self){Text("\($0) giây").tag($0)}}
                Text("\(min(60,shots.count)) ảnh · MP4 H.264 · 24 fps").font(.caption)
                Toggle("Video dọc 9:16",isOn:$vertical)
                Picker("Chuyển động",selection:$motion){ForEach(MovieMotion.allCases,id:\.self){Text($0.rawValue).tag($0)}}
                Picker("Chuyển cảnh",selection:$transition){ForEach(MovieTransition.allCases,id:\.self){Text($0.rawValue).tag($0)}}
            }
            Section("Nhạc nền"){
                Button(audio?.lastPathComponent ?? "Chọn nhạc từ Tệp"){chooseAudio=true}.disabled(working)
                if audio != nil{Slider(value:$volume,in:0...1);Button("Bỏ nhạc",role:.destructive){audio=nil}.disabled(working)}
                Text("Nhạc được lặp theo thời lượng phim và giảm âm cuối.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Tạo video"){working=true;notice="";output=nil;Task{
                let items=Array(shots.prefix(60)),v=vault,r=resolution,s=seconds,t=title,m=motion,tr=transition,a=audio,vol=Float(volume),isVertical=vertical
                do{
                    output=try await Task.detached(priority:.userInitiated){
                        let long=r==2160 ? 3840:1920
                        let video=try await MemoryMovie.make(items,vault:v,width:isVertical ? r:long,height:isVertical ? long:r,seconds:s,title:t,motion:m,transition:tr)
                        if let a{do{let result=try await MovieSoundtrack.add(video:video,audio:a,volume:vol);try? FileManager.default.removeItem(at:video);return result}catch{try? FileManager.default.removeItem(at:video);throw error}}
                        return video
                    }.value;notice="Đã xuất video."
                }
                catch{notice=error.localizedDescription}
                working=false
            }}.disabled(working || shots.isEmpty)
            if working{ProgressView("Đang mã hóa video…")}
            if let output{ShareLink(item:output){Label("Lưu / Chia sẻ MP4",systemImage:"square.and.arrow.up")}}
            Text(notice).font(.caption)
        }.navigationTitle("Memory Cinema")
        .fileImporter(isPresented:$chooseAudio,allowedContentTypes:[.audio]){result in
            do{let url=try result.get(),access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}};let target=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+"-"+url.lastPathComponent);try FileManager.default.copyItem(at:url,to:target);audio=target}catch{notice=error.localizedDescription}
        }
    }
}
