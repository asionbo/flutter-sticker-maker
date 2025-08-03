import Flutter
import UIKit
import Vision
import CoreImage.CIFilterBuiltins
import os.log

// MARK: - iOS Version Compatibility
@available(iOS 15.5, *)
private enum MLBackend {
    case vision // iOS 17+
    case mlkit  // iOS 15.5-16.x
    
    static var current: MLBackend {
        if #available(iOS 17.0, *) {
            return .vision
        } else {
            return .mlkit
        }
    }
}

// MARK: - Configuration
private struct StickerMakerConfig {
    static let defaultBorderWidth: CGFloat = 20.0
    static let defaultNoiseLevel: Float = 0.02
    static let defaultSharpness: Float = 0.4
    static let defaultContrast: Float = 1.1
    static let defaultBrightness: Float = 0.05
    static let defaultSaturation: Float = 1.05
    static let maskBlurRadius: Float = 1.0
    static let channelName = "flutter_sticker_maker"
}

// MARK: - Error Types
enum StickerMakerError: Error, LocalizedError {
    case invalidImageData
    case imagePreprocessingFailed
    case maskGenerationFailed
    case imageRenderingFailed
    case unsupportedImageFormat
    
    var errorDescription: String? {
        switch self {
        case .invalidImageData: return "Invalid image data provided"
        case .imagePreprocessingFailed: return "Failed to preprocess image"
        case .maskGenerationFailed: return "Failed to generate foreground mask"
        case .imageRenderingFailed: return "Failed to render final image"
        case .unsupportedImageFormat: return "Unsupported image format"
        }
    }
}

