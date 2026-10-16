import Foundation

@MainActor public final class RuntimeController {
    public private(set) var state: AppState = .off
    public private(set) var connected = false
    public private(set) var lastMessage: String?
    public var onChange: (() -> Void)?
    public var profile: Profile { saved.profile }
    public var enabled: Bool { saved.enabled }
    public var receipt: OwnershipReceipt { saved.receipt }
    private let runtime: HIDRuntime
    private let input: ChordInput
    private let store: SettingsStore
    private let scheduler: ReadinessScheduler
    private var saved = SavedState()
    private var loadFailure: Error?
    private var appliedProfile: Profile?
    private var generation: UInt64 = 0
    private var retries: [Cancellation] = []

    public init(runtime: HIDRuntime, input: ChordInput, store: SettingsStore, scheduler: ReadinessScheduler? = nil) {
        self.runtime=runtime; self.input=input; self.store=store; self.scheduler=scheduler ?? MainQueueScheduler()
        do { saved=try store.load(); try saved.validate() } catch { loadFailure=error; state = .problem(error.localizedDescription); lastMessage=error.localizedDescription }
        input.onFailure = { [weak self] error in self?.inputFailed(error) }
    }
    public func start() { refresh() }
    public func refresh() {
        guard loadFailure == nil else { publish(); return }
        cancelWork()
        if enabled { reconcileWithReadiness() }
        else {
            do {
                let snapshot=try runtime.read(); connected=snapshot.isPresent
                var foreign=false
                if case .mapped(let pairs)=snapshot {
                    if saved.receipt.owns(pairs) { _ = try clearOwned() }
                    else { foreign=true }
                }
                state = .off; lastMessage=foreign ? "Назначения другой программы сохранены." : nil
            }
            catch { connected=false; setProblem(error) }
            publish()
        }
    }
    public func deviceChanged() { refresh() }
    public func setEnabled(_ enabled: Bool) throws {
        try ensureLoaded()
        let previous=saved.enabled
        saved.enabled=enabled
        if !enabled { cancelWork() }
        do { try store.save(saved) }
        catch {
            if enabled { saved.enabled=previous }
            else { _ = try? clearOwned() }
            setProblem(error); publish(); throw error
        }
        if enabled { cancelWork() }
        if enabled { reconcileWithReadiness() }
        else {
            do { let foreign=try clearOwned(); state = .off; lastMessage=foreign ? "Назначения другой программы сохранены." : nil; publish() }
            catch { setProblem(error); publish(); throw error }
        }
    }
    public func updateProfile(_ profile: Profile) throws {
        try ensureLoaded(); try profile.validate()
        let previous=saved.profile
        saved.profile=profile
        do { try store.save(saved) } catch { saved.profile=previous; throw error }
        cancelWork()
        guard enabled else { state = .off; publish(); return }
        do {
            let available=try apply(profile)
            if available { state = .active; lastMessage=nil; publish() }
            else { reconcileWithReadiness() }
        } catch {
            // Keep both pending and verified ownership through a failed write/readback.
            saved.profile=previous
            var detail=error.localizedDescription
            var restored=false
            do {
                try store.save(saved)
                restored=try apply(previous)
                if restored { detail += " Прежние назначения восстановлены." }
            } catch { input.stop(); appliedProfile=nil; detail += " Восстановление: \(error.localizedDescription)" }
            state = restored ? .active : .problem(detail); lastMessage=detail; publish()
            throw AppFailure(detail)
        }
    }
    public func requestPermissions() { input.requestPermissions(); refresh() }
    public func prepareRemoval() throws {
        // Even a failing operation leaves disabled intent and ownership for Retry.
        try setEnabled(false)
    }
    public func stopForTermination() throws {
        try ensureLoaded(); cancelWork()
        do { _ = try clearOwned() } // Preserve enabled intent for the next login.
        catch { setProblem(error); publish(); throw error }
    }
    public func inputFailed(_ error: Error) {
        cancelWork()
        var message=error.localizedDescription
        do { _ = try clearOwned() } catch { message += " Сброс назначений: \(error.localizedDescription)" }
        state = .problem(message); lastMessage=message; publish()
    }
    private func ensureLoaded() throws { if let error=loadFailure { throw error } }
    private func cancelWork() {
        generation &+= 1
        retries.forEach { $0.cancel() }; retries.removeAll()
        input.stop(); appliedProfile=nil
    }
    private func reconcileWithReadiness() {
        let token=generation
        attempt(generation: token, scheduleFurther: true)
    }
    private func attempt(generation token: UInt64, scheduleFurther: Bool) {
        guard token == generation, enabled else { return }
        do {
            if try apply(saved.profile) {
                retries.forEach { $0.cancel() }; retries.removeAll()
                state = .active; lastMessage=nil
            } else {
                state = .waiting; lastMessage=nil
                if scheduleFurther {
                    for seconds in [0.1,0.3,1.0,2.0] {
                        let cancellation=scheduler.schedule(after: seconds) { [weak self] in self?.attempt(generation: token, scheduleFurther: false) }
                        retries.append(cancellation)
                    }
                }
            }
        } catch {
            retries.forEach { $0.cancel() }; retries.removeAll()
            input.stop(); appliedProfile=nil
            var message=error.localizedDescription
            do { _ = try clearOwned() } catch { message += " Возврат кнопок: \(error.localizedDescription)" }
            if case AppState.needsPermissions = state { lastMessage=message }
            else { state = .problem(message); lastMessage=message }
        }
        publish()
    }
    private func apply(_ profile: Profile) throws -> Bool {
        if let legacy=try runtime.legacyConflict() {
            throw AppFailure("Найдена прежняя настройка EarPods (\(legacy)). Сначала отключите её автозагрузку и удалите прежнюю установку. Эта версия не меняет её файлы и назначения.")
        }
        let snapshot=try runtime.read()
        connected=snapshot.isPresent
        guard snapshot != .absent else { input.stop(); appliedProfile=nil; return false }
        if case .mapped(let pairs)=snapshot, !saved.receipt.owns(pairs) {
            throw AppFailure("EarPods уже настроены другой программой. Её назначения сохранены.")
        }
        if profile.needsChordInput {
            let permission=input.permissions()
            guard permission.ready else {
                state = .needsPermissions(permission)
                throw AppFailure("Для сочетаний разрешите нужные функции в «Конфиденциальность и безопасность».")
            }
            try input.start(profile: profile) { [weak self] button in self?.pressed(button) }
        } else { input.stop() }
        let target=MappingParser.canonical(profile.mapping)
        if snapshot != .mapped(target) {
            // A successful read proves which of our rules is currently live.
            // Preserve it as verified before replacing pending during rollback.
            if case .mapped(let current)=snapshot, saved.receipt.owns(current) { saved.receipt.verified=current }
            saved.receipt.pending=target
            try store.save(saved) // Write-ahead: recover even if the following read fails.
            try runtime.write(target)
            let verified=try runtime.read()
            guard verified == .mapped(target) else { throw AppFailure("Назначения не прошли проверку. Данные для восстановления сохранены.") }
        }
        saved.receipt.verified=target; saved.receipt.pending=nil
        try store.save(saved)
        appliedProfile=profile
        return true
    }
    private func pressed(_ button: RemoteButton) {
        guard enabled, state == .active, let current=appliedProfile, case .key(let binding)=current[button], !binding.modifiers.isEmpty else { return }
        do { try input.send(binding) } catch { inputFailed(error) }
    }
    @discardableResult private func clearOwned() throws -> Bool {
        let current=try runtime.read(); connected=current.isPresent
        if case .mapped(let pairs)=current {
            guard saved.receipt.owns(pairs) else { return true }
            try runtime.write([])
            let after=try runtime.read()
            guard after == .empty || after == .absent else { throw AppFailure("Не удалось подтвердить возврат музыкальных кнопок. Повторите удаление; данные сохранены.") }
        }
        saved.receipt=OwnershipReceipt()
        try store.save(saved)
        return false
    }
    private func setProblem(_ error: Error) { state = .problem(error.localizedDescription); lastMessage=error.localizedDescription }
    private func publish() { onChange?() }
}
