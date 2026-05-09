//
//  AppRoute.swift
//  Shared
//
//  Canonical app-entry routes shared by app, intents, and widgets.
//

import Foundation

enum AppRoute: Equatable, Codable {
    case logFood
    case logWeight
    case workout(templateName: String?)
    case chat

    static let scheme = "trai"
    private static let workoutTemplateQueryName = "template"

    static var appURL: URL {
        URL(string: "\(scheme)://")!
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme

        switch self {
        case .logFood:
            components.host = "logfood"
        case .logWeight:
            components.host = "logweight"
        case .workout(let templateName):
            components.host = "workout"
            if let templateName, !templateName.isEmpty {
                components.queryItems = [URLQueryItem(name: Self.workoutTemplateQueryName, value: templateName)]
            }
        case .chat:
            components.host = "chat"
        }

        return components.url ?? Self.appURL
    }

    var urlString: String {
        url.absoluteString
    }

    init?(urlString: String) {
        guard let url = URL(string: urlString) else { return nil }
        self.init(url: url)
    }

    init?(url: URL) {
        guard url.scheme?.localizedCaseInsensitiveCompare(Self.scheme) == .orderedSame else {
            return nil
        }

        switch url.host?.lowercased() {
        case "logfood":
            self = .logFood
        case "logweight":
            self = .logWeight
        case "workout":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let templateName = components?.queryItems?
                .first(where: { $0.name == Self.workoutTemplateQueryName })?
                .value
            self = .workout(templateName: templateName)
        case "chat":
            self = .chat
        default:
            return nil
        }
    }
}

enum PendingAppRouteStore {
    static func setPendingRoute(_ route: AppRoute, defaults: UserDefaults = .standard) {
        defaults.set(route.urlString, forKey: SharedStorageKeys.AppRouting.pendingRoute)
    }

    static func consumePendingRoute(defaults: UserDefaults = .standard) -> AppRoute? {
        if let route = consumePendingRouteValue(defaults: defaults) {
            return route
        }

        if defaults === UserDefaults.standard,
           let appGroupDefaults = UserDefaults(suiteName: SharedStorageKeys.AppGroup.suiteName),
           let route = consumePendingRouteValue(defaults: appGroupDefaults) {
            return route
        }

        // Backwards compatibility for pre-route payload versions.
        if defaults.bool(forKey: SharedStorageKeys.LegacyLaunchIntents.openFoodCamera) {
            defaults.removeObject(forKey: SharedStorageKeys.LegacyLaunchIntents.openFoodCamera)
            return .logFood
        }

        if let workoutName = defaults.string(forKey: SharedStorageKeys.LegacyLaunchIntents.startWorkout) {
            defaults.removeObject(forKey: SharedStorageKeys.LegacyLaunchIntents.startWorkout)
            return .workout(templateName: workoutName == "custom" ? nil : workoutName)
        }

        return nil
    }

    private static func consumePendingRouteValue(defaults: UserDefaults) -> AppRoute? {
        guard let routeString = defaults.string(forKey: SharedStorageKeys.AppRouting.pendingRoute) else {
            return nil
        }
        defaults.removeObject(forKey: SharedStorageKeys.AppRouting.pendingRoute)
        return AppRoute(urlString: routeString)
    }
}
