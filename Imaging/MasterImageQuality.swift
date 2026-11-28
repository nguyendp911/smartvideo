import CoreImage
import Foundation

/// A restrained chroma-only correction: retain the edited luminance and restore
/// part of the source chroma in warm skin-like hues and near-neutral highlights.
/// This is a hue-based guard, not a semantic skin detector.
enum MasterImageQuality{
    private static let protectKernel=CIColorKernel(source:"""
        kernel vec4 preserveChroma(__sample original, __sample graded, float protection) {
            vec3 a = original.rgb;
            vec3 b = graded.rgb;
            vec3 luma = vec3(0.2126, 0.7152, 0.0722);
            float y = dot(b,luma);
            float ya = dot(a,luma);
            float hi = max(a.r,max(a.g,a.b));
            float lo = min(a.r,min(a.g,a.b));
            float chroma = hi-lo;
            float warm = smoothstep(0.015,0.12,a.r-a.b) *
                         smoothstep(-0.02,0.07,a.g-a.b) *
                         (1.0-smoothstep(0.04,0.20,a.g-a.r));
            float skin = warm * smoothstep(0.02,0.08,chroma) *
                         (1.0-smoothstep(0.48,0.80,chroma));
            float neutral = (1.0-smoothstep(0.015,0.09,chroma)) *
                            smoothstep(0.30,0.85,ya);
            vec3 restored = vec3(y)+(a-vec3(ya));
            float amount = max(skin*protection,neutral*protection*0.65);
            return vec4(mix(b,restored,amount),graded.a);
        }
        """)
    static func preserveChroma(original:CIImage,graded:CIImage,amount:Double)->CIImage{
        guard amount>0,let kernel=protectKernel else{return graded}
        return kernel.apply(extent:graded.extent,arguments:[original,graded,Float(min(1,amount))]) ?? graded
    }
    /// Clamp only the final finite crop; Lanczos is used when the user
    /// requests a smaller output, rather than default affine interpolation.
    static func downsample(_ image:CIImage,maxSize:Int)->CIImage{
        let rect=image.extent
        guard rect.width>0,rect.height>0,maxSize>0 else{return image}
        let s=min(1,CGFloat(maxSize)/max(rect.width,rect.height))
        let normalized=image.transformed(by:CGAffineTransform(translationX:-rect.minX,y:-rect.minY))
        if s>=1{return normalized}
        let target=CGRect(x:0,y:0,width:max(1,floor(rect.width*s)),height:max(1,floor(rect.height*s)))
        return normalized.applyingFilter("CILanczosScaleTransform",parameters:[kCIInputScaleKey:s,kCIInputAspectRatioKey:1]).cropped(to:target)
    }
    static func noise(_ image:CIImage,amount:Double)->CIImage{
        guard amount>0 else{return image}
        return image.applyingFilter("CINoiseReduction",parameters:["inputNoiseLevel":min(1,amount)*0.075,"inputSharpness":0.18]).cropped(to:image.extent)
    }
    static func sharpen(_ image:CIImage,amount:Double)->CIImage{
        guard amount>0 else{return image}
        // Avoid doubling high-frequency halos after denoising.
        return image.applyingFilter("CISharpenLuminance",parameters:[kCIInputSharpnessKey:min(1,amount)*0.72]).cropped(to:image.extent)
    }
}
