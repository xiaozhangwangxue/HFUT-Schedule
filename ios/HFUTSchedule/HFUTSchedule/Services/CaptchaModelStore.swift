import Foundation
import libtesseract

/// Only user-installed models are writable; deleting them restores the included upstream model.
enum CaptchaModelStore {
    static let downloadURL = URL(string: "https://gitee.com/chiu-xah/HFUT-Schedule/releases/download/Android/eng.traineddata")!
    static let maximumBytes = 52_428_800
    static var customDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HFUTSchedule/ocr/tessdata", isDirectory: true)
    }
    static var customModel: URL { customDirectory.appendingPathComponent("captcha.traineddata") }
    static var hasCustomModel: Bool { FileManager.default.fileExists(atPath: customModel.path) }
    static var effectiveDirectory: URL? { hasCustomModel ? customDirectory : Bundle.main.url(forResource: "tessdata", withExtension: nil) }
    static var statusText: String { hasCustomModel ? "用户模型" : effectiveDirectory == nil ? "模型缺失" : "内置原版模型" }

    static func install(_ data: Data, directory: URL = customDirectory) throws {
        guard !data.isEmpty, data.count <= maximumBytes else { throw ModelError.invalidSize }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("ocr-import-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary.appendingPathComponent("captcha.traineddata"), options: .atomic)
        guard let engine = TessBaseAPICreate() else { throw ModelError.invalidModel }
        defer { TessBaseAPIEnd(engine); TessBaseAPIDelete(engine) }
        guard TessBaseAPIInit2(engine, temporary.path, "captcha", OEM_LSTM_ONLY) == 0 else { throw ModelError.invalidModel }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("captcha.traineddata"), options: .atomic)
    }
    static func installAsync(_ data: Data) async throws {
        let worker = Task.detached(priority: .utility) { try install(data) }
        try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { worker.cancel() }
    }
    static func removeCustom(directory: URL = customDirectory) throws {
        let file = directory.appendingPathComponent("captcha.traineddata")
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
    static func download(session: URLSession = .shared) async throws {
        var request = URLRequest(url: downloadURL); request.timeoutInterval = 60
        let (file, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: file) }
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              response.expectedContentLength <= Int64(maximumBytes),
              let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maximumBytes else { throw ModelError.invalidSize }
        try Task.checkCancellation()
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        try await installAsync(data)
    }
    enum ModelError: LocalizedError {
        case invalidSize, invalidModel
        var errorDescription: String? {
            switch self {
            case .invalidSize: "模型为空、下载未成功或超过 50 MB"
            case .invalidModel: "文件不是可用的 Tesseract LSTM 模型，已保留原模型"
            }
        }
    }
}
