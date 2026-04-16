//
//  AppLaunchArguments.swift
//  Trai
//
//  Shared launch arguments used for app/runtime test behavior.
//

import Foundation

enum AppLaunchArguments {
    static let uiTestMode = "UITEST_MODE"
    static let pendingAppRoute = "-pendingAppRoute"
    static let seedLiveWorkoutPerfData = "--seed-live-workout-perf-data"
    static let uiTestLiveWorkoutPreset = "--ui-test-live-workout-preset"
    static let mockFoodAIResponses = "--ui-test-mock-food-ai"
    static let enableTabPrewarm = "--enable-tab-prewarm"
    static let disableTabPrewarm = "--disable-tab-prewarm"
    static let disableHeavyTabDeferral = "--disable-heavy-tab-deferral"
    static let enableLatencyProbe = "--enable-latency-probe"
    static let useInMemoryStore = "--use-in-memory-store"
    static let usePersistentStore = "--use-persistent-store"
    static let onboardingCompletedCacheKey = "hasCompletedOnboardingCached"
    private static let processStartupUptime = ProcessInfo.processInfo.systemUptime
    private static let startupSuppressedAnimationWindowSeconds: TimeInterval = 4

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestMode)
    }

    static var isRunningUnitTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        guard environment["XCTestConfigurationFilePath"] != nil else { return false }
        // UI tests launch the app as a separate process without test-bundle injection.
        return environment["XCInjectBundleInto"] != nil
    }

    static var isRunningTests: Bool {
        isUITesting || isRunningUnitTests
    }

    static var shouldUseInMemoryStore: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(usePersistentStore) {
            return false
        }
        if arguments.contains(useInMemoryStore) {
            return true
        }
        return isUITesting || isRunningUnitTests
    }

    static var shouldSeedLiveWorkoutPerfData: Bool {
        ProcessInfo.processInfo.arguments.contains(seedLiveWorkoutPerfData)
    }

    static var shouldUseLiveWorkoutUITestPreset: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestLiveWorkoutPreset)
    }

    static var shouldUseMockFoodAIResponses: Bool {
        ProcessInfo.processInfo.arguments.contains(mockFoodAIResponses)
    }

    static var shouldEnableTabPrewarm: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(disableTabPrewarm) {
            return false
        }
        if arguments.contains(enableTabPrewarm) {
            return true
        }
        // Enable by default so real users benefit from background tab warming.
        return true
    }

    static var shouldAggressivelyDeferHeavyTabWork: Bool {
        !isRunningTests && !ProcessInfo.processInfo.arguments.contains(disableHeavyTabDeferral)
    }

    static var shouldEnableLatencyProbe: Bool {
        ProcessInfo.processInfo.arguments.contains(enableLatencyProbe)
    }

    static var shouldSuppressStartupAnimations: Bool {
        if isUITesting {
            return true
        }
        return (ProcessInfo.processInfo.systemUptime - processStartupUptime) < startupSuppressedAnimationWindowSeconds
    }

    static var launchPendingRoute: AppRoute? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let routeFlagIndex = arguments.firstIndex(of: pendingAppRoute) else {
            return nil
        }
        let valueIndex = arguments.index(after: routeFlagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return nil
        }
        return AppRoute(urlString: arguments[valueIndex])
    }
}
