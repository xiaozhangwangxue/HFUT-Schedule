import XCTest
import SwiftUI
import UIKit
@testable import HFUTSchedule

final class ExamPresentationTests: XCTestCase {
    @MainActor
    func testWeekendExamAppearsInRenderedTimetableWithWeekendsInitiallyHidden() async throws {
        let suite = "HFUTExamPresentation.\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suite)!
        let keys = [AppSettingsKey.autoTermStart, AppSettingsKey.manualTermStart, "scheduleShowsWeekend"]
        let previous = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            isolated.removePersistentDomain(forName: suite)
            for (key, value) in zip(keys, previous) {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        let calendar = ScheduleCalendar.calendar
        let monday = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: Date())?.start)
        let sunday = try XCTUnwrap(calendar.date(byAdding: .day, value: 6, to: monday))
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let records = AcademicRecordsStore(defaults: isolated)
        records.replaceExams(with: [.init(name: "周末考试验证", dateTime: formatter.string(from: sunday) + " 09:00~11:00", place: "测试考场 A101")])
        UserDefaults.standard.set(false, forKey: AppSettingsKey.autoTermStart)
        UserDefaults.standard.set(monday.timeIntervalSince1970, forKey: AppSettingsKey.manualTermStart)
        UserDefaults.standard.set(false, forKey: "scheduleShowsWeekend")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScheduleStore(fileURL: directory.appendingPathComponent("courses.json"), syncWidgets: false)
        let events = CustomEventStore(fileURL: directory.appendingPathComponent("events.json"))
        let root = NavigationStack { ScheduleView() }
            .environmentObject(store).environmentObject(records).environmentObject(events)
            .environmentObject(CourseNotificationManager())
            .preferredColorScheme(.light)
        let controller = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 932))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(600))
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "scheduleShowsWeekend"), "The actual ScheduleView should reveal weekend exams on appearance.")
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("HFUT-timetable-exam-QA.png")
        try XCTUnwrap(image.pngData()).write(to: path)
        print("HFUT_QA_SCREENSHOT=\(path.path)")
        let attachment = XCTAttachment(image: image)
        attachment.name = "Weekend exam in timetable"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
