#if canImport(UIKit) && canImport(SwiftUI)
import SwiftUI
import UIKit
import CoreImage

@available(iOS 17.0, *)
struct StickerAnimateView: View {
    let originalImage: UIImage
    let parameters: StickerParameters
    let plugin: FlutterStickerMakerPlugin
    let onComplete: (Data) -> Void
    let onError: (Error) -> Void

    @State private var stickerImage: UIImage?
    @State private var stickerScaleProgress: CGFloat = 0.0
    @State private var spoilerViewOpacity: CGFloat = 0.0
    @State private var shakeProgress: CGFloat = 0.0
    @State private var hasAnimatedSticker = false
    @State private var hasShakenSticker = false
    @State private var hasStartedProcessing = false

    private static let stickerAnimationDuration: TimeInterval = 1.0
    private static let stickerScaleAnimationDuration: TimeInterval = 0.62
    private let stickerAnimation: Animation
    private let rotationAngle: Angle
    private let scaleTransform: CGSize
    private let spoilerColor: UIColor

    private static let overlayBackground = Color(red: 0, green: 0, blue: 0, opacity: 0.35)

    init(
        originalImage: UIImage,
        parameters: StickerParameters,
        plugin: FlutterStickerMakerPlugin,
        onComplete: @escaping (Data) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.originalImage = originalImage
        self.parameters = parameters
        self.plugin = plugin
        self.onComplete = onComplete
        self.onError = onError
        self.stickerAnimation = .easeOut(duration: Self.stickerAnimationDuration)

        // Pre-compute transforms
        self.rotationAngle = Self.computeRotationAngle(for: originalImage.imageOrientation)
        self.scaleTransform = Self.computeScaleTransform(for: originalImage.imageOrientation)
        self.spoilerColor = Self.deriveSpoilerColor(from: originalImage)
    }

    var body: some View {
        ZStack {
            Self.overlayBackground

            ZStack {
                Image(uiImage: originalImage)
                    .resizable()
                    .scaledToFit()
                    .opacity(stickerImage == nil ? 1 : 0)
                    .animation(stickerAnimation, value: stickerImage)

                Group {
                    if parameters.speckleType == .flutteroverlay {
                        AnimatedSpeckleOverlay(color: spoilerColor)
                    } else {
                        SpoilerView(
                            isOn: true,
                            color: spoilerColor,
                            speckleType: parameters.speckleType)
                    }
                }
                .opacity(spoilerViewOpacity)

                if let stickerImage {
                    Image(uiImage: stickerImage)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(stickerScale)
                        .rotationEffect(rotationAngle)
                        .scaleEffect(scaleTransform)
                        .modifier(
                            DampedShakeEffect(
                                progress: shakeProgress,
                                isEnabled: parameters.speckleType == .flutteroverlay)
                        )
                }
            }
            .aspectRatio(
                originalImage.size.width / originalImage.size.height,
                contentMode: .fit)
        }
        .allowsHitTesting(false)
        .onAppear {
            if !hasStartedProcessing {
                hasStartedProcessing = true
                startStickerCreation()
            }
        }
    }

    private static func computeRotationAngle(for orientation: UIImage.Orientation) -> Angle {
        switch orientation {
        case .up, .upMirrored:
            return .zero
        case .down, .downMirrored:
            return .degrees(180)
        case .left, .leftMirrored:
            return .degrees(90)
        case .right, .rightMirrored:
            return .degrees(-90)
        @unknown default:
            return .zero
        }
    }

    private static func computeScaleTransform(for orientation: UIImage.Orientation) -> CGSize {
        switch orientation {
        case .upMirrored, .downMirrored:
            return CGSize(width: -1, height: 1)
        case .leftMirrored, .rightMirrored:
            return CGSize(width: 1, height: -1)
        default:
            return CGSize(width: 1, height: 1)
        }
    }

