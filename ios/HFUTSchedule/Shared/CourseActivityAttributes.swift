import ActivityKit
import Foundation

struct CourseActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let title: String
        let location: String
        let start: Date
        let end: Date
        let kind: String
    }
    let occurrenceID: String
    let route: String
}
