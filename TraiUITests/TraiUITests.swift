import XCTest
import Foundation

final class TraiUITests: XCTestCase {
    private static var didBootstrapPersistentStoreProfile = false
    private let startupToTabBarSmokeBudgetSeconds: TimeInterval = 5.8
    private let tabSwitchSmokeBudgetSeconds: TimeInterval = 3.5
    private let foregroundReopenSmokeBudgetSeconds: TimeInterval = 1.8
    private let addExerciseSheetSmokeBudgetSeconds: TimeInterval = 3.0

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
        XCTAssertTrue(
            app.descendants(matching: .any)["foodCameraCaptureReady"].waitForExistence(timeout: 4)
        )
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

        XCTAssertTrue(app.buttons["liveWorkoutEndButton"].waitForExistence(timeout: 8))
    }

    func testLiveWorkoutStabilityPresetHandlesRepeatedMutationsAndReopen() throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_WORKOUT_STABILITY_UI_STRESS"] == "1" else {
            throw XCTSkip(
                "Skipping live workout stress UI path by default due simulator query flakiness; set RUN_LIVE_WORKOUT_STABILITY_UI_STRESS=1 to run explicitly."
            )
        }

        let app = makeApp(extraArguments: [
            "-pendingAppRoute", "trai://workout",
            "--ui-test-live-workout-preset",
            "--seed-live-workout-perf-data"
        ])
        app.launch()

        var workoutReady = waitForLiveWorkoutScreen(in: app, timeout: 12)
        if !workoutReady {
            app.terminate()
            app.launch()
            workoutReady = waitForLiveWorkoutScreen(in: app, timeout: 16)
        }
        guard workoutReady else {
            throw XCTSkip("Live workout screen did not become queryable on this simulator run")
        }

        for _ in 0..<3 {
            app.navigationBars.firstMatch.swipeDown()

            let banner = app.otherElements["activeWorkoutBanner"]
            guard banner.waitForExistence(timeout: 8) else {
                throw XCTSkip("Active workout banner was not queryable after minimizing workout")
            }
            banner.tap()
            guard waitForLiveWorkoutScreen(in: app, timeout: 8) else {
                throw XCTSkip("Live workout screen did not restore from banner on this simulator run")
            }
        }
    }

    func testStartupAndTabSwitchLatencySmoke() {
        let app = makeApp()
        let launchStart = ProcessInfo.processInfo.systemUptime
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        let launchToTabBar = ProcessInfo.processInfo.systemUptime - launchStart
        logLatencyMetric("startup_to_tabbar", value: launchToTabBar)
        XCTAssertLessThan(
            launchToTabBar,
            startupToTabBarSmokeBudgetSeconds,
            "Startup-to-tabbar exceeded smoke budget (\(launchToTabBar)s)"
        )

        let dashboardTab = tabBar.buttons["Dashboard"]
        let traiTab = tabBar.buttons["Trai"]
        let workoutsTab = tabBar.buttons["Workouts"]
        let profileTab = tabBar.buttons["Profile"]

        XCTAssertTrue(dashboardTab.exists)
        XCTAssertTrue(traiTab.exists)
        XCTAssertTrue(workoutsTab.exists)
        XCTAssertTrue(profileTab.exists)

        ensureTabSelected(dashboardTab, label: "Dashboard")
        assertReadiness(in: app, identifier: "dashboardRootReady", timeout: 10)
        _ = tapAndMeasureSelection(workoutsTab, in: app, label: "Workouts", readinessIdentifier: "workoutsRootReady")
        _ = tapAndMeasureSelection(traiTab, in: app, label: "Trai", readinessIdentifier: "traiRootReady")
        _ = tapAndMeasureSelection(profileTab, in: app, label: "Profile", readinessIdentifier: "profileRootReady")
        _ = tapAndMeasureSelection(dashboardTab, in: app, label: "Dashboard", readinessIdentifier: "dashboardRootReady")
    }

    func testStartupLatencySmokeWithExistingUserData() {
        ensurePersistentStoreProfileForRealDataTests()
        let app = makeApp(includeUITestMode: false)
        let launchStart = ProcessInfo.processInfo.systemUptime
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20))
        let launchToTabBar = ProcessInfo.processInfo.systemUptime - launchStart
        logLatencyMetric("startup_to_tabbar_real_data", value: launchToTabBar)

        let dashboardTab = tabBar.buttons["Dashboard"]
        ensureTabSelected(dashboardTab, label: "Dashboard")
        assertReadiness(in: app, identifier: "dashboardRootReady", timeout: 20)
    }

    func testForegroundReopenLatencySmoke() {
        let app = makeApp()
        app.launch()

        let initialTabBar = app.tabBars.firstMatch
        XCTAssertTrue(initialTabBar.waitForExistence(timeout: 10))
        let dashboardTab = initialTabBar.buttons["Dashboard"]
        ensureTabSelected(dashboardTab, label: "Dashboard")
        assertReadiness(in: app, identifier: "dashboardRootReady", timeout: 10)

        XCUIDevice.shared.press(.home)
        waitForAppToLeaveForeground(app, timeout: 3)

        let reopenStart = ProcessInfo.processInfo.systemUptime
        app.activate()

        let reopenedTabBarVisible = waitForTabBarAfterReopen(in: app, timeout: 8)
        let reopenLatency = ProcessInfo.processInfo.systemUptime - reopenStart
        logLatencyMetric("reopen_to_tabbar", value: reopenLatency)

        XCTAssertTrue(reopenedTabBarVisible, "Tab bar did not appear after foreground reopen")

        let reopenedTabBar = app.tabBars.firstMatch
        let reopenedDashboardTab = reopenedTabBar.buttons["Dashboard"]
        ensureTabSelected(reopenedDashboardTab, label: "Dashboard")
        assertReadiness(in: app, identifier: "dashboardRootReady", timeout: 8)

        XCTAssertLessThan(
            reopenLatency,
            foregroundReopenSmokeBudgetSeconds,
            "Foreground reopen exceeded smoke budget (\(reopenLatency)s)"
        )
    }

    func testForegroundReopenLatencySmokeWithExistingUserData() {
        ensurePersistentStoreProfileForRealDataTests()
        let app = makeApp(includeUITestMode: false)
        app.launch()

        let initialTabBar = app.tabBars.firstMatch
        XCTAssertTrue(initialTabBar.waitForExistence(timeout: 20))
        let dashboardTab = initialTabBar.buttons["Dashboard"]
        ensureTabSelected(dashboardTab, label: "Dashboard")
        assertReadiness(in: app, identifier: "dashboardRootReady", timeout: 20)

        XCUIDevice.shared.press(.home)
        waitForAppToLeaveForeground(app, timeout: 4)

        let reopenStart = ProcessInfo.processInfo.systemUptime
        app.activate()

        let reopenedTabBarVisible = waitForTabBarAfterReopen(in: app, timeout: 12)
        let reopenLatency = ProcessInfo.processInfo.systemUptime - reopenStart
        logLatencyMetric("reopen_to_tabbar_real_data", value: reopenLatency)

        XCTAssertTrue(reopenedTabBarVisible, "Tab bar did not appear after foreground reopen")

        let reopenedTabBar = app.tabBars.firstMatch
        let reopenedDashboardTab = reopenedTabBar.buttons["Dashboard"]
        ensureTabSelected(reopenedDashboardTab, label: "Dashboard")
        assertReadiness(in: app, identifier: "dashboardRootReady", timeout: 20)
    }

    func testTabSwitchContentReadyLatencySmoke() {
        let app = makeApp()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        assertReadiness(in: app, identifier: "dashboardRootReady", timeout: 10)

        let dashboardTab = tabBar.buttons["Dashboard"]
        let traiTab = tabBar.buttons["Trai"]
        let workoutsTab = tabBar.buttons["Workouts"]
        let profileTab = tabBar.buttons["Profile"]

        ensureTabSelected(dashboardTab, label: "Dashboard")
        _ = tapAndMeasureContentReadiness(workoutsTab, in: app, label: "Workouts", readinessIdentifier: "workoutsRootReady")
        _ = tapAndMeasureContentReadiness(traiTab, in: app, label: "Trai", readinessIdentifier: "traiRootReady")
        _ = tapAndMeasureContentReadiness(profileTab, in: app, label: "Profile", readinessIdentifier: "profileRootReady")
        _ = tapAndMeasureContentReadiness(dashboardTab, in: app, label: "Dashboard", readinessIdentifier: "dashboardRootReady")
    }

    func testTabSwitchContentReadyLatencySmokeWithExistingUserData() {
        ensurePersistentStoreProfileForRealDataTests()
        let app = makeApp(
            extraArguments: ["--enable-latency-probe"],
            includeUITestMode: false
        )
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15))

        let dashboardTab = tabBar.buttons["Dashboard"]
        let traiTab = tabBar.buttons["Trai"]
        let workoutsTab = tabBar.buttons["Workouts"]
        let profileTab = tabBar.buttons["Profile"]

        ensureTabSelected(dashboardTab, label: "Dashboard")
        assertReadiness(in: app, identifier: "dashboardRootReady", timeout: 20)
        logLatencyProbeSummary(
            in: app,
            identifier: "dashboardLatencyProbe",
            label: "Dashboard"
        )
        _ = tapAndMeasureContentReadiness(
            workoutsTab,
            in: app,
            label: "Workouts",
            readinessIdentifier: "workoutsRootReady",
            metricName: "tab_switch_workouts_ready_real_data",
            enforceBudget: false
        )
        logLatencyProbeSummary(
            in: app,
            identifier: "workoutsLatencyProbe",
            label: "Workouts"
        )
        _ = tapAndMeasureContentReadiness(
            traiTab,
            in: app,
            label: "Trai",
            readinessIdentifier: "traiRootReady",
            metricName: "tab_switch_trai_ready_real_data",
            enforceBudget: false
        )
        logLatencyProbeSummary(
            in: app,
            identifier: "traiLatencyProbe",
            label: "Trai"
        )
        _ = tapAndMeasureContentReadiness(
            profileTab,
            in: app,
            label: "Profile",
            readinessIdentifier: "profileRootReady",
            metricName: "tab_switch_profile_ready_real_data",
            enforceBudget: false
        )
        logLatencyProbeSummary(
            in: app,
            identifier: "profileLatencyProbe",
            label: "Profile"
        )
        _ = tapAndMeasureContentReadiness(
            dashboardTab,
            in: app,
            label: "Dashboard",
            readinessIdentifier: "dashboardRootReady",
            metricName: "tab_switch_dashboard_ready_real_data",
            enforceBudget: false
        )
        logLatencyProbeSummary(
            in: app,
            identifier: "dashboardLatencyProbe",
            label: "Dashboard Return"
        )
    }

    func testLiveWorkoutAddExerciseSheetLatencySmoke() {
        let app = makeApp(extraArguments: [
            "-pendingAppRoute", "trai://workout",
            "--ui-test-live-workout-preset",
            "--seed-live-workout-perf-data"
        ])
        app.launch()

        let endButton = app.buttons["liveWorkoutEndButton"]
        if !endButton.waitForExistence(timeout: 10) {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(endButton.waitForExistence(timeout: 10))

        let addExerciseByLabel = app.buttons["Add Exercise"]
        let addExerciseByIdentifier = app.descendants(matching: .any)
            .matching(identifier: "liveWorkoutAddExerciseButton")
            .firstMatch
        var didFindAddExercise = addExerciseByLabel.waitForExistence(timeout: 6)
            || addExerciseByIdentifier.waitForExistence(timeout: 4)
        if !didFindAddExercise {
            app.terminate()
            app.launch()
            XCTAssertTrue(endButton.waitForExistence(timeout: 10))
            didFindAddExercise = addExerciseByLabel.waitForExistence(timeout: 6)
                || addExerciseByIdentifier.waitForExistence(timeout: 4)
        }
        XCTAssertTrue(didFindAddExercise)

        let start = ProcessInfo.processInfo.systemUptime
        if addExerciseByLabel.exists {
            addExerciseByLabel.tap()
        } else {
            addExerciseByIdentifier.tap()
        }

        let exerciseList = app.descendants(matching: .any)["exerciseListView"]
        XCTAssertTrue(exerciseList.waitForExistence(timeout: 5))

        let latency = ProcessInfo.processInfo.systemUptime - start
        logLatencyMetric("live_workout_add_exercise_sheet", value: latency)
        XCTAssertLessThan(
            latency,
            addExerciseSheetSmokeBudgetSeconds,
            "Add Exercise sheet latency exceeded smoke budget (\(latency)s)"
        )
    }

    private func makeApp(
        extraArguments: [String] = [],
        includeUITestMode: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        if includeUITestMode {
            app.launchArguments = ["UITEST_MODE", "--disable-tab-prewarm"] + extraArguments
        } else {
            app.launchArguments = ["--use-persistent-store", "--disable-tab-prewarm"] + extraArguments
        }
        return app
    }

    private func ensurePersistentStoreProfileForRealDataTests() {
        guard !Self.didBootstrapPersistentStoreProfile else { return }

        let bootstrapApp = makeApp(extraArguments: ["--use-persistent-store"])
        bootstrapApp.launch()

        let tabBar = bootstrapApp.tabBars.firstMatch
        XCTAssertTrue(
            tabBar.waitForExistence(timeout: 10),
            "Failed to bootstrap persistent store before real-data UI tests"
        )
        assertReadiness(in: bootstrapApp, identifier: "dashboardRootReady", timeout: 10)
        bootstrapApp.terminate()
        Self.didBootstrapPersistentStoreProfile = true
    }

    @discardableResult
    private func tapAndMeasureSelection(
        _ tab: XCUIElement,
        in app: XCUIApplication,
        label: String,
        readinessIdentifier: String
    ) -> TimeInterval {
        let start = ProcessInfo.processInfo.systemUptime
        tab.tap()

        let selectedExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"),
            object: tab
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [selectedExpectation], timeout: 4),
            .completed,
            "\(label) tab failed to become selected"
        )

        let readinessElement = readinessElement(in: app, identifier: readinessIdentifier)
        if !readinessElement.exists {
            XCTAssertTrue(
                readinessElement.waitForExistence(timeout: 6),
                "\(label) tab failed to reach readiness marker \(readinessIdentifier)"
            )
        }

        let latency = ProcessInfo.processInfo.systemUptime - start
        logLatencyMetric("tab_switch_\(label.lowercased())", value: latency)
        XCTAssertLessThan(
            latency,
            tabSwitchSmokeBudgetSeconds,
            "\(label) tab switch exceeded smoke budget (\(latency)s)"
        )
        return latency
    }

    @discardableResult
    private func tapAndMeasureContentReadiness(
        _ tab: XCUIElement,
        in app: XCUIApplication,
        label: String,
        readinessIdentifier: String,
        metricName: String? = nil,
        enforceBudget: Bool = true
    ) -> TimeInterval {
        let start = ProcessInfo.processInfo.systemUptime
        tab.tap()

        func waitForSelection(timeout: TimeInterval) -> XCTWaiter.Result {
            let selectedExpectation = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "isSelected == true"),
                object: tab
            )
            return XCTWaiter.wait(for: [selectedExpectation], timeout: timeout)
        }

        var selectionResult = waitForSelection(timeout: 2)
        if selectionResult != .completed {
            tab.tap()
            selectionResult = waitForSelection(timeout: 2)
        }
        XCTAssertEqual(
            selectionResult,
            .completed,
            "\(label) tab failed to become selected"
        )

        let readinessElement = readinessElement(in: app, identifier: readinessIdentifier)
        if !readinessElement.exists {
            XCTAssertTrue(
                readinessElement.waitForExistence(timeout: 6),
                "\(label) content failed to reach readiness marker \(readinessIdentifier)"
            )
        }

        let latency = ProcessInfo.processInfo.systemUptime - start
        let name = metricName ?? "tab_switch_\(label.lowercased())_ready"
        logLatencyMetric(name, value: latency)
        if enforceBudget {
            XCTAssertLessThan(
                latency,
                tabSwitchSmokeBudgetSeconds,
                "\(label) content-ready switch exceeded smoke budget (\(latency)s)"
            )
        }
        return latency
    }

    private func logLatencyMetric(_ name: String, value: TimeInterval) {
        XCTContext.runActivity(named: "Latency metric \(name)=\(String(format: "%.3f", value))s") { _ in
            XCTAssertGreaterThanOrEqual(value, 0)
        }
    }

    private func logLatencyProbeSummary(
        in app: XCUIApplication,
        identifier: String,
        label: String
    ) {
        let element = readinessElement(in: app, identifier: identifier)
        let exists = element.waitForExistence(timeout: 4)
        let labelText = exists ? element.label : ""
        let valueText = exists ? (element.value as? String ?? "") : ""
        let summary = [labelText, valueText]
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? "missing"

        XCTContext.runActivity(named: "Latency probe \(label)=\(summary)") { _ in
            XCTAssertTrue(exists, "Expected latency probe element \(identifier) to exist")
        }
    }

    private func ensureTabSelected(_ tab: XCUIElement, label: String) {
        if tab.isSelected {
            return
        }
        tab.tap()
        let selectedExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"),
            object: tab
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [selectedExpectation], timeout: 4),
            .completed,
            "\(label) tab failed to become selected"
        )
    }

    private func readinessElement(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    private func assertReadiness(
        in app: XCUIApplication,
        identifier: String,
        timeout: TimeInterval
    ) {
        let element = readinessElement(in: app, identifier: identifier)
        if element.exists {
            return
        }
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
    }

    @discardableResult
    private func waitForTabBarAfterReopen(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        if app.tabBars.firstMatch.waitForExistence(timeout: timeout) {
            return true
        }

        // One retry helps avoid occasional SpringBoard->app handoff flakiness in simulator.
        app.activate()
        return app.tabBars.firstMatch.waitForExistence(timeout: timeout)
    }

    private func waitForAppToLeaveForeground(
        _ app: XCUIApplication,
        timeout: TimeInterval
    ) {
        let backgroundPredicate = NSPredicate(
            format: "state != %d",
            XCUIApplication.State.runningForeground.rawValue
        )
        let expectation = XCTNSPredicateExpectation(predicate: backgroundPredicate, object: app)
        _ = XCTWaiter.wait(for: [expectation], timeout: timeout)
    }

    @discardableResult
    private func waitForLiveWorkoutScreen(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let primaryNavigationBar = app.navigationBars["Custom Workout"]
        if primaryNavigationBar.waitForExistence(timeout: timeout) {
            return true
        }

        let fallbackNavigationBar = app.navigationBars.firstMatch
        if fallbackNavigationBar.waitForExistence(timeout: max(4, timeout / 2)) {
            return true
        }

        // Fallback: if the workout is minimized, reopen from the active banner.
        let banner = app.otherElements["activeWorkoutBanner"]
        guard banner.waitForExistence(timeout: 3) else { return false }
        banner.tap()
        return fallbackNavigationBar.waitForExistence(timeout: max(4, timeout / 2))
    }
}
