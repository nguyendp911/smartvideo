import SwiftUI
import Vision
import UIKit

struct CompositionAnchor:Codable,Equatable{
    var x=0.5
    var y=0.5
    static func ratio(_ crop:String)->CGFloat?{
        switch crop{case "1:1":return 1;case "4:5":return 0.8;case "9:16":return 9/16;case "3:2":return 3/2;case "16:9":return 16/9;default:return nil}
    }
    func rect(in rect:CGRect,ratio:CGFloat)->CGRect{
        let w=min(rect.width,rect.height*ratio),h=w/ratio
        return CGRect(x:rect.minX+(rect.width-w)*max(0,min(1,x)),y:rect.minY+(rect.height-h)*(1-max(0,min(1,y))),width:w,height:h)
    }
    static func fromFocus(x:Double,y:Double,width:Double,height:Double,crop:String)->Self{
        guard let ratio=ratio(crop),width>0,height>0 else{return Self()}
        let w=min(width,height*Double(ratio)),h=w/Double(ratio)
        func anchor(_ p:Double,_ size:Double,_ target:Double)->Double{size-target<0.001 ? 0.5:max(0,min(1,(p*size-target/2)/(size-target)))}
        return Self(x:anchor(x,width,w),y:anchor(y,height,h))
    }
}
struct CompositionFeedback:Codable,Equatable{
    let crop:String
    let dx:Double
    let dy:Double
}
enum CompositionEngine{
    static func proposal(url:URL,crop:String)->CompositionAnchor?{
        guard CompositionAnchor.ratio(crop) != nil,let data=try? Data(contentsOf:url,options:.mappedIfSafe),let image=PhotoEngine.thumb(data,limit:640) else{return nil}
        let request=VNGenerateAttentionBasedSaliencyImageRequest(),handler=VNImageRequestHandler(cgImage:image,options:[:])
        do{try handler.perform([request])}catch{return nil}
        guard let boxes=request.results?.first?.salientObjects,!boxes.isEmpty else{return nil}
        let area=boxes.map(\.boundingBox).reduce(CGRect.null){$0.union($1)}
        guard !area.isNull else{return nil}
        return CompositionAnchor.fromFocus(x:Double(area.midX),y:Double(1-area.midY),width:Double(image.width),height:Double(image.height),crop:crop)
    }
    static func feedback(url:URL,recipe:CreativeRecipe)->CompositionFeedback?{
        guard recipe.rotation ?? 0 == 0,recipe.mirror != true,let actual=recipe.compositionAnchor,let base=proposal(url:url,crop:recipe.crop) else{return nil}
        return CompositionFeedback(crop:recipe.crop,dx:actual.x-base.x,dy:actual.y-base.y)
    }
    static func suggest(url:URL,crop:String,samples:[TasteSample])->CompositionAnchor?{
        guard var base=proposal(url:url,crop:crop) else{return nil}
        let values=samples.compactMap(\.compositionFeedback).filter{$0.crop==crop}
        guard values.count>=3 else{return base}
        // Validate whether a shared offset predicts other confirmed corrections better than zero.
        var baseline=0.0,adapted=0.0
        for i in values.indices{
            let rest=values.enumerated().filter{$0.offset != i}.map(\.element)
            let dx=rest.reduce(0.0){$0+$1.dx}/Double(rest.count),dy=rest.reduce(0.0){$0+$1.dy}/Double(rest.count)
            baseline+=abs(values[i].dx)+abs(values[i].dy)
            adapted+=abs(values[i].dx-dx)+abs(values[i].dy-dy)
        }
        if baseline>0.001,adapted<baseline*0.95{
            base.x=max(0,min(1,base.x+values.reduce(0.0){$0+$1.dx}/Double(values.count)))
            base.y=max(0,min(1,base.y+values.reduce(0.0){$0+$1.dy}/Double(values.count)))
        }
        return base
    }
}
