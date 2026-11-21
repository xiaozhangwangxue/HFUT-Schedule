import Combine
import Foundation

/// Matches upstream Starter.startWebUrlInner: this affects newly opened pages only.
/// The opt-in is deliberately process-local and resets when the app exits.
@MainActor
final class WebVPNBrowsingSession: ObservableObject {
    static let shared = WebVPNBrowsingSession()
    @Published private(set) var isEnabled = false

    @discardableResult
    func setEnabled(_ enabled: Bool, hasSession: Bool) -> Bool {
        isEnabled = enabled && hasSession
        return !enabled || hasSession
    }

    /// Call when displaying the tool or opening a page, so an expired session disables the opt-in.
    @discardableResult
    func refreshSession(hasSession: Bool) -> Bool {
        if !hasSession { isEnabled = false }
        return hasSession
    }

    static func hasSavedSession(now: Date = .now) -> Bool {
        CampusSessionStore.shared.hasSavedWebVPNTicket(now: now)
    }

    func initialURL(_ url: URL, isProtectedFlow: Bool = false) -> URL {
        initialURL(url, hasSession: Self.hasSavedSession(), isProtectedFlow: isProtectedFlow)
    }

    /// Explicit availability injection keeps policy tests away from the real cookie jar.
    func initialURL(_ url: URL, hasSession: Bool, isProtectedFlow: Bool = false) -> URL {
        refreshSession(hasSession: hasSession)
        return WebVPNBrowsingPolicy.initialURL(
            url, isEnabled: isEnabled, hasSession: hasSession, isProtectedFlow: isProtectedFlow
        )
    }
}

enum WebVPNBrowsingPolicy {
    static let ticketCookieName = "wengine_vpn_ticketwebvpn_hfut_edu_cn"
    static let portalHost = "webvpn.hfut.edu.cn"

    /// The availability check only needs metadata, never a cookie's credential value.
    struct TicketMetadata {
        let name: String
        let domain: String
        let expiresAt: Date?
    }

    static func hasValidTicket(_ tickets: [TicketMetadata], now: Date) -> Bool {
        tickets.contains { ticket in
            let domain = ticket.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return ticket.name == ticketCookieName && domain == portalHost
                && ticket.expiresAt.map { $0 > now } == true
        }
    }

    static func initialURL(
        _ url: URL, isEnabled: Bool, hasSession: Bool, isProtectedFlow: Bool = false
    ) -> URL {
        guard isEnabled, hasSession, !isProtectedFlow,
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(), host != portalHost,
              !isAuthenticationURL(url) else { return url }
        return WebVPNURLConverter.convert(url) ?? url
    }

    private static func isAuthenticationURL(_ url: URL) -> Bool {
        // Keep registered CAS service URLs and the ticket-exchange route intact.
        if url.host?.lowercased() == "cas.hfut.edu.cn" { return true }
        let path = url.path.lowercased()
        if path.contains("/neusoft-sso/") || path.hasSuffix("/neusoft-sso") { return true }
        let queryNames = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .map { $0.name.lowercased() } ?? []
        return queryNames.contains("service") && (path.contains("/login") || path.contains("/sso"))
    }
}
