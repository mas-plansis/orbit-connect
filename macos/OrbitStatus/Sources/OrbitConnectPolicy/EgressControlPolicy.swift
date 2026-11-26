import Foundation

public enum EgressControlTrustState: String, Codable, Sendable {
    case disabled
    case verifying
    case trusted
    case blocked
}

public enum EgressControlDecision: Equatable, Sendable {
    case allow
    case drop(reason: String)
}

public enum ApplicationRouteMode: String, Codable, CaseIterable, Sendable {
    case direct
    case trustedExit
    case orbitSOCKS
    case blocked
}

public struct ProtectedApplication: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var bundleIdentifier: String
    public var displayName: String
    public var routeMode: ApplicationRouteMode

    public init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        displayName: String,
        routeMode: ApplicationRouteMode = .trustedExit
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.routeMode = routeMode
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case bundleIdentifier
        case displayName
        case routeMode
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        bundleIdentifier = try values.decode(String.self, forKey: .bundleIdentifier)
        displayName = try values.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        routeMode = try values.decodeIfPresent(ApplicationRouteMode.self, forKey: .routeMode)
            ?? .trustedExit
    }
}

public struct ProtectedDestination: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var value: String

    public init(id: UUID = UUID(), value: String) {
        self.id = id
        self.value = value
    }
}

public struct EgressControlConfiguration: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var expectedFinalAddresses: [String]
    public var applications: [ProtectedApplication]
    public var destinations: [ProtectedDestination]
    public var confirmationLifetime: TimeInterval

    public init(
        isEnabled: Bool = false,
        expectedFinalAddresses: [String] = [],
        applications: [ProtectedApplication] = [],
        destinations: [ProtectedDestination] = [],
        confirmationLifetime: TimeInterval = 12
    ) {
        self.isEnabled = isEnabled
        self.expectedFinalAddresses = expectedFinalAddresses
        self.applications = applications
        self.destinations = destinations
        self.confirmationLifetime = confirmationLifetime
    }

    public var normalized: EgressControlConfiguration {
        var copy = self
        // The home Orbit is the only source of trust for the final address.
        // Keep the array in the persisted schema for backward compatibility,
        // but never allow more than one active trust anchor.
        copy.expectedFinalAddresses = Array(
            uniqueNormalized(expectedFinalAddresses).prefix(1)
        )
        copy.applications = applications.reduce(into: []) { result, application in
            let identifier = normalize(application.bundleIdentifier)
            guard !identifier.isEmpty,
                  !result.contains(where: { $0.bundleIdentifier == identifier })
            else { return }
            result.append(
                ProtectedApplication(
                    id: application.id,
                    bundleIdentifier: identifier,
                    displayName: application.displayName.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    routeMode: application.routeMode
                )
            )
        }
        copy.destinations = destinations.reduce(into: []) { result, destination in
            let value = normalize(destination.value)
            guard !value.isEmpty,
                  !result.contains(where: { $0.value == value })
            else { return }
            result.append(ProtectedDestination(id: destination.id, value: value))
        }
        copy.confirmationLifetime = min(max(confirmationLifetime, 6), 30)
        return copy
    }
}

public struct EgressTrustSnapshot: Codable, Equatable, Sendable {
    public var state: EgressControlTrustState
    public var finalAddress: String?
    public var confirmedAt: Date?
    public var reason: String

    public init(
        state: EgressControlTrustState,
        finalAddress: String? = nil,
        confirmedAt: Date? = nil,
        reason: String = ""
    ) {
        self.state = state
        self.finalAddress = finalAddress
        self.confirmedAt = confirmedAt
        self.reason = reason
    }

    public static let disabled = EgressTrustSnapshot(state: .disabled)
}

public struct EgressFlowDescriptor: Equatable, Sendable {
    public var sourceApplicationIdentifier: String?
    public var remoteHost: String?

