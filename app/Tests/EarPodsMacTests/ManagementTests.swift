import EarPodsCore
@testable import EarPodsMac
import Foundation
import ServiceManagement
import Testing

@MainActor private final class LoginDouble {
    var status: SMAppService.Status = .enabled
    var registrationResult: SMAppService.Status = .enabled
    var registrationError: NSError?
    var registerCalls = 0
    var failUnregister = false
    var unregisterCalls = 0
    func service() -> MacLoginService {
        MacLoginService(readStatus: { self.status }, register: {
                            self.registerCalls += 1
                            if let error = self.registrationError { throw error }
                            self.status = self.registrationResult
                        },
                        unregister: {
                            self.unregisterCalls += 1
                            if self.failUnregister { throw AppFailure("unregister failed") }
                            self.status = .notRegistered
                        })
    }
}

@MainActor private final class RemovalFixture {
    let root: URL
    let app: URL
    let store: DiskSettingsStore
    let original = SavedState(enabled: true, receipt: OwnershipReceipt(verified: Profile.standard.mapping))
    let login = LoginDouble()
    var prepared = false
    var launched = false
    var stage: URL?

    init(bundleID: String = AppIdentity.bundleID) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("EarPods-management-test-" + UUID().uuidString, isDirectory: true)
        app = root.appendingPathComponent("EarPods AI Keys.app", isDirectory: true)
        store = DiskSettingsStore(directory: root.appendingPathComponent("Support", isDirectory: true))
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/Helpers"), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleExecutable": "EarPodsAIKeys"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        for name in ["MacOS/EarPodsAIKeys", "Helpers/EarPodsUninstallHelper"] {
            let url = app.appendingPathComponent("Contents/" + name)
            try Data([1, 2, 3]).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
        try store.save(original)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func uninstaller(prepare: (() throws -> Void)? = nil,
                     launch: ((URL, [String]) throws -> Void)? = nil) -> MacUninstaller {
        MacUninstaller(prepare: prepare ?? { self.prepared = true }, store: store, login: login.service(), temporaryRoot: root,
                       launch: launch ?? { executable, args in
                           self.launched = true; self.stage = executable.deletingLastPathComponent()
                           #expect(args.first == "--stage-token")
                           #expect(!FileManager.default.fileExists(atPath: self.store.directory.path))
                       })
    }
    var stages: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("EarPodsAIKeys-uninstall-") }
    }
}

