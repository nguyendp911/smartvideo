import CoreImage
import Foundation

struct HealingSpot:Codable,Equatable{
    var source:MaskPoint
    var target:MaskPoint
    var radius:Double
}
struct PremiumEffects:Codable,Equatable{
    var protectSkin=0.0
    var adaptivePreset=false
    var dodgeBurn=0.0
    var skinEqualizer=0.0
    var eyeDetail=0.0
    var hairDetail=0.0
    var backgroundBlur=0.0
    var softbox=0.0
    var direction=0.0
    var softness=0.6
    var lightWarmth=0.0
    var rim=0.0
    var spill=0.0
    var ambient=0.0
    var shadow=0.0
    var denoise=0.0
    var deblur=0.0
    var jpegRepair=0.0
    var fadedPhoto=0.0
    var highlightRecovery=0.0
    var upscale=1
    var spots:[String:[HealingSpot]]=[:]
    var needsMask:Bool{dodgeBurn != 0 || skinEqualizer>0 || eyeDetail>0 || hairDetail>0 || backgroundBlur>0 || rim>0 || spill>0 || ambient>0}
    var styleOnly:Self{
        var copy=self
        copy.spots=[:];copy.dodgeBurn=0;copy.skinEqualizer=0;copy.eyeDetail=0;copy.hairDetail=0;copy.backgroundBlur=0;copy.rim=0;copy.spill=0;copy.ambient=0;copy.upscale=1
        return copy
    }
}
enum PremiumEffectsEngine{
    static func mix(_ changed:CIImage,_ base:CIImage,mask:CIImage)->CIImage{
        changed.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:base,kCIInputMaskImageKey:mask]).cropped(to:base.extent)
    }
    static func solid(_ value:Double,rect:CGRect)->CIImage{
        let v=ProColorEngine.clamp(value)
        return CIImage(color:CIColor(red:v,green:v,blue:v,alpha:1)).cropped(to:rect)
    }
    static func amount(_ mask:CIImage,_ value:Double)->CIImage{
        let v=ProColorEngine.clamp(value)
        return mask.applyingFilter("CIColorMatrix",parameters:["inputRVector":CIVector(x:v,y:0,z:0,w:0),"inputGVector":CIVector(x:0,y:v,z:0,w:0),"inputBVector":CIVector(x:0,y:0,z:v,w:0)]).cropped(to:mask.extent)
    }
    static func radial(_ rect:CGRect,center:CGPoint,radius:CGFloat,inner:CGFloat=0.35)->CIImage{
        CIFilter(name:"CIRadialGradient",parameters:["inputCenter":CIVector(cgPoint:center),"inputRadius0":radius*inner,"inputRadius1":radius,"inputColor0":CIColor.white,"inputColor1":CIColor.black])!.outputImage!.cropped(to:rect)
    }
    static func spot(_ image:CIImage,_ spot:HealingSpot)->CIImage{
        let r=image.extent
        let radius=max(1,min(r.width,r.height)*max(0.002,min(0.06,spot.radius)))
        func position(_ p:MaskPoint)->CGPoint{CGPoint(x:r.minX+r.width*p.x,y:r.maxY-r.height*p.y)}
        let a=position(spot.source),b=position(spot.target)
        guard r.insetBy(dx:radius,dy:radius).contains(a),r.contains(b) else{return image}
        let clone=image.transformed(by:CGAffineTransform(translationX:b.x-a.x,y:b.y-a.y))
        return mix(clone,image,mask:radial(r,center:b,radius:radius,inner:0.2))
    }
    static func gradient(_ rect:CGRect,direction:Double,softness:Double)->CIImage{
        let angle=direction*Double.pi/180
        let x=cos(angle),y=sin(angle),length=max(rect.width,rect.height)*(0.15+0.85*ProColorEngine.clamp(softness))
        return CIFilter(name:"CILinearGradient",parameters:["inputPoint0":CIVector(x:rect.midX-x*length/2,y:rect.midY-y*length/2),"inputPoint1":CIVector(x:rect.midX+x*length/2,y:rect.midY+y*length/2),"inputColor0":CIColor.black,"inputColor1":CIColor.white])!.outputImage!.cropped(to:rect)
    }
    static func exposure(_ image:CIImage,_ ev:Double)->CIImage{image.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:ev]).cropped(to:image.extent)}
    static func tint(_ image:CIImage,_ warm:Double)->CIImage{
        image.applyingFilter("CITemperatureAndTint",parameters:["inputNeutral":CIVector(x:6500,y:0),"inputTargetNeutral":CIVector(x:6500+max(-1,min(1,warm))*1800,y:0)]).cropped(to:image.extent)
    }
    static func blur(_ image:CIImage,_ radius:CGFloat)->CIImage{image.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:radius]).cropped(to:image.extent)}
    static func adaptiveStrength(_ strength:Double,features:EditingFeatures?)->Double{
        guard let f=features else{return strength}
        return ProColorEngine.clamp(strength*max(0.5,min(1.1,1-f.bright*0.6-max(0,f.saturation-0.25)*0.6)))
    }
    static func restore(_ image:CIImage,e:PremiumEffects)->CIImage{
        var r=image
        if e.jpegRepair>0{r=mix(blur(r,0.6),r,mask:solid(e.jpegRepair*0.28,rect:r.extent))}
        if e.denoise>0{r=MasterImageQuality.noise(r,amount:e.denoise)}
        if e.deblur>0{r=r.applyingFilter("CIUnsharpMask",parameters:[kCIInputRadiusKey:1.8,kCIInputIntensityKey:e.deblur*0.65]).cropped(to:r.extent)}
        if e.fadedPhoto>0{
            let corrected=r.applyingFilter("CIColorControls",parameters:[kCIInputContrastKey:1+e.fadedPhoto*0.18,kCIInputSaturationKey:1+e.fadedPhoto*0.12])
            r=corrected.cropped(to:r.extent)
        }
        if e.highlightRecovery>0{r=r.applyingFilter("CIHighlightShadowAdjust",parameters:["inputHighlightAmount":1-e.highlightRecovery*0.85,"inputShadowAmount":0]).cropped(to:r.extent)}
        return r
    }
    static func apply(_ image:CIImage,original:CIImage,e:PremiumEffects,document:PhotoMaskDocument?,key:String)->CIImage{
        var r=image
        let rect=r.extent
        let short=min(rect.width,rect.height)
        func chosen(_ kinds:[PhotoMaskKind])->CIImage?{
            guard let layer=document?.layers.last(where:{$0.enabled && !$0.inverted && kinds.contains($0.kind)}),let mask=try? SemanticMaskEngine.mask(original,layer:layer,key:key) else{return nil}
            return amount(mask,layer.strength)
        }
        if let spots=e.spots[key]{for s in spots.prefix(64){r=spot(r,s)}}
        if e.dodgeBurn != 0,let mask=chosen([.brush,.face]){r=mix(exposure(r,e.dodgeBurn*0.65),r,mask:mask)}
        if e.skinEqualizer>0,let mask=chosen([.face,.brush]),let even=ProColorEngine.retouch(r,mask:mask,amount:e.skinEqualizer,radius:0.009){r=even}
        if e.eyeDetail>0{
            let mask=chosen([.eyes]) ?? (try? SemanticMaskEngine.mask(original,layer:PhotoMaskLayer(name:"Mắt",kind:.eyes),key:key))
            if let mask{r=mix(MasterImageQuality.sharpen(exposure(r,e.eyeDetail*0.12),amount:e.eyeDetail*0.6),r,mask:mask)}
        }
        if e.hairDetail>0,let mask=chosen([.brush]){r=mix(MasterImageQuality.sharpen(r,amount:e.hairDetail),r,mask:mask)}
        let direction=gradient(rect,direction:e.direction,softness:e.softness)
        if e.softbox>0{r=mix(tint(exposure(r,e.softbox*0.45),e.lightWarmth),r,mask:amount(direction,e.softbox))}
        if e.shadow>0{r=mix(exposure(r,-e.shadow*0.6),r,mask:direction.applyingFilter("CIColorInvert").cropped(to:rect))}
        if e.backgroundBlur>0 || e.rim>0 || e.spill>0 || e.ambient>0{
            if let matte=LightMockupEngine.foregroundMask(original,key:key,document:document,feather:0.002,inset:0){
                let coverage=LightMockupEngine.maskCoverage(matte)
                if coverage>0.002,coverage<0.998{
                    let background=matte.applyingFilter("CIColorInvert").cropped(to:rect)
                    if e.backgroundBlur>0{
                        // Normalized masked blur avoids bleeding foreground colors into the background.
                        let radius=max(1,min(45,short*0.014*e.backgroundBlur))
                        let weighted=r.applyingFilter("CIMultiplyCompositing",parameters:[kCIInputBackgroundImageKey:background]).cropped(to:rect)
                        let blurred=blur(weighted,radius)
                        let weight=blur(background,radius)
                        if let kernel=normalizeKernel,let b=kernel.apply(extent:rect,arguments:[blurred,weight,r]){
                            r=mix(b,r,mask:background)
                        }
                    }
                    let work=CGRect(x:0,y:0,width:max(1,rect.width*min(1,768/max(rect.width,rect.height))),height:max(1,rect.height*min(1,768/max(rect.width,rect.height))))
                    let small=SemanticMaskEngine.fit(matte,to:work)
                    let inner=small.clampedToExtent().applyingFilter("CIMorphologyMinimum",parameters:[kCIInputRadiusKey:3]).cropped(to:work)
                    let edge=small.applyingFilter("CISubtractBlendMode",parameters:[kCIInputBackgroundImageKey:inner]).cropped(to:work)
                    // Subtract blend order is background minus foreground; use explicit kernel below.
                    if let edgeKernel,let ring=edgeKernel.apply(extent:work,arguments:[small,inner]){
                        let feather=SemanticMaskEngine.fit(blur(ring,2),to:rect)
                        if e.rim>0{let mask=amount(feather,e.rim).applyingFilter("CIMultiplyCompositing",parameters:[kCIInputBackgroundImageKey:direction]).cropped(to:rect);r=mix(tint(exposure(r,0.65),e.lightWarmth),r,mask:mask)}
                        if e.spill>0{r=mix(tint(r,e.lightWarmth*e.spill),r,mask:amount(feather,e.spill))}
                    }
                    _=edge
                    if e.ambient>0,let a=mean(r,mask:matte),let b=mean(r,mask:background){
                        let delta=max(-0.45,min(0.45,log2(max(0.04,b)/max(0.04,a))))
                        r=mix(exposure(r,delta*e.ambient),r,mask:matte)
                    }
                }
            }
        }
        if e.protectSkin>0{r=MasterImageQuality.preserveChroma(original:original,graded:r,amount:e.protectSkin)}
        return r.cropped(to:rect)
    }
    private static let normalizeKernel=CIColorKernel(source:"""
        kernel vec4 normalizeBlur(__sample color, __sample weight, __sample source) {
            float w=weight.r;
            return vec4(mix(source.rgb,color.rgb/max(w,0.02),smoothstep(0.02,0.15,w)),source.a);
        }
        """)
    private static let edgeKernel=CIColorKernel(source:"""
        kernel vec4 innerEdge(__sample outer, __sample inner) {
            float v=clamp(outer.r-inner.r,0.0,1.0);
            return vec4(v,v,v,1.0);
        }
        """)
    private static func mean(_ image:CIImage,mask:CIImage)->Double?{
        let rect=image.extent
        let m=LightMockupEngine.maskCoverage(mask)
        guard m>0.002 else{return nil}
        let weighted=image.applyingFilter("CIMultiplyCompositing",parameters:[kCIInputBackgroundImageKey:mask]).cropped(to:rect)
        let avg=weighted.applyingFilter("CIAreaAverage",parameters:[kCIInputExtentKey:CIVector(cgRect:rect)])
        var p=[Float](repeating:0,count:4)
        p.withUnsafeMutableBytes{b in SemanticMaskEngine.context.render(avg,toBitmap:b.baseAddress!,rowBytes:16,bounds:CGRect(x:0,y:0,width:1,height:1),format:.RGBAf,colorSpace:nil)}
        return (0.2126*Double(p[0])+0.7152*Double(p[1])+0.0722*Double(p[2]))/m
    }
    static func upscale(_ image:CIImage,factor:Int,maxSize:Int)->CIImage{
        let r=image.extent
        let s=min(CGFloat(max(1,min(2,factor))),CGFloat(maxSize)/max(r.width,r.height),sqrt(70_000_000/(r.width*r.height)))
        guard s>1.001 else{return image}
        return image.applyingFilter("CILanczosScaleTransform",parameters:[kCIInputScaleKey:s,kCIInputAspectRatioKey:1]).cropped(to:CGRect(x:0,y:0,width:floor(r.width*s),height:floor(r.height*s)))
    }
}
