import SwiftUI

struct UpcomingExamDetailView: View {
    let item: ResolvedAcademicExam

    var body: some View {
        List {
            Section("考试安排") {
                LabeledContent("课程", value: item.exam.name)
                LabeledContent("时间", value: item.exam.dateTime)
                LabeledContent("地点", value: item.location)
            }
            Section {
                NavigationLink("查看全部考试与同步") { AcademicRecordsView(kind: .exams) }
            }
        }
        .navigationTitle("考试详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TimetableExamDestination: View {
    let courseID: UUID
    @EnvironmentObject private var recordsStore: AcademicRecordsStore

    var body: some View {
        if let exam = UpcomingExamResolver.exam(forCourseID: courseID, in: recordsStore.exams, calendar: ScheduleCalendar.calendar) {
            UpcomingExamDetailView(item: exam)
        } else {
            ContentUnavailableView("考试安排已更新", systemImage: "calendar", description: Text("请返回课表或重新同步考试安排。"))
        }
    }
}
