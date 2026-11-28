import SwiftUI
import CoreImage
import UIKit
import Vision
import UniformTypeIdentifiers
import CryptoKit
import ImageIO

enum LightBlendMode:String,Codable,CaseIterable,Identifiable{
    case natural="Ánh sáng & bóng",screen="Ánh sáng",multiply="Bóng đổ",soft="Soft Light"
    var id:String{rawValue}
}
enum LightingScope:String,Codable,CaseIterable,Identifiable{
    case all="Toàn ảnh",subject="Chủ thể",background="Hậu cảnh"
    var id:String{rawValue}
}
struct LightMockupRecipe:Codable,Equatable{
    var textureID:String?=nil
    var sceneID:String?=nil
    var blend:LightBlendMode = .natural
    var opacity=0.45
    var warmth=0.12
    var zoom=1.0
    var x=0.0
    var y=0.0
    var angle=0.0
    var mirror=false
    var sceneZoom=1.0
    var sceneX=0.0
    var sceneY=0.0
    var customTexture:Data?=nil
    var customName:String?=nil
    var customScene:Data?=nil
    var customSceneName:String?=nil
    var scope:LightingScope?=nil
    var edgeFade:Double?=nil
    var sceneBlur:Double?=nil
    var sceneExposure:Double?=nil
    var sceneWarmth:Double?=nil
    var matteFeather:Double?=nil
    var matteInset:Double?=nil
    var foregroundExposure:Double?=nil
    var foregroundWarmth:Double?=nil
}
struct LightAsset:Identifiable{
    let id:String
    let name:String
    let index:Int
}
struct LightingCollectionPackage:Codable{
    let version:Int
    let scene:[String]
    let light:[String]
    func decoded()throws->(Data,Data){
        guard version==1,
              scene.count<=10000,light.count<=10000,
              let a=Data(base64Encoded:scene.joined()),let b=Data(base64Encoded:light.joined()),
              !a.isEmpty,!b.isEmpty,a.count<=20_000_000,b.count<=10_000_000 else{throw CameraError.unreadable}
        func dimensions(_ bytes:Data,_ columns:Int,_ rows:Int)throws{
            guard let source=CGImageSourceCreateWithData(bytes as CFData,nil),
                  let props=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any],
                  let w=props[kCGImagePropertyPixelWidth as String] as? Int,
                  let h=props[kCGImagePropertyPixelHeight as String] as? Int,
                  w>=columns*128,h>=rows*128,w<=8192,h<=8192,w*h<=24_000_000,
                  w%columns==0,h%rows==0 else{throw CameraError.unreadable}
        }
        try dimensions(a,4,4);try dimensions(b,4,2)
        return (a,b)
    }
}
enum LightingPackStore{
    static var root:URL{FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("VieLensLightingPacks",isDirectory:true)}
    static func ids()->[String]{
        ((try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)) ?? [])
            .filter{valid($0.lastPathComponent) && FileManager.default.fileExists(atPath:$0.appendingPathComponent("scenes.jpg").path) && FileManager.default.fileExists(atPath:$0.appendingPathComponent("lights.jpg").path)}
            .map(\.lastPathComponent).sorted()
    }
    private static func valid(_ id:String)->Bool{id.count==64 && id.utf8.allSatisfy{(48...57).contains($0)||(97...102).contains($0)}}
    static func atlas(_ id:String,scene:Bool)->CGImage?{
        guard valid(id),let source=CGImageSourceCreateWithURL(root.appendingPathComponent(id,isDirectory:true).appendingPathComponent(scene ? "scenes.jpg":"lights.jpg") as CFURL,nil) else{return nil}
        return CGImageSourceCreateImageAtIndex(source,0,nil)
    }
    static func install(_ bytes:Data)throws->String{
        guard bytes.count<=45_000_000 else{throw CameraError.unreadable}
        let (a,b)=try JSONDecoder().decode(LightingCollectionPackage.self,from:bytes).decoded()
        var digest=SHA256();digest.update(data:a);digest.update(data:b)
        let id=digest.finalize().map{String(format:"%02x",$0)}.joined()
        if ids().contains(id){return id}
        guard ids().count<12 else{throw CameraError.writeFailed}
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let temp=root.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:temp)}
        try a.write(to:temp.appendingPathComponent("scenes.jpg"),options:[.atomic,.completeFileProtection])
        try b.write(to:temp.appendingPathComponent("lights.jpg"),options:[.atomic,.completeFileProtection])
        let target=root.appendingPathComponent(id,isDirectory:true)
        try FileManager.default.moveItem(at:temp,to:target)
        return id
    }
}
enum LightAssets{
    static let scenes:[LightAsset]=[
        .init(id:"window_morning",name:"Cửa sổ nắng sớm",index:0),
        .init(id:"lace_window",name:"Rèm voan & hoa",index:1),
        .init(id:"golden_lantern",name:"Đèn vàng cổ điển",index:2),
        .init(id:"rainy_night",name:"Cửa kính đêm mưa",index:3),
        .init(id:"venetian_blinds",name:"Rèm chớp",index:4),
        .init(id:"coastal_arch",name:"Vòm cửa biển",index:5),
        .init(id:"mountain_moon_gate",name:"Khung tròn núi xanh",index:6),
        .init(id:"fairy_curtain",name:"Rèm đèn cổ tích",index:7),
        .init(id:"beach_sunset",name:"Biển hoàng hôn",index:8),
        .init(id:"wall_lantern",name:"Đèn tường Indochine",index:9),
        .init(id:"moon_blossom",name:"Ánh trăng & hoa",index:10),
        .init(id:"rainy_cafe",name:"Café ngày mưa",index:11),
        .init(id:"garden_arch",name:"Vòm hoa sân vườn",index:12),
        .init(id:"palm_shadows",name:"Nắng lá cọ",index:13),
        .init(id:"golden_curtain",name:"Rèm ánh vàng",index:14),
        .init(id:"arched_window",name:"Vòm nắng cổ điển",index:15)
    ]
    static let textures:[LightAsset]=[
        .init(id:"window_sun",name:"Nắng xuyên cửa",index:0),
        .init(id:"blinds",name:"Bóng rèm chớp",index:1),
        .init(id:"leaf_sun",name:"Bóng lá ngoài hiên",index:2),
        .init(id:"palm_light",name:"Nắng nhiệt đới",index:3),
        .init(id:"arch_light",name:"Vòm cửa nắng vàng",index:4),
        .init(id:"lantern_glow",name:"Ánh đèn vàng",index:5),
        .init(id:"curtain_glow",name:"Đèn dây xuyên rèm",index:6),
        .init(id:"blue_window",name:"Ánh cửa đêm",index:7)
    ]
    private static let cache=NSCache<NSString,UIImage>()
    static func entries(scene:Bool,pack:String?)->[LightAsset]{
        let list=scene ? scenes:textures
        guard let pack else{return list}
        return list.map{LightAsset(id:"pack:"+pack+":"+$0.id,name:$0.name,index:$0.index)}
    }
    static func image(_ id:String,scene:Bool)->UIImage?{
        let key="\(scene):\(id)" as NSString
        if let cached=cache.object(forKey:key){return cached}
        let list=scene ? scenes:textures
        let components=id.split(separator:":").map(String.init)
        let imported=components.count==3 && components[0]=="pack"
        let assetID=imported ? components[2]:id
        let atlas=imported ? LightingPackStore.atlas(components[1],scene:scene):UIImage(named:scene ? "premium_scene_atlas":"premium_light_atlas")?.cgImage
        guard let item=list.first(where:{$0.id==assetID}),let atlas else{return nil}
        let columns=4,rows=scene ? 4:2
        let w=atlas.width/columns,h=atlas.height/rows,margin=scene ? 3:0
        let r=CGRect(x:(item.index%columns)*w+margin,y:(item.index/columns)*h+margin,width:w-2*margin,height:h-2*margin)
        guard let cg=atlas.cropping(to:r) else{return nil}
        let image=UIImage(cgImage:cg);cache.totalCostLimit=32*1024*1024;cache.countLimit=72;cache.setObject(image,forKey:key,cost:cg.bytesPerRow*cg.height)
        return image
    }
}
enum LightMockupEngine{
    private static let context=CIContext(options:[.cacheIntermediates:false])
    private static func unit(_ x:Double)->Double{max(0,min(1,x))}
    private static func cover(_ source:CIImage,rect:CGRect,zoom:Double,x:Double,y:Double,angle:Double=0,mirror:Bool=false)->CIImage{
        let box=source.extent
        guard box.width>0,box.height>0 else{return source}
        let scale=max(rect.width/box.width,rect.height/box.height)*CGFloat(max(0.5,min(3,zoom)))
        var im=source.transformed(by:CGAffineTransform(translationX:-box.midX,y:-box.midY))
        im=im.transformed(by:CGAffineTransform(scaleX:mirror ? -scale:scale,y:scale))
        im=im.transformed(by:CGAffineTransform(rotationAngle:CGFloat(angle)*CGFloat.pi/180))
        return im.transformed(by:CGAffineTransform(translationX:rect.midX+rect.width*CGFloat(x)*0.5,y:rect.midY+rect.height*CGFloat(y)*0.5))
    }
    private static func mixed(_ foreground:CIImage,_ background:CIImage,amount:Double,rect:CGRect)->CIImage{
        let v=unit(amount)
        let mask=CIImage(color:CIColor(red:v,green:v,blue:v,alpha:1)).cropped(to:rect)
        return foreground.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:background,kCIInputMaskImageKey:mask]).cropped(to:rect)
    }
    // Pan only within the overscan of a cover-fit background. No stretched edge pixels.
    static func sceneRect(source:CGRect,target:CGRect,zoom:Double,x:Double,y:Double)->CGRect{
        let scale=max(target.width/max(1,source.width),target.height/max(1,source.height))*CGFloat(max(1,min(3,zoom)))
        let w=source.width*scale,h=source.height*scale
        let dx=max(0,(w-target.width)/2)*CGFloat(max(-1,min(1,x)))
        let dy=max(0,(h-target.height)/2)*CGFloat(max(-1,min(1,y)))
        return CGRect(x:target.midX-w/2+dx,y:target.midY-h/2+dy,width:w,height:h)
    }
    static func sceneCover(_ source:CIImage,target:CGRect,zoom:Double,x:Double,y:Double)->CIImage{
        let r=sceneRect(source:source.extent,target:target,zoom:zoom,x:x,y:y)
        return SemanticMaskEngine.fit(source,to:r).cropped(to:target)
    }
    static func softTexture(_ image:CIImage,fade:Double)->CIImage{
        let rect=image.extent
        let width=min(rect.width,rect.height)*CGFloat(max(0,min(0.35,fade)))
        guard width>0.5 else{return image}
        func gradient(_ a:CGPoint,_ b:CGPoint)->CIImage{
            CIFilter(name:"CILinearGradient",parameters:["inputPoint0":CIVector(cgPoint:a),"inputPoint1":CIVector(cgPoint:b),"inputColor0":CIColor.black,"inputColor1":CIColor.white])!.outputImage!.cropped(to:rect)
        }
        let edges=[
            gradient(CGPoint(x:rect.minX,y:rect.midY),CGPoint(x:rect.minX+width,y:rect.midY)),
            gradient(CGPoint(x:rect.maxX,y:rect.midY),CGPoint(x:rect.maxX-width,y:rect.midY)),
            gradient(CGPoint(x:rect.midX,y:rect.minY),CGPoint(x:rect.midX,y:rect.minY+width)),
            gradient(CGPoint(x:rect.midX,y:rect.maxY),CGPoint(x:rect.midX,y:rect.maxY-width))
        ]
        let mask=edges.dropFirst().reduce(edges[0]){a,b in a.applyingFilter("CIMultiplyCompositing",parameters:[kCIInputBackgroundImageKey:b]).cropped(to:rect)}
        let clear=CIImage(color:CIColor(red:0,green:0,blue:0,alpha:0)).cropped(to:rect)
        return image.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:clear,kCIInputMaskImageKey:mask]).cropped(to:rect)
    }
    static func foregroundMask(_ image:CIImage,key:String,document:PhotoMaskDocument?,feather:Double,inset:Double)->CIImage?{
        let r=image.extent
        // Reuse the exact user-corrected mask including the learned model, brush strokes and threshold.
        let layer=document?.layers.last(where:{$0.enabled && !$0.inverted && ($0.kind == .subject || $0.kind == .person)})
        var matte:CIImage
        if let layer{
            guard let corrected=try? SemanticMaskEngine.mask(image,layer:layer,key:key) else{return nil}
            matte=corrected
        }else{
            guard let raw=try? SemanticMaskEngine.rawSemantic(image,kind:.subject,key:key) else{return nil}
            matte=SemanticMaskEngine.fit(raw,to:r)
        }
        // Process morphology at bounded resolution to avoid multi-megapixel radius costs.
        let s=min(1,1536/max(r.width,r.height))
        let work=CGRect(x:0,y:0,width:max(1,(r.width*s).rounded()),height:max(1,(r.height*s).rounded()))
        matte=SemanticMaskEngine.fit(matte,to:work)
        let short=min(work.width,work.height)
        let shrink=max(-0.012,min(0.012,inset))*short
        if abs(shrink)>0.1{
            matte=matte.clampedToExtent().applyingFilter(shrink>0 ? "CIMorphologyMinimum":"CIMorphologyMaximum",parameters:[kCIInputRadiusKey:abs(shrink)]).cropped(to:work)
        }
        let softness=max(0,min(0.025,feather))*short
        if softness>0.1{matte=matte.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:softness]).cropped(to:work)}
        return SemanticMaskEngine.fit(matte,to:r)
    }
    private static func tone(_ image:CIImage,exposure:Double,warmth:Double)->CIImage{
        var r=image
        if exposure != 0{r=r.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:exposure])}
        if warmth != 0{r=r.applyingFilter("CITemperatureAndTint",parameters:["inputNeutral":CIVector(x:6500,y:0),"inputTargetNeutral":CIVector(x:6500+warmth*2000,y:0)])}
        return r.cropped(to:image.extent)
    }
    static func apply(_ image:CIImage,original:CIImage,recipe:LightMockupRecipe?,key:String?=nil,document:PhotoMaskDocument?=nil,sourceKey:String?=nil)->CIImage?{
        guard let r=recipe else{return image}
        let rect=image.extent
        var result=image
        let scope=r.scope ?? .all
        let hasScene=r.sceneID != nil || r.customScene != nil
        let hasTexture=r.textureID != nil || r.customTexture != nil
        var matte:CIImage?
        if hasScene || (scope != .all && hasTexture && r.opacity>0){
            let stableKey=sourceKey ?? key ?? UUID().uuidString
            guard let mask=foregroundMask(original,key:stableKey,document:document,feather:r.matteFeather ?? 0.0015,inset:r.matteInset ?? 0) else{return nil}
            matte=mask
        }
        if hasScene{
            let scene:CIImage?
            if let data=r.customScene{scene=CIImage(data:data,options:[.applyOrientationProperty:true])}
            else if let id=r.sceneID,let cg=LightAssets.image(id,scene:true)?.cgImage{scene=CIImage(cgImage:cg)}
            else{scene=nil}
            guard let scene,let matte else{return nil}
            var background=sceneCover(scene,target:rect,zoom:r.sceneZoom,x:r.sceneX,y:r.sceneY)
            if let blur=r.sceneBlur,blur>0{
                background=background.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:min(0.035,max(0,blur))*min(rect.width,rect.height)]).cropped(to:rect)
            }
            background=tone(background,exposure:r.sceneExposure ?? 0,warmth:r.sceneWarmth ?? 0)
            let foreground=tone(result,exposure:r.foregroundExposure ?? 0,warmth:r.foregroundWarmth ?? 0)
            result=foreground.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:background,kCIInputMaskImageKey:matte]).cropped(to:rect)
        }
        guard r.opacity>0,hasTexture else{return result}
        let texture:CIImage?
        if let data=r.customTexture{texture=CIImage(data:data,options:[.applyOrientationProperty:true])}
        else if let id=r.textureID,let cg=LightAssets.image(id,scene:false)?.cgImage{texture=CIImage(cgImage:cg)}
        else{texture=nil}
        guard let texture else{return nil}
        let gray=texture.applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:0])
        let placed=cover(softTexture(gray,fade:r.edgeFade ?? 0.12),rect:rect,zoom:r.zoom,x:r.x,y:r.y,angle:r.angle,mirror:r.mirror)
        // Back transparent pixels with the correct neutral value for each blend mode.
        func backed(_ level:Double)->CIImage{
            let neutral=CIImage(color:CIColor(red:level,green:level,blue:level,alpha:1)).cropped(to:rect)
            return placed.composited(over:neutral).cropped(to:rect)
        }
        func shadow(_ base:CIImage,amount:Double)->CIImage{
            let layer=backed(1).applyingFilter("CIColorMatrix",parameters:[
                "inputRVector":CIVector(x:0.52,y:0,z:0,w:0),"inputGVector":CIVector(x:0,y:0.52,z:0,w:0),
                "inputBVector":CIVector(x:0,y:0,z:0.52,w:0),"inputBiasVector":CIVector(x:0.48,y:0.48,z:0.48,w:0)])
            return mixed(layer.applyingFilter("CIMultiplyBlendMode",parameters:[kCIInputBackgroundImageKey:base]),base,amount:amount,rect:rect)
        }
        func sunlight(_ base:CIImage,amount:Double)->CIImage{
            let warm=max(-1,min(1,r.warmth))
            let red=0.66+0.22*max(0,warm),blue=0.66+0.22*max(0,-warm)-0.28*max(0,warm)
            let layer=backed(0).applyingFilter("CIColorMatrix",parameters:[
                "inputRVector":CIVector(x:red,y:0,z:0,w:0),"inputGVector":CIVector(x:0,y:0.62,z:0,w:0),"inputBVector":CIVector(x:0,y:0,z:blue,w:0)])
            return mixed(layer.applyingFilter("CIScreenBlendMode",parameters:[kCIInputBackgroundImageKey:base]),base,amount:amount,rect:rect)
        }
        let lit:CIImage
        switch r.blend{
        case .natural:lit=sunlight(shadow(result,amount:r.opacity*0.68),amount:r.opacity*0.62)
        case .screen:lit=sunlight(result,amount:r.opacity)
        case .multiply:lit=shadow(result,amount:r.opacity)
        case .soft:lit=mixed(backed(0.5).applyingFilter("CISoftLightBlendMode",parameters:[kCIInputBackgroundImageKey:result]),result,amount:r.opacity,rect:rect)
        }
        if scope != .all,let matte{
            let selected=scope == .background ? matte.applyingFilter("CIColorInvert"):matte
            return lit.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:result,kCIInputMaskImageKey:selected]).cropped(to:rect)
        }
        return lit
    }

}
struct LightMockupPanel:View{
    @Binding var recipe:CreativeRecipe
    var onRefine:(()->Void)?=nil
    private enum ImportKind:Equatable{case pack,texture,scene}
    @State private var importKind=ImportKind.texture
    @State private var importing=false
    @State private var notice=""
    @State private var packs=[String]()
    @State private var pack:String?=nil

