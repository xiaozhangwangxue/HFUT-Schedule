import Combine
import Foundation

enum ElectricityCampus: String, Codable, CaseIterable, Sendable {
    case hefei, xuancheng

    var title: String { self == .hefei ? "合肥校区" : "宣城校区" }
    var feeItemID: Int { self == .hefei ? 1 : 261 }
}

struct ElectricityDormitory: Codable, Equatable, Sendable {
    enum Side: String, Codable, CaseIterable, Identifiable, Sendable {
        case south, north
        var id: String { rawValue }
        var title: String { self == .south ? "南边" : "北边" }
        var meterPrefix: String { self == .south ? "1" : "2" }
    }

    var building = ""
    var room = ""
    var side: Side = .south
    var airConditioningBuilding = ""
    var airConditioningRoom = ""

    init(building: String = "", room: String = "", side: Side = .south,
         airConditioningBuilding: String = "", airConditioningRoom: String = "") {
        self.building = building
        self.room = room
        self.side = side
        self.airConditioningBuilding = airConditioningBuilding
        self.airConditioningRoom = airConditioningRoom
    }

    private enum CodingKeys: String, CodingKey {
        case building, room, side, airConditioningBuilding, airConditioningRoom
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        building = try values.decodeIfPresent(String.self, forKey: .building) ?? ""
        room = try values.decodeIfPresent(String.self, forKey: .room) ?? ""
        side = try values.decodeIfPresent(Side.self, forKey: .side) ?? .south
        airConditioningBuilding = try values.decodeIfPresent(String.self, forKey: .airConditioningBuilding) ?? ""
        airConditioningRoom = try values.decodeIfPresent(String.self, forKey: .airConditioningRoom) ?? ""
    }

    var hasLightingMeter: Bool { !building.isEmpty && !room.isEmpty }
    var hasAirConditioningMeter: Bool { !airConditioningBuilding.isEmpty && !airConditioningRoom.isEmpty }
    var hasDuplicateHefeiMeters: Bool {
        hasLightingMeter && hasAirConditioningMeter && building == airConditioningBuilding && room == airConditioningRoom
    }

    func isValid(for campus: ElectricityCampus) -> Bool {
        if campus == .hefei {
            return (hasLightingMeter || hasAirConditioningMeter) && !hasDuplicateHefeiMeters
        }
        guard !building.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !room.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let buildingNumber = Int(building), (1...10).contains(buildingNumber),
              building == String(buildingNumber), room.count == 3,
              let roomNumber = Int(room), (1...6).contains(roomNumber / 100),
              (1...30).contains(roomNumber % 100) else { return false }
        return true
    }

    var xuanchengMeterRequests: [(title: String, kind: HuiXinFeeKind)] {
        [
            ("照明电费", .electricXuancheng(room: "300\(building)\(room)\(side.meterPrefix)1")),
            ("空调电费", .electricXuancheng(room: "300\(building)\(room)\(side.meterPrefix)2"))
        ]
    }
}

/// Dormitory defaults are separate per campus: a Hefei room's server ID is not a Xuancheng room number.
@MainActor
final class ElectricityDefaultsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load(for campus: ElectricityCampus) -> ElectricityDormitory? {
        if let data = defaults.data(forKey: key(campus)),
           let saved = try? JSONDecoder().decode(ElectricityDormitory.self, from: data),
           saved.isValid(for: campus) { return saved }

        // The old global keys had no campus of their own. Only migrate when the
        // selected campus supplies the missing provenance, never into both campuses.
        guard defaults.string(forKey: "selectedCampus") == campus.title else { return nil }
        let legacy = ElectricityDormitory(
            building: defaults.string(forKey: "electricityBuilding") ?? "",
            room: defaults.string(forKey: "electricityRoom") ?? "",
            side: (defaults.string(forKey: "electricityRegion") ?? "11").hasPrefix("2") ? .north : .south
        )
        guard legacy.isValid(for: campus) else { return nil }
        save(legacy, for: campus)
        // A successful migration is one-shot even if the global campus changes later.
        defaults.removeObject(forKey: "electricityBuilding")
        defaults.removeObject(forKey: "electricityRoom")
        defaults.removeObject(forKey: "electricityRegion")
        return legacy
    }

    func save(_ dormitory: ElectricityDormitory, for campus: ElectricityCampus) {
        guard dormitory.isValid(for: campus), let data = try? JSONEncoder().encode(dormitory) else { return }
        defaults.set(data, forKey: key(campus))
    }

    private func key(_ campus: ElectricityCampus) -> String { "electricityDormitoryDefaults.v1.\(campus.rawValue)" }
}

