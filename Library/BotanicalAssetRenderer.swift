import SwiftUI
import UIKit

/// Actual raster assets generated for VieLens, not vector imitations.
enum BotanicalAssets {
    static let names = [
        "botanical_young","botanical_bloom","botanical_autumn","botanical_autumn_sprig",
        "botanical_corner","botanical_flower","botanical_leaf","botanical_petal","botanical_bud",
        "botanical_dew","botanical_drop","botanical_firefly","botanical_light","botanical_bokeh",
        "botanical_snow_crystal","botanical_snow_small","botanical_snow_soft"
    ]
    static func rail(theme:VineTheme,age:VineGrowth)->String{
        guard age.hasFlowers,theme != .minimal else{return "botanical_young"}
        return [.autumn,.heritage,.dragon].contains(theme) ? "botanical_autumn":"botanical_bloom"
    }
    static func hue(_ theme:VineTheme,young:Bool)->Double{
        switch theme{
        case .autumn,.heritage,.dragon:return young ? -65:0
        case .moon,.winter:return 70
        case .wisteria:return 110
        case .neon:return 62
        case .sakura:return 18
        case .rose:return -8
        case .midnight:return 10
        case .bamboo:return -10
        default:return 0
        }
    }
    static func saturation(_ theme:VineTheme)->Double{
        switch theme{case .minimal:return 0.4;case .winter,.moon:return 0.58;case .midnight:return 0.76;default:return 1}
    }
    static func available(_ name:String)->Bool{UIImage(named:name) != nil}
}

struct BotanicalAssetVine:View{
    let level:Int
    let theme:VineTheme
    let age:VineGrowth
    let density:Double
    let curvature:Double
    let node:VineNode
    let special:Bool
    let seed:Int
    let time:Double
    let animate:Bool
    let speed:Double
    let glow:Double
    var customLeaf:Color?=nil
    var customStem:Color?=nil
    var customBloom:Color?=nil
    var body:some View{
        Canvas{ctx,size in
            guard size.width>10,size.height>2 else{return}
            let rail=BotanicalAssets.rail(theme:theme,age:age)
            let source=ctx.resolve(Image(rail))
            let young=ctx.resolve(Image("botanical_young"))
            let corner=ctx.resolve(Image("botanical_corner"))
            let bud=ctx.resolve(Image("botanical_bud"))
            let bloom=ctx.resolve(Image(theme == .autumn ? "botanical_autumn_sprig":"botanical_flower"))
            let leaf=ctx.resolve(Image("botanical_leaf"))
            let dew=ctx.resolve(Image("botanical_dew"))
            let light=ctx.resolve(Image("botanical_light"))
            let root:CGFloat=18
            let stage=CGFloat(age.maturity)
            let w=CGFloat(13+15*stage)*CGFloat(max(0.75,min(1.22,density)))
            let h=size.height
            func sprite(_ context:GraphicsContext,_ image:GraphicsContext.ResolvedImage,_ center:CGPoint,_ width:CGFloat,_ angle:Double=0,_ opacity:Double=1,_ height:CGFloat?=nil){
                let ratio=image.size.height/max(1,image.size.width)
                let hh=height ?? width*ratio
                var layer=context;layer.translateBy(x:center.x,y:center.y);layer.rotate(by:.degrees(angle));layer.opacity=opacity
                layer.draw(image,in:CGRect(x:-width/2,y:-hh/2,width:width,height:hh))
            }
            func tint(_ context:GraphicsContext,_ color:Color?)->GraphicsContext{
                var layer=context
                if let color{
                    // Modulate a copy of the texture, preserving its photographic luminance.
                    layer.addFilter(.colorMultiply(color))
                }
                return layer
            }
            func stem(_ x:CGFloat,_ width:CGFloat,_ image:GraphicsContext.ResolvedImage,_ offset:Int){
                let ratio=image.size.height/max(1,image.size.width)
                let tile=max(84,width*ratio)
                let overlap=min(14,tile*0.10)
                let stride=max(1,tile-overlap)
                let count=max(1,Int(ceil(h/stride))+1)
                for i in 0..<count{
                    let jitter=CGFloat(NaturalSample.value(seed &+ i &+ offset,5)-0.5)*CGFloat(curvature)*2.5
                    let sway=animate ? CGFloat(sin(time*0.32*speed+Double(i)*0.81+Double(offset)))*0.7:0
                    let top=CGFloat(i)*stride-overlap/2
                    sprite(tint(ctx,customStem),image,CGPoint(x:x+jitter+sway,y:top+tile/2),width,0,1,tile)
                }
            }
            stem(root,w,source,0)
            if level==2 && age.hasBranches{stem(44,w*0.66,young,17)}
            let origin:CGFloat=level==2 && age.hasBranches ? 44:root
            let y=min(h-3,min(h*0.55,level==0 ? 35:level==1 ? 34:30))
            let arm=max(9,size.width-origin+3)
            if age.hasFlowers && node == .natural && theme != .minimal{
                sprite(tint(ctx,customBloom),corner,CGPoint(x:origin+arm*0.43,y:y-4),arm*1.12,0,0.96,arm*0.51)
            }else{
                // The original young vine is rotated to make a branch without flowers.
                sprite(tint(ctx,customStem),young,CGPoint(x:origin+arm*0.39,y:y),max(3.5,w*0.42),-90,0.95,arm)
            }
            let c=CGPoint(x:level==0 ? root:size.width-9,y:y)
            if age.hasFlowers && node == .natural && theme != .minimal && (special || level==0){
                sprite(tint(ctx,customBloom),bloom,c,special ? 22:17,-8,1)
            }else if age.hasBuds && node == .pearl{
                sprite(ctx,dew,c,6+stage*4)
            }else if age.hasBuds && node == .natural{
                sprite(tint(ctx,customBloom),bud,c,7+stage*3,-12)
            }else{
                sprite(tint(ctx,customLeaf),leaf,c,5+stage*5,level==0 ? -25:16)
            }
            if animate && age.hasBuds && special && glow>0{
                let p=0.32+0.25*sin(time*speed+Double(seed%17))
                sprite(ctx,light,CGPoint(x:c.x-2,y:c.y-8),14,0,p*glow)
            }
        }.clipped().hueRotation(.degrees(BotanicalAssets.hue(theme,young:!age.hasFlowers))).saturation(BotanicalAssets.saturation(theme)).accessibilityHidden(true)
    }
}

