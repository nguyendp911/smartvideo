import SwiftUI
import UIKit

enum VineTheme:String,CaseIterable,Identifiable {
    case emerald="Emerald Vine",midnight="Midnight Vine",heritage="Golden Heritage",autumn="Autumn Memory",lotus="Lotus Garden",minimal="Minimal Vine",sakura="Sakura Vine",rose="Rose Romance",wisteria="Wisteria Dream",bamboo="Vietnamese Bamboo",jasmine="White Jasmine",moon="Moonlight Vine",winter="Crystal Winter",neon="Neon Fantasy",dragon="Royal Dragon"
    var id:String{rawValue}
    var stem:Color{
        switch self{
        case .emerald:return Color(red:0.25,green:0.66,blue:0.43)
        case .midnight:return Color(red:0.32,green:0.46,blue:0.42)
        case .heritage:return Color(red:0.82,green:0.63,blue:0.28)
        case .autumn:return Color(red:0.73,green:0.38,blue:0.21)
        case .lotus:return Color(red:0.40,green:0.65,blue:0.48)
        case .minimal:return Color(red:0.69,green:0.74,blue:0.68)
        case .sakura:return Color(red:0.58,green:0.32,blue:0.43)
        case .rose:return Color(red:0.38,green:0.54,blue:0.31)
        case .wisteria:return Color(red:0.44,green:0.34,blue:0.62)
        case .bamboo:return Color(red:0.43,green:0.58,blue:0.27)
        case .jasmine:return Color(red:0.35,green:0.63,blue:0.4)
        case .moon:return Color(red:0.38,green:0.54,blue:0.76)
        case .winter:return Color(red:0.45,green:0.68,blue:0.78)
        case .neon:return Color(red:0.53,green:0.24,blue:0.83)
        case .dragon:return Color(red:0.63,green:0.32,blue:0.16)
        }
    }
    var leaf:Color{
        switch self{
        case .emerald:return Color(red:0.32,green:0.82,blue:0.51)
        case .midnight:return Color(red:0.34,green:0.60,blue:0.48)
        case .heritage:return Color(red:0.94,green:0.78,blue:0.44)
        case .autumn:return Color(red:0.94,green:0.57,blue:0.25)
        case .lotus:return Color(red:0.54,green:0.79,blue:0.55)
        case .minimal:return stem
        case .sakura:return Color(red:0.89,green:0.57,blue:0.69)
        case .rose:return Color(red:0.44,green:0.75,blue:0.4)
        case .wisteria:return Color(red:0.65,green:0.55,blue:0.86)
        case .bamboo:return Color(red:0.66,green:0.84,blue:0.36)
        case .jasmine:return Color(red:0.56,green:0.77,blue:0.48)
        case .moon:return Color(red:0.57,green:0.75,blue:0.96)
        case .winter:return Color(red:0.71,green:0.9,blue:0.99)
        case .neon:return Color(red:0.24,green:0.82,blue:0.97)
        case .dragon:return Color(red:0.93,green:0.64,blue:0.27)
        }
    }
    var bloom:Color{
        switch self{
        case .emerald:return Color(red:0.88,green:0.95,blue:0.68)
        case .midnight:return gold
        case .heritage:return Color(red:1,green:0.89,blue:0.58)
        case .autumn:return Color(red:0.93,green:0.35,blue:0.23)
        case .lotus:return Color(red:0.96,green:0.62,blue:0.73)
        case .minimal:return .white
        case .sakura:return Color(red:1,green:0.82,blue:0.88)
        case .rose:return Color(red:0.94,green:0.3,blue:0.43)
        case .wisteria:return Color(red:0.83,green:0.67,blue:0.98)
        case .bamboo:return Color(red:0.92,green:0.8,blue:0.45)
        case .jasmine:return Color(red:0.99,green:0.98,blue:0.85)
        case .moon:return Color(red:0.83,green:0.91,blue:1)
        case .winter:return Color(red:0.94,green:0.98,blue:1)
        case .neon:return Color(red:0.99,green:0.34,blue:0.77)
        case .dragon:return Color(red:1,green:0.86,blue:0.44)
        }
    }
    var description:String{
        switch self{
        case .emerald:return "Lá xanh ngọc, nụ kem và gân lá mềm"
        case .midnight:return "Dây xanh trầm, hoa champagne"
        case .heritage:return "Nhánh ánh kim, hoa vàng cổ điển"
        case .autumn:return "Lá phong cách mùa thu, quả đỏ"
        case .lotus:return "Cánh sen hồng, lá tròn cách điệu"
        case .minimal:return "Nét mảnh, lá thưa, nụ nhỏ"
        case .sakura:return "Hoa anh đào hồng"
        case .rose:return "Hoa hồng đỏ"
        case .wisteria:return "Tử đằng tím"
        case .bamboo:return "Tre Việt, lá dài"
        case .jasmine:return "Hoa nhài trắng"
        case .moon:return "Ánh trăng bạc"
        case .winter:return "Sương và băng"
        case .neon:return "Tím xanh phát sáng"
        case .dragon:return "Vàng son Á Đông"
        }
    }
}
enum VineNode:String,CaseIterable{case natural="Hoa và nụ",leaf="Lá",pearl="Giọt sương"}
struct VineRail:View {
    let level:Int
    let theme:VineTheme
    var density:Double=1
    var curvature:Double=1
    var node:VineNode = .natural
    var useCustom=false
    var growth:VineGrowth?=nil
    var specialBloom=false
    @AppStorage("garden.live") private var live=true
    @AppStorage("garden.speed") private var speed=0.7
    @AppStorage("garden.glow") private var glow=0.6
    @AppStorage("garden.custom") private var custom=false
    @AppStorage("garden.stem") private var stemHex="438F65"
    @AppStorage("garden.leaf") private var leafHex="81C68A"
    @AppStorage("garden.bloom") private var bloomHex="E5C78E"
    @Environment(\.accessibilityReduceMotion) private var reduced
    private var stemColor:Color{useCustom && custom ? GardenColor.decode(stemHex):theme.stem}
    private var leafColor:Color{useCustom && custom ? GardenColor.decode(leafHex):theme.leaf}
    private var bloomColor:Color{useCustom && custom ? GardenColor.decode(bloomHex):theme.bloom}
    var body:some View{
        TimelineView(.animation(minimumInterval:0.1,paused:!live || reduced)){clock in
            drawing(time:live && !reduced ? clock.date.timeIntervalSinceReferenceDate:0)
        }.accessibilityHidden(true)
    }
    private func drawing(time:Double)->some View{
        Canvas{ctx,size in
            guard size.height>0 else{return}
            let h=size.height,root:CGFloat=18,branch=size.width-9,y=min(h*0.65,level==0 ? 35:level==1 ? 34:30)
            let phase=time*speed
            let amplitude=CGFloat(max(0.2,min(2,curvature)))*5
            let sway=CGFloat(sin(phase))*1.6
            let age=growth ?? VineGrowth(days:365)
            let stemFactor=CGFloat(age.stemScale),leafFactor=CGFloat(age.leafScale)
            let maturity=age.maturity
            func stem(_ x:CGFloat,_ color:Color,_ width:CGFloat){
                var p=Path();p.move(to:CGPoint(x:x,y:0))
                let segments=max(1,Int(ceil(h/42)))
                for i in 0..<segments{
                    let a=h*CGFloat(i)/CGFloat(segments),b=h*CGFloat(i+1)/CGFloat(segments),sign:CGFloat=i%2==0 ? 1:-1
                    p.addCurve(to:CGPoint(x:x,y:b),control1:CGPoint(x:x+amplitude*sign,y:a+(b-a)*0.35),control2:CGPoint(x:x-amplitude*sign,y:a+(b-a)*0.7))
                }
                ctx.stroke(p,with:.color(color.opacity(0.2*maturity)),style:StrokeStyle(lineWidth:width*stemFactor+2*maturity,lineCap:.round))
                ctx.stroke(p,with:.color(color),style:StrokeStyle(lineWidth:width*stemFactor,lineCap:.round))
                let interval=CGFloat(theme == .minimal ? 65:32)/CGFloat(max(0.15,min(1.8,density*age.leafDensity)))
                var pos:CGFloat=12;var index=0
                while pos<h-5{
                    let side:CGFloat=index%2==0 ? -1:1
                    leaf(ctx,base:CGPoint(x:x,y:pos),tip:CGPoint(x:x+side*(theme == .minimal ? 8:12)*leafFactor+sway*leafFactor,y:pos-10*leafFactor),color:leafColor.opacity(index%3==0 ? 0.75:1))
                    if age.hasBranches && index%3==1{
                        let start=CGPoint(x:x,y:pos+5),end=CGPoint(x:x+side*9*leafFactor,y:pos-10*leafFactor)
                        var shoot=Path();shoot.move(to:start);shoot.addQuadCurve(to:end,control:CGPoint(x:x+side*4,y:pos-2));ctx.stroke(shoot,with:.color(stemColor.opacity(0.85)),lineWidth:0.85)
                        leaf(ctx,base:end,tip:CGPoint(x:end.x-side*5,y:end.y-7*leafFactor),color:leafColor)
                    }
                    if age.hasBuds && index%age.bloomEvery==0 && theme != .minimal{
                        let c=CGPoint(x:x+side*6*leafFactor,y:pos+5),r:CGFloat=age.hasFlowers ? CGFloat(3.2*age.flowerScale):1.65
                        if age.hasFlowers{for i in 0..<5{let a=Double(i)*2*Double.pi/5;let q=CGPoint(x:c.x+CGFloat(cos(a))*r,y:c.y+CGFloat(sin(a))*r);ctx.fill(Path(ellipseIn:CGRect(x:q.x-r*0.65,y:q.y-r*0.65,width:r*1.3,height:r*1.3)),with:.color(bloomColor.opacity(0.85)))}}
                        ctx.fill(Path(ellipseIn:CGRect(x:c.x-r*0.65,y:c.y-r*0.65,width:r*1.3,height:r*1.3)),with:.color(bloomColor))
                    }
                    pos+=interval;index+=1
                }
            }
            stem(root,stemColor,level==0 ? 2.6:1.8)
            if level==2 && age.hasBranches{stem(45,stemColor.opacity(0.68),1.2)}
            let origin:CGFloat=level==2 && age.hasBranches ? 45:root
            var arm=Path();arm.move(to:CGPoint(x:origin,y:max(0,y-13)))
            arm.addCurve(to:CGPoint(x:size.width,y:y),control1:CGPoint(x:origin+6,y:y+6),control2:CGPoint(x:branch-5,y:y-8))
            ctx.stroke(arm,with:.color(stemColor),style:StrokeStyle(lineWidth:(level==0 ? 2:1.6)*stemFactor,lineCap:.round))
            if level>0 && theme != .minimal && age.hasBranches{leaf(ctx,base:CGPoint(x:branch-10,y:y),tip:CGPoint(x:branch-4,y:y-12),color:leafColor)}
            if live && !reduced && glow>0 && age.hasBuds{
                for i in 0..<(age.hasFlowers ? 3:1){
                    let t=phase+Double(i)*2.1
                    let p=CGPoint(x:root+CGFloat(sin(t))*12,y:h*CGFloat(i+1)/4+CGFloat(cos(t*0.8))*7)
                    let opacity=(0.3+0.3*sin(t))*glow
                    ctx.fill(Path(ellipseIn:CGRect(x:p.x-3,y:p.y-3,width:6,height:6)),with:.color(bloomColor.opacity(opacity)))
                    ctx.fill(Path(ellipseIn:CGRect(x:p.x-1,y:p.y-1,width:2,height:2)),with:.color(bloomColor.opacity(0.9)))
                }
            }
            let center=CGPoint(x:level==0 ? root:branch,y:y),r:CGFloat=(level==0 ? 6:4)*leafFactor
            if !age.hasBuds{
                ctx.fill(Path(ellipseIn:CGRect(x:center.x-r*0.6,y:center.y-r*0.6,width:r*1.2,height:r*1.2)),with:.color(leafColor))
            }else if node == .leaf || (node == .natural && level==1 && !specialBloom){
                leaf(ctx,base:CGPoint(x:center.x-4,y:center.y+5),tip:CGPoint(x:center.x+5,y:center.y-7),color:bloomColor)
            }else if node == .pearl || theme == .minimal || !age.hasFlowers || (level==2 && !specialBloom){
                ctx.fill(Path(ellipseIn:CGRect(x:center.x-r-3,y:center.y-r-3,width:(r+3)*2,height:(r+3)*2)),with:.color(bloomColor.opacity(0.17)))
                ctx.fill(Path(ellipseIn:CGRect(x:center.x-r,y:center.y-r,width:r*2,height:r*2)),with:.color(bloomColor))
                ctx.fill(Path(ellipseIn:CGRect(x:center.x-r*0.5,y:center.y-r*0.6,width:r*0.65,height:r*0.65)),with:.color(.white.opacity(0.8)))
            }else{
                let petals=theme == .lotus || theme == .wisteria ? 7:(theme == .rose ? 9:5)
                for i in 0..<petals{
                    let a=Double(i)*2*Double.pi/Double(petals),d=Double(r)*0.9
                    let p=CGPoint(x:center.x+CGFloat(cos(a)*d),y:center.y+CGFloat(sin(a)*d))
                    ctx.fill(Path(ellipseIn:CGRect(x:p.x-r*0.75,y:p.y-r*0.75,width:r*1.5,height:r*1.5)),with:.color(bloomColor.opacity(0.88)))
                }
                ctx.fill(Path(ellipseIn:CGRect(x:center.x-2,y:center.y-2,width:4,height:4)),with:.color(stemColor))
            }
        }.accessibilityHidden(true)
    }
    private func leaf(_ ctx:GraphicsContext,base:CGPoint,tip:CGPoint,color:Color){
        let dx=tip.x-base.x,dy=tip.y-base.y
        let wide:CGFloat=theme == .lotus ? 0.55:(theme == .bamboo ? 0.13:0.34)
        var path=Path();path.move(to:base)
        path.addQuadCurve(to:tip,control:CGPoint(x:base.x+dx*0.48-dy*wide,y:base.y+dy*0.48+dx*wide))
        path.addQuadCurve(to:base,control:CGPoint(x:base.x+dx*0.52+dy*wide,y:base.y+dy*0.52-dx*wide));path.closeSubpath()
        ctx.fill(path,with:.color(color))
        var vein=Path();vein.move(to:base);vein.addLine(to:CGPoint(x:base.x+dx*0.84,y:base.y+dy*0.84))
        ctx.stroke(vein,with:.color(stemColor.opacity(0.7)),lineWidth:0.55)
    }
}
struct VineCollectionView:View{
    @ObservedObject private var life=LifeArchive.shared
    @AppStorage("timeline.vine.theme") private var themeValue=VineTheme.emerald.rawValue
    @AppStorage("timeline.vine.density") private var density=1.0
    @AppStorage("timeline.vine.curvature") private var curvature=1.0
    @AppStorage("timeline.vine.node") private var nodeValue=VineNode.natural.rawValue
    @State private var showDesigner=false
    @Environment(\.dismiss) private var dismiss
    private var theme:VineTheme{VineTheme(rawValue:themeValue) ?? .emerald}
    var body:some View{
        NavigationStack{
            ScrollView{
                VStack(alignment:.leading,spacing:18){
                    Text("Khu vườn ký ức").font(.system(size:32,design:.serif))
                    Text("Chọn dây leo, lá, hoa và nụ để cá nhân hóa cây thời gian. Vector sắc nét, không dùng ảnh nền raster.").font(.caption).foregroundStyle(.secondary)
                    VineGrowthCard(life:life)
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:10),count:2),spacing:12){
                        ForEach(VineTheme.allCases){item in
                            Button{withAnimation(.easeInOut(duration:0.25)){themeValue=item.rawValue}}label:{
                                VStack(alignment:.leading,spacing:7){
                                    HStack{
                                        VineRail(level:2,theme:item,density:density,curvature:curvature,node:VineNode(rawValue:nodeValue) ?? .natural,growth:VineGrowth(days:life.gardenDays)).frame(width:75,height:112)
                                        VStack(alignment:.leading,spacing:5){
                                            RoundedRectangle(cornerRadius:5).fill(item.leaf.opacity(0.18)).frame(height:27).overlay{Image(systemName:"leaf.fill").foregroundStyle(item.leaf)}
                                            RoundedRectangle(cornerRadius:5).fill(item.bloom.opacity(0.14)).frame(height:35).overlay{Image(systemName:"photo").foregroundStyle(item.bloom)}
                                        }
                                    }
                                    Text(item.rawValue).font(.system(.headline,design:.serif)).lineLimit(2)
                                    Text(item.description).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                }.padding(10).frame(maxWidth:.infinity,alignment:.leading)
                                    .background(.white.opacity(0.055),in:RoundedRectangle(cornerRadius:13))
                                    .overlay{RoundedRectangle(cornerRadius:13).strokeBorder(theme==item ? item.bloom:.clear,lineWidth:1.5)}
                                    .overlay(alignment:.topTrailing){if theme==item{Image(systemName:"checkmark.circle.fill").foregroundStyle(item.bloom).padding(6)}}
                            }.buttonStyle(.plain)
                        }
                    }
                    Button("Vine Designer & hiệu ứng",systemImage:"paintpalette"){showDesigner=true}.buttonStyle(.borderedProminent)
                    GroupBox("Tùy chỉnh dây leo"){
                        VStack(alignment:.leading,spacing:10){
                            Text("Mật độ lá · theo tuổi cây").font(.caption)
                            Slider(value:$density,in:0.35...1.8)
                            Text("Độ uốn lượn").font(.caption)
                            Slider(value:$curvature,in:0.2...2)
                            Picker("Nút ký ức",selection:$nodeValue){ForEach(VineNode.allCases,id:\.self){Text($0.rawValue).tag($0.rawValue)}}
                            Button("Khôi phục mặc định"){themeValue=VineTheme.emerald.rawValue;density=1;curvature=1;nodeValue=VineNode.natural.rawValue}
                        }
                    }
                }.padding(16)
            }.background(night).navigationTitle("Bộ sưu tập dây leo").navigationBarTitleDisplayMode(.inline).toolbar{Button("Xong"){dismiss()}}.sheet(isPresented:$showDesigner){GardenDesigner()}
        }
    }
}

