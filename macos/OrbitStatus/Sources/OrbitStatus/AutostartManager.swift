import Foundation
import ServiceManagement

enum AutostartManager {
    private static let configuredKey = "orbitConnect.autostartConfigured"
    private static let enabledKey = "orbitConnect.autostartEnabled"

    static var isEnabled: Bool {
        guard !OrbitRuntime.isDevelopment else { return false }
        return switch SMAppService.mainApp.status {
        case .enabled:
            true
        case .requiresApproval:
            OrbitRuntime.defaults.bool(forKey: enabledKey)
        default:
            false
        }
    }

    static func enableByDefaultIfNeeded() {
        guard !OrbitRuntime.isDevelopment else { return }
        let defaults = OrbitRuntime.defaults
        guard !defaults.bool(forKey: configuredKey) else { return }
        defaults.set(true, forKey: configuredKey)
        do {
            try setEnabled(true)
        } catch {
            defaults.set(false, forKey: enabledKey)
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard !OrbitRuntime.isDevelopment else { return }
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
        OrbitRuntime.defaults.set(enabled, forKey: enabledKey)
        OrbitRuntime.defaults.set(true, forKey: configuredKey)
    }
}
