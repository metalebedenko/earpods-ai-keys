import Foundation
import Darwin
import EarPodsCore

struct NativeToolResult {
    let status: Int32
    let output: String
}

enum NativeToolFailure: LocalizedError, Equatable {
    case invalidLimits, timeout, outputLimit, invalidUTF8
    case launch(String), pipe(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidLimits: return "Некорректные ограничения системной команды. Изменения остановлены."
        case .timeout: return "Системная команда не завершилась вовремя. Завершение процесса запрошено; ответ не использован."
        case .outputLimit: return "Ответ системной команды превышает 64 КиБ или установленный меньший предел. Завершение процесса запрошено; ответ не использован."
        case .invalidUTF8: return "Системная команда вернула нечитаемый ответ. Изменения остановлены."
        case .launch(let detail): return "Не удалось запустить системную команду: \(detail)"
        case .pipe(let code): return "Не удалось прочитать ответ системной команды (errno \(code)). Изменения остановлены."
        }
    }
}

private func stopNativeChild(_ process: Process, pid: pid_t) {
    guard process.isRunning else { return }
    _ = Darwin.kill(pid, SIGTERM)
    let grace = ProcessInfo.processInfo.systemUptime + 0.1
    while process.isRunning && ProcessInfo.processInfo.systemUptime < grace { _ = Darwin.poll(nil, 0, 10) }
    if process.isRunning {
        _ = Darwin.kill(pid, SIGKILL)
        // Foundation owns child reaping; give its termination monitor a bounded
        // opportunity to finish. Never wait indefinitely after a failed command.
        let killGrace = ProcessInfo.processInfo.systemUptime + 0.1
        while process.isRunning && ProcessInfo.processInfo.systemUptime < killGrace { _ = Darwin.poll(nil, 0, 10) }
    }
}

// Internal limits allow short isolated process tests. Production callers below
// always use the fixed native paths, a 3-second deadline and at most 64 KiB.
// No shell, PATH lookup, environment-selected tool or device polling is used.
func runNativeTool(_ path: String, arguments: [String],
                   deadline seconds: TimeInterval = 3,
                   maximumOutputBytes: Int = 64 * 1024) throws -> NativeToolResult {
    guard seconds > 0, seconds <= 5, maximumOutputBytes > 0, maximumOutputBytes <= 64 * 1024 else {
        throw NativeToolFailure.invalidLimits
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    var environment = ProcessInfo.processInfo.environment
    environment["LC_ALL"] = "C"
    process.environment = environment
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    process.standardInput = FileHandle.nullDevice
    let descriptor = pipe.fileHandleForReading.fileDescriptor
    var childPID: pid_t?
    var completed = false
    defer {
        // Close the parent's handles first, including an inherited writer that
        // could otherwise prevent EOF. Partial data is never returned on error.
        try? pipe.fileHandleForReading.close()
        try? pipe.fileHandleForWriting.close()
        if !completed, let childPID { stopNativeChild(process, pid: childPID) }
    }
    let flags = Darwin.fcntl(descriptor, F_GETFL)
    guard flags >= 0, Darwin.fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
        throw NativeToolFailure.pipe(errno)
    }
    do { try process.run() }
    catch { throw NativeToolFailure.launch(error.localizedDescription) }
    childPID = process.processIdentifier
    try? pipe.fileHandleForWriting.close()
    let deadline = ProcessInfo.processInfo.systemUptime + seconds
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    var eof = false

    while true {
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { throw NativeToolFailure.timeout }
        let milliseconds = Int32(min(20, max(1, ceil(remaining * 1000))))
        if eof {
            // A child may close both output streams and keep running. EOF alone
            // is not completion and must never be interpreted as HID absence.
            _ = Darwin.poll(nil, 0, milliseconds)
        } else {
            var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP | POLLERR), revents: 0)
            let ready = Darwin.poll(&pollDescriptor, 1, milliseconds)
            if ready < 0 {
                if errno == EINTR { continue }
                throw NativeToolFailure.pipe(errno)
            }
            if ready > 0 {
                guard pollDescriptor.revents & Int16(POLLNVAL) == 0 else { throw NativeToolFailure.pipe(EBADF) }
                while true {
                    guard ProcessInfo.processInfo.systemUptime < deadline else { throw NativeToolFailure.timeout }
                    let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
                    if count > 0 {
                        guard count <= maximumOutputBytes - data.count else { throw NativeToolFailure.outputLimit }
                        data.append(contentsOf: buffer.prefix(count))
                    } else if count == 0 {
                        eof = true
                        break
                    } else if errno == EINTR {
                        continue
                    } else if errno == EAGAIN || errno == EWOULDBLOCK {
                        break
                    } else {
                        throw NativeToolFailure.pipe(errno)
                    }
                }
            }
        }
        if eof && !process.isRunning { break }
    }
    guard let output = String(data: data, encoding: .utf8) else {
        throw NativeToolFailure.invalidUTF8
    }
    completed = true
    return NativeToolResult(status: process.terminationStatus, output: output)
}