    public init(
        sourceApplicationIdentifier: String?,
        remoteHost: String?
    ) {
        self.sourceApplicationIdentifier = sourceApplicationIdentifier
        self.remoteHost = remoteHost
    }
}

public struct EgressFlowEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var applicationIdentifier: String
    public var remoteHost: String
    public var routeMode: ApplicationRouteMode
    public var allowed: Bool
    public var reason: String
    public var observedAt: Date

    public init(
        id: UUID = UUID(),
        applicationIdentifier: String,
        remoteHost: String,
        routeMode: ApplicationRouteMode,
        allowed: Bool,
        reason: String,
        observedAt: Date = Date()
    ) {
        self.id = id
        self.applicationIdentifier = applicationIdentifier
        self.remoteHost = remoteHost
        self.routeMode = routeMode
        self.allowed = allowed
        self.reason = reason
        self.observedAt = observedAt
    }
}

public enum EgressControlEvaluator {
    public static func decision(
        configuration: EgressControlConfiguration,
        snapshot: EgressTrustSnapshot,
        flow: EgressFlowDescriptor,
        now: Date = Date()
    ) -> EgressControlDecision {
        let configuration = configuration.normalized
        guard configuration.isEnabled else { return .allow }
        let routeMode = routeMode(configuration: configuration, flow: flow)
        guard let routeMode else { return .allow }
        if routeMode == .direct { return .allow }
        if routeMode == .blocked { return .drop(reason: "Приложение заблокировано правилом") }
        if routeMode == .orbitSOCKS {
            return .drop(reason: "Транспорт Orbit SOCKS ещё не установлен")
        }
        guard snapshot.state == .trusted else {
            return .drop(reason: snapshot.reason.isEmpty ? "Выход не подтверждён" : snapshot.reason)
        }
        guard let confirmedAt = snapshot.confirmedAt,
              now.timeIntervalSince(confirmedAt) <= configuration.confirmationLifetime
        else {
            return .drop(reason: "Подтверждение выхода устарело")
        }
        guard let finalAddress = snapshot.finalAddress.map(normalize),
              configuration.expectedFinalAddresses.contains(finalAddress)
        else {
            return .drop(reason: "Конечный адрес не совпадает с доверенным")
        }
        return .allow
    }

    public static func isProtected(
        configuration: EgressControlConfiguration,
        flow: EgressFlowDescriptor
    ) -> Bool {
        routeMode(configuration: configuration, flow: flow) != nil
    }

    public static func routeMode(
        configuration: EgressControlConfiguration,
        flow: EgressFlowDescriptor
    ) -> ApplicationRouteMode? {
        let applicationIdentifier = flow.sourceApplicationIdentifier.map(normalize)
        if let applicationIdentifier,
           let application = configuration.applications.first(where: {
               let configuredIdentifier = normalize($0.bundleIdentifier)
               return applicationIdentifier == configuredIdentifier
                   || applicationIdentifier.hasPrefix(configuredIdentifier + ".")
           }) {
            return application.routeMode
        }
        guard let remoteHost = flow.remoteHost.map(normalize), !remoteHost.isEmpty else {
            return configuration.destinations.isEmpty ? nil : .trustedExit
        }
        return configuration.destinations.contains {
            destinationMatches(rule: normalize($0.value), host: remoteHost)
        } ? .trustedExit : nil
    }

    private static func destinationMatches(rule: String, host: String) -> Bool {
        guard !rule.isEmpty else { return false }
        if rule.hasPrefix("*.") {
            let suffix = String(rule.dropFirst())
            return host.hasSuffix(suffix) && host.count > suffix.count
        }
        if let cidr = IPv4CIDR(rule) {
            return cidr.contains(host)
        }
        return host == rule || host.hasSuffix("." + rule)
    }
}

