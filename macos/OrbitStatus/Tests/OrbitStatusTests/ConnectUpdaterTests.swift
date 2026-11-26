@testable import OrbitStatus
import Foundation
import XCTest

private final class ConnectUpdateURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: OrbitAPIError.invalidResponse)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class ConnectUpdaterTests: XCTestCase {
    override func tearDown() {
        ConnectUpdateURLProtocol.handler = nil
        super.tearDown()
    }

    func testTrafficPauseAlertIsShownOncePerBlockedEpisode() {
        var tracker = TrafficPauseAlertTracker()

        XCTAssertEqual(tracker.update(isBlocked: true), .present)
        tracker.didDismiss()
        XCTAssertEqual(tracker.update(isBlocked: true), .none)
        XCTAssertEqual(tracker.update(isBlocked: false), .none)
        XCTAssertEqual(tracker.update(isBlocked: true), .present)
    }

    func testTrafficPauseAlertIsDismissedAfterRecovery() {
        var tracker = TrafficPauseAlertTracker()

        XCTAssertEqual(tracker.update(isBlocked: true), .present)
        XCTAssertEqual(tracker.update(isBlocked: false), .dismiss)
        XCTAssertFalse(tracker.episodeAcknowledged)
        XCTAssertFalse(tracker.isPresented)
    }

    func testDiscoveryRetryScheduleUsesThreeAttemptsAndCappedBackoff() {
        var schedule = DiscoveryRetrySchedule()
        var now = Date(timeIntervalSince1970: 1_000)

        for expectedDelay in DiscoveryRetrySchedule.delays {
            XCTAssertNil(schedule.recordFailure(at: now))
            XCTAssertNil(schedule.recordFailure(at: now))
            XCTAssertEqual(schedule.recordFailure(at: now), expectedDelay)
            XCTAssertFalse(schedule.canAttempt(at: now))
            now = now.addingTimeInterval(expectedDelay)
            XCTAssertTrue(schedule.canAttempt(at: now))
        }

        XCTAssertNil(schedule.recordFailure(at: now))
        XCTAssertNil(schedule.recordFailure(at: now))
        XCTAssertEqual(schedule.recordFailure(at: now), 24 * 60 * 60)
    }

    func testDiscoveryRetryScheduleResetsForNewSessionOrNetwork() {
        var schedule = DiscoveryRetrySchedule()
        let now = Date(timeIntervalSince1970: 1_000)

        _ = schedule.recordFailure(at: now)
        _ = schedule.recordFailure(at: now)
        _ = schedule.recordFailure(at: now)
        schedule.reset()

        XCTAssertTrue(schedule.canAttempt(at: now))
        XCTAssertNil(schedule.retryAfter)
        XCTAssertEqual(schedule.attemptsInRound, 0)
        XCTAssertEqual(schedule.delayIndex, 0)
    }

    func testDiscoveryCandidatesStayOnActiveGateway() {
        XCTAssertEqual(
            OrbitAPIClient.discoveryCandidates(
                preferredURL: "http://192.168.50.1:3000/",
                gateway: "192.168.50.1"
            ),
            ["http://192.168.50.1:3000"]
        )
        XCTAssertEqual(
            OrbitAPIClient.discoveryCandidates(
                preferredURL: "http://192.168.1.1:3000",
                gateway: "192.168.50.1"
            ),
            ["http://192.168.50.1:3000"]
        )
        XCTAssertEqual(
            OrbitAPIClient.discoveryCandidates(preferredURL: "http://orbit.home", gateway: nil),
            []
        )
    }

    func testPublicIPAddressParsesPlainResponse() {
        XCTAssertEqual(
            OrbitAPIClient.publicIPAddress(from: "203.0.113.42\n"),
            "203.0.113.42"
        )
    }

    func testPublicIPAddressParsesCloudflareTrace() {
        XCTAssertEqual(
            OrbitAPIClient.publicIPAddress(
                from: "fl=123f1\nip=2001:db8::42\nts=123456\n"
            ),
            "2001:db8::42"
        )
    }

    func testChecksumUsesExactAssetName() throws {
        let expected = String(repeating: "a", count: 64)
        let text = """
        \(String(repeating: "b", count: 64))  other.zip
        \(expected)  OrbitConnect_v1.2.3.zip
        """

        XCTAssertEqual(
            try ConnectUpdater.checksum(in: text, filename: "OrbitConnect_v1.2.3.zip"),
            expected
        )
    }

    func testChecksumRejectsMissingAsset() {
        let text = "\(String(repeating: "a", count: 64))  other.zip\n"

        XCTAssertThrowsError(
            try ConnectUpdater.checksum(in: text, filename: "OrbitConnect_v1.2.3.zip")
        )
    }

