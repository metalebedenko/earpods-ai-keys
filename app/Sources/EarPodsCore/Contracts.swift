import Foundation

public struct PermissionState: Equatable {
    public var listen: Bool
    public var post: Bool
    public init(listen: Bool, post: Bool) { self.listen=listen; self.post=post }
    public var ready: Bool { listen && post }
}

public enum AppState: Equatable {
    case off, waiting, active, needsPermissions(PermissionState), problem(String)
    public var title: String {
        switch self { case .off: return "Режим выключен"; case .waiting: return "Ждём EarPods"
        case .active: return "Пульт работает"; case .needsPermissions: return "Нужно разрешение macOS"
        case .problem: return "Нужна проверка" }
    }
}

@MainActor public protocol HIDRuntime {
    func read() throws -> MappingSnapshot
    func write(_ pairs: [MappingPair]) throws
    func legacyConflict() throws -> String?
}

@MainActor public protocol ChordInput: AnyObject {
    var onFailure: ((Error) -> Void)? { get set }
    func permissions() -> PermissionState
    func requestPermissions()
    func start(profile: Profile, onPress: @escaping (RemoteButton) -> Void) throws
    func stop()
    func send(_ binding: KeyBinding) throws
}

public struct SavedState: Codable, Equatable {
    public var schema: Int = 1
    public var enabled: Bool
    public var profile: Profile
    public var receipt: OwnershipReceipt
    public init(enabled: Bool = false, profile: Profile = .standard, receipt: OwnershipReceipt = OwnershipReceipt()) {
        self.enabled=enabled; self.profile=profile; self.receipt=receipt
    }
    public func validate() throws {
        guard schema == 1 else { throw AppFailure("Эта версия настроек не поддерживается.") }
        try profile.validate(); try receipt.validate()
    }
}

public protocol SettingsStore {
    func load() throws -> SavedState
    func save(_ state: SavedState) throws
    func removeOwnedFiles() throws
}

@MainActor public protocol Cancellation { func cancel() }
@MainActor public protocol ReadinessScheduler {
    func schedule(after seconds: TimeInterval, action: @escaping () -> Void) -> Cancellation
}

@MainActor public final class MainQueueScheduler: ReadinessScheduler {
    private final class Token: Cancellation {
        var item: DispatchWorkItem?
        func cancel() { item?.cancel(); item=nil }
    }
    public init() {}
    public func schedule(after seconds: TimeInterval, action: @escaping () -> Void) -> Cancellation {
        let token = Token()
        let item = DispatchWorkItem { [weak token] in guard token?.item?.isCancelled == false else { return }; action(); token?.item=nil }
        token.item=item; DispatchQueue.main.asyncAfter(deadline: .now()+seconds, execute: item)
        return token
    }
}

public enum AppIdentity {
    public static let bundleID = "local.earpods-ai-keys.app"
    public static let name = "EarPods AI Keys"
    public static let supportName = "EarPods AI Keys App"
    public static let ownershipMarker = "earpods-ai-keys-app-owned-v1"
}

public final class DiskSettingsStore: SettingsStore {
    public let directory: URL
    public var settingsURL: URL { directory.appendingPathComponent("settings.json") }
    public var markerURL: URL { directory.appendingPathComponent(".owned") }
    private let fm = FileManager.default
    public init(directory: URL) { self.directory=directory }
    public static func userStore() -> DiskSettingsStore {
        DiskSettingsStore(directory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/"+AppIdentity.supportName, isDirectory: true))
    }
    private func checkOwnership() throws {
        guard fm.fileExists(atPath: directory.path) else { return }
        let attrs = try fm.attributesOfItem(atPath: directory.path)
        guard attrs[.type] as? FileAttributeType == .typeDirectory,
              let data = try? Data(contentsOf: markerURL), String(data: data, encoding: .utf8) == AppIdentity.ownershipMarker,
              !isLink(markerURL), !isLink(settingsURL) else { throw AppFailure("Папка настроек не распознана как наша. Ничего не перезаписано.") }
    }
    private func isLink(_ url: URL) -> Bool { ((try? fm.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType) == .typeSymbolicLink }
    public func load() throws -> SavedState {
        try checkOwnership()
        guard fm.fileExists(atPath: settingsURL.path) else { return SavedState() }
        do { let state=try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: settingsURL)); try state.validate(); return state }
        catch { throw AppFailure("Не удалось прочитать настройки. Автоматическое управление остановлено: \(error.localizedDescription)") }
    }
    public func save(_ state: SavedState) throws {
        try state.validate(); try checkOwnership()
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try Data(AppIdentity.ownershipMarker.utf8).write(to: markerURL, options: .atomic)
        }
        let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(state).write(to: settingsURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
    }
    public func removeOwnedFiles() throws {
        try checkOwnership()
        guard fm.fileExists(atPath: directory.path) else { return }
        // Extra files are not assumed to be ours. Caller must report a partial support-folder removal.
        let allowed=Set(["settings.json", ".owned"])
        let contents=try fm.contentsOfDirectory(atPath: directory.path)
        guard Set(contents).isSubset(of: allowed) else { throw AppFailure("В папке приложения есть дополнительные файлы. Они сохранены; удаление остановлено.") }
        for name in ["settings.json", ".owned"] {
            let url=directory.appendingPathComponent(name); if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        }
        try fm.removeItem(at: directory)
    }
}
