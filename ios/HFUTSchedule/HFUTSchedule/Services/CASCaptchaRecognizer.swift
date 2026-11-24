import Foundation
import CoreGraphics
import ImageIO
import libtesseract

protocol CASCaptchaRecognizing: Sendable {
    func recognize(_ imageData: Data) async throws -> String
}

/// Uses the upstream CAPTCHA training data and single-line Tesseract pipeline.
/// Actor isolation keeps decoding and recognition off the main actor and serializes the C engine.
actor CASCaptchaRecognizer: CASCaptchaRecognizing {
    static let shared = CASCaptchaRecognizer()
    private let modelDirectory: URL?
    private let usesManagedModel: Bool

    init() {
        self.modelDirectory = nil
        self.usesManagedModel = true
    }

    /// Explicit injection, including nil, always takes precedence over the managed/bundled model.
    init(modelDirectory: URL?) {
        self.modelDirectory = modelDirectory
        self.usesManagedModel = false
    }

    func recognize(_ imageData: Data) async throws -> String {
        try Task.checkCancellation()
        let image = try Self.grayscaleImage(imageData)
        guard let modelDirectory = usesManagedModel ? CaptchaModelStore.effectiveDirectory : modelDirectory,
              FileManager.default.fileExists(atPath: modelDirectory.appendingPathComponent("captcha.traineddata").path)
        else { throw RecognitionError.missingModel }
        guard let engine = TessBaseAPICreate() else { throw RecognitionError.initializationFailed }
        defer {
            TessBaseAPIEnd(engine)
            TessBaseAPIDelete(engine)
        }
        guard TessBaseAPIInit2(engine, modelDirectory.path, "captcha", OEM_LSTM_ONLY) == 0
        else { throw RecognitionError.initializationFailed }
        TessBaseAPISetPageSegMode(engine, PSM_SINGLE_LINE)
        try Task.checkCancellation()
        let text: String? = image.pixels.withUnsafeBytes { bytes in
            guard let address = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            TessBaseAPISetImage(engine, address, Int32(image.width), Int32(image.height), 1, Int32(image.width))
            guard let result = TessBaseAPIGetUTF8Text(engine) else { return nil }
            defer { TessDeleteText(result) }
            return String(cString: result).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        try Task.checkCancellation()
        guard let text, !text.isEmpty else { throw RecognitionError.noText }
        return text
    }

    struct GrayscaleImage {
        let width: Int
        let height: Int
        let pixels: Data
    }

    /// Mirrors upstream 0.299 R + 0.587 G + 0.114 B, without thresholding or guessing characters.
    static func grayscaleImage(_ data: Data) throws -> GrayscaleImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 2048, height <= 2048,
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw RecognitionError.invalidImage }
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw RecognitionError.invalidImage }
        var gray = Data(count: width * height)
        gray.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for i in 0..<(width * height) {
                bytes[i] = UInt8(0.299 * Double(rgba[4 * i]) + 0.587 * Double(rgba[4 * i + 1]) + 0.114 * Double(rgba[4 * i + 2]))
            }
        }
        return GrayscaleImage(width: width, height: height, pixels: gray)
    }

    enum RecognitionError: LocalizedError, Equatable {
        case invalidImage, missingModel, initializationFailed, noText
        var errorDescription: String? {
            switch self {
            case .invalidImage: return "验证码图片无法读取，请刷新或手动填写"
            case .missingModel: return "未找到本地识别模型，请手动填写验证码"
            case .initializationFailed: return "本地识别模型无法加载，请手动填写验证码"
            case .noText: return "未识别出验证码，请手动填写或刷新图片"
            }
        }
    }
}
