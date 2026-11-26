import AppKit
import CryptoKit
import Foundation

enum ConnectUpdateError: LocalizedError {
    case invalidSource
    case packageTooLarge
    case missingChecksum
    case checksumMismatch
    case invalidArchive
    case invalidApplication
    case unsupportedLocation
    case installationFailed

    var errorDescription: String? {
        switch self {
        case .invalidSource:
            "Источник обновления не прошёл проверку"
        case .packageTooLarge:
            "Пакет обновления слишком большой"
        case .missingChecksum:
            "В релизе отсутствует контрольная сумма пакета"
        case .checksumMismatch:
            "Контрольная сумма обновления не совпала"
        case .invalidArchive:
            "Архив обновления повреждён"
        case .invalidApplication:
            "Архив не содержит подходящую версию Orbit Connect"
        case .unsupportedLocation:
            "Переместите Orbit Connect в папку «Программы» и повторите обновление"
        case .installationFailed:
            "Не удалось заменить приложение. Текущая версия сохранена"
        }
    }
}

struct InstalledConnectUpdate {
    let applicationURL: URL
    let backupURL: URL
}

struct ConnectUpdater {
    private static let maximumPackageSize: Int64 = 128 * 1024 * 1024
    private static let maximumChecksumSize: Int64 = 1024 * 1024

    func install(_ update: ConnectUpdate) async throws -> InstalledConnectUpdate {
        try Self.validateSource(update.downloadURL)
        try Self.validateSource(update.checksumURL)

        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory
            .appendingPathComponent("orbit-connect-update-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: work) }

        let package = work.appendingPathComponent(update.assetName)
        let checksums = work.appendingPathComponent("SHA256SUMS")
        async let packageDownload: Void = Self.download(
            update.downloadURL,
            to: package,
            limit: Self.maximumPackageSize
        )
        async let checksumDownload: Void = Self.download(
            update.checksumURL,
            to: checksums,
            limit: Self.maximumChecksumSize
        )
        _ = try await (packageDownload, checksumDownload)

        let checksumText = try String(contentsOf: checksums, encoding: .utf8)
        let expected = try Self.checksum(in: checksumText, filename: update.assetName)
        let actual = try Self.sha256(package)
        guard expected == actual else { throw ConnectUpdateError.checksumMismatch }

        let extracted = work.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: extracted, withIntermediateDirectories: true)
        try Self.run("/usr/bin/ditto", arguments: ["-x", "-k", package.path, extracted.path])
        let candidate = try Self.application(in: extracted, version: update.version)
        try Self.rejectSymbolicLinks(in: candidate)
        try Self.run("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", candidate.path])

        return try Self.replaceCurrentApplication(with: candidate)
    }

    static func validateSource(_ url: URL) throws {
        let allowedPrefixes = [
            "/mas-plansis/orbit-connect/releases/download/",
            "/mas-plansis/orbit/releases/download/",
        ]
        guard url.scheme == "https",
              url.host == "github.com",
              url.user == nil,
              url.password == nil,
              url.port == nil,
              url.query == nil,
              url.fragment == nil,
              allowedPrefixes.contains(where: url.path.hasPrefix)
        else {
            throw ConnectUpdateError.invalidSource
        }
    }

    private static func download(_ url: URL, to destination: URL, limit: Int64) async throws {
        let (location, response) = try await URLSession.shared.download(from: url)
        let expected = response.expectedContentLength
        guard expected <= 0 || expected <= limit else {
            try? FileManager.default.removeItem(at: location)
            throw ConnectUpdateError.packageTooLarge
        }
        let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= limit else {
            try? FileManager.default.removeItem(at: location)
            throw ConnectUpdateError.packageTooLarge
        }
        try FileManager.default.moveItem(at: location, to: destination)
    }

    static func checksum(in content: String, filename: String) throws -> String {
        for line in content.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2 else { continue }
            let digest = String(parts[0]).lowercased()
            let candidate = String(parts[parts.count - 1]).trimmingCharacters(
                in: CharacterSet(charactersIn: "*")
            )
            guard candidate == filename,
                  digest.count == 64,
                  digest.allSatisfy({ $0.isHexDigit })
            else { continue }
            return digest
        }
        throw ConnectUpdateError.missingChecksum
    }

    private static func sha256(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var digest = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            digest.update(data: data)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func application(in directory: URL, version: String) throws -> URL {
        let fileManager = FileManager.default
        let candidates = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        guard candidates.count == 1,
              let candidate = candidates.first,
              candidate.pathExtension == "app",
              let bundle = Bundle(url: candidate),
              bundle.bundleIdentifier == "io.orbit.status",
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version,
              fileManager.isExecutableFile(
                  atPath: candidate.appendingPathComponent("Contents/MacOS/OrbitStatus").path
              )
        else {
            throw ConnectUpdateError.invalidApplication
        }
        return candidate
    }

    private static func rejectSymbolicLinks(in application: URL) throws {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: application,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in false }
        ) else {
            throw ConnectUpdateError.invalidApplication
        }
        for case let item as URL in enumerator {
            if try item.resourceValues(forKeys: Set(keys)).isSymbolicLink == true {
                throw ConnectUpdateError.invalidApplication
            }
        }
    }

    private static func replaceCurrentApplication(with candidate: URL) throws -> InstalledConnectUpdate {
        let fileManager = FileManager.default
        let current = Bundle.main.bundleURL.standardizedFileURL
        guard current.pathExtension == "app",
              !current.path.contains("/AppTranslocation/")
        else {
            throw ConnectUpdateError.unsupportedLocation
        }
        let parent = current.deletingLastPathComponent()
        let staged = parent.appendingPathComponent(".OrbitConnect-update-\(UUID().uuidString).app")
        let backup = parent.appendingPathComponent(".OrbitConnect-previous.app")
        do {
            try? fileManager.removeItem(at: staged)
            try fileManager.copyItem(at: candidate, to: staged)
            try? fileManager.removeItem(at: backup)
            try fileManager.moveItem(at: current, to: backup)
            do {
                try fileManager.moveItem(at: staged, to: current)
            } catch {
                try? fileManager.moveItem(at: backup, to: current)
                throw error
            }
        } catch {
            try? fileManager.removeItem(at: staged)
            throw ConnectUpdateError.installationFailed
        }
        return InstalledConnectUpdate(applicationURL: current, backupURL: backup)
    }

    private static func run(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ConnectUpdateError.invalidArchive
        }
        guard process.terminationStatus == 0 else {
            throw ConnectUpdateError.invalidArchive
        }
    }
}
