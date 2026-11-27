import UIKit
import CoreImage
import Vision
import ImageIO
import UniformTypeIdentifiers

enum Light: String, Codable, CaseIterable {
    case natural = "Tự nhiên", backlit = "Ngược sáng", night = "Ánh sáng yếu", portrait = "Chân dung", warm = "Ánh đèn ấm"
}
enum Look: String, CaseIterable, Codable, Identifiable {
    case neutral = "Tự nhiên", amber = "Nắng phim", street = "Phố đêm"
    case mono = "Đen trắng", vintage = "Hoài cổ", vivid = "Rực rỡ", soft = "Dịu nhẹ", cool = "Xanh lạnh", cinematic = "Điện ảnh"
    var id: Self { self }
}
struct RenderedPhoto {
    let jpeg: Data
    let thumbnail: Data
    let light: Light
}
enum CameraError: LocalizedError {
    case unreadable, writeFailed, missingCamera, noSpace
    var errorDescription: String? {
        switch self {
        case .unreadable: return "Không đọc được dữ liệu ảnh."
        case .writeFailed: return "Chưa thể lưu ảnh. Hãy kiểm tra dung lượng."
        case .missingCamera: return "Camera này hiện chưa khả dụng."
        case .noSpace: return "iPhone không còn đủ dung lượng để lưu ảnh."
        }
    }
}
enum PhotoEngine {
    private static let color = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let context = CIContext(options: [.cacheIntermediates: false])
    static func thumb(_ data: Data, limit: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limit, kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
    static func thumbnail(_ data: Data, limit: Int = 420) -> Data? {
        guard let frame = thumb(data, limit: limit) else { return nil }
        return UIImage(cgImage: frame).jpegData(compressionQuality: 0.82)
    }
    static func render(_ data: Data, look: Look) throws -> RenderedPhoto {
        guard let source = CGImageSourceCreateWithData(data as CFData,nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any],
              let small = thumb(data, limit: 640),
              let original = CIImage(data: data, options: [.applyOrientationProperty: true]) else { throw CameraError.unreadable }
        let extent = original.extent.integral
        guard extent.width > 0, extent.height > 0, extent.width * extent.height <= 70_000_000 else { throw CameraError.unreadable }
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cgImage: small, options: [:]).perform([request])
        let faces = (request.results ?? []).sorted { $0.boundingBox.width > $1.boundingBox.width }.prefix(5).map(\.boundingBox)
        let stats = samples(of: small, faces: faces)
        let light: Light
        if !faces.isEmpty && stats.face < 0.47 && stats.high > 0.76 && stats.high - stats.face > 0.37 { light = .backlit }
        else if stats.mid < 0.22 { light = .night }
        else if stats.warmth > 0.15 { light = .warm }
        else if !faces.isEmpty { light = .portrait }
        else { light = .natural }

        // The camera has already tone-mapped a processed capture. Keep this second pass restrained.
        let lift = light == .night ? 0.025 : min(0.058, max(0, (0.44 - stats.mid) * 0.19))
        let shoulder = stats.high > 0.86 ? 0.016 : 0.0
        var image = curve(original, low: 0.25 + lift, mid: 0.5 + lift * 0.72, high: 0.75 - shoulder)
        let saturation: Double = light == .warm ? 0.97 : (light == .night ? 0.98 : 1.025)
        image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey:saturation])
        if look == .amber {
            image = image.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral":CIVector(x:6500,y:0),"inputTargetNeutral":CIVector(x:6050,y:0)])
        } else if look == .street {
            image = curve(image, low: 0.235, mid: 0.506, high: 0.757)
            image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey:0.93])
        }
        switch look {
        case .mono: image=image.applyingFilter("CIPhotoEffectMono")
        case .vintage: image=image.applyingFilter("CIPhotoEffectInstant")
        case .vivid: image=image.applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:1.23,kCIInputContrastKey:1.05])
        case .soft: image=image.applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:0.9,kCIInputContrastKey:0.92])
        case .cool: image=image.applyingFilter("CITemperatureAndTint",parameters:["inputNeutral":CIVector(x:6500,y:0),"inputTargetNeutral":CIVector(x:7300,y:0)])
        case .cinematic: image=image.applyingFilter("CIPhotoEffectProcess").applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:0.88,kCIInputContrastKey:1.04])
        default: break
        }
        // Feather local exposure across the face. No geometric or skin-texture edits.
        if !faces.isEmpty {
            let brighten = min(0.42, max(0, (0.46 - stats.face) * 1.15))
            var subject = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey:brighten])
            if light == .warm && look != .mono {
                subject = subject.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey:0.93])
            }
            for face in faces {
                let cx = extent.minX + face.midX * extent.width, cy = extent.minY + face.midY * extent.height
                let rx = max(1,face.width * extent.width * 0.83), ry = max(1,face.height * extent.height * 0.83)
                guard let mask = CIFilter(name:"CIRadialGradient", parameters:[
                    "inputCenter":CIVector(x:0,y:0),"inputRadius0":0.37,"inputRadius1":1.0,
                    "inputColor0":CIColor.white,"inputColor1":CIColor.black
                ])?.outputImage?.transformed(by:CGAffineTransform(a:rx,b:0,c:0,d:ry,tx:cx,ty:cy)).cropped(to:extent) else { continue }
                image = subject.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:image,kCIInputMaskImageKey:mask])
            }
        }
        guard let cg = context.createCGImage(image.cropped(to:extent), from:extent, format:.RGBA8, colorSpace:color) else { throw CameraError.writeFailed }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1,nil) else { throw CameraError.writeFailed }
        // Whitelist camera information; all derived pictures are upright SDR sRGB JPEGs.
        var tags: [String:Any] = [kCGImageDestinationLossyCompressionQuality as String:0.94,
                                  kCGImagePropertyOrientation as String:1]
        if var exif = props[kCGImagePropertyExifDictionary as String] as? [String:Any] {
            exif[kCGImagePropertyExifPixelXDimension as String]=cg.width
            exif[kCGImagePropertyExifPixelYDimension as String]=cg.height
            exif.removeValue(forKey:kCGImagePropertyExifMakerNote as String)
            tags[kCGImagePropertyExifDictionary as String]=exif
        }
        CGImageDestinationAddImage(dest,cg,tags as CFDictionary)
        guard CGImageDestinationFinalize(dest), let thumbnail = thumbnail(out as Data) else { throw CameraError.writeFailed }
        return RenderedPhoto(jpeg:out as Data,thumbnail:thumbnail,light:light)
    }
    private static func curve(_ image: CIImage, low:Double, mid:Double, high:Double) -> CIImage {
        image.applyingFilter("CIToneCurve", parameters:["inputPoint0":CIVector(x:0,y:0),"inputPoint1":CIVector(x:0.25,y:low),
            "inputPoint2":CIVector(x:0.5,y:mid),"inputPoint3":CIVector(x:0.75,y:high),"inputPoint4":CIVector(x:1,y:1)])
    }
    private static func samples(of image:CGImage, faces:[CGRect]) -> (mid:Double,high:Double,face:Double,warmth:Double) {
        let n=64
        var data=[UInt8](repeating:0,count:n*n*4)
        var hist=[Int](repeating:0,count:256), faceSum=0.0, warmSum=0.0, hits=0
        data.withUnsafeMutableBytes { bytes in
            guard let ctx=CGContext(data:bytes.baseAddress,width:n,height:n,bitsPerComponent:8,bytesPerRow:n*4,space:color,
                bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return }
            ctx.draw(image,in:CGRect(x:0,y:0,width:n,height:n))
        }
        for y in 0..<n { for x in 0..<n {
            let i=(y*n+x)*4, r=Double(data[i])/255, g=Double(data[i+1])/255, b=Double(data[i+2])/255
            let l=0.2126*r+0.7152*g+0.0722*b
            hist[min(255,Int(l*255))] += 1
            let point=CGPoint(x:(Double(x)+0.5)/Double(n),y:1-(Double(y)+0.5)/Double(n))
            if faces.contains(where:{$0.contains(point)}) { faceSum+=l; hits+=1 }
            if l > 0.07 && l < 0.95 { warmSum += r-b }
        }}
        func percentile(_ p:Double)->Double {
            var total=0
            for (i,v) in hist.enumerated() { total+=v; if total >= Int(Double(n*n)*p) { return Double(i)/255 } }
            return 0.5
        }
        let mid=percentile(0.5)
        return (mid,percentile(0.95),hits>0 ? faceSum/Double(hits) : mid,warmSum/Double(n*n))
    }
}