protocol ElectricityServicing: Sendable {
    func fee(for kind: HuiXinFeeKind) async throws -> [String: String]
    func options(building: String?) async throws -> [HuiXinSelectionOption]
}

struct CampusElectricityService: ElectricityServicing {
    func fee(for kind: HuiXinFeeKind) async throws -> [String: String] {
        try await CampusServiceClient.shared.fetchFee(kind)
    }
    func options(building: String?) async throws -> [HuiXinSelectionOption] {
        try await CampusServiceClient.shared.fetchHefeiElectricOptions(building: building)
    }
}

struct ElectricityMeterResult: Identifiable, Equatable {
    let id: Int
    let title: String
    var values: [String: String] = [:]
    var error: String?
    var isLoading = true
    var needsConfiguration = false
}

@MainActor
final class ElectricityQueryModel: ObservableObject {
    @Published private(set) var campus: ElectricityCampus = .hefei
    @Published private(set) var selection = ElectricityDormitory()
    @Published private(set) var savedSelection: ElectricityDormitory?
    @Published private(set) var buildings: [HuiXinSelectionOption] = []
    @Published private(set) var rooms: [HuiXinSelectionOption] = []
    @Published private(set) var airConditioningRooms: [HuiXinSelectionOption] = []
    @Published private(set) var results: [ElectricityMeterResult] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingOptions = false
    @Published private(set) var optionsError: String?

    private let defaults: ElectricityDefaultsStore
    private let service: any ElectricityServicing
    private var generation = UUID()
    private var optionsTask: Task<Void, Never>?
    private var queryTask: Task<Void, Never>?
    private var isActive = false

    init(defaults: ElectricityDefaultsStore, service: any ElectricityServicing = CampusElectricityService()) {
        self.defaults = defaults
        self.service = service
    }

    convenience init() { self.init(defaults: ElectricityDefaultsStore()) }

    var canSave: Bool { selection.isValid(for: campus) && !isLoadingOptions && !isLoading }
    var canRefresh: Bool { savedSelection == selection && selection.isValid(for: campus) && !isLoading && !isLoadingOptions }
    var hasUnsavedChanges: Bool { savedSelection != selection }
    var hasError: Bool { optionsError != nil || results.contains { $0.error != nil } }

    func activate(campus: ElectricityCampus) {
        invalidate()
        isActive = true
        self.campus = campus
        savedSelection = defaults.load(for: campus)
        selection = savedSelection ?? ElectricityDormitory()
        buildings = []
        rooms = []
        airConditioningRooms = []
        optionsError = nil
        if campus == .hefei { loadOptions(andQuery: savedSelection != nil) }
        else if savedSelection != nil { startQuery() }
    }

    func deactivate() { isActive = false; invalidate() }

    func setBuilding(_ building: String) {
        guard selection.building != building else { return }
        invalidate()
        selection.building = building
        selection.room = ""
        rooms = []
        optionsError = nil
        if campus == .hefei, !building.isEmpty { loadOptions(loadBuildings: false) }
    }

    func setRoom(_ room: String) {
        guard selection.room != room else { return }
        invalidate()
        selection.room = room
    }

    func setAirConditioningBuilding(_ building: String) {
        guard selection.airConditioningBuilding != building else { return }
        invalidate()
        selection.airConditioningBuilding = building
        selection.airConditioningRoom = ""
        airConditioningRooms = []
        optionsError = nil
        if campus == .hefei, !building.isEmpty { loadOptions(loadBuildings: false) }
    }

    func setAirConditioningRoom(_ room: String) {
        guard selection.airConditioningRoom != room else { return }
        invalidate()
        selection.airConditioningRoom = room
    }

