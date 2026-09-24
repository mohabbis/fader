import Foundation

public enum RoutingPolicy {
    /// Headphones unplugged: keep the pin, play on the system output, and
    /// switch back when that device returns.
    public static func resolve(
        route: AppRoute,
        devices: [RouteDevice],
        systemDefaultUID: String?
    ) -> ResolvedRoute {
        if let pinned = route.outputDeviceUID,
           let match = devices.first(where: { $0.uid == pinned }) {
            return ResolvedRoute(
                deviceUID: match.uid,
                deviceName: match.name,
                followsSystem: false,
                isFallback: false
            )
        }

        let fallback = devices.first(where: { $0.uid == systemDefaultUID }) ?? devices.first
        let followsSystem = route.outputDeviceUID == nil
        let missingName = followsSystem ? nil : (route.outputDeviceName ?? "Saved output")

        return ResolvedRoute(
            deviceUID: fallback?.uid,
            deviceName: fallback?.name ?? "No output",
            followsSystem: followsSystem,
            isFallback: !followsSystem,
            missingDeviceName: missingName
        )
    }

    public static func playbackGain(volume: Double, muted: Bool, master: Double) -> Double {
        guard !muted else { return 0 }
        return clamp(volume) * clamp(master)
    }

    public static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
