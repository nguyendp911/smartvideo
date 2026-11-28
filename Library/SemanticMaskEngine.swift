import SwiftUI
import CoreImage
import CoreML
import Vision
import UIKit

enum PhotoMaskKind:String,CaseIterable,Codable,Identifiable{
    case sky="Bầu trời",subject="Chủ thể",background="Hậu cảnh",brush="Cọ vẽ",linear="Gradient tuyến tính",radial="Gradient tròn",luminance="Vùng sáng tối"
    var id:String{rawValue}
    var symbol:String{switch self{case .sky:return "cloud.sun";case .subject:return "person.crop.rectangle";case .background:return "rectangle.dashed";case .brush:return "paintbrush.pointed";case .linear:return "line.diagonal";case .radial:return "circle.dotted";case .luminance:return "sun.max"}}
}
struct MaskPoint:Codable,Equatable{var x:Double;var y:Double}
struct MaskStroke:Codable,Equatable,Identifiable{
    var id=UUID()
    var subtract=false
    var size=0.08
    var points:[MaskPoint]=[]
}
struct LocalGrade:Codable,Equatable{
    var exposure=0.0
    var contrast=1.0
    var saturation=1.0
    var warmth=0.0
    var tint=0.0
    var highlights=0.0
    var shadows=0.0
    var clarity=0.0
    var dehaze=0.0
    var sharpness=0.0
    var preset:String?=nil
    var presetStrength=0.8
}
struct PhotoMaskLayer:Codable,Identifiable,Equatable{
    var id=UUID()
    var name:String
    var kind:PhotoMaskKind
    var enabled=true
    var inverted=false
    var feather=0.008
    var threshold=0.5
    var strength=1.0
    var centerX=0.5
    var centerY=0.5
    var radius=0.35
    var angle=0.0
    var strokes:[MaskStroke]=[]
    var grade=LocalGrade()
    var replacement:Data?=nil
}
struct PhotoMaskDocument:Codable,Equatable{
    var source:String
    var layers:[PhotoMaskLayer]=[]
}
enum PhotoMaskError:LocalizedError{
    case modelMissing,unreadable,noSubject,invalidOutput
    var errorDescription:String?{switch self{
    case .modelMissing:return "Chưa có mô hình SkySegSmall trong bản cài này. Dùng cọ/gradient hoặc cài bản build có model."
    case .unreadable:return "Không đọc được ảnh hoặc mặt nạ."
    case .noSubject:return "Không tìm thấy chủ thể rõ. Hãy dùng cọ để chọn vùng."
    case .invalidOutput:return "Đầu ra mô hình không đúng định dạng."
    }}
}
enum SemanticMaskEngine{
    static let context=CIContext(options:[.cacheIntermediates:false])
    private static let cache=NSCache<NSString,CIImage>()
    private static let skyModel:MLModel?={
        guard let url=Bundle.main.url(forResource:"SkySegSmall",withExtension:"mlmodelc") else{return nil}
        let config=MLModelConfiguration();config.computeUnits = .all
        return try? MLModel(contentsOf:url,configuration:config)
    }()
    static var skyAvailable:Bool{skyModel != nil}
    static func sourceKey(_ url:URL)->String{
        let parent=url.deletingLastPathComponent().lastPathComponent
        if UUID(uuidString:parent) != nil{return parent+"/"+url.lastPathComponent}
        return url.standardizedFileURL.path
    }
    private static func normalized(_ image:CIImage)->CIImage{
        image.transformed(by:CGAffineTransform(translationX:-image.extent.minX,y:-image.extent.minY))
    }
    static func fit(_ image:CIImage,to rect:CGRect)->CIImage{
        let v=normalized(image)
        return v.transformed(by:CGAffineTransform(scaleX:rect.width/v.extent.width,y:rect.height/v.extent.height)).transformed(by:CGAffineTransform(translationX:rect.minX,y:rect.minY)).cropped(to:rect)
    }
    private static func resized(_ image:CIImage,limit:CGFloat)->CIImage{
        let v=normalized(image),s=min(1,limit/max(v.extent.width,v.extent.height))
        return v.transformed(by:CGAffineTransform(scaleX:s,y:s))
    }
    private static func sky(_ image:CIImage)throws->CIImage{
        guard let model=skyModel else{throw PhotoMaskError.modelMissing}
        let n=384
        var pixel:CVPixelBuffer?
        let attrs:[String:Any]=[kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true]
        guard CVPixelBufferCreate(nil,n,n,kCVPixelFormatType_32BGRA,attrs as CFDictionary,&pixel)==kCVReturnSuccess,let pixel else{throw PhotoMaskError.unreadable}
        let rect=CGRect(x:0,y:0,width:n,height:n)
        context.render(fit(image,to:rect),to:pixel,bounds:rect,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))
        let input=try MLDictionaryFeatureProvider(dictionary:["image":MLFeatureValue(pixelBuffer:pixel)])
        let out=try model.prediction(from:input)
        guard let value=out.featureValue(for:"sky") else{throw PhotoMaskError.invalidOutput}
        if let p=value.imageBufferValue{return CIImage(cvPixelBuffer:p)}
        guard let array=value.multiArrayValue,array.shape.count>=2 else{throw PhotoMaskError.invalidOutput}
        let shape=array.shape.map{$0.intValue},w=shape.last!,h=shape[shape.count-2]
        guard w>0,h>0,w*h<=4_000_000 else{throw PhotoMaskError.invalidOutput}
        var bytes=[UInt8](repeating:0,count:w*h)
        for y in 0..<h{for x in 0..<w{
            var index=Array(repeating:NSNumber(value:0),count:shape.count)
            index[shape.count-2]=NSNumber(value:y);index[shape.count-1]=NSNumber(value:x)
            let p=array[index].doubleValue
            bytes[y*w+x]=UInt8((min(1,max(0,p.isFinite ? p:0))*255).rounded())
        }}
        let data=Data(bytes)
        guard let provider=CGDataProvider(data:data as CFData),let cg=CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else{throw PhotoMaskError.invalidOutput}
        return CIImage(cgImage:cg)
    }
    private static func subject(_ image:CIImage)throws->CIImage{
        let small=resized(image,limit:1600)
        guard let cg=context.createCGImage(small,from:small.extent) else{throw PhotoMaskError.unreadable}
        let handler=VNImageRequestHandler(cgImage:cg,options:[:]),request=VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let result=request.results?.first,!result.allInstances.isEmpty else{throw PhotoMaskError.noSubject}
        return CIImage(cvPixelBuffer:try result.generateScaledMaskForImage(forInstances:result.allInstances,from:handler))
    }
    private static func semantic(_ image:CIImage,kind:PhotoMaskKind,key:String)throws->CIImage{
        let canonical=kind == .background ? PhotoMaskKind.subject:kind
        let cacheKey=(key+"#"+canonical.rawValue) as NSString
        if let saved=cache.object(forKey:cacheKey){return saved}
        let mask:CIImage
        if canonical == .sky{mask=try sky(image)}else{mask=try subject(image)}
        // Store a concrete bitmap, not a graph that retains original images.
        guard let cg=context.createCGImage(mask,from:mask.extent) else{throw PhotoMaskError.invalidOutput}
        let result=CIImage(cgImage:cg)
        cache.countLimit=12;cache.setObject(result,forKey:cacheKey)
        return result
    }
    static func mask(_ original:CIImage,layer:PhotoMaskLayer,key:String)throws->CIImage{
        let scaled=resized(original,limit:1536)
        let w=max(1,Int(scaled.extent.width.rounded())),h=max(1,Int(scaled.extent.height.rounded()))
        let rect=CGRect(x:0,y:0,width:w,height:h),short=min(rect.width,rect.height)
        var base:CIImage
        switch layer.kind{
        case .sky,.subject,.background:
            base=fit(try semantic(original,kind:layer.kind,key:key),to:rect)
            if layer.kind == .background{base=base.applyingFilter("CIColorInvert")}
            if layer.threshold != 0.5{
                base=base.applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:0.5-layer.threshold,kCIInputContrastKey:1.4])
            }
        case .brush:
            base=CIImage(color:.black).cropped(to:rect)
        case .linear:
            let angle=layer.angle*Double.pi/180,dx=CGFloat(cos(angle)),dy=CGFloat(sin(angle))
            let x=rect.width*layer.centerX,y=rect.height*(1-layer.centerY),r=short*layer.radius
            base=CIFilter(name:"CILinearGradient",parameters:["inputPoint0":CIVector(x:x-dx*r,y:y-dy*r),"inputPoint1":CIVector(x:x+dx*r,y:y+dy*r),"inputColor0":CIColor.white,"inputColor1":CIColor.black])!.outputImage!.cropped(to:rect)
        case .radial:
            base=CIFilter(name:"CIRadialGradient",parameters:["inputCenter":CIVector(x:rect.width*layer.centerX,y:rect.height*(1-layer.centerY)),"inputRadius0":short*layer.radius*0.55,"inputRadius1":short*layer.radius,"inputColor0":CIColor.white,"inputColor1":CIColor.black])!.outputImage!.cropped(to:rect)
        case .luminance:
            base=fit(scaled,to:rect).applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:0,kCIInputContrastKey:4,kCIInputBrightnessKey:0.5-layer.threshold])
        }
        if layer.inverted{base=base.applyingFilter("CIColorInvert")}
        if !layer.strokes.isEmpty{
            guard let cg=context.createCGImage(base,from:rect) else{throw PhotoMaskError.unreadable}
            let fmt=UIGraphicsImageRendererFormat();fmt.scale=1;fmt.opaque=true
            let drawn=UIGraphicsImageRenderer(size:rect.size,format:fmt).image{r in
                UIColor.black.setFill();r.fill(rect);UIImage(cgImage:cg).draw(in:rect)
                let c=r.cgContext
                for stroke in layer.strokes where !stroke.points.isEmpty{
                    let color=stroke.subtract ? UIColor.black:UIColor.white
                    c.setStrokeColor(color.cgColor);c.setFillColor(color.cgColor);c.setLineCap(.round);c.setLineJoin(.round)
                    let diameter=max(1,short*stroke.size)
                    c.setLineWidth(diameter)
                    let points=stroke.points.map{CGPoint(x:$0.x*rect.width,y:$0.y*rect.height)}
                    if points.count==1,let p=points.first{c.fillEllipse(in:CGRect(x:p.x-diameter/2,y:p.y-diameter/2,width:diameter,height:diameter))}
                    else if let p=points.first{c.beginPath();c.move(to:p);for p in points.dropFirst(){c.addLine(to:p)};c.strokePath()}
                }
            }
            guard let cg=drawn.cgImage else{throw PhotoMaskError.unreadable};base=CIImage(cgImage:cg)
        }
        if layer.feather>0{base=base.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:short*layer.feather]).cropped(to:rect)}
        base=base.applyingFilter("CIColorClamp",parameters:["inputMinComponents":CIVector(x:0,y:0,z:0,w:0),"inputMaxComponents":CIVector(x:1,y:1,z:1,w:1)])
        return fit(base,to:original.extent)
    }
    static func grade(_ input:CIImage,_ g:LocalGrade)->CIImage{
        var image=PremiumColorEngine.apply(input,id:g.preset,strength:g.presetStrength)
        image=image.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:g.exposure])
            .applyingFilter("CIColorControls",parameters:[kCIInputContrastKey:g.contrast,kCIInputSaturationKey:g.saturation])
        if g.warmth != 0 || g.tint != 0{image=image.applyingFilter("CITemperatureAndTint",parameters:["inputNeutral":CIVector(x:6500,y:0),"inputTargetNeutral":CIVector(x:6500+g.warmth*2200,y:g.tint*100)])}
        if g.highlights != 0 || g.shadows != 0{image=image.applyingFilter("CIHighlightShadowAdjust",parameters:["inputHighlightAmount":1+g.highlights,"inputShadowAmount":g.shadows])}
        if g.clarity != 0{image=image.applyingFilter("CIUnsharpMask",parameters:[kCIInputRadiusKey:8,kCIInputIntensityKey:g.clarity])}
        if g.dehaze != 0{image=image.applyingFilter("CIColorControls",parameters:[kCIInputContrastKey:1+g.dehaze*0.25,kCIInputSaturationKey:1+g.dehaze*0.15])}
        if g.sharpness>0{image=image.applyingFilter("CISharpenLuminance",parameters:[kCIInputSharpnessKey:g.sharpness])}
        return image
    }
    static func apply(_ input:CIImage,original:CIImage,document:PhotoMaskDocument?,key:String)throws->CIImage{
        guard let document,document.source==key else{return input}
        var image=input
        for layer in document.layers where layer.enabled && layer.strength>0{
            var matte=try mask(original,layer:layer,key:key)
            if layer.strength<1{let t=CGFloat(layer.strength);matte=matte.applyingFilter("CIColorMatrix",parameters:["inputRVector":CIVector(x:t,y:0,z:0,w:0),"inputGVector":CIVector(x:0,y:t,z:0,w:0),"inputBVector":CIVector(x:0,y:0,z:t,w:0)])}
            var region=image
            if layer.kind == .sky,let bytes=layer.replacement,let raw=CIImage(data:bytes,options:[.applyOrientationProperty:true]){
                let rect=input.extent,sky=normalized(raw),s=max(rect.width/sky.extent.width,rect.height/sky.extent.height)
                let scaled=sky.transformed(by:CGAffineTransform(scaleX:s,y:s))
                region=scaled.transformed(by:CGAffineTransform(translationX:rect.midX-scaled.extent.midX,y:rect.midY-scaled.extent.midY)).cropped(to:rect)
            }
            image=grade(region,layer.grade).applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:image,kCIInputMaskImageKey:matte]).cropped(to:input.extent)
        }
        return image
    }
    static func preview(_ url:URL,document:PhotoMaskDocument,selected:UUID?,overlay:Bool)throws->UIImage{
        guard let raw=CIImage(contentsOf:url,options:[.applyOrientationProperty:true]) else{throw PhotoMaskError.unreadable}
        let original=resized(raw,limit:1400)
        var result=try apply(original,original:original,document:document,key:sourceKey(url))
        if overlay,let layer=document.layers.first(where:{$0.id==selected}){
            let mask=try mask(original,layer:layer,key:sourceKey(url))
            let red=CIImage(color:CIColor(red:1,green:0.08,blue:0.12,alpha:0.48)).cropped(to:original.extent).composited(over:result)
            result=red.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:result,kCIInputMaskImageKey:mask]).cropped(to:original.extent)
        }
        guard let cg=context.createCGImage(result,from:result.extent) else{throw PhotoMaskError.unreadable}
        return UIImage(cgImage:cg)
    }
}
