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
    var branchKey="preview"
    var continuous=false
    var trunkTheme:VineTheme?=nil
    @AppStorage("garden.quality") private var quality=GardenRenderQuality.automatic.rawValue
    @Environment(\.gardenLowPower) private var lowPower
    @AppStorage("garden.live") private var live=true
    @AppStorage("garden.speed") private var speed=0.7
    @AppStorage("garden.glow") private var glow=0.6
    @AppStorage("garden.custom") private var custom=false
    @AppStorage("garden.stem") private var stemHex="438F65"
    @AppStorage("garden.leaf") private var leafHex="81C68A"
    @AppStorage("garden.bloom") private var bloomHex="E5C78E"
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var scene
    private var stemColor:Color{useCustom && custom ? GardenColor.decode(stemHex):theme.stem}
    private var leafColor:Color{useCustom && custom ? GardenColor.decode(leafHex):theme.leaf}
    private var bloomColor:Color{useCustom && custom ? GardenColor.decode(bloomHex):theme.bloom}
    var body:some View{
        if continuous{
            GeometryReader{geometry in
                animated(offset:geometry.frame(in:.named("gardenContent")).minY)
            }.accessibilityHidden(true)
        }else{animated(offset:0).accessibilityHidden(true)}
    }
    private func animated(offset:CGFloat)->some View{
        let active=live && !reduced && scene == .active
        let rate=(GardenRenderQuality(rawValue:quality) ?? .automatic).rate(lowPower:lowPower)
        return TimelineView(.animation(minimumInterval:1/min(15,rate),paused:!active)){clock in
            BotanicalAssetVine(level:level,theme:theme,age:growth ?? VineGrowth(days:365),density:density,curvature:curvature,node:node,special:specialBloom,seed:NaturalSample.seed(branchKey),time:active ? clock.date.timeIntervalSinceReferenceDate:0,animate:active,speed:speed,glow:glow,customLeaf:useCustom && custom ? leafColor:nil,customStem:useCustom && custom ? stemColor:nil,customBloom:useCustom && custom ? bloomColor:nil,railOffset:offset,trunkTheme:trunkTheme)
        }
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
                    Text("Dây leo và hiệu ứng dùng ảnh thực vật PNG trong suốt. 15 bảng màu chia sẻ bộ texture xanh non, hoa trắng và mùa thu. Dây leo lớn dần theo tuổi cây.").font(.caption).foregroundStyle(.secondary)
                    VineGrowthCard(life:life)
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:10),count:2),spacing:12){
                        ForEach(VineTheme.allCases){item in
                            Button{withAnimation(.easeInOut(duration:0.25)){themeValue=item.rawValue}}label:{
                                VStack(alignment:.leading,spacing:7){
                                    HStack{
                                        VineRail(level:2,theme:item,density:density,curvature:curvature,node:VineNode(rawValue:nodeValue) ?? .natural,growth:VineGrowth(days:life.gardenDays)).frame(width:75,height:112)
                                        VStack(alignment:.leading,spacing:5){
                                            Image("botanical_leaf").resizable().scaledToFit().hueRotation(.degrees(BotanicalAssets.hue(item,young:true))).frame(height:30)
                                            Image("botanical_flower").resizable().scaledToFit().hueRotation(.degrees(BotanicalAssets.hue(item,young:false))).frame(height:36)
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
    @AppStorage("garden.quality") private var quality=GardenRenderQuality.automatic.rawValue
    @AppStorage("garden.weather.speed") private var speed=0.8
    @AppStorage("garden.weather.wind") private var wind=0.0
    @Environment(\.gardenLowPower) private var lowPower
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var phase
    var body:some View{
        if effect != .none && !reduced && intensity>0 && phase == .active{
            let policy=GardenRenderQuality(rawValue:quality) ?? .automatic
            TimelineView(.animation(minimumInterval:1/policy.rate(lowPower:lowPower))){clock in
                BotanicalAssetWeather(effect:effect,intensity:intensity,time:clock.date.timeIntervalSinceReferenceDate,speed:speed,wind:wind,particleScale:policy.particleScale(lowPower:lowPower))
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
    @AppStorage("garden.quality") private var renderQuality=GardenRenderQuality.automatic.rawValue
    @AppStorage("garden.weather.speed") private var weatherSpeed=0.8
    @AppStorage("garden.weather.wind") private var weatherWind=0.0
    @AppStorage("garden.weather.foreground") private var weatherForeground=false
    @AppStorage("garden.daylight") private var daylight=false
    @AppStorage("timeline.vine.density") private var density=1.0
    @AppStorage("timeline.vine.curvature") private var curvature=1.0
    @AppStorage("timeline.vine.node") private var node=VineNode.natural.rawValue
    @Environment(\.dismiss) private var dismiss
    struct Preset:Codable,Identifiable{
        var id=UUID();var name:String;var theme:String;var custom:Bool;var stem:String;var leaf:String;var bloom:String;var live:Bool;var speed:Double;var glow:Double;var seasonal:Bool;var weather:String;var intensity:Double;var paper:String;var density:Double?=nil;var curvature:Double?=nil;var node:String?=nil;var haptics:Bool?=nil;var renderQuality:String?=nil;var weatherSpeed:Double?=nil;var weatherWind:Double?=nil;var weatherForeground:Bool?=nil;var daylight:Bool?=nil
    }
    @State private var name=""
    @State private var presets=[Preset]()
    var body:some View{
        NavigationStack{
            Form{
                Section("Xem trước"){
                    HStack{VineRail(level:2,theme:VineTheme(rawValue:theme) ?? .emerald,density:density,curvature:curvature,node:VineNode(rawValue:node) ?? .natural,useCustom:true,growth:VineGrowth(days:life.gardenDays)).frame(width:78,height:150);VStack(alignment:.leading){Text("Một ngày đáng nhớ").font(.system(.title2,design:.serif));Text("Ký ức nở hoa").font(.caption);RoundedRectangle(cornerRadius:12).fill(GardenColor.decode(leaf).opacity(0.2)).frame(height:65)}}
                        .padding().background{if !weatherForeground{GardenWeather(effect:GardenAtmosphere(rawValue:weather) ?? .none,intensity:intensity)}}.background{GardenSceneBackground(paper:paper)}.overlay{if weatherForeground{GardenWeather(effect:GardenAtmosphere(rawValue:weather) ?? .none,intensity:intensity)}}
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
                GardenAtmosphereSettings()
                Section("Bộ phối cá nhân"){
                    TextField("Tên bộ phối",text:$name)
                    Button("Lưu bộ phối"){presets.append(Preset(name:name,theme:theme,custom:custom,stem:stem,leaf:leaf,bloom:bloom,live:live,speed:speed,glow:glow,seasonal:seasonal,weather:weather,intensity:intensity,paper:paper,density:density,curvature:curvature,node:node,haptics:haptics,renderQuality:renderQuality,weatherSpeed:weatherSpeed,weatherWind:weatherWind,weatherForeground:weatherForeground,daylight:daylight));persist();name=""}.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    ForEach(presets){p in Button(p.name){theme=p.theme;custom=p.custom;stem=p.stem;leaf=p.leaf;bloom=p.bloom;live=p.live;speed=p.speed;glow=p.glow;seasonal=p.seasonal;weather=p.weather;intensity=p.intensity;paper=p.paper;density=p.density ?? 1;curvature=p.curvature ?? 1;node=p.node ?? VineNode.natural.rawValue;haptics=p.haptics ?? true;renderQuality=p.renderQuality ?? GardenRenderQuality.automatic.rawValue;weatherSpeed=p.weatherSpeed ?? 0.8;weatherWind=p.weatherWind ?? 0;weatherForeground=p.weatherForeground ?? false;daylight=p.daylight ?? false}}
                        .onDelete{presets.remove(atOffsets:$0);persist()}
                }
            }.navigationTitle("Vine Designer").toolbar{Button("Xong"){dismiss()}}
        }.modifier(GardenPowerObserver()).onAppear{presets=(try? JSONDecoder().decode([Preset].self,from:saved)) ?? []}
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
