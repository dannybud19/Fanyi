import Cocoa

@MainActor
final class FnDoubleTapDetector {
    var onDoubleTap: (() -> Void)?
    /// Set true whenever a debug build wants verbose flagsChanged logging (see AppDelegate).
    var verboseLogging = false

    private enum TapState: Equatable {
        case idle
        case pressed(downAt: Date)
        case releasedArmed(releasedAt: Date)
        case firedWaitingRelease
    }

    private var state: TapState = .idle
    private var wasFnDown = false
    private var interleaved = false

    private let tapMaxDuration: TimeInterval = 0.3
    private let secondTapMaxGap: TimeInterval = 0.35

    private var monitors: [Any] = []

    func start() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            Task { @MainActor in self?.handleFlags(event) }
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            self?.handleFlags(event)
            return event
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] _ in
            Task { @MainActor in self?.markInterleaved() }
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            self?.markInterleaved()
            return event
        }) {
            monitors.append(m)
        }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    private func markInterleaved() {
        if state != .idle { interleaved = true }
    }

    private func handleFlags(_ event: NSEvent) {
        let fnDown = event.modifierFlags.contains(.function)
        let otherMods = event.modifierFlags.subtracting(.function)
            .intersection([.command, .option, .control, .shift])

        if verboseLogging {
            print("[Fanyi] flagsChanged keyCode=\(event.keyCode) fnDown=\(fnDown) otherMods=\(otherMods.rawValue)")
        }

        guard fnDown != wasFnDown else { return }
        wasFnDown = fnDown

        if fnDown {
            switch state {
            case .idle:
                interleaved = false
                state = otherMods.isEmpty ? .pressed(downAt: Date()) : .idle
            case .releasedArmed(let releasedAt):
                if !interleaved, otherMods.isEmpty, Date().timeIntervalSince(releasedAt) <= secondTapMaxGap {
                    onDoubleTap?()
                    state = .firedWaitingRelease
                } else {
                    interleaved = false
                    state = otherMods.isEmpty ? .pressed(downAt: Date()) : .idle
                }
            case .pressed, .firedWaitingRelease:
                break
            }
        } else {
            switch state {
            case .pressed(let downAt):
                if !interleaved, otherMods.isEmpty, Date().timeIntervalSince(downAt) <= tapMaxDuration {
                    let releasedAt = Date()
                    state = .releasedArmed(releasedAt: releasedAt)
                    scheduleExpiry(for: releasedAt)
                } else {
                    state = .idle
                }
            case .firedWaitingRelease:
                state = .idle
            default:
                state = .idle
            }
        }
    }

    private func scheduleExpiry(for releasedAt: Date) {
        let gap = secondTapMaxGap
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000))
            guard let self else { return }
            if case .releasedArmed(let t) = self.state, t == releasedAt {
                self.state = .idle
            }
        }
    }
}
