import SwiftUI

enum VineTheme:String,CaseIterable,Identifiable {
    case emerald="Emerald Vine",midnight="Midnight Vine",heritage="Golden Heritage",autumn="Autumn Memory",lotus="Lotus Garden",minimal="Minimal Vine"
    var id:String{rawValue}
    var stem:Color{
        switch self{
        case .emerald:return Color(red:0.25,green:0.66,blue:0.43)
        case .midnight:return Color(red:0.32,green:0.46,blue:0.42)
        case .heritage:return Color(red:0.82,green:0.63,blue:0.28)
        case .autumn:return Color(red:0.73,green:0.38,blue:0.21)
        case .lotus:return Color(red:0.40,green:0.65,blue:0.48)
        case .minimal:return Color(red:0.69,green:0.74,blue:0.68)
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
    var body:some View{
        Canvas{ctx,size in
            guard size.height>0 else{return}
            let h=size.height,root:CGFloat=18,branch=size.width-9,y=min(h*0.65,level==0 ? 35:level==1 ? 34:30)
            let amplitude=CGFloat(max(0.2,min(2,curvature)))*5
            func stem(_ x:CGFloat,_ color:Color,_ width:CGFloat){
                var p=Path();p.move(to:CGPoint(x:x,y:0))
                let segments=max(1,Int(ceil(h/42)))
                for i in 0..<segments{
                    let a=h*CGFloat(i)/CGFloat(segments),b=h*CGFloat(i+1)/CGFloat(segments),sign:CGFloat=i%2==0 ? 1:-1
                    p.addCurve(to:CGPoint(x:x,y:b),control1:CGPoint(x:x+amplitude*sign,y:a+(b-a)*0.35),control2:CGPoint(x:x-amplitude*sign,y:a+(b-a)*0.7))
                }
                ctx.stroke(p,with:.color(color.opacity(0.2)),style:StrokeStyle(lineWidth:width+3,lineCap:.round))
                ctx.stroke(p,with:.color(color),style:StrokeStyle(lineWidth:width,lineCap:.round))
                let interval=CGFloat(theme == .minimal ? 65:32)/CGFloat(max(0.35,min(1.8,density)))
                var pos:CGFloat=12;var index=0
                while pos<h-5{
                    let side:CGFloat=index%2==0 ? -1:1
                    leaf(ctx,base:CGPoint(x:x,y:pos),tip:CGPoint(x:x+side*(theme == .minimal ? 8:12),y:pos-10),color:theme.leaf.opacity(index%3==0 ? 0.75:1))
                    pos+=interval;index+=1
                }
            }
            stem(root,theme.stem,level==0 ? 2.6:1.8)
            if level==2{stem(45,theme.stem.opacity(0.68),1.2)}
            let origin:CGFloat=level==2 ? 45:root
            var arm=Path();arm.move(to:CGPoint(x:origin,y:max(0,y-13)))
            arm.addCurve(to:CGPoint(x:size.width,y:y),control1:CGPoint(x:origin+6,y:y+6),control2:CGPoint(x:branch-5,y:y-8))
            ctx.stroke(arm,with:.color(theme.stem),style:StrokeStyle(lineWidth:level==0 ? 2:1.6,lineCap:.round))
            if level>0 && theme != .minimal{leaf(ctx,base:CGPoint(x:branch-10,y:y),tip:CGPoint(x:branch-4,y:y-12),color:theme.leaf)}
            let center=CGPoint(x:level==0 ? root:branch,y:y),r:CGFloat=level==0 ? 6:4
            if node == .leaf || (node == .natural && level==1){
                leaf(ctx,base:CGPoint(x:center.x-4,y:center.y+5),tip:CGPoint(x:center.x+5,y:center.y-7),color:theme.bloom)
            }else if node == .pearl || theme == .minimal || level==2{
                ctx.fill(Path(ellipseIn:CGRect(x:center.x-r-3,y:center.y-r-3,width:(r+3)*2,height:(r+3)*2)),with:.color(theme.bloom.opacity(0.17)))
                ctx.fill(Path(ellipseIn:CGRect(x:center.x-r,y:center.y-r,width:r*2,height:r*2)),with:.color(theme.bloom))
                ctx.fill(Path(ellipseIn:CGRect(x:center.x-r*0.5,y:center.y-r*0.6,width:r*0.65,height:r*0.65)),with:.color(.white.opacity(0.8)))
            }else{
                let petals=theme == .lotus ? 7:5
                for i in 0..<petals{
                    let a=Double(i)*2*Double.pi/Double(petals),d=Double(r)*0.9
                    let p=CGPoint(x:center.x+CGFloat(cos(a)*d),y:center.y+CGFloat(sin(a)*d))
                    ctx.fill(Path(ellipseIn:CGRect(x:p.x-r*0.75,y:p.y-r*0.75,width:r*1.5,height:r*1.5)),with:.color(theme.bloom.opacity(0.88)))
                }
                ctx.fill(Path(ellipseIn:CGRect(x:center.x-2,y:center.y-2,width:4,height:4)),with:.color(theme.stem))
            }
        }.accessibilityHidden(true)
    }
    private func leaf(_ ctx:GraphicsContext,base:CGPoint,tip:CGPoint,color:Color){
        let dx=tip.x-base.x,dy=tip.y-base.y
        let wide:CGFloat=theme == .lotus ? 0.55:0.34
        var path=Path();path.move(to:base)
        path.addQuadCurve(to:tip,control:CGPoint(x:base.x+dx*0.48-dy*wide,y:base.y+dy*0.48+dx*wide))
        path.addQuadCurve(to:base,control:CGPoint(x:base.x+dx*0.52+dy*wide,y:base.y+dy*0.52-dx*wide));path.closeSubpath()
        ctx.fill(path,with:.color(color))
        var vein=Path();vein.move(to:base);vein.addLine(to:CGPoint(x:base.x+dx*0.84,y:base.y+dy*0.84))
        ctx.stroke(vein,with:.color(theme.stem.opacity(0.7)),lineWidth:0.55)
    }
}
struct VineCollectionView:View{
    @AppStorage("timeline.vine.theme") private var themeValue=VineTheme.emerald.rawValue
    @AppStorage("timeline.vine.density") private var density=1.0
    @AppStorage("timeline.vine.curvature") private var curvature=1.0
    @AppStorage("timeline.vine.node") private var nodeValue=VineNode.natural.rawValue
    @Environment(\.dismiss) private var dismiss
    private var theme:VineTheme{VineTheme(rawValue:themeValue) ?? .emerald}
    var body:some View{
        NavigationStack{
            ScrollView{
                VStack(alignment:.leading,spacing:18){
                    Text("Khu vườn ký ức").font(.system(size:32,design:.serif))
                    Text("Chọn dây leo, lá, hoa và nụ để cá nhân hóa cây thời gian. Vector sắc nét, không dùng ảnh nền raster.").font(.caption).foregroundStyle(.secondary)
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:10),count:2),spacing:12){
                        ForEach(VineTheme.allCases){item in
                            Button{withAnimation(.easeInOut(duration:0.25)){themeValue=item.rawValue}}label:{
                                VStack(alignment:.leading,spacing:7){
                                    HStack{
                                        VineRail(level:2,theme:item,density:density,curvature:curvature,node:VineNode(rawValue:nodeValue) ?? .natural).frame(width:75,height:112)
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
                    GroupBox("Tùy chỉnh dây leo"){
                        VStack(alignment:.leading,spacing:10){
                            Text("Mật độ lá").font(.caption)
                            Slider(value:$density,in:0.35...1.8)
                            Text("Độ uốn lượn").font(.caption)
                            Slider(value:$curvature,in:0.2...2)
                            Picker("Nút ký ức",selection:$nodeValue){ForEach(VineNode.allCases,id:\.self){Text($0.rawValue).tag($0.rawValue)}}
                            Button("Khôi phục mặc định"){themeValue=VineTheme.emerald.rawValue;density=1;curvature=1;nodeValue=VineNode.natural.rawValue}
                        }
                    }
                }.padding(16)
            }.background(night).navigationTitle("Bộ sưu tập dây leo").navigationBarTitleDisplayMode(.inline).toolbar{Button("Xong"){dismiss()}}
        }
    }
}