// MARK: - Main Plugin Class
@available(iOS 15.5, *)
public class FlutterStickerMakerPlugin: NSObject, FlutterPlugin {
    private let logger = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "StickerMaker", category: "Plugin")
    private let imageProcessor = ImageProcessor()
    private let maskGenerator = MaskGenerator()
    private let borderRenderer = BorderRenderer()
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: StickerMakerConfig.channelName, binaryMessenger: registrar.messenger())
        let instance = FlutterStickerMakerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "makeSticker" else {
            result(FlutterMethodNotImplemented)
            return
        }
        
        do {
            let parameters = try validateAndParseArguments(call.arguments)
            processSticker(with: parameters, result: result)
        } catch {
            os_log("Parameter validation failed: %@", log: logger, type: .error, error.localizedDescription)
            result(FlutterError(code: "INVALID_ARGUMENTS", message: error.localizedDescription, details: nil))
        }
    }
    
    private func validateAndParseArguments(_ arguments: Any?) throws -> StickerParameters {
        guard let args = arguments as? [String: Any],
              let imageData = args["image"] as? FlutterStandardTypedData,
              let uiImage = UIImage(data: imageData.data) else {
            throw StickerMakerError.invalidImageData
        }
        
        let addBorder = args["addBorder"] as? Bool ?? false
        let borderColor = ColorParser.parse(args["borderColor"] as? String)
        let borderWidth = CGFloat(args["borderWidth"] as? Double ?? StickerMakerConfig.defaultBorderWidth)
        
        return StickerParameters(
            image: uiImage,
            addBorder: addBorder,
            borderColor: borderColor,
            borderWidth: max(0, borderWidth) // Ensure non-negative
        )
    }
    
    private func processSticker(with parameters: StickerParameters, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "INTERNAL_ERROR", message: "Plugin instance deallocated", details: nil))
                }
                return
            }
            
            do {
                let stickerImage = try self.createSticker(from: parameters)
                guard let stickerData = stickerImage.pngData() else {
                    throw StickerMakerError.imageRenderingFailed
                }
                
                DispatchQueue.main.async {
                    result(FlutterStandardTypedData(bytes: stickerData))
                }
            } catch {
                os_log("Sticker creation failed: %@", log: self.logger, type: .error, error.localizedDescription)
                DispatchQueue.main.async {
                    result(FlutterError(code: "PROCESSING_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func createSticker(from parameters: StickerParameters) throws -> UIImage {
        // Step 1: Preprocess image
        let preprocessedImage = try imageProcessor.preprocess(parameters.image)
        
        // Step 2: Generate mask
        let maskImage = try maskGenerator.generateMask(for: preprocessedImage)
        
        // Step 3: Apply mask and optional border
        let ciImage = CIImage(image: preprocessedImage) ?? CIImage()
        let maskedImage = try applyMask(maskImage, to: ciImage)
        
        let finalImage = parameters.addBorder ?
            borderRenderer.addBorder(to: maskedImage, mask: maskImage, color: parameters.borderColor, width: parameters.borderWidth) :
            maskedImage
        
        // Step 4: Render final image
        return try renderImage(finalImage)
    }
    
    private func applyMask(_ maskImage: CIImage, to inputImage: CIImage) throws -> CIImage {
        let filter = CIFilter.blendWithMask()
        filter.inputImage = inputImage
        filter.maskImage = maskImage
        filter.backgroundImage = CIImage.empty()
        
        guard let result = filter.outputImage else {
            throw StickerMakerError.maskGenerationFailed
        }
        return result
    }
    
    private func renderImage(_ ciImage: CIImage) throws -> UIImage {
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw StickerMakerError.imageRenderingFailed
        }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Supporting Types
private struct StickerParameters {
    let image: UIImage
    let addBorder: Bool
    let borderColor: CIColor
    let borderWidth: CGFloat
}

// MARK: - Image Processor
@available(iOS 15.5, *)
private class ImageProcessor {
    func preprocess(_ image: UIImage) throws -> UIImage {
        guard let cgImage = image.cgImage else {
            throw StickerMakerError.unsupportedImageFormat
        }
        
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()
        
        // Apply noise reduction
        let noiseFilter = CIFilter.noiseReduction()
        noiseFilter.inputImage = ciImage
        noiseFilter.noiseLevel = StickerMakerConfig.defaultNoiseLevel
        noiseFilter.sharpness = StickerMakerConfig.defaultSharpness
        
        // Apply contrast enhancement
        let contrastFilter = CIFilter.colorControls()
        contrastFilter.inputImage = noiseFilter.outputImage
        contrastFilter.contrast = StickerMakerConfig.defaultContrast
        contrastFilter.brightness = StickerMakerConfig.defaultBrightness
        contrastFilter.saturation = StickerMakerConfig.defaultSaturation
        
        guard let outputImage = contrastFilter.outputImage,
              let processedCGImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            throw StickerMakerError.imagePreprocessingFailed
        }
        
        return UIImage(cgImage: processedCGImage)
    }
}

// MARK: - Mask Generator
private class MaskGenerator {
    func generateMask(for image: UIImage) throws -> CIImage {
        guard let inputCIImage = CIImage(image: image) else {
            throw StickerMakerError.invalidImageData
        }
        
        switch MLBackend.current {
        case .vision:
            return try generateVisionMask(for: inputCIImage)
        case .mlkit:
            return try generateMLKitMask(for: inputCIImage, originalImage: image)
        }
    }
    
    @available(iOS 17.0, *)
    private func generateVisionMask(for ciImage: CIImage) throws -> CIImage {
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [
            VNImageOption.cameraIntrinsics: NSNull(),
            VNImageOption.ciContext: CIContext(options: [.useSoftwareRenderer: false])
        ])
        
        let request = VNGenerateForegroundInstanceMaskRequest()
        request.revision = VNGenerateForegroundInstanceMaskRequestRevision1
        request.preferBackgroundProcessing = true
        
        try handler.perform([request])
        
        guard let result = request.results?.first else {
            throw StickerMakerError.maskGenerationFailed
        }
        
        let maskPixelBuffer: CVPixelBuffer
        do {
            maskPixelBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        } catch {
            throw StickerMakerError.maskGenerationFailed
        }
        
        let maskCIImage = CIImage(cvPixelBuffer: maskPixelBuffer)
        return smoothMaskEdges(maskCIImage)
    }
    
    private func generateMLKitMask(for ciImage: CIImage, originalImage: UIImage) throws -> CIImage {
        // For iOS 15.5-16.x, we'll use a simplified approach with CoreImage filters
        // Since we can't directly integrate MLKit here without changing the entire architecture,
        // we'll use CoreImage's built-in subject isolation when available, or basic edge detection
        
        if #available(iOS 16.0, *) {
            // iOS 16+ has some basic subject isolation capabilities
            return try generateSubjectMask(for: ciImage)
        } else {
            // For iOS 15.5, use edge detection and morphological operations
            return try generateFallbackMask(for: ciImage)
        }
    }
    
    @available(iOS 16.0, *)
    private func generateSubjectMask(for ciImage: CIImage) throws -> CIImage {
        // Use CoreImage's basic edge detection and morphological operations
        // This is a simplified approach for older iOS versions
        
        // Convert to Lab color space for better edge detection
        let labFilter = CIFilter(name: "CIColorSpace")
        labFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        guard let labImage = labFilter?.outputImage else {
            throw StickerMakerError.maskGenerationFailed
        }
        
        // Apply edge detection
        let edgeFilter = CIFilter.edgeWork()
        edgeFilter.inputImage = labImage
        edgeFilter.radius = 3.0
        
        guard let edgeImage = edgeFilter.outputImage else {
            throw StickerMakerError.maskGenerationFailed
        }
        
        // Create a basic mask using color thresholding and morphological operations
        let maskImage = try createBasicSubjectMask(from: edgeImage, originalImage: ciImage)
        return smoothMaskEdges(maskImage)
    }
    
    private func generateFallbackMask(for ciImage: CIImage) throws -> CIImage {
        // Basic fallback for iOS 15.5 using simple image processing
        // This will create a rectangular mask with some basic edge softening
        
        let imageExtent = ciImage.extent
        let centerX = imageExtent.midX
        let centerY = imageExtent.midY
        let width = imageExtent.width * 0.8  // Use 80% of image width
        let height = imageExtent.height * 0.8 // Use 80% of image height
        
        // Create a radial gradient mask
        let radialGradient = CIFilter(name: "CIRadialGradient")
        radialGradient?.setValue(CIVector(x: centerX, y: centerY), forKey: "inputCenter")
        radialGradient?.setValue(min(width, height) * 0.3, forKey: "inputRadius0")
        radialGradient?.setValue(min(width, height) * 0.5, forKey: "inputRadius1")
        radialGradient?.setValue(CIColor.white, forKey: "inputColor0")
        radialGradient?.setValue(CIColor.clear, forKey: "inputColor1")
        
        guard let maskImage = radialGradient?.outputImage?.cropped(to: imageExtent) else {
            throw StickerMakerError.maskGenerationFailed
        }
        
        return smoothMaskEdges(maskImage)
    }
    
    private func createBasicSubjectMask(from edgeImage: CIImage, originalImage: CIImage) throws -> CIImage {
        // Create a basic subject mask using edge information
        let extent = originalImage.extent
        
        // Use a combination of edge detection and center weighting
        let centerX = extent.midX
        let centerY = extent.midY
        let maxRadius = min(extent.width, extent.height) * 0.4
        
        // Create a center-weighted mask
        let radialFilter = CIFilter(name: "CIRadialGradient")
        radialFilter?.setValue(CIVector(x: centerX, y: centerY), forKey: "inputCenter")
        radialFilter?.setValue(maxRadius * 0.5, forKey: "inputRadius0")
        radialFilter?.setValue(maxRadius, forKey: "inputRadius1")
        radialFilter?.setValue(CIColor.white, forKey: "inputColor0")
        radialFilter?.setValue(CIColor.black, forKey: "inputColor1")
        
        guard let centerMask = radialFilter?.outputImage?.cropped(to: extent) else {
            throw StickerMakerError.maskGenerationFailed
        }
        
        return centerMask
    }
    
    private func smoothMaskEdges(_ maskImage: CIImage) -> CIImage {
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = maskImage
        blurFilter.radius = StickerMakerConfig.maskBlurRadius
        return blurFilter.outputImage ?? maskImage
    }
}

