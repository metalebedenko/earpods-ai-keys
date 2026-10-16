import Darwin
import Foundation
import Testing
@testable import EarPodsMac

// Every command in this suite is an ordinary isolated child process. No real
// hidutil, launchctl, permissions API or HID input implementation is invoked.
@Suite @MainActor struct NativeToolRunnerTests {
    @Test func ordinaryCompletionCapturesBothStreams() throws {
        #expect(Thread.isMainThread) // Same synchronous context as HIDRuntime.
        let result = try runNativeTool("/bin/sh", arguments: ["-c", "printf 'out'; printf 'err' >&2"])
        #expect(result.status == 0)
        #expect(result.output.contains("out"))
        #expect(result.output.contains("err"))
    }

    @Test func nonzeroExitIsNotConfusedWithEmptySuccessfulOutput() throws {
        let result = try runNativeTool("/bin/sh", arguments: ["-c", "printf 'diagnostic' >&2; exit 7"])
        #expect(result.status == 7)
        #expect(result.output == "diagnostic")
    }

    @Test func timeoutStopsChildAndDoesNotReturnPartialOutput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EarPods-runner-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let pidFile = root.appendingPathComponent("child.pid")
        let start = ProcessInfo.processInfo.systemUptime
        #expect(throws: NativeToolFailure.timeout) {
            try runNativeTool("/bin/sh", arguments: ["-c", "printf '%s' \"$$\" > \"$1\"; printf 'partial'; exec /bin/sleep 2", "runner-test", pidFile.path], deadline: 0.15)
        }
        #expect(ProcessInfo.processInfo.systemUptime - start < 1.2)
        let child = try #require(pid_t(try String(contentsOf: pidFile, encoding: .utf8)))
        let presence = Darwin.kill(child, 0)
        let code = errno
        #expect(presence == -1)
        #expect(code == ESRCH)
    }

    @Test func closedStreamsDoNotMakeRunningChildLookAbsent() throws {
        let start = ProcessInfo.processInfo.systemUptime
        #expect(throws: NativeToolFailure.timeout) {
            try runNativeTool("/bin/sh", arguments: ["-c", "trap '' TERM; exec /bin/sleep 2 >/dev/null 2>&1"], deadline: 0.1)
        }
        #expect(ProcessInfo.processInfo.systemUptime - start < 1.2)
    }

    @Test func defaultCombinedOutputLimitStopsUnboundedStderr() throws {
        let start = ProcessInfo.processInfo.systemUptime
        #expect(throws: NativeToolFailure.outputLimit) {
            try runNativeTool("/bin/sh", arguments: ["-c", "while :; do printf '0123456789abcdef' >&2; done"])
        }
        #expect(ProcessInfo.processInfo.systemUptime - start < 1.2)
    }

    @Test func exactLimitCanFinishNormallyAndLargerLimitsAreRejected() throws {
        let result = try runNativeTool("/bin/sh", arguments: ["-c", "printf '12345678'"], maximumOutputBytes: 8)
        #expect(result.status == 0)
        #expect(result.output == "12345678")
        #expect(throws: NativeToolFailure.invalidLimits) {
            try runNativeTool("/bin/sh", arguments: [], maximumOutputBytes: 65537)
        }
    }

    @Test func launchFailureAndInvalidEncodingAreErrors() throws {
        #expect(throws: NativeToolFailure.self) {
            try runNativeTool("/nonexistent/earpods-runner-test", arguments: [])
        }
        #expect(throws: NativeToolFailure.invalidUTF8) {
            try runNativeTool("/bin/sh", arguments: ["-c", "printf '\\377'"])
        }
    }
}
