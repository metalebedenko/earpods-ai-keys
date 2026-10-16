import AppKit
import EarPodsCore
import EarPodsMac

@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {
    private let controller: RuntimeController
    private let watcher: EarPodsDeviceWatcher?
    private let store: DiskSettingsStore?
    private let login: MacLoginService?
    private let isPreview: Bool
    private var statusItem: NSStatusItem?
    private var statusMenu: StatusMenu!
    private var settings: SettingsWindowController?
    private var observationFailure: String?
    private var terminationPrepared = false

    convenience override init() {
        let store = DiskSettingsStore.userStore()
        self.init(controller: RuntimeController(runtime: NativeHIDRuntime(), input: NativeChordInput(), store: store),
                  watcher: EarPodsDeviceWatcher(), store: store, login: MacLoginService(), isPreview: false)
    }

    init(controller: RuntimeController, watcher: EarPodsDeviceWatcher?, store: DiskSettingsStore?, login: MacLoginService?, isPreview: Bool) {
        self.controller = controller
        self.watcher = watcher
        self.store = store
        self.login = login
        self.isPreview = isPreview
        super.init()
        statusMenu = StatusMenu(onToggle: { [weak self] in self?.toggleMode() },
                                onConfigure: { [weak self] in self?.showSettings() },
                                onRefresh: { [weak self] in self?.retry() },
                                onPermissions: { [weak self] in self?.controller.requestPermissions() },
                                onLogin: { [weak self] in self?.toggleLogin() },
                                onLoginSettings: { [weak self] in self?.login?.openSettings() },
                                onQuit: { [weak self] in self?.disableAndQuit() },
                                onUninstall: { [weak self] in self?.uninstall() },
                                onOpen: { [weak self] in self?.controller.refresh(); self?.refreshPresentation() })
        controller.onChange = { [weak self] in self?.refreshPresentation() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isPreview else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = Self.bundledMenuIcon() ?? NSImage(systemSymbolName: "earbuds", accessibilityDescription: AppIdentity.name) {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "EP"
        }
        item.menu = statusMenu.menu
        statusItem = item
        controller.start()
        startWatcher()
        refreshPresentation()
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher?.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isPreview, !terminationPrepared else { return .terminateNow }
        do {
            try controller.stopForTermination()
            watcher?.stop()
            terminationPrepared = true
            return .terminateNow
        } catch {
            showError(error)
            refreshPresentation()
            return .terminateCancel
        }
    }

    private var presentation: MenuPresentation {
        MenuPresentation(state: presentedState, enabled: controller.enabled, connected: controller.connected,
                         message: observationFailure ?? controller.lastMessage, loginEnabled: login?.enabled ?? false,
                         loginDescription: login?.statusDescription,
                         loginRequiresApproval: login?.requiresApproval ?? false)
    }

    private var presentedState: AppState {
        observationFailure.map(AppState.problem) ?? controller.state
    }

    private static func bundledMenuIcon() -> NSImage? {
        let image = NSImage(size: NSSize(width: 22, height: 22))
        for name in ["MenuIconTemplate", "MenuIconTemplate@2x"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
                  let data = try? Data(contentsOf: url),
                  let representation = NSBitmapImageRep(data: data) else { continue }
            representation.size = image.size
            image.addRepresentation(representation)
        }
        guard !image.representations.isEmpty else { return nil }
        image.accessibilityDescription = AppIdentity.name
        image.isTemplate = true
        return image
    }

    private func startWatcher() {
        guard let watcher else { return }
        do {
            try watcher.start(onChange: { [weak self] in self?.controller.deviceChanged() })
            observationFailure = nil
        } catch {
            observationFailure = "Автовосстановление не запущено: " + error.localizedDescription
        }
    }

    private func retry() {
        if observationFailure != nil { startWatcher() }
        controller.refresh()
        refreshPresentation()
    }

    private func refreshPresentation() {
        statusMenu.update(presentation)
        statusItem?.button?.toolTip = ["\(AppIdentity.name) — \(presentedState.title)",
                                     observationFailure ?? controller.lastMessage].compactMap { $0 }.joined(separator: "\n")
        settings?.updateActual(profile: controller.profile, state: presentedState,
                               connected: controller.connected, message: observationFailure ?? controller.lastMessage)
    }

    private func toggleMode() {
        do { try controller.setEnabled(!controller.enabled) }
        catch { showError(error) }
        refreshPresentation()
    }

    private func toggleLogin() {
        guard let login else { return }
        do { try login.setEnabled(!login.enabled) }
        catch { showError(error) }
        refreshPresentation()
    }

    private func makeSettings() -> SettingsWindowController {
        let window = SettingsWindowController(profile: controller.profile, onSave: { [weak self] profile in
            guard let self else { return }
            try self.controller.updateProfile(profile)
            self.refreshPresentation()
        }, onPermissions: { [weak self] in self?.controller.requestPermissions() })
        window.updateActual(profile: controller.profile, state: presentedState,
                            connected: controller.connected, message: observationFailure ?? controller.lastMessage)
        return window
    }

    private func showSettings() {
        if settings == nil { settings = makeSettings() }
        guard !isPreview else { return }
        NSApp.activate(ignoringOtherApps: true)
        settings?.showWindow(nil)
        settings?.window?.makeKeyAndOrderFront(nil)
    }

    private func disableAndQuit() {
        do {
            try controller.prepareRemoval()
            watcher?.stop()
            terminationPrepared = true
            NSApp.terminate(nil)
        } catch { showError(error) }
        refreshPresentation()
    }

    private func uninstall() {
        guard !isPreview, let store, let login else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Удалить EarPods AI Keys?"
        alert.informativeText = "Выключим пульт, снимем принадлежащие приложению назначения, уберём его запуск при входе и настройки. Затем переместим приложение в Корзину:\n\n\(Bundle.main.bundleURL.path)\n\nЧужие назначения и настройки Диктовки и Siri сохранятся."
        alert.addButton(withTitle: "Удалить")
        alert.addButton(withTitle: "Отмена")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        while true {
            do {
                try MacUninstaller(controller: controller, store: store, login: login).uninstall(appURL: Bundle.main.bundleURL)
                watcher?.stop()
                terminationPrepared = true
                NSApp.terminate(nil)
                return
            } catch {
                refreshPresentation()
                let failure = NSAlert()
                failure.alertStyle = .warning
                failure.messageText = "Удаление не завершено"
                failure.informativeText = error.localizedDescription + "\n\nПриложение остаётся здесь:\n" + Bundle.main.bundleURL.path
                failure.addButton(withTitle: "Повторить")
                failure.addButton(withTitle: "Позже")
                guard failure.runModal() == .alertFirstButtonReturn else { return }
            }
        }
    }

    private func showError(_ error: Error) {
        guard !isPreview else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Не удалось завершить действие"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Понятно")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // Preview services have no access to HID, saved user files, permissions or login registration.
    static func preview() -> AppCoordinator {
        let profile = Profile(center: .dictation, minus: .key(KeyBinding(virtualKey: 6, modifiers: .command)),
                              plus: .key(KeyBinding(virtualKey: 36)))
        let saved = SavedState(enabled: true, profile: profile, receipt: OwnershipReceipt(verified: profile.mapping))
        let controller = RuntimeController(runtime: PreviewHID(mapping: profile.mapping), input: PreviewInput(), store: PreviewStore(saved: saved))
        let coordinator = AppCoordinator(controller: controller, watcher: nil, store: nil, login: nil, isPreview: true)
        controller.start()
        coordinator.refreshPresentation()
        return coordinator
    }

    func renderPreview(to directory: URL) throws {
        guard isPreview else { throw AppFailure("Предпросмотр требует изолированного режима.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let overview = statusMenu.previewView(presentation)
        try Self.render(overview, to: directory.appendingPathComponent("menu.png"))
        let settings = makeSettings()
        self.settings = settings
        guard let content = settings.window?.contentView else { throw AppFailure("Не удалось создать окно настроек.") }
        try Self.render(content, to: directory.appendingPathComponent("settings.png"))
    }

    private static func render(_ view: NSView, to url: URL) throws {
        view.appearance = NSAppearance(named: .aqua)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width*2),
                                           pixelsHigh: Int(view.bounds.height*2), bitsPerSample: 8,
                                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32) else {
            throw AppFailure("Не удалось создать изображение интерфейса.")
        }
        bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw AppFailure("Не удалось сохранить изображение интерфейса.") }
        try png.write(to: url, options: .atomic)
    }
}

@MainActor private final class PreviewHID: HIDRuntime {
    private var mapping: [MappingPair]
    init(mapping: [MappingPair]) { self.mapping = mapping }
    func read() throws -> MappingSnapshot { .mapped(mapping) }
    func write(_ pairs: [MappingPair]) throws { mapping = pairs }
    func legacyConflict() throws -> String? { nil }
}

@MainActor private final class PreviewInput: ChordInput {
    var onFailure: ((Error) -> Void)?
    func permissions() -> PermissionState { PermissionState(listen: true, post: true) }
    func requestPermissions() {}
    func start(profile: Profile, onPress: @escaping (RemoteButton) -> Void) throws {}
    func stop() {}
    func send(_ binding: KeyBinding) throws {}
}

private final class PreviewStore: SettingsStore {
    private var saved: SavedState
    init(saved: SavedState) { self.saved = saved }
    func load() throws -> SavedState { saved }
    func save(_ state: SavedState) throws { saved = state }
    func removeOwnedFiles() throws {}
}
