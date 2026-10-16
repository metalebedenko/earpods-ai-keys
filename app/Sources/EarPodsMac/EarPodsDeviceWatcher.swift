import Foundation
import IOKit
import IOKit.hid
import EarPodsCore

// Shared identity for both presence notifications and nonexclusive input.
// IOPropertyMatch narrows an IOHIDDevice service, rather than observing every
// keyboard or treating a later CGEvent as evidence of device identity.
enum EarPodsDeviceMatch {
    static let hidutilJSON = "{\"VendorID\":1452,\"ProductID\":4363,\"PrimaryUsagePage\":12,\"PrimaryUsage\":1}"

    static func dictionary() throws -> CFMutableDictionary {
        guard let matching = IOServiceMatching("IOHIDDevice") else {
            throw AppFailure("Не удалось создать точный запрос устройства EarPods.")
        }
        let dictionary = matching as NSMutableDictionary
        dictionary[kIOPropertyMatchKey] = [
            kIOHIDVendorIDKey: 1452,
            kIOHIDProductIDKey: 4363,
            kIOHIDPrimaryUsagePageKey: 12,
            kIOHIDPrimaryUsageKey: 1
        ]
        return matching
    }

    static func isExpected(_ device: IOHIDDevice) -> Bool {
        let expected: [(String, UInt32)] = [
            (kIOHIDVendorIDKey, 1452), (kIOHIDProductIDKey, 4363),
            (kIOHIDPrimaryUsagePageKey, 12), (kIOHIDPrimaryUsageKey, 1)
        ]
        return expected.allSatisfy { key, value in
            guard let property = IOHIDDeviceGetProperty(device, key as CFString),
                  CFGetTypeID(property) != CFBooleanGetTypeID(),
                  let number = property as? NSNumber else { return false }
            return number.stringValue == String(value)
        }
    }
}

private let earPodsRegistryChanged: IOServiceMatchingCallback = { context, iterator in
    // Draining is required both to release service references and to rearm the
    // IOKit notification. Delivery is scheduled only on the main run loop.
    while true {
        let service = IOIteratorNext(iterator)
        guard service != IO_OBJECT_NULL else { break }
        IOObjectRelease(service)
    }
    guard let context else { return }
    MainActor.assumeIsolated {
        Unmanaged<EarPodsDeviceWatcher>.fromOpaque(context).takeUnretainedValue().changed()
    }
}

@MainActor
public final class EarPodsDeviceWatcher {
    private var port: IONotificationPortRef?
    private var source: CFRunLoopSource?
    private var arrived: io_iterator_t = IO_OBJECT_NULL
    private var removed: io_iterator_t = IO_OBJECT_NULL
    private var onChange: (() -> Void)?

    public init() {}

    public func start(onChange: @escaping () -> Void) throws {
        stop()
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            throw AppFailure("Не удалось начать наблюдение за подключением EarPods.")
        }
        guard let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() else {
            IONotificationPortDestroy(port)
            throw AppFailure("Не удалось создать источник событий подключения EarPods.")
        }
        self.port = port
        self.source = source
        self.onChange = onChange
        CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)

        do {
            let context = Unmanaged.passUnretained(self).toOpaque()
            var result = IOServiceAddMatchingNotification(
                port, kIOFirstMatchNotification, try EarPodsDeviceMatch.dictionary(),
                earPodsRegistryChanged, context, &arrived
            )
            guard result == KERN_SUCCESS else {
                throw AppFailure("Не удалось подписаться на подключение EarPods (IOKit \(result)).")
            }
            result = IOServiceAddMatchingNotification(
                port, kIOTerminatedNotification, try EarPodsDeviceMatch.dictionary(),
                earPodsRegistryChanged, context, &removed
            )
            guard result == KERN_SUCCESS else {
                throw AppFailure("Не удалось подписаться на отключение EarPods (IOKit \(result)).")
            }
            // Initial enumeration also arms both notifications. Notify once,
            // after both subscriptions exist, even when no device is present.
            drain(arrived)
            drain(removed)
            changed()
        } catch {
            stop()
            throw error
        }
    }

    public func stop() {
        onChange = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes) }
        source = nil
        if arrived != IO_OBJECT_NULL { IOObjectRelease(arrived); arrived = IO_OBJECT_NULL }
        if removed != IO_OBJECT_NULL { IOObjectRelease(removed); removed = IO_OBJECT_NULL }
        if let port { IONotificationPortDestroy(port) }
        port = nil
    }

    fileprivate func changed() { onChange?() }

    private func drain(_ iterator: io_iterator_t) {
        while true {
            let service = IOIteratorNext(iterator)
            guard service != IO_OBJECT_NULL else { return }
            IOObjectRelease(service)
        }
    }

    deinit {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes) }
        if arrived != IO_OBJECT_NULL { IOObjectRelease(arrived) }
        if removed != IO_OBJECT_NULL { IOObjectRelease(removed) }
        if let port { IONotificationPortDestroy(port) }
    }
}
