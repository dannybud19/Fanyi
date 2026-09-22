import Cocoa
import ApplicationServices
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let fnDetector = FnDoubleTapDetector()
    private var hotkeyStarted = false
    private var lastSelection: String?

    private var statusLineItem: NSMenuItem!
    private var accessibilityItem: NSMenuItem!
    private var targetLanguageItems: [NSMenuItem] = []
    private var showPinyinItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        requestAccessibilityThenStart()
    }

    // MARK: - Accessibility permission

    private func requestAccessibilityThenStart() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [promptKey: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        print("[Fanyi] AXIsProcessTrusted = \(trusted)")
        if trusted {
            startHotkey()
        } else {
            Task { [weak self] in
                while true {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if AXIsProcessTrustedWithOptions(nil) {
                        print("[Fanyi] Accessibility granted, starting hotkey")
                        self?.startHotkey()
                        break
                    }
                }
            }
        }
    }

    private func startHotkey() {
        guard !hotkeyStarted else { return }
        hotkeyStarted = true
        fnDetector.onDoubleTap = { [weak self] in self?.handleDoubleTap() }
        fnDetector.start()
        refreshMenu()
    }

    // MARK: - Translation flow

    private func handleDoubleTap() {
        Task { [weak self] in
            await self?.runTranslationFlow()
        }
    }

    private func runTranslationFlow() async {
        guard let text = await SelectionReader.readSelectedText(),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            IslandController.shared.showMessage("Highlight some text first")
            lastSelection = nil
            return
        }
        if IslandController.shared.isVisible, text == lastSelection {
            IslandController.shared.hide()
            return
        }
        lastSelection = text
        await translateAndShow(text: text)
    }

    private func translateAndShow(text: String) async {
        IslandController.shared.showLoading()
        let target = Settings.targetLanguage
        do {
            let result = try await Translator.translate(text: text, target: target)
            IslandController.shared.showResult(makeIslandResult(original: text, result: result))
        } catch {
            IslandController.shared.showMessage("Translation failed — check your connection")
        }
    }

    private func makeIslandResult(original: String, result: TranslationResult) -> IslandResult {
        let sourceLabel = languageLabel(for: result.detectedSourceLanguage)
        let targetLabel = languageLabel(for: result.effectiveTargetLanguage.rawValue)
        let showPinyin = Settings.showPinyin && original.count <= 300

        let font = NSFont.systemFont(ofSize: 15)
        let cardWidth = TextMeasure.width(for: result.translatedText, font: font, min: 300, max: 640, horizontalPadding: 32)
        let translationHeight = TextMeasure.height(for: result.translatedText, font: font, width: cardWidth - 32)

        return IslandResult(
            sourceLangLabel: sourceLabel,
            targetLangLabel: targetLabel,
            originalText: original,
            sourceRomanization: showPinyin ? result.sourceRomanization : nil,
            translatedText: result.translatedText,
            targetRomanization: showPinyin ? result.targetRomanization : nil,
            showCopiedFeedback: false,
            cardWidth: cardWidth,
            needsScroll: translationHeight > 320
        )
    }

    private func languageLabel(for code: String) -> String {
        switch Translator.langBase(code) {
        case "zh": return "Chinese"
        case "en": return "English"
        case "id": return "Indonesian"
        default: return code.uppercased()
        }
    }

    // MARK: - Menu

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Fanyi")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.delegate = self

        let testItem = NSMenuItem(title: "Test translation", action: #selector(runTestTranslation), keyEquivalent: "")
        testItem.target = self
        menu.addItem(testItem)
        menu.addItem(.separator())

        let statusLine = NSMenuItem(title: "Double-tap fn to translate", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        statusLineItem = statusLine

        let accessItem = NSMenuItem(title: "Grant Accessibility access…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessItem.target = self
        accessItem.isHidden = true
        menu.addItem(accessItem)
        accessibilityItem = accessItem

        menu.addItem(.separator())

        let translateIntoHeader = NSMenuItem(title: "Translate into", action: nil, keyEquivalent: "")
        translateIntoHeader.isEnabled = false
        menu.addItem(translateIntoHeader)

        for lang in TargetLanguage.allCases {
            let langItem = NSMenuItem(title: lang.displayName, action: #selector(selectTargetLanguage(_:)), keyEquivalent: "")
            langItem.target = self
            langItem.representedObject = lang.rawValue
            menu.addItem(langItem)
            targetLanguageItems.append(langItem)
        }

        menu.addItem(.separator())

        let pinyinItem = NSMenuItem(title: "Show pinyin", action: #selector(toggleShowPinyin), keyEquivalent: "")
        pinyinItem.target = self
        menu.addItem(pinyinItem)
        showPinyinItem = pinyinItem

        let loginItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        launchAtLoginItem = loginItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
        refreshMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenu()
    }

    private func refreshMenu() {
        guard statusLineItem != nil else { return }
        if hotkeyStarted {
            statusLineItem.title = "Double-tap fn to translate"
            accessibilityItem.isHidden = true
        } else {
            statusLineItem.title = "Grant Accessibility access…"
            accessibilityItem.isHidden = false
        }
        for item in targetLanguageItems {
            let raw = item.representedObject as? String
            item.state = (raw == Settings.targetLanguage.rawValue) ? .on : .off
        }
        showPinyinItem.state = Settings.showPinyin ? .on : .off
        launchAtLoginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    // MARK: - Menu actions

    @objc private func runTestTranslation() {
        Task { [weak self] in
            await self?.translateAndShow(text: "你好，今天天气怎么样？")
        }
    }

    @objc private func selectTargetLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let lang = TargetLanguage(rawValue: raw) else { return }
        Settings.targetLanguage = lang
    }

    @objc private func toggleShowPinyin() {
        Settings.showPinyin.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
