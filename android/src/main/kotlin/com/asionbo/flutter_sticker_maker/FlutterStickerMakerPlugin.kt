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

class FlutterStickerMakerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_sticker_maker")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "makeSticker") {
            val imageBytes = call.argument<ByteArray>("image")
            val addBorder = call.argument<Boolean>("addBorder") ?: false
            val borderColor = call.argument<String>("borderColor") ?: "#FFFFFF"
            val borderWidth = call.argument<Double>("borderWidth")?.toInt() ?: 12
            if (imageBytes != null) {
                processSticker(imageBytes, addBorder, borderColor, borderWidth, result)
            } else {
                result.error("NO_IMAGE", "No image provided", null)
            }
        } else {
            result.notImplemented()
        }
    }

    private fun processSticker(imageBytes: ByteArray, addBorder: Boolean, borderColor: String, borderWidth: Int, result: MethodChannel.Result) {
        // Preprocess image for better quality
        val originalBitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
        val preprocessedBitmap = preprocessImage(originalBitmap)
        val inputImage = InputImage.fromBitmap(preprocessedBitmap, 0)
        
        // Enhanced segmentation options for better quality
        val options = SelfieSegmenterOptions.Builder()
            .setDetectorMode(SelfieSegmenterOptions.SINGLE_IMAGE_MODE)
            .enableRawSizeMask()
            .build()
        val segmenter = Segmentation.getClient(options)

        segmenter.process(inputImage)
            .addOnSuccessListener { segmentationMask ->
                val mask = segmentationMask.buffer
                mask.rewind()
                val maskWidth = segmentationMask.width
                val maskHeight = segmentationMask.height
                val maskArray = FloatArray(maskWidth * maskHeight)
                mask.asFloatBuffer().get(maskArray)
                
                // Apply mask smoothing for better edge quality
                val smoothedMask = smoothMaskEdges(maskArray, maskWidth, maskHeight)
                
                // Scale mask to original image dimensions
                val scaledMask = scaleMaskToOriginalSize(
                    smoothedMask, 
                    maskWidth, 
                    maskHeight, 
                    originalBitmap.width, 
                    originalBitmap.height
                )
                
                val stickerBitmap = createStickerBitmap(
                    originalBitmap, 
                    scaledMask, 
                    originalBitmap.width, 
                    originalBitmap.height, 
                    addBorder, 
                    borderColor, 
                    borderWidth
                )
                
                val outputStream = ByteArrayOutputStream()
                stickerBitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
                val outputBytes = outputStream.toByteArray()
                Handler(Looper.getMainLooper()).post {
                    result.success(outputBytes)
                }
            }
            .addOnFailureListener { e ->
                Handler(Looper.getMainLooper()).post {
                    result.error("SEGMENTATION_FAILED", e.localizedMessage, null)
                }
            }
    }
    
    private fun preprocessImage(bitmap: Bitmap): Bitmap {
        val matrix = android.graphics.ColorMatrix()
        // Enhance contrast and brightness for better detection
        matrix.setSaturation(1.1f)
        val contrastMatrix = android.graphics.ColorMatrix(floatArrayOf(
            1.1f, 0f, 0f, 0f, 10f,  // Red
            0f, 1.1f, 0f, 0f, 10f,  // Green  
            0f, 0f, 1.1f, 0f, 10f,  // Blue
            0f, 0f, 0f, 1f, 0f      // Alpha
        ))
        matrix.postConcat(contrastMatrix)
        
        val enhancedBitmap = Bitmap.createBitmap(bitmap.width, bitmap.height, bitmap.config ?: Bitmap.Config.ARGB_8888)
        val canvas = Canvas(enhancedBitmap)
        val paint = Paint().apply {
            colorFilter = android.graphics.ColorMatrixColorFilter(matrix)
            isAntiAlias = true
            isDither = true
        }
        canvas.drawBitmap(bitmap, 0f, 0f, paint)
        
        return enhancedBitmap
    }
    
    private fun smoothMaskEdges(maskArray: FloatArray, width: Int, height: Int): FloatArray {
        val smoothedMask = FloatArray(width * height)
        val kernelSize = 3
        val kernel = floatArrayOf(
            0.0625f, 0.125f, 0.0625f,
            0.125f, 0.25f, 0.125f,
            0.0625f, 0.125f, 0.0625f
        )
        
        for (y in 1 until height - 1) {
            for (x in 1 until width - 1) {
                var sum = 0f
                var kernelIndex = 0
                
                for (ky in -1..1) {
                    for (kx in -1..1) {
                        val maskValue = maskArray[(y + ky) * width + (x + kx)]
                        sum += maskValue * kernel[kernelIndex]
                        kernelIndex++
                    }
                }
                
                smoothedMask[y * width + x] = sum.coerceIn(0f, 1f)
            }
        }
        
        // Copy edges without smoothing
        for (y in 0 until height) {
            smoothedMask[y * width] = maskArray[y * width] // Left edge
            smoothedMask[y * width + width - 1] = maskArray[y * width + width - 1] // Right edge
        }
        for (x in 0 until width) {
            smoothedMask[x] = maskArray[x] // Top edge
            smoothedMask[(height - 1) * width + x] = maskArray[(height - 1) * width + x] // Bottom edge
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
        borderWidth: Int
    ): Bitmap {
        val stickerBitmap = Bitmap.createBitmap(maskWidth, maskHeight, Bitmap.Config.ARGB_8888)
        val actualBorderWidth = if (addBorder) borderWidth else 0
        val borderColor = parseBorderColor(borderColorHex)
        
        // Create expanded mask for border if needed
        val expandedMask = if (addBorder) {
            createExpandedMask(maskArray, maskWidth, maskHeight, actualBorderWidth)
        } else {
            maskArray
        }
        
        for (y in 0 until maskHeight) {
            for (x in 0 until maskWidth) {
                val maskVal = maskArray[y * maskWidth + x]
                val expandedMaskVal = if (addBorder) expandedMask[y * maskWidth + x] else maskVal
                
                when {
                    maskVal > 0.5f -> {
                        // Original subject pixel - use original coordinates directly
                        val pixelColor = originalBitmap.getPixel(x, y)
                        stickerBitmap.setPixel(x, y, pixelColor)
                    }
                    addBorder && expandedMaskVal > 0.5f -> {
                        // Border pixel
                        stickerBitmap.setPixel(x, y, borderColor)
                    }
                    else -> {
                        // Transparent pixel
                        stickerBitmap.setPixel(x, y, 0x00000000)
                    }
                }
            }
        }
        
        return stickerBitmap
    }
    
    private fun createExpandedMask(maskArray: FloatArray, width: Int, height: Int, borderWidth: Int): FloatArray {
        val expandedMask = FloatArray(width * height) { 0f }
        
        for (y in 0 until height) {
            for (x in 0 until width) {
                if (maskArray[y * width + x] > 0.5f) {
                    // Mark this pixel and surrounding pixels within border width
                    for (dy in -borderWidth..borderWidth) {
                        for (dx in -borderWidth..borderWidth) {
                            val nx = x + dx
                            val ny = y + dy
                            if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
                                expandedMask[ny * width + nx] = 1f
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