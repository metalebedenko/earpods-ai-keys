import Testing
import Foundation
@testable import EarPodsCore

@Suite struct ParsingTests {
    @Test func testNativeAbsentAndEmptyDiffer() throws {
        #expect((try MappingParser.parse("")) == (.absent))
        #expect((try MappingParser.parse("RegistryID Key Value\n")) == (.absent))
        #expect((try MappingParser.parse("RegistryID Key Value\n100084187 UserKeyMapping (null)\n")) == (.empty))
    }
    @Test func testNativeOpenStepPairs() throws {
        let pairs=Profile.standard.mapping
        let payload=pairs.map { "{ HIDKeyboardModifierMappingSrc = \($0.source); HIDKeyboardModifierMappingDst = \($0.destination); }" }.joined(separator: ",\n")
        #expect((try MappingParser.parse("RegistryID Key Value\n100084187 UserKeyMapping (\n\(payload)\n)")) == (.mapped(MappingParser.canonical(pairs))))
    }
    @Test func testMultipleAndUnknownRepliesRefuse() {
        #expect(throws: (any Error).self) { try MappingParser.parse("error-like output") }
        #expect(throws: (any Error).self) { try MappingParser.parse("A UserKeyMapping (null)\nB UserKeyMapping (null)") }
        #expect(throws: (any Error).self) { try MappingParser.parse("A UserKeyMapping ({ HIDKeyboardModifierMappingSrc=1; extra=2; })") }
    }
    @Test func testChordUsesNoEventOnlyForConfiguredButton() throws {
        var profile=Profile.standard; profile.minus = .key(KeyBinding(virtualKey: 6, modifiers: .command))
        try profile.validate()
        #expect((profile.minus.destination) == (0x700000000))
        #expect((profile.center.destination) == (0xC000000CF))
        #expect((profile.plus.destination) == (0x700000028))
    }
    @Test func testInvalidKeyAndModifierReject() {
        #expect(throws: (any Error).self) { try KeyBinding(virtualKey: 65535).validate() }
        #expect(throws: (any Error).self) { try KeyBinding(virtualKey: 6, modifiers: KeyModifiers(rawValue: 128)).validate() }
    }
    @Test func testWriteAheadOwnershipSurvivesRoundTripAndDoesNotOwnForeign() throws {
        let receipt=OwnershipReceipt(verified:Profile.standard.mapping,pending:[MappingPair(source:RemoteButton.center.source,destination:0xC000000CF),MappingPair(source:RemoteButton.minus.source,destination:0x700000000),MappingPair(source:RemoteButton.plus.source,destination:0x700000028)])
        let restored=try JSONDecoder().decode(OwnershipReceipt.self,from:JSONEncoder().encode(receipt))
        try restored.validate(); #expect(restored.owns(receipt.pending!)); #expect(restored.owns(Profile.standard.mapping))
        #expect(!(restored.owns([MappingPair(source:1,destination:2)])))
    }
    @Test func testForeignSupportFolderAndSymlinkArePreserved() throws {
        let base=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:base) }
        let store=DiskSettingsStore(directory:base.appendingPathComponent("ours"))
        try store.save(SavedState())
        try Data("keep".utf8).write(to:store.directory.appendingPathComponent("foreign.txt"))
        #expect(throws: (any Error).self) { try store.removeOwnedFiles() }; #expect(FileManager.default.fileExists(atPath:store.settingsURL.path))
        let link=base.appendingPathComponent("link"); try FileManager.default.createSymbolicLink(at:link,withDestinationURL:store.directory)
        #expect(throws: (any Error).self) { try DiskSettingsStore(directory:link).save(SavedState(enabled:true)) }
    }
}

