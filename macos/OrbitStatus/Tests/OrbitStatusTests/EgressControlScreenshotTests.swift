import AppKit
import SwiftUI
import XCTest

@testable import OrbitStatus

@MainActor
final class EgressControlScreenshotTests: XCTestCase {
    private struct ScreenProfile {
        let name: String
        let size: CGSize
    }

    private let profiles = [
        ScreenProfile(name: "wide", size: CGSize(width: 1_180, height: 760)),
        ScreenProfile(name: "medium", size: CGSize(width: 920, height: 720)),
        ScreenProfile(name: "narrow", size: CGSize(width: 760, height: 720)),
    ]

    func testSettingsScreens() throws {
        guard let outputPath = ProcessInfo.processInfo.environment[
            "ORBIT_CONNECT_SCREENSHOT_DIR"
        ], !outputPath.isEmpty else {
            throw XCTSkip(
                "Set ORBIT_CONNECT_SCREENSHOT_DIR to capture UI screenshots"
            )
        }

        let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputURL,
            withIntermediateDirectories: true
        )

        let model = OrbitStatusModel(isDemo: true)
        let sections: [SettingsSection] = [
            .control,
            .application,
        ]
        let applicationWithEvents = model.egressControl.configuration.applications
            .first { application in
                model.egressControl.flowEvents.contains { event in
                    event.applicationIdentifier == application.bundleIdentifier
                        || event.applicationIdentifier.hasPrefix(
                            application.bundleIdentifier + "."
                        )
                }
            }

