//
//  AppLaunchArguments.swift
//  Trai
//
//  Shared launch arguments used for app/runtime test behavior.
//

import Foundation

enum AppLaunchArguments {
    static let uiTestMode = "UITEST_MODE"

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestMode)
    }
}
