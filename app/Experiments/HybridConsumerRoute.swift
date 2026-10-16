// Original compile-only API probe. No main and no top-level HID operations.
// Functions below must NOT be invoked until a hardware experiment is approved.
import Foundation
import IOKit.hid
import CoreGraphics

enum HybridRouteError: Error {
    case deviceOpenFailed(IOReturn)
    case postPermissionMissing
    case eventCreationFailed
}

// A proposed UserKeyMapping plan, not an applied mapping. Destination usage 0
// is only a suppression candidate: real media suppression must be measured.
let hybridSuppressionCandidate: [[String: UInt64]] = [
    ["HIDKeyboardModifierMappingSrc": 0xC000000CD,
     "HIDKeyboardModifierMappingDst": 0xC000000CF],
    ["HIDKeyboardModifierMappingSrc": 0xC000000EA,
     "HIDKeyboardModifierMappingDst": 0x700000000],
    ["HIDKeyboardModifierMappingSrc": 0xC000000E9,
     "HIDKeyboardModifierMappingDst": 0x700000000]
]

func receivePhysicalConsumerValue(_ context: UnsafeMutableRawPointer?,
                                  _ result: IOReturn,
                                  _ sender: UnsafeMutableRawPointer?,
                                  _ value: IOHIDValue) {
    guard result == kIOReturnSuccess else { return }
    let element = IOHIDValueGetElement(value)
    guard IOHIDElementGetUsagePage(element) == 0x0C else { return }
    let usage = IOHIDElementGetUsage(element)
    let integer = IOHIDValueGetIntegerValue(value)
    // This only demonstrates the typed value API. No logging or posting.
    // A hardware test must establish whether these remain original EA/E9
    // values when the event-service UserKeyMapping suppresses their output.
    _ = (usage, integer)
}

func beginNonexclusiveConsumerObservation(_ device: IOHIDDevice) throws {
    // Caller would first match VID 0x5AC, PID 0x110B, ConsumerControl 0x0C/1.
    // No seize: the hardware center can still take its native CF mapping path.
    let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard result == kIOReturnSuccess else {
        throw HybridRouteError.deviceOpenFailed(result)
    }
    IOHIDDeviceRegisterInputValueCallback(device, receivePhysicalConsumerValue, nil)
    IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
}

func endNonexclusiveConsumerObservation(_ device: IOHIDDevice) {
    IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
    IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
}

func postSingleChord(_ key: CGKeyCode, flags: CGEventFlags) throws {
    // User approval is a runtime gate, not something this probe can grant.
    guard CGPreflightPostEventAccess() else { throw HybridRouteError.postPermissionMissing }
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false) else {
        throw HybridRouteError.eventCreationFailed
    }
    down.flags = flags
    up.flags = flags
    down.post(tap: .cgSessionEventTap)
    up.post(tap: .cgSessionEventTap)
}
