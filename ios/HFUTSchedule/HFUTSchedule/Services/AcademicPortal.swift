import Foundation

enum AcademicConnectionMode: String, CaseIterable, Identifiable {
    case direct
    case webVPN

    var id: String { rawValue }
    var title: String { self == .direct ? "校园网直连" : "校外 WebVPN" }
}

enum AcademicPortal {
    static let directAcademicRoot = URL(string: "https://jxglstu.hfut.edu.cn/eams5-student/")!
    static let webVPNAcademicRoot = URL(
        string: "https://webvpn.hfut.edu.cn/http/77726476706e69737468656265737421faef469034247d1e760e9cb8d6502720ede479/eams5-student/"
    )!

    static func loginURL(for mode: AcademicConnectionMode) -> URL {
        if mode == .webVPN {
            return URL(string: "https://webvpn.hfut.edu.cn/login?cas_login=true")!
        }

        var components = URLComponents(string: "https://cas.hfut.edu.cn/cas/login")!
        components.queryItems = [URLQueryItem(
            name: "service",
            value: CASLoginClient.service
        )]
        return components.url!
    }

    static func academicRoot(for mode: AcademicConnectionMode) -> URL {
        mode == .direct ? directAcademicRoot : webVPNAcademicRoot
    }

    static func url(_ path: String, mode: AcademicConnectionMode) -> URL {
        URL(string: path, relativeTo: academicRoot(for: mode))!.absoluteURL
    }

    static var currentSemesterID: Int {
        let components = Calendar.current.dateComponents([.year, .month], from: Date())
        let year = components.year ?? 2026
        let month = components.month ?? 9
        let startYear = month <= 7 ? year - 1 : year
        let firstSemester = ((startYear - 2018) * 4 + 3) * 10 + 4
        return month <= 7 && month >= 2 ? firstSemester + 20 : firstSemester
    }

    static func shouldEnterAcademicAfterWebVPNLogin(_ url: URL?) -> Bool {
        guard let url, url.host?.lowercased() == "webvpn.hfut.edu.cn" else { return false }
        let path = url.path.lowercased()
        return path == "/" || path.hasPrefix("/user/portal") || path.hasPrefix("/portal")
    }

    static func isAcademicPage(_ url: URL?, mode: AcademicConnectionMode) -> Bool {
        guard let url, let host = url.host?.lowercased() else { return false }
        switch mode {
        case .direct:
            return host == "jxglstu.hfut.edu.cn"
        case .webVPN:
            return host == "webvpn.hfut.edu.cn" && url.path.contains("/eams5-student/")
        }
    }

    /// Works for both the direct portal and WebVPN's encrypted path prefix.
    static let javaScriptBasePath = """
    const marker = '/eams5-student/';
    const markerIndex = window.location.pathname.indexOf(marker);
    if (markerIndex < 0) throw new Error('当前页面不是教务系统，请先完成登录');
    const academicBase = window.location.pathname.slice(0, markerIndex) + '/eams5-student';
    """
}
