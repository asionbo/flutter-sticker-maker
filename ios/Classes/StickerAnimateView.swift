#if canImport(UIKit) && canImport(SwiftUI)
import SwiftUI
import UIKit

@available(iOS 18.0, *)
struct StickerAnimateView: View {
	let originalImage: UIImage
	let stickerImage: UIImage?

	@State private var stickerScale: CGFloat = 1.0
	@State private var spoilerViewOpacity: CGFloat = 0.0
	@State private var hasAnimatedSticker = false

	private let stickerAnimation = Animation.spring(response: 0.5, dampingFraction: 0.75, blendDuration: 0.25)

	var body: some View {
		ZStack {
			originalImageView
			stickerImageView
		}
		.padding(32)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(Color.black.opacity(0.85))
	}

	@ViewBuilder
	private var originalImageView: some View {
		Image(uiImage: originalImage)
			.resizable()
			.scaledToFit()
			.opacity(stickerImage == nil ? 1 : 0)
			.animation(stickerAnimation, value: stickerImage)
			.overlay {
				SpoilerView(isOn: true)
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
				.onAppear { runStickerAnimation() }
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

	func makeUIView(context: Context) -> EmitterView {
		let emitterView = EmitterView()

		let resourceBundle = Bundle(for: FlutterStickerMakerPlugin.self)
		let emitterCell = CAEmitterCell()
		emitterCell.contents = Self.speckleImage(in: resourceBundle)
		emitterCell.color = UIColor.label.cgColor
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

#endif
