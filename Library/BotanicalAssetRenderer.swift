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
    var railOffset:CGFloat=0
    var trunkTheme:VineTheme?=nil
    var body:some View{
        Canvas{ctx,size in
            guard size.width>10,size.height>2 else{return}
            let rail=BotanicalAssets.rail(theme:trunkTheme ?? theme,age:age)
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
            let w=CGFloat(17+17*stage)*CGFloat(max(0.85,min(1.15,density)))
            let h=size.height
            func sprite(_ context:GraphicsContext,_ image:GraphicsContext.ResolvedImage,_ center:CGPoint,_ width:CGFloat,_ angle:Double=0,_ opacity:Double=1,_ height:CGFloat?=nil){
                let ratio=image.size.height/max(1,image.size.width)
                let hh=height ?? width*ratio
                var layer=context;layer.translateBy(x:center.x,y:center.y);layer.rotate(by:.degrees(angle));layer.opacity=opacity
                layer.draw(image,in:CGRect(x:-width/2,y:-hh/2,width:width,height:hh))
            }
            func tint(_ context:GraphicsContext,_ color:Color?,seasonal:Bool=false)->GraphicsContext{
                var layer=context
                if seasonal,let trunkTheme,theme != trunkTheme{
                    let delta=BotanicalAssets.hue(theme,young:!age.hasFlowers)-BotanicalAssets.hue(trunkTheme,young:!age.hasFlowers)
                    layer.addFilter(.hueRotation(.degrees(delta)))
                }
                if let color{
                    // Modulate a copy of the texture, preserving its photographic luminance.
                    layer.addFilter(.colorMultiply(color))
                }
                return layer
            }
            func tileHeight(_ width:CGFloat,_ image:GraphicsContext.ResolvedImage)->CGFloat{
                width*image.size.height/max(1,image.size.width)
            }
            // Each row samples one continuous image strip in content coordinates.
            // Use the same tile transform at every boundary; only the branch is local.
            func stem(_ x:CGFloat,_ width:CGFloat,_ image:GraphicsContext.ResolvedImage,_ offset:CGFloat){
                let tile=tileHeight(width,image)
                for part in BotanicalTilePlan.tiles(height:h,offset:offset,tileHeight:tile){
                    var layer=tint(ctx,customStem)
                    layer.translateBy(x:x,y:part.top+tile/2)
                    if part.mirrored{layer.scaleBy(x:1,y:-1)}
                    layer.draw(image,in:CGRect(x:-width/2,y:-tile/2,width:width,height:tile+0.35))
                }
            }
            func centerX(_ y:CGFloat,_ x:CGFloat,_ width:CGFloat,_ image:GraphicsContext.ResolvedImage,_ offset:CGFloat,_ name:String)->CGFloat{
                let tile=tileHeight(width,image)
                guard tile>0 else{return x}
                let position=(offset+y)/tile
                let index=Int(floor(position)),f=position-floor(position)
                let u=index%2 != 0 ? 1-f:f
                // Stem anchors sampled from the alpha silhouettes of the actual PNGs.
                let profile:[CGFloat]
                switch name{
                case "botanical_autumn":profile=[0.60,0.63,0.35,0.51,0.40,0.41,0.45,0.39,0.51,0.41,0.57,0.39,0.42]
                case "botanical_bloom":profile=[0.47,0.53,0.48,0.56,0.39,0.43,0.49,0.38,0.44,0.43,0.49,0.53,0.32]
                default:profile=[0.52,0.30,0.50,0.45,0.28,0.55,0.52,0.33,0.59,0.39,0.31,0.58,0.34]
                }
                let t=max(0,min(CGFloat(profile.count-1),u*CGFloat(profile.count-1)))
                let j=min(profile.count-2,Int(t)),frac=t-CGFloat(j)
                return x+(profile[j]*(1-frac)+profile[j+1]*frac-0.5)*width
            }
            stem(root,w,source,railOffset)
            if level==2 && age.hasBranches{stem(44,w*0.66,young,railOffset+24)}
            // More foliage and buds are separate textures, never baked into the young stem.
            let foliage=BotanicalTilePlan.extraLeaves(age:age,density:density)
            if foliage>0 && theme != .minimal{
                let spacing=max(37,CGFloat(220)/CGFloat(foliage))
                let first=Int(floor(railOffset/spacing)),last=Int(floor((railOffset+h)/spacing))
                for i in first...last{
                    let key=seed &+ i &* 7919
                    let y=CGFloat(i)*spacing-railOffset+spacing*0.38
                    guard y>4,y<h-4 else{continue}
                    let side:CGFloat=i%2==0 ? 1:-1
                    let scale=CGFloat(age.leafScale)
                    let leafWidth=(9+CGFloat(NaturalSample.value(key,7))*5)*scale
                    let sway=animate ? sin(time*speed*0.8+Double(i%97))*5:0
                    let x=centerX(y,root,w,source,railOffset,rail)
                    let angle=Double(side)*(-24-NaturalSample.value(key,18)*23)+sway
                    var layer=tint(ctx,customLeaf,seasonal:true)
                    layer.translateBy(x:x+side*leafWidth*0.30,y:y-2)
                    if side<0{layer.scaleBy(x:-1,y:1)}
                    sprite(layer,leaf,.zero,leafWidth,angle,0.95)
                    if age.hasBuds && i%5==0{
                        sprite(tint(ctx,customBloom,seasonal:true),bud,CGPoint(x:x+side*4,y:y+4),6+stage*4,angle,0.96)
                    }
                    if age.hasFlowers && i%age.bloomEvery==0 && (age.stage == .mature || special){
                        sprite(tint(ctx,customBloom,seasonal:true),bloom,CGPoint(x:x-side*4,y:y-2),13+stage*6,angle*0.4,0.98)
                    }
                }
            }
            let origin:CGFloat=level==2 && age.hasBranches ? 44:root
            let y=min(h-3,min(h*0.55,level==0 ? 35:level==1 ? 34:30))
            let anchor=centerX(y,origin,origin==root ? w:w*0.66,origin==root ? source:young,origin==root ? railOffset:railOffset+24,origin==root ? rail:"botanical_young")
            let arm=max(9,size.width-anchor+3)
            if age.hasFlowers && node == .natural && theme != .minimal{
                sprite(tint(ctx,customBloom,seasonal:true),corner,CGPoint(x:anchor+arm*0.43,y:y-4),arm*1.12,0,0.96,arm*0.51)
            }else{
                // Keep the texture aspect and rotate a smaller crop-like connector.
                sprite(tint(ctx,customStem,seasonal:true),young,CGPoint(x:anchor+arm*0.42,y:y),max(4,arm*0.145),-90,0.96,arm)
            }
            let c=CGPoint(x:level==0 ? root:size.width-9,y:y)
            if age.hasFlowers && node == .natural && theme != .minimal && (special || level==0){
                sprite(tint(ctx,customBloom,seasonal:true),bloom,c,special ? 22:17,-8,1)
            }else if age.hasBuds && node == .pearl{
                sprite(ctx,dew,c,6+stage*4)
            }else if age.hasBuds && node == .natural{
                sprite(tint(ctx,customBloom,seasonal:true),bud,c,7+stage*3,-12)
            }else{
                sprite(tint(ctx,customLeaf,seasonal:true),leaf,c,5+stage*5,level==0 ? -25:16)
            }
            if animate && age.hasBuds && special && glow>0{
                let p=0.32+0.25*sin(time*speed+Double(seed%17))
                sprite(ctx,light,CGPoint(x:c.x-2,y:c.y-8),14,0,p*glow)
            }
        }.clipped().hueRotation(.degrees(BotanicalAssets.hue(trunkTheme ?? theme,young:!age.hasFlowers))).saturation(BotanicalAssets.saturation(theme)).accessibilityHidden(true)
    }
}

