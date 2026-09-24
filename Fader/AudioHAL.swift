#if os(macOS)
import CoreAudio
import Foundation

struct HALProcess {
    var objectID: AudioObjectID
    var pid: pid_t
    var bundleID: String?
    var name: String
}

struct HALDevice {
    var id: AudioObjectID
    var uid: String
    var name: String
    var transport: String
}

enum AudioHAL {
    static func runningOutputProcesses() -> [HALProcess] {
        objectIDs(
            AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyProcessObjectList
        ).compactMap { objectID in
            let pid = readPID(objectID, selector: kAudioProcessPropertyPID) ?? -1
            guard pid > 0 else { return nil }
            let running = readUInt32(objectID, selector: kAudioProcessPropertyIsRunningOutput) ?? 0
            guard running != 0 else { return nil }
            let bundle: String? = readString(objectID, selector: kAudioProcessPropertyBundleID)
            return HALProcess(objectID: objectID, pid: pid, bundleID: bundle, name: "")
        }
    }

    static func outputDevices() -> [HALDevice] {
        objectIDs(
            AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDevices
        ).compactMap { deviceID in
            let streams = objectIDs(
                deviceID,
                selector: kAudioDevicePropertyStreams,
                scope: kAudioObjectPropertyScopeOutput
            )
            guard !streams.isEmpty else { return nil }
            guard let uid = readString(deviceID, selector: kAudioDevicePropertyDeviceUID),
                  !uid.hasPrefix("fader-") else { return nil }
            let name = readString(deviceID, selector: kAudioObjectPropertyName) ?? "Output"
            let transport = readUInt32(deviceID, selector: kAudioDevicePropertyTransportType) ?? 0
            return HALDevice(id: deviceID, uid: uid, name: name, transport: transportName(transport))
        }
    }

    static func defaultOutputDevice() -> (id: AudioObjectID, uid: String)? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        guard let uid = readString(device, selector: kAudioDevicePropertyDeviceUID) else { return nil }
        return (device, uid)
    }

    static func deviceID(forUID uid: String) -> AudioObjectID? {
        outputDevices().first { $0.uid == uid }?.id
    }

    static func streamFormat(objectID: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> AudioStreamBasicDescription? {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &format)
        guard status == noErr, format.mSampleRate > 0, format.mChannelsPerFrame > 0 else { return nil }
        return format
    }

    static func readString(_ objectID: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    static func readUInt32(_ objectID: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value
    }

    static func readPID(_ objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value
    }

    static func objectIDs(_ objectID: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids
    }

    static func statusMessage(_ status: OSStatus) -> String {
        let bytes = [
            UInt8((status >> 24) & 0xff),
            UInt8((status >> 16) & 0xff),
            UInt8((status >> 8) & 0xff),
            UInt8(status & 0xff)
        ]
        if bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) {
            return "'" + String(bytes: bytes, encoding: .ascii)! + "'"
        }
        return "\(status)"
    }

    private static func transportName(_ value: UInt32) -> String {
        switch value {
        case kAudioDeviceTransportTypeBuiltIn: return "Built in"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth"
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeDisplayPort: return "Display"
        case kAudioDeviceTransportTypeHDMI: return "HDMI"
        case kAudioDeviceTransportTypeThunderbolt: return "Thunderbolt"
        case kAudioDeviceTransportTypeVirtual: return "Virtual"
        case kAudioDeviceTransportTypeAirPlay: return "AirPlay"
        default: return "Output"
        }
    }
}

#endif
