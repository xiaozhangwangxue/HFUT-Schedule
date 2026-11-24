import XCTest
@testable import HFUTSchedule

@MainActor
final class CoreParityTests: XCTestCase {
    func testCommunityCourseUsesPlatformPeriodsWeeksAndStableIdentity() throws {
        let data = Data(#"{"result":{"start":"2026-11-16","startTime":["8:00","8:55"],"endTime":["8:45","9:40"],"courseBasicInfoDTOList":[{"courseName":"测试课程A","courseId":"course-A","credit":2,"className":"测试班","courseDetailDTOList":[{"section":1,"sectionCount":2,"teacher":"测试教师","place":"测试教室","weekCount":[1,3],"week":1}]}]}}"#.utf8)
        let rows = try ScheduleSourceParser.community(data)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].startTime, "08:00")
        XCTAssertEqual(rows[0].endTime, "09:40")
        XCTAssertEqual(rows[0].dates, ["2026-11-16", "2026-11-30"])
        XCTAssertEqual(rows[0].weekIndices, [1,3])
        XCTAssertEqual(rows[0].id, try ScheduleSourceParser.community(data)[0].id)
        XCTAssertEqual(rows[0].source, "community")
    }

    func testUniAppGroupsRepeatedDatesWithoutDuplicatingTheLesson() throws {
        let data = Data(#"{"data":[{"id":12,"course":{"nameZh":"测试课程B","credits":3},"schedules":[{"weekday":2,"startTime":1400,"endTime":1540,"date":"2026-11-17","weekIndex":1,"room":{"nameZh":"教室B"},"teacherName":"教师B"},{"weekday":2,"startTime":1400,"endTime":1540,"date":"2026-11-24","weekIndex":2,"room":{"nameZh":"教室B"},"teacherName":"教师B"}]}]}"#.utf8)
        let rows = try ScheduleSourceParser.uniApp(data)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].dates, ["2026-11-17", "2026-11-24"])
        XCTAssertEqual(rows[0].weekIndices, [1,2])
        XCTAssertEqual(rows[0].startTime, "14:00")
    }

    func testSwitchingSourcesPreservesManualAndOfflineCourses() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScheduleStore(fileURL: directory.appendingPathComponent("courses.json"), syncWidgets: false)
        let manual = Course(name: "本地测试", teacher: "", location: "", weekday: 1, startTime: "08:00", endTime: "09:00", colorIndex: 0)
        var academic = manual; academic.id = UUID(); academic.source = "academic"
        XCTAssertTrue(store.replace(with: [manual, academic]))
        let coordinator = ScheduleSourceCoordinator(cacheURL: directory.appendingPathComponent("sources.json"))
        let previous = UserDefaults.standard.object(forKey: AppSettingsKey.defaultCourseSource)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: AppSettingsKey.defaultCourseSource) }
            else { UserDefaults.standard.removeObject(forKey: AppSettingsKey.defaultCourseSource) }
        }
        coordinator.activate(.community, store: store)
        XCTAssertEqual(store.courses.map(\.id), [manual.id])
        coordinator.activate(.academic, store: store)
        XCTAssertEqual(Set(store.courses.map(\.id)), Set([manual.id, academic.id]))
    }

    func testFocusSwitchesOnlyAtFinalLessonEnd() throws {
        let calendar = FocusPlanResolver.calendar
        let day = try XCTUnwrap(ScheduleCalendar.isoDate("2026-11-16"))
        let morning = Course(name: "测试A", teacher: "", location: "", weekday: 1, startTime: "08:00", endTime: "09:40", colorIndex: 0)
        var afternoon = morning; afternoon.endTime = "15:40"
        func time(_ hour: Int, _ minute: Int) -> Date { calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)! }
        XCTAssertFalse(FocusPlanResolver.showsTomorrow(today: [morning,afternoon], now: time(15,39)))
        XCTAssertTrue(FocusPlanResolver.showsTomorrow(today: [morning,afternoon], now: time(15,40)))
        XCTAssertTrue(FocusPlanResolver.showsTomorrow(today: [], now: time(0,0)))
    }

    func testPublicScheduleRejectsPrivateAndInvalidDates() {
        let valid: [String: Any] = ["title":"测试安排", "showPublic":true, "startTime":[2026,11,16,8,0], "endTime":[2026,11,16,9,0]]
        var hidden = valid; hidden["showPublic"] = false
        var invalid = valid; invalid["startTime"] = [2026,2,31,8,0]
        let values = PublicCampusEvent.decode([valid,hidden,invalid], deadline: false)
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values[0].title, "测试安排")
        XCTAssertEqual(LearningPlatform.url(for: "U校园AI版")?.host, "ucloud.unipus.cn")
        XCTAssertNil(LearningPlatform.url(for: "普通备注"))
    }

    func testFloorRoomCoordinatesAndRelativeImages() throws {
        let xml = Data("<annotation><object><name>101</name><bndbox><xmin>10</xmin><ymin>20</ymin><xmax>30</xmax><ymax>50</ymax></bndbox></object><object><name>invalid</name><bndbox><xmin>20</xmin><xmax>1</xmax></bndbox></object></annotation>".utf8)
        let rooms = BuildingRoomXMLParser.parse(xml)
        XCTAssertEqual(rooms.count, 1)
        XCTAssertEqual(rooms[0].name, "101")
        XCTAssertEqual(rooms[0].rectangle, CGRect(x: 10, y: 20, width: 20, height: 30))
        XCTAssertEqual(BuildingFloorMapView.resourceURL("XC002_1.jpg")?.path, "/Chiu-xaH/HFUT-Schedule/dev/src/source/building/detail/XC002_1.jpg")
    }

    func testBorrowKeywordsPreserveFrequencyAndRemoveOriginalPinyinPrefix() {
        let rows = LibraryKeywordAnalysis.frequencies(["ji suan/计算机/程序设计", "计算机/程序设计"])
        XCTAssertEqual(rows.first?.count, 2)
        XCTAssertEqual(Set(rows.map(\.word)), Set(["计算机", "程序设计"]))
    }

    func testPublicWeatherParsesLocalWarningsAndRejectsUnknownMarkup() throws {
        let html = """
        <div class="current-live"><div><p>14°</p><p>多云</p></div></div>
        <div class="current-basic d-flex"><div><p>2级</p><p>北风</p></div><div><p>60%</p><p>相对湿度</p></div><div><p>12°</p><p>体感温度</p></div></div>
        """
        let observation = try QWeatherPublicPage.observation(html)
        XCTAssertEqual(observation.temperature, 14)
        XCTAssertEqual(observation.humidity, 60)
        XCTAssertEqual(observation.apparent, 12)
        XCTAssertEqual(try QWeatherPublicPage.warnings("<div class='c-city-warning-no-data'><h3>暂无预警</h3></div>"), [])
        let warning = "<div class='c-city-warning-events'><div><h3>测试地区预警</h3></div><p class='warning-events__txt'>测试内容</p></div><div class='c-city-warning-around'><h3>附近预警</h3></div>"
        XCTAssertEqual(try QWeatherPublicPage.warnings(warning).count, 1)
        XCTAssertThrowsError(try QWeatherPublicPage.warnings("<html>系统暂不可用</html>"))
    }
    func testCommunityRepeatedPeriodsMergeDatesWithoutDuplicateIDs() throws {
        let data = Data(#"{"result":{"start":"2026-11-16","startTime":["8:00"],"endTime":["8:45"],"courseBasicInfoDTOList":[{"courseName":"测试课程","courseId":"A","courseDetailDTOList":[{"section":1,"sectionCount":1,"weekCount":[1],"week":1},{"section":1,"sectionCount":1,"weekCount":[3],"week":1}]}]}}"#.utf8)
        let rows = try ScheduleSourceParser.community(data)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.weekIndices, [1, 3])
        XCTAssertEqual(rows.first?.dates, ["2026-11-16", "2026-11-30"])
    }

    func testReportExportsRealPNGAndSurfacesWriteFailure() throws {
        let date = try XCTUnwrap(ScheduleCalendar.isoDate("2026-11-16"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let section = CampusReportSection(id: "test", title: "课程与考试", metrics: [
            .init(name: "课堂时长", value: "12.5 小时"), .init(name: "考试", value: "2 场")],
            points: [.init(label: "测试教室 A", value: 3), .init(label: "测试教室 B", value: 2)], note: "合成测试数据，不包含真实课表。")
        let urls = try CampusReportExporter.export(sections: [section], start: date, end: date, directory: directory)
        XCTAssertEqual(urls.count, 1)
        let data = try Data(contentsOf: XCTUnwrap(urls.first))
        XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "学期报告-合成数据"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertThrowsError(try CampusReportExporter.export(sections: [section], start: date, end: date,
            directory: directory.appendingPathComponent("absent-directory")))
    }

}
