import XCTest
@testable import HFUTSchedule

final class AcademicUpgradeTests: XCTestCase {
    // Sanitized fixtures reproduce the school's card/form structure. IDs and
    // account values here are synthetic and contain no student information.
    func testMultipleStudentRecordsPreferMainProgramRegardlessOfCardOrder() {
        let html = """
        <main>
          <div class="student-panel-block"><dl><dt>培养类型</dt><dd>辅修</dd></dl><button value="101">进入</button></div>
          <div class="panel student-panel-block selected">
            <div><dl><dt><span>培养类型</span></dt>\n<dd><strong>主修</strong></dd></dl></div>
            <button class="btn" value=" 202 ">进入</button>
          </div>
        </main>
        """
        XCTAssertEqual(AcademicHTMLParser.studentID(fromLandingHTML: html), 202)
    }

    func testOlderStudentCardsFallBackToFirstCard() {
        let html = """
        <button value="999">页面操作</button>
        <section class='student-panel-block'><button value=303>进入</button></section>
        <section class='student-panel-block'><button value='404'>进入</button></section>
        """
        XCTAssertEqual(AcademicHTMLParser.studentID(fromLandingHTML: html), 303)
    }

    func testStudentSelectionRequiresMatchingLabelAndItsNextElement() {
        let html = """
        <div class="student-panel-block"><dl><dt>培养类型</dt><dd>辅修</dd></dl><button value="101">进入</button></div>
        <div class="student-panel-block"><dl><dt>其他类型</dt><dd>主修</dd><dt>培养类型</dt><dd>辅修</dd></dl><button value="202">进入</button></div>
        """
        XCTAssertEqual(AcademicHTMLParser.studentID(fromLandingHTML: html), 101)
    }

    func testInvalidMainProgramIDDoesNotSelectAnotherStudentOrScriptURL() {
        for invalid in ["", "202x", "-202", "2.02", "２０２", "999999999999999999999999999999"] {
            let html = """
            <script>const legacy = '/for-std/course-table/info/999';</script>
            <div class="student-panel-block"><button value="101">进入</button></div>
            <div class="student-panel-block"><dt>培养类型</dt><dd>主修</dd><button value="\(invalid)">进入</button></div>
            """
            XCTAssertNil(AcademicHTMLParser.studentID(fromLandingHTML: html), "Invalid selected ID must fail")
        }
    }

    func testMainProgramWithoutButtonKeepsUpstreamFirstCardFallback() {
        let html = """
        <div class="student-panel-block"><button value="101">进入</button></div>
        <div class="student-panel-block"><dt>培养类型</dt><dd>主修</dd></div>
        """
        XCTAssertEqual(AcademicHTMLParser.studentID(fromLandingHTML: html), 101)
    }

    func testLegacySingleStudentLandingStillParsesAndLoginPageDoesNot() {
        XCTAssertEqual(AcademicHTMLParser.studentID(fromLandingHTML: "<a href='/eams5-student/for-std/course-table/info/505'>课表</a>"), 505)
        XCTAssertNil(AcademicHTMLParser.studentID(fromLandingHTML: "<form action='/cas/login'><input name='username'></form>"))
    }

    func testAccountPasswordUsesOnlySchoolSaveFormAndDecodesAttributes() {
        let html = """
        <form id="other"><input id="plainPassword" value="unrelated-fixture"></form>
        <input id="plainPassword" value="outside-fixture">
        <form class="account" id='save-form'>
          <div><input value='fixture&amp;value&#x27;&#33;' type="password" id="plainPassword"></div>
        </form>
        """
        XCTAssertEqual(AcademicHTMLParser.accountPassword(from: html), "fixture&value'!")
    }

    func testAccountPasswordRejectsMissingEmptyMaskedAndControlValues() {
        XCTAssertNil(AcademicHTMLParser.accountPassword(from: "<input id='plainPassword' value='outside-fixture'>"))
        for invalid in ["", "   ", "********", "••••••", "fixture&#10;value"] {
            let html = "<form id='save-form'><input id='plainPassword' value='\(invalid)'></form>"
            XCTAssertNil(AcademicHTMLParser.accountPassword(from: html))
        }
        XCTAssertNil(AcademicHTMLParser.accountPassword(from: "<form id='save-form'><input id='plainPassword'></form>"))
    }

    func testAccountPasswordDoesNotReadCommentOrScriptMarkup() {
        let html = """
        <!-- <form id='save-form'><input id='plainPassword' value='comment-fixture'></form> -->
        <script>const template = "<form id='save-form'><input id='plainPassword' value='script-fixture'></form>";</script>
        <form id="save-form"><input id="plainPassword" value="actual-fixture"></form>
        """
        XCTAssertEqual(AcademicHTMLParser.accountPassword(from: html), "actual-fixture")
    }

    func testAcademicAccountRouteSupportsDirectAndWebVPNModes() {
        XCTAssertEqual(AcademicPortal.url("my/account", mode: .direct).absoluteString, "https://jxglstu.hfut.edu.cn/eams5-student/my/account")
        let proxied = AcademicPortal.url("my/account", mode: .webVPN)
        XCTAssertEqual(proxied.host, "webvpn.hfut.edu.cn")
        XCTAssertTrue(proxied.path.hasSuffix("/eams5-student/my/account"))
    }
}
