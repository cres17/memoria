import Foundation
import Metal

/// Precompiled Metal operations. Call on the plugin's serial worker queue.
/// NR processes row tiles with a full-radius halo, preserving neighborhood math
/// while avoiding two full-resolution float4 Lab buffers on iPhone.
final class GpuOps {
    enum Failure: Error { case unavailable, invalidInput, allocation, timedOut, command(String) }
    struct NrParams {
        var width: Int32; var height: Int32; var lumRadius: Int32; var colRadius: Int32
        var sigRangeL2: Float; var sigRangeC2: Float; var detailBlend: Float
    }
    struct BlurParams {
        var lines: Int32; var length: Int32; var lineStride: Int32
        var step: Int32; var radius: Int32; var channels: Int32
    }
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let toLab: MTLComputePipelineState
    private let bilateral: MTLComputePipelineState
    private let toRgb: MTLComputePipelineState
    private let blur: MTLComputePipelineState

    init(libraryURL: URL? = nil) throws {
        guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue() else {
            throw Failure.unavailable
        }
        #if os(iOS) && !targetEnvironment(simulator)
        // dispatchThreads uses nonuniform threadgroups. Older iOS GPUs use
        // the CPU fallback before encoding an unsupported command.
        guard d.supportsFamily(.apple4) else { throw Failure.unavailable }
        #endif
        device = d; queue = q
        let library: MTLLibrary
        if let url = libraryURL { library = try d.makeLibrary(URL: url) }
        else { library = try d.makeDefaultLibrary(bundle: .main) }
        func pipeline(_ name: String) throws -> MTLComputePipelineState {
            guard let f = library.makeFunction(name: name) else { throw Failure.unavailable }
            return try d.makeComputePipelineState(function: f)
        }
        toLab = try pipeline("rgb_to_lab"); bilateral = try pipeline("bilateral_lab")
        toRgb = try pipeline("lab_to_rgb"); blur = try pipeline("blur_pass")
    }

    private func buffer(_ length: Int, bytes: UnsafeRawPointer? = nil,
                        privateStorage: Bool = false) throws -> MTLBuffer {
        guard length > 0, length <= device.maxBufferLength else { throw Failure.allocation }
        let b: MTLBuffer?
        if let p = bytes { b = device.makeBuffer(bytes: p, length: length, options: .storageModeShared) }
        else { b = device.makeBuffer(length: length, options: privateStorage ? .storageModePrivate : .storageModeShared) }
        guard let value = b else { throw Failure.allocation }
        return value
    }

    private func table(_ r: Int) -> [Float] {
        if r == 0 { return [1] }
        let ss = Double(r) * 0.5
        return (-r...r).flatMap { dy in (-r...r).map { dx in
            Float(exp(-Double(dx * dx + dy * dy) / (2 * ss * ss)))
        } }
    }

    private func dispatch(_ e: MTLComputeCommandEncoder, _ p: MTLComputePipelineState,
                          width: Int, height: Int = 1) {
        e.setComputePipelineState(p)
        let (w, h) = GpuDispatchShape.make(executionWidth: p.threadExecutionWidth,
            maxThreads: p.maxTotalThreadsPerThreadgroup, twoDimensional: height > 1)
        e.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
    }

    private func submit(deadline: DispatchTime, check: () throws -> Void,
                        _ encode: (MTLComputeCommandEncoder) -> Void) throws -> Double {
        try check()
        guard let cb = queue.makeCommandBuffer(), let e = cb.makeComputeCommandEncoder() else {
            throw Failure.allocation
        }
        let completed = DispatchSemaphore(value: 0)
        cb.addCompletedHandler { _ in completed.signal() }
        encode(e); e.endEncoding()
        try check()
        guard DispatchTime.now().uptimeNanoseconds < deadline.uptimeNanoseconds else { throw Failure.timedOut }
        cb.commit()
        // Metal cannot cancel a committed command. On timeout the plugin
        // quarantines this build; retainedReferences keeps its buffers alive.
        guard completed.wait(timeout: deadline) == .success else { throw Failure.timedOut }
        try check()
        if let error = cb.error as NSError?, error.domain == MTLCommandBufferErrorDomain,
           error.code == MTLCommandBufferError.notPermitted.rawValue {
            throw GpuRequestGate.Failure.interrupted
        }
        guard cb.status == .completed else { throw Failure.command(String(describing: cb.error)) }
        return (cb.gpuEndTime - cb.gpuStartTime) * 1000
    }

