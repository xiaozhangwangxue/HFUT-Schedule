import XCTest
@testable import HFUTSchedule

final class CampusNewsAndShortcutsTests: XCTestCase {
    func testAllUpstreamNewsCategoriesAndRealPaginationURLRules() {
        XCTAssertEqual(CampusNewsCategory.hefeiAcademic.count, 7)
        XCTAssertEqual(CampusNewsCategory.xuanchengAcademic.count, 19)
        let category = CampusNewsCategory.hefeiAcademic[0]
        XCTAssertEqual(CampusNewsClient.pageURL(category: category, page: 1).path, "/tzgg/jxbzl.htm")
        XCTAssertEqual(CampusNewsClient.pageURL(category: category, page: 2, totalPages: 122).path, "/tzgg/jxbzl/121.htm")
        XCTAssertEqual(CampusNewsClient.pageURL(category: category, page: 122, totalPages: 122).path, "/tzgg/jxbzl/1.htm")
        XCTAssertEqual(CampusNewsClient.pageURL(category: .xuanchengNotices, page: 1).path, "/1955/list.htm")
        XCTAssertEqual(CampusNewsClient.pageURL(category: .xuanchengNotices, page: 2).path, "/1955/list2.htm")
        XCTAssertEqual(CampusNewsClient.pageURL(category: CampusNewsCategory.xuanchengAcademic[0], page: 2).path, "/1177/list2.htm")
    }
    func testAcademicParserUsesNewsStructureAndIgnoresMenusAndScriptTemplates() throws {
        let category = CampusNewsCategory.hefeiAcademic[0]
        let page = CampusNewsClient.parse("""
        <html><a href="/navigation">菜单</a>
        <script>const template = '<a class="l3-news--item" href="/fake"><div class="l3-news--title">脚本模板</div></a>';</script>
        <a class="l3-news--item" href="../info/1249/100.htm"><div class="l3-news--day">24</div><div class="l3-news--month">2030-01</div><div class="l3-news--title">离线测试通知</div></a>
        <a class="l3-news--item" href="javascript:alert(1)"><div class="l3-news--title">非法链接</div></a>
        <span class="p_no"><a href="jxbzl/1.htm">122</a></span></html>
        """, category: category, pageURL: CampusNewsClient.pageURL(category: category, page: 1))
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items.first?.title, "离线测试通知")
        XCTAssertEqual(page.items.first?.date, "2030-01-24")
        XCTAssertEqual(page.items.first?.url.path, "/info/1249/100.htm")
        XCTAssertEqual(page.totalPages, 122)
    }
    func testXuanchengTableListAndOfficialDepartmentDirectory() {
        let category = CampusNewsCategory.xuanchengAcademic[0]
        let academic = CampusNewsClient.parse("""
        <table><tr><td align="left"><a target="_blank" title="测试考试通知" href="/item/page.htm">缩略标题</a></td><td align="right">2030-01-24</td></tr></table><em class="all_pages">10</em>
        """, category: category, pageURL: CampusNewsClient.pageURL(category: category, page: 1))
        XCTAssertEqual(academic.items.first?.title, "测试考试通知")
        XCTAssertEqual(academic.items.first?.url.host, "xcjwb.hfut.edu.cn")
        XCTAssertEqual(academic.totalPages, 10)
        let campus = CampusNewsClient.parse("""
        <ul class="news_list list2"><li><span class="news_title"><a href="/notice/page.htm" title="测试校区通知">标题</a></span><span class="news_meta">2030-01-24</span></li></ul><em class="all_pages">73</em>
        """, category: .xuanchengNotices, pageURL: CampusNewsClient.pageURL(category: .xuanchengNotices, page: 1))
        XCTAssertEqual(campus.items.count, 1); XCTAssertEqual(campus.totalPages, 73)
        let departments = CampusNewsClient.parseDepartments("""
        <ul class="sz-list"><li><a href="https://college.hfut.edu.cn/"><font><img src="../images/icon.png"></font><div class="sz-list-tt">测试学院</div></a></li>
        <li><a href="https://outside.invalid/"><div class="sz-list-tt">不属于学校</div></a></li></ul>
        """)
        XCTAssertEqual(departments.map(\.name), ["测试学院"])
        XCTAssertEqual(departments.first?.iconURL?.absoluteString, "https://www.hfut.edu.cn/images/icon.png")
    }
    func testThirdPartyCollectionCoversEveryUpstreamCardWithoutInventedSchemes() {
        let all = ThirdPartyShortcutCatalog.all
        XCTAssertEqual(all.count, 12)
        XCTAssertEqual(Set(all.map(\.id)).count, 12)
        XCTAssertEqual(Set(all.map(\.id)), Set(["survive","anhui","pdd","taobao","alipay-card","alipay-water","running","campus","rain","chaoxing","mooc","wechat"]))
        XCTAssertTrue(all.allSatisfy { ["https", "http", "alipays"].contains($0.url.scheme ?? "") })
        let appLinks = all.filter { $0.url.scheme == "alipays" }
        XCTAssertEqual(appLinks.count, 2)
        XCTAssertTrue(appLinks.allSatisfy { $0.fallback?.scheme == "https" })
        XCTAssertEqual(all.first { $0.id == "running" }?.url.host, "apps.apple.com")
    }
}
