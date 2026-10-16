import AppKit
import CryptoKit
import EarPodsCore
import Foundation
import ServiceManagement

@MainActor public final class MacLoginService {
    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    private let showSettings: () -> Void

    public convenience init() {
        let service = SMAppService.mainApp
        self.init(readStatus: { service.status }, register: { try service.register() },
                  unregister: { try service.unregister() },
                  showSettings: { SMAppService.openSystemSettingsLoginItems() })
    }

    // Test adapters do not register or unregister a real login item.
    init(readStatus: @escaping () -> SMAppService.Status,
         register: @escaping () throws -> Void,
         unregister: @escaping () throws -> Void,
         showSettings: @escaping () -> Void = {}) {
        self.readStatus = readStatus; self.register = register
        self.unregister = unregister; self.showSettings = showSettings
    }

    public var enabled: Bool { readStatus() == .enabled }
    public var requiresApproval: Bool { readStatus() == .requiresApproval }
    public var statusDescription: String {
        switch readStatus() {
        case .enabled: return "Запуск при входе включён"
        case .notRegistered: return "Запуск при входе выключен"
        case .requiresApproval: return "Подтверди запуск в настройках macOS"
        case .notFound: return "Регистрация автозапуска не найдена"
        @unknown default: return "Состояние автозапуска не распознано"
        }
    }

    public func setEnabled(_ desired: Bool) throws {
        let before = readStatus()
        if desired {
            if before == .enabled || before == .requiresApproval { return }
            // A never-seen service can report .notFound. An explicit user
            // request may attempt registration; only the result proves it on.
            guard before == .notRegistered || before == .notFound else {
                throw AppFailure("Не удалось проверить автозапуск. Запусти приложение из Applications и проверь настройки macOS.")
            }
            do { try register() }
            catch let error as NSError {
                throw AppFailure("Не удалось зарегистрировать автозапуск: \(error.localizedDescription) (\(error.domain), код \(error.code)).")
            }
            let after = readStatus()
            guard after == .enabled || after == .requiresApproval else {
                throw AppFailure("macOS не подтвердила регистрацию автозапуска. Состояние службы: \(after.rawValue). Проверь «Объекты входа».")
            }
        } else {
            if before == .notRegistered { return }
            do { try unregister() }
            catch {
                // A concurrent removal can report 'not found'. Trust the
                // verified state, never an error code alone.
                guard readStatus() == .notRegistered else { throw error }
            }
            guard readStatus() == .notRegistered else {
                throw AppFailure("Отключение автозапуска не подтверждено. Приложение сохранено; попробуй ещё раз.")
            }
        }
    }
    public func openSettings() { showSettings() }
}

private struct HelperManifest: Codable {
    let schema: Int
    let token: String
    let bundleID: String
    let appPath: String
    let parentPID: Int32
    let helperDigest: String
}

@MainActor public final class MacUninstaller {
    private let prepare: () throws -> Void
    private let store: DiskSettingsStore
    private let login: MacLoginService
    private let launch: (URL, [String]) throws -> Void
    private let temporaryRoot: URL
    private let fm = FileManager.default
    private static let helperName = "EarPodsUninstallHelper"
    private static let stagePrefix = "EarPodsAIKeys-uninstall-"

    public convenience init(controller: RuntimeController, store: DiskSettingsStore, login: MacLoginService) {
        self.init(prepare: { try controller.prepareRemoval() }, store: store, login: login,
                  temporaryRoot: FileManager.default.temporaryDirectory,
                  launch: { executable, arguments in
                      let process = Process()
                      process.executableURL = executable; process.arguments = arguments
                      process.standardInput = FileHandle.nullDevice
                      try process.run()
                  })
    }

