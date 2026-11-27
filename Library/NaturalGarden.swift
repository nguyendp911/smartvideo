import SwiftUI
import UIKit

// Stable pseudo-random samples: every branch retains its own shape while scrolling.
enum NaturalSample{
    static func value(_ index:Int,_ salt:Int=0)->Double{
        var n=UInt64(truncatingIfNeeded:index) &* 0x9E3779B97F4A7C15 &+ UInt64(truncatingIfNeeded:salt)
        n ^= n >> 30;n = n &* 0xBF58476D1CE4E5B9;n ^= n >> 27;n = n &* 0x94D049BB133111EB;n ^= n >> 31
        return Double(n & 0xffffff)/16777215
    }
    static func seed(_ text:String)->Int{text.utf8.reduce(0){($0 &* 31) &+ Int($1)}}
    static func fraction(_ n:Double)->Double{n-floor(n)}
}
enum NaturalBotany{
    static func tone(_ color:Color,_ factor:Double)->Color{
        var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0
        guard UIColor(color).getRed(&r,green:&g,blue:&b,alpha:&a) else{return color}
        func adjust(_ x:CGFloat)->Double{factor<=1 ? Double(x)*factor:Double(x)+(1-Double(x))*(factor-1)}
        return Color(red:adjust(r),green:adjust(g),blue:adjust(b),opacity:Double(a))
    }
    static func stem(_ ctx:GraphicsContext,path:Path,color:Color,width:CGFloat){
        var shadow=ctx;shadow.addFilter(.shadow(color:.black.opacity(0.68),radius:1.4,x:1.2,y:1.5))
        shadow.stroke(path,with:.color(tone(color,0.48)),style:StrokeStyle(lineWidth:width+0.9,lineCap:.round,lineJoin:.round))
        ctx.stroke(path,with:.color(tone(color,0.82)),style:StrokeStyle(lineWidth:width,lineCap:.round,lineJoin:.round))
        var light=ctx;light.translateBy(x:-width*0.16,y:0)
        light.stroke(path,with:.color(tone(color,1.20).opacity(0.68)),style:StrokeStyle(lineWidth:max(0.3,width*0.28),lineCap:.round,lineJoin:.round))
    }
    static func leaf(_ ctx:GraphicsContext,base:CGPoint,tip:CGPoint,color:Color,shape:CGFloat,seed:Int,veins:Bool=true){
        let dx=tip.x-base.x,dy=tip.y-base.y
        let skew=CGFloat(NaturalSample.value(seed,9)*0.22-0.11)
        func p(_ a:CGFloat,_ b:CGFloat)->CGPoint{CGPoint(x:base.x+dx*a-dy*b,y:base.y+dy*a+dx*b)}
        var shapePath=Path();shapePath.move(to:base)
        shapePath.addCurve(to:tip,control1:p(0.12,shape*0.95),control2:p(0.66,shape*1.25+skew))
        shapePath.addCurve(to:base,control1:p(0.76,-shape*0.66),control2:p(0.22,-shape*0.83))
        shapePath.closeSubpath()
        var shadow=ctx;shadow.addFilter(.shadow(color:.black.opacity(0.48),radius:1.2,x:1,y:1))
        shadow.fill(shapePath,with:.color(tone(color,0.47)))
        ctx.fill(shapePath,with:.linearGradient(Gradient(stops:[.init(color:tone(color,0.48),location:0),.init(color:tone(color,0.90),location:0.36),.init(color:tone(color,1.22),location:0.53),.init(color:tone(color,0.72),location:1)]),startPoint:p(0.3,-shape),endPoint:p(0.7,shape)))
        var rib=Path();rib.move(to:base);rib.addQuadCurve(to:tip,control:p(0.55,skew))
        ctx.stroke(rib,with:.color(tone(color,1.28).opacity(0.58)),lineWidth:0.43)
        if veins && hypot(dx,dy)>9{
            for i in 1...4{
                let a=CGFloat(i)*0.16
                var vein=Path();vein.move(to:p(a,skew*a));vein.addQuadCurve(to:p(a+0.17,shape*0.52*sin(a*CGFloat.pi)),control:p(a+0.08,shape*0.14))
                vein.move(to:p(a,0));vein.addQuadCurve(to:p(a+0.19,-shape*0.42*sin(a*CGFloat.pi)),control:p(a+0.12,-shape*0.12))
                ctx.stroke(vein,with:.color(tone(color,1.3).opacity(0.25)),lineWidth:0.26)
            }
        }
    }
    static func flower(_ ctx:GraphicsContext,at center:CGPoint,r:CGFloat,color:Color,seed:Int,petals:Int){
        for i in 0..<petals{
            let angle=Double(i)*2*Double.pi/Double(petals)+NaturalSample.value(seed,21)*0.7
            let a=CGFloat(angle),dx=cos(a),dy=sin(a),length=r*(1.15+CGFloat(NaturalSample.value(seed+i,41))*0.45)
            let tip=CGPoint(x:center.x+dx*length,y:center.y+dy*length)
            leaf(ctx,base:center,tip:tip,color:tone(color,i%2==0 ? 1.12:0.88),shape:0.52,seed:seed+i,veins:false)
        }
        let inner=CGRect(x:center.x-r*0.33,y:center.y-r*0.33,width:r*0.66,height:r*0.66)
        ctx.fill(Path(ellipseIn:inner),with:.radialGradient(Gradient(colors:[.yellow.opacity(0.92),tone(color,0.6)]),center:center,startRadius:0,endRadius:r*0.4))
        for i in 0..<5{
            let angle=Double(i)*2*Double.pi/5
            let x=center.x+CGFloat(cos(angle))*r*0.21,y=center.y+CGFloat(sin(angle))*r*0.21
            ctx.fill(Path(ellipseIn:CGRect(x:x-0.35,y:y-0.35,width:0.7,height:0.7)),with:.color(.white.opacity(0.75)))
        }
    }
    static func dew(_ ctx:GraphicsContext,at p:CGPoint,r:CGFloat,color:Color){
        let rect=CGRect(x:p.x-r,y:p.y-r,width:2*r,height:2*r)
        ctx.fill(Path(ellipseIn:rect),with:.radialGradient(Gradient(stops:[.init(color:.white.opacity(0.93),location:0),.init(color:color.opacity(0.72),location:0.27),.init(color:color.opacity(0.15),location:0.75),.init(color:.black.opacity(0.42),location:1)]),center:CGPoint(x:p.x-r*0.33,y:p.y-r*0.38),startRadius:0,endRadius:r*1.5))
        ctx.stroke(Path(ellipseIn:rect),with:.color(.white.opacity(0.24)),lineWidth:0.35)
    }
    static func light(_ ctx:GraphicsContext,at p:CGPoint,r:CGFloat,color:Color,opacity:Double){
        let halo=r*5
        ctx.fill(Path(ellipseIn:CGRect(x:p.x-halo,y:p.y-halo,width:halo*2,height:halo*2)),with:.radialGradient(Gradient(stops:[.init(color:color.opacity(opacity*0.5),location:0),.init(color:color.opacity(opacity*0.15),location:0.28),.init(color:color.opacity(0),location:1)]),center:p,startRadius:0,endRadius:halo))
        ctx.fill(Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:2*r,height:2*r)),with:.radialGradient(Gradient(colors:[.white.opacity(opacity),color.opacity(opacity*0.55),color.opacity(0)]),center:p,startRadius:0,endRadius:r))
    }
}
struct NaturalVineCanvas:View{
    let level:Int
    let theme:VineTheme
    let stemColor:Color
    let leafColor:Color
    let bloomColor:Color
    let density:Double
    let curvature:Double
    let age:VineGrowth
    let node:VineNode
    let special:Bool
    let seed:Int
    let time:Double
    let animate:Bool
    let glow:Double
    var body:some View{
        Canvas{ctx,size in
            guard size.height>8,size.width>10 else{return}
            let h=size.height,root:CGFloat=18,edge=size.width-9
            let thickness=CGFloat(age.stemScale),scale=CGFloat(age.leafScale)
            let branchY=min(h-5,min(h*0.55,level==0 ? 35:level==1 ? 34:30))
            let amplitude=CGFloat(max(0.2,min(2,curvature)))*4.8
            let count=max(1,Int(ceil(h/67)))
            func xAt(_ y:CGFloat,_ x:CGFloat,_ salt:Int)->CGFloat{
                let p=y/max(h,1),wave=sin(p*CGFloat.pi*CGFloat(count))
                return x+wave*amplitude*(0.62+CGFloat(NaturalSample.value(seed,salt))*0.38)*sin(p*CGFloat.pi*1.4+0.7)
            }
            func drawStem(_ x:CGFloat,_ salt:Int,_ color:Color,_ width:CGFloat){
                var path=Path();path.move(to:CGPoint(x:x,y:0))
                let steps=max(3,Int(ceil(h/13)))
                for i in 1...steps{
                    let y=h*CGFloat(i)/CGFloat(steps)
                    let end=CGPoint(x:xAt(y,x,salt),y:y)
                    path.addQuadCurve(to:end,control:CGPoint(x:xAt(y-h/CGFloat(steps)*0.5,x,salt),y:y-h/CGFloat(steps)*0.5))
                }
                NaturalBotany.stem(ctx,path:path,color:color,width:width*thickness)
                let spacing=CGFloat(theme == .minimal ? 70:39)/CGFloat(max(0.14,min(1.8,density*age.leafDensity)))
                var pos:CGFloat=min(18,h*0.35);var i=0
                while pos<h-6{
                    let k=seed &+ salt &+ i &* 103
                    let side:CGFloat=i%2==0 ? -1:1
                    let length=(theme == .bamboo ? CGFloat(20):CGFloat(15))*scale*(0.64+CGFloat(NaturalSample.value(k,4))*0.58)
                    let angle=CGFloat(0.42+NaturalSample.value(k,7)*0.55)
                    let motion=animate ? CGFloat(sin(time*0.8+Double(i)*1.9+Double(salt%17)))*0.65*scale:0
                    let start=CGPoint(x:xAt(pos,x,salt),y:pos)
                    let joint=CGPoint(x:start.x+side*2.7*scale,y:pos-1.5*scale)
                    var stalk=Path();stalk.move(to:start);stalk.addQuadCurve(to:joint,control:CGPoint(x:start.x+side*1.6,y:pos+1))
                    NaturalBotany.stem(ctx,path:stalk,color:color,width:max(0.4,0.8*scale))
                    let tip=CGPoint(x:joint.x+side*length*cos(angle)+motion,y:joint.y-length*sin(angle))
                    NaturalBotany.leaf(ctx,base:joint,tip:tip,color:NaturalBotany.tone(leafColor,0.78+NaturalSample.value(k,8)*0.33),shape:theme == .bamboo ? 0.16:theme == .lotus ? 0.46:0.31,seed:k)
                    if age.hasBranches && i%3==1 && theme != .minimal{
                        let end=CGPoint(x:start.x-side*7*scale,y:pos-12*scale)
                        var shoot=Path();shoot.move(to:start);shoot.addCurve(to:end,control1:CGPoint(x:start.x-side*6,y:pos+1),control2:CGPoint(x:end.x+side*2,y:end.y+5))
                        NaturalBotany.stem(ctx,path:shoot,color:color,width:0.8*thickness)
                        NaturalBotany.leaf(ctx,base:end,tip:CGPoint(x:end.x-side*6*scale,y:end.y-7*scale),color:leafColor,shape:0.27,seed:k+19)
                    }
                    if age.hasBuds && i%age.bloomEvery==0 && theme != .minimal{
                        let c=CGPoint(x:start.x+side*6*scale,y:pos+4)
                        var stalk=Path();stalk.move(to:start);stalk.addQuadCurve(to:c,control:CGPoint(x:c.x,y:start.y))
                        NaturalBotany.stem(ctx,path:stalk,color:color,width:0.65)
                        if age.hasFlowers{NaturalBotany.flower(ctx,at:c,r:CGFloat(3.4*age.flowerScale),color:bloomColor,seed:k,petals:theme == .rose ? 8:5)}
                        else{NaturalBotany.leaf(ctx,base:c,tip:CGPoint(x:c.x+side*2,y:c.y-4),color:bloomColor,shape:0.55,seed:k,veins:false)}
                    }
                    if age.hasBuds && i%4==2{NaturalBotany.dew(ctx,at:CGPoint(x:joint.x+side*length*0.34,y:joint.y-length*0.35),r:0.95,color:leafColor)}
                    pos+=spacing*CGFloat(0.78+NaturalSample.value(k,12)*0.44);i+=1
                }
            }
            drawStem(root,3,stemColor,level==0 ? 3.1:2.5)
            let origin:CGFloat=level==2 && age.hasBranches ? 44:root
            if origin != root{drawStem(origin,17,NaturalBotany.tone(stemColor,0.72),1.75)}
            let start=CGPoint(x:xAt(max(0,branchY-11),origin,origin==root ? 3:17),y:max(0,branchY-11))
            var branch=Path();branch.move(to:start)
            branch.addCurve(to:CGPoint(x:size.width,y:branchY),control1:CGPoint(x:origin+7,y:branchY+7),control2:CGPoint(x:edge-9,y:branchY-6))
            NaturalBotany.stem(ctx,path:branch,color:stemColor,width:(level==0 ? 2.2:1.7)*thickness)
            let c=CGPoint(x:level==0 ? xAt(branchY,root,3):edge,y:branchY)
            let r:CGFloat=(level==0 ? 5:3.8)*scale
            if age.hasFlowers && node == .natural && theme != .minimal && (special || level==0){
                NaturalBotany.flower(ctx,at:c,r:r,color:bloomColor,seed:seed,petals:theme == .rose ? 9:theme == .lotus ? 7:5)
            }else if age.hasBuds && node == .pearl{
                NaturalBotany.dew(ctx,at:c,r:r,color:bloomColor)
            }else if age.hasBuds{
                NaturalBotany.leaf(ctx,base:c,tip:CGPoint(x:c.x+3*scale,y:c.y-8*scale),color:age.hasFlowers ? leafColor:bloomColor,shape:0.38,seed:seed)
            }else{
                NaturalBotany.leaf(ctx,base:c,tip:CGPoint(x:c.x+2*scale,y:c.y-6*scale),color:leafColor,shape:0.3,seed:seed)
            }
            if animate && age.hasBuds && special && glow>0{
                let flicker=0.45+0.23*sin(time*1.2+Double(seed%19))
                NaturalBotany.light(ctx,at:CGPoint(x:c.x+3,y:c.y-7),r:0.95,color:bloomColor,opacity:flicker*glow)
            }
        }.accessibilityHidden(true)
    }
}
struct NaturalWeatherCanvas:View{
    let effect:GardenAtmosphere
    let intensity:Double
    let time:Double
    var body:some View{
        Canvas{ctx,size in
            let strength=max(0,min(1,intensity)),w=size.width,h=size.height
            guard w>0,h>0,strength>0 else{return}
            let count=Int((effect == .rain ? 85:effect == .snow ? 58:effect == .firefly ? 14:28)*strength)+1
            for i in 0..<count{
                let a=NaturalSample.value(i,91),b=NaturalSample.value(i,34),depth=NaturalSample.value(i,72),phase=NaturalSample.value(i,14)*2*Double.pi
                let speed:Double=effect == .rain ? 0.62+depth*0.85:effect == .snow ? 0.035+depth*0.10:0.027+depth*0.055
                var y=CGFloat(NaturalSample.fraction(b+time*speed))*h
                var x=CGFloat(NaturalSample.fraction(a+time*(effect == .rain ? 0.025:0.002)))*w
                x+=CGFloat(sin(time*(0.45+depth*0.65)+phase))*CGFloat(6+depth*21)
                let opacity=(0.22+0.55*depth)*strength
                if effect == .firefly || effect == .gold{
                    y=CGFloat(b)*h+CGFloat(sin(time*(0.28+depth*0.4)+phase))*CGFloat(9+depth*18)
                    x=CGFloat(a)*w+CGFloat(sin(time*0.35+phase))*CGFloat(12+depth*30)
                    let pulse=pow(max(0,0.5+0.5*sin(time*(0.65+depth)+phase)),2)
                    let color:Color=effect == .gold ? Color(red:1,green:0.76,blue:0.37):Color(red:0.81,green:0.96,blue:0.46)
                    NaturalBotany.light(ctx,at:CGPoint(x:x,y:y),r:CGFloat(0.55+depth*1.15),color:color,opacity:opacity*pulse)
                }else if effect == .rain{
                    let length=CGFloat(9+depth*24),end=CGPoint(x:x-3-length*0.22,y:y+length)
                    var line=Path();line.move(to:CGPoint(x:x,y:y));line.addLine(to:end)
                    var layer=ctx;if depth>0.82{layer.addFilter(.blur(radius:0.8))}
                    layer.stroke(line,with:.linearGradient(Gradient(colors:[.clear,Color(red:0.69,green:0.81,blue:0.88).opacity(opacity*0.42),.clear]),startPoint:CGPoint(x:x,y:y),endPoint:end),style:StrokeStyle(lineWidth:CGFloat(0.4+depth*0.6),lineCap:.round))
                }else if effect == .snow{
                    let r=CGFloat(0.65+depth*2.3),p=CGPoint(x:x,y:y)
                    var layer=ctx;if depth>0.78{layer.addFilter(.blur(radius:CGFloat(0.75+depth)))}
                    if depth>0.35 && depth<0.78 && i%5==0{
                        var flake=Path()
                        for k in 0..<6{
                            let angle=Double(k)*Double.pi/3+time*0.12+phase
                            let dx=CGFloat(cos(angle)),dy=CGFloat(sin(angle)),tip=CGPoint(x:x+dx*r*1.5,y:y+dy*r*1.5)
                            flake.move(to:p);flake.addLine(to:tip)
                            for side in [-1.0,1.0]{
                                let fork=angle+side*2.3
                                flake.move(to:CGPoint(x:x+dx*r,y:y+dy*r));flake.addLine(to:CGPoint(x:x+dx*r+CGFloat(cos(fork))*r*0.48,y:y+dy*r+CGFloat(sin(fork))*r*0.48))
                            }
                        }
                        layer.stroke(flake,with:.color(.white.opacity(opacity)),style:StrokeStyle(lineWidth:0.47,lineCap:.round))
                    }else{
                        layer.fill(Path(ellipseIn:CGRect(x:x-r,y:y-r,width:r*2,height:r*2)),with:.radialGradient(Gradient(colors:[.white.opacity(opacity),.white.opacity(opacity*0.55),.clear]),center:p,startRadius:0,endRadius:r))
                    }
                }else{
                    let p=CGPoint(x:x,y:y),angle=time*(0.4+depth)+phase
                    let length=CGFloat(4+depth*6),tip=CGPoint(x:x+CGFloat(cos(angle))*length,y:y+CGFloat(sin(angle))*length)
                    let color:Color=effect == .petals ? Color(red:0.94,green:0.62,blue:0.73):Color(red:0.76,green:0.40,blue:0.19)
                    var layer=ctx;layer.opacity=opacity
                    if depth>0.88{layer.addFilter(.blur(radius:0.65))}
                    NaturalBotany.leaf(layer,base:p,tip:tip,color:color,shape:effect == .petals ? 0.50:0.29,seed:i,veins:effect == .leaves)
                }
            }
        }
    }
}
