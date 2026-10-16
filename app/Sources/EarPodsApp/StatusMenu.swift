import AppKit
import EarPodsCore

struct MenuPresentation {
    let state: AppState
    let enabled: Bool
    let connected: Bool
    let message: String?
    let loginEnabled: Bool
    let loginDescription: String?
    let loginRequiresApproval: Bool
    var connectionTitle: String { Self.connectionTitle(state: state, connected: connected) }
    static func connectionTitle(state: AppState, connected: Bool) -> String {
        if connected { return "EarPods подключены" }
        if case .problem = state { return "Наличие EarPods не подтверждено" }
        return "EarPods не подключены"
    }
}

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    private let stateItem = NSMenuItem(title: "Режим выключен", action: nil, keyEquivalent: "")
    private let connectionItem = NSMenuItem(title: "EarPods не подключены", action: nil, keyEquivalent: "")
    private let messageItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "Включить пульт", action: nil, keyEquivalent: "")
    private let permissionsItem = NSMenuItem(title: "Разрешения macOS…", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Запускать при входе", action: nil, keyEquivalent: "")
    private let loginStatusItem = NSMenuItem(title: "Подтвердить запуск в настройках…", action: nil, keyEquivalent: "")
    private let onToggle: () -> Void
    private let onConfigure: () -> Void
    private let onRefresh: () -> Void
    private let onPermissions: () -> Void
    private let onLogin: () -> Void
    private let onLoginSettings: () -> Void
    private let onQuit: () -> Void
    private let onUninstall: () -> Void
    private let onOpen: () -> Void

    init(onToggle: @escaping () -> Void, onConfigure: @escaping () -> Void, onRefresh: @escaping () -> Void,
         onPermissions: @escaping () -> Void, onLogin: @escaping () -> Void, onLoginSettings: @escaping () -> Void,
         onQuit: @escaping () -> Void, onUninstall: @escaping () -> Void, onOpen: @escaping () -> Void) {
        self.onToggle=onToggle; self.onConfigure=onConfigure; self.onRefresh=onRefresh
        self.onPermissions=onPermissions; self.onLogin=onLogin; self.onLoginSettings=onLoginSettings
        self.onQuit=onQuit; self.onUninstall=onUninstall; self.onOpen=onOpen
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        [stateItem, connectionItem, messageItem].forEach { $0.isEnabled = false; menu.addItem($0) }
        menu.addItem(.separator())
        wire(toggleItem, #selector(toggle))
        add("Настроить кнопки…", #selector(configure))
        wire(permissionsItem, #selector(permissions))
        add("Повторить проверку", #selector(refresh))
        menu.addItem(.separator())
        wire(loginItem, #selector(login))
        wire(loginStatusItem, #selector(loginSettings))
        menu.addItem(.separator())
        add("Выключить и выйти", #selector(quit))
        add("Удалить приложение…", #selector(uninstall))
    }

    private func wire(_ item: NSMenuItem, _ selector: Selector) { item.target=self; item.action=selector; menu.addItem(item) }
    private func add(_ title: String, _ selector: Selector) { wire(NSMenuItem(title: title, action: nil, keyEquivalent: ""), selector) }

    func update(_ value: MenuPresentation) {
        stateItem.title = value.state.title
        connectionItem.title = value.connectionTitle
        toggleItem.title = value.enabled ? "Выключить пульт" : "Включить пульт"
        let problem: String?
        if case .problem(let detail) = value.state { problem = detail } else { problem = value.message }
        stateItem.toolTip = problem
        messageItem.toolTip = problem
        messageItem.isHidden = problem?.isEmpty != false
        if let problem, !problem.isEmpty { messageItem.view = Self.messageView(problem) } else { messageItem.view = nil }
        if case .needsPermissions = value.state { permissionsItem.isHidden = false } else { permissionsItem.isHidden = true }
        loginItem.state = value.loginEnabled ? .on : .off
        loginStatusItem.isHidden = !value.loginRequiresApproval
        loginItem.toolTip = value.loginDescription
    }

    func menuWillOpen(_ menu: NSMenu) { onOpen() }
    @objc private func toggle() { onToggle() }
    @objc private func configure() { onConfigure() }
    @objc private func refresh() { onRefresh() }
    @objc private func permissions() { onPermissions() }
    @objc private func login() { onLogin() }
    @objc private func loginSettings() { onLoginSettings() }
    @objc private func quit() { onQuit() }
    @objc private func uninstall() { onUninstall() }

    private static func messageView(_ message: String) -> NSView {
        let width: CGFloat = 290
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.toolTip = message
        let height = label.sizeThatFits(NSSize(width: width-28, height: .greatestFiniteMagnitude)).height
        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height+12))
        label.frame = NSRect(x: 14, y: 6, width: width-28, height: height)
        view.addSubview(label)
        return view
    }

    // A native, static menu-shaped view: NSMenu itself cannot be opened safely in render mode.
    func previewView(_ value: MenuPresentation) -> NSView {
        let rows: [(String, Bool)] = [
            (AppIdentity.name, true), (value.state.title, true),
            (value.connectionTitle, false),
            ("", false), (value.enabled ? "Выключить пульт" : "Включить пульт", true),
            ("Настроить кнопки…", true), ("Повторить проверку", true), ("", false),
            (value.loginEnabled ? "✓  Запускать при входе" : "Запускать при входе", true),
            ("", false), ("Выключить и выйти", true), ("Удалить приложение…", true)
        ]
        let width: CGFloat = 310
        let height = CGFloat(rows.count)*28+22
        let view = AppSurfaceView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.appearance = NSAppearance(named: .aqua)
        view.rounded = true
        var y = height-36
        for (index, row) in rows.enumerated() {
            if row.0.isEmpty {
                let line = NSBox(frame: NSRect(x: 10, y: y+12, width: width-20, height: 1))
                line.boxType = .separator
                view.addSubview(line)
            } else {
                let label = NSTextField(labelWithString: row.0)
                label.font = index < 2 ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 13)
                label.textColor = row.1 ? .labelColor : .secondaryLabelColor
                label.frame = NSRect(x: 18, y: y+4, width: width-36, height: 19)
                view.addSubview(label)
            }
            y -= 28
        }
        return view
    }
}

@MainActor
final class AppSurfaceView: NSView {
    var rounded = false
    override var isOpaque: Bool { !rounded }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        if rounded { NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill() }
        else { bounds.fill() }
    }
}
