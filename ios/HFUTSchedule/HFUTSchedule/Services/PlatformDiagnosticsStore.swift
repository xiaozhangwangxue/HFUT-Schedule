import Foundation

struct PlatformDiagnosticReport: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let context: String
    let message: String
    let errorType: String
    let callStack: [String]

    var exportText: String {
        (["\(createdAt.formatted()) · \(context)", errorType, message, "调用位置："] + callStack).joined(separator: "\n")
    }
}

enum PlatformDiagnosticRedactor {
    static func safeMessage(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 600 || trimmed.hasPrefix("{") || trimmed.hasPrefix("[") ||
            trimmed.range(of: #"(?i)<(?:!doctype|html|body|script|div|form)\b"#, options: .regularExpression) != nil {
            return "服务返回了较长或结构化的错误内容，原始响应未记录。"
        }
        let withoutObjects = trimmed.replacingOccurrences(of: #"\{[\s\S]*\}"#, with: "[原始结构化内容未记录]", options: .regularExpression)
        return redact(withoutObjects.replacingOccurrences(of: #"https?://[^\s\"'<>]+"#, with: "[URL路径与参数已省略]", options: .regularExpression))
    }
    static func redact(_ value: String) -> String {
        var text = String(value.prefix(16_384))
        let patterns = [
            #"(?im)(?:cookie|set-cookie|authorization)\s*:\s*[^\r\n]+"#,
            #"(?i)Bearer\s+[A-Za-z0-9._~+/=-]+"#,
            #"(?i)(?:password|passwd|upass|cookie|authorization|ticket|token|access_token|refresh_token|api[_-]?key)\s*[=:]\s*[^\s&,;\"']+"#,
            #"(?i)https?://[^\s/:]+:[^\s/@]+@"#
        ]
        for pattern in patterns { text = text.replacingOccurrences(of: pattern, with: "[已隐藏凭据]", options: .regularExpression) }
        return text
    }
}

@MainActor
final class PlatformDiagnosticsStore: ObservableObject {
    static let shared = PlatformDiagnosticsStore()
    @Published private(set) var reports: [PlatformDiagnosticReport] = []
    @discardableResult func record(context: String, error: Error) -> PlatformDiagnosticReport {
        let nsError = error as NSError
        let report = PlatformDiagnosticReport(id: UUID(), createdAt: Date(), context: String(PlatformDiagnosticRedactor.redact(context).prefix(160)),
            message: PlatformDiagnosticRedactor.safeMessage(error.localizedDescription),
            errorType: "\(String(reflecting: type(of: error))) · \(String(nsError.domain.prefix(120))) (\(nsError.code))",
            callStack: Thread.callStackSymbols.prefix(20).map(PlatformDiagnosticRedactor.redact))
        reports.insert(report, at: 0)
        reports = Array(reports.prefix(30))
        return report
    }
    nonisolated static func capture(context: String, error: Error) {
        Task { @MainActor in shared.record(context: context, error: error) }
    }
    func clear() { reports = [] }
}
