import AppKit
import Darwin
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = OrbitStatusModel()
    private let statusPanel = OrbitStatusPanel(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 1),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    private var statusHostingController: NSViewController?
    private let contextPanel = OrbitStatusPanel(
        contentRect: NSRect(x: 0, y: 0, width: 300, height: 1),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    private var contextHostingController: NSViewController?
    private var statusItem: NSStatusItem!
    private var singleInstanceGuard: SingleInstanceGuard?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var trafficPauseAlertTracker = TrafficPauseAlertTracker()
    private var trafficPauseAlert: NSAlert?
    private var settingsWindow: NSWindow?
    private var terminationApproved = false
    private var terminationInProgress = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let guardInstance = SingleInstanceGuard.acquire() else {
            showAlreadyRunningAlert()
            terminationApproved = true
            NSApplication.shared.terminate(nil)
            return
        }
        singleInstanceGuard = guardInstance

        installEditMenu()
        AutostartManager.enableByDefaultIfNeeded()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = StatusIconRenderer.image(state: model.state)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = OrbitRuntime.isDevelopment ? "Orbit Connect Dev" : "Orbit"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleStatusItemClick)
        statusItem.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])

        let hostingController = NSHostingController(rootView: ContentView(model: model))
        statusHostingController = hostingController
        statusPanel.contentViewController = hostingController

        let contextController = NSHostingController(
            rootView: OrbitContextMenuView(
                model: model,
                openKeeneticOS: { [weak self] in
                    self?.closeStatusPanel()
                    self?.openKeeneticOS()
                },
                openOrbit: { [weak self] in
                    self?.closeStatusPanel()
                    self?.openOrbit()
                },
                restart: { [weak self] in
                    self?.closeStatusPanel()
                    self?.restartApplication()
                },
                checkForUpdates: { [weak self] in
                    self?.closeStatusPanel()
                    self?.checkForUpdates()
                },
                settings: { [weak self] in
                    self?.closeStatusPanel()
                    self?.showSettings()
                },
                unlink: { [weak self] in
                    self?.closeStatusPanel()
                    self?.confirmUnlink()
                },
                close: { [weak self] in
                    self?.quitApplication()
                }
            )
            .orbitAppearance()
        )
        contextHostingController = contextController
        contextPanel.contentViewController = contextController

        model.onStateChange = { [weak self] state in
            guard let self else { return }
            self.statusItem.button?.image = StatusIconRenderer.image(state: state)
            self.updateTrafficPauseAlert(isBlocked: state == .blocked)
            DispatchQueue.main.async {
                self.resizeStatusPanelIfNeeded()
            }
        }

        observeWorkspaceChanges()

        if OrbitRuntime.isDemo {
            DispatchQueue.main.async { [weak self] in
                self?.showSettings()
            }
        }
    }

    private func installEditMenu() {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Правка")

        editMenu.addItem(withTitle: "Отменить", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Выбрать всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApplication.shared.mainMenu = mainMenu
    }

    @objc private func handleStatusItemClick() {
        if NSApplication.shared.currentEvent?.type == .rightMouseDown {
            showContextMenu()
        } else {
            toggleStatusPanel()
        }
    }

    private func toggleStatusPanel() {
        if statusPanelIsActuallyVisible {
            closeStatusPanel()
        } else {
            closeStatusPanel()
            if !model.loading {
                model.refresh()
            }
            let itemFrame = statusItemScreenFrame
            let fallbackPoint = NSEvent.mouseLocation
            let anchorPoint = itemFrame.isEmpty
                ? fallbackPoint
                : NSPoint(x: itemFrame.midX, y: itemFrame.minY)
            let screen = statusItem.button?.window?.screen
                ?? NSScreen.screens.first { NSMouseInRect(anchorPoint, $0.frame, false) }
                ?? NSScreen.main
            let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            resizeStatusPanel(in: visibleFrame)
            let panelSize = statusPanel.frame.size
            let requestedX = anchorPoint.x - panelSize.width / 2
            let requestedY = anchorPoint.y - panelSize.height - 4
            let origin = NSPoint(
                x: min(max(requestedX, visibleFrame.minX + 8), visibleFrame.maxX - panelSize.width - 8),
                y: min(
                    max(requestedY, visibleFrame.minY + 8),
                    visibleFrame.maxY - panelSize.height
                )
            )
            statusPanel.setFrameOrigin(origin)
            NSApplication.shared.activate(ignoringOtherApps: true)
            statusPanel.makeKeyAndOrderFront(nil)
            statusPanel.orderFrontRegardless()
            installOutsideClickMonitors()
        }
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()
        guard statusPanel.isVisible || contextPanel.isVisible else { return }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                guard let self, !self.statusItemScreenFrame.contains(location) else { return }
                self.closeStatusPanel()
            }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.windowNumber != self.statusPanel.windowNumber,
               event.windowNumber != self.contextPanel.windowNumber {
                self.closeStatusPanel()
            }
            return event
        }
    }

    private func closeStatusPanel() {
        statusPanel.orderOut(nil)
        contextPanel.orderOut(nil)
        removeOutsideClickMonitors()
    }

    private var statusPanelIsActuallyVisible: Bool {
        guard statusPanel.isVisible, statusPanel.isOnActiveSpace else { return false }
        guard statusPanel.occlusionState.contains(.visible) else { return false }
        return NSScreen.screens.contains { $0.visibleFrame.intersects(statusPanel.frame) }
    }

    private var statusItemScreenFrame: NSRect {
        guard let button = statusItem.button, let window = button.window else { return .zero }
        let frameInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(frameInWindow).insetBy(dx: -4, dy: -4)
    }

    private func observeWorkspaceChanges() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.closeStatusPanel() }
            }
        )
        workspaceObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.closeStatusPanel() }
            }
        )
    }

    private func removeOutsideClickMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    private func resizeStatusPanelIfNeeded() {
        guard statusPanel.isVisible else { return }
        let top = statusPanel.frame.maxY
        let screenFrame = statusPanel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        resizeStatusPanel(in: screenFrame)
        statusPanel.setFrameOrigin(NSPoint(x: statusPanel.frame.minX, y: top - statusPanel.frame.height))
    }

    private func resizeStatusPanel(in visibleFrame: NSRect) {
        guard let view = statusHostingController?.view else { return }
        view.layoutSubtreeIfNeeded()
        let fittedHeight = view.fittingSize.height
        let height = min(max(fittedHeight, 180), visibleFrame.height - 16)
        guard abs(statusPanel.frame.width - 400) > 0.5 ||
                abs(statusPanel.frame.height - height) > 0.5 else { return }
        statusPanel.setContentSize(NSSize(width: 400, height: height))
    }

    private func showContextMenu() {
        if panelIsActuallyVisible(contextPanel) {
            closeStatusPanel()
            return
        }
        closeStatusPanel()
        let itemFrame = statusItemScreenFrame
        let fallbackPoint = NSEvent.mouseLocation
        let anchorPoint = itemFrame.isEmpty
            ? fallbackPoint
            : NSPoint(x: itemFrame.midX, y: itemFrame.minY)
        let screen = statusItem.button?.window?.screen
            ?? NSScreen.screens.first { NSMouseInRect(anchorPoint, $0.frame, false) }
            ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        resizeContextPanel(in: visibleFrame)
        let panelSize = contextPanel.frame.size
        let requestedX = anchorPoint.x - panelSize.width / 2
        let requestedY = anchorPoint.y - panelSize.height - 4
        contextPanel.setFrameOrigin(
            NSPoint(
                x: min(max(requestedX, visibleFrame.minX + 8), visibleFrame.maxX - panelSize.width - 8),
                y: min(
                    max(requestedY, visibleFrame.minY + 8),
                    visibleFrame.maxY - panelSize.height
                )
            )
        )
        NSApplication.shared.activate(ignoringOtherApps: true)
        contextPanel.makeKeyAndOrderFront(nil)
        contextPanel.orderFrontRegardless()
        installOutsideClickMonitors()
    }

    private func resizeContextPanel(in visibleFrame: NSRect) {
        guard let view = contextHostingController?.view else { return }
        view.layoutSubtreeIfNeeded()
        let height = min(max(view.fittingSize.height, 180), visibleFrame.height - 16)
        contextPanel.setContentSize(NSSize(width: 300, height: height))
    }

    private func panelIsActuallyVisible(_ panel: NSPanel) -> Bool {
        guard panel.isVisible, panel.isOnActiveSpace else { return false }
        guard panel.occlusionState.contains(.visible) else { return false }
        return NSScreen.screens.contains { $0.visibleFrame.intersects(panel.frame) }
    }

    @objc private func checkForUpdates() {
        model.checkForUpdates { [weak self] result in
            self?.showUpdateResult(result)
        }
    }

    @objc private func openOrbit() {
        model.openOrbit()
    }

    @objc private func openKeeneticOS() {
        model.openKeeneticOS()
    }

    private func showSettings() {
        if let settingsWindow {
            NSApplication.shared.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = OrbitRuntime.isDevelopment
            ? "Настройки Orbit Connect Dev"
            : "Настройки Orbit Connect"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = NSHostingController(
            rootView: EgressControlSettingsView(model: model)
        )
        window.delegate = self
        settingsWindow = window
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func restartApplication() {
        singleInstanceGuard?.release()
        singleInstanceGuard = nil
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                if error == nil {
                    self?.terminationApproved = true
                    NSApplication.shared.terminate(nil)
                } else {
                    self?.singleInstanceGuard = SingleInstanceGuard.acquire()
                }
            }
        }
    }

    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationApproved else { return .terminateNow }
        guard !terminationInProgress else { return .terminateLater }
        guard model.egressControl.isEnabled else { return .terminateNow }
        guard confirmProtectedQuit() else { return .terminateCancel }
        terminationInProgress = true
        model.egressControl.disableForApplicationTermination { [weak self, weak sender] result in
            guard let self, let sender else { return }
            self.terminationInProgress = false
            switch result {
            case .success:
                self.terminationApproved = true
                sender.reply(toApplicationShouldTerminate: true)
            case let .failure(error):
                self.showTerminationFailure(error)
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }

    private func confirmProtectedQuit() -> Bool {
        let code = String(format: "%04d", Int.random(in: 0 ... 9999))
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Закрыть Orbit Connect?"
        alert.informativeText = "Контроль доверенного выхода включён. Перед закрытием Orbit Connect отключит все правила сетевого контроля. Введите код \(code), чтобы подтвердить действие."
        alert.addButton(withTitle: "Закрыть")
        alert.addButton(withTitle: "Отменить")
        alert.buttons.first?.hasDestructiveAction = true

        let field = NSTextField(string: "")
        field.placeholderString = "Код из 4 цифр"
        field.alignment = .center
        field.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 30)
        alert.accessoryView = field

        NSApplication.shared.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        guard field.stringValue == code else {
            let failure = NSAlert()
            failure.alertStyle = .warning
            failure.messageText = "Код не совпал"
            failure.informativeText = "Orbit Connect продолжает работать."
            failure.addButton(withTitle: "Готово")
            failure.runModal()
            return false
        }
        return true
    }

    private func showTerminationFailure(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Не удалось отключить сетевой контроль"
        alert.informativeText = "Orbit Connect продолжает работать, чтобы правила не остались в неопределённом состоянии. \(error.localizedDescription)"
        alert.addButton(withTitle: "Готово")
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showUpdateResult(_ result: Result<ConnectUpdate?, Error>) {
        if OrbitRuntime.isDevelopment {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Обновление отключено в dev-режиме"
            alert.informativeText = "Тестовая сборка не изменяет установленный Orbit Connect."
            alert.addButton(withTitle: "Готово")
            NSApplication.shared.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .informational
        switch result {
        case let .success(update?):
            alert.messageText = "Доступна новая версия v\(update.version)"
            alert.informativeText = "Обновление Orbit Connect готово к загрузке."
            alert.addButton(withTitle: "Обновить")
            alert.addButton(withTitle: "Позже")
            NSApplication.shared.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                installUpdate(update)
            }
        case .success(nil):
            alert.messageText = "Установлена актуальная версия"
            alert.informativeText = "Orbit Connect v\(model.currentVersion) не требует обновления."
            alert.addButton(withTitle: "Готово")
            NSApplication.shared.activate(ignoringOtherApps: true)
            alert.runModal()
        case .failure:
            alert.alertStyle = .warning
            alert.messageText = "Не удалось проверить обновления"
            alert.informativeText = "Проверьте подключение к интернету и повторите попытку."
            alert.addButton(withTitle: "Готово")
            NSApplication.shared.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private func installUpdate(_ update: ConnectUpdate) {
        let progress = NSAlert()
        progress.alertStyle = .informational
        progress.messageText = "Устанавливаем Orbit Connect v\(update.version)"
        progress.informativeText = "Загружаем и проверяем пакет обновления…"
        let spinner = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        spinner.style = .spinning
        spinner.startAnimation(nil)
        progress.accessoryView = spinner
        NSApplication.shared.activate(ignoringOtherApps: true)
        progress.window.center()
        progress.window.makeKeyAndOrderFront(nil)

        Task {
            do {
                let installed = try await ConnectUpdater().install(update)
                progress.window.orderOut(nil)
                restartAfterUpdate(installed)
            } catch {
                progress.window.orderOut(nil)
                showUpdateFailure(error, update: update)
            }
        }
    }

    private func restartAfterUpdate(_ installed: InstalledConnectUpdate) {
        singleInstanceGuard?.release()
        singleInstanceGuard = nil
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: installed.applicationURL,
            configuration: configuration
        ) { [weak self] _, error in
            Task { @MainActor in
                if error == nil {
                    try? FileManager.default.removeItem(at: installed.backupURL)
                    self?.terminationApproved = true
                    NSApplication.shared.terminate(nil)
                    return
                }
                try? FileManager.default.removeItem(at: installed.applicationURL)
                try? FileManager.default.moveItem(
                    at: installed.backupURL,
                    to: installed.applicationURL
                )
                self?.singleInstanceGuard = SingleInstanceGuard.acquire()
                self?.showUpdateFailure(
                    ConnectUpdateError.installationFailed,
                    update: nil
                )
            }
        }
    }

    private func showUpdateFailure(_ error: Error, update: ConnectUpdate?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Не удалось установить обновление"
        alert.informativeText = error.localizedDescription
        if update != nil {
            alert.addButton(withTitle: "Скачать вручную")
            alert.addButton(withTitle: "Закрыть")
        } else {
            alert.addButton(withTitle: "Готово")
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, let update {
            NSWorkspace.shared.open(update.downloadURL)
        }
    }

    private func confirmUnlink() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Разорвать связь приложения с устройством?"
        alert.informativeText = "Приложение потеряет доступ к Orbit. Сетевые настройки устройства не изменятся."
        alert.addButton(withTitle: "Разорвать связь")
        alert.addButton(withTitle: "Отменить")
        alert.buttons.first?.hasDestructiveAction = true
        NSApplication.shared.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            model.deleteLink()
        }
    }

    private func showAlreadyRunningAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Orbit Connect уже запущен"
        alert.informativeText = "Одновременно может работать только один экземпляр приложения."
        alert.addButton(withTitle: "Готово")
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func updateTrafficPauseAlert(isBlocked: Bool) {
        switch trafficPauseAlertTracker.update(isBlocked: isBlocked) {
        case .none:
            return
        case .present:
            presentTrafficPauseAlert()
        case .dismiss:
            dismissTrafficPauseAlert()
        }
    }

    private func presentTrafficPauseAlert() {
        let alert = TrafficPauseAlertFactory.makeAlert()
        trafficPauseAlert = alert

        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.window.center()
        alert.runModal()

        if trafficPauseAlert === alert {
            trafficPauseAlert = nil
            trafficPauseAlertTracker.didDismiss()
        }
    }

    private func dismissTrafficPauseAlert() {
        guard let alert = trafficPauseAlert else { return }
        trafficPauseAlert = nil
        if NSApplication.shared.modalWindow === alert.window {
            NSApplication.shared.abortModal()
        }
        alert.window.orderOut(nil)
    }

}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === settingsWindow
        else { return }
        settingsWindow = nil
    }
}

private final class OrbitStatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )
        level = .popUpMenu
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.moveToActiveSpace, .stationary, .transient, .fullScreenAuxiliary, .ignoresCycle]
    }

}

private final class SingleInstanceGuard {
    private var descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    static func acquire() -> SingleInstanceGuard? {
        let fileManager = FileManager.default
        guard let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = applicationSupport.appendingPathComponent(
            OrbitRuntime.applicationSupportDirectoryName,
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let path = directory.appendingPathComponent("instance.lock").path
        let descriptor = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        return SingleInstanceGuard(descriptor: descriptor)
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit {
        release()
    }
}

@main
enum OrbitStatusApplication {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
