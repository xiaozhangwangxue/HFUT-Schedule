import XCTest
import SwiftUI
import UIKit
@testable import HFUTSchedule

@MainActor
final class ElectricityDefaultsTests: XCTestCase {
    private let south = ElectricityDormitory(building: "1", room: "101", side: .south)
    private let north = ElectricityDormitory(building: "2", room: "202", side: .north)
    private let hefei = ElectricityDormitory(building: "A", room: "A101", airConditioningBuilding: "B", airConditioningRoom: "B101")

    func testDormitoryDefaultsRemainSeparateForBothCampuses() throws {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        store.save(south, for: .xuancheng)
        store.save(hefei, for: .hefei)
        let reopened = ElectricityDefaultsStore(defaults: defaults)
        XCTAssertEqual(reopened.load(for: .xuancheng), south)
        XCTAssertEqual(reopened.load(for: .hefei), hefei)
    }

    func testLegacyDefaultsMigrateOnlyIntoTheirKnownCampusOnce() {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("宣城校区", forKey: "selectedCampus")
        defaults.set("2", forKey: "electricityBuilding")
        defaults.set("202", forKey: "electricityRoom")
        defaults.set("22", forKey: "electricityRegion")
        XCTAssertNil(store.load(for: .hefei))
        XCTAssertEqual(store.load(for: .xuancheng), north)
        defaults.set("合肥校区", forKey: "selectedCampus")
        XCTAssertNil(store.load(for: .hefei), "Legacy room numbers must not migrate into a second campus later")
        XCTAssertEqual(store.load(for: .xuancheng), north)
    }

    func testAmbiguousOrInvalidLegacyDormitoryDoesNotBecomeDefault() {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("1", forKey: "electricityBuilding")
        defaults.set("101", forKey: "electricityRoom")
        XCTAssertNil(store.load(for: .hefei))
        XCTAssertNil(store.load(for: .xuancheng))
        defaults.set("宣城校区", forKey: "selectedCampus")
        defaults.set("999", forKey: "electricityRoom")
        XCTAssertNil(store.load(for: .xuancheng))
    }

    func testXuanchengUsesBothMetersForTheChosenSideWithoutInventingHefeiMeters() {
        let southRooms = south.xuanchengMeterRequests.map { Dictionary(uniqueKeysWithValues: $0.kind.fields)["room"] }
        XCTAssertEqual(southRooms, ["300110111", "300110112"])
        let northRooms = north.xuanchengMeterRequests.map { Dictionary(uniqueKeysWithValues: $0.kind.fields)["room"] }
        XCTAssertEqual(northRooms, ["300220221", "300220222"])
        for invalid in [ElectricityDormitory(building: "", room: "101"), .init(building: "11", room: "101"),
                        .init(building: "1", room: "100"), .init(building: "1", room: "131"),
                        .init(building: "1", room: "701"), .init(building: "1", room: "1") ] {
            XCTAssertFalse(invalid.isValid(for: .xuancheng))
        }
    }

    func testOpeningWithoutASavedDormitoryDoesNotQueryAnArbitraryRoom() async throws {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        let service = ImmediateService()
        let model = ElectricityQueryModel(defaults: store, service: service)
        model.activate(campus: .xuancheng)
        await settle()
        let calls = await service.feeRequests
        XCTAssertTrue(calls.isEmpty)
        XCTAssertFalse(model.canSave)
        XCTAssertFalse(model.canRefresh)
        model.deactivate()
    }

    func testSavedXuanchengRoomAutomaticallyQueriesBothMetersWithIndependentFailure() async throws {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        store.save(south, for: .xuancheng)
        let service = ImmediateService(responses: [.success(["剩余金额": "100.00 元"]), .failure(.failed)])
        let model = ElectricityQueryModel(defaults: store, service: service)
        model.activate(campus: .xuancheng)
        try await eventually { model.results.count == 2 && !model.isLoading }
        XCTAssertEqual(model.results[0].values, ["剩余金额": "100.00 元"])
        XCTAssertNil(model.results[0].error)
        XCTAssertNotNil(model.results[1].error)
        XCTAssertTrue(model.results[1].values.isEmpty)
        let calls = await service.feeRequests
        XCTAssertEqual(calls.map { $0.fields["room"] }, ["300110111", "300110112"])
        XCTAssertTrue(calls.allSatisfy { $0.itemID == 261 })
        model.deactivate()
    }