public final class EgressControlStore: @unchecked Sendable {
    public static let appGroupIdentifier = "group.io.orbit.connect"
    public static let developmentSuiteIdentifier = "io.orbit.connect.development"
    public static let configurationKey = "egress-control.configuration"
    public static let snapshotKey = "egress-control.snapshot"
    public static let flowEventsKey = "egress-control.flow-events"
    public static let trafficDiscoveryKey = "egress-control.traffic-discovery"
    public static let maximumFlowEvents = 80

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults? = nil) {
        if let defaults {
            self.defaults = defaults
        } else if ProcessInfo.processInfo.environment["ORBIT_CONNECT_DEVELOPMENT"] == "1"
            || Bundle.main.bundleIdentifier == "io.orbit.status.development"
        {
            self.defaults = UserDefaults(suiteName: Self.developmentSuiteIdentifier) ?? .standard
        } else {
            self.defaults = UserDefaults(suiteName: Self.appGroupIdentifier) ?? .standard
        }
    }

    public func loadConfiguration() -> EgressControlConfiguration {
        defaults.synchronize()
        return decode(EgressControlConfiguration.self, forKey: Self.configurationKey)
            ?? EgressControlConfiguration()
    }

    public func saveConfiguration(_ configuration: EgressControlConfiguration) throws {
        try encode(configuration.normalized, forKey: Self.configurationKey)
    }

    public func loadSnapshot() -> EgressTrustSnapshot {
        defaults.synchronize()
        return decode(EgressTrustSnapshot.self, forKey: Self.snapshotKey) ?? .disabled
    }

    public func saveSnapshot(_ snapshot: EgressTrustSnapshot) throws {
        try encode(snapshot, forKey: Self.snapshotKey)
    }

    public func resetSnapshot(reason: String) throws {
        try saveSnapshot(
            EgressTrustSnapshot(
                state: .blocked,
                reason: reason
            )
        )
    }

    public func loadFlowEvents() -> [EgressFlowEvent] {
        defaults.synchronize()
        return decode([EgressFlowEvent].self, forKey: Self.flowEventsKey) ?? []
    }

    public func recordFlowEvent(_ event: EgressFlowEvent) throws {
        var events = loadFlowEvents()
        events.removeAll {
            $0.applicationIdentifier == event.applicationIdentifier
                && $0.remoteHost == event.remoteHost
                && $0.routeMode == event.routeMode
                && $0.allowed == event.allowed
        }
        events.insert(event, at: 0)
        try encode(Array(events.prefix(Self.maximumFlowEvents)), forKey: Self.flowEventsKey)
    }

    public func isTrafficDiscoveryEnabled() -> Bool {
        defaults.synchronize()
        return defaults.bool(forKey: Self.trafficDiscoveryKey)
    }

    public func setTrafficDiscoveryEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.trafficDiscoveryKey)
        defaults.synchronize()
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) throws {
        defaults.set(try encoder.encode(value), forKey: key)
        defaults.synchronize()
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}

private func normalize(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        .lowercased()
}

private func uniqueNormalized(_ values: [String]) -> [String] {
    values.reduce(into: []) { result, value in
        let value = normalize(value)
        guard !value.isEmpty, !result.contains(value) else { return }
        result.append(value)
    }
}

private struct IPv4CIDR {
    let network: UInt32
    let mask: UInt32

    init?(_ value: String) {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let address = Self.address(String(parts[0])),
              let prefix = Int(parts[1]),
              (0 ... 32).contains(prefix)
        else { return nil }
        mask = prefix == 0 ? 0 : UInt32.max << UInt32(32 - prefix)
        network = address & mask
    }

    func contains(_ value: String) -> Bool {
        guard let address = Self.address(value) else { return false }
        return address & mask == network
    }

    private static func address(_ value: String) -> UInt32? {
        let octets = value.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return nil }
        var address = UInt32(0)
        for octet in octets {
            guard let value = UInt8(octet) else { return nil }
            address = (address << 8) | UInt32(value)
        }
        return address
    }
}
