import Darwin
import Foundation

struct PairResponse: Decodable {
    let token: String
    let device: String
}

struct ConnectUpdate {
    let version: String
    let downloadURL: URL
    let checksumURL: URL
    let assetName: String
}

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let assets: [Asset]
}

private struct OrbitHealth: Decodable {
    let orbitVersion: String

    enum CodingKeys: String, CodingKey {
        case orbitVersion = "orbit_version"
    }
}

struct ClientStatus: Decodable {
    let device: String
    let usingOrbit: Bool
    let macChanged: Bool
    let finalIP: String?
    let countryCode: String?
    let chain: [String]
    let routeSteps: [ClientRouteStep]?
    let checkedAt: Date?
    let statusDetail: String?
    let staticExitEnabled: Bool?
    let staticExitBlocked: Bool?
    let staticExitError: String?
    let trafficBlocked: Bool?

    enum CodingKeys: String, CodingKey {
        case device
        case usingOrbit = "using_orbit"
        case macChanged = "mac_changed"
        case finalIP = "final_ip"
        case countryCode = "country_code"
        case chain
        case routeSteps = "route_steps"
        case checkedAt = "checked_at"
        case statusDetail = "status_detail"
        case staticExitEnabled = "static_exit_enabled"
        case staticExitBlocked = "static_exit_blocked"
        case staticExitError = "static_exit_error"
        case trafficBlocked = "traffic_blocked"
    }
}

struct ClientRouteStep: Decodable {
    let role: String
    let label: String
    let server: String?
    let `protocol`: String?
    let ip: String?
    let countryCode: String?

    enum CodingKeys: String, CodingKey {
        case role
        case label
        case server
        case `protocol`
        case ip
        case countryCode = "country_code"
    }
}

extension ClientStatus {
    static let developmentDemo = ClientStatus(
        device: "Тестовый MacBook",
        usingOrbit: true,
        macChanged: false,
        finalIP: "203.0.113.42",
        countryCode: nil,
        chain: [],
        routeSteps: [
            ClientRouteStep(
                role: "device",
                label: "Устройство",
                server: nil,
                protocol: nil,
                ip: nil,
                countryCode: nil
            ),
            ClientRouteStep(
                role: "primary",
                label: "Основной выход",
                server: "primary.example:443",
                protocol: "VLESS",
                ip: "198.51.100.10",
                countryCode: nil
            ),
            ClientRouteStep(
                role: "static_exit",
                label: "Статический выход",
                server: "exit.example:443",
                protocol: "Trojan",
                ip: "203.0.113.42",
                countryCode: nil
            ),
            ClientRouteStep(
                role: "internet",
                label: "Интернет",
                server: nil,
                protocol: nil,
                ip: nil,
                countryCode: nil
            ),
        ],
        checkedAt: Date(),
        statusDetail: "Демонстрационный маршрут подтверждён",
        staticExitEnabled: true,
        staticExitBlocked: false,
        staticExitError: nil,
        trafficBlocked: false
    )
}

enum OrbitAPIError: LocalizedError {
    case invalidAddress
    case notFound
    case rejected(String)
    case invalidResponse
    case updateUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Проверьте адрес Orbit"
        case .notFound:
            return "Orbit не найден в локальной сети"
        case let .rejected(message):
            return message
        case .invalidResponse:
            return "Orbit вернул неожиданный ответ"
        case .updateUnavailable:
            return "Не удалось проверить обновления Orbit Connect"
        }
    }
}

struct OrbitAPIClient {
    static let connectReleaseURLs = [
        URL(string: "https://api.github.com/repos/mas-plansis/orbit-connect/releases?per_page=20")!,
        URL(string: "https://api.github.com/repos/mas-plansis/orbit/releases?per_page=20")!,
    ]

    private let session: URLSession

    private static let publicIPAddressURLs = [
        URL(string: "https://1.1.1.1/cdn-cgi/trace")!,
        URL(string: "https://api.ipify.org")!,
    ]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func discover(preferredURL: String?) async throws -> String {
        for candidate in Self.discoveryCandidates(preferredURL: preferredURL) {
            guard let url = URL(string: candidate + "/api/v1/health") else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 2
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            do {
                let health: OrbitHealth = try await perform(request)
                if !health.orbitVersion.isEmpty {
                    return candidate
                }
            } catch {
                continue
            }
        }
        throw OrbitAPIError.notFound
    }

    func keeneticURL(preferredURL: String?) -> URL? {
        if let gateway = Self.defaultGateway() {
            return URL(string: "http://\(gateway)")
        }
        return nil
    }

