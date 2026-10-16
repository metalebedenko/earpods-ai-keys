import Foundation
import CoreFoundation

public struct MappingPair: Codable, Equatable, Hashable {
    public let source: UInt64
    public let destination: UInt64
    public init(source: UInt64, destination: UInt64) { self.source=source; self.destination=destination }
}

public enum MappingSnapshot: Equatable {
    case absent, empty, mapped([MappingPair])
    public var isPresent: Bool { self != .absent }
}

public enum MappingParser {
    public static func canonical(_ pairs: [MappingPair]) -> [MappingPair] { pairs.sorted { $0.source < $1.source } }
    public static func parse(_ text: String) throws -> MappingSnapshot {
        let compact = text.filter { !$0.isWhitespace }
        if compact.isEmpty || compact == "RegistryIDKeyValue" { return .absent }
        let lines = text.components(separatedBy: .newlines)
        let rows = lines.enumerated().filter { $0.element.split(whereSeparator: { $0.isWhitespace }).dropFirst().first == "UserKeyMapping" }
        guard rows.count == 1, let row = rows.first else { throw AppFailure("Не удалось однозначно прочитать EarPods: неизвестный ответ или несколько устройств.") }
        guard let range = row.element.range(of: "UserKeyMapping") else { throw AppFailure("Не удалось прочитать правило EarPods.") }
        let tail = row.element[range.upperBound...]
        let payload = (String(tail) + "\n" + lines.dropFirst(row.offset + 1).joined(separator: "\n")).trimmingCharacters(in: .whitespacesAndNewlines)
        if ["(null)","()","[]"].contains(payload.filter { !$0.isWhitespace }) { return .empty }
        let object: Any
        do { object = try PropertyListSerialization.propertyList(from: Data(payload.utf8), options: [], format: nil) }
        catch { throw AppFailure("Ответ о переназначении не распознан. Ничего не изменено.") }
        guard let array = object as? [[String: Any]] else { throw AppFailure("Неизвестное правило EarPods сохранено.") }
        if array.isEmpty { return .empty }
        var pairs: [MappingPair] = []
        for entry in array {
            guard Set(entry.keys) == ["HIDKeyboardModifierMappingSrc","HIDKeyboardModifierMappingDst"],
                  let src = unsigned(entry["HIDKeyboardModifierMappingSrc"]),
                  let dst = unsigned(entry["HIDKeyboardModifierMappingDst"]) else { throw AppFailure("Неизвестное правило EarPods сохранено.") }
            pairs.append(MappingPair(source: src, destination: dst))
        }
        guard Set(pairs.map(\.source)).count == pairs.count else { throw AppFailure("Неоднозначные назначения EarPods сохранены.") }
        return .mapped(canonical(pairs))
    }
    private static func unsigned(_ value: Any?) -> UInt64? {
        if let string = value as? String { return UInt64(string) }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return UInt64(number.stringValue) }
        return nil
    }
    public static func json(_ pairs: [MappingPair]) throws -> String {
        let object = ["UserKeyMapping": pairs.map { ["HIDKeyboardModifierMappingSrc": $0.source, "HIDKeyboardModifierMappingDst": $0.destination] }]
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }
}

public struct OwnershipReceipt: Codable, Equatable {
    public var verified: [MappingPair]?
    public var pending: [MappingPair]?
    public init(verified: [MappingPair]? = nil, pending: [MappingPair]? = nil) { self.verified=verified; self.pending=pending }
    public func owns(_ pairs: [MappingPair]) -> Bool {
        let canonical = MappingParser.canonical(pairs)
        return [verified, pending].compactMap { $0 }.contains { MappingParser.canonical($0) == canonical }
    }
    public func validate() throws {
        for pairs in [verified,pending].compactMap({ $0 }) {
            guard pairs.count == 3, Set(pairs.map(\.source)) == Set(RemoteButton.allCases.map(\.source)),
                  pairs.allSatisfy({ pair in pair.destination == 0xC000000CF || pair.destination == 0x700000000 || KeyCatalog.all.contains(where: { (0x700000000 | UInt64($0.usage)) == pair.destination }) }) else {
                throw AppFailure("Файл владения назначениями повреждён. Автоматические изменения остановлены.")
            }
        }
    }
}
