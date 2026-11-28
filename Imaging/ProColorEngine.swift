import Foundation
import CoreImage
import UIKit

struct ProRGB:Codable,Equatable{
    var r:Double
    var g:Double
    var b:Double
    var hue:Double{
        let hi=max(r,max(g,b)),lo=min(r,min(g,b)),d=hi-lo
        guard d>0.00001 else{return 0}
        let h:Double
        if hi==r{h=(g-b)/d/6}else if hi==g{h=((b-r)/d+2)/6}else{h=((r-g)/d+4)/6}
        return h-floor(h)
    }
}
struct ProColorBand:Codable,Equatable{
    var hue=0.0
    var width=0.10
    var shift=0.0
    var saturation=0.0
    var luminance=0.0
}
struct ProCurve:Codable,Equatable{
    var low=0.25
    var mid=0.5
    var high=0.75
    static let identity=Self()
    // Monotonic, piecewise linear interpolation: never overshoot adjacent control points.
    func value(_ x:Double)->Double{
        let t=min(1,max(0,x))*4
        let i=min(3,Int(t)),f=t-Double(i)
        let a=min(1,max(0,low)),b=max(a,min(1,mid)),c=max(b,min(1,high))
        let points=[0.0,a,b,c,1.0]
        return points[i]+(points[i+1]-points[i])*f
    }
}
struct ProColorStatistics:Codable,Equatable{
    var mean:ProRGB
    var deviation:ProRGB
    var black:Double
    var white:Double
    var edge:Double
    static func analyze(_ image:CGImage)->Self?{
        let n=96
        var bytes=[UInt8](repeating:0,count:n*n*4)
        let ok=bytes.withUnsafeMutableBytes{p->Bool in
            guard let c=CGContext(data:p.baseAddress,width:n,height:n,bitsPerComponent:8,bytesPerRow:n*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else{return false}
            c.draw(image,in:CGRect(x:0,y:0,width:n,height:n));return true
        }
        guard ok else{return nil}
        var sum=[Double](repeating:0,count:3),sq=sum,gray=[Double](),black=0,white=0
        for i in stride(from:0,to:bytes.count,by:4){
            let r=Double(bytes[i])/255,g=Double(bytes[i+1])/255,b=Double(bytes[i+2])/255
            for (j,v) in [r,g,b].enumerated(){sum[j]+=v;sq[j]+=v*v}
            let y=0.2126*r+0.7152*g+0.0722*b;gray.append(y)
            if max(r,max(g,b))<=0.015{black+=1}
            if max(r,max(g,b))>=0.985{white+=1}
        }
        let count=Double(n*n),m=sum.map{$0/count}
        let dev=sq.enumerated().map{j,v in sqrt(max(0,v/count-m[j]*m[j]))}
        var edge=0.0
        for y in 1..<n{for x in 1..<n{let i=y*n+x;edge+=abs(gray[i]-gray[i-1])+abs(gray[i]-gray[i-n])}}
        return Self(mean:ProRGB(r:m[0],g:m[1],b:m[2]),deviation:ProRGB(r:dev[0],g:dev[1],b:dev[2]),black:Double(black)/count,white:Double(white)/count,edge:edge/count)
    }
    static func url(_ url:URL)->Self?{
        guard let bytes=try? Data(contentsOf:url,options:.mappedIfSafe),let cg=PhotoEngine.thumb(bytes,limit:512) else{return nil}
        return analyze(cg)
    }
}
struct ProReference:Codable,Equatable{
    var source:ProColorStatistics
    var target:ProColorStatistics
    var strength=0.5
}
struct ProColorRecipe:Codable,Equatable{
    var bands:[ProColorBand]=[]
    var master=ProCurve()
    var red=ProCurve()
    var green=ProCurve()
    var blue=ProCurve()
    var reference:ProReference?=nil
    var shadowColor=0.0
    var midColor=0.0
    var highlightColor=0.0
    var skinSmooth=0.0
    var skinRadius=0.004
    var colorOnly:Bool{skinSmooth<=0}
    var hasColor:Bool{!bands.isEmpty || master != .identity || red != .identity || green != .identity || blue != .identity || reference != nil || shadowColor != 0 || midColor != 0 || highlightColor != 0}
}
enum ProColorEngine{
    static func clamp(_ v:Double)->Double{max(0,min(1,v))}
    static func smooth(_ x:Double)->Double{let v=clamp(x);return v*v*(3-2*v)}
    static func rgb(_ h:Double,_ s:Double,_ v:Double)->ProRGB{
        let h=(h-floor(h))*6,i=Int(h),f=h-Double(i),a=v*(1-s),b=v*(1-s*f),c=v*(1-s*(1-f))
        switch i%6{case 0:return ProRGB(r:v,g:c,b:a);case 1:return ProRGB(r:b,g:v,b:a);case 2:return ProRGB(r:a,g:v,b:c);case 3:return ProRGB(r:a,g:b,b:v);case 4:return ProRGB(r:c,g:a,b:v);default:return ProRGB(r:v,g:a,b:b)}
    }
    static func grade(_ input:ProRGB,recipe:ProColorRecipe)->ProRGB{
        var c=input
        if let ref=recipe.reference{
            let a=clamp(ref.strength)
            func match(_ v:Double,_ sm:Double,_ sd:Double,_ tm:Double,_ td:Double)->Double{
                let ratio=max(0.75,min(1.30,td/max(0.035,sd)))
                let offset=max(-0.16,min(0.16,tm-sm))
                return clamp(v+a*((v-sm)*(ratio-1)+offset))
            }
            c=ProRGB(r:match(c.r,ref.source.mean.r,ref.source.deviation.r,ref.target.mean.r,ref.target.deviation.r),g:match(c.g,ref.source.mean.g,ref.source.deviation.g,ref.target.mean.g,ref.target.deviation.g),b:match(c.b,ref.source.mean.b,ref.source.deviation.b,ref.target.mean.b,ref.target.deviation.b))
        }
        let maxv=max(c.r,max(c.g,c.b)),minv=min(c.r,min(c.g,c.b)),d=maxv-minv
        if d>0.00001,maxv>0{
            let h=c.hue,s=d/maxv
            var shift=0.0,sat=0.0,lum=0.0
            for band in recipe.bands.prefix(9){
                let diff=abs(h-(band.hue-floor(band.hue))),distance=min(diff,1-diff)
                let weight=smooth(1-distance/max(0.025,min(0.5,band.width)))*smooth(d/0.12)
                shift+=band.shift*weight;sat+=band.saturation*weight;lum+=band.luminance*weight
            }
            c=rgb(h+max(-0.5,min(0.5,shift)),clamp(s+sat*s*(sat>0 ? 1-s:1)),clamp(maxv+lum*0.35))
        }
        let y=0.2126*c.r+0.7152*c.g+0.0722*c.b
        let warm=0.10*(recipe.shadowColor*(1-smooth(y/0.5))+recipe.midColor*(1-abs(2*y-1))+recipe.highlightColor*smooth((y-0.5)/0.5))
        c=ProRGB(r:clamp(c.r+warm),g:clamp(c.g-warm*0.12),b:clamp(c.b-warm))
        return ProRGB(r:recipe.red.value(recipe.master.value(c.r)),g:recipe.green.value(recipe.master.value(c.g)),b:recipe.blue.value(recipe.master.value(c.b)))
    }
    private static let cache=NSCache<NSData,NSData>()
    static func cube(_ recipe:ProColorRecipe,dimension:Int=32)->Data{
        var keyRecipe=recipe;keyRecipe.skinSmooth=0;keyRecipe.skinRadius=0
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        var encoded=(try? encoder.encode(keyRecipe)) ?? Data()
        encoded.append(contentsOf:String(dimension).utf8)
        let key=encoded as NSData
        if let cached=cache.object(forKey:key){return cached as Data}
        let n=Double(dimension-1)
        var values=[Float]();values.reserveCapacity(dimension*dimension*dimension*4)
        for b in 0..<dimension{for g in 0..<dimension{for r in 0..<dimension{
            let c=grade(ProRGB(r:Double(r)/n,g:Double(g)/n,b:Double(b)/n),recipe:recipe)
            values.append(contentsOf:[Float(c.r),Float(c.g),Float(c.b),1])
        }}}
        let data=values.withUnsafeBytes{Data($0)}
        cache.totalCostLimit=12*1024*1024;cache.countLimit=18;cache.setObject(data as NSData,forKey:key,cost:data.count)
        return data
    }
    static func apply(_ image:CIImage,recipe:ProColorRecipe?)->CIImage{
        guard let recipe,recipe.hasColor else{return image}
        return image.applyingFilter("CIColorCubeWithColorSpace",parameters:["inputCubeDimension":32,"inputCubeData":cube(recipe),"inputColorSpace":CGColorSpace(name:CGColorSpace.sRGB)!]).cropped(to:image.extent)
    }
    // Recombine the high-frequency residual with a gently smoothed low-frequency
    // layer, only inside an explicitly chosen face/brush mask. No generative skin.
    private static let separation=CIColorKernel(source:"""
        kernel vec4 retouch(__sample source, __sample low, __sample even, float amount){
            vec3 high=source.rgb-low.rgb;
            return vec4(source.rgb + (even.rgb-low.rgb)*amount,source.a);
        }
        """)
    static func retouch(_ image:CIImage,mask:CIImage,amount:Double,radius:Double)->CIImage?{
        guard amount>0 else{return image}
        let rect=image.extent
        let r=max(1,min(32,min(rect.width,rect.height)*max(0.001,min(0.012,radius))))
        let low=image.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:r]).cropped(to:rect)
        let even=low.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:r*2]).cropped(to:rect)
        guard let kernel=separation,let refined=kernel.apply(extent:rect,arguments:[image,low,even,Float(clamp(amount)*0.65)]) else{return nil}
        return refined.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:image,kCIInputMaskImageKey:mask]).cropped(to:rect)
    }
    static func sample(_ image:CGImage,x:Double,y:Double)->ProRGB?{
        let px=min(image.width-1,max(0,Int(clamp(x)*Double(image.width)))),py=min(image.height-1,max(0,Int(clamp(y)*Double(image.height))))
        guard let patch=image.cropping(to:CGRect(x:px,y:py,width:1,height:1)) else{return nil}
        var bytes=[UInt8](repeating:0,count:4)
        let ok=bytes.withUnsafeMutableBytes{p->Bool in
            guard let ctx=CGContext(data:p.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else{return false}
            ctx.draw(patch,in:CGRect(x:0,y:0,width:1,height:1));return true
        }
        return ok ? ProRGB(r:Double(bytes[0])/255,g:Double(bytes[1])/255,b:Double(bytes[2])/255):nil
    }
}
