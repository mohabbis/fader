import Foundation

/// Stereo float ring used between a process tap and an output device.
/// The capture callback pushes; the output callback mixes out with resampling.
final class StereoRing: @unchecked Sendable {
    private let capacity = 16_384
    private let mask: Int
    private var storage: [Float]
    private var write: Int = 0
    private var read: Int = 0
    private var cursor: Double = 0
    private var rate: Double = 48_000
    private var peak: Float = 0
    private let lock = NSLock()

    init() {
        mask = capacity - 1
        storage = [Float](repeating: 0, count: capacity * 2)
    }

    func reset(rate: Double) {
        lock.lock()
        write = 0
        read = 0
        cursor = 0
        peak = 0
        if rate > 0 { self.rate = rate }
        lock.unlock()
    }

    func push(interleaved: UnsafePointer<Float>, frames: Int, rate: Double) {
        guard frames > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        if rate > 0 { self.rate = rate }
        var incoming = frames
        var source = interleaved
        if incoming >= capacity {
            source = interleaved.advanced(by: (incoming - capacity) * 2)
            incoming = capacity - 1
        }
        let overflow = (write - read) + incoming - (capacity - 1)
        if overflow > 0 {
            read += overflow
            if cursor < Double(read) { cursor = Double(read) }
        }
        var localPeak = peak
        for frame in 0..<incoming {
            let index = (write + frame) & mask
            let left = source[frame * 2]
            let right = source[frame * 2 + 1]
            storage[index * 2] = left
            storage[index * 2 + 1] = right
            localPeak = max(localPeak, abs(left), abs(right))
        }
        write += incoming
        peak = localPeak
    }

    func mix(
        into destination: UnsafeMutablePointer<Float>,
        frames: Int,
        destinationRate: Double,
        gainStart: Float,
        gainEnd: Float
    ) {
        guard frames > 0, destinationRate > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        let step = rate / destinationRate
        for frame in 0..<frames {
            guard cursor + 1 < Double(write) else { return }
            let base = Int(cursor)
            let fraction = Float(cursor - Double(base))
            let left = sample(base, channel: 0) * (1 - fraction) + sample(base + 1, channel: 0) * fraction
            let right = sample(base, channel: 1) * (1 - fraction) + sample(base + 1, channel: 1) * fraction
            let span = Float(max(frames - 1, 1))
            let gain = gainStart + (gainEnd - gainStart) * Float(frame) / span
            destination[frame * 2] += left * gain
            destination[frame * 2 + 1] += right * gain
            cursor += step
        }
        let consumed = min(write, Int(cursor))
        if consumed > read { read = consumed }
    }

    func decayedPeak() -> Float {
        lock.lock()
        let value = peak
        peak *= 0.45
        lock.unlock()
        return value
    }

    private func sample(_ frame: Int, channel: Int) -> Float {
        storage[(frame & mask) * 2 + channel]
    }
}
