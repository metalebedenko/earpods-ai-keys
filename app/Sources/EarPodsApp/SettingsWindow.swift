import AppKit
import EarPodsCore

@MainActor
final class SettingsWindowController: NSWindowController {
    private let onSave: (Profile) throws -> Void
    private let onPermissions: () -> Void
    private var actualProfile: Profile
    private var rows: [RemoteButton: ActionRow] = [:]
    private let status = NSTextField(labelWithString: "Режим выключен")
    private let message = NSTextField(wrappingLabelWithString: "")
    private let result = NSTextField(wrappingLabelWithString: "")
    private let applyButton = NSButton(title: "Применить", target: nil, action: nil)
    private let permissionButton = NSButton(title: "Разрешения macOS…", target: nil, action: nil)

    init(profile: Profile, onSave: @escaping (Profile) throws -> Void, onPermissions: @escaping () -> Void) {
        self.actualProfile=profile; self.onSave=onSave; self.onPermissions=onPermissions
        let window = RecorderWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 520),
                                    styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Кнопки EarPods"
        window.isReleasedWhenClosed = false
        window.contentView = AppSurfaceView(frame: NSRect(x: 0, y: 0, width: 580, height: 520))
        super.init(window: window)
        buildContent(profile)
        window.center()
    }
    required init?(coder: NSCoder) { nil }

    private func buildContent(_ profile: Profile) {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: "Три кнопки — ваши действия")
        title.font = .boldSystemFont(ofSize: 20)
        title.frame = NSRect(x: 26, y: 458, width: 528, height: 27)
        content.addSubview(title)
        status.font = .systemFont(ofSize: 13, weight: .medium)
        status.frame = NSRect(x: 26, y: 428, width: 528, height: 20)
        content.addSubview(status)
        message.font = .systemFont(ofSize: 12)
        message.textColor = .secondaryLabelColor
        message.frame = NSRect(x: 26, y: 380, width: 528, height: 43)
        content.addSubview(message)
        for (index, button) in RemoteButton.allCases.enumerated() {
            let row = ActionRow(button: button, action: profile[button]) { [weak self] in self?.draftChanged() }
            row.frame = NSRect(x: 26, y: CGFloat(316-index*62), width: 528, height: 50)
            rows[button] = row
            content.addSubview(row)
        }
        let note = NSTextField(wrappingLabelWithString: "Чтобы записать клавишу, нажмите поле справа. Поддерживаются ⌘, ⌃, ⌥ и ⇧. Сочетания пока требуют проверки на реальных EarPods.\n\nДля Диктовки включите её в macOS и выключите Siri вручную. Enter выполняет обычное действие активного окна.")
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor
        note.frame = NSRect(x: 26, y: 94, width: 528, height: 93)
        content.addSubview(note)
        result.font = .systemFont(ofSize: 12)
        result.textColor = .secondaryLabelColor
        result.frame = NSRect(x: 26, y: 57, width: 528, height: 34)
        content.addSubview(result)
        let reset = NSButton(title: "Сбросить назначения", target: self, action: #selector(resetAssignments))
        reset.bezelStyle = .rounded
        reset.frame = NSRect(x: 22, y: 20, width: 167, height: 30)
        content.addSubview(reset)
        permissionButton.target = self
        permissionButton.action = #selector(requestPermissions)
        permissionButton.bezelStyle = .rounded
        permissionButton.frame = NSRect(x: 198, y: 20, width: 189, height: 30)
        content.addSubview(permissionButton)
        applyButton.target = self
        applyButton.action = #selector(applyAssignments)
        applyButton.bezelStyle = .rounded
        applyButton.frame = NSRect(x: 447, y: 20, width: 111, height: 30)
        content.addSubview(applyButton)
        draftChanged()
    }

    func updateActual(profile: Profile, state: AppState, connected: Bool, message detail: String?) {
        if actualProfile != profile {
            actualProfile = profile
            for button in RemoteButton.allCases { rows[button]?.load(profile[button]) }
            draftChanged()
        }
        status.stringValue = state.title + " · " + MenuPresentation.connectionTitle(state: state, connected: connected)
        if case .problem(let problem) = state { message.stringValue = problem }
        else if case .needsPermissions = state { message.stringValue = "Для сочетаний разрешите ввод и управление в macOS. Затем повторите проверку в меню." }
        else { message.stringValue = detail ?? "Назначения сохраняются. При включённом режиме приложение восстанавливает их после подключения." }
        message.toolTip = message.stringValue
        permissionButton.isHidden = !profile.needsChordInput && !hasChordDraft
    }

    private var hasChordDraft: Bool { rows.values.contains { $0.action?.isChord == true } }
    private var draft: Profile? {
        guard let center=rows[.center]?.action, let minus=rows[.minus]?.action, let plus=rows[.plus]?.action else { return nil }
        return Profile(center: center, minus: minus, plus: plus)
    }
    private func draftChanged() {
        applyButton.isEnabled = draft != nil && draft != actualProfile
        permissionButton.isHidden = !actualProfile.needsChordInput && !hasChordDraft
        result.stringValue = draft == nil ? "Запишите клавишу для выбранного действия." : (draft == actualProfile ? "" : "Есть несохранённые назначения.")
        result.textColor = .secondaryLabelColor
        result.toolTip = nil
    }
    @objc private func applyAssignments() {
        guard let profile = draft else { return }
        save(profile)
    }
    @objc private func resetAssignments() { save(.standard) }
    private func save(_ profile: Profile) {
        do {
            try profile.validate()
            try onSave(profile)
            actualProfile = profile
            for button in RemoteButton.allCases { rows[button]?.load(profile[button]) }
            draftChanged()
            result.stringValue = "Назначения сохранены."
            result.toolTip = nil
        } catch {
            result.stringValue = "Не применено: " + error.localizedDescription
            result.textColor = .systemRed
            result.toolTip = result.stringValue
        }
    }
    @objc private func requestPermissions() { onPermissions() }
}