    func pair(baseURL: String, key: String) async throws -> PairResponse {
        var request = try request(baseURL: baseURL, path: "/api/v1/client/pair")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["key": key])
        return try await perform(request)
    }

    func status(baseURL: String, token: String) async throws -> ClientStatus {
        var request = try request(baseURL: baseURL, path: "/api/v1/client/status")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    func currentPublicIPAddress() async throws -> String {
        for url in Self.publicIPAddressURLs {
            var request = URLRequest(url: url)
            request.timeoutInterval = 4
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200 ... 299).contains(http.statusCode),
                      let body = String(data: data, encoding: .utf8),
                      let address = Self.publicIPAddress(from: body),
                      Self.isIPAddress(address)
                else { continue }
                return address
            } catch {
                continue
            }
        }
        throw OrbitAPIError.rejected("Не удалось подтвердить текущий конечный адрес")
    }

    static func publicIPAddress(from body: String) -> String? {
        let lines = body.split(whereSeparator: \.isNewline)
        if let line = lines.first(where: { $0.hasPrefix("ip=") }) {
            return String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return lines.first.map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func isIPAddress(_ value: String) -> Bool {
        var ipv4 = in_addr()
        if value.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            return true
        }
        var ipv6 = in6_addr()
        return value.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1
    }

    func rebind(baseURL: String, token: String) async throws -> ClientStatus {
        var request = try request(baseURL: baseURL, path: "/api/v1/client/rebind")
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    func revoke(baseURL: String, token: String) async throws {
        var request = try request(baseURL: baseURL, path: "/api/v1/client/link")
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OrbitAPIError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw OrbitAPIError.rejected("Orbit не смог удалить связь")
        }
    }

    func retryStaticExit(baseURL: String, token: String) async throws -> ClientStatus {
        var request = try request(baseURL: baseURL, path: "/api/v1/client/static-exit/retry")
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    func disableStaticExit(baseURL: String, token: String) async throws -> ClientStatus {
        var request = try request(baseURL: baseURL, path: "/api/v1/client/static-exit")
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    func latestConnectUpdate(currentVersion: String) async throws -> ConnectUpdate? {
        async let primary = connectReleases(
            at: Self.connectReleaseURLs[0],
            currentVersion: currentVersion
        )
        async let legacy = connectReleases(
            at: Self.connectReleaseURLs[1],
            currentVersion: currentVersion
        )
        let (primaryReleases, legacyReleases) = await (primary, legacy)
        guard primaryReleases != nil || legacyReleases != nil else {
            throw OrbitAPIError.updateUnavailable
        }
        let releases = (primaryReleases ?? []) + (legacyReleases ?? [])
        let prefix = "OrbitConnect_v"
        let suffix = ".zip"
        let updates = releases.flatMap { release -> [ConnectUpdate] in
            guard let checksum = release.assets.first(where: { $0.name == "SHA256SUMS" }) else {
                return []
            }
            return release.assets.compactMap { asset -> ConnectUpdate? in
                guard asset.name.hasPrefix(prefix), asset.name.hasSuffix(suffix) else {
                    return nil
                }
                let start = asset.name.index(asset.name.startIndex, offsetBy: prefix.count)
                let end = asset.name.index(asset.name.endIndex, offsetBy: -suffix.count)
                let version = String(asset.name[start ..< end])
                guard !version.isEmpty else { return nil }
                return ConnectUpdate(
                    version: version,
                    downloadURL: asset.browserDownloadURL,
                    checksumURL: checksum.browserDownloadURL,
                    assetName: asset.name
                )
            }
        }
        guard let newest = updates.max(by: {
            $0.version.compare($1.version, options: .numeric) == .orderedAscending
        }) else {
            return nil
        }
        guard newest.version.compare(currentVersion, options: .numeric) == .orderedDescending else {
            return nil
        }
        return newest
    }

    private func connectReleases(
        at url: URL,
        currentVersion: String
    ) async -> [GitHubRelease]? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("OrbitConnect/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        return try? await perform(request)
    }

    private func request(baseURL: String, path: String) throws -> URLRequest {
        let normalized = Self.normalizeBaseURL(baseURL)
        guard let url = URL(string: normalized + path) else {
            throw OrbitAPIError.invalidAddress
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        if let adapter = Self.activeAdapter() {
            request.setValue(adapter.id, forHTTPHeaderField: "X-Orbit-Adapter-ID")
            request.setValue(adapter.name, forHTTPHeaderField: "X-Orbit-Adapter-Name")
        }
        return request
    }

    private static func discoveryCandidates(preferredURL: String?) -> [String] {
        discoveryCandidates(preferredURL: preferredURL, gateway: defaultGateway())
    }

    static func discoveryCandidates(preferredURL: String?, gateway: String?) -> [String] {
        var candidates: [String] = []
        func append(_ value: String?) {
            guard let value else { return }
            let normalized = normalizeBaseURL(value)
            guard !normalized.isEmpty, !candidates.contains(normalized) else { return }
            candidates.append(normalized)
        }

        guard let gateway, isIPv4Address(gateway) else { return candidates }
        if let preferredURL,
           let components = URLComponents(string: normalizeBaseURL(preferredURL)),
           components.scheme == "http",
           components.host == gateway,
           components.user == nil,
           components.password == nil,
           components.path.isEmpty || components.path == "/",
           components.query == nil,
           components.fragment == nil
        {
            append(preferredURL)
        }
        append("http://\(gateway):3000")
        return candidates
    }

    private static func isIPv4Address(_ value: String) -> Bool {
        var address = in_addr()
        return value.withCString { inet_pton(AF_INET, $0, &address) == 1 }
    }

    private static func normalizeBaseURL(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func defaultGateway() -> String? {
        defaultRouteValue(named: "gateway")
    }

    private static func activeAdapter() -> (id: String, name: String)? {
        guard let interface = defaultRouteValue(named: "interface"), !interface.isEmpty else {
            return nil
        }
        let name = interface == "en0" ? "Wi-Fi" : interface
        return (id: "macos:\(interface)", name: name)
    }

    private static func defaultRouteValue(named key: String) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "default"]
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if parts.count == 2, parts[0] == key, !parts[1].isEmpty {
                return parts[1]
            }
        }
        return nil
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OrbitAPIError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            if let value = try? JSONDecoder().decode([String: String].self, from: data),
               let message = value["error"]
            {
                throw OrbitAPIError.rejected(message)
            }
            throw OrbitAPIError.rejected("Orbit отклонил запрос")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            for formatter in Self.dateFormatters {
                if let date = formatter.date(from: value) {
                    return date
                }
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported ISO 8601 date: \(value)"
            )
        }
        return try decoder.decode(Response.self, from: data)
    }

    private static let dateFormatters: [ISO8601DateFormatter] = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return [fractional, standard]
    }()
}
