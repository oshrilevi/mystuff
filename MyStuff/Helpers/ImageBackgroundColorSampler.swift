import Foundation
import CoreGraphics
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Samples the image at 8 points (4 corners + 4 edge centers), drops the 4 farthest from the median
/// in RGB space, and returns the average of the remaining 4 as (red, green, blue) in 0...1.
/// Used to infer the "background" color for thumbnail letterbox fill; robust to a single bad pixel.
enum ImageBackgroundColorSampler {
    private static let maxSampleSide: Int = 100
    private static let cacheLock = NSLock()
    private static var cache: [String: (Double, Double, Double)] = [:]
    private static let cacheCountLimit = 300

    /// Returns (red, green, blue) in 0...1, or nil on failure.
    /// If `fileId` is provided, result is cached and returned from cache on subsequent calls.
    static func sampleBackgroundRGB(from data: Data, fileId: String? = nil) -> (red: Double, green: Double, blue: Double)? {
        if let id = fileId {
            cacheLock.lock()
            if let cached = cache[id] {
                cacheLock.unlock()
                return cached
            }
            cacheLock.unlock()
        }

        guard let cgImage = decodeToCGImage(data: data) else { return nil }
        guard let rgb = sampleEdgeRGBWithOutlierRemoval(cgImage: cgImage) else { return nil }

        if let id = fileId {
            cacheLock.lock()
            if cache.count >= cacheCountLimit, let first = cache.keys.first {
                cache.removeValue(forKey: first)
            }
            cache[id] = rgb
            cacheLock.unlock()
        }
        return rgb
    }

    private static func decodeToCGImage(data: Data) -> CGImage? {
        #if os(iOS)
        guard let uiImage = UIImage(data: data) else { return nil }
        return uiImage.cgImage
        #elseif os(macOS)
        guard let nsImage = NSImage(data: data) else { return nil }
        return nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return nil
        #endif
    }

    private static func sampleEdgeRGBWithOutlierRemoval(cgImage: CGImage) -> (Double, Double, Double)? {
        let w = cgImage.width
        let h = cgImage.height
        guard w >= 1, h >= 1 else { return nil }

        let scale = min(1, Double(maxSampleSide) / Double(max(w, h)))
        let sw = max(1, Int(Double(w) * scale))
        let sh = max(1, Int(Double(h) * scale))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: nil,
            width: sw,
            height: sh,
            bitsPerComponent: 8,
            bytesPerRow: 4 * sw,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sw, height: sh))
        guard let data = context.data else { return nil }
        let bytes = data.assumingMemoryBound(to: UInt8.self)

        let i = { (x: Int, y: Int) -> Int in
            (sh - 1 - y) * sw * 4 + x * 4
        }
        let offset = min(2, sw / 4)
        let oy = min(2, sh / 4)
        let cx = min(sw - 1 - offset, max(offset, sw / 2))
        let cy = min(sh - 1 - oy, max(oy, sh / 2))

        let positions: [(Int, Int)] = [
            (offset, oy),
            (sw - 1 - offset, oy),
            (offset, sh - 1 - oy),
            (sw - 1 - offset, sh - 1 - oy),
            (cx, oy),
            (sw - 1 - offset, cy),
            (cx, sh - 1 - oy),
            (offset, cy),
        ]

        var samples: [(r: Double, g: Double, b: Double)] = []
        for (px, py) in positions {
            let idx = i(px, py)
            guard idx + 2 < sw * sh * 4 else { continue }
            let r = Double(bytes[idx]) / 255
            let g = Double(bytes[idx + 1]) / 255
            let b = Double(bytes[idx + 2]) / 255
            samples.append((r, g, b))
        }
        guard samples.count >= 4 else { return nil }

        let medianR = median(samples.map(\.r))
        let medianG = median(samples.map(\.g))
        let medianB = median(samples.map(\.b))

        let withDistance = samples.map { s -> (r: Double, g: Double, b: Double, d2: Double) in
            let d2 = (s.r - medianR) * (s.r - medianR) + (s.g - medianG) * (s.g - medianG) + (s.b - medianB) * (s.b - medianB)
            return (s.r, s.g, s.b, d2)
        }
        let kept = withDistance.sorted { $0.d2 < $1.d2 }.prefix(4)
        let count = kept.count
        guard count > 0 else { return nil }
        let sumR = kept.reduce(0) { $0 + $1.r }
        let sumG = kept.reduce(0) { $0 + $1.g }
        let sumB = kept.reduce(0) { $0 + $1.b }
        return (sumR / Double(count), sumG / Double(count), sumB / Double(count))
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let c = sorted.count
        if c == 0 { return 0 }
        if c.isMultiple(of: 2) {
            return (sorted[c / 2 - 1] + sorted[c / 2]) / 2
        }
        return sorted[c / 2]
    }
}
