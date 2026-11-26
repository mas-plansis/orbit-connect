import AppKit
import Foundation
import OrbitConnectPolicy

struct InstalledApplication: Identifiable, Hashable {
    let bundleIdentifier: String
    let displayName: String
    let url: URL?

    var id: String { bundleIdentifier }

    var icon: NSImage {
        guard let url else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

enum ApplicationCatalog {
    static func icon(
        for bundleIdentifier: String,
        displayName: String? = nil
    ) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) ?? installedApplicationURL(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName
        ) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    static func load(
        configuredApplications: [ProtectedApplication],
        observedApplicationIdentifiers: [String]
    ) -> [InstalledApplication] {
        var applications: [String: InstalledApplication] = [:]
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true),
        ]

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()
                guard let application = application(at: url) else { continue }
                applications[application.bundleIdentifier] = application
            }
        }

        for configured in configuredApplications {
            guard applications[configured.bundleIdentifier] == nil else { continue }
            applications[configured.bundleIdentifier] = InstalledApplication(
                bundleIdentifier: configured.bundleIdentifier,
                displayName: configured.displayName.isEmpty
                    ? configured.bundleIdentifier
                    : configured.displayName,
                url: nil
            )
        }

        for identifier in observedApplicationIdentifiers {
            guard !identifier.isEmpty, applications[identifier] == nil else { continue }
            applications[identifier] = InstalledApplication(
                bundleIdentifier: identifier,
                displayName: displayName(for: identifier),
                url: nil
            )
        }

        return applications.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private static func application(at url: URL) -> InstalledApplication? {
        guard let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier,
              !identifier.isEmpty
        else { return nil }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledApplication(
            bundleIdentifier: identifier,
            displayName: name,
            url: url
        )
    }

    private static func installedApplicationURL(
        bundleIdentifier: String,
        displayName: String?
    ) -> URL? {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true),
        ]

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in urls where url.pathExtension.lowercased() == "app" {
                if Bundle(url: url)?.bundleIdentifier == bundleIdentifier {
                    return url
                }
                if let displayName,
                   url.deletingPathExtension().lastPathComponent
                    .localizedCaseInsensitiveCompare(displayName) == .orderedSame {
                    return url
                }
            }
        }
        return nil
    }

    private static func displayName(for bundleIdentifier: String) -> String {
        bundleIdentifier.split(separator: ".").last
            .map { String($0).replacingOccurrences(of: "-", with: " ").capitalized }
            ?? bundleIdentifier
    }
}
