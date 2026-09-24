#if os(macOS)
import AppKit
import Combine
import CoreAudio
import Foundation
import FaderCore
import os

struct OutputDevice: Identifiable, Equatable {
    var uid: String
    var name: String
    var transport: String
    var id: String { uid }
}

struct PlayingApp: Identifiable {
    var id: String
    var name: String
    var icon: NSImage?
    var volume: Double
    var isMuted: Bool
    var followsSystem: Bool
    var isFallback: Bool
    var pinnedDeviceUID: String?
    var pinnedDeviceName: String?
    var activeDeviceUID: String?
    var activeDeviceName: String
    var level: Float
}

enum CapturePermission: Equatable {
    case unknown
    case granted
    case needsApproval
}

@MainActor
final class AudioEngine: ObservableObject {
    @Published var apps: [PlayingApp] = []
    @Published var devices: [OutputDevice] = []
    @Published var masterVolume: Double
    @Published var permission: CapturePermission = .unknown
    @Published var status: String?

    private let store: RouteStore
    private let graph = MixGraph()
    private let masterGain: OSAllocatedUnfairLock<Float>
    private var streams: [String: AppStream] = [:]
    private var outputs: [String: DeviceOutput] = [:]
    private var presence = PlayingPresence()
    private var icons: [String: NSImage] = [:]
    private var timer: Timer?
    private let log = Logger(subsystem: "com.mohabbis.fader", category: "engine")

    init(store: RouteStore = RouteStore(fileURL: RouteStore.applicationSupportURL())) {
        self.store = store
        let master = Float(store.state.masterVolume)
        masterVolume = Double(master)
        masterGain = OSAllocatedUnfairLock(initialState: master)
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        tick()
    }

    func setMasterVolume(_ value: Double) {
        let clamped = RoutingPolicy.clamp(value)
        masterVolume = clamped
        masterGain.withLock { $0 = Float(clamped) }
        store.setMasterVolume(clamped)
    }

    func setVolume(_ id: String, _ value: Double) {
        let clamped = RoutingPolicy.clamp(value)
        store.update(id) { $0.volume = clamped }
        streams[id]?.controls.withLock { $0.volume = Float(clamped) }
        updateApp(id) { $0.volume = clamped }
    }

    func setMuted(_ id: String, _ muted: Bool) {
        store.update(id) { $0.isMuted = muted }
        streams[id]?.controls.withLock { $0.muted = muted }
        updateApp(id) { $0.isMuted = muted }
    }

    func selectOutput(_ id: String, deviceUID: String?) {
        if let deviceUID, let device = devices.first(where: { $0.uid == deviceUID }) {
            store.update(id) {
                $0.outputDeviceUID = device.uid
                $0.outputDeviceName = device.name
            }
        } else {
            store.update(id) {
                $0.outputDeviceUID = nil
                $0.outputDeviceName = nil
            }
        }
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        graph.replace([:])
        for output in outputs.values { output.stop() }
        outputs.removeAll()
        for stream in streams.values {
            stream.capture?.stop()
            stream.capture = nil
        }
        streams.removeAll()
    }

