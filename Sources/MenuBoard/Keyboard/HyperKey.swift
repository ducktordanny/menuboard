import AppKit
import Combine
import CoreGraphics
import Foundation

struct HyperSourceKey: Identifiable, Hashable {
    let keyCode: Int64
    /// Device-specific modifier bit in CGEventFlags, which distinguishes left from right keys.
    let deviceFlag: UInt64
    let name: String
    var id: Int64 { keyCode }

    static let all: [HyperSourceKey] = [
        .init(keyCode: 59, deviceFlag: 0x0001, name: "Left Control"),
        .init(keyCode: 62, deviceFlag: 0x2000, name: "Right Control"),
        .init(keyCode: 58, deviceFlag: 0x0020, name: "Left Option"),
        .init(keyCode: 61, deviceFlag: 0x0040, name: "Right Option"),
        .init(keyCode: 55, deviceFlag: 0x0008, name: "Left Command"),
        .init(keyCode: 54, deviceFlag: 0x0010, name: "Right Command"),
    ]
}

/// Turns one modifier into a hyper key (Control+Option+Shift+Command) using a session event tap.
/// The real modifier event is swallowed; key events while it is held get all four flags.
final class HyperKey: ObservableObject {
    enum Status: Equatable {
        case off, active, needsPermission, failed(String)
    }

    private static let enabledKey = "keys.hyper.enabled"
    private static let sourceKey = "keys.hyper.source"
    private static let escapeKey = "keys.hyper.escape"
    private static let hyperFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            isEnabled ? start(prompt: true) : stop()
        }
    }
    @Published var sourceKeyCode: Int64 {
        didSet { UserDefaults.standard.set(sourceKeyCode, forKey: Self.sourceKey) }
    }
    @Published var tapSendsEscape: Bool {
        didSet { UserDefaults.standard.set(tapSendsEscape, forKey: Self.escapeKey) }
    }
    @Published private(set) var status = Status.off

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?
    private var isHeld = false
    private var usedAsModifier = false

    private var source: HyperSourceKey {
        HyperSourceKey.all.first { $0.keyCode == sourceKeyCode } ?? HyperSourceKey.all[0]
    }

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        sourceKeyCode = UserDefaults.standard.object(forKey: Self.sourceKey) as? Int64 ?? 59
        tapSendsEscape = UserDefaults.standard.bool(forKey: Self.escapeKey)
        if isEnabled { start(prompt: false) }
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: Lifecycle

    private func start(prompt: Bool) {
        guard tap == nil else { return }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([promptKey: prompt] as CFDictionary)
        guard trusted, createTap() else {
            status = trusted ? .failed("Could not create event tap") : .needsPermission
            scheduleRetry()
            return
        }
        retryTimer?.invalidate()
        retryTimer = nil
        status = .active
    }

    private func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        tap = nil
        isHeld = false
        status = .off
    }

    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, self.isEnabled else { return }
            self.start(prompt: false)
        }
    }

    private func createTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            return Unmanaged<HyperKey>.fromOpaque(refcon).takeUnretainedValue().handle(proxy: proxy, type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = runLoopSource
        return true
    }

    // MARK: Event handling

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let source = self.source

        if type == .flagsChanged, keyCode == source.keyCode {
            let pressed = event.flags.rawValue & source.deviceFlag != 0
            if pressed {
                isHeld = true
                usedAsModifier = false
            } else {
                let tappedAlone = isHeld && !usedAsModifier
                isHeld = false
                if tappedAlone, tapSendsEscape { postEscape(proxy: proxy) }
            }
            return nil
        }

        guard isHeld else { return Unmanaged.passUnretained(event) }

        switch type {
        case .keyDown, .keyUp:
            usedAsModifier = true
            event.flags = event.flags.union(Self.hyperFlags)
        case .flagsChanged:
            usedAsModifier = true
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private func postEscape(proxy: CGEventTapProxy) {
        for down in [true, false] {
            guard let escape = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down) else { continue }
            escape.flags = []
            escape.tapPostEvent(proxy)
        }
    }
}
