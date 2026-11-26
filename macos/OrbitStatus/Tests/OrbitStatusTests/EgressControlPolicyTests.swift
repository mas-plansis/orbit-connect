import Foundation
import OrbitConnectPolicy
import XCTest

final class EgressControlPolicyTests: XCTestCase {
    private let protectedApplication = ProtectedApplication(
        bundleIdentifier: "com.example.meeting",
        displayName: "Meeting"
    )

    func testDisabledControlAllowsProtectedApplication() {
        let decision = EgressControlEvaluator.decision(
            configuration: configuration(enabled: false),
            snapshot: blockedSnapshot(),
            flow: applicationFlow()
        )

        XCTAssertEqual(decision, .allow)
    }

    func testDisabledControlIgnoresEverySavedApplicationRule() {
        for routeMode in ApplicationRouteMode.allCases {
            var disabledConfiguration = configuration(enabled: false)
            disabledConfiguration.applications[0].routeMode = routeMode

            XCTAssertEqual(
                EgressControlEvaluator.decision(
                    configuration: disabledConfiguration,
                    snapshot: blockedSnapshot(),
                    flow: applicationFlow()
                ),
                .allow,
                "Master control must override saved \(routeMode) rules after Connect exits"
            )
        }
    }

    func testProtectedApplicationIsBlockedWithoutTrust() {
        let decision = EgressControlEvaluator.decision(
            configuration: configuration(),
            snapshot: blockedSnapshot(),
            flow: applicationFlow()
        )

        XCTAssertEqual(decision, .drop(reason: "Orbit недоступен"))
    }

    func testFreshMatchingTrustAllowsProtectedApplication() {
        let now = Date()
        let decision = EgressControlEvaluator.decision(
            configuration: configuration(),
            snapshot: EgressTrustSnapshot(
                state: .trusted,
                finalAddress: "203.0.113.10",
                confirmedAt: now,
                reason: "Маршрут подтверждён"
            ),
            flow: applicationFlow(),
            now: now.addingTimeInterval(5)
        )

        XCTAssertEqual(decision, .allow)
    }

    func testExpiredTrustIsBlocked() {
        let now = Date()
        let decision = EgressControlEvaluator.decision(
            configuration: configuration(),
            snapshot: EgressTrustSnapshot(
                state: .trusted,
                finalAddress: "203.0.113.10",
                confirmedAt: now,
                reason: "Маршрут подтверждён"
            ),
            flow: applicationFlow(),
            now: now.addingTimeInterval(13)
        )

        XCTAssertEqual(decision, .drop(reason: "Подтверждение выхода устарело"))
    }

    func testDifferentFinalAddressIsBlocked() {
        let now = Date()
        let decision = EgressControlEvaluator.decision(
            configuration: configuration(),
            snapshot: EgressTrustSnapshot(
                state: .trusted,
                finalAddress: "198.51.100.20",
                confirmedAt: now
            ),
            flow: applicationFlow(),
            now: now
        )

        XCTAssertEqual(decision, .drop(reason: "Конечный адрес не совпадает с доверенным"))
    }

    func testDomainAndSubdomainAreProtected() {
        let configuration = EgressControlConfiguration(
            isEnabled: true,
            expectedFinalAddresses: ["203.0.113.10"],
            destinations: [ProtectedDestination(value: "example.com")]
        )

        XCTAssertTrue(
            EgressControlEvaluator.isProtected(
                configuration: configuration,
                flow: EgressFlowDescriptor(
                    sourceApplicationIdentifier: nil,
                    remoteHost: "api.example.com"
                )
            )
        )
    }

    func testCIDRProtectsOnlyMatchingAddress() {
        let configuration = EgressControlConfiguration(
            isEnabled: true,
            expectedFinalAddresses: ["203.0.113.10"],
            destinations: [ProtectedDestination(value: "198.51.100.0/24")]
        )

        XCTAssertTrue(
            EgressControlEvaluator.isProtected(
                configuration: configuration,
                flow: EgressFlowDescriptor(
                    sourceApplicationIdentifier: nil,
                    remoteHost: "198.51.100.42"
                )
            )
        )
        XCTAssertFalse(
            EgressControlEvaluator.isProtected(
                configuration: configuration,
                flow: EgressFlowDescriptor(
                    sourceApplicationIdentifier: nil,
                    remoteHost: "198.51.101.42"
                )
            )
        )
    }

