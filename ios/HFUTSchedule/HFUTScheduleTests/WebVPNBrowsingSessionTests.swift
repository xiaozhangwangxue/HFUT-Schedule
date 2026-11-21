import XCTest
@testable import HFUTSchedule

final class WebVPNBrowsingSessionTests: XCTestCase {
    @MainActor
    func testOptInStartsDisabledAndIsNotInheritedByNewSession() {
        let first = WebVPNBrowsingSession()
        XCTAssertFalse(first.isEnabled)
        XCTAssertTrue(first.setEnabled(true, hasSession: true))
        XCTAssertTrue(first.isEnabled)
        XCTAssertFalse(WebVPNBrowsingSession().isEnabled)
    }

    @MainActor
    func testCannotEnableWithoutTicketAndMissingSessionClearsAnEnabledOptIn() {
        let session = WebVPNBrowsingSession()
        XCTAssertFalse(session.setEnabled(true, hasSession: false))
        XCTAssertFalse(session.isEnabled)
        XCTAssertTrue(session.setEnabled(true, hasSession: true))
        XCTAssertFalse(session.refreshSession(hasSession: false))
        XCTAssertFalse(session.isEnabled)
        XCTAssertTrue(session.refreshSession(hasSession: true))
        XCTAssertFalse(session.isEnabled, "A refreshed ticket must not silently enable the opt-in")
    }

    @MainActor
    func testUserMayDisableEvenAfterSessionHasExpired() {
        let session = WebVPNBrowsingSession()
        XCTAssertTrue(session.setEnabled(true, hasSession: true))
        XCTAssertTrue(session.setEnabled(false, hasSession: false))
        XCTAssertFalse(session.isEnabled)
    }

    @MainActor
    func testOpeningPageAfterSessionExpiresDisablesOptInAndKeepsOriginalURL() {
        let session = WebVPNBrowsingSession()
        let url = URL(string: "https://example.org/article")!
        session.setEnabled(true, hasSession: true)
        XCTAssertEqual(session.initialURL(url, hasSession: false), url)
        XCTAssertFalse(session.isEnabled)
    }

    func testGlobalRouteIncludesOrdinaryExternalHTTPAndHTTPSPages() {
        for value in ["https://example.org/library/path?a=1#part", "http://example.org/article"] {
            let input = URL(string: value)!
            let result = WebVPNBrowsingPolicy.initialURL(input, isEnabled: true, hasSession: true)
            XCTAssertEqual(result.host, "webvpn.hfut.edu.cn")
            XCTAssertNotEqual(result, input)
            XCTAssertTrue(result.path.hasPrefix("/\(input.scheme!)/"))
            XCTAssertEqual(result.query, input.query)
            XCTAssertEqual(result.fragment, input.fragment)
            XCTAssertTrue(result.path.hasSuffix(input.path))
        }
    }

    func testAlreadyVPNURLsRemainUnchangedIncludingLoginPage() {
        for value in [
            "https://webvpn.hfut.edu.cn/login?cas_login=true",
            "https://webvpn.hfut.edu.cn/http/77726476706e69737468656265737421faef469034247d1e760e9cb8d6502720ede479/eams5-student/"
        ] {
            let input = URL(string: value)!
            XCTAssertEqual(WebVPNBrowsingPolicy.initialURL(input, isEnabled: true, hasSession: true), input)
        }
    }

    func testExplicitAcademicOrCallbackFlowIsNeverGloballyRewritten() {
        let direct = URL(string: "https://jxglstu.hfut.edu.cn/eams5-student/for-std/course-table")!
        XCTAssertEqual(WebVPNBrowsingPolicy.initialURL(direct, isEnabled: true, hasSession: true, isProtectedFlow: true), direct)
    }

    func testCASServiceAndAcademicTicketExchangeStayIntactWithoutExplicitContext() {
        for value in [
            "https://cas.hfut.edu.cn/cas/login?service=http%3A%2F%2Fjxglstu.hfut.edu.cn%2Feams5-student%2Fneusoft-sso%2Flogin",
            "http://jxglstu.hfut.edu.cn/eams5-student/neusoft-sso/login?ticket=test-only-ticket",
            "https://sso.example.org/login?service=https%3A%2F%2Fexample.org%2Fcallback"
        ] {
            let input = URL(string: value)!
            XCTAssertEqual(WebVPNBrowsingPolicy.initialURL(input, isEnabled: true, hasSession: true), input)
        }
    }

    func testDefaultOffPreservesExistingCallerSelectedCampusRoute() {
        let direct = URL(string: "https://lib.hfut.edu.cn/")!
        let vpn = URL(string: "https://webvpn.hfut.edu.cn/user/portal")!
        XCTAssertEqual(WebVPNBrowsingPolicy.initialURL(direct, isEnabled: false, hasSession: true), direct)
        XCTAssertEqual(WebVPNBrowsingPolicy.initialURL(vpn, isEnabled: false, hasSession: true), vpn)
        XCTAssertEqual(WebVPNBrowsingPolicy.initialURL(direct, isEnabled: true, hasSession: false), direct)
    }

    @MainActor
    func testOpeningAnOrdinaryRestoredResultFollowsCurrentGlobalOptIn() {
        let session = WebVPNBrowsingSession()
        let restored = URL(string: "https://example.org/original/path")!
        XCTAssertEqual(session.initialURL(restored, hasSession: true), restored)
        session.setEnabled(true, hasSession: true)
        XCTAssertEqual(session.initialURL(restored, hasSession: true).host, "webvpn.hfut.edu.cn")
        session.setEnabled(false, hasSession: true)
        XCTAssertEqual(session.initialURL(restored, hasSession: true), restored)
    }

    func testNonHTTPLinksAreNeverWrapped() {
        for value in ["alipays://platformapi/startapp?appId=test", "about:blank", "file:///tmp/example.html"] {
            let input = URL(string: value)!
            XCTAssertEqual(WebVPNBrowsingPolicy.initialURL(input, isEnabled: true, hasSession: true), input)
        }
    }

    func testSessionAvailabilityUsesTicketNameExactPortalDomainAndExpirationOnly() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        typealias Ticket = WebVPNBrowsingPolicy.TicketMetadata
        let valid = Ticket(name: WebVPNBrowsingPolicy.ticketCookieName, domain: ".WEBVPN.HFUT.EDU.CN", expiresAt: now.addingTimeInterval(60))
        XCTAssertTrue(WebVPNBrowsingPolicy.hasValidTicket([valid], now: now))
        for invalid in [
            Ticket(name: "JSESSIONID", domain: "webvpn.hfut.edu.cn", expiresAt: now.addingTimeInterval(60)),
            Ticket(name: valid.name, domain: "webvpn.hfut.edu.cn.evil.invalid", expiresAt: now.addingTimeInterval(60)),
            Ticket(name: valid.name, domain: "sub.webvpn.hfut.edu.cn", expiresAt: now.addingTimeInterval(60)),
            Ticket(name: valid.name, domain: valid.domain, expiresAt: now),
            Ticket(name: valid.name, domain: valid.domain, expiresAt: now.addingTimeInterval(-1)),
            Ticket(name: valid.name, domain: valid.domain, expiresAt: nil)
        ] {
            XCTAssertFalse(WebVPNBrowsingPolicy.hasValidTicket([invalid], now: now))
        }
        XCTAssertFalse(WebVPNBrowsingPolicy.hasValidTicket([], now: now))
    }
}
