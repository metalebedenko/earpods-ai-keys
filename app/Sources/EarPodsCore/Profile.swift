import Foundation

public enum RemoteButton: String, Codable, CaseIterable, Hashable {
    case center, minus, plus
    public var title: String { switch self { case .center: return "Центр"; case .minus: return "−"; case .plus: return "+" } }
    public var source: UInt64 { switch self { case .center: return 0xC000000CD; case .minus: return 0xC000000EA; case .plus: return 0xC000000E9 } }
    public static func from(usagePage: UInt32, usage: UInt32) -> RemoteButton? {
        guard usagePage == 12 else { return nil }
        return allCases.first { UInt32($0.source & 0xFFFFFFFF) == usage }
    }
}

public struct KeyModifiers: OptionSet, Codable, Equatable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let command = KeyModifiers(rawValue: 1)
    public static let control = KeyModifiers(rawValue: 2)
    public static let option = KeyModifiers(rawValue: 4)
    public static let shift = KeyModifiers(rawValue: 8)
    public var symbols: String {
        (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "") +
        (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
    }
}

public struct KeyDefinition: Equatable {
    public let virtualKey: UInt16
    public let usage: UInt16
    public let title: String
}

public enum KeyCatalog {
    // Physical key codes are macOS virtual key codes; destinations are USB HID usages.
    private static let data: [(UInt16, UInt16, String)] = [
        (0,4,"A"),(1,22,"S"),(2,7,"D"),(3,9,"F"),(4,11,"H"),(5,10,"G"),
        (6,29,"Z"),(7,27,"X"),(8,6,"C"),(9,25,"V"),(11,5,"B"),
        (12,20,"Q"),(13,26,"W"),(14,8,"E"),(15,21,"R"),(16,28,"Y"),(17,23,"T"),
        (18,30,"1"),(19,31,"2"),(20,32,"3"),(21,33,"4"),(22,35,"6"),(23,34,"5"),
        (24,46,"="),(25,38,"9"),(26,36,"7"),(27,45,"−"),(28,37,"8"),(29,39,"0"),
        (30,48,"]"),(31,18,"O"),(32,24,"U"),(33,47,"["),(34,12,"I"),(35,19,"P"),
        (36,40,"Enter"),(37,15,"L"),(38,13,"J"),(39,52,"'"),(40,14,"K"),
        (41,51,";"),(42,49,"\\"),(43,54,","),(44,56,"/"),(45,17,"N"),(46,16,"M"),
        (47,55,"."),(48,43,"Tab"),(49,44,"Пробел"),(50,53,"`"),(51,42,"Backspace"),
        (53,41,"Escape"),(10,100,"§"),
        (122,58,"F1"),(120,59,"F2"),(99,60,"F3"),(118,61,"F4"),(96,62,"F5"),
        (97,63,"F6"),(98,64,"F7"),(100,65,"F8"),(101,66,"F9"),(109,67,"F10"),
        (103,68,"F11"),(111,69,"F12"),(105,104,"F13"),(107,105,"F14"),
        (113,106,"F15"),(106,107,"F16"),(64,108,"F17"),(79,109,"F18"),
        (80,110,"F19"),(90,111,"F20"),
        (115,74,"Home"),(119,77,"End"),(116,75,"Page Up"),(121,78,"Page Down"),
        (117,76,"Delete"),(123,80,"←"),(124,79,"→"),(125,81,"↓"),(126,82,"↑"),
        (65,99,"Num ."),(67,85,"Num ×"),(69,87,"Num +"),(75,84,"Num /"),
        (76,88,"Num Enter"),(78,86,"Num −"),(81,103,"Num ="),(82,98,"Num 0"),
        (83,89,"Num 1"),(84,90,"Num 2"),(85,91,"Num 3"),(86,92,"Num 4"),
        (87,93,"Num 5"),(88,94,"Num 6"),(89,95,"Num 7"),(91,96,"Num 8"),(92,97,"Num 9")
    ]
    public static let all: [KeyDefinition] = data.map { KeyDefinition(virtualKey: $0.0, usage: $0.1, title: $0.2) }
    public static func key(_ virtualKey: UInt16) -> KeyDefinition? { all.first { $0.virtualKey == virtualKey } }
}

public struct KeyBinding: Codable, Equatable {
    public let virtualKey: UInt16
    public let modifiers: KeyModifiers
    public init(virtualKey: UInt16, modifiers: KeyModifiers = []) {
        self.virtualKey = virtualKey; self.modifiers = modifiers
    }
    public var title: String { modifiers.symbols + (KeyCatalog.key(virtualKey)?.title ?? "Неизвестная клавиша") }
    public var usage: UInt64? { KeyCatalog.key(virtualKey).map { 0x700000000 | UInt64($0.usage) } }
    public func validate() throws {
        guard KeyCatalog.key(virtualKey) != nil, modifiers.rawValue & ~UInt8(15) == 0 else {
            throw AppFailure("Это назначение не поддерживается. Выберите клавишу или сочетание с ⌘, ⌃, ⌥, ⇧.")
        }
    }
}

public enum ButtonAction: Codable, Equatable {
    case dictation
    case key(KeyBinding)
    public var title: String { switch self { case .dictation: return "Диктовка macOS"; case .key(let binding): return binding.title } }
    public var isChord: Bool { if case .key(let binding) = self { return !binding.modifiers.isEmpty }; return false }
    public var destination: UInt64 {
        switch self { case .dictation: return 0xC000000CF
        case .key(let binding): return isChord ? 0x700000000 : (binding.usage ?? 0) }
    }
    public func validate() throws { if case .key(let binding) = self { try binding.validate() } }
}

public struct Profile: Codable, Equatable {
    public var center: ButtonAction
    public var minus: ButtonAction
    public var plus: ButtonAction
    public init(center: ButtonAction, minus: ButtonAction, plus: ButtonAction) { self.center=center; self.minus=minus; self.plus=plus }
    public static let standard = Profile(center: .dictation, minus: .key(KeyBinding(virtualKey: 51)), plus: .key(KeyBinding(virtualKey: 36)))
    public subscript(_ button: RemoteButton) -> ButtonAction {
        get { switch button { case .center: return center; case .minus: return minus; case .plus: return plus } }
        set { switch button { case .center: center=newValue; case .minus: minus=newValue; case .plus: plus=newValue } }
    }
    public var needsChordInput: Bool { RemoteButton.allCases.contains { self[$0].isChord } }
    public var mapping: [MappingPair] { RemoteButton.allCases.map { MappingPair(source: $0.source, destination: self[$0].destination) } }
    public func validate() throws { for button in RemoteButton.allCases { try self[button].validate() } }
}

public struct AppFailure: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
