import Accelerate
import CoreAudio
import Foundation

/// Taps the output of one app (all of its processes), mutes the original, and replays it
/// through a private aggregate device on the chosen output at an adjustable gain.
final class AppAudioTap {
    let processObjectIDs: Set<AudioObjectID>

    private var tapID = AudioObjectID.unknown
    private var aggregateID = AudioObjectID.unknown
    private var ioProcID: AudioDeviceIOProcID?
    private let gainPointer: UnsafeMutablePointer<Float>

    var gain: Float {
        get { gainPointer.pointee }
        set { gainPointer.pointee = newValue }
    }

    init(processObjectIDs: [AudioObjectID], outputDeviceUID: String, gain: Float) throws {
        self.processObjectIDs = Set(processObjectIDs)
        gainPointer = .allocate(capacity: 1)
        gainPointer.initialize(to: gain)
        do {
            try setUp(processObjectIDs: processObjectIDs, outputDeviceUID: outputDeviceUID)
        } catch {
            tearDown()
            throw error
        }
    }

    deinit {
        tearDown()
        gainPointer.deallocate()
    }

    private func setUp(processObjectIDs: [AudioObjectID], outputDeviceUID: String) throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        description.uuid = UUID()
        description.name = "MenuBoard"
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior.mutedWhenTapped
        try checkStatus(AudioHardwareCreateProcessTap(description, &tapID), "Create process tap")

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MenuBoard Mixer",
            kAudioAggregateDeviceUIDKey: "com.daniellazar.menuboard.aggregate.\(description.uuid.uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputDeviceUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        try checkStatus(AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID), "Create aggregate device")

        let gainPointer = self.gainPointer
        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { _, input, _, output, _ in
            AppAudioTap.render(input: input, output: output, gain: gainPointer.pointee)
        }
        try checkStatus(status, "Create IO proc")
        try checkStatus(AudioDeviceStart(aggregateID, ioProcID), "Start aggregate device")
    }

    func tearDown() {
        if let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateID != .unknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = .unknown
        }
        if tapID != .unknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = .unknown
        }
    }

    // Runs on the realtime audio thread: no allocation, no locks, no ObjC.
    private static func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>, gain: Float) {
        let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputBuffers = UnsafeMutableAudioBufferListPointer(output)

        var inputChannelCount = 0
        for buffer in inputBuffers { inputChannelCount += Int(buffer.mNumberChannels) }

        var outputChannelIndex = 0
        for outBuffer in outputBuffers {
            let outStride = max(Int(outBuffer.mNumberChannels), 1)
            defer { outputChannelIndex += outStride }
            guard let outData = outBuffer.mData else { continue }
            let frames = Int(outBuffer.mDataByteSize) / (MemoryLayout<Float>.size * outStride)
            let outBase = outData.assumingMemoryBound(to: Float.self)

            guard inputChannelCount > 0 else {
                memset(outData, 0, Int(outBuffer.mDataByteSize))
                continue
            }

            for channel in 0..<outStride {
                let target = (outputChannelIndex + channel) % inputChannelCount
                var remaining = target
                var source: UnsafeMutablePointer<Float>?
                var inStride = 1
                var inOffset = 0
                var inFrames = 0
                for inBuffer in inputBuffers {
                    let channels = max(Int(inBuffer.mNumberChannels), 1)
                    if remaining < channels {
                        source = inBuffer.mData?.assumingMemoryBound(to: Float.self)
                        inStride = channels
                        inOffset = remaining
                        inFrames = Int(inBuffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
                        break
                    }
                    remaining -= channels
                }

                let count = min(frames, inFrames)
                if let source, count > 0 {
                    var scale = gain
                    vDSP_vsmul(source + inOffset, inStride, &scale, outBase + channel, outStride, vDSP_Length(count))
                }
                if count < frames {
                    var zero: Float = 0
                    vDSP_vfill(&zero, outBase + channel + count * outStride, outStride, vDSP_Length(frames - count))
                }
            }
        }
    }
}