    private func tick() {
        let halDevices = AudioHAL.outputDevices()
        let listed = halDevices.map {
            OutputDevice(uid: $0.uid, name: $0.name, transport: $0.transport)
        }
        if listed != devices { devices = listed }

        let routeDevices = listed.map { RouteDevice(uid: $0.uid, name: $0.name) }
        let systemUID = AudioHAL.defaultOutputDevice()?.uid
        let running = AudioHAL.runningOutputProcesses().filter { $0.pid != getpid() }
        let named = running.map { process -> (HALProcess, String) in
            let app = NSRunningApplication(processIdentifier: process.pid)
            let name = app?.localizedName ?? process.bundleID ?? "Process \(process.pid)"
            return (HALProcess(objectID: process.objectID, pid: process.pid, bundleID: process.bundleID ?? app?.bundleIdentifier, name: name), name)
        }

        let grouped = Dictionary(grouping: named, by: { appGroupKey(bundleID: $0.0.bundleID, processName: $0.1) })
        let active = Set(grouped.keys)
        let visible = presence.visibleIDs(active: active, now: Date())

        for key in streams.keys where !visible.contains(key) {
            streams[key]?.capture?.stop()
            streams[key] = nil
        }

        var assignment: [String: [AppStream]] = [:]
        var rows: [PlayingApp] = []
        var sawCapture = false
        var sawFailure = false
        var failureStatus: OSStatus = noErr

        for key in visible.sorted() {
            let members = grouped[key] ?? []
            let stream = streams[key] ?? AppStream(key: key)
            streams[key] = stream
            let saved = store.route(for: key)
            stream.controls.withLock {
                $0.volume = Float(saved.volume)
                $0.muted = saved.isMuted
            }

            let objectIDs = members.map(\.0.objectID).sorted()
            if stream.objectIDs != objectIDs {
                stream.capture?.stop()
                stream.capture = nil
                stream.objectIDs = objectIDs
            }

            let resolved = RoutingPolicy.resolve(
                route: saved,
                devices: routeDevices,
                systemDefaultUID: systemUID
            )
            let names = members.map(\.1)
            let displayName = parentName(groupKey: key, processNames: names)
            let icon = iconFor(groupKey: key, members: members.map(\.0))

            if !objectIDs.isEmpty, let deviceUID = resolved.deviceUID,
               let deviceID = halDevices.first(where: { $0.uid == deviceUID })?.id {
                let output = ensureOutput(uid: deviceUID, deviceID: deviceID)
                if output.isRunning {
                    if stream.capture == nil {
                        let capture = ProcessCapture(objectIDs: objectIDs, ring: stream.ring)
                        let status = capture.start(name: displayName)
                        if status == noErr {
                            stream.capture = capture
                            sawCapture = true
                        } else {
                            capture.stop()
                            sawFailure = true
                            failureStatus = status
                            log.error("Capture \(key, privacy: .public) failed \(status, privacy: .public)")
                        }
                    } else {
                        sawCapture = true
                    }
                    if stream.capture != nil {
                        assignment[deviceUID, default: []].append(stream)
                    }
                } else {
                    status = "Couldn't open \(resolved.deviceName). Audio is still going to the system output."
                }
            }

            rows.append(PlayingApp(
                id: key,
                name: displayName,
                icon: icon,
                volume: saved.volume,
                isMuted: saved.isMuted,
                followsSystem: resolved.followsSystem,
                isFallback: resolved.isFallback,
                pinnedDeviceUID: saved.outputDeviceUID,
                pinnedDeviceName: saved.outputDeviceName,
                activeDeviceUID: resolved.deviceUID,
                activeDeviceName: resolved.deviceName,
                level: stream.ring.decayedPeak()
            ))
        }

        graph.replace(assignment)
        for uid in outputs.keys where assignment[uid] == nil {
            outputs[uid]?.stop()
            outputs[uid] = nil
        }

        rows.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        publish(rows)

        if sawCapture {
            permission = .granted
            if !sawFailure { status = nil }
        } else if sawFailure {
            permission = .needsApproval
            status = "System Audio Recording is off (\(AudioHAL.statusMessage(failureStatus)))."
        } else if apps.isEmpty {
            status = nil
        }
    }

    private func ensureOutput(uid: String, deviceID: AudioObjectID) -> DeviceOutput {
        if let existing = outputs[uid], existing.deviceID == deviceID, existing.isRunning {
            return existing
        }
        outputs[uid]?.stop()
        let output = DeviceOutput(uid: uid, deviceID: deviceID, graph: graph, master: masterGain)
        let status = output.start()
        if status != noErr {
            log.error("Device \(uid, privacy: .public) failed \(status, privacy: .public)")
        }
        outputs[uid] = output
        return output
    }

    private func publish(_ rows: [PlayingApp]) {
        if rows.map(\.id) != apps.map(\.id) {
            apps = rows
            return
        }
        for index in rows.indices {
            apps[index].name = rows[index].name
            apps[index].icon = rows[index].icon ?? apps[index].icon
            apps[index].volume = rows[index].volume
            apps[index].isMuted = rows[index].isMuted
            apps[index].followsSystem = rows[index].followsSystem
            apps[index].isFallback = rows[index].isFallback
            apps[index].pinnedDeviceUID = rows[index].pinnedDeviceUID
            apps[index].pinnedDeviceName = rows[index].pinnedDeviceName
            apps[index].activeDeviceUID = rows[index].activeDeviceUID
            apps[index].activeDeviceName = rows[index].activeDeviceName
            apps[index].level = rows[index].level
        }
    }

    private func updateApp(_ id: String, _ change: (inout PlayingApp) -> Void) {
        guard let index = apps.firstIndex(where: { $0.id == id }) else { return }
        change(&apps[index])
    }

    private func parentName(groupKey: String, processNames: [String]) -> String {
        if !groupKey.hasPrefix("name:"),
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: groupKey).first,
           let name = app.localizedName {
            return name
        }
        return friendlyAppName(groupKey: groupKey, processNames: processNames)
    }

    private func iconFor(groupKey: String, members: [HALProcess]) -> NSImage? {
        if let cached = icons[groupKey] { return cached }
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: groupKey).first
            ?? members.compactMap { NSRunningApplication(processIdentifier: $0.pid) }.first
        guard let icon = app?.icon else { return nil }
        icon.size = NSSize(width: 32, height: 32)
        icons[groupKey] = icon
        return icon
    }
}

#endif
