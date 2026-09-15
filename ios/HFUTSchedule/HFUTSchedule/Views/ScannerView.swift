import SwiftUI
import VisionKit

struct ScannerView: View {
    @State private var scannedValue: String?

    var body: some View {
        Group {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                ZStack(alignment: .bottom) {
                    DataScannerRepresentable(scannedValue: $scannedValue)
                        .ignoresSafeArea(edges: .bottom)

                    VStack(spacing: 7) {
                        Image(systemName: "viewfinder")
                            .font(.title2.weight(.semibold))
                        Text(scannedValue ?? "将二维码放入取景框")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(3)
                            .multilineTextAlignment(.center)
                    }
                    .padding(18)
                    .frame(maxWidth: 320)
                    .adaptiveGlass(cornerRadius: 24)
                    .padding(.bottom, 24)
                }
            } else {
                ContentUnavailableView(
                    "设备不支持实时扫码",
                    systemImage: "camera.badge.ellipsis",
                    description: Text("请在支持的 iPhone 或 iPad 上使用。")
                )
            }
        }
        .navigationTitle("扫码")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    @Binding var scannedValue: String?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if !controller.isScanning { try? controller.startScanning() }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: DataScannerRepresentable

        init(parent: DataScannerRepresentable) {
            self.parent = parent
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard let item = addedItems.first else { return }
            if case let .barcode(barcode) = item {
                parent.scannedValue = barcode.payloadStringValue
            }
        }
    }
}