    func testChecksumRejectsMalformedDigest() {
        let text = "\(String(repeating: "z", count: 64))  OrbitConnect_v1.2.3.zip\n"

        XCTAssertThrowsError(
            try ConnectUpdater.checksum(in: text, filename: "OrbitConnect_v1.2.3.zip")
        )
    }

    func testUpdateCheckFallsBackToLegacyRepository() async throws {
        let version = "9.8.7"
        ConnectUpdateURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            if url.path.contains("/orbit-connect/") {
                return (
                    try XCTUnwrap(HTTPURLResponse(
                        url: url,
                        statusCode: 503,
                        httpVersion: nil,
                        headerFields: nil
                    )),
                    Data()
                )
            }
            let release = [[
                "assets": [
                    [
                        "name": "OrbitConnect_v\(version).zip",
                        "browser_download_url": "https://github.com/mas-plansis/orbit/releases/download/connect-macos-v\(version)/OrbitConnect_v\(version).zip",
                    ],
                    [
                        "name": "SHA256SUMS",
                        "browser_download_url": "https://github.com/mas-plansis/orbit/releases/download/connect-macos-v\(version)/SHA256SUMS",
                    ],
                ],
            ]]
            return (
                try XCTUnwrap(HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )),
                try JSONSerialization.data(withJSONObject: release)
            )
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConnectUpdateURLProtocol.self]
        let client = OrbitAPIClient(session: URLSession(configuration: configuration))

        let update = try await client.latestConnectUpdate(currentVersion: "0.1.14")

        XCTAssertEqual(update?.version, version)
        XCTAssertEqual(update?.downloadURL.host, "github.com")
        XCTAssertTrue(update?.downloadURL.path.contains("/mas-plansis/orbit/") == true)
    }

    func testUpdaterAcceptsOnlyConnectReleaseRepositories() throws {
        for repository in ["orbit-connect", "orbit"] {
            let url = try XCTUnwrap(URL(
                string: "https://github.com/mas-plansis/\(repository)/releases/download/connect-macos-v1.2.3/OrbitConnect_v1.2.3.zip"
            ))
            XCTAssertNoThrow(try ConnectUpdater.validateSource(url))
        }

        for value in [
            "https://github.com/another/orbit-connect/releases/download/v1/file.zip",
            "https://github.com/mas-plansis/orbit-connect-malicious/releases/download/v1/file.zip",
            "https://github.com@evil.example/mas-plansis/orbit-connect/releases/download/v1/file.zip",
            "https://github.com/mas-plansis/orbit-connect/releases/download/v1/file.zip?redirect=1",
        ] {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertThrowsError(try ConnectUpdater.validateSource(url))
        }
    }

    func testDeferredReplacementMovesPreparedApplicationIntoPlace() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let current = root.appendingPathComponent("OrbitConnect.app", isDirectory: true)
        let stagedRoot = root.appendingPathComponent("update", isDirectory: true)
        let staged = stagedRoot.appendingPathComponent("OrbitConnect.app", isDirectory: true)
        let backup = root.appendingPathComponent(
            ".OrbitConnect-previous-test.app",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: current.appendingPathComponent("version"))
        try Data("new".utf8).write(to: staged.appendingPathComponent("version"))
        let plan = ConnectUpdateInstallationPlan(
            currentApplicationURL: current,
            stagedApplicationURL: staged,
            backupApplicationURL: backup,
            workDirectoryURL: stagedRoot,
            sourceProcessIdentifier: 0
        )

        try ConnectUpdater.replaceApplication(using: plan)

        XCTAssertEqual(
            try String(contentsOf: current.appendingPathComponent("version")),
            "new"
        )
        XCTAssertEqual(
            try String(contentsOf: backup.appendingPathComponent("version")),
            "old"
        )
    }

    func testDeferredReplacementRestoresCurrentApplicationWhenMoveFails() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let current = root.appendingPathComponent("OrbitConnect.app", isDirectory: true)
        let stagedRoot = root.appendingPathComponent("update", isDirectory: true)
        let staged = stagedRoot.appendingPathComponent("missing.app", isDirectory: true)
        let backup = root.appendingPathComponent(
            ".OrbitConnect-previous-test.app",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stagedRoot, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: current.appendingPathComponent("version"))
        let plan = ConnectUpdateInstallationPlan(
            currentApplicationURL: current,
            stagedApplicationURL: staged,
            backupApplicationURL: backup,
            workDirectoryURL: stagedRoot,
            sourceProcessIdentifier: 0
        )

        XCTAssertThrowsError(try ConnectUpdater.replaceApplication(using: plan))
        XCTAssertEqual(
            try String(contentsOf: current.appendingPathComponent("version")),
            "old"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
    }
}