    func run(input: Data, width: Int, height: Int, channels: Int,
             operation: String, radius: Int = 0,
             luma: Double = 0, chroma: Double = 0, detail: Double = 0,
             check: () throws -> Void = {}) throws -> (Data, [String: Any]) {
        let deadline = DispatchTime.now() + .seconds(20)
        try check()
        guard width > 0, height > 0, width <= 32768, height <= 32768,
              channels == 3 || channels == 4, input.count == width * height * channels,
              luma.isFinite, chroma.isFinite, detail.isFinite,
              (0...100).contains(luma), (0...100).contains(chroma), (0...100).contains(detail),
              operation == "noise" || (operation == "blur" && radius > 0 && radius <= 256 && radius < min(width, height)) else {
            throw Failure.invalidInput
        }
        let t0 = CFAbsoluteTimeGetCurrent()
        // Bound native input/output + scratch before allocating. Refuse a large
        // operation and let Dart fall back; never use half precision silently.
        let scratch = operation == "noise" ? width * min(height, 262) * (32 + channels * 2) : input.count * 3
        guard UInt64(scratch + input.count * 2) <= ProcessInfo.processInfo.physicalMemory / 4 else {
            throw Failure.allocation
        }
        let output: Data
        var kernelMs = 0.0, tiles = 0
        if operation == "noise" {
            var nrOutput = Data(count: input.count)
            let lr = luma > 0 ? min(max(Int((luma / 50 * 2 + 1).rounded()), 1), 3) : 0
            let cr = chroma > 0 ? min(max(Int((chroma / 50 * 2 + 1).rounded()), 1), 3) : 0
            let halo = max(lr, cr), stride = width * channels
            let lt = table(lr), ct = table(cr)
            let lb = try lt.withUnsafeBytes { try buffer($0.count, bytes: $0.baseAddress) }
            let cb = try ct.withUnsafeBytes { try buffer($0.count, bytes: $0.baseAddress) }
            for top in Swift.stride(from: 0, to: height, by: 256) {
                try autoreleasepool {
                    try check()
                    let start = max(0, top - halo), end = min(height, top + 256 + halo)
                    let rows = end - start, count = width * rows, byteCount = count * channels
                    let src = try input.withUnsafeBytes { try buffer(byteCount, bytes: $0.baseAddress!.advanced(by: start * stride)) }
                    let lab = try buffer(count * 16, privateStorage: true)
                    let lab2 = try buffer(count * 16, privateStorage: true)
                    let dst = try buffer(byteCount)
                    let sl = 3 + luma * 0.22, sc = 8 + chroma * 0.40
                    var p = NrParams(width: Int32(width), height: Int32(rows), lumRadius: Int32(lr), colRadius: Int32(cr),
                        sigRangeL2: Float(2 * sl * sl), sigRangeC2: Float(2 * sc * sc), detailBlend: Float(detail / 100))
                    var nc = Int32(channels)
                    kernelMs += try submit(deadline: deadline, check: check) { e in
                        e.setBuffer(src, offset: 0, index: 0); e.setBuffer(lab, offset: 0, index: 1)
                        e.setBytes(&nc, length: 4, index: 2); dispatch(e, toLab, width: count)
                        e.memoryBarrier(scope: .buffers)
                        e.setBuffer(lab, offset: 0, index: 0); e.setBuffer(lab2, offset: 0, index: 1)
                        e.setBytes(&p, length: MemoryLayout<NrParams>.stride, index: 2)
                        e.setBuffer(lb, offset: 0, index: 3); e.setBuffer(cb, offset: 0, index: 4)
                        dispatch(e, bilateral, width: width, height: rows)
                        e.memoryBarrier(scope: .buffers)
                        e.setBuffer(lab2, offset: 0, index: 0); e.setBuffer(dst, offset: 0, index: 1)
                        e.setBytes(&nc, length: 4, index: 2); e.setBuffer(src, offset: 0, index: 3)
                        dispatch(e, toRgb, width: count)
                    }
                    let keep = min(256, height - top) * stride
                    nrOutput.withUnsafeMutableBytes { raw in
                        raw.baseAddress!.advanced(by: top * stride).copyMemory(
                            from: dst.contents().advanced(by: (top - start) * stride), byteCount: keep)
                    }
                    tiles += 1
                }
            }
            output = nrOutput
        } else {
            let src = try input.withUnsafeBytes { try buffer($0.count, bytes: $0.baseAddress) }
            let tmp = try buffer(input.count, privateStorage: true), dst = try buffer(input.count)
            let sigma = Double(radius) * (2.0 / 3.0), scale = 2 * sigma * sigma
            let weights = (-radius...radius).map { exp(-Double($0 * $0) / scale) }
            let inv = 1.0 / weights.reduce(0, +), k = weights.map { Float($0 * inv) }
            let kb = try k.withUnsafeBytes { try buffer($0.count, bytes: $0.baseAddress) }
            var h = BlurParams(lines: Int32(height), length: Int32(width), lineStride: Int32(width * channels),
                               step: Int32(channels), radius: Int32(radius), channels: Int32(channels))
            var v = BlurParams(lines: Int32(width), length: Int32(height), lineStride: Int32(channels),
                               step: Int32(width * channels), radius: Int32(radius), channels: Int32(channels))
            kernelMs = try submit(deadline: deadline, check: check) { e in
                e.setBuffer(src, offset: 0, index: 0); e.setBuffer(tmp, offset: 0, index: 1)
                e.setBytes(&h, length: MemoryLayout<BlurParams>.stride, index: 2); e.setBuffer(kb, offset: 0, index: 3)
                dispatch(e, blur, width: width, height: height)
                e.memoryBarrier(scope: .buffers)
                e.setBuffer(tmp, offset: 0, index: 0); e.setBuffer(dst, offset: 0, index: 1)
                e.setBytes(&v, length: MemoryLayout<BlurParams>.stride, index: 2)
                dispatch(e, blur, width: height, height: width)
            }
            output = Data(bytes: dst.contents(), count: input.count); tiles = 1
        }
        var pipelineLimits: [String: Any] = [:]
        for (name, pipeline, twoD) in [("rgb_to_lab", toLab, false), ("bilateral_lab", bilateral, true),
                                       ("lab_to_rgb", toRgb, false), ("blur_pass", blur, true)] {
            let (w, h) = GpuDispatchShape.make(executionWidth: pipeline.threadExecutionWidth,
                maxThreads: pipeline.maxTotalThreadsPerThreadgroup, twoDimensional: twoD)
            pipelineLimits[name] = ["execution_width": pipeline.threadExecutionWidth,
                "max_threads": pipeline.maxTotalThreadsPerThreadgroup, "group_width": w, "group_height": h]
        }
        let wall = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        return (output, ["kernel_ms": kernelMs, "native_wall_ms": wall,
                         "allocation_copy_submit_ms": max(0, wall - kernelMs), "tiles": tiles,
                         "gpu": device.name, "math": operation == "noise" ? "fast" : "precise",
                         "pipeline_limits": pipelineLimits])
    }
}
