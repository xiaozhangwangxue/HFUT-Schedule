import Foundation

enum FeatureCategory: String, CaseIterable, Identifiable {
    case study = "教学"
    case campus = "校园"
    case life = "生活"
    case information = "资讯"
    case tools = "工具"

    var id: String { rawValue }
}

enum NativeDestination: String, Hashable {
    case schedule
    case scanner
    case calendar
    case workRest
    case notifications
    case settings
    case grades
    case exams
    case personInfo
    case courseSearch
    case classrooms
    case failRate
    case campusCard
    case electricity
    case campusNetwork
    case bathing
    case laundry
    case secondClass
    case courseSummary
    case dormitory
    case program
    case library
    case campusLife
    case holidays
    case express
    case appointment
    case repair
    case campusMail
    case webNavigation
    case courseSelection
    case teachingSurvey
    case webVPN
    case todayCampus
    case huiXin
    case fee
    case teacherSearch
    case transferMajor
}

struct CampusFeature: Identifiable, Hashable {
    let id: Int
    let title: String
    let subtitle: String
    let systemImage: String
    let category: FeatureCategory
    let urlString: String?
    let nativeDestination: NativeDestination?

    var url: URL? {
        guard let urlString else { return nil }
        return URL(string: urlString)
    }
}

enum FeatureCatalog {
    static let all: [CampusFeature] = [
        .init(id: 1, title: "校园卡", subtitle: "余额、账单、充值与缴费", systemImage: "creditcard.fill", category: .life, urlString: "http://121.251.19.62/", nativeDestination: .campusCard),
        .init(id: 2, title: "扫码", subtitle: "二维码与校园登录", systemImage: "qrcode.viewfinder", category: .tools, urlString: nil, nativeDestination: .scanner),
        .init(id: 3, title: "宿舍电费", subtitle: "查询与缴费", systemImage: "bolt.fill", category: .life, urlString: "http://121.251.19.62/", nativeDestination: .electricity),
        .init(id: 4, title: "校园网", subtitle: "登录、余额与用量", systemImage: "wifi", category: .campus, urlString: "https://xywzz.hfut.edu.cn:8443/", nativeDestination: .campusNetwork),
        .init(id: 5, title: "校园邮箱", subtitle: "合工大邮箱", systemImage: "envelope.fill", category: .campus, urlString: "https://one.hfut.edu.cn/", nativeDestination: .campusMail),
        .init(id: 6, title: "考试安排", subtitle: "考试时间、地点与提醒", systemImage: "doc.text.fill", category: .study, urlString: "https://jwglapp.hfut.edu.cn/", nativeDestination: .exams),
        .init(id: 7, title: "成绩", subtitle: "成绩查询与分析", systemImage: "chart.bar.fill", category: .study, urlString: "https://jwglapp.hfut.edu.cn/", nativeDestination: .grades),
        .init(id: 8, title: "挂科率", subtitle: "课程通过情况", systemImage: "percent", category: .study, urlString: "https://community.hfut.edu.cn/", nativeDestination: .failRate),
        .init(id: 9, title: "课程汇总", subtitle: "学期课程与教材", systemImage: "books.vertical.fill", category: .study, urlString: "https://jxglstu.hfut.edu.cn/eams5-student/", nativeDestination: .courseSummary),
        .init(id: 10, title: "个人信息", subtitle: "学籍与校园身份", systemImage: "person.text.rectangle.fill", category: .campus, urlString: nil, nativeDestination: .personInfo),
        .init(id: 11, title: "网址导航", subtitle: "实验室与常用站点", systemImage: "folder.fill", category: .tools, urlString: "https://one.hfut.edu.cn/", nativeDestination: .webNavigation),
        .init(id: 12, title: "洗浴", subtitle: "洗浴服务与账单", systemImage: "shower.fill", category: .life, urlString: "https://bathing.hfut.edu.cn/", nativeDestination: .bathing),
        .init(id: 13, title: "选课", subtitle: "选课与确认", systemImage: "checklist", category: .study, urlString: "https://jxglstu.hfut.edu.cn/eams5-student/", nativeDestination: .courseSelection),
        .init(id: 14, title: "宿舍评分", subtitle: "寝室卫生评分", systemImage: "house.fill", category: .life, urlString: "https://community.hfut.edu.cn/", nativeDestination: .dormitory),
        .init(id: 15, title: "通知中心", subtitle: "校园通知统一收纳", systemImage: "bell.badge.fill", category: .information, urlString: nil, nativeDestination: .notifications),
        .init(id: 16, title: "教师评教", subtitle: "课程评价", systemImage: "text.bubble.fill", category: .study, urlString: "https://jxglstu.hfut.edu.cn/eams5-student/", nativeDestination: .teachingSurvey),
        .init(id: 17, title: "校园新闻", subtitle: "学校与教务新闻", systemImage: "newspaper.fill", category: .information, urlString: "https://news.hfut.edu.cn/", nativeDestination: nil),
        .init(id: 18, title: "培养方案", subtitle: "方案与完成情况", systemImage: "list.clipboard.fill", category: .study, urlString: "https://jxglstu.hfut.edu.cn/eams5-student/", nativeDestination: .program),
        .init(id: 19, title: "图书馆", subtitle: "借阅、检索与座位", systemImage: "books.vertical.circle.fill", category: .campus, urlString: "https://lib.hfut.edu.cn/", nativeDestination: .library),
        .init(id: 20, title: "校车", subtitle: "校车时刻与路线", systemImage: "bus.fill", category: .campus, urlString: "https://community.hfut.edu.cn/", nativeDestination: nil),
        .init(id: 21, title: "智慧后勤", subtitle: "合肥与宣城校区", systemImage: "wrench.and.screwdriver.fill", category: .campus, urlString: nil, nativeDestination: .repair),
        .init(id: 23, title: "饮水热水", subtitle: "热水与设备服务", systemImage: "drop.fill", category: .life, urlString: "alipays://platformapi/startapp?appId=20000067", nativeDestination: nil),
        .init(id: 24, title: "空教室", subtitle: "空闲教室查询", systemImage: "door.left.hand.open", category: .study, urlString: "https://jwglapp.hfut.edu.cn/", nativeDestination: .classrooms),
        .init(id: 25, title: "体育与体测", subtitle: "体测、校园跑与体育课", systemImage: "figure.run", category: .campus, urlString: "https://bdlp.hfut.edu.cn/", nativeDestination: nil),
        .init(id: 26, title: "作息", subtitle: "校历、作息与学期安排", systemImage: "calendar", category: .study, urlString: "https://www.hfut.edu.cn/", nativeDestination: .workRest),
        .init(id: 27, title: "学信网", subtitle: "学籍与学历档案", systemImage: "graduationcap.fill", category: .study, urlString: "https://my.chsi.com.cn/archive/wap/gdjy/index.action", nativeDestination: nil),
        .init(id: 28, title: "校园生活", subtitle: "地图、天气与学期报告", systemImage: "leaf.fill", category: .life, urlString: "https://www.hfut.edu.cn/", nativeDestination: .campusLife),
        .init(id: 29, title: "转专业", subtitle: "申请与进度", systemImage: "arrow.triangle.swap", category: .study, urlString: "https://jxglstu.hfut.edu.cn/eams5-student/", nativeDestination: .transferMajor),
        .init(id: 30, title: "全校课程", subtitle: "课程检索", systemImage: "magnifyingglass", category: .study, urlString: "https://jwglapp.hfut.edu.cn/", nativeDestination: .courseSearch),
        .init(id: 31, title: "教师查询", subtitle: "教师与研究方向", systemImage: "person.crop.square.filled.and.at.rectangle", category: .study, urlString: "http://121.251.19.138/", nativeDestination: .teacherSearch),
        .init(id: 32, title: "费用中心", subtitle: "学费与欠费查询", systemImage: "yensign.circle.fill", category: .campus, urlString: "http://pay.hfut.edu.cn/payment/mobileOnlinePay", nativeDestination: .fee),
        .init(id: 34, title: "校友服务", subtitle: "校友平台", systemImage: "person.3.fill", category: .campus, urlString: "https://xypt.hfut.edu.cn/", nativeDestination: nil),
        .init(id: 35, title: "今日校园", subtitle: "请假、奖助与学生事务", systemImage: "person.badge.clock.fill", category: .campus, urlString: "https://stu.hfut.edu.cn/", nativeDestination: .todayCampus),
        .init(id: 36, title: "创新创业", subtitle: "IETP 项目管理", systemImage: "lightbulb.fill", category: .study, urlString: "http://dcxt.hfut.edu.cn/", nativeDestination: nil),
        .init(id: 37, title: "就业服务", subtitle: "招聘、实习与双选", systemImage: "briefcase.fill", category: .campus, urlString: "https://gdjy.hfut.edu.cn/", nativeDestination: nil),
        .init(id: 38, title: "节假日", subtitle: "放假与调休", systemImage: "calendar.badge.clock", category: .information, urlString: "https://www.gov.cn/", nativeDestination: .holidays),
        .init(id: 39, title: "信息共建", subtitle: "共享日程与校园资料", systemImage: "icloud.fill", category: .tools, urlString: "https://community.hfut.edu.cn/", nativeDestination: nil),
        .init(id: 40, title: "洗衣", subtitle: "洗衣、洗鞋与烘干", systemImage: "washer.fill", category: .life, urlString: "https://yshz-user.haier-ioc.com/", nativeDestination: .laundry),
        .init(id: 41, title: "招生信息", subtitle: "计划与历年分数", systemImage: "person.2.crop.square.stack.fill", category: .information, urlString: "https://bkzs.hfut.edu.cn/", nativeDestination: nil),
        .init(id: 42, title: "WebVPN", subtitle: "校外访问校内资源", systemImage: "lock.shield.fill", category: .tools, urlString: "https://webvpn.hfut.edu.cn/", nativeDestination: .webVPN),
        .init(id: 43, title: "办事大厅", subtitle: "网上办事与流程", systemImage: "building.columns.fill", category: .campus, urlString: "https://ehall.hfut.edu.cn/", nativeDestination: nil),
        .init(id: 44, title: "慧新易校", subtitle: "校园卡、电费与生活缴费平台", systemImage: "building.2.fill", category: .life, urlString: "http://121.251.19.62/", nativeDestination: .huiXin),
        .init(id: 45, title: "第二课堂", subtitle: "活动与学分", systemImage: "person.3.sequence.fill", category: .study, urlString: "https://dekt.hfut.edu.cn/", nativeDestination: .secondClass),
        .init(id: 46, title: "场地预约", subtitle: "原版功能开发中", systemImage: "table.furniture", category: .campus, urlString: nil, nativeDestination: .appointment),
        .init(id: 47, title: "AI 助手", subtitle: "校园问答与学习辅助", systemImage: "sparkles", category: .tools, urlString: nil, nativeDestination: nil),
        .init(id: 48, title: "事务跟踪", subtitle: "反馈、进度与开发动态", systemImage: "point.3.connected.trianglepath.dotted", category: .tools, urlString: "https://github.com/Chiu-xaH/HFUT-Schedule/issues", nativeDestination: nil),
        .init(id: 49, title: "快递", subtitle: "包裹与取件码", systemImage: "shippingbox.fill", category: .life, urlString: "https://m.pinduoduo.net/mdkd/package?tab=ID_CODE", nativeDestination: .express),
        .init(id: 50, title: "意见反馈", subtitle: "建议与问题反馈", systemImage: "bubble.left.and.exclamationmark.bubble.right.fill", category: .information, urlString: "https://github.com/Chiu-xaH/HFUT-Schedule/issues/new", nativeDestination: nil)
    ]
}