@Suite @MainActor struct ManagementTests {
    @Test func loginApprovalIsVisibleRatherThanEnabled() throws {
            let double = LoginDouble(); double.status = .notRegistered; double.registrationResult = .requiresApproval
            let service = double.service()
            try service.setEnabled(true)
            #expect(service.requiresApproval); #expect(!service.enabled)
            #expect(service.statusDescription.contains("Подтверди"))
    }
    @Test func loginUnregistrationFailureAndNotFoundAreRefused() throws {
            let double = LoginDouble(); double.failUnregister = true
            #expect(throws: AppFailure.self) { try double.service().setEnabled(false) }
            double.status = .notFound
            #expect(throws: AppFailure.self) { try double.service().setEnabled(false) }
            #expect(double.unregisterCalls == 2)
            #expect(double.registerCalls == 0)
    }
    @Test func firstLoginRegistrationFromNotFoundCanBecomeEnabled() throws {
            let double = LoginDouble(); double.status = .notFound
            let service = double.service()
            #expect(!service.enabled)
            #expect(service.statusDescription == "Регистрация автозапуска не найдена")
            try service.setEnabled(true)
            #expect(double.registerCalls == 1); #expect(service.enabled)
            #expect(!service.requiresApproval)
    }
    @Test func firstLoginRegistrationFromNotFoundCanRequireApproval() throws {
            let double = LoginDouble(); double.status = .notFound
            double.registrationResult = .requiresApproval
            let service = double.service()
            try service.setEnabled(true)
            #expect(double.registerCalls == 1)
            #expect(service.requiresApproval); #expect(!service.enabled)
    }
    @Test func registeredLoginEnableRequestIsIdempotent() throws {
            for status in [SMAppService.Status.enabled, .requiresApproval] {
                let double = LoginDouble(); double.status = status
                try double.service().setEnabled(true)
                #expect(double.registerCalls == 0); #expect(double.status == status)
            }
    }
    @Test func loginRegistrationErrorRetainsActualDomainAndCode() throws {
            let double = LoginDouble(); double.status = .notFound
            double.registrationError = NSError(domain: "SMAppServiceErrorDomain", code: 22,
                                               userInfo: [NSLocalizedDescriptionKey: "Invalid argument"])
            do { try double.service().setEnabled(true); Issue.record("Expected registration to fail") }
            catch {
                #expect(error.localizedDescription.contains("SMAppServiceErrorDomain"))
                #expect(error.localizedDescription.contains("код 22"))
                #expect(error.localizedDescription.contains("Invalid argument"))
            }
            #expect(double.registerCalls == 1); #expect(!double.service().enabled)
    }
    @Test func loginRegistrationReadbackCannotTreatNotFoundAsEnabled() throws {
            let double = LoginDouble(); double.status = .notFound
            double.registrationResult = .notFound
            do { try double.service().setEnabled(true); Issue.record("Expected verification to fail") }
            catch { #expect(error.localizedDescription.contains("Состояние службы: \(SMAppService.Status.notFound.rawValue)")) }
            #expect(double.registerCalls == 1); #expect(!double.service().enabled)
            #expect(!double.service().requiresApproval)
    }
    @Test func verifiedConcurrentUnregisterIsIdempotent() throws {
            var status = SMAppService.Status.enabled
            let service = MacLoginService(readStatus: { status }, register: {}, unregister: {
                status = .notRegistered; throw AppFailure("already gone")
            })
            try service.setEnabled(false)
            #expect(!service.enabled)
    }
    @Test func completeRemovalSchedulesOnlyAfterCleanup() throws {
            let fixture = try RemovalFixture(); defer { fixture.remove() }
            try fixture.uninstaller().uninstall(appURL: fixture.app)
            #expect(fixture.prepared); #expect(fixture.launched)
            #expect(fixture.login.status == .notRegistered)
            #expect(FileManager.default.fileExists(atPath: fixture.app.path)) // helper has not run
            let stage = try #require(fixture.stage)
            let snapshot = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: stage.appendingPathComponent("recovery.json")))
            #expect(!snapshot.enabled); #expect(snapshot.receipt == fixture.original.receipt)
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath: stage.path)) == Set(["EarPodsUninstallHelper", "manifest.json", "recovery.json"]))
    }
    @Test func schedulingFailureRestoresDisabledReceiptAndKeepsApp() throws {
            let fixture = try RemovalFixture(); defer { fixture.remove() }
            let remover = fixture.uninstaller(launch: { _, _ in throw AppFailure("launch failed") })
            #expect(throws: AppFailure.self) { try remover.uninstall(appURL: fixture.app) }
            let recovered = try fixture.store.load()
            #expect(!recovered.enabled); #expect(recovered.receipt == fixture.original.receipt)
            #expect(FileManager.default.fileExists(atPath: fixture.app.path))
            #expect(fixture.stages.isEmpty)
    }
    @Test func loginFailureRetainsRecoveryAndNeverSchedulesTrash() throws {
            let fixture = try RemovalFixture(); defer { fixture.remove() }
            fixture.login.failUnregister = true
            let remover = fixture.uninstaller(prepare: {
                fixture.prepared = true
                try fixture.store.save(SavedState()) // emulate successful owned-rule clear
            })
            #expect(throws: AppFailure.self) { try remover.uninstall(appURL: fixture.app) }
            #expect(!fixture.launched)
            let saved = try fixture.store.load()
            #expect(!saved.enabled); #expect(saved.receipt == fixture.original.receipt)
            #expect(fixture.stages.isEmpty)
    }
    @Test func mappingFailureStopsBeforeLoginAndKeepsReceipt() throws {
            let fixture = try RemovalFixture(); defer { fixture.remove() }
            let remover = fixture.uninstaller(prepare: { throw AppFailure("readback failed") })
            #expect(throws: AppFailure.self) { try remover.uninstall(appURL: fixture.app) }
            #expect(fixture.login.unregisterCalls == 0); #expect(!fixture.launched)
            #expect(try fixture.store.load().receipt == fixture.original.receipt)
            #expect(fixture.stages.isEmpty)
    }
    @Test func extraSupportFilePreservedAndTrashNotScheduled() throws {
            let fixture = try RemovalFixture(); defer { fixture.remove() }
            let extra = fixture.store.directory.appendingPathComponent("my-note")
            try Data("keep".utf8).write(to: extra)
            #expect(throws: AppFailure.self) { try fixture.uninstaller().uninstall(appURL: fixture.app) }
            #expect(try String(contentsOf: extra, encoding: .utf8) == "keep")
            #expect(!fixture.launched); #expect(try fixture.store.load().receipt == fixture.original.receipt)
    }
    @Test func failedSupportRecoveryKeepsStandaloneRecoveryCopy() throws {
            let fixture = try RemovalFixture(); defer { fixture.remove() }
            let remover = fixture.uninstaller(launch: { _, _ in
                try FileManager.default.createDirectory(at: fixture.store.directory, withIntermediateDirectories: true)
                try Data("another owner".utf8).write(to: fixture.store.markerURL)
                throw AppFailure("launch failed")
            })
            do { try remover.uninstall(appURL: fixture.app); Issue.record("Expected removal to fail") }
            catch { #expect(error.localizedDescription.contains("recovery.json")) }
            let stage = try #require(fixture.stages.first)
            let recovered = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: stage.appendingPathComponent("recovery.json")))
            #expect(recovered.receipt == fixture.original.receipt)
            #expect(FileManager.default.fileExists(atPath: fixture.app.path))
            #expect(try String(contentsOf: fixture.store.markerURL, encoding: .utf8) == "another owner")
    }
    @Test func foreignBundleIsRefusedBeforeCleanup() throws {
            let fixture = try RemovalFixture(bundleID: "someone.else"); defer { fixture.remove() }
            #expect(throws: AppFailure.self) { try fixture.uninstaller().uninstall(appURL: fixture.app) }
            #expect(!fixture.prepared); #expect(!fixture.launched)
            #expect(fixture.login.unregisterCalls == 0); #expect(try fixture.store.load() == fixture.original)
    }
    @Test func symlinkHelperIsRefusedBeforeCleanup() throws {
            let fixture = try RemovalFixture(); defer { fixture.remove() }
            let helper = fixture.app.appendingPathComponent("Contents/Helpers/EarPodsUninstallHelper")
            try FileManager.default.removeItem(at: helper)
            try FileManager.default.createSymbolicLink(at: helper, withDestinationURL: fixture.app.appendingPathComponent("Contents/MacOS/EarPodsAIKeys"))
            #expect(throws: AppFailure.self) { try fixture.uninstaller().uninstall(appURL: fixture.app) }
            #expect(!fixture.prepared); #expect(try fixture.store.load() == fixture.original)
    }
}