        for profile in profiles {
            for section in sections {
                try capture(
                    model: model,
                    section: section,
                    initiallyExpandedApplicationIDs: Set(
                        [applicationWithEvents?.id].compactMap { $0 }
                    ),
                    profile: profile,
                    colorScheme: .light,
                    appearance: .aqua,
                    outputURL: outputURL
                )
                try capture(
                    model: model,
                    section: section,
                    initiallyExpandedApplicationIDs: Set(
                        [applicationWithEvents?.id].compactMap { $0 }
                    ),
                    profile: profile,
                    colorScheme: .dark,
                    appearance: .darkAqua,
                    outputURL: outputURL
                )
            }
        }
    }

    func testApplicationPickerScreen() throws {
        guard let outputPath = ProcessInfo.processInfo.environment[
            "ORBIT_CONNECT_SCREENSHOT_DIR"
        ], !outputPath.isEmpty else {
            throw XCTSkip(
                "Set ORBIT_CONNECT_SCREENSHOT_DIR to capture UI screenshots"
            )
        }

        let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputURL,
            withIntermediateDirectories: true
        )

        let model = OrbitStatusModel(isDemo: true)
        let applications = ApplicationCatalog.load(
            configuredApplications: model.egressControl.configuration.applications,
            observedApplicationIdentifiers: model.egressControl.flowEvents.map(
                \.applicationIdentifier
            )
        )
        let applicationWithEvents = applications.first { application in
            model.egressControl.flowEvents.contains { event in
                event.applicationIdentifier == application.bundleIdentifier
                    || event.applicationIdentifier.hasPrefix(
                        application.bundleIdentifier + "."
                    )
            }
        }
        let applicationWithoutEvents = applications.first { application in
            !model.egressControl.flowEvents.contains { event in
                event.applicationIdentifier == application.bundleIdentifier
                    || event.applicationIdentifier.hasPrefix(
                        application.bundleIdentifier + "."
                    )
            }
        }

        for profile in [
            ScreenProfile(name: "wide", size: CGSize(width: 680, height: 640)),
            ScreenProfile(name: "narrow", size: CGSize(width: 620, height: 640)),
        ] {
            try captureApplicationPicker(
                model: model,
                applications: applications,
                expandedIdentifier: applicationWithEvents?.bundleIdentifier
                    ?? applications.first?.bundleIdentifier,
                search: applicationWithEvents?.displayName ?? "",
                profile: profile,
                colorScheme: .light,
                appearance: .aqua,
                outputURL: outputURL
            )
            try captureApplicationPicker(
                model: model,
                applications: applications,
                expandedIdentifier: applicationWithEvents?.bundleIdentifier
                    ?? applications.first?.bundleIdentifier,
                search: applicationWithEvents?.displayName ?? "",
                profile: profile,
                colorScheme: .dark,
                appearance: .darkAqua,
                outputURL: outputURL
            )
        }

        if let applicationWithoutEvents {
            for profile in [
                ScreenProfile(
                    name: "empty-wide",
                    size: CGSize(width: 680, height: 640)
                ),
                ScreenProfile(
                    name: "empty-narrow",
                    size: CGSize(width: 620, height: 640)
                ),
            ] {
                try captureApplicationPicker(
                    model: model,
                    applications: applications,
                    expandedIdentifier: applicationWithoutEvents.bundleIdentifier,
                    search: applicationWithoutEvents.displayName,
                    profile: profile,
                    colorScheme: .light,
                    appearance: .aqua,
                    outputURL: outputURL
                )
            }
        }
    }

    func testConnectMainScreen() throws {
        guard let outputPath = ProcessInfo.processInfo.environment[
            "ORBIT_CONNECT_SCREENSHOT_DIR"
        ], !outputPath.isEmpty else {
            throw XCTSkip(
                "Set ORBIT_CONNECT_SCREENSHOT_DIR to capture UI screenshots"
            )
        }

        let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputURL,
            withIntermediateDirectories: true
        )

        try captureConnectMainScreen(
            model: OrbitStatusModel(isDemo: true),
            colorScheme: .light,
            appearance: .aqua,
            outputURL: outputURL
        )
        try captureConnectMainScreen(
            model: OrbitStatusModel(isDemo: true),
            colorScheme: .dark,
            appearance: .darkAqua,
            outputURL: outputURL
        )
    }

    private func capture(
        model: OrbitStatusModel,
        section: SettingsSection,
        initiallyExpandedApplicationIDs: Set<UUID>,
        profile: ScreenProfile,
        colorScheme: ColorScheme,
        appearance: NSAppearance.Name,
        outputURL: URL
    ) throws {
        let rootView = EgressControlSettingsView(
            model: model,
            initialSection: section,
            initiallyExpandedApplicationIDs: initiallyExpandedApplicationIDs
        )
        .environment(\.colorScheme, colorScheme)
        .frame(width: profile.size.width, height: profile.size.height)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.appearance = NSAppearance(named: appearance)
        hostingView.frame = CGRect(origin: .zero, size: profile.size)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        guard let representation = hostingView.bitmapImageRepForCachingDisplay(
            in: hostingView.bounds
        ) else {
            XCTFail("Unable to create screenshot buffer")
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)

        guard let data = representation.representation(
            using: .png,
            properties: [:]
        ) else {
            XCTFail("Unable to encode screenshot")
            return
        }

        let theme = colorScheme == .dark ? "dark" : "light"
        let fileURL = outputURL.appendingPathComponent(
            "settings-\(section.rawValue)-\(profile.name)-\(theme).png"
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private func captureApplicationPicker(
        model: OrbitStatusModel,
        applications: [InstalledApplication],
        expandedIdentifier: String?,
        search: String,
        profile: ScreenProfile,
        colorScheme: ColorScheme,
        appearance: NSAppearance.Name,
        outputURL: URL
    ) throws {
        let size = profile.size
        let rootView = ApplicationPickerView(
            control: model.egressControl,
            initialApplications: applications,
            initialExpandedIdentifiers: Set([expandedIdentifier].compactMap { $0 }),
            initialSearch: search,
            close: {}
        )
        .environment(\.colorScheme, colorScheme)
        .frame(width: size.width, height: size.height)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.appearance = NSAppearance(named: appearance)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        guard let representation = hostingView.bitmapImageRepForCachingDisplay(
            in: hostingView.bounds
        ) else {
            XCTFail("Unable to create application picker screenshot buffer")
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)

        guard let data = representation.representation(
            using: .png,
            properties: [:]
        ) else {
            XCTFail("Unable to encode application picker screenshot")
            return
        }

        let theme = colorScheme == .dark ? "dark" : "light"
        let fileURL = outputURL.appendingPathComponent(
            "application-picker-\(profile.name)-\(theme).png"
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private func captureConnectMainScreen(
        model: OrbitStatusModel,
        colorScheme: ColorScheme,
        appearance: NSAppearance.Name,
        outputURL: URL
    ) throws {
        if let appIcon = NSImage(contentsOf: appIconURL) {
            NSApplication.shared.applicationIconImage = appIcon
        }
        let rootView = ContentView(model: model)
            .environment(\.colorScheme, colorScheme)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.appearance = NSAppearance(named: appearance)
        hostingView.frame = CGRect(
            origin: .zero,
            size: CGSize(width: 400, height: 1)
        )
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        hostingView.frame = CGRect(
            origin: .zero,
            size: CGSize(width: 400, height: fittingSize.height)
        )
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        guard let representation = hostingView.bitmapImageRepForCachingDisplay(
            in: hostingView.bounds
        ) else {
            XCTFail("Unable to create main screen screenshot buffer")
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)

        guard let data = representation.representation(
            using: .png,
            properties: [:]
        ) else {
            XCTFail("Unable to encode main screen screenshot")
            return
        }

        let theme = colorScheme == .dark ? "dark" : "light"
        let fileURL = outputURL.appendingPathComponent(
            "connect-main-\(theme).png"
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private var appIconURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/AppIcon.icns")
    }
}
