package com.memoria

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID

/**
 * LutEnginePlugin — Flutter MethodChannel handler for GPU LUT operations.
 *
 * Channel: com.memoria/lut_engine
 *
 * Methods:
 *   generateLut(styleImagePath: String) → Map
 *   renderPreview(imagePath: String, editOps: Map) → Map
 *   export(imagePath: String, editOps: Map, outPath: String, format: String, quality: Int) → Map
 */
class LutEnginePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    companion object {
        const val CHANNEL = "com.memoria/lut_engine"
        const val LUT_DIM = 33
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "generateLut"   -> handleGenerateLut(call, result)
            "renderPreview" -> handleRenderPreview(call, result)
            "export"        -> handleExport(call, result)
            else            -> result.notImplemented()
        }
    }

    // ── generateLut ────────────────────────────────────────────
    private fun handleGenerateLut(call: MethodCall, result: MethodChannel.Result) {
        val styleImagePath = call.argument<String>("styleImagePath") ?: run {
            result.error("INVALID_ARG", "styleImagePath required", null)
            return
        }

        scope.launch {
            try {
                val output = withContext(Dispatchers.Default) {
                    generateLutInternal(styleImagePath)
                }
                result.success(output)
            } catch (e: Exception) {
                result.error("LUT_ERROR", e.message, null)
            }
        }
    }

    private fun generateLutInternal(styleImagePath: String): Map<String, Any> {
        val presetId = UUID.randomUUID().toString()
        val dir = File(context.filesDir, "filters/$presetId").also { it.mkdirs() }

        val bitmap = BitmapFactory.decodeFile(styleImagePath)
            ?: throw Exception("Cannot decode image: $styleImagePath")

        // Downscale to max 512px
        val scaled = scaleBitmap(bitmap, 512)

        // Analyze style
        val stats = analyzeStyle(scaled)

        // Build tone curve
        val toneCurve = buildToneCurve(NeutralStats.cdf, stats.cdf)

        // Clamp sigma ratios
        val ratioL = (stats.sigL / NeutralStats.SIG_L).coerceIn(0.5, 2.0)
        val ratioA = (stats.sigA / NeutralStats.SIG_A).coerceIn(0.5, 2.0)
        val ratioB = (stats.sigB / NeutralStats.SIG_B).coerceIn(0.5, 2.0)

        // Generate 33³ LUT → float16
        val total = LUT_DIM * LUT_DIM * LUT_DIM
        val lutBuffer = ByteBuffer.allocate(total * 3 * 2).order(ByteOrder.LITTLE_ENDIAN)

        for (r in 0 until LUT_DIM) {
            for (g in 0 until LUT_DIM) {
                for (b in 0 until LUT_DIM) {
                    val rgb = floatArrayOf(r / 32f, g / 32f, b / 32f)
                    val lab = rgbToLab(rgb)

                    val lBin = (lab[0] * 255f / 100f).toInt().coerceIn(0, 255)
                    val l1   = toneCurve[lBin] * 100f / 255f

                    val l2 = (l1  - NeutralStats.MU_L) * ratioL + stats.muL
                    val a2 = (lab[1] - NeutralStats.MU_A) * ratioA + stats.muA
                    val b2 = (lab[2] - NeutralStats.MU_B) * ratioB + stats.muB

                    val rgbOut = labToRgb(doubleArrayOf(l2, a2, b2))
                    lutBuffer.putShort(floatToHalf(rgbOut[0].toFloat()))
                    lutBuffer.putShort(floatToHalf(rgbOut[1].toFloat()))
                    lutBuffer.putShort(floatToHalf(rgbOut[2].toFloat()))
                }
            }
        }

        val lutFile = File(dir, "lut.bin")
        FileOutputStream(lutFile).use { it.write(lutBuffer.array()) }

        // Thumbnail (128×128 crop)
        val thumb = Bitmap.createScaledBitmap(scaled, 128, 128, true)
        val thumbFile = File(dir, "thumbnail.jpg")
        FileOutputStream(thumbFile).use { thumb.compress(Bitmap.CompressFormat.JPEG, 80, it) }

        return mapOf(
            "presetId"      to presetId,
            "lutPath"       to lutFile.absolutePath,
            "thumbnailPath" to thumbFile.absolutePath,
            "defaultParams" to mapOf(
                "exposure" to 0.0, "contrast" to 0.0, "saturation" to 0.0,
                "temperature" to 0.0, "tint" to 0.0, "highlights" to 0.0,
                "shadows" to 0.0, "sharpen" to 0.0, "vignette" to 0.0
            )
        )
    }

    // ── renderPreview ───────────────────────────────────────────
    private fun handleRenderPreview(call: MethodCall, result: MethodChannel.Result) {
        // GPU rendering via OpenGL would use a TextureId.
        // For this skeleton, we return a placeholder indicating Dart-side fallback.
        result.success(mapOf("useDartFallback" to true))
    }

    // ── export ──────────────────────────────────────────────────
    private fun handleExport(call: MethodCall, result: MethodChannel.Result) {
        result.success(mapOf("useDartFallback" to true))
    }

    // ── Color Math ──────────────────────────────────────────────

    private fun scaleBitmap(src: Bitmap, maxDim: Int): Bitmap {
        val w = src.width; val h = src.height
        val maxSide = maxOf(w, h)
        if (maxSide <= maxDim) return src
        val scale = maxDim.toFloat() / maxSide
        return Bitmap.createScaledBitmap(src, (w * scale).toInt(), (h * scale).toInt(), true)
    }

    private data class StyleStats(
        val muL: Double, val sigL: Double,
        val muA: Double, val sigA: Double,
        val muB: Double, val sigB: Double,
        val cdf: FloatArray,
    )

    private fun analyzeStyle(bmp: Bitmap): StyleStats {
        val lList = mutableListOf<Double>()
        val aList = mutableListOf<Double>()
        val bList = mutableListOf<Double>()
        val lHist = IntArray(256)

        for (y in 0 until bmp.height) {
            for (x in 0 until bmp.width) {
                val px = bmp.getPixel(x, y)
                val r = ((px shr 16) and 0xFF) / 255.0
                val g = ((px shr 8)  and 0xFF) / 255.0
                val b = (px          and 0xFF) / 255.0
                val lab = rgbToLab(floatArrayOf(r.toFloat(), g.toFloat(), b.toFloat()))
                lList.add(lab[0]); aList.add(lab[1]); bList.add(lab[2])
                val bin = (lab[0] * 255.0 / 100.0).toInt().coerceIn(0, 255)
                lHist[bin]++
            }
        }

        val n = lList.size.toDouble()
        val muL = lList.sum() / n
        val muA = aList.sum() / n
        val muB = bList.sum() / n
        val sigL = stdDev(lList, muL)
        val sigA = stdDev(aList, muA)
        val sigB = stdDev(bList, muB)

        val total = lHist.sum().toDouble()
        var cumul = 0.0
        val cdf = FloatArray(256)
        for (i in 0 until 256) { cumul += lHist[i] / total; cdf[i] = cumul.toFloat() }

        return StyleStats(muL, sigL, muA, sigA, muB, sigB, cdf)
    }

    private fun stdDev(vals: List<Double>, mean: Double): Double {
        if (vals.isEmpty()) return 1.0
        val variance = vals.sumOf { (it - mean) * (it - mean) } / vals.size
        return Math.sqrt(variance).coerceAtLeast(0.001)
    }

    private fun buildToneCurve(neutralCdf: FloatArray, styleCdf: FloatArray): FloatArray {
        val curve = FloatArray(256)
        for (i in 0 until 256) {
            val target = neutralCdf[i]
            var j = 0
            while (j < 255 && styleCdf[j] < target) j++
            curve[i] = j.toFloat()
        }
        // Enforce monotonicity
        for (i in 1 until 256) if (curve[i] < curve[i-1]) curve[i] = curve[i-1]
        return curve
    }

    // sRGB → CIE Lab (D65)
    private fun rgbToLab(rgb: FloatArray): DoubleArray {
        fun linearize(c: Double) =
            if (c <= 0.04045) c / 12.92 else Math.pow((c + 0.055) / 1.055, 2.4)

        val rl = linearize(rgb[0].toDouble())
        val gl = linearize(rgb[1].toDouble())
        val bl = linearize(rgb[2].toDouble())

        val x = 0.4124564*rl + 0.3575761*gl + 0.1804375*bl
        val y = 0.2126729*rl + 0.7151522*gl + 0.0721750*bl
        val z = 0.0193339*rl + 0.1191920*gl + 0.9503041*bl

        fun f(t: Double): Double {
            val d = 6.0/29.0
            return if (t > d*d*d) Math.pow(t, 1.0/3.0) else t/(3*d*d) + 4.0/29.0
        }
        val fx = f(x/0.95047); val fy = f(y/1.00000); val fz = f(z/1.08883)
        return doubleArrayOf(116*fy - 16, 500*(fx - fy), 200*(fy - fz))
    }

    // CIE Lab → sRGB (D65)
    private fun labToRgb(lab: DoubleArray): DoubleArray {
        val fy = (lab[0] + 16) / 116.0
        val fx = lab[1] / 500.0 + fy
        val fz = fy - lab[2] / 200.0
        fun fInv(t: Double): Double {
            val d = 6.0/29.0
            return if (t > d) t*t*t else 3*d*d*(t - 4.0/29.0)
        }
        val x = fInv(fx)*0.95047; val y = fInv(fy)*1.00000; val z = fInv(fz)*1.08883
        val rl =  3.2404542*x - 1.5371385*y - 0.4985314*z
        val gl = -0.9692660*x + 1.8760108*y + 0.0415560*z
        val bl =  0.0556434*x - 0.2040259*y + 1.0572252*z
        fun delinearize(c: Double): Double {
            val clamped = c.coerceIn(0.0, 1.0)
            return if (clamped <= 0.0031308) 12.92*clamped
                   else 1.055*Math.pow(clamped, 1.0/2.4) - 0.055
        }
        return doubleArrayOf(
            delinearize(rl).coerceIn(0.0,1.0),
            delinearize(gl).coerceIn(0.0,1.0),
            delinearize(bl).coerceIn(0.0,1.0)
        )
    }

    // IEEE 754 float → float16 (half-float)
    private fun floatToHalf(f: Float): Short {
        val bits = java.lang.Float.floatToIntBits(f)
        val sign = (bits ushr 31) and 0x1
        var exp  = ((bits ushr 23) and 0xFF) - 127 + 15
        var mant = (bits ushr 13) and 0x3FF
        if (exp <= 0) { exp = 0; mant = 0 }
        if (exp >= 31) { exp = 31; mant = 0 }
        return ((sign shl 15) or (exp shl 10) or mant).toShort()
    }
}

// Neutral Lab reference constants
object NeutralStats {
    const val MU_L  = 50.0; const val SIG_L = 18.0
    const val MU_A  =  0.0; const val SIG_A =  8.0
    const val MU_B  =  0.0; const val SIG_B =  8.0

    // Gaussian N(50,18) normalised CDF over [0,255] representing L in [0,100]
    val cdf: FloatArray by lazy {
        val bins = 256
        val hist = FloatArray(bins)
        for (i in 0 until bins) {
            val l = i * 100.0 / 255.0
            val z = (l - MU_L) / SIG_L
            hist[i] = Math.exp(-0.5 * z * z).toFloat()
        }
        val sum = hist.sum()
        var cumul = 0f
        FloatArray(bins) { i -> cumul += hist[i] / sum; cumul }
    }
}
