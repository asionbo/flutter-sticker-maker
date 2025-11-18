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
	@State private var stickerScale: CGFloat = 1.0
	@State private var spoilerViewOpacity: CGFloat = 0.0
	@State private var hasAnimatedSticker = false
	@State private var hasStartedProcessing = false

	private let stickerAnimation = Animation.spring(response: 0.5, dampingFraction: 0.75, blendDuration: 0.25)
	private let rotationAngle: Angle
	private let scaleTransform: CGSize
	private let spoilerColor: UIColor
	
	init(originalImage: UIImage, parameters: StickerParameters, plugin: FlutterStickerMakerPlugin, onComplete: @escaping (Data) -> Void, onError: @escaping (Error) -> Void) {
		self.originalImage = originalImage
		self.parameters = parameters
		self.plugin = plugin
		self.onComplete = onComplete
		self.onError = onError
		
		// Pre-compute transforms
		self.rotationAngle = Self.computeRotationAngle(for: originalImage.imageOrientation)
		self.scaleTransform = Self.computeScaleTransform(for: originalImage.imageOrientation)
		self.spoilerColor = Self.deriveSpoilerColor(from: originalImage)
	}

	var body: some View {
		ZStack {
			originalImageView
			stickerImageView
		}
		.onAppear {
			if !hasStartedProcessing {
				hasStartedProcessing = true
				startStickerCreation()
			}
		}
	}

	@ViewBuilder
	private var originalImageView: some View {
		Image(uiImage: originalImage)
			.resizable()
			.scaledToFit()
			.opacity(stickerImage == nil ? 1 : 0)
			.animation(stickerAnimation, value: stickerImage)
			.overlay {
				SpoilerView(isOn: true, color: spoilerColor)
					.opacity(spoilerViewOpacity)
			}
	}

	@ViewBuilder
	private var stickerImageView: some View {
		if let stickerImage {
			Image(uiImage: stickerImage)
				.resizable()
				.scaledToFit()
				.scaleEffect(stickerScale)
				.rotationEffect(rotationAngle)
				.scaleEffect(scaleTransform)
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
			return UIColor.label
		}
		// Increase brightness slightly so speckles stand out against matching tones
		var hue: CGFloat = 0
		var saturation: CGFloat = 0
		var brightness: CGFloat = 0
		var alpha: CGFloat = 0
		avgColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
		return UIColor(
			hue: hue,
			saturation: max(0.1, saturation),
			brightness: min(1.0, brightness + 0.15),
			alpha: alpha)
	}

	private func startStickerCreation() {
		DispatchQueue.global(qos: .userInitiated).async { [self, originalImage, parameters, plugin, onComplete, onError] in
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
		stickerScale = 0.9

		withAnimation(stickerAnimation) {
			spoilerViewOpacity = 1
			stickerScale = 1.1
		}

		DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
			withAnimation(.linear(duration: 0.25)) {
				spoilerViewOpacity = 0
			}
		}

		DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
			withAnimation(stickerAnimation) {
				stickerScale = 1.0
			}
		}
	}
}

// MARK: - Spoiler View
final class EmitterView: UIView {
	override class var layerClass: AnyClass { CAEmitterLayer.self }

	override var layer: CAEmitterLayer { super.layer as! CAEmitterLayer }

	override func layoutSubviews() {
		super.layoutSubviews()
		layer.emitterPosition = CGPoint(x: bounds.size.width / 2, y: bounds.size.height / 2)
		layer.emitterSize = bounds.size
	}
}

struct SpoilerView: UIViewRepresentable {
	var isOn: Bool
	var color: UIColor

	func makeUIView(context: Context) -> EmitterView {
		let emitterView = EmitterView()

		let resourceBundle = Bundle(for: FlutterStickerMakerPlugin.self)
		let emitterCell = CAEmitterCell()
		emitterCell.contents = Self.speckleImage(in: resourceBundle)
		emitterCell.color = color.cgColor
		emitterCell.contentsScale = 1.8
		emitterCell.emissionRange = .pi * 2
		emitterCell.lifetime = 1
		emitterCell.scale = 0.5
		emitterCell.velocityRange = 20
		emitterCell.alphaRange = 1
		emitterCell.birthRate = 4000

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

	private static func speckleImage(in bundle: Bundle) -> CGImage? {
		UIImage(
			named: "textSpeckle_Normal",
			in: bundle,
			compatibleWith: nil
		)?.cgImage ?? fallbackSpeckleImage
	}

	private static let fallbackSpeckleImage: CGImage = {
		let size = CGSize(width: 32, height: 32)
		let renderer = UIGraphicsImageRenderer(size: size)
		let image = renderer.image { context in
			context.cgContext.setFillColor(UIColor.white.cgColor)
			let inset = size.width * 0.2
			let circle = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
			context.cgContext.fillEllipse(in: circle)
		}
		guard let cgImage = image.cgImage else {
			preconditionFailure("Failed to render fallback speckle image")
		}
		return cgImage
	}()
}

private extension UIImage {
	var averageColor: UIColor? {
		guard let inputImage = CIImage(image: self) else { return nil }
		let extent = inputImage.extent
		let parameters: [String: Any] = [
			kCIInputImageKey: inputImage,
			kCIInputExtentKey: CIVector(cgRect: extent)
		]
		guard let filter = CIFilter(name: "CIAreaAverage", parameters: parameters),
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

#endif
