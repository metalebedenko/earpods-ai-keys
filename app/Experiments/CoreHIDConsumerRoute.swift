// Original compile-only API probe. No main, no device is created by loading it.
// Calling makeAndSendVoiceCommand would mutate the HID registry and emit input;
// it requires a separately authorized hardware experiment and entitlement.
import Foundation
import CoreHID

@available(macOS 15.0, *)
private enum VirtualRouteError: Error {
    case creationDenied
}

@available(macOS 15.0, *)
private final class ConsumerReportDelegate: HIDVirtualDeviceDelegate {
    func hidVirtualDevice(_ device: HIDVirtualDevice,
                          receivedSetReportRequestOfType type: HIDReportType,
                          id: HIDReportID?, data: Data) async throws {
        // This descriptor has no output reports.
    }

    func hidVirtualDevice(_ device: HIDVirtualDevice,
                          receivedGetReportRequestOfType type: HIDReportType,
                          id: HIDReportID?, maxSize: Int) async throws -> Data {
        Data([0, 0].prefix(max(0, maxSize)))
    }
}

@available(macOS 15.0, *)
func makeAndSendVoiceCommand() async throws {
    // Consumer Control collection: one 16-bit array usage, no report ID.
    // Constructed here from HID descriptor fields, not copied from sample code.
    let descriptor = Data([
        0x05, 0x0C,       // Usage Page: Consumer
        0x09, 0x01,       // Usage: Consumer Control
        0xA1, 0x01,       // Application collection
        0x15, 0x00,       // Logical minimum: 0
        0x26, 0xFF, 0xFF, // Logical maximum: 65535
        0x19, 0x00,       // Usage minimum: 0
        0x2A, 0xFF, 0xFF, // Usage maximum: 65535
        0x75, 0x10,       // Report size: 16 bits
        0x95, 0x01,       // Report count: 1
        0x81, 0x00,       // Input: data, array, absolute
        0xC0              // End collection
    ])
    let properties = HIDVirtualDevice.Properties(
        descriptor: descriptor,
        vendorID: 0xFFFF, // Probe identity; deliberately differs from EarPods.
        productID: 1,
        transport: .virtual,
        product: "EarPods AI Keys compile-only consumer probe",
        uniqueID: "earpods-ai-keys-consumer-probe"
    )
    guard let device = HIDVirtualDevice(properties: properties) else {
        throw VirtualRouteError.creationDenied
    }
    let delegate = ConsumerReportDelegate()
    await device.activate(delegate: delegate)
    // Candidate VoiceCommand press/release through an actual HID report.
    // Compilation does not establish creation permission or Dictation behavior.
    try await device.dispatchInputReport(data: Data([0xCF, 0x00]), timestamp: .now)
    try await device.dispatchInputReport(data: Data([0x00, 0x00]), timestamp: .now)
}