    private var light:LightMockupRecipe{recipe.lighting ?? LightMockupRecipe()}
    private func binding<T>(_ key:WritableKeyPath<LightMockupRecipe,T>)->Binding<T>{
        Binding(get:{light[keyPath:key]},set:{var r=light;r[keyPath:key]=$0;recipe.lighting=r})
    }
    private func choose(_ id:String?,scene:Bool){
        var r=light
        if scene{r.sceneID=id;r.customScene=nil;r.customSceneName=nil;r.sceneZoom=1;r.sceneX=0;r.sceneY=0}
        else{r.textureID=id;r.customTexture=nil;r.customName=nil;r.x=0;r.y=0;r.zoom=1;r.angle=0;if let id{let base=id.split(separator:":").last.map(String.init) ?? id;r.blend=["lantern_glow","curtain_glow","blue_window"].contains(base) ? .screen:.natural}}
        recipe.lighting=r
    }
    var body:some View{
        VStack(alignment:.leading,spacing:12){
            Text("PREMIUM LIGHTING LAB").font(.system(size:10,weight:.semibold,design:.monospaced)).foregroundStyle(gold)
            Text("Texture ánh sáng & bóng từ asset tạo sẵn").font(.caption).foregroundStyle(.secondary)
            if !packs.isEmpty{Picker("Bộ asset",selection:$pack){Text("Tích hợp sẵn").tag(String?.none);ForEach(packs,id:\.self){id in Text("Bộ nhập "+String(id.prefix(6))).tag(Optional(id))}}}
            Button("Nhập gói Lighting Collection JSON",systemImage:"folder.badge.plus"){importKind = .pack;importing=true}.font(.caption)
            ScrollView(.horizontal,showsIndicators:false){LazyHStack(spacing:9){
                Button{choose(nil,scene:false)}label:{VStack{Image(systemName:"nosign").font(.title2).frame(width:84,height:82).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:9));Text("Không").font(.caption2)}}.buttonStyle(.plain)
                ForEach(LightAssets.entries(scene:false,pack:pack)){asset in
                    Button{choose(asset.id,scene:false)}label:{tile(asset,scene:false,selected:light.textureID==asset.id && light.customTexture==nil)}.buttonStyle(.plain)
                }
            }}
            Button("Nhập texture PNG/JPEG từ Tệp",systemImage:"square.and.arrow.down"){importKind = .texture;importing=true}.font(.caption)
            if let name=light.customName{Text(name).font(.caption2).foregroundStyle(gold)}
            if light.textureID != nil || light.customTexture != nil{
                Picker("Hòa trộn",selection:binding(\.blend)){ForEach(LightBlendMode.allCases){Text($0.rawValue).tag($0)}}
                control("Cường độ",binding(\.opacity),0...1)
                control("Nhiệt độ sáng",binding(\.warmth),-1...1)
                control("Phóng",binding(\.zoom),0.5...2.5)
                control("Vị trí ngang",binding(\.x),-1...1)
                control("Vị trí dọc",binding(\.y),-1...1)
                control("Góc xoay",binding(\.angle),-180...180)
                Picker("Vùng chiếu sáng",selection:Binding(get:{light.scope ?? .all},set:{var r=light;r.scope=$0;recipe.lighting=r})){ForEach(LightingScope.allCases){Text($0.rawValue).tag($0)}}
                control("Tan mềm mép texture",optional(\.edgeFade,0.12),0...0.35)
                Toggle("Lật ngang ánh sáng",isOn:binding(\.mirror))
            }
            Divider()
            Text("MOCKUP BỐI CẢNH").font(.system(size:10,weight:.semibold,design:.monospaced)).foregroundStyle(gold)
            Text("Dùng mặt nạ chủ thể đã chỉnh nếu có; nếu không, Vision tách tự động. Cảnh tích hợp độ phân giải thấp; nên nhập phông nền riêng chất lượng cao.").font(.caption2).foregroundStyle(.secondary)
            ScrollView(.horizontal,showsIndicators:false){LazyHStack(spacing:9){
                Button{choose(nil,scene:true)}label:{VStack{Image(systemName:"nosign").font(.title2).frame(width:116,height:82).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:9));Text("Nền gốc").font(.caption2)}}.buttonStyle(.plain)
                ForEach(LightAssets.entries(scene:true,pack:pack)){asset in Button{choose(asset.id,scene:true)}label:{tile(asset,scene:true,selected:light.sceneID==asset.id && light.customScene==nil)}.buttonStyle(.plain)}
            }}
            Button("Nhập phông nền riêng · tối đa 4096 px",systemImage:"photo.badge.plus"){importKind = .scene;importing=true}.font(.caption)
            if let name=light.customSceneName{Text(name).font(.caption2).foregroundStyle(gold)}
            if light.sceneID != nil || light.customScene != nil{
                control("Phóng phông nền",binding(\.sceneZoom),1...3)
                control("Nền ngang",binding(\.sceneX),-1...1)
                control("Nền dọc",binding(\.sceneY),-1...1)
                control("Xóa phông",optional(\.sceneBlur,0),0...0.035)
                control("Sáng phông nền",optional(\.sceneExposure,0),-1.5...1.5)
                control("Nhiệt độ phông nền",optional(\.sceneWarmth,0),-1...1)
                control("Sáng chủ thể",optional(\.foregroundExposure,0),-1...1)
                control("Nhiệt độ chủ thể",optional(\.foregroundWarmth,0),-1...1)
            }
            if light.sceneID != nil || light.customScene != nil || (light.scope ?? .all) != .all{
                control("Mềm biên chủ thể",optional(\.matteFeather,0.0015),0...0.025)
                control("Thu / mở mép vùng chọn",optional(\.matteInset,0),-0.012...0.012)
                if let onRefine{Button("Sửa mặt nạ chủ thể",systemImage:"paintbrush.pointed"){onRefine()}.font(.caption)}
                Text("Tạo hoặc sửa mặt nạ Chủ thể / Người trong Masking Studio. Các nét cọ và AI đã học được dùng khi ghép.").font(.caption2).foregroundStyle(.secondary)
            }
            Button("Xóa toàn bộ hiệu ứng ánh sáng & mockup",role:.destructive){recipe.lighting=nil}.font(.caption)
            Text(notice).font(.caption2).foregroundStyle(.secondary)
        }.onAppear{packs=LightingPackStore.ids()}
        .fileImporter(isPresented:$importing,allowedContentTypes:importKind == .pack ? [.json]:[.image]){response in
            do{
                let url=try response.get(),access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
                let bytes=try Data(contentsOf:url,options:.mappedIfSafe)
                if importKind == .pack{
                    let id=try LightingPackStore.install(bytes);packs=LightingPackStore.ids();pack=id;notice="Đã nhập bộ 16 cảnh và 8 texture.";return
                }
                let scene=importKind == .scene
                guard bytes.count<=50_000_000,let cg=PhotoEngine.thumb(bytes,limit:scene ? 4096:3072) else{throw CameraError.unreadable}
                var r=light
                if scene{
                    guard let jpeg=UIImage(cgImage:cg).jpegData(compressionQuality:0.94),jpeg.count<=16_000_000 else{throw CameraError.unreadable}
                    r.sceneID=nil;r.customScene=jpeg;r.customSceneName=url.lastPathComponent;r.sceneZoom=1;r.sceneX=0;r.sceneY=0
                }else{
                    let alpha=[CGImageAlphaInfo.first,.last,.premultipliedFirst,.premultipliedLast].contains(cg.alphaInfo)
                    let data=alpha ? UIImage(cgImage:cg).pngData():UIImage(cgImage:cg).jpegData(compressionQuality:0.94)
                    guard let data,data.count<=24_000_000 else{throw CameraError.unreadable}
                    r.textureID=nil;r.customTexture=data;r.customName=url.lastPathComponent;r.x=0;r.y=0;r.zoom=1;r.angle=0
                }
                recipe.lighting=r;notice="Đã nhập \(cg.width) × \(cg.height) px."
            }catch{notice=error.localizedDescription}
        }
    }
    private func optional(_ key:WritableKeyPath<LightMockupRecipe,Double?>,_ fallback:Double)->Binding<Double>{
        Binding(get:{light[keyPath:key] ?? fallback},set:{var r=light;r[keyPath:key]=$0;recipe.lighting=r})
    }

    private func tile(_ item:LightAsset,scene:Bool,selected:Bool)->some View{
        VStack(alignment:.leading,spacing:5){
            if let image=LightAssets.image(item.id,scene:scene){
                Image(uiImage:image).resizable().scaledToFill().frame(width:scene ? 116:84,height:82).clipped().clipShape(RoundedRectangle(cornerRadius:9))
                    .overlay{RoundedRectangle(cornerRadius:9).strokeBorder(selected ? gold:.clear,lineWidth:2)}
            }
            Text(item.name).font(.caption2.weight(selected ? .semibold:.regular)).lineLimit(1)
        }.frame(width:scene ? 116:84,alignment:.leading)
    }
    private func control(_ title:String,_ value:Binding<Double>,_ range:ClosedRange<Double>)->some View{
        VStack(alignment:.leading,spacing:3){HStack{Text(title);Spacer();Text(String(format:"%.2f",value.wrappedValue)).monospacedDigit().foregroundStyle(gold)}.font(.caption);Slider(value:value,in:range)}
    }
}