private final class MemoryStore: SettingsStore {
    var value=SavedState(); var saves=0; var fails=false
    func load() throws -> SavedState { value }
    func save(_ state:SavedState) throws { if fails { throw AppFailure("save failed") }; value=state; saves += 1 }
    func removeOwnedFiles() throws { value=SavedState() }
}
@MainActor private final class FakeRuntime: HIDRuntime {
    var snapshot:MappingSnapshot = .empty; var writes:[[MappingPair]]=[]; var legacy:String?; var failRead=false; var failWrite=false; var wrongReadback=false; var failReadAfterWrite=false
    var readCalls=0; var writeCalls=0; var failReadsAt:Set<Int>=[]; var failWritesAt:Set<Int>=[]
    func read() throws -> MappingSnapshot { readCalls += 1; if failRead || failReadsAt.contains(readCalls) { throw AppFailure("read failed") }; return snapshot }
    func write(_ pairs:[MappingPair]) throws { writeCalls += 1; if failWrite || failWritesAt.contains(writeCalls) { throw AppFailure("write failed") }; writes.append(pairs); snapshot=wrongReadback ? .mapped([MappingPair(source:1,destination:2)]) : (pairs.isEmpty ? .empty : .mapped(MappingParser.canonical(pairs))); if failReadAfterWrite { failRead=true } }
    func legacyConflict() throws -> String? { legacy }
}
@MainActor private final class FakeInput: ChordInput {
    var onFailure:((Error)->Void)?; var grants=PermissionState(listen:true,post:true); var listener:((RemoteButton)->Void)?; var sent:[KeyBinding]=[]; var starts=0; var sendError=false
    func permissions()->PermissionState { grants }
    func requestPermissions() {}
    func start(profile:Profile,onPress:@escaping(RemoteButton)->Void)throws { starts += 1; listener=onPress }
    func stop() { listener=nil }
    func send(_ binding:KeyBinding)throws { if sendError { throw AppFailure("posting revoked") }; sent.append(binding) }
}
@MainActor private final class FakeScheduler: ReadinessScheduler {
    final class Token:Cancellation { var canceled=false; func cancel(){canceled=true}; let action:()->Void; init(_ action:@escaping()->Void){self.action=action} }
    var jobs:[Token]=[]
    func schedule(after seconds:TimeInterval,action:@escaping()->Void)->Cancellation { let token=Token(action); jobs.append(token); return token }
    func run(){ let jobs=self.jobs; self.jobs=[]; for job in jobs where !job.canceled { job.action() } }
}

