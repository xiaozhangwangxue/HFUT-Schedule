import SwiftUI
import UIKit
import XCTest
@testable import HFUTSchedule

@MainActor
final class CASLoginLifecycleTests: XCTestCase {
    func testParentRedrawPreservesThePreparedViewsClient() throws {
        let recorder = CASClientIdentityRecorder()
        let host = UIHostingController(rootView: page(revision:0,recorder:recorder))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene:scene)
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true }
        host.view.frame = CGRect(x:0,y:0,width:402,height:874)
        settle(host)
        let first = try XCTUnwrap(recorder.identities.last)
        // Recreate NativeCASLoginView exactly as the parent login page does
        // when its UI state changes. Its identity in the hierarchy is stable.
        host.rootView = page(revision:1,recorder:recorder)
        settle(host)
        XCTAssertEqual(recorder.identities.last,first,"Visible preparation must keep the client holding its AES key")
        XCTAssertEqual(Set(recorder.identities).count,1)
    }
    private func page(revision:Int,recorder:CASClientIdentityRecorder) -> some View {
        VStack {
            Text("Redraw \(revision)")
            NativeCASLoginView(mode:.direct,onAuthenticated:{ _,_,_ in },
                initialPreparation:CASLoginPreparation(execution:"offline-prepared-form",needsCaptcha:false,captchaImageData:nil))
                .onPreferenceChange(CASLoginClientIdentityPreference.self) { if let value = $0 { recorder.identities.append(value) } }
        }
    }
    private func settle<Content:View>(_ host:UIHostingController<Content>) {
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        RunLoop.main.run(until:Date().addingTimeInterval(0.2))
        host.view.layoutIfNeeded()
    }
}

@MainActor
private final class CASClientIdentityRecorder { var identities:[ObjectIdentifier] = [] }
