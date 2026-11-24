import Foundation

struct ThirdPartyShortcut: Identifiable, Hashable {
    enum Opening: String { case website = "官方网页", appStore = "App Store", alipay = "打开支付宝", guide = "新生指南" }
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let opening: Opening
    let url: URL
    let fallback: URL?
    let copyText: String?
}

enum ThirdPartyShortcutCatalog {
    /// All 12 cards from upstream StarterScreen, including its two distinct Alipay services.
    static let all: [ThirdPartyShortcut] = [
        .init(id: "survive", title: "活在肥宣", detail: "转载的非官方新生指南", symbol: "book.closed", opening: .guide,
              url: URL(string: "https://survive-hfut.cc/intro")!, fallback: nil, copyText: nil),
        .init(id: "anhui", title: "皖事通", detail: "医保、政务及宣城实时公交等服务", symbol: "building.columns", opening: .appStore,
              url: URL(string: "https://apps.apple.com/cn/app/id1302204874")!, fallback: URL(string: "https://www.ahzwfw.gov.cn/"), copyText: nil),
        .init(id: "pdd", title: "拼多多身份码", detail: "校区快递站取件身份码", symbol: "shippingbox", opening: .website,
              url: URL(string: "https://m.pinduoduo.net/mdkd/package?tab=ID_CODE")!, fallback: nil, copyText: nil),
        .init(id: "taobao", title: "淘宝身份码", detail: "合肥校区快递站取件身份码", symbol: "shippingbox.fill", opening: .website,
              url: URL(string: "https://pages-fast.m.taobao.com/wow/z/uniapp/1011717/last-mile-fe/end-collect-platform/identity-code")!, fallback: nil, copyText: nil),
        .init(id: "alipay-card", title: "支付宝校园卡", detail: "校园卡缴费", symbol: "creditcard", opening: .alipay,
              url: URL(string: "alipays://platformapi/startapp?appId=20000067&url=https://ur.alipay.com/_4kQhV32216tp7bzlDc3E1k")!,
              fallback: URL(string: "https://ur.alipay.com/_4kQhV32216tp7bzlDc3E1k"), copyText: nil),
        .init(id: "alipay-water", title: "支付宝海乐生活热水机", detail: "打开原版配置的热水服务", symbol: "drop.fill", opening: .alipay,
              url: URL(string: "alipays://platformapi/startapp?appId=20000067&url=https://ur.alipay.com/_3B2YzKjbV75xL9a2oapcNz")!,
              fallback: URL(string: "https://ur.alipay.com/_3B2YzKjbV75xL9a2oapcNz"), copyText: nil),
        .init(id: "running", title: "云运动", detail: "大一、大二校园跑", symbol: "figure.run", opening: .appStore,
              url: URL(string: "https://apps.apple.com/cn/app/id1563408569")!, fallback: nil, copyText: nil),
        .init(id: "campus", title: "今日校园", detail: "离返校、心理测试等校园应用", symbol: "person.2", opening: .appStore,
              url: URL(string: "https://apps.apple.com/cn/app/id1207509945")!, fallback: URL(string: "https://stu.hfut.edu.cn/"), copyText: nil),
        .init(id: "rain", title: "雨课堂", detail: "考勤、作业等课堂功能", symbol: "cloud.rain", opening: .website,
              url: URL(string: "https://www.yuketang.cn/")!, fallback: nil, copyText: nil),
        .init(id: "chaoxing", title: "学习通", detail: "考勤、作业等课堂功能", symbol: "graduationcap", opening: .website,
              url: URL(string: "https://i.chaoxing.com/")!, fallback: nil, copyText: nil),
        .init(id: "mooc", title: "中国大学 MOOC", detail: "网课与作业", symbol: "play.rectangle", opening: .website,
              url: URL(string: "https://www.icourse163.org/")!, fallback: nil, copyText: nil),
        .init(id: "wechat", title: "微信", detail: "合工大教务公众号、第二课堂小程序等", symbol: "message", opening: .appStore,
              url: URL(string: "https://apps.apple.com/cn/app/id414478124")!, fallback: URL(string: "https://weixin.qq.com/"), copyText: "第二课堂")
    ]
}
