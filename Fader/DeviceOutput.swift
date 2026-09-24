#if os(macOS)
import AudioToolbox
import CoreAudio
import Foundation
import os

struct StreamControls: Sendable {
    var volume: Float
    var muted: Bool
}

final class AppStream: @unchecked Sendable {
    let key: String
    let ring = StereoRing()
    let controls = OSAllocatedUnfairLock(initialState: StreamControls(volume: 1, muted: false))
    var smoothedGain: Float = 0
    var objectIDs: [AudioObjectID] = []
    var capture: ProcessCapture?

    init(key: String) {
        self.key = key
    }

    func targetGain(master: Float) -> Float {
        let state = controls.withLock { $0 }
        guard !state.muted else { return 0 }
        return min(1, max(0, state.volume)) * min(1, max(0, master))
    }
}

/// One hardware output. Every app pinned to this device is mixed here.
final class DeviceOutput: @unchecked Sendable {
    let uid: String
    let deviceID: AudioObjectID
    private var procID: AudioDeviceIOProcID?
    private(set) var isRunning = false
    private var format = AudioStreamBasicDescription()
    private var mix = [Float](repeating: 0, count: 8_192 * 2)
    private var snapshot = [AppStream?](repeating: nil, count: 128)
    private let graph: MixGraph
    private let master: OSAllocatedUnfairLock<Float>
    private let accepting = OSAllocatedUnfairLock(initialState: false)
    private let log = Logger(subsystem: "com.mohabbis.fader", category: "output")

    init(uid: String, deviceID: AudioObjectID, graph: MixGraph, master: OSAllocatedUnfairLock<Float>) {
        self.uid = uid
        self.deviceID = deviceID
        self.graph = graph
        self.master = master
    }

    func start() -> OSStatus {
        format = AudioHAL.streamFormat(
            objectID: deviceID,
            selector: kAudioDevicePropertyStreamFormat,
            scope: kAudioObjectPropertyScopeOutput
        ) ?? DeviceOutput.fallbackFormat

        let block: AudioDeviceIOBlock = { [weak self] _, _, _, outputData, _ in
            self?.render(outputData)
        }
        var proc: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&proc, deviceID, nil, block)
        guard procStatus == noErr, let proc else { return procStatus }
        procID = proc
        accepting.withLock { $0 = true }
        let startStatus = AudioDeviceStart(deviceID, proc)
        if startStatus != noErr {
            log.error("Output start failed \(startStatus, privacy: .public)")
            stop()
            return startStatus
        }
        isRunning = true
        return noErr
    }

    func stop() {
        isRunning = false
        accepting.withLock { $0 = false }
        if let procID {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
        }
        procID = nil
    }

    private func render(_ outputData: UnsafeMutablePointer<AudioBufferList>) {
        guard accepting.withLock({ $0 }) else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(outputData)
        guard let first = buffers.first, first.mData != nil else { return }
        let nonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let bytesPerFrame = max(Int(format.mBytesPerFrame), 1)
        let frames: Int
        if nonInterleaved {
            let sampleBytes = max(Int(format.mBitsPerChannel) / 8, 1)
            frames = Int(first.mDataByteSize) / sampleBytes
        } else {
            frames = Int(first.mDataByteSize) / bytesPerFrame
        }
        guard frames > 0 else { return }

        let masterGain = master.withLock { $0 }
        let memberCount = graph.copyMembers(for: uid, into: &snapshot)
        var offset = 0
        while offset < frames {
            let chunk = min(8_192, frames - offset)
            for index in 0..<(chunk * 2) { mix[index] = 0 }
            for member in 0..<memberCount {
                guard let stream = snapshot[member] else { continue }
                let target = stream.targetGain(master: masterGain)
                let start = stream.smoothedGain
                let step: Float = 0.08
                let end = start + min(step, max(-step, target - start))
                stream.smoothedGain = end
                mix.withUnsafeMutableBufferPointer { pointer in
                    guard let base = pointer.baseAddress else { return }
                    stream.ring.mix(
                        into: base,
                        frames: chunk,
                        destinationRate: format.mSampleRate > 0 ? format.mSampleRate : 48_000,
                        gainStart: start,
                        gainEnd: end
                    )
                }
            }
            mix.withUnsafeBufferPointer { pointer in
                guard let base = pointer.baseAddress else { return }
                write(base, frames: chunk, frameOffset: offset, to: buffers, format: format)
            }
            offset += chunk
        }
    }

    private func write(
        _ mix: UnsafePointer<Float>,
        frames: Int,
        frameOffset: Int,
        to buffers: UnsafeMutableAudioBufferListPointer,
        format: AudioStreamBasicDescription
    ) {
        let channels = Int(max(format.mChannelsPerFrame, 1))
        let nonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let bits = Int(format.mBitsPerChannel)

        if nonInterleaved {
            for channel in 0..<min(channels, buffers.count) {
                guard let data = buffers[channel].mData else { continue }
                for frame in 0..<frames {
                    let sample = channel == 0 ? mix[frame * 2] : (channels == 1 ? mix[frame * 2] : mix[frame * 2 + 1])
                    store(sample, data: data, index: frameOffset + frame, isFloat: isFloat, bits: bits)
                }
            }
            return
        }
        guard let data = buffers.first?.mData else { return }
        for frame in 0..<frames {
            let destFrame = frameOffset + frame
            for channel in 0..<channels {
                let sample: Float
                if channel == 0 { sample = mix[frame * 2] }
                else if channel == 1 { sample = mix[frame * 2 + 1] }
                else { sample = 0 }
                store(sample, data: data, index: destFrame * channels + channel, isFloat: isFloat, bits: bits)
            }
        }
    }

    private func store(_ sample: Float, data: UnsafeMutableRawPointer, index: Int, isFloat: Bool, bits: Int) {
        let clamped = min(1, max(-1, sample))
        if isFloat && bits == 32 {
            data.assumingMemoryBound(to: Float.self)[index] = clamped
        } else if bits == 16 {
            data.assumingMemoryBound(to: Int16.self)[index] = Int16(clamped * Float(Int16.max))
        } else if bits == 32 {
            data.assumingMemoryBound(to: Int32.self)[index] = Int32(clamped * Float(Int32.max))
        }
    }

    private static let fallbackFormat = AudioStreamBasicDescription(
        mSampleRate: 48_000,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 8,
        mFramesPerPacket: 1,
        mBytesPerFrame: 8,
        mChannelsPerFrame: 2,
        mBitsPerChannel: 32,
        mReserved: 0
    )

    deinit { stop() }
}

final class MixGraph: @unchecked Sendable {
    private let lock = NSLock()
    private var members: [String: [AppStream]] = [:]

    func replace(_ members: [String: [AppStream]]) {
        lock.lock()
        self.members = members
        lock.unlock()
    }

    func copyMembers(for uid: String, into buffer: inout [AppStream?]) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let list = members[uid] else {
            for index in buffer.indices { buffer[index] = nil }
            return 0
        }
        let count = min(list.count, buffer.count)
        for index in 0..<count { buffer[index] = list[index] }
        if count < buffer.count {
            for index in count..<buffer.count { buffer[index] = nil }
        }
        return count
    }
}

#endif
