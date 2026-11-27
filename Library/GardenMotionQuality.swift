import SwiftUI
import UIKit

enum GardenRenderQuality:String,CaseIterable,Identifiable{
    case automatic="Tự động",economy="Tiết kiệm pin",detail="Chi tiết cao"
    var id:String{rawValue}
    func rate(lowPower:Bool)->Double{
        switch self{case .automatic:return lowPower ? 12:24;case .economy:return 12;case .detail:return lowPower ? 18:30}
    }
    func particleScale(lowPower:Bool)->Double{
        switch self{case .automatic:return lowPower ? 0.5:0.85;case .economy:return 0.45;case .detail:return lowPower ? 0.65:1}
    }
}
struct GardenPowerObserver:ViewModifier{
    @State private var lowPower=ProcessInfo.processInfo.isLowPowerModeEnabled
    func body(content:Content)->some View{
        content.environment(\.gardenLowPower,lowPower)
            .onReceive(NotificationCenter.default.publisher(for:Notification.Name.NSProcessInfoPowerStateDidChange)){_ in
                lowPower=ProcessInfo.processInfo.isLowPowerModeEnabled
            }
    }
}
private struct GardenPowerKey:EnvironmentKey{static let defaultValue=false}
extension EnvironmentValues{
    var gardenLowPower:Bool{get{self[GardenPowerKey.self]}set{self[GardenPowerKey.self]=newValue}}
}
enum GardenDaylight{
    static func palette(hour:Int)->[Color]{
        switch hour{
        case 5..<8:return [Color(red:0.21,green:0.25,blue:0.17),Color(red:0.07,green:0.12,blue:0.10)]
        case 8..<17:return [Color(red:0.13,green:0.22,blue:0.16),Color(red:0.055,green:0.10,blue:0.08)]
        case 17..<20:return [Color(red:0.27,green:0.17,blue:0.12),Color(red:0.09,green:0.10,blue:0.08)]
        default:return [Color(red:0.07,green:0.12,blue:0.17),Color(red:0.035,green:0.045,blue:0.07)]
        }
    }
    static func title(hour:Int)->String{
        switch hour{case 5..<8:return "Bình minh";case 8..<17:return "Ban ngày";case 17..<20:return "Hoàng hôn";default:return "Đêm"}
    }
}
struct GardenSceneBackground:View{
    let paper:String
    @AppStorage("garden.daylight") private var daylight=false
    var body:some View{
        if daylight{
            TimelineView(.periodic(from:.now,by:60)){clock in
                let hour=Calendar.current.component(.hour,from:clock.date)
                LinearGradient(colors:GardenDaylight.palette(hour:hour),startPoint:.topLeading,endPoint:.bottomTrailing)
            }
        }else{GardenBackground.color(paper)}
    }
}
enum BotanicalTilePlan{
    // Mirrored adjacent tiles meet at the same image edge, avoiding unrelated stem ends.
    struct Tile:Equatable{let index:Int;let top:CGFloat;var mirrored:Bool{index%2 != 0}}
    static func tiles(height:CGFloat,offset:CGFloat,tileHeight:CGFloat)->[Tile]{
        guard height>0,tileHeight>1 else{return []}
        let first=Int(floor(offset/tileHeight)),last=Int(floor((offset+height)/tileHeight))
        return (first...last).map{Tile(index:$0,top:CGFloat($0)*tileHeight-offset)}
    }
    static func extraLeaves(age:VineGrowth,density:Double)->Int{
        guard age.stage.rawValue>=VineGrowthStage.sprout.rawValue else{return 0}
        return max(1,min(6,Int((age.maturity*5+1)*max(0.35,min(1.8,density)))))
    }
    static func edgeFade(_ position:Double)->Double{
        let p=max(0,min(1,position))
        return min(1,min(p/0.07,(1-p)/0.09))
    }
}
struct GardenAtmosphereSettings:View{
    @AppStorage("garden.quality") private var quality=GardenRenderQuality.automatic.rawValue
    @AppStorage("garden.weather.speed") private var speed=0.8
    @AppStorage("garden.weather.wind") private var wind=0.0
    @AppStorage("garden.weather.foreground") private var foreground=false
    @AppStorage("garden.daylight") private var daylight=false
    @AppStorage("garden.intensity") private var intensity=0.35
    @AppStorage("garden.weather") private var weather=GardenAtmosphere.none.rawValue
    var body:some View{
        Section("Chuyển động & chiều sâu"){
            Picker("Chất lượng",selection:$quality){ForEach(GardenRenderQuality.allCases){Text($0.rawValue).tag($0.rawValue)}}
            Toggle("Ánh sáng theo giờ iPhone",isOn:$daylight)
            if daylight{Text(GardenDaylight.title(hour:Calendar.current.component(.hour,from:Date()))).font(.caption).foregroundStyle(.secondary)}
            Toggle("Hạt ở phía trước ảnh",isOn:$foreground)
            Text("Tốc độ hiệu ứng").font(.caption)
            Slider(value:$speed,in:0.25...1.8)
            Text("Hướng gió").font(.caption)
            Slider(value:$wind,in:-1...1)
            Button("Khôi phục hiệu ứng mặc định"){quality=GardenRenderQuality.automatic.rawValue;speed=0.8;wind=0;foreground=false;daylight=false;intensity=0.35;weather=GardenAtmosphere.none.rawValue}
            Text("Mặc định hạt nằm sau ảnh và nội dung. Chế độ tiết kiệm giảm tần suất vẽ, không giảm độ phân giải PNG.").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