enum GardenColor{
    static func decode(_ hex:String)->Color{
        let n=UInt32(hex,radix:16) ?? 0x81C68A
        return Color(red:Double((n>>16)&255)/255,green:Double((n>>8)&255)/255,blue:Double(n&255)/255)
    }
    static func encode(_ color:Color)->String{
        var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0
        UIColor(color).getRed(&r,green:&g,blue:&b,alpha:&a)
        return String(format:"%02X%02X%02X",Int(max(0,min(1,r))*255),Int(max(0,min(1,g))*255),Int(max(0,min(1,b))*255))
    }
}
enum GardenAtmosphere:String,CaseIterable{
    case none="Tắt",firefly="Đom đóm",petals="Cánh hoa",rain="Mưa",snow="Tuyết",leaves="Lá rơi",gold="Bụi vàng"
}
struct GardenWeather:View{
    let effect:GardenAtmosphere
    let intensity:Double
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body:some View{
        if effect != .none && !reduced && intensity>0{
            TimelineView(.animation(minimumInterval:1/20)){clock in
                Canvas{ctx,size in
                    let t=clock.date.timeIntervalSinceReferenceDate
                    for i in 0..<Int(12+28*intensity){
                        let seed=Double(i)*0.61803398875
                        let base=seed-floor(seed)
                        let speed=effect == .rain ? 0.6:0.065+Double(i%5)*0.015
                        let raw=t*speed+Double(i)*0.137
                        let y=CGFloat(raw-floor(raw))*size.height
                        let x=CGFloat(base)*size.width+CGFloat(sin(t*0.65+Double(i)))*12
                        let r:CGFloat=effect == .snow ? 2.5:3
                        let color:Color=effect == .gold ? gold:effect == .petals ? .pink:effect == .leaves ? .orange:effect == .firefly ? .yellow:.white
                        if effect == .rain{
                            var p=Path();p.move(to:CGPoint(x:x,y:y));p.addLine(to:CGPoint(x:x-3,y:y+16))
                            ctx.stroke(p,with:.color(.white.opacity(0.16*intensity)),lineWidth:0.7)
                        }else if effect == .petals || effect == .leaves{
                            let rect=CGRect(x:x-r,y:y-r,width:r*2,height:r*3)
                            ctx.fill(Path(ellipseIn:rect),with:.color(color.opacity(0.4*intensity)))
                        }else{
                            let opacity=effect == .firefly ? (0.25+0.25*sin(t+Double(i)))*intensity:0.35*intensity
                            ctx.fill(Path(ellipseIn:CGRect(x:x-r,y:y-r,width:r*2,height:r*2)),with:.color(color.opacity(opacity)))
                        }
                    }
                }
            }.allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}
struct GardenDesigner:View{
    @ObservedObject private var life=LifeArchive.shared
    @AppStorage("timeline.vine.theme") private var theme=VineTheme.emerald.rawValue
    @AppStorage("garden.live") private var live=true
    @AppStorage("garden.speed") private var speed=0.7
    @AppStorage("garden.glow") private var glow=0.6
    @AppStorage("garden.custom") private var custom=false
    @AppStorage("garden.stem") private var stem="438F65"
    @AppStorage("garden.leaf") private var leaf="81C68A"
    @AppStorage("garden.bloom") private var bloom="E5C78E"
    @AppStorage("garden.seasonal") private var seasonal=false
    @AppStorage("garden.weather") private var weather=GardenAtmosphere.none.rawValue
    @AppStorage("garden.intensity") private var intensity=0.6
    @AppStorage("garden.paper") private var paper="Đêm"
    @AppStorage("garden.haptics") private var haptics=true
    @AppStorage("garden.saved") private var saved=Data()
    @AppStorage("timeline.vine.density") private var density=1.0
    @AppStorage("timeline.vine.curvature") private var curvature=1.0
    @AppStorage("timeline.vine.node") private var node=VineNode.natural.rawValue
    @Environment(\.dismiss) private var dismiss
    struct Preset:Codable,Identifiable{
        var id=UUID();var name:String;var theme:String;var custom:Bool;var stem:String;var leaf:String;var bloom:String;var live:Bool;var speed:Double;var glow:Double;var seasonal:Bool;var weather:String;var intensity:Double;var paper:String;var density:Double?=nil;var curvature:Double?=nil;var node:String?=nil;var haptics:Bool?=nil
    }
    @State private var name=""
    @State private var presets=[Preset]()
    var body:some View{
        NavigationStack{
            Form{
                Section("Xem trước"){
                    HStack{VineRail(level:2,theme:VineTheme(rawValue:theme) ?? .emerald,density:density,curvature:curvature,node:VineNode(rawValue:node) ?? .natural,useCustom:true,growth:VineGrowth(days:life.gardenDays)).frame(width:78,height:150);VStack(alignment:.leading){Text("Một ngày đáng nhớ").font(.system(.title2,design:.serif));Text("Ký ức nở hoa").font(.caption);RoundedRectangle(cornerRadius:12).fill(GardenColor.decode(leaf).opacity(0.2)).frame(height:65)}}
                        .padding().background(GardenBackground.color(paper)).overlay{GardenWeather(effect:GardenAtmosphere(rawValue:weather) ?? .none,intensity:intensity)}
                }
                Section("Dây leo sống"){
                    Toggle("Chuyển động lá & hạt sáng",isOn:$live)
                    Text("Tốc độ");Slider(value:$speed,in:0.1...2)
                    Text("Ánh sáng");Slider(value:$glow,in:0...1)
                    Toggle("Màu theo mùa quy ước Bắc bán cầu",isOn:$seasonal)
                    Text("Mật độ lá");Slider(value:$density,in:0.35...1.8)
                    Text("Độ uốn lượn");Slider(value:$curvature,in:0.2...2)
                    Picker("Kiểu nút",selection:$node){ForEach(VineNode.allCases,id:\.self){Text($0.rawValue).tag($0.rawValue)}}
                    Toggle("Tùy phối màu",isOn:$custom)
                    if custom{
                        ColorPicker("Thân",selection:Binding(get:{GardenColor.decode(stem)},set:{stem=GardenColor.encode($0)}),supportsOpacity:false)
                        ColorPicker("Lá",selection:Binding(get:{GardenColor.decode(leaf)},set:{leaf=GardenColor.encode($0)}),supportsOpacity:false)
                        ColorPicker("Hoa",selection:Binding(get:{GardenColor.decode(bloom)},set:{bloom=GardenColor.encode($0)}),supportsOpacity:false)
                    }
                }
                Section("Môi trường"){
                    Picker("Hiệu ứng",selection:$weather){ForEach(GardenAtmosphere.allCases,id:\.self){Text($0.rawValue).tag($0.rawValue)}}
                    Slider(value:$intensity,in:0...1)
                    Picker("Nền",selection:$paper){ForEach(["Đêm","Giấy cổ","Nhung","Rừng","Ánh kim"],id:\.self){Text($0).tag($0)}}
                    Toggle("Phản hồi rung",isOn:$haptics)
                }
                Section("Bộ phối cá nhân"){
                    TextField("Tên bộ phối",text:$name)
                    Button("Lưu bộ phối"){presets.append(Preset(name:name,theme:theme,custom:custom,stem:stem,leaf:leaf,bloom:bloom,live:live,speed:speed,glow:glow,seasonal:seasonal,weather:weather,intensity:intensity,paper:paper,density:density,curvature:curvature,node:node,haptics:haptics));persist();name=""}.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    ForEach(presets){p in Button(p.name){theme=p.theme;custom=p.custom;stem=p.stem;leaf=p.leaf;bloom=p.bloom;live=p.live;speed=p.speed;glow=p.glow;seasonal=p.seasonal;weather=p.weather;intensity=p.intensity;paper=p.paper;density=p.density ?? 1;curvature=p.curvature ?? 1;node=p.node ?? VineNode.natural.rawValue;haptics=p.haptics ?? true}}
                        .onDelete{presets.remove(atOffsets:$0);persist()}
                }
            }.navigationTitle("Vine Designer").toolbar{Button("Xong"){dismiss()}}
        }.onAppear{presets=(try? JSONDecoder().decode([Preset].self,from:saved)) ?? []}
    }
    private func persist(){if let data=try? JSONEncoder().encode(presets){saved=data}}
}
enum GardenBackground{
    static func color(_ name:String)->Color{
        switch name{case "Giấy cổ":return Color(red:0.26,green:0.20,blue:0.15);case "Nhung":return Color(red:0.22,green:0.09,blue:0.19);case "Rừng":return Color(red:0.07,green:0.20,blue:0.14);case "Ánh kim":return Color(red:0.23,green:0.19,blue:0.11);default:return night}
    }
    static func season(_ key:String,fallback:VineTheme)->VineTheme{
        guard key.count>=7,let month=Int(key.dropFirst(5).prefix(2)) else{return fallback}
        switch month{case 3...5:return .sakura;case 6...8:return .emerald;case 9...11:return .autumn;default:return .winter}
    }
}
