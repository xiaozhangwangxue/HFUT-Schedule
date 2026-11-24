import SwiftUI

struct CommunityAppointmentView: View {
    struct Place: Decodable, Identifiable {
        struct Frame: Decodable, Identifiable {
            let appointmentFlag: String
            let timeFrame: String
            var id: String { timeFrame }
        }
        struct Administrator: Decodable {
            let realname: String
            let phone: String?
            let telephone: String?
        }
        let id: String
        let name: String
        let communityName: String
        let address: String
        let startTime: String
        let endTime: String
        let voList: [Frame]
        let adminList: [Administrator]
        var frames: [Frame] { voList }
    }
    struct Seat: Decodable, Identifiable {
        let communityId: String
        let communityName: String
        let startTime: String
        let endTime: String
        let seatNum: String
        var id: String { communityId }
    }
    private struct Page<T: Decodable>: Decodable { let result: Records<T> }
    private struct Records<T: Decodable>: Decodable { let records: [T] }
    @State private var section = 0
    @State private var onlyAvailable = false
    @State private var places: [Place] = []
    @State private var seats: [Seat] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?
    @State private var generation = UUID()

    var body: some View {
        List {
            Section {
                Picker("类型", selection: $section) { Text("场地").tag(0); Text("座位").tag(1) }.pickerStyle(.segmented)
                LabeledContent("日期", value: Date().formatted(date: .numeric, time: .omitted))
                if section == 0 { Toggle("仅显示可用时段", isOn: $onlyAvailable) }
                Text("原版尚未开放最终预约提交和指定日期切换，此处展示今日列表与可用时段。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if section == 0 {
                ForEach(places.filter { !onlyAvailable || $0.frames.contains { $0.appointmentFlag == "1" } }) { place in
                    Section(place.name) {
                        Text("\(place.communityName) · \(place.address)")
                        Text("\(place.startTime)–\(place.endTime)").font(.caption).foregroundStyle(.secondary)
                        ForEach(place.frames.filter { !onlyAvailable || $0.appointmentFlag == "1" }) { frame in
                            HStack {
                                Text(frame.timeFrame)
                                Spacer()
                                Label(frame.appointmentFlag == "1" ? "可用" : "占用", systemImage: frame.appointmentFlag == "1" ? "checkmark.circle" : "minus.circle")
                                    .foregroundStyle(frame.appointmentFlag == "1" ? .green : .secondary)
                            }.font(.subheadline)
                        }
                        ForEach(Array(place.adminList.enumerated()), id: \.offset) { _, person in
                            LabeledContent("管理员", value: person.realname)
                            if let phone = person.phone ?? person.telephone, !phone.isEmpty,
                               let url = URL(string: "tel:\(phone)") { Link(phone, destination: url) }
                        }
                    }
                }
            } else {
                ForEach(seats) { seat in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(seat.communityName).font(.headline)
                        Text("\(seat.startTime)–\(seat.endTime) · 座位数：\(seat.seatNum)").font(.caption)
                    }
                }
            }
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            if hasMore { Button("加载更多") { Task { await load(reset: false) } }.disabled(loading) }
        }
        .navigationTitle("场地与座位")
        .task(id: section) { await load(reset: true) }
        .refreshable { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        if loading && !reset { return }
        let token = UUID(); generation = token; loading = true; error = nil
        let next = reset ? 1 : page + 1
        defer { if generation == token { loading = false } }
        do {
            let path = section == 0
                ? "api//mobile/community/site/page?localDate=\(HolidayCalendarStore.key(for: Date()))&pageNo=\(next)&pageSize=30"
                : "api//mobile/community/seat/pageSeat?pageNo=\(next)&pageSize=30"
            let data = try await OfficialCampusAPIClient.shared.communityAuthorizedData(path: path)
            guard generation == token else { return }
            if section == 0 {
                let rows = try JSONDecoder().decode(Page<Place>.self, from: data).result.records
                places = reset ? rows : places + rows; hasMore = rows.count == 30
            } else {
                let rows = try JSONDecoder().decode(Page<Seat>.self, from: data).result.records
                seats = reset ? rows : seats + rows; hasMore = rows.count == 30
            }
            page = next
        } catch { if generation == token { self.error = error.localizedDescription } }
    }
}