@MainActor
private final class ActionRow: NSView {
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let recorder = KeyRecorder(frame: .zero)
    private let onChange: () -> Void
    private var key: KeyBinding?
    var action: ButtonAction? {
        popup.indexOfSelectedItem == 0 ? .dictation : key.map(ButtonAction.key)
    }

    init(button: RemoteButton, action: ButtonAction, onChange: @escaping () -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: button == .center ? "Центр" : (button == .minus ? "Минус −" : "Плюс +"))
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.frame = NSRect(x: 0, y: 16, width: 83, height: 19)
        addSubview(label)
        popup.frame = NSRect(x: 88, y: 10, width: 195, height: 30)
        popup.addItems(withTitles: ["Диктовка macOS", "Клавиша / сочетание"])
        popup.target = self
        popup.action = #selector(selectAction)
        addSubview(popup)
        recorder.frame = NSRect(x: 290, y: 10, width: 238, height: 30)
        recorder.onRecord = { [weak self] binding in self?.key=binding; self?.onChange() }
        addSubview(recorder)
        load(action)
    }
    required init?(coder: NSCoder) { nil }
    func load(_ action: ButtonAction) {
        recorder.cancelRecording()
        switch action {
        case .dictation: popup.selectItem(at: 0); key=nil
        case .key(let binding): popup.selectItem(at: 1); key=binding
        }
        recorder.binding = key
        recorder.isEnabled = popup.indexOfSelectedItem == 1
    }
    @objc private func selectAction() {
        recorder.cancelRecording()
        recorder.isEnabled = popup.indexOfSelectedItem == 1
        recorder.binding = key
        onChange()
        if recorder.isEnabled { recorder.beginRecording() }
    }
}

// Receives events only as the focused responder in this settings window.
@MainActor
private final class KeyRecorder: NSButton {
    var onRecord: ((KeyBinding) -> Void)?
    var binding: KeyBinding? { didSet { updateTitle() } }
    private(set) var recording = false
    override var acceptsFirstResponder: Bool { isEnabled }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target=self; action=#selector(startRecording)
        font = .systemFont(ofSize: 13)
        setAccessibilityLabel("Записать клавишу или сочетание")
        updateTitle()
    }
    required init?(coder: NSCoder) { nil }
    @objc private func startRecording() { beginRecording() }
    func beginRecording() {
        guard isEnabled, window?.makeFirstResponder(self) == true else { return }
        recording=true
        title="Нажмите клавишу…"
    }
    func cancelRecording() {
        recording=false
        updateTitle()
    }
    override func resignFirstResponder() -> Bool {
        recording=false; updateTitle()
        return super.resignFirstResponder()
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        record(event)
    }
    override func flagsChanged(with event: NSEvent) {
        guard recording else { return }
        title = modifiers(event.modifierFlags).symbols + "Нажмите клавишу…"
    }
    func record(_ event: NSEvent) {
        guard recording, isEnabled, event.type == .keyDown, !event.isARepeat else { return }
        guard KeyCatalog.key(event.keyCode) != nil else {
            title="Эта клавиша не поддерживается"
            return
        }
        let binding = KeyBinding(virtualKey: event.keyCode, modifiers: modifiers(event.modifierFlags))
        self.binding=binding
        recording=false
        updateTitle()
        onRecord?(binding)
    }
    private func modifiers(_ flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var value: KeyModifiers = []
        if flags.contains(.command) { value.insert(.command) }
        if flags.contains(.control) { value.insert(.control) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.shift) { value.insert(.shift) }
        return value
    }
    private func updateTitle() { title = binding?.title ?? "Записать клавишу…" }
}

@MainActor
private final class RecorderWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let recorder = firstResponder as? KeyRecorder, recorder.recording {
            recorder.record(event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
