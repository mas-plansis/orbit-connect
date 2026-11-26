import AppKit
import CryptoKit
import Darwin
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

struct PreparedConnectUpdate {
    let installerURL: URL
    let planURL: URL
}

struct ConnectUpdateInstallationPlan: Codable {
    let currentApplicationURL: URL
    let stagedApplicationURL: URL
    let backupApplicationURL: URL
    let workDirectoryURL: URL
    let sourceProcessIdentifier: Int32
}

struct ConnectUpdater {
    private static let maximumPackageSize: Int64 = 128 * 1024 * 1024
    private static let maximumChecksumSize: Int64 = 1024 * 1024

    func install(_ update: ConnectUpdate) async throws -> PreparedConnectUpdate {
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

        return try Self.prepareCurrentApplication(with: candidate)
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

    private static func prepareCurrentApplication(with candidate: URL) throws -> PreparedConnectUpdate {
        let fileManager = FileManager.default
        let current = Bundle.main.bundleURL.standardizedFileURL
        guard current.pathExtension == "app",
              !current.path.contains("/AppTranslocation/"),
              let executable = Bundle.main.executableURL
        else {
            throw ConnectUpdateError.unsupportedLocation
        }

        let identifier = UUID().uuidString
        let root = updateSupportDirectory()
            .appendingPathComponent(identifier, isDirectory: true)
        let staged = root.appendingPathComponent("OrbitConnect.app", isDirectory: true)
        let installer = root.appendingPathComponent("OrbitConnectUpdateInstaller")
        let planURL = root.appendingPathComponent("installation.json")
        let backup = current.deletingLastPathComponent()
            .appendingPathComponent(".OrbitConnect-previous-\(identifier).app")
        let plan = ConnectUpdateInstallationPlan(
            currentApplicationURL: current,
            stagedApplicationURL: staged,
            backupApplicationURL: backup,
            workDirectoryURL: root,
            sourceProcessIdentifier: ProcessInfo.processInfo.processIdentifier
        )

        do {
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.copyItem(at: candidate, to: staged)
            try fileManager.copyItem(at: executable, to: installer)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: installer.path)
            let data = try JSONEncoder().encode(plan)
            try data.write(to: planURL, options: [.atomic])
            UpdateInstallationLog.write("Update prepared for deferred installation")
        } catch {
            try? fileManager.removeItem(at: root)
            UpdateInstallationLog.write(error, context: "Unable to prepare update")
            throw ConnectUpdateError.installationFailed
        }
        return PreparedConnectUpdate(
            installerURL: installer,
            planURL: planURL
        )
    }

    static func completePreparedInstallation(planURL: URL) -> Int32 {
        do {
            let data = try Data(contentsOf: planURL)
            let plan = try JSONDecoder().decode(ConnectUpdateInstallationPlan.self, from: data)
            try validate(plan, planURL: planURL)
            try waitForProcessToExit(plan.sourceProcessIdentifier)
            try replaceApplication(using: plan)
            do {
                try launchApplication(at: plan.currentApplicationURL)
            } catch {
                try restorePreviousApplication(using: plan)
                try? launchApplication(at: plan.currentApplicationURL)
                throw error
            }
            try? FileManager.default.removeItem(at: plan.backupApplicationURL)
            UpdateInstallationLog.write("Updated application launched successfully")
            try? FileManager.default.removeItem(at: plan.workDirectoryURL)
            return EXIT_SUCCESS
        } catch {
            UpdateInstallationLog.write(error, context: "Deferred installation failed")
            return EXIT_FAILURE
        }
    }

    static func replaceApplication(using plan: ConnectUpdateInstallationPlan) throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: plan.backupApplicationURL)
        try fileManager.moveItem(
            at: plan.currentApplicationURL,
            to: plan.backupApplicationURL
        )
        do {
            try fileManager.moveItem(
                at: plan.stagedApplicationURL,
                to: plan.currentApplicationURL
            )
        } catch {
            try? fileManager.moveItem(
                at: plan.backupApplicationURL,
                to: plan.currentApplicationURL
            )
            throw error
        }
    }

    private static func restorePreviousApplication(
        using plan: ConnectUpdateInstallationPlan
    ) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: plan.currentApplicationURL.path) {
            try fileManager.removeItem(at: plan.currentApplicationURL)
        }
        try fileManager.moveItem(
            at: plan.backupApplicationURL,
            to: plan.currentApplicationURL
        )
    }

    private static func validate(
        _ plan: ConnectUpdateInstallationPlan,
        planURL: URL
    ) throws {
        let current = plan.currentApplicationURL.standardizedFileURL
        let staged = plan.stagedApplicationURL.standardizedFileURL
        let backup = plan.backupApplicationURL.standardizedFileURL
        let root = plan.workDirectoryURL.standardizedFileURL
        guard current.pathExtension == "app",
              staged.pathExtension == "app",
              backup.pathExtension == "app",
              backup.deletingLastPathComponent() == current.deletingLastPathComponent(),
              backup.lastPathComponent.hasPrefix(".OrbitConnect-previous-"),
              staged.path.hasPrefix(root.path + "/"),
              planURL.standardizedFileURL.deletingLastPathComponent() == root,
              !current.path.contains("/AppTranslocation/")
        else {
            throw ConnectUpdateError.installationFailed
        }
    }

    private static func waitForProcessToExit(_ processIdentifier: Int32) throws {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            errno = 0
            if Darwin.kill(pid_t(processIdentifier), 0) != 0, errno == ESRCH {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw ConnectUpdateError.installationFailed
    }

    private static func launchApplication(at application: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", application.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ConnectUpdateError.installationFailed
        }
    }

    private static func updateSupportDirectory() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Orbit Connect", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
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

private enum UpdateInstallationLog {
    static func write(_ message: String) {
        writeLine("\(ISO8601DateFormatter().string(from: Date())) \(message)")
    }

    static func write(_ error: Error, context: String) {
        let value = error as NSError
        write("\(context): \(value.domain) \(value.code): \(value.localizedDescription)")
    }

    private static func writeLine(_ line: String) {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = base
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Orbit Connect", isDirectory: true)
        let file = directory.appendingPathComponent("update.log")
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size > 1_048_576 {
                try? fileManager.removeItem(at: file)
            }
            let data = Data((line + "\n").utf8)
            if !fileManager.fileExists(atPath: file.path) {
                try data.write(to: file, options: [.atomic])
                return
            }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // The updater must not fail only because diagnostics cannot be written.
        }
    }
}
