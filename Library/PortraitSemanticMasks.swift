import UIKit
import Vision
import CoreImage

enum PortraitSemanticMasks{
    static func mask(_ image:CIImage,kind:PhotoMaskKind)throws->CIImage{
        let rect=image.extent
        let s=min(1,1200/max(rect.width,rect.height))
        let small=image.transformed(by:CGAffineTransform(scaleX:s,y:s))
        guard let cg=SemanticMaskEngine.context.createCGImage(small,from:small.extent) else{throw PhotoMaskError.unreadable}
        let handler=VNImageRequestHandler(cgImage:cg,options:[:])
        if kind == .person{
            let request=VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .accurate
            request.outputPixelFormat=kCVPixelFormatType_OneComponent8
            try handler.perform([request])
            guard let result=request.results?.first else{throw PhotoMaskError.noSubject}
            return CIImage(cvPixelBuffer:result.pixelBuffer)
        }
        let request=VNDetectFaceLandmarksRequest()
        try handler.perform([request])
        let faces=request.results ?? []
        guard !faces.isEmpty else{throw PhotoMaskError.noSubject}
        let w=cg.width,h=cg.height
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
        var found=false
        let drawn=UIGraphicsImageRenderer(size:CGSize(width:w,height:h),format:format).image{r in
            let ctx=r.cgContext
            ctx.setFillColor(UIColor.black.cgColor);ctx.fill(CGRect(x:0,y:0,width:w,height:h))
            ctx.setFillColor(UIColor.white.cgColor)
            for face in faces{
                let box=face.boundingBox
                func points(_ region:VNFaceLandmarkRegion2D?)->[CGPoint]{
                    guard let region else{return []}
                    return region.normalizedPoints.map{p in CGPoint(x:(box.minX+p.x*box.width)*CGFloat(w),y:(1-box.minY-p.y*box.height)*CGFloat(h))}
                }
                func fill(_ points:[CGPoint]){
                    guard points.count>=3,let first=points.first else{return}
                    found=true;ctx.beginPath();ctx.move(to:first)
                    for p in points.dropFirst(){ctx.addLine(to:p)}
                    ctx.closePath();ctx.fillPath()
                }
                switch kind{
                case .face:
                    let b=CGRect(x:box.minX*CGFloat(w),y:(1-box.maxY)*CGFloat(h),width:box.width*CGFloat(w),height:box.height*CGFloat(h))
                    ctx.fillEllipse(in:b.insetBy(dx:b.width*0.06,dy:b.height*0.04));found=true
                case .eyes:
                    fill(points(face.landmarks?.leftEye));fill(points(face.landmarks?.rightEye))
                case .lips:
                    fill(points(face.landmarks?.outerLips))
                    let inner=points(face.landmarks?.innerLips)
                    ctx.setFillColor(UIColor.black.cgColor);fill(inner);ctx.setFillColor(UIColor.white.cgColor)
                default:break
                }
            }
        }
        guard found,let bitmap=drawn.cgImage else{throw PhotoMaskError.noSubject}
        return CIImage(cgImage:bitmap)
    }
}
