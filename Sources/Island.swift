import Cocoa
import SwiftUI

// MARK: - State model

enum IslandContent: Equatable {
    case loading
    case message(String)
    case result(IslandResult)
}

struct IslandResult: Equatable {
    let sourceLangLabel: String
    let targetLangLabel: String
    let originalText: String
    let sourceRomanization: String?
    let translatedText: String
    let targetRomanization: String?
    let showCopiedFeedback: Bool
    let cardWidth: CGFloat
    let needsScroll: Bool
}

// MARK: - Text measurement (drives card width + scroll decision)

enum TextMeasure {
    static func width(for text: String, font: NSFont, min: CGFloat, max: CGFloat, horizontalPadding: CGFloat) -> CGFloat {
        let attr = NSAttributedString(string: text, attributes: [.font: font])
        let unbounded = attr.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        )
        return Swift.min(Swift.max(unbounded.width + horizontalPadding, min), max)
    }

    static func height(for text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let attr = NSAttributedString(string: text, attributes: [.font: font])
        let bounded = attr.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        )
        return bounded.height
    }
}

// MARK: - SwiftUI views

struct IslandBackground: View {
    var body: some View {
        Group {
            if #available(macOS 26, *) {
                Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 20))
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            }
        }
    }
}

struct LoadingPillView: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = Double(i) * (Double.pi / 2)
                    let wave = sin(t * 3 + phase)
                    Circle()
                        .fill(Color.primary.opacity(0.4 + 0.3 * wave))
                        .frame(width: 6, height: 6)
                        .offset(y: -wave * 3)
                }
            }
            .frame(width: 92, height: 38)
            .background(IslandBackground())
        }
    }
}

struct MessagePillView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .fixedSize()
            .background(IslandBackground())
    }
}

struct ResultCardView: View {
    let result: IslandResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(result.sourceLangLabel.uppercased()) → \(result.targetLangLabel.uppercased())")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(result.showCopiedFeedback ? "Copied ✓" : "Click to copy")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Text(result.originalText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let srcRom = result.sourceRomanization {
                Text(srcRom)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if result.needsScroll {
                ScrollView {
                    Text(result.translatedText)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(height: 320)
            } else {
                Text(result.translatedText)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let tgtRom = result.targetRomanization {
                Text(tgtRom)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: result.cardWidth, alignment: .leading)
        .background(IslandBackground())
    }
}

struct IslandRootView: View {
    let content: IslandContent
    let onHover: (Bool) -> Void

    var body: some View {
        Group {
            switch content {
            case .loading:
                LoadingPillView()
            case .message(let text):
                MessagePillView(text: text)
            case .result(let r):
                ResultCardView(result: r)
            }
        }
        .onHover { onHover($0) }
    }
}

// MARK: - AppKit hosting

@MainActor
final class ClickableHostingView<Content: View>: NSHostingView<Content> {
    var onMouseDown: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }
}

@MainActor
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class IslandController {
    static let shared = IslandController()
    private init() {}

    private var panel: IslandPanel?
    private var hostingView: ClickableHostingView<IslandRootView>?
    private var currentContent: IslandContent = .loading
    private var dismissTask: Task<Void, Never>?
    private var isHovering = false
    private var escMonitor: Any?
    private var clickOutsideMonitor: Any?

    var isVisible: Bool { panel?.isVisible ?? false }

    func showLoading() {
        present(.loading, autoDismissSeconds: nil)
    }

    func showMessage(_ text: String) {
        present(.message(text), autoDismissSeconds: 2.5)
    }

    func showResult(_ result: IslandResult) {
        let charCount = result.translatedText.count
        let seconds = min(30.0, max(5.0, 4.0 + 0.05 * Double(charCount)))
        present(.result(result), autoDismissSeconds: seconds)
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        removeMonitors()
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.panel?.orderOut(nil)
            }
        })
    }

    private func present(_ content: IslandContent, autoDismissSeconds: TimeInterval?) {
        dismissTask?.cancel()
        currentContent = content
        rebuildHostingView()
        installMonitorsIfNeeded()
        if let seconds = autoDismissSeconds {
            startDismissTimer(seconds: seconds)
        }
    }

    private func rebuildHostingView() {
        let rootView = IslandRootView(content: currentContent, onHover: { [weak self] hovering in
            self?.isHovering = hovering
        })

        let hv: ClickableHostingView<IslandRootView>
        if let existing = hostingView {
            existing.rootView = rootView
            hv = existing
        } else {
            hv = ClickableHostingView(rootView: rootView)
            hostingView = hv
        }
        hv.onMouseDown = { [weak self] in self?.handleCopyTap() }

        let size = hv.fittingSize
        hv.frame = NSRect(origin: .zero, size: size)

        if let existingPanel = panel {
            existingPanel.contentView = hv
            existingPanel.setContentSize(size)
        } else {
            let p = IslandPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.hasShadow = true
            p.contentView = hv
            panel = p
        }

        positionPanel()

        guard let panel else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    private func positionPanel() {
        guard let panel else { return }
        let mouseLoc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLoc) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let x = vf.midX - size.width / 2
        let y = vf.minY + 24
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func startDismissTimer(seconds: TimeInterval) {
        dismissTask?.cancel()
        var remaining = seconds
        dismissTask = Task { [weak self] in
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if Task.isCancelled { return }
                guard let self else { return }
                if !self.isHovering { remaining -= 0.2 }
            }
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func handleCopyTap() {
        guard case .result(let r) = currentContent, !r.showCopiedFeedback else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(r.translatedText, forType: .string)

        dismissTask?.cancel()
        let copiedResult = IslandResult(
            sourceLangLabel: r.sourceLangLabel,
            targetLangLabel: r.targetLangLabel,
            originalText: r.originalText,
            sourceRomanization: r.sourceRomanization,
            translatedText: r.translatedText,
            targetRomanization: r.targetRomanization,
            showCopiedFeedback: true,
            cardWidth: r.cardWidth,
            needsScroll: r.needsScroll
        )
        currentContent = .result(copiedResult)
        rebuildHostingView()

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self?.hide()
        }
    }

    private func installMonitorsIfNeeded() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.hide()
                return nil
            }
            return event
        }
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeMonitors() {
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        if let m = clickOutsideMonitor { NSEvent.removeMonitor(m); clickOutsideMonitor = nil }
    }
}
