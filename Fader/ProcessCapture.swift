import AudioToolbox
import CoreAudio
import Foundation
import os

/// Captures one app's output and mutes its original playback so Fader can send it elsewhere.
final class ProcessCapture: @unchecked Sendable {
    let objectIDs: [AudioObjectID]
    let ring: StereoRing
    private let accepting = OSAllocatedUnfairLock(initialState: false)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var format = AudioStreamBasicDescription()
    private let scratch = OSAllocatedUnfairLock(initialState: [Float](repeating: 0, count: 16_384))
    private let log = Logger(subsystem: "com.mohabbis.fader", category: "tap")

    init(objectIDs: [AudioObjectID], ring: StereoRing) {
        self.objectIDs = objectIDs
        self.ring = ring
    }

    func start(name: String) -> OSStatus {
        let description = CATapDescription(stereoMixdownOfProcesses: objectIDs)
        description.uuid = UUID()
        description.name = "Fader \(name)"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped

        var created = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &created)
        guard tapStatus == noErr else {
            log.error("Tap failed \(tapStatus, privacy: .public)")
            return tapStatus
        }
        tapID = created

        let aggregateUID = "fader-\(UUID().uuidString)"
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Fader \(name)",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]
        var aggregateObject = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateObject)
        guard aggregateStatus == noErr else {
            stop()
            return aggregateStatus
        }
        aggregateID = aggregateObject
        format = AudioHAL.streamFormat(
            objectID: tapID,
            selector: kAudioTapPropertyFormat,
            scope: kAudioObjectPropertyScopeGlobal
        ) ?? AudioHAL.streamFormat(
            objectID: aggregateID,
            selector: kAudioDevicePropertyStreamFormat,
            scope: kAudioObjectPropertyScopeInput
        ) ?? Self.fallbackFormat
        ring.reset(rate: format.mSampleRate)

        let block: AudioDeviceIOBlock = { [weak self] _, inputData, _, _, _ in
            self?.consume(inputData)
        }
        var proc: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregateID, nil, block)
        guard procStatus == noErr, let proc else {
            stop()
            return procStatus
        }
        procID = proc
        accepting.withLock { $0 = true }
        let startStatus = AudioDeviceStart(aggregateID, proc)
        if startStatus != noErr {
            stop()
            return startStatus
        }
        return noErr
    }

    func stop() {
        accepting.withLock { $0 = false }
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = kAudioObjectUnknown
        tapID = kAudioObjectUnknown
    }

    private func consume(_ inputData: UnsafePointer<AudioBufferList>) {
        guard accepting.withLock({ $0 }) else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        guard let first = buffers.first, let data = first.mData else { return }
        let channels = Int(format.mChannelsPerFrame == 0 ? 2 : format.mChannelsPerFrame)
        let bytesPerFrame = Int(format.mBytesPerFrame == 0 ? 8 : format.mBytesPerFrame)
        let frameCount: Int
        if format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 {
            let bytesPerSample = max(1, Int(format.mBitsPerChannel) / 8)
            frameCount = Int(first.mDataByteSize) / bytesPerSample
        } else {
            frameCount = Int(first.mDataByteSize) / max(bytesPerFrame, 1)
        }
        guard frameCount > 0 else { return }
        let count = min(frameCount, 8_192)
        scratch.withLock { existing in
            writeStereo(from: buffers, format: format, frames: count, channels: channels, into: &existing)
            existing.withUnsafeBufferPointer { pointer in
                guard let base = pointer.baseAddress else { return }
                ring.push(interleaved: base, frames: count, rate: format.mSampleRate)
            }
        }
    }

    private func writeStereo(
        from buffers: UnsafeMutableAudioBufferListPointer,
        format: AudioStreamBasicDescription,
        frames: Int,
        channels: Int,
        into destination: inout [Float]
    ) {
        let isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let nonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let bits = Int(format.mBitsPerChannel)

        for frame in 0..<frames {
            var left: Float = 0
            var right: Float = 0
            if nonInterleaved {
                left = sample(buffers[0], frame: frame, isFloat: isFloat, bits: bits)
                if channels > 1, buffers.count > 1 {
                    right = sample(buffers[1], frame: frame, isFloat: isFloat, bits: bits)
                } else {
                    right = left
                }
            } else if let buffer = buffers.first {
                left = sample(buffer, frame: frame * max(channels, 1), isFloat: isFloat, bits: bits)
                if channels > 1 {
                    right = sample(buffer, frame: frame * channels + 1, isFloat: isFloat, bits: bits)
                } else {
                    right = left
                }
            }
            destination[frame * 2] = left
            destination[frame * 2 + 1] = right
        }
    }

    private func sample(_ buffer: AudioBuffer, frame: Int, isFloat: Bool, bits: Int) -> Float {
        guard let data = buffer.mData else { return 0 }
        if isFloat && bits == 32 {
            return data.assumingMemoryBound(to: Float.self)[frame]
        }
        if bits == 16 {
            let value = data.assumingMemoryBound(to: Int16.self)[frame]
            return Float(value) / Float(Int16.max)
        }
        if bits == 32 {
            let value = data.assumingMemoryBound(to: Int32.self)[frame]
            return Float(value) / Float(Int32.max)
        }
        return 0
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
