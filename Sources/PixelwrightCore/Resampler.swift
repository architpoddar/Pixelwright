import Foundation

/// Wraps a raw pointer so it can be captured by concurrent row workers. Each worker writes
/// only its own rows, so there is no overlap.
private struct SharedPointer<T>: @unchecked Sendable {
    let base: UnsafeMutablePointer<T>
}

/// Read-only counterpart: workers only read from it, and it outlives them (the enclosing
/// `withUnsafeBufferPointer` call doesn't return until every worker is done).
private struct SharedReadBuffer<T>: @unchecked Sendable {
    let buffer: UnsafeBufferPointer<T>
    subscript(index: Int) -> T { buffer[index] }
}

public enum Resampler {
    /// Resizes `image` to `width` x `height`.
    ///
    /// Pixels are filtered as premultiplied RGBA floats so transparent pixels do not bleed
    /// color into their neighbors. With `gammaCorrect` the filtering happens in linear light
    /// (what the "Use gamma correction" checkbox does); without it, directly on the
    /// sRGB-encoded values.
    public static func resize(
        _ image: RasterImage,
        width: Int,
        height: Int,
        method: ResamplingMethod = .bicubic,
        gammaCorrect: Bool = true
    ) -> RasterImage {
        precondition(width > 0 && height > 0, "target size must be at least 1x1")
        if width == image.width && height == image.height { return image }

        let scaleX = Double(width) / Double(image.width)
        let scaleY = Double(height) / Double(image.height)
        guard let strategy = method.weightStrategy(scaleX: scaleX, scaleY: scaleY) else {
            return nearestNeighbor(image, width: width, height: height)
        }

        let source = toPremultiplied(image, linear: gammaCorrect)
        let xWeights = AxisWeights(sourceSize: image.width, destinationSize: width, strategy: strategy)
        let yWeights = AxisWeights(sourceSize: image.height, destinationSize: height, strategy: strategy)

        let horizontal = horizontalPass(source, srcWidth: image.width, rows: image.height, weights: xWeights, dstWidth: width)
        let both = verticalPass(horizontal, width: width, srcRows: image.height, weights: yWeights, dstRows: height)
        return fromPremultiplied(both, width: width, height: height, linear: gammaCorrect)
    }

    // MARK: Nearest neighbor (works directly on bytes, no color math)

    private static func nearestNeighbor(_ image: RasterImage, width: Int, height: Int) -> RasterImage {
        var out = [UInt8](repeating: 0, count: width * height * 4)
        let xMap = (0..<width).map { min(image.width - 1, Int((Double($0) + 0.5) * Double(image.width) / Double(width))) }
        let yMap = (0..<height).map { min(image.height - 1, Int((Double($0) + 0.5) * Double(image.height) / Double(height))) }
        image.pixels.withUnsafeBufferPointer { src in
            for y in 0..<height {
                let srcRow = yMap[y] * image.width
                let dstRow = y * width
                for x in 0..<width {
                    let s = (srcRow + xMap[x]) * 4
                    let d = (dstRow + x) * 4
                    out[d] = src[s]
                    out[d + 1] = src[s + 1]
                    out[d + 2] = src[s + 2]
                    out[d + 3] = src[s + 3]
                }
            }
        }
        return RasterImage(width: width, height: height, pixels: out)
    }

    // MARK: Filtering passes

    private static func horizontalPass(
        _ src: [Float], srcWidth: Int, rows: Int, weights: AxisWeights, dstWidth: Int
    ) -> [Float] {
        var dst = [Float](repeating: 0, count: dstWidth * rows * 4)
        dst.withUnsafeMutableBufferPointer { dstBuf in
            let out = SharedPointer(base: dstBuf.baseAddress!)
            src.withUnsafeBufferPointer { srcRaw in
                let srcBuf = SharedReadBuffer(buffer: srcRaw)
                weights.weights.withUnsafeBufferPointer { wRaw in
                    let wBuf = SharedReadBuffer(buffer: wRaw)
                    DispatchQueue.concurrentPerform(iterations: rows) { y in
                        let srcRow = y * srcWidth * 4
                        let dstRow = y * dstWidth * 4
                        for x in 0..<dstWidth {
                            let start = weights.starts[x]
                            let count = weights.counts[x]
                            let wOff = weights.offsets[x]
                            var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
                            for k in 0..<count {
                                let w = wBuf[wOff + k]
                                let s = srcRow + (start + k) * 4
                                r += w * srcBuf[s]
                                g += w * srcBuf[s + 1]
                                b += w * srcBuf[s + 2]
                                a += w * srcBuf[s + 3]
                            }
                            let d = dstRow + x * 4
                            out.base[d] = r
                            out.base[d + 1] = g
                            out.base[d + 2] = b
                            out.base[d + 3] = a
                        }
                    }
                }
            }
        }
        return dst
    }

