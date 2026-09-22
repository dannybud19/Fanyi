import Cocoa
import ApplicationServices

enum SelectionReader {
    static func readSelectedText() async -> String? {
        if let ax = readViaAccessibility(), !ax.isEmpty {
            print("[Fanyi] selection via Accessibility: \"\(ax.prefix(60))\"")
            return ax
        }
        print("[Fanyi] Accessibility read empty/failed, falling back to clipboard")
        let clip = await readViaClipboardFallback()
        print("[Fanyi] selection via clipboard: \(clip.map { "\"\($0.prefix(60))\"" } ?? "nil")")
        return clip
    }

    // MARK: - Accessibility

    private static func readViaAccessibility() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard err == .success, let focusedRef else {
            print("[Fanyi] AX focused-element lookup failed: err=\(err.rawValue)")
            return nil
        }

        // kAXFocusedUIElementAttribute is guaranteed to return an AXUIElement by the API contract.
        let element = unsafeBitCast(focusedRef, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.25)

        var textRef: CFTypeRef?
        let err2 = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &textRef)
        guard err2 == .success, let text = textRef as? String, !text.isEmpty else {
            print("[Fanyi] AX selected-text lookup failed: err=\(err2.rawValue) value=\(String(describing: textRef))")
            return nil
        }
        return text
    }

    // MARK: - Clipboard fallback

    private static func readViaClipboardFallback() async -> String? {
        let pb = NSPasteboard.general

        let snapshot: [(types: [NSPasteboard.PasteboardType], data: [NSPasteboard.PasteboardType: Data])] =
            (pb.pasteboardItems ?? []).map { item in
                var d: [NSPasteboard.PasteboardType: Data] = [:]
                for t in item.types {
                    if let v = item.data(forType: t) { d[t] = v }
                }
                return (item.types, d)
            }
        let originalChangeCount = pb.changeCount

        postCmdC()

        let deadline = Date().addingTimeInterval(0.45)
        var result: String?
        var changed = false
        while Date() < deadline {
            if pb.changeCount != originalChangeCount {
                changed = true
                result = pb.string(forType: .string)
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        print("[Fanyi] clipboard fallback: changeCount changed=\(changed) (orig=\(originalChangeCount), now=\(pb.changeCount))")

        restorePasteboard(pb, snapshot: snapshot)

        return (result?.isEmpty == false) ? result : nil
    }

    private static func restorePasteboard(
        _ pb: NSPasteboard,
        snapshot: [(types: [NSPasteboard.PasteboardType], data: [NSPasteboard.PasteboardType: Data])]
    ) {
        pb.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.map { s -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for t in s.types {
                if let v = s.data[t] { item.setData(v, forType: t) }
            }
            return item
        }
        pb.writeObjects(items)
    }

    private static func postCmdC() {
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: false) else { return }
        // Explicit flags so a still-held fn key can't leak into the synthesized event.
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
