import CoreAudio
import Foundation

struct CoreAudioError: Error, CustomStringConvertible {
    let status: OSStatus
    let operation: String

    var description: String { "\(operation) failed (\(fourCharCode(UInt32(bitPattern: status))), \(status))" }
}

func fourCharCode(_ value: UInt32) -> String {
    let bytes = [UInt8(value >> 24 & 0xff), UInt8(value >> 16 & 0xff), UInt8(value >> 8 & 0xff), UInt8(value & 0xff)]
    guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7f }), let text = String(bytes: bytes, encoding: .ascii) else {
        return String(value)
    }
    return "'\(text)'"
}

func checkStatus(_ status: OSStatus, _ operation: @autoclosure () -> String) throws {
    guard status == noErr else { throw CoreAudioError(status: status, operation: operation()) }
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)

    private func address(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope,
        _ element: AudioObjectPropertyElement
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    func hasProperty(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> Bool {
        var address = address(selector, scope, element)
        return AudioObjectHasProperty(self, &address)
    }

    func isSettable(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> Bool {
        var address = address(selector, scope, element)
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(self, &address, &settable) == noErr && settable.boolValue
    }

    func read<T>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        initial: T
    ) throws -> T {
        var address = address(selector, scope, element)
        var size = UInt32(MemoryLayout<T>.size)
        var value = initial
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, $0)
        }
        try checkStatus(status, "Get \(fourCharCode(selector))")
        return value
    }

    func readArray<T>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) throws -> [T] {
        var address = address(selector, scope, element)
        var size: UInt32 = 0
        try checkStatus(AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size), "Size of \(fourCharCode(selector))")
        let capacity = Int(size) / MemoryLayout<T>.stride
        guard capacity > 0 else { return [] }

        var status: OSStatus = noErr
        let values = [T](unsafeUninitializedCapacity: capacity) { buffer, initialized in
            status = AudioObjectGetPropertyData(self, &address, 0, nil, &size, buffer.baseAddress!)
            initialized = status == noErr ? Int(size) / MemoryLayout<T>.stride : 0
        }
        try checkStatus(status, "Get \(fourCharCode(selector))")
        return values
    }

    func readString(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) throws -> String {
        var address = address(selector, scope, element)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, $0)
        }
        try checkStatus(status, "Get \(fourCharCode(selector))")
        guard let string = value?.takeRetainedValue() else {
            throw CoreAudioError(status: kAudioHardwareUnspecifiedError, operation: "Get \(fourCharCode(selector))")
        }
        return string as String
    }

    func write<T>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        value: T
    ) throws {
        var address = address(selector, scope, element)
        var value = value
        let status = withUnsafePointer(to: &value) {
            AudioObjectSetPropertyData(self, &address, 0, nil, UInt32(MemoryLayout<T>.size), $0)
        }
        try checkStatus(status, "Set \(fourCharCode(selector))")
    }

    @discardableResult
    func addListener(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        queue: DispatchQueue = .main,
        _ block: @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus {
        var address = address(selector, scope, element)
        return AudioObjectAddPropertyListenerBlock(self, &address, queue, block)
    }
}