@Suite struct ControllerTests {
    @Test func testLateArrivalAndDisableCancelReadiness() async throws {
        try await MainActor.run {
            let runtime=FakeRuntime(); runtime.snapshot = .absent
            let input=FakeInput(), store=MemoryStore(), scheduler=FakeScheduler()
            let controller=RuntimeController(runtime:runtime,input:input,store:store,scheduler:scheduler)
            try controller.setEnabled(true); #expect((controller.state) == (.waiting)); #expect((scheduler.jobs.count) == (4))
            try controller.setEnabled(false); runtime.snapshot = .empty; scheduler.run(); #expect(runtime.writes.isEmpty)
            try controller.setEnabled(true); #expect((controller.state) == (.active)); #expect((runtime.writes.count) == (1))
            try controller.setEnabled(false); #expect((runtime.snapshot) == (.empty)); #expect((controller.state) == (.off))
        }
    }
    @Test func testForeignAndLegacyDoNotWrite() async throws {
        try await MainActor.run {
            let runtime=FakeRuntime(); runtime.snapshot = .mapped([MappingPair(source:1,destination:2)])
            let controller=RuntimeController(runtime:runtime,input:FakeInput(),store:MemoryStore())
            try controller.setEnabled(true); #expect(runtime.writes.isEmpty)
            runtime.snapshot = .empty; runtime.legacy="legacy owner"; controller.refresh(); #expect(runtime.writes.isEmpty)
        }
    }
    @Test func testChordPermissionGatesBeforeSuppression() async throws {
        try await MainActor.run {
            let runtime=FakeRuntime(), input=FakeInput(), store=MemoryStore()
            input.grants=PermissionState(listen:false,post:true)
            let controller=RuntimeController(runtime:runtime,input:input,store:store)
            var profile=Profile.standard; profile.minus = .key(KeyBinding(virtualKey:6,modifiers:.command))
            try controller.updateProfile(profile); try controller.setEnabled(true)
            #expect((controller.state) == (.needsPermissions(input.grants))); #expect(runtime.writes.isEmpty)
            input.grants=PermissionState(listen:true,post:true); controller.refresh(); #expect((controller.state) == (.active))
            input.listener?(.minus); #expect((input.sent.count) == (1))
            input.sendError=true; input.listener?(.minus); #expect((runtime.snapshot) == (.empty))
            if case .problem=controller.state {} else { Issue.record("Revoked posting must not remain active") }
        }
    }
    @Test func testFailedClearRetainsReceiptAndDisabledIntent() async throws {
        try await MainActor.run {
            let runtime=FakeRuntime(), store=MemoryStore()
            let controller=RuntimeController(runtime:runtime,input:FakeInput(),store:store)
            try controller.setEnabled(true); let receipt=store.value.receipt
            runtime.failWrite=true; #expect(throws: (any Error).self) { try controller.prepareRemoval() }
            #expect(!(store.value.enabled)); #expect((store.value.receipt) == (receipt))
        }
    }
    @Test func testProfileFailureKeepsRecoveryOwnership() async throws {
        try await MainActor.run {
            let runtime=FakeRuntime(), store=MemoryStore()
            let controller=RuntimeController(runtime:runtime,input:FakeInput(),store:store)
            try controller.setEnabled(true); var change=Profile.standard; change.plus = .key(KeyBinding(virtualKey:48))
            runtime.failReadAfterWrite=true; #expect(throws: (any Error).self) { try controller.updateProfile(change) }
            #expect((controller.profile) == (.standard)); #expect(store.value.receipt.owns(Profile.standard.mapping))
            #expect(store.value.receipt.owns(change.mapping))
        }
    }
    @Test func testDisabledStartupRecoversOwnedMapAndClearFailureIsVisible() async throws {
        try await MainActor.run {
            let runtime=FakeRuntime(), store=MemoryStore()
            store.value=SavedState(enabled:false,receipt:OwnershipReceipt(verified:Profile.standard.mapping))
            runtime.snapshot = .mapped(MappingParser.canonical(Profile.standard.mapping))
            let controller=RuntimeController(runtime:runtime,input:FakeInput(),store:store)
            controller.start(); #expect(runtime.snapshot == .empty); #expect(controller.state == .off)
            store.value=SavedState(enabled:false,receipt:OwnershipReceipt(verified:Profile.standard.mapping))
            runtime.snapshot = .mapped(MappingParser.canonical(Profile.standard.mapping)); runtime.failWrite=true
            let failed=RuntimeController(runtime:runtime,input:FakeInput(),store:store)
            failed.start(); if case .problem=failed.state {} else { Issue.record("Failed cleanup must be visible") }
            #expect(store.value.receipt.owns(Profile.standard.mapping))
        }
    }
    @Test func testFailedRollbackStillOwnsForwardRuleAndDisableClearsIt() async throws {
        try await MainActor.run {
            let runtime=FakeRuntime(), store=MemoryStore()
            let controller=RuntimeController(runtime:runtime,input:FakeInput(),store:store)
            try controller.setEnabled(true)
            var change=Profile.standard; change.minus = .key(KeyBinding(virtualKey:6,modifiers:.command))
            runtime.failReadsAt=[4]; runtime.failWritesAt=[3]
            #expect(throws:(any Error).self) { try controller.updateProfile(change) }
            #expect(store.value.receipt.owns(change.mapping))
            #expect(runtime.snapshot == .mapped(MappingParser.canonical(change.mapping)))
            try controller.setEnabled(false); #expect(runtime.snapshot == .empty)
        }
    }
    @Test func testRestoredChordProfileStillEmitsAfterRejectedEdit() async throws {
        try await MainActor.run {
            let runtime=FakeRuntime(), input=FakeInput(), store=MemoryStore()
            var original=Profile.standard; original.minus = .key(KeyBinding(virtualKey:6,modifiers:.command))
            store.value.profile=original
            let controller=RuntimeController(runtime:runtime,input:input,store:store)
            try controller.setEnabled(true)
            var change=original; change.plus = .key(KeyBinding(virtualKey:36,modifiers:.command))
            runtime.failWritesAt=[2]
            #expect(throws:(any Error).self) { try controller.updateProfile(change) }
            #expect(controller.state == .active); #expect(controller.profile == original)
            input.listener?(.minus); #expect(input.sent == [KeyBinding(virtualKey:6,modifiers:.command)])
        }
    }
    @Test func testQuitPreservesLoginIntentAndFailedQuitStopsClaimingActive() async throws {
        try await MainActor.run {
            let runtime=FakeRuntime(), store=MemoryStore()
            let controller=RuntimeController(runtime:runtime,input:FakeInput(),store:store)
            try controller.setEnabled(true); try controller.stopForTermination()
            #expect(store.value.enabled); #expect(runtime.snapshot == .empty)
            controller.refresh(); #expect(controller.state == .active)
            runtime.failWrite=true
            #expect(throws:(any Error).self) { try controller.stopForTermination() }
            if case .problem=controller.state {} else { Issue.record("Failed termination must not remain active") }
            #expect(store.value.enabled); #expect(store.value.receipt.owns(Profile.standard.mapping))
        }
    }
    @Test func testFailedDisablePersistenceStillStopsInput() async throws {
        try await MainActor.run {
            let runtime=FakeRuntime(), input=FakeInput(), store=MemoryStore()
            var profile=Profile.standard; profile.minus = .key(KeyBinding(virtualKey:6,modifiers:.command)); store.value.profile=profile
            let controller=RuntimeController(runtime:runtime,input:input,store:store)
            try controller.setEnabled(true); store.fails=true
            #expect(throws:(any Error).self) { try controller.setEnabled(false) }
            #expect(input.listener == nil); #expect(runtime.snapshot == .empty)
            if case .problem=controller.state {} else { Issue.record("Persistence error must be visible") }
        }
    }
}
