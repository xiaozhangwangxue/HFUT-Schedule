import Foundation

struct HefeiDormitoryMeterGroup: Identifiable {
    let name: String
    let options: [HuiXinSelectionOption]
    var lighting: HuiXinSelectionOption? { options.first { $0.name.contains("照明") } }
    var airConditioning: HuiXinSelectionOption? { options.first { $0.name.contains("空调") } }
    var primary: HuiXinSelectionOption { lighting ?? airConditioning ?? options[0] }
    var id: String { primary.value }
    var hasKnownTypes: Bool { lighting != nil || airConditioning != nil }
    func contains(_ value: String) -> Bool { !value.isEmpty && options.contains { $0.value == value } }
}

enum HefeiMeterPairing {
    static func normalizedName(_ text: String) -> String {
        text.folding(options:[.widthInsensitive,.caseInsensitive],locale:Locale(identifier:"zh_CN"))
            .replacingOccurrences(of:"照明",with:"").replacingOccurrences(of:"空调",with:"")
            .replacingOccurrences(of:"()",with:"").replacingOccurrences(of:"（）",with:"")
            .filter { !$0.isWhitespace }
    }
    static func groups(_ options: [HuiXinSelectionOption]) -> [HefeiDormitoryMeterGroup] {
        var names:[String] = [], grouped:[String:[HuiXinSelectionOption]] = [:]
        for option in options {
            let name = normalizedName(option.name)
            if grouped[name] == nil { names.append(name) }
            grouped[name,default:[]].append(option)
        }
        return names.map { HefeiDormitoryMeterGroup(name:$0,options:grouped[$0]!) }
    }
    static func matchingRoom(_ reference: HuiXinSelectionOption, in options: [HuiXinSelectionOption], airConditioning: Bool) -> HuiXinSelectionOption? {
        let rows = options.filter {
            normalizedName($0.name) == normalizedName(reference.name) &&
            (airConditioning ? !$0.name.contains("照明") : !$0.name.contains("空调"))
        }
        return rows.count == 1 ? rows[0] : nil
    }
}
