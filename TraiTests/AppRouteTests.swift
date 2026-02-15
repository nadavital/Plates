import XCTest
@testable import Trai

final class AppRouteTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "AppRouteTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func testURLRoundTripForCanonicalRoutes() {
        let routes: [AppRoute] = [
            .logFood,
            .logWeight,
            .workout(templateName: nil),
            .workout(templateName: "Push Pull Legs"),
            .chat
        ]

        for route in routes {
            let parsed = AppRoute(urlString: route.urlString)
            XCTAssertEqual(parsed, route)
        }
    }

    func testWorkoutRouteParsesTemplateFromQuery() {
        let route = AppRoute(urlString: "trai://workout?template=Upper%20Body")
        XCTAssertEqual(route, .workout(templateName: "Upper Body"))
    }

    func testInitRejectsUnknownSchemeOrHost() {
        XCTAssertNil(AppRoute(urlString: "https://example.com/workout"))
        XCTAssertNil(AppRoute(urlString: "trai://unknown"))
        XCTAssertNil(AppRoute(urlString: "not a url"))
    }

    func testPendingRouteStoreConsumesAndClearsStoredRoute() {
        PendingAppRouteStore.setPendingRoute(.chat, defaults: defaults)

        let consumed = PendingAppRouteStore.consumePendingRoute(defaults: defaults)
        XCTAssertEqual(consumed, .chat)
        XCTAssertNil(defaults.string(forKey: SharedStorageKeys.AppRouting.pendingRoute))
        XCTAssertNil(PendingAppRouteStore.consumePendingRoute(defaults: defaults))
    }

    func testPendingRouteStorePrefersPendingRouteOverLegacyFlags() {
        defaults.set(true, forKey: SharedStorageKeys.LegacyLaunchIntents.openFoodCamera)
        PendingAppRouteStore.setPendingRoute(.logWeight, defaults: defaults)

        let consumed = PendingAppRouteStore.consumePendingRoute(defaults: defaults)
        XCTAssertEqual(consumed, .logWeight)

        // Legacy value should remain for the next consume cycle since pending route wins first.
        XCTAssertEqual(PendingAppRouteStore.consumePendingRoute(defaults: defaults), .logFood)
    }

    func testPendingRouteStoreConsumesLegacyFoodCameraFlag() {
        defaults.set(true, forKey: SharedStorageKeys.LegacyLaunchIntents.openFoodCamera)

        let consumed = PendingAppRouteStore.consumePendingRoute(defaults: defaults)
        XCTAssertEqual(consumed, .logFood)
        XCTAssertFalse(defaults.bool(forKey: SharedStorageKeys.LegacyLaunchIntents.openFoodCamera))
    }

    func testPendingRouteStoreConsumesLegacyWorkoutFlagCustomAsNilTemplate() {
        defaults.set("custom", forKey: SharedStorageKeys.LegacyLaunchIntents.startWorkout)

        let consumed = PendingAppRouteStore.consumePendingRoute(defaults: defaults)
        XCTAssertEqual(consumed, .workout(templateName: nil))
        XCTAssertNil(defaults.string(forKey: SharedStorageKeys.LegacyLaunchIntents.startWorkout))
    }

    func testPendingRouteStoreConsumesLegacyWorkoutFlagWithTemplateName() {
        defaults.set("Leg Day", forKey: SharedStorageKeys.LegacyLaunchIntents.startWorkout)

        let consumed = PendingAppRouteStore.consumePendingRoute(defaults: defaults)
        XCTAssertEqual(consumed, .workout(templateName: "Leg Day"))
    }

    func testPendingRouteStoreReturnsNilWhenNoPendingData() {
        XCTAssertNil(PendingAppRouteStore.consumePendingRoute(defaults: defaults))
    }
}
