// Timing of the pen's main-thread work, to find what makes writing hitch. Cheap enough to stay on: a section
// is measured with two clock reads, and only slow ones (and dropped frames) are logged. Launch with
// `-penperf` to also print them (read with `xcrun devicectl device process launch --console`).
import Foundation
import QuartzCore
import UIKit
import os

/// Whether the pen is touching the page now (set by the canvas), so background work can wait for the lift.
@MainActor
enum PenState {
    /// When the pen last touched down (nil: it is up). A touch is only believed for a few seconds: if PencilKit
    /// never reports a stroke's end (a cancelled touch, a tool changed under it), a plain flag stayed "down" for
    /// good and held back the saves and the transcription for ever.
    private static var since: Date?
    static var down: Bool {
        guard let since else { return false }
        return Date().timeIntervalSince(since) < 4
    }
    static func began() { since = Date() }
    static func ended() { since = nil }
    /// The pen page is on screen: background counting waits until it is left.
    static var pageOpen = false
}

enum PenPerf {
    private static let log = Logger(subsystem: "com.bulletlife.notebook", category: "penperf")
    private static let signposter = OSSignposter(subsystem: "com.bulletlife.notebook", category: "penperf")
    static let echo = ProcessInfo.processInfo.arguments.contains("-penperf")
    /// Sections slower than this (ms) are logged.
    static let threshold = 3.0
    /// The slowest recent sections, so a dropped frame can say what ran before it.
    nonisolated(unsafe) private static var recent: [(name: String, ms: Double, at: CFTimeInterval)] = []

    @discardableResult
    static func measure<T>(_ name: StaticString, _ body: () -> T) -> T {
        let state = signposter.beginInterval(name)
        let start = CACurrentMediaTime()
        let result = body()
        let ms = (CACurrentMediaTime() - start) * 1000
        signposter.endInterval(name, state)
        if ms >= threshold {
            recent.append((String(describing: name), ms, start))
            if recent.count > 12 { recent.removeFirst() }
            emit("slow \(name) \(String(format: "%.1f", ms)) ms")
        }
        return result
    }

    fileprivate static func emit(_ message: String) {
        log.notice("\(message, privacy: .public)")
        if echo { print("[penperf] \(message)") }
    }

    fileprivate static func dropped(gap ms: Double, at time: CFTimeInterval) {
        let near = recent.filter { time - $0.at < 0.5 }.map { "\($0.name) \(String(format: "%.0f", $0.ms))" }.joined(separator: ", ")
        emit("frame gap \(String(format: "%.0f", ms)) ms" + (near.isEmpty ? "" : " after: \(near)"))
    }
}

/// Reports frames the main thread missed while the pen page is on screen.
@MainActor
final class FrameWatch: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        // Without this the system hands a display link a slower cadence when little is drawn, and its gaps would
        // look like dropped frames.
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
        last = 0
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ l: CADisplayLink) {
        defer { last = l.timestamp }
        guard last > 0 else { return }
        let gap = (l.timestamp - last) * 1000
        let frame = (l.targetTimestamp - l.timestamp) * 1000
        if gap > max(24, frame * 2.5) { PenPerf.dropped(gap: gap, at: l.timestamp) }
    }
}
