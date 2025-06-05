package com.asionbo.flutter_sticker_maker

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.Segmentation
import com.google.mlkit.vision.segmentation.selfie.SelfieSegmenterOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import kotlin.math.*

class FlutterStickerMakerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val executor = Executors.newSingleThreadExecutor()

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_sticker_maker")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "makeSticker") {
            val imageBytes = call.argument<ByteArray>("image")
            val addBorder = call.argument<Boolean>("addBorder") ?: false
            val borderColor = call.argument<String>("borderColor") ?: "#FFFFFF"
            val borderWidth = call.argument<Double>("borderWidth")?.toInt() ?: 12
            val quality = call.argument<String>("quality") ?: "medium" // low, medium, high
            if (imageBytes != null) {
                // Process on background thread to avoid blocking UI
                executor.execute {
                    processSticker(imageBytes, addBorder, borderColor, borderWidth, quality, result)
                }
            } else {
                result.error("NO_IMAGE", "No image provided", null)
            }
        } else {
            result.notImplemented()
        }
    }

    private fun processSticker(imageBytes: ByteArray, addBorder: Boolean, borderColor: String, borderWidth: Int, quality: String, result: MethodChannel.Result) {
        try {
            val originalBitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
            
            // Optimize image size based on quality setting
            val optimizedBitmap = optimizeImageSize(originalBitmap, quality)
            val preprocessedBitmap = preprocessImage(optimizedBitmap)
            val inputImage = InputImage.fromBitmap(preprocessedBitmap, 0)
            
            // Enhanced segmentation options
            val optionsBuilder = SelfieSegmenterOptions.Builder()
                .setDetectorMode(SelfieSegmenterOptions.SINGLE_IMAGE_MODE)
                .enableRawSizeMask()

           
            val segmenter = Segmentation.getClient(optionsBuilder.build())

            segmenter.process(inputImage)
                .addOnSuccessListener { segmentationMask ->
                    try {
                        val mask = segmentationMask.buffer
                        mask.rewind()
                        val maskWidth = segmentationMask.width
                        val maskHeight = segmentationMask.height
                        val maskArray = FloatArray(maskWidth * maskHeight)
                        mask.asFloatBuffer().get(maskArray)
                        
                        // Apply advanced mask processing
                        val refinedMask = refineSegmentationMask(maskArray, maskWidth, maskHeight, quality)
                        
                        // Scale mask to original image dimensions
                        val scaledMask = scaleMaskToOriginalSize(
                            refinedMask, 
                            maskWidth, 
                            maskHeight, 
                            optimizedBitmap.width, 
                            optimizedBitmap.height
                        )
                        
                        val stickerBitmap = createStickerBitmap(
                            optimizedBitmap, 
                            scaledMask, 
                            optimizedBitmap.width, 
                            optimizedBitmap.height, 
                            addBorder, 
                            borderColor, 
                            borderWidth,
                            quality
                        )
                        
                        val outputStream = ByteArrayOutputStream()
                        val compressionQuality = when (quality) {
                            "low" -> 70
                            "medium" -> 85
                            else -> 100
                        }
                        stickerBitmap.compress(Bitmap.CompressFormat.PNG, compressionQuality, outputStream)
                        val outputBytes = outputStream.toByteArray()
                        
                        Handler(Looper.getMainLooper()).post {
                            result.success(outputBytes)
                        }
                    } catch (e: Exception) {
                        Handler(Looper.getMainLooper()).post {
                            result.error("PROCESSING_FAILED", e.localizedMessage, null)
                        }
                    }
                }
                .addOnFailureListener { e ->
                    Handler(Looper.getMainLooper()).post {
                        result.error("SEGMENTATION_FAILED", e.localizedMessage, null)
                    }
                }
        } catch (e: Exception) {
            Handler(Looper.getMainLooper()).post {
                result.error("IMAGE_PROCESSING_FAILED", e.localizedMessage, null)
            }
        }
    }
    
    private fun optimizeImageSize(bitmap: Bitmap, quality: String): Bitmap {
        val maxDimension = when (quality) {
            "low" -> 512
            "medium" -> 1024
            else -> 2048
        }
        
        val currentMax = max(bitmap.width, bitmap.height)
        return if (currentMax > maxDimension) {
            val scale = maxDimension.toFloat() / currentMax
            val newWidth = (bitmap.width * scale).toInt()
            val newHeight = (bitmap.height * scale).toInt()
            Bitmap.createScaledBitmap(bitmap, newWidth, newHeight, true)
        } else {
            bitmap
        }
    }
    
    private fun preprocessImage(bitmap: Bitmap): Bitmap {
        // Enhanced preprocessing with adaptive contrast
        val matrix = android.graphics.ColorMatrix()
        matrix.setSaturation(1.2f)
        
        // Adaptive contrast based on image brightness
        val brightness = calculateImageBrightness(bitmap)
        val contrastFactor = if (brightness < 0.3f) 1.3f else if (brightness > 0.7f) 0.9f else 1.1f
        val brightnessFactor = if (brightness < 0.3f) 20f else if (brightness > 0.7f) -10f else 5f
        
        val contrastMatrix = android.graphics.ColorMatrix(floatArrayOf(
            contrastFactor, 0f, 0f, 0f, brightnessFactor,
            0f, contrastFactor, 0f, 0f, brightnessFactor,
            0f, 0f, contrastFactor, 0f, brightnessFactor,
            0f, 0f, 0f, 1f, 0f
        ))
        matrix.postConcat(contrastMatrix)
        
        val enhancedBitmap = Bitmap.createBitmap(bitmap.width, bitmap.height, bitmap.config ?: Bitmap.Config.ARGB_8888)
        val canvas = Canvas(enhancedBitmap)
        val paint = Paint().apply {
            colorFilter = android.graphics.ColorMatrixColorFilter(matrix)
            isAntiAlias = true
            isDither = true
            isFilterBitmap = true
        }
        canvas.drawBitmap(bitmap, 0f, 0f, paint)
        
        return enhancedBitmap
    }
    
    private fun calculateImageBrightness(bitmap: Bitmap): Float {
        var totalBrightness = 0f
        val sampleSize = 10 // Sample every 10th pixel for performance
        var pixelCount = 0
        
        for (y in 0 until bitmap.height step sampleSize) {
            for (x in 0 until bitmap.width step sampleSize) {
                val pixel = bitmap.getPixel(x, y)
                val r = (pixel shr 16) and 0xFF
                val g = (pixel shr 8) and 0xFF
                val b = pixel and 0xFF
                totalBrightness += (0.299f * r + 0.587f * g + 0.114f * b) / 255f
                pixelCount++
            }
        }
        
        return totalBrightness / pixelCount
    }
    
    private fun refineSegmentationMask(maskArray: FloatArray, width: Int, height: Int, quality: String): FloatArray {
        val iterations = when (quality) {
            "low" -> 1
            "medium" -> 2
            else -> 3
        }
        
        var refinedMask = maskArray.clone()
        
        // Apply multiple refinement passes
        repeat(iterations) {
            refinedMask = applyMorphologicalOperations(refinedMask, width, height)
            refinedMask = smoothMaskEdges(refinedMask, width, height, quality)
        }
        
        // Apply edge-preserving filter
        refinedMask = applyBilateralFilter(refinedMask, width, height)
        
        return refinedMask
    }
    
    private fun applyMorphologicalOperations(maskArray: FloatArray, width: Int, height: Int): FloatArray {
        // Opening operation (erosion followed by dilation) to remove noise
        val eroded = erodeMask(maskArray, width, height)
        return dilateMask(eroded, width, height)
    }
    
    private fun erodeMask(maskArray: FloatArray, width: Int, height: Int): FloatArray {
        val result = FloatArray(width * height)
        val kernel = arrayOf(
            intArrayOf(-1, -1), intArrayOf(-1, 0), intArrayOf(-1, 1),
            intArrayOf(0, -1), intArrayOf(0, 0), intArrayOf(0, 1),
            intArrayOf(1, -1), intArrayOf(1, 0), intArrayOf(1, 1)
        )
        
        for (y in 1 until height - 1) {
            for (x in 1 until width - 1) {
                var minVal = 1f
                for (offset in kernel) {
                    val nx = x + offset[0]
                    val ny = y + offset[1]
                    if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
                        minVal = min(minVal, maskArray[ny * width + nx])
                    }
                }
                result[y * width + x] = minVal
            }
        }
        return result
    }
    
    private fun dilateMask(maskArray: FloatArray, width: Int, height: Int): FloatArray {
        val result = FloatArray(width * height)
        val kernel = arrayOf(
            intArrayOf(-1, -1), intArrayOf(-1, 0), intArrayOf(-1, 1),
            intArrayOf(0, -1), intArrayOf(0, 0), intArrayOf(0, 1),
            intArrayOf(1, -1), intArrayOf(1, 0), intArrayOf(1, 1)
        )
        
        for (y in 1 until height - 1) {
            for (x in 1 until width - 1) {
                var maxVal = 0f
                for (offset in kernel) {
                    val nx = x + offset[0]
                    val ny = y + offset[1]
                    if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
                        maxVal = max(maxVal, maskArray[ny * width + nx])
                    }
                }
                result[y * width + x] = maxVal
            }
        }
        return result
    }
    
    private fun applyBilateralFilter(maskArray: FloatArray, width: Int, height: Int): FloatArray {
        val filtered = FloatArray(width * height)
        val spatialSigma = 2.0
        val intensitySigma = 0.1
        val kernelRadius = 2
        
        for (y in kernelRadius until height - kernelRadius) {
            for (x in kernelRadius until width - kernelRadius) {
                var weightSum = 0.0
                var valueSum = 0.0
                val centerValue = maskArray[y * width + x]
                
                for (ky in -kernelRadius..kernelRadius) {
                    for (kx in -kernelRadius..kernelRadius) {
                        val nx = x + kx
                        val ny = y + ky
                        val neighborValue = maskArray[ny * width + nx]
                        
                        val spatialDist = sqrt((kx * kx + ky * ky).toDouble())
                        val intensityDist = abs(centerValue - neighborValue).toDouble()
                        
                        val spatialWeight = exp(-(spatialDist * spatialDist) / (2 * spatialSigma * spatialSigma))
                        val intensityWeight = exp(-(intensityDist * intensityDist) / (2 * intensitySigma * intensitySigma))
                        val weight = spatialWeight * intensityWeight
                        
                        weightSum += weight
                        valueSum += weight * neighborValue
                    }
                }
                
                filtered[y * width + x] = (valueSum / weightSum).toFloat()
            }
        }
        
        return filtered
    }
    
    private fun smoothMaskEdges(maskArray: FloatArray, width: Int, height: Int, quality: String): FloatArray {
        val kernelSize = when (quality) {
            "low" -> 3
            "medium" -> 5
            else -> 7
        }
        
        val smoothedMask = FloatArray(width * height)
        val radius = kernelSize / 2
        
        // Gaussian kernel
        val kernel = FloatArray(kernelSize * kernelSize)
        val sigma = kernelSize / 3.0
        var kernelSum = 0f
        
        for (y in 0 until kernelSize) {
            for (x in 0 until kernelSize) {
                val distance = sqrt(((x - radius) * (x - radius) + (y - radius) * (y - radius)).toDouble())
                val value = exp(-(distance * distance) / (2 * sigma * sigma)).toFloat()
                kernel[y * kernelSize + x] = value
                kernelSum += value
            }
        }
        
        // Normalize kernel
        for (i in kernel.indices) {
            kernel[i] /= kernelSum
        }
        
        for (y in radius until height - radius) {
            for (x in radius until width - radius) {
                var sum = 0f
                var kernelIndex = 0
                
                for (ky in -radius..radius) {
                    for (kx in -radius..radius) {
                        val maskValue = maskArray[(y + ky) * width + (x + kx)]
                        sum += maskValue * kernel[kernelIndex]
                        kernelIndex++
                    }
                }
                
                smoothedMask[y * width + x] = sum.coerceIn(0f, 1f)
            }
        }
        
        // Copy edges
        for (y in 0 until height) {
            for (x in 0 until width) {
                if (x < radius || x >= width - radius || y < radius || y >= height - radius) {
                    smoothedMask[y * width + x] = maskArray[y * width + x]
                }
            }
        }
        
        return smoothedMask
    }
    
    private fun scaleMaskToOriginalSize(
        maskArray: FloatArray,
        maskWidth: Int,
        maskHeight: Int,
        targetWidth: Int,
        targetHeight: Int
    ): FloatArray {
        val scaledMask = FloatArray(targetWidth * targetHeight)
        
        for (y in 0 until targetHeight) {
            for (x in 0 until targetWidth) {
                // Map coordinates from target to mask dimensions
                val maskX = (x * maskWidth / targetWidth).coerceIn(0, maskWidth - 1)
                val maskY = (y * maskHeight / targetHeight).coerceIn(0, maskHeight - 1)
                
                scaledMask[y * targetWidth + x] = maskArray[maskY * maskWidth + maskX]
            }
        }
        
        return scaledMask
    }
    
    private fun createStickerBitmap(
        originalBitmap: Bitmap,
        maskArray: FloatArray,
        maskWidth: Int,
        maskHeight: Int,
        addBorder: Boolean,
        borderColorHex: String,
        borderWidth: Int,
        quality: String
    ): Bitmap {
        val stickerBitmap = Bitmap.createBitmap(maskWidth, maskHeight, Bitmap.Config.ARGB_8888)
        val actualBorderWidth = if (addBorder) borderWidth else 0
        val borderColor = parseBorderColor(borderColorHex)
        
        // Create anti-aliased border
        val expandedMask = if (addBorder) {
            createSmoothExpandedMask(maskArray, maskWidth, maskHeight, actualBorderWidth)
        } else {
            maskArray
        }
        
        // Use threshold based on quality
        val threshold = when (quality) {
            "low" -> 0.6f
            "medium" -> 0.5f
            else -> 0.4f
        }
        
        for (y in 0 until maskHeight) {
            for (x in 0 until maskWidth) {
                val maskVal = maskArray[y * maskWidth + x]
                val expandedMaskVal = if (addBorder) expandedMask[y * maskWidth + x] else maskVal
                
                when {
                    maskVal > threshold -> {
                        val pixelColor = originalBitmap.getPixel(x, y)
                        // Apply alpha blending for smooth edges
                        val alpha = ((maskVal - threshold) / (1f - threshold) * 255).toInt().coerceIn(0, 255)
                        val blendedColor = (alpha shl 24) or (pixelColor and 0x00FFFFFF)
                        stickerBitmap.setPixel(x, y, blendedColor)
                    }
                    addBorder && expandedMaskVal > threshold -> {
                        // Border pixels should be fully opaque
                        stickerBitmap.setPixel(x, y, borderColor or 0xFF000000.toInt())
                    }
                    else -> {
                        stickerBitmap.setPixel(x, y, 0x00000000)
                    }
                }
            }
        }
        
        return stickerBitmap
    }
    
    private fun createSmoothExpandedMask(maskArray: FloatArray, width: Int, height: Int, borderWidth: Int): FloatArray {
        val expandedMask = FloatArray(width * height) { 0f }
        
        // Create solid border without falloff for crisp edges
        for (y in 0 until height) {
            for (x in 0 until width) {
                if (maskArray[y * width + x] > 0.5f) {
                    for (dy in -borderWidth..borderWidth) {
                        for (dx in -borderWidth..borderWidth) {
                            val nx = x + dx
                            val ny = y + dy
                            if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
                                val distance = sqrt((dx * dx + dy * dy).toDouble()).toFloat()
                                if (distance <= borderWidth) {
                                    // Set border pixels to full opacity
                                    expandedMask[ny * width + nx] = 1f
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return expandedMask
    }
    
    private fun parseBorderColor(colorString: String): Int {
        return try {
            val hex = if (colorString.startsWith("#")) colorString.substring(1) else colorString
            if (hex.length == 6) {
                0xFF000000.toInt() or hex.toInt(16)
            } else {
                0xFFFFFFFF.toInt() // Default white
            }
        } catch (e: Exception) {
            0xFFFFFFFF.toInt() // Default white
        }
    }
}