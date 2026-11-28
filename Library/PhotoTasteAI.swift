import SwiftUI
import Vision
import UIKit
import CoreImage

enum TasteScene:String,CaseIterable,Codable,Identifiable{
    case auto="Tự nhận diện",beach="Biển & Resort",travel="Du lịch & kiến trúc",mountain="Núi & thiên nhiên",portrait="Chân dung",night="Phố đêm",sunset="Hoàng hôn",food="Ẩm thực & Café",other="Khác"
    var id:String{rawValue}
    static func classify(_ labels:[String])->Self{
        let joined=labels.joined(separator:" ").lowercased()
        let rules:[(Self,[String])]=[
            (.beach,["beach","coast","seashore","ocean","seaside","tropical beach","surf"]),
            (.sunset,["sunset","sunrise","dusk","twilight"]),
            (.food,["food","meal","cuisine","coffee","dessert","dish","restaurant"]),
            (.night,["night","neon","nighttime"]),
            (.portrait,["portrait","selfie","human_face","person","people"]),
            (.mountain,["mountain","forest","woodland","waterfall","valley","hill","landscape","nature"]),
            (.travel,["architecture","building","street","temple","city","monument","urban","village"])
        ]
        for (scene,terms) in rules{if terms.contains(where:{joined.contains($0)}){return scene}}
        return .other
    }
}
struct TasteContext:Codable,Equatable{
    let scene:TasteScene
    let brightness:Double
    var features:EditingFeatures?=nil
    static func analyze(_ url:URL,override:TasteScene)->Self?{
        guard let bytes=try? Data(contentsOf:url,options:.mappedIfSafe),let image=PhotoEngine.thumb(bytes,limit:640) else{return nil}
        var scene=override
        if scene == .auto{
            let request=VNClassifyImageRequest(),handler=VNImageRequestHandler(cgImage:image,options:[:])
            do{try handler.perform([request]);scene=TasteScene.classify((request.results ?? []).filter{$0.confidence>=0.12}.prefix(10).map(\.identifier))}
            catch{scene = .other}
        }
        var pixels=[UInt8](repeating:0,count:48*48)
        let ok=pixels.withUnsafeMutableBytes{p->Bool in
            guard let ctx=CGContext(data:p.baseAddress,width:48,height:48,bitsPerComponent:8,bytesPerRow:48,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else{return false}
            ctx.draw(image,in:CGRect(x:0,y:0,width:48,height:48));return true
        }
        guard ok else{return nil}
        return Self(scene:scene,brightness:pixels.reduce(0.0){$0+Double($1)}/Double(pixels.count)/255,features:EditingFeatures.analyze(image))
    }
}
struct TasteRegion:Codable,Equatable{
    let kind:PhotoMaskKind
    let grade:LocalGrade
    let strength:Double
    let feather:Double
}
struct TasteSample:Codable,Equatable,Identifiable{
    var id:UUID{photo}
    let photo:UUID
    let date:Date
    let context:TasteContext
    let global:CreativeRecipe
    let regions:[TasteRegion]
    var compositionCrop:String?=nil
    var compositionFeedback:CompositionFeedback?=nil
    var lightStyle:LightMockupRecipe?=nil
    init(photo:UUID,date:Date=Date(),context:TasteContext,recipe:CreativeRecipe,source:String){
        self.photo=photo;self.date=date;self.context=context
        var clean=recipe
        clean.masking=nil;clean.lighting=nil;clean.crop="Gốc";clean.compositionAnchor=nil;clean.rotation=nil;clean.mirror=nil
        global=clean
        compositionCrop=recipe.crop
        if var light=recipe.lighting,light.textureID != nil,light.sceneID==nil,light.customScene==nil,light.customTexture==nil{light.x=0;light.y=0;light.angle=0;light.mirror=false;light.customName=nil;light.matteCorrection=nil;lightStyle=light}
        // Never retain replacement images, brush paths, object coordinates or source paths.
        let layers=recipe.masking?.first(where:{$0.source==source})?.layers ?? []
        regions=PhotoMaskKind.learnable.compactMap{kind in
            guard let layer=layers.last(where:{$0.kind==kind && $0.enabled && !$0.inverted && $0.replacement==nil && $0.strength>0}) else{return nil}
            return TasteRegion(kind:kind,grade:layer.grade,strength:layer.strength,feather:layer.feather)
        }
    }
    func sameEdit(as other:Self)->Bool{photo==other.photo && context==other.context && global==other.global && regions==other.regions && compositionCrop==other.compositionCrop && compositionFeedback==other.compositionFeedback && lightStyle==other.lightStyle}
}
struct TasteSuggestion{
    let context:TasteContext
    let count:Int
    let global:CreativeRecipe
    let regions:[TasteRegion]
    func applying(to original:CreativeRecipe,source:String,verified:[TasteRegion])->CreativeRecipe{
        var result=global
        result.crop=original.crop;result.compositionAnchor=original.compositionAnchor;result.rotation=original.rotation;result.mirror=original.mirror;result.lighting=original.lighting
        result.masking=original.masking
        var docs=result.masking ?? []
        var doc=docs.first(where:{$0.source==source}) ?? PhotoMaskDocument(source:source)
        for region in verified where !doc.layers.contains(where:{$0.kind==region.kind}){
            var layer=PhotoMaskLayer(name:"Gu AI · "+region.kind.rawValue,kind:region.kind)
            layer.grade=region.grade;layer.strength=region.strength;layer.feather=region.feather
            doc.layers.append(layer)
        }
        if !doc.layers.isEmpty{docs.removeAll{$0.source==source};docs.append(doc);result.masking=docs}
        return result
    }
    func verifiedRegions(url:URL)->[TasteRegion]{
        guard let image=CIImage(contentsOf:url,options:[.applyOrientationProperty:true]) else{return []}
        let key=SemanticMaskEngine.sourceKey(url)
        return regions.filter{region in
            guard region.kind != .sky || SemanticMaskEngine.skyAvailable else{return false}
            let layer=PhotoMaskLayer(name:region.kind.rawValue,kind:region.kind)
            guard let mask=try? SemanticMaskEngine.mask(image,layer:layer,key:key) else{return false}
            let average=mask.applyingFilter("CIAreaAverage",parameters:[kCIInputExtentKey:CIVector(cgRect:mask.extent)]).cropped(to:CGRect(x:0,y:0,width:1,height:1))
            var bytes=[UInt8](repeating:0,count:4)
            bytes.withUnsafeMutableBytes{p in SemanticMaskEngine.context.render(average,toBitmap:p.baseAddress!,rowBytes:4,bounds:CGRect(x:0,y:0,width:1,height:1),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))}
            return bytes[0]>8
        }
    }
}
struct TasteProfile:Codable,Equatable{
    var samples:[TasteSample]=[]
    mutating func record(_ sample:TasteSample){
        if samples.contains(where:{$0.sameEdit(as:sample)}){return}
        samples.removeAll{$0.photo==sample.photo}
        samples.append(sample)
        samples=Array(samples.sorted{$0.date>$1.date}.prefix(300))
    }
    func suggest(_ context:TasteContext)->TasteSuggestion?{
        func distance(_ s:TasteSample)->Double{
            let brightness=abs(s.context.brightness-context.brightness)
            guard let a=s.context.features,let b=context.features else{return brightness}
            return brightness+0.55*abs(a.contrast-b.contrast)+0.35*abs(a.dark-b.dark)+0.35*abs(a.bright-b.bright)+0.25*abs(a.saturation-b.saturation)
        }
        let candidates=samples.filter{$0.context.scene==context.scene}.sorted{distance($0)<distance($1)}
        let nearest=Array(candidates.prefix(12))
        guard !nearest.isEmpty else{return nil}
        func weight(_ s:TasteSample)->Double{1/(0.12+distance(s))}
        // Vote for a coherent preset + film combination; don't average incompatible LUTs.
        func style(_ s:TasteSample)->String{(s.global.premiumID ?? "")+"|"+(s.global.film ?? "Gốc")}
        let groups=Dictionary(grouping:nearest,by:style)
        guard let group=groups.values.max(by:{a,b in a.reduce(0.0){$0+weight($1)}<b.reduce(0.0){$0+weight($1)}}),let anchor=group.first else{return nil}
        func mean(_ value:(TasteSample)->Double)->Double{group.reduce(0.0){$0+value($1)*weight($1)}/group.reduce(0.0){$0+weight($1)}}
        var r=anchor.global
        r.exposure=mean{$0.global.exposure};r.contrast=mean{$0.global.contrast};r.saturation=mean{$0.global.saturation};r.warmth=mean{$0.global.warmth}
        r.highlights=mean{$0.global.highlights ?? 0};r.shadows=mean{$0.global.shadows ?? 0};r.tint=mean{$0.global.tint ?? 0}
        r.vibrance=mean{$0.global.vibrance ?? 0};r.sharpness=mean{$0.global.sharpness ?? 0};r.noise=mean{$0.global.noise ?? 0};r.vignette=mean{$0.global.vignette ?? 0}
        r.premiumStrength=mean{$0.global.premiumStrength ?? 0.8}
        // A region must have at least two examples; use the closest example's local grade.
        let regions:[TasteRegion]=PhotoMaskKind.learnable.compactMap{kind in
            let values=group.compactMap{$0.regions.first(where:{$0.kind==kind})}
            guard values.count>=2 else{return nil}
            return values.first
        }
        return TasteSuggestion(context:context,count:group.count,global:r,regions:regions)
    }
}
@MainActor final class PhotoTasteStore:ObservableObject{
    static let shared=PhotoTasteStore()
    @Published private(set) var profile=TasteProfile()
    @Published var enabled:Bool{didSet{UserDefaults.standard.set(enabled,forKey:"photo.taste.enabled");generation=UUID()}}
    @Published private(set) var issue=""
    private(set) var generation=UUID()
    private let file:URL
    init(file:URL=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("VieLensTaste/profile.json")){
        self.file=file
        enabled=UserDefaults.standard.object(forKey:"photo.taste.enabled") as? Bool ?? true
        if FileManager.default.fileExists(atPath:file.path){do{profile=try JSONDecoder().decode(TasteProfile.self,from:Data(contentsOf:file))}catch{issue="Không đọc được hồ sơ gu màu. Có thể đặt lại hồ sơ."}}
    }
    func record(_ sample:TasteSample,token:UUID){
        guard enabled,token==generation,issue.isEmpty else{return}
        var next=profile;next.record(sample)
        guard next != profile else{return}
        do{try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true);try JSONEncoder().encode(next).write(to:file,options:[.atomic,.completeFileProtection]);profile=next}
        catch{issue=error.localizedDescription}
    }
    func reset(){
        generation=UUID()
        do{if FileManager.default.fileExists(atPath:file.path){try FileManager.default.removeItem(at:file)};profile=TasteProfile();issue=""}
        catch{issue=error.localizedDescription}
    }
}
struct PhotoTastePanel:View{
    let url:URL
    @Binding var recipe:CreativeRecipe
    @Binding var scene:TasteScene
    @ObservedObject var store:PhotoTasteStore
    @State private var candidate:TasteSuggestion?
    @State private var verified:[TasteRegion]=[]
    @State private var local=false
    @State private var busy=false
    @State private var notice=""
    @State private var reset=false
    @State private var requestID=UUID()
    var body:some View{
        VStack(alignment:.leading,spacing:10){
            Toggle("Học từ chỉnh sửa đã lưu",isOn:$store.enabled)
            Text("\(store.profile.samples.count) ảnh đã học · lưu trên iPhone").font(.caption).foregroundStyle(.secondary)
            Picker("Loại ảnh",selection:$scene){ForEach(TasteScene.allCases){Text($0.rawValue).tag($0)}}
            Button("Phân tích & đề xuất gu của tôi",systemImage:"sparkles"){suggest()}.disabled(busy || !store.enabled)
            if busy{ProgressView()}
            if let candidate{
                Text(candidate.context.scene.rawValue+" · \(candidate.count) ảnh tương đồng").font(.caption.weight(.semibold)).foregroundStyle(gold)
                Text(candidate.global.premiumID.flatMap{PremiumPresets.find($0)?.name} ?? "Thông số màu cá nhân").font(.headline)
                if !verified.isEmpty{Toggle("Tạo lại vùng AI tương ứng",isOn:$local);Text(verified.map{$0.kind.rawValue}.joined(separator:", ")).font(.caption)}
                Button("Áp dụng đề xuất"){var next=candidate.applying(to:recipe,source:SemanticMaskEngine.sourceKey(url),verified:local ? verified:[]);let key=SemanticMaskEngine.sourceKey(url);if var docs=next.masking,let i=docs.firstIndex(where:{$0.source==key}){for j in docs[i].layers.indices where docs[i].layers[j].name.hasPrefix("Gu AI · ") && docs[i].layers[j].learnedCorrection==nil{let kind=docs[i].layers[j].kind;docs[i].layers[j].learnedCorrection=MaskSkillStore.shared.model(kind)};next.masking=docs};recipe=next;notice="Đã áp dụng. Bạn vẫn có thể chỉnh sửa trước khi lưu.";self.candidate=nil}.buttonStyle(.borderedProminent).disabled(!store.enabled)
            }
            if !notice.isEmpty{Text(notice).font(.caption)}
            if !store.issue.isEmpty{Text(store.issue).font(.caption).foregroundStyle(.orange)}
            Button("Xóa toàn bộ gu đã học",role:.destructive){reset=true}.font(.caption)
            Text("Học công thức màu và thông số vùng, không huấn luyện lại model, không lưu ảnh vào hồ sơ. Chỉ gợi ý khi có ảnh cùng loại. Không tự áp dụng.").font(.caption2).foregroundStyle(.secondary)
        }.confirmationDialog("Xóa hồ sơ học gu màu?",isPresented:$reset){Button("Xóa dữ liệu học",role:.destructive){store.reset();invalidate()}}
        .onChange(of:url){_,_ in invalidate()}.onChange(of:scene){_,_ in invalidate()}.onChange(of:store.generation){_,_ in invalidate()}
    }
    private func invalidate(){requestID=UUID();candidate=nil;verified=[];local=false;busy=false;notice=""}
    private func suggest(){
        invalidate();busy=true
        let token=requestID,profile=store.profile,u=url,chosen=scene
        Task{
            let result=await Task.detached(priority:.userInitiated){()->(TasteContext?,TasteSuggestion?,[TasteRegion]) in
                guard let context=TasteContext.analyze(u,override:chosen) else{return (nil,nil,[])}
                let result=profile.suggest(context)
                return (context,result,result?.verifiedRegions(url:u) ?? [])
            }.value
            guard requestID==token else{return}
            busy=false;candidate=result.1;verified=result.2
            notice=result.0==nil ? "Không phân tích được ảnh.":result.1==nil ? "Chưa có ảnh cùng loại đã học. Hãy chỉnh và lưu vài ảnh trước.":"Chọn áp dụng nếu phù hợp; vùng AI cần kiểm tra lại mép chọn."
        }
    }
}
