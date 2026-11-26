import Foundation
import OrbitConnectAgentProtocol
import XCTest

final class AgentPolicyTests: XCTestCase {
    func testDisabledPolicyDoesNotBlock() {
        XCTAssertEqual(
            OrbitConnectAgentPolicy(enabled: false).enforcement(),
            .disabled
        )
    }

    func testFreshMatchingAddressIsTrusted() {
        let now = Date()
        let policy = OrbitConnectAgentPolicy(
            enabled: true,
            expectedAddress: "203.0.113.10",
            observedAddress: " 203.0.113.10 ",
            trustedUntil: now.addingTimeInterval(12)
        )

        XCTAssertEqual(policy.enforcement(at: now), .trusted)
    }

    func testDifferentAddressIsBlocked() {
        let now = Date()
        let policy = OrbitConnectAgentPolicy(
            enabled: true,
            expectedAddress: "203.0.113.10",
            observedAddress: "198.51.100.20",
            trustedUntil: now.addingTimeInterval(12)
        )

        XCTAssertEqual(policy.enforcement(at: now), .blocked)
    }

    func testExpiredLeaseIsBlocked() {
        let now = Date()
        let policy = OrbitConnectAgentPolicy(
            enabled: true,
            expectedAddress: "203.0.113.10",
            observedAddress: "203.0.113.10",
            trustedUntil: now.addingTimeInterval(-1)
        )

        XCTAssertEqual(policy.enforcement(at: now), .blocked)
    }
}
