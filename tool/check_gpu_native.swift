import Foundation

/// Compile with GpuRequestGate.swift and GpuOps.swift. Takes a macOS metallib
/// and memoria-gpu-bench/out. This is native Mac evidence, not an iOS test.
@main enum NativeCheck {
    static func main() throws {
        let library = URL(fileURLWithPath: CommandLine.arguments[1])
        let dir = URL(fileURLWithPath: CommandLine.arguments[2])
        let cpu = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("cpu.json"))) as! [String: Any]
        let w = cpu["width"] as! Int, h = cpu["height"] as! Int
        let input = try Data(contentsOf: dir.appendingPathComponent("input.rgb"))
        let engine = try GpuOps(libraryURL: library)
        for name in ["nr_A", "nr_B", "blur_r5", "blur_r20"] {
            let nr = name.hasPrefix("nr")
            let value = name == "nr_A" ? 25.0 : 100.0
            let (output, timing) = try engine.run(input: input, width: w, height: h, channels: 3,
                operation: nr ? "noise" : "blur", radius: name == "blur_r5" ? 5 : 20,
                luma: value, chroma: value)
            let expected = try Data(contentsOf: dir.appendingPathComponent("\(name).rgb"))
            var maxAbs = 0, sum = 0, changed = 0
            output.withUnsafeBytes { (a: UnsafeRawBufferPointer) in
                expected.withUnsafeBytes { (b: UnsafeRawBufferPointer) in
                    for i in 0..<a.count {
                        let d = abs(Int(a[i]) - Int(b[i]))
                        maxAbs = max(maxAbs, d); sum += d; changed += d == 0 ? 0 : 1
                    }
                }
            }
            let row: [String: Any] = ["test": name, "max_abs": maxAbs,
                "mean_abs": Double(sum) / Double(input.count),
                "frac_nonzero": Double(changed) / Double(input.count), "timing": timing]
            print(String(data: try JSONSerialization.data(withJSONObject: row, options: .sortedKeys), encoding: .utf8)!)
            guard maxAbs <= (nr ? 1 : 2) else { throw GpuOps.Failure.command("D1 exceeded: \(name)") }
        }
    }
}
