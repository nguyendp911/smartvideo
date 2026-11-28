import SwiftUI
import CoreImage
import CryptoKit

// Learn a small residual classifier on top of the frozen semantic model.
// No source images or stroke coordinates are retained by the training store.
struct MaskTrainingPoint:Codable,Equatable{
    let features:[Double]
    let positive:Bool
    var prior:Double{features.first.map{$0.isFinite ? max(0,min(1,$0)):0.5} ?? 0.5}
}
struct MaskTrainingExample:Codable,Equatable{
    let key:String
    let kind:PhotoMaskKind
    let points:[MaskTrainingPoint]
}
struct MaskCorrectionModel:Codable,Equatable{
    let weights:[Double]
    let imageCount:Int
    let baselineLoss:Double
    let validationLoss:Double
    static let dimension=12
    static func clamp(_ x:Double,_ low:Double,_ high:Double)->Double{max(low,min(high,x))}
    static func vector(_ f:[Double])->[Double]{
        guard f.count==dimension-1 else{return Array(repeating:0,count:dimension)}
        return [1]+f.map{2*$0-1}
    }
    static func logit(_ p:Double)->Double{let q=clamp(p,0.025,0.975);return log(q/(1-q))}
    static func sigmoid(_ x:Double)->Double{1/(1+exp(-clamp(x,-20,20)))}
    func probability(_ point:MaskTrainingPoint)->Double{
        guard weights.count==Self.dimension,weights.allSatisfy(\.isFinite),point.features.count==Self.dimension-1 else{return point.prior}
        let delta=zip(weights,Self.vector(point.features)).reduce(0.0){$0+$1.0*$1.1}
        // Leave confident pixels mostly intact; avoid unconstrained recoloring of the whole mask.
        let gate=0.25+0.75*(1-abs(2*point.prior-1))
        let prior=Self.logit(point.prior)
        return Self.clamp(point.prior+Self.sigmoid(prior+Self.clamp(delta,-2.5,2.5)*gate)-Self.sigmoid(prior),0,1)
    }
    static func fit(_ examples:[MaskTrainingExample])->Self?{
        let points=examples.flatMap(\.points).filter{$0.features.count==dimension-1 && $0.features.allSatisfy(\.isFinite)}
        guard points.count>=12,points.contains(where:{$0.positive}),points.contains(where:{!$0.positive}) else{return nil}
        var w=Array(repeating:0.0,count:dimension)
        let positives=Double(points.filter(\.positive).count),negatives=Double(points.count)-positives
        for _ in 0..<85{
            var g=Array(repeating:0.0,count:dimension)
            for p in points{
                let x=vector(p.features),prediction=sigmoid(logit(p.prior)+zip(w,x).reduce(0.0){$0+$1.0*$1.1})
                let error=(prediction-(p.positive ? 1:0))/(p.positive ? 2*positives:2*negatives)
                for i in w.indices{g[i]+=error*x[i]}
            }
            for i in w.indices{w[i]=clamp(w[i]-0.35*(g[i]+0.025*w[i]),-3,3)}
        }
        return Self(weights:w,imageCount:examples.count,baselineLoss:0,validationLoss:0)
    }
    static func loss(_ points:[MaskTrainingPoint],model:Self?)->Double{
        let valid=points.filter{$0.features.count==dimension-1 && $0.features.allSatisfy(\.isFinite)}
        let groups=[valid.filter(\.positive),valid.filter{!$0.positive}].filter{!$0.isEmpty}
        guard !groups.isEmpty else{return 0}
        return groups.reduce(0.0){total,group in
            total+group.reduce(0.0){sum,p in
                let q=clamp(model?.probability(p) ?? p.prior,0.025,0.975)
                return sum-(p.positive ? log(q):log(1-q))
            }/Double(group.count)
        }/Double(groups.count)
    }
    static func validated(_ examples:[MaskTrainingExample])->Self?{
        // Hold out complete images, not random pixels from the same image.
        guard examples.count>=3,let final=fit(examples) else{return nil}
        let folds=Array(examples.prefix(6))
        var base=0.0,learned=0.0,count=0,regressions=0
        for held in folds{
            guard let model=fit(examples.filter{$0.key != held.key}) else{continue}
            let b=loss(held.points,model:nil),l=loss(held.points,model:model)
            base+=b;learned+=l;count+=1
            if l>b*1.10{regressions+=1}
        }
        guard count>=3,regressions==0,learned<base*0.97 else{return nil}
        return Self(weights:final.weights,imageCount:examples.count,baselineLoss:base/Double(count),validationLoss:learned/Double(count))
    }
}
enum MaskCorrectionPixels{
    static let side=128
    struct Grid{
        let width:Int;let height:Int;let rgb:[UInt8];let mask:[UInt8]
        func point(_ i:Int,positive:Bool)->MaskTrainingPoint{
            let x=i%width,y=i/width,k=i*4
            let r=Double(rgb[k])/255,g=Double(rgb[k+1])/255,b=Double(rgb[k+2])/255
            let lum=(r+g+b)/3,sat=max(r,max(g,b))-min(r,min(g,b))
            let left=(y*width+max(0,x-1))*4,right=(y*width+min(width-1,x+1))*4
            let down=(max(0,y-1)*width+x)*4,up=(min(height-1,y+1)*width+x)*4
            let edge=Double(abs(Int(rgb[left])-Int(rgb[right]))+abs(Int(rgb[down])-Int(rgb[up])))/510
            let prior=Double(mask[k])/255
            let near=(Double(mask[left])+Double(mask[right])+Double(mask[down])+Double(mask[up]))/1020
            return MaskTrainingPoint(features:[prior,r,g,b,lum,sat,(b-r+1)/2,(g-r+1)/2,Double(y)/Double(max(1,height-1)),edge,near],positive:positive)
        }
    }
    static func grid(image:CIImage,base:CIImage,limit:Int=side)->Grid{
        let factor=Double(limit)/Double(max(image.extent.width,image.extent.height))
        let w=max(1,Int(Double(image.extent.width)*factor)),h=max(1,Int(Double(image.extent.height)*factor))
        let rect=CGRect(x:0,y:0,width:w,height:h)
        let space=CGColorSpace(name:CGColorSpace.sRGB)!
        func render(_ input:CIImage,mask:Bool=false)->[UInt8]{
            var bytes=Array(repeating:UInt8(0),count:w*h*4)
            bytes.withUnsafeMutableBytes{p in SemanticMaskEngine.context.render(SemanticMaskEngine.fit(input,to:rect),toBitmap:p.baseAddress!,rowBytes:w*4,bounds:rect,format:.RGBA8,colorSpace:mask ? nil:space)}
            return bytes
        }
        return Grid(width:w,height:h,rgb:render(image),mask:render(base,mask:true))
    }
    static func labels(width:Int,height:Int,strokes:[MaskStroke])->[Int8]{
        var out=Array(repeating:Int8(-1),count:width*height)
        for stroke in strokes{
            let radius=max(0.7,Double(min(width,height))*stroke.size*0.5)
            func dab(_ x:Double,_ y:Double){
                let loX=max(0,Int(floor(x-radius))),hiX=min(width-1,Int(ceil(x+radius)))
                let loY=max(0,Int(floor(y-radius))),hiY=min(height-1,Int(ceil(y+radius)))
                guard loX<=hiX,loY<=hiY else{return}
                for j in loY...hiY{for i in loX...hiX where pow(Double(i)-x,2)+pow(Double(j)-y,2)<=radius*radius{out[j*width+i]=stroke.subtract ? 0:1}}
            }
            var previous:CGPoint?
            for p in stroke.points{
                let x=max(0,min(1,p.x))*Double(width-1),y=(1-max(0,min(1,p.y)))*Double(height-1)
                if let previous{
                    let dx=x-previous.x,dy=y-previous.y,steps=max(1,Int(ceil(hypot(dx,dy)/max(0.5,radius*0.6))))
                    for j in 0...steps{let t=Double(j)/Double(steps);dab(previous.x+dx*t,previous.y+dy*t)}
                }else{dab(x,y)}
                previous=CGPoint(x:x,y:y)
            }
        }
        return out
    }
    static func examples(url:URL,document:PhotoMaskDocument)->[MaskTrainingExample]{
        guard let image=CIImage(contentsOf:url,options:[.applyOrientationProperty:true]),image.extent.width>0,image.extent.height>0 else{return []}
        let key=SemanticMaskEngine.sourceKey(url)
        let digest=SHA256.hash(data:Data(key.utf8)).map{String(format:"%02x",$0)}.joined()
        return PhotoMaskKind.learnable.compactMap{kind in
            guard let layer=document.layers.last(where:{$0.kind==kind && $0.enabled && !$0.inverted && !$0.strokes.isEmpty}),
                  let base=try? SemanticMaskEngine.rawSemantic(image,kind:kind,key:key) else{return nil}
            let g=grid(image:image,base:base)
            let labels=labels(width:g.width,height:g.height,strokes:layer.strokes)
            var points:[MaskTrainingPoint]=[]
            for label in [Int8(0),Int8(1)]{
                let indices=labels.indices.filter{labels[$0]==label}
                let stride=max(1,Int(ceil(Double(indices.count)/64)))
                for i in indices.enumerated() where i.offset%stride==0{points.append(g.point(i.element,positive:label==1))}
            }
            guard !points.isEmpty else{return nil}
            return MaskTrainingExample(key:digest,kind:kind,points:points)
        }
    }
    static func refine(image:CIImage,base:CIImage,model:MaskCorrectionModel)->CIImage{
        let g=grid(image:image,base:base,limit:384)
        let w=g.width,h=g.height
        // Preserve original edge detail: use a signed, interpolated residual rather than replacing the high-resolution mask.
        var positive=[Float](repeating:0,count:w*h*4),negative=positive
        for i in 0..<(w*h){
            let point=g.point(i,positive:false),delta=model.probability(point)-point.prior
            for channel in 0..<3{positive[i*4+channel]=Float(max(0,delta));negative[i*4+channel]=Float(max(0,-delta))}
            positive[i*4+3]=1;negative[i*4+3]=1
        }
        func imageFrom(_ pixels:[Float])->CIImage{
            let bytes=pixels.withUnsafeBytes{Data($0)}
            return SemanticMaskEngine.fit(CIImage(bitmapData:bytes,bytesPerRow:w*16,size:CGSize(width:w,height:h),format:.RGBAf,colorSpace:nil),to:base.extent)
        }
        let plus=imageFrom(positive),minus=imageFrom(negative)
        let raised=plus.applyingFilter("CIAdditionCompositing",parameters:[kCIInputBackgroundImageKey:base])
        return minus.applyingFilter("CISubtractBlendMode",parameters:[kCIInputBackgroundImageKey:raised]).cropped(to:base.extent).applyingFilter("CIColorClamp",parameters:["inputMinComponents":CIVector(x:0,y:0,z:0,w:0),"inputMaxComponents":CIVector(x:1,y:1,z:1,w:1)])
    }
}
struct MaskSkillProfile:Codable,Equatable{
    var examples:[MaskTrainingExample]=[]
    var models:[String:MaskCorrectionModel]=[:]
    mutating func ingest(_ incoming:[MaskTrainingExample]){
        for e in incoming{
            examples.removeAll{$0.key==e.key && $0.kind==e.kind}
            examples.insert(e,at:0)
        }
        examples=PhotoMaskKind.learnable.flatMap{kind in Array(examples.filter{$0.kind==kind}.prefix(12))}
        for kind in PhotoMaskKind.learnable{
            models[kind.rawValue]=MaskCorrectionModel.validated(Array(examples.filter{$0.kind==kind}.prefix(12)))
        }
    }
}
@MainActor final class MaskSkillStore:ObservableObject{
    static let shared=MaskSkillStore()
    @Published private(set) var profile=MaskSkillProfile()
    @Published var enabled:Bool{didSet{UserDefaults.standard.set(enabled,forKey:"mask.skill.enabled");generation=UUID()}}
    @Published private(set) var issue=""
    private let file:URL
    private var generation=UUID()
    init(file:URL=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("VieLensMaskSkill/profile.json")){
        self.file=file;enabled=UserDefaults.standard.object(forKey:"mask.skill.enabled") as? Bool ?? true
        if FileManager.default.fileExists(atPath:file.path){do{profile=try JSONDecoder().decode(MaskSkillProfile.self,from:Data(contentsOf:file))}catch{issue=error.localizedDescription}}
    }
    func model(_ kind:PhotoMaskKind)->MaskCorrectionModel?{enabled ? profile.models[kind.rawValue]:nil}
    func learn(url:URL,document:PhotoMaskDocument)async{
        guard enabled,issue.isEmpty else{return}
        let token=generation
        let incoming=await Task.detached(priority:.utility){MaskCorrectionPixels.examples(url:url,document:document)}.value
        guard enabled,token==generation,!incoming.isEmpty else{return}
        // Fit off the main thread; serialize writes against reset/toggle and other training jobs.
        while enabled,token==generation,issue.isEmpty{
            let snapshot=profile
            let next=await Task.detached(priority:.utility){var next=snapshot;next.ingest(incoming);return next}.value
            guard enabled,token==generation,!Task.isCancelled else{return}
            if profile != snapshot{continue}
            do{try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true);try JSONEncoder().encode(next).write(to:file,options:[.atomic,.completeFileProtection]);profile=next}catch{issue=error.localizedDescription}
            return
        }
    }
    func reset(){
        generation=UUID()
        do{if FileManager.default.fileExists(atPath:file.path){try FileManager.default.removeItem(at:file)};profile=MaskSkillProfile();issue=""}catch{issue=error.localizedDescription}
    }
}