    func setSide(_ side: ElectricityDormitory.Side) {
        guard selection.side != side else { return }
        invalidate()
        selection.side = side
    }

    func saveAndQuery() {
        guard isActive, canSave else { return }
        defaults.save(selection, for: campus)
        savedSelection = selection
        startQuery()
    }

    func refreshSaved() {
        guard isActive, canRefresh else { return }
        startQuery()
    }

    func restoreSaved() { activate(campus: campus) }

    func reloadAfterLogin() {
        guard isActive else { return }
        invalidate()
        optionsError = nil
        let shouldQuery = savedSelection == selection && selection.isValid(for: campus)
        if campus == .hefei { loadOptions(andQuery: shouldQuery) }
        else if shouldQuery { startQuery() }
    }

    private func invalidate() {
        generation = UUID()
        queryTask?.cancel()
        optionsTask?.cancel()
        queryTask = nil
        optionsTask = nil
        results = []
        isLoading = false
        isLoadingOptions = false
    }

    private func loadOptions(loadBuildings: Bool = true, andQuery: Bool = false) {
        let requestGeneration = generation
        let building = selection.building
        let airConditioningBuilding = selection.airConditioningBuilding
        let service = service
        isLoadingOptions = true
        optionsTask = Task { [weak self] in
            do {
                if loadBuildings {
                    let values = try await service.options(building: nil)
                    guard let self, self.isCurrent(requestGeneration) else { return }
                    self.buildings = values
                }
            } catch {
                guard let self, self.isCurrent(requestGeneration) else { return }
                self.optionsError = error.localizedDescription
            }
            for (isAirConditioning, selectedBuilding) in [(false, building), (true, airConditioningBuilding)] where !selectedBuilding.isEmpty {
                do {
                    let values = try await service.options(building: selectedBuilding)
                    guard let self, self.isCurrent(requestGeneration) else { return }
                    if isAirConditioning { self.airConditioningRooms = values }
                    else { self.rooms = values }
                } catch {
                    guard let self, self.isCurrent(requestGeneration) else { return }
                    self.optionsError = error.localizedDescription
                }
            }
            guard let self, self.isCurrent(requestGeneration) else { return }
            self.isLoadingOptions = false
            self.optionsTask = nil
            // A list-service failure must not prevent querying a valid, already saved dormitory.
            if andQuery { self.startQuery() }
        }
    }

    private func startQuery() {
        guard isActive, selection.isValid(for: campus) else { return }
        queryTask?.cancel()
        generation = UUID()
        let requestGeneration = generation
        let dormitory = selection
        let requests: [(title: String, kind: HuiXinFeeKind?)] = campus == .xuancheng
            ? dormitory.xuanchengMeterRequests.map { ($0.title, Optional($0.kind)) }
            : [
                ("照明电费", dormitory.hasLightingMeter ? .electricHefei(building: dormitory.building, room: dormitory.room) : nil),
                ("空调电费", dormitory.hasAirConditioningMeter ? .electricHefei(building: dormitory.airConditioningBuilding, room: dormitory.airConditioningRoom) : nil)
            ]
        results = requests.enumerated().map {
            ElectricityMeterResult(id: $0.offset, title: $0.element.title, isLoading: $0.element.kind != nil,
                                   needsConfiguration: $0.element.kind == nil)
        }
        isLoading = true
        let service = service
        queryTask = Task { [weak self] in
            // Serial requests also avoid issuing two simultaneous token refreshes on an expired session.
            for (index, request) in requests.enumerated() {
                guard let kind = request.kind else { continue }
                do {
                    let values = try await service.fee(for: kind)
                    guard let self, self.isCurrent(requestGeneration) else { return }
                    self.results[index].values = values
                    self.results[index].isLoading = false
                } catch {
                    guard let self, self.isCurrent(requestGeneration) else { return }
                    self.results[index].error = error.localizedDescription
                    self.results[index].isLoading = false
                }
            }
            guard let self, self.isCurrent(requestGeneration) else { return }
            self.isLoading = false
            self.queryTask = nil
        }
    }

    private func isCurrent(_ requestGeneration: UUID) -> Bool {
        isActive && generation == requestGeneration && !Task.isCancelled
    }
}
