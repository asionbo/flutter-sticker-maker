import SwiftUI
import Vision
import CoreImage

// MARK: - Visual Effect State
@available(iOS 18.0, *)
class VisualEffectState: ObservableObject {
    @Published var animationProgress: CGFloat = 0.0
    @Published var isPresented: Bool = true
}

// MARK: - Visual Effect View for iOS 18+
@available(iOS 18.0, *)
struct VisualEffectView: View {
    let image: UIImage
    let mask: CIImage?
    @ObservedObject var state: VisualEffectState
    
    var body: some View {
        ZStack {
            // Blurred background
            if let ciImage = CIImage(image: image) {
                Image(uiImage: applyBlur(to: ciImage))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(1.0 - Double(state.animationProgress))
            }
            
            // Highlighted mask overlay
            if let mask = mask,
               let highlightedImage = applyHighlight(to: image, with: mask) {
                Image(uiImage: highlightedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(Double(state.animationProgress))
                    .scaleEffect(1.0 + (state.animationProgress * 0.1))
            }
        }
        .background(Color.black.opacity(0.3))
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            // Start animation after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 1.0)) {
                    state.animationProgress = 1.0
                }
            }
        }
    }
    
    private func applyBlur(to image: CIImage) -> UIImage {
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = image
        blurFilter.radius = 15.0
        
        let context = CIContext()
        if let outputImage = blurFilter.outputImage,
           let cgImage = context.createCGImage(outputImage, from: image.extent) {
            return UIImage(cgImage: cgImage)
        }
        return UIImage()
    }
    
    private func applyHighlight(to image: UIImage, with mask: CIImage) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        
        // Create a glow effect for the mask
        let glowFilter = CIFilter.bloom()
        glowFilter.inputImage = mask
        glowFilter.intensity = 0.5
        glowFilter.radius = 10.0
        
        // Blend the glowing mask with the original image
        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = ciImage
        blendFilter.maskImage = mask
        blendFilter.backgroundImage = CIImage.empty()
        
        let context = CIContext()
        guard let outputImage = blendFilter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: ciImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}

// MARK: - View Controller for SwiftUI Integration
@available(iOS 18.0, *)
class VisualEffectViewController: UIViewController {
    private var hostingController: UIHostingController<VisualEffectView>?
    private var state: VisualEffectState?
    private var onDismiss: (() -> Void)?
    
    func present(image: UIImage, mask: CIImage?, from viewController: UIViewController, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        
        let state = VisualEffectState()
        self.state = state
        
        let visualEffectView = VisualEffectView(
            image: image,
            mask: mask,
            state: state
        )
        
        hostingController = UIHostingController(rootView: visualEffectView)
        hostingController?.modalPresentationStyle = .overFullScreen
        hostingController?.modalTransitionStyle = .crossDissolve
        
        if let hostingController = hostingController {
            viewController.present(hostingController, animated: true)
        }
    }
    
    func dismiss(completion: @escaping () -> Void) {
        // Animate out
        withAnimation(.easeOut(duration: 0.5)) {
            state?.animationProgress = 0.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.hostingController?.dismiss(animated: true) {
                completion()
                self.onDismiss?()
            }
        }
    }
}
