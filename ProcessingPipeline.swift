import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import Foundation

/// Pipeline não destrutivo: sempre parte do CIImage original (imutável) + CameraProfile.
/// Modo `.preview` pula etapas caras (grão, halation, bloom) para manter o vídeo fluido.
final class ProcessingPipeline {
    enum Mode: Equatable { case preview, full }

    let context: CIContext

    init(context: CIContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) as Any])) {
        self.context = context
    }

    // MARK: Pública

    func process(_ source: CIImage, profile: CameraProfile, mode: Mode) -> CIImage {
        var img = source.clampedToExtent().cropped(to: source.extent)
        let extent = source.extent
        let scale = max(extent.width, extent.height) / 3000.0   // parâmetros referenciados a ~12 MP

        img = Self.crop(img, aspect: profile.aspect.ratio)
        let box = img.extent

        // 1. Exposição
        let flash = profile.flash.look
        let fi = profile.flashIntensity
        img = img.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: profile.exposure])

        // 2. Balanço de branco (positivo = mais quente). Verificar visualmente no aparelho.
        let temp = profile.temperature + flash.warmth * fi
        img = img.applyingFilter("CITemperatureAndTint", parameters: [
            "inputNeutral": CIVector(x: 6500 + temp, y: profile.tint),
            "inputTargetNeutral": CIVector(x: 6500, y: 0)])

        // 3/5/6. Cor, contraste, saturação
        img = img.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: profile.saturation,
            kCIInputContrastKey: profile.contrast + flash.contrast * fi])

        // 7. Highlights / shadows
        img = img.applyingFilter("CIHighlightShadowAdjust", parameters: [
            "inputHighlightAmount": max(0, min(1, 1 + profile.highlights)),
            "inputShadowAmount": profile.shadows])

        // 4/8/10. Curva tonal com black point
        let c = profile.curve.count == 5 ? profile.curve : [0, 0.25, 0.5, 0.75, 1]
        img = img.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0, y: max(c[0], profile.blackPoint)),
            "inputPoint1": CIVector(x: 0.25, y: c[1]),
            "inputPoint2": CIVector(x: 0.5, y: c[2]),
            "inputPoint3": CIVector(x: 0.75, y: c[3]),
            "inputPoint4": CIVector(x: 1, y: c[4])])

        // 13/14. Flash simulado (centro mais claro, fundo mais escuro)
        if flash.bg > 0 { img = Self.applyFlash(img, box: box, look: flash, intensity: fi) }

        if mode == .full {
            // Bloom
            if profile.bloom > 0 {
                img = img.applyingFilter("CIBloom", parameters: [
                    kCIInputRadiusKey: 12 * scale, kCIInputIntensityKey: profile.bloom])
            }
            // Halation: realces fortes borrados e tingidos de vermelho/laranja, somados
            if profile.halation > 0 { img = Self.halation(img, amount: profile.halation, radius: 28 * scale) }
        }

        // 12. Nitidez
        if profile.sharpness > 0 {
            img = img.applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: profile.sharpness, "inputRadius": 1.2 * scale])
        }

        // 15. Vinheta
        if profile.vignette > 0 {
            img = img.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: profile.vignette * 1.5,
                kCIInputRadiusKey: max(box.width, box.height) / 1500.0 * 1.4])
        }

        // 11. Grão (por último antes da moldura, para não ser borrado)
        if mode == .full && profile.grain > 0 {
            img = Self.grain(img, box: box, amount: profile.grain, size: profile.grainSize * max(scale, 0.5))
        }

        img = img.cropped(to: box)

        // Moldura (aplicada sobre a imagem já processada, não substitui o processamento)
        if mode == .full { img = Self.applyFrame(img, style: profile.frame) }
        return img
    }

    // MARK: Render / encode

    func render(_ image: CIImage) -> CGImage? {
        context.createCGImage(image, from: image.extent, format: .RGBA8,
                              colorSpace: CGColorSpace(name: CGColorSpace.displayP3))
    }

    func encodeHEIF(_ image: CIImage, quality: Double = 0.92) -> Data? {
        let cs = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        let opts: [CIImageRepresentationOption: Any] =
            [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality]
        return context.heifRepresentation(of: image, format: .RGBA8, colorSpace: cs, options: opts)
            ?? context.jpegRepresentation(of: image, colorSpace: cs, options: opts)
    }

    // MARK: Etapas

    static func crop(_ img: CIImage, aspect: Double) -> CIImage {
        let e = img.extent
        let current = e.width / e.height
        var r = e
        if current > aspect { r.size.width = e.height * aspect; r.origin.x += (e.width - r.width) / 2 }
        else { r.size.height = e.width / aspect; r.origin.y += (e.height - r.height) / 2 }
        return img.cropped(to: r)
    }

    static func applyFlash(_ img: CIImage, box: CGRect, look: (bg: Double, center: Double, warmth: Double, contrast: Double), intensity: Double) -> CIImage {
        let center = CIVector(x: box.midX, y: box.midY + box.height * 0.04)
        let rIn = min(box.width, box.height) * 0.22
        let rOut = max(box.width, box.height) * 0.75
        let dark = CIFilter.radialGradient()
        dark.center = CGPoint(x: center.x, y: center.y)
        dark.radius0 = Float(rIn); dark.radius1 = Float(rOut)
        dark.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        dark.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: CGFloat(look.bg * intensity))
        var out = img
        if let g = dark.outputImage { out = g.cropped(to: box).composited(over: out) }
        let lift = CIFilter.radialGradient()
        lift.center = CGPoint(x: center.x, y: center.y)
        lift.radius0 = 0; lift.radius1 = Float(rIn * 2.2)
        lift.color0 = CIColor(red: 1, green: 0.97, blue: 0.92, alpha: CGFloat(look.center * intensity))
        lift.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 0)
        if let g = lift.outputImage { out = g.cropped(to: box).composited(over: out) }
        return out
    }

    static func halation(_ img: CIImage, amount: Double, radius: Double) -> CIImage {
        let box = img.extent
        let bright = img
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 3, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 3, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 3, w: 0),
                "inputBiasVector": CIVector(x: -2, y: -2, z: -2, w: 0)])
            .applyingFilter("CIColorClamp")
        let glow = bright
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: box)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: CGFloat(amount) * 1.0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: CGFloat(amount) * 0.28, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(amount) * 0.05, w: 0)])
        return glow.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: img]).cropped(to: box)
    }

    static func grain(_ img: CIImage, box: CGRect, amount: Double, size: Double) -> CIImage {
        guard let noise = CIFilter.randomGenerator().outputImage else { return img }
        let mono = noise
            .transformed(by: CGAffineTransform(scaleX: CGFloat(size), y: CGFloat(size)))
            .cropped(to: box)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(min(1, amount * 0.55)))])
        return mono.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: img]).cropped(to: box)
    }

    static func applyFrame(_ img: CIImage, style: FrameStyle) -> CIImage {
        guard style != .none else { return img }
        let e = img.extent
        let side = min(e.width, e.height) * (style == .instant ? 0.07 : 0.05)
        let bottom = style == .instant ? side * 3.2 : side
        let canvas = CGRect(x: 0, y: 0, width: e.width + side * 2, height: e.height + side + bottom)
        let color: CIColor
        switch style {
        case .black: color = CIColor(red: 0.03, green: 0.03, blue: 0.03)
        case .instant: color = CIColor(red: 0.96, green: 0.95, blue: 0.92)
        default: color = CIColor(red: 1, green: 1, blue: 1)
        }
        let bg = CIImage(color: color).cropped(to: canvas)
        let moved = img.transformed(by: CGAffineTransform(translationX: side - e.minX, y: bottom - e.minY))
        return moved.composited(over: bg)
    }
}
