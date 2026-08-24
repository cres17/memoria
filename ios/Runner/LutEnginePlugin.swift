import Flutter
import UIKit
import CoreImage
import Accelerate
import ImageIO

/// LutEnginePlugin — Flutter MethodChannel handler for iOS Core Image LUT pipeline.
///
/// Channel: com.memoria/lut_engine
///
/// Methods:
///   generateLut(styleImagePath: String) → Dictionary
///   renderPreview(imagePath: String, editOps: Dictionary) → Dictionary
///   export(imagePath: String, editOps: Dictionary, outPath: String, format: String, quality: Int) → Dictionary

@objc public class LutEnginePlugin: NSObject, FlutterPlugin {
    static let channelName = "com.memoria/lut_engine"
    static let lutDim = 33

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = LutEnginePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "generateLut":
            handleGenerateLut(call: call, result: result)
        case "renderPreview":
            result(["useDartFallback": true])
        case "export":
            result(["useDartFallback": true])
        case "encodeWebP":
            handleEncodeWebP(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: — WebP export

    /// ImageIO is the source of truth for native codec support. The app only
    /// exposes WebP when this conversion succeeds, so an extension can never
    /// claim WebP while containing JPEG bytes.
    private func handleEncodeWebP(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let inputPath = args["inputPath"] as? String,
              let outputPath = args["outputPath"] as? String else {
            result(FlutterError(code: "INVALID_ARG",
                                message: "inputPath and outputPath required", details: nil))
            return
        }
        let quality = max(0.0, min(1.0, Double(args["quality"] as? Int ?? 95) / 100.0))

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let webpType = "org.webmproject.webp" as CFString
                let supportedTypes = CGImageDestinationCopyTypeIdentifiers() as NSArray
                guard supportedTypes.contains(where: { String(describing: $0) == webpType as String }) else {
                    throw NSError(domain: "LutEngine", code: 20,
                                  userInfo: [NSLocalizedDescriptionKey: "WebP is not supported by ImageIO on this device"])
                }
                guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: inputPath) as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                      let destination = CGImageDestinationCreateWithURL(
                        URL(fileURLWithPath: outputPath) as CFURL, webpType, 1, nil
                      ) else {
                    throw NSError(domain: "LutEngine", code: 21,
                                  userInfo: [NSLocalizedDescriptionKey: "Unable to create WebP destination"])
                }
                CGImageDestinationAddImage(destination, image, [
                    kCGImageDestinationLossyCompressionQuality: quality
                ] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else {
                    throw NSError(domain: "LutEngine", code: 22,
                                  userInfo: [NSLocalizedDescriptionKey: "WebP encoding failed"])
                }
                DispatchQueue.main.async { result(true) }
            } catch {
                DispatchQueue.main.async { result(false) }
            }
        }
    }

    // MARK: — generateLut

    private func handleGenerateLut(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let styleImagePath = args["styleImagePath"] as? String else {
            result(FlutterError(code: "INVALID_ARG",
                                message: "styleImagePath required", details: nil))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let output = try self.generateLutInternal(styleImagePath: styleImagePath)
                DispatchQueue.main.async { result(output) }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "LUT_ERROR",
                                        message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    private func generateLutInternal(styleImagePath: String) throws -> [String: Any] {
        let presetId = UUID().uuidString
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let presetDir = docsDir.appendingPathComponent("filters/\(presetId)")
        try FileManager.default.createDirectory(at: presetDir, withIntermediateDirectories: true)

        guard let uiImage = UIImage(contentsOfFile: styleImagePath),
              let cgImage = uiImage.cgImage else {
            throw NSError(domain: "LutEngine", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot decode image"])
        }

        // Downscale to max 512px
        let scaled = scaleCGImage(cgImage, maxDim: 512)

        // Analyze style
        let stats = analyzeStyle(image: scaled)

        // Build tone curve
        let toneCurve = buildToneCurve(neutralCdf: NeutralStats.cdf, styleCdf: stats.cdf)

        // Clamped sigma ratios
        let ratioL = (stats.sigL / NeutralStats.sigL).clamped(to: 0.5...2.0)
        let ratioA = (stats.sigA / NeutralStats.sigA).clamped(to: 0.5...2.0)
        let ratioB = (stats.sigB / NeutralStats.sigB).clamped(to: 0.5...2.0)

        // Build cubeData for CIColorCube (RGBA float32, R-fastest, B-slowest)
        // dimension=33, order: R fastest → G → B
        let dim = LutEnginePlugin.lutDim
        var cubeData = [Float](repeating: 0, count: dim * dim * dim * 4)
        var idx = 0

        for b in 0..<dim {
            for g in 0..<dim {
                for r in 0..<dim {
                    let rgb = [Float(r)/32, Float(g)/32, Float(b)/32]
                    let lab = rgbToLab(rgb)

                    let lBin = Int((lab[0] * 255.0 / 100.0).clamped(to: 0...255))
                    let l1   = Double(toneCurve[lBin]) * 100.0 / 255.0

                    let l2 = (l1  - NeutralStats.muL) * ratioL + stats.muL
                    let a2 = (lab[1] - NeutralStats.muA) * ratioA + stats.muA
                    let b2 = (lab[2] - NeutralStats.muB) * ratioB + stats.muB

                    let rgbOut = labToRgb([l2, a2, b2])
                    cubeData[idx]   = Float(rgbOut[0])
                    cubeData[idx+1] = Float(rgbOut[1])
                    cubeData[idx+2] = Float(rgbOut[2])
                    cubeData[idx+3] = 1.0
                    idx += 4
                }
            }
        }

        // Save lut.bin (float16 binary for compatibility with Dart side)
        let lutBinData = float32ToFloat16Binary(cubeData)
        let lutURL = presetDir.appendingPathComponent("lut.bin")
        try lutBinData.write(to: lutURL)

        // Save cubeData separately for native CIColorCube usage
        let cubeURL = presetDir.appendingPathComponent("cube.f32")
        let cubeRawData = Data(bytes: cubeData, count: cubeData.count * MemoryLayout<Float>.size)
        try cubeRawData.write(to: cubeURL)

        // Thumbnail
        let thumbUI = UIImage(cgImage: cropSquare(scaled, size: 128))
        let thumbURL = presetDir.appendingPathComponent("thumbnail.jpg")
        if let jpegData = thumbUI.jpegData(compressionQuality: 0.8) {
            try jpegData.write(to: thumbURL)
        }

        return [
            "presetId":      presetId,
            "lutPath":       lutURL.path,
            "thumbnailPath": thumbURL.path,
            "defaultParams": [
                "exposure": 0.0, "contrast": 0.0, "saturation": 0.0,
                "temperature": 0.0, "tint": 0.0, "highlights": 0.0,
                "shadows": 0.0, "sharpen": 0.0, "vignette": 0.0
            ]
        ]
    }

    // MARK: — Apply CIColorCube (native filter application)

    func applyCIColorCube(to image: CIImage, cubeDataPath: String, intensity: Float) -> CIImage? {
        guard let rawData = try? Data(contentsOf: URL(fileURLWithPath: cubeDataPath)) else {
            return nil
        }
        let dim = LutEnginePlugin.lutDim
        let filter = CIFilter(name: "CIColorCube")!
        filter.setValue(dim, forKey: "inputCubeDimension")
        filter.setValue(rawData as NSData, forKey: "inputCubeData")
        filter.setValue(image, forKey: kCIInputImageKey)
        guard let filtered = filter.outputImage else { return nil }

        // Intensity mix
        let blend = CIFilter(name: "CIBlendWithMask") ??
                    CIFilter(name: "CISourceOverCompositing")!
        // Simple lerp via dissolve
        let dissolve = CIFilter(name: "CIDissolveTransition")!
        dissolve.setValue(image,    forKey: kCIInputImageKey)
        dissolve.setValue(filtered, forKey: kCIInputTargetImageKey)
        dissolve.setValue(NSNumber(value: intensity), forKey: kCIInputTimeKey)
        return dissolve.outputImage ?? filtered
    }

    // MARK: — Image helpers

    private func scaleCGImage(_ src: CGImage, maxDim: Int) -> CGImage {
        let w = src.width; let h = src.height
        let maxSide = max(w, h)
        guard maxSide > maxDim else { return src }
        let scale = Double(maxDim) / Double(maxSide)
        let newW = Int(Double(w) * scale); let newH = Int(Double(h) * scale)
        let ctx = CGContext(data: nil, width: newW, height: newH,
                            bitsPerComponent: 8, bytesPerRow: newW * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage()!
    }

    private func cropSquare(_ src: CGImage, size: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: size, height: size,
                            bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()!
    }

    // MARK: — Style analysis

    private struct StyleStats {
        var muL, sigL, muA, sigA, muB, sigB: Double
        var cdf: [Float]
    }

    private func analyzeStyle(image: CGImage) -> StyleStats {
        let w = image.width; let h = image.height
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h * 4)
        defer { data.deallocate() }
        let ctx = CGContext(data: data, width: w, height: h,
                            bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var lSum = 0.0, aSum = 0.0, bSum = 0.0
        var lSumSq = 0.0, aSumSq = 0.0, bSumSq = 0.0
        var lHist = [Int](repeating: 0, count: 256)
        let n = w * h

        for i in 0..<n {
            let r = Double(data[i*4])   / 255.0
            let g = Double(data[i*4+1]) / 255.0
            let b = Double(data[i*4+2]) / 255.0
            let lab = rgbToLab([Float(r), Float(g), Float(b)])
            lSum += lab[0]; aSum += lab[1]; bSum += lab[2]
            lSumSq += lab[0]*lab[0]; aSumSq += lab[1]*lab[1]; bSumSq += lab[2]*lab[2]
            let bin = Int((lab[0] * 255.0 / 100.0).clamped(to: 0...255))
            lHist[bin] += 1
        }

        let nd = Double(n)
        let muL = lSum/nd; let muA = aSum/nd; let muB = bSum/nd
        let sigL = sqrt(max(lSumSq/nd - muL*muL, 1e-6))
        let sigA = sqrt(max(aSumSq/nd - muA*muA, 1e-6))
        let sigB = sqrt(max(bSumSq/nd - muB*muB, 1e-6))

        var cumul = 0.0
        let cdf = lHist.map { v -> Float in
            cumul += Double(v) / nd; return Float(cumul) }

        return StyleStats(muL: muL, sigL: sigL, muA: muA, sigA: sigA,
                          muB: muB, sigB: sigB, cdf: cdf)
    }

    // MARK: — Tone curve

    private func buildToneCurve(neutralCdf: [Float], styleCdf: [Float]) -> [Float] {
        var curve = [Float](repeating: 0, count: 256)
        for i in 0..<256 {
            let target = neutralCdf[i]
            var j = 0
            while j < 255 && styleCdf[j] < target { j += 1 }
            curve[i] = Float(j)
        }
        for i in 1..<256 { if curve[i] < curve[i-1] { curve[i] = curve[i-1] } }
        return curve
    }

    // MARK: — Color conversion

    private func rgbToLab(_ rgb: [Float]) -> [Double] {
        func linearize(_ c: Double) -> Double {
            return c <= 0.04045 ? c/12.92 : pow((c+0.055)/1.055, 2.4)
        }
        let rl = linearize(Double(rgb[0])); let gl = linearize(Double(rgb[1])); let bl = linearize(Double(rgb[2]))
        let x = 0.4124564*rl + 0.3575761*gl + 0.1804375*bl
        let y = 0.2126729*rl + 0.7151522*gl + 0.0721750*bl
        let z = 0.0193339*rl + 0.1191920*gl + 0.9503041*bl
        func f(_ t: Double) -> Double {
            let d = 6.0/29.0; return t > d*d*d ? pow(t, 1.0/3.0) : t/(3*d*d) + 4.0/29.0
        }
        return [116*f(y/1.0)-16, 500*(f(x/0.95047)-f(y/1.0)), 200*(f(y/1.0)-f(z/1.08883))]
    }

    private func labToRgb(_ lab: [Double]) -> [Double] {
        let fy = (lab[0]+16)/116; let fx = lab[1]/500+fy; let fz = fy - lab[2]/200
        func fInv(_ t: Double) -> Double {
            let d = 6.0/29.0; return t > d ? t*t*t : 3*d*d*(t-4.0/29.0)
        }
        let x = fInv(fx)*0.95047; let y = fInv(fy)*1.0; let z = fInv(fz)*1.08883
        let rl =  3.2404542*x - 1.5371385*y - 0.4985314*z
        let gl = -0.9692660*x + 1.8760108*y + 0.0415560*z
        let bl2 =  0.0556434*x - 0.2040259*y + 1.0572252*z
        func delinearize(_ c: Double) -> Double {
            let cc = c.clamped(to: 0...1)
            return cc <= 0.0031308 ? 12.92*cc : 1.055*pow(cc, 1.0/2.4) - 0.055
        }
        return [delinearize(rl).clamped(to: 0...1),
                delinearize(gl).clamped(to: 0...1),
                delinearize(bl2).clamped(to: 0...1)]
    }

    // MARK: — float32 → float16 binary

    private func float32ToFloat16Binary(_ floats: [Float]) -> Data {
        var result = Data(capacity: floats.count * 2)
        for f in floats {
            let bits = f.bitPattern
            let sign = (bits >> 31) & 0x1
            var exp  = Int((bits >> 23) & 0xFF) - 127 + 15
            var mant = (bits >> 13) & 0x3FF
            if exp <= 0 { exp = 0; mant = 0 }
            if exp >= 31 { exp = 31; mant = 0 }
            var half = UInt16((sign << 15) | (UInt32(exp) << 10) | mant)
            withUnsafeBytes(of: &half) { result.append(contentsOf: $0) }
        }
        return result
    }
}

// MARK: — Neutral constants
private enum NeutralStats {
    static let muL = 50.0, sigL = 18.0
    static let muA =  0.0, sigA =  8.0
    static let muB =  0.0, sigB =  8.0

    static let cdf: [Float] = {
        var hist = [Double](repeating: 0, count: 256)
        for i in 0..<256 {
            let l = Double(i) * 100.0 / 255.0
            let z = (l - muL) / sigL
            hist[i] = exp(-0.5 * z * z)
        }
        let sum = hist.reduce(0, +)
        var cumul = 0.0
        return hist.map { v -> Float in cumul += v/sum; return Float(cumul) }
    }()
}

// MARK: — Comparable helpers
extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
