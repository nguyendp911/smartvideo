import SwiftUI
import CoreImage
import UIKit

enum PresetCollection:String,CaseIterable,Identifiable{
    case beach="Biển & Resort",travel="Du lịch",mountain="Đà Lạt & Núi",portrait="Chân dung",city="Phố & Đêm",sunset="Hoàng hôn",food="Ẩm thực & Café",film="Film & Editorial"
    var id:String{rawValue}
}
struct PremiumGrade{
    let ev:Double,contrast:Double,sat:Double,warm:Double,high:Double,shadow:Double,blueHue:Double,blueSat:Double,greenHue:Double,greenSat:Double,fade:Double
    init(_ e:Double,_ c:Double,_ s:Double,_ w:Double,_ h:Double,_ sh:Double,_ bh:Double,_ bs:Double,_ gh:Double,_ gs:Double,_ f:Double){
        ev=e;contrast=c;sat=s;warm=w;high=h;shadow=sh;blueHue=bh;blueSat=bs;greenHue=gh;greenSat=gs;fade=f
    }
}
struct PremiumPreset:Identifiable{
    let id:String;let name:String;let collection:PresetCollection;let subtitle:String;let grade:PremiumGrade
    init(_ id:String,_ name:String,_ collection:PresetCollection,_ subtitle:String,_ grade:PremiumGrade){self.id=id;self.name=name;self.collection=collection;self.subtitle=subtitle;self.grade=grade}
}
enum PremiumPresets{
    static let all:[PremiumPreset]=[
        .init("sea.01","Maldives Aqua",.beach,"Nước xanh ngọc, cát sáng",.init(0.06,1.04,1.04,0.02,0.17,0.06,-0.045,0.23,-0.02,-0.04,0)),
        .init("sea.02","Mediterranean Blue",.beach,"Biển xanh sâu, trắng sạch",.init(0.02,1.12,1.02,-0.07,0.15,0.02,0.028,0.25,0,-0.08,0)),
        .init("sea.03","Bali Resort",.beach,"Nắng ấm, xanh dịu",.init(0.08,1.02,0.98,0.12,0.20,0.1,-0.035,0.10,-0.03,0.08,0.012)),
        .init("sea.04","Pearl Coast",.beach,"Pastel, cát trắng kem",.init(0.14,0.92,0.91,0.04,0.23,0.12,-0.02,0.05,0,-0.13,0.025)),
        .init("sea.05","Ocean Editorial",.beach,"Biển lạnh, tương phản sang",.init(-0.06,1.16,0.96,-0.08,0.18,0.04,0.02,0.19,-0.02,-0.12,0.006)),
        .init("travel.01","European Summer",.travel,"Kiến trúc sáng, màu kem",.init(0.12,1.04,0.95,0.09,0.22,0.1,-0.015,0.06,0.015,-0.12,0.014)),
        .init("travel.02","Japan Diary",.travel,"Màu nhẹ, trong trẻo",.init(0.1,0.95,0.88,-0.02,0.20,0.14,0.01,-0.08,0.02,-0.15,0.025)),
        .init("travel.03","Hội An Gold",.travel,"Vàng cổ, tường ấm",.init(0.02,1.07,1.03,0.19,0.15,0.06,0,-0.12,-0.02,-0.1,0.006)),
        .init("travel.04","Indochine Travel",.travel,"Xanh rêu, màu gỗ",.init(-0.04,1.10,0.94,0.10,0.18,0.08,-0.02,-0.1,-0.035,-0.15,0.014)),
        .init("mountain.01","Đà Lạt Sương",.mountain,"Sương mềm, xanh lạnh",.init(0.12,0.92,0.91,-0.08,0.16,0.14,0.018,-0.05,0.035,-0.1,0.032)),
        .init("mountain.02","Pine Forest",.mountain,"Thông sâu, xanh rêu",.init(-0.04,1.13,0.96,-0.04,0.21,0.08,0,-0.14,0.04,0.12,0.008)),
        .init("mountain.03","Highland Morning",.mountain,"Sáng sớm, lá xanh trong",.init(0.16,1.01,1.01,0.03,0.16,0.11,-0.02,0.03,-0.02,0.12,0.01)),
        .init("mountain.04","Cloud Valley",.mountain,"Mây trắng, núi xa dịu",.init(0.08,0.98,0.91,-0.04,0.27,0.12,0.025,0.05,0,-0.16,0.016)),
        .init("portrait.01","Soft Skin",.portrait,"Da tự nhiên, nền dịu",.init(0.12,0.94,0.94,0.04,0.20,0.10,0,-0.10,0,-0.20,0.016)),
        .init("portrait.02","Luxury Portrait",.portrait,"Chân dung đậm chiều sâu",.init(0.02,1.13,0.95,0.04,0.20,0.06,0.02,-0.12,0.015,-0.21,0.005)),
        .init("portrait.03","Cream Editorial",.portrait,"Trắng kem, mềm sáng",.init(0.15,0.95,0.86,0.09,0.23,0.11,0,-0.18,0,-0.23,0.025)),
        .init("portrait.04","Rose Morning",.portrait,"Hồng nhẹ, dịu dàng",.init(0.07,0.96,0.95,0.04,0.18,0.1,0.02,-0.07,-0.02,-0.16,0.02)),
        .init("city.01","Tokyo Neon",.city,"Xanh tím, đèn phố",.init(0.05,1.12,1.08,-0.12,0.30,0.11,0.035,0.15,0.01,-0.17,0.006)),
        .init("city.02","Saigon After Dark",.city,"Phố đêm, đèn vàng ấm",.init(0.06,1.08,0.98,0.09,0.27,0.12,-0.035,0.10,-0.02,-0.16,0.012)),
        .init("city.03","Urban Concrete",.city,"Xi măng, màu trung tính",.init(0,1.16,0.78,-0.03,0.16,0.06,0.015,-0.08,0,-0.25,0.008)),
        .init("city.04","Rainy Cinema",.city,"Mưa lạnh, bóng xanh",.init(0.02,1.08,0.90,-0.13,0.26,0.10,-0.02,0.12,0.01,-0.18,0.016)),
        .init("sunset.01","Golden Hour",.sunset,"Nắng chiều vàng mật",.init(0.03,1.04,1.02,0.23,0.26,0.09,-0.02,-0.08,-0.01,-0.1,0.006)),
        .init("sunset.02","Amber Romance",.sunset,"Cam mật ong, bóng dịu",.init(-0.04,1.09,0.94,0.18,0.23,0.12,0,-0.16,-0.015,-0.13,0.018)),
        .init("sunset.03","Pink Horizon",.sunset,"Hồng chiều, xanh tím",.init(0.04,0.98,0.96,0.03,0.23,0.10,0.045,0.06,0,-0.18,0.018)),
        .init("food.01","Cafe Mocha",.food,"Nâu cà phê, kem",.init(0.03,1.08,0.90,0.14,0.19,0.08,0,-0.24,0,-0.2,0.012)),
        .init("food.02","Fresh Table",.food,"Thức ăn trong, tươi",.init(0.10,1.03,1.07,0.04,0.16,0.08,0,-0.12,-0.015,0.09,0)),
        .init("food.03","Japanese Cafe",.food,"Ánh sáng sạch, nâu gỗ",.init(0.12,0.96,0.92,0.02,0.18,0.12,0,-0.11,0,-0.14,0.02)),
        .init("film.01","Portra Inspired",.film,"Chất film ấm, da mềm",.init(0.05,0.99,0.91,0.09,0.20,0.12,0.01,-0.1,-0.02,-0.15,0.025)),
        .init("film.02","Classic Chrome",.film,"Tông báo ảnh, xanh trầm",.init(-0.02,1.10,0.86,-0.03,0.16,0.07,0.01,-0.07,0.03,-0.16,0.012)),
        .init("film.03","Teal & Amber",.film,"Xanh cyan, vàng ấm",.init(-0.03,1.13,0.98,0.07,0.20,0.07,-0.065,0.12,0.035,-0.04,0.008)),
        .init("film.04","Vintage 1978",.film,"Đen nâng nhẹ, màu cũ",.init(0.04,0.96,0.82,0.16,0.21,0.14,-0.01,-0.16,-0.025,-0.18,0.048)),
        .init("film.05","Silver Editorial",.film,"Đen trắng tinh tế",.init(0.02,1.14,0,-0.01,0.19,0.09,0,0,0,0,0.012))
    ]
    static func find(_ id:String?)->PremiumPreset?{all.first{$0.id==id}}
}
enum PremiumColorEngine{
    private static let cache=NSCache<NSString,NSData>()
    private static func clamp(_ x:Double)->Double{min(1,max(0,x))}
    private static func distance(_ a:Double,_ b:Double)->Double{let d=abs(a-b);return min(d,1-d)}
    private static func weight(_ h:Double,_ center:Double,_ radius:Double)->Double{
        let x=clamp(1-distance(h,center)/radius);return x*x*(3-2*x)
    }
    static func cube(_ p:PremiumPreset,strength:Double,dimension:Int=32)->Data{
        let q=min(100,max(0,Int((strength*100).rounded())))
        let key="\(p.id):\(q):\(dimension)" as NSString
        if let found=cache.object(forKey:key){return found as Data}
        let t=Double(q)/100,g=p.grade,n=Double(dimension-1)
        var data=[Float]();data.reserveCapacity(dimension*dimension*dimension*4)
        for b in 0..<dimension{for gr in 0..<dimension{for r in 0..<dimension{
            let red=Double(r)/n,green=Double(gr)/n,blue=Double(b)/n
            let maxv=max(red,green,blue),minv=min(red,green,blue),d=maxv-minv
            var hue=0.0
            if d>0.00001{
                if maxv==red{hue=(green-blue)/d/6}
                else if maxv==green{hue=((blue-red)/d+2)/6}
                else{hue=((red-green)/d+4)/6}
                if hue<0{hue+=1}
            }
            let sat=maxv>0 ? d/maxv:0
            // Feathered selective hue ranges; orange/red skin hues are not targeted by blue/green corrections.
            let bw=weight(hue,0.57,0.18)*min(1,sat*3),gw=weight(hue,0.30,0.15)*min(1,sat*3)
            let shifted=hue+(g.blueHue*bw+g.greenHue*gw)*t
            let h=shifted-floor(shifted),s=clamp(sat*(1+(g.blueSat*bw+g.greenSat*gw)*t))
            let z=h*6,i=Int(floor(z)),f=z-Double(i),v=maxv
            let a=v*(1-s),m=v*(1-s*f),k=v*(1-s*(1-f))
            let rgb:(Double,Double,Double)
            switch i%6{case 0:rgb=(v,k,a);case 1:rgb=(m,v,a);case 2:rgb=(a,v,k);case 3:rgb=(a,m,v);case 4:rgb=(k,a,v);default:rgb=(v,a,m)}
            data.append(Float(clamp(rgb.0+(1-rgb.0)*g.fade*t)))
            data.append(Float(clamp(rgb.1+(1-rgb.1)*g.fade*t)))
            data.append(Float(clamp(rgb.2+(1-rgb.2)*g.fade*t)))
            data.append(1)
        }}}
        let bytes=data.withUnsafeBytes{Data($0)}
        cache.countLimit=24;cache.totalCostLimit=16*1024*1024
        cache.setObject(bytes as NSData,forKey:key,cost:bytes.count)
        return bytes
    }
    static func apply(_ image:CIImage,id:String?,strength:Double)->CIImage{
        guard let p=PremiumPresets.find(id),strength>0 else{return image}
        let t=min(1,max(0,strength)),g=p.grade
        var result=image.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:g.ev*t])
        result=result.applyingFilter("CIHighlightShadowAdjust",parameters:["inputHighlightAmount":1-g.high*t,"inputShadowAmount":g.shadow*t])
        result=result.applyingFilter("CIColorControls",parameters:[kCIInputContrastKey:1+(g.contrast-1)*t,kCIInputSaturationKey:1+(g.sat-1)*t])
        if g.warm != 0{result=result.applyingFilter("CITemperatureAndTint",parameters:["inputNeutral":CIVector(x:6500,y:0),"inputTargetNeutral":CIVector(x:6500+g.warm*t*2200,y:0)])}
        return result.applyingFilter("CIColorCubeWithColorSpace",parameters:["inputCubeDimension":32,"inputCubeData":cube(p,strength:t),"inputColorSpace":CGColorSpace(name:CGColorSpace.sRGB)!])
    }
}
struct PremiumPresetPanel:View{
    let url:URL?
    @Binding var recipe:CreativeRecipe
    @State private var category=PresetCollection.beach
    @State private var previews=[String:UIImage]()
    @AppStorage("premium.favorite.presets") private var saved=Data()
    @State private var favorites=Set<String>()
    @State private var onlyFavorites=false
    private var items:[PremiumPreset]{onlyFavorites ? PremiumPresets.all.filter{favorites.contains($0.id)}:PremiumPresets.all.filter{$0.collection==category}}
    var body:some View{
        VStack(alignment:.leading,spacing:11){
            HStack{Text("PREMIUM COLOR COLLECTION").font(.system(size:10,weight:.semibold,design:.monospaced)).foregroundStyle(gold);Spacer();Button{onlyFavorites.toggle()}label:{Image(systemName:onlyFavorites ? "heart.fill":"heart")}.buttonStyle(.plain)}
            ScrollView(.horizontal,showsIndicators:false){HStack{ForEach(PresetCollection.allCases){c in Button{category=c;onlyFavorites=false}label:{Text(c.rawValue).font(.caption.weight(.medium)).padding(9).background(category==c && !onlyFavorites ? gold.opacity(0.24):.white.opacity(0.055),in:Capsule())}.buttonStyle(.plain)}}}
            ScrollView(.horizontal,showsIndicators:false){LazyHStack(spacing:10){
                Button{recipe.premiumID=nil}label:{VStack{if let url{DiskImage(url:url,limit:220).scaledToFill().frame(width:100,height:114).clipped().clipShape(RoundedRectangle(cornerRadius:9))};Text("Gốc").font(.caption)}.frame(width:104)}.buttonStyle(.plain)
                ForEach(items){p in
                    Button{recipe.premiumID=p.id;if recipe.premiumStrength==nil{recipe.premiumStrength=0.8}}label:{
                        VStack(alignment:.leading,spacing:5){
                            ZStack(alignment:.topTrailing){
                                if let image=previews[p.id]{Image(uiImage:image).resizable().scaledToFill()}
                                else{RoundedRectangle(cornerRadius:9).fill(.white.opacity(0.06)).overlay{ProgressView().controlSize(.small)}}
                            }.frame(width:108,height:114).clipped().clipShape(RoundedRectangle(cornerRadius:9))
                                .overlay{RoundedRectangle(cornerRadius:9).strokeBorder(recipe.premiumID==p.id ? gold:.clear,lineWidth:2)}
                            Text(p.name).font(.caption.weight(.semibold)).lineLimit(1)
                            Text(p.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }.frame(width:108,alignment:.leading)
                    }.buttonStyle(.plain).contextMenu{Button(favorites.contains(p.id) ? "Bỏ yêu thích":"Yêu thích",systemImage:"heart"){if favorites.contains(p.id){favorites.remove(p.id)}else{favorites.insert(p.id)};saved=(try? JSONEncoder().encode(favorites)) ?? Data()}}
                }
            }}
            if let p=PremiumPresets.find(recipe.premiumID){
                HStack{Text(p.name).font(.caption.weight(.semibold));Spacer();Text("\(Int((recipe.premiumStrength ?? 0.8)*100))%").font(.caption.monospacedDigit()).foregroundStyle(gold)}
                Slider(value:Binding(get:{recipe.premiumStrength ?? 0.8},set:{recipe.premiumStrength=$0}),in:0...1)
                Text(p.subtitle+" · màu chọn lọc, không phải nhận diện vật thể.").font(.caption2).foregroundStyle(.secondary)
            }
        }.onAppear{favorites=(try? JSONDecoder().decode(Set<String>.self,from:saved)) ?? []}
        .task(id:(url?.path ?? "")+category.rawValue+String(onlyFavorites)+favorites.sorted().joined()){
            previews=[:];guard let url else{return}
            let list=items
            for p in list{
                if Task.isCancelled{return}
                var r=CreativeRecipe();r.premiumID=p.id;r.premiumStrength=0.8
                let bytes=await PhotoPreviewWorker.shared.photo(url,recipe:r,maxSize:260,thumbnail:true)
                let image=bytes.flatMap{UIImage(data:$0)}
                if Task.isCancelled{return}
                if let image{previews[p.id]=image}
            }
        }
    }
}
