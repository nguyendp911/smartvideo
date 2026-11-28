import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ProColorPanel:View{
    let url:URL?
    @Binding var recipe:CreativeRecipe
    let pickColor:()->Void
    @State private var mode="HSL"
    @State private var bandIndex=0
    @State private var channel="RGB"
    @State private var importing=false
    @State private var busy=false
    @State private var message=""
    private var pro:ProColorRecipe{recipe.proColor ?? ProColorRecipe()}
    private func bind<T>(_ key:WritableKeyPath<ProColorRecipe,T>)->Binding<T>{
        Binding(get:{pro[keyPath:key]},set:{var p=pro;p[keyPath:key]=$0;recipe.proColor=p})
    }
    private let names=["Đỏ","Cam","Vàng","Lục","Cyan","Lam","Tím","Hồng"]
    private let hues:[Double]=[0,0.075,0.16,0.33,0.50,0.62,0.75,0.90]
    private func ensureBand(_ i:Int){
        var p=pro
        while p.bands.count<=i && p.bands.count<8{p.bands.append(ProColorBand(hue:hues[p.bands.count]))}
        recipe.proColor=p;bandIndex=i
    }
    private func band(_ key:WritableKeyPath<ProColorBand,Double>,fallback:Double)->Binding<Double>{
        Binding(get:{pro.bands.indices.contains(bandIndex) ? pro.bands[bandIndex][keyPath:key]:fallback},set:{v in
            var p=pro
            guard p.bands.indices.contains(bandIndex) else{return}
            p.bands[bandIndex][keyPath:key]=v;recipe.proColor=p
        })
    }
    private var curveKey:WritableKeyPath<ProColorRecipe,ProCurve>{
        switch channel{case "R":return \.red;case "G":return \.green;case "B":return \.blue;default:return \.master}
    }
    private func curveValue(_ key:WritableKeyPath<ProCurve,Double>)->Binding<Double>{
        Binding(get:{pro[keyPath:curveKey][keyPath:key]},set:{v in var p=pro;p[keyPath:curveKey][keyPath:key]=v;recipe.proColor=p})
    }
    var body:some View{
        VStack(alignment:.leading,spacing:10){
            Picker("Công cụ màu",selection:$mode){ForEach(["HSL","Curves","Grading","Ảnh mẫu"],id:\.self){Text($0).tag($0)}}.pickerStyle(.segmented)
            switch mode{
            case "HSL":
                ScrollView(.horizontal,showsIndicators:false){
                    HStack(spacing:9){ForEach(0..<8,id:\.self){i in
                        Button{ensureBand(i)}label:{
                            VStack(spacing:5){Circle().fill(Color(hue:hues[i],saturation:0.78,brightness:0.92)).frame(width:28,height:28).overlay{Circle().strokeBorder(bandIndex==i ? .white:.clear,lineWidth:2)};Text(names[i]).font(.caption2)}
                        }.buttonStyle(.plain)
                    }}
                }
                HStack{
                    Button("Lấy màu trên ảnh",systemImage:"eyedropper"){pickColor()}.font(.caption)
                    if pro.bands.count>8{Button("Màu đã lấy"){bandIndex=8}.font(.caption).foregroundStyle(gold)}
                }
                if pro.bands.indices.contains(bandIndex){
                    if bandIndex==8{control("Phạm vi màu",band(\.width,fallback:0.1),0.025...0.25)}
                    control("Dịch sắc độ",band(\.shift,fallback:0),-0.16...0.16)
                    control("Bão hòa",band(\.saturation,fallback:0),-1...1)
                    control("Độ sáng màu",band(\.luminance,fallback:0),-1...1)
                    Button("Đặt lại dải màu"){var p=pro;let h=p.bands[bandIndex].hue;p.bands[bandIndex]=ProColorBand(hue:h);recipe.proColor=p}.font(.caption)
                }else{Text("Chọn một dải màu để chỉnh.").font(.caption).foregroundStyle(.secondary)}
            case "Curves":
                Picker("Kênh",selection:$channel){ForEach(["RGB","R","G","B"],id:\.self){Text($0).tag($0)}}.pickerStyle(.segmented)
                Canvas{ctx,size in
                    let curve=pro[keyPath:curveKey]
                    var grid=Path()
                    for i in 0...4{let x=size.width*CGFloat(i)/4,y=size.height*CGFloat(i)/4;grid.move(to:CGPoint(x:x,y:0));grid.addLine(to:CGPoint(x:x,y:size.height));grid.move(to:CGPoint(x:0,y:y));grid.addLine(to:CGPoint(x:size.width,y:y))}
                    ctx.stroke(grid,with:.color(.white.opacity(0.12)),lineWidth:1)
                    var line=Path()
                    for i in 0...64{let x=Double(i)/64,p=CGPoint(x:size.width*x,y:size.height*(1-curve.value(x)));if i==0{line.move(to:p)}else{line.addLine(to:p)}}
                    ctx.stroke(line,with:.color(channel=="R" ? .red:channel=="G" ? .green:channel=="B" ? .blue:gold),lineWidth:2)
                }.frame(height:108).background(.black.opacity(0.35))
                control("Vùng tối",curveValue(\.low),0...1)
                control("Trung gian",curveValue(\.mid),0...1)
                control("Vùng sáng",curveValue(\.high),0...1)
                Button("Đặt lại kênh"){var p=pro;p[keyPath:curveKey]=ProCurve();recipe.proColor=p}.font(.caption)
            case "Grading":
                Text("Phối màu ấm/lạnh riêng từng vùng sáng tối.").font(.caption).foregroundStyle(.secondary)
                control("Bóng tối",bind(\.shadowColor),-1...1)
                control("Trung gian",bind(\.midColor),-1...1)
                control("Vùng sáng",bind(\.highlightColor),-1...1)
            default:
                Text("Khớp thống kê màu RGB và tương phản ảnh mẫu ở mức giới hạn. Không sao chép nội dung.").font(.caption).foregroundStyle(.secondary)
                Button("Nhập ảnh mẫu từ Tệp",systemImage:"photo.badge.plus"){importing=true}.disabled(url==nil || busy)
                if busy{ProgressView()}
                if pro.reference != nil{
                    control("Mức ảnh hưởng",Binding(get:{pro.reference?.strength ?? 0.5},set:{v in var p=pro;p.reference?.strength=v;recipe.proColor=p}),0...1)
                    Button("Bỏ màu ảnh mẫu"){var p=pro;p.reference=nil;recipe.proColor=p}.font(.caption)
                }
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Button("Đặt lại màu chuyên sâu"){var p=ProColorRecipe();p.skinSmooth=pro.skinSmooth;p.skinRadius=pro.skinRadius;recipe.proColor=p}.font(.caption)
        }.padding(10).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
        .fileImporter(isPresented:$importing,allowedContentTypes:[.image]){result in
            do{
                guard let source=url else{return}
                let target=try result.get(),access=target.startAccessingSecurityScopedResource()
                defer{if access{target.stopAccessingSecurityScopedResource()}}
                let bytes=try Data(contentsOf:target,options:.mappedIfSafe)
                guard bytes.count<=50_000_000,let cg=PhotoEngine.thumb(bytes,limit:512),let stats=ProColorStatistics.analyze(cg) else{throw CameraError.unreadable}
                busy=true;message=""
                Task{
                    let original=await Task.detached(priority:.utility){ProColorStatistics.url(source)}.value
                    busy=false
                    guard !Task.isCancelled,source==url,let original else{message="Không đọc được ảnh nguồn.";return}
                    var p=pro;p.reference=ProReference(source:original,target:stats);recipe.proColor=p;message="Đã tính bảng màu từ ảnh mẫu."
                }
            }catch{message=error.localizedDescription}
        }
        .onChange(of:pro.bands.count){_,n in if n>8{bandIndex=8}else{bandIndex=min(bandIndex,max(0,n-1))}}
    }
    private func control(_ title:String,_ value:Binding<Double>,_ range:ClosedRange<Double>)->some View{
        VStack(spacing:3){HStack{Text(title);Spacer();Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2)))).monospacedDigit().foregroundStyle(gold)}.font(.caption);Slider(value:value,in:range)}
    }
}
struct ProRetouchPanel:View{
    @Binding var recipe:CreativeRecipe
    let openMask:()->Void
    private var pro:ProColorRecipe{recipe.proColor ?? ProColorRecipe()}
    var body:some View{
        VStack(alignment:.leading,spacing:8){
            Label("Frequency Separation",systemImage:"person.crop.circle").font(.headline)
            Text("Chỉnh lớp màu tần số thấp, giữ lại chi tiết tần số cao. Dùng mặt nạ khuôn mặt hoặc cọ sửa da đã chọn; không tự xóa mụn.").font(.caption).foregroundStyle(.secondary)
            Button("Chọn vùng da / khuôn mặt",action:openMask)
            Text("Cường độ \(Int(pro.skinSmooth*100))%").font(.caption)
            Slider(value:Binding(get:{pro.skinSmooth},set:{v in var p=pro;p.skinSmooth=v;recipe.proColor=p}),in:0...1)
            Text("Bán kính làm đều").font(.caption)
            Slider(value:Binding(get:{pro.skinRadius},set:{v in var p=pro;p.skinRadius=v;recipe.proColor=p}),in:0.001...0.012)
            Button("Tắt làm đều da"){var p=pro;p.skinSmooth=0;recipe.proColor=p}.font(.caption)
        }.padding(10).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
    }
}
struct ProQualityPanel:View{
    let result:UIImage?
    let url:URL?
    let ready:Bool
    @State private var stats:ProColorStatistics?
    @State private var original:ProColorStatistics?
    @State private var busy=false
    var body:some View{
        VStack(alignment:.leading,spacing:8){
            Label("Quality Inspector",systemImage:"checkmark.shield").font(.headline)
            Button("Đo ảnh đang xem",systemImage:"chart.bar.xaxis"){
                guard let cg=result?.cgImage,let url else{return}
                busy=true
                Task{
                    let pair=await Task.detached(priority:.utility){(ProColorStatistics.analyze(cg),ProColorStatistics.url(url))}.value
                    stats=pair.0;original=pair.1;busy=false
                }
            }.disabled(!ready || busy)
            if busy{ProgressView()}
            if let s=stats{
                metric("Pixel sát trắng",s.white,original?.white)
                metric("Pixel sát đen",s.black,original?.black)
                Text("Chỉ số biên ảnh: \(s.edge.formatted(.number.precision(.fractionLength(3))))").font(.caption.monospacedDigit())
                if s.white>0.03{Label("Kiểm tra vùng sáng và màu bão hòa.",systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange)}
                if s.black>0.05{Label("Kiểm tra chi tiết vùng tối.",systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange)}
            }
            Text("Đo từ preview thu nhỏ. Chỉ số biên phụ thuộc nội dung; không phải điểm sắc nét tuyệt đối. Số liệu có thể khác khi cắt ảnh.").font(.caption2).foregroundStyle(.secondary)
        }.padding(10).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
    }
    private func metric(_ title:String,_ value:Double,_ previous:Double?)->some View{
        HStack{Text(title);Spacer();if let previous{Text("\(previous*100,specifier:"%.1f")% →")};Text("\(value*100,specifier:"%.1f")%").foregroundStyle(gold)}.font(.caption.monospacedDigit())
    }
}
