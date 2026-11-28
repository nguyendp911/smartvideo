import SwiftUI
import Vision
import UIKit
import CoreImage

struct EditingFeatures:Codable,Equatable{
    let brightness:Double
    let contrast:Double
    let dark:Double
    let bright:Double
    let saturation:Double
    let edge:Double
    let aspect:Double
    var vector:[Double]{[1,brightness,contrast,dark,bright,saturation,edge,min(2,aspect)/2]}
    static func analyze(_ cg:CGImage)->Self?{
        let n=48
        var bytes=[UInt8](repeating:0,count:n*n*4)
        let ok=bytes.withUnsafeMutableBytes{p->Bool in
            guard let c=CGContext(data:p.baseAddress,width:n,height:n,bitsPerComponent:8,bytesPerRow:n*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return false}
            c.draw(cg,in:CGRect(x:0,y:0,width:n,height:n));return true
        }
        guard ok else{return nil}
        var l=[Double](),sat=0.0
        for i in stride(from:0,to:bytes.count,by:4){
            let r=Double(bytes[i])/255,g=Double(bytes[i+1])/255,b=Double(bytes[i+2])/255
            l.append(0.2126*r+0.7152*g+0.0722*b);sat+=max(r,max(g,b))-min(r,min(g,b))
        }
        let count=Double(l.count),avg=l.reduce(0,+)/count
        let contrast=sqrt(l.reduce(0.0){$0+pow($1-avg,2)}/count)
        var edge=0.0
        for y in 1..<n{for x in 1..<n{let i=y*n+x;edge+=abs(l[i]-l[i-1])+abs(l[i]-l[i-n])}}
        return Self(brightness:avg,contrast:contrast,dark:Double(l.filter{$0<0.12}.count)/count,bright:Double(l.filter{$0>0.92}.count)/count,saturation:sat/count,edge:edge/count,aspect:Double(cg.width)/Double(max(1,cg.height)))
    }
    func baseline()->CreativeRecipe{
        var r=CreativeRecipe()
        r.exposure=max(-0.65,min(0.85,log2(0.47/max(0.10,brightness))*0.52))
        r.highlights = -min(0.65,bright*1.8)
        r.shadows=min(0.45,dark*0.85)
        r.contrast=max(0.92,min(1.18,1+(0.19-contrast)*0.6))
        r.saturation=max(0.93,min(1.12,1+(0.20-saturation)*0.2))
        return r
    }
}
enum LearnedEditParameter:String,CaseIterable,Codable,Identifiable{
    case exposure,contrast,saturation,warmth,highlights,shadows,tint,vibrance,sharpness,noise,vignette
    var id:String{rawValue}
    var title:String{switch self{
    case .exposure:return "Phơi sáng";case .contrast:return "Tương phản";case .saturation:return "Bão hòa";case .warmth:return "Nhiệt độ";case .highlights:return "Vùng sáng";case .shadows:return "Vùng tối";case .tint:return "Tint";case .vibrance:return "Vibrance";case .sharpness:return "Độ nét";case .noise:return "Khử nhiễu";case .vignette:return "Tối viền"
    }}
    var range:ClosedRange<Double>{switch self{
    case .exposure:return -2...2;case .contrast:return 0.6...1.5;case .saturation:return 0...2;case .warmth,.tint,.vibrance:return -1...1;case .highlights:return -1...0;case .shadows:return -0.5...1;case .sharpness,.noise:return 0...1;case .vignette:return 0...2
    }}
    func value(_ r:CreativeRecipe)->Double{switch self{
    case .exposure:return r.exposure;case .contrast:return r.contrast;case .saturation:return r.saturation;case .warmth:return r.warmth;case .highlights:return r.highlights ?? 0;case .shadows:return r.shadows ?? 0;case .tint:return r.tint ?? 0;case .vibrance:return r.vibrance ?? 0;case .sharpness:return r.sharpness ?? 0;case .noise:return r.noise ?? 0;case .vignette:return r.vignette ?? 0
    }}
    func set(_ v:Double,_ r:inout CreativeRecipe){
        let v=max(range.lowerBound,min(range.upperBound,v))
        switch self{
        case .exposure:r.exposure=v;case .contrast:r.contrast=v;case .saturation:r.saturation=v;case .warmth:r.warmth=v;case .highlights:r.highlights=v;case .shadows:r.shadows=v;case .tint:r.tint=v;case .vibrance:r.vibrance=v;case .sharpness:r.sharpness=v;case .noise:r.noise=v;case .vignette:r.vignette=v
        }
    }
}
struct EditSkillRegressor{
    let weights:[Double]
    let heldOutError:Double
    let baselineError:Double
    func predict(_ f:EditingFeatures,_ parameter:LearnedEditParameter)->Double{
        parameter.value(f.baseline())+zip(weights,f.vector).reduce(0.0){$0+$1.0*$1.1}
    }
    static func fit(_ examples:[(EditingFeatures,Double)],parameter:LearnedEditParameter)->[Double]{
        let n=Double(max(1,examples.count))
        var w=Array(repeating:0.0,count:8)
        for _ in 0..<100{
            var gradient=Array(repeating:0.0,count:8)
            for (f,target) in examples{
                let x=f.vector,base=parameter.value(f.baseline())
                let error=base+zip(w,x).reduce(0.0){$0+$1.0*$1.1}-target
                for i in w.indices{gradient[i]+=error*x[i]/n}
            }
            for i in w.indices{w[i]-=0.17*(gradient[i]+(i==0 ? 0.015:0.07)*w[i])}
        }
        return w
    }
    static func validated(_ examples:[(EditingFeatures,Double)],parameter:LearnedEditParameter)->Self?{
        guard examples.count>=5 else{return nil}
        let limited=Array(examples.prefix(24))
        var base=0.0,error=0.0
        // Each sample belongs to a distinct photo, not an edit event.
        for i in limited.indices{
            let training=limited.enumerated().filter{$0.offset != i}.map(\.element)
            let w=fit(training,parameter:parameter),f=limited[i].0,target=limited[i].1
            let b=parameter.value(f.baseline())
            base+=abs(b-target);error+=abs(b+zip(w,f.vector).reduce(0.0){$0+$1.0*$1.1}-target)
        }
        guard base>0.00001,error<base*0.95 else{return nil}
        return Self(weights:fit(limited,parameter:parameter),heldOutError:error/Double(limited.count),baselineError:base/Double(limited.count))
    }
}
struct WorkflowPlan{
    let recipe:CreativeRecipe
    let learned:[LearnedEditParameter]
    let examples:Int
    let regions:[TasteRegion]
    let scene:TasteScene
    static func make(context:TasteContext,profile:TasteProfile,source:String,existing:CreativeRecipe)->Self?{
        guard let f=context.features else{return nil}
        let samples=profile.samples.filter{$0.context.scene==context.scene && $0.context.features != nil}.sorted{abs($0.context.brightness-context.brightness)<abs($1.context.brightness-context.brightness)}
        let taste=profile.suggest(context)
        // Use the same preset family for training; don't confuse a LUT change with exposure correction.
        let similar=samples.filter{$0.global.premiumID==taste?.global.premiumID && $0.global.film==taste?.global.film}
        var r=taste?.applying(to:existing,source:source,verified:[]) ?? f.baseline()
        r.crop=existing.crop;r.compositionAnchor=existing.compositionAnchor;r.rotation=existing.rotation;r.mirror=existing.mirror;r.lighting=existing.lighting;r.masking=existing.masking
        var learned:[LearnedEditParameter]=[]
        for parameter in LearnedEditParameter.allCases{
            let examples=similar.compactMap{s in s.context.features.map{($0,parameter.value(s.global))}}
            if let model=EditSkillRegressor.validated(examples,parameter:parameter){
                parameter.set(model.predict(f,parameter),&r);learned.append(parameter)
            }
        }
        return Self(recipe:r,learned:learned,examples:similar.count,regions:taste?.regions ?? [],scene:context.scene)
    }
}
struct AdaptiveWorkflowPanel:View{
    let url:URL
    @Binding var recipe:CreativeRecipe
    let scene:TasteScene
    @ObservedObject var taste:PhotoTasteStore
    @ObservedObject private var skill=MaskSkillStore.shared
    @State private var plan:WorkflowPlan?
    @State private var previous:CreativeRecipe?
    @State private var busy=false
    @State private var issue=""
    @State private var useCrop=false
    @State private var useLighting=false
    @State private var useMasks=false
    @State private var regions:[TasteRegion]=[]
    @State private var candidateCrop:String?
    @State private var candidateAnchor:CompositionAnchor?
    @State private var candidateLight:LightMockupRecipe?
    @State private var token=UUID()
    var body:some View{
        VStack(alignment:.leading,spacing:9){
            Label("Adaptive AI Core",systemImage:"brain").font(.headline)
            Text("Học kỹ thuật chỉnh sửa từ dữ liệu ảnh và kết quả đã xác nhận. Không gửi ảnh lên máy chủ.").font(.caption)
            Button("Phân tích quy trình hậu kỳ",systemImage:"wand.and.stars"){analyze()}.disabled(busy)
            if busy{ProgressView()}
            if let plan{
                Text(plan.scene.rawValue+" · \(plan.examples) ảnh tương đồng").font(.caption).foregroundStyle(gold)
                Text(plan.learned.isEmpty ? "Chưa có bộ hồi quy vượt kiểm tra; dùng gợi ý cơ sở / gu đã lưu.":"Kỹ năng đã qua kiểm tra: "+plan.learned.map(\.title).joined(separator:", ")).font(.caption)
                if let crop=candidateCrop{Toggle("Đề xuất tỷ lệ cắt "+crop,isOn:$useCrop)}
                if candidateLight != nil{Toggle("Dùng công thức ánh sáng đã học",isOn:$useLighting)}
                if !regions.isEmpty{Toggle("Tạo lại mặt nạ AI: "+regions.map{$0.kind.rawValue}.joined(separator:", "),isOn:$useMasks)}
                Button("Áp dụng quy trình"){apply(plan)}.buttonStyle(.borderedProminent)
            }
            if let previous{Button("Hoàn tác đề xuất AI"){recipe=previous;self.previous=nil}}
            if !issue.isEmpty{Text(issue).font(.caption).foregroundStyle(.secondary)}
            Text("Mô hình hồi quy từng thông số chỉ dùng khi sai số tuyệt đối trên ảnh giữ lại giảm ít nhất 5%. Đây là mức độ khớp với chỉnh sửa của bạn, không phải điểm chất lượng nghệ thuật.").font(.caption2).foregroundStyle(.secondary)
        }.onChange(of:url){_,_ in clear()}.onChange(of:scene){_,_ in clear()}.onChange(of:taste.generation){_,_ in clear()}
    }
    private func clear(){token=UUID();plan=nil;previous=nil;busy=false;regions=[];candidateCrop=nil;candidateAnchor=nil;candidateLight=nil;useCrop=false;useLighting=false;useMasks=false;issue=""}
    private func analyze(){
        clear();busy=true
        let id=token,u=url,s=scene,p=taste.enabled ? taste.profile:TasteProfile(),r=recipe
        Task{
            let result=await Task.detached(priority:.userInitiated){()->(WorkflowPlan?,[TasteRegion],String?,LightMockupRecipe?,CompositionAnchor?) in
                guard let c=TasteContext.analyze(u,override:s),let plan=WorkflowPlan.make(context:c,profile:p,source:SemanticMaskEngine.sourceKey(u),existing:r) else{return (nil,[],nil,nil,nil)}
                let near=Array(p.samples.filter{$0.context.scene==c.scene}.sorted{abs($0.context.brightness-c.brightness)<abs($1.context.brightness-c.brightness)}.prefix(12))
                let crop=near.compactMap(\.compositionCrop)
                let counts=Dictionary(grouping:crop,by:{$0})
                let winner=counts.values.max{$0.count<$1.count}
                let suggestion=winner.flatMap{$0.count>=3 && $0.count*2>near.count ? $0.first:nil}
                let lights=near.compactMap(\.lightStyle)
                let lightGroups=Dictionary(grouping:lights,by:{($0.textureID ?? "")+"|"+$0.blend.rawValue})
                let best=lightGroups.values.max{$0.count<$1.count}
                let light=best.flatMap{$0.count>=3 && $0.count*2>near.count ? $0.first:nil}
                let verified=p.suggest(c)?.verifiedRegions(url:u) ?? []
                let anchor=suggestion.flatMap{crop in (r.rotation ?? 0)==0 && r.mirror != true ? CompositionEngine.suggest(url:u,crop:crop,samples:near):nil}
                return (plan,verified,suggestion,light,anchor)
            }.value
            guard id==token else{return}
            busy=false;plan=result.0;regions=result.1;candidateCrop=result.2;candidateLight=result.3;candidateAnchor=result.4
            if plan==nil{issue="Không đọc được đặc trưng ảnh."}
        }
    }
    private func apply(_ plan:WorkflowPlan){
        previous=recipe;var next=plan.recipe
        if useCrop,let candidateCrop{next.crop=candidateCrop;next.compositionAnchor=candidateAnchor}
        if useLighting,let candidateLight{next.lighting=candidateLight}
        if useMasks{
            let key=SemanticMaskEngine.sourceKey(url)
            var docs=next.masking ?? [],doc=docs.first(where:{$0.source==key}) ?? PhotoMaskDocument(source:key)
            for region in regions where !doc.layers.contains(where:{$0.kind==region.kind}){
                var layer=PhotoMaskLayer(name:"AI · "+region.kind.rawValue,kind:region.kind);layer.grade=region.grade;layer.strength=region.strength;layer.feather=region.feather;layer.learnedCorrection=skill.model(region.kind);doc.layers.append(layer)
            }
            if !doc.layers.isEmpty{docs.removeAll{$0.source==key};docs.append(doc);next.masking=docs}
        }
        recipe=next;self.plan=nil;issue="Đã áp dụng. Kiểm tra và tinh chỉnh trước khi lưu."
    }
}
