import Foundation

enum OrbitRuntime {
    private static let developmentEnvironmentKey = "ORBIT_CONNECT_DEVELOPMENT"
    private static let demoEnvironmentKey = "ORBIT_CONNECT_DEMO"

    static let isDevelopment =
        ProcessInfo.processInfo.environment[developmentEnvironmentKey] == "1"
            || Bundle.main.bundleIdentifier == "io.orbit.status.development"

    static let isDemo = isDevelopment
        && (ProcessInfo.processInfo.environment[demoEnvironmentKey] == "1"
            || Bundle.main.object(forInfoDictionaryKey: "OrbitConnectDemoMode") as? Bool == true)

    static var defaults: UserDefaults {
        guard isDevelopment else { return .standard }
        return UserDefaults(suiteName: "io.orbit.status.development.preferences") ?? .standard
    }

    static var keychainService: String {
        isDevelopment ? "io.orbit.status.development" : "io.orbit.status"
    }

    static var applicationSupportDirectoryName: String {
        isDevelopment ? "Orbit Connect Development" : "Orbit Connect"
    }
}
