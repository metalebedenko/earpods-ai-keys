import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem
import CoreGraphics
import EarPodsCore

private let earPodsRawValue: IOHIDValueCallback = { context, result, _, value in
    guard let context else { return }
    // Scheduled on the main run loop; delivery and the synthetic pair stay on
    // the same actor as profile changes and controller cancellation.
    MainActor.assumeIsolated {
        Unmanaged<NativeChordInput>.fromOpaque(context).takeUnretainedValue().receive(result: result, value: value)
    }
}

@MainActor
public final class NativeChordInput: ChordInput {
    private var device: IOHIDDevice?
    private var chordButtons: Set<RemoteButton> = []
    private var pressed: Set<RemoteButton> = []
    private var onPress: ((RemoteButton) -> Void)?
    private var failure: AppFailure?

    // The protocol's press callback cannot express asynchronous IOKit errors.
    // The controller can use this hook to clear an exactly owned map and show
    // the failure. No input callback silently replaces a failed backend.
    public var onFailure: ((Error) -> Void)?

    public init() {}

    public func permissions() -> PermissionState {
        PermissionState(listen: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted,
                        post: CGPreflightPostEventAccess())
    }

    public func requestPermissions() {
        let state = permissions()
        if !state.listen { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
        if !state.post { _ = CGRequestPostEventAccess() }
    }

    public func start(profile: Profile, onPress: @escaping (RemoteButton) -> Void) throws {
        try profile.validate()
        stop()
        failure = nil
        guard profile.needsChordInput else { return }
        guard permissions().ready else { throw AppFailure("Для сочетаний нужны разрешения «Мониторинг ввода» и «Универсальный доступ».") }

        let device = try singleDevice()
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            throw AppFailure("Не удалось открыть ввод EarPods без эксклюзивного захвата (IOKit \(result)).")
        }
        chordButtons = Set(RemoteButton.allCases.filter { profile[$0].isChord })
        let elements = chordButtons.map { button in
            [kIOHIDElementUsagePageKey: UInt32(12), kIOHIDElementUsageKey: UInt32(button.source & 0xFFFFFFFF)]
        }
        IOHIDDeviceSetInputValueMatchingMultiple(device, elements as CFArray)
        self.device = device
        self.onPress = onPress
        IOHIDDeviceRegisterInputValueCallback(device, earPodsRawValue, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }

    public func stop() {
        onPress = nil
        chordButtons.removeAll()
        pressed.removeAll()
        guard let device else { return }
        self.device = nil
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    public func send(_ binding: KeyBinding) throws {
        try binding.validate()
        if let failure { throw failure }
        guard device != nil else { throw AppFailure("Обработка сочетаний EarPods остановлена.") }
        guard CGPreflightPostEventAccess() else {
            stop()
            throw AppFailure("macOS не разрешает отправку сочетаний. Проверьте «Универсальный доступ».")
        }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: binding.virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: binding.virtualKey, keyDown: false) else {
            stop()
            throw AppFailure("Не удалось создать нажатие и отпускание клавиши.")
        }
        var flags: CGEventFlags = []
        if binding.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if binding.modifiers.contains(.control) { flags.insert(.maskControl) }
        if binding.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if binding.modifiers.contains(.shift) { flags.insert(.maskShift) }
        down.flags = flags
        up.flags = flags

        // A complete synchronous pair; no separate modifier-down events and no
        // await/cancellation point. Even denial after down attempts the up.
        down.post(tap: .cgSessionEventTap)
        let allowedAfterDown = CGPreflightPostEventAccess()
        up.post(tap: .cgSessionEventTap)
        let allowedAfterUp = CGPreflightPostEventAccess()
        guard allowedAfterDown && allowedAfterUp else {
            stop()
            throw AppFailure("Разрешение отправки было отозвано. Отпускание клавиши попытались отправить; доставка не подтверждена.")
        }
        // CGEventPost returns void; success here is not proof of delivery to a
        // focused app. The hardware acceptance test must check actual behavior.
    }

    fileprivate func receive(result: IOReturn, value: IOHIDValue) {
        guard let device else { return }
        guard result == kIOReturnSuccess else {
            fail(AppFailure("Ошибка чтения кнопки EarPods (IOKit \(result))."))
            return
        }
        let element = IOHIDValueGetElement(value)
        let origin = IOHIDElementGetDevice(element)
        guard CFEqual(origin, device),
              let button = RemoteButton.from(usagePage: IOHIDElementGetUsagePage(element), usage: IOHIDElementGetUsage(element)),
              chordButtons.contains(button) else { return }
        guard permissions().ready else {
            fail(AppFailure("Разрешения обработки сочетаний отозваны. Проверьте настройки конфиденциальности macOS."))
            return
        }
        let integer = IOHIDValueGetIntegerValue(value)
        if integer == 0 { pressed.remove(button); return }
        guard integer > 0, pressed.insert(button).inserted else { return }
        onPress?(button)
    }

    private func fail(_ error: AppFailure) {
        stop()
        failure = error
        onFailure?(error)
    }

    private func singleDevice() throws -> IOHIDDevice {
        var iterator: io_iterator_t = IO_OBJECT_NULL
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, try EarPodsDeviceMatch.dictionary(), &iterator)
        guard result == KERN_SUCCESS else { throw AppFailure("Не удалось найти устройство EarPods (IOKit \(result)).") }
        defer { if iterator != IO_OBJECT_NULL { IOObjectRelease(iterator) } }
        var devices: [IOHIDDevice] = []
        while iterator != IO_OBJECT_NULL {
            let service = IOIteratorNext(iterator)
            guard service != IO_OBJECT_NULL else { break }
            defer { IOObjectRelease(service) }
            guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service), EarPodsDeviceMatch.isExpected(device) else {
                throw AppFailure("Сервис ввода не подтверждён как нужный Consumer Control EarPods.")
            }
            devices.append(device)
        }
        guard devices.count == 1, let device = devices.first else {
            throw AppFailure(devices.isEmpty ? "EarPods ещё не доступны для чтения кнопок." : "Подключено несколько подходящих устройств EarPods. Выберите одно.")
        }
        return device
    }

    deinit {
        if let device {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
}