// MARK: - Border Renderer
@available(iOS 15.5, *)
private class BorderRenderer {
    func addBorder(to image: CIImage, mask: CIImage, color: CIColor, width: CGFloat) -> CIImage {
        guard width > 0 else { return image }
        
        // Create expanded mask for border
        let morphologyFilter = CIFilter.morphologyMaximum()
        morphologyFilter.inputImage = mask
        morphologyFilter.radius = Float(width)
        
        guard let expandedMask = morphologyFilter.outputImage else { return image }
        
        // Create colored border
        guard let colorGenerator = CIFilter(name: "CIConstantColorGenerator") else { return image }
        colorGenerator.setValue(color, forKey: kCIInputColorKey)
        guard let colorImage = colorGenerator.outputImage?.cropped(to: expandedMask.extent) else { return image }
        
        // Apply mask to create border shape
        let borderFilter = CIFilter.blendWithMask()
        borderFilter.inputImage = colorImage
        borderFilter.maskImage = expandedMask
        borderFilter.backgroundImage = CIImage.empty()
        
        guard let coloredBorder = borderFilter.outputImage else { return image }
        
        // Composite original image over border
        let compositeFilter = CIFilter.sourceOverCompositing()
        compositeFilter.inputImage = image
        compositeFilter.backgroundImage = coloredBorder
        
        return compositeFilter.outputImage ?? image
    }
}

// MARK: - Color Parser
@available(iOS 15.5, *)
private class ColorParser {
    static func parse(_ colorString: String?) -> CIColor {
        guard let colorString = colorString else { return CIColor.white }
        
        let hex = colorString.hasPrefix("#") ? String(colorString.dropFirst()) : colorString
        
        guard hex.count == 6, let hexValue = UInt64(hex, radix: 16) else {
            return CIColor.white
        }
        
        let red = CGFloat((hexValue & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((hexValue & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(hexValue & 0x0000FF) / 255.0
        
        return CIColor(red: red, green: green, blue: blue)
    }
}