import SwiftUI
import CoreImage
import UIKit
import Vision
import UniformTypeIdentifiers

enum LightBlendMode:String,Codable,CaseIterable,Identifiable{
    case natural="Ánh sáng & bóng",screen="Ánh sáng",multiply="Bóng đổ",soft="Soft Light"
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
}
struct LightAsset:Identifiable{
    let id:String
    let name:String
    let index:Int
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
    static func image(_ id:String,scene:Bool)->UIImage?{
        let key="\(scene):\(id)" as NSString
        if let cached=cache.object(forKey:key){return cached}
        let list=scene ? scenes:textures
        guard let item=list.first(where:{$0.id==id}),let atlas=UIImage(named:scene ? "premium_scene_atlas":"premium_light_atlas")?.cgImage else{return nil}
        let columns=4,rows=scene ? 4:2
        let w=atlas.width/columns,h=atlas.height/rows,margin=scene ? 3:0
        let r=CGRect(x:(item.index%columns)*w+margin,y:(item.index/columns)*h+margin,width:w-2*margin,height:h-2*margin)
        guard let cg=atlas.cropping(to:r) else{return nil}
        let image=UIImage(cgImage:cg);cache.setObject(image,forKey:key,cost:cg.bytesPerRow*cg.height)
        return image
    }
}
enum LightMockupEngine{
    private static let context=CIContext(options:[.cacheIntermediates:false])
    private static let maskCache=NSCache<NSString,CIImage>()
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
    private static func foregroundMask(_ image:CIImage,key:String?)->CIImage?{
        let rect=image.extent
        if let key,let found=maskCache.object(forKey:key as NSString){return fittedMask(found,to:rect)}
        let scale=min(1,768/max(rect.width,rect.height))
        let small=image.transformed(by:CGAffineTransform(translationX:-rect.minX,y:-rect.minY)).transformed(by:CGAffineTransform(scaleX:scale,y:scale))
        guard let cg=context.createCGImage(small,from:small.extent.integral) else{return nil}
        let request=VNGenerateForegroundInstanceMaskRequest()
        let handler=VNImageRequestHandler(cgImage:cg,options:[:])
        do{
            try handler.perform([request])
            guard let observation=request.results?.first,!observation.allInstances.isEmpty else{return nil}
            let buffer=try observation.generateScaledMaskForImage(forInstances:observation.allInstances,from:handler)
            let mask=CIImage(cvPixelBuffer:buffer)
            if let key{maskCache.countLimit=8;maskCache.setObject(mask,forKey:key as NSString)}
            return fittedMask(mask,to:rect)
        }catch{return nil}
    }
    private static func fittedMask(_ mask:CIImage,to rect:CGRect)->CIImage{
        let box=mask.extent
        return mask.transformed(by:CGAffineTransform(translationX:-box.minX,y:-box.minY))
            .transformed(by:CGAffineTransform(scaleX:rect.width/max(1,box.width),y:rect.height/max(1,box.height)))
            .transformed(by:CGAffineTransform(translationX:rect.minX,y:rect.minY)).cropped(to:rect)
    }
    static func apply(_ image:CIImage,original:CIImage,recipe:LightMockupRecipe?,key:String?=nil)->CIImage?{
        guard let r=recipe else{return image}
        let rect=image.extent
        var result=image
        if let id=r.sceneID{
            guard let cg=LightAssets.image(id,scene:true)?.cgImage,let mask=foregroundMask(original,key:key) else{return nil}
            let background=cover(CIImage(cgImage:cg),rect:rect,zoom:max(1,r.sceneZoom),x:r.sceneX,y:r.sceneY)
                .clampedToExtent().cropped(to:rect)
            result=result.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:background,kCIInputMaskImageKey:fittedMask(mask,to:rect)]).cropped(to:rect)
        }
        guard r.opacity>0 else{return result}
        let texture:CIImage?
        if let data=r.customTexture,let custom=CIImage(data:data,options:[.applyOrientationProperty:true]){texture=custom}
        else if let id=r.textureID,let cg=LightAssets.image(id,scene:false)?.cgImage{texture=CIImage(cgImage:cg)}
        else{texture=nil}
        guard let texture else{return result}
        let gray=texture.applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:0])
        let placed=cover(gray,rect:rect,zoom:r.zoom,x:r.x,y:r.y,angle:r.angle,mirror:r.mirror)
        // Neutral backing avoids a hard black rectangle where the texture is moved outside the canvas.
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
        switch r.blend{
        case .natural:return sunlight(shadow(result,amount:r.opacity*0.68),amount:r.opacity*0.62)
        case .screen:return sunlight(result,amount:r.opacity)
        case .multiply:return shadow(result,amount:r.opacity)
        case .soft:return mixed(backed(0.5).applyingFilter("CISoftLightBlendMode",parameters:[kCIInputBackgroundImageKey:result]),result,amount:r.opacity,rect:rect)
        }
    }
}
struct LightMockupPanel:View{
    @Binding var recipe:CreativeRecipe
    @State private var importing=false
    @State private var notice=""
    private var light:LightMockupRecipe{recipe.lighting ?? LightMockupRecipe()}
    private func binding<T>(_ key:WritableKeyPath<LightMockupRecipe,T>)->Binding<T>{
        Binding(get:{light[keyPath:key]},set:{var r=light;r[keyPath:key]=$0;recipe.lighting=r})
    }
    private func choose(_ id:String?,scene:Bool){
        var r=light
        if scene{r.sceneID=id;r.sceneZoom=1;r.sceneX=0;r.sceneY=0}
        else{r.textureID=id;r.customTexture=nil;r.customName=nil}
        recipe.lighting=r
    }
    var body:some View{
        VStack(alignment:.leading,spacing:12){
            Text("PREMIUM LIGHTING LAB").font(.system(size:10,weight:.semibold,design:.monospaced)).foregroundStyle(gold)
            Text("Texture ánh sáng & bóng thật từ asset tạo sẵn").font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal,showsIndicators:false){LazyHStack(spacing:9){
                Button{choose(nil,scene:false)}label:{VStack{Image(systemName:"nosign").font(.title2).frame(width:84,height:82).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:9));Text("Không").font(.caption2)}}.buttonStyle(.plain)
                ForEach(LightAssets.textures){asset in
                    Button{choose(asset.id,scene:false)}label:{tile(asset,scene:false,selected:light.textureID==asset.id && light.customTexture==nil)}.buttonStyle(.plain)
                }
            }}
            Button("Nhập texture PNG/JPEG từ Tệp",systemImage:"square.and.arrow.down"){importing=true}.font(.caption)
            if let name=light.customName{Text(name).font(.caption2).foregroundStyle(gold)}
            if light.textureID != nil || light.customTexture != nil{
                Picker("Hòa trộn",selection:binding(\.blend)){ForEach(LightBlendMode.allCases){Text($0.rawValue).tag($0)}}
                control("Cường độ",binding(\.opacity),0...1)
                control("Nhiệt độ sáng",binding(\.warmth),-1...1)
                control("Phóng",binding(\.zoom),0.5...2.5)
                control("Vị trí ngang",binding(\.x),-1...1)
                control("Vị trí dọc",binding(\.y),-1...1)
                control("Góc xoay",binding(\.angle),-180...180)
                Toggle("Lật ngang ánh sáng",isOn:binding(\.mirror))
            }
            Divider()
            Text("MOCKUP BỐI CẢNH").font(.system(size:10,weight:.semibold,design:.monospaced)).foregroundStyle(gold)
            Text("Tách chủ thể bằng Vision trên máy, rồi ghép vào phông nền đã tạo. Bản hiện tại dùng cảnh nguồn 378 × 250 px; không dùng cho bản in lớn.").font(.caption2).foregroundStyle(.secondary)
            ScrollView(.horizontal,showsIndicators:false){LazyHStack(spacing:9){
                Button{choose(nil,scene:true)}label:{VStack{Image(systemName:"nosign").font(.title2).frame(width:116,height:82).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:9));Text("Nền gốc").font(.caption2)}}.buttonStyle(.plain)
                ForEach(LightAssets.scenes){asset in Button{choose(asset.id,scene:true)}label:{tile(asset,scene:true,selected:light.sceneID==asset.id)}.buttonStyle(.plain)}
            }}
            if light.sceneID != nil{
                control("Phóng phông nền",binding(\.sceneZoom),1...2.5)
                control("Nền ngang",binding(\.sceneX),-0.6...0.6)
                control("Nền dọc",binding(\.sceneY),-0.6...0.6)
            }
            Button("Xóa toàn bộ hiệu ứng ánh sáng & mockup",role:.destructive){recipe.lighting=nil}.font(.caption)
            Text(notice).font(.caption2).foregroundStyle(.secondary)
        }.fileImporter(isPresented:$importing,allowedContentTypes:[.png,.jpeg,.heic,.image]){response in
            do{
                let url=try response.get(),access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
                let bytes=try Data(contentsOf:url,options:.mappedIfSafe)
                guard bytes.count<=30_000_000,let cg=PhotoEngine.thumb(bytes,limit:1536),let jpeg=UIImage(cgImage:cg).jpegData(compressionQuality:0.9),jpeg.count<=4_000_000 else{throw CameraError.unreadable}
                var r=light;r.textureID=nil;r.customTexture=jpeg;r.customName=url.lastPathComponent;recipe.lighting=r;notice="Đã nhập texture riêng; dữ liệu được lưu trong công thức chỉnh ảnh."
            }catch{notice=error.localizedDescription}
        }
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
