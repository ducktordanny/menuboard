import AppKit
import Foundation

/// There is no public API to request the "System Audio Recording" permission ahead of time,
/// so this uses the TCC SPI when available and otherwise lets the first tap trigger the prompt.
enum AudioCapturePermission {
    private typealias RequestFunction = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void

    static func request(_ completion: @escaping (Bool) -> Void) {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_NOW),
              let symbol = dlsym(handle, "TCCAccessRequest") else {
            completion(true)
            return
        }
        let request = unsafeBitCast(symbol, to: RequestFunction.self)
        request("kTCCServiceAudioCapture" as CFString, nil) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!
        NSWorkspace.shared.open(url)
    }
}