/// Real transparent sprites move on independent deterministic trajectories.
/// Backgrounded screens and Reduce Motion are handled by GardenWeather.
struct BotanicalAssetWeather:View{
    let effect:GardenAtmosphere
    let intensity:Double
    let time:Double
    var speed:Double=0.8
    var wind:Double=0
    var particleScale:Double=1
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
            let count=Int(Double(effect == .rain ? 48:effect == .snow ? 44:effect == .firefly ? 12:effect == .gold ? 18:20)*strength*max(0.3,min(1,particleScale)))+1
            func draw(_ sprite:GraphicsContext.ResolvedImage,_ x:CGFloat,_ y:CGFloat,_ width:CGFloat,_ angle:Double,_ alpha:Double,_ stretch:CGFloat=1){
                guard alpha>0.012 else{return}
                let height=width*sprite.size.height/max(1,sprite.size.width)*stretch
                var layer=ctx;layer.translateBy(x:x,y:y);layer.rotate(by:.degrees(angle));layer.opacity=alpha
                layer.draw(sprite,in:CGRect(x:-width/2,y:-height/2,width:width,height:height))
            }
            for i in 0..<count{
                let a=NaturalSample.value(i,91),b=NaturalSample.value(i,34),d=NaturalSample.value(i,72),p=NaturalSample.value(i,14)*2*Double.pi
                let clock=time*max(0.25,min(1.8,speed))
                // Points per second, not a fixed fraction of the viewport.
                let velocity=effect == .rain ? 220+d*390:effect == .snow ? 14+d*41:12+d*32
                let track=NaturalSample.fraction(b+clock*velocity/Double(h+28))
                var x=CGFloat(NaturalSample.fraction(a+clock*(wind*0.045+(effect == .rain ? 0.012:0.001))))*w
                var y=CGFloat(track)*(h+28)-14
                x+=CGFloat(sin(clock*(0.4+d*0.3)+p))*CGFloat(8+d*15)
                let fade=effect == .firefly || effect == .gold ? 1:BotanicalTilePlan.edgeFade(track)
                let alpha=(0.25+0.55*d)*min(1,0.4+strength)*fade
                if effect == .firefly || effect == .gold{
                    x=CGFloat(a)*w+CGFloat(sin(clock*0.42+p))*CGFloat(14+d*24)
                    y=CGFloat(b)*h+CGFloat(cos(clock*0.32+p))*CGFloat(12+d*20)
                    let pulse=pow(max(0,0.5+0.5*sin(clock*(0.5+d*0.55)+p)),1.7)
                    if effect == .firefly && i%7==0 && d>0.36{draw(fly,x,y,CGFloat(15+10*d),sin(clock*0.55+p)*16,alpha*pulse)}
                    else if d>0.8{draw(bokeh,x,y,CGFloat(14+16*d),0,alpha*pulse*0.56)}
                    else{draw(light,x,y,CGFloat(4+9*d),0,alpha*pulse)}
                }else if effect == .snow{
                    let sprite=d>0.82 ? softSnow:(i%4==0 ? crystal:smallSnow)
                    draw(sprite,x,y,CGFloat(2.4+9*d),clock*(7+d*13)+p*45,alpha)
                }else if effect == .rain{
                    draw(drop,x,y,CGFloat(0.8+d*1.6),-17-wind*24,alpha*0.50,CGFloat(3.5+d*2.5))
                }else if effect == .petals{
                    draw(petal,x,y,CGFloat(4+8*d),clock*(12+d*14)+p*52,alpha,CGFloat(0.60+0.40*abs(sin(clock*0.65+p))))
                }else if effect == .leaves{
                    draw(leaf,x,y,CGFloat(6+9*d),clock*(10+d*12)+p*48,alpha,CGFloat(0.65+0.35*abs(cos(clock*0.55+p))))
                }
            }
        }.clipped().accessibilityHidden(true)
    }
}
