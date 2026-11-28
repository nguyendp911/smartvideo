import Foundation
import UIKit

/// Serializes interactive renders. Cancelled views do not start another expensive
/// render after waiting in the actor queue. Full-size exports retain their existing pipeline.
actor PhotoPreviewWorker{
    static let shared=PhotoPreviewWorker()
    func photo(_ url:URL,recipe:CreativeRecipe,maxSize:Int,thumbnail:Bool)->Data?{
        guard !Task.isCancelled else{return nil}
        return autoreleasepool{
            CreativeEngine.render(url,recipe:recipe,maxSize:maxSize,format:"JPEG",quality:thumbnail ? 0.85:0.93,metadata:false,thumbnailOnly:thumbnail)
        }
    }
    func mask(_ url:URL,document:PhotoMaskDocument,selected:UUID?,overlay:Bool)throws->Data{
        try Task.checkCancellation()
        return try autoreleasepool{
            let image=try SemanticMaskEngine.preview(url,document:document,selected:selected,overlay:overlay)
            guard let data=image.pngData() else{throw PhotoMaskError.unreadable}
            return data
        }
    }
}
