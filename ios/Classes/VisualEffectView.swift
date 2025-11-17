#if canImport(UIKit)
import SwiftUI
import Vision
import CoreImage
import UIKit

// MARK: - Visual Effect State
@available(iOS 18.0, *)
class VisualEffectState: ObservableObject {
    @Published var liftProgress: CGFloat = 0.0
    @Published var progress: CGFloat = 0.05
    @Published var statusText: String = "Preparing sticker…"
    @Published var mask: CIImage?
    @Published var isPresented: Bool = true
}

// MARK: - Visual Effect View for iOS 18+
@available(iOS 18.0, *)
struct VisualEffectView: View {
    let image: UIImage
    @ObservedObject var state: VisualEffectState
    // smaller, snappy animation duration for a pleasant UX
    private let shortAnimationDuration: Double = 0.18
    
    var body: some View {
        ZStack {
            // Blurred background respects original orientation
            if let blurredImage = applyBlur(to: image) {
                Image(uiImage: blurredImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(Double(1.0 - (backgroundDismissAmount * 0.9)))
                    .scaleEffect(1.0 - (backgroundDismissAmount * 0.04))
                    .offset(y: -backgroundDismissAmount * 45.0)
                    // preserve original UIImage orientation by applying equivalent SwiftUI transforms
                    .rotationEffect(.degrees(orientationRotationAngle(for: image)))
                    .scaleEffect(x: orientationScaleX(for: image), y: 1.0)
            }
            
            // Highlighted mask overlay
            if let mask = state.mask,
               let highlightedImage = applyHighlight(to: image, with: mask) {
                Image(uiImage: highlightedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(Double(state.liftProgress))
                    .scaleEffect(1.0 + (state.liftProgress * 0.08))
                    .offset(y: -state.liftProgress * 24.0)
                    .rotation3DEffect(
                        .degrees(Double(state.liftProgress) * -6.0),
                        axis: (x: 1, y: 0, z: 0),
                        perspective: 0.7
                    )
                    .shadow(
                        color: Color.black.opacity(0.25 * Double(state.liftProgress)),
                        radius: 25,
                        x: 0,
                        y: 18 * (1 - Double(state.liftProgress) * 0.5)
                    )
                    // keep mask aligned to original image orientation
                    .rotationEffect(.degrees(orientationRotationAngle(for: image)))
                    .scaleEffect(x: orientationScaleX(for: image), y: 1.0)
            }
            progressHud
        }
        .background(Color.black.opacity(0.3))
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            // Kick off a subtle lift to indicate work has started
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                withAnimation(.easeInOut(duration: self.shortAnimationDuration)) {
                    state.liftProgress = 0.35
                }
            }
        }
    }

    private var backgroundDismissAmount: CGFloat {
        min(max(state.liftProgress, 0.0), 1.0)
    }
    
    private var progressHud: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                 ProgressView(value: Double(min(max(state.progress, 0.0), 1.0)))
                     .progressViewStyle(LinearProgressViewStyle())
                     .tint(.white)
             }
             .padding(.horizontal, 24)
             .padding(.vertical, 18)
             .background(Color.black.opacity(0.45))
             .cornerRadius(18)
             .padding(.bottom, 48)
             .padding(.horizontal, 32)
         }
     }
 
     // MARK: - Orientation helpers
     private func orientationRotationAngle(for image: UIImage) -> Double {
         switch image.imageOrientation {
         case .up: return 0
         case .down: return 180
         case .left: return 90
         case .right: return -90
         case .upMirrored: return 0
         case .downMirrored: return 180
         case .leftMirrored: return 90
         case .rightMirrored: return -90
         @unknown default:
             return 0
         }
     }
 
     private func orientationScaleX(for image: UIImage) -> CGFloat {
         switch image.imageOrientation {
         case .upMirrored, .downMirrored, .leftMirrored, .rightMirrored:
             return -1.0
         default:
             return 1.0
         }
     }
    
    private func applyBlur(to image: UIImage) -> UIImage? {
        guard let orientedImage = orientedCIImage(from: image) else { return nil }
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = orientedImage
        blurFilter.radius = 15.0
        
        let context = CIContext()
        if let outputImage = blurFilter.outputImage,
           let cgImage = context.createCGImage(outputImage, from: orientedImage.extent) {
            return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        }
        return nil
    }
    
    private func applyHighlight(to image: UIImage, with mask: CIImage) -> UIImage? {
        guard let ciImage = orientedCIImage(from: image) else { return nil }
        let orientedMask = mask.cropped(to: ciImage.extent)
        
        // Create a glow effect for the mask
        let glowFilter = CIFilter.bloom()
        glowFilter.inputImage = orientedMask
        glowFilter.intensity = 0.5
        glowFilter.radius = 10.0
        
        // Blend the glowing mask with the original image
        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = ciImage
        blendFilter.maskImage = orientedMask
        blendFilter.backgroundImage = CIImage.empty()
        
        let context = CIContext()
        guard let outputImage = blendFilter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: ciImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    private func orientedCIImage(from image: UIImage) -> CIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return ciImage.oriented(orientation)
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}

// MARK: - View Controller for SwiftUI Integration
@available(iOS 18.0, *)
class VisualEffectViewController: UIViewController {
    private var hostingController: UIHostingController<VisualEffectView>?
    private var state = VisualEffectState()
    private var onDismiss: (() -> Void)?
    // short animation duration for controller-driven animations (match view)
    private let shortAnimationDuration: Double = 0.18

    func present(image: UIImage, from viewController: UIViewController, initialStatus: String, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        state.statusText = initialStatus
        state.progress = 0.05
        state.mask = nil
        state.liftProgress = 0.0
        state.isPresented = true

        let visualEffectView = VisualEffectView(
            image: image,
            state: state
        )

        hostingController = UIHostingController(rootView: visualEffectView)
        hostingController?.modalPresentationStyle = .overFullScreen
        hostingController?.modalTransitionStyle = .crossDissolve

        if let hostingController = hostingController {
            viewController.present(hostingController, animated: true)
        }
    }

    func updateStatus(_ status: String, progress: CGFloat? = nil) {
        DispatchQueue.main.async {
            self.state.statusText = status
            if let progress = progress {
                self.state.progress = min(max(progress, 0.0), 1.0)
            }
        }
    }

    func updateMask(_ mask: CIImage?, progress: CGFloat? = nil, animateLift: Bool = false) {
        DispatchQueue.main.async {
            self.state.mask = mask
            if let progress = progress {
                self.state.progress = min(max(progress, 0.0), 1.0)
            }
            guard animateLift else { return }
            withAnimation(.easeInOut(duration: self.shortAnimationDuration)) {
                self.state.liftProgress = 1.0
            }
          }
      }

    func complete(with status: String, completion: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.state.statusText = status
            self.state.progress = 1.0
            withAnimation(.easeInOut(duration: self.shortAnimationDuration)) {
               self.state.liftProgress = 1.0
            }
            self.dismiss(completion: completion)
        }
    }

    func fail(with status: String, completion: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.state.statusText = status
            self.state.progress = 1.0
            self.dismiss(completion: completion)
        }
    }

    private func dismiss(completion: @escaping () -> Void) {
        withAnimation(.easeOut(duration: self.shortAnimationDuration)) {
            self.state.liftProgress = 0.0
            self.state.isPresented = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + self.shortAnimationDuration) {
             if let hostingController = self.hostingController {
                 hostingController.dismiss(animated: true) {
                     completion()
                     self.onDismiss?()
                     self.hostingController = nil
                 }
             } else {
                 completion()
                 self.onDismiss?()
             }
         }
     }
 }
 #endif
