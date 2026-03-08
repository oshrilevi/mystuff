import Foundation
import CoreGraphics
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Samples the image at the corners and returns the average color as (red, green, blue) in 0...1.
/// Used to infer the "background" color for thumbnail letterbox fill.
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
        guard let rgb = sampleCornerRGB(cgImage: cgImage) else { return nil }

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

    private static func sampleCornerRGB(cgImage: CGImage) -> (Double, Double, Double)? {
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
        var r: Double = 0, g: Double = 0, b: Double = 0
        var count = 0
        for (px, py) in [(offset, oy), (sw - 1 - offset, oy), (offset, sh - 1 - oy), (sw - 1 - offset, sh - 1 - oy)] {
            let idx = i(px, py)
            guard idx + 2 < sw * sh * 4 else { continue }
            r += Double(bytes[idx]) / 255
            g += Double(bytes[idx + 1]) / 255
            b += Double(bytes[idx + 2]) / 255
            count += 1
        }
        guard count > 0 else { return nil }
        return (r / Double(count), g / Double(count), b / Double(count))
    }
}