    private static func verticalPass(
        _ src: [Float], width: Int, srcRows: Int, weights: AxisWeights, dstRows: Int
    ) -> [Float] {
        let rowLength = width * 4
        var dst = [Float](repeating: 0, count: rowLength * dstRows)
        dst.withUnsafeMutableBufferPointer { dstBuf in
            let out = SharedPointer(base: dstBuf.baseAddress!)
            src.withUnsafeBufferPointer { srcRaw in
                let srcBuf = SharedReadBuffer(buffer: srcRaw)
                weights.weights.withUnsafeBufferPointer { wRaw in
                    let wBuf = SharedReadBuffer(buffer: wRaw)
                    DispatchQueue.concurrentPerform(iterations: dstRows) { y in
                        let start = weights.starts[y]
                        let count = weights.counts[y]
                        let wOff = weights.offsets[y]
                        let dstRow = out.base + y * rowLength
                        for k in 0..<count {
                            let w = wBuf[wOff + k]
                            let srcRow = (start + k) * rowLength
                            for i in 0..<rowLength {
                                dstRow[i] += w * srcBuf[srcRow + i]
                            }
                        }
                    }
                }
            }
        }
        return dst
    }

    // MARK: Color conversion

    /// sRGB byte -> linear light, 0...1.
    private static let decodeTable: [Float] = (0..<256).map { i in
        let c = Double(i) / 255
        let linear = c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        return Float(linear)
    }

    private static let encodeTableSize = 4096
    /// Linear light -> sRGB, 0...1, sampled for lookup with interpolation.
    private static let encodeTable: [Float] = (0..<4096).map { i in
        let l = Double(i) / 4095
        let c = l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055
        return Float(c)
    }

    private static func encode(_ linear: Float) -> Float {
        let v = min(max(linear, 0), 1) * Float(encodeTableSize - 1)
        let i = Int(v)
        if i >= encodeTableSize - 1 { return encodeTable[encodeTableSize - 1] }
        let f = v - Float(i)
        return encodeTable[i] + (encodeTable[i + 1] - encodeTable[i]) * f
    }

    private static func toPremultiplied(_ image: RasterImage, linear: Bool) -> [Float] {
        var out = [Float](repeating: 0, count: image.width * image.height * 4)
        for p in 0..<(image.width * image.height) {
            let i = p * 4
            let a = Float(image.pixels[i + 3]) / 255
            let r: Float, g: Float, b: Float
            if linear {
                r = decodeTable[Int(image.pixels[i])]
                g = decodeTable[Int(image.pixels[i + 1])]
                b = decodeTable[Int(image.pixels[i + 2])]
            } else {
                r = Float(image.pixels[i]) / 255
                g = Float(image.pixels[i + 1]) / 255
                b = Float(image.pixels[i + 2]) / 255
            }
            out[i] = r * a
            out[i + 1] = g * a
            out[i + 2] = b * a
            out[i + 3] = a
        }
        return out
    }

    private static func fromPremultiplied(_ data: [Float], width: Int, height: Int, linear: Bool) -> RasterImage {
        var out = [UInt8](repeating: 0, count: width * height * 4)
        for p in 0..<(width * height) {
            let i = p * 4
            // Cubic and Lanczos can overshoot; keep alpha in range and color within alpha.
            let a = min(max(data[i + 3], 0), 1)
            if a <= 0 { continue }
            var channels: [Float] = [0, 0, 0]
            for c in 0..<3 {
                var v = min(max(data[i + c], 0), a) / a
                if linear { v = encode(v) }
                channels[c] = v
            }
            out[i] = UInt8(min(255, max(0, channels[0] * 255 + 0.5)))
            out[i + 1] = UInt8(min(255, max(0, channels[1] * 255 + 0.5)))
            out[i + 2] = UInt8(min(255, max(0, channels[2] * 255 + 0.5)))
            out[i + 3] = UInt8(min(255, max(0, a * 255 + 0.5)))
        }
        return RasterImage(width: width, height: height, pixels: out)
    }
}
