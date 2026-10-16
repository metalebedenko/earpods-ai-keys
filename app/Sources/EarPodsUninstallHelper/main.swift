import AppKit
import CryptoKit
import Darwin
import EarPodsCore
import Foundation

private struct HelperManifest: Codable {
    let schema: Int
    let token: String
    let bundleID: String
    let appPath: String
    let parentPID: Int32
    let helperDigest: String
}

private let fm = FileManager.default
private let prefix = "EarPodsAIKeys-uninstall-"
private let helperName = "EarPodsUninstallHelper"

private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
private func regularFile(_ url: URL) -> Bool {
    ((try? fm.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType) == .typeRegular
}
private func validatedApp(_ path: String) throws -> URL {
    let supplied = URL(fileURLWithPath: path).standardizedFileURL
    let canonical = supplied.resolvingSymlinksInPath()
    guard supplied.path == canonical.path, canonical.pathExtension == "app",
          ((try? fm.attributesOfItem(atPath: canonical.path)[.type]) as? FileAttributeType) == .typeDirectory else {
        throw AppFailure("Путь приложения изменился. Файл оставлен без изменений: \(path)")
    }
    let infoURL = canonical.appendingPathComponent("Contents/Info.plist")
    let executable = canonical.appendingPathComponent("Contents/MacOS/EarPodsAIKeys")
    guard regularFile(infoURL), regularFile(executable),
          let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as? [String: Any],
          info["CFBundleIdentifier"] as? String == AppIdentity.bundleID,
          info["CFBundleExecutable"] as? String == "EarPodsAIKeys" else {
        throw AppFailure("Идентификатор приложения изменился. Файл не удалён: \(path)")
    }
    return canonical
}

private func reportFailure(_ message: String, appURL: URL?) {
    fputs("EarPods uninstall: \(message)\n", stderr)
    NSApplication.shared.setActivationPolicy(.accessory)
    let alert = NSAlert()
    alert.messageText = "Удаление приложения не завершено"
    alert.informativeText = message + "\nПравило и автозапуск уже отключены, если основной этап завершился. Корзина не очищается автоматически."
    alert.addButton(withTitle: appURL == nil ? "Закрыть" : "Показать в Finder")
    if appURL != nil { alert.addButton(withTitle: "Закрыть") }
    NSApplication.shared.activate(ignoringOtherApps: true)
    let response = alert.runModal()
    if response == .alertFirstButtonReturn, let appURL = appURL {
        NSWorkspace.shared.activateFileViewerSelecting([appURL])
    }
}

private func run() -> Int32 {
    let args = CommandLine.arguments
    guard args.count == 3, args[1] == "--stage-token", UUID(uuidString: args[2]) != nil else {
        fputs("This helper is launched only by EarPods AI Keys Uninstall.\n", stderr)
        return 2
    }
    let executable = URL(fileURLWithPath: args[0]).standardizedFileURL
    let stage = executable.deletingLastPathComponent()
    let token = args[2]
    guard executable.lastPathComponent == helperName,
          executable.path == executable.resolvingSymlinksInPath().path,
          stage.lastPathComponent == prefix + token,
          stage.deletingLastPathComponent().path == fm.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath().path,
          regularFile(executable) else {
        reportFailure("Временный компонент удаления не распознан. Ничего не перемещено.", appURL: nil)
        return 1
    }
    let manifestURL = stage.appendingPathComponent("manifest.json")
    let recoveryURL = stage.appendingPathComponent("recovery.json")
    var appURL: URL?
    do {
        guard regularFile(manifestURL), regularFile(recoveryURL) else {
            throw AppFailure("Временные данные удаления отсутствуют или заменены.")
        }
        let manifestData = try Data(contentsOf: manifestURL)
        let recoveryData = try Data(contentsOf: recoveryURL)
        let helperData = try Data(contentsOf: executable)
        let manifest = try JSONDecoder().decode(HelperManifest.self, from: manifestData)
        guard manifest.schema == 1, manifest.token == token,
              manifest.bundleID == AppIdentity.bundleID,
              manifest.helperDigest == digest(helperData),
              manifest.parentPID > 1, manifest.parentPID != getpid() else {
            throw AppFailure("Данные компонента удаления не совпали. Ничего не перемещено.")
        }
        defer {
            // This process owns only these three temporary files. Keep any
            // replaced/extra data; never remove a folder recursively.
            for (url, expected) in [(executable, helperData), (manifestURL, manifestData), (recoveryURL, recoveryData)] {
                if regularFile(url), (try? Data(contentsOf: url)) == expected { try? fm.removeItem(at: url) }
            }
            if (try? fm.contentsOfDirectory(atPath: stage.path).isEmpty) == true { try? fm.removeItem(at: stage) }
        }
        appURL = URL(fileURLWithPath: manifest.appPath)
        let deadline = ProcessInfo.processInfo.systemUptime + 15
        while kill(manifest.parentPID, 0) == 0 || errno == EPERM {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw AppFailure("Приложение ещё работает, поэтому файл не перемещён. Заверши его и убери через Finder. Путь: \(manifest.appPath)")
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard errno == ESRCH else {
            throw AppFailure("Не удалось проверить завершение приложения. Файл оставлен: \(manifest.appPath)")
        }
        let verified = try validatedApp(manifest.appPath)
        var trashed: NSURL?
        try fm.trashItem(at: verified, resultingItemURL: &trashed)
        guard let trashed = trashed, fm.fileExists(atPath: trashed.path ?? ""),
              !fm.fileExists(atPath: verified.path) else {
            throw AppFailure("Перемещение в Корзину не подтверждено. Проверь путь: \(manifest.appPath)")
        }
        return 0
    } catch {
        reportFailure(error.localizedDescription, appURL: appURL)
        return 1
    }
}

exit(run())
