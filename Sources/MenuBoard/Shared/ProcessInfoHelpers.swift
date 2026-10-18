import Darwin
import Foundation

/// Maps helper processes (WebContent, GPU, Chrome Helper…) to the app responsible for them,
/// the same way Activity Monitor groups them. Uses a private libsystem symbol; falls back to the pid itself.
enum ResponsiblePID {
    private typealias Function = @convention(c) (pid_t) -> pid_t

    private static let function: Function? = {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(rtldDefault, "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: Function.self)
    }()

    static func of(_ pid: pid_t) -> pid_t {
        guard let function else { return pid }
        let owner = function(pid)
        return owner > 0 ? owner : pid
    }
}

enum ProcessNames {
    static func name(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}

enum Sysctl {
    static func string(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }

    static func value<T>(_ name: String, default defaultValue: T) -> T {
        var value = defaultValue
        var size = MemoryLayout<T>.size
        let result = withUnsafeMutableBytes(of: &value) { sysctlbyname(name, $0.baseAddress, &size, nil, 0) }
        return result == 0 ? value : defaultValue
    }
}
