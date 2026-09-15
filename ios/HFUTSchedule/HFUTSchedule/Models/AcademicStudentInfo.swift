import Foundation

struct AcademicStudentInfo: Codable, Equatable {
    let studentID: String
    let name: String
    let fields: [String: String]

    var major: String { fields["专业"] ?? fields["专业名称"] ?? "" }
    var department: String { fields["院系"] ?? fields["院系名称"] ?? fields["学院"] ?? "" }
    var className: String { fields["班级"] ?? fields["行政班"] ?? "" }
    var campus: String { fields["校区"] ?? "" }
}
