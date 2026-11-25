import Foundation
import XCTest
@testable import HFUTSchedule

final class CampusServiceAuthenticationTests: XCTestCase {
    func testSecondClassUsesItsScopedCookieAfterFinalRedirect() throws {
        let jar = URLSessionConfiguration.ephemeral.httpCookieStorage!
        let cookie = try XCTUnwrap(HTTPCookie(properties:[.name:"SESSION",.value:"synthetic-session",.domain:"dekt.hfut.edu.cn",.path:"/scReports"]))
        jar.setCookie(cookie)
        XCTAssertTrue((jar.cookies(for:URL(string:"https://dekt.hfut.edu.cn/")!) ?? []).isEmpty)
        let url = URL(string:"https://dekt.hfut.edu.cn/scReports/uccp_index")!
        XCTAssertNil(CampusServiceAuthentication.secondClassSession(url:url,status:302,location:"/scReports/uccp_index",setCookie:"SESSION=anonymous",storage:jar))
        XCTAssertEqual(CampusServiceAuthentication.secondClassSession(url:url,status:200,location:nil,setCookie:"",storage:jar),"SESSION=synthetic-session")
        XCTAssertNil(CampusServiceAuthentication.secondClassSession(url:URL(string:"https://cas.hfut.edu.cn/cas/login")!,status:200,location:nil,setCookie:"SESSION=wrong-origin",storage:jar))
    }
    func testOnePortalCodeParsingUsesOfficialCallbackAndAnyValidCodePrefix() {
        XCTAssertNotNil(CampusServiceAuthentication.onePortalCallback("https://one.hfut.edu.cn/home/index?code=OC-fixture"))
        XCTAssertNotNil(CampusServiceAuthentication.onePortalCallback("https://one.hfut.edu.cn/home/index?code=new-prefix-fixture"))
        XCTAssertNil(CampusServiceAuthentication.onePortalCallback("https://untrusted.example/?code=OC-fixture"))
        XCTAssertNil(CampusServiceAuthentication.onePortalCallback("https://one.hfut.edu.cn/home/index?code="))
        XCTAssertNil(CampusServiceAuthentication.onePortalCallback("<html>code=OC-fixture</html>"))
    }
    func testWebVPNGrantIsScopedToItsCASOriginAndNeverUsesAnonymousSession() throws {
        let value = try XCTUnwrap(CASCookieParser.grantingCookie(fromVirtualData:Data("SESSION=anonymous; TGC=synthetic-tgc; LOGIN_FLAVORING=0123456789abcdef".utf8)))
        XCTAssertEqual(value.name,"TGC");XCTAssertEqual(value.value,"synthetic-tgc")
        XCTAssertEqual(value.domain,"cas.hfut.edu.cn");XCTAssertEqual(value.path,"/cas/");XCTAssertTrue(value.isSecure)
        XCTAssertNil(CASCookieParser.grantingCookie(fromVirtualData:Data("SESSION=anonymous; NOTTGC=wrong".utf8)))
        XCTAssertNil(CASCookieParser.grantingCookie(fromVirtualData:Data("TGC=".utf8)))
    }
}
