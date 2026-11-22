import Combine
import Foundation

/// Owns only captcha presentation and OCR. It never fetches a new challenge or submits a login.
@MainActor
final class CASCaptchaAutofillModel: ObservableObject {
    enum State: Equatable { case idle, disabled, recognizing, filled, manual, failed }

    @Published private(set) var text = ""
    @Published private(set) var state: State = .idle
    private let recognizer: any CASCaptchaRecognizing
    private var imageData: Data?
    private var isActive = false
    private var isEnabled = true
    private var generation = UUID()
    private var manualRevision = 0
    private var hasManualText = false
    private var recognitionTask: Task<Void, Never>?

    init(recognizer: any CASCaptchaRecognizing = CASCaptchaRecognizer.shared) {
        self.recognizer = recognizer
    }

    var isRecognizing: Bool { state == .recognizing }
    var canRetry: Bool {
        isActive && isEnabled && imageData != nil && !isRecognizing && (!hasManualText || text.isEmpty)
    }
    var statusText: String? {
        switch state {
        case .idle: nil
        case .disabled: "已关闭自动填充，可手动输入。"
        case .recognizing: "正在识别当前图片，也可直接手动输入。"
        case .filled: "已自动填入，请核对后登录。"
        case .manual: "已保留手动输入。"
        case .failed: "自动识别未成功，可手动输入或重新识别。"
        }
    }

    func activate(enabled: Bool) {
        isActive = true
        isEnabled = enabled
        if !enabled { cancelRecognition(); state = .disabled }
        else if imageData != nil && text.isEmpty { startRecognition() }
    }

    func deactivate() {
        isActive = false
        cancelPendingRecognition()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        cancelRecognition()
        if !enabled { state = .disabled }
        else if imageData != nil && (!hasManualText || text.isEmpty) { startRecognition() }
        else { state = hasManualText ? .manual : .idle }
    }

    /// Installs exactly the bytes shown by the login form; the recognizer must not request another image.
    func setImage(_ data: Data?) {
        cancelRecognition()
        imageData = data
        text = ""
        hasManualText = false
        manualRevision += 1
        state = isEnabled ? .idle : .disabled
        if data != nil { startRecognition() }
    }

    func userEdited(_ value: String) {
        manualRevision += 1
        cancelRecognition()
        text = value
        hasManualText = true
        state = .manual
    }

    func retry() {
        guard canRetry else { return }
        startRecognition()
    }

    /// Login takes a stable snapshot of the field and invalidates any delayed OCR result first.
    func cancelPendingRecognition() {
        cancelRecognition()
        state = !isEnabled ? .disabled : hasManualText ? .manual : text.isEmpty ? .idle : .filled
    }

    private func cancelRecognition() {
        generation = UUID()
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func startRecognition() {
        guard isActive, isEnabled, let imageData, !hasManualText || text.isEmpty else { return }
        cancelRecognition()
        let requestGeneration = generation
        let editRevision = manualRevision
        let recognizer = recognizer
        text = ""
        state = .recognizing
        recognitionTask = Task { [weak self] in
            do {
                let result = try await recognizer.recognize(imageData)
                guard !Task.isCancelled else { return }
                self?.finish(result: result, generation: requestGeneration, editRevision: editRevision)
            } catch {
                guard !Task.isCancelled else { return }
                self?.finish(result: nil, generation: requestGeneration, editRevision: editRevision)
            }
        }
    }

    private func finish(result: String?, generation requestGeneration: UUID, editRevision: Int) {
        guard isActive, isEnabled, generation == requestGeneration, manualRevision == editRevision else { return }
        recognitionTask = nil
        // Match upstream's trimmed OCR text; no guessed four-character rule or O/0 substitution.
        let value = result?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else { state = .failed; return }
        text = value
        hasManualText = false
        state = .filled
    }
}
