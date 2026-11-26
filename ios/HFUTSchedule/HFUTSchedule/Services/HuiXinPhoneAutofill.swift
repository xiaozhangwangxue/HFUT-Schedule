import Foundation
import WebKit

/// Phone-based HuiXin fee forms. Never inject a phone into unrelated pages,
/// account selection for electricity, or an embedded third-party frame.
struct HuiXinPhoneAutofill: Equatable {
    static let feeItemIDs: Set<Int> = [26, 222, 223]
    static let scriptMarker = "/* HFUT HuiXin phone autofill */"
    let phone: String
    let itemID: Int

    static func isOfficialChargePage(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""), components.host == "121.251.19.62",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == (components.scheme?.lowercased() == "https" ? 443 : 80) else { return false }
        return ["/charge-app", "/charge-app/", "/charge-app/index.html"].contains(components.path)
    }

    init?(phone: String?, itemID: Int, url: URL) {
        guard Self.feeItemIDs.contains(itemID), let phone = StudentPhone.normalized(phone), Self.isOfficialChargePage(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.queryItems?.filter({ $0.name == "id" }).map(\.value) == [String(itemID)] else { return nil }
        self.phone = phone; self.itemID = itemID
    }

    static let stopScript = "window.__hfutHuiXinPhoneAutofill?.stop(); delete window.__hfutHuiXinPhoneAutofill;"

    var script: String {
        // Only normalised digits and a fixed numeric fee ID enter this script.
        Self.scriptMarker + "\n" + #"""
        (() => {
          if (window.top !== window) return;
          window.__hfutHuiXinPhoneAutofill?.stop();
          if (!['http:', 'https:'].includes(location.protocol) || location.hostname !== '121.251.19.62' ||
              (location.port && location.port !== (location.protocol === 'https:' ? '443' : '80')) ||
              !['/charge-app', '/charge-app/', '/charge-app/index.html'].includes(location.pathname)) return;
          const phone = '\#(phone)', itemID = '\#(itemID)';
          const edited = new WeakSet(), filled = new WeakSet();
          let writing = false, scheduled = false, stopped = false;
          function allowedRoute() {
            const query = new URLSearchParams(location.search);
            if (query.getAll('id').length !== 1 || query.get('id') !== itemID) return false;
            const route = location.hash.replace(/^#/, '');
            const path = route.split('?')[0];
            if (path && !['/', '/pays'].includes(path)) return false;
            const hashID = new URLSearchParams(route.split('?')[1] || '').getAll('id');
            return hashID.length === 0 || (hashID.length === 1 && hashID[0] === itemID);
          }
          function labels(input) {
            const row = input.closest('.weui-cell, .van-field, .el-form-item, .field-row');
            return [input.name, input.id, input.placeholder, input.getAttribute('aria-label'),
              input.autocomplete, ...Array.from(input.labels || []).map(x => x.textContent),
              row?.querySelector('.weui-label, .vux-label, .van-field__label, .el-form-item__label, label')?.textContent
            ].filter(Boolean).join(' ').toLowerCase();
          }
          function eligible(input) {
            return ['text', 'tel', 'number'].includes(input.type) && !input.disabled && !input.readOnly &&
              !edited.has(input) && !filled.has(input) && !input.value.trim() && input.getClientRects().length > 0 &&
              getComputedStyle(input).visibility !== 'hidden';
          }
          function fill(input) {
            const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
            if (!setter) return;
            writing = true; filled.add(input);
            try {
              setter.call(input, phone);
              input.dispatchEvent(new Event('input', {bubbles: true}));
              input.dispatchEvent(new Event('change', {bubbles: true}));
            } finally { writing = false; }
          }
          function apply() {
            scheduled = false;
            if (stopped || !allowedRoute()) return;
            const candidates = Array.from(document.querySelectorAll('input')).filter(eligible).map(input => ({input, text: labels(input)}))
              .filter(x => !/验证码|短信|密码|金额|余额|数量|税号|邮箱|password|amount|price|verification|otp|sms|email/.test(x.text));
            const phones = candidates.filter(x => /手机|联系电话|phone|mobile|\btel\b/.test(x.text));
            if (phones.length) { phones.forEach(x => fill(x.input)); return; }
            // Some deployments label the one phone-based account simply “账号”.
            const accounts = candidates.filter(x => /账号|账户|account/.test(x.text));
            if (accounts.length === 1) fill(accounts[0].input);
          }
          function schedule() {
            if (stopped || scheduled) return;
            scheduled = true; queueMicrotask(apply);
          }
          function onEdit(event) {
            if (!writing && event.target instanceof HTMLInputElement) edited.add(event.target);
          }
          const observer = new MutationObserver(schedule);
          observer.observe(document.documentElement, {subtree: true, childList: true, attributes: true,
            attributeFilter: ['placeholder', 'disabled', 'readonly', 'name', 'id', 'aria-label', 'class', 'style']});
          document.addEventListener('input', onEdit, true);
          document.addEventListener('change', onEdit, true);
          window.addEventListener('hashchange', schedule);
          window.__hfutHuiXinPhoneAutofill = {stop() {
            stopped = true; observer.disconnect();
            document.removeEventListener('input', onEdit, true);
            document.removeEventListener('change', onEdit, true);
            window.removeEventListener('hashchange', schedule);
          }};
          apply();
        })();
        """#
    }
}

/// Handles a phone arriving after the web page has loaded without reloading
/// the payment page or stacking multiple observers and user scripts.
@MainActor final class HuiXinPhoneAutofillController {
    private var current: HuiXinPhoneAutofill?
    func update(_ autofill: HuiXinPhoneAutofill?, on webView: WKWebView) {
        guard autofill != current else { return }
        current = autofill
        let scripts = webView.configuration.userContentController
        let unrelated = scripts.userScripts.filter { !$0.source.hasPrefix(HuiXinPhoneAutofill.scriptMarker) }
        scripts.removeAllUserScripts()
        unrelated.forEach(scripts.addUserScript)
        if let autofill {
            scripts.addUserScript(WKUserScript(source: autofill.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            webView.evaluateJavaScript(autofill.script, completionHandler: nil)
        } else { webView.evaluateJavaScript(HuiXinPhoneAutofill.stopScript, completionHandler: nil) }
    }
}
