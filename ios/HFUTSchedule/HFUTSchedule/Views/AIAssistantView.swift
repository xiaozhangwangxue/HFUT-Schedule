import SwiftUI

struct AIAssistantView: View {
    var page: DeepSeekWebPageContext?
    var initialQuestion: String? = nil
    @AppStorage("aiDeepSeekModel") private var modelName = DeepSeekModel.flash.rawValue
    @State private var input = ""
    @State private var messages: [DeepSeekMessage] = []
    @State private var hasAPIKey = false
    @State private var pendingQuestion: String?
    @State private var errorMessage: String?
    @State private var requestTask: Task<Void, Never>?
    @FocusState private var inputIsFocused: Bool

    private var isSending: Bool { pendingQuestion != nil }
    private var model: DeepSeekModel { DeepSeekModel(rawValue: modelName) ?? .flash }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    Picker("模型", selection: $modelName) {
                        ForEach(DeepSeekModel.allCases) { model in Text(model.title).tag(model.rawValue) }
                    }
                    .disabled(isSending)
                    AppNavigationLink { NetworkSettingsView() } label: {
                        Label(hasAPIKey ? "DeepSeek 已配置" : "配置 DeepSeek ApiKey", systemImage: "key.fill")
                    }
                } footer: {
                    Text("发送的消息由 DeepSeek 处理；对话仅保留在当前页面。")
                }

                if let page {
                    Section("网页摘要") {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(page.title.isEmpty ? "当前网页" : page.title).font(.subheadline.weight(.medium))
                            Text(page.sourceURL.absoluteString).font(.caption).foregroundStyle(.secondary)
                            Text("发送时附上当前网页正文（\(page.text.count) 字，最多 \(DeepSeekWebPageContext.maximumCharacters) 字）。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        DisclosureGroup("查看网页正文") {
                            Text(page.text).font(.caption).textSelection(.enabled)
                        }
                    }
                }

                if messages.isEmpty && !isSending {
                    Section {
                        ContentUnavailableView(
                            hasAPIKey ? "发送消息以开始聊天" : "请先配置 DeepSeek",
                            systemImage: "sparkles",
                            description: Text(hasAPIKey ? "可连续提问，也可以从网页工具栏发起摘要。" : "在网络设置中填写自己的 ApiKey 后即可使用。")
                        )
                    }
                }

                ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                    messageRow(message)
                }
                if let pendingQuestion {
                    messageRow(.init(role: .user, content: pendingQuestion))
                    HStack { ProgressView(); Text("正在等待 DeepSeek 回复…").foregroundStyle(.secondary) }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                        Text("输入内容已保留，可重新发送。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("输入内容后发送", text: $input, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.roundedBorder)
                    .focused($inputIsFocused)
                    .disabled(isSending)
                if isSending {
                    Button("停止", systemImage: "stop.circle.fill") { requestTask?.cancel() }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("停止生成")
                } else {
                    Button("发送", systemImage: "arrow.up.circle.fill", action: send)
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .disabled(!hasAPIKey || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle("AI 助手")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("清空对话", systemImage: "trash") {
                    messages = []
                    errorMessage = nil
                }
                .disabled(isSending || messages.isEmpty)
            }
        }
        .onAppear {
            hasAPIKey = !(AppSecretStore.read(AppSecretStore.Account.aiAPIKey) ?? "").isEmpty
            if messages.isEmpty && input.isEmpty {
                if let initialQuestion { input = initialQuestion }
                else if page != nil { input = "简明扼要地归纳网页中的关键信息，包括需要注意的时间、地点与操作。" }
            }
        }
        .onDisappear { requestTask?.cancel() }
    }

    private func messageRow(_ message: DeepSeekMessage) -> some View {
        Section(message.role == .user ? "我" : "DeepSeek") {
            Text(message.content).textSelection(.enabled)
        }
    }

    @MainActor
    private func send() {
        guard !isSending else { return }
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        let key = AppSecretStore.read(AppSecretStore.Account.aiAPIKey) ?? ""
        guard !key.isEmpty else {
            hasAPIKey = false
            errorMessage = DeepSeekClientError.missingAPIKey.localizedDescription
            return
        }
        let newMessage = DeepSeekMessage(role: .user, content: question)
        let requestMessages = (page?.messages ?? []) + messages + [newMessage]
        let selectedModel = model
        pendingQuestion = question
        errorMessage = nil
        inputIsFocused = false
        requestTask = Task {
            do {
                let reply = try await DeepSeekClient().chat(apiKey: key, messages: requestMessages, model: selectedModel)
                guard !Task.isCancelled else { pendingQuestion = nil; return }
                messages += [newMessage, reply]
                input = ""
            } catch is CancellationError {
                // Keep the draft and previous successful turns when the user stops a request.
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
            pendingQuestion = nil
            requestTask = nil
        }
    }
}