    init(prepare: @escaping () throws -> Void, store: DiskSettingsStore,
         login: MacLoginService, temporaryRoot: URL,
         launch: @escaping (URL, [String]) throws -> Void) {
        self.prepare = prepare; self.store = store; self.login = login
        self.temporaryRoot = temporaryRoot; self.launch = launch
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func regularFile(_ url: URL) -> Bool {
        ((try? fm.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType) == .typeRegular
    }

    private func validateBundle(_ supplied: URL) throws -> URL {
        guard supplied.isFileURL else { throw AppFailure("Путь приложения не является локальным файлом.") }
        let path = supplied.standardizedFileURL.resolvingSymlinksInPath()
        guard path.pathExtension == "app",
              ((try? fm.attributesOfItem(atPath: path.path)[.type]) as? FileAttributeType) == .typeDirectory else {
            throw AppFailure("Не удалось проверить папку приложения. Ничего не удалено.")
        }
        let infoURL = path.appendingPathComponent("Contents/Info.plist")
        let executable = path.appendingPathComponent("Contents/MacOS/EarPodsAIKeys")
        guard regularFile(infoURL), regularFile(executable),
              let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == AppIdentity.bundleID,
              info["CFBundleExecutable"] as? String == "EarPodsAIKeys" else {
            throw AppFailure("Идентификатор приложения не совпал. Удаление остановлено.")
        }
        guard fm.isWritableFile(atPath: path.deletingLastPathComponent().path) else {
            throw AppFailure("Нет доступа для перемещения приложения в Корзину. Перемести его в доступную папку Applications и запусти оттуда. Путь: \(path.path)")
        }
        return path
    }

    public func uninstall(appURL: URL) throws {
        let app = try validateBundle(appURL)
        let helper = app.appendingPathComponent("Contents/Helpers/" + Self.helperName)
        guard regularFile(helper), fm.isExecutableFile(atPath: helper.path) else {
            throw AppFailure("Компонент удаления отсутствует или повреждён. Приложение и настройки сохранены.")
        }
        var recovery = try store.load()
        recovery.enabled = false
        let recoveryData = try JSONEncoder().encode(recovery)
        let token = UUID().uuidString
        let stage = temporaryRoot.standardizedFileURL.resolvingSymlinksInPath()
            .appendingPathComponent(Self.stagePrefix + token, isDirectory: true)
        let stagedHelper = stage.appendingPathComponent(Self.helperName)
        let manifestURL = stage.appendingPathComponent("manifest.json")
        let recoveryURL = stage.appendingPathComponent("recovery.json")
        let helperData = try Data(contentsOf: helper)
        let helperHash = digest(helperData)
        let manifest = HelperManifest(schema: 1, token: token, bundleID: AppIdentity.bundleID,
                                      appPath: app.path, parentPID: Int32(ProcessInfo.processInfo.processIdentifier),
                                      helperDigest: helperHash)
        let manifestData = try JSONEncoder().encode(manifest)
        var stageOwned = false
        var transferred = false
        var keepRecovery = false
        defer {
            if stageOwned && !transferred && !keepRecovery {
                // Delete only byte-identical files created by this invocation.
                for (url, expected) in [(stagedHelper, helperData), (manifestURL, manifestData), (recoveryURL, recoveryData)] {
                    if regularFile(url), (try? Data(contentsOf: url)) == expected { try? fm.removeItem(at: url) }
                }
                if (try? fm.contentsOfDirectory(atPath: stage.path).isEmpty) == true { try? fm.removeItem(at: stage) }
            }
        }
        guard !fm.fileExists(atPath: stage.path) else { throw AppFailure("Временная папка удаления уже существует.") }
        try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        stageOwned = true
        try helperData.write(to: stagedHelper)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stagedHelper.path)
        try manifestData.write(to: manifestURL)
        try recoveryData.write(to: recoveryURL)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recoveryURL.path)

        do {
            try prepare()
            try login.setEnabled(false)
            try store.removeOwnedFiles()
            try launch(stagedHelper, ["--stage-token", token])
            transferred = true
        } catch {
            // The support directory may have been removed before Process.run
            // failed. Recreate the disabled recovery state before returning.
            do { try store.save(recovery) }
            catch let restoreError {
                keepRecovery = true
                throw AppFailure("Удаление остановлено. Приложение не отправлено в Корзину. Не удалось вернуть файл настроек: \(restoreError.localizedDescription). Резервная копия: \(recoveryURL.path)")
            }
            throw AppFailure("Удаление остановлено. Приложение и восстановление настроек сохранены; режим выключен. Попробуй ещё раз. Причина: \(error.localizedDescription)")
        }
    }
}
