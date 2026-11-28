import SwiftUI

enum PhotoLabPanel:String,CaseIterable,Identifiable{
    case light="Ánh sáng",color="Màu",detail="Chi tiết",crop="Bố cục",presets="Preset",mask="Masking",mockup="Mockup",ai="AI",history="Lịch sử",export="Xuất"
    var id:String{rawValue}
    var icon:String{
        switch self{
        case .light:return "sun.max"
        case .color:return "paintpalette"
        case .detail:return "viewfinder"
        case .crop:return "crop"
        case .presets:return "camera.filters"
        case .mask:return "circle.dotted.circle"
        case .mockup:return "square.3.layers.3d"
        case .ai:return "sparkles"
        case .history:return "clock.arrow.circlepath"
        case .export:return "square.and.arrow.up"
        }
    }
}
enum PhotoLabLayout{
    static func previewHeight(_ available:CGFloat,expanded:Bool=false)->CGFloat{
        let h=max(0,available)
        return expanded ? max(0,h-80):min(390,h*0.43)
    }
    static func fittedSize(image:CGSize,inside:CGSize)->CGSize{
        guard image.width>0,image.height>0,inside.width>0,inside.height>0 else{return .zero}
        let factor=min(inside.width/image.width,inside.height/image.height)
        return CGSize(width:image.width*factor,height:image.height*factor)
    }
}
