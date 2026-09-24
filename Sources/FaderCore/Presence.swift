import Foundation

/// Apps that just paused stay listed briefly so a fader doesn't vanish between tracks.
public struct PlayingPresence: Equatable, Sendable {
    public var grace: TimeInterval
    private var lastSeen: [String: Date]

    public init(grace: TimeInterval = 2.5, lastSeen: [String: Date] = [:]) {
        self.grace = grace
        self.lastSeen = lastSeen
    }

    public mutating func visibleIDs(active: Set<String>, now: Date) -> Set<String> {
        for id in active {
            lastSeen[id] = now
        }
        lastSeen = lastSeen.filter { id, seen in
            active.contains(id) || now.timeIntervalSince(seen) < grace
        }
        return Set(lastSeen.keys)
    }
}
