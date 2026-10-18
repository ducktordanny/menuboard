import Combine
import Foundation

struct KeyDefinition: Identifiable, Hashable {
    let usage: UInt64
    let name: String
    var id: UInt64 { usage }
}

/// HID usages (keyboard page 0x07 unless noted) for the keys worth remapping without a full Karabiner.
enum KeyCatalog {
    private static let page: UInt64 = 0x7_0000_0000

    static let all: [KeyDefinition] = [
        .init(usage: page | 0x39, name: "Caps Lock"),
        .init(usage: page | 0xE0, name: "Left Control"),
        .init(usage: page | 0xE1, name: "Left Shift"),
        .init(usage: page | 0xE2, name: "Left Option"),
        .init(usage: page | 0xE3, name: "Left Command"),
        .init(usage: page | 0xE4, name: "Right Control"),
        .init(usage: page | 0xE5, name: "Right Shift"),
        .init(usage: page | 0xE6, name: "Right Option"),
        .init(usage: page | 0xE7, name: "Right Command"),
        .init(usage: 0xFF_0000_0003, name: "Fn / Globe"),
        .init(usage: page | 0x29, name: "Escape"),
        .init(usage: page | 0x2B, name: "Tab"),
        .init(usage: page | 0x28, name: "Return"),
        .init(usage: page | 0x2A, name: "Delete"),
        .init(usage: page | 0x4C, name: "Forward Delete"),
        .init(usage: page | 0x2C, name: "Space"),
        .init(usage: page | 0x35, name: "` (Grave)"),
        .init(usage: page | 0x64, name: "§ (ISO key)"),
        .init(usage: page | 0x50, name: "Left Arrow"),
        .init(usage: page | 0x4F, name: "Right Arrow"),
        .init(usage: page | 0x52, name: "Up Arrow"),
        .init(usage: page | 0x51, name: "Down Arrow"),
        .init(usage: page | 0x4A, name: "Home"),
        .init(usage: page | 0x4D, name: "End"),
        .init(usage: page | 0x4B, name: "Page Up"),
        .init(usage: page | 0x4E, name: "Page Down"),
    ] + (0..<12).map { .init(usage: page | (0x3A + UInt64($0)), name: "F\($0 + 1)") }

    static func name(for usage: UInt64) -> String {
        all.first { $0.usage == usage }?.name ?? String(format: "0x%llX", usage)
    }
}

struct KeyRemap: Codable, Hashable, Identifiable {
    var id = UUID()
    var from: UInt64
    var to: UInt64
}

/// Applies simple key-to-key remaps system-wide through `hidutil`, the same mechanism Karabiner's
/// "simple modifications" use. Mappings live in the HID system until logout, so they are re-applied at launch.
final class KeyRemapper: ObservableObject {
    private static let rulesKey = "keys.rules"
    private static let enabledKey = "keys.enabled"

    @Published private(set) var rules: [KeyRemap] = []
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            apply()
        }
    }
    @Published private(set) var lastError: String?
    @Published private(set) var isApplied = false

    private let queue = DispatchQueue(label: "menuboard.hidutil")

    init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        if let data = UserDefaults.standard.data(forKey: Self.rulesKey),
           let saved = try? JSONDecoder().decode([KeyRemap].self, from: data) {
            rules = saved
        }
        if isEnabled, !rules.isEmpty { apply() }
    }

    func add(from: UInt64, to: UInt64) {
        guard from != to else { return }
        rules.removeAll { $0.from == from }
        rules.append(KeyRemap(from: from, to: to))
        save()
        apply()
    }

    func addSwap(_ first: UInt64, _ second: UInt64) {
        rules.removeAll { $0.from == first || $0.from == second }
        rules.append(KeyRemap(from: first, to: second))
        rules.append(KeyRemap(from: second, to: first))
        save()
        apply()
    }

    func remove(_ rule: KeyRemap) {
        rules.removeAll { $0.id == rule.id }
        save()
        apply()
    }

    func removeAll() {
        rules.removeAll()
        save()
        apply()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: Self.rulesKey)
    }

    func apply() {
        let mapping: [[String: UInt64]] = isEnabled
            ? rules.map { ["HIDKeyboardModifierMappingSrc": $0.from, "HIDKeyboardModifierMappingDst": $0.to] }
            : []
        guard let data = try? JSONSerialization.data(withJSONObject: ["UserKeyMapping": mapping]),
              let json = String(data: data, encoding: .utf8) else { return }

        queue.async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
            process.arguments = ["property", "--set", json]
            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = Pipe()

            var failure: String?
            do {
                try process.run()
                process.waitUntilExit()
                let errorText = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if process.terminationStatus != 0 {
                    failure = errorText.isEmpty ? "hidutil exited with status \(process.terminationStatus)" : errorText
                }
            } catch {
                failure = error.localizedDescription
            }

            DispatchQueue.main.async {
                self?.lastError = failure
                self?.isApplied = failure == nil && !mapping.isEmpty
            }
        }
    }
}
