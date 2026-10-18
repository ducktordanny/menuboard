import Darwin
import Foundation
import IOKit
import IOKit.ps

struct CPUSample {
    var total: Double = 0
    var perCore: [Double] = []
}

enum MemoryPressure: Int32 {
    case normal = 1, warning = 2, critical = 4

    var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }
}

struct MemorySample {
    var total: UInt64
    var app: UInt64
    var wired: UInt64
    var compressed: UInt64
    var cached: UInt64
    var swapUsed: UInt64
    var swapTotal: UInt64
    var pressure: MemoryPressure

    var used: UInt64 { app + wired + compressed }
}

struct DiskSample {
    var total: Int64
    var free: Int64
    var used: Int64 { total - free }
}

struct BatterySample {
    var percent: Int
    var isCharging: Bool
    var onAC: Bool
    var minutesRemaining: Int?
    var cycleCount: Int?
}

final class SystemStats: ObservableObject {
    @Published private(set) var cpu = CPUSample()
    @Published private(set) var memory: MemorySample?
    @Published private(set) var disk: DiskSample?
    @Published private(set) var battery: BatterySample?
    @Published private(set) var uptime: TimeInterval = 0
    @Published private(set) var loadAverage: [Double] = [0, 0, 0]
    @Published private(set) var thermalState: ProcessInfo.ThermalState = .nominal

    let modelName = Sysctl.string("hw.model")
    let chipName = Sysctl.string("machdep.cpu.brand_string")
    let coreCount = ProcessInfo.processInfo.activeProcessorCount
    let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
    let hostName = Host.current().localizedName ?? ""

    private var timer: Timer?
    private var previousTicks: [[UInt32]] = []

    func start() {
        guard timer == nil else { return }
        previousTicks = Self.cpuTicks()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        cpu = sampleCPU()
        memory = Self.sampleMemory()
        disk = Self.sampleDisk()
        battery = Self.sampleBattery()
        uptime = ProcessInfo.processInfo.systemUptime
        thermalState = ProcessInfo.processInfo.thermalState

        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) == 3 { loadAverage = loads }
    }

    // MARK: CPU

    private func sampleCPU() -> CPUSample {
        let ticks = Self.cpuTicks()
        defer { previousTicks = ticks }
        guard ticks.count == previousTicks.count, !ticks.isEmpty else {
            return CPUSample(total: 0, perCore: Array(repeating: 0, count: ticks.count))
        }

        var perCore: [Double] = []
        var busySum = 0.0
        var totalSum = 0.0
        for (index, current) in ticks.enumerated() {
            let previous = previousTicks[index]
            let user = Double(current[Int(CPU_STATE_USER)] &- previous[Int(CPU_STATE_USER)])
            let system = Double(current[Int(CPU_STATE_SYSTEM)] &- previous[Int(CPU_STATE_SYSTEM)])
            let nice = Double(current[Int(CPU_STATE_NICE)] &- previous[Int(CPU_STATE_NICE)])
            let idle = Double(current[Int(CPU_STATE_IDLE)] &- previous[Int(CPU_STATE_IDLE)])
            let busy = user + system + nice
            let total = busy + idle
            perCore.append(total > 0 ? busy / total : 0)
            busySum += busy
            totalSum += total
        }
        return CPUSample(total: totalSum > 0 ? busySum / totalSum : 0, perCore: perCore)
    }

    private static func cpuTicks() -> [[UInt32]] {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &infoArray, &infoCount)
        guard result == KERN_SUCCESS, let info = infoArray else { return [] }
        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        let stateCount = Int(CPU_STATE_MAX)
        return (0..<Int(cpuCount)).map { core in
            (0..<stateCount).map { UInt32(bitPattern: info[core * stateCount + $0]) }
        }
    }

    // MARK: Memory

    private static func sampleMemory() -> MemorySample? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = UInt64(pageSize)

        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = (internalPages > purgeable ? internalPages - purgeable : 0) * page

        let swap = Sysctl.value("vm.swapusage", default: xsw_usage())
        let pressure = MemoryPressure(rawValue: Sysctl.value("kern.memorystatus_vm_pressure_level", default: Int32(1))) ?? .normal

        return MemorySample(
            total: ProcessInfo.processInfo.physicalMemory,
            app: app,
            wired: UInt64(stats.wire_count) * page,
            compressed: UInt64(stats.compressor_page_count) * page,
            cached: (UInt64(stats.external_page_count) + purgeable) * page,
            swapUsed: swap.xsu_used,
            swapTotal: swap.xsu_total,
            pressure: pressure
        )
    }

    // MARK: Disk

    private static func sampleDisk() -> DiskSample? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskSample(total: Int64(total), free: free)
    }

    // MARK: Battery

    private static func sampleBattery() -> BatterySample? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let timeKey = isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let minutes = (description[timeKey] as? Int).flatMap { $0 > 0 ? $0 : nil }

            return BatterySample(
                percent: description[kIOPSCurrentCapacityKey] as? Int ?? 0,
                isCharging: isCharging,
                onAC: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                minutesRemaining: minutes,
                cycleCount: batteryCycleCount()
            )
        }
        return nil
    }

    private static func batteryCycleCount() -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "CycleCount" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int
    }
}