@MainActor
public final class NativeHIDRuntime: HIDRuntime {
    private var lastRead: MappingSnapshot?

    public init() {}

    public func read() throws -> MappingSnapshot {
        lastRead = nil
        let result = try runNativeTool("/usr/bin/hidutil", arguments: [
            "property", "--matching", EarPodsDeviceMatch.hidutilJSON, "--get", "UserKeyMapping"
        ])
        guard result.status == 0 else {
            throw toolFailure("Не удалось прочитать назначения EarPods", result)
        }
        // The parser refuses multiple rows, unknown properties and malformed
        // nonempty output. A successful blank response means device absent.
        let snapshot = try MappingParser.parse(result.output)
        lastRead = snapshot
        return snapshot
    }

    public func write(_ pairs: [MappingPair]) throws {
        // A write or failed attempt invalidates the prior snapshot, including
        // timeouts where the child might have changed HID before being stopped.
        defer { lastRead = nil }
        guard getuid() != 0, geteuid() != 0 else {
            throw AppFailure("Запустите приложение от обычного пользователя, без sudo.")
        }
        if !pairs.isEmpty { try OwnershipReceipt(verified: pairs).validate() }
        guard let expected = lastRead else {
            throw AppFailure("Перед изменением нужно проверить текущие назначения EarPods.")
        }
        // Refuse a missing, malformed or ambiguous target before every write.
        // Receipt ownership and legacy refusal belong to the serial controller;
        // this adapter cannot infer ownership merely from a familiar rule.
        let current = try read()
        guard current.isPresent else { throw AppFailure("EarPods отключены; правило не изменено.") }
        guard current == expected else {
            throw AppFailure("Назначения EarPods изменились после проверки. Новое правило сохранено; запись отменена.")
        }
        let result = try runNativeTool("/usr/bin/hidutil", arguments: [
            "property", "--matching", EarPodsDeviceMatch.hidutilJSON,
            "--set", try MappingParser.json(MappingParser.canonical(pairs))
        ])
        guard result.status == 0 else { throw toolFailure("Не удалось изменить назначения EarPods", result) }
    }

    public func legacyConflict() throws -> String? {
        var completed = false
        defer { if !completed { lastRead = nil } }
        let home = FileManager.default.homeDirectoryForCurrentUser
        for label in ["local.earpods-macos-dictation", "local.earpods-gpt-dictation", "local.earpods-ai-keys"] {
            let plist = home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
            // attributesOfItem sees even a broken symlink; unknown files are a
            // conflict, never an invitation to overwrite or adopt the old job.
            do {
                _ = try FileManager.default.attributesOfItem(atPath: plist.path)
                completed = true
                return label
            } catch {
                let error = error as NSError
                guard error.domain == NSCocoaErrorDomain,
                      error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError else {
                    throw AppFailure("Не удалось проверить прежнюю установку \(label): \(error.localizedDescription)")
                }
            }
            let result = try runNativeTool("/bin/launchctl", arguments: ["print", "gui/\(getuid())/\(label)"])
            if result.status == 0 { completed = true; return label }
            guard result.output.contains("Could not find service") else {
                throw toolFailure("Не удалось проверить прежнюю задачу \(label)", result)
            }
        }
        completed = true
        return nil
    }

    private func toolFailure(_ message: String, _ result: NativeToolResult) -> AppFailure {
        let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return AppFailure("\(message) (код \(result.status))." + (detail.isEmpty ? "" : " \(detail.prefix(4096))"))
    }
}
