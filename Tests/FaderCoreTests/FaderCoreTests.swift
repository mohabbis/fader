import XCTest
@testable import FaderCore

final class FaderCoreTests: XCTestCase {
    func testChromeHelpersShareOneFader() {
        let parent = appGroupKey(bundleID: "com.google.Chrome", processName: "Google Chrome")
        let renderer = appGroupKey(bundleID: "com.google.Chrome.helper.renderer", processName: "Google Chrome Helper (Renderer)")
        let gpu = appGroupKey(bundleID: "com.google.Chrome.helper", processName: "Google Chrome Helper")
        XCTAssertEqual(parent, "com.google.Chrome")
        XCTAssertEqual(renderer, parent)
        XCTAssertEqual(gpu, parent)
    }

    func testMissingBundleIDUsesProcessName() {
        XCTAssertEqual(appGroupKey(bundleID: nil, processName: "VLC"), "name:VLC")
        XCTAssertEqual(appGroupKey(bundleID: "  ", processName: "VLC"), "name:VLC")
    }

    func testFriendlyNameStripsHelperSuffix() {
        XCTAssertEqual(cleanedProcessName("Google Chrome Helper (Renderer)"), "Google Chrome")
        XCTAssertEqual(friendlyAppName(groupKey: "name:Spotify Helper", processNames: []), "Spotify")
    }

    func testPinnedDeviceIsUsedWhenPresent() {
        let devices = [
            RouteDevice(uid: "speakers", name: "MacBook Speakers"),
            RouteDevice(uid: "phones", name: "AirPods")
        ]
        let route = AppRoute(outputDeviceUID: "phones", outputDeviceName: "AirPods")
        let resolved = RoutingPolicy.resolve(route: route, devices: devices, systemDefaultUID: "speakers")
        XCTAssertEqual(resolved.deviceUID, "phones")
        XCTAssertFalse(resolved.isFallback)
        XCTAssertFalse(resolved.followsSystem)
    }

    func testMissingDeviceFallsBackAndCanReturn() {
        let speakers = [RouteDevice(uid: "speakers", name: "MacBook Speakers")]
        let route = AppRoute(outputDeviceUID: "phones", outputDeviceName: "AirPods")
        let fallen = RoutingPolicy.resolve(route: route, devices: speakers, systemDefaultUID: "speakers")
        XCTAssertEqual(fallen.deviceUID, "speakers")
        XCTAssertTrue(fallen.isFallback)
        XCTAssertEqual(fallen.missingDeviceName, "AirPods")

        let both = speakers + [RouteDevice(uid: "phones", name: "AirPods")]
        let restored = RoutingPolicy.resolve(route: route, devices: both, systemDefaultUID: "speakers")
        XCTAssertEqual(restored.deviceUID, "phones")
        XCTAssertFalse(restored.isFallback)
    }

    func testUnsetRouteFollowsSystemOutput() {
        let devices = [
            RouteDevice(uid: "speakers", name: "MacBook Speakers"),
            RouteDevice(uid: "phones", name: "AirPods")
        ]
        let resolved = RoutingPolicy.resolve(route: .followSystem, devices: devices, systemDefaultUID: "phones")
        XCTAssertEqual(resolved.deviceUID, "phones")
        XCTAssertTrue(resolved.followsSystem)
        XCTAssertFalse(resolved.isFallback)
    }

    func testMuteAndMasterGain() {
        XCTAssertEqual(RoutingPolicy.playbackGain(volume: 0.5, muted: false, master: 0.5), 0.25)
        XCTAssertEqual(RoutingPolicy.playbackGain(volume: 0.8, muted: true, master: 1), 0)
        XCTAssertEqual(RoutingPolicy.playbackGain(volume: 2, muted: false, master: 2), 1)
    }

    func testPresenceKeepsAPausedAppBriefly() {
        var presence = PlayingPresence(grace: 2.5)
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(presence.visibleIDs(active: ["spotify"], now: start), ["spotify"])
        let during = presence.visibleIDs(active: [], now: start.addingTimeInterval(2))
        XCTAssertEqual(during, ["spotify"])
        let after = presence.visibleIDs(active: [], now: start.addingTimeInterval(3))
        XCTAssertTrue(after.isEmpty)
    }

    func testRouteStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fader-tests-\(UUID().uuidString)")
            .appendingPathComponent("routes.json")
        let store = RouteStore(fileURL: url)
        store.setMasterVolume(0.4)
        store.update("com.spotify.client") { route in
            route.volume = 0.25
            route.isMuted = true
            route.outputDeviceUID = "phones"
            route.outputDeviceName = "AirPods"
        }
        let loaded = RouteStore(fileURL: url)
        XCTAssertEqual(loaded.state.masterVolume, 0.4)
        XCTAssertEqual(loaded.route(for: "com.spotify.client").volume, 0.25)
        XCTAssertTrue(loaded.route(for: "com.spotify.client").isMuted)
        XCTAssertEqual(loaded.route(for: "com.spotify.client").outputDeviceUID, "phones")
        XCTAssertEqual(loaded.route(for: "missing"), .followSystem)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
