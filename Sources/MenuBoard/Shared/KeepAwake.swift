import Combine
import Foundation
import IOKit.pwr_mgt

/// Prevents display (and therefore idle system) sleep via a power assertion, optionally for a fixed duration.
final class KeepAwake: ObservableObject {
    static let durations: [(title: String, seconds: TimeInterval?)] = [
        ("15 minutes", 15 * 60),
        ("30 minutes", 30 * 60),
        ("1 hour", 3600),
        ("2 hours", 2 * 3600),
        ("Indefinitely", nil),
    ]

    @Published private(set) var isActive = false
    @Published private(set) var until: Date?

    private var assertionID: IOPMAssertionID = 0
    private var timer: Timer?

    var remainingText: String? {
        guard isActive else { return nil }
        guard let until else { return "Awake" }
        let minutes = max(Int(until.timeIntervalSinceNow / 60), 0)
        return "Awake · \(Format.minutes(minutes)) left"
    }

    func toggle() {
        isActive ? deactivate() : activate(for: nil)
    }

    func activate(for duration: TimeInterval?) {
        deactivate()
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "MenuBoard keep awake" as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { return }
        assertionID = id
        isActive = true
        until = duration.map { Date().addingTimeInterval($0) }
        if let duration {
            timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in self?.deactivate() }
        }
    }

    func deactivate() {
        timer?.invalidate()
        timer = nil
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
        isActive = false
        until = nil
    }

    deinit {
        deactivate()
    }
}
