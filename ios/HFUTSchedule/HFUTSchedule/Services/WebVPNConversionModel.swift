import Foundation
import Combine

@MainActor
final class WebVPNConversionModel: ObservableObject {
    enum Direction: String, CaseIterable, Identifiable {
        case toWebVPN, toOriginal
        var id: String { rawValue }
        var title: String { self == .toWebVPN ? "转换为 WebVPN" : "还原原始链接" }
    }

    struct Form {
        var input = ""
        var result: URL?
    }

    @Published var direction: Direction = .toWebVPN
    @Published private(set) var forward = Form()
    @Published private(set) var reverse = Form()

    var input: String {
        get { direction == .toWebVPN ? forward.input : reverse.input }
        set {
            if direction == .toWebVPN { forward = Form(input: newValue, result: nil) }
            else { reverse = Form(input: newValue, result: nil) }
        }
    }

    var result: URL? { direction == .toWebVPN ? forward.result : reverse.result }
    var canConvert: Bool { candidate != nil }

    private var candidate: URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return direction == .toWebVPN ? WebVPNURLConverter.convert(text) : WebVPNURLConverter.restore(text)
    }

    @discardableResult
    func convert() -> Bool {
        let value = candidate
        if direction == .toWebVPN { forward.result = value }
        else { reverse.result = value }
        return value != nil
    }

    func clearResult() {
        if direction == .toWebVPN { forward.result = nil }
        else { reverse.result = nil }
    }

    func canOpenResult(hasSession: Bool) -> Bool {
        result != nil && (direction == .toOriginal || hasSession)
    }
}
