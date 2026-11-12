import Foundation
import CoreImage
import UIKit
import Vision

/// Shared frame compositor for photos and videos. Because the effect is
/// applied to source pixels before TimelineComposer and AVAssetExportSession,
/// imported PNGs, blend modes, animation and people masking survive MP4.
/// No CALayer.mask or unsynchronized AVPlayerLayer is involved.
enum MockupFrameRenderer {
    static func apply(
        to original: CIImage,
        items: [MockupOverlayClip],
        projectTime: Double,
        maskSource: CIImage? = nil,
        cachedPersonMask: CIImage? = nil
    ) throws -> CIImage {
        guard projectTime.isFinite else { return original }
        let active = items.filter {
            $0.isVisible && projectTime >= $0.start &&
            projectTime < $0.end
        }
        guard !active.isEmpty else { return original }
        let frame = original.extent
        guard frame.width > 0 && frame.height > 0 else {
            return original
        }

        // The person matte can be shared across all mockup tracks in
        // this frame (and across still-video frames using cachedPersonMask).
        var personMask = cachedPersonMask
        var protectionMask: CIImage?
        var result = original
        for item in active {
            guard let texture = texture(for: item) else {
                // Missing assets are nonfatal and never hide other layers.
                continue
            }
            let position = MockupAnimationSampler.sample(
                item, atProjectTime: projectTime
            )
            var layer = transformed(
                texture, item: item,
                state: position, canvas: frame
            )
            let blur = max(0, item.blurRadius + item.feather)
            if blur > 0.01 {
                layer = layer.applyingFilter(
                    "CIGaussianBlur",
                    parameters: [
                        kCIInputRadiusKey: min(35, blur)
                    ]
                )
            }
            layer = colorized(layer, item: item,
                              opacity: position.opacity)
            let blended = blend(base: result, layer: layer,
                                mode: item.blendMode)
            if item.depthMode == .behindPerson {
                if personMask == nil {
                    personMask = try PersonCutoutProcessor.personMask(
                        maskSource ?? original, quality: .fast
                    )
                }
                if let personMask {
                    result = result.applyingFilter(
                        "CIBlendWithMask", parameters: [
                            kCIInputBackgroundImageKey: blended,
                            kCIInputMaskImageKey: personMask
                        ]
                    ).cropped(to: frame)
                } else {
                    result = blended
                }
            } else if item.avoidFace {
                if protectionMask == nil {
                    protectionMask = MockupFaceAwareLayout.protectionMask(
                        maskSource ?? original
                    )
                }
                if let protectionMask {
                    result = blended.applyingFilter(
                        "CIBlendWithMask",
                        parameters: [
                            kCIInputBackgroundImageKey: result,
                            kCIInputMaskImageKey: protectionMask
                        ]
                    ).cropped(to: frame)
                } else {
                    result = blended
                }
            } else {
                result = blended
            }
        }
        return result.cropped(to: frame)
    }

    private static func texture(
        for item: MockupOverlayClip
    ) -> CIImage? {
        if let url = item.assetURL {
            // User-imported alpha PNG / JPEG is resolved from Media at
            // project load time. Preserve PNG alpha and image orientation.
            return CIImage(
                contentsOf: url,
                options: [.applyOrientationProperty: true]
            )
        }
        guard let image = MockupProceduralTexture.artwork(
            id: item.effectID
        )?.cgImage else { return nil }
        return CIImage(cgImage: image)
    }

    private static func transformed(
        _ source: CIImage, item: MockupOverlayClip,
        state: MockupMotionState, canvas: CGRect
    ) -> CIImage {
        let ext = source.extent
        guard ext.width > 0 && ext.height > 0 else {
            return source
        }
        let fill = max(
            canvas.width / ext.width,
            canvas.height / ext.height
        )
        let scale = CGFloat(min(5, max(0.25, state.scale))) * fill
        let sx = scale * (item.flipHorizontal ? -1 : 1)
        let sy = scale * (item.flipVertical ? -1 : 1)
        let angle = CGFloat(state.rotation * .pi / 180)
        let cs = cos(angle), sn = sin(angle)
        let a = sx * cs, b = sx * sn
        let c = -sy * sn, d = sy * cs
        let mid = CGPoint(
            x: ext.midX, y: ext.midY
        )
        let center = CGPoint(
            x: canvas.minX + CGFloat(state.x) * canvas.width,
            y: canvas.minY +
                (1 - CGFloat(state.y)) * canvas.height
        )
        let t = CGAffineTransform(
            a: a, b: b, c: c, d: d,
            tx: center.x - a * mid.x - c * mid.y,
            ty: center.y - b * mid.x - d * mid.y
        )
        return source.transformed(by: t)
    }

    private static func colorized(
        _ image: CIImage,
        item: MockupOverlayClip, opacity: Double
    ) -> CIImage {
        let warm = CGFloat(item.warmth)
        let tint = CGFloat(item.tint)
        let contrast = CGFloat(item.contrast)
        let brighten = CGFloat(item.brightness)
        var processed = image.applyingFilter(
            "CIColorControls", parameters: [
                kCIInputContrastKey: contrast,
                kCIInputBrightnessKey: brighten,
                kCIInputSaturationKey: 1
            ]
        )
        processed = processed.applyingFilter(
            "CIColorMatrix", parameters: [
                "inputRVector": CIVector(
                    x: 1 + max(0, warm) * 0.28,
                    y: 0, z: 0, w: 0
                ),
                "inputGVector": CIVector(
                    x: 0, y: 1 + tint * 0.15,
                    z: 0, w: 0
                ),
                "inputBVector": CIVector(
                    x: 0, y: 0,
                    z: 1 + max(0, -warm) * 0.28, w: 0
                ),
                "inputAVector": CIVector(
                    x: 0, y: 0, z: 0,
                    w: CGFloat(min(1, max(0, opacity)))
                )
            ]
        )
        return processed
    }

    static func blend(
        base: CIImage, layer: CIImage,
        mode: MockupBlendMode
    ) -> CIImage {
        let filter: String
        switch mode {
        case .normal:
            return layer.composited(over: base)
                .cropped(to: base.extent)
        case .multiply: filter = "CIMultiplyBlendMode"
        case .screen: filter = "CIScreenBlendMode"
        case .overlay: filter = "CIOverlayBlendMode"
        case .softLight: filter = "CISoftLightBlendMode"
        case .hardLight: filter = "CIHardLightBlendMode"
        case .add: filter = "CIAdditionCompositing"
        case .darken: filter = "CIDarkenBlendMode"
        case .lighten: filter = "CILightenBlendMode"
        }
        return layer.applyingFilter(
            filter, parameters: [
                kCIInputBackgroundImageKey: base
            ]
        ).cropped(to: base.extent)
    }
}
