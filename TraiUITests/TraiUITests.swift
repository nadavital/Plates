import XCTest

final class TraiUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMainTabsAreVisibleAndNavigable() {
        let app = makeApp()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8))

        let dashboardTab = tabBar.buttons["Dashboard"]
        let traiTab = tabBar.buttons["Trai"]
        let workoutsTab = tabBar.buttons["Workouts"]
        let profileTab = tabBar.buttons["Profile"]

        XCTAssertTrue(dashboardTab.exists)
        XCTAssertTrue(traiTab.exists)
        XCTAssertTrue(workoutsTab.exists)
        XCTAssertTrue(profileTab.exists)

        workoutsTab.tap()
        XCTAssertTrue(workoutsTab.isSelected)

        traiTab.tap()
        XCTAssertTrue(traiTab.isSelected)

        profileTab.tap()
        XCTAssertTrue(profileTab.isSelected)

        dashboardTab.tap()
        XCTAssertTrue(dashboardTab.isSelected)
    }

    func testPendingChatRouteSelectsTraiTabOnLaunch() {
        let app = makeApp(extraArguments: ["-pendingAppRoute", "trai://chat"])
        app.launch()

        let traiTab = app.tabBars.buttons["Trai"]
        XCTAssertTrue(traiTab.waitForExistence(timeout: 8))

        let selectedPredicate = NSPredicate(format: "isSelected == true")
        let selectedExpectation = XCTNSPredicateExpectation(predicate: selectedPredicate, object: traiTab)

        XCTAssertEqual(XCTWaiter.wait(for: [selectedExpectation], timeout: 5), .completed)
    }

    func testPendingLogFoodRoutePresentsFoodCamera() {
        let app = makeApp(extraArguments: ["-pendingAppRoute", "trai://logfood"])
        app.launch()

        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Manual"].exists)
    }

    func testPendingLogWeightRoutePresentsLogWeightSheet() {
        let app = makeApp(extraArguments: ["-pendingAppRoute", "trai://logweight"])
        app.launch()

        XCTAssertTrue(app.navigationBars["Log Weight"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Save"].exists)
    }

    func testPendingWorkoutRoutePresentsLiveWorkout() {
        let app = makeApp(extraArguments: ["-pendingAppRoute", "trai://workout"])
        app.launch()

        XCTAssertTrue(app.buttons["End"].waitForExistence(timeout: 8))
    }

    private func makeApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_MODE"] + extraArguments
        return app
    }
}