    func testLightingFailureStillAllowsTheAirConditioningQueryToFinish() async throws {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        store.save(south, for: .xuancheng)
        let service = ImmediateService(responses: [.failure(.failed), .success(["余额": "空调成功"])])
        let model = ElectricityQueryModel(defaults: store, service: service)
        model.activate(campus: .xuancheng)
        try await eventually { model.results.count == 2 && !model.isLoading }
        XCTAssertNotNil(model.results[0].error)
        XCTAssertNil(model.results[1].error)
        XCTAssertEqual(model.results[1].values, ["余额": "空调成功"])
        model.deactivate()
    }

    func testHefeiSingleConfiguredMeterDoesNotInventOrQueryTheOtherMeter() async throws {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        let oneMeter = ElectricityDormitory(building: "A", room: "A101")
        store.save(oneMeter, for: .hefei)
        let service = ImmediateService()
        let model = ElectricityQueryModel(defaults: store, service: service)
        model.activate(campus: .hefei)
        try await eventually { model.results.count == 2 && !model.isLoading }
        XCTAssertFalse(model.results[0].values.isEmpty)
        XCTAssertTrue(model.results[1].needsConfiguration)
        XCTAssertTrue(model.results[1].values.isEmpty)
        XCTAssertNil(model.results[1].error, "A missing configuration is not a login failure")
        let calls = await service.feeRequests
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].fields["building"], "A")
        model.deactivate()
    }

    func testHefeiAirConditioningCanBeSavedWithoutLightingAndDuplicateMetersAreRejected() async throws {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        let airOnly = ElectricityDormitory(airConditioningBuilding: "B", airConditioningRoom: "B101")
        XCTAssertTrue(airOnly.isValid(for: .hefei))
        store.save(airOnly, for: .hefei)
        let service = ImmediateService()
        let model = ElectricityQueryModel(defaults: store, service: service)
        model.activate(campus: .hefei)
        try await eventually { model.results.count == 2 && !model.isLoading }
        XCTAssertTrue(model.results[0].needsConfiguration)
        XCTAssertFalse(model.results[1].values.isEmpty)
        let calls = await service.feeRequests
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].fields["building"], "B")
        XCTAssertFalse(ElectricityDormitory(building: "A", room: "101", airConditioningBuilding: "A", airConditioningRoom: "101").isValid(for: .hefei))
        model.deactivate()
    }

    func testSavingAndReopeningQueriesThePersistedDormitory() async throws {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        let service = ImmediateService()
        let model = ElectricityQueryModel(defaults: store, service: service)
        model.activate(campus: .xuancheng)
        model.setBuilding("2")
        model.setRoom("202")
        model.setSide(.north)
        XCTAssertTrue(model.canSave)
        model.saveAndQuery()
        try await eventually { model.results.count == 2 && !model.isLoading }
        XCTAssertEqual(store.load(for: .xuancheng), north)
        model.deactivate()
        let reopened = ElectricityQueryModel(defaults: ElectricityDefaultsStore(defaults: defaults), service: service)
        reopened.activate(campus: .xuancheng)
        try await eventually { reopened.results.count == 2 && !reopened.isLoading }
        XCTAssertEqual(reopened.selection, north)
        let calls = await service.feeRequests
        XCTAssertEqual(calls.count, 4)
        reopened.deactivate()
    }

    func testChangingRoomRejectsAResponseForThePreviousDormitory() async throws {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        store.save(south, for: .xuancheng)
        let service = ControlledService()
        let model = ElectricityQueryModel(defaults: store, service: service)
        model.activate(campus: .xuancheng)
        try await eventually { await service.feeCount == 1 }
        model.setRoom("102")
        await service.completeFee(0, values: ["余额": "旧宿舍"])
        await settle()
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.canRefresh, "Pulling a refresh must not query an unsaved draft")
        XCTAssertEqual(model.savedSelection, south)
        model.deactivate()
    }

    func testSwitchingCampusRejectsTheOldCampusAndKeepsItsDefaultsSeparate() async throws {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        store.save(south, for: .xuancheng)
        store.save(hefei, for: .hefei)
        let service = ControlledService()
        let model = ElectricityQueryModel(defaults: store, service: service)
        model.activate(campus: .xuancheng)
        try await eventually { await service.feeCount == 1 }
        model.activate(campus: .hefei)
        try await eventually { await service.feeCount == 2 }
        await service.completeFee(1, values: ["余额": "80"])
        try await eventually { await service.feeCount == 3 }
        await service.completeFee(2, values: ["余额": "50"])
        try await eventually { !model.isLoading }
        await service.completeFee(0, values: ["余额": "旧校区"])
        await settle()
        XCTAssertEqual(model.campus, .hefei)
        XCTAssertEqual(model.selection, hefei)
        XCTAssertEqual(model.results.count, 2)
        XCTAssertEqual(model.results[0].values, ["余额": "80"])
        XCTAssertEqual(model.results[1].values, ["余额": "50"])
        let calls = await service.feeRequests
        XCTAssertEqual(calls.map(\.itemID), [261, 1, 1])
        XCTAssertEqual(calls[1].fields["building"], "A")
        XCTAssertEqual(calls[1].fields["room"], "A101")
        XCTAssertEqual(calls[2].fields["building"], "B")
        XCTAssertEqual(calls[2].fields["room"], "B101")
        model.deactivate()
    }

    func testLateRoomOptionsCannotReplaceTheNewBuildingsRooms() async throws {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        let service = ControlledService(delayOptions: true)
        let model = ElectricityQueryModel(defaults: store, service: service)
        model.activate(campus: .hefei)
        try await eventually { await service.optionCount == 1 }
        await service.completeOptions(0, values: [.init(name: "A", value: "A"), .init(name: "B", value: "B")])
        try await eventually { !model.isLoadingOptions }
        model.setBuilding("A")
        try await eventually { await service.optionCount == 2 }
        model.setBuilding("B")
        try await eventually { await service.optionCount == 3 }
        await service.completeOptions(1, values: [.init(name: "旧房间", value: "A101")])
        await service.completeOptions(2, values: [.init(name: "新房间", value: "B102")])
        try await eventually { !model.isLoadingOptions }
        XCTAssertEqual(model.rooms.map(\.value), ["B102"])
        XCTAssertEqual(model.selection.building, "B")
        model.deactivate()
    }

    func testHefeiSavedRoomStillQueriesIfItsOptionsServiceFails() async throws {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        store.save(hefei, for: .hefei)
        let service = ImmediateService(optionsFail: true)
        let model = ElectricityQueryModel(defaults: store, service: service)
        model.activate(campus: .hefei)
        try await eventually { model.results.count == 2 && !model.isLoading }
        XCTAssertNotNil(model.optionsError)
        XCTAssertFalse(model.results[0].values.isEmpty)
        XCTAssertFalse(model.results[1].values.isEmpty)
        let calls = await service.feeRequests
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls.map(\.itemID), [1, 1], "Both meter IDs use the same verified fee endpoint")
        XCTAssertEqual(calls.map { $0.fields["building"] }, ["A", "B"])
        model.deactivate()
    }

    func testLeavingPageDiscardsLateResponses() async throws {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        store.save(south, for: .xuancheng)
        let service = ControlledService()
        let model = ElectricityQueryModel(defaults: store, service: service)
        model.activate(campus: .xuancheng)
        try await eventually { await service.feeCount == 1 }
        model.deactivate()
        await service.completeFee(0, values: ["余额": "迟到结果"])
        await settle()
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertFalse(model.isLoading)
        let count = await service.feeCount
        XCTAssertEqual(count, 1)
    }

    func testBothCampusPagesRenderWithSavedDormitoriesAndLocalResults() async throws {
        let defaults = UserDefaults.standard
        let oldCampus = defaults.object(forKey: "selectedCampus")
        defer {
            if let oldCampus { defaults.set(oldCampus, forKey: "selectedCampus") }
            else { defaults.removeObject(forKey: "selectedCampus") }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let oldWindow = scene.windows.first(where: \.isKeyWindow)
        defer { oldWindow?.makeKeyAndVisible() }
        for campus in ElectricityCampus.allCases {
            let (store, isolatedDefaults, name) = makeStore()
            defer { isolatedDefaults.removePersistentDomain(forName: name) }
            store.save(campus == .hefei ? hefei : south, for: campus)
            let model = ElectricityQueryModel(defaults: store, service: ImmediateService())
            let appState = AppState()
            appState.campus = campus == .hefei ? .hefei : .xuancheng
            let host = UIHostingController(rootView: NavigationStack { ElectricityServiceView(model: model) }
                .environmentObject(appState).preferredColorScheme(.light))
            let window = UIWindow(windowScene: scene)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; model.deactivate() }
            try await eventually { !model.results.isEmpty && !model.isLoading }
            try await Task.sleep(for: .milliseconds(150))
            host.view.layoutIfNeeded()
            let screenshot = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("HFUT-electricity-default-\(campus.rawValue).png")
            try XCTUnwrap(screenshot.pngData()).write(to: output)
            print("HFUT_ELECTRICITY_SCREENSHOT=\(output.path)")
            let attachment = XCTAttachment(image: screenshot)
            attachment.name = "Default dormitory electricity \(campus.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
        }
    }

    private func makeStore() -> (ElectricityDefaultsStore, UserDefaults, String) {
        let name = "HFUT-electricity-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        return (ElectricityDefaultsStore(defaults: defaults), defaults, name)
    }

    private func eventually(_ predicate: () async -> Bool) async throws {
        for _ in 0..<400 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Electricity state did not settle")
        throw FixtureError.timeout
    }

    private func settle() async { try? await Task.sleep(for: .milliseconds(20)) }

    private enum FixtureError: LocalizedError { case failed, timeout
        var errorDescription: String? { "本地测试：暂时无法读取" }
    }
    private struct FeeRequest: Sendable {
        let itemID: Int
        let fields: [String: String]
        init(_ kind: HuiXinFeeKind) { itemID = kind.itemID; fields = Dictionary(uniqueKeysWithValues: kind.fields) }
    }

    private actor ImmediateService: ElectricityServicing {
        var feeRequests: [FeeRequest] = []
        private var responses: [Result<[String: String], FixtureError>]
        private let optionsFail: Bool
        init(responses: [Result<[String: String], FixtureError>] = [], optionsFail: Bool = false) {
            self.responses = responses; self.optionsFail = optionsFail
        }
        func fee(for kind: HuiXinFeeKind) async throws -> [String: String] {
            feeRequests.append(FeeRequest(kind))
            return try responses.isEmpty ? ["剩余金额": "100.00 元（示例）"] : responses.removeFirst().get()
        }
        func options(building: String?) async throws -> [HuiXinSelectionOption] {
            if optionsFail { throw FixtureError.failed }
            if let building { return [.init(name: "101", value: building + "101")] }
            return [.init(name: "示例宿舍楼·照明", value: "A"), .init(name: "示例宿舍楼·空调", value: "B")]
        }
    }

    /// Finishes even cancelled requests to exercise the stale-response guards.
    private actor ControlledService: ElectricityServicing {
        var feeRequests: [FeeRequest] = []
        var feeCount: Int { feeRequests.count }
        var optionCount: Int { optionContinuations.count }
        private var feeContinuations: [CheckedContinuation<[String: String], Error>?] = []
        private var optionContinuations: [CheckedContinuation<[HuiXinSelectionOption], Error>?] = []
        private let delayOptions: Bool
        init(delayOptions: Bool = false) { self.delayOptions = delayOptions }
        func fee(for kind: HuiXinFeeKind) async throws -> [String: String] {
            feeRequests.append(FeeRequest(kind))
            return try await withCheckedThrowingContinuation { feeContinuations.append($0) }
        }
        func options(building: String?) async throws -> [HuiXinSelectionOption] {
            if delayOptions { return try await withCheckedThrowingContinuation { optionContinuations.append($0) } }
            if let building { return [.init(name: "101", value: building + "101")] }
            return [.init(name: "A", value: "A"), .init(name: "B", value: "B")]
        }
        func completeFee(_ index: Int, values: [String: String]) {
            feeContinuations[index]?.resume(returning: values); feeContinuations[index] = nil
        }
        func completeOptions(_ index: Int, values: [HuiXinSelectionOption]) {
            optionContinuations[index]?.resume(returning: values); optionContinuations[index] = nil
        }
    }
}