    func testUnprotectedFlowRemainsAvailableWhileControlIsBlocked() {
        let decision = EgressControlEvaluator.decision(
            configuration: configuration(),
            snapshot: blockedSnapshot(),
            flow: EgressFlowDescriptor(
                sourceApplicationIdentifier: "com.example.browser",
                remoteHost: "example.org"
            )
        )

        XCTAssertEqual(decision, .allow)
    }

    func testUnknownApplicationIdentityDoesNotInheritSelectedApplicationRule() {
        let decision = EgressControlEvaluator.decision(
            configuration: configuration(),
            snapshot: blockedSnapshot(),
            flow: EgressFlowDescriptor(
                sourceApplicationIdentifier: nil,
                remoteHost: nil
            )
        )

        XCTAssertEqual(decision, .allow)
    }

    func testHelperProcessOfProtectedApplicationIsProtected() {
        XCTAssertTrue(
            EgressControlEvaluator.isProtected(
                configuration: configuration(),
                flow: EgressFlowDescriptor(
                    sourceApplicationIdentifier: "com.example.meeting.helper.renderer",
                    remoteHost: "conference.example"
                )
            )
        )
    }

    func testSimilarBundleIdentifierIsNotTreatedAsHelper() {
        XCTAssertFalse(
            EgressControlEvaluator.isProtected(
                configuration: configuration(),
                flow: EgressFlowDescriptor(
                    sourceApplicationIdentifier: "com.example.meetingroom",
                    remoteHost: "conference.example"
                )
            )
        )
    }

    func testConfigurationKeepsOnlyOneTrustedFinalAddress() {
        let configuration = EgressControlConfiguration(
            expectedFinalAddresses: [
                " 203.0.113.10 ",
                "198.51.100.20",
                "203.0.113.10",
            ]
        ).normalized

        XCTAssertEqual(configuration.expectedFinalAddresses, ["203.0.113.10"])
    }

    func testDirectApplicationRemainsAvailableWithoutTrustedExit() {
        var configuration = configuration()
        configuration.applications[0].routeMode = .direct

        XCTAssertEqual(
            EgressControlEvaluator.decision(
                configuration: configuration,
                snapshot: blockedSnapshot(),
                flow: applicationFlow()
            ),
            .allow
        )
    }

    func testBlockedApplicationIsAlwaysDropped() {
        var configuration = configuration()
        configuration.applications[0].routeMode = .blocked

        XCTAssertEqual(
            EgressControlEvaluator.decision(
                configuration: configuration,
                snapshot: .disabled,
                flow: applicationFlow()
            ),
            .drop(reason: "Приложение заблокировано правилом")
        )
    }

    func testSOCKSApplicationFailsClosedUntilTransportIsInstalled() {
        var configuration = configuration()
        configuration.applications[0].routeMode = .orbitSOCKS

        XCTAssertEqual(
            EgressControlEvaluator.decision(
                configuration: configuration,
                snapshot: .disabled,
                flow: applicationFlow()
            ),
            .drop(reason: "Транспорт Orbit SOCKS ещё не установлен")
        )
    }

    func testLegacyApplicationDefaultsToTrustedExit() throws {
        let data = Data(
            #"{"id":"00000000-0000-0000-0000-000000000001","bundleIdentifier":"com.example.legacy","displayName":"Legacy"}"#.utf8
        )

        let application = try JSONDecoder().decode(ProtectedApplication.self, from: data)

        XCTAssertEqual(application.routeMode, .trustedExit)
    }

    private func configuration(enabled: Bool = true) -> EgressControlConfiguration {
        EgressControlConfiguration(
            isEnabled: enabled,
            expectedFinalAddresses: ["203.0.113.10"],
            applications: [protectedApplication],
            confirmationLifetime: 12
        )
    }

    private func applicationFlow() -> EgressFlowDescriptor {
        EgressFlowDescriptor(
            sourceApplicationIdentifier: protectedApplication.bundleIdentifier,
            remoteHost: "conference.example"
        )
    }

    private func blockedSnapshot() -> EgressTrustSnapshot {
        EgressTrustSnapshot(state: .blocked, reason: "Orbit недоступен")
    }
}