/// Real transparent sprites move on independent deterministic trajectories.
/// Backgrounded screens and Reduce Motion are handled by GardenWeather.
struct BotanicalAssetWeather:View{
    let effect:GardenAtmosphere
    let intensity:Double
    let time:Double
    var body:some View{
        Canvas{ctx,size in
            let strength=max(0,min(1,intensity)),w=size.width,h=size.height
            guard strength>0,w>0,h>0 else{return}
            let fly=ctx.resolve(Image("botanical_firefly"))
            let light=ctx.resolve(Image("botanical_light"))
            let bokeh=ctx.resolve(Image("botanical_bokeh"))
            let crystal=ctx.resolve(Image("botanical_snow_crystal"))
            let smallSnow=ctx.resolve(Image("botanical_snow_small"))
            let softSnow=ctx.resolve(Image("botanical_snow_soft"))
            let drop=ctx.resolve(Image("botanical_drop"))
            let petal=ctx.resolve(Image("botanical_petal"))
            let leaf=ctx.resolve(Image("botanical_leaf"))
            let count=Int(Double(effect == .rain ? 48:effect == .snow ? 44:effect == .firefly ? 12:effect == .gold ? 18:20)*strength)+1
            func draw(_ sprite:GraphicsContext.ResolvedImage,_ x:CGFloat,_ y:CGFloat,_ width:CGFloat,_ angle:Double,_ alpha:Double,_ stretch:CGFloat=1){
                guard alpha>0.012 else{return}
                let height=width*sprite.size.height/max(1,sprite.size.width)*stretch
                var layer=ctx;layer.translateBy(x:x,y:y);layer.rotate(by:.degrees(angle));layer.opacity=alpha
                layer.draw(sprite,in:CGRect(x:-width/2,y:-height/2,width:width,height:height))
            }
            for i in 0..<count{
                let a=NaturalSample.value(i,91),b=NaturalSample.value(i,34),d=NaturalSample.value(i,72),p=NaturalSample.value(i,14)*2*Double.pi
                let velocity=effect == .rain ? 0.45+d*0.55:0.025+d*0.07
                var x=CGFloat(NaturalSample.fraction(a+time*(effect == .rain ? 0.015:0.003)))*w
                var y=CGFloat(NaturalSample.fraction(b+time*velocity))*h
                x+=CGFloat(sin(time*(0.4+d*0.3)+p))*CGFloat(8+d*15)
                let alpha=(0.25+0.55*d)*min(1,0.4+strength)
                if effect == .firefly || effect == .gold{
                    x=CGFloat(a)*w+CGFloat(sin(time*0.42+p))*CGFloat(14+d*24)
                    y=CGFloat(b)*h+CGFloat(cos(time*0.32+p))*CGFloat(12+d*20)
                    let pulse=pow(max(0,0.5+0.5*sin(time*(0.5+d*0.55)+p)),1.7)
                    if effect == .firefly && i%7==0 && d>0.36{draw(fly,x,y,CGFloat(15+10*d),sin(time*0.55+p)*16,alpha*pulse)}
                    else if d>0.8{draw(bokeh,x,y,CGFloat(14+16*d),0,alpha*pulse*0.56)}
                    else{draw(light,x,y,CGFloat(4+9*d),0,alpha*pulse)}
                }else if effect == .snow{
                    let sprite=d>0.82 ? softSnow:(i%4==0 ? crystal:smallSnow)
                    draw(sprite,x,y,CGFloat(2.4+9*d),time*(7+d*13)+p*45,alpha)
                }else if effect == .rain{
                    draw(drop,x,y,CGFloat(0.8+d*1.6),-17,alpha*0.50,CGFloat(3.5+d*2.5))
                }else if effect == .petals{
                    draw(petal,x,y,CGFloat(4+8*d),time*(12+d*14)+p*52,alpha,CGFloat(0.60+0.40*abs(sin(time*0.65+p))))
                }else if effect == .leaves{
                    draw(leaf,x,y,CGFloat(6+9*d),time*(10+d*12)+p*48,alpha,CGFloat(0.65+0.35*abs(cos(time*0.55+p))))
                }
            }
        }.clipped().accessibilityHidden(true)
    }
}