    private static func deriveSpoilerColor(from image: UIImage) -> UIColor {
        guard let avgColor = image.averageColor else {
            return UIColor.white.withAlphaComponent(0.4)
        }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        let resolved = avgColor.getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha)
        let safeBrightness = resolved ? brightness : avgColor.cgColor.brightnessFallback
        let targetAlpha = max(0.3, min(0.55, 0.35 + abs(0.5 - safeBrightness)))
        if safeBrightness >= 0.55 {
            return UIColor.black.withAlphaComponent(targetAlpha)
        } else {
            return UIColor.white.withAlphaComponent(targetAlpha)
        }
    }

    private func startStickerCreation() {
        DispatchQueue.global(qos: .userInitiated).async { [self, originalImage, parameters, plugin] in
            autoreleasepool {
                do {
                    let maskImage = try plugin.generateMask(for: originalImage)
                    let maskedCIImage = try plugin.buildMaskedImage(
                        preprocessedImage: originalImage,
                        maskImage: maskImage)
                    let preview = try plugin.uiImage(
                        from: maskedCIImage,
                        orientation: parameters.image.imageOrientation)

                    DispatchQueue.main.async {
                        self.stickerImage = preview
                        self.runStickerAnimation()
                    }

                    let stickerData: Data = try autoreleasepool {
                        let finalCIImage = plugin.addBorderIfNeeded(
                            to: maskedCIImage,
                            mask: maskImage,
                            parameters: parameters)
                        let renderedSticker = try plugin.renderImage(
                            finalCIImage,
                            originalImage: parameters.image)

                        guard let data = renderedSticker.pngData() else {
                            throw StickerMakerError.imageRenderingFailed
                        }
                        return data
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                        self.onComplete(stickerData)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.onError(error)
                    }
                }
            }
        }
    }

    @MainActor
    private func runStickerAnimation() {
        guard !hasAnimatedSticker else { return }
        hasAnimatedSticker = true

        spoilerViewOpacity = 0
        stickerScaleProgress = 0

        withAnimation(stickerAnimation) {
            spoilerViewOpacity = 1
        }

        withAnimation(.easeOut(duration: Self.stickerScaleAnimationDuration)) {
            stickerScaleProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stickerScaleAnimationDuration) {
            self.runStickerShakeIfNeeded()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.linear(duration: 0.75)) {
                spoilerViewOpacity = 0
            }
        }
    }

    @MainActor
    private func runStickerShakeIfNeeded() {
        guard parameters.speckleType == .flutteroverlay, !hasShakenSticker else { return }
        hasShakenSticker = true
        shakeProgress = 0
        withAnimation(.linear(duration: 0.42)) {
            shakeProgress = 1
        }
    }

    private var stickerScale: CGFloat {
        let progress = max(0, min(1, Double(stickerScaleProgress)))
        let minScale = 0.6
        let k = 5.0
        let denom = 1 - exp(-k)
        let eased = denom == 0 ? progress : (1 - exp(-k * progress)) / denom
        let scale = 1.0 + (minScale - 1.0) * eased
        return CGFloat(scale)
    }
}

private struct DampedShakeEffect: GeometryEffect {
    var progress: CGFloat
    var isEnabled: Bool

    private let cycles: CGFloat = 6.0
    private let baseAmplitude: CGFloat = 8.0

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard isEnabled else { return ProjectionTransform(.identity) }
        let clamped = max(0, min(1, progress))
        guard clamped > 0 else { return ProjectionTransform(.identity) }
        let damp = easeOutCubic(max(0, 1 - clamped))
        let x = sin(clamped * 2 * .pi * cycles) * baseAmplitude * damp
        let y = sin(clamped * 2 * .pi * cycles * 0.5) * (baseAmplitude / 3) * damp
        let transform = CGAffineTransform(translationX: x, y: y)
        return ProjectionTransform(transform)
    }

    private func easeOutCubic(_ value: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, value))
        return 1 - CGFloat(pow(Double(1 - clamped), 3))
    }
}

// MARK: - Spoiler View
final class EmitterView: UIView {
    override class var layerClass: AnyClass { CAEmitterLayer.self }

    override var layer: CAEmitterLayer { super.layer as! CAEmitterLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.emitterPosition = CGPoint(
            x: bounds.size.width / 2,
            y: bounds.size.height / 2)
        layer.emitterSize = bounds.size
    }
}

struct SpoilerView: UIViewRepresentable {
    var isOn: Bool
    var color: UIColor
    var speckleType: SpeckleType

    func makeUIView(context: Context) -> EmitterView {
        let emitterView = EmitterView()

        let resourceBundle = Bundle(for: FlutterStickerMakerPlugin.self)
        let emitterCell = CAEmitterCell()
        let config = speckleType.emitterSettings
        emitterCell.contents = Self.speckleImage(for: speckleType, in: resourceBundle)
        emitterCell.color = color.cgColor
        emitterCell.contentsScale = 1.8
        emitterCell.emissionRange = config.emissionRange
        emitterCell.lifetime = config.lifetime
        emitterCell.scale = config.scale
        emitterCell.velocityRange = config.velocity
        emitterCell.alphaRange = config.alphaRange
        emitterCell.birthRate = config.birthRate

        emitterView.layer.emitterShape = .rectangle
        emitterView.layer.emitterCells = [emitterCell]

        return emitterView
    }

    func updateUIView(_ uiView: EmitterView, context: Context) {
        if isOn {
            uiView.layer.beginTime = CACurrentMediaTime()
        }
        uiView.layer.birthRate = isOn ? 1 : 0
    }

    private static func speckleImage(for type: SpeckleType, in bundle: Bundle) -> CGImage {
        if
            let assetName = type.emitterSettings.assetName,
            let cgImage = UIImage(
                named: assetName,
                in: bundle,
                compatibleWith: nil
            )?.cgImage {
            return cgImage
        }
        return fallbackSpeckleImage(for: type)
    }

