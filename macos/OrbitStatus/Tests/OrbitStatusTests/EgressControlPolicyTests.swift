import Foundation
import OrbitConnectPolicy
import XCTest

final class EgressControlPolicyTests: XCTestCase {
    func testDisabledControlAllowsTraffic() {
        XCTAssertEqual(
            EgressControlEvaluator.decision(
                configuration: configuration(enabled: false),
                snapshot: blockedSnapshot(),
                flow: flow()
            ),
            .allow
        )
    }

    func testEnabledControlProtectsEveryFlow() {
        let configuration = configuration()
        XCTAssertTrue(
            EgressControlEvaluator.isProtected(
                configuration: configuration,
                flow: EgressFlowDescriptor(
                    sourceApplicationIdentifier: "com.example.browser",
                    remoteHost: "example.org"
                )
            )
        )
        XCTAssertTrue(
            EgressControlEvaluator.isProtected(
                configuration: configuration,
                flow: EgressFlowDescriptor(
                    sourceApplicationIdentifier: nil,
                    remoteHost: nil
                )
            )
        )
    }

    func testBlockedTrustBlocksEveryFlow() {
        XCTAssertEqual(
            EgressControlEvaluator.decision(
                configuration: configuration(),
                snapshot: blockedSnapshot(),
                flow: flow()
            ),
            .drop(reason: "Orbit недоступен")
        )
    }

    func testFreshMatchingTrustAllowsTraffic() {
        let now = Date()
        XCTAssertEqual(
            EgressControlEvaluator.decision(
                configuration: configuration(),
                snapshot: EgressTrustSnapshot(
                    state: .trusted,
                    finalAddress: "203.0.113.10",
                    confirmedAt: now
                ),
                flow: flow(),
                now: now.addingTimeInterval(5)
            ),
            .allow
        )
    }

    func testExpiredTrustBlocksTraffic() {
        let now = Date()
        XCTAssertEqual(
            EgressControlEvaluator.decision(
                configuration: configuration(),
                snapshot: EgressTrustSnapshot(
                    state: .trusted,
                    finalAddress: "203.0.113.10",
                    confirmedAt: now
                ),
                flow: flow(),
                now: now.addingTimeInterval(31)
            ),
            .drop(reason: "Подтверждение выхода устарело")
        )
    }

    func testDifferentFinalAddressBlocksTraffic() {
        let now = Date()
        XCTAssertEqual(
            EgressControlEvaluator.decision(
                configuration: configuration(),
                snapshot: EgressTrustSnapshot(
                    state: .trusted,
                    finalAddress: "198.51.100.20",
                    confirmedAt: now
                ),
                flow: flow(),
                now: now
            ),
            .drop(reason: "Конечный адрес не совпадает с доверенным")
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

    func testApplicationPathRoundTripsThroughJSON() throws {
        let application = ProtectedApplication(
            bundleIdentifier: "com.example.meeting",
            displayName: "Meeting",
            applicationPath: "/Applications/Meeting.app"
        )

        let data = try JSONEncoder().encode(application)
        let decoded = try JSONDecoder().decode(ProtectedApplication.self, from: data)

        XCTAssertEqual(decoded.applicationPath, "/Applications/Meeting.app")
    }

    func testLegacyApplicationWithoutPathRemainsDecodable() throws {
        let data = Data(
            #"{"id":"00000000-0000-0000-0000-000000000001","bundleIdentifier":"com.example.legacy","displayName":"Legacy","routeMode":"blocked"}"#.utf8
        )

        let application = try JSONDecoder().decode(ProtectedApplication.self, from: data)

        XCTAssertNil(application.applicationPath)
        XCTAssertEqual(application.routeMode, .blocked)
    }

    private func configuration(enabled: Bool = true) -> EgressControlConfiguration {
        EgressControlConfiguration(
            isEnabled: enabled,
            expectedFinalAddresses: ["203.0.113.10"],
            confirmationLifetime: 30
        )
    }

    private func flow() -> EgressFlowDescriptor {
        EgressFlowDescriptor(
            sourceApplicationIdentifier: "com.example.browser",
            remoteHost: "example.org"
        )
    }

    private func blockedSnapshot() -> EgressTrustSnapshot {
        EgressTrustSnapshot(state: .blocked, reason: "Orbit недоступен")
    }
}
