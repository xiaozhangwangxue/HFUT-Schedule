import Foundation
import CoreGraphics
import ImageIO

/// Bounded thumbnail sampling avoids decoding a full-resolution photo into a large RGBA buffer.
enum ThemeImageColorExtractor {
    static func dominantHex(in data: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 64,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        let width = image.width, height = image.height
        guard width > 0, height > 0, width <= 64, height <= 64 else { throw CocoaError(.fileReadCorruptFile) }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw CocoaError(.fileReadCorruptFile) }
        struct Bucket { var count = 0; var red = 0; var green = 0; var blue = 0 }
        var buckets: [Int: Bucket] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = Int(pixels[i + 3])
            guard a >= 128 else { continue }
            let r = min(255, Int(pixels[i]) * 255 / a), g = min(255, Int(pixels[i + 1]) * 255 / a), b = min(255, Int(pixels[i + 2]) * 255 / a)
            let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
            var bucket = buckets[key, default: Bucket()]
            bucket.count += 1; bucket.red += r; bucket.green += g; bucket.blue += b
            buckets[key] = bucket
        }
        guard let chosen = buckets.sorted(by: { $0.key < $1.key }).max(by: { $0.value.count < $1.value.count })?.value else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return String(format: "%02X%02X%02X", chosen.red / chosen.count, chosen.green / chosen.count, chosen.blue / chosen.count)
    }
}