    private static func fallbackSpeckleImage(for type: SpeckleType) -> CGImage {
        let size = CGSize(width: 20, height: 20)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            switch type.emitterSettings.fallbackShape {
            case .circle:
                let inset = size.width * 0.4
                let circle = CGRect(origin: .zero, size: size)
                    .insetBy(dx: inset, dy: inset)
                context.cgContext.fillEllipse(in: circle)
            case .diamond:
                let path = UIBezierPath()
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = size.width * 0.35
                path.move(to: CGPoint(x: center.x, y: center.y - radius))
                path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
                path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
                path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
                path.close()
                path.fill()
            case .stripe:
                let stripeWidth = size.width * 0.2
                let rect = CGRect(
                    x: (size.width - stripeWidth) / 2,
                    y: size.height * 0.15,
                    width: stripeWidth,
                    height: size.height * 0.7)
                context.cgContext.fill(rect)
            }
        }
        guard let cgImage = image.cgImage else {
            preconditionFailure("Failed to render fallback speckle image")
        }
        return cgImage
    }
}

@available(iOS 17.0, *)
struct AnimatedSpeckleOverlay: View {
    var color: UIColor

    private static let animationDuration: TimeInterval = 1.4

    var body: some View {
        TimelineView(.animation) { context in
            SpeckleGradientField(
                baseColor: Color(uiColor: color),
                style: .flutterOverlay,
                phase: normalizedPhase(for: context.date))
        }
    }

    private func normalizedPhase(for date: Date) -> CGFloat {
        let cycle = Self.animationDuration
        guard cycle > 0 else { return 0 }
        let elapsed = date.timeIntervalSinceReferenceDate
        let progress = (elapsed.truncatingRemainder(dividingBy: cycle)) / cycle
        return CGFloat(progress)
    }
}

@available(iOS 17.0, *)
private struct SpeckleGradientField: View {
    let baseColor: Color
    let style: SpeckleStyleConfig
    let phase: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let primaryAlignment = alignment(for: phase)
            let secondaryAlignment = alignment(for: phase + 0.35)
            let radius = max(proxy.size.width, proxy.size.height) * 0.75

            ZStack {
                Rectangle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: baseColor.opacity(style.primaryOpacity), location: 0.0),
                                .init(color: baseColor.opacity(style.midOpacity), location: 0.45),
                                .init(color: .clear, location: 1.0)
                            ]),
                            center: primaryAlignment,
                            startRadius: 0,
                            endRadius: radius))

                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: baseColor.opacity(style.secondaryOpacity), location: 0.0),
                                .init(color: .clear, location: 1.0)
                            ]),
                            startPoint: secondaryAlignment,
                            endPoint: UnitPoint(
                                x: 1 - secondaryAlignment.x,
                                y: 1 - secondaryAlignment.y)))
            }
            .drawingGroup()
            .blur(radius: style.blurSigma)
        }
    }

    private func alignment(for progress: CGFloat) -> UnitPoint {
        let wrapped = progress.truncatingRemainder(dividingBy: 1)
        let angle = 2 * CGFloat.pi * wrapped
        let dx = cos(angle) * style.drift * 0.5
        let dy = sin(angle) * style.drift * 0.5
        return UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
    }
}

private struct SpeckleStyleConfig {
    let drift: CGFloat
    let primaryOpacity: CGFloat
    let midOpacity: CGFloat
    let secondaryOpacity: CGFloat
    let blurSigma: CGFloat

    static let flutterOverlay = SpeckleStyleConfig(
        drift: 0.88,
        primaryOpacity: 0.82,
        midOpacity: 0.32,
        secondaryOpacity: 0.42,
        blurSigma: 11)
}

private extension UIImage {
    var averageColor: UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let extent = inputImage.extent
        let parameters: [String: Any] = [
            kCIInputImageKey: inputImage,
            kCIInputExtentKey: CIVector(cgRect: extent)
        ]
        guard
            let filter = CIFilter(name: "CIAreaAverage", parameters: parameters),
            let outputImage = filter.outputImage else {
            return nil
        }
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB())
        return UIColor(
            red: CGFloat(bitmap[0]) / 255.0,
            green: CGFloat(bitmap[1]) / 255.0,
            blue: CGFloat(bitmap[2]) / 255.0,
            alpha: CGFloat(bitmap[3]) / 255.0)
    }
}

private extension CGColor {
    var brightnessFallback: CGFloat {
        guard let components = components else { return 0.5 }
        switch numberOfComponents {
        case 2:
            return components[0]
        case 4:
            let red = components[0]
            let green = components[1]
            let blue = components[2]
            return 0.2126 * red + 0.7152 * green + 0.0722 * blue
        default:
            return 0.5
        }
    }
}

#endif
