import SwiftUI
import VisionKit
import PhotosUI

struct ScannerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var scannedValue: String?
    @State private var photo: PhotosPickerItem?
    @State private var imageGeneration = UUID()
    @State private var availableCodes: [String] = []
    @State private var isDecoding = false
    @State private var isConfirming = false
    @State private var status: String?
    @State private var showLogin = false
    @State private var openInApp = false
    @State private var openedURL: URL?

    var body: some View {
        ZStack(alignment: .bottom) {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                DataScannerRepresentable(scannedValue: $scannedValue).ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView("实时扫码暂不可用", systemImage: "camera.badge.ellipsis",
                    description: Text("可从相册识别二维码，或在系统设置中允许相机访问。"))
            }
            ScrollView {
                VStack(spacing: 12) {
                    if let value = scannedValue { result(value) }
                    else { Label(isDecoding ? "正在识别相册图片…" : "将二维码放入取景框", systemImage: "viewfinder") }
                    if availableCodes.count > 1 {
                        Picker("图片内的二维码", selection: Binding(get: { scannedValue ?? "" }, set: { scannedValue = $0 })) {
                            ForEach(availableCodes, id: \.self) { Text($0).lineLimit(1).tag($0) }
                        }
                    }
                    if let status { Text(status).font(.footnote).textSelection(.enabled) }
                }.padding(18).frame(maxWidth: 420).adaptiveGlass(cornerRadius: 24)
            }.fixedSize(horizontal: false, vertical: true).frame(maxHeight: 440).padding(.horizontal, 18).padding(.bottom, 20)
        }
        .navigationTitle("扫码").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PhotosPicker(selection: $photo, matching: .images) { Image(systemName: "photo") }.accessibilityLabel("从相册识别")
            }
            ToolbarItem(placement: .topBarTrailing) { Button { showLogin = true } label: { Image(systemName: "person.crop.circle.badge.checkmark") }.accessibilityLabel("指间工大扫码登录") }
        }
        .onChange(of: photo) { _, selected in
            guard let selected else { return }
            let generation = UUID(); imageGeneration = generation
            isDecoding = true; status = nil
            Task {
                do {
                    guard let data = try await selected.loadTransferable(type: Data.self) else { throw ZhiJianScannerError.invalidResponse }
                    let codes = try await ScannerService.decodeImage(data)
                    guard imageGeneration == generation else { return }
                    availableCodes = codes
                    scannedValue = codes.first
                    if codes.isEmpty { status = "图片中没有识别到二维码或条形码，请换一张清晰的图片。" }
                } catch {
                    if imageGeneration == generation {
                        status = (error as? ScannerImageRecognitionError)?.localizedDescription ?? "图片识别失败，请重试。"
                        PlatformDiagnosticsStore.shared.record(context: "相册二维码识别", error: error)
                    }
                }
                if imageGeneration == generation { isDecoding = false; photo = nil }
            }
        }
        .sheet(isPresented: $showLogin) { AppNavigationStack { ZhiJianScannerLoginView() } }
        .sheet(isPresented: $openInApp) { if let openedURL { AppNavigationStack { PortalWebView(url: openedURL).navigationTitle("扫码链接").navigationBarTitleDisplayMode(.inline) } } }
        .onDisappear { imageGeneration = UUID() }
    }

    @ViewBuilder private func result(_ value: String) -> some View {
        Text(value).font(.subheadline).lineLimit(4).textSelection(.enabled)
        if ScannerService.casURL(value) != nil {
            Text("统一身份认证登录二维码").font(.headline)
            Button(isConfirming ? "正在确认…" : "确认登录该设备") {
                isConfirming = true; status = nil
                Task {
                    defer { isConfirming = false }
                    do { try await ZhiJianScannerClient.shared.confirm(value); status = "已确认登录，请查看待登录设备。" }
                    catch ZhiJianScannerError.loginRequired { showLogin = true; status = ZhiJianScannerError.loginRequired.localizedDescription }
                    catch { status = (error as? ZhiJianScannerError)?.localizedDescription ?? "网络请求失败，请稍后重试。" }
                }
            }.buttonStyle(.borderedProminent).disabled(isConfirming)
        } else if PlatformDeepLinkURL.url(from: value) != nil {
            Button("打开 App 内页面") { _ = appState.open(value) }
        } else if let wifi = ScannedWiFi.parse(value) {
            LabeledContent("无线网络", value: wifi.name)
            Button("复制 Wi-Fi 密码") { UIPasteboard.general.string = wifi.password; status = "密码已复制，可在系统 Wi-Fi 列表中连接 \(wifi.name)。" }
        } else if let url = ScannerService.webURL(value) {
            Button("在 App 内打开链接") { openedURL = url; openInApp = true }
        }
        HStack {
            Button("复制结果", systemImage: "doc.on.doc") { UIPasteboard.general.string = value; status = "已复制识别结果。" }
            Spacer()
            Button("继续扫描", systemImage: "viewfinder") {
                imageGeneration = UUID(); scannedValue = nil; availableCodes = []; status = nil
            }.disabled(isConfirming)
        }
    }
}

struct ZhiJianScannerLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var status: String?
    var body: some View {
        Form {
            Section("指间工大扫码服务") {
                TextField("学号", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("信息门户密码", text: $password).textContentType(.password)
                Text("使用与原版一致的校方扫码接口。密码仅用于本次登录；会话票据保存在系统钥匙串中。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button(busy ? "正在登录…" : "登录扫码服务") {
                    busy = true; status = nil
                    Task {
                        defer { busy = false; password = "" }
                        do { try await ZhiJianScannerClient.shared.login(username: username, password: password); dismiss() }
                        catch { status = (error as? ZhiJianScannerError)?.localizedDescription ?? "网络请求失败，请稍后重试。" }
                    }
                }.disabled(busy || username.isEmpty || password.isEmpty)
                Button("退出扫码服务", role: .destructive) { Task { await ZhiJianScannerClient.shared.logout(); status = "已退出扫码服务。" } }.disabled(busy)
            }
            if let status { Section { Text(status).font(.footnote) } }
        }.navigationTitle("扫码登录").toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
    }
}

struct DataScannerRepresentable: UIViewControllerRepresentable {
    @Binding var scannedValue: String?
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(recognizedDataTypes: [.barcode()], qualityLevel: .balanced,
            recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: true, isPinchToZoomEnabled: true,
            isGuidanceEnabled: true, isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.parent = self
        if scannedValue != nil { controller.stopScanning() }
        else if !controller.isScanning { try? controller.startScanning() }
    }
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) { controller.stopScanning() }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: DataScannerRepresentable
        init(parent: DataScannerRepresentable) { self.parent = parent }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard parent.scannedValue == nil, let item = addedItems.first else { return }
            if case let .barcode(barcode) = item { parent.scannedValue = barcode.payloadStringValue }
        }
    }
}
